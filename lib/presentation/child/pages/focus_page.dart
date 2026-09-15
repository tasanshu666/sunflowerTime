import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _planned = Duration(minutes: widget.plannedMinutes);
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
    final isPortrait = orient == NativeDeviceOrientation.portraitUp ||
        orient == NativeDeviceOrientation.portraitDown;
    // 物理竖屏 = 中途退出意图（PRD §4.1.6 退出路径）：暂停 + 确认
    if (isPortrait && !_paused) {
      setState(() => _paused = true);
      _showExitConfirm();
    }
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
      // 结算动画占位：回到上一页（M1 接入结算动画）
      Navigator.of(context).pop();
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
    return Scaffold(
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
    );
  }
}
