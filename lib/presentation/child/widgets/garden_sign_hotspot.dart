/// 花园左下角木牌的可点击热区 + 轻微呼吸高亮（2026-09-24 花园页 v3 改造）。
///
/// ## 职责
/// 背景图左下角有一块木牌，玄参大人要求它**可点击**并弹出「玩法说明」（原来贴底的
/// 半透明白块文案收进该弹窗）。本组件只负责「热区 + 按下反馈 + 呼吸高亮」，弹窗内容
/// 由调用方（`GardenPage._showGardenHelp` → `GardenHelpSheet`）给出。
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

import 'package:flutter/material.dart';

/// 背景图左下角木牌的点击热区（含按下缩放 + 呼吸光晕）。
class GardenSignHotspot extends StatefulWidget {
  const GardenSignHotspot({super.key, required this.onTap, this.animate = true});

  /// 点击木牌的回调（花园页里打开「玩法说明」弹窗）。
  final VoidCallback onTap;

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
          // StackFit.expand：让唯一子层填满热区矩形（`Positioned.fromRect` 已给定边界）。
          fit: StackFit.expand,
          children: <Widget>[_buildGlow()],
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
