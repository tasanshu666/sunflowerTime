/// 领域层「文案装配函数」的本地化出口（i18n B3 · T02）。
///
/// ## 为什么存在
/// 迁移前 `lib/domain/**` 里有 4 个**纯文案装配**函数（中文硬编码）：
///  · `perkSummaryTextOf`（称号属性摘要 + 详情卡 tooltip）；
///  · `weeklyRedeemLabel`（奖励卡「周限 N 次」）；
///  · `formatDurationMinutes`（等级详情卡时长）；
///  · `nextLevelGapTextOf`（「距 Lv.N 还差 …」）。
/// 它们没有业务语义，只是拼字符串 —— 属于展示层职责，故整体搬到本文件。
///
/// ## 口径铁律
/// **逐字节等价**：zh 渲染结果与迁移前中文完全一致（现有测试钉死），
/// 故本文件是「换实现，不换文案」：
///  · 时长口径（≥ 60 分钟出小时、余 0 只出小时、负数钳 0）原样保留；
///  · 属性摘要「逐项只输出非零项、` · ` 连接、全 0 输出空串」原样保留；
///  · 周限「limit ≤ 0 → 不限；remaining ≤ 0 → null（隐藏）」原样保留。
library domain_text_l10n;

import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 称号专属属性摘要（升级演出「本称号专属：…」/ 详情卡 tooltip）。
///
/// 逐项只输出**非零**属性，用 ` · ` 连接；[PlantPerk.none] → 空串。
/// 页面禁止写 if-else 拼 9 种（防孪生 S2）。
String perkSummaryTextL10n(PlantPerk p, AppLocalizations t) {
  final List<String> parts = <String>[];
  if (p.waterDiscount > 0) {
    parts.add(t.shared_perk_water_discount(p.waterDiscount));
  }
  if (p.fertilizeDiscount > 0) {
    parts.add(t.shared_perk_fertilize_discount(p.fertilizeDiscount));
  }
  if (p.weedBonus > 0) {
    parts.add(t.shared_perk_weed_bonus(p.weedBonus));
  }
  if (p.pestBonus > 0) {
    parts.add(t.shared_perk_pest_bonus(p.pestBonus));
  }
  if (p.bloomInstantBonus > 0) {
    parts.add(t.shared_perk_bloom_bonus(p.bloomInstantBonus));
  }
  if (p.dewBonus > 0) {
    parts.add(t.shared_perk_dew_bonus(p.dewBonus));
  }
  if (p.eyeCareBonus > 0) {
    parts.add(t.shared_perk_eyecare_bonus(p.eyeCareBonus));
  }
  if (p.expandDiscount > 0) {
    parts.add(t.shared_perk_expand_discount(p.expandDiscount));
  }
  if (p.shovelRefundBonus > 0) {
    parts.add(t.shared_perk_shovel_refund(p.shovelRefundBonus));
  }
  return parts.join(' · ');
}

/// 奖励卡「周限 N 次」标签（替代已删除的顶层 `weeklyRedeemLabel`）。
///
/// 口径（逐字节保留）：
///  · `limit <= 0` → 「不限次数」；
///  · `remaining = limit - used` 钳到 `[0, limit]`；
///  · `remaining >= 1` → 「周限 N 次」（N = 剩余可兑换次数）；
///  · `remaining == 0` → `null`（隐藏，由卡片禁用态 / 「本周已领」承载）。
String? weeklyRedeemLabelL10n(int limit, int used, AppLocalizations t) {
  if (limit <= 0) return t.shared_reward_unlimited;
  final int remaining = (limit - used).clamp(0, limit);
  if (remaining <= 0) return null;
  return t.shared_reward_weekly_limit(remaining);
}

/// 时长展示格式化（≥ 60 分钟 → 「X 小时 Y 分钟」，否则「Y 分钟」）。
///
/// 儿童向：避免把「满级门槛那么大的分钟数」直接给孩子看（C74 §2）。
/// 分钟取余为 0 时只出小时；负数钳到 0（与原 `formatDurationMinutes` 同口径）。
String formatDurationL10n(int minutes, AppLocalizations t) {
  final int safe = minutes < 0 ? 0 : minutes;
  final int h = safe ~/ 60;
  final int m = safe % 60;
  if (h <= 0) return t.shared_duration_minutes(m);
  if (m == 0) return t.shared_duration_hours(h);
  return t.shared_duration_hours_minutes(h, m);
}

/// 等级详情卡副标题：**非满级 → 「距 Lv.{n} 还差 {duration}」；满级 → 满级文案**。
///
/// 数据全部复用 [FocusLevelProgress] 已有字段（`nextLevel` / `minutesToNext`
/// = 下一级门槛分钟 − 累计有效分钟，由 `progressOf` 纯派生），本函数只做文案装配 ——
/// UI 层禁止再重写一遍 duration 算式（S14）。
String nextLevelGapTextL10n(FocusLevelProgress progress, AppLocalizations t) {
  if (progress.isMax) {
    return t.shared_level_gap_max(progress.title);
  }
  final int next = progress.nextLevel ?? progress.level + 1;
  return t.shared_level_gap_next(next, formatDurationL10n(progress.minutesToNext, t));
}

/// 称号节点属性的**名称**（详情卡属性行「👁 护眼 +1 ☀」的「护眼」位）。
///
/// 替代已删除的 `domain/services/plant_perk.dart::perkNameOfTitleNode` +
/// `prd_params.dart::kPerkNames`（9 条中文常量）。**索引对齐关系不变**：
/// `kFocusLevelTitleLevels` 的顺序 = 9 个 `shared_perk_name_*` 的顺序
/// = `kPerkEmojis` / `kPlantPerkPerTitleNode` 的顺序（🔴 勿重排，重排即错位）。
///
/// 非节点（不在 `kFocusLevelTitleLevels` 里）返回**空串** —— 与原实现同口径
/// （属性行按空名渲染 = 视觉上不占位，而不是显示 `null` 或抛错）。
String perkNameOfTitleNodeL10n(int nodeLevel, AppLocalizations t) {
  switch (nodeLevel) {
    case 1:
      return t.shared_perk_name_eye_care;
    case 5:
      return t.shared_perk_name_water;
    case 10:
      return t.shared_perk_name_fertilize;
    case 15:
      return t.shared_perk_name_weed;
    case 20:
      return t.shared_perk_name_pest;
    case 25:
      return t.shared_perk_name_bloom;
    case 30:
      return t.shared_perk_name_dew;
    case 35:
      return t.shared_perk_name_pot_expand;
    case 40:
      return t.shared_perk_name_shovel;
    default:
      return '';
  }
}
