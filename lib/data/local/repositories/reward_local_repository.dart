/// 本地奖励/兑换仓储（实现 domain 接口，§2.1 / §3.2）。
///
/// 真实 Drift 实现，替换 M0 的 `RewardLocalRepositoryStub`。
library reward_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';

class RewardLocalRepository implements RewardRepository {
  final db.AppDatabase _db;

  RewardLocalRepository(this._db);

  @override
  Future<List<RewardTemplate>> templates() async {
    final List<db.RewardTemplate> rows = await _db.rewardTemplateDao.all();
    return rows.map(_toTemplate).toList();
  }

  @override
  Future<void> saveTemplate(RewardTemplate t) => _db.rewardTemplateDao.upsert(
      db.RewardTemplatesCompanion(
        id: Value(t.id),
        name: Value(t.name),
        category: Value(t.category.index),
        contentCategory: Value(t.contentCategory.index),
        baseCost: Value(t.baseCost),
        freqLimit: Value(t.frequencyLimitPerWeek),
        enabled: const Value(true),
        cooldownRule: Value(t.cooldownRule.index),
      ),
      );

  @override
  Future<void> deleteTemplate(String id) async {
    await _db.rewardTemplateDao.deleteById(id);
  }

  @override
  Future<void> createRequest(RedemptionRequest r) async {
    await _db.redemptionRequestDao.insert(_requestCompanion(r));
    // 落单即 bump 本周冷却计数（D4）：使「每周限领次数」真正生效——
    // 既驱动孩子端卡片「剩余次数」递减，也驱动 RedemptionOrchestrationService._onCooldown 冷却闸门。
    // 与 redemption_orchestration_test 的 FakeRewardRepository.createRequest 行为对齐（落申请即 +1）。
    await _db.cooldownCounterDao.bump(r.templateId, CooldownPeriod.weekly);
  }

  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async {
    final List<db.RedemptionRequest> rows =
        await _db.redemptionRequestDao.pendingAndQueued();
    return rows.map(_toRequest).toList();
  }

  @override
  Future<List<RedemptionRequest>> verifiedRequests() async {
    final List<db.RedemptionRequest> rows =
        await _db.redemptionRequestDao.verified();
    final List<RedemptionRequest> list = rows.map(_toRequest).toList();
    // 按核销时间倒序（verifiedAt 为空时退回 requestedAt），最新在最前。
    list.sort((RedemptionRequest a, RedemptionRequest b) =>
        (b.verifiedAt ?? b.requestedAt)
            .compareTo(a.verifiedAt ?? a.requestedAt));
    return list;
  }

  @override
  Future<List<RedemptionRequest>> rejectedRequests() async {
    final List<db.RedemptionRequest> rows =
        await _db.redemptionRequestDao.rejected();
    return rows.map(_toRequest).toList();
  }

  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async {
    final List<db.RedemptionRequest> rows =
        await _db.redemptionRequestDao.queuedOfWeek(weekKey);
    return rows.map(_toRequest).toList();
  }

  @override
  Future<void> updateRequest(RedemptionRequest r) =>
      _db.redemptionRequestDao.updateRow(_requestCompanion(r));

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) =>
      _db.cooldownCounterDao.count(templateId, window);

  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) =>
      _db.cooldownCounterDao.decrement(templateId, window);

  db.RedemptionRequestsCompanion _requestCompanion(RedemptionRequest r) =>
      db.RedemptionRequestsCompanion(
        id: Value(r.id),
        childId: Value(r.childId),
        templateId: Value(r.templateId),
        requestedAt: Value(r.requestedAt),
        cost: Value(r.cost),
        status: Value(r.status.index),
        autoApproved: Value(r.autoApproved),
        queuePosition: Value(r.queuePosition),
        verifiedAt: Value(r.verifiedAt),
        parentNote: Value(r.parentNote),
      );

  RewardTemplate _toTemplate(db.RewardTemplate r) => RewardTemplate(
        id: r.id,
        name: r.name,
        category: RewardCategory.values[r.category],
        contentCategory: RewardContentCategory.values[r.contentCategory],
        baseCost: r.baseCost,
        frequencyLimitPerWeek: r.freqLimit ?? kCooldownWeeklyDefault,
        cooldownRule: CooldownRule.values[r.cooldownRule],
      );

  RedemptionRequest _toRequest(db.RedemptionRequest r) => RedemptionRequest(
        id: r.id,
        childId: r.childId,
        templateId: r.templateId,
        requestedAt: r.requestedAt,
        cost: r.cost,
        status: RequestStatus.values[r.status],
        autoApproved: r.autoApproved,
        queuePosition: r.queuePosition,
        verifiedAt: r.verifiedAt,
        parentNote: r.parentNote,
      );
}
