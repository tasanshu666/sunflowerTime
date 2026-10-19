/// 家长周阳光池（PRD §4.8 E9；C90-C 修订）。
///
/// 仅 spike 判定所需字段：budget 为当周池（家长可设 50–500；默认低 200 / 中 400 /
/// **高不限额** —— `budget <= kWeeklyPoolBudgetUnlimited`（0）= 不设上限，
/// 兑换只受阳光余额约束）；used 为家长显式核销扣减累计；autoReleased 为
/// 历史自动放行累计（🔴 C90-C 起不再累加，字段保留以兼容历史行）。
/// 二者独立但都受 budget 约束，与阳光账本对账（架构设计 §3.2）。
class WeeklyPool {
  final String weekKey; // e.g. 2026-09-07（周一）
  final int budget;
  final int used;
  final int autoReleased;
  final DateTime? resetAt; // 最近一次重置时间（表列已存在，实体补齐）

  const WeeklyPool({
    required this.weekKey,
    required this.budget,
    this.used = 0,
    this.autoReleased = 0,
    this.resetAt,
  });
}
