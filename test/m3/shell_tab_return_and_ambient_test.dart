/// F138 护栏：**退出家长天地回到离开前的 tab** + **花园氛围音不再串页循环**。
///
/// ## 玄参反馈（2026-10-19，真机）
/// 「在花园页面进入家长天地，设置完之后，退出家长天地后，孩子端自动直接到了今日 tab 页，
/// 在今日 tab 页不动，则能听见花园的背景音乐，可循环听见。」
///
/// **根因**（`presentation/child/state/shell_tab.dart` 有完整记录）：
/// 家长天地入口是 `context.go('/parent')` → 整条路由栈被替换 → `ChildShellPage` 销毁重建；
/// 旧的 `childShellTabIndexProvider` 被当成「当前可见 tab」的唯一真源，外壳销毁后**没人
/// 清理**（仍是 2=花园），新外壳 `_index` 初值 0 → `IndexedStack` 把花园页也 build 出来，
/// 花园页读 provider 认为自己「可见」→ `_syncAmbientTimer()` 起播 + 每 30s 补播一次。
///
/// **修法**：把「记忆（tab 索引）」与「可见性（外壳在台前）」拆成两个 provider，
/// 可见性统一判据 = `onStage && tabIndex == 本页下标`；外壳 `initState` 恢复记忆值。
///
/// ## 本文件守的是「接线」（C101-5）
/// 全部用例从**真实入口**进：真实 `ChildShellPage` + 真实 `NavigationBar` 点击 +
/// 真实 `SettlePage` 返回按钮；**只有** T1 的「外壳下台」一步直接改 provider —— 那一处
/// 正是模拟 `context.go('/parent')` 打掉外壳后的语义（外壳无法在测试里自证下台，
/// 真实写入口是 `ChildShellPage.dispose`，由 T4 单独钉住）。
///
/// ⚠️ 花园页有**两个无限动画**（木牌呼吸 + 害虫待机）→ 全程有界 `pump`，
/// **禁止 `pumpAndSettle`**。
///
/// ⚠️ 音频后端：假设置里 `bgmOn=false / soundOn=false`，把 just_audio / path_provider
/// 彻底挡在测试之外 —— 于是 [AudioService] 只走「意图位 + 起播请求计数」这两条纯内存路径，
/// 而这两条**正是本 bug 的判据本体**（花园页每 30s 调一次 `playGardenAmbient` = 无限循环）。
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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';

// ───────────────────────────────────────────────────────────────────────────
// 有界 pump（花园页有无限循环动画 → 绝不能用 pumpAndSettle）
// ───────────────────────────────────────────────────────────────────────────

Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 12,
  int stepMs = 100,
}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(Duration(milliseconds: stepMs));
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 假仓储（与 nav_structure_test 同口径：各页面自带 try-catch 兜底，返回空值即可渲染）
// ───────────────────────────────────────────────────────────────────────────

/// 低年段默认设置。
///
/// 🔴 **`bgmOn` / `soundOn` 刻意关掉**：把真实音频后端（just_audio + path_provider）
/// 完全挡在测试之外，[AudioService] 于是只走「意图位 + 起播请求计数」—— 见文件头注释。
const AppSettings _testSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
  soundOn: false,
  bgmOn: false,
);

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _testSettings;
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
    String refType,
    String refId,
    String dayKey,
  ) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
    String refType,
    String refId,
  ) async =>
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
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

/// 假任务仓储：同时实现 [CheckInAdminRepository]（外壳的通知检查会做能力探测）。
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
  Future<void> decrementCooldown(
    String templateId,
    CooldownPeriod window,
  ) async {}
}

// ───────────────────────────────────────────────────────────────────────────
// 装配
// ───────────────────────────────────────────────────────────────────────────

Future<SharedPreferences> _mockPrefs({
  Map<String, Object> extraPrefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(extraPrefs);
  return SharedPreferences.getInstance();
}

List<Override> _overrides(SharedPreferences prefs) => <Override>[
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
      // 结算页的配音走 `audioServiceProvider`（不碰静态单例）：给一个无播放器的实例。
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null),
      ),
    ];

/// 真实外壳的挂载 / 卸载脚手架（`ProviderScope` 模拟 App 根部，跨路由存活）。
class _ShellHarness {
  _ShellHarness({required this.tester, required this.container});

  final WidgetTester tester;
  final ProviderContainer container;

  static Future<_ShellHarness> create(
    WidgetTester tester, {
    Map<String, Object> extraPrefs = const <String, Object>{},
  }) async {
    final SharedPreferences prefs = await _mockPrefs(extraPrefs: extraPrefs);
    final ProviderContainer container =
        ProviderContainer(overrides: _overrides(prefs));
    addTearDown(container.dispose);
    return _ShellHarness(tester: tester, container: container);
  }

  /// 挂载真实 `ChildShellPage`（与 `app.dart` 的 `ProviderScope → MaterialApp` 同构）。
  Future<void> mountShell() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );
    // `onStage` 由外壳 `initState` **延后一微任务**发布（Riverpod 禁止在生命周期里
    // 直接改 provider）→ 首帧后必须再 pump 一次让它落地。
    await _pumpFrames(tester);
  }

  /// 卸载整个外壳但**保住** [container]（= 家长天地 `go('/parent')` 的真实效果：
  /// 外壳与 5 个 tab 页一起销毁，路由底下的 provider 容器仍在）。
  Future<void> destroyShell() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await _pumpFrames(tester, frames: 4);
  }

  /// 真实点击底部 tab（不用直接改 provider —— 那是 C101-5 明令禁止的「自己传参」）。
  Future<void> tapTab(String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await _pumpFrames(tester);
  }

  int get selectedIndex =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  int get tabIndexMemory => container.read(childShellTabIndexProvider);

  bool get onStage => container.read(childShellOnStageProvider);

  /// 把「外壳下台」摆好（模拟 `context.go('/parent')` 打掉外壳后的语义；
  /// 真实写入口 = `ChildShellPage.dispose`，由「T4」用例单独钉住）。
  void setOnStage(bool value) =>
      container.read(childShellOnStageProvider.notifier).state = value;
}

/// 花盆（虚空）列表：本文件不关心植物内容，只要花园页正常渲染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AudioService audio = AudioService.instance;

  setUp(() {
    // ⚠️ 静态单例跨用例复用，且 `garden_page` 直接调 `AudioService.instance`
    //（`overrideWithValue` 无效）→ 每个用例前必须复位（项目既有口径）。
    audio.resetForTest();
  });

  testWidgets(
      'T1 串页氛围音核心回归：外壳已下台（记忆仍=花园）→ 不播、不补播；重新上台才恢复',
      (WidgetTester tester) async {
    final _ShellHarness h = await _ShellHarness.create(tester);
    await h.mountShell();

    // 真实入口：点底部「花园」。
    await h.tapTab('花园');
    expect(h.selectedIndex, kChildTabIndexOfGarden);
    expect(h.tabIndexMemory, kChildTabIndexOfGarden);
    expect(audio.gardenAmbientPlayCalls, 1,
        reason: '进入花园立即播一次（既有口径）');
    expect(audio.ambientShouldPlay, isTrue);

    // 第二拍：30s 定时补播确实在工作（这是「可循环听见」的机制本体）。
    await tester.pump(
      const Duration(seconds: kGardenAmbientIntervalSeconds),
    );
    await _pumpFrames(tester, frames: 2);
    expect(audio.gardenAmbientPlayCalls, 2,
        reason: '花园可见期间每 30s 补播一次（既有口径，不能被本修复改掉）');

    // ── 外壳下台（家长天地期间：外壳已销毁，tab 记忆仍是 2）────────────────
    h.setOnStage(false);
    await _pumpFrames(tester);
    expect(audio.ambientShouldPlay, isFalse,
        reason: 'F138：外壳不在台前 → 花园页必须立刻判自己「不可见」并停播。'
            '只认 tab 记忆（=2）就是真机「今日 tab 上听见花园音乐」的根因');

    final int frozen = audio.gardenAmbientPlayCalls;
    await tester.pump(
      const Duration(seconds: kGardenAmbientIntervalSeconds * 2),
    );
    await _pumpFrames(tester, frames: 2);
    expect(audio.gardenAmbientPlayCalls, frozen,
        reason: 'F138：不可见期间**不得**有定时补播（真机就是每 30s 无限循环）');

    // ── 外壳重新上台（记忆=花园 → 花园重新可见）→ 氛围音恢复 ────────────────
    h.setOnStage(true);
    await _pumpFrames(tester);
    expect(audio.ambientShouldPlay, isTrue,
        reason: '外壳重新上台且本页确是当前 tab → 氛围音必须恢复');
    expect(audio.gardenAmbientPlayCalls, greaterThan(frozen));
  });

  testWidgets(
      'T2 退出家长天地：重新挂载外壳 → 回到离开前的「花园」tab（不是今日），氛围音恢复',
      (WidgetTester tester) async {
    final _ShellHarness h = await _ShellHarness.create(tester);
    await h.mountShell();

    await h.tapTab('花园');
    expect(h.selectedIndex, kChildTabIndexOfGarden);
    expect(audio.gardenAmbientPlayCalls, 1);

    // ── 进家长天地：`go('/parent')` 把整条路由栈换掉 → 外壳 + 5 个 tab 页全销毁 ──
    await h.destroyShell();
    expect(audio.ambientShouldPlay, isFalse,
        reason: '花园页 dispose 会 stopGardenAmbient（既有行为，本修复不动它）');
    final int frozen = audio.gardenAmbientPlayCalls;
    await tester.pump(
      const Duration(seconds: kGardenAmbientIntervalSeconds * 2),
    );
    expect(audio.gardenAmbientPlayCalls, frozen,
        reason: '外壳已销毁 → 不该有任何补播（没有页面在跑）');

    // ── 退出家长天地：`go('/')` 重建外壳 → 必须回到离开前的 tab ──────────────
    await h.mountShell();
    expect(h.selectedIndex, kChildTabIndexOfGarden,
        reason: 'F138 口径 B（玄参拍板）：退出家长天地回离开前那个 tab，不是重新回今日');
    expect(h.tabIndexMemory, kChildTabIndexOfGarden);
    expect(audio.ambientShouldPlay, isTrue,
        reason: 'F138：回到花园 tab → 氛围音必须正常播放（修复不能把音乐一起修没）');
    expect(audio.gardenAmbientPlayCalls, greaterThan(frozen));

    // 回花园后 30s 补播照旧（口径不变）。
    final int afterRestore = audio.gardenAmbientPlayCalls;
    await tester.pump(
      const Duration(seconds: kGardenAmbientIntervalSeconds),
    );
    await _pumpFrames(tester, frames: 2);
    expect(audio.gardenAmbientPlayCalls, afterRestore + 1);
  });

  testWidgets('T3 结算页返回：记忆是花园也必须落回「今日」（保持既有观感）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // 结算页序列帧是真实位图 → 拦截资产加载（与 settle_*_test 同纪律）。
    const MethodChannel assets = MethodChannel('flutter/assets');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      assets,
      (MethodCall call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(assets, null));

    final SharedPreferences prefs = await _mockPrefs();
    final ProviderContainer container =
        ProviderContainer(overrides: _overrides(prefs));
    addTearDown(container.dispose);

    // 进入结算页之前的真实状态：外壳在台上，孩子在花园（记忆=2）。
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;

    final GoRouter router = GoRouter(
      initialLocation: '/settle',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const ChildShellPage(),
        ),
        GoRoute(
          path: '/settle',
          builder: (BuildContext context, GoRouterState state) =>
              const SettlePage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpFrames(tester, frames: 20, stepMs: 60);

    // 真实入口：结算页底部「回首页」按钮。
    final Finder homeButton = find.widgetWithText(FilledButton, '回首页');
    expect(homeButton, findsOneWidget);
    await tester.ensureVisible(homeButton);
    await _pumpFrames(tester, frames: 4);
    await tester.tap(homeButton);
    await _pumpFrames(tester, frames: 20, stepMs: 60);

    expect(container.read(childShellTabIndexProvider), kChildTabIndexOfToday,
        reason: 'F138 口径 D：结算返回前把 tab 记忆归 0 —— 否则外壳恢复时会落回花园');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      kChildTabIndexOfToday,
      reason: '专注结束回今日（既有观感，不能被「恢复上次 tab」改掉）',
    );
    expect(audio.ambientShouldPlay, isFalse,
        reason: '落在今日 → 花园不可见 → 氛围音不应响（F138 的另一个面）');
  });

  testWidgets('T4 上台/下台信号：真实外壳 initState 置真、dispose 置假',
      (WidgetTester tester) async {
    final _ShellHarness h = await _ShellHarness.create(tester);
    expect(h.onStage, isFalse, reason: '初值 = 没有外壳在屏上');

    await h.mountShell();
    expect(h.onStage, isTrue,
        reason: '外壳 initState 必须发布「在台前」，否则花园页永远不可见 → 音乐再也不响');

    await h.destroyShell();
    expect(h.onStage, isFalse,
        reason: '外壳 dispose 必须发布「下台」（⚠️ 只能走 initState 抓的字段引用 + '
            '延后一微任务 —— dispose 里用 ref 会抛 Bad state）');
  });

  testWidgets('T5 路由直推的花园页（embedded:false）仍恒可见 —— 不被 onStage 误伤',
      (WidgetTester tester) async {
    final SharedPreferences prefs = await _mockPrefs();
    final ProviderContainer container =
        ProviderContainer(overrides: _overrides(prefs));
    addTearDown(container.dispose);
    // 没有任何外壳：索引记忆=今日、外壳不在台前。
    expect(container.read(childShellOnStageProvider), isFalse);
    expect(container.read(childShellTabIndexProvider), kChildTabIndexOfToday);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GardenPage()),
      ),
    );
    await _pumpFrames(tester);

    expect(audio.ambientShouldPlay, isTrue,
        reason: '`/garden` 路由直推形态整屏都是花园，与外壳 tab 无关 → 必须照常起播'
            '（`!widget.embedded` 这一支不能被修复顺手删掉）');
  });

  // ── P1：恢复上次 tab 必须走与「点 tab」同一道防沉迷闸门 ──────────────────────
  //
  // 玄参复核指出的真漏洞：只补 `startCounting()` 不补「能不能进」→
  // 「玩到单次锁定 / 日总量到顶 → 被踢回今日 → 进家长天地转一圈出来 → 直接落回花园」
  // 就是一条稳定的免计时 / 免锁定通道。
  group('P1 恢复上次 tab 不得绕过防沉迷', () {
    testWidgets('已到顶 → 恢复落在「今日」、不起表、给上限卡（不得落回花园）',
        (WidgetTester tester) async {
      final _ShellHarness h = await _ShellHarness.create(
        tester,
        extraPrefs: <String, Object>{
          kPrefAppUsageDate: dayKey(DateTime.now()),
          // 假设置里 dailyAppCapMinutes = 30 → capSeconds = 1800 → 1800 即到顶。
          kPrefAppUsageSeconds: 1800,
          // 拦截用例必须显式关掉「调试跳过限时」（默认 true = 绕过，玄参 2026-09-29）。
          kPrefDebugCapBypass: false,
        },
      );
      // 进家长天地之前：孩子在花园（记忆=2），且到顶状态已落库。
      h.container.read(childShellTabIndexProvider.notifier).state =
          kChildTabIndexOfGarden;

      await h.mountShell();

      expect(h.selectedIndex, kChildTabIndexOfToday,
          reason: 'P1：到顶时恢复路径必须被闸门拦下，落回「今日」而不是花园'
              '（否则「到顶 → 进家长天地 → 出来」就是一条免拦截通道）');
      expect(h.container.read(appUsageControllerProvider).counting, isFalse,
          reason: 'P1：被拦下就**不得**起表');
      expect(find.textContaining('今天逛 App 的时间用完啦'), findsOneWidget,
          reason: 'P1：被拦下要给与点 tab 完全一致的分因提示（不静默）');
      expect(h.tabIndexMemory, kChildTabIndexOfToday,
          reason: '被拦下后孩子实际在「今日」→ tab 记忆必须同步（可见性判据依赖它，'
              '否则花园页会认为「在台前 && 记忆=2」= 可见 → 又在今日上补播背景音）');
      expect(audio.gardenAmbientPlayCalls, 0,
          reason: '花园没上屏 → 不该有任何起播请求（F138 的另一个面）');
    });

    testWidgets('单次锁定中 → 恢复落在「今日」、不起表、给「休息一下」卡',
        (WidgetTester tester) async {
      final _ShellHarness h = await _ShellHarness.create(
        tester,
        extraPrefs: <String, Object>{
          kPrefAppUsageDate: dayKey(DateTime.now()),
          kPrefAppUsageSeconds: 60, // 日总量未到顶
          kPrefAppUsageLockedUntilMs: DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch, // F99 单次锁定中
          kPrefDebugCapBypass: false,
        },
      );
      h.container.read(childShellTabIndexProvider.notifier).state =
          kChildTabIndexOfStore;

      await h.mountShell();

      expect(h.selectedIndex, kChildTabIndexOfToday,
          reason: 'P1：单次锁定中同样不得恢复娱乐 tab');
      expect(h.container.read(appUsageControllerProvider).counting, isFalse);
      expect(h.tabIndexMemory, kChildTabIndexOfToday,
          reason: '被拦下后 tab 记忆必须同步成今日（同「已到顶」用例的理由）');
      expect(find.text('休息一下，等会再来玩'), findsOneWidget,
          reason: 'P1：单次锁定给「休息一下」卡（与点 tab 同一条路径、同一份文案）');
    });

    testWidgets('未到顶（正向对照）→ 恢复成功落回花园并起表（修复不能把恢复一起挡死）',
        (WidgetTester tester) async {
      final _ShellHarness h = await _ShellHarness.create(
        tester,
        extraPrefs: <String, Object>{
          // 0 秒、未锁定；仍然关掉 debug 绕过，确保走的是真实闸门判定。
          kPrefDebugCapBypass: false,
        },
      );
      h.container.read(childShellTabIndexProvider.notifier).state =
          kChildTabIndexOfGarden;

      await h.mountShell();

      expect(h.selectedIndex, kChildTabIndexOfGarden,
          reason: '未到顶 → 闸门放行 → 必须回上次那个 tab（口径 B 与 P1 同时成立）');
      expect(h.container.read(appUsageControllerProvider).counting, isTrue,
          reason: '放行后必须起表（否则恢复路径又成了免计时通道的另一半）');
      expect(find.textContaining('今天逛 App 的时间用完啦'), findsNothing);
      expect(audio.ambientShouldPlay, isTrue);
    });
  });
}
