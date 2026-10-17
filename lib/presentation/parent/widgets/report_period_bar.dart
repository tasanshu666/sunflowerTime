/// 专注报告 v2 · 周期切换器（日 / 周 / 月 / 年，C76 / T03）。
///
/// 视觉范式对齐记录页 `history_activity_section.dart` 的 `_PeriodBar`
/// （`Row` + `Expanded` + `GestureDetector` + 选中白底/主色底），但**多两件事**：
///
///  1. **锁定态视觉**：月 / 年在免费档「视觉置灰 + 🔒 图标」，但**仍可点**——
///     🔴 C62 纪律：「不可点」≠ 静默。点击由上层（[FocusReportSection]）接住，
///     **不切换周期**并弹「升级解锁」对话框给因；
///  2. **稳定 Key**：每档给 `ValueKey('reportPeriod_<name>')`，供测试用
///     `find.byKey` 精确定位（不依赖文本，避免文案微调就把测试打红）。
///
/// 🔴 本文件**不含任何权益标识符**：只吃 `bool unlocked`（判定在
/// `focus_report_section.dart` 单点完成）。
///
/// 排版纪律（C65 / F118 双重缩放红线）：
///  · 文字**不乘** `uiScaleOf` —— 文字缩放由 `MediaQuery.textScaler` 注入一次，
///    这里再乘一次就是双重放大；
///  · 只有 🔒 图标尺寸乘 `uiScaleOf`（非文字元素）；
///  · 每档 label 一律包 `FittedBox(fit: BoxFit.scaleDown)` —— 窄屏 / 1.3× 文字
///    缩放下绝不 `RenderFlex overflow`（宁可缩小，不许溢出）。
library report_period_bar;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/report_period.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 周期切换器：日 / 周 / 月 / 年（月 / 年在免费档带 🔒 视觉，仍可点）。
class ReportPeriodBar extends StatelessWidget {
  const ReportPeriodBar({
    required this.period,
    required this.unlocked,
    required this.onTap,
    super.key,
  });

  /// 当前选中档。
  final ReportPeriod period;

  /// 深度报告是否已解锁（`deepReport` 能力放行）。
  ///
  /// 只用于**视觉**（月 / 年置灰 + 🔒）；拦截与给因由上层负责。
  final bool unlocked;

  /// 点击某档（**四档都可点**，包括锁定的月 / 年）。
  final ValueChanged<ReportPeriod> onTap;

  /// 展示顺序：日 → 周 → 月 → 年（与 PRD 口径一致）。
  static const List<ReportPeriod> _periods = <ReportPeriod>[
    ReportPeriod.day,
    ReportPeriod.week,
    ReportPeriod.month,
    ReportPeriod.year,
  ];

  /// 档位短标签（`日 / 周 / 月 / 年`）。
  static String _labelOf(ReportPeriod p) {
    switch (p) {
      case ReportPeriod.day:
        return '日';
      case ReportPeriod.week:
        return '周';
      case ReportPeriod.month:
        return '月';
      case ReportPeriod.year:
        return '年';
    }
  }

  /// 该档在免费档下是否「锁着」——只有月 / 年需要 `deepReport`。
  ///
  /// 注意：这只决定**看起来锁着**，不决定是否放行（放行判定在上层单点）。
  static bool _isLocked(ReportPeriod p, bool unlocked) {
    if (unlocked) return false;
    return p == ReportPeriod.month || p == ReportPeriod.year;
  }

  @override
  Widget build(BuildContext context) {
    final ReportPalette palette = ReportPalette.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 选中档文字色：浅色档配白字；深色档 accent 偏亮，改配深字（避免白字压浅蓝）。
    final Color onSelected = isDark ? const Color(0xFF152329) : Colors.white;
    final double iconScale = uiScaleOf(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.softBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (final ReportPeriod p in _periods)
            Expanded(
              child: GestureDetector(
                key: ValueKey<String>('reportPeriod_${p.name}'),
                behavior: HitTestBehavior.opaque,
                // 🔴 C62：锁定档也**必须**给回调（不置 null / 不静默）。
                onTap: () => onTap(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p == period ? palette.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _labelOf(p),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: p == period
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: p == period
                                ? onSelected
                                : _isLocked(p, unlocked)
                                    ? palette.inkAt(0.45)
                                    : palette.ink,
                          ),
                        ),
                        if (_isLocked(p, unlocked)) ...<Widget>[
                          const SizedBox(width: 2),
                          Icon(
                            Icons.lock_outline,
                            size: 12 * iconScale,
                            color: palette.inkAt(0.45),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
