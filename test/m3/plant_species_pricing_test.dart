/// 物种表改版（玄参 2026-09-27 拍板）单测：**按物种计价** + 每物种仅一株 + 免费券 + 死亡后再种重扣。
///
/// 覆盖：
///  ① [PlantGrowthService.plantCost] 具体值：向日葵免费 / 月光兰 400 阳光 / 普通 6 碎片 / 精英 10 碎片；
///  ② 向日葵免费种植：不扣阳光、不扣碎片、不写账本；
///  ③ 月光兰扣 400 阳光进账本（`refType='plant_plant'`）；
///  ④ 精英 / 普通碎片物种扣对应碎片；
///  ⑤ 碎片余额不足 → 拒绝且余额不变（**绝不为负**）；
///  ⑥ 免费券（`UnlockedSpecies` 语义）：有券时种植不扣碎片 / 阳光，且券被消耗；
///  ⑦ 每物种同时仅存活一株（同物种再种被拒；枯萎仍算存活）；
///  ⑧ 死亡后再种 → 允许且**重新扣费**（一次兑换买一株）；
///  ⑨ 花园页「选择要种的植物」弹窗：稀有度两档（普通 / 精英）与价格文案渲染。
///
/// 纯 Dart 仓储以内存 Fake 实现；弹窗用例为真实 `GardenPage` 组件测试。
library plant_species_pricing_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as t;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

class _MemPlantRepo implements PlantRepository {
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
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
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
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 账本 Fake：初始余额可配置，记录全部 append 条目。
class _MemLedger implements SunlightRepository {
  _MemLedger({this.initialBalance = 1000000});
  double initialBalance;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> entriesOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

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
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }
}

class _MemSettingsRepo implements SettingsRepository {
  /// 花盆容量（本用例统一 12）。
  static const int capacity = 12;
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: capacity,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger, this.bloomRewards);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
  final InMemoryBloomRewardRepository bloomRewards;
}

_Ctx _make({double balance = 1000000}) {
  final _MemPlantRepo plants = _MemPlantRepo();
  final _MemLedger ledger = _MemLedger(initialBalance: balance);
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: bloomRewards,
  );
  return _Ctx(svc, plants, ledger, bloomRewards);
}

PlantSpecies _sp(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

/// 复制一株植物并改状态（供「死亡后再种」用例）。
Plant _withStatus(Plant p, PlantStatus status) => p.copyWith(status: status);

void main() {
  // ── ① plantCost 具体值 ────────────────────────────────────────────────────
  t.group('① plantCost 具体值（按物种计价）', () {
    final _Ctx ctx = _make();

    t.test('向日葵（初始物种）→ 免费', () async {
      final PlantCost c =
          await ctx.svc.plantCost(_sp(kStarterSpeciesId), AgeTier.low);
      t.expect(c.kind, PlantCostKind.free);
      t.expect(c.amount, 0);
    });

    t.test('月光兰首购 → 400 阳光（低 / 高年段同值）', () async {
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low)).kind,
        PlantCostKind.sunlight,
      );
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low)).amount,
        kSpeciesMoonOrchidSunlightCost,
      );
      t.expect(kSpeciesMoonOrchidSunlightCost, 400);
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.high))
            .amount,
        400,
      );
    });

    t.test('普通档（番茄 / 草莓）→ 6 碎片', () async {
      for (final String id in <String>['species_tomato', 'species_strawberry']) {
        final PlantCost c = await ctx.svc.plantCost(_sp(id), AgeTier.low);
        t.expect(c.kind, PlantCostKind.fragments);
        t.expect(c.amount, kSpeciesFragmentCostCommon);
        t.expect(c.amount, 6);
      }
    });

    t.test('精英档（4 种）→ 10 碎片', () async {
      for (final String id in <String>[
        'species_star_flower',
        'species_rainbow_fern',
        'species_coral_orchid',
        'species_jade_hydrangea',
      ]) {
        final PlantCost c = await ctx.svc.plantCost(_sp(id), AgeTier.low);
        t.expect(c.kind, PlantCostKind.fragments);
        t.expect(c.amount, kSpeciesFragmentCostPremium);
        t.expect(c.amount, 10);
      }
    });

    t.test('fragmentCostOf：初始物种为 0，其余按档位派生', () {
      t.expect(ctx.svc.fragmentCostOf(_sp(kStarterSpeciesId)), 0);
      t.expect(ctx.svc.fragmentCostOf(_sp('species_tomato')), 6);
      t.expect(ctx.svc.fragmentCostOf(_sp('species_moon_orchid')), 10,
          reason: '月光兰为 rare（精英档），碎片价按档位派生为 10（但其阳光价优先）');
    });

    t.test('物种表：恰 8 种、顺序 = 展示顺序、移除 daisy/cactus', () {
      t.expect(kSeedPlantSpecies.length, 8);
      t.expect(
        kSeedPlantSpecies.map((PlantSpecies s) => s.id).toList(),
        <String>[
          'species_sunflower',
          'species_moon_orchid',
          'species_tomato',
          'species_strawberry',
          'species_star_flower',
          'species_rainbow_fern',
          'species_coral_orchid',
          'species_jade_hydrangea',
        ],
      );
      final Set<String> ids =
          kSeedPlantSpecies.map((PlantSpecies s) => s.id).toSet();
      t.expect(ids.contains('species_daisy'), t.isFalse);
      t.expect(ids.contains('species_cactus'), t.isFalse);
    });
  });

  // ── ②③④⑤ 种植收费 ────────────────────────────────────────────────────────
  t.group('②③④⑤ 种植收费（阳光 / 碎片）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('向日葵免费：不扣阳光、不扣碎片、不写账本', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
      t.expect((await ctx.plants.plants()), t.hasLength(1));
    });

    t.test('月光兰扣 400 阳光进账本（refType=plant_plant）', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant('species_moon_orchid', 0, now);
      final List<SunlightEntry> spends = ctx.ledger.entriesOf('plant_plant');
      t.expect(spends, t.hasLength(1));
      t.expect(spends.first.net, -kSpeciesMoonOrchidSunlightCost.toDouble());
      t.expect(spends.first.refId, 'species_moon_orchid');
      t.expect(await ctx.ledger.balance(), 1000000 - 400);
    });

    t.test('精英物种扣 10 碎片', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_star_flower', 0, now);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 10);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty,
          reason: '碎片物种不扣阳光');
    });

    t.test('普通物种扣 6 碎片', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_tomato', 0, now);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 14);
    });

    t.test('碎片不足 → 拒绝且余额不变（不得为负）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(5);
      await t.expectLater(
        () => ctx.svc.plant('species_tomato', 0, now),
        t.throwsA(t.isA<PlantOperationException>()),
      );
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 5);
      t.expect(await ctx.plants.plants(), t.isEmpty, reason: '失败不应落植物');
    });

    t.test('阳光不足（月光兰）→ 拒绝且不扣', () async {
      final _Ctx ctx = _make(balance: 100);
      await t.expectLater(
        () => ctx.svc.plant('species_moon_orchid', 0, now),
        t.throwsA(t.isA<PlantOperationException>()),
      );
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty);
      t.expect(await ctx.plants.plants(), t.isEmpty);
    });
  });

  // ── ⑥ 免费券 ──────────────────────────────────────────────────────────────
  t.group('⑥ 免费种植券（种子掉落语义）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('有券时种植不扣碎片 / 阳光，且券被消耗', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(0);
      await ctx.bloomRewards.unlockSpecies('species_star_flower'); // 发一张免费券

      await ctx.svc.plant('species_star_flower', 0, now);

      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 0,
          reason: '有券 → 不扣碎片');
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty,
          reason: '有券 → 不扣阳光');
      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(), t.isEmpty,
          reason: '券应被消耗');
      t.expect(await ctx.plants.plants(), t.hasLength(1));
    });

    t.test('券对月光兰同样生效（不扣 400 阳光）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_moon_orchid');
      await ctx.svc.plant('species_moon_orchid', 0, now);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty);
      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(), t.isEmpty);
    });
  });

  // ── ⑦⑧ 每物种仅一株 + 死亡后再种重扣 ──────────────────────────────────────
  t.group('⑦⑧ 每物种仅一株 / 死亡后再种重扣', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('同物种再种被拒（同物种已存活）', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await t.expectLater(
        () => ctx.svc.plant(kStarterSpeciesId, 1, now),
        t.throwsA(t.isA<PlantOperationException>()),
      );
      t.expect(await ctx.plants.plants(), t.hasLength(1));
    });

    t.test('不同物种可各种一株', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(40);
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.svc.plant('species_tomato', 1, now);
      await ctx.svc.plant('species_star_flower', 2, now);
      t.expect(await ctx.plants.plants(), t.hasLength(3));
    });

    t.test('死亡后同物种可再种：首购 400 阳光已用 → 重种改走 10 碎片（不再扣阳光）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, now);
      // 置为死亡（全损：不退款）。
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.dead));

      final Plant p1 = await ctx.svc.plant('species_moon_orchid', 0, now);
      t.expect(p1.id, t.isNot(p0.id));

      final List<SunlightEntry> spends = ctx.ledger.entriesOf('plant_plant');
      t.expect(spends, t.hasLength(1), reason: '首购阳光仅一次，重种不再扣阳光');
      t.expect(spends.single.net, -400, reason: '首购 400 阳光');
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 10,
          reason: '首购用尽 → 重种按档位碎片价 10');
      t.expect(await ctx.plants.plants(), t.hasLength(1),
          reason: '同花盆死亡残留已清理，仅剩新株');
    });

    t.test('枯萎中（wilting）仍算存活 → 同物种不可再种', () async {
      final _Ctx ctx = _make();
      final Plant p0 = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.wilting));
      await t.expectLater(
        () => ctx.svc.plant(kStarterSpeciesId, 1, now),
        t.throwsA(t.isA<PlantOperationException>()),
      );
    });
  });

  // ── ⑨ 花园页「选择要种的植物」弹窗：稀有度两档 + 价格文案 ───────────────────
  t.group('⑨ 花园页选种弹窗（稀有度两档 + 价格文案）', () {
    testWidgets('点空花盆 → 弹窗展示「普通 · 免费」「精英 · 400 阳光」等',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
          plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ));

      // 等空花盆建好（木牌是无限呼吸动画 → 只能有界 pump）。
      final bool ready = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      t.expect(ready, t.isTrue);

      await tester.tap(find.byType(EmptyPot).first);
      // _openPlantSheet 现为异步预取计价（依赖账本）→ 有界 pump 直到弹窗标题出现。
      final bool sheetShown = await _pumpUntil(
        tester,
        () => find.text('选择要种的植物').evaluate().isNotEmpty,
      );
      t.expect(sheetShown, t.isTrue, reason: '异步预取后应弹出「选择要种的植物」弹窗');
      // 弹窗入场动画（有限时长）走完。
      await tester.pump(const Duration(milliseconds: 400));

      // 稀有度两档 + 免费 / 阳光价格文案。
      t.expect(find.text('普通 · 免费'), findsOneWidget,
          reason: '向日葵 = 普通档 + 免费');
      t.expect(find.text('精英 · 400 阳光'), findsOneWidget,
          reason: '月光兰首购 = 精英档 + 400 阳光');
      // 稀有度只显示两档：不应再出现旧的「优良 / 稀有」。
      t.expect(find.textContaining('优良'), findsNothing);
      t.expect(find.textContaining('稀有'), findsNothing);
    });
  });
}

// ── 弹窗用例的假仓储（返回真实 8 物种种子表）─────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepo implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _FakeFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _FakePlantRepo implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

/// 有界帧推进（木牌无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}
