/// 本地月度池仓储（实现 domain 接口，§2.1 / §3.2）。
library monthly_pool_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/monthly_pool.dart';
import 'package:sunflower_time/domain/repositories/monthly_pool_repository.dart';

class MonthlyPoolLocalRepository implements MonthlyPoolRepository {
  final db.AppDatabase _db;

  MonthlyPoolLocalRepository(this._db);

  @override
  Future<MonthlyPool?> get(String monthKey) async {
    final db.MonthlyPool? row = await _db.monthlyPoolDao.of(monthKey);
    if (row == null) return null;
    return MonthlyPool(
      monthKey: row.monthKey,
      budget: row.budget,
      used: row.used,
      autoReleased: row.autoReleased,
      resetAt: row.resetAt,
    );
  }

  @override
  Future<void> upsert(MonthlyPool pool) => _db.monthlyPoolDao.upsert(
        db.MonthlyPoolsCompanion(
          monthKey: Value(pool.monthKey),
          budget: Value(pool.budget),
          used: Value(pool.used),
          autoReleased: Value(pool.autoReleased),
          resetAt: Value(pool.resetAt ?? DateTime.now()),
        ),
      );

  @override
  List<String> monthsBetween(String fromKey, String toKey) {
    final DateTime from = DateTime.parse('$fromKey-01');
    final DateTime to = DateTime.parse('$toKey-01');
    final List<String> keys = <String>[];
    DateTime cursor = DateTime(from.year, from.month, 1);
    while (!cursor.isAfter(to)) {
      keys.add(monthKey(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return keys;
  }
}
