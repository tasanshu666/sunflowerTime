/// 专注页向日葵舞台（2026-09-29 玄参素材落地）。
///
/// 常态播放 idle 循环帧；收到上升沿信号时切换为一次性动画（播完自动回 idle）：
///  · [collectSignal] 上升沿 → 1/3（与 2/3）进度「收集阳光」帧（配 `focus_collect`）；
///  · [returnSignal]  上升沿 → 离席回来「欢迎」帧（配 `welcome_back`）。
///
/// 帧目录与帧数见 `frame_sequence_player.dart`（kFocus*FxDir）/ `prd_params.dart`
/// （kFocus*FrameCount / kFocus*DurationMs）。舞台只负责「按相位换一组帧」，
/// 不感知业务事件来源。
library focus_sunflower_stage;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

/// 舞台相位。
enum FocusStagePhase { idle, collect, welcome }

/// 专注页向日葵舞台：idle 循环 + collect/welcome 一次性。
class FocusSunflowerStage extends StatefulWidget {
  const FocusSunflowerStage({
    super.key,
    required this.collectSignal,
    required this.returnSignal,
    this.size = 320,
  });

  /// 收集阳光触发信号（**true 的上升沿**触发一次 collect）。
  final bool collectSignal;

  /// 回来触发信号（**true 的上升沿**触发一次 welcome）。
  final bool returnSignal;

  /// 舞台边长（逻辑像素）。
  final double size;

  @override
  State<FocusSunflowerStage> createState() => _FocusSunflowerStageState();
}

class _FocusSunflowerStageState extends State<FocusSunflowerStage> {
  FocusStagePhase _phase = FocusStagePhase.idle;

  @override
  void didUpdateWidget(FocusSunflowerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 上升沿检测：回来优先于收集（二者同帧同时到达时的取舍）。
    if (widget.returnSignal && !oldWidget.returnSignal) {
      _phase = FocusStagePhase.welcome;
    } else if (widget.collectSignal && !oldWidget.collectSignal) {
      _phase = FocusStagePhase.collect;
    }
    // 此处无需 setState：didUpdateWidget 之后必然跟随一次 build。
  }

  void _backToIdle() {
    if (mounted) setState(() => _phase = FocusStagePhase.idle);
  }

  @override
  Widget build(BuildContext context) {
    late final List<String> frames;
    late final int durationMs;
    late final bool loop;
    late final VoidCallback? onComplete;
    switch (_phase) {
      case FocusStagePhase.idle:
        frames = fxFrameAssets(kFocusIdleFxDir, kFocusIdleFrameCount);
        durationMs = kFocusIdleLoopDurationMs;
        loop = true;
        onComplete = null;
      case FocusStagePhase.collect:
        frames = fxFrameAssets(kFocusCollectFxDir, kFocusCollectFrameCount);
        durationMs = kFocusCollectDurationMs;
        loop = false;
        onComplete = _backToIdle;
      case FocusStagePhase.welcome:
        frames = fxFrameAssets(kFocusReturnFxDir, kFocusReturnFrameCount);
        durationMs = kFocusReturnDurationMs;
        loop = false;
        onComplete = _backToIdle;
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FrameSequencePlayer(
        // 相位变化即换 key → 重建播放器（新一组帧从头播）。
        key: ValueKey<FocusStagePhase>(_phase),
        frames: frames,
        durationMs: durationMs,
        loop: loop,
        onComplete: onComplete,
      ),
    );
  }
}
