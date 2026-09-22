/// 全量专注统计（M4 任务打卡领域层聚合，§3.3）。
///
/// 与 [FocusSession]（单场会话）不同，本实体承载「历史累计」口径，供成长页 /
/// 报告页展示：累计专注分钟、累计会话数、累计有效专注日。
///
/// [totalValidDays] 的口径与 `FocusLocalRepository.countValidFocusDaysLastWeek`
/// 保持一致：某日存在至少一次「实际专注 ≥ kValidFocusMinutes 且完成率 ≥
/// kCompletionRateThreshold」的会话，即计为一个有效专注日（同一日多次仅计一次）。
class FocusStats {
  /// 累计专注分钟（全部会话 actualFocusMin 之和）。
  final double totalFocusMinutes;

  /// 累计会话数（含短于门槛的 shortAborted 会话）。
  final int totalSessions;

  /// 累计有效专注日天数（见类注释口径）。
  final int totalValidDays;

  const FocusStats({
    required this.totalFocusMinutes,
    required this.totalSessions,
    required this.totalValidDays,
  });
}
