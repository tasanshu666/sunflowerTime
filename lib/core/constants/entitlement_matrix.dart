/// 门控能力矩阵 —— **付费墙门控的唯一收口**（付费墙 · 阶段 1 技术底座）。
///
/// 设计纪律（架构 §「门控单点收口」）：
/// - 每个门控点的 free / premium 行为与额度**只在此处声明**；业务代码与
///   [`PremiumGate`] / [`EntitlementService`] 一律读矩阵，禁止各自散落判断
///   （否则阶段 4 逐个收紧时会漏点，产生「判定孪生」）。
/// - 纯 Dart 常量，零平台依赖，可被纯逻辑单测直接断言。
///
/// ⚠️⚠️ **阶段 1 全部放开（免费行为 = 现状）**：下表每一项的 free 都与 premium
/// **完全等价**（均 enabled 且额度一致），故「未开通」用户行为与今天**逐像素一致**。
/// 这是刻意的——本轮只做技术底座、不接线任何门控点。
/// **阶段 4 才会逐个收紧**：届时将对应项的 `freeEnabled` 置 false 或把 `freeQuota`
/// 调小即可，业务代码零改动。
library entitlement_matrix;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

/// 「不限额度」哨兵值：额度为它表示该项不做次数 / 数量限制。
const int kUnlimitedQuota = -1;

// ───────────────────────────────────────────────────────────────────────────
// 免费边界目标值（付费墙 · 阶段 3 登记）
//
// 🔴 **本批只登记、不收紧**：下列具名常量是**阶段 4 收紧时要写入各 FeatureRule
//    `freeQuota` / `freeEnabled` 的目标值**，现在仅作「单点声明 + 防漂移」，
//    **不参与任何判定** —— 本批所有 `freeEnabled` 仍为 true、`freeQuota` 仍为
//    [kUnlimitedQuota]，行为与阶段 1 逐像素一致。
//
// 口径（已拍板）：免费增值 + 一次性买断。免费边界 = 核心循环 + 防沉迷 + 护眼 +
// 1 个孩子档案 + 任务/奖励各 5 条 + 花盆 4 个 + 近 7 天报告。
// ───────────────────────────────────────────────────────────────────────────

/// 免费档成长项（任务）模板数量上限（阶段 4 目标值 = 5）。
const int kFreeTaskQuota = 5;

/// 免费档奖励模板数量上限（阶段 4 目标值 = 5）。
const int kFreeRewardQuota = 5;

/// 免费档孩子档案数量上限（阶段 4 目标值 = 1）。
const int kFreeChildProfileCount = 1;

/// 免费档花盆容量上限（阶段 4 目标值）。
///
/// ⚠️ **必须引用** [`kGardenPotCapacityDefault`]（PRD 基础容量），**不得另写死 4**
/// —— 否则 PRD 调基础容量时两处漂移。
const int kFreeGardenPotQuota = kGardenPotCapacityDefault;

/// 买断档花盆容量上限（阶段 4 目标值）。
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
/// 阶段 1：每项 free == premium（全放开）。阶段 4 逐个收紧时只改本表。
const Map<FeatureKey, FeatureRule> kEntitlementMatrix = <FeatureKey, FeatureRule>{
  // 花园「一键操作」：阶段 1 免费不限（阶段 4 计划：free 关闭，premium 开启）。
  FeatureKey.oneClickCare: FeatureRule(
    key: FeatureKey.oneClickCare,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 花园花盆容量：阶段 1 免费与 premium 一致（阶段 4 计划：free 收窄到基础容量）。
  FeatureKey.gardenPotCapacity: FeatureRule(
    key: FeatureKey.gardenPotCapacity,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 家长端专注报告：阶段 1 免费开放（阶段 4 计划：free 关闭 / 仅基础区间）。
  FeatureKey.parentReport: FeatureRule(
    key: FeatureKey.parentReport,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 成长项（任务）模板数量：阶段 1 免费不限（阶段 4 计划：free 限制条数）。
  FeatureKey.taskTemplateCount: FeatureRule(
    key: FeatureKey.taskTemplateCount,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 奖励模板数量：阶段 1 免费不限（阶段 4 计划：free 限制条数）。
  FeatureKey.rewardTemplateCount: FeatureRule(
    key: FeatureKey.rewardTemplateCount,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // ⚠️ 以下五项为阶段 3 **登记**（新增能力点）；本批仍全放开（free == premium），
  //    阶段 4 再按免费边界目标值（见上方常量）逐个收紧。
  // 多孩子档案：阶段 1/3 免费不限（阶段 4 目标：free 限 [kFreeChildProfileCount] 个）。
  FeatureKey.multiChildProfile: FeatureRule(
    key: FeatureKey.multiChildProfile,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 深度报告：阶段 1/3 免费开放（阶段 4 目标：free 关闭，或仅基础区间）。
  FeatureKey.deepReport: FeatureRule(
    key: FeatureKey.deepReport,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 导出 / 分享：阶段 1/3 免费开放（阶段 4 目标：free 关闭）。
  FeatureKey.exportShare: FeatureRule(
    key: FeatureKey.exportShare,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 纪念册导出：阶段 1/3 免费开放（阶段 4 目标：free 关闭）。
  FeatureKey.memoirExport: FeatureRule(
    key: FeatureKey.memoirExport,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
  // 家庭共享：阶段 1/3 免费开放（阶段 4 目标：free 关闭）。
  FeatureKey.familySharing: FeatureRule(
    key: FeatureKey.familySharing,
    freeEnabled: true,
    freeQuota: kUnlimitedQuota,
    premiumQuota: kUnlimitedQuota,
  ),
};

/// 便捷判定：给定能力点与档位，是否允许（未登记 = 不门控，安全放行）。
///
/// 这是矩阵判定的**唯一实现入口**；[EntitlementService.can] 与 [`PremiumGate`]
/// 均委托到此，杜绝判定孪生。[matrix] 仅供测试注入自定义矩阵。
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
