import 'package:sunflower_time/domain/entities/enums.dart';

/// 奖励模板（PRD §4.8 定价表的最小实体，spike 仅取兑换判定所需字段）。
class RewardTemplate {
  final String id;
  final String name;
  final RewardCategory category;
  final int baseCostHigh; // 高年级参考定价（消耗侧，未乘 K）
  final int baseCostLow; // 低年级参考定价
  final int frequencyLimitPerWeek;

  const RewardTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.baseCostHigh,
    required this.baseCostLow,
    required this.frequencyLimitPerWeek,
  });
}
