/// 护眼横屏竞速守卫（玄参荣耀平板真机 Bug，2026-10-16 修复）。
///
/// **Bug 现场**：专注结束 → 进护眼 → 护眼那一分钟整页被压回**竖屏**。根因是转场链
/// 上有两条方向指令竞速：`focus_page` 的 `go('/settle')` 替换路由后，旧页 dispose 里
/// 兜底复位的 portrait 迟到（路由退场过渡结束后才 dispose），覆盖了护眼卡 initState
/// 刚发出的 landscape——Android 平台通道「后发覆盖先发」，最后一条生效。
///
/// 修复（lib 侧两处）：
///  ① `focus_page._handleOutcome` 复位后置 `_chromeRestoreHandled`，dispose 不再
///     重复发 portrait（该删的删：同一转场链只留一条竖屏指令，且在压卡之前）；
///  ② 护眼卡横屏指令改走 `OrientationBridge.lockLandscape()` 并在退场（`_finish`）
///     前 await——调用方随后的竖屏复位严格排在横屏指令之后（该 await 的 await）。
///
/// 本守卫按平台通道**行为级**断言（TestDefaultBinaryMessenger mock
/// `SystemChannels.platform`，录下 `SystemChrome.setPreferredOrientations` 的调用
/// 序列，非源码字符串守卫），钉死两条契约：
///  ① **结算插卡路径**（= 真机出事的转场形状：手动结束 / 离席打断 + 达护眼门槛 →
///     结算页先插护眼卡）：方向指令序列必须恰为 **[结算竖屏, 护眼横屏, 护眼退场后
///     结算复位竖屏]**——护眼展示期间其后绝不允许再出现任何方向指令（portrait 覆盖
///     即 Bug 复现）；
///  ② **护眼卡自身**：进场恰发一条横屏指令且展示期间 / 自身退场均不再发方向指令
///    （C44 口径：退场复位是调用方职责，护眼卡绝不与人抢方向盘）。
///
/// ⚠️ 护眼页内嵌 SunflowerCanvas 无限呼吸动画 → **禁用 pumpAndSettle**，一律有界
/// pump（与 eye_care_page_test / settle_eye_care_test 同纪律）。
library eye_care_orientation_guard_test;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, MethodCall, MethodChannel, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';

/// 方向指令记录仪：mock `flutter/platform` 通道，录下每一条
/// `SystemChrome.setPreferredOrientations` 的实参（按发送顺序，Android 上
/// 「后发覆盖先发」→ 序列的最后一条就是实际生效的方向）。
class _OrientationLog {
  final List<List<DeviceOrientation>> calls = <List<DeviceOrientation>>[];

  static bool _isLandscapeOnly(List<DeviceOrientation> os) =>
      os.isNotEmpty &&
      os.every((DeviceOrientation o) =>
          o == DeviceOrientation.landscapeLeft ||
          o == DeviceOrientation.landscapeRight);

  static bool _isPortraitOnly(List<DeviceOrientation> os) =>
      os.isNotEmpty &&
      os.every((DeviceOrientation o) =>
          o == DeviceOrientation.portraitUp ||
          o == DeviceOrientation.portraitDown);

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          final List<dynamic> raw = call.arguments! as List<dynamic>;
          calls.add(raw
              .map((dynamic e) => DeviceOrientation.values
                  .firstWhere((DeviceOrientation o) => o.toString() == e))
              .toList());
        }
        return null; // 其余平台消息照旧空应答（测试环境默认行为）
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }
}

/// Wakelock 通道假应答：flutter_tester 里 wakelock_plus 的 pigeon
/// BasicMessageChannel 消息**永不回包**（无 mock handler 时 send 的 future 不
/// 完成）→ FocusPage._enterFocusMode / _restoreSystemChrome 的
/// `await WakelockPlus.enable()/disable()` 会把后续的方向指令卡死在 fake-async
/// 外面。这里把通道 mock 成「立即回 null」——pigeon 侧视为 channel-error 抛
/// PlatformException，被调用方既有 try/catch 兜住（生产语义：常亮失败不影响主流程）。
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

/// 只记录 `append` 的假账本（与 settle_eye_care_test 同款，防真库触库）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this.startBalance);

  final double startBalance;
  final List<SunlightEntry> appended = <SunlightEntry>[];

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(appended);

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
  Future<int> countByResult(EyeCareResultType type) async => appended
      .where((EyeCareLog l) => l.result == type)
      .length;

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) async => appended
      .where((EyeCareLog l) => l.result == type)
      .fold<int>(0, (int sum, EyeCareLog l) => sum + l.watchedSeconds);
}

/// 假专注会话仓储：SunlightService.settle 结算时会 saveSession（防真库触库）。
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

/// 假埋点仓储：focus_session_start/end 等埋点只记账不落库。
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

/// 守卫专用迷你路由（与 lib/shared/app_router.dart 的 /focus、/settle 同形，
/// 无首启同意重定向——测试环境不读 SP）。
GoRouter _guardRouter() => GoRouter(
      initialLocation: '/focus',
      routes: <RouteBase>[
        GoRoute(
          path: '/focus',
          builder: (BuildContext context, GoRouterState state) =>
              const FocusPage(plannedMinutes: 15, dnd: false),
        ),
        GoRoute(
          path: '/settle',
          // 结算参数经 go extra 传入（与生产路由一致）。
          builder: (BuildContext context, GoRouterState state) =>
              SettlePage(args: state.extra as SettleArgs?),
        ),
      ],
    );

/// 默认设置（护眼三项取实体默认：开 / 20 分钟 / 允许跳过）。
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

/// 最小可用结算结果（settlement != null 才会挂庆祝序列帧，与真机流程一致）。
FocusSettlement _settlement() => const FocusSettlement(
      sessionId: 's-orient-guard',
      actualFocusMin: 14.0,
      rawS: 14.0,
      net: 14.0,
      balanceAfter: 114,
      todayNet: 14.0,
      plannedMin: 15,
      status: FocusStatus.completed,
      endReason: FocusEndReason.manual,
    );

/// 固定手机尺寸 + 拦截资产加载（护眼帧是真实 720×720 位图，真解码会 OOM——
/// 与 eye_care_page_test 同坑同解：errorBuilder 占位，不依赖位图）。
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  const MethodChannel assets = MethodChannel('flutter/assets');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    assets,
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(assets, null));
}

/// 有界收敛（护眼页呼吸动画 → 禁 pumpAndSettle）。
Future<void> _pump(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 结算页测试台（与 settle_eye_care_test 同形状：SettlePage 直接作 home，
/// 护眼卡由其 post-frame 回调经 Navigator.push 压上——即真机的结算插卡路径）。
Future<void> _pumpSettlePage(
  WidgetTester tester, {
  required bool eyeCarePending,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository(100)),
      eyeCareLogRepositoryProvider
          .overrideWithValue(_FakeEyeCareLogRepository()),
      settingsRepositoryProvider.overrideWithValue(
        _FakeSettingsRepository(_defaultSettings()),
      ),
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null), // headless 无音频后端
      ),
    ],
    child: MaterialApp(
      home: SettlePage(
        args: SettleArgs(
          settlement: _settlement(),
          eyeCarePending: eyeCarePending,
        ),
      ),
    ),
  ));
}

/// 护眼卡测试台（与 eye_care_page_test 同形状：直接 push 一张卡，隔离出
/// 「护眼卡自己」的方向行为——结算页 / 专注页都不在场）。
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
        builder: (_) => const EyeCarePage(
          args: EyeCareArgs(skipAllowed: true),
        ),
      ),
    );
    await _pump(tester);
  }
}

void main() {
  group('结算插卡路径（真机出事的转场形状）方向指令序列', () {
    testWidgets('序列恰为 [结算竖屏 → 护眼横屏 → 护眼退场后复位竖屏]，展示期间无覆盖',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _OrientationLog log = _OrientationLog()..install(tester);
      await _pumpSettlePage(tester, eyeCarePending: true);
      await _pump(tester);

      // 入场形状：结算页 initState 竖屏在先，护眼卡横屏在后——「进入护眼页后
      // 最后一条方向指令是 landscape」。
      expect(log.calls, hasLength(2), reason: '入场应恰两条：结算竖屏 + 护眼横屏');
      expect(_OrientationLog._isPortraitOnly(log.calls[0]), isTrue,
          reason: '第 1 条：结算页强制竖屏（口径不动）');
      expect(_OrientationLog._isLandscapeOnly(log.calls[1]), isTrue,
          reason: '第 2 条（后发者，即实际生效方向）：护眼卡横屏');

      // 护眼展示期间（额外有界 pump ≈5s）绝不允许出现第 3 条方向指令——
      // 迟到的 portrait 覆盖正是荣耀平板真机 Bug 的复现形状。
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(log.calls, hasLength(2),
          reason: '护眼展示期间不得再发任何方向指令（portrait 覆盖即 Bug 复现）');

      // 跳过收口（主按钮 → 二次确认）→ 护眼退场 → 结算页复位竖屏。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);
      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
      await _pump(tester);

      expect(log.calls, hasLength(3));
      expect(_OrientationLog._isPortraitOnly(log.calls[2]), isTrue,
          reason: '护眼退场后结算页必须复位竖屏（口径：只有结算页竖屏）');
    });
  });

  group('护眼卡自身方向纪律（C44：退场复位是调用方职责）', () {
    testWidgets('进场恰发一条横屏指令；展示期间与自身退场均不再发方向指令',
        (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _OrientationLog log = _OrientationLog()..install(tester);
      final _EyeCareHarness h = _EyeCareHarness();
      await h.open(tester);

      expect(log.calls, hasLength(1));
      expect(_OrientationLog._isLandscapeOnly(log.calls.single), isTrue,
          reason: '护眼卡进场必须把（当时）最后一条方向指令钉在横屏');

      // 展示期间（含跳过二次确认弹窗打开）不得再发任何方向指令。
      await tester.tap(find.text(kEyeCareFinishLabel));
      await _pump(tester);
      expect(log.calls, hasLength(1));

      // 确认跳过 → 护眼卡退场（含 dispose）：自身不发方向指令，与调用方
      // 的复位指令零竞速（若它退场时手痒发 portrait，就是本 Bug 的同族形态）。
      await tester.tap(find.text(kEyeCareEarlyFinishQuitLabel));
      await _pump(tester);
      await h.pushed;
      expect(log.calls, hasLength(1),
          reason: '护眼卡自身退场（含 dispose）不得发任何方向指令');
    });
  });

  group('全链路（真机根因那半边）：FocusPage dispose 迟到 portrait 守卫', () {
    testWidgets(
        'FocusPage 手动结束 → go(/settle) → 结算页插护眼卡 → 退场过渡后真实 dispose，'
        '护眼横屏之后不得再出现任何 portrait', (WidgetTester tester) async {
      _usePhoneScreen(tester);
      final _OrientationLog log = _OrientationLog()..install(tester);
      _installWakelockNoop(tester); // wakelock 通道假应答（否则方向链卡死）

      // 走**生产路由**进场：/focus 挂真 FocusPage（go_router 替换路由 → 旧页
      // 等退场过渡结束才 dispose，正是真机竞速的时序形状）。
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          sunlightRepositoryProvider
              .overrideWithValue(_FakeSunlightRepository(100)),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          eyeCareLogRepositoryProvider
              .overrideWithValue(_FakeEyeCareLogRepository()),
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(_defaultSettings()),
          ),
          trackingRepositoryProvider
              .overrideWithValue(_FakeTrackingRepository()),
          audioServiceProvider.overrideWithValue(
            AudioService(playerFactory: () => null), // headless 无音频后端
          ),
        ],
        child: MaterialApp.router(routerConfig: _guardRouter()),
      ));
      await _pump(tester); // 引擎 post-frame start + _applyAudioOnEnter 完成

      // 入场形状：专注页 initState 锁横屏，恰 1 条。
      expect(log.calls, hasLength(1), reason: '专注页入场应恰发 1 条横屏锁');
      expect(_OrientationLog._isLandscapeOnly(log.calls.single), isTrue,
          reason: '第 1 条：专注页入场锁横屏');

      // 快进角标（kDebugMode 专属）×2 → 引擎累计注视 10 分钟 =
      // kEyeCareSessionEndMinutes 门槛 → 手动结束时 _shouldEyeCareAtSessionEnd
      // 必为真（真机 Bug 的前提：结算页会插护眼卡）。
      final Finder fastForward = find.byTooltip('调试：快进 5 分钟（护眼触发用）');
      expect(fastForward, findsOneWidget,
          reason: 'flutter test 是 debug 构建，快进角标必须在场');
      await tester.tap(fastForward);
      await _pump(tester);
      await tester.tap(fastForward);
      await _pump(tester);
      expect(log.calls, hasLength(1),
          reason: '快进只推进引擎时间：默认护眼间隔 20 分钟 > 已注入的 10 分钟，'
              '不得触场内护眼、不得发任何方向指令');

      // 系统返回键 → PopScope(canPop:false) → 暂停 + 退出确认（B18/B20 生产路径）。
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.text('确定结束吗？'), findsOneWidget,
          reason: '前置：退出确认框必须已弹出');
      await tester.tap(find.text('结束'));
      await _pump(tester);

      // 转场链形状：[专注横屏, 手动结束复位竖屏, 结算竖屏, 护眼横屏]。
      expect(log.calls, hasLength(4),
          reason: '链上应恰 4 条：专注横屏 → 复位竖屏 → 结算竖屏 → 护眼横屏');
      expect(_OrientationLog._isLandscapeOnly(log.calls[0]), isTrue,
          reason: '①专注页入场锁横屏');
      expect(_OrientationLog._isPortraitOnly(log.calls[1]), isTrue,
          reason: '②_handleOutcome 复位竖屏（同时置 _chromeRestoreHandled）');
      expect(_OrientationLog._isPortraitOnly(log.calls[2]), isTrue,
          reason: '③结算页 initState 强制竖屏');
      expect(_OrientationLog._isLandscapeOnly(log.calls[3]), isTrue,
          reason: '④结算页插的护眼卡锁横屏');

      // 泵够路由退场过渡（MaterialPage ≈300ms）→ 旧 FocusPage 真实 dispose：
      // 元素离树 ⇒ State 必已 dispose（dispose 先于 unmount 发生）。
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(FocusPage, skipOffstage: false).evaluate(), isEmpty,
          reason: '前置：go(/settle) 退场过渡结束后旧 FocusPage 必须已卸载（dispose 已执行）');

      // 护眼展示期间继续有界 pump ≈5s：不得出现第 5 条方向指令——
      // dispose 迟到 portrait 一出现即红（真机荣耀平板 Bug 的根因那半边：
      // go 替换路由后旧页 dispose 的兜底复位把护眼卡压回竖屏）。
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(log.calls, hasLength(4),
          reason: '护眼横屏之后、护眼结束之前不得再发任何方向指令'
              '（FocusPage dispose 迟到 portrait 即 Bug 复现）');
    });
  });
}
