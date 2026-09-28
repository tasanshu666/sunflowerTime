/// 植物物种种子（玄参 2026-09-27 物种表改版）：**8 种**，稀有度收成 2 档。
///
/// ## 口径（玄参 2026-09-27 拍板，一次说完）
///  · 稀有度 UI 只显示「普通 / 精英」两档：精英统一用 [Rarity.rare]（[Rarity.legendary]
///    暂无物种，枚举保留不动）；
///  · **按物种计价**（在物种列表直接兑换并种下；种植本身不额外扣阳光）：
///      - 向日葵 [kStarterSpeciesId] = **免费**（初始物种，阳光价 / 碎片价均为 0）；
///      - 月光兰（精英）= **10 碎片**（[kSpeciesFragmentCostPremium]，精英档仅碎片）；
///      - 番茄 / 草莓（普通）= **6 碎片**（[kSpeciesFragmentCostCommon]）或 **400 阳光**（[kSpeciesSunlightCostCommon]，二选一）；
///      - 星辰花 / 虹影蕨 / 珊瑚岭兰 / 翡翠绣球（精英）= **10 碎片**（[kSpeciesFragmentCostPremium]）。
///  · **每物种同时仅存活一株**；植株死亡 / 移除后再种需**重新交费**（= 一次兑换买一株）；
///  · 种子掉落保留：掉到某物种种子 = 该物种一张**免费种植券**（种植时消耗券，不扣碎片 / 阳光）。
///
/// ## 列表顺序 = 花园「选择要种的植物」弹窗展示顺序
/// 向日葵（免费）第一、月光兰（精英 · 10 碎片）第二，其后普通 / 精英各按上述顺序。
///
/// ## 成长时长
///  · 普通植物（向日葵 / 番茄 / 草莓）→ [kPlantGrowthHoursPerStageDefault]
///    （240h，每阶段 10 天 → 完全不养护 30 天长成）；
///  · 精英植物（其余 5 种）→ [kPlantGrowthHoursPerStagePremium]
///    （480h，每阶段 20 天 → 完全不养护 60 天长成）。
library plant_seed;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 8 种植物物种种子（首次启动即提供，全部 subscriptionOnly=false）。
const List<PlantSpecies> kSeedPlantSpecies = <PlantSpecies>[
  // ── 普通档（3 种）────────────────────────────────────────────────────────
  PlantSpecies(
    id: kStarterSpeciesId,
    name: '向日葵',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_moon_orchid',
    name: '月光兰',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_tomato',
    name: '番茄',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_strawberry',
    name: '草莓',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    subscriptionOnly: false,
  ),
  // ── 精英档（5 种）────────────────────────────────────────────────────────
  PlantSpecies(
    id: 'species_star_flower',
    name: '星辰花',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_rainbow_fern',
    name: '虹影蕨',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_coral_orchid',
    name: '珊瑚岭兰',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
  PlantSpecies(
    id: 'species_jade_hydrangea',
    name: '翡翠绣球',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
];
