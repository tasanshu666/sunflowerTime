import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 兑换申请的判定结果（S2 纯逻辑，不落库）。
class RedemptionDecision {
  /// 判定走向。C62 起只会是 pending / rejected；末者 = **超周池拒绝**，
  /// 调用方**不得把它落库**（见 [RedemptionService.decide] 与 orchestration.submit）。
  ///
  /// 🔴 C90-C：原 `verified`（免确认自动放行）分支已随自动放行功能删除 ——
  /// 本判定**只会产生 pending / rejected**，核销一律由家长显式完成。
  final RequestStatus status;
  final String reason;

  const RedemptionDecision({
    required this.status,
    required this.reason,
  });
}

/// 兑换服务（S2 spike）：兑换申请状态机。
///
/// 🔴 **C90-C（玄参 2026-10-18 拍板）：自动放行（C5 免确认双条件）设计全删**。
/// 原「单笔 ≤ 130/50 + 周累计 ≤ min(天花板, 池×25%) → verified 自动放行」判定
/// 整体移除；`template` / `ageTier` 形参保留以不动调用点与签名（当前不参与判定）。
///
/// 状态机（**C62，2026-10-13 起停用排队**；C90-C 修订）：
///  周池未超（或不限额）→ pending（待家长显式核销）
///  周池超限（且家长设过额度）→ **rejected**（超周池**直接拒绝**：不生成申请、不扣账本/不扣池）
///
/// 「不设上限」口径（C90-C）：`pool.budget <= kWeeklyPoolBudgetUnlimited`（0）=
/// 高年级默认不限额 —— 兑换只受阳光余额约束（余额闸门在编排层），不判超池。
///
/// ⚠️ `RequestStatus.queued` 成员**保留不动**：它是**按 index 落库**的持久化枚举
/// （pending=0 / queued=1 / verified=2 / rejected=3），删成员会让 verified/rejected
/// 位移 → 存量数据全部错读。C62 只停用「产生新排队」；存量 queued 行仍由
/// `RedemptionOrchestrationService.releaseQueue` 跨周释放。
class RedemptionService {
  RedemptionService._();

  /// 计算本次兑换申请的判定结果（纯函数）。
  ///
  /// [template] / [ageTier] 形参保留以不动调用点与签名（C90-C 删除自动放行后
  /// 当前不参与判定；未来如需按类目/档位分流可复用）。
  static RedemptionDecision decide({
    required RewardTemplate template,
    required int cost,
    required AgeTier ageTier,
    required WeeklyPool pool,
  }) {
    // C90-C：家长设过额度（budget > 0）才做超池判断；0 = 不设上限。
    final int projected = pool.used + pool.autoReleased + cost;
    if (pool.budget > kWeeklyPoolBudgetUnlimited &&
        projected > pool.budget) {
      return const RedemptionDecision(
        status: RequestStatus.rejected,
        // i18n B3（T05）：`reason` 是**开发期说明**（编排层只看 `status`，
        // 页面从不渲染它），故用 ASCII 英文，不进 ARB —— 领域层零 CJK。
        reason: 'over weekly pool: rejected directly since C62 (no queue)',
      );
    }
    return const RedemptionDecision(
      status: RequestStatus.pending,
      reason: 'queued for explicit parent verification',
    );
  }
}
