/// 花园右上角「图标 + 下方单行文字」复用簇（v0.3.0 / R3-P0-11）。
///
/// ## 为什么要有这个文件（玄参反馈 5 的根因）
/// 旧实现是**多个并列 `Positioned`，各自用未缩放常量算 `top`**：
/// `top: 12 + kGardenWeatherBadgeIconSize + kGardenTopEntryGap`。而徽标实际渲染高
/// 是 `kGardenWeatherBadgeIconSize * uiScaleOf(context)`（平板 `uiScale = 1.3`
/// ⇒ 实际 72.8 而非 56）⇒ `uiScale > 1` 时下方元素**必然被压住**。
///
/// ## 解法：结构折叠 —— 堆叠交给布局，不留给常量
/// 右上角改为**单个 `Positioned(right, top)` + `Column`**，本 widget 是 Column 的
/// 一个子项：`Column[图标, SizedBox(kGardenTopLabelGap), 单行文字]`。
/// 子项间距由 `SizedBox` 保证，与 `uiScale` / `textScaler` / 素材尺寸**完全解耦**
/// —— **没有固定偏移常量可供漂移**（这是「scale 感知」的最强形式）。
///
/// ## 热区
/// 图标 + 文字**同属一个热区**（外层 `InkWell` 包住两者）：点文字等同点图标
/// （R3-P0-11⑤）。图标自身尺寸由调用方保证 ≥44×44（天气徽标 56、许愿树入口 48）。
library wish_top_entry_cluster;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 「图标 + 下方单行文字」簇。
///
/// 纯展示 widget：不读 provider、不取 ARB（[label] 由调用方在 `L10nScope` 内取好）。
class WishTopEntryCluster extends StatelessWidget {
  const WishTopEntryCluster({
    super.key,
    required this.icon,
    required this.label,
    required this.labelKey,
    this.onTap,
    this.semanticLabel,
  });

  /// 图标本体（尺寸由调用方决定，建议 ≥44×44 以满足触控热区）。
  final Widget icon;

  /// 图标正下方的单行文字（`maxLines: 1` + ellipsis，R3-P0-11③④）。
  final String label;

  /// 文字节点的 Key（测试用 `tester.getRect` 量图标与文字的间距）。
  final Key labelKey;

  /// 点击回调；`null` ⇒ 不可点（但仍排版，用于只读展示）。
  final VoidCallback? onTap;

  /// 无障碍标签（默认退化用 [label]）。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      child: InkWell(
        // 图标与文字同属一个热区：点文字等同点图标（R3-P0-11⑤）。
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        // 🔴 本簇**不加任何外边距**：整簇由外层 `Positioned(right: 12, top: 12)`
        // 定位，簇内再补水平内边距会把图标的右缘推离 `right: 12` 锚点
        // （历史基线断言「状态灯 right == 屏宽 − 12」会整体偏移 2dp）。
        // 相邻簇的间距由外层 `SizedBox(height: kGardenTopEntryGap)` 负责，
        // 故簇自身贴边不会导致热区互相覆盖。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 居中：两簇共用本 widget，「阴天」2 字与「许愿树」3 字都必须
          // 在图标正下方居中完整显示（玄参 v0.3 真机反馈 1：旧右对齐
          // 让 5 字的「我的许愿树」右贴并被 96dp 截断）。
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            icon,
            // 🔴 图标与其文字的间距走常量单点（R3-P0-11②：4dp）。
            const SizedBox(height: kGardenTopLabelGap),
            // 单行、超长省略：不换行 ⇒ 文字高度恒定，不会把下方簇推走。
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5D4A2A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
