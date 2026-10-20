/// F140（玄参 2026-10-20 iPad 13″ 截图实测）：**结算页 / 专注页中央向日葵
/// 未随平板等比例放大**的回归守卫。
///
/// ## 缺陷现象
/// iPad 13″ 上结算页「文字很大、花很小」。截图实测：花可见区 170.6×215.7 pt，
/// 只占屏宽 **16.5%**；同尺寸在手机 390 上占 **43.7%** —— 平板上只剩手机的 38%。
///
/// ## 根因（两处同源：定尺寸元素漏乘 [uiScaleOf]）
///  ① `settle_page.dart` 中央向日葵容器写死 `260×260`（光晕 `300×300`），
///     全页一次没调 `uiScaleOf`；而文字走 `textScaler`（iPad 13″ = 1.6×）
///     → 文字放大 1.6 倍、花纹丝不动，视觉占比直接失衡。
///  ② `focus_page.dart`（打盹屏）按可用高度自适应，但**上限死写 230**
///     → 平板再高也撑不过 230，与手机同尺寸。
///
/// ## 修法
/// 两处一律乘 [uiScaleOf]：260/300 → `× uiScaleOf`，上限 230 → `230 × uiScaleOf`。
/// 手机倍率恒 1.0 → **手机零像素变化**（本文件前三个用例即零回归守卫）。
///
/// ## 本文件锁什么（从**真实页面入口**量，不自己传尺寸 —— C101-5 接线守）
///  - 结算页静态花：手机 260 ／ iPad 11″ 338 ／ iPad 13″ 416；
///  - 结算页庆祝帧容器：与静态花**同值**（两条分支不得只改一条）；
///  - 专注页打盹花：手机 230 ／ iPad 13″ 368；
///  - 「花 / 屏宽」占比不得低于手机的一半（视觉占比坍缩的直接量化）。
///
/// ⚠️ 结算页静态花 = `SunflowerCanvas` **无限呼吸动画** → 全程禁 `pumpAndSettle`
/// （有界 pump，同 `settle_eye_care_test` 纪律）。
/// ⚠️ 结算庆祝帧是 36 张 720×720 真位图，`flutter_tester` 里真解码会 OOM
/// （2026-10-05 实证 exit 137）→ 拦截 `flutter/assets` 走 errorBuilder 占位；
/// 本文件只量容器尺寸，不依赖位图内容。
library f140_tablet_sunflower_scale_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart' show FocusSettlement;
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 手机基准（iPhone 17 逻辑尺寸）—— 本次改动的「零回归」锚点。
const Size _kPhone = Size(390, 844);

/// iPad Pro 11″ 竖屏 —— 已被玄参确认「1.3 倍正常」的锚点机型。
const Size _kIpad11 = Size(834, 1194);

/// iPad Pro 13″（M5）竖屏 —— 本次缺陷的实测机型（倍率 1.6）。
const Size _kIpad13 = Size(1032, 1376);

/// 结算页中央花容器在手机上的原始尺寸（改动前的写死值，作为基准断言）。
const double _kSettleFlowerBase = 260;

/// 专注页打盹花的原始上限（改动前的写死值）。
const double _kFocusFlowerMax = 230;

// ─────────────────────────── 假仓储（够用即止） ───────────────────────────

class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository(this.startBalance);

  final double startBalance;

  @override
  Future<List<SunlightEntry>> all() async => const <SunlightEntry>[];

  @override
  Future<double> balance() async => startBalance;

  @override
  Future<double> append(SunlightEntry entry) async => startBalance;

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

AppSettings _defaultSettings() => const AppSettings(
      ageTier: AgeTier.high,
      dailyFocusCap: 60,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 400,
    );

/// 结算结果（非空才会走庆祝序列帧分支；本文件只用它验证两条分支同值）。
FocusSettlement _settlement() => const FocusSettlement(
      sessionId: 's-f140',
      actualFocusMin: 15.0,
      rawS: 15.0,
      net: 15.0,
      balanceAfter: 115,
      todayNet: 15.0,
      plannedMin: 15,
      status: FocusStatus.completed,
      endReason: FocusEndReason.manual,
    );

// ─────────────────────────── 测试台 ───────────────────────────

/// 设视口 + 拦资产解码（防序列帧 OOM / 手机画布顶到屏幕外）。
void _useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
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

/// 「app.dart 同款注入壳」：平板文字放大走真实单点 [applyTabletTextScaling]。
///
/// 与 `tablet_scale_ipad13_test` 同构 —— 不自己写死倍率，让
/// 「视口 → MediaQueryData → 注入点 → uiScaleOf」整条链路跑通。
Widget _injectedApp(Widget home) => MaterialApp(
      builder: (BuildContext ctx, Widget? child) {
        final Widget content = child ?? const SizedBox.shrink();
        final MediaQueryData mq = MediaQuery.maybeOf(ctx) ?? const MediaQueryData();
        final MediaQueryData scaled = applyTabletTextScaling(mq);
        if (identical(scaled, mq)) return content; // 手机：不引入 MediaQuery
        return MediaQuery(data: scaled, child: content);
      },
      home: home,
    );

List<Override> _overrides() => <Override>[
      sunlightRepositoryProvider
          .overrideWithValue(_FakeSunlightRepository(100)),
      eyeCareLogRepositoryProvider
          .overrideWithValue(_FakeEyeCareLogRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      settingsRepositoryProvider
          .overrideWithValue(_FakeSettingsRepository(_defaultSettings())),
      trackingRepositoryProvider
          .overrideWithValue(_FakeTrackingRepository()),
      // headless 无音频后端
      audioServiceProvider
          .overrideWithValue(AudioService(playerFactory: () => null)),
    ];

/// 有界收敛（结算页呼吸动画 / 专注页引擎 tick → 禁 pumpAndSettle）。
Future<void> _settlePump(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pumpSettlePage(
  WidgetTester tester, {
  FocusSettlement? settlement,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: _injectedApp(SettlePage(
      args: SettleArgs(settlement: settlement, eyeCarePending: false),
    )),
  ));
  await _settlePump(tester);
}

/// 专注页专用迷你路由（与 `app_router.dart` 的 `/focus` 同形）。
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

Future<void> _pumpFocusPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: MaterialApp.router(routerConfig: _focusRouter()),
  ));
  await _settlePump(tester);
}

/// 元素在屏幕上的**真实**矩形宽（会应用 FittedBox 等祖先变换）。
double _renderedWidth(WidgetTester tester, String key) {
  final Finder f = find.byKey(ValueKey<String>(key), skipOffstage: false);
  expect(f, findsOneWidget, reason: '前置：$key 必须在场');
  return tester.getRect(f).width;
}

void main() {
  group('结算页中央向日葵：随平板等比例放大（F140）', () {
    testWidgets('手机 390：容器恒 260（零回归，改动前后逐位相等）', (tester) async {
      _useScreen(tester, _kPhone);
      await _pumpSettlePage(tester);

      expect(_renderedWidth(tester, 'settle-sunflower'), _kSettleFlowerBase,
          reason: '手机倍率 1.0 → 必须逐位等于原写死值 260');
    });

    testWidgets('iPad 11″ 834：容器 = 260 × 1.3 = 338', (tester) async {
      _useScreen(tester, _kIpad11);
      await _pumpSettlePage(tester);

      expect(_renderedWidth(tester, 'settle-sunflower'), 260 * 1.3,
          reason: 'iPad 11″ 倍率 1.3（kTabletUiScale 锚点）');
    });

    testWidgets('iPad 13″ 1032：容器 = 260 × 1.6 = 416（本次缺陷机型）',
        (tester) async {
      _useScreen(tester, _kIpad13);
      await _pumpSettlePage(tester);

      final double flower = _renderedWidth(tester, 'settle-sunflower');
      expect(flower, 260 * 1.6, reason: 'iPad 13″ 倍率 1.6（封顶）');
      // 缺陷本体：花/屏宽占比 25.2% → 40.3%；不得再落回 25% 档。
      expect(flower / _kIpad13.width, greaterThan(0.38),
          reason: '花占屏宽 416/1032 = 40.3%，修复前只有 25.2%');
    });

    testWidgets('庆祝帧容器与静态花同值 —— 两条分支不得只改一条', (tester) async {
      _useScreen(tester, _kIpad13);
      await _pumpSettlePage(tester, settlement: _settlement());

      expect(_renderedWidth(tester, 'settle-sunflower-fx'), 260 * 1.6,
          reason: 'settlement 非空走序列帧分支，尺寸必须与静态花一致');
    });

    testWidgets('放大后不溢出：iPad 13″ 全页零异常', (tester) async {
      _useScreen(tester, _kIpad13);
      await _pumpSettlePage(tester);

      expect(tester.takeException(), isNull,
          reason: '416 + 光晕 480 必须塞得进 Expanded（可用 >730）');
    });

    testWidgets('夸奖卡图标同属「定尺寸元素」：手机 20 → iPad 13″ 32',
        (tester) async {
      // C97：图标不在 textScaler 管辖内，必须单独乘倍率；本用例接住该接线
      // （否则把 `size: 20 * uiScaleOf(context)` 改回 `20` 无人报警）。
      _useScreen(tester, _kPhone);
      await _pumpSettlePage(tester);
      expect(tester.getSize(find.byIcon(Icons.auto_awesome)).width, 20,
          reason: '手机倍率 1.0 → 逐位等于原写死值');

      _useScreen(tester, _kIpad13);
      await _pumpSettlePage(tester);
      expect(tester.getSize(find.byIcon(Icons.auto_awesome)).width, 20 * 1.6,
          reason: 'iPad 13″ 倍率 1.6 → 32');
    });
  });

  group('专注页打盹花：上限随平板放开（F140）', () {
    testWidgets('手机 390：仍钳在 230（零回归）', (tester) async {
      _useScreen(tester, _kPhone);
      await _pumpFocusPage(tester);

      expect(_renderedWidth(tester, 'focus-sunflower-stage'), _kFocusFlowerMax,
          reason: '手机倍率 1.0 → 上限仍是 230');
    });

    testWidgets('iPad 13″ 1032：上限 = 230 × 1.6 = 368（不再死卡 230）',
        (tester) async {
      _useScreen(tester, _kIpad13);
      await _pumpFocusPage(tester);

      final double flower = _renderedWidth(tester, 'focus-sunflower-stage');
      expect(flower, 230 * 1.6, reason: '平板倍率 1.6 后上限放开到 368');
      expect(flower, greaterThan(_kFocusFlowerMax),
          reason: '修复前平板上永远 ≤230，与手机同尺寸');
    });

    testWidgets('iPad 13″ 放大后不溢出：全页零异常', (tester) async {
      _useScreen(tester, _kIpad13);
      await _pumpFocusPage(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
