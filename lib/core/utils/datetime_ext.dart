/// 时间工具：月池重置（每月 1 日 0 点）、夜间边界判断、日键。
/// 对应架构设计 §1.1（intl）、§3.2（月池每月 1 日 0 点重置）、§6.1（夜间边界唯一值）。
library datetime_ext;

import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';

/// 月份键：形如 `2026-09`，用于 `monthly_pool.month_key` 与按日聚合。
String monthKey(DateTime t) => DateFormat('yyyy-MM').format(t);

/// 日键：形如 `2026-09-15`，用于 `focus_session.day_key` / `sunlight_ledger.day_key`。
String dayKey(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

/// 计算从 [from] 到 [to] 之间「应重置月池」的次数（含跨年）。
///
/// 规则：每月 1 日 0 点重置。若 App 长期未打开，启动即补跑。
/// 例：from=2026-08-15, to=2026-09-10 → 1 次（9 月 1 日）。
int countMonthlyResets(DateTime from, DateTime to) {
  if (to.isBefore(from)) return 0;
  int resets = 0;
  DateTime cursor = DateTime(from.year, from.month + 1, 1);
  while (!cursor.isAfter(to)) {
    resets += 1;
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return resets;
}

/// 是否处于夜间（读 Settings.nightBoundary 唯一值；此处以默认边界做纯函数判断）。
bool isNight(
  DateTime t, {
  int boundaryHour = kNightBoundaryHour,
  int boundaryMinute = kNightBoundaryMinute,
}) {
  final boundary = boundaryHour * 60 + boundaryMinute;
  final now = t.hour * 60 + t.minute;
  // 夜间 = [边界, 24:00) ∪ [00:00, 边界) 视为次日；简化：now >= boundary。
  return now >= boundary;
}
