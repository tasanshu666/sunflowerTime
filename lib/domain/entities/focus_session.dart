import 'package:sunflower_time/domain/entities/enums.dart';

/// 专注会话（§3.1 focus_session）。纯领域模型，与 Drift 表解耦。
class FocusSession {
  final String id;
  final DateTime start;
  final DateTime? end;
  final int plannedMin;
  final double actualFocusMin; // 仅 ≥5 分钟才计（§6.2）
  final FocusStatus status;
  final double sunlightEarned;
  final DateTime createdAt;

  const FocusSession({
    required this.id,
    required this.start,
    this.end,
    required this.plannedMin,
    required this.actualFocusMin,
    required this.status,
    required this.sunlightEarned,
    required this.createdAt,
  });
}
