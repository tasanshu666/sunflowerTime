import 'package:sunflower_time/domain/entities/enums.dart';

/// 奖励模板（PRD §4.8 定价表的最小实体）。
class RewardTemplate {
  final String id;
  final String name;
  final RewardCategory category;
  final int baseCost; // 单基准价（消耗侧，未乘 K；价格 = applyAgeTierK(baseCost, tier)）
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
