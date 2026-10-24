/// 植物物种种子（玄参 2026-09-27 物种表改版；2026-10-08 删星辰花/虹影蕨 → **6 种**），稀有度收成 2 档。
///
/// ## 口径（玄参 2026-09-27 拍板，一次说完）
///  · 稀有度 UI 只显示「普通 / 精英」两档：精英统一用 [Rarity.rare]（[Rarity.legendary]
///    暂无物种，枚举保留不动）；
///  · **按物种计价**（在物种列表直接兑换并种下；种植本身不额外扣阳光）：
///      - 向日葵 [kStarterSpeciesId] = **免费**（初始物种，阳光价 / 碎片价均为 0）；
///      - 月光兰（精英）= **20 碎片**（[kSpeciesFragmentCostPremium]，精英档仅碎片）；
///      - 番茄 / 草莓（普通）= **10 碎片**（[kSpeciesFragmentCostCommon]）或 **300 阳光**（[kSpeciesSunlightCostCommon]，二选一）；
///      - 珊瑚岭兰 / 翡翠绣球（精英）= **20 碎片**（[kSpeciesFragmentCostPremium]）。
///  · **F144（玄参 2026-10-22 拍板）**：碎片价普通 6 → **10**、精英 10 → **20**
///    （价格只在种下时扣；已种植物与铲除返还「普通 300 / 精英 500 × 50%」不受影响）。
///  · 植物**可重复种植**（C29，2026-10-05）：唯一约束只剩「花盆容量 / 占用」；
///  · 种子掉落保留：掉到某物种种子 = 该物种一张**免费种植券**（种植时消耗券，不扣碎片 / 阳光）。
///
/// ## 列表顺序 = 花园「选择要种的植物」弹窗展示顺序
/// 向日葵（免费）第一、月光兰（精英 · 20 碎片）第二，其后普通 / 精英各按上述顺序。
///
/// ## 成长时长
///  · 普通植物（向日葵 / 番茄 / 草莓）→ [kPlantGrowthHoursPerStageDefault]
///    （240h，每阶段 10 天 → 完全不养护 30 天长成）；
///  · 精英植物（其余 3 种）→ [kPlantGrowthHoursPerStagePremium]
///    （480h，每阶段 20 天 → 完全不养护 60 天长成）。
///
/// ## i18n B3（T05）：`PlantSpecies.name` 是**落库基线，不翻译**
/// 本文件的 `name`（向日葵 / 月光兰 / …）刻意保留中文、**不进 ARB**：
///  · 它是老库 `plant_species.name` 的种子值，改它等于制造「同一物种两个名字」；
///  · 语言切换不该改写已有数据（同 `task_seed` / `reward_seed` 的口径）。
///
/// 上屏的物种名一律经 `core/i18n/species_l10n.dart` 的
/// `speciesNameOr(speciesId, species.name, l10n)` —— 以 **speciesId** 为键查 ARB，
/// 未知 id 才回退 `species.name`（其已被兜成「未知植物」）。见 T04。
library plant_seed;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 6 种植物物种种子（首次启动即提供，全部 subscriptionOnly=false）。
/// 历史：2026-09-27 为 8 种；2026-10-08 玄参删除星辰花（species_star_flower）/
/// 虹影蕨（species_rainbow_fern）→ 6 种（历史库中残留的该物种数据按「未知物种
/// 安全默认」处理，各查找点均有 null 兜底，不做迁移清理）。
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
  // ── 精英档（3 种）────────────────────────────────────────────────────────
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
  // F151（玄参 2026-10-23 拍板）：第 7 种，精英档。物种名上屏走
  // `species_l10n.dart`（ARB `shared_species_grape`），此处 name 仅落库基线。
  PlantSpecies(
    id: 'species_grape',
    name: '葡萄',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
    subscriptionOnly: false,
  ),
];
