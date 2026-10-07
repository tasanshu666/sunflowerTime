/// 花园页「花期调试」面板（**仅 kDebugMode**）冒烟测试。
///
/// 覆盖：
///  · 源码守卫：入口确实被 `if (kDebugMode …)` 包裹（release 自动隐藏）。
///  · 真实 `GardenPage`：debug 下入口渲染 → 点击弹出面板（标题 + 5 个动作按钮）。
///  · 面板动作**走真实领域逻辑**：点「催熟到成株」→ 目标株被 [PlantGrowthService]
///    结算为「盛开」（status=bloomed、bloomCount+1），而非面板自己造状态。
///
/// ⚠️ 花园页木牌是**无限呼吸动画** → 本文件一律用**有界 `pump`**（禁止 `pumpAndSettle`）。
library bloom_debug_panel_test;

import 'dart:io';

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

import '../helpers/no_hit_random.dart';

// ── 假仓储 ──────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株「幼苗 · 成长中」的植物（未被催熟前不是盛开态）。
///
/// ⚠️ 时间戳必须**相对 `DateTime.now()`** 构造，不能写死绝对日期：
/// 花园页内部走真实时钟，若 `lastWaterAt` 写死成过去的某一天，
/// 一旦真实时间超过 `kPlantWiltDays`（3 天）未浇水，`tickAll` 会把该株结算成
/// `wilting`，「催熟前应为 growing」的断言必然变红（2026-09-28 实际踩到：
/// 夹具写死 09-25，跑到 09-28 时满 3.4 天 → 假红）。
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
    lastWaterAt: now, // 刚浇过水 → 3 天内不会枯萎
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

/// **会落库**的植物仓储：面板动作写字段后，tickAll 结算结果可被断言。
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

/// 有界帧推进：最多 [maxFrames] 帧、每帧 [step]，直到 [ready] 为真即停。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 120,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Widget _host(PlantRepository plants, {InMemoryBloomRewardRepository? bloom}) =>
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
        bloomRewardRepositoryProvider.overrideWithValue(
            bloom ?? InMemoryBloomRewardRepository()),
        // C26：干扰物 roll 注入「永不命中」桩 —— 本文件验的是调试面板与催熟
        // 链路，随机长出的杂草/虫会当天暂停成长、让催熟结算不盛开（实证红过）。
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
  testWidgets('源码守卫：入口必须写在 if (kDebugMode …) 内（release 自动隐藏）',
      (WidgetTester tester) async {
    final String src = File('lib/presentation/child/pages/garden_page.dart')
        .readAsStringSync();
    expect(src.contains("import 'package:flutter/foundation.dart';"), isTrue,
        reason: 'kDebugMode 来自 foundation.dart');
    expect(
      RegExp(r'if \(kDebugMode[\s\S]{0,400}?BloomDebugEntry').hasMatch(src),
      isTrue,
      reason: '调试入口必须被 if (kDebugMode …) 包裹，release 才不会渲染',
    );
  });

  testWidgets('debug 下入口渲染 → 点击弹出面板，含 5 个动作按钮', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_sprout()])));

    // 入口渲染（debug 恒为 true）。
    final bool entryShown = await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    expect(entryShown, isTrue, reason: 'debug 下花园页应出现「花期调试」入口');

    // 点击 → 弹出面板（等动作按钮出现 = 数据加载完成 `_loaded`）。
    await tester.tap(find.byType(BloomDebugEntry));
    final bool sheetShown = await _pumpUntil(
      tester,
      () => find.text('催熟到成株').evaluate().isNotEmpty,
    );
    expect(sheetShown, isTrue, reason: '点击入口应弹出调试面板');
    expect(find.text('花期调试'), findsOneWidget);

    // 面板最小可用能力：目标选择 + 5 个动作按钮。
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    for (final String label in <String>[
      '应用进度并结算',
      '催熟到成株',
      '立即花谢',
      '让待领奖励可领取',
      '快进 +1 天',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺动作按钮：$label');
    }
  });

  testWidgets('动作走真实领域逻辑：点「催熟到成株」→ 目标株被结算为盛开', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _StoringPlantRepository repo =
        _StoringPlantRepository(<Plant>[_sprout()]);
    await tester.pumpWidget(_host(repo));

    await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(BloomDebugEntry));
    await _pumpUntil(
      tester,
      () => find.text('催熟到成株').evaluate().isNotEmpty,
    );
    // 等 bottom sheet 的**入场滑入动画**走完（有限时长）——否则按钮还在屏幕外，
    // tap 会落空。（花园页木牌是无限动画，故用有界 pump 而非 pumpAndSettle。）
    await tester.pump(const Duration(milliseconds: 400));

    // 催熟前：非盛开。
    expect((await repo.plant('p1'))!.status, PlantStatus.growing);

    await tester.tap(find.text('催熟到成株'));
    final bool bloomed = await _pumpUntil(
      tester,
      () => find.text('盛开').evaluate().isNotEmpty,
    );
    expect(bloomed, isTrue, reason: '催熟后状态回显应变为「盛开」');

    // 领域真实结果：tickAll 已把该株结算为盛开（bloomCount 0 → 1）。
    final Plant after = (await repo.plant('p1'))!;
    expect(after.stage, PlantStage.adult);
    expect(after.status, PlantStatus.bloomed);
    expect(after.bloomCount, 1);
  });

  testWidgets('调试面板「+1 普通种子」→ 走领域发券（unlockedSpecies 增）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _StoringPlantRepository repo =
        _StoringPlantRepository(<Plant>[_sprout()]);
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    await tester.pumpWidget(_host(repo, bloom: bloom));

    await _pumpUntil(
      tester,
      () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(BloomDebugEntry));
    await _pumpUntil(
      tester,
      () => find.text('+1 普通种子').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(await bloom.unlockedSpeciesIds(), isEmpty, reason: '发券前无种子');
    await tester.tap(find.text('+1 普通种子'));
    // 等发券落库（按钮动作异步 → 逐帧推进有限帧）。
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(await bloom.unlockedSpeciesIds(), contains('species_sunflower'),
        reason: '普通档券应落到普通物种 species_sunflower');
  });
}
