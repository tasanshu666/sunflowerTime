/// 演出**共享卡体**（奶油阳光风）+ 共享**包络**（弹入 / 停留 / 淡出）。
///
/// ## 为什么抽这个文件（设计 §5.24.6 · Q-K）
/// 成长演出（[`growth_fx_overlay.dart`]）与 C74 升级演出都想要同一张卡：奶油渐变底 +
/// 暖黄描边 + 圆角 + 暖棕外发光 + 胶囊标题 + `Curves.easeOutBack` 弹入 + 整卡淡出。
/// 若不共享，第二处必然**复制色值** → 孪生（宪法总纪律 #2）。
///
/// ## 🔴 抽取纪律：**零视觉变化**
///  · 视觉常量从 `growth_fx_overlay.dart` **原值搬迁**（一个色值都没改），
///    既有 `test/m3/growth_fx_overlay_test.dart` / `test/m3/fx_frame_assets_guard_test.dart`
///    与 `tablet_adaptation_test.dart` 必须全绿；
///  · 包络（[FxCardEnvelope]）与卡体（[FxCardShell]）抽出后，成长演出的 widget 树
///    与原先**逐层一致**（外层弹入 → 内层淡出 → 卡片 Container → Column）。
///
/// ## 本文件不承担的东西
/// 具体内容（序列帧播放区 / 升级徽章）由调用方作为 `child` 传入 —— 本文件只管
/// **外观骨架**与**进出场节奏**，两处演出共用同一份。
library fx_card_shell;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/shared/responsive.dart';

// —— 奶油阳光风视觉常量（原 `growth_fx_overlay.dart` 就近定义，本轮**原值搬迁**至此）——
//
// ⚠️ 这是唯一真源：成长演出与升级演出都引用本段，改这里会同时影响两处演出。

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

/// 标题与内容之间的垂直间距。
const double kGrowFxTagGap = 10;

/// 演出卡**共享外观骨架**：渐变底 + 暖黄描边 + 圆角 + 暖棕外发光 + 胶囊标题 + 内容。
///
/// * [width] 省略时按 `shortestSide × kGrowFxCardWidthRatio`（平板钳
///   [kGrowFxCardMaxWidth]）自算（见 [growFxCardWidthOf]；C61 平板适配）；
/// * [title] 为 null 时不渲染标题胶囊；
/// * [child] 为卡内容（成长演出 = 序列帧播放区；升级演出 = 等级徽章内容）。
///
/// 🔴 抽出后 `growth_fx_overlay` 的卡片 Container 结构**逐位未变**（同一 decoration、
/// 同一 padding、Column 同一顺序），视觉零变化。
class FxCardShell extends StatelessWidget {
  const FxCardShell({
    super.key,
    this.width,
    this.title,
    required this.child,
  });

  /// 卡宽（≤ 0 或省略 → 按屏幕短边自算）。
  final double? width;

  /// 顶部胶囊标题文案（null = 不显示）。
  final String? title;

  /// 卡内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double cardW =
        width ?? growFxCardWidthOf(MediaQuery.sizeOf(context).shortestSide);
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
          if (title != null) ...<Widget>[
            fxCardTag(title!),
            const SizedBox(height: kGrowFxTagGap),
          ],
          child,
        ],
      ),
    );
  }
}

/// 阳光黄胶囊标题（与 `reward_card.dart` 的价格胶囊同语言）。
Widget fxCardTag(String text) => Container(
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

/// 演出**进出场包络**：弹入（`Curves.easeOutBack`）→ 停留 → 整卡淡出 + 轻微收拢。
///
/// 两种触发方式共用同一对外层/内层控制器：
///  · **内容驱动**（成长演出）：序列帧播完 → 调用方 [fadeOut]；
///  · **时长驱动**（C74 升级演出）：[startEnter] 后调用 [scheduleAutoFadeOut]，
///    弹入结束 + 停留 `holdMs` 后自动淡出。
///
/// 淡出结束回吐 [onComplete]（**恰好一次**，深层调用 Hosting State 的 dispose 后不再回吐）。
class FxCardEnvelope {
  FxCardEnvelope({
    required TickerProvider vsync,
    this.onComplete,
    int enterMs = kGrowFxEnterMs,
    int fadeOutMs = kFxDisplayFadeOutMs,
  })  : _enterCtrl = AnimationController(
          vsync: vsync,
          duration: Duration(milliseconds: enterMs),
        ),
        _fadeCtrl = AnimationController(
          vsync: vsync,
          duration: Duration(milliseconds: fadeOutMs),
        ),
        _enterMs = enterMs {
    _fadeCtrl.addStatusListener(_onFadeStatus);
  }

  final AnimationController _enterCtrl;
  final AnimationController _fadeCtrl;
  final int _enterMs;

  /// 淡出全部结束的回调（= 演出结束；调用方据此移除浮层）。
  VoidCallback? onComplete;

  Timer? _autoFadeTimer;
  bool _completed = false;

  Animation<double> get enter => _enterCtrl;
  Animation<double> get fade => _fadeCtrl;

  /// 起手弹入（一次性；fire-and-forget，不 await）。
  void startEnter() => unawaited(_enterCtrl.forward());

  /// 内容播完 → 整卡淡出（幂等：重复调用只生效第一次）。
  void fadeOut() {
    if (_fadeCtrl.isAnimating || _fadeCtrl.isCompleted) return;
    unawaited(_fadeCtrl.forward());
  }

  /// 时长驱动：弹入 + 停留 [holdMs] 后自动淡出（C74 升级演出用）。
  void scheduleAutoFadeOut(int holdMs) {
    _autoFadeTimer?.cancel();
    _autoFadeTimer =
        Timer(Duration(milliseconds: _enterMs + holdMs), fadeOut);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_completed) return; // 严格一次
    _completed = true;
    onComplete?.call();
  }

  /// 包络包裹 [child] → 双层 AnimatedBuilder（外层弹入 / 内层淡出），
  /// 与抽取前 `growth_fx_overlay` 的树**逐层一致**。
  Widget wrap(Widget child) {
    return AnimatedBuilder(
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
        child: child,
      ),
    );
  }

  /// 释放（必须由宿主 State 的 dispose 调用，否则控制器泄漏）。
  void dispose() {
    _autoFadeTimer?.cancel();
    _autoFadeTimer = null;
    _fadeCtrl.removeStatusListener(_onFadeStatus);
    _enterCtrl.dispose();
    _fadeCtrl.dispose();
  }
}
