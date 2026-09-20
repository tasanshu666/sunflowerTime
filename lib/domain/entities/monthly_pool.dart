/// 家长月度奖励预算池（PRD §4.8 E9）。
///
/// 仅 spike 判定所需字段：budget 为当月池（100–1200，默认高 400 / 低 160）；
/// used 为家长显式核销扣减累计；autoReleased 为免确认自动放行累计。
/// 二者独立但都受 budget 约束，与阳光账本对账（架构设计 §3.2）。
class MonthlyPool {
  final String monthKey; // e.g. 2026-09
  final int budget;
  final int used;
  final int autoReleased;
  final DateTime? resetAt; // 最近一次重置时间（表列已存在，实体补齐）

  const MonthlyPool({
    required this.monthKey,
    required this.budget,
    this.used = 0,
    this.autoReleased = 0,
    this.resetAt,
  });
}
