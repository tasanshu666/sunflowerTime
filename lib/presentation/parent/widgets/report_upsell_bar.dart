/// 专注报告 v2 · 深度报告引导**横条**（C85）。
///
/// 为什么从「卡」改成「条」：原设计在稳定性 / 热力图两处各放一张
/// `PremiumUpsellCard` 大卡（`解锁「深度专注报告」` + `一次买断，永久解锁全部功能`
/// + 大按钮），免费档家长向下滚动时要穿过**两块几乎一样的广告牌**，既重复又
/// 把真正的免费内容（护眼统计）挤到很下面。C85 拍板：压成**一条**横条 ——
/// 免费档只在他的视线上占约 60pt，且只在稳定性区块出现一次。
///
/// ## 门控纪律（守卫契约）
/// 本文件**不含任何权益标识符**（权益实体 / 能力键 / 门控类 / 权益 Provider 全都不出现）：
/// 判定与文案构造全部在上层 `focus_report_section.dart`（判定单点）完成，
/// 这里只吃一个 [onTap] 回调 + 静态文案 —— 故本文件不需要进守卫白名单。
///
/// ## 窄屏 / 大字纪律（C65 / F118）
///  · 两段文字都 `maxLines: 1` + [TextOverflow.ellipsis] → 320pt 屏 + 1.3× 文字
///    缩放也不 `RenderFlex overflow`（宁可省略号，也不换行顶破横条）；
///  · 文字**只吃系统 `textScaler`**，**不**乘 [uiScaleOf]（否则平板上文字被放大
///    两次，横条高度失控）；
///  · 图标 / 间距 / 圆角这类**尺寸**才乘 [uiScaleOf]（平板视觉重量对齐）。
library report_upsell_bar;

import 'package:flutter/material.dart';

import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 深度报告引导横条（点右侧「查看详情」→ 上层弹「升级解锁」对话框）。
class ReportUpsellBar extends StatelessWidget {
  const ReportUpsellBar({required this.onTap, super.key});

  /// 点「查看详情」的回调（上层绑定 `showPremiumUpsell(context, ...)`）。
  final VoidCallback onTap;

  /// 主文案（免费档唯一一处重复出现也不会嫌吵的那句）。
  static const String titleText = '解锁深度专注报告';

  /// 副文案（一行说清买断后能多看到什么）。
  static const String subtitleText = '近 4 周稳定性 · 全年热力图';

  /// 右侧按钮文案。
  static const String actionText = '查看详情';

  @override
  Widget build(BuildContext context) {
    final ReportPalette palette = ReportPalette.of(context);
    // 尺寸类缩放（文字**不**乘，见文件头 C65/F118 说明）。
    final double ui = uiScaleOf(context);

    return Container(
      padding: EdgeInsets.fromLTRB(14 * ui, 12, 10 * ui, 12),
      decoration: BoxDecoration(
        color: palette.softBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.insights_rounded,
            size: 22 * ui,
            color: palette.accent,
          ),
          SizedBox(width: 12 * ui),
          // 文字区吃满剩余宽度；两行都单行省略 → 窄屏不溢出。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.inkAt(0.7),
                  ),
                ),
              ],
            ),
          ),
          // 按钮贴右且尽量紧凑：`minimumSize` + `shrinkWrap` 去掉 Material 默认
          // 48pt 触控高度带来的额外纵向占用（横条才能压到 ~60pt）。
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: palette.accent,
            ),
            child: const Text(
              actionText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
