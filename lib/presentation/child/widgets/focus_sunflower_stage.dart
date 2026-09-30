/// 专注页向日葵舞台（2026-09-29 玄参素材落地）。
///
/// 常态播放 idle 循环帧；收到上升沿信号时切换为一次性动画（播完自动回 idle）：
///  · [collectSignal] 上升沿 → 1/3（与 2/3）进度「收集阳光」帧（配 `focus_collect`）；
///  · [returnSignal]  上升沿 → 离席回来「欢迎」帧（配 `welcome_back`）。
///
/// ## 切换过渡（玄参 2026-09-30 拍板）
/// idle 作为**常驻底层**始终渲染；collect/welcome 触发时在上方**叠一层 transient**，
/// 用 [_xfade] 做交叉淡入淡出（idle 渐隐、新相位渐显），播完再交叉淡出回 idle，
/// 画面平滑过渡、不再硬切。
///
/// 帧目录与帧数见 `frame_sequence_player.dart`（kFocus*FxDir）/ `prd_params.dart`
/// （kFocus*FrameCount / kFocus*DurationMs）。舞台只负责「按相位换一组帧 + 过渡」，
/// 不感知业务事件来源。
library focus_sunflower_stage;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

/// 舞台相位。
enum FocusStagePhase { idle, collect, welcome }

/// 专注页向日葵舞台：idle 循环 + collect/welcome 一次性（交叉淡入淡出切换）。
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

class _FocusSunflowerStageState extends State<FocusSunflowerStage>
    with SingleTickerProviderStateMixin {
  /// 当前叠加层相位；[FocusStagePhase.idle] 表示无叠加层（仅常驻 idle 底层）。
  FocusStagePhase _transient = FocusStagePhase.idle;

  /// 交叉淡入淡出控制器（0 = idle 全显、1 = transient 全显）。
  late final AnimationController _xfade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kFocusTransientCrossfadeMs),
  );

  @override
  void didUpdateWidget(FocusSunflowerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 上升沿检测：回来优先于收集（二者同帧同时到达时的取舍）。
    if (widget.returnSignal && !oldWidget.returnSignal) {
      _trigger(FocusStagePhase.welcome);
    } else if (widget.collectSignal && !oldWidget.collectSignal) {
      _trigger(FocusStagePhase.collect);
    }
  }

  /// 触发一次性相位：挂上叠加层并交叉淡入（idle 同步交叉淡出，由 [_xfade] 驱动）。
  void _trigger(FocusStagePhase p) {
    if (!mounted) return;
    setState(() => _transient = p);
    // forward 从当前值继续：idle→触发 由 0→1；播放中重复触发（已=1）则为 no-op；
    // 淡出途中再触发会由当前值继续回到 1。
    _xfade.forward(from: _xfade.value);
  }

  /// 一次性相位播放结束：交叉淡出回 idle，淡出完成后卸载叠加层。
  void _onTransientPlayed() {
    final FocusStagePhase finished = _transient;
    _xfade.reverse().then((_) {
      // 仅在「没有中途被新的相位替换」时才回落为空闲层，避免 race 误清。
      if (mounted && _transient == finished) {
        setState(() => _transient = FocusStagePhase.idle);
      }
    });
  }

  @override
  void dispose() {
    _xfade.dispose();
    super.dispose();
  }

  List<String> _framesFor(FocusStagePhase p) {
    switch (p) {
      case FocusStagePhase.collect:
        return fxFrameAssets(kFocusCollectFxDir, kFocusCollectFrameCount);
      case FocusStagePhase.welcome:
        return fxFrameAssets(kFocusReturnFxDir, kFocusReturnFrameCount);
      case FocusStagePhase.idle:
        return const <String>[];
    }
  }

  int _durationMsFor(FocusStagePhase p) {
    switch (p) {
      case FocusStagePhase.collect:
        return kFocusCollectDurationMs;
      case FocusStagePhase.welcome:
        return kFocusReturnDurationMs;
      case FocusStagePhase.idle:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 常驻 idle 底层：xfade=0 时全显、=1 时完全隐藏（让位给 transient）。
    final Widget idleLayer = FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_xfade),
      child: FrameSequencePlayer(
        // 稳定 key：idle 层生命周期与舞台一致，不随相位切换重建。
        key: const ValueKey<String>('idle'),
        frames: fxFrameAssets(kFocusIdleFxDir, kFocusIdleFrameCount),
        durationMs: kFocusIdleLoopDurationMs,
        loop: true,
      ),
    );

    Widget? transientLayer;
    if (_transient != FocusStagePhase.idle) {
      // 叠加层：xfade=1 时全显。淡出完全交给舞台交叉淡出，故 fadeOutMs=0，
      // 避免「transient 自己先淡出露出底色、再弹回 idle」的双重淡出硬感。
      transientLayer = FadeTransition(
        opacity: _xfade,
        child: FrameSequencePlayer(
          key: ValueKey<FocusStagePhase>(_transient),
          frames: _framesFor(_transient),
          durationMs: _durationMsFor(_transient),
          loop: false,
          fadeOutMs: 0,
          onComplete: _onTransientPlayed,
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: <Widget>[
          idleLayer,
          if (transientLayer != null) transientLayer,
        ],
      ),
    );
  }
}
