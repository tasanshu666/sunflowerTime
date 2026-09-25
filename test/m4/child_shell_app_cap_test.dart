/// 孩子端外壳 · App 总时长到顶拦截 widget 测试（P0 · A，§6 测试要点）。
///
/// 验收：
///  · **到顶**（seed prefs：当日已用满上限）→ 点花园 / 商店 / 我的**均不切换**
///    且出现分因提示；点今日 / 成长**正常切换**（专注入口永远可用）。
///  · **未到顶**（当日 0 秒）→ 点商店正常切到 index 3（默认行为与改动前一致）。
///
/// 通过 `ProviderScope` 覆盖注入假仓储 + mock prefs，无需真实 DB。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
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
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';

// ── 假仓储（与 nav_structure_test 同款最小实现，返回安全空值）──────────────

const AppSettings _settings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 60,
  dailyAppCapMinutes: 30, // → capSeconds = 1800
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
    String refType,
    String refId,
    DateTime since,
  ) async =>
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
  @override
  Future<void> track(TrackingEvent e) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
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

/// 记录「最后一次 append 金额」的账本 spy：验证调试入口确实写了 +1000。
class _SpySunlightRepository extends _FakeSunlightRepository {
  double? lastGross;

  @override
  Future<double> append(SunlightEntry entry) async {
    lastGross = entry.gross;
    return 1000.0;
  }
}

// ── 装配辅助 ──────────────────────────────────────────────────────────────

Future<SharedPreferences> _mockPrefs({required bool reached}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (reached) kPrefAppUsageDate: dayKey(DateTime.now()),
    if (reached) kPrefAppUsageSeconds: 1800, // = 30 分钟 → 到顶
  });
  return SharedPreferences.getInstance();
}

/// [sunlight] 可传入自定义账本（如「记录 append 金额」的 spy），默认用安全空值 fake。
List<Override> _overrides(SharedPreferences prefs, {SunlightRepository? sunlight}) =>
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider
          .overrideWithValue(sunlight ?? _FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      weeklyPoolRepositoryProvider
          .overrideWithValue(_FakeWeeklyPoolRepository()),
    ];

/// 仅命中底部导航内的 tab 文案（避免与页面正文同名文案冲突）。
Finder _navTab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

int _stackIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShell(WidgetTester tester, SharedPreferences prefs) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(prefs),
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ChildShellPage · App 总时长到顶拦截', () {
    testWidgets('到顶：点花园/商店/我的均不切换 + 出现提示；今日/成长正常切换',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(reached: true);
      await pumpShell(tester, prefs);

      expect(_stackIndex(tester), 0, reason: '初始应停在「今日」');

      for (final String label in <String>['花园', '商店', '我的']) {
        await tester.tap(_navTab(label));
        await tester.pumpAndSettle();

        expect(_stackIndex(tester), 0, reason: '到顶时点「$label」不应切换 tab');
        expect(
          find.textContaining('今天逛 App 的时间用完啦'),
          findsOneWidget,
          reason: '到顶应弹分因提示',
        );

        // 关掉提示框，避免模态遮挡后续点击。
        await tester.tap(find.text('知道啦'));
        await tester.pumpAndSettle();
      }

      // 今日 / 成长 永远可用（专注入口绝不挡）。
      await tester.tap(_navTab('成长'));
      await tester.pumpAndSettle();
      expect(_stackIndex(tester), 1, reason: '成长 tab 应正常切换');

      await tester.tap(_navTab('今日'));
      await tester.pumpAndSettle();
      expect(_stackIndex(tester), 0, reason: '今日 tab 应正常切换');
    });

    testWidgets('未到顶：点商店正常切到 index 3', (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(reached: false);
      await pumpShell(tester, prefs);

      expect(_stackIndex(tester), 0);

      await tester.tap(_navTab('商店'));
      await tester.pumpAndSettle();

      expect(_stackIndex(tester), 3);
      expect(find.textContaining('今天逛 App 的时间用完啦'), findsNothing);
    });

    testWidgets('prefs 是「未来日期」+ 极大秒数 → 视为隔日残留，不误判到顶（QA 补强）',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kPrefAppUsageDate: '2099-01-01', // 未来日期（异常/脏数据）
        kPrefAppUsageSeconds: 999999, // 极大值
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await pumpShell(tester, prefs);

      await tester.tap(_navTab('商店'));
      await tester.pumpAndSettle();

      expect(_stackIndex(tester), 3,
          reason: '未来日期 != 今天 → 当日按 0 秒计 → 娱乐 tab 不应被拦');
      expect(find.textContaining('今天逛 App 的时间用完啦'), findsNothing);
    });

    testWidgets('C 清理回归：调试入口必须受 kDebugMode 约束（release 自动隐藏）',
        (WidgetTester tester) async {
      // ⚠️ widget 测试**恒在 debug 模式**下运行，无法直接断言「release 下不渲染」，
      // 故改为**源码守卫**：断言「DEBUG 加1000阳光」入口确实被 `if (kDebugMode)`
      // 包裹。一旦有人改成裸入口（release 也会渲染 → 提审事故），本用例立刻变红。
      // 玄参 2026-09-24 要求把调试入口**加回**用于调试，故不再断言「查无 DEBUG」。
      final String src = File(
        'lib/presentation/child/pages/child_profile_page.dart',
      ).readAsStringSync();
      expect(src.contains("import 'package:flutter/foundation.dart';"), isTrue,
          reason: 'kDebugMode 来自 foundation.dart');
      expect(
        RegExp(r'if \(kDebugMode\)[\s\S]{0,600}?DEBUG 加1000阳光').hasMatch(src),
        isTrue,
        reason: '调试入口必须写在 if (kDebugMode) 块内，release 才不会渲染',
      );
    });

    testWidgets('dispose 停表：离开外壳后 ticker 必须被取消（P2-2 · 真机路径）',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(reached: false);
      // 手动持有容器：外壳 unmount 后容器仍存活 → `ref.onDispose` 的兜底被排除，
      // 本用例只能靠 ChildShellPage.dispose() 自身的停表逻辑通过；
      // 若 dispose 漏停表，结尾会因「periodic Timer still pending」断言变红（可变异验证）。
      final ProviderContainer container =
          ProviderContainer(overrides: _overrides(prefs));
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChildShellPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 进入娱乐 tab → startCounting（ticker 进入运行态）。
      await tester.tap(_navTab('商店'));
      await tester.pumpAndSettle();

      // 卸载外壳（容器刻意不释放）——模拟 push 进 /entry 独立路由、shell 被 dispose。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      // 用例到此结束：dispose() 若未取消 ticker，flutter_test 收尾的
      // 「A periodic Timer is still pending」断言会让本用例变红。
    });

    testWidgets('调试入口（kDebugMode）：点「DEBUG 加1000阳光」真的入账 1000 ☀',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(reached: false);
      final _SpySunlightRepository ledger = _SpySunlightRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(prefs, sunlight: ledger),
          child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
        ),
      );
      await tester.pumpAndSettle();

      // debug 构建下入口可见（玄参 2026-09-24 要求加回）。
      expect(find.text('DEBUG 加1000阳光'), findsOneWidget);

      await tester.tap(find.text('DEBUG 加1000阳光'));
      await tester.pumpAndSettle();

      expect(ledger.lastGross, 1000.0,
          reason: '调试入口必须真的追加一条 +1000 账本流水（并自增经济修订号）');
      expect(find.text('DEBUG：已加 1000 阳光'), findsOneWidget);
    });
  });
}
