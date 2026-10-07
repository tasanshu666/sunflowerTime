/// QA 独立反证 · 第二批 E/F 项（2026-10-07）——调试面板文案「待领奖励」精确匹配唯一性。
///
/// 背景：F 项把调试面板**状态卡标签**由「48h 奖励」订正为「待领奖励」；同时
/// `bloom_debug_panel.dart:517` 的**动作按钮**文案亦订正为「让待领奖励可领取」。
/// 本用例独立断言二者**互不碰撞**：
///   · `find.text('待领奖励')`         → 恰好 1 个（状态卡标签，精确匹配）；
///   · `find.text('让待领奖励可领取')` → 恰好 1 个（动作按钮，精确匹配）；
///   · `find.text('让 48h 奖励可领取')` → 0 个（旧按钮文案已移除）；
///   · `find.text('48h 奖励')`         → 0 个（旧状态标签已移除）。
///
/// 说明：`find.text` 默认**精确**匹配，故「待领奖励」不会命中「让待领奖励可领取」。
/// ⚠️ 花园页木牌无限呼吸动画 → 全程有界 `pump`（禁止 pumpAndSettle）。
library qa_independent_round2_ef_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

Plant _sprout() {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: now.subtract(const Duration(hours: 2)),
    growthProgress: 0.3,
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
      gardenPotCapacity: 6,
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
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Widget _host(SharedPreferences prefs) => ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider
            .overrideWithValue(_StoringPlantRepository(<Plant>[_sprout()])),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
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
    );

void main() {
  testWidgets('E/F：「待领奖励」精确匹配唯一，与按钮「让待领奖励可领取」互不碰撞',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_host(prefs));

    final bool entryShown = await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    expect(entryShown, isTrue, reason: 'debug 下花园页应出现「花期调试」入口');
    await tester.tap(find.byType(BloomDebugEntry));
    final bool panelShown = await _pumpUntil(
      tester,
      () => find.text('待领奖励').evaluate().isNotEmpty,
    );
    expect(panelShown, isTrue, reason: '调试面板应出现状态卡标签「待领奖励」');
    await tester.pump(const Duration(milliseconds: 400));

    // F：状态卡标签（精确匹配恰好 1 个）。
    expect(find.text('待领奖励'), findsOneWidget,
        reason: 'F：状态卡标签应恰为「待领奖励」');

    // 动作按钮（精确匹配恰好 1 个）——与「待领奖励」是不同字符串，不互撞。
    expect(find.text('让待领奖励可领取'), findsOneWidget,
        reason: '动作按钮文案应为「让待领奖励可领取」；与「待领奖励」不同串，不互撞');

    // 旧文案已移除。
    expect(find.text('48h 奖励'), findsNothing,
        reason: 'F：过期的状态标签「48h 奖励」应已移除');
    expect(find.text('让 48h 奖励可领取'), findsNothing,
        reason: '旧动作按钮文案「让 48h 奖励可领取」应已订正');
  });
}
