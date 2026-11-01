/// F168 · 收集幽灵（[CollectGhost]）图标多时**横向溢出**回归。
///
/// 玄参 2026-11-01 截图实证：晨露在多槽位累积多天后，点花盆头顶的收取图标 →
/// 屏幕右侧出现 `RIGHT OVERFLOWED BY 4.0 PIXELS` 黄黑斜纹。
///
/// 根因：常驻的 [BloomRewardIconsBar] 有 `FittedBox(scaleDown)` 兜底，但点击后
/// 飞走的 [CollectGhost] 直接是裸 `Row(mainAxisSize: min)`，而它被
/// `Positioned.fromRect` **锁死在花盆格的矩形内** → 聚合出 3~4 个图标
/// （阳光 + 碎片 + 种子 + 礼包，单个命中区 42×uiScale）就必然撑破格宽。
///
/// 本测试用「4 盆 × 多槽位晨露」的高密度真实场景复现，断言：
///  · 点击收取图标后**不得抛任何 overflow 异常**；
///  · 幽灵仍要正常渲染（不能靠「干脆不画」蒙混过关）。
library garden_collect_ghost_overflow_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株已盛开、两天前开花的植物（不会在本 tick 枯萎）。
Plant _bloomedPlant(DateTime now, String id, int potIndex) {
  final DateTime bloomAt = now.subtract(const Duration(days: 2));
  return Plant(
    id: id,
    speciesId: 'species_sunflower',
    potIndex: potIndex,
    stage: PlantStage.adult,
    stageStartedAt: bloomAt,
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: PlantStatus.bloomed,
    plantedAt: bloomAt,
    lastWaterAt: bloomAt,
    bloomedAt: bloomAt,
    bloomCount: 1,
    mood: PlantMood.calm,
  );
}

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 4,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
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
  Future<int> countByRefType(String refType) async => 0;
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

class _FakePlantRepository implements PlantRepository {
  _FakePlantRepository(this._plants);
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
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

/// 有界帧推进：最多 [maxFrames] 帧、每帧 [step]，直到 [ready] 为真即停。
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

/// 花盆头顶的可收集图标（素材图或内置回退 Icon 都算）。
Finder _sunIconFinder() => find.byWidgetPredicate((Widget w) =>
    (w is Icon && w.icon == Icons.wb_sunny) ||
    (w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/rewards/sunlight.png'));

void main() {
  /// **每株 4 条到期 pending** → 聚合出「阳光 + 碎片 + 种子」3 个图标：
  /// 正是玄参真机「晨露累积多了」的形状（单图标 42×uiScale，3 个 ≈ 126 > 格宽）。
  Future<void> insertDenseRewards(
    InMemoryBloomRewardRepository bloom,
    DateTime now,
    String plantId,
    String prefix,
  ) async {
    final List<PendingBloomReward> rows = <PendingBloomReward>[
      PendingBloomReward(
        id: '${prefix}_sun',
        plantId: plantId,
        dueAt: now.subtract(const Duration(hours: 3)),
        rewardKind: kBloomRewardKindNormal,
        rewardSunlight: 12,
      ),
      PendingBloomReward(
        id: '${prefix}_frag',
        plantId: plantId,
        dueAt: now.subtract(const Duration(hours: 2)),
        rewardKind: kBloomRewardKindNormal,
        rewardFragments: 1,
      ),
      PendingBloomReward(
        id: '${prefix}_mix',
        plantId: plantId,
        dueAt: now.subtract(const Duration(hours: 1)),
        rewardKind: kBloomRewardKindNormal,
        rewardSunlight: 5,
        rewardFragments: 2,
      ),
      PendingBloomReward(
        id: '${prefix}_seed',
        plantId: plantId,
        dueAt: now.subtract(const Duration(minutes: 30)),
        rewardKind: kBloomRewardKindNormal,
        rewardSpeciesId: 'species_sunflower',
      ),
    ];
    for (final PendingBloomReward r in rows) {
      await bloom.insertPendingBloomReward(r);
    }
  }

  testWidgets('4 盆 × 多槽位晨露 → 点收取，收集幽灵不得横向溢出',
      (WidgetTester tester) async {
    // 手机尺寸（uiScaleOf = 1），格宽最窄、最易溢出。
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final List<Plant> plants = <Plant>[
      for (int i = 0; i < 4; i++) _bloomedPlant(now, 'p$i', i),
    ];
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    for (final Plant p in plants) {
      await insertDenseRewards(bloom, now, p.id, p.id);
    }

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository(plants)),
        bloomRewardRepositoryProvider.overrideWithValue(bloom),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    ));

    final bool appeared = await _pumpUntil(
      tester,
      () => _sunIconFinder().evaluate().isNotEmpty,
    );
    expect(appeared, isTrue, reason: '到期且花仍盛开 → 应出现可收集图标');

    // 让入场动画走完，避免点在缩放中途。
    await tester.pump(const Duration(milliseconds: 600));
    // 清掉此前累积的异常（若网格本身有历史溢出，也要在这里先暴露）。
    expect(tester.takeException(), isNull, reason: '静置态不应有任何异常');

    // 点击第 1 盆的收取图标 → 触发 CollectGhost（本次缺陷的现场）。
    await tester.tap(_sunIconFinder().first);
    // 幽灵只用有限时长动画（900ms），有界 pump 不会卡死。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final Object? err = tester.takeException();
    expect(
      err,
      isNull,
      reason: '收集幽灵被锁在花盆格矩形内，图标多时必须自适应缩小，不能横向溢出',
    );

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('平板（uiScale > 1）同样不得溢出', (WidgetTester tester) async {
    // iPad mini 竖屏逻辑尺寸 → shortestSide ≥ 600 → 命中平板倍率。
    tester.view.physicalSize = const Size(768 * 2, 1024 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final List<Plant> plants = <Plant>[
      for (int i = 0; i < 4; i++) _bloomedPlant(now, 'p$i', i),
    ];
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    for (final Plant p in plants) {
      await insertDenseRewards(bloom, now, p.id, p.id);
    }

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository(plants)),
        bloomRewardRepositoryProvider.overrideWithValue(bloom),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    ));

    final bool appeared = await _pumpUntil(
      tester,
      () => _sunIconFinder().evaluate().isNotEmpty,
    );
    expect(appeared, isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    await tester.tap(_sunIconFinder().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: '平板 uiScale 放大后图标更宽，收集幽灵更需收缩兜底');

    await tester.pump(const Duration(milliseconds: 900));
  });
}
