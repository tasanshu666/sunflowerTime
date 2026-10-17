/// 孩子档案本地仓储（Drift `child_profiles` 表实现，C90 期 1）。
library child_profile_local_repository;

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/repositories/child_profile_repository.dart';

/// Drift 实现：CRUD 只做落库，门控配额判定在调用方（矩阵单点）。
class ChildProfileLocalRepository implements ChildProfileRepository {
  final AppDatabase _db;

  ChildProfileLocalRepository(this._db);

  @override
  Future<List<ChildProfile>> children() async {
    final List<ChildProfileRow> rows = await _db.childProfileDao.all();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<ChildProfile> create(String name, AgeTier ageTier, {String? id}) async {
    final String childId = id ?? const Uuid().v4();
    final DateTime now = DateTime.now();
    await _db.childProfileDao.upsert(ChildProfilesCompanion.insert(
      id: childId,
      name: name,
      ageTier: Value(ageTier.index),
      createdAt: now,
    ));
    return ChildProfile(
      id: childId,
      name: name,
      ageTier: ageTier,
      createdAt: now,
    );
  }

  @override
  Future<int> count() => _db.childProfileDao.count();

  @override
  Future<void> update(
    String id, {
    required String name,
    required AgeTier ageTier,
  }) =>
      _db.childProfileDao.updateProfile(
        id,
        name: name,
        ageTier: ageTier.index,
      );

  @override
  Future<void> deleteById(String id) => _db.childProfileDao.deleteById(id);

  ChildProfile _fromRow(ChildProfileRow row) => ChildProfile(
        id: row.id,
        name: row.name,
        // index 越界防御：夹取到合法区间（历史行只可能 0..2）。
        ageTier: AgeTier
            .values[row.ageTier.clamp(0, AgeTier.values.length - 1)],
        createdAt: row.createdAt,
      );
}
