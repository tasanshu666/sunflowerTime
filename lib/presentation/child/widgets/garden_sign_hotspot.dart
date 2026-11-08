/// 花园木牌的可点击热区 + 轻微呼吸高亮 + **本地化文字**（2026-09-24 v3 / 2026-11-06 无字版）。
///
/// ## 职责
/// 背景图上有一块木牌，玄参大人要求它**可点击**并弹出「玩法说明」（原来贴底的
/// 半透明白块文案收进该弹窗）。本组件负责「热区 + 按下反馈 + 呼吸高亮 +
/// **牌面文字**」，弹窗内容由调用方（`GardenPage._showGardenHelp` → `GardenHelpSheet`）给出。
///
/// ## 为什么牌面文字在代码里画（2026-11-06，玄参拍板方案 B）
/// 旧背景图把「玩法」二字**烤死**在图里，换语言不跟着变。新图（无字版）木牌留白，
/// 本组件按 `label` 参数在牌面中央叠加本地化文字（zh「玩法」/ en "PLAY"）——
/// 一张图永久用，以后改文案不用再找美术。文字用 [FittedBox] 自适应，并按牌面
/// 透视角度整体倾斜（见 [kGardenSignLabelTiltRadians]）。
///
/// ## 位置由调用方给定（不在组件内再算一遍）
/// 木牌在屏幕上的矩形由 `garden_background_layout.dart` 的 [gardenSignScreenRect] 算出，
/// 调用方用 `Positioned.fromRect(rect: ...)` 摆放。组件内部**不再计算 cover 映射**，
/// 避免两处口径漂移。
///
/// ## 测试陷阱（务必牢记）
/// 无限重复的呼吸动画会让 `tester.pumpAndSettle()` **永不返回**（测试超时失败）。
/// 故 [GardenSignHotspot.animate] 提供关停开关：widget 测试传 `false`，花园页默认 `true`。
library garden_sign_hotspot;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 牌面文字的**倾斜角** = **-7.6°**（弧度；负值 = 逆时针 = 左低右高）。
///
/// 测量依据（2026-11-06，无字版 background.jpg 牌面 flood-fill 后按列拟合）：
///  · 牌面**顶边**斜率 -0.1111（= -6.34°）；
///  · 牌面**底边**斜率 -0.1582（= -8.99°）；
///  · 牌面是透视梯形（非平行四边形），文字取两边的**均值** -7.6° 最不违和。
const double kGardenSignLabelTiltRadians = -7.6 * math.pi / 180;

/// 背景图木牌的点击热区（含牌面文字 + 按下缩放 + 呼吸光晕）。
class GardenSignHotspot extends StatefulWidget {
  const GardenSignHotspot({
    super.key,
    required this.onTap,
    this.label,
    this.animate = true,
  });

  /// 点击木牌的回调（花园页里打开「玩法说明」弹窗）。
  final VoidCallback onTap;

  /// 牌面中央叠加的本地化文字（zh「玩法」/ en "PLAY"）。
  ///
  /// `null` 时不渲染文字层（旧图带字时代的行为，向后兼容）。
  final String? label;

  /// 是否执行呼吸动画。
  ///
  /// `false` 时**不创建、不启动** `AnimationController`（`dispose` 亦安全）——
  /// widget 测试需要它，避免 `pumpAndSettle` 永不返回。
  final bool animate;

  @override
  State<GardenSignHotspot> createState() => _GardenSignHotspotState();
}

class _GardenSignHotspotState extends State<GardenSignHotspot>
    with SingleTickerProviderStateMixin {
  /// 光晕不透明度呼吸区间（**轻微**即可，不抢戏）。
  static const double _glowMinOpacity = 0.06;
  static const double _glowMaxOpacity = 0.22;

  /// 按下缩放比例（轻微回弹反馈）。
  static const double _pressedScale = 0.94;

  /// 呼吸光晕的倾斜角（微微贴合牌面透视）。
  static const double _glowTiltRadians = -0.10;

  /// 呼吸周期（秒）。
  static const Duration _breathPeriod = Duration(seconds: 2);

  /// 呼吸控制器；`animate == false` 时为 null（不创建 / 不启动）。
  AnimationController? _controller;

  /// 按下反馈状态（驱动 [AnimatedScale]）。
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant GardenSignHotspot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncController();
  }

  /// 依据 [GardenSignHotspot.animate] 创建 / 销毁呼吸控制器。
  void _syncController() {
    if (widget.animate) {
      _controller ??= AnimationController(
        vsync: this,
        duration: _breathPeriod,
      )..repeat(reverse: true);
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    // 安全：`animate == false` 时 [AnimationController] 为 null，`?.` 保证不崩。
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? _pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Stack(
          // StackFit.expand：让子层填满热区矩形（`Positioned.fromRect` 已给定边界）。
          fit: StackFit.expand,
          children: <Widget>[
            _buildGlow(),
            if (widget.label != null) _buildLabel(),
          ],
        ),
      ),
    );
  }

  /// 牌面文字层（[GardenSignHotspot.label] 非空时渲染）。
  ///
  /// 深棕字压亮橙牌面（对比足够，无需描边）；整体按 [kGardenSignLabelTiltRadians]
  /// 倾斜以贴合牌面透视；[FittedBox] 等比缩放兜底——基准字号 34 下 zh「玩法」/
  /// en "PLAY" 都在宽约束内原尺寸呈现，串长变化只会 scaleDown、永不溢出牌面。
  Widget _buildLabel() {
    return Transform.rotate(
      angle: kGardenSignLabelTiltRadians,
      child: Center(
        child: FractionallySizedBox(
          // 占热区中带：宽 84% / 高 50%（热区上下各外扩过 ~6‰，牌面本体在中段）；
          // 目标 = 文字高度接近牌面高的 40~50%（玄参 2026-11-06 复看截图后拍板放大）。
          widthFactor: 0.84,
          heightFactor: 0.50,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.label!,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B3F10),
                height: 1.0,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 呼吸光晕层（`animate == false` 时退化为不占空间的空层）。
  Widget _buildGlow() {
    final AnimationController? controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final double opacity = _glowMinOpacity +
            (_glowMaxOpacity - _glowMinOpacity) * controller.value;
        return Transform.rotate(
          angle: _glowTiltRadians,
          child: Container(
            key: const Key('garden_sign_glow'),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE9A8).withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x33FFD54F), blurRadius: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}
