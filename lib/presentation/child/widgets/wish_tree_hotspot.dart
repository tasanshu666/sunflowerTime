/// 花园页「许愿树」入口热区（A-T04 / A7.6 S4~S7）。
///
/// ## 落点纪律（不可破）
///  - 本 widget 只画**按钮本体**（图标 + 文案 + 呼吸高亮），**不**自己算位置；
///    调用方（`garden_page.dart`）用带稳定 `Key` 的 `Positioned` 摆在根 Stack 的
///    **children 末尾** —— 既有节点 index 不变，C82 的按 index 复用坑不触发。
///  - **不进**花园左上 chips 行 ⇒ `weather_a3_banner_ui_test` V6/V7/V8 的逐像素
///    断言零回归。
///  - 孩子端**零购买入口**：本 widget 只 `onTap` 打开许愿树页，不含任何
///    家长端付费跳转或购买字样。
///
/// ## 测试陷阱（与 `GardenSignHotspot` 同款）
/// 无限重复的呼吸动画会让 `tester.pumpAndSettle()` **永不返回**。故提供 [animate]
/// 开关：widget 测试传 `false`（不创建、不启动 controller），花园页默认 `true`。
library wish_tree_hotspot;

import 'package:flutter/material.dart';

/// 呼吸周期（秒）——轻微即可，不抢木牌 / 花盆的戏。
const Duration kWishTreeHotspotBreathPeriod = Duration(seconds: 2);

/// 呼吸光晕的不透明度区间。
const double kWishTreeHotspotGlowMin = 0.05;
const double kWishTreeHotspotGlowMax = 0.18;

/// 按下缩放比例（轻微回弹反馈）。
const double kWishTreeHotspotPressedScale = 0.94;

/// 呼吸光晕基色（与 alpha 组合成实际阴影色）。
const Color kWishTreeHotspotGlowColor = Color(0xFFFFE9A8);

/// 花园页「我的许愿树」入口热点。
///
/// [label] 为本地化文案（zh「许愿树」/ en「Wish Tree」），由页级 scope 内取好传入
/// ——弹窗 / 浮层 builder 上下文在 `L10nScope` 之外的铁律同样适用。
class WishTreeHotspot extends StatefulWidget {
  const WishTreeHotspot({
    super.key,
    required this.onTap,
    required this.label,
    this.animate = true,
  });

  /// 点击入口的回调（花园页里 push 到 `/wish-tree`）。
  final VoidCallback onTap;

  /// 入口文案（本地化后在页级 scope 内取好）。
  final String label;

  /// 是否执行呼吸动画。`false` 时不创建 controller，`pumpAndSettle` 可正常返回。
  final bool animate;

  @override
  State<WishTreeHotspot> createState() => _WishTreeHotspotState();
}

class _WishTreeHotspotState extends State<WishTreeHotspot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant WishTreeHotspot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncController();
  }

  /// 依据 [WishTreeHotspot.animate] 创建 / 销毁呼吸控制器。
  void _syncController() {
    if (widget.animate) {
      _controller ??= AnimationController(
        vsync: this,
        duration: kWishTreeHotspotBreathPeriod,
      )..repeat(reverse: true);
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? kWishTreeHotspotPressedScale : 1.0,
          duration: const Duration(milliseconds: 120),
          child: _buildBreathingBody(),
        ),
      ),
    );
  }

  /// 呼吸层：`animate == false` 时 controller 为 null，退化为静态 body（测试可 settle）。
  Widget _buildBreathingBody() {
    final AnimationController? controller = _controller;
    if (controller == null) return _buildBody(kWishTreeHotspotGlowMin);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) => _buildBody(
        kWishTreeHotspotGlowMin +
            (kWishTreeHotspotGlowMax - kWishTreeHotspotGlowMin) *
                controller.value,
      ),
    );
  }

  Widget _buildBody(double glowOpacity) {
    return Container(
      key: const Key('wish_tree_hotspot_body'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66E8A600)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kWishTreeHotspotGlowColor.withValues(alpha: glowOpacity),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🌳', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B4E12),
            ),
          ),
        ],
      ),
    );
  }

}
