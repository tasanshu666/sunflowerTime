import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 奖励/兑换仓储抽象（§2.1 / §3.1 / §3.2）。
abstract class RewardRepository {
  Future<List<RewardTemplate>> templates();
  Future<void> saveTemplate(RewardTemplate t);
  Future<void> deleteTemplate(String id);
  Future<void> createRequest(RedemptionRequest request);
  Future<List<RedemptionRequest>> pendingAndQueued();

  /// 已核销（verified）的申请，按核销时间倒序。
  ///
  /// 供孩子端「家长已核销」同步提醒使用（M2 家长-孩子同步）。
  Future<List<RedemptionRequest>> verifiedRequests();

  /// 已拒绝的申请（status==rejected），供孩子端「拒绝对称通知」使用（B4）。
  Future<List<RedemptionRequest>> rejectedRequests();

  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey);
  Future<void> updateRequest(RedemptionRequest request);
  Future<int> cooldownCount(String templateId, CooldownPeriod window);
}
