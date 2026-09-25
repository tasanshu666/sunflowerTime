/// 养护面板 · iPhone 17 尺寸（402×874）溢出回归（2026-09-24 玄参模拟器反馈）。
///
/// 真实症状：在 iOS 模拟器（iPhone 17，iOS 27.0）点**已种植物的花盆**，
/// 弹出的养护面板右侧出现**贯穿全高的黄黑溢出警示条**（水平方向溢出约 40+px）。
/// 原有布局测试都在 360×780 / 800×600 下跑 —— 屏宽口径没有覆盖 402，漏了这档。
///
/// 本文件把 iPhone 17 的逻辑尺寸钉成回归：`tester.takeException()` 抓
/// RenderFlex overflow（debug 下溢出必经 `FlutterError.reportError`），
/// 溢出即红，且错误信息自带 widget 链（定位用）。
library plant_care_sheet_iphone_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

final DateTime _t = DateTime(2026, 9, 24, 8);

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

Plant _plantedSunflower() => Plant(
      id: 'plant-1',
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: _t,
      growthProgress: 0.1,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: _t,
    );

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

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async => <FocusSession>[];
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
  @override
  Future<List<Plant>> plants() async => <Plant>[_plantedSunflower()];
  @override
  Future<Plant?> plant(String id) async =>
      id == 'plant-1' ? _plantedSunflower() : null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

Widget _host() => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

/// 有界推进：木牌呼吸动画无限循环，`pumpAndSettle` 永不返回，必须按条件有界 pump。
Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'iPhone 17（402×874）：点已种植物 → 养护面板不得溢出（黄黑条回归）',
    (WidgetTester tester) async {
      // iPhone 17 逻辑分辨率：402×874 @3x（模拟器实测 402x874@3x）。
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host());
      await _pumpFrames(tester, 30); // 等网格 + 数据就绪
      expect(find.byType(GardenPot), findsOneWidget);

      // 点已种植物的花盆 → 弹养护面板（内部异步读数据）。
      await tester.tap(find.byType(GardenPot));
      await _pumpFrames(tester, 30); // 面板路由动画 + _load 完成

      expect(find.text('向日葵'), findsWidgets,
          reason: '养护面板应已打开（能看到植物名）');

      final Object? ex = tester.takeException();
      expect(
        ex,
        isNull,
        reason: '养护面板在 402 宽下溢出（RenderFlex overflow）'
            '——玄参 2026-09-24 模拟器截图：右侧贯穿全高的黄黑警示条',
      );
    },
  );
}
