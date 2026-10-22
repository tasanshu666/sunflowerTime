import 'package:sunflower_time/domain/entities/enums.dart';

/// 奖励模板（PRD §4.8 定价表的最小实体）。
class RewardTemplate {
  final String id;
  final String name;
  final RewardCategory category; // 兑现方式分类（自服务 / 家长经手），与 contentCategory 语义不同
  final RewardContentCategory contentCategory; // 内容分类（零食/游玩/娱乐/其他），默认 other = 历史/未分类安全默认
  final int baseCost; // 家长设定单价：显示价 = 扣费价（2026-09-21 决策，不再叠加分龄系数 K）
  final int frequencyLimitPerWeek;
  final CooldownRule cooldownRule; // 冷却规则（D3，默认每周限领）

  const RewardTemplate({
    required this.id,
    required this.name,
    required this.category,
    this.contentCategory = RewardContentCategory.other,
    required this.baseCost,
    required this.frequencyLimitPerWeek,
    this.cooldownRule = CooldownRule.weekly,
  });

  /// 内容分类占位图标（emoji）。
  ///
  /// i18n B3（T02）：**已删除** `contentCategoryLabel` getter（原实现转发到
  /// `contentCategory.label`，即 domain 里的中文分类名）。分类名统一走
  /// `core/i18n/enum_l10n.dart` 的 `rewardContentCategoryLabel(contentCategory, l10n)`。
  /// [contentCategoryIcon] 保留：emoji 是符号不是文案。
  String get contentCategoryIcon => contentCategory.icon;
}

/// 奖励卡「本周可兑换次数」文案 —— **已迁出 domain**（i18n B3 · T02）。
///
/// 原顶层函数 `weeklyRedeemLabel(limit, used)` 只做文案装配（「不限次数」/
/// 「周限 N 次」），属展示层职责，且中文硬编码违反 domain 零 CJK 纪律。
///
/// 迁移后入口：`core/i18n/domain_text_l10n.dart` 的
/// `weeklyRedeemLabelL10n(limit, used, l10n)`，**返回语义与口径逐字节保留**：
///   · `limit <= 0`          → 「不限次数」（ARB `shared_reward_unlimited`）；
///   · `remaining >= 1`      → 「周限 N 次」（ARB `shared_reward_weekly_limit`，
///     N = 剩余可兑换次数）；
///   · `remaining == 0`      → `null`（隐藏，由卡片禁用态 / 「本周已领」承载）。

