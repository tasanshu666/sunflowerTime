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
/// （R3-P0-11⑤）。图标自身尺寸由调用方保证 ≥44×44（天气徽标 56、许愿树入口 56，两者等大）。
library wish_top_entry_cluster;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/shared/responsive.dart';

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
          // 🔴 对齐锚（C129 修订，玄参 iPad13 反馈「天气文字没在天气图标正下方
          //    ——不要把保护罩算进去」）：改为 **CrossAxisAlignment.end**，配合
          //    文字框定宽 = 图标本体宽（见下），使「文字框右缘 == 簇右缘 ==
          //    图标本体右缘」⇒ 文字中心 x 恒等于**图标本体**中心 x。
          //    为什么 center 不行：天气徽章 `GardenWeatherBadge` 在已购保护罩时
          //    是 Row[罩 72 + gap 7 + 图标 56]（宽 135×s），center 会把文字对到
          //    整个 Row 的中心（左偏 (72+7)/2×s）；end + 定宽框则天然对齐图标
          //    本体、罩显隐 / 语言切换零分支。两处入口图标本体恒为
          //    `kWishTreeWeatherEntrySize × s`（天气框与许愿树框同 56，PRD 口径）。
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            icon,
            // 🔴 图标与其文字的间距走常量单点（R3-P0-11②：4dp）。
            const SizedBox(height: kGardenTopLabelGap),
            // 单行、超长省略：不换行 ⇒ 文字高度恒定，不会把下方簇推走。
            // 🔴 C129：框宽从「maxWidth ≤ 图标宽」收紧为**定宽 = 图标本体宽**
            //    `kWishTreeWeatherEntrySize × uiScaleOf(context)` —— 定宽 +
            //    crossAxis.end ⇒ 文字框中心 = 图标本体中心（保护罩不参与）。
            //    内层 `FittedBox(scaleDown)` 沿用 C128：英文长词整串缩放
            //    （绝不 ellipsis 截半）、中文短词直通（不放大不缩小）。
            SizedBox(
              width: kWishTreeWeatherEntrySize * uiScaleOf(context),
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
            ),
          ],
        ),
      ),
    );
  }
}
