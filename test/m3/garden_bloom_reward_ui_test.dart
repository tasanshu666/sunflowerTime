/// 花园页「第二段奖励气泡 + 精品碎片入口」UI 冒烟测试（成株后循环玩法 Batch 1 修订）。
///
/// 覆盖：
///  · 存在「可收集」第二段奖励时，花盆旁出现可点击明细图标；点击收集后图标消失。
///  · 常驻「精品碎片 N」入口显示当前余额。
///
/// ⚠️ 花园页木牌默认 `animate: true`（无限呼吸动画）→ 一律 `pumpAndSettle` 会永不返回，
///    故用**有界 `pump`** 推进（同 `garden_layout_v3_test` 的手法）。
library garden_bloom_reward_ui_test;

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

// ── 假仓储（参考 garden_layout_v3_test 的覆盖手法）────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株「已盛开且不会在本 tick 枯萎」的植物（now 相对构造）：2 天前开花 / 2 天前浇水。
Plant _bloomedPlant(DateTime now) {
  final DateTime bloomAt = now.subtract(const Duration(days: 2));
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
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

bool _bubblePresent() => find.byIcon(Icons.card_giftcard).evaluate().isNotEmpty;
bool _sunPresent() => find.byIcon(Icons.wb_sunny).evaluate().isNotEmpty;

void main() {
  testWidgets('有可收集第二段奖励 → 花盆旁出现明细图标；点击后消失（已收集）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final Plant plant = _bloomedPlant(now);
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    // 已到期（now 之前 1 小时）→ 可收集；显式带明细列（阳光 12）使图标确定、不触发物化。
    await bloom.insertPendingBloomReward(PendingBloomReward(
      id: 'pr1',
      plantId: plant.id,
      dueAt: now.subtract(const Duration(hours: 1)),
      rewardKind: kBloomRewardKindNormal,
      rewardSunlight: 12,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider
            .overrideWithValue(_FakePlantRepository(<Plant>[plant])),
        bloomRewardRepositoryProvider.overrideWithValue(bloom),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    ));

    // 明细图标出现（入场动画为有限时长，有界 pump 收敛）。
    final bool appeared = await _pumpUntil(tester, _sunPresent);
    expect(appeared, isTrue, reason: '到期且花仍盛开 → 应出现可收集明细图标');

    // 精品碎片入口常驻，显示余额 0。
    expect(find.text('植物碎片 0'), findsOneWidget);

    // 让头顶图标入场动画（有限时长）走完，避免误点在缩放中途。
    await tester.pump(const Duration(milliseconds: 600));

    // 点击收集 → 服务发放并置 claimed → 刷新后头顶图标消失。
    await tester.tap(find.byIcon(Icons.wb_sunny));
    final bool gone = await _pumpUntil(tester, () => !_sunPresent());
    expect(gone, isTrue, reason: '收集后明细图标应消失（奖励已 claimed）');

    // 已收集：无剩余可收集奖励。
    expect(await bloom.pendingBloomRewardsDue(DateTime.now()), isEmpty);
  });

  testWidgets('无到期奖励 → 无气泡，但碎片入口仍在', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final Plant plant = _bloomedPlant(now);
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider
            .overrideWithValue(_FakePlantRepository(<Plant>[plant])),
        bloomRewardRepositoryProvider.overrideWithValue(bloom),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    ));

    // 等一次网格/入口建好。
    final bool ready = await _pumpUntil(
      tester,
      () => find.text('植物碎片 0').evaluate().isNotEmpty,
    );
    expect(ready, isTrue, reason: '碎片入口应常驻显示');
    expect(_bubblePresent(), isFalse, reason: '无到期奖励不应出现气泡');
  });
}
