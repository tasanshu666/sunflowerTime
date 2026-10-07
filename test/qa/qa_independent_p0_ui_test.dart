/// 独立复验（QA/Edward）· P0-① 冷启动首屏 + P0-② 真实外壳下提示卡居中（widget 级）。
///
/// 与工程用例的差异（团队负责人点名）：
///  · B0/B1 冷启动首屏：**素材集合为空**时头顶奖励图标仍必须渲染（不因 `resolveRewardAsset`
///    返回 null 而被跳过项），且真实 GardenPage 必须出现 `BloomRewardIconsBar`。
///  · C1 P0-② 提示卡「屏幕正中」在**真实外壳（底部导航 + IndexedStack）**下也成立；
///    并断言约 1.5s 后浮层被移除、多次触发不叠加（OverlayEntry 不泄漏）。
library qa_independent_p0_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
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

// ── 假仓储 ──────────────────────────────────────────────────────────────────

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

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];
  @override
  Future<int> totalCheckInCount() async => 0;
}

class _FakeRewardRepository implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => <RewardTemplate>[];
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];
  @override
  Future<void> updateRequest(RedemptionRequest r) async {}
  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;
  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent event) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;
  @override
  Future<void> upsert(WeeklyPool pool) async {}
  @override
  List<String> weeksBetween(String fromKey, String toKey) => <String>[
        fromKey,
        toKey,
      ];
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

/// 4 株「可一键浇水」的活株。
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

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // B · 冷启动首屏：空素材集合
  // ═══════════════════════════════════════════════════════════════════════
  group('B · 冷启动首屏：空素材集合下头顶奖励图标仍可见', () {
    testWidgets('B0 BloomRewardIconsBar 空素材 → 仍渲染可点图标（回退内置 Icons）',
        (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BloomRewardIconsBar(
            rewards: <PendingBloomReward>[
              PendingBloomReward(
                id: 'r1',
                plantId: 'p1',
                dueAt: now,
                rewardKind: kBloomRewardPhaseInstant,
                rewardSunlight: 10,
              ),
            ],
            availableAssets: const <String>{}, // 冷启动：素材集合为空
            onCollect: (PendingBloomReward _, RewardIconSpec __) {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 350)); // 入场动画
      expect(find.byType(BloomRewardIcon), findsOneWidget,
          reason: '空素材集合不得让图标项被跳过');
      expect(find.byIcon(Icons.wb_sunny), findsOneWidget,
          reason: 'resolveRewardAsset 返回 null → 必须回退内置 Icons.wb_sunny');
    });

    testWidgets('B1 真实 GardenPage 冷启动 + rewardAssetsProvider=∅ + 已有可收集奖励 → 图标渲染',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final DateTime now = DateTime.now();
      // 一株正在盛开的植物 + 一条「本轮」instant 奖励（due = bloomedAt）。
      final Plant bloomed = Plant(
        id: 'p1',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: now.subtract(const Duration(hours: 3)),
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.bloomed,
        plantedAt: now.subtract(const Duration(hours: 5)),
        lastWaterAt: now,
        bloomedAt: now.subtract(const Duration(hours: 2)),
        bloomCount: 1,
      );
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'r1',
        plantId: 'p1',
        dueAt: now.subtract(const Duration(hours: 2)), // = bloomedAt（本轮）
        rewardKind: kBloomRewardPhaseInstant,
        rewardSunlight: 10,
      ));

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          plantRepositoryProvider
              .overrideWithValue(_StoringPlantRepository(<Plant>[bloomed])),
          bloomRewardRepositoryProvider.overrideWithValue(bloom),
          rewardAssetsProvider.overrideWith((Ref ref) async => <String>{}),
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
      ));

      final bool shown = await _pumpUntil(
        tester,
        () => find.byType(BloomRewardIconsBar).evaluate().isNotEmpty,
        maxFrames: 200,
      );
      expect(shown, isTrue,
          reason: '冷启动首屏（素材集合为空）头顶奖励图标仍必须渲染');
      expect(find.byType(BloomRewardIcon).evaluate(), isNotEmpty  ,
          reason: '必须是可点击的 BloomRewardIcon 节点');
      expect(find.byIcon(Icons.wb_sunny).evaluate(), isNotEmpty,
          reason: '空素材 → 回退内置 Icons.wb_sunny（不跳过项）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C · P0-② 真实外壳（底部导航 + IndexedStack）下提示卡居中 + 不泄漏
  // ═══════════════════════════════════════════════════════════════════════
  group('C · P0-② 真实外壳下提示卡居中 + 浮层不泄漏', () {
    testWidgets('C1 底部导航外壳中触发一键浇水 → 提示卡中心 = 整屏中心、~1.5s 后移除、多次触发不叠加',
        (WidgetTester tester) async {
      const Size logical = Size(390, 844);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
          plantRepositoryProvider
              .overrideWithValue(_StoringPlantRepository(_fourSprouts())),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
          rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
          trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
          weeklyPoolRepositoryProvider
              .overrideWithValue(_FakeWeeklyPoolRepository()),
        ],
        child: const MaterialApp(home: ChildShellPage()),
      ));

      // 切到「花园」tab（底部导航，index 2）。
      final bool shellShown =
          await _pumpUntil(tester, () => find.text('花园').evaluate().isNotEmpty);
      expect(shellShown, isTrue, reason: '外壳应渲染底部导航');
      await tester.tap(find.byIcon(Icons.yard_outlined));
      await tester.pump(const Duration(milliseconds: 300));

      // 一键 FAB 出现（存活株 ≥4）。
      final bool fabShown = await _pumpUntil(
        tester,
        () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
      );
      expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

      Future<void> triggerOneClickWater() async {
        await tester.tap(find.byIcon(Icons.touch_app));
        await _pumpUntil(tester, () => find.text('一键浇水').evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('一键浇水'));
        await _pumpUntil(
            tester, () => find.text('要一键浇水吗？').evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('确定'));
        await _pumpUntil(
            tester, () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty);
      }

      await triggerOneClickWater();
      expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isNotEmpty,
          reason: '一键浇水成功后应显示汇总提示卡');

      // 度量：胶囊中心 = **整屏**中心（真实外壳：底部导航 + AppBar）。
      final Offset pillCenter =
          tester.getCenter(find.byKey(kOneClickBatchHintPillKey));
      final Offset screenCenter =
          Offset(logical.width / 2, logical.height / 2);
      expect((pillCenter.dx - screenCenter.dx).abs(),
          lessThan(kOneClickBatchHintCenterTolerance),
          reason: '真实外壳下提示卡必须整屏水平居中（而非贴底 / 落在导航栏之上）');
      expect((pillCenter.dy - screenCenter.dy).abs(),
          lessThan(kOneClickBatchHintCenterTolerance),
          reason: '真实外壳下提示卡必须整屏垂直居中（真机「在最下面」回归）');

      // 停留 ~1s + 淡出后移除（总 = 120 + 1000 + 300 = 1420ms）。
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isEmpty,
          reason: '提示卡应在约 1.3s 后淡出消失');

      // 再次触发 → 仍只应有一个胶囊（OverlayEntry 不叠加 / 不泄漏）。
      await triggerOneClickWater();
      expect(find.byKey(kOneClickBatchHintPillKey).evaluate().length, 1,
          reason: '多次触发不得叠加多个提示浮层（OverlayEntry 不泄漏）');
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
      expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isEmpty,
          reason: '第二次提示也应自清，不留残影');

      // 排空 A 项（SFX ducking）在花园氛围音在播时挂出的 5s 兜底恢复 Timer，
      // 避免测试结束时出现「Tree disposed 后仍有 pending timer」的假失败
      // （本用例只验提示卡居中/不泄漏，与音频无关）。
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    });
  });
}
