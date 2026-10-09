/// 一条护眼记录（玄参 2026-10-09：家长端报告的护眼次数 / 时长 / 跳过统计）。
///
/// 每次**护眼卡退出**时落一行（完成与跳过都记，见 `eye_care_page._finish`）：
///  · [result] = completed（自然走完，有奖励）/ skipped（二次确认跳过，无奖励）；
///  · [watchedSeconds] = 实际观看秒数（completed 恒为 kEyeCareDurationSeconds；
///    skipped = 点跳过那一刻已看的秒数，由页内 1s tick 累计）；
///  · [source] = 场内 / 场末触发来源。
///
/// 口径注记：完成的「累计护眼次数」**以阳光账本 `refType='eye_care_break'` 为准**
/// （孩子端「我的」页用，含功能上线以来的全部历史）；本表补齐账本没有的两个维度
/// ——**跳过**（从不入账）与**实际观看时长**。家长报告的完成次数同样走账本口径，
/// 跳过次数 / 观看时长走本表。
library eye_care_log;

import 'package:sunflower_time/domain/services/eye_care_service.dart';

/// 护眼记录（不可变值对象）。
class EyeCareLog {
  final String id;
  final DateTime ts;

  /// 所属日（`dayKey` 口径，与账本一致，便于按日聚合）。
  final String dayKey;
  final EyeCareResultType result;

  /// 实际观看秒数（≥ 0）。
  final int watchedSeconds;
  final EyeCareSource source;

  const EyeCareLog({
    required this.id,
    required this.ts,
    required this.dayKey,
    required this.result,
    required this.watchedSeconds,
    required this.source,
  });
}
