/// 物种图鉴文案本地化出口（F147）。
///
/// ## 为什么存在
/// 迁移前 6 个物种的**简短介绍 + 小故事**（C29 种植卡「翻面」背面文案，玄参
/// 2026-10-05 需求）硬编码中文在 `core/constants/species_lore.dart`，唯一消费点
/// `garden_page.dart::_backFace`。英文模式下选种卡翻面后**标题已英文**
/// （`speciesNameOr` 走 `core/i18n/species_name_l10n.dart`），介绍和故事**仍是
/// 中文** —— 与称号文案 `core/i18n/title_l10n.dart` 同类的 i18n 残留。
///
/// 本文件把文案整体搬到 ARB（`species_lore_{id}_intro/_story` +
/// `species_lore_fallback_intro/_story`，共 14 条），并按 id 取用 —— 与
/// `title_l10n.dart::focusLevelTitleRowL10n` **同构**：
///  · **zh 逐字节不变**：14 条 ARB zh 值与迁移前 `kSpeciesLore` /
///    `kFallbackSpeciesLore` 完全一致（守卫见
///    `test/i18n/species_lore_l10n_test.dart`）；
///  · **纯语义 id 判断**：本文件只认物种 id 字符串，不知道任何稀有度 / 解锁
///    状态；未知 id（如老库自造、2026-10-08 已删的 star_flower / rainbow_fern）
///    回退 fallback 文案，不会崩；
///  · **单点真源**：`core/constants/species_lore.dart` 已整体删除，防止
///    「迁了 ARB 但 UI 仍读常量」的双真源假迁移。
library species_lore_l10n;

import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 一条物种图鉴文案。
class SpeciesLore {
  const SpeciesLore({required this.intro, required this.story});

  /// 一句话介绍（卡片背面第二行）。
  final String intro;

  /// 小故事（卡片背面正文，2~3 行内）。
  final String story;
}

/// 取物种图鉴文案（未知 id → fallback 文案）。
///
/// id 与 `plant_seed.dart` 物种表一致；`species_star_flower` /
/// `species_rainbow_fern`（2026-10-08 玄参删除）等未知 id 一律回退
/// `species_lore_fallback_*`。
SpeciesLore speciesLoreL10n(String speciesId, AppLocalizations t) {
  switch (speciesId) {
    case 'species_sunflower':
      return SpeciesLore(
          intro: t.species_lore_sunflower_intro,
          story: t.species_lore_sunflower_story);
    case 'species_tomato':
      return SpeciesLore(
          intro: t.species_lore_tomato_intro,
          story: t.species_lore_tomato_story);
    case 'species_strawberry':
      return SpeciesLore(
          intro: t.species_lore_strawberry_intro,
          story: t.species_lore_strawberry_story);
    case 'species_moon_orchid':
      return SpeciesLore(
          intro: t.species_lore_moon_orchid_intro,
          story: t.species_lore_moon_orchid_story);
    case 'species_coral_orchid':
      return SpeciesLore(
          intro: t.species_lore_coral_orchid_intro,
          story: t.species_lore_coral_orchid_story);
    case 'species_jade_hydrangea':
      return SpeciesLore(
          intro: t.species_lore_jade_hydrangea_intro,
          story: t.species_lore_jade_hydrangea_story);
    default:
      return SpeciesLore(
          intro: t.species_lore_fallback_intro,
          story: t.species_lore_fallback_story);
  }
}
