import 'package:sunflower_time/domain/entities/enums.dart';

/// 打卡记录（§3.1 check_in）。完美日 = 同日同科「专注 + 打卡」（§4.4）。
///
/// M4（v6）新增家长核销字段：[status] / [sunlightGross] / [sunlightGranted] /
/// [resolvedAt] / [parentNote]。默认 [status] = [CheckInStatus.verified]，
/// 与「老库 status 列默认 0 = 已核销」的历史语义保持一致（见 CheckInStatus 注释）。
class CheckIn {
  final String id;
  final String taskId;
  final DateTime date;
  final DateTime completedAt;
  final String? sessionId; // 关联的 ≥15 分钟专注
  final bool isPerfectDay;

  /// 核销状态：联动项自动结算 / 家长核销通过 → verified；非联动项手动打卡 → pending。
  final CheckInStatus status;

  /// 应发阳光（含完美日系数）；pending 阶段即已写入，供家长端展示。
  final double sunlightGross;

  /// 实际入账阳光；pending / rejected 时为 0。
  final double sunlightGranted;

  /// 家长处理时间（核销或驳回）；未处理为 null。
  final DateTime? resolvedAt;

  /// 家长驳回理由；无则 null。
  final String? parentNote;

  /// 本次打卡对应的**实际专注分钟**（F143，v30 新增；单位 = 分钟，可含小数）。
  ///
  /// 语义：**null = 未记录** —— 历史行（v30 之前落库）、非联动项手动打卡、待家长核销
  /// 的 pending 行均为 null；只有**联动专注结算**（含「5 分钟 ≤ 实际 < 门槛」的部分
  /// 完成）才写实际专注分钟，供孩子端任务卡与家长端记录展示
  /// 「实际 X 分钟 · 完成度 Y%」。
  final double? actualFocusMin;

  const CheckIn({
    required this.id,
    required this.taskId,
    required this.date,
    required this.completedAt,
    this.sessionId,
    required this.isPerfectDay,
    this.status = CheckInStatus.verified,
    this.sunlightGross = 0.0,
    this.sunlightGranted = 0.0,
    this.resolvedAt,
    this.parentNote,
    this.actualFocusMin,
  });
}
