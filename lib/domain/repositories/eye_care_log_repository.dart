/// 护眼记录仓储抽象（玄参 2026-10-09：家长报告护眼统计的数据口）。
///
/// 只追加、只聚合，不修改不删除（与账本同为事实记录）。
/// 「完成次数」的权威口径在阳光账本（`SunlightRepository`，`refType='eye_care_break'`）；
/// 本仓储承载**跳过**（账本从无记录）与**实际观看时长**。
library eye_care_log_repository;

import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

abstract class EyeCareLogRepository {
  /// 追加一条护眼记录（护眼卡退出时调用，完成 / 跳过都记）。
  Future<void> append(EyeCareLog log);

  /// 指定结果的累计条数（skipped = 累计跳过次数）。
  Future<int> countByResult(EyeCareResultType type);

  /// 指定结果的观看秒数合计（skipped 的部分观看时长）。
  ///
  /// 完成态的时长**不走本方法**：completed 每条恒为 kEyeCareDurationSeconds，
  /// 报告侧用「账本完成次数 × kEyeCareDurationSeconds」口径（含 v18 之前的
  /// 历史完成，且天然防双重计数）。
  Future<int> watchedSecondsByResult(EyeCareResultType type);
}
