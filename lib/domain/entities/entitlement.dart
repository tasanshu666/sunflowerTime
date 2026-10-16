/// 权益领域模型（付费墙 · 阶段 1 技术底座）。
///
/// 设计约束（与 `anti_addiction_service.dart` 同风格）：
/// - **纯 Dart，零 Flutter 依赖**——`lib/domain/` 下不得 import flutter，
///   本文件可被 `package:test` / `flutter test` 直接单测；
/// - 本阶段**不接线任何门控点**：默认档位恒为 [EntitlementTier.free]，
///   门控矩阵（`kEntitlementMatrix`）全放开，确保「未开通」行为与今天逐像素一致。
///
/// 背景：老板拍板「先上海外区 App Store + 仅一次性永久买断 + 不做账号 + 不做订阅 +
/// 无后端」。故权益只有「永久买断」一种增量，[Entitlement.tier] 二值即可。
library entitlement;

/// 权益档位。
///
/// - [free]：默认档（未购买 / 无法判定时的安全默认值）；
/// - [premium]：一次性永久买断后解锁。
enum EntitlementTier {
  free,
  premium,
}

/// 可门控的能力点（**门控矩阵的键**，单点收口见 `entitlement_matrix.dart`）。
///
/// 每个值为一个「能力」，其 free / premium 行为由矩阵声明。本阶段矩阵全部放开，
/// 阶段 4 才逐个收紧（届时只改矩阵，不改业务代码）。
enum FeatureKey {
  /// 花园「一键操作」（浇水 / 施肥 / 护理）。
  oneClickCare,

  /// 花园花盆容量上限。
  gardenPotCapacity,

  /// 家长端专注报告。
  parentReport,

  /// 成长项（任务）模板数量上限。
  taskTemplateCount,

  /// 奖励模板数量上限。
  rewardTemplateCount,

  // ── 阶段 3 登记（目标值见 `entitlement_matrix.dart`；本批**仅登记、不收紧**）──

  /// 多孩子档案（免费目标：1 个档案；多档案 = 阶段 2 实现）。
  multiChildProfile,

  /// 深度家长报告（免费目标：仅近 7 天基础区间；完整趋势/对比为付费）。
  deepReport,

  /// 数据导出 / 分享（免费目标：关闭）。
  exportShare,

  /// 纪念册导出（免费目标：关闭）。
  memoirExport,

  /// 家庭共享（免费目标：关闭）。
  familySharing,

  // ── C80 登记（称号属性付费解锁）──

  /// 称号专属属性（9 条：浇水/施肥折扣、扩盆/铲退/绽放/护眼等增益）。
  ///
  /// free = 不生效（`currentPerk()` 回 [PlantPerk.none]），premium = 按等级累积解锁。
  /// 门控判定唯一入口 = `featureAllowedFor(FeatureKey.titlePerks, tier)`。
  titlePerks,
}

/// 一次（永久）买断的权益快照。
///
/// **默认值必须是 [EntitlementTier.free]**——任何「读不到票据 / 平台不可用 / 数据异常」
/// 的路径都回退到此默认，绝不因付费墙逻辑把已购用户误判、也绝不把免费用户误放。
class Entitlement {
  /// 当前档位。
  final EntitlementTier tier;

  /// 购买时间（仅展示用，可为空）。
  final DateTime? acquiredAt;

  /// 商品 ID（识别票据来源；free 时为 null）。
  final String? productId;

  const Entitlement({
    this.tier = EntitlementTier.free,
    this.acquiredAt,
    this.productId,
  });

  /// 安全默认：未开通。
  static const Entitlement free = Entitlement();

  /// 构造一个「永久买断」权益快照（不改状态，仅生成实体）。
  static Entitlement lifetime({
    DateTime? acquiredAt,
    String? productId,
  }) =>
      Entitlement(
        tier: EntitlementTier.premium,
        acquiredAt: acquiredAt,
        productId: productId,
      );

  /// 是否已解锁全部付费能力（**权益侧唯一判定入口**；门控处一律走门控矩阵，勿直接
  /// 用它旁路矩阵——否则阶段 4 收紧某个能力时会漏掉这些旁路点）。
  bool get isPremium => tier == EntitlementTier.premium;

  /// 不可变副本。
  Entitlement copyWith({
    EntitlementTier? tier,
    DateTime? acquiredAt,
    String? productId,
  }) =>
      Entitlement(
        tier: tier ?? this.tier,
        acquiredAt: acquiredAt ?? this.acquiredAt,
        productId: productId ?? this.productId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entitlement &&
          other.tier == tier &&
          other.acquiredAt == acquiredAt &&
          other.productId == productId;

  @override
  int get hashCode => Object.hash(tier, acquiredAt, productId);

  @override
  String toString() =>
      'Entitlement(tier: $tier, productId: $productId, acquiredAt: $acquiredAt)';
}

/// 恢复购买（Restore Purchases）的结果。
///
/// - [restored]：本地票据判定为已购（恢复成功）；
/// - [nothingToRestore]：平台无有效票据（无购买历史 / 未登录同一 Apple ID）；
/// - [failed]：查询过程出错（网络 / 平台异常），UI 应提示「稍后重试」而非谎报未购。
enum RestoreResult {
  restored,
  nothingToRestore,
  failed,
}
