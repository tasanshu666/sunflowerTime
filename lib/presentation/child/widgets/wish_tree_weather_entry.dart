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
library wish_tree_weather_entry;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 新入口稳定 Key（widget / 集成测试与布局断言共用）。
const Key kWishTreeWeatherEntryKey = Key('wish_tree_weather_entry');

/// 天气下方许愿树入口。
class WishTreeWeatherEntry extends StatelessWidget {
  const WishTreeWeatherEntry({
    super.key = kWishTreeWeatherEntryKey,
    required this.label,
    this.onTap,
  });

  /// 入口文案（ARB，调用方取好）。
  final String label;

  /// 点击上抛；页面负责 `context.push('/wish-tree')`。
  ///
  /// v0.3.0（R3-P0-11）：改为**可选**。收进 `WishTopEntryCluster` 后热区由外层
  /// 那一个 `InkWell` 统一（点文字等同点图标），本 widget 传 `null` 只做视觉。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // v0.3.0：与天气徽标同源等比（徽标自身即 `56 * uiScaleOf`）。
    final double scale = uiScaleOf(context);
    final double side = kWishTreeWeatherEntrySize * scale;
    return Semantics(
      button: onTap != null,
      label: label,
      child: Material(
        color: const Color(0xFFFFF8E6),
        borderRadius: BorderRadius.circular(side / 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(side / 2),
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              child: Icon(
                Icons.park_outlined,
                size: kWishTreeWeatherEntryIconSize * scale,
                color: const Color(0xFF4E7A32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
