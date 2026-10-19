import 'package:sunflower_time/domain/entities/enums.dart';

/// 兑换申请（S2 状态机载体，最小实体）。
class RedemptionRequest {
  final String id;
  final String childId; // 归属孩子（C1/D2 多档案预留；Plan B 固定 kChildIdDefault）
  final String templateId;
  final DateTime requestedAt;
  final int cost; // 已乘 K 的消耗侧价（孩子端实际扣减价）
  final RequestStatus status;

  /// 🔴 **已废弃（C90-C，2026-10-18）**：自动放行功能全删后本字段**恒为 false**、
  /// 不再写 true；读方一律按恒 false 处理。字段与 `redemption_requests.auto_approved`
  /// 列保留（列删除不值得单独迁移；且枚举/列删改会破坏存量数据对账）。
  final bool autoApproved;
  final int? queuePosition;
  final DateTime? verifiedAt;
  final String? parentNote; // 家长核销备注（表列已存在，实体补齐）

  const RedemptionRequest({
    required this.id,
    required this.childId,
    required this.templateId,
    required this.requestedAt,
    required this.cost,
    this.status = RequestStatus.pending,
    this.autoApproved = false,
    this.queuePosition,
    this.verifiedAt,
    this.parentNote,
  });
}
