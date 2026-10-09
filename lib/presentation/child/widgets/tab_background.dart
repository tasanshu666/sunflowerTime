/// C44 tab 整页背景组件（2026-10-09 玄参「上半场景+下半留白」底图）。
///
/// 用法：包住 tab 页内容，`BoxFit.cover + topCenter` 铺满（含 shell 透明 AppBar
/// 底下——外壳对今日/成长/商店开了 `extendBodyBehindAppBar`，见 child_shell_page）。
///  · 图片加载失败 → 回退 [fallbackColor] 纯色（原奶油底），**绝不阻塞内容**；
///  · 下半留白区即内容区，白卡直接浮在上面（与设计稿分层一致）。
library tab_background;

import 'package:flutter/material.dart';

class TabBackground extends StatelessWidget {
  final String asset;

  /// 图片缺失/解码失败时的兜底底色（各页原奶油底 / 白底）。
  final Color fallbackColor;

  final Widget child;

  const TabBackground({
    super.key,
    required this.asset,
    required this.fallbackColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fallbackColor,
        image: DecorationImage(
          image: AssetImage(asset),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          onError: (Object _, StackTrace? __) {
            // 静默：兜底色已由 decoration.color 承载，不打日志刷屏。
          },
        ),
      ),
      child: child,
    );
  }
}
