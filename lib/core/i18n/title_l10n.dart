/// 专注称号文案本地化出口（F144 · D 项）。
///
/// ## 为什么存在
/// 迁移前 9 条称号中文硬编码在 `prd_params.dart::kFocusLevelTitles`，经
/// `focus_level_service.dart::titleOfLevel` / `titleRowsOfLevel` 派生到三处 UI
/// （今日页徽章 / 等级详情卡 / 升级演出卡）。英文模式下这三处**仍显示中文**
/// —— 与 i18n B3 已出清的领域层文案口径不一致。
///
/// 本文件把「称号文案」整体搬到 ARB（`shared_title_lv1` … `shared_title_lv40`），
/// 领域层只保留**纯语义**的节点等级（`kFocusLevelTitleLevels` /
/// `latestTitleNodeOfLevel`），UI 一律经本文件取文案 —— 与
/// `domain_text_l10n.dart::perkNameOfTitleNodeL10n` **同构**。
///
/// ## 口径铁律
///  · **zh 逐字节不变**：9 条 ARB zh 值与迁移前 `kFocusLevelTitles` 完全一致
///    （既有 `find.text('专注小芽…')` 类断言必须仍绿）；
///  · **索引对齐**：`kFocusLevelTitleLevels` 的顺序 = 9 个 `shared_title_lv*`
///    的顺序（1/5/10/15/20/25/30/35/40）—— 🔴 勿重排，重排即错位；
///  · **非节点返回空串**：与原 `titleOfLevel` 同口径（`level < 1` 也是空串，
///    未解锁态由 UI 自行判 `isLocked` 后显示「尚未解锁称号」/ `Locked`）。
library title_l10n;

import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 等级 → **称号文案**（按 9 个称号节点分档；当前称号 = 已解锁的最高节点）。
///
/// [level] 直接接受**等级**（1..40）：内部按「已解锁的最高称号节点」取文案，
/// 故 `level = 7` 返回 Lv.5 节点的称号（等级 ↔ 称号解耦，C74 §3）。
/// 调用方若已算好节点等级，也可直接传节点值（两者在节点上等价）。
///
/// 返回 [level] < 1（含负数）→ 空串（未解锁，UI 走未解锁态文案）。
String focusLevelTitleL10n(int level, AppLocalizations t) {
  if (level < 1) return '';
  // 越界上钳到最高称号（level > 40 ⇒ Lv.40 节点的称号），与原 `titleOfLevel` 一致。
  if (level >= 40) return t.shared_title_lv40;
  if (level >= 35) return t.shared_title_lv35;
  if (level >= 30) return t.shared_title_lv30;
  if (level >= 25) return t.shared_title_lv25;
  if (level >= 20) return t.shared_title_lv20;
  if (level >= 15) return t.shared_title_lv15;
  if (level >= 10) return t.shared_title_lv10;
  if (level >= 5) return t.shared_title_lv5;
  return t.shared_title_lv1;
}

/// **某个称号节点**的称号文案（详情卡「9 行全列」逐行取用）。
///
/// 与 [focusLevelTitleL10n] 的区别只在**入参语义**：本函数入参必须是
/// `kFocusLevelTitleLevels` 里的节点值，非节点（含 `0` / 非 5 的倍数）返回空串
/// —— 详情卡按 `row.level` 逐行取，取到空串说明表格被改坏，属可自证错误。
///
/// 之所以不复用 [focusLevelTitleL10n]：后者会把「Lv.7」映射成 Lv.5 的称号（对
/// 徽章/演出是对的），但详情卡每一行必须显示**自己那个节点**的称号，语义不同。
String focusLevelTitleRowL10n(int nodeLevel, AppLocalizations t) {
  switch (nodeLevel) {
    case 1:
      return t.shared_title_lv1;
    case 5:
      return t.shared_title_lv5;
    case 10:
      return t.shared_title_lv10;
    case 15:
      return t.shared_title_lv15;
    case 20:
      return t.shared_title_lv20;
    case 25:
      return t.shared_title_lv25;
    case 30:
      return t.shared_title_lv30;
    case 35:
      return t.shared_title_lv35;
    case 40:
      return t.shared_title_lv40;
    default:
      return '';
  }
}
