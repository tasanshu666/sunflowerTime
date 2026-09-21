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
