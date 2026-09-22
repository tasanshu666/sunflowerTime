import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 兑换申请的判定结果（S2 纯逻辑，不落库）。
class RedemptionDecision {
  final RequestStatus status;
  final bool autoApproved;
  final String reason;

  const RedemptionDecision({
    required this.status,
    required this.autoApproved,
    required this.reason,
  });
}

/// 兑换服务（S2 spike）：兑换申请状态机 + 免确认双条件判定。
///
/// 口径裁定 C5：免确认须**同时**满足
///  ① 单笔价 ≤ 高 130 / 低 50
///  ② 当月累计自动放行 ≤ 月池 × 25%，且上限 = min(固定天花板 100/40, 月池 × 25%)
///  ③ 自服务类一律 0（不自动放行，走家长放行）
///
/// 状态机：
///  满足双条件        → verified（autoApproved = true）
///  不满足 且 池未满  → pending（待家长显式核销，分母计入核销履约率）
///  不满足 且 池已满  → queued（下月 1 日按申请先后自动放行，不拒绝、不失效）
class RedemptionService {
  RedemptionService._();

  /// 计算本次兑换申请的判定结果（纯函数）。
  ///
  /// [cost] 为已乘分龄系数 K 的消耗侧价（调用方负责 ×K，本服务不乘 K）。
  static RedemptionDecision decide({
    required RewardTemplate template,
    required int cost,
    required AgeTier ageTier,
    required WeeklyPool pool,
  }) {
    final bool isSelfService = template.category == RewardCategory.selfService;
    final AgeTierParams p = kAgeTierParams[ageTier]!;
    final int maxCost = p.autoApproveMaxCost; // C5① 单笔候选阈值（查表）
    final int ceiling = p.autoApproveCapCeiling; // C5② 固定天花板（查表）

    // ② 月累计自动放行上限 = min(固定天花板, 月池 × 25%)
    final int capFromPool = (pool.budget * kAutoApprovePoolRatio).floor();
    final int autoCap = capFromPool < ceiling ? capFromPool : ceiling;

    // ②-a 月度自动放行子限额：当月累计自动放行不得超过 autoCap（C5 ②）
    final bool withinMonthlyCap = (pool.autoReleased + cost) <= autoCap;
    // ②-b 整体池余量：自动放行同样占用月池，池已被家长显式核销(used)占满时不得再自动放行
    final bool withinPool = (pool.used + pool.autoReleased + cost) <= pool.budget;

    final bool cond1 = cost <= maxCost; // ① 单笔价 ≤ 高 130 / 低 50
    final bool cond2 = withinMonthlyCap && withinPool; // ② 双闸
    final bool cond3 = !isSelfService; // ③ 自服务类一律不自动放行

    if (cond1 && cond2 && cond3) {
      return const RedemptionDecision(
        status: RequestStatus.verified,
        autoApproved: true,
        reason: '免确认双条件满足，自动放行',
      );
    }

    // 不满足自动放行 → 判断是否超池（池满则排队，不拒绝、不失效）
    final int projected = pool.used + pool.autoReleased + cost;
    if (projected <= pool.budget) {
      return const RedemptionDecision(
        status: RequestStatus.pending,
        autoApproved: false,
        reason: '进入待核销队列，需家长显式核销',
      );
    }
    return const RedemptionDecision(
      status: RequestStatus.queued,
      autoApproved: false,
      reason: '超池，状态改排队中，下月 1 日按申请先后自动放行',
    );
  }
}
