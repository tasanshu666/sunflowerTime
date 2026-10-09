/// P0 端到端 · 一键操作汇总提示卡「**确定性居中** + 快速淡出」（真机回归守卫）。
///
/// 玄参 2026-10-07 真机口径：「一键浇水的提示卡，还是在屏幕的最下面，没有移动到中间，
/// 而且淡出的时间还是很长，不是 1s」。本用例走**真实 GardenPage**：
/// 种 4 株 → 点右下 FAB → 一键浇水 → 确认 → 断言提示卡胶囊**中心 = 屏幕中心**
/// （偏差 < [kOneClickBatchHintCenterTolerance]），且停留 ~1s 后**被移除**。
///
/// ⚠️ 花园页木牌是**无限呼吸动画** → 全程用有界 `pump`（禁止 pumpAndSettle）。
library one_click_batch_hint_center_test;

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

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 4 株「幼苗 · 成长中 · 两日前浇过水」的活株（可一键浇水，未枯萎）。
List<Plant> _fourSprouts() {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: 0.3,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now.subtract(const Duration(hours: 2)),
        lastWaterAt: now.subtract(const Duration(days: 2)),
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
  testWidgets('一键浇水汇总提示卡：中心 = 屏幕中心、约 1s 后移除', (WidgetTester tester) async {
    const Size logical = Size(390, 844);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_fourSprouts())));

    // 等一键 FAB 出现（存活株 ≥ 4）。
    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

    // 展开 FAB → 点「一键浇水」。
    await tester.tap(find.byIcon(Icons.touch_app));
    final bool cardShown = await _pumpUntil(
      tester,
      () => find.text('一键浇水').evaluate().isNotEmpty,
    );
    expect(cardShown, isTrue, reason: '点 FAB 应展开操作卡');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('一键浇水'));

    // 确认卡 → 点「确定」。
    final bool dialogShown = await _pumpUntil(
      tester,
      () => find.text('要一键浇水吗？').evaluate().isNotEmpty,
    );
    expect(dialogShown, isTrue, reason: '一键浇水应先弹确认卡');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定'));

    // 提示卡出现。
    final bool hintShown = await _pumpUntil(
      tester,
      () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty,
    );
    expect(hintShown, isTrue, reason: '一键浇水成功后应显示汇总提示卡');

    // 度量：胶囊中心 = 屏幕中心（偏差 < 容差）。
    final Offset pillCenter = tester.getCenter(find.byKey(kOneClickBatchHintPillKey));
    final Offset screenCenter = Offset(logical.width / 2, logical.height / 2);
    expect((pillCenter.dx - screenCenter.dx).abs(),
        lessThan(kOneClickBatchHintCenterTolerance),
        reason: '提示卡必须**屏幕水平居中**（真机「在最下面」回归）');
    expect((pillCenter.dy - screenCenter.dy).abs(),
        lessThan(kOneClickBatchHintCenterTolerance),
        reason: '提示卡必须**屏幕垂直居中**（真机「在最下面」回归）');

    // 停留 ~1s + 淡出后，浮层被移除（总 = 淡入120 + 停留1000 + 淡出300 = 1420ms）。
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isEmpty,
        reason: '提示卡应在约 1.3s 后淡出消失（玄参「淡出时间还是很长」回归）');
  });
}
