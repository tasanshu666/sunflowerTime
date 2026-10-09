/// E 项（玄参 2026-10-07「打开软件直接进主页，看不到欢迎页，无法反馈」）：
/// 花期调试面板新增「预览首启欢迎页」入口 → **只读预览** [ConsentPage]（preview:true）。
///
/// 断言：
///   · 入口存在，点击后打开的是欢迎/同意页（有「返回花园」按钮 / 吉祥物）；
///   · 预览路径**不写任何同意状态**（[SettingsStore.isFirstLaunchConsented] 仍为 false）；
///   · 返回后回到花园（调试入口重新可见）。
///   ·（顺带覆盖 F 项）调试面板状态卡标签为「待领奖励」、不再是过期的「48h 奖励」。
///
/// ⚠️ 花园页木牌是**无限呼吸动画** → 全程用有界 `pump`（禁止 pumpAndSettle）。
library consent_preview_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
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
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Widget _host(PlantRepository plants, SharedPreferences prefs) => ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
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
  testWidgets('调试面板「预览首启欢迎页」只读打开，不写同意状态',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_sprout()]), prefs));

    // 打开花期调试面板。
    final bool entryShown = await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    expect(entryShown, isTrue, reason: 'debug 下花园页应出现「花期调试」入口');
    await tester.tap(find.byType(BloomDebugEntry));
    final bool panelShown = await _pumpUntil(
      tester,
      () => find.text('预览首启欢迎页').evaluate().isNotEmpty,
    );
    expect(panelShown, isTrue, reason: '调试面板应有「预览首启欢迎页」按钮');

    // F 项（顺带）：状态卡标签已订正为「待领奖励」、无过期的「48h 奖励」。
    expect(find.text('待领奖励'), findsOneWidget, reason: '标签应订正为「待领奖励」');
    expect(find.text('48h 奖励'), findsNothing, reason: '过期的「48h 奖励」标签应已移除');

    await tester.pump(const Duration(milliseconds: 400)); // sheet 入场动画

    // 预览按钮位于面板（可滚动）底部，可能落在屏幕外 → 先滚入可见区再点，
    // 否则 tap 的落点越界（360×780 下实测在 y=808）会命中失败。
    final Finder previewBtn = find.text('预览首启欢迎页');
    await tester.ensureVisible(previewBtn);
    await tester.pump();

    // 点预览 → 打开欢迎/同意页（只读：按钮文案为「返回花园」）。
    await tester.tap(previewBtn);
    final bool consentShown = await _pumpUntil(
      tester,
      () => find.text('返回花园').evaluate().isNotEmpty,
    );
    expect(consentShown, isTrue, reason: '预览应打开欢迎/同意页（只读：按钮为「返回花园」）');
    expect(find.text('欢迎使用向日葵专注'), findsOneWidget);
    expect(find.text('同意并开始'), findsNothing,
        reason: '预览模式不得出现真实「同意并开始」主按钮');

    // 预览不得写任何同意状态。
    expect(await SettingsStore(prefs).isFirstLaunchConsented(), isFalse,
        reason: '预览只读：不得写入首次启动同意标记');

    // 返回 → 回到花园（调试入口重新可见），仍未写同意状态。
    await tester.tap(find.text('返回花园'));
    final bool backToGarden = await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    expect(backToGarden, isTrue, reason: '返回后应回到花园');
    expect(await SettingsStore(prefs).isFirstLaunchConsented(), isFalse,
        reason: '预览全程不得写入同意状态');
  });
}
