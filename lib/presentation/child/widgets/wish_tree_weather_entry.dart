/// 花园右上角天气徽标**正下方**的许愿树入口（v0.2.0 / R-P0-05）。
///
/// 纯展示 widget：文案由调用方在页级 `L10nScope` 内取好经 [label] 传入（仅作
/// 无障碍标签；**可见文字由 `WishTopEntryCluster` 在图标下方渲染**，避免双份）。
/// 点击只上抛 [onTap]（页面 `context.push('/wish-tree')`）。
///
/// v0.3.0（R3-P0-11）：尺寸改走 `kWishTreeWeatherEntrySize * uiScaleOf(context)`
/// —— 与天气徽标（`kGardenWeatherBadgeIconSize * uiScaleOf`）同源等比，
/// 平板 `uiScale = 1.3` 时两者一起放大，不会出现一大一小。
/// 不使用 `FittedBox`（无障碍大字号下会压缩文本）。
///
/// 玄参 2026-11-20 真机反馈：中心图标由系统 `Icons.park_outlined` 换成美术素材
/// `许愿树1.png`（落盘 `assets/wish_tree/wish_tree_icon.webp`），容器由正圆改为
/// 与天气徽标一致的 12dp 圆角方形（复用 `kGardenWeatherBadgeIconContainerRadius`，
/// 圆角不乘 scale —— 与天气徽标写法保持一致）。
///
/// 玄参 2026-11-20 二次真机反馈：容器边长由 48 对齐到天气徽标的 56
/// （`kWishTreeWeatherEntrySize`），位图显示盒由 26 放大到 52
/// （`kWishTreeWeatherEntryIconSize`）——源图四周约 15% 透明留白，旧值下树
/// 实际只有 ≈18dp，看起来又小又糊；新值下树 ≈36dp，接近天气图标视觉主体。
library wish_tree_weather_entry;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 新入口稳定 Key（widget / 集成测试与布局断言共用）。
const Key kWishTreeWeatherEntryKey = Key('wish_tree_weather_entry');

/// 许愿树入口图标资源路径（2048×2048 方图，UI 图标直接 `BoxFit.contain` 缩放，
/// 不走植物盆图 C13 归一管线）。
const String kWishTreeWeatherEntryIconAsset =
    'assets/wish_tree/wish_tree_icon.webp';

/// 天气下方许愿树入口。
class WishTreeWeatherEntry extends StatelessWidget {
  const WishTreeWeatherEntry({
    super.key = kWishTreeWeatherEntryKey,
    required this.label,
    this.onTap,
    this.scale = 1.0,
  });

  /// 入口文案（ARB，调用方取好）。
  final String label;

  /// 点击上抛；页面负责 `context.push('/wish-tree')`。
  ///
  /// v0.3.0（R3-P0-11）：改为**可选**。收进 `WishTopEntryCluster` 后热区由外层
  /// 那一个 `InkWell` 统一（点文字等同点图标），本 widget 传 `null` 只做视觉。
  final VoidCallback? onTap;

  /// R7-P0-03 手机单侧缩放系数（页面传 `compactScaleOf`）：手机 0.8 / iPad 1.0。
  /// `side` 与位图尺寸 `× uiScaleOf × scale`，默认 1.0 保证其它宿主逐字节不变。
  final double scale;

  @override
  Widget build(BuildContext context) {
    // v0.3.0：与天气徽标同源等比（徽标自身即 `56 * uiScaleOf`）；
    // R7-P0-03：再乘手机紧凑系数，二者始终同源。
    final double s = uiScaleOf(context) * scale;
    final double side = kWishTreeWeatherEntrySize * s;
    // 圆角方形：与天气徽标同半径、同样不乘 scale（对齐两个入口的观感）。
    final BorderRadius radius =
        BorderRadius.circular(kGardenWeatherBadgeIconContainerRadius);
    return Semantics(
      button: onTap != null,
      label: label,
      child: Material(
        color: const Color(0xFFFFF8E6),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              // 显式宽高 + contain：loose 约束下不写尺寸会被 2048 源图撑爆。
              child: Image.asset(
                kWishTreeWeatherEntryIconAsset,
                width: kWishTreeWeatherEntryIconSize * s,
                height: kWishTreeWeatherEntryIconSize * s,
                fit: BoxFit.contain,
                // 资产已声明，真机不会走此分支；部分 widget 测试 mock 掉
                // `flutter/assets` 通道（避免序列帧解码 OOM），空占位兜底，
                // 不让本图标把无关用例的「零异常」判据打红。
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
