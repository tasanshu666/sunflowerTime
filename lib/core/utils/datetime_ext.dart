/// 时间工具：周池重置（每周一 0 点）、夜间边界判断、日键、周期起点纯函数。
/// 对应架构设计 §1.1（intl）、§3.2（周池每周一 0 点重置）、§6.1（夜间边界唯一值）、
/// C55 / C76（期间口径：周一为始 / 自然月 / 自然年 / 半开区间）。
library datetime_ext;

import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';

// ───────────────────────────────────────────────────────────────────────────
// 周期起点纯函数（C55 / C76 单点：周起始 / 月起始 / 年起始**只在此处算一遍**）。
//
// 消费方：`datetime_ext.weekKey`（周池）、`domain/entities/report_period.dart`
// （专注报告 v2 的日/周/月/年半开区间）。记录页 / 报告页**不得**再自写
// `t.weekday - 1` 之类的算式（防孪生宪法总纪律 #2）。
// ⚠️ 本文件属 core 层，**禁止** import 任何 domain 类型（依赖方向 core ← domain）。
// ───────────────────────────────────────────────────────────────────────────

/// 取 [t] 当日 **0 点**（自然日边界，本地时区）。
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// 取 [t] 所在周的 **周一 0 点**（周池 / 报告「周」口径，§3.2 / C55）。
DateTime startOfWeek(DateTime t) =>
    startOfDay(t).subtract(Duration(days: t.weekday - 1));

/// 取 [t] 所在自然月的 **1 日 0 点**（报告「月」口径，C76）。
DateTime startOfMonth(DateTime t) => DateTime(t.year, t.month, 1);

/// 取 [t] 所在自然年的 **1 月 1 日 0 点**（报告「年」口径，C76）。
DateTime startOfYear(DateTime t) => DateTime(t.year, 1, 1);

/// 周键：所在周的周一，形如 `2026-09-07`（yyyy-MM-dd），用于周池。
String weekKey(DateTime t) => DateFormat('yyyy-MM-dd').format(_mondayOf(t));

/// 上周周键：用于启动时释放「上周排队」（次周周一自动放行，§4.2）。
String previousWeekKey(DateTime t) => weekKey(t.subtract(const Duration(days: 7)));

/// 取 [t] 所在周的周一（零点）。
///
/// C76 起**只是 [startOfWeek] 的别名**，不再自算 `t.weekday - 1`——
/// 行为与改前逐字节一致（`weekKey` / `previousWeekKey` 结果不变），仅消除孪生。
DateTime _mondayOf(DateTime t) => startOfWeek(t);

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
