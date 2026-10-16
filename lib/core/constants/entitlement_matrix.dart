/// 门控能力矩阵 —— **付费墙门控的唯一收口**（付费墙 · 阶段 1 底座 / 阶段 4 收紧）。
///
/// 设计纪律（架构 §「门控单点收口」）：
/// - 每个门控点的 free / premium 行为与额度**只在此处声明**；业务代码与
///   [`PremiumGate`] / [`PremiumQuotaGate`] / `EntitlementService` 一律读矩阵，
///   禁止各自散落判断（否则会漏点，产生「判定孪生」）。
/// - 纯 Dart 常量，零平台依赖，可被纯逻辑单测直接断言。
///
/// ⚠️⚠️ **阶段 4 已收紧其中 5 项**（`oneClickCare` / `gardenPotCapacity` /
/// `taskTemplateCount` / `rewardTemplateCount` / `deepReport`）；其余（`parentReport`
/// + 4 个未实现键）**保持免费放开**。
///
/// 🔴 红线 C69：额度超限**只拦新增、绝不删已存数据** —— 判定点只落在「新增动作」
/// 入口（见 [quotaAllowsAdd]），绝不落在列表 / settings 的规范化上。
library entitlement_matrix;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

/// 「不限额度」哨兵值：额度为它表示该项不做次数 / 数量限制。
const int kUnlimitedQuota = -1;

// ───────────────────────────────────────────────────────────────────────────
// 免费边界目标值（付费墙 · 阶段 3 登记 → 阶段 4 启用）
//
// 口径（已拍板）：免费增值 + 一次性买断。免费边界 = 核心循环 + 防沉迷 + 护眼 +
// 1 个孩子档案 + 任务/奖励各 5 条 + 花盆 4 个 + 近 7 天报告（4 周深度区付费）。
// ───────────────────────────────────────────────────────────────────────────

/// 免费档成长项（任务）模板数量上限（= 5）。
const int kFreeTaskQuota = 5;

/// 免费档奖励模板数量上限（= 5）。
const int kFreeRewardQuota = 5;

/// 免费档孩子档案数量上限（= 1）。
///
/// ⚠️ 本期**未接门控**（多档案功能尚未实现），仅作目标值登记；阶段 N 实现后再接。
const int kFreeChildProfileCount = 1;

/// 免费档花盆容量上限。
///
/// ⚠️ **必须引用** [`kGardenPotCapacityDefault`]（PRD 基础容量），**不得另写死 4**
/// —— 否则 PRD 调基础容量时两处漂移。
const int kFreeGardenPotQuota = kGardenPotCapacityDefault;

/// 买断档花盆容量上限。
///
/// ⚠️ **必须引用** [`kGardenPotCapacityMax`]（PRD 解锁上限），**不得另写死 12**。
const int kPremiumGardenPotQuota = kGardenPotCapacityMax;

/// 单个门控点的规则（free / premium 的开关与额度）。
///
/// 判定逻辑集中在此，避免调用方各写 `tier == premium ? A : B` 三元。
class FeatureRule {
  /// 该规则对应的能力点（与映射表的键一致，便于自检 / 排查）。
  final FeatureKey key;

  /// free 档是否可用该能力。
  final bool freeEnabled;

  /// free 档额度（[kUnlimitedQuota] = 不限）。
  final int freeQuota;

  /// premium 档是否可用该能力（永久买断后恒 true）。
  final bool premiumEnabled;

  /// premium 档额度（[kUnlimitedQuota] = 不限）。
  final int premiumQuota;

  const FeatureRule({
    required this.key,
    required this.freeEnabled,
    required this.freeQuota,
    this.premiumEnabled = true,
    required this.premiumQuota,
  });

  /// 该档位下能力是否可用。
  bool isEnabledFor(EntitlementTier tier) =>
      tier == EntitlementTier.premium ? premiumEnabled : freeEnabled;

  /// 该档位下能力额度（[kUnlimitedQuota] = 不限）。
  int quotaFor(EntitlementTier tier) =>
      tier == EntitlementTier.premium ? premiumQuota : freeQuota;
}

/// 门控能力矩阵（**单点收口**）。
///
/// 阶段 4：5 项按免费边界收紧（free 关闭 / 额度受限），其余保持放开。
const Map<FeatureKey, FeatureRule> kEntitlementMatrix = <FeatureKey, FeatureRule>{
  // 花园「一键操作」（阶段 4 收紧）：免费版**关闭**（free 隐藏一键 FAB；单株
  // 浇水 / 施肥 / 护理仍在，功能不退化），买断后不限。D3 拍板。
  FeatureKey.oneClickCare: FeatureRule(
    key: FeatureKey.oneClickCare,
    freeEnabled: false,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 花园花盆容量（阶段 4 收紧）：免费 = 基础容量（[kFreeGardenPotQuota] = 4），
  // 买断 = 解锁上限（[kPremiumGardenPotQuota] = 12）。只拦「扩容」，不压已有盆位。D4 拍板。
  FeatureKey.gardenPotCapacity: FeatureRule(
    key: FeatureKey.gardenPotCapacity,
    freeEnabled: true,
    freeQuota: kFreeGardenPotQuota,
    premiumQuota: kPremiumGardenPotQuota,
  ),
  // 家长端专注报告（阶段 4 **保持免费开启**）：兑现 C69 免费边界「近 7 天报告」；
  // 4 周深度区由 [FeatureKey.deepReport] 承担分层。⚠️ 报告页门控本批缓做。
  FeatureKey.parentReport: FeatureRule(
    key: FeatureKey.parentReport,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 成长项（任务）模板数量（阶段 4 收紧）：免费 = [kFreeTaskQuota]（5），买断不限。
  // 只拦「新增」，编辑 / 删除照常（存量超额：可编辑 / 可删、不能新增）。C69 红线。
  FeatureKey.taskTemplateCount: FeatureRule(
    key: FeatureKey.taskTemplateCount,
    freeEnabled: true,
    freeQuota: kFreeTaskQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 奖励模板数量（阶段 4 收紧）：免费 = [kFreeRewardQuota]（5），买断不限。同上只拦新增。
  FeatureKey.rewardTemplateCount: FeatureRule(
    key: FeatureKey.rewardTemplateCount,
    freeEnabled: true,
    freeQuota: kFreeRewardQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // ── 以下为「功能尚未实现」的键：🔴 **不接门控**（Apple 3.1.1/2.3.1 拒审风险）
  //    —— 行文保持 freeEnabled:true / kUnlimitedQuota = 现状（等价放行）。
  // 多孩子档案（未实现，无档案实体 / 无 UI）：TODO(阶段N) 实现后按 [kFreeChildProfileCount] 收紧。
  FeatureKey.multiChildProfile: FeatureRule(
    key: FeatureKey.multiChildProfile,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 深度报告（阶段 4 收紧）：免费关闭，买断不限。⚠️ 报告页接线本批缓做（先做报告改造）。
  FeatureKey.deepReport: FeatureRule(
    key: FeatureKey.deepReport,
    freeEnabled: false,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 导出 / 分享（未实现，无导出 UI）：TODO(阶段N) 实现后再接门控。
  FeatureKey.exportShare: FeatureRule(
    key: FeatureKey.exportShare,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 纪念册导出（未实现，无页面）：TODO(阶段N) 实现后再接门控。
  FeatureKey.memoirExport: FeatureRule(
    key: FeatureKey.memoirExport,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 家庭共享（未实现，linkFamily 直接抛 UnsupportedError）：TODO(阶段N) 实现后再接门控。
  FeatureKey.familySharing: FeatureRule(
    key: FeatureKey.familySharing,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // ── C80 · 称号专属属性（真门控）：免费 = 关闭（当前属性恒为 none），
  //    买断 = 按等级累积解锁（见 `kPlantPerkPerTitleNode`）。
  //    门控判定唯一入口 = `featureAllowedFor(FeatureKey.titlePerks, tier)`；
  //    UI（详情卡 / 演出卡）与域层（`PlantGrowthService.currentPerk`）均走此判定。
  FeatureKey.titlePerks: FeatureRule(
    key: FeatureKey.titlePerks,
    freeEnabled: false,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
};

/// 便捷判定：给定能力点与档位，是否允许（未登记 = 不门控，安全放行）。
///
/// 这是矩阵「布尔能力」判定的**唯一实现入口**；`EntitlementService.can` 与
/// [`PremiumGate`] 均委托到此，杜绝判定孪生。[matrix] 仅供测试注入自定义矩阵。
bool featureAllowedFor(
  FeatureKey feature,
  EntitlementTier tier, {
  Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
}) {
  final FeatureRule? rule = matrix[feature];
  if (rule == null) return true; // 未登记的能力 = 不在付费墙内 → 放行
  return rule.isEnabledFor(tier);
}

/// 便捷查询：给定能力点与档位，额度是多少（未登记 = 不限）。
int featureQuotaFor(
  FeatureKey feature,
  EntitlementTier tier, {
  Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
}) {
  final FeatureRule? rule = matrix[feature];
  return rule?.quotaFor(tier) ?? kUnlimitedQuota;
}

/// 「新增」是否放行（**唯一配额判定入口**，杜绝判定孪生）。
///
/// 判定次序：
///   1. 整项能力被该档位关闭（[featureAllowedFor] == false）→ **false**；
///   2. 额度不限（[kUnlimitedQuota]）→ **true**；
///   3. 否则 → `currentCount < 额度`（达到 / 超过额度一律拦新增）。
///
/// 🔴 红线 C69：本函数**只读**计数、**绝不**删除任何已存数据；达到 / 超过额度时
/// 已存条目**只读保留**（可编辑 / 可删除），待用户手动删除降到 `< 额度` 后自然恢复。
bool quotaAllowsAdd(
  FeatureKey feature,
  EntitlementTier tier,
  int currentCount, {
  Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
}) {
  if (!featureAllowedFor(feature, tier, matrix: matrix)) return false;
  final int quota = featureQuotaFor(feature, tier, matrix: matrix);
  return quota == kUnlimitedQuota || currentCount < quota;
}
