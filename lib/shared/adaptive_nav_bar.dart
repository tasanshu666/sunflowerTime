/// 底部导航栏的**平板限宽外壳**（C61 平板适配，2026-10-13 玄参拍板）。
///
/// ## 解决什么
/// `NavigationBar` 把 destinations 按**可用宽度均分铺满**：
///  · 手机 390 宽 → 5 个 destination 各 ≈78，刚好；
///  · 平板 800 宽 → 各 ≈160，图标被拉得很散（M3 的通用建议是换 `NavigationRail`，
///    但玄参 2026-10-13 拍板**保持底部导航**——儿童跨设备操作习惯统一、拇指可达；
///    只做「约束宽度 + 居中」）。
///
/// ## 做法
///  · 手机（`shortestSide < kTabletShortestSideThreshold`）→ **原样返回 `child`**，
///    不包任何 widget，**零像素变化**；
///  · 平板 → 内容限宽 [kNavBarMaxWidth] 并水平居中，两侧用**导航栏自身背景色**
///    补满 —— 视觉上仍是一条通栏底栏，而不是「悬浮在中间的一条」。
///
/// ⚠️ 补色必须与 `NavigationBar` 实际背景色**同源**，否则底栏会「断成三截」。
/// M3 下 `NavigationBar` 默认底色 = `colorScheme.surfaceContainer`；若主题侧
/// 显式配过 `NavigationBarTheme.backgroundColor`，这里优先取它。
///
/// ⚠️ **布局安全性（踩过的坑，2026-10-13 平板实测翻车）**：`bottomNavigationBar`
/// 槽位给的是「宽有界、**高也有界**（max = 屏高）」的 loose 约束 —— **不是无界**。
/// `Center` 只在「高度无界」时才 shrink-wrap；高度有界时它会**撑满 maxHeight
/// = 整屏高**！后果：底栏外壳占满整屏高、body 被挤成 0 高 → **所有页面一片空白**，
/// 且 `Center` 把导航垂直居中 → 导航浮在屏幕中间、`ColoredBox` 的底色铺满全屏
/// （iPad 上「全米色 + 导航浮中间」正是此因）。
/// 因此这里必须显式 `heightFactor: 1` 强制纵向 shrink-wrap（宽度仍撑满槽位）。
library adaptive_nav_bar;

import 'package:flutter/material.dart';

import '../core/constants/prd_params.dart';
import 'responsive.dart';

/// 底部导航栏的平板限宽外壳（手机端零变化）。
class AdaptiveNavBarHost extends StatelessWidget {
  const AdaptiveNavBarHost({super.key, required this.child});

  /// 导航栏本体（通常是 `NavigationBar`）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 手机：原样返回，不引入任何包装（保证零像素变化）。
    if (!isTabletOf(context)) return child;

    final Color navBg = NavigationBarTheme.of(context).backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainer;
    return ColoredBox(
      color: navBg,
      child: Center(
        // ⚠️ 必须是 1，不能省：底栏槽位高度**有界**（max = 屏高），`Center` 默认会
        // 撑满该 maxHeight → 底栏占满整屏、body 归零、导航垂直居中（平板空白页根因）。
        // `heightFactor: 1` → 纵向 shrink-wrap（size.height = child.height）；
        // 宽度仍被撑满槽位（`widthFactor` 为 null 且槽位宽有界）。
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kNavBarMaxWidth),
          child: child,
        ),
      ),
    );
  }
}
