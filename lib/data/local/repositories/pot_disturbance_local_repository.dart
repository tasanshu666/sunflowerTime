/// 本地空花盆干扰物仓储（实现 domain 接口，F155-B）。
///
/// 真实 Drift 实现：空盆干扰物落 `EmptyPotDisturbances` 表（复合主键
/// `(childId, potIndex)`）。C90 期 2 口径：写入落 [AccountService.childId]，
/// 读取按当前孩子过滤 —— 与 [PlantLocalRepository] 同一套处理。
///
/// 🔴 仓储接口签名一律不变（过滤在实现内部完成）；[AccountService] 可选
///（null → 按 kChildIdDefault，既有单测零改动）。
library pot_disturbance_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

class PotDisturbanceLocalRepository implements PotDisturbanceRepository {
  final db.AppDatabase _db;
  final AccountService? _account;

  PotDisturbanceLocalRepository(this._db, {AccountService? account})
      : _account = account;

  /// 当前孩子的 childId（写入落标 + 读取过滤统一收口）。
  String get _childId => _account?.childId ?? kChildIdDefault;

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      (await _db.emptyPotDisturbanceDao.all(childId: _childId))
          .map(_toEntity)
          .toList();

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async {
    final db.EmptyPotDisturbanceRow? row =
        await _db.emptyPotDisturbanceDao.byPot(potIndex, childId: _childId);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> save(PotDisturbance disturbance) => _db.emptyPotDisturbanceDao
      .upsert(_toCompanion(disturbance), childId: _childId);

  @override
  Future<void> deletePot(int potIndex) =>
      _db.emptyPotDisturbanceDao.deleteByPot(potIndex, childId: _childId);

  @override
  Future<void> deleteAll() =>
      _db.emptyPotDisturbanceDao.deleteAll(childId: _childId);
}

/// [db.EmptyPotDisturbanceRow]（Drift 数据类）→ 领域 [PotDisturbance]。
PotDisturbance _toEntity(db.EmptyPotDisturbanceRow r) => PotDisturbance(
      potIndex: r.potIndex,
      weedAt: r.weedAt,
      pestAt: r.pestAt,
      rollDay: r.rollDay,
    );

/// 领域 [PotDisturbance] → [db.EmptyPotDisturbancesCompanion]。
///
/// `childId` 刻意**不写**（`Value.absent()`）：由 DAO 的 `upsert(childId:)` 统一补当前
/// 孩子，避免两处各写一份口径漂移。
db.EmptyPotDisturbancesCompanion _toCompanion(PotDisturbance d) =>
    db.EmptyPotDisturbancesCompanion(
      potIndex: Value(d.potIndex),
      weedAt: Value(d.weedAt),
      pestAt: Value(d.pestAt),
      rollDay: Value(d.rollDay),
    );
