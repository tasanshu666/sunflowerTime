/// 护眼记录本地仓储（Drift `eye_care_logs` 表实现）。
library eye_care_log_local_repository;

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

/// Drift 实现：只追加 + 聚合（append-only 事实记录，与账本同纪律）。
class EyeCareLogLocalRepository implements EyeCareLogRepository {
  final AppDatabase _db;

  EyeCareLogLocalRepository(this._db);

  @override
  Future<void> append(EyeCareLog log) {
    return _db.eyeCareLogDao.appendRow(EyeCareLogsCompanion.insert(
      id: log.id,
      ts: log.ts,
      dayKey: log.dayKey,
      result: log.result.name,
      watchedSeconds: log.watchedSeconds,
      source: log.source.name,
    ));
  }

  @override
  Future<int> countByResult(EyeCareResultType type) =>
      _db.eyeCareLogDao.countByResult(type.name);

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) =>
      _db.eyeCareLogDao.sumWatchedSecondsByResult(type.name);
}
