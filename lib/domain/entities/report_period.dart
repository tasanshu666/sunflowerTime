/// 报告周期（专注报告改造 v2，口径裁定 C76）。
///
/// 四档粒度：日 / 周 / 月 / 年。全部按**半开区间** [start, end) 表达，
/// 即「含起点、不含终点」：
///   · 日   = 当日 00:00            → 次日 00:00；
///   · 周   = **周一 00:00**（C55） → 下周一 00:00；
///   · 月   = 自然月 1 日 00:00     → **次月 1 日 00:00**；
///   · 年   = 自然年 1 月 1 日 00:00 → **次年 1 月 1 日 00:00**。
///
/// ⚠️ 月 / 年**禁止**用 `Duration(days: 30)` 之类的定长偏移推算终点——
/// 2 月 / 闰年 / 大小月都会错位；一律用 `DateTime(y, m + 1, 1)` /
/// `DateTime(y + 1, 1, 1)`（Dart 会自动归一化越界月份）。
library report_period;

import 'package:sunflower_time/core/utils/datetime_ext.dart';

/// 报告周期：日 / 周 / 月 / 年（C76）。
///
/// 口径：周 = 周一 00:00 起；月 = 自然月；年 = 自然年；全部**半开区间** [start, end)。
enum ReportPeriod { day, week, month, year }

/// [ReportPeriod] → 区间边界（半开区间 `[startOf, endOf)`）的纯派生扩展。
///
/// 依赖方向 domain → core（本仓既有方向，如 `FocusReportService` 引 `datetime_ext`），
/// 周期起点统一复用 core 的 `startOfDay / startOfWeek / startOfMonth / startOfYear`，
/// 不在本文件重复实现「周一 = weekday - 1」之类算式（防孪生）。
extension ReportPeriodRange on ReportPeriod {
  /// 以 [anchor] 所在周期为准，返回区间起点（含）。
  DateTime startOf(DateTime anchor) {
    switch (this) {
      case ReportPeriod.day:
        return startOfDay(anchor);
      case ReportPeriod.week:
        return startOfWeek(anchor);
      case ReportPeriod.month:
        return startOfMonth(anchor);
      case ReportPeriod.year:
        return startOfYear(anchor);
    }
  }

  /// 半开区间终点（不含）。
  ///
  /// 月 / 年必须用 `DateTime(y, m + 1, 1)` / `DateTime(y + 1, 1, 1)`，
  /// **禁止** `Duration(days: 30)`（大小月 / 闰年 / 年末跨年会错位）。
  DateTime endOf(DateTime anchor) {
    final DateTime start = startOf(anchor);
    switch (this) {
      case ReportPeriod.day:
        return DateTime(start.year, start.month, start.day + 1);
      case ReportPeriod.week:
        return DateTime(start.year, start.month, start.day + 7);
      case ReportPeriod.month:
        return DateTime(start.year, start.month + 1, 1);
      case ReportPeriod.year:
        return DateTime(start.year + 1, 1, 1);
    }
  }
}
