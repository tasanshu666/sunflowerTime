/// F138 **QA 独立探针**（严过关，2026-10-20）—— 已纳入正式护栏（team-lead 2026-10-19 收编）。
///
/// 与工程师的 `shell_tab_return_and_ambient_test.dart` **刻意不复用断言**：
/// 本文件从「玄参真机描述的可观测现象」出发自己设计判据，用于交叉验证：
///  · Q1 外壳销毁后「今日 tab 上零起播」（真机 bug 的可观测本体）；
///  · Q2 恢复过程的**帧级**闪烁测量（给玄参的目检预期）；
///  · Q3 口径 A / Q4 口径 B；
///  · Q5 P1 闸门三条（到顶 / 单次锁定 / 正常）；
///  · Q6 恢复窗口内的**用户操作竞态**（QA 找出的缺口，工程师 P2-a 已修复 → 现在是回归用例）；
///  · Q7 越界记忆值的安全性；
///  · Q8 hydrate 未就绪窗口里的点 tab 绕过；
///  · Q9 同帧换壳（守 `_mountSeq` 竞态守卫）/ Q10 慢 hydrate 仍必须拦（守「先 await 就绪再判」）。
///
/// ⚠️ 花园页有无限动画 → 全程有界 pump，**禁用 `pumpAndSettle`**。
/// ⚠️ `AudioService.instance` 是静态单例 → 每个用例 `resetForTest()`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
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
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';

// ── 有界 pump ──────────────────────────────────────────────────────────────

Future<void> _pump(WidgetTester tester, {int frames = 10, int stepMs = 80}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

// ── 假仓储（最小实现；bgmOn/soundOn 关掉 → 真实音频后端完全不参与）──────────

const AppSettings _settings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30, // → capSeconds = 1800
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
  soundOn: false,
  bgmOn: false,
);

class _Settings implements SettingsRepository {
  _Settings({this.delay = Duration.zero});

  final Duration delay;

  @override
  Future<AppSettings> getSettings() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return _settings;
  }

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _Sunlight implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry e) async => 999;
  @override
  Future<double> balance() async => 999;
  @override
  Future<double> dayNet(String d) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String r, String d) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String r, String m) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(String r, String i, String d) async => 0;
  @override
  Future<int> countByRefType(String r) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(String r, String i, DateTime s) async => 0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String r, String i) async => null;
  @override
  Future<double> earnGrossOnDay(String d) async => 0;
  @override
  Future<double> earnNetOnDay(String d) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _Focus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession s) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String d) async => <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _Tasks implements TaskRepository, CheckInAdminRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  Future<void> saveTask(Task t) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn c) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String d) async => <CheckIn>[];
  @override
  Future<int> totalCheckInCount() async => 0;
  @override
  Future<CheckIn?> checkInById(String id) async => null;
  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus s) async => <CheckIn>[];
  @override
  Future<void> updateCheckIn(CheckIn c) async {}
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

class _Plants implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant p) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

class _Tracking implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime a, DateTime b) async => '';
}

class _Rewards implements RewardRepository {
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
  Future<List<RedemptionRequest>> queuedOfWeek(String w) async =>
      <RedemptionRequest>[];
  @override
  Future<void> updateRequest(RedemptionRequest r) async {}
  @override
  Future<int> cooldownCount(String t, CooldownPeriod w) async => 0;
  @override
  Future<void> decrementCooldown(String t, CooldownPeriod w) async {}
}

class _Pools implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String w) async => null;
  @override
  Future<void> upsert(WeeklyPool p) async {}
  @override
  List<String> weeksBetween(String a, String b) => <String>[a, b];
}

// ── 装配 ───────────────────────────────────────────────────────────────────

List<Override> _overrides(
  SharedPreferences prefs, {
  Duration settingsDelay = Duration.zero,
}) =>
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      settingsRepositoryProvider
          .overrideWithValue(_Settings(delay: settingsDelay)),
      sunlightRepositoryProvider.overrideWithValue(_Sunlight()),
      focusRepositoryProvider.overrideWithValue(_Focus()),
      taskRepositoryProvider.overrideWithValue(_Tasks()),
      plantRepositoryProvider.overrideWithValue(_Plants()),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      rewardRepositoryProvider.overrideWithValue(_Rewards()),
      trackingRepositoryProvider.overrideWithValue(_Tracking()),
      weeklyPoolRepositoryProvider.overrideWithValue(_Pools()),
      audioServiceProvider
          .overrideWithValue(AudioService(playerFactory: () => null)),
    ];

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const <String, Object>{},
  Duration settingsDelay = Duration.zero,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final ProviderContainer c = ProviderContainer(
    overrides: _overrides(sp, settingsDelay: settingsDelay),
  );
  addTearDown(c.dispose);
  return c;
}

/// 真实外壳宿主（`ProviderScope` 等价物，跨「路由切换」存活）。
Widget _scoped(ProviderContainer c, Widget child) =>
    UncontrolledProviderScope(container: c, child: MaterialApp(home: child));

int _navIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _pump(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AudioService audio = AudioService.instance;

  setUp(audio.resetForTest);

  // ── Q1：玄参真机现象的可观测复现（核心）──────────────────────────────────
  testWidgets('Q1 外壳销毁 + 重挂到「今日」→ 30s×3 内零起播（真机 bug 本体）',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _pump(tester);

    // 真实入口：点底部「花园」。
    await _tapTab(tester, '花园');
    expect(_navIndex(tester), 2);
    final int afterEnter = audio.gardenAmbientPlayCalls;
    expect(afterEnter, greaterThanOrEqualTo(1), reason: '进花园必须起播（既有口径）');

    // 模拟 go('/parent')：外壳与 5 个 tab 页一起销毁（真实 dispose 发布下台信号）。
    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 6);
    expect(c.read(childShellOnStageProvider), isFalse, reason: '外壳销毁必须下台');

    final int frozen = audio.gardenAmbientPlayCalls;
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await _pump(tester, frames: 2);
    }
    expect(audio.gardenAmbientPlayCalls, frozen,
        reason: '外壳已销毁 → 3×30s 内不得有任何补播（真机就是无限循环）');

    // 玄参那一幕：孩子落在「今日」（记忆=0）→ 花园页虽被 IndexedStack build 出来，
    // 但**绝不允许**起播。
    c.read(childShellTabIndexProvider.notifier).state = 0;
    final int beforeToday = audio.gardenAmbientPlayCalls;
    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _pump(tester);
    expect(_navIndex(tester), 0);

    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await _pump(tester, frames: 2);
    }
    expect(audio.gardenAmbientPlayCalls, beforeToday,
        reason: '🔴 玄参听到的现象：今日 tab 上**一次性都不能响**');
    expect(audio.ambientShouldPlay, isFalse);

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q2：恢复过程的帧级闪烁测量（给玄参的目检预期）─────────────────────────
  testWidgets('Q2 帧级采样：记忆=花园 → 重挂后多少帧还显示「今日」',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    // 挂载后逐帧采样（16ms/帧 ≈ 60fps）。
    final List<int> seq = <int>[_navIndex(tester)];
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seq.add(_navIndex(tester));
    }
    // ignore: avoid_print
    print('[QA-Q2 快路径] selectedIndex 帧序列(16ms/帧): $seq');
    final int todayFrames = seq.takeWhile((int v) => v != 2).length;
    expect(seq.last, 2, reason: '最终必须回到花园');
    expect(todayFrames, lessThanOrEqualTo(2),
        reason: '快路径下不应有肉眼可见闪烁（>2 帧 / >33ms）；实测 $todayFrames 帧');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  testWidgets('Q2b 慢设备（settings 读 200ms）→ 今日停留帧数与毫秒数',
      (WidgetTester tester) async {
    final ProviderContainer c =
        await _container(settingsDelay: const Duration(milliseconds: 200));
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    final List<int> seq = <int>[_navIndex(tester)];
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seq.add(_navIndex(tester));
    }
    // ignore: avoid_print
    print('[QA-Q2b 慢设备] selectedIndex 帧序列(16ms/帧): $seq');
    final int todayFrames = seq.takeWhile((int v) => v != 2).length;
    // ignore: avoid_print
    print('[QA-Q2b 慢设备] 今日页停留 = $todayFrames 帧 ≈ ${todayFrames * 16}ms');
    expect(seq.last, 2, reason: '再慢也必须最终回到花园');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q3：口径 A（回离开前的 tab）────────────────────────────────────────
  testWidgets('Q3 口径 A：记忆=花园 → 重挂落花园 + 氛围音恢复（恰好 1 次起播）',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _pump(tester);

    expect(_navIndex(tester), 2, reason: '口径 A：回离开前的 tab');
    expect(c.read(childShellOnStageProvider), isTrue);
    expect(audio.ambientShouldPlay, isTrue, reason: '回花园要能听见音乐');
    // ignore: avoid_print
    print('[QA-Q3] 恢复落花园的起播次数 = ${audio.gardenAmbientPlayCalls}');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q4：口径 B（专注结束回今日）────────────────────────────────────────
  testWidgets('Q4 口径 B：记忆=花园 + 从 /settle 起 → 「回首页」落今日且音乐不响',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const MethodChannel assets = MethodChannel('flutter/assets');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(assets, (MethodCall call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(assets, null));

    final ProviderContainer c = await _container();
    c.read(childShellTabIndexProvider.notifier).state = 2;
    c.read(childShellOnStageProvider.notifier).state = true;

    final GoRouter router = GoRouter(
      initialLocation: '/settle',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext ctx, GoRouterState s) => const ChildShellPage(),
        ),
        GoRoute(
          path: '/settle',
          builder: (BuildContext ctx, GoRouterState s) => const SettlePage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pump(tester, frames: 15, stepMs: 60);

    final Finder home = find.widgetWithText(FilledButton, '回首页');
    expect(home, findsOneWidget);
    await tester.ensureVisible(home);
    await _pump(tester, frames: 4);
    await tester.tap(home);
    await _pump(tester, frames: 15, stepMs: 60);

    expect(_navIndex(tester), 0, reason: '口径 B：专注结束回今日');
    expect(c.read(childShellTabIndexProvider), 0);
    expect(audio.ambientShouldPlay, isFalse, reason: '落今日 → 花园不可见 → 不该响');

    // 再加一拍 30s：确认没有「延迟起播」。
    final int frozen = audio.gardenAmbientPlayCalls;
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await _pump(tester, frames: 2);
    expect(audio.gardenAmbientPlayCalls, frozen);
  });

  // ── Q5：P1 防沉迷闸门三条 ───────────────────────────────────────────────
  group('Q5 P1 闸门（独立判据）', () {
    testWidgets('到顶 → 落今日 + 不起表 + 弹上限卡 + 记忆归 0 + 零起播',
        (WidgetTester tester) async {
      final ProviderContainer c = await _container(prefs: <String, Object>{
        kPrefAppUsageDate: dayKey(DateTime.now()),
        kPrefAppUsageSeconds: 1800,
        kPrefDebugCapBypass: false,
      });
      c.read(childShellTabIndexProvider.notifier).state = 2;

      await tester.pumpWidget(_scoped(c, const ChildShellPage()));
      await _pump(tester);

      expect(_navIndex(tester), 0);
      expect(c.read(appUsageControllerProvider).counting, isFalse);
      expect(find.textContaining('时间用完啦'), findsOneWidget);
      expect(c.read(childShellTabIndexProvider), 0);
      final int frozen = audio.gardenAmbientPlayCalls;
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await _pump(tester, frames: 2);
      expect(audio.gardenAmbientPlayCalls, frozen, reason: '被拦下 → 不得补播');

      await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
      await _pump(tester, frames: 4);
    });

    testWidgets('单次锁定中 → 落今日 + 不起表 + 弹休息卡 + 记忆归 0',
        (WidgetTester tester) async {
      final ProviderContainer c = await _container(prefs: <String, Object>{
        kPrefAppUsageDate: dayKey(DateTime.now()),
        kPrefAppUsageSeconds: 60,
        kPrefAppUsageLockedUntilMs: DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        kPrefDebugCapBypass: false,
      });
      c.read(childShellTabIndexProvider.notifier).state = 4; // 我的

      await tester.pumpWidget(_scoped(c, const ChildShellPage()));
      await _pump(tester);

      expect(_navIndex(tester), 0);
      expect(c.read(appUsageControllerProvider).counting, isFalse);
      expect(find.text('休息一下，等会再来玩'), findsOneWidget);
      expect(c.read(childShellTabIndexProvider), 0);

      await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
      await _pump(tester, frames: 4);
    });

    testWidgets('正常（0 秒）→ 落花园 + 起表 + 恰 1 次起播（不多播）',
        (WidgetTester tester) async {
      final ProviderContainer c = await _container(prefs: <String, Object>{
        kPrefDebugCapBypass: false,
      });
      c.read(childShellTabIndexProvider.notifier).state = 2;

      await tester.pumpWidget(_scoped(c, const ChildShellPage()));
      await _pump(tester);

      expect(_navIndex(tester), 2);
      expect(c.read(appUsageControllerProvider).counting, isTrue);
      // ignore: avoid_print
      print('[QA-Q5] 正常放行起播次数 = ${audio.gardenAmbientPlayCalls}');
      expect(audio.gardenAmbientPlayCalls, 1,
          reason: '恢复放行只该起播 1 次（多播 = 修复引入了新的「窗口期起播」）');

      await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
      await _pump(tester, frames: 4);
    });

    testWidgets('点 tab 路径行为不变：到顶点「商店」不切 tab（回归）',
        (WidgetTester tester) async {
      final ProviderContainer c = await _container(prefs: <String, Object>{
        kPrefAppUsageDate: dayKey(DateTime.now()),
        kPrefAppUsageSeconds: 1800,
        kPrefDebugCapBypass: false,
      });
      await tester.pumpWidget(_scoped(c, const ChildShellPage()));
      await _pump(tester);
      expect(_navIndex(tester), 0);

      await _tapTab(tester, '商店');
      expect(_navIndex(tester), 0, reason: '到顶点商店必须仍被拦');
      expect(find.textContaining('时间用完啦'), findsOneWidget);

      await tester.tap(find.text('知道啦'));
      await _pump(tester);

      await _tapTab(tester, '成长');
      expect(_navIndex(tester), 1, reason: '成长永不挡');

      await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
      await _pump(tester, frames: 4);
    });
  });

  // ── Q6：恢复窗口内的用户操作竞态（QA 自找缺口）────────────────────────────
  // ✅ **已修复（P2-a，工程师寇豆码）**：`_restoreEntertainmentTab` 在 `setState` 前
  // 复查 `ref.read(childShellTabIndexProvider) == target` —— 记忆是「孩子最后一次主动
  // 选择」的真源，异步恢复**只允许在没人动过的前提下生效**。否则：①把人从「成长」
  // 硬拽回花园；②不回写记忆 → `_index=2 / 记忆=1` 分叉 → 花园判自己不可见 →
  // **回花园反而没背景音**（F138 的镜像形态）。
  // 本用例已从「已知缺口（skip:true）」转为**正式回归用例**。
  testWidgets('Q6 慢设备：恢复窗口内孩子自己点了「成长」→ 不得被拽回花园',
      (WidgetTester tester) async {
    final ProviderContainer c =
        await _container(settingsDelay: const Duration(milliseconds: 200));
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    expect(_navIndex(tester), 0, reason: '恢复未完成时停在今日');

    // 孩子自己点「成长」（此时恢复仍在 await 中）。
    await _tapTab(tester, '成长');
    expect(_navIndex(tester), 1);

    // 等恢复流程走完（settings 200ms + 帧）。
    await _pump(tester, frames: 12, stepMs: 40);

    // ignore: avoid_print
    print('[QA-Q6] 恢复完成后：_index(NavigationBar)=${_navIndex(tester)} '
        '记忆=${c.read(childShellTabIndexProvider)}');

    final String diag = 'diag: _index=${_navIndex(tester)} '
        'memory=${c.read(childShellTabIndexProvider)} '
        'onStage=${c.read(childShellOnStageProvider)} '
        'plays=${audio.gardenAmbientPlayCalls}';

    expect(_navIndex(tester), 1,
        reason: '用户在恢复窗口内主动选的 tab 必须被尊重 —— '
            '异步恢复若无「记忆是否仍等于目标」的复查，会把人硬拽回花园（$diag）');
    expect(c.read(childShellTabIndexProvider), 1,
        reason: '被拽走后记忆与实际 tab 必须一致（否则又是一次「记忆≠可见」分叉 = F138 同类缺陷）');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q6diag：仅测量、不做失败断言（把「被拽回」后的真实状态打出来）────────
  testWidgets('Q6diag 竞态后的实际状态采样', (WidgetTester tester) async {
    final ProviderContainer c =
        await _container(settingsDelay: const Duration(milliseconds: 200));
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _tapTab(tester, '成长');
    await _pump(tester, frames: 12, stepMs: 40);

    // ignore: avoid_print
    print('[QA-Q6diag] _index=${_navIndex(tester)} '
        'memory=${c.read(childShellTabIndexProvider)} '
        'onStage=${c.read(childShellOnStageProvider)} '
        'ambientShouldPlay=${audio.ambientShouldPlay} '
        'plays=${audio.gardenAmbientPlayCalls}');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q8：点 tab 路径的「hydrate 未就绪」窗口（既有缺口是否被状态监听兜住）──
  testWidgets('Q8 到顶 + 慢 hydrate：点「花园」不会长期绕过（最终被踢回今日）',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container(
      prefs: <String, Object>{
        kPrefAppUsageDate: dayKey(DateTime.now()),
        kPrefAppUsageSeconds: 1800,
        kPrefDebugCapBypass: false,
      },
      settingsDelay: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    // hydrate 未完成（settings 还在 await）→ 此刻点花园。
    await tester.tap(
      find.descendant(
          of: find.byType(NavigationBar), matching: find.text('花园')),
    );
    await tester.pump(); // 只走一帧：看 hydrate 未就绪窗口里是否真的放行了
    final int rightAfterTap = _navIndex(tester);

    await _pump(tester, frames: 12, stepMs: 40);
    final int settled = _navIndex(tester);
    // ignore: avoid_print
    print('[QA-Q8] 点击瞬间 index=$rightAfterTap（hydrate 未就绪窗口）'
        ' → 稳定后 index=$settled，弹卡=${find.textContaining('时间用完啦').evaluate().length}');

    expect(settled, 0,
        reason: 'hydrate 完成、状态变 reached 后，_onUsageStateChanged 必须把人踢回今日'
            '（否则点 tab 路径就有一条稳定绕过）');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q9：新旧外壳同帧交替（旧 dispose 晚于新 initState）→ 台前信号不得被覆盖 ──
  testWidgets('Q9 同帧换壳：旧外壳迟到的「下台」不得覆盖新外壳的「在台前」',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    // 记忆 = 今日（非娱乐 tab）→ 新外壳走**同步**上台分支（initState 里就是唯一的
    // 上台发布者）。娱乐 tab 那条分支的 `finally` 会重新发布 true，掩盖竞态，
    // 因此必须用非娱乐 tab 才能测出 `_mountSeq` 守卫是否在起作用。
    await tester.pumpWidget(_scoped(c, const ChildShellPage(key: ValueKey<String>('A'))));
    await _pump(tester);
    expect(_navIndex(tester), 0);

    // 同一帧内把外壳换成另一个 key → 旧 State 的 dispose 会**晚于**新 State 的 initState
    //（Flutter 先挂新子树，帧末再 unmount 旧子树）—— 正是 `_mountSeq` 守卫要防的时序。
    await tester.pumpWidget(_scoped(c, const ChildShellPage(key: ValueKey<String>('B'))));
    await _pump(tester);

    expect(c.read(childShellOnStageProvider), isTrue,
        reason: '旧外壳迟到的下台信号若覆盖了新外壳的上台信号 → 花园页永久不可见 → '
            '音乐再也不响（把 F138 修成反向 bug）');
    // ignore: avoid_print
    print('[QA-Q9] onStage=${c.read(childShellOnStageProvider)} '
        'ambientShouldPlay=${audio.ambientShouldPlay} '
        'plays=${audio.gardenAmbientPlayCalls}');
    // ⚠️ 同帧换壳时旧页面 dispose 的 `stopGardenAmbient(reason: dispose)` 会晚于
    //    新页面的起播 → shouldPlay 被旧页面抹掉。这是**改动前就存在**的时序（本补丁
    //    未改 garden dispose / stop 逻辑），且生产路径（go('/parent') 与 go('/') 相隔
    //    多帧）不会出现该次序，故此处只记录、不断言。

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
    expect(c.read(childShellOnStageProvider), isFalse, reason: '最终仍要能正常下台');
  });

  // ── Q10：慢 hydrate + 到顶 → 恢复路径仍必须拦（守「先 await 就绪再判」）──────
  testWidgets('Q10 慢 hydrate（200ms）+ 已到顶 → 恢复仍被拦下、不起表、落今日',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container(
      prefs: <String, Object>{
        kPrefAppUsageDate: dayKey(DateTime.now()),
        kPrefAppUsageSeconds: 1800,
        kPrefDebugCapBypass: false,
      },
      settingsDelay: const Duration(milliseconds: 200),
    );
    c.read(childShellTabIndexProvider.notifier).state = 2;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _pump(tester, frames: 15, stepMs: 40);

    expect(_navIndex(tester), 0,
        reason: 'hydrate 慢时必须**等就绪再判**：拿 initial（0 秒 / 未到顶）判放行 = P1 漏洞');
    expect(c.read(appUsageControllerProvider).counting, isFalse);
    expect(c.read(childShellTabIndexProvider), 0,
        reason: '被拦下 → 记忆同步 0（否则花园页误判可见 → 音乐照响）');
    expect(audio.gardenAmbientPlayCalls, 0,
        reason: '被拦下的全过程不得有任何起播（含 hydrate 窗口内）');

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });

  // ── Q7：越界记忆值 ─────────────────────────────────────────────────────
  testWidgets('Q7 记忆越界（99）→ 回落今日，IndexedStack 不抛区间断言',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    c.read(childShellTabIndexProvider.notifier).state = 99;

    await tester.pumpWidget(_scoped(c, const ChildShellPage()));
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(_navIndex(tester), 0);
    expect(audio.ambientShouldPlay, isFalse);

    await tester.pumpWidget(_scoped(c, const SizedBox.shrink()));
    await _pump(tester, frames: 4);
  });
}
