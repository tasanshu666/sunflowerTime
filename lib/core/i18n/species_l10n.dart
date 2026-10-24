/// 植物物种名映射（i18n B3 · T04）。
///
/// ## 为什么存在
/// 迁移前物种中文名写死在 `lib/data/local/plant_seed.dart` 的
/// `kSeedPlantSpecies[i].name`（种子数据即文案），UI 各处直接读 `species.name`
/// —— 英文环境下花园里仍是「向日葵 / 月光兰」。
///
/// ## 设计取舍
/// **不改** `PlantSpecies.name`（它是落库基线 + 老数据兼容的锚点，见 T05
/// `plant_seed.dart` 的注释），而是新增 [speciesNameOrNull]：以 **speciesId**
/// 为键查 ARB。这样：
///  · 老库里的物种行、`plants.species_id` 值**零迁移**；
///  · 语言切换即时生效（不碰数据库）；
///  · 未知 id（历史上被删的星辰花 / 虹影蕨）返回 `null`，由调用方决定兜底：
///    - 花盆格 / 植物卡 → `?? species.name`（其 name 已被兜成
///      `garden_unknown_plant` =「未知植物」，语义正确）；
///    - 奖励文案串 → `?? speciesId`（与迁移前 `_speciesNameById` 的兜底一致）。
library species_l10n;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 已知物种 id 列表（6 种，顺序 = 花园「选择要种的植物」弹窗顺序）。
///
/// 与 `lib/data/local/plant_seed.dart` 的 `kSeedPlantSpecies` 一一对应；
/// 单独列在这里是为了让本文件零 dart:ui / 零数据层依赖（纯 switch 映射）。
const List<String> kKnownSpeciesIds = <String>[
  kStarterSpeciesId, // species_sunflower 向日葵
  'species_moon_orchid', // 月光兰
  'species_tomato', // 番茄
  'species_strawberry', // 草莓
  'species_coral_orchid', // 珊瑚岭兰
  'species_jade_hydrangea', // 翡翠绣球
  'species_grape', // 葡萄（F151，精英档）
];

/// speciesId → 当前语言的物种名；**未知 id 返回 `null`**（调用方决定兜底）。
///
/// 兜底纪律：不要在这里返回 id 或「未知植物」—— 花盆格与奖励串的兜底口径不同
/// （前者要「未知植物」、后者要原始 id），把口径留在调用点才不会被统一错。
String? speciesNameOrNull(String speciesId, AppLocalizations t) {
  switch (speciesId) {
    case kStarterSpeciesId:
      return t.shared_species_sunflower;
    case 'species_moon_orchid':
      return t.shared_species_moon_orchid;
    case 'species_tomato':
      return t.shared_species_tomato;
    case 'species_strawberry':
      return t.shared_species_strawberry;
    case 'species_coral_orchid':
      return t.shared_species_coral_orchid;
    case 'species_jade_hydrangea':
      return t.shared_species_jade_hydrangea;
    case 'species_grape':
      return t.shared_species_grape;
    default:
      return null;
  }
}

/// speciesId → 当前语言的物种名；未知 id 回退到 [fallback]（通常是
/// `species.name`，已含「未知植物」兜底）。
///
/// 这是花盆格 / 植物卡 / 选择弹窗的**推荐入口**：既有兜底、又不丢 id。
String speciesNameOr(String speciesId, String fallback, AppLocalizations t) =>
    speciesNameOrNull(speciesId, t) ?? fallback;
