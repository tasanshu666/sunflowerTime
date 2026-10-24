/// C90 期 2 护栏：家长端 `ParentHomePage` 的 5 tab 按 `childProfileRevisionProvider`
/// 修订号**整组重挂载**（IndexedStack 子树 key 全换 → 各页全量重读当前孩子数据）。
///
/// 口径（玄参 2026-10-17 拍板）：切孩子低频，丢滚动位 / 输入态可接受，换来五个
/// 页面数据源一次换净；不做逐页 listenManual 改造。日常切 tab（修订号不变）
/// 仍是原样保活（key 不变 → State 保留）。
///
/// 脚手架参照 `test/nav/nav_structure_test.dart`：假仓储 + mock SP，无平台通道。
library parent_home_remount_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_home_page.dart';

/// 有界 pump（同 nav_structure_test：悬浮气泡 / 呼吸动画 pumpAndSettle 不收敛）。
Future<void> _pumpFrames(WidgetTester tester,
    {int frames = 8, int stepMs = 100}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

const AppSettings _settings = AppSettings(
  ageTier: AgeTier.high,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 0;
  @override
  Future<double> balance() async => 0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
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
      totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

class _FakeTaskRepository implements TaskRepository, CheckInAdminRepository {
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

  // C91：记录段新增「修订号自增 → 重拉」后，修订号 bump 会让
  // HistoryActivitySection 走 TaskCheckInService.verifiedCheckIns() —— 该服务
  // 强制要求仓储实现 CheckInAdminRepository（家长端核销能力）。本假仓储按
  // C91 测试同款空实现补齐（空态，不影响本测试的重挂载断言）。
  @override
  Future<CheckIn?> checkInById(String id) async => null;
  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async =>
      <CheckIn>[];
  @override
  Future<void> updateCheckIn(CheckIn checkIn) async {}
  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async =>
      false;
}

class _FakePlantRepository implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent event) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
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
  List<String> weeksBetween(String fromKey, String toKey) => <String>[];
}

class _FakeRewardRepository implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => <RewardTemplate>[];
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest request) async {}
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
  Future<void> updateRequest(RedemptionRequest request) async {}
  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;
  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

Future<ProviderContainer> _mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ParentHomePage()),
    ),
  );
  await _pumpFrames(tester);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('C90 期 2：修订号变化 → IndexedStack 五个 tab 的 key 整组更换（重挂载）',
      (WidgetTester tester) async {
    final ProviderContainer container = await _mount(tester);

    // 初始 revision = 0：五个 c90-child-0-* key。
    // ⚠️ IndexedStack 非选中 tab 处于 Offstage → 查找必须 skipOffstage: false。
    expect(find.byKey(const ValueKey<String>('c90-child-0-today'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-0-settings'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-1-today'), skipOffstage: false),
        findsNothing);

    // 模拟家长端切换 / 新建 / 编辑 / 删除孩子成功（修订号自增）。
    container.read(childProfileRevisionProvider.notifier).state++;
    await _pumpFrames(tester);

    // 旧 key 全部消失、新 key 全部就位 → 五个页面 State 全量重建。
    expect(find.byKey(const ValueKey<String>('c90-child-0-today'), skipOffstage: false),
        findsNothing, reason: '旧孩子的 tab State 必须被卸载（防上个孩子的快照）');
    expect(find.byKey(const ValueKey<String>('c90-child-0-settings'), skipOffstage: false),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('c90-child-1-today'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-1-reward'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-1-task'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-1-history'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('c90-child-1-settings'), skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('日常切 tab（修订号不变）→ key 不变，保活不重挂载',
      (WidgetTester tester) async {
    await _mount(tester);

    // 点底栏切到「设置」tab。
    await tester.tap(find.text('设置').last);
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey<String>('c90-child-0-today'), skipOffstage: false),
        findsOneWidget, reason: '修订号没变 → 五个 tab State 仍保活（IndexedStack 原语义）');
  });
}
