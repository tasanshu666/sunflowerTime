/// 本地专注会话仓储（实现 domain 接口，§2.1 / §3.1）。
///
/// 真实 Drift 实现，替换 M0 的 `FocusLocalRepositoryStub`（该桩已从
/// `local_stub_repositories.dart` 移除）。
library focus_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';

class FocusLocalRepository implements FocusRepository {
  final db.AppDatabase _db;

  FocusLocalRepository(this._db);

  @override
  Future<void> saveSession(FocusSession session) async {
    await _db.into(_db.focusSessions).insertOnConflictUpdate(
          db.FocusSessionsCompanion(
            id: Value(session.id),
            start: Value(session.start),
            end: Value(session.end),
            plannedMin: Value(session.plannedMin),
            actualFocusMin: Value(session.actualFocusMin),
            status: Value(session.status.index),
            sunlightEarned: Value(session.sunlightEarned),
            createdAt: Value(session.createdAt),
          ),
        );
  }

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async {
    final DateTime dayStart = _parseDay(dayKey);
    final DateTime dayEnd = dayStart.add(const Duration(days: 1));
    final rows = await (_db.select(_db.focusSessions)
          ..where((t) =>
              t.start.isBiggerOrEqualValue(dayStart) &
              t.start.isSmallerThanValue(dayEnd))
          ..orderBy([(t) => OrderingTerm(expression: t.start)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async {
    // WFD（§3.3 / PRD §8.3）：近 7 天内「当日完成 ≥1 次有效专注」的天数。
    // 有效专注 = actual_focus_min ≥ kValidFocusMinutes 且完成率 ≥ kCompletionRateThreshold。
    final DateTime from =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final DateTime to =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final rows = await (_db.select(_db.focusSessions)
          ..where((t) =>
              t.start.isBiggerOrEqualValue(from) & t.start.isSmallerThanValue(to)))
        .get();

    final Set<String> validDays = <String>{};
    for (final db.FocusSession r in rows) {
      if (_isValidSession(r)) {
        validDays.add(_dayKeyOf(r.start));
      }
    }
    return validDays.length;
  }

  @override
  Future<FocusStats> totalStats() async {
    // 全量聚合（§3.3）：累计专注分钟 / 会话数 / 有效专注日。
    // 数据量级为单机孩子的历史会话数，全量取内存聚合足够（不做分页/SQL 聚合）。
    final List<db.FocusSession> rows = await _db.select(_db.focusSessions).get();

    double totalMinutes = 0.0;
    final Set<String> validDays = <String>{};
    for (final db.FocusSession r in rows) {
      totalMinutes += r.actualFocusMin;
      if (_isValidSession(r)) {
        validDays.add(_dayKeyOf(r.start));
      }
    }

    return FocusStats(
      totalFocusMinutes: totalMinutes,
      totalSessions: rows.length,
      totalValidDays: validDays.length,
    );
  }

  /// 有效专注判定（单点）：实际专注 ≥ [kValidFocusMinutes] 且完成率 ≥
  /// [kCompletionRateThreshold]。[countValidFocusDaysLastWeek] 与 [totalStats]
  /// 共用同一口径，避免判定逻辑孪生。
  bool _isValidSession(db.FocusSession r) {
    final double completion =
        r.plannedMin == 0 ? 0.0 : r.actualFocusMin / r.plannedMin;
    return r.actualFocusMin >= kValidFocusMinutes &&
        completion >= kCompletionRateThreshold;
  }

  /// 会话日键 `yyyy-M-d`（用于有效日去重；仅作内存 Set key，不对齐零填充）。
  String _dayKeyOf(DateTime d) => '${d.year}-${d.month}-${d.day}';

  FocusSession _toDomain(db.FocusSession r) => FocusSession(
        id: r.id,
        start: r.start,
        end: r.end,
        plannedMin: r.plannedMin,
        actualFocusMin: r.actualFocusMin,
        status: FocusStatus.values[r.status],
        sunlightEarned: r.sunlightEarned,
        createdAt: r.createdAt,
      );

  /// 解析日键 `yyyy-MM-dd` 为当日 0 点。
  DateTime _parseDay(String dayKey) {
    final parts = dayKey.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
