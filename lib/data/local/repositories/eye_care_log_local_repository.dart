/// 护眼记录本地仓储（Drift `eye_care_logs` 表实现）。
///
/// C90 期 2：数据按「当前孩子」隔离 —— 写入落 [AccountService.childId]，聚合
/// 只算当前孩子。🔴 接口签名不变（过滤在实现内部）；[AccountService] 可选
///（null → 按 kChildIdDefault，既有单测零改动）。
library eye_care_log_local_repository;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

/// Drift 实现：只追加 + 聚合（append-only 事实记录，与账本同纪律）。
class EyeCareLogLocalRepository implements EyeCareLogRepository {
  final AppDatabase _db;
  final AccountService? _account;

  EyeCareLogLocalRepository(this._db, {AccountService? account})
      : _account = account;

  /// 当前孩子的 childId（C90 期 2：写入落标 + 读取过滤统一收口）。
  String get _childId => _account?.childId ?? kChildIdDefault;

  @override
  Future<void> append(EyeCareLog log) {
    return _db.eyeCareLogDao.appendRow(
        EyeCareLogsCompanion.insert(
          id: log.id,
          ts: log.ts,
          dayKey: log.dayKey,
          result: log.result.name,
          watchedSeconds: log.watchedSeconds,
          source: log.source.name,
        ),
        childId: _childId);
  }

  @override
  Future<int> countByResult(EyeCareResultType type) =>
      _db.eyeCareLogDao.countByResult(type.name, childId: _childId);

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) =>
      _db.eyeCareLogDao.sumWatchedSecondsByResult(type.name,
          childId: _childId);
}
