/// 植物物种种子（M3 U2）：3 种，含 0 株稀有（向日葵初始0 + 小雏菊普通 + 仙人掌优良）。
///
/// 口径（§4.6 两档定价，保留稀有度经济平衡；C10 不套用于植物，见架构决策 U3）：
///  · 向日葵：初始物种，cost 0（baseCostHigh/Low 均为 0）；
///  · 小雏菊：普通（common），high 180 / low 72；
///  · 仙人掌：优良（legendary），high 420 / low 168。
///
/// 成长时长（V2，玄参大人 2026-09-22 拍板；不再「统一 24h」）：
///  · 普通植物（向日葵 / 小雏菊）→ [kPlantGrowthHoursPerStageDefault]
///    （240h，每阶段 10 天 → 完全不养护 30 天长成）；
///  · 精品植物（仙人掌 legendary）→ [kPlantGrowthHoursPerStagePremium]
///    （480h，每阶段 20 天 → 完全不养护 60 天长成）。
library plant_seed;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 3 种植物物种种子（首次启动即提供，M3 全部 subscriptionOnly=false）。
const List<PlantSpecies> kSeedPlantSpecies = <PlantSpecies>[
  PlantSpecies(
    id: 'species_sunflower',
    name: '向日葵',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_daisy',
    name: '小雏菊',
    rarity: Rarity.common,
    baseCostHigh: 180,
    baseCostLow: 72,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_cactus',
    name: '仙人掌',
    rarity: Rarity.legendary,
    baseCostHigh: 420,
    baseCostLow: 168,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
];
