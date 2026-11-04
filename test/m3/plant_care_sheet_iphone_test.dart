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

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

import '../helpers/no_hit_random.dart';

/// 夹具的时间基准：**相对当前时刻**，不写死日期。
///
/// 🔴 原写法是 `DateTime(2026, 9, 24, 8)`（一个固定过去的日期）。本文件每跑一天，
/// 这株「种子」的「已种时长」就多一天；`_sunflower.growthHoursPerStage = 240`
/// （10 天/阶段），41 天后它会被 `tickAll` 补结算到开花甚至枯萎，
/// 「点花盆 → 弹养护卡」这条**前置**会在某个日期之后整体失效。
/// 取「5 分钟前」⇒ 无论哪天跑都稳定停在 `seed` + `growing`（5 分钟只够走
/// 0.0035 个阶段，离下一阶段差 299.6pp）。
DateTime get _t => DateTime.now().subtract(const Duration(minutes: 5));

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

/// 被测领域服务：**干扰物随机源注入 [NoHitRandom]**，让这一轮恒定没有杂草 / 害虫。
///
/// 🔴 为什么必须注入（真正的 flaky 根因，2026-11-05 诊断实测确认）：
/// `PlantGrowthService._rollWeedPest` 每株每次 tick 各自 roll 一次
/// （`kGardenWeedRate` 0.40 / `kGardenPestRate` 0.30，互不排斥），默认 `Random()`
/// 是**真随机** ⇒ 每天至少中一项的概率 `1 − 0.6×0.7 = 58%`。中招时花盆上会多出
/// 「杂草 / 害虫」清除浮标，且它压在花盆的命中中心上 ——
/// `tester.tap(find.byType(GardenPot))` 于是点到的是**清除浮标**而不是花盆：
/// 弹出来的是「这盆没有害虫哦」（`shared_plant_err_no_pest`）的 SnackBar，
/// 养护卡压根没打开 ⇒ `find.text('向日葵')` 找到 0 个。
/// 这个 58% 与「连跑 8 次 5 红 3 绿」的实测比例吻合，且红的那一轮屏幕文案里
/// **没有**任何 Dialog 内容、只有一句「这盆没有害虫哦」。
///
/// ⚠️ 只改时间**不足以**修好它：roll 与盆龄无关，是每次 tick 独立掷骰子。
PlantGrowthService _serviceForTest() => PlantGrowthService(
      plants: _FakePlantRepository(),
      focus: _FakeFocusRepository(),
      ledger: _FakeSunlightRepository(),
      settings: _FakeSettingsRepository(),
      bloomRewards: InMemoryBloomRewardRepository(),
      weedRandom: NoHitRandom(), // C26 干扰物永不出现（0.40 / 0.30 任一命中都会抢走点击）
    );

Widget _host() => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        // 领域服务必须一并覆盖：仓储覆盖只换了数据源，`weedRandom` 仍然长在
        // `plantGrowthServiceProvider` 内部的 `Random()` 上（该 provider 没有暴露
        // 注入位），不覆盖就等于没注入。
        plantGrowthServiceProvider.overrideWithValue(_serviceForTest()),
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
