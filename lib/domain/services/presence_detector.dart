/// 在场检测 PresenceDetector（T07）。
///
/// 输入：屏幕状态（`WidgetsBindingObserver.didChangeAppLifecycleState`，
/// Android 灭屏会让 App 进入 inactive/paused）+ 物理方向（`native_device_orientation`
/// 的**传感器模式** `onOrientationChanged(useSensor: true)`）+ 预留「长时间无触摸」信号。
///
/// 输出**两路独立信号**（不要混为一谈）：
/// - 离席 / 恢复：`onAbsent` / `onPresent`（灭屏→离席；亮屏→恢复在场，PRD §4.3 / §6.2）；
/// - 竖屏退出意图：`onPortraitIntent`（PRD §4.1.6，走「暂停 + 确认框」，**不是**离席）。
///
/// 核心判定抽成纯函数 [classifyPresence] / [classifyOrientation]，便于单测。
library presence_detector;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';

/// 在场信号。
enum ScreenPresence { present, absent }

/// 竖屏退出意图信号。
enum OrientationIntent { none, portraitExitIntent }

/// 纯判定：生命周期状态 → 在场 / 离席（**灭屏 = 离席**，PRD §4.3 / §6.2 基线）。
///
/// 仅 `resumed` 视为在场；`inactive` / `paused` / `hidden` / `detached` 一律视为离席
/// （Android 灭屏会依次进入 inactive→paused）。本工程**不实现**「灭屏继续计时产出」。
ScreenPresence classifyPresence(AppLifecycleState state) =>
    state == AppLifecycleState.resumed
        ? ScreenPresence.present
        : ScreenPresence.absent;

/// 纯判定：物理方向 + 武装 + 宽限期 → 竖屏退出意图（PRD §4.1.6，真机 B18）。
///
/// [armed] 必须先观察到一次横屏后才为 true；[withinGrace] 为进入瞬间的抑制窗口。
OrientationIntent classifyOrientation({
  required bool isPortrait,
  required bool armed,
  required bool withinGrace,
}) {
  if (withinGrace || !armed) return OrientationIntent.none;
  return isPortrait ? OrientationIntent.portraitExitIntent : OrientationIntent.none;
}

/// 在场检测器：桥接 Flutter 生命周期与物理方向，向专注页回传三路信号。
///
/// 用法：`PresenceDetector(...).start()` 于打盹屏 `initState`；`stop()` 于 `dispose`。
class PresenceDetector with WidgetsBindingObserver {
  PresenceDetector({
    this.onAbsent,
    this.onPresent,
    this.onPortraitIntent,
    Duration grace = const Duration(seconds: kOrientationGraceSeconds),
    this.touchTimeoutEnabled = false,
    DateTime Function()? clock,
  })  : _grace = grace,
        _clock = clock ?? DateTime.now;

  /// 灭屏 / 离席回调（PRD §4.3）。
  final void Function()? onAbsent;

  /// 亮屏 / 恢复在场回调（PRD §4.3）。
  final void Function()? onPresent;

  /// 物理竖屏退出意图回调（PRD §4.1.6，走「暂停 + 确认框」）。
  final void Function()? onPortraitIntent;

  /// 「长时间无触摸」信号开关：**M1 默认关闭**（PRD §4.3 三信号之「无触摸」）。
  ///
  /// 关闭理由：打盹屏本屏不可交互（PRD §4.1.2 / §4.2「本屏不可交互」），
  /// 缺少有效触摸输入源，该信号在 MVP 基线无法获得可靠输入；留作后续增强接口。
  final bool touchTimeoutEnabled;

  final Duration _grace;
  final DateTime Function() _clock;

  StreamSubscription<NativeDeviceOrientation>? _sub;
  DateTime? _graceUntil;
  Timer? _portraitTimer; // 竖屏退出定时器（B26 去抖 + B31 修复）
  bool _portraitFired = false; // 本次「竖屏持有」是否已触发过（防重复弹框）
  bool _armed = false;
  bool _started = false;
  bool _lastPresent = true;

  /// 开始监听（注册生命周期观察者 + 订阅物理方向传感器流）。
  void start() {
    if (_started) return;
    _started = true;
    _graceUntil = _clock().add(_grace);
    WidgetsBinding.instance.addObserver(this);
    _sub = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true) // 传感器模式：物理方向，不受横屏锁影响（B12）
        .listen(_onOrientation);
    // touchTimeout 信号预留：M1 默认关闭，见 touchTimeoutEnabled 说明。
  }

  /// 停止监听并释放资源。
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    _cancelPortraitTimer();
  }

  void _cancelPortraitTimer() {
    _portraitTimer?.cancel();
    _portraitTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ScreenPresence presence = classifyPresence(state);
    if (presence == ScreenPresence.absent) {
      if (_lastPresent) {
        _lastPresent = false;
        onAbsent?.call();
      }
    } else {
      if (!_lastPresent) {
        _lastPresent = true;
        onPresent?.call();
      }
    }
  }

  void _onOrientation(NativeDeviceOrientation orient) {
    // 宽限期一律忽略：抑制传感器订阅首帧回调与进场抖动（B18）。
    final DateTime now = _clock();
    if (_graceUntil != null && now.isBefore(_graceUntil!)) return;

    final bool isLandscape = orient == NativeDeviceOrientation.landscapeLeft ||
        orient == NativeDeviceOrientation.landscapeRight;
    if (isLandscape) {
      // 已确认横屏放置 → 武装（B18）；同时取消竖屏定时器并复位已触发标记，
      // 之后回到竖屏需重新计时（B26 防误弹 / B31 复位可重触）。
      _armed = true;
      _cancelPortraitTimer();
      _portraitFired = false;
      return;
    }

    final bool isPortrait = orient == NativeDeviceOrientation.portraitUp ||
        orient == NativeDeviceOrientation.portraitDown;
    if (!isPortrait) {
      // 非横非竖（unknown/faceUp/faceDown）：取消竖屏定时器，不触发。
      _cancelPortraitTimer();
      return;
    }

    if (!_armed) {
      // 尚未观察到横屏：不算「中途退出意图」，取消计时。
      _cancelPortraitTimer();
      return;
    }

    // 竖屏退出意图（B26 去抖 + B31 关键修复）：
    // `native_device_orientation` 在手机**静止后不再回调** orientation 事件，
    // 旧方案依赖「连续事件里重新计算时长」永远达不成 → 静止竖放不弹确认框。
    // 改为：首次观察到竖屏即起一个 kPortraitExitDebounceSeconds 的定时器，
    // 到点必触发 onPortraitIntent；重复 portrait 不重置定时器（防抖动连发），
    // 任何 landscape / 非横非竖都取消定时器（防晃动误弹）。_portraitFired 保证
    // 一次「竖屏持有」只弹一次，用户 resume 后需先回横屏才能再次触发。
    if (_portraitTimer == null && !_portraitFired) {
      _portraitTimer = Timer(
        Duration(milliseconds: (kPortraitExitDebounceSeconds * 1000).round()),
        () {
          _portraitTimer = null;
          _portraitFired = true;
          onPortraitIntent?.call();
        },
      );
    }
  }
}
