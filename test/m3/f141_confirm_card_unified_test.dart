/// F141 · 「孩子端裸弹窗全面收口」守卫 + `GoldNoticeDialog` 宽度收敛验收。
///
/// ## 本批改了什么（6 处裸 `AlertDialog` → 两个统一卡壳）
/// | # | 位置 | 改成 |
/// |---|------|------|
/// | ① | `focus_page.dart` 专注退出确认 | `showChildConfirmCard`（barrier 不可关） |
/// | ② | `child_shell_page.dart` 兑换未通过通知 | `showGoldNoticeDialog(tone: warn)` |
/// | ③ | `child_task_page.dart` 完美日庆祝 | `showGoldNoticeDialog`（「太棒啦」） |
/// | ④ | `eye_care_page.dart` 护眼提前结束确认 | `showChildConfirmCard`（barrier 不可关） |
/// | ⑤ | `focus_level_badge.dart` 等级锁标提示 | `showGoldNoticeDialog`（无标题） |
/// | ⑥ | `premium_gate.dart` 付费引导 | `showChildConfirmCard` |
///
/// ## 本文件钉住的四类契约
/// 1. **源码守卫**：`lib/presentation/child/**` + `lib/presentation/shared/premium_gate.dart`
///    内 `AlertDialog(` **零命中** —— 再有人写回裸弹窗，本条立刻变红。
///    ⚠️ 用 `File.readAsStringSync()` 而非 shell grep（本机 bash grep 中文/编码不稳）。
/// 2. **逐处行为**：每处都走**真实入口**（真页面 / 真弹窗路由），断言卡片在场、
///    文案逐字、按钮逐字、以及「点完会发生什么」与改前一致。
/// 3. **金色通知卡宽度**（玄参本轮核心诉求）：手机 390 实测 **310**（逐像素零回归）、
///    iPad 13″ 1032 实测 **544 ≤ 544 且 < 952**（改前值）。
/// 4. **`barrierDismissible` 语义**：①④ 点卡外后卡片**仍在场**（原语义保留）。
///
/// ⚠️ 测试纪律（项目铁律）：结算 / 护眼 / 花园页有**无限动画** →
/// 禁 `pumpAndSettle`，一律有界 `pump(Duration)`；序列帧素材真解码会 OOM →
/// 拦 `flutter/assets` 通道（本文件 `_useScreen` 已统一处理）。
library f141_confirm_card_unified_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart'
    show EyeCareResultType;
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

// ─────────────────────────── 项目根 / 源码守卫 ───────────────────────────

/// 项目根（`flutter test` 的 cwd 是项目根；在 IDE 里可能是 `test/m3`）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/m3') || cwd.endsWith('\\test\\m3')
      ? Directory.current.parent.parent.path
      : cwd;
}

/// 递归列出 [dir] 下的所有 `.dart` 文件（相对路径，已统一 `/`）。
List<File> _dartFiles(Directory dir) {
  if (!dir.existsSync()) return <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();
}

// ─────────────────────────── 通用假仓储 ───────────────────────────

/// 只记录 `append` 的假账本（防真库触库）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this.startBalance);

  final double startBalance;
  final List<SunlightEntry> appended = <SunlightEntry>[];

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(appended);
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  @override
  Future<double> balance() async => startBalance;

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry);
    return startBalance + entry.net;
  }

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

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
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 假护眼记录仓储：护眼卡退场会写一行，测试环境无真实数据库，只防崩。
class _FakeEyeCareLogRepository implements EyeCareLogRepository {
  final List<EyeCareLog> appended = <EyeCareLog>[];

  @override
  Future<void> append(EyeCareLog log) async => appended.add(log);

  @override
  Future<int> countByResult(EyeCareResultType type) async =>
      appended.where((EyeCareLog l) => l.result == type).length;

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) async => appended
      .where((EyeCareLog l) => l.result == type)
      .fold<int>(0, (int sum, EyeCareLog l) => sum + l.watchedSeconds);
}

/// 假专注会话仓储：`SunlightService.settle` 结算时会 saveSession（防真库触库）。
class _FakeFocusRepository implements FocusRepository {
  final List<FocusSession> saved = <FocusSession>[];

  @override
  Future<void> saveSession(FocusSession session) async => saved.add(session);

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

/// 假埋点仓储：只记账不落库。
class _FakeTrackingRepository implements TrackingRepository {
  final List<TrackingEvent> tracked = <TrackingEvent>[];

  @override
  Future<void> track(TrackingEvent event) async => tracked.add(event);

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      <TrackingEvent>[];

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

/// 内存任务仓储（③ 完美日入口用：1 条非联动日任务，打完即「全部完成」）。
class _MemTaskRepository implements TaskRepository {
  _MemTaskRepository(this._tasks);

  final List<Task> _tasks;
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasks() async => List<Task>.of(_tasks);

  @override
  Future<void> saveTask(Task task) async {}

  @override
  Future<void> deleteTaskById(String id) async {}

  @override
  Future<void> checkIn(CheckIn c) async => checkIns.add(c);

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => checkIns
      .where((CheckIn c) => _dayKey(c.date) == dayKey)
      .toList();

  @override
  Future<int> totalCheckInCount() async => checkIns.length;

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// ⚠️ 故意**不过滤**的假兑换仓储（② 用：孩子端外壳必须自己按 childId 拦）。
class _RejectOnlyRewardRepository implements RewardRepository {
  _RejectOnlyRewardRepository(this.rejected);

  final List<RedemptionRequest> rejected;

  @override
  Future<List<RewardTemplate>> templates() async =>
      const <RewardTemplate>[_kRewardTpl];

  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];

  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      List<RedemptionRequest>.of(rejected);

  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];

  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];

  @override
  Future<void> createRequest(RedemptionRequest request) async {}

  @override
  Future<void> updateRequest(RedemptionRequest request) async {}

  @override
  Future<void> saveTemplate(RewardTemplate t) async {}

  @override
  Future<void> deleteTemplate(String id) async {}

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;

  @override
  Future<void> decrementCooldown(
      String templateId, CooldownPeriod window) async {}
}

const RewardTemplate _kRewardTpl = RewardTemplate(
  id: 'tpl_x',
  name: '小零食',
  category: RewardCategory.parentHandled,
  contentCategory: RewardContentCategory.snacks,
  baseCost: 10,
  frequencyLimitPerWeek: 7,
  cooldownRule: CooldownRule.none,
);

/// 设置默认值（护眼三项取实体默认：开 / 20 分钟 / 允许跳过）。
AppSettings _defaultSettings() => const AppSettings(
      ageTier: AgeTier.high,
      dailyFocusCap: 60,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 400,
      eyeCareSkipAllowed: true,
    );

/// 挂真 `ChildShellPage`（内存 Drift + mock SP + 真 AccountService），
/// 用假兑换仓储喂入 N 条**被拒**申请（[notes] 长度 = 条数，元素为家长备注）。
///
/// ②「兑换未被通过」通知的唯一真入口：外壳 initState 的 `_checkRejectedNotices`。
/// 供排版/溢出用例复用（同一份挂载形状，避免每个用例各抄一遍）。
Future<void> _pumpShellWithRejectedNotes(
  WidgetTester tester,
  List<String?> notes,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  await account.createChild('备用娃', AgeTier.mid); // 触发默认孩子初始化

  final List<RedemptionRequest> rejected = <RedemptionRequest>[];
  for (int i = 0; i < notes.length; i++) {
    rejected.add(RedemptionRequest(
      id: 'r_rej_$i',
      childId: account.childId,
      templateId: 'tpl_x', // → 名称「小零食」（_kRewardTpl）
      requestedAt: DateTime(2026, 10, 20, 9).add(Duration(minutes: i)),
      cost: 10,
      status: RequestStatus.rejected,
      parentNote: notes[i],
    ));
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
          rewardRepositoryProvider
              .overrideWithValue(_RejectOnlyRewardRepository(rejected)),
        ],
      ),
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卡内可滚动视口（E-系用例验证「超高时能在卡内滚动」）。
ScrollPosition _cardScrollPosition(WidgetTester tester) =>
    tester
        .state<ScrollableState>(find
            .descendant(
              of: find.byKey(GoldNoticeDialog.surfaceKey),
              matching: find.byType(Scrollable),
            )
            .first)
        .position;

/// 挂真 `ChildShellPage`，喂一条**当日额度已封顶**的成长任务打卡
/// （`sunlightGranted = 0` → 走 NEW-F141-01 的「金额留空 + 说明走副行」分支）。
///
/// 走真 `TaskLocalRepository`（内存 Drift）而不是假仓储：本条守卫的正是
/// `_checkTaskVerifiedNotices` 组装 `GoldNoticeItem` 的那几行，任何一层假掉都白测。
Future<void> _pumpShellWithCappedTask(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final TaskLocalRepository repo =
      TaskLocalRepository(database, account: account);

  final DateTime now = DateTime.now();
  await repo.saveTask(const Task(
    id: 't_cap',
    name: '晨读',
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 12,
    isCustom: true,
  ));
  // 当日成长奖励额度用尽：家长仍点「确认发放」→ gross 12 / granted 0。
  await repo.checkIn(CheckIn(
    id: 'c_cap',
    taskId: 't_cap',
    date: now,
    completedAt: now.subtract(const Duration(hours: 3)),
    isPerfectDay: false,
    status: CheckInStatus.verified,
    sunlightGross: 12,
    sunlightGranted: 0,
    resolvedAt: now.subtract(const Duration(minutes: 20)),
  ));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      ),
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ─────────────────────────── 视口 / 泵 / 通道 ───────────────────────────

/// 固定视口 + 拦截资产加载（序列帧真解码会 OOM；本文件不依赖任何位图）。
///
/// 🔴 必须同时 mock `SystemChannels.platform`：`FocusPage._handleOutcome` 里
/// `await SystemChrome.setPreferredOrientations(...)` 在**无 handler** 的测试环境
/// 下永不回包（future 不完成）→ 结算页永远进不去（实测「点结束无反应」的假故障）。
/// 既有 `eye_care_orientation_guard_test` 是靠方向指令记录仪顺带 mock 的。
void _useScreen(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double textScale = 1.0,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

/// Wakelock 通道假应答（无 mock 时 focus_page 的 `await WakelockPlus.enable()`
/// 永不回包 → 后续方向指令卡在 fake-async 外）。
void _installWakelockNoop(WidgetTester tester) {
  const List<String> channels = <String>[
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    'wakelock_plus_macos',
  ];
  for (final String name in channels) {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      name,
      (ByteData? message) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler(name, null));
  }
}

/// 有界收敛（页面里可能有无限呼吸 / 序列帧动画 → 禁 pumpAndSettle）。
Future<void> _pump(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 有界「泵到条件成立」（最多 [rounds] × 100ms，仍禁 pumpAndSettle）。
///
/// 用于跨路由 / 跨异步链的断言（如「结束专注 → 结算页」要等引擎 finished +
/// `SunlightService.settle` 落账 + `go('/settle')` 转场，固定轮数容易偶发不够）。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int rounds = 80,
}) async {
  for (int i = 0; i < rounds; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ─────────────────────────── ① 专注页退出确认 ───────────────────────────

GoRouter _focusRouter() => GoRouter(
      initialLocation: '/focus',
      routes: <RouteBase>[
        GoRoute(
          path: '/focus',
          builder: (BuildContext context, GoRouterState state) =>
              const FocusPage(plannedMinutes: 15, dnd: false),
        ),
        GoRoute(
          path: '/settle',
          builder: (BuildContext context, GoRouterState state) =>
              SettlePage(args: state.extra as SettleArgs?),
        ),
      ],
    );

/// 挂真 FocusPage（生产路由形状：go_router 替换路由）。
Future<void> _pumpFocusPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository(100)),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      eyeCareLogRepositoryProvider
          .overrideWithValue(_FakeEyeCareLogRepository()),
      settingsRepositoryProvider
          .overrideWithValue(_FakeSettingsRepository(_defaultSettings())),
      trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null), // headless 无音频后端
      ),
    ],
    child: MaterialApp.router(routerConfig: _focusRouter()),
  ));
  await _pump(tester);
}

/// 从真实专注页触发退出确认（系统返回键 → PopScope(canPop:false) → `_requestExit`）。
Future<void> _openFocusExitConfirm(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _pump(tester);
}

// ─────────────────────────── ④ 护眼提前结束 ───────────────────────────

class _EyeCareHarness {
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  Future<Object?>? pushed;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        sunlightRepositoryProvider
            .overrideWithValue(_FakeSunlightRepository(100)),
        eyeCareLogRepositoryProvider
            .overrideWithValue(_FakeEyeCareLogRepository()),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    await _pump(tester);

    pushed = navKey.currentState!.push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const EyeCarePage(args: EyeCareArgs(skipAllowed: true)),
      ),
    );
    await _pump(tester);
  }
}

// ─────────────────────────── ⑤ 等级详情 · 锁标提示 ───────────────────────────

Future<void> _pumpLevelBadge(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FocusLevelBadge(
            progress: progressOf(900), // Lv.7：Lv.1 / Lv.5 都在锁标态
            totalMinutes: 900,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────── 1. 源码守卫：零裸 AlertDialog ─────────────────────
  group('源码守卫 · 孩子端弹窗全量收口', () {
    test('lib/presentation/child/** 内 `AlertDialog(` 零命中', () {
      final Directory child =
          Directory('${_projectRoot()}/lib/presentation/child');
      final List<File> files = _dartFiles(child);
      expect(files.length, greaterThan(20),
          reason: '前置：目录必须真的被扫到（否则本守卫是假绿）');
      final List<String> hits = <String>[];
      for (final File f in files) {
        if (f.readAsStringSync().contains('AlertDialog(')) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason: '孩子端仍有裸 AlertDialog（应改走 ChildConfirmCard / '
              'GoldNoticeDialog）：\n${hits.join('\n')}');
    });

    test('lib/presentation/shared/premium_gate.dart 内 `AlertDialog(` 零命中', () {
      final File gate =
          File('${_projectRoot()}/lib/presentation/shared/premium_gate.dart');
      expect(gate.existsSync(), isTrue, reason: '前置：路径必须存在');
      expect(gate.readAsStringSync().contains('AlertDialog('), isFalse,
          reason: '付费引导弹窗应改走 showChildConfirmCard（F141 ⑥）');
    });
  });

  // ───────────────────── 2. ① 专注页退出确认 ─────────────────────
  group('① 专注页退出确认 → ChildConfirmCard', () {
    testWidgets('卡片在场 + 文案逐字 + 点卡外不关（barrierDismissible: false）',
        (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocusPage(tester);

      await _openFocusExitConfirm(tester);

      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '退出确认必须走统一卡壳');
      expect(find.text('确定结束吗？'), findsOneWidget);
      expect(find.text('向日葵还在这儿陪着你，要现在结束专注吗？'), findsOneWidget,
          reason: '中性正文槽原样呈现（不红不金）');
      expect(find.text('再坐一会'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);

      // 🔴 F141 修 2：按钮**权重**必须是「再坐一会 = 主按钮（金色实心）、
      // 结束 = 次按钮（弱化 TextButton）」—— 孩子专注页误点「结束」会中断专注。
      expect(
        find.widgetWithText(FilledButton, '再坐一会'),
        findsOneWidget,
        reason: '主按钮（金色实心）必须是「再坐一会」（默认期望 = 继续坐）',
      );
      expect(
        find.widgetWithText(TextButton, '结束'),
        findsOneWidget,
        reason: '「结束」必须退成弱化次按钮（不催不赶）',
      );

      // 原语义：barrierDismissible: false → 点卡外不关。
      await tester.tapAt(const Offset(5, 5));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '点卡外不得关闭退出确认（原 barrierDismissible: false 语义）');
    });

    testWidgets('「再坐一会」（主按钮）→ 留在专注页；「结束」（次按钮）→ 进结算页',
        (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocusPage(tester);

      await _openFocusExitConfirm(tester);
      await tester.tap(find.text('再坐一会'));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsNothing, reason: '取消后卡片关闭');
      expect(find.byType(FocusPage), findsOneWidget,
          reason: '「再坐一会」→ 仍留在专注页（不中断专注）');
      expect(find.byType(SettlePage), findsNothing, reason: '「再坐一会」绝不进结算');

      // 再次触发 → 说明 _resume() 已把 _paused 复位（否则 _requestExit 会被闸门挡掉）。
      await _openFocusExitConfirm(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '「再坐一会」必须真正恢复（_paused 复位），否则第二次退出点不出来');

      await tester.tap(find.text('结束'));
      await _pumpUntil(
          tester, () => find.byType(SettlePage).evaluate().isNotEmpty);
      expect(find.byType(SettlePage), findsOneWidget,
          reason: '确认结束 → 引擎 finished → 结算页（副作用时机不变）');
    });

    testWidgets('系统返回键把卡片 pop 成 null → 按「再坐一会」处理，不卡死',
        (WidgetTester tester) async {
      _useScreen(tester);
      _installWakelockNoop(tester);
      await _pumpFocusPage(tester);

      await _openFocusExitConfirm(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget);

      // 系统返回键 pop 掉对话框（barrier 挡不住返回键）→ 结果为 null。
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsNothing, reason: '返回键关闭卡片');
      expect(find.byType(FocusPage), findsOneWidget, reason: '仍留在专注页');
      // 关键：null 分支走 _resume()，故第二次退出仍能弹出（原实现此处会卡死）。
      await _openFocusExitConfirm(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: 'null（返回键）也必须恢复计时，否则专注页永远暂停、退不出去');
    });
  });

  // ───────────────────── 3. ④ 护眼提前结束确认 ─────────────────────
  group('④ 护眼提前结束 → ChildConfirmCard', () {
    testWidgets('卡片在场 + 文案逐字 + 点卡外不关', (WidgetTester tester) async {
      _useScreen(tester);
      final _EyeCareHarness h = _EyeCareHarness();
      await h.open(tester);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);

      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '护眼提前结束必须走统一卡壳');
      expect(find.text(kEyeCareEarlyFinishTitle), findsOneWidget);
      expect(find.text(kEyeCareEarlyFinishConfirmText), findsOneWidget);
      expect(find.text(kEyeCareEarlyFinishStayLabel), findsOneWidget);
      expect(find.text(kEyeCareEarlyFinishQuitLabel), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '点卡外不得关闭（原 barrierDismissible: false 语义）');
    });

    testWidgets('「再休息一会儿」→ 留在护眼页；「确定结束」→ 按跳过退场',
        (WidgetTester tester) async {
      _useScreen(tester);
      final _EyeCareHarness h = _EyeCareHarness();
      await h.open(tester);

      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);
      await tester.tap(find.text(kEyeCareEarlyFinishStayLabel));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsNothing);
      expect(find.byType(EyeCarePage), findsOneWidget, reason: '取消 → 留在护眼页');

      // 再点一次（`_confirmOpen` 已复位，否则被防重入闸门挡住）。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '_confirmOpen 必须在关闭后复位（防重入时序不变）');

      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
      await _pump(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(await h.pushed, isNotNull, reason: '确认结束 → 护眼页按跳过退场');
    });
  });

  // ───────────────────── 4. ⑤ 锁标提示（无标题通知卡） ─────────────────────
  group('⑤ 等级锁标提示 → GoldNoticeDialog（title 为 null）', () {
    testWidgets('卡片在场 + 文案逐字 + 不 pop 详情卡', (WidgetTester tester) async {
      _useScreen(tester);
      await _pumpLevelBadge(tester);
      await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);

      await tester.tap(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)));
      await tester.pumpAndSettle();

      expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey),
          findsOneWidget,
          reason: 'byKey 必须恰好命中 1 个（Key 只挂在弹窗根 Widget 上，不得下传 Dialog）');
      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '锁标提示改走统一通知卡壳');
      expect(find.text(kPremiumUpsellHintText), findsOneWidget);
      expect(find.text(kLevelDetailHintConfirmText), findsOneWidget);
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
          reason: 'V3-Q1：只提示、不 pop 详情卡、不跳购买页');

      await tester.tap(find.text(kLevelDetailHintConfirmText));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusLevelDetailDialog.perkLockedHintKey), findsNothing);
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget,
          reason: '关提示卡后回到详情卡');
    });
  });

  // ───────────────────── 5. ② 兑换未通过通知（warn 档） ─────────────────────
  group('② 兑换未通过通知 → GoldNoticeDialog(tone: warn)', () {
    testWidgets('真外壳入口：卡在场 + 明细与兜底文案逐字 + 底部说明逐字',
        (WidgetTester tester) async {
      _useScreen(tester);
      // 一条被拒申请（parentNote 为 null → 走「家长拒绝了该申请」兜底）。
      await _pumpShellWithRejectedNotes(tester, <String?>[null]);

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '拒绝通知必须走统一通知卡壳');
      expect(find.text('🚫 兑换未被通过'), findsOneWidget);
      // 明细：名称带「· 」前缀（原实现同形）；家长备注改走 subtitle（名称下方小字）。
      expect(find.text('· 小零食'), findsOneWidget);
      expect(find.text('（家长拒绝了该申请）'), findsOneWidget,
          reason: '兜底文案不得丢（parentNote 为 null 时）');
      expect(find.text('本次阳光未被扣除，可重新兑换其他奖励'), findsOneWidget);
      expect(find.text('知道啦'), findsOneWidget);
    });

    // 🔴 F141 修 1（QA 探针 F141-BUG-01 打回）：旧实现把备注塞进右侧 `amountText`
    // —— Row 的非 flex 子节点拿无界主轴约束 → 长备注/小屏大字号直接 RenderFlex 溢出
    // （实测 24 字备注溢出 213px；320×568 + 1.3 倍连兜底串都溢出 55px）。
    // 本组把 5 个生产可达场景逐一钉死：零异常 + 名称列有宽度 + 备注不越卡。
    group('明细行零溢出（修 1，5 个生产可达场景）', () {
      testWidgets('场景①兜底串 · 320×568 · 1.0 倍', (WidgetTester tester) async {
        _useScreen(tester, width: 320, height: 568);
        await _pumpShellWithRejectedNotes(tester, <String?>[null]);
        expect(find.text('（家长拒绝了该申请）'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '320×568（1.0 倍）兜底串不得溢出');
        expect(tester.getSize(find.text('· 小零食')).width, greaterThan(0));
      });

      testWidgets('场景②兜底串 · 320×568 · 1.3 倍', (WidgetTester tester) async {
        _useScreen(tester, width: 320, height: 568, textScale: 1.3);
        await _pumpShellWithRejectedNotes(tester, <String?>[null]);
        expect(find.text('（家长拒绝了该申请）'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '320×568（1.3 倍）兜底串不得溢出');
        expect(tester.getSize(find.text('· 小零食')).width, greaterThan(0));
      });

      testWidgets('场景③24 字家长备注 · 390×844（备注不越卡右缘）',
          (WidgetTester tester) async {
        _useScreen(tester);
        const String note = '这个奖励本周已经兑换过了，先攒着阳光下周再来找我哦';
        await _pumpShellWithRejectedNotes(tester, <String?>[note]);
        expect(tester.takeException(), isNull, reason: '长备注不得触发 RenderFlex 溢出');
        final Rect card =
            tester.getRect(find.byKey(GoldNoticeDialog.surfaceKey));
        final Rect sub = tester.getRect(find.text('（$note）'));
        expect(sub.right, lessThanOrEqualTo(card.right + 0.5),
            reason: '备注右缘不得越出卡片（实测 ${sub.right} vs ${card.right}）');
        expect(sub.left, greaterThanOrEqualTo(card.left - 0.5));
        // 备注在名称**下方**（subtitle）：顶边必须低于名称顶边。
        expect(sub.top, greaterThan(tester.getRect(find.text('· 小零食')).top));
      });

      testWidgets('场景④3 条明细 · 320×568 · 1.3 倍（零异常 + 卡内可滚动）',
          (WidgetTester tester) async {
        _useScreen(tester, width: 320, height: 568, textScale: 1.3);
        const String longNote = '家长这次没有通过，你先把作业写完再来兑换吧';
        await _pumpShellWithRejectedNotes(
            tester, <String?>[longNote, longNote, longNote]);
        expect(tester.takeException(), isNull,
            reason: '320 小屏 + 1.3 倍 + 3 条明细不得溢出（F126 老坑位）');
        expect(
            tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey)).height,
            lessThanOrEqualTo(568 * 0.7 + 0.5),
            reason: '卡高受 maxHeightRatio(0.7) 约束');
        expect(_cardScrollPosition(tester).maxScrollExtent, greaterThan(0),
            reason: '内容超高时必须能在卡内滚动（否则就是被裁掉）');
      });

      testWidgets('场景⑤金额列始终右贴卡片内缘且不超宽（回归「金额」语义）',
          (WidgetTester tester) async {
        _useScreen(tester);
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showGoldNoticeDialog(
                    c,
                    title: '🎉 家长已确认你的兑换',
                    items: const <GoldNoticeItem>[
                      GoldNoticeItem(
                        icon: Icons.redeem,
                        name: '超级无敌长名字的奖励模板测试用',
                        amountText: '-1234.5 阳光',
                      ),
                    ],
                    footerText: '共扣除 1234.5 阳光',
                  ),
                  child: const Text('弹卡'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('弹卡'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '长名称 + 长金额也不得溢出（两列都是 flex 子节点）');
        final Rect card =
            tester.getRect(find.byKey(GoldNoticeDialog.surfaceKey));
        final Rect amount = tester.getRect(find.text('-1234.5 阳光'));
        expect(amount.right, lessThanOrEqualTo(card.right + 0.5),
            reason: '金额右缘贴齐卡片内容右缘、绝不越界');
      });
    });
  });

  // ────────────── 5b. NEW-F141-01：封顶条目「今日额度已满」走副行 ──────────────
  // QA 二轮：改成 60/40 两列后，390 屏上金额列恒 87.2px，而「今日额度已满」
  // = 6 汉字 ≈ 96px → 必折两行、断在第 5 个字（右对齐「今日额度已」/「满」）。
  // 口径修正：封顶行 `amountText` 留空（该列整块不渲染）、说明走 `subtitle`。
  // 文案逐字不变（`今日额度已满` 仍出现），`isCapped`（granted <= 0）判据不动。
  group('封顶条目 → 「今日额度已满」必须在副行（NEW-F141-01）', () {
    for (final (double w, double h, double scale, String tag)
        in <(double, double, double, String)>[
      (390, 844, 1.0, '390×844 @1.0'),
      (320, 568, 1.3, '320×568 @1.3'),
    ]) {
      testWidgets('$tag：文案在场 + 位于副行（非金额列）+ 只占 1 行',
          (WidgetTester tester) async {
        _useScreen(tester, width: w, height: h, textScale: scale);
        await _pumpShellWithCappedTask(tester);

        expect(tester.takeException(), isNull, reason: '封顶行不得溢出（$tag）');
        expect(find.text('🎉 家长已确认你的成长任务'), findsOneWidget);
        // 文案逐字不变（只是从金额位挪到副行）。
        expect(find.text('今日额度已满'), findsOneWidget,
            reason: '封顶说明必须仍然出现（$tag）');
        expect(find.text('+12 阳光'), findsNothing,
            reason: '绝不能把应发 gross 当实发报给孩子（虚报阳光 = 口径错误）');

        final Rect name = tester.getRect(find.text('晨读'));
        final Rect note = tester.getRect(find.text('今日额度已满'));

        // ① 只占 1 行：字号 13、height 1.35，两行必然 ≥ 2×13×1.35×底数。
        expect(note.height, lessThanOrEqualTo(13 * 1.35 * scale * 1.25),
            reason: '说明不得折成 2 行（实测 ${note.height}，单行上限'
                ' ${(13 * 1.35 * scale * 1.25).toStringAsFixed(1)}）');

        // ② 位置在「名称下方、与名称左对齐」= 副行；金额列是右对齐的，左缘会明显偏右。
        expect(note.top, greaterThan(name.top),
            reason: '必须在名称下方（副行），不能与名称同排');
        expect(note.left, moreOrLessEquals(name.left, epsilon: 0.5),
            reason: '副行与名称左对齐（金额列右对齐，左缘必然更靠右）');

        // ③ 金额列整块不渲染：封顶行只有「图标 + 名称列」两个子节点。
        final Finder row = find
            .ancestor(of: find.text('今日额度已满'), matching: find.byType(Row))
            .first;
        expect(
          find.descendant(of: row, matching: find.byType(Expanded)).evaluate(),
          hasLength(1),
          reason: '封顶行的 amountText 为空串 → 右侧金额列整块不渲染（只剩名称列 1 个 Expanded）',
        );
      });
    }
  });

  // ───────────────────── 6. ③ 完美日庆祝（真页面入口） ─────────────────────
  group('③ 完美日庆祝 → GoldNoticeDialog（「太棒啦」）', () {
    testWidgets('打完当日最后一个成长项 → 通知卡在场 + 文案逐字',
        (WidgetTester tester) async {
      _useScreen(tester);
      const Task only = Task(
        id: 't_only',
        name: '自己整理书包',
        subject: TaskSubject.general,
        requiresFocus: false,
        minFocusMin: 15,
        sunlightReward: 12,
        isCustom: false,
      );
      final _MemTaskRepository tasks = _MemTaskRepository(<Task>[only]);
      final _FakeSunlightRepository ledger = _FakeSunlightRepository(100);
      final _FakeFocusRepository focus = _FakeFocusRepository();
      final _FakeSettingsRepository settings =
          _FakeSettingsRepository(_defaultSettings());

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          taskCheckInServiceProvider.overrideWithValue(TaskCheckInService(
            tasks: tasks,
            ledger: ledger,
            focus: focus,
            settings: settings,
          )),
        ],
        child: const MaterialApp(home: Scaffold(body: ChildTaskPage())),
      ));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 真实入口：点该行的「我做 / 到了」方盒。
      expect(find.text('我做'), findsOneWidget, reason: '前置：未打卡项给出了打卡按钮');
      await tester.tap(find.text('我做'));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(GoldNoticeDialog), findsOneWidget,
          reason: '完美日庆祝必须走统一通知卡壳');
      expect(find.text('🌻 今日成长项全部完成！'), findsOneWidget);
      expect(find.text('你今天把全部成长项都做完啦，获得「完美日」标记！'), findsOneWidget);
      expect(find.text('太棒啦'), findsOneWidget, reason: 'confirmLabel 定制为「太棒啦」');
    });
  });

  // ───────────────────── 7. ⑥ 付费引导（真入口） ─────────────────────
  group('⑥ 付费引导 → ChildConfirmCard', () {
    testWidgets('卡片在场 + 文案逐字；「稍后」不跳转，「解锁全部功能」跳购买页',
        (WidgetTester tester) async {
      _useScreen(tester);
      final GoRouter router = GoRouter(
        initialLocation: '/gate',
        routes: <RouteBase>[
          GoRoute(
            path: '/gate',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showPremiumUpsell(context, FeatureKey.gardenPotCapacity),
                  child: const Text('打开付费引导'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/parent/premium',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Center(child: Text('购买页占位'))),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开付费引导'));
      await tester.pumpAndSettle();

      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '付费引导必须走统一卡壳');
      expect(find.text('升级解锁'), findsOneWidget);
      expect(find.text('「更多花盆」需要一次性买断解锁。'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('解锁全部功能'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.byType(ChildConfirmCard), findsNothing);
      expect(find.text('购买页占位'), findsNothing, reason: '「稍后」绝不跳购买页');

      await tester.tap(find.text('打开付费引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('解锁全部功能'));
      await tester.pumpAndSettle();
      expect(find.text('购买页占位'), findsOneWidget,
          reason: 'ok == true 才 push /parent/premium');
    });
  });

  // ───────────────────── 8. 金色通知卡宽度（本轮核心诉求） ─────────────────────
  group('金色通知卡宽度收敛（340 × uiScaleOf）', () {
    /// 从真实入口弹一张通知卡（长标题 + 1 条明细 + 合计），量卡片本体渲染宽度。
    Future<double> openAndMeasure(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: TextButton(
                onPressed: () => showGoldNoticeDialog(
                  ctx,
                  title: '🎉 家长已确认你的成长任务',
                  items: const <GoldNoticeItem>[
                    GoldNoticeItem(
                      icon: Icons.task_alt,
                      name: '自己整理书包',
                      amountText: '+12 阳光',
                    ),
                  ],
                  footerText: '共获得 12 阳光',
                ),
                child: const Text('弹卡'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('弹卡'));
      await tester.pumpAndSettle();
      final Size size =
          tester.getSize(find.byKey(GoldNoticeDialog.surfaceKey));
      return size.width;
    }

    testWidgets('手机 390 → 实测 310（改前改后逐像素零回归）',
        (WidgetTester tester) async {
      _useScreen(tester); // 390 × 844
      final double w = await openAndMeasure(tester);
      expect(w, moreOrLessEquals(310, epsilon: 0.5),
          reason: '手机端：可用宽 = 390 − insetPadding(40×2) = 310，'
              '340 的上界不生效 → 与改前完全一致');
    });

    testWidgets('iPad 13″（1032，倍率 1.6）→ 实测 544（改前 952，收窄 43%）',
        (WidgetTester tester) async {
      _useScreen(tester, width: 1032, height: 1376);
      final double w = await openAndMeasure(tester);
      expect(w, lessThanOrEqualTo(544.5),
          reason: '上界 = GoldNoticeStyle.maxWidth(340) × uiScaleOf(1.6) = 544');
      expect(w, lessThan(952),
          reason: '改前实测 952（1032 − 40×2）几乎铺满屏幕（玄参反馈「太宽」）');
      expect(w, moreOrLessEquals(544, epsilon: 0.5),
          reason: 'iPad 13″ 应精确落在 544');
    });
  });
}
