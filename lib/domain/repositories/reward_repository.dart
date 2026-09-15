import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 奖励/兑换仓储抽象（§2.1 / §3.1）。
abstract class RewardRepository {
  Future<List<RewardTemplate>> templates();
  Future<void> saveTemplate(RewardTemplate t);
  Future<void> createRequest(RedemptionRequest request);
  Future<List<RedemptionRequest>> pendingAndQueued();
  Future<void> updateRequest(RedemptionRequest request);
}
