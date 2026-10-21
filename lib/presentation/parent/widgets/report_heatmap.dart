/// 专注报告 v2 · 专注热力图（近 1 年日历格，C76 / T03）。
///
/// 布局：**行 = 周一…周日**（周一在最上，与「周一为一周之始」口径一致），
/// **列 = 周**（最多 53 列）；顶部一行月份刻度（仅在该月第一列上方显示 `M月`）。
/// 单格 12×12、间距 3（即每格步进 15），整块宽约 `26 + 53×15 ≈ 821pt`，
/// 手机上必然超宽 → 整块包 `SingleChildScrollView(horizontal)` 横滑。
///
/// 色阶 5 档（按当日专注分钟）：
///   · `0`        → `palette.idle`；
///   · `1–14`     → `palette.valid` @ 35%；
///   · `15–29`    → 60%；`30–59` → 85%；`≥60` → 实心 `palette.valid`。
///
/// 交互：点格 → `ScaffoldMessenger` 1 秒轻提示 `'M月d日 · N 分钟'`
/// （先 `hideCurrentSnackBar`，避免连点堆积）。
///
/// 🔴 门控纪律：本文件**不含任何权益标识符**。未解锁时**直接返回**
/// [lockedPlaceholder]（上层构造好的付费引导卡），因此**真实数据一个格子都不会渲染**
/// —— 这也是 `test/qa/focus_report_gating_test.dart` 断言
/// `find.byType(ReportHeatmap) findsNothing` 的依据（免费档上层根本不建本组件）。
///
/// 🔴 日期差一律走 [_dayIndexOf]（UTC 毫秒差）而非 `Duration(days:)` /
/// `DateTime.difference`，避免夏令时（23h/25h 天）把列号算偏一格。
library report_heatmap;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 单格边长（pt）。
const double _kCellSize = 12;

/// 格间距（pt）。
const double _kCellGap = 3;

/// 每格步进 = 边长 + 间距。
const double _kCellStep = _kCellSize + _kCellGap;

/// 行首星期标签宽度（pt），月份刻度行用同一缩进对齐。
const double _kRowLabelWidth = 26;

/// 周内短标签（索引 = `DateTime.weekday - 1`，周一起始）。
///
/// i18n B2：标签改由 ARB 提供（`parent_report_wd_*`），见 [_weekdayShorts]。
List<String> _weekdayShorts(AppLocalizations t) => <String>[
      t.parent_report_wd_mon,
      t.parent_report_wd_tue,
      t.parent_report_wd_wed,
      t.parent_report_wd_thu,
      t.parent_report_wd_fri,
      t.parent_report_wd_sat,
      t.parent_report_wd_sun,
    ];

/// 日期模式（zh 逐字节保留现网 `M月d日`；en 用 `MMM d`）。
///
/// 与 `focus_report_section.dart` / `history_activity_section.dart` 同一口径：
/// 模式串属**本地化格式**而非上屏文案，故按 locale 分支而不进 ARB。
String _datePatternMd(AppLocalizations t) =>
    t.localeName == 'en' ? 'MMM d' : 'M月d日';

/// 近 1 年专注热力图（7 行 × 最多 53 列）。
class ReportHeatmap extends StatelessWidget {
  const ReportHeatmap({
    required this.days,
    required this.unlocked,
    required this.lockedPlaceholder,
    super.key,
  });

  /// 逐日序列（升序、含零值日、末位 = 今天；通常 365 条）。
  final List<DailyFocusPoint> days;

  /// 是否已解锁（免费档直接返回 [lockedPlaceholder]）。
  final bool unlocked;

  /// 未解锁时展示的付费引导卡（由上层 `FocusReportSection` 构造后传入）。
  final Widget lockedPlaceholder;

  /// 把日期折算为「自 1970-01-01 起的天序数」（**UTC 毫秒差**，抗夏令时）。
  static int _dayIndexOf(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;

  /// 色阶（5 档，按当日专注分钟）。
  static Color levelColor(double minutes, ReportPalette palette) {
    if (minutes <= 0) return palette.idle;
    if (minutes < 15) return palette.valid.withValues(alpha: 0.35);
    if (minutes < 30) return palette.valid.withValues(alpha: 0.6);
    if (minutes < 60) return palette.valid.withValues(alpha: 0.85);
    return palette.valid;
  }

  /// 当前连续有效专注日（自末尾往前数，断一天即停）。
  static int _currentStreak(List<DailyFocusPoint> list) {
    int n = 0;
    for (int i = list.length - 1; i >= 0; i--) {
      if (!list[i].isWfd) break;
      n++;
    }
    return n;
  }

  /// 全序列最长连续有效专注日。
  static int _longestStreak(List<DailyFocusPoint> list) {
    int longest = 0;
    int current = 0;
    for (final DailyFocusPoint p in list) {
      if (p.isWfd) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  }

  /// 点格轻提示（1 秒，先清掉上一条）。
  void _showTip(BuildContext context, DailyFocusPoint p) {
    final AppLocalizations t = l10nOf(context);
    final String date = DateFormat(_datePatternMd(t)).format(p.date);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          t.parent_report_heat_tip(date, p.focusMinutes.round()),
        ),
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!unlocked) return lockedPlaceholder;

    final ReportPalette palette = ReportPalette.of(context);
    // i18n B2：文案经 [l10nOf]（页级 scope 内取；裸宿主回退 zh）。
    final AppLocalizations t = l10nOf(context);
    if (days.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.softBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          t.parent_report_heat_empty,
          style: TextStyle(fontSize: 12.5, color: palette.inkAt(0.8)),
        ),
      );
    }

    // 列对齐基准：首日所在周的周一（保证第一列 = 一整周，行号 = weekday-1）。
    final DateTime firstMonday = startOfWeek(days.first.date);
    final int firstIdx = _dayIndexOf(firstMonday);
    final int lastIdx = _dayIndexOf(days.last.date);
    final int columns = ((lastIdx - firstIdx) ~/ 7) + 1;

    final Map<int, DailyFocusPoint> byIndex = <int, DailyFocusPoint>{
      for (final DailyFocusPoint p in days) _dayIndexOf(p.date): p,
    };

    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildMonthTicks(columns, firstIdx, palette, t),
                for (int row = 0; row < 7; row++)
                  _buildRow(
                    context: context,
                    row: row,
                    columns: columns,
                    firstIdx: firstIdx,
                    byIndex: byIndex,
                    palette: palette,
                    t: t,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildLegend(palette, t),
        ],
      ),
    );
  }

  /// 顶部月份刻度：仅在该月「第一列」上方显示 `M月`。
  ///
  /// 列宽只有 15pt 而 `10月` 约 22pt，故用 `OverflowBox` 让文字**向右溢出绘制**
  /// （不是溢出报错），相邻月份相隔 4~5 列，不会互相压字。
  Widget _buildMonthTicks(
    int columns,
    int firstIdx,
    ReportPalette palette,
    AppLocalizations t,
  ) {
    final List<Widget> ticks = <Widget>[];
    int lastMonth = -1;
    for (int c = 0; c < columns; c++) {
      final DateTime monday = DateTime.utc(1970, 1, 1)
          .add(Duration(days: firstIdx + c * 7));
      final bool isFirstOfMonth = monday.month != lastMonth;
      lastMonth = monday.month;
      ticks.add(
        SizedBox(
          width: _kCellStep,
          height: 14,
          child: isFirstOfMonth
              ? OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: 44,
                  child: Text(
                    t.parent_report_month_tick(monday.month),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: palette.inkAt(0.65),
                    ),
                  ),
                )
              : null,
        ),
      );
    }
    return Row(
      children: <Widget>[
        const SizedBox(width: _kRowLabelWidth),
        ...ticks,
      ],
    );
  }

  /// 单行（周内某一天）：左侧短星期 + 各列格子。
  Widget _buildRow({
    required BuildContext context,
    required int row,
    required int columns,
    required int firstIdx,
    required Map<int, DailyFocusPoint> byIndex,
    required ReportPalette palette,
    required AppLocalizations t,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: _kRowLabelWidth,
          height: _kCellStep,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _weekdayShorts(t)[row],
              style: TextStyle(fontSize: 10, color: palette.inkAt(0.65)),
            ),
          ),
        ),
        for (int c = 0; c < columns; c++)
          _buildCell(
            context: context,
            day: byIndex[firstIdx + c * 7 + row],
            palette: palette,
          ),
      ],
    );
  }

  /// 单格：有数据 → 可点（给轻提示）；无数据（未来补位）→ 透明占位。
  Widget _buildCell({
    required BuildContext context,
    required DailyFocusPoint? day,
    required ReportPalette palette,
  }) {
    if (day == null) {
      return const SizedBox(width: _kCellStep, height: _kCellStep);
    }
    return GestureDetector(
      key: ValueKey<String>('heatCell_${day.dayKey}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _showTip(context, day),
      child: Padding(
        padding: const EdgeInsets.all(_kCellGap / 2),
        child: Container(
          width: _kCellSize,
          height: _kCellSize,
          decoration: BoxDecoration(
            color: levelColor(day.focusMinutes, palette),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  /// 图例 `少 ▢▢▢▢▢ 多` + 两枚读数（当前 / 最长连续）。
  ///
  /// 用 `Wrap`：1.3× 文字缩放下自动换行，绝不 `RenderFlex overflow`。
  Widget _buildLegend(ReportPalette palette, AppLocalizations t) {
    final int current = _currentStreak(days);
    final int longest = _longestStreak(days);
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(t.parent_report_legend_less,
                style: TextStyle(fontSize: 11, color: palette.inkAt(0.65))),
            const SizedBox(width: 4),
            for (final double level in <double>[0, 10, 20, 40, 60])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: levelColor(level, palette),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text(t.parent_report_legend_more,
                style: TextStyle(fontSize: 11, color: palette.inkAt(0.65))),
          ],
        ),
        Text(
          t.parent_report_streak_current(current),
          style: TextStyle(fontSize: 12, color: palette.inkAt(0.8)),
        ),
        Text(
          t.parent_report_streak_longest(longest),
          style: TextStyle(fontSize: 12, color: palette.inkAt(0.8)),
        ),
      ],
    );
  }
}
