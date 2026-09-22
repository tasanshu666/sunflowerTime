import 'package:sunflower_time/domain/entities/enums.dart';

/// 奖励模板（PRD §4.8 定价表的最小实体）。
class RewardTemplate {
  final String id;
  final String name;
  final RewardCategory category;
  final int baseCost; // 家长设定单价：显示价 = 扣费价（2026-09-21 决策，不再叠加分龄系数 K）
  final int frequencyLimitPerWeek;
  final CooldownRule cooldownRule; // 冷却规则（D3，默认每周限领）

  const RewardTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.baseCost,
    required this.frequencyLimitPerWeek,
    this.cooldownRule = CooldownRule.weekly,
  });
}

/// 计算奖励卡「本周可兑换次数」展示文案（孩子端剩余次数 / 家长端配置次数共用）。
///
/// [limit] = [frequencyLimitPerWeek]（<=0 视为不限次数）；[used] = 本周已领次数
/// （孩子端传 [cooldownCount]，家长端传 0 即配置值本身）。
/// 返回 null 表示无需展示（已领完，由卡片禁用态 / 「本周已领」承载）。
///
/// 口径（与用户原话一致）：
///   · limit<=0          → 「不限次数」；
///   · remaining>=2      → 「可兑换次数为 N」；
///   · remaining==1      → 「仅可兑换 1 次」；
///   · remaining==0      → null（隐藏，避免与「本周已领」重复）。
String? weeklyRedeemLabel(int limit, int used) {
  if (limit <= 0) return '不限次数';
  final int remaining = (limit - used).clamp(0, limit);
  if (remaining <= 0) return null;
  if (remaining == 1) return '仅可兑换 1 次';
  return '可兑换次数为$remaining';
}
