/// 一键采集晨露（玄参 2026-11-02 需求：「在一键操作系统里面，再增加一个一键采集，
/// 就是一键采集晨露的功能」）端到端回归。
///
/// ## 为什么必须走真实 GardenPage
/// 一键操作体系最容易假绿的地方是「组件层自己传参」——`_OneClickItem(onTap:)` 写对了
/// 不等于**点下去真的收到钱**。本用例从真实入口走进去：种 4 株盛开植物 → 点右下角
/// 悬浮球 → 点「一键采集晨露」→ 断言**仓储里 4 条 pending 全部 claimed** 且
/// **阳光合计入账 = 4 × 6 = 24**。
///
/// ## 与浇水 / 施肥 / 护理三条线的差异（本用例一并钉死）
///  · **不弹确认卡**（收钱不是花钱）：全程 `find.text('确定')` 必须为空；
///  · **不受额度 / 阳光余额拦截**：余额 999 / 0 都能收；
///  · **跨株一次摊平**：只 2 株有晨露时也一次收走这 2 条，不按株挑选。
///
/// ⚠️ 花园页木牌是**无限呼吸动画** → 全程用有界 `pump`（禁止 `pumpAndSettle`，C101-3）。
library one_click_collect_dew_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
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

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 每条晨露预先定奖的阳光数（故意取 6，4 条合计 24，便于断言「一分不少也没多给」）。
const int _kDewSunlight = 6;

const String _kCollectLabel = '一键采集';
const String _kEmptyHint = '暂时没有可以采集的晨露';

/// [blooming] = true → 4 株「正在盛开」的成株（可挂晨露图标）；
/// false → 4 株普通幼苗（无晨露，用于空态）。
List<Plant> _fourPlants({required bool blooming}) {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: blooming ? PlantStage.adult : PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: blooming ? 1.0 : 0.3,
        growthFactor: 1.0,
        status: blooming ? PlantStatus.bloomed : PlantStatus.growing,
        plantedAt: now.subtract(const Duration(days: 5)),
        bloomedAt: blooming ? now.subtract(const Duration(hours: 1)) : null,
        bloomCount: blooming ? 1 : 0,
        lastWaterAt: now, // 刚浇过水 → 3 天内不枯萎
      ),
  ];
}

/// 给前 [count] 株各挂 1 条「开花瞬间 · 即刻可收」的晨露（与真实掉落同形状）。
List<PendingBloomReward> _dueRewards(int count) {
  final DateTime now = DateTime.now();
  return <PendingBloomReward>[
    for (int i = 0; i < count; i++)
      PendingBloomReward(
        id: 'r$i',
        plantId: 'p$i',
        dueAt: now.subtract(const Duration(hours: 1)),
        rewardKind: 'instant',
        rewardSunlight: _kDewSunlight,
      ),
  ];
}

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 6,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// **记账版**阳光仓储：把每次 [append] 的金额记下来，用于断言「收了几条、共多少钱」。
class _RecordingSunlightRepository implements SunlightRepository {
  final List<double> appended = <double>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry.net);
    return 999.0;
  }

  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
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
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _FakeFocusRepository implements FocusRepository {
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

class _StoringPlantRepository implements PlantRepository {
  _StoringPlantRepository(this._plants);
  final List<Plant> _plants;
  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _plants) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    _plants.removeWhere((Plant p) => p.id == plant.id);
    _plants.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      _plants.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 把 4 株 + 若干条晨露装进真实花园页，返回（仓储, 记账阳光仓储）。
Future<({InMemoryBloomRewardRepository rewards, _RecordingSunlightRepository ledger})>
    _pumpGarden(
  WidgetTester tester, {
  required bool blooming,
  required int dueCount,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final List<Plant> plants = _fourPlants(blooming: blooming);
  final InMemoryBloomRewardRepository rewards = InMemoryBloomRewardRepository();
  for (final PendingBloomReward r in _dueRewards(dueCount)) {
    await rewards.insertPendingBloomReward(r);
  }
  final _RecordingSunlightRepository ledger = _RecordingSunlightRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        // 一键操作按档位门控（free 隐藏 FAB）→ 本用例按买断档运行。
        entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(ledger),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider
            .overrideWithValue(_StoringPlantRepository(plants)),
        bloomRewardRepositoryProvider.overrideWithValue(rewards),
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

  // 等花园页首次加载完（悬浮球出现 = 存活株 ≥ 4 已判定）。
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作悬浮球');

  // 展开操作卡。
  await tester.tap(find.byIcon(Icons.touch_app));
  final bool cardShown = await _pumpUntil(
    tester,
    () => find.text(_kCollectLabel).evaluate().isNotEmpty,
  );
  expect(cardShown, isTrue,
      reason: '展开卡必须有「$_kCollectLabel」这一行（第 4 行）');
  await tester.pump(const Duration(milliseconds: 300));

  return (rewards: rewards, ledger: ledger);
}

void main() {
  testWidgets('4 株各挂 1 条晨露 → 一键采集：不走确认卡、4 条全收、合计 24 ☀',
      (WidgetTester tester) async {
    final ({
      InMemoryBloomRewardRepository rewards,
      _RecordingSunlightRepository ledger
    }) ctx =
        await _pumpGarden(tester, blooming: true, dueCount: 4);

    // 前置：4 条确实「到期可收」（否则后面断言 claimed 会变成空转）。
    final List<PendingBloomReward> before =
        await ctx.rewards.pendingBloomRewardsDue(DateTime.now());
    expect(before.length, 4, reason: '前置：应有 4 条到期晨露可收');

    await tester.tap(find.text(_kCollectLabel));
    // 采集是异步（逐条结算），给足帧数等结果。
    final bool collected = await _pumpUntil(
      tester,
      () => ctx.ledger.appended.length >= 4,
    );
    expect(collected, isTrue, reason: '点「$_kCollectLabel」后应立即逐条结算入账');

    // ① **不弹确认卡**（这是收钱不是花钱，孩子不该被多点一次）。
    expect(find.text('确定'), findsNothing,
        reason: '一键采集**不得**弹确认卡（与浇水/施肥/护理刻意区分）');

    // ② 4 条全部 marked claimed（一条不剩、也不再「可收」）。
    final List<PendingBloomReward> after =
        await ctx.rewards.pendingBloomRewardsDue(DateTime.now());
    expect(after, isEmpty, reason: '一键采集后不得残留任何到期未领的晨露');

    // ③ 阳光合计入账 = 4 × 6 = 24，且是**4 笔**（不是合并成一笔乱账）。
    expect(ctx.ledger.appended.length, 4, reason: '每条晨露各入账一笔');
    expect(ctx.ledger.appended.fold<double>(0, (double a, double b) => a + b),
        _kDewSunlight * 4.0,
        reason: '合计必须等于 4 条预估阳光之和（多给/少给都是账错）');

    // ④ 提示文案**按类目合并**，不是把同一句复读 4 遍。
    expect(find.text('+24 ☀ 阳光'), findsOneWidget,
        reason: '一次收 4 条应合并成「+24 ☀ 阳光」（玄参：孩子要知道一共收到多少）');

    // 提示浮层约 1.3s 后自清（与一键成功提示同节奏）。
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump();
    expect(find.text('+24 ☀ 阳光').evaluate(), isEmpty,
        reason: '提示浮层应按 kOneClickHintHoldMs 节奏淡出');
  });

  testWidgets('只有 2 株有晨露 → 仍一次收走这 2 条（跨株摊平，不按株挑选）',
      (WidgetTester tester) async {
    final ({
      InMemoryBloomRewardRepository rewards,
      _RecordingSunlightRepository ledger
    }) ctx =
        await _pumpGarden(tester, blooming: true, dueCount: 2);

    await tester.tap(find.text(_kCollectLabel));
    await _pumpUntil(
      tester,
      () => ctx.ledger.appended.length >= 2,
    );

    expect(await ctx.rewards.pendingBloomRewardsDue(DateTime.now()), isEmpty,
        reason: '一键采集是「全花园摊平」，有晨露的株全部收走');
    expect(ctx.ledger.appended.length, 2, reason: '只有 2 条 → 只入账 2 笔');
    expect(
        ctx.ledger.appended.fold<double>(0, (double a, double b) => a + b),
        _kDewSunlight * 2.0);
    expect(find.text('+12 ☀ 阳光'), findsOneWidget,
        reason: '2 条合并成「+12 ☀ 阳光」');
  });

  testWidgets('一株晨露都没有 → 居中提示「$_kEmptyHint」，且不写任何账',
      (WidgetTester tester) async {
    final ({
      InMemoryBloomRewardRepository rewards,
      _RecordingSunlightRepository ledger
    }) ctx =
        await _pumpGarden(tester, blooming: false, dueCount: 0);

    await tester.tap(find.text(_kCollectLabel));
    final bool hinted = await _pumpUntil(
      tester,
      () => find.text(_kEmptyHint).evaluate().isNotEmpty,
    );
    expect(hinted, isTrue,
        reason: '空态必须给「$_kEmptyHint」（与其余三项空态同节奏，走居中浮层）');

    // 空态：绝不入账、绝不误弹确认卡。
    expect(ctx.ledger.appended, isEmpty, reason: '没有晨露时不得写任何阳光流水');
    expect(find.text('确定'), findsNothing);
  });
}
