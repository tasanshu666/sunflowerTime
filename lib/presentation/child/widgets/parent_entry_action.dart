/// 孩子端 AppBar 右上角「家长天地」入口（🔑 单点收口，供 shell 与度量测试**共用同一份**）。
///
/// ## 为什么抽成独立组件
/// 2026-10-14 「徽章 v3」要求把 iPad 徽章**右对齐到右上家长入口图标所在的竖线**
/// —— 该约束靠 RenderBox 实测锁定（`today_badge_bounds_test.dart`）。
/// 若测试里自己复制一份图标，一旦生产 AppBar 的 `actions` / `margin` 变化，测试
/// 量到的就不是**真实渲染**的图标（玄参纪律「AI 不截图不自查 UI」要求实测）。
/// 故把图标抽成本组件，shell 与测试**引用同一个** widget，度量与生产同源。
///
/// ## 两种形态（与 [ChildShellPage] 沉浸式口径一致）
///  · [immersive] = true：垫一层半透白胶囊（沉浸式 tab 是亮色场景，纯图标看不清）；
///  · false：裸 [IconButton]（非沉浸 tab 原样）。
library parent_entry_action;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 右上角「家长天地」入口按钮。
class ParentEntryAction extends StatelessWidget {
  const ParentEntryAction({super.key, required this.immersive});

  /// 是否沉浸式（今日 / 成长 / 商店三个整页底图 tab）—— 决定是否垫白胶囊。
  final bool immersive;

  /// 图标本体 Key（度量用：读它的 RenderBox 得到**真实**右上角图标矩形）。
  static const Key iconKey = Key('childParentEntryIcon');

  @override
  Widget build(BuildContext context) {
    final Widget button = IconButton(
      key: iconKey,
      icon: const Icon(Icons.family_restroom),
      tooltip: '家长天地',
      onPressed: () => context.go('/parent'),
    );
    if (!immersive) return button;
    // C44e 二轮反馈（玄参 2026-10-09）：沉浸式亮场景底上纯图标看不清 → 垫白胶囊。
    return Container(
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: button,
    );
  }
}
