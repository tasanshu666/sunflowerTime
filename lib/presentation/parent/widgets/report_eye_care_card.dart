/// 专注报告 v2 · 护眼统计卡（**免费可见**，C76 / T03）。
///
/// 文案 / 口径**逐字照搬**老页 `parent_report_page.dart` 的 `_EyeCareCard`
/// （`:222-317`，含零数据时的 `'—'` 占位口径与「跳过 > 0」的关注提示行）：
///
///  · **完成护眼** = 账本 `refType='eye_care_break'` 全量计数（与孩子端「我的」同源）；
///  · **跳过护眼** = `eye_care_logs` 表 skipped 计数（v18 起才有数）；
///  · **累计护眼时长** = 完成次数 × [kEyeCareDurationSeconds] + 跳过那几次的实际观看秒数
///    （部分观看也算护眼，如实计入）；
///  · **跳过率** = 跳过 /（完成 + 跳过）—— 衡量孩子对护眼提醒的配合度。
///
/// 🔴 口径纪律（C76 裁定 #1）：护眼统计**保持免费可见**，因此本组件
/// **既不吃 `unlocked`、也不吃占位卡**，更不含任何权益标识符。
library report_eye_care_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';

/// 护眼统计卡（四项指标：完成 / 跳过 / 累计时长 / 跳过率）。
class ReportEyeCareCard extends StatelessWidget {
  const ReportEyeCareCard({
    required this.completed,
    required this.skipped,
    required this.skippedWatchedSeconds,
    super.key,
  });

  /// 完成护眼次数（阳光账本 `eye_care_break` 全量计数）。
  final int completed;

  /// 跳过护眼次数（`eye_care_logs` 中 result = skipped）。
  final int skipped;

  /// 跳过那几次的**实际观看秒数**（部分观看也计入护眼时长）。
  final int skippedWatchedSeconds;

  @override
  Widget build(BuildContext context) {
    final ReportPalette palette = ReportPalette.of(context);

    final int totalSeconds =
        completed * kEyeCareDurationSeconds + skippedWatchedSeconds;
    final String durationText = totalSeconds <= 0
        ? '—'
        : totalSeconds < 60
            ? '$totalSeconds 秒'
            : '${(totalSeconds / 60).toStringAsFixed(1)} 分钟';
    final int totalEvents = completed + skipped;
    final String skipRateText = totalEvents <= 0
        ? '—'
        : '${(skipped * 100 / totalEvents).toStringAsFixed(0)}%';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.softBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _EyeCareMetric(
                  label: '完成护眼',
                  value: '$completed 次',
                  palette: palette,
                ),
              ),
              Expanded(
                child: _EyeCareMetric(
                  label: '跳过护眼',
                  value: '$skipped 次',
                  palette: palette,
                  highlight: skipped > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _EyeCareMetric(
                  label: '累计护眼时长',
                  value: durationText,
                  palette: palette,
                ),
              ),
              Expanded(
                child: _EyeCareMetric(
                  label: '跳过率',
                  value: skipRateText,
                  palette: palette,
                ),
              ),
            ],
          ),
          if (skipped > 0) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '有 $skipped 次护眼被跳过（跳过的观看时长已如实计入）。',
                style: TextStyle(fontSize: 12, color: palette.inkAt(0.65)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 护眼统计单格（标签 + 数值）。
class _EyeCareMetric extends StatelessWidget {
  const _EyeCareMetric({
    required this.label,
    required this.value,
    required this.palette,
    this.highlight = false,
  });

  final String label;
  final String value;
  final ReportPalette palette;

  /// true 时数值用 warn 色（跳过 > 0 提示家长关注）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 12, color: palette.inkAt(0.65)),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: highlight ? palette.warn : palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}
