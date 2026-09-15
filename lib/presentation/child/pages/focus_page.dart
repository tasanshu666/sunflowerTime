import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

/// S3 打盹屏专注页（最小实现）：横屏 + 计时 + 常亮保持 + 方向锁。
///
/// 验收（真机）：常亮稳定（国内 ROM 省电可能杀常亮，3–5 台连跑 30–60min 验证）；
/// 计时在灭屏恢复后不漂移。
///
/// 计时用「墙钟差」而非 tick 计数：灭屏期间系统时间仍走，恢复后 elapsed 自然连续，
/// 不依赖后台计时器（C3 / 验证计划 §2.5 / 架构 §1.3）。
class FocusPage extends StatefulWidget {
  final int plannedMinutes;

  const FocusPage({super.key, this.plannedMinutes = 20});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late DateTime _startTime;
  late final Duration _planned;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  StreamSubscription<NativeDeviceOrientation>? _orientSub;
  bool _paused = false;
  bool _finished = false;

  /// 方向宽限期截止时刻：抑制「传感器订阅首帧回调」与进入瞬间的方向抖动。
  late DateTime _graceUntil;

  /// 「已武装」标记：必须先观察到一次**横屏**，之后的竖屏才视为中途退出意图。
  ///
  /// 传感器模式在订阅瞬间即回调当前物理方向，孩子竖握手机进入时首帧就是
  /// portrait —— 不武装就会误弹「确定结束吗？」（真机实测 B18）。
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _planned = Duration(minutes: widget.plannedMinutes);
    _graceUntil =
        _startTime.add(const Duration(seconds: kOrientationGraceSeconds));
    _enterFocusMode();
  }

  Future<void> _enterFocusMode() async {
    // 常亮保持（P6 风险：国内 ROM 省电可能杀常亮，待真机验证）
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    // 锁横屏 + 隐藏系统 UI（沉浸）
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _orientSub = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true) // 传感器模式：物理方向，不受 SystemChrome 横屏锁影响
        .listen(_onOrientation);
  }

  void _tick() {
    if (_paused || _finished) return;
    final e = DateTime.now().difference(_startTime); // 墙钟差：灭屏恢复不漂移
    if (mounted) setState(() => _elapsed = e);
    if (e >= _planned) _finish();
  }

  void _onOrientation(NativeDeviceOrientation orient) {
    if (_finished) return;
    // 宽限期内一律忽略：传感器订阅首帧会立刻回调当前物理方向，
    // 孩子竖握手机进入打盹屏时首帧即 portrait，不应视为退出意图（B18）。
    if (DateTime.now().isBefore(_graceUntil)) return;

    final isLandscape =
        orient == NativeDeviceOrientation.landscapeLeft ||
            orient == NativeDeviceOrientation.landscapeRight;
    if (isLandscape) {
      // 已确认横屏放置 → 武装，此后出现的竖屏才算「中途退出意图」
      _armed = true;
      return;
    }

    final isPortrait = orient == NativeDeviceOrientation.portraitUp ||
        orient == NativeDeviceOrientation.portraitDown;
    // 物理竖屏 = 中途退出意图（PRD §4.1.6 退出路径）：暂停 + 确认。
    // 仅在「已武装」后生效，避免进入瞬间误弹。
    if (isPortrait && _armed) {
      _requestExit();
    }
  }

  /// 退出意图的统一入口：暂停 + 「确定结束吗？」确认框。
  ///
  /// 两类触发共用（架构 §1.3：「竖屏动作（物理竖屏 OR 手动退出）→ 暂停+确认」）：
  /// ① 物理竖屏（PRD §4.1.6）；② Android 返回键（手动退出）。
  /// 打盹屏本身不提供任何可点控件（§4.1）。
  void _requestExit() {
    if (_finished || _paused) return; // 已在确认中/已结束则不重复弹
    setState(() => _paused = true);
    _showExitConfirm();
  }

  void _showExitConfirm() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('确定结束吗？'),
        content: const Text('向日葵还在这儿陪着你，要现在结束专注吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resume();
            },
            child: const Text('再坐一会'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _finish();
            },
            child: const Text('结束'),
          ),
        ],
      ),
    );
  }

  void _resume() {
    // 保留已专注时长，把基准时间回拨，避免竖屏期间被计入
    _startTime = DateTime.now().subtract(_elapsed);
    setState(() => _paused = false);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    _orientSub?.cancel();
    _restoreSystemChrome();
    if (mounted) {
      // 回孩子端首页（M1 在此接入结算动画）。
      //
      // ⚠️ 必须用 `go('/')` 而非 `Navigator.pop()`：打盹屏是经 `go('/focus')`
      // 进入的，go_router 的 go 是**替换路由栈**而非入栈，`/` 已不在栈中，
      // pop 会把最后一个页面弹掉 → 黑屏（真机实测 B20）。
      context.go('/');
    }
  }

  void _restoreSystemChrome() {
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]); // 复位方向
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _orientSub?.cancel();
    _restoreSystemChrome();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final remaining = _planned - _elapsed;
    final showRemaining = remaining > Duration.zero ? remaining : Duration.zero;
    // 打盹屏经 go('/focus') 进入 = 路由栈底，不拦的话 Android 返回键会直接退出 App。
    // 按架构 §1.3，「手动退出」与物理竖屏同路：暂停 + 确认框。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _requestExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B1B2F), // 低亮深色打盹屏底
        body: Stack(
          alignment: Alignment.center,
          children: [
            // 中央：在做自己事的花（呼吸式明暗，零突事件）
            const SunflowerCanvas(level: FeedbackLevel.lvl1),
            // 顶部：本次倒计时（只留倒计时，不显示阳光池数字，PRD §4.2）
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Text(
                '本次 ${_fmt(_elapsed)} / ${_fmt(_planned)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 22,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            // 底部：本屏不可交互提示
            const Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Text(
                '本屏不可交互 · 竖屏即可结束',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF616161), fontSize: 14),
              ),
            ),
            // 暂停遮罩
            if (_paused)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Text('已暂停',
                      style: TextStyle(color: Colors.white, fontSize: 28)),
                ),
              ),
            // 真机调试用：剩余时间小字（产品页将移除）
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Text(
                '剩余 ${_fmt(showRemaining)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
