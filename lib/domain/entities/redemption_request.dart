import 'package:sunflower_time/domain/entities/enums.dart';

/// 兑换申请（S2 状态机载体，最小实体）。
class RedemptionRequest {
  final String id;
  final String templateId;
  final DateTime requestedAt;
  final int cost; // 已乘 K 的消耗侧价（孩子端实际扣减价）
  final RequestStatus status;
  final bool autoApproved;
  final int? queuePosition;
  final DateTime? verifiedAt;

  const RedemptionRequest({
    required this.id,
    required this.templateId,
    required this.requestedAt,
    required this.cost,
    this.status = RequestStatus.pending,
    this.autoApproved = false,
    this.queuePosition,
    this.verifiedAt,
  });
}
