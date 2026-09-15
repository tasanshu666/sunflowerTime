/// 打卡记录（§3.1 check_in）。完美日 = 同日同科「专注 + 打卡」（§4.4）。
class CheckIn {
  final String id;
  final String taskId;
  final DateTime date;
  final DateTime completedAt;
  final String? sessionId; // 关联的 ≥15 分钟专注
  final bool isPerfectDay;

  const CheckIn({
    required this.id,
    required this.taskId,
    required this.date,
    required this.completedAt,
    this.sessionId,
    required this.isPerfectDay,
  });
}
