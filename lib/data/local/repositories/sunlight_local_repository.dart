/// 本地阳光账本仓储（实现 domain 接口，§2.1 / §3.2）。
library sunlight_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';

class SunlightLocalRepository implements SunlightRepository {
  final AppDatabase _db;

  SunlightLocalRepository(this._db);

  @override
  Future<double> append(SunlightEntry entry) async {
    await _db.sunlightLedgerDao.append(
      SunlightLedgersCompanion(
        id: Value(entry.id),
        ts: Value(entry.ts),
        type: Value(entry.type.index),
        gross: Value(entry.gross),
        net: Value(entry.net),
        balanceAfter: Value(entry.balanceAfter),
        refType: Value(entry.refType),
        refId: Value(entry.refId),
        dayKey: Value(entry.dayKey),
      ),
    );
    // 余额 = 已存余额 + 本次 net（append-only 账本）。
    final prev = await _db.sunlightLedgerDao.balance();
    return prev; // 注：balance() 已含刚插入行；此返回值供上层参考
  }

  @override
  Future<double> balance() => _db.sunlightLedgerDao.balance();

  @override
  Future<List<SunlightEntry>> all() async {
    final List<SunlightLedger> rows = await _db.sunlightLedgerDao.allDesc();
    return rows.map((SunlightLedger r) => SunlightEntry(
      id: r.id,
      ts: r.ts,
      type: SunlightType.values[r.type],
      gross: r.gross,
      net: r.net,
      balanceAfter: r.balanceAfter,
      refType: r.refType,
      refId: r.refId,
      dayKey: r.dayKey,
    )).toList();
  }

  @override
  Future<double> dayNet(String dayKey) => _db.sunlightLedgerDao.dayNet(dayKey);

  @override
  Future<double> earnGrossOnDay(String dayKey) =>
      _db.sunlightLedgerDao.sumEarnGrossOnDay(dayKey);

  @override
  Future<double> earnNetOnDay(String dayKey) =>
      _db.sunlightLedgerDao.sumEarnNetOnDay(dayKey);

  @override
  Future<double> verifiedRedeemTotal() =>
      _db.sunlightLedgerDao.verifiedRedeemTotal();

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) =>
      _db.sunlightLedgerDao.sumNetByRefTypeDay(refType, dayKey);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) =>
      _db.sunlightLedgerDao.sumNetByRefTypeMonth(refType, monthKey);

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) =>
      _db.sunlightLedgerDao.countByRefTypeAndRefIdOnDay(refType, refId, dayKey);

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) =>
      _db.sunlightLedgerDao.lastTsByRefTypeAndRefId(refType, refId);
}
