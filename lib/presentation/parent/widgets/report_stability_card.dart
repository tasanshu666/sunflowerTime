/// 专注报告 v2 · 专注稳定性卡（近 4 周，C76 / T03）。
///
/// 内容（对应 PRD §8.3「北极星」与 §3.3「有效专注日」）：
///   · **4 根周柱** = [FocusReport.weeklyValidDayTrend]（旧→新，最后一根 = 本周，
///     用 `palette.accent` 高亮，其余 `palette.idle`）；
///   · **稳定性读数** `'稳定性 N%'`（`stabilityScore × 100` 取整）。
///
/// 柱高按「有效专注日上限 7 天」归一，故四周柱高可直接横向比较。
/// 布局纪律同老页：**不设外层固定高度**，数值标签在柱上、周标签在基线下方，
/// 各行自适应 → 1.3× 文字缩放也不会 `RenderFlex overflow`。
///
/// 🔴 门控纪律：本文件**不含任何权益标识符**，只吃 `bool unlocked` +
/// 上层构造好的 `lockedPlaceholder`（未解锁时**整卡替换**为付费引导，不渲染任何真数据）。
library report_stability_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 稳定性卡（近 4 周有效专注日柱状 + 稳定性读数）。
class ReportStabilityCard extends StatelessWidget {
  const ReportStabilityCard({
    required this.unlocked,
    required this.lockedPlaceholder,
    required this.report,
    super.key,
  });

  /// 是否已解锁（免费档直接返回 [lockedPlaceholder]）。
  final bool unlocked;

  /// 未解锁时展示的付费引导卡（由上层 `FocusReportSection` 构造后传入）。
  final Widget lockedPlaceholder;

  /// 近 7 日 + 近 4 周稳定性报告（仅解锁档才会真正取数）。
  final FocusReport report;

  /// 单柱最大高度（pt，与老页一致）。
  static const double _barMaxHeight = 72;

  @override
  Widget build(BuildContext context) {
    if (!unlocked) return lockedPlaceholder;

    final ReportPalette palette = ReportPalette.of(context);
    final List<int> trend = report.weeklyValidDayTrend;

    if (trend.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.softBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '近 4 周还没有专注记录。',
          style: TextStyle(fontSize: 12.5, color: palette.inkAt(0.8)),
        ),
      );
    }

    final int stabilityPercent = (report.stabilityScore * 100).round();
    final Color tone =
        report.stabilityScore >= 0.5 ? palette.good : palette.warn;

    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < trend.length; i++)
                Expanded(
                  child: _WeekBar(
                    days: trend[i],
                    isCurrent: i == trend.length - 1,
                    palette: palette,
                  ),
                ),
            ],
          ),
          Container(height: 1.5, color: palette.inkAt(0.15)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (int i = 0; i < trend.length; i++)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      i == trend.length - 1 ? '本周' : '${trend.length - i - 1} 周前',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == trend.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i == trend.length - 1
                            ? palette.ink
                            : palette.inkAt(0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.insights, size: 18, color: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '稳定性 $stabilityPercent%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tone,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单周柱（数值在上 + 柱体在下，自适应高度）。
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.days,
    required this.isCurrent,
    required this.palette,
  });

  /// 该周有效专注日数（0–7）。
  final int days;

  /// 是否本周（最后一根，主色高亮）。
  final bool isCurrent;

  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    // 上限 7 天 → 按 7 归一，四周柱高可直接横向比较。
    final double height =
        (days / 7 * ReportStabilityCard._barMaxHeight).clamp(6.0, 72.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 16,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$days',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isCurrent ? palette.accent : palette.inkAt(0.65),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 26,
          height: height,
          decoration: BoxDecoration(
            color: isCurrent ? palette.accent : palette.idle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
      ],
    );
  }
}
