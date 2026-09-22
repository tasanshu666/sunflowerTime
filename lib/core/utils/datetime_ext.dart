/// 时间工具：周池重置（每周一 0 点）、夜间边界判断、日键。
/// 对应架构设计 §1.1（intl）、§3.2（周池每周一 0 点重置）、§6.1（夜间边界唯一值）。
library datetime_ext;

import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';

/// 周键：所在周的周一，形如 `2026-09-07`（yyyy-MM-dd），用于周池。
String weekKey(DateTime t) => DateFormat('yyyy-MM-dd').format(_mondayOf(t));

/// 上周周键：用于启动时释放「上周排队」（次周周一自动放行，§4.2）。
String previousWeekKey(DateTime t) => weekKey(t.subtract(const Duration(days: 7)));

/// 取 [t] 所在周的周一（零点）。
DateTime _mondayOf(DateTime t) {
  final int daysSinceMonday = t.weekday - 1;
  return DateTime(t.year, t.month, t.day).subtract(Duration(days: daysSinceMonday));
}

/// 日键：形如 `2026-09-15`，用于 `focus_session.day_key` / `sunlight_ledger.day_key`。
String dayKey(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

/// 月键：形如 `2026-09`（yyyy-MM），用于月度聚合 / 赠予月上限（§4.5 / M3 U5）。
String monthKey(DateTime t) => DateFormat('yyyy-MM').format(t);

/// 是否处于夜间（读 Settings.nightBoundary 唯一值；此处以默认边界做纯函数判断）。
bool isNight(
  DateTime t, {
  int boundaryHour = kNightBoundaryDefaultHour,
  int boundaryMinute = kNightBoundaryMinute,
}) {
  final boundary = boundaryHour * 60 + boundaryMinute;
  final now = t.hour * 60 + t.minute;
  // 夜间 = [边界, 24:00) ∪ [00:00, 边界) 视为次日；简化：now >= boundary。
  return now >= boundary;
}
