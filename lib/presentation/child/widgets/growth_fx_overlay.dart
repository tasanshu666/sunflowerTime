/// 成长（升级）演出：**屏幕中央焦点卡片**（玄参 2026-09-29 拍板）。
///
/// ## 为什么独立成组件
/// 原实现把成长帧按「花盆格位置 ×1.4」就地放大播放 —— 玄参实测：格子太小看不清、
/// 且和底层花盆重叠显得乱。新口径：**画面正中弹出一张卡片，卡内放大播放成长
/// 序列帧（焦点演出），播完整卡淡出消失**，回到花园。
///
/// ## 视觉（2026-09-29 玄参反馈「纯白底很难看」后重做）
/// 弃用纯白，改与 App 其余卡片同语言的**奶油阳光风**：
///  · 卡底：奶白 → 奶油黄竖向渐变 + 暖黄描边（不再是刺眼的白色块）；
///  · 卡内播放区：**金色径向柔光**，透明底的植株看起来站在光里而非贴在白纸上；
///  · 标题：阳光黄胶囊标签（色值与 `reward_card.dart` 一致）；
///  · 入场：轻微弹入（缩放 + 淡入，[Curves.easeOutBack]），退场：淡出并轻微收拢。
///
/// ## 行为
///  · 卡片宽 = 屏幕短边 × [kGrowFxCardWidthRatio]，**平板钳到 [kGrowFxCardMaxWidth]**
///    （见 [growFxCardWidthOf]；C61 平板适配），圆角 [kGrowFxCardRadius]；
///  · 卡内正方形区域播放 [frames]（每帧时长 = 音频时长 / 帧数，见
///    [FrameSequencePlayer]），播放**不遮挡花园**（无遮罩层）；
///  · 播完 → 整张卡 [kFxDisplayFadeOutMs] 淡出 → [onComplete]；
///  · 全程 `IgnorePointer`（不拦截点击）、总时长有限（可被 `pumpAndSettle` 结束）。
///
/// ## C74 重构说明（2026-10-14，设计 §5.24.6 / Q-K）
/// 卡体与进出场包络已抽到 [`fx_card_shell.dart`]（`FxCardShell` + `FxCardEnvelope`），
/// 本文件只剩「序列帧播放区」这一块内容。**视觉零变化**：色值原值搬迁、widget 树
/// 逐层一致（`test/m3/growth_fx_overlay_test.dart` 等既有用例锁定）。
library growth_fx_overlay;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/fx_card_shell.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 成长演出：中央卡片 + 序列帧 + 弹入 / 播完淡出。
class GrowthFxOverlay extends StatefulWidget {
  const GrowthFxOverlay({
    super.key,
    required this.frames,
    required this.durationMs,
    this.title,
    this.onComplete,
  });

  /// 序列帧路径列表（顺序即播放顺序）。
  final List<String> frames;

  /// 播放时长（毫秒）= 对应成长音频时长。
  final int durationMs;

  /// 卡片顶部标题文案（如「长大啦！🌿」）；为 null 时不显示。
  final String? title;

  /// 演出（播放 + 淡出）全部结束回调，供调用方移除本组件。
  final VoidCallback? onComplete;

  @override
  State<GrowthFxOverlay> createState() => _GrowthFxOverlayState();
}

class _GrowthFxOverlayState extends State<GrowthFxOverlay>
    with TickerProviderStateMixin {
  /// 进出场包络（弹入 + 整卡淡出），与 C74 升级演出共用同一个实现。
  late final FxCardEnvelope _envelope = FxCardEnvelope(
    vsync: this,
    onComplete: _onFinished,
  );

  /// 播放是否已结束（结束后卡片不再接收重建抖动）。
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _envelope.startEnter();
  }

  @override
  void dispose() {
    _envelope.dispose();
    super.dispose();
  }

  void _onFinished() {
    if (mounted) setState(() => _playing = false);
    widget.onComplete?.call();
  }

  /// 序列帧播完 → 启动整卡淡出。
  void _onPlayComplete() {
    if (!mounted) return;
    _envelope.fadeOut();
  }

  @override
  Widget build(BuildContext context) {
    // C61 平板适配：手机 = 原值（390 → 304.2），平板钳到 kGrowFxCardMaxWidth
    // （800 → 360；原 624 会让卡内播放区 596² 糊满整屏）。
    final double screenW = MediaQuery.sizeOf(context).shortestSide;
    final double cardW = growFxCardWidthOf(screenW);
    final double inner = cardW - kGrowFxCardPadding * 2;
    return IgnorePointer(
      child: Center(
        child: _envelope.wrap(
          FxCardShell(
            width: cardW,
            title: widget.title,
            child: _playArea(inner),
          ),
        ),
      ),
    );
  }

  /// 卡内播放区：金色径向柔光打底，让透明底的植株「站在光里」。
  Widget _playArea(double inner) {
    return ClipRRect(
      borderRadius:
          const BorderRadius.all(Radius.circular(kGrowFxInnerRadius)),
      child: SizedBox(
        width: inner,
        height: inner,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.08),
              radius: 0.72,
              colors: <Color>[kGrowFxGlowCore, kGrowFxGlowEdge],
            ),
          ),
          child: _playing
              ? FrameSequencePlayer(
                  frames: widget.frames,
                  durationMs: widget.durationMs,
                  fadeOutMs: 0, // 淡出由**整卡**统一处理
                  onComplete: _onPlayComplete,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
