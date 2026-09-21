/// 兑换编排服务（§2.4 / §3.2 / §4.1–4.3）：M2 核心。
///
/// 在 S2 纯判定 [RedemptionService.decide] 之上做完整兑换链路：
/// 读模板 → 算价（baseCost，2026-09-21 起不再叠加分龄系数 K）→ 取/建周池 →
/// decide() → 落 RedemptionRequest → 扣账本 → 更新池 → 埋点。
/// **不改动 decide() 的判定语义**（13 单测回归基线）。
///
/// 设计纪律（§7）：
///  · 2026-09-21 决策：定价不再叠加分龄系数 K，显示价 = 扣费价 = baseCost；
///    `k` 字段与 `ageTierK()` 保留为档位参数单点，但生产定价链路不得再调用；
///  · ledger 单一账本 + 周池独立对账：每笔兑换（自动放行/家长核销/次周排队释放）
///    都写一条 SunlightEntry，且 queued 状态**绝不**提前扣账本/扣池；
///  · 阳光不足 / 冷却未过 → 不生成申请、不埋 reward_* 事件。
library redemption_orchestration_service;

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/domain/services/redemption_service.dart';

/// submit() 的结果类别。
enum SubmitOutcome {
  verified, // 免确认自动放行
  pending, // 待家长核销
  queued, // 超池排队（次周释放）
  rejectedCooldown, // 冷却中（每周限领 1 次）
  rejectedBalance, // 阳光余额不足
}

/// submit() 返回值（不可变）。
class SubmitResult {
  final SubmitOutcome outcome;
  final String? requestId;
  final int? cost;
  final bool autoApproved;
  final int? queueRank;

  const SubmitResult({
    required this.outcome,
    this.requestId,
    this.cost,
    this.autoApproved = false,
    this.queueRank,
  });
}

/// releaseQueue() 返回值（不可变）。
class ReleaseReport {
  final int released; // 本次成功释放数
  final int deferred; // 顺延至下周数

  const ReleaseReport(this.released, this.deferred);
}

/// 兑换编排服务。
class RedemptionOrchestrationService {
  final RewardRepository _reward;
  final WeeklyPoolService _pools;
  final SunlightRepository _ledger;
  final TrackingRepository _tracking;
  final AccountService _account;
  final SettingsRepository _settings;

  /// 每个服务实例一个 id 生成器（Uuid() 非 const，用作字段初始化）。
  final Uuid _uuid = Uuid();

  RedemptionOrchestrationService({
    required RewardRepository reward,
    required WeeklyPoolService pools,
    required SunlightRepository ledger,
    required TrackingRepository tracking,
    required AccountService account,
    required SettingsRepository settings,
  })  : _reward = reward,
        _pools = pools,
        _ledger = ledger,
        _tracking = tracking,
        _account = account,
        _settings = settings;

  /// 消耗侧价格：2026-09-21 决策后不再叠加分龄系数 K —— 显示价 = 扣费价 = 家长设定价。
  ///
  /// [tier] 形参保留以不动调用点与签名（未来如需分档展示可复用，但当前不参与定价）。
  int _priceFor(RewardTemplate t, AgeTier tier) => t.baseCost;

  /// 冷却判定：本周已领次数 ≥ 该模板的每周限领次数（frequencyLimitPerWeek）。
  /// frequencyLimitPerWeek <= 0 视为不限次数（永不冷却，按钮不灰）。
  Future<bool> _onCooldown(RewardTemplate t) async {
    if (t.frequencyLimitPerWeek <= 0) return false;
    return (await _reward.cooldownCount(t.id, CooldownPeriod.weekly)) >=
        t.frequencyLimitPerWeek;
  }

  /// 孩子端发起一笔兑换（§4.1 时序）。
  /// [forcePending]：孩子端发起时传 true，强制走「待家长核销」——不立即扣账本，
  /// 阳光扣减延后到 [verify]（家长确认）时才发生。
  Future<SubmitResult> submit(
    String templateId,
    AgeTier ageTier,
    DateTime now, {
    bool forcePending = false,
  }) async {
    final List<RewardTemplate> templates = await _reward.templates();
    final RewardTemplate tpl = templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw StateError('no template'),
    );

    // 冷却未过 → 拒绝（不生成申请、不埋 reward_*）。
    if (await _onCooldown(tpl)) {
      return const SubmitResult(outcome: SubmitOutcome.rejectedCooldown);
    }

    final WeeklyPool pool = await _pools.ensureAndReset(now);
    final int cost = _priceFor(tpl, ageTier);

    // 阳光不足 → 拒绝（不生成申请、不埋 reward_*）。
    if ((await _ledger.balance()) < cost) {
      return SubmitResult(outcome: SubmitOutcome.rejectedBalance, cost: cost);
    }

    final RedemptionDecision decision = RedemptionService.decide(
      template: tpl,
      cost: cost,
      ageTier: ageTier,
      pool: pool,
    );

    // 孩子端发起：即使是「免确认双条件」满足的便宜奖励，也强制进入 pending，
    // 由家长在「今日」里显式确认后才扣阳光（C5 自动放行不再对孩子端生效）。
    RequestStatus finalStatus = decision.status;
    bool finalAuto = decision.autoApproved;
    if (forcePending && finalStatus == RequestStatus.verified) {
      finalStatus = RequestStatus.pending;
      finalAuto = false;
    }

    final String childId = _account.currentChildId();
    final int? queueRank = decision.status == RequestStatus.queued
        ? (await _reward.queuedOfWeek(weekKey(now))).length + 1
        : null;

    final String id = _uuid.v4();
    final RedemptionRequest req = RedemptionRequest(
      id: id,
      childId: childId,
      templateId: tpl.id,
      requestedAt: now,
      cost: cost,
      status: finalStatus,
      autoApproved: finalAuto,
      queuePosition: queueRank,
    );
    await _reward.createRequest(req);

    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.rewardRedeemRequest,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'reward_id': req.id,
        'cost_sun': cost,
        'category': tpl.category.name,
        'tier': ageTier.name,
        'is_auto_pass': decision.autoApproved,
      },
    ));

    switch (finalStatus) {
      case RequestStatus.verified:
        await _appendLedger(now, cost, SunlightType.redeem, req.id);
        await _pools.applyRedemption(pool, cost, auto: true);
        return SubmitResult(
          outcome: SubmitOutcome.verified,
          requestId: req.id,
          cost: cost,
          autoApproved: true,
        );
      case RequestStatus.pending:
        return SubmitResult(
          outcome: SubmitOutcome.pending,
          requestId: req.id,
          cost: cost,
        );
      case RequestStatus.queued:
        await _tracking.track(TrackingEvent(
          id: _uuid.v4(),
          name: TrackingEventNames.rewardQueue,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'request_id': req.id,
            'queue_rank': queueRank,
            'week': weekKey(now),
          },
        ));
        return SubmitResult(
          outcome: SubmitOutcome.queued,
          requestId: req.id,
          cost: cost,
          queueRank: queueRank,
        );
      case RequestStatus.rejected:
        // submit() 永远不会产出 rejected（rejected 仅由显式 reject() 产生）
        throw StateError('submit() 不应产生 rejected 状态');
    }
  }

  /// 家长核销一笔 pending 请求（§4.3 时序）。
  Future<void> verify(String requestId, DateTime now) async {
    final List<RedemptionRequest> list = await _reward.pendingAndQueued();
    final RedemptionRequest req = list.firstWhere(
      (r) => r.id == requestId && r.status == RequestStatus.pending,
      orElse: () => throw StateError('no pending'),
    );

    final AgeTier tier = (await _settings.getSettings()).ageTier;

    await _appendLedger(now, req.cost, SunlightType.redeem, req.id);
    await _pools.applyRedemption(await _pools.ensureAndReset(now), req.cost,
        auto: false);

    await _reward.updateRequest(RedemptionRequest(
      id: req.id,
      childId: req.childId,
      templateId: req.templateId,
      requestedAt: req.requestedAt,
      cost: req.cost,
      status: RequestStatus.verified,
      autoApproved: req.autoApproved,
      queuePosition: null,
      verifiedAt: now,
      parentNote: req.parentNote,
    ));

    final bool within48 =
        now.difference(req.requestedAt) <= Duration(hours: kPendingReminderHours);
    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.rewardVerified,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'request_id': req.id,
        'verify_ts': now.toIso8601String(),
        'within_48h': within48,
        'amount': req.cost,
        'tier': tier.name,
        'is_small': req.cost <= 50,
      },
    ));
  }

  /// 家长拒绝一笔待处理请求（§4.3 家长拒绝）：不核销、阳光原路返回。
  ///
  /// pending / queued 状态**从不扣账本**，故拒绝 = 从不做扣减，无需回写 ledger；
  /// 仅将状态置 [RequestStatus.rejected]，使其退出 pendingAndQueued 列表
  /// （家长端核销卡消失、孩子端可在商店重新兑换）。埋点记一笔拒办。
  Future<void> reject(String requestId, DateTime now, {String? note}) async {
    final List<RedemptionRequest> list = await _reward.pendingAndQueued();
    final RedemptionRequest req = list.firstWhere(
      (r) =>
          r.id == requestId &&
          (r.status == RequestStatus.pending ||
              r.status == RequestStatus.queued),
      orElse: () => throw StateError('no pending/queued'),
    );
    final String source =
        req.status == RequestStatus.queued ? 'queued' : 'pending';
    // 拒绝 = 该次兑换不生效：回退落单时 bump 的本周冷却计数，
    // 使「每周可兑换次数」不因被拒而减少（M2 真机验收·第4轮 第3点）。
    await _reward.decrementCooldown(req.templateId, CooldownPeriod.weekly);
    await _reward.updateRequest(RedemptionRequest(
      id: req.id,
      childId: req.childId,
      templateId: req.templateId,
      requestedAt: req.requestedAt,
      cost: req.cost,
      status: RequestStatus.rejected,
      autoApproved: req.autoApproved,
      queuePosition: null,
      verifiedAt: null,
      parentNote: note,
    ));
    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.rewardRejected,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'request_id': req.id,
        'amount': req.cost,
        'source': source,
      },
    ));
  }

  /// 跨周释放排队请求（§4.2 时序）：按 requested_at 升序逐条尝试释放。
  ///
  /// 余额 ≥ cost 且 新周池未超 → 释放为 verified（写账本 + 扣池 + 埋点）；
  /// 否则 → 顺延下周（不拒绝、不失效）。
  Future<ReleaseReport> releaseQueue(String weekKey, DateTime now) async {
    final List<RedemptionRequest> queue =
        (await _reward.queuedOfWeek(weekKey))
          ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));

    final WeeklyPool newPool = await _pools.ensureAndReset(now);
    int released = 0;
    int deferred = 0;

    for (final RedemptionRequest req in queue) {
      if ((await _ledger.balance()) >= req.cost &&
          (newPool.used + newPool.autoReleased + req.cost) <= newPool.budget) {
        await _appendLedger(now, req.cost, SunlightType.queueRelease, req.id);
        await _pools.applyRedemption(newPool, req.cost, auto: false);
        await _reward.updateRequest(RedemptionRequest(
          id: req.id,
          childId: req.childId,
          templateId: req.templateId,
          requestedAt: req.requestedAt,
          cost: req.cost,
          status: RequestStatus.verified,
          autoApproved: req.autoApproved,
          queuePosition: null,
          verifiedAt: now,
          parentNote: req.parentNote,
        ));
        await _tracking.track(TrackingEvent(
          id: _uuid.v4(),
          name: TrackingEventNames.rewardVerified,
          type: TrackingType.metric,
          ts: now,
          payload: {
            'request_id': req.id,
            'source': 'queueRelease',
            'amount': req.cost,
          },
        ));
        released += 1;
      } else {
        deferred += 1; // 顺延下周
      }
    }
    return ReleaseReport(released, deferred);
  }

  /// 家长强制立即释放一笔排队请求（A3）：跳过等次周，余额/周池充足时立即放行。
  ///
  /// 与 [releaseQueue] 单条逻辑一致：写账本 + 扣池 + 置 verified + 埋点；
  /// 余额或周池不足则抛 [StateError]（由 UI 捕获提示），不修改任何状态。
  Future<void> forceRelease(String requestId, DateTime now) async {
    final List<RedemptionRequest> list = await _reward.pendingAndQueued();
    final RedemptionRequest req = list.firstWhere(
      (r) => r.id == requestId && r.status == RequestStatus.queued,
      orElse: () => throw StateError('no queued'),
    );
    final WeeklyPool newPool = await _pools.ensureAndReset(now);
    if ((await _ledger.balance()) < req.cost ||
        (newPool.used + newPool.autoReleased + req.cost) > newPool.budget) {
      throw StateError('余额或周池不足，无法立即释放');
    }
    await _appendLedger(now, req.cost, SunlightType.queueRelease, req.id);
    await _pools.applyRedemption(newPool, req.cost, auto: false);
    await _reward.updateRequest(RedemptionRequest(
      id: req.id,
      childId: req.childId,
      templateId: req.templateId,
      requestedAt: req.requestedAt,
      cost: req.cost,
      status: RequestStatus.verified,
      autoApproved: req.autoApproved,
      queuePosition: null,
      verifiedAt: now,
      parentNote: req.parentNote,
    ));
    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.rewardVerified,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'request_id': req.id,
        'source': 'queueForceRelease',
        'amount': req.cost,
      },
    ));
  }

  /// 待处理列表（pending + queued），按 requested_at 升序，供家长端核销卡。
  Future<List<RedemptionRequest>> pendingList() async {
    final List<RedemptionRequest> list = await _reward.pendingAndQueued();
    list.sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
    return list;
  }

  /// 私有：写一条账本扣减（net = -cost），balanceAfter 由调用前余额推导。
  Future<void> _appendLedger(
    DateTime now,
    int cost,
    SunlightType type,
    String refId,
  ) async {
    final double before = await _ledger.balance();
    final double after = before - cost;
    await _ledger.append(SunlightEntry(
      id: _uuid.v4(),
      ts: now,
      type: type,
      gross: cost.toDouble(),
      net: -cost.toDouble(),
      balanceAfter: after,
      refType: 'redemption',
      refId: refId,
      dayKey: dayKey(now),
    ));
  }
}
