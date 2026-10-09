/// P0 端到端 · 花园页「催熟到成株」后头顶奖励图标必须在树中渲染（真机回归守卫）。
///
/// 用户口径（2026-10-07）：「催熟植物，催熟后，植物产生的产物不在植物前面显示了」。
/// 本用例走**真实 GardenPage + 真实 PlantGrowthService**：种一株「成株 / 成长中 / 进度满」
/// 的植物 → 打开花期调试面板 → 点「催熟到成株」→ 断言花园页出现 `BloomRewardIconsBar`
/// （头顶奖励图标数据源 = `collectibleBloomRewards`）。
///
/// ⚠️ 花园页木牌是**无限呼吸动画** → 全程用有界 `pump`（禁止 pumpAndSettle）。
library garden_bloom_reward_after_force_adult_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
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
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株「成株 / 成长中 / 进度满」的植物（点「催熟到成株」→ 本 tick 即开花）。
/// ⚠️ 时间戳一律相对 now 构造（花园页走真实时钟，写死绝对日期会随天数变化假红）。
Plant _readyToBloom() {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.adult,
    stageStartedAt: now.subtract(const Duration(hours: 1)),
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now.subtract(const Duration(hours: 2)),
    lastWaterAt: now,
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
  int maxFrames = 160,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Widget _host(PlantRepository plants) => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        plantGrowthServiceProvider.overrideWith((ref) => PlantGrowthService(
              plants: ref.watch(plantRepositoryProvider),
              focus: ref.watch(focusRepositoryProvider),
              ledger: ref.watch(sunlightRepositoryProvider),
              settings: ref.watch(settingsRepositoryProvider),
              bloomRewards: ref.watch(bloomRewardRepositoryProvider),
              weedRandom: NoHitRandom(),
            )),
      ],
      child:
          const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

void main() {
  testWidgets('催熟到成株 → 头顶奖励图标（BloomRewardIconsBar）必须渲染', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _StoringPlantRepository repo =
        _StoringPlantRepository(<Plant>[_readyToBloom()]);
    await tester.pumpWidget(_host(repo));

    // 打开调试面板。
    await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(BloomDebugEntry));
    await _pumpUntil(tester, () => find.text('催熟到成株').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400)); // sheet 入场动画

    // 点「催熟到成株」→ 该株本 tick 开花 → 头顶奖励图标应出现。
    await tester.tap(find.text('催熟到成株'));
    final bool iconsShown = await _pumpUntil(
      tester,
      () => find.byType(BloomRewardIconsBar).evaluate().isNotEmpty,
      maxFrames: 200,
    );
    expect(iconsShown, isTrue,
        reason: '催熟开花后，花盆头顶必须渲染可点击奖励图标（用户口径：看不到 = 回归）');
    // 进一步：图标确实是**可点击节点**（BloomRewardIcon 带命中区），且落在花盆格内
    // （= 叠在植物图层之上、不越界），确认「能看见、能点」。
    expect(find.byType(BloomRewardIcon).evaluate(), isNotEmpty,
        reason: '奖励图标必须是可点击的 BloomRewardIcon 节点');
    final Rect iconRect = tester.getRect(find.byType(BloomRewardIconsBar).first);
    final Rect screenRect = tester.getRect(find.byType(GardenPage));
    expect(screenRect.overlaps(iconRect), isTrue,
        reason: '头顶奖励图标必须落在屏幕可视范围内（可被看到 / 点击）');
  });
}
