/// 本地周阳光池仓储（实现 domain 接口，§2.1 / §3.2）。
library weekly_pool_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';

class WeeklyPoolLocalRepository implements WeeklyPoolRepository {
  final db.AppDatabase _db;

  WeeklyPoolLocalRepository(this._db);

  @override
  Future<WeeklyPool?> get(String weekKey) async {
    final db.MonthlyPool? row = await _db.monthlyPoolDao.of(weekKey);
    if (row == null) return null;
    return WeeklyPool(
      weekKey: row.monthKey,
      budget: row.budget,
      used: row.used,
      autoReleased: row.autoReleased,
      resetAt: row.resetAt,
    );
  }

  @override
  Future<void> upsert(WeeklyPool pool) => _db.monthlyPoolDao.upsert(
        db.MonthlyPoolsCompanion(
          monthKey: Value(pool.weekKey),
          budget: Value(pool.budget),
          used: Value(pool.used),
          autoReleased: Value(pool.autoReleased),
          resetAt: Value(pool.resetAt ?? DateTime.now()),
        ),
      );

  @override
  List<String> weeksBetween(String fromKey, String toKey) {
    final DateTime from = DateTime.parse(fromKey);
    final DateTime to = DateTime.parse(toKey);
    final List<String> keys = <String>[];
    // 回拨到当周周一，保证起点对齐（weekKey 自身也会按周一归一）。
    DateTime cursor = DateTime(from.year, from.month, from.day);
    while (cursor.weekday > DateTime.monday) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (!cursor.isAfter(to)) {
      keys.add(weekKey(cursor));
      cursor = cursor.add(const Duration(days: 7));
    }
    return keys;
  }
}
