/// 护眼卡「平板横屏不铺满」几何守卫（2026-10-19 荣耀平板真机反馈）。
///
/// **Bug 现场**：荣耀平板横屏进护眼，内容块贴屏顶、只占上半屏（下方大片空白），
/// 手机上却看起来是满的。
///
/// **根因**：横屏正方形图卡边长写成 `min(360.0, max(160.0, maxHeight * 0.85))`——
/// 360 是「720×720 素材在 DPR 2.0 下 1:1 不放大」的经验绝对值，**只读高度、与宽度
/// 无关**：平板 1280×800 时 0.85×800=680 被永久截到 360（内容块高 384 ≈ 屏高 48%）；
/// 手机 844×390 时 0.85×390=331.5 < 360 未触发封顶，所以「手机上看着是满的」。
/// 另有第二处缺陷：`Scaffold.body` 是宽松约束 + 顶对齐，横屏内容块没包 `Center`，
/// 即使图卡变大也仍然贴顶。
///
/// 本守卫按**真实渲染几何**（`tester.getSize` / `getRect`）钉死四条契约：
///  ① 平板横屏（1280×800）图卡高度 ≥ 屏高 × 0.80，且保持正方形；
///  ② 内容块垂直居中（图卡到上下边距之差 < 屏高 × 0.10）；
///  ③ 手机横屏（844×390）**零回归**：边长恰 331.5（旧实现同值，红线）；
///  ④ iPad 13 / iPad（1024×768）两档 smoke：图卡高度 ≥ 屏高 × 0.70；
///  ⑤ 竖屏兜底（390×844）：零溢出且图卡宽度 ≤ 屏宽。
///
/// ⚠️ 布局分支只看 `LayoutBuilder` 的 `c.maxWidth >= c.maxHeight`（不是
/// `MediaQuery.orientation`），把测试视口设成横屏尺寸即可进横屏分支，无需真旋转。
/// ⚠️ 护眼页内嵌 `FrameSequencePlayer` 的真实 720×720 帧位图在 flutter_tester 里真
/// 解码会 OOM（与 eye_care_page_test 同坑）：这里 mock `flutter/assets` 让加载失败，
/// 走 errorBuilder 占位——几何只看容器尺寸，不依赖位图。另 mock
/// `SystemChannels.platform` 吞掉 initState 的横屏指令（否则 MissingPluginException）。
/// ⚠️ 页面有周期 timer + 呼吸动画 → **禁用 pumpAndSettle**，一律有界 pump。
library eye_care_landscape_tablet_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

/// 只记录 `append` 的假账本（护眼卡退场才写；本文件不触发退场，防真库触库）。
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

/// 假护眼记录仓储（本文件不退场 → 不应被写；只防 provider 缺省触库）。
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

/// 把测试视口设成 [screen]（逻辑像素），并拦掉会炸测试的环境通道：
///  · `flutter/assets`：真实 720×720 帧位图真解码 → OOM（见库注释）；
///  · `flutter/platform`：护眼卡 initState 的横屏指令（无 handler 会抛
///    MissingPluginException）。
void _useScreen(WidgetTester tester, Size screen) {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final TestDefaultBinaryMessenger messenger =
      tester.binding.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/assets'),
    (MethodCall call) async => null, // 加载失败 → errorBuilder 占位
  );
  addTearDown(() =>
      messenger.setMockMethodCallHandler(const MethodChannel('flutter/assets'),
          null));

  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async => null,
  );
  addTearDown(() =>
      messenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

/// 有界收敛（护眼页有周期 timer + 呼吸动画 → 禁 pumpAndSettle）。
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 直接以护眼卡为 home 泵起来（不经过路由转场：本文件只量几何）。
Future<void> _pumpEyeCare(WidgetTester tester, Size screen) async {
  _useScreen(tester, screen);
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository(100)),
      eyeCareLogRepositoryProvider
          .overrideWithValue(_FakeEyeCareLogRepository()),
      audioServiceProvider.overrideWithValue(
        AudioService(playerFactory: () => null), // headless 无音频后端
      ),
    ],
    child: const MaterialApp(
      home: EyeCarePage(args: EyeCareArgs(skipAllowed: true)),
    ),
  ));
  await _settle(tester);
}

/// 图卡（正方形帧容器）的真实渲染尺寸。`FrameSequencePlayer` 内部是
/// `SizedBox.expand`，故它的 RenderBox 尺寸 == AspectRatio 盒尺寸。
Size _frameSize(WidgetTester tester) =>
    tester.getSize(find.byType(FrameSequencePlayer));

/// 量一张图卡并把实测值打进测试输出（复核用，非断言）。
void _log(String label, Size screen, Size frame, Rect rect) {
  debugPrint('[measure] $label screen=${screen.width}x${screen.height} '
      'frame=${frame.width.toStringAsFixed(2)}x${frame.height.toStringAsFixed(2)} '
      'heightRatio=${(frame.height / screen.height).toStringAsFixed(4)} '
      'top=${rect.top.toStringAsFixed(2)} '
      'bottom=${(screen.height - rect.bottom).toStringAsFixed(2)}');
}

void main() {
  testWidgets('1280×800 平板横屏：图卡吃满高度且保持正方形', (WidgetTester tester) async {
    const Size screen = Size(1280, 800);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('tablet-1280x800', screen, frame, tester.getRect(find.byType(FrameSequencePlayer)));

    expect(frame.height, greaterThanOrEqualTo(screen.height * 0.80),
        reason: '平板横屏图卡高度必须 ≥ 屏高 80%（旧实现被 360 绝对值截到 45%）');
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01),
        reason: '图卡必须保持正方形（AspectRatio 1:1）');
    expect(tester.takeException(), isNull, reason: '不得有布局溢出等异常');
  });

  testWidgets('1280×800 平板横屏：内容块垂直居中（不是贴顶）', (WidgetTester tester) async {
    const Size screen = Size(1280, 800);
    await _pumpEyeCare(tester, screen);

    final Rect rect = tester.getRect(find.byType(FrameSequencePlayer));
    final Size frame = rect.size;
    _log('tablet-1280x800-center', screen, frame, rect);

    final double topGap = rect.top;
    final double bottomGap = screen.height - rect.bottom;
    expect((topGap - bottomGap).abs(), lessThan(screen.height * 0.10),
        reason: '上下边距之差必须 < 屏高 10%（贴顶时差 = 屏高 - 内容高 ≈ 52%）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('844×390 手机横屏零回归：边长恰 331.5（与旧实现逐位一致）',
      (WidgetTester tester) async {
    const Size screen = Size(844, 390);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('phone-844x390', screen, frame, tester.getRect(find.byType(FrameSequencePlayer)));

    // 红线：0.85×390 = 331.5，旧实现（360 封顶未触发）同样是 331.5。
    expect(frame.height, moreOrLessEquals(331.5, epsilon: 0.5),
        reason: '手机横屏边长必须与改前逐位一致（零回归红线）');
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01));
    expect(tester.takeException(), isNull, reason: '手机横屏不得溢出');
  });

  testWidgets('1024×768 横屏 smoke：图卡 ≥ 屏高 70%、零异常', (WidgetTester tester) async {
    const Size screen = Size(1024, 768);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('ipad-1024x768', screen, frame, tester.getRect(find.byType(FrameSequencePlayer)));

    expect(frame.height, greaterThanOrEqualTo(screen.height * 0.70));
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1366×1024 横屏 smoke（iPad 13 寸）：图卡 ≥ 屏高 70%、零异常',
      (WidgetTester tester) async {
    const Size screen = Size(1366, 1024);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('ipad13-1366x1024', screen, frame, tester.getRect(find.byType(FrameSequencePlayer)));

    expect(frame.height, greaterThanOrEqualTo(screen.height * 0.70));
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1200×800 / 1194×834 两档复算 smoke：图卡 ≥ 屏高 70%、零异常',
      (WidgetTester tester) async {
    for (final Size screen in const <Size>[Size(1200, 800), Size(1194, 834)]) {
      await _pumpEyeCare(tester, screen);

      final Size frame = _frameSize(tester);
      _log('tablet-${screen.width.toInt()}x${screen.height.toInt()}', screen, frame,
          tester.getRect(find.byType(FrameSequencePlayer)));

      expect(frame.height, greaterThanOrEqualTo(screen.height * 0.70));
      expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('390×844 竖屏兜底：零溢出且图卡宽度 ≤ 屏宽', (WidgetTester tester) async {
    const Size screen = Size(390, 844);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('phone-portrait-390x844', screen, frame,
        tester.getRect(find.byType(FrameSequencePlayer)));

    expect(frame.width, lessThanOrEqualTo(screen.width));
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01));
    expect(tester.takeException(), isNull, reason: '竖屏兜底不得溢出（旧实现 340 已贴近上限）');
  });

  // 🔴 竖屏平板档（QA 复核 P2-1 补的盲区）：上面那条 390×844 只断言
  // `width <= 屏宽`，把竖屏公式改回写死 `340.0` 时它**照样全绿**（340 ≤ 390），
  // 等于没有守卫。竖屏兜底同样被这次缺陷波及：旧实现写死 340 → 平板竖屏
  // （800×1280）只占屏宽 42%，与「文字已按 1.3 倍放大」严重失衡。
  // 这里按派生公式**钉死具体数值**：`min(800×0.86, 1280×0.45) = 576`。
  testWidgets('800×1280 平板竖屏：图卡边长 = min(宽×0.86, 高×0.45) = 576',
      (WidgetTester tester) async {
    const Size screen = Size(800, 1280);
    await _pumpEyeCare(tester, screen);

    final Size frame = _frameSize(tester);
    _log('tablet-portrait-800x1280', screen, frame,
        tester.getRect(find.byType(FrameSequencePlayer)));

    // 高度侧 0.45 生效：1280×0.45 = 576 < 800×0.86 = 688。
    expect(frame.height, moreOrLessEquals(576.0, epsilon: 0.5),
        reason: '竖屏平板必须按派生公式取值（旧实现写死 340 = 屏宽 42%）');
    expect(frame.width, moreOrLessEquals(frame.height, epsilon: 0.01),
        reason: '竖屏同样必须保持正方形');
    // 派生值必须显著大于旧常量 340，防止「改回 340 但断言也放宽」的假绿。
    expect(frame.height, greaterThan(400.0),
        reason: '写死 340 的实现必须在这里变红');
    expect(tester.takeException(), isNull);
  });
}
