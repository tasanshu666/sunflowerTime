/// F157-FEAT-3 · **QA 独立验收探针**（严过关，2026-10-27）：
/// 「空盆强制干扰物」调试入口是不是**真**入口。
///
/// 玄参原话：「我没有调试按钮，建了空盆之后，我不能在空盆上让它直接长草或长虫，
/// 然后再去清除草和虫」。验收要求四条，缺一条都算「看着能用、其实验不了」：
///
/// | # | 口径 | 本文件怎么证明 |
/// |---|------|----------------|
/// | ① | DB 里 `weedAt` / `rollDay` 都是**今天零点** | 域层直调 [EmptyPotService.forceDisturbanceForDebug]，逐字段断言 |
/// | ② | **再跑一次生产 tick 不会把刚种的草掷掉** | 用「永不命中」随机源 tick 一次：若重掷，草必被清零 → 断言草仍在 |
/// | ③ | 次日自动失效（与生产 roll 同语义，不是写脏数据） | `now` 推到明天再 tick（永不命中）→ 草必须消失 |
/// | ④ | 回到花园**看得到杂草浮标** | 真 `GardenPage` + 预置干扰物（不经面板）→ 断言 `kGardenWeedAsset` 节点在场 |
/// | ⑤ | 「全清」账本**恰 2 行**（草 + 虫，`refId = pot:<i>`） | 生产 [EmptyPotService.clearWeed] / [clearPest] 直调 + 账本逐行核对 |
///
/// 与工程师 `empty_pot_debug_panel_test.dart` 的分工：那边的入口是**面板按钮点击**；
/// 本文件从**领域服务 + 页面渲染**两端夹住，避免「面板接线错但服务对 / 服务错但面板看起来对」
/// 这类互相掩盖。
library f157_qa_empty_pot_debug_probe_test;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

import '../helpers/no_hit_random.dart';

// ─────────────────────────── 内存 fake ───────────────────────────

class _MemPotRepo implements PotDisturbanceRepository {
  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      store.values.toList()
        ..sort((PotDisturbance a, PotDisturbance b) =>
            a.potIndex.compareTo(b.potIndex));
  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];
  @override
  Future<void> save(PotDisturbance d) async => store[d.potIndex] = d;
  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);
  @override
  Future<void> deleteAll() async => store.clear();
}

class _MemLedger implements SunlightRepository {
  double _balance = 100;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> of(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    _balance += entry.net;
    return _balance;
  }

  @override
  Future<double> balance() async => _balance;
  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    final List<SunlightEntry> hits = of(refType);
    return hits.isEmpty ? null : hits.last;
  }

  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

/// 永远命中（`nextDouble() == 0` → 对任何 >0 的概率都判中）。
class _AlwaysHitRandom implements Random {
  @override
  double nextDouble() => 0.0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => true;
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemPlantRepo implements PlantRepository {
  _MemPlantRepo(this.rows);
  final List<Plant> rows;
  @override
  Future<List<Plant>> plants() async => List<Plant>.of(rows);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in rows) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant p) async {
    rows.removeWhere((Plant e) => e.id == p.id);
    rows.add(p);
  }

  @override
  Future<void> deletePlant(String id) async =>
      rows.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 只有 1 株植物（占盆 0）→ 盆 1 / 2 / 3 是空盆。
List<Plant> _onePlant() {
  final DateTime now = DateTime.now();
  return <Plant>[
    Plant(
      id: 'p0',
      speciesId: _sunflower.id,
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: now.subtract(const Duration(hours: 2)),
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(hours: 2)),
      lastWaterAt: now,
    ),
  ];
}

DateTime get _today {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────── ① 域层：写入值与语义 ───────────────────
  group('① 「空盆长草 / 长虫」写库口径', () {
    late _MemPotRepo pots;
    late _MemLedger ledger;
    late EmptyPotService svc;

    setUp(() {
      pots = _MemPotRepo();
      ledger = _MemLedger();
      svc = EmptyPotService(
        disturbances: pots,
        ledger: ledger,
        // 生产 roll「永不命中」：任何仍存在的草/虫都只可能来自 force 入口。
        weedRandom: NoHitRandom(),
        pestRandom: NoHitRandom(),
      );
    });

    test('长草：weedAt == rollDay == 今天零点（不写脏数据）', () async {
      await svc.forceDisturbanceForDebug(potIndex: 2, weed: true);
      final PotDisturbance? d = pots.store[2];
      expect(d, isNotNull, reason: '盆 2 必须落库');
      expect(d!.weedAt, equals(_today), reason: 'weedAt 必须是今天零点（次日即失效）');
      expect(d.rollDay, equals(_today),
          reason: 'rollDay 必须同步对齐今天 → 当日 tick 不再重掷');
      expect(d.hasWeed, isTrue);
      expect(d.hasPest, isFalse, reason: '只长草时不该凭空长虫');
    });

    test('长虫：pestAt == rollDay == 今天零点', () async {
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: false);
      final PotDisturbance d = pots.store[1]!;
      expect(d.pestAt, equals(_today));
      expect(d.rollDay, equals(_today));
      expect(d.hasPest, isTrue);
      expect(d.hasWeed, isFalse);
    });

    test('先长草再长虫：两侧**同时**存在（copyWith 未传字段原样保留）', () async {
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: true);
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: false);
      final PotDisturbance d = pots.store[1]!;
      expect(d.hasWeed, isTrue, reason: '长虫不得把已存在的草覆盖掉');
      expect(d.hasPest, isTrue);
      expect(d.weedAt, equals(_today));
      expect(d.pestAt, equals(_today));
    });

    test('② 再跑一次生产 tick（永不命中）→ 刚种的草**不被掷掉**', () async {
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: true);
      // 生产同日 tick：rollDay 已是今天 → 必须**跳过**重掷。
      // 若误重掷，永不命中的随机源会把 weedAt 清空 → 本断言立刻红。
      final List<PotDisturbance> after =
          await svc.tick(<int>[1], DateTime.now());
      expect(after.single.hasWeed, isTrue,
          reason: '🔴 rollDay 对齐的意图：同日 tick 不得重掷把手工状态清掉');
      expect(after.single.weedAt, equals(_today));
      expect(pots.store[1]!.hasWeed, isTrue, reason: '落库状态同样必须保留');
    });

    test('②-b 反面：若 rollDay 未对齐（改写成昨天），tick 会重掷 → 说明断言有效',
        () async {
      // 手工造一个「昨天已 roll」的记录，证明上一用例的绿不是「tick 根本不工作」。
      final DateTime yesterday = _today.subtract(const Duration(days: 1));
      await pots.save(PotDisturbance(
        potIndex: 1,
        weedAt: yesterday,
        rollDay: yesterday,
      ));
      final List<PotDisturbance> after =
          await svc.tick(<int>[1], DateTime.now());
      expect(after.single.hasWeed, isFalse,
          reason: '跨日 tick + 永不命中 → 草必须过期清零（证明 tick 确实在工作）');
      expect(after.single.rollDay, equals(_today));
    });

    test('③ 次日自动失效：今天 force 的草，明天 tick 后消失（与 roll 同语义）',
        () async {
      await svc.forceDisturbanceForDebug(potIndex: 3, weed: true);
      final DateTime tomorrow = _today.add(const Duration(days: 1));
      final List<PotDisturbance> after = await svc.tick(<int>[3], tomorrow);
      expect(after.single.hasWeed, isFalse,
          reason: '「当天有效、次日失效」是生产口径，调试入口不得绕过它');
    });

    test('②-c 正面控制：命中随机的 tick 确实会长草（证明 ②/②-b 的推断有效）',
        () async {
      final _MemPotRepo p2 = _MemPotRepo();
      final EmptyPotService hitSvc = EmptyPotService(
        disturbances: p2,
        ledger: _MemLedger(),
        weedRandom: _AlwaysHitRandom(),
        pestRandom: _AlwaysHitRandom(),
        firstSightImmune: false,
      );
      final List<PotDisturbance> after =
          await hitSvc.tick(<int>[2], DateTime.now());
      expect(after.single.hasWeed, isTrue,
          reason: '命中随机的 tick 必须长草 —— 否则前面「永不命中 → 草被清空」的'
              '推断链不成立（tick 可能根本没在工作）');
      expect(after.single.hasPest, isTrue);
    });

    test('⑤ 全清：账本恰 2 行（草 + 虫），refId = pot:<i>，refType 用生产常量',
        () async {
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: true);
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: false);
      expect(ledger.entries, isEmpty, reason: '「长草 / 长虫」只是写状态，一分钱都不许入账');

      final DateTime now = DateTime.now();
      await svc.clearWeed(1, now);
      await svc.clearPest(1, now);

      expect(ledger.entries.length, 2, reason: '全清 = 净新增 2 行（草 + 虫各 1）');
      expect(ledger.of(kGardenWeedRefType).length, 1);
      expect(ledger.of(kGardenPestRefType).length, 1);
      expect(ledger.of(kGardenWeedRefType).single.refId,
          equals(EmptyPotService.refIdOf(1)));
      expect(EmptyPotService.refIdOf(1), equals('pot:1'),
          reason: 'refId 口径必须是 pot:<potIndex>（与植物侧 plantId 同构）');
      expect(ledger.of(kGardenWeedRefType).single.net, greaterThan(0),
          reason: '拔草必须真的发阳光（玄参要在同一次验收里核对到账）');
      expect(ledger.of(kGardenPestRefType).single.net, greaterThan(0));
      expect(pots.store[1]!.hasPestOrWeed, isFalse, reason: '清完状态必须为空');
    });

    test('⑥ 清完后再 tick（永不命中）不会「几分钟后又冒出来」', () async {
      await svc.forceDisturbanceForDebug(potIndex: 1, weed: true);
      await svc.clearWeed(1, DateTime.now());
      final List<PotDisturbance> after =
          await svc.tick(<int>[1], DateTime.now());
      expect(after.single.hasWeed, isFalse,
          reason: '清除后保留 rollDay=今天 → 同日 tick 不得重掷再长出来');
    });

    test('⑦ 除调试面板外，生产代码不得调用 forceDisturbanceForDebug', () {
      // 面板本身也在 lib/ 内（只在 kDebugMode 渲染）。这里钉的是「除面板（与
      // 定义它的服务）以外，没有任何文件调它」—— 否则等于给线上留了一条
      // 凭空长草的后门。
      final List<String> offenders = <String>[];
      final Directory libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: '测试应在工程根目录运行');
      for (final FileSystemEntity e
          in libDir.listSync(recursive: true, followLinks: false)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String path = e.path.replaceAll(r'\', '/');
        if (path.endsWith('domain/services/empty_pot_service.dart')) continue;
        if (path.endsWith('widgets/bloom_debug_panel.dart')) continue;
        final List<String> lines = e.readAsStringSync().split('\n');
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (!line.contains('forceDisturbanceForDebug')) continue;
          final int comment = line.indexOf('//');
          final int hit = line.indexOf('forceDisturbanceForDebug');
          if (comment >= 0 && comment < hit) continue; // 注释提及不算
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty,
          reason: '调试入口只能由调试面板调用，出现了别的调用方：\n'
              '${offenders.join('\n')}');
    });
  });

  // ─────────────────── ④ 页面：浮标真的能看见 ───────────────────
  testWidgets('④ 预置「盆 1 有草」→ 真花园页渲染出杂草浮标（不经调试面板）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemPotRepo pots = _MemPotRepo();
    final _MemLedger ledger = _MemLedger();
    final EmptyPotService svc = EmptyPotService(
      disturbances: pots,
      ledger: ledger,
      weedRandom: NoHitRandom(),
      pestRandom: NoHitRandom(),
      // 生产默认首日免疫；本用例用 force 直写，故免疫与否不影响结果，保持默认。
    );
    // 预置：盆 1 今天有草（等价于玄参在调试面板点了「空盆长草」）。
    await svc.forceDisturbanceForDebug(potIndex: 1, weed: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider
              .overrideWithValue(_FakeSettingsRepository()),
          sunlightRepositoryProvider.overrideWithValue(ledger),
          focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
          plantRepositoryProvider.overrideWithValue(_MemPlantRepo(_onePlant())),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
          potDisturbanceRepositoryProvider.overrideWithValue(pots),
          emptyPotServiceProvider.overrideWithValue(svc),
          plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
                plants: ref.watch(plantRepositoryProvider),
                focus: ref.watch(focusRepositoryProvider),
                ledger: ref.watch(sunlightRepositoryProvider),
                settings: ref.watch(settingsRepositoryProvider),
                bloomRewards: ref.watch(bloomRewardRepositoryProvider),
                weedRandom: NoHitRandom(),
              )),
        ],
        child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
      ),
    );

    final Finder weedChip = find.byWidgetPredicate((Widget w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == kGardenWeedAsset);

    bool visible = false;
    for (int i = 0; i < 300; i++) {
      if (weedChip.evaluate().isNotEmpty) {
        visible = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(visible, isTrue,
        reason: 'DB 里有草 → 花园页必须渲染杂草浮标（否则玄参「看得到草」这条验收不成立）');
    expect(tester.takeException(), isNull, reason: '渲染浮标不得抛布局异常');
    // 反过来：盆 0 有植物、不该出现空盆浮标之外的异常状态；这里只保证「恰 1 个草浮标」。
    expect(weedChip.evaluate().length, 1,
        reason: '只有盆 1 有草 → 草浮标应恰 1 个（多盆串味/重复渲染都算错）');
  });
}
