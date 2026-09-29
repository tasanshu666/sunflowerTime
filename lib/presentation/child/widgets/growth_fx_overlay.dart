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
///  · 卡片宽 = 屏幕短边 × [kGrowFxCardWidthRatio]，圆角 [kGrowFxCardRadius]；
///  · 卡内正方形区域播放 [frames]（每帧时长 = 音频时长 / 帧数，见
///    [FrameSequencePlayer]），播放**不遮挡花园**（无遮罩层）；
///  · 播完 → 整张卡 [kFxDisplayFadeOutMs] 淡出 → [onComplete]；
///  · 全程 `IgnorePointer`（不拦截点击）、总时长有限（可被 `pumpAndSettle` 结束）。
library growth_fx_overlay;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

// —— 奶油阳光风视觉常量（仅本组件使用，故就近定义；与 App 马卡龙/奶油风同源） ——

/// 卡底渐变：顶部奶白。
const Color kGrowFxCardTop = Color(0xFFFFFDF7);

/// 卡底渐变：底部奶油黄。
const Color kGrowFxCardBottom = Color(0xFFFFF2D9);

/// 卡片描边（暖黄，压住渐变边缘让卡片有「厚度」）。
const Color kGrowFxCardEdge = Color(0xFFFFE0A3);

/// 标题胶囊底色（与 `reward_card.dart` 的价格胶囊同色）。
const Color kGrowFxTagBg = Color(0xFFFFF1C2);

/// 标题胶囊文字色（深棕黄，暖色板上可读）。
const Color kGrowFxTagText = Color(0xFF8D6E00);

/// 外发光阴影（暖棕，替代纯黑阴影，避免发灰）。
const Color kGrowFxShadowWarm = Color(0x2E8D6E00);

/// 贴地阴影（极淡，给卡片落地感）。
const Color kGrowFxShadowDark = Color(0x14000000);

/// 卡内金色柔光（径向中心色，末端色为同 RGB 的 0 alpha 避免插出灰边）。
const Color kGrowFxGlowCore = Color(0x4DFFD77A);

/// 卡内金色柔光末端色。
const Color kGrowFxGlowEdge = Color(0x00FFD77A);

/// 弹入动画时长（毫秒）。
const int kGrowFxEnterMs = 360;

/// 卡内容区左右/上下内边距。
const double kGrowFxCardPadding = 14;

/// 卡内播放区圆角。
const double kGrowFxInnerRadius = 20;

/// 退场时缩到的比例（1.0 = 不缩小）。
const double kGrowFxExitScale = 0.94;

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
  /// 弹入控制器（一次性，[Curves.easeOutBack] 轻微回弹）。
  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kGrowFxEnterMs),
  );

  /// 整卡淡出控制器（播放段结束后启动）。
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kFxDisplayFadeOutMs),
  );

  /// 播放是否已结束（结束后卡片不再接收重建抖动）。
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl.addStatusListener(_onFadeStatus);
    unawaited(_enterCtrl.forward());
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (mounted) setState(() => _playing = false);
      widget.onComplete?.call();
    }
  }

  /// 序列帧播完 → 启动整卡淡出。
  void _onPlayComplete() {
    if (!mounted) return;
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.removeStatusListener(_onFadeStatus);
    _enterCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.shortestSide;
    final double cardW = screenW * kGrowFxCardWidthRatio;
    final double inner = cardW - kGrowFxCardPadding * 2;
    return IgnorePointer(
      child: Center(
        // 外层：弹入（缩放 + 淡入）。
        child: AnimatedBuilder(
          animation: _enterCtrl,
          builder: (BuildContext context, Widget? child) {
            final double enter =
                Curves.easeOutBack.transform(_enterCtrl.value).clamp(0.0, 1.2);
            return Opacity(
              opacity: _enterCtrl.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.86 + 0.14 * enter,
                child: child,
              ),
            );
          },
          // 内层：整卡淡出 + 轻微收拢。
          child: AnimatedBuilder(
            animation: _fadeCtrl,
            builder: (BuildContext context, Widget? child) {
              final double t = _fadeCtrl.value.clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - t,
                child: Transform.scale(
                  scale: 1 - (1 - kGrowFxExitScale) * t,
                  child: child,
                ),
              );
            },
            child: _card(cardW, inner),
          ),
        ),
      ),
    );
  }

  /// 奶油阳光卡：渐变底 + 暖黄描边 + 胶囊标题 + 金色柔光播放区。
  Widget _card(double cardW, double inner) {
    return Container(
      width: cardW,
      padding: const EdgeInsets.all(kGrowFxCardPadding),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[kGrowFxCardTop, kGrowFxCardBottom],
        ),
        border: Border.fromBorderSide(
          BorderSide(color: kGrowFxCardEdge, width: 2),
        ),
        borderRadius: BorderRadius.all(Radius.circular(kGrowFxCardRadius)),
        boxShadow: <BoxShadow>[
          // 暖棕外发光（主）+ 极淡贴地阴影（次），避免纯黑阴影把卡片压灰。
          BoxShadow(
            color: kGrowFxShadowWarm,
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: kGrowFxShadowDark,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.title != null) ...<Widget>[
            _tag(widget.title!),
            const SizedBox(height: 10),
          ],
          // 播放区：金色径向柔光打底，让透明底的植株「站在光里」。
          ClipRRect(
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
          ),
        ],
      ),
    );
  }

  /// 阳光黄胶囊标题。
  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: kGrowFxTagBg,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: kGrowFxTagText,
        ),
      ),
    );
  }
}
