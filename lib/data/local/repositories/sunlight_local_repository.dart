/// 本地阳光账本仓储（实现 domain 接口，§2.1 / §3.2）。
library sunlight_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
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
  Future<double> dayNet(String dayKey) => _db.sunlightLedgerDao.dayNet(dayKey);

  @override
  Future<double> verifiedRedeemTotal() =>
      _db.sunlightLedgerDao.verifiedRedeemTotal();
}
