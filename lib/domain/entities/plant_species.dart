import 'package:sunflower_time/domain/entities/enums.dart';

/// 植物物种模板（§3.1 plant_species）。MVP 3 种（§8.2 推迟）。
class PlantSpecies {
  final String id;
  final String name;
  final Rarity rarity;
  final int baseCostHigh; // 高年段基础成本
  final int baseCostLow; // 低年段基础成本
  final double growthHoursPerStage;

  const PlantSpecies({
    required this.id,
    required this.name,
    required this.rarity,
    required this.baseCostHigh,
    required this.baseCostLow,
    required this.growthHoursPerStage,
  });
}
