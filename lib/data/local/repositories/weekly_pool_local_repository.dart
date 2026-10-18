/// 本地周阳光池仓储（实现 domain 接口，§2.1 / §3.2）。
///
/// C90 期 2 第二批：monthly_pools（周池）按孩子隔离（v28）—— 读写全落当前孩子、
/// 按当前孩子过滤；AccountService 可选注入（null → 恒按 kChildIdDefault，
/// 既有单测零改动）。🔴 仓储接口签名一律不变。
library weekly_pool_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

class WeeklyPoolLocalRepository implements WeeklyPoolRepository {
  final db.AppDatabase _db;
  final AccountService? _account;

  WeeklyPoolLocalRepository(this._db, {AccountService? account})
      : _account = account;

  /// 当前孩子的 childId（C90 期 2：周池隔离统一收口）。
  String get _childId => _account?.childId ?? kChildIdDefault;

  @override
  Future<WeeklyPool?> get(String weekKey) async {
    final db.MonthlyPool? row =
        await _db.monthlyPoolDao.of(weekKey, childId: _childId);
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
        childId: _childId,
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
