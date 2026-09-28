import 'package:sunflower_time/domain/entities/enums.dart';

/// 植物物种模板（§3.1 plant_species）。MVP 3 种（§8.2 推迟）。
class PlantSpecies {
  final String id;
  final String name;
  final Rarity rarity;
  final int baseCostHigh; // 高年段基础成本（§4.6 两档，保留稀有度经济平衡）
  final int baseCostLow; // 低年段基础成本
  final double growthHoursPerStage;
  final bool subscriptionOnly; // 是否订阅专属（M3 全部 false，V2 划归）

  const PlantSpecies({
    required this.id,
    required this.name,
    required this.rarity,
    required this.baseCostHigh,
    required this.baseCostLow,
    required this.growthHoursPerStage,
    this.subscriptionOnly = false,
  });

  /// 是否「精品」档（成株后循环玩法 Batch 1 的普通/精品双档差异化判据）。
  ///
  /// 口径（玄参 2026-09-26 拍板）：精品档 = **`rare` + `legendary`**（即除 `common` 外均为精品）。
  /// 精品档复开花节奏 ×[kRebloomPremiumCycleMultiplier]、花期 [kBloomDurationDaysPremium]、
  /// 开花奖励概率更高（见 `plant_growth_service.dart`）。
  bool get isPremium => rarity == Rarity.rare || rarity == Rarity.legendary;
}
