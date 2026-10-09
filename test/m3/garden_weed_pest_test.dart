/// 花园干扰物「杂草 / 害虫」玩法回归测试（玄参 2026-09-30 拍板，口径 C26）。
///
/// 覆盖五件事（判据都是**可观测产物**，不是「跑通了」）：
///  ① **每日一次 roll 且幂等**：同一天重复 tick 不重 roll（否则开着 App 的几小时里
///     杂草会凭空冒出来）；
///  ② **当天有效、次日自动过期**：杂草只在其出现的当天存在，第二天重新 roll ——
///     这是「不会永久卡住成长」的唯一保证（死锁不可能出现）；
///  ③ **成长暂停且**不倒补：有杂草时当天不涨进度；清掉后**只补清掉之后的时间**，
///     暂停那段就这么过去（否则暂停会攒着以后一起长 → 惩罚净损失为零）；
///  ④ **清字段即入账**：拔草 +[kGardenWeedReward]、除虫 +[kGardenPestReward]，
///     账本 refType 必须分别是 `plant_weed` / `plant_pest`（孩子端阳光来源靠它）；
///  ⑤ **分因与护栏**：无杂草时拔草要抛 [PlantOperationException] 而不是静默成功；
///     实体侧 [Plant.kClear] 哨兵必须真能置空）。
///
/// 纯 Dart：仓储以内存 Fake 实现，随机源用 [Random] 固定种子（保证可重复）。
library garden_weed_pest_test;

import 'dart:math';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

class _MemPlantRepo implements PlantRepository {
  _MemPlantRepo(this.speciesList);

  final List<PlantSpecies> speciesList;
  final List<Plant> store = <Plant>[];

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(store);

  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    store.removeWhere((Plant p) => p.id == plant.id);
    store.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      store.removeWhere((Plant p) => p.id == id);

  @override
  Future<List<PlantSpecies>> species() async => List<PlantSpecies>.of(speciesList);
}

/// 无任何专注会话：成长系数恒 1.0。
class _MemFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) =>
      Future<List<FocusSession>>.value(const <FocusSession>[]);

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemLedgerRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<double> balance() async => 1000000.0;

  @override
  Future<double> dayNet(String key) async => 0;

  @override
  Future<double> earnGrossOnDay(String key) async => 0;

  @override
  Future<double> earnNetOnDay(String key) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String key,
  ) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType != refType || e.refId != refId) continue;
      if (last == null || e.ts.isAfter(last)) last = e.ts;
    }
    return last;
  }
}

class _MemSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

// ── 组装辅助 ────────────────────────────────────────────────────────────────

const String _kPlantId = 'p_wp';

/// 组装服务。
///
/// `seed` 直接喂给 `Random`，roll 结果完全确定（不依赖运行次数）：
///  · seed 3 → 杂草 + 害虫**同时**出现；
///  · seed 4 → 只有杂草；seed 0 → 两者都不出现。
({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) _make(
  int seed,
) {
  final _MemPlantRepo plants = _MemPlantRepo(<PlantSpecies>[
    PlantSpecies(
      id: 'sp_test',
      name: '测试草',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
      subscriptionOnly: false,
    ),
  ]);
  final _MemLedgerRepo ledger = _MemLedgerRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _MemFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    random: Random(seed),
  );
  return (svc: svc, plants: plants, ledger: ledger);
}

/// 种一株「活的、不会枯萎」的植株（`lastWaterAt = null` → 隔离枯萎 / 死亡）。
Plant _livePlant(DateTime now, {double progress = 0.0}) => Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthProgress: progress,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      bloomedAt: null,
      bloomCount: 0,
      mood: PlantMood.calm,
    );

DateTime _todayOf(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  // ── ① 每日一次 roll 且幂等 ────────────────────────────────────────────────
  group('① 每日 roll 幂等（seed 4 = 只有杂草）', () {
    test('同一天第二次 tick 不重 roll，杂草与 roll 基准都不变', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(4);
      f.plants.store.add(_livePlant(now));

      await f.svc.tickAll(now);
      final Plant first = (await f.plants.plant(_kPlantId))!;
      expect(first.hasWeed, isTrue, reason: 'seed 4 必须 roll 出杂草');
      expect(first.hasPest, isFalse);
      expect(first.weedPestRollDay, _todayOf(now));

      await f.svc.tickAll(now.add(const Duration(hours: 2)));
      final Plant second = (await f.plants.plant(_kPlantId))!;
      // 同一天：roll 基准不动、杂草还在（不许「roll 一次抽走再来一次」）
      expect(second.weedPestRollDay, _todayOf(now));
      expect(second.hasWeed, isTrue);
      // 幂等基准被推进（暂停期正常消耗时间）
      expect(second.stageStartedAt, now.add(const Duration(hours: 2)));
    });
  });

  // ── ② 当天有效 / 次日自动过期 ────────────────────────────────────────────
  group('② 当天有效、次日自动过期（不会永久卡住成长）', () {
    test('第二天重新 roll：没中就是干净的一盆，且 roll 基准挪到新的一天', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      // seed 0 = 杂草（40%）都没中的种子
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(0);
      f.plants.store.add(_livePlant(now));

      await f.svc.tickAll(now);
      expect((await f.plants.plant(_kPlantId))!.hasWeed, isFalse);

      final DateTime tomorrow = now.add(const Duration(days: 1));
      await f.svc.tickAll(tomorrow);
      final Plant p = (await f.plants.plant(_kPlantId))!;
      expect(p.weedPestRollDay, _todayOf(tomorrow));
      expect(p.hasWeed, isFalse);
    });

    test('杂草只在当天：次日即使不中也不会「复活」成旧的那株', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(4);
      f.plants.store.add(_livePlant(now));
      await f.svc.tickAll(now);
      expect((await f.plants.plant(_kPlantId))!.hasWeed, isTrue);

      final DateTime tomorrow = now.add(const Duration(days: 1));
      // 换一个「连虫都不中」的种子 → 次日重新 roll 后应该两样都空
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f2 =
          _make(0);
      f2.plants.store.add((await f.plants.plant(_kPlantId))!);
      await f2.svc.tickAll(tomorrow);
      final Plant p = (await f2.plants.plant(_kPlantId))!;
      expect(p.hasWeed, isFalse);
      expect(p.hasPest, isFalse);
      expect(p.hasPestOrWeed, isFalse);
    });
  });

  // ── ③ 成长暂停且不倒补 ───────────────────────────────────────────────────
  group('③ 成长暂停且不倒补（惩罚不能归零）', () {
    test('有杂草期间进度为 0；清掉后只补「清掉之后」的时间', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(4);
      // 阶段起点定在 24h 前：若暂停时长被倒补，这里会一次涨掉 24h 的量
      f.plants.store.add(_livePlant(
        now.subtract(const Duration(hours: 24)),
      ));

      await f.svc.tickAll(now);
      final Plant rolled = (await f.plants.plant(_kPlantId))!;
      expect(rolled.hasWeed, isTrue);
      expect(rolled.growthProgress, 0.0,
          reason: '有杂草的当天一步都不许涨');

      final DateTime cleared = now.add(const Duration(hours: 6));
      await f.svc.tickAll(cleared);
      final Plant stillPaused = (await f.plants.plant(_kPlantId))!;
      expect(stillPaused.growthProgress, 0.0, reason: '暂停期间一直不许涨');

      await f.svc.clearWeed(_kPlantId, cleared);
      // ⚠️ 必须再往后推 1h 才 tick：清除那一刻 stageStartedAt 已被暂停推进到 `cleared`，
      // 同一时刻再 tick 是 0 增量（这正是「暂停不倒补」的证明方式之一）。
      final DateTime resumed = cleared.add(const Duration(hours: 1));
      await f.svc.tickAll(resumed);
      final Plant after = (await f.plants.plant(_kPlantId))!;
      expect(after.hasWeed, isFalse);
      // 1h / 阶段时长。若把暂停的 30h 一起倒补回来会是 30/240 ≈ 0.125。
      final double expect1h =
          1.0 / kPlantGrowthHoursPerStageDefault / kPlantAutoGrowthScale;
      expect(after.growthProgress, greaterThan(0.0));
      expect(
        after.growthProgress,
        lessThan(expect1h * 2),
        reason: '清除后只补 1h 的量（≈$expect1h），不得倒补暂停掉的 30h',
      );
    });
  });

  // ── ④ 清字段即入账 ───────────────────────────────────────────────────────
  group('④ 拔草 / 除虫入账（账本 refType 可被孩子端阳光来源识别）', () {
    test('拔草：+kGardenWeedReward 阳光，refType = plant_weed，字段清空且当日不再长出',
        () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f =
          _make(4);
      f.plants.store.add(_livePlant(now));
      await f.svc.tickAll(now);

      await f.svc.clearWeed(_kPlantId, now);
      final Plant p = (await f.plants.plant(_kPlantId))!;
      expect(p.hasWeed, isFalse, reason: '清完必须立刻看不见杂草');
      expect(p.weedPestRollDay, _todayOf(now),
          reason: '保留当日 roll 基准：否则同日再 tick 会又长出杂草');

      // 同日再 tick 不再冒出来
      await f.svc.tickAll(now.add(const Duration(minutes: 30)));
      expect((await f.plants.plant(_kPlantId))!.hasWeed, isFalse);

      final List<SunlightEntry> weedRows = f.ledger.entries
          .where((SunlightEntry e) => e.refType == kGardenWeedRefType)
          .toList();
      expect(weedRows, hasLength(1));
      expect(weedRows.single.net, kGardenWeedReward);
      expect(weedRows.single.type, SunlightType.earn);
      expect(weedRows.single.refId, _kPlantId);
      expect(kGardenWeedRefType, 'plant_weed',
          reason: 'refType 字符串一经写入即冻结，改值会让历史行与新增行 tag 分裂');
    });

    test('除虫：+kGardenPestReward 阳光，refType = plant_pest', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f =
          _make(3); // seed 3 = 杂草 + 害虫同时出现
      f.plants.store.add(_livePlant(now));
      await f.svc.tickAll(now);
      final Plant rolled = (await f.plants.plant(_kPlantId))!;
      expect(rolled.hasWeed, isTrue);
      expect(rolled.hasPest, isTrue,
          reason: '两种干扰物互相独立、可同时出现（口径 C26）');

      await f.svc.clearPest(_kPlantId, now);
      final Plant p = (await f.plants.plant(_kPlantId))!;
      expect(p.hasPest, isFalse);
      expect(p.hasWeed, isTrue, reason: '除虫不该顺手把杂草也清掉');

      final List<SunlightEntry> pestRows = f.ledger.entries
          .where((SunlightEntry e) => e.refType == kGardenPestRefType)
          .toList();
      expect(pestRows, hasLength(1));
      expect(pestRows.single.net, kGardenPestReward);
      expect(kGardenPestRefType, 'plant_pest');
    });
  });

  // ── ⑤ 分因与护栏 ─────────────────────────────────────────────────────────
  group('⑤ 分因失败与实体护栏', () {
    test('没有杂草时拔草 → 抛 PlantOperationException（不许静默成功）', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(0);
      f.plants.store.add(_livePlant(now));
      await f.svc.tickAll(now);

      await expectLater(
        f.svc.clearWeed(_kPlantId, now),
        throwsA(isA<PlantOperationException>()),
      );
    });

    test('重复拔草第二次抛异常（杜绝连点写出两条阳光账本行）', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(4);
      f.plants.store.add(_livePlant(now));
      await f.svc.tickAll(now);
      await f.svc.clearWeed(_kPlantId, now);
      await expectLater(
        f.svc.clearWeed(_kPlantId, now.add(const Duration(seconds: 5))),
        throwsA(isA<PlantOperationException>()),
      );
    });

    test('枯萎植物不参与 roll（干扰物只长在活株上）', () async {
      final DateTime now = DateTime(2026, 10, 3, 9, 0);
      final ({PlantGrowthService svc, _MemPlantRepo plants, _MemLedgerRepo ledger}) f = _make(4);
      f.plants.store.add(_livePlant(now).copyWith(status: PlantStatus.dead));
      await f.svc.tickAll(now);
      final Plant p = (await f.plants.plant(_kPlantId))!;
      expect(p.hasWeed, isFalse);
      expect(p.hasPest, isFalse);
    });

    test('Plant.copyWith：kClear 哨兵能置空，默认不动（历史坑的护栏）', () {
      final DateTime d = DateTime(2026, 10, 3);
      final Plant p = _livePlant(d).copyWith(weedAt: d, pestAt: d, weedPestRollDay: d);
      expect(p.hasWeed, isTrue);

      // 默认参数 = 保持原值（不是清零）
      expect(p.copyWith().weedAt, d);
      // 显式 null 也是「清空」（哨兵分支）
      expect(p.copyWith(weedAt: null).hasWeed, isFalse);
      // 哨兵对象同样能清空
      expect(p.copyWith(pestAt: Plant.kClear).hasPest, isFalse);
      expect(p.copyWith(weedPestRollDay: Plant.kClear).weedPestRollDay, isNull);
    });

    test('常量口径护栏：概率 / 奖励 / emoji 全部单点收敛', () {
      expect(kGardenWeedRate, 0.40);
      expect(kGardenPestRate, 0.25);
      expect(kGardenWeedReward, 1);
      expect(kGardenPestReward, 2);
      expect(kGardenWeedEmoji, '🌿');
      expect(kGardenPestEmoji, '🦗');
    });
  });
}
