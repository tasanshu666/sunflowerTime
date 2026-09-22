/// 植物能力（Perk）骨架回归测试（M3）。
///
/// 覆盖的是**契约**而非玩法数值——本轮只有骨架、没有任何具体规则，因此这里的
/// 判据全部是「抽象行为是否正确」：
///  ① 默认注册表为空：保证当前不会凭空发出任何新玩法（`all` 空、`hasAnyReady` false）；
///  ② 注册表的去重与参数校验：重复 id / 空 id 必须抛 `StateError`（且不能是 assert，
///     release 下 assert 会被剥离，真机才炸）；
///  ③ 解锁门槛默认实现：成株 / 已开花 才解锁，种子 / 幼苗 / 枯萎 / 死亡 不解锁；
///  ④ 子类可覆盖门槛；
///  ⑤ `readyFor` 必须在「已解锁」集合内筛选，未解锁者即便 evaluate 返回 ready 也不命中；
///  ⑥ `PlantDrop.isCollectableAt` 的收集态与过期边界（正好等于 expiresAt 算过期）。
///
/// 纯 Dart：不 import flutter_test，领域层无 Flutter 依赖。
/// 注册表是进程内单例，故每个用例 setUp / tearDown 都 reset，杜绝跨用例污染。
library plant_perk_skeleton_test;

import 'package:test/test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_perk.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_perk_registry.dart';

// ── 测试替身 ────────────────────────────────────────────────────────────────

/// 可控的假能力：`unlocked` 为 null 时走基类默认门槛实现，否则覆盖门槛。
class _FakePerk extends PlantPerk {
  const _FakePerk({
    required this.id,
    this.kind = PlantPerkKind.custom,
    this.displayName = '测试能力',
    this.unlocked,
    this.state = PlantPerkState.ready,
  });

  @override
  final String id;

  @override
  final PlantPerkKind kind;

  @override
  final String displayName;

  /// null = 不覆盖，使用 [PlantPerk.isUnlocked] 的默认门槛。
  final bool? unlocked;

  /// [PlantPerk.evaluate] 的固定返回值。
  final PlantPerkState state;

  @override
  bool isUnlocked(Plant plant, PlantSpecies species) =>
      unlocked ?? super.isUnlocked(plant, species);

  @override
  PlantPerkState evaluate({
    required Plant plant,
    required PlantSpecies species,
    required DateTime now,
  }) =>
      state;
}

// ── 构造辅助 ────────────────────────────────────────────────────────────────

final DateTime _kNow = DateTime(2026, 3, 1, 10);

PlantSpecies _species() {
  return const PlantSpecies(
    id: 'sp_sunflower',
    name: '向日葵',
    rarity: Rarity.common,
    baseCostHigh: 120,
    baseCostLow: 80,
    growthHoursPerStage: 240,
  );
}

Plant _plant({
  PlantStage stage = PlantStage.adult,
  PlantStatus status = PlantStatus.growing,
}) {
  return Plant(
    id: 'p1',
    speciesId: 'sp_sunflower',
    potIndex: 0,
    stage: stage,
    stageStartedAt: _kNow,
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: status,
    plantedAt: _kNow,
  );
}

void main() {
  setUp(() => PlantPerkRegistry.instance.resetForTest());
  tearDown(() => PlantPerkRegistry.instance.resetForTest());

  // ── ① 默认注册表为空 ────────────────────────────────────────────────────
  group('默认注册表为空', () {
    test('all 为空且 hasAnyReady 为 false（当前不发版任何新玩法）', () {
      expect(PlantPerkRegistry.instance.all, isEmpty);
      expect(
        PlantPerkRegistry.instance.hasAnyReady(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isFalse,
      );
    });

    test('unlockedFor / readyFor 在空注册表下均为空', () {
      expect(
        PlantPerkRegistry.instance.unlockedFor(
          plant: _plant(),
          species: _species(),
        ),
        isEmpty,
      );
      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isEmpty,
      );
    });
  });

  // ── ② 注册与去重 ────────────────────────────────────────────────────────
  group('register / unregister', () {
    test('注册后可通过 all 与 id 取到', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(
          id: 'perk_a',
          kind: PlantPerkKind.sunlightDrop,
          displayName: '阳光掉落',
        ),
      );

      final List<PlantPerk> all = PlantPerkRegistry.instance.all;
      expect(all.length, 1);
      expect(all.first.id, 'perk_a');
      expect(all.first.kind, PlantPerkKind.sunlightDrop);
      expect(all.first.displayName, '阳光掉落');
    });

    test('all 返回不可修改列表（外部无法绕过 register 改表）', () {
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a'));

      expect(
        () => PlantPerkRegistry.instance.all.add(const _FakePerk(id: 'perk_b')),
        throwsUnsupportedError,
      );
    });

    test('重复 id 抛 StateError', () {
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a'));

      expect(
        () => PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a')),
        throwsA(isA<StateError>()),
      );
      expect(PlantPerkRegistry.instance.all.length, 1);
    });

    test('空 id 抛 StateError', () {
      expect(
        () => PlantPerkRegistry.instance.register(const _FakePerk(id: '')),
        throwsA(isA<StateError>()),
      );
      expect(PlantPerkRegistry.instance.all, isEmpty);
    });

    test('unregisterById 移除指定项；id 不存在时静默无操作', () {
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a'));
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_b'));

      PlantPerkRegistry.instance.unregisterById('perk_a');
      expect(PlantPerkRegistry.instance.all.map((PlantPerk p) => p.id),
          ['perk_b']);

      PlantPerkRegistry.instance.unregisterById('not_exist');
      expect(PlantPerkRegistry.instance.all.length, 1);

      PlantPerkRegistry.instance.unregisterById('perk_b');
      expect(PlantPerkRegistry.instance.all, isEmpty);
    });

    test('注销后可重新注册同一 id（不再视为重复）', () {
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a'));
      PlantPerkRegistry.instance.unregisterById('perk_a');

      expect(
        () => PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a')),
        returnsNormally,
      );
    });
  });

  // ── ③ 默认解锁门槛 ──────────────────────────────────────────────────────
  group('unlockedFor 默认门槛', () {
    void expectUnlocked(Plant plant, bool expected) {
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'perk_a'));
      final List<PlantPerk> unlocked = PlantPerkRegistry.instance.unlockedFor(
        plant: plant,
        species: _species(),
      );
      expect(unlocked.length, expected ? 1 : 0, reason: 'plant=$plant');
    }

    test('adult + growing 解锁', () {
      expectUnlocked(
        _plant(stage: PlantStage.adult, status: PlantStatus.growing),
        true,
      );
    });

    test('bloomed 解锁（成株终点）', () {
      expectUnlocked(
        _plant(stage: PlantStage.adult, status: PlantStatus.bloomed),
        true,
      );
    });

    test('seed 不解锁', () {
      expectUnlocked(
        _plant(stage: PlantStage.seed, status: PlantStatus.growing),
        false,
      );
    });

    test('sprout 不解锁', () {
      expectUnlocked(
        _plant(stage: PlantStage.sprout, status: PlantStatus.growing),
        false,
      );
    });

    test('wilting 不解锁（即便已成株）', () {
      expectUnlocked(
        _plant(stage: PlantStage.adult, status: PlantStatus.wilting),
        false,
      );
    });

    test('dead 不解锁', () {
      expectUnlocked(
        _plant(stage: PlantStage.adult, status: PlantStatus.dead),
        false,
      );
    });

    test('sprout + bloomed 仍解锁（status 优先于 stage）', () {
      expectUnlocked(
        _plant(stage: PlantStage.sprout, status: PlantStatus.bloomed),
        true,
      );
    });
  });

  // ── ④ 子类覆盖门槛 ──────────────────────────────────────────────────────
  group('子类覆盖 isUnlocked', () {
    test('恒 true 的 Perk 对 seed 也解锁', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'always', unlocked: true),
      );

      expect(
        PlantPerkRegistry.instance.unlockedFor(
          plant: _plant(stage: PlantStage.seed),
          species: _species(),
        ).length,
        1,
      );
    });

    test('恒 false 的 Perk 对 adult 也不解锁', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'never', unlocked: false),
      );

      expect(
        PlantPerkRegistry.instance.unlockedFor(
          plant: _plant(stage: PlantStage.adult),
          species: _species(),
        ),
        isEmpty,
      );
    });
  });

  // ── ⑤ readyFor ──────────────────────────────────────────────────────────
  group('readyFor / hasAnyReady', () {
    test('evaluate 返回 ready 时命中', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'perk_a', state: PlantPerkState.ready),
      );

      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ).map((PlantPerk p) => p.id),
        ['perk_a'],
      );
      expect(
        PlantPerkRegistry.instance.hasAnyReady(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isTrue,
      );
    });

    test('evaluate 返回 idle 时不命中', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'perk_a', state: PlantPerkState.idle),
      );

      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isEmpty,
      );
      expect(
        PlantPerkRegistry.instance.hasAnyReady(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isFalse,
      );
    });

    test('evaluate 返回 locked 时不命中', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'perk_a', state: PlantPerkState.locked),
      );

      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isEmpty,
      );
    });

    test('未解锁的能力即使 evaluate 返回 ready 也不命中', () {
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'perk_a', unlocked: false),
      );

      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(stage: PlantStage.adult),
          species: _species(),
          now: _kNow,
        ),
        isEmpty,
      );
    });

    test('多个 Perk 只返回 ready 的子集且保持注册顺序', () {
      PlantPerkRegistry.instance
          .register(const _FakePerk(id: 'a', state: PlantPerkState.idle));
      PlantPerkRegistry.instance
          .register(const _FakePerk(id: 'b', state: PlantPerkState.ready));
      PlantPerkRegistry.instance.register(
        const _FakePerk(id: 'c', unlocked: false, state: PlantPerkState.ready),
      );
      PlantPerkRegistry.instance
          .register(const _FakePerk(id: 'd', state: PlantPerkState.ready));

      expect(
        PlantPerkRegistry.instance.readyFor(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ).map((PlantPerk p) => p.id),
        ['b', 'd'],
      );
    });
  });

  // ── ⑥ PlantDrop 收集态与过期边界 ────────────────────────────────────────
  group('PlantDrop', () {
    PlantDrop drop({DateTime? collectedAt}) {
      return PlantDrop(
        id: 'drop_1',
        plantId: 'p1',
        kind: PlantPerkKind.sunlightDrop,
        createdAt: _kNow,
        expiresAt: _kNow.add(const Duration(hours: 1)),
        collectedAt: collectedAt,
        amount: 5,
      );
    }

    test('未收集且未过期 → 可收集', () {
      expect(drop().isCollectableAt(_kNow.add(const Duration(minutes: 30))),
          isTrue);
      expect(drop().isCollected, isFalse);
    });

    test('已收集 → 不可收集（即便尚未过期）', () {
      final PlantDrop d = drop(
        collectedAt: _kNow.add(const Duration(minutes: 10)),
      );

      expect(d.isCollected, isTrue);
      expect(d.isCollectableAt(_kNow.add(const Duration(minutes: 20))), isFalse);
    });

    test('已过期 → 不可收集', () {
      expect(
        drop().isCollectableAt(_kNow.add(const Duration(hours: 2))),
        isFalse,
      );
    });

    test('边界：正好等于 expiresAt 判为过期', () {
      expect(drop().isCollectableAt(_kNow.add(const Duration(hours: 1))),
          isFalse);
      expect(
        drop().isCollectableAt(
          _kNow.add(const Duration(hours: 1)).subtract(
                const Duration(milliseconds: 1),
              ),
        ),
        isTrue,
      );
    });

    test('copyWith 标记已收集后其余字段不变', () {
      final PlantDrop d = drop();
      final PlantDrop collected = d.copyWith(
        collectedAt: _kNow.add(const Duration(minutes: 5)),
      );

      expect(collected.id, 'drop_1');
      expect(collected.plantId, 'p1');
      expect(collected.kind, PlantPerkKind.sunlightDrop);
      expect(collected.amount, 5);
      expect(collected.isCollected, isTrue);
      expect(d.isCollected, isFalse, reason: '原对象保持不可变');
    });

    test('非阳光掉落物 amount 默认 0', () {
      final PlantDrop d = PlantDrop(
        id: 'drop_2',
        plantId: 'p1',
        kind: PlantPerkKind.custom,
        createdAt: _kNow,
        expiresAt: _kNow.add(const Duration(hours: 1)),
      );

      expect(d.amount, 0);
      expect(d.isCollectableAt(_kNow), isTrue);
    });
  });

  // ── ⑦ resetForTest ──────────────────────────────────────────────────────
  group('resetForTest', () {
    test('清空后 all 为空、hasAnyReady 为 false', () {
      PlantPerkRegistry.instance
          .register(const _FakePerk(id: 'a', state: PlantPerkState.ready));
      PlantPerkRegistry.instance.register(const _FakePerk(id: 'b'));
      expect(PlantPerkRegistry.instance.all.length, 2);

      PlantPerkRegistry.instance.resetForTest();

      expect(PlantPerkRegistry.instance.all, isEmpty);
      expect(
        PlantPerkRegistry.instance.hasAnyReady(
          plant: _plant(),
          species: _species(),
          now: _kNow,
        ),
        isFalse,
      );
    });
  });
}
