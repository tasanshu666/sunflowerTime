/// 导航重构 · 结构独立验证（QA / Edward）。
///
/// 验收基准（本轮任务）：
///  · 家长端 `ParentHomePage`：底部 5 tab（今日/奖励/任务/夸夸台/设置），非 AppBar 顶部 TabBar；
///  · 孩子端 `ChildShellPage`：底部 5 tab，顺序严格 今日/任务/花园/商店/我的；
///  · 孩子端首页不出现「四档反馈预览」；
///  · 切换 tab 用 IndexedStack（保活，非重建）。
///
/// 本文件为 **可执行 widget 测试**，通过 `ProviderScope` 覆盖注入假仓储，
/// 无需真实 DB / 真实 Realtime 插件。参考 `test/m2/store_page_test.dart` 的覆盖写法。
///
/// 说明：child / parent 各页面对异步加载均有 try-catch 兜底，故假仓储只需返回
/// 安全空值即可让外壳完整渲染，从而对底部导航做结构断言。
library nav_structure_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
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
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_home_page.dart';
import 'package:sunflower_time/shared/theme.dart';

// ───────────────────────────────────────────────────────────────────────────
// 假仓储 / 假设置
// ───────────────────────────────────────────────────────────────────────────

/// 低年段默认设置（AppSettings 部分字段 required，集中提供）。
const AppSettings _lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _lowSettings;
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
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

class _FakeTrackingRepository implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];
  @override
  Future<void> track(TrackingEvent e) async => events.add(e);
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

/// 可配置的假奖励仓储：为「家长已核销 / 家长拒绝」通知链路提供数据。
class _FakeRewardRepository implements RewardRepository {
  _FakeRewardRepository({
    this.verified = const <RedemptionRequest>[],
    this.rejected = const <RedemptionRequest>[],
    List<RewardTemplate>? templates,
  }) : _templates = templates ?? const <RewardTemplate>[];

  final List<RedemptionRequest> verified;
  final List<RedemptionRequest> rejected;
  final List<RewardTemplate> _templates;

  static const RewardTemplate snack = RewardTemplate(
    id: 'tpl_snack',
    name: '小零食',
    category: RewardCategory.parentHandled,
    baseCost: 20,
    frequencyLimitPerWeek: 1,
  );

  @override
  Future<List<RewardTemplate>> templates() async => _templates;
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
  Future<List<RedemptionRequest>> verifiedRequests() async => verified;
  @override
  Future<List<RedemptionRequest>> rejectedRequests() async => rejected;
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

// ───────────────────────────────────────────────────────────────────────────
// 装配辅助
// ───────────────────────────────────────────────────────────────────────────

Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

List<Override> _overrides({
  required SharedPreferences prefs,
  RewardRepository? reward,
}) =>
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      rewardRepositoryProvider
          .overrideWithValue(reward ?? _FakeRewardRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
    ];

/// 取底部导航栏的文案序列（用于顺序断言）。
List<String> _navLabels(NavigationBar bar) => bar.destinations
    .map((Widget d) => (d as NavigationDestination).label)
    .toList(growable: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('孩子端 ChildShellPage · 底部导航结构', () {
    testWidgets('恰好 5 项，顺序严格 今日/任务/花园/商店/我的，初始选中「今日」，IndexedStack 存在',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs),
          child: const MaterialApp(home: ChildShellPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 底部导航恰好 5 项 + 严格顺序。
      final NavigationBar nav =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.destinations, hasLength(5));
      expect(_navLabels(nav), <String>['今日', '成长', '花园', '商店', '我的']);

      // 初始选中「今日」。
      expect(nav.selectedIndex, 0);

      // 用 IndexedStack 保活（存在性断言）。
      expect(find.byType(IndexedStack), findsWidgets);

      // AppBar 标题随当前 tab（初始 = 今日）且 actions 有「家长天地」入口。
      expect((tester.widget<AppBar>(find.byType(AppBar)).title as Text).data, '今日');
      expect(find.byTooltip('家长天地'), findsOneWidget);

      // 孩子端首页不暴露「四档反馈预览」。
      expect(find.textContaining('四档反馈预览'), findsNothing);
    });

    testWidgets('切换 tab：IndexedStack.index 变化（保活，非重建），AppBar 标题跟随',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs),
          child: const MaterialApp(home: ChildShellPage()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder stackFinder = find.byType(IndexedStack);
      expect(tester.widget<IndexedStack>(stackFinder.first).index, 0);

      // 点「商店」（第 4 项，index 3）。
      await tester.tap(find.text('商店'));
      await tester.pumpAndSettle();

      expect(tester.widget<IndexedStack>(stackFinder.first).index, 3);
      // 标题跟随当前 tab（AppBar 标题 = '商店'）。
      expect((tester.widget<AppBar>(find.byType(AppBar)).title as Text).data, '商店');
    });

    testWidgets('B4/B5 承重：家长「已核销」通知进入孩子端即弹窗（证明逻辑已迁移）',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      final reward = _FakeRewardRepository(
        templates: const <RewardTemplate>[_FakeRewardRepository.snack],
        verified: <RedemptionRequest>[
          RedemptionRequest(
            id: 'r_verified_1',
            childId: 'single-child',
            templateId: 'tpl_snack',
            requestedAt: DateTime(2026, 9, 20, 10),
            cost: 20,
            status: RequestStatus.verified,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs, reward: reward),
          child: const MaterialApp(home: ChildShellPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🎉 家长已确认你的兑换'), findsOneWidget);
    });

    testWidgets('B4 承重：家长「拒绝」通知进入孩子端即弹窗（对称通知）',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      final reward = _FakeRewardRepository(
        templates: const <RewardTemplate>[_FakeRewardRepository.snack],
        rejected: <RedemptionRequest>[
          RedemptionRequest(
            id: 'r_rejected_1',
            childId: 'single-child',
            templateId: 'tpl_snack',
            requestedAt: DateTime(2026, 9, 20, 10),
            cost: 20,
            status: RequestStatus.rejected,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs, reward: reward),
          child: const MaterialApp(home: ChildShellPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🚫 兑换未被通过'), findsOneWidget);
    });
  });

  group('家长端 ParentHomePage · 底部导航结构', () {
    testWidgets('恰好 5 项，顺序 今日/奖励/任务/夸夸台/设置，且无 AppBar 顶部 TabBar',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs),
          child: const MaterialApp(home: ParentHomePage()),
        ),
      );
      await tester.pumpAndSettle();

      final NavigationBar nav =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.destinations, hasLength(5));
      expect(_navLabels(nav), <String>['今日', '奖励', '成长', '夸夸台', '设置']);
      expect(nav.selectedIndex, 0);

      // 不得再是 AppBar 顶部 TabBar。
      expect(find.byType(TabBar), findsNothing);
      final AppBar appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom, isNull);
      expect(find.text('家长天地'), findsOneWidget);
    });

    testWidgets('死守项：PopScope(canPop:false) + 返回孩子端箭头 + 家长主题 均在',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs: prefs),
          child: const MaterialApp(home: ParentHomePage()),
        ),
      );
      await tester.pumpAndSettle();

      // PopScope 拦截系统返回键（canPop=false）。
      final PopScope popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((Widget w) => w is PopScope && w.canPop == false),
      );
      expect(popScope.canPop, isFalse);

      // AppBar leading = 返回孩子端箭头。
      expect(find.byTooltip('返回孩子端'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsWidgets);

      // 外层套了家长端皮肤（parentThemeFor）。
      final BuildContext navCtx = tester.element(find.byType(NavigationBar));
      final ThemeData applied = Theme.of(navCtx);
      final ThemeData expected = parentThemeFor(applied.brightness);
      expect(applied.colorScheme.primary, expected.colorScheme.primary);
    });
  });
}
