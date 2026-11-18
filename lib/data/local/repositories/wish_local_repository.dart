/// Local WishRepository implementation (drift adapter, no extra DAO needed).
library wish_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/wish_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

/// Drift adapter: filters by current child inside the implementation so the
/// domain interface stays signature-stable (C90 pattern).
class WishLocalRepository implements WishRepository {
  WishLocalRepository(this._db, {AccountService? account})
      : _account = account;

  final db.AppDatabase _db;
  final AccountService? _account;

  String get _childId => _account?.childId ?? kChildIdDefault;

  @override
  Future<List<Wish>> mounted() async {
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) &
              t.status.isIn(<int>[
                WishStatus.pending.index,
                WishStatus.tagged.index,
                WishStatus.committed.index,
              ]) &
              t.releasedAt.isNull())
          ..orderBy(<OrderClauseGenerator<db.$WishesTable>>[
            (db.$WishesTable t) => OrderingTerm.asc(t.treeSlot),
          ]))
        .get();
    return rows.map(_toWish).toList();
  }

  @override
  Future<List<Wish>> pool() async {
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) &
              t.status.isIn(<int>[
                WishStatus.fulfilled.index,
                WishStatus.replaced.index,
              ]))
          ..orderBy(<OrderClauseGenerator<db.$WishesTable>>[
            (db.$WishesTable t) => OrderingTerm.desc(t.fulfilledAt),
          ]))
        .get();
    return rows.map(_toWish).toList();
  }

  @override
  Future<List<Wish>> boxed() async {
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) & t.releasedAt.isNotNull())
          ..orderBy(<OrderClauseGenerator<db.$WishesTable>>[
            (db.$WishesTable t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
    return rows.map(_toWish).toList();
  }

  @override
  Future<List<Wish>> abandoned() async {
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) &
              t.status.equals(WishStatus.abandoned.index))
          ..orderBy(<OrderClauseGenerator<db.$WishesTable>>[
            (db.$WishesTable t) => OrderingTerm.desc(t.abandonedAt),
          ]))
        .get();
    return rows.map(_toWish).toList();
  }

  @override
  Future<List<Wish>> byStatuses(Set<WishStatus> statuses) async {
    if (statuses.isEmpty) return <Wish>[];
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) &
              t.status.isIn(statuses.map((WishStatus s) => s.index).toList())))
        .get();
    return rows.map(_toWish).toList();
  }

  @override
  Future<int> countByStatuses(Set<WishStatus> statuses) async =>
      (await byStatuses(statuses)).length;

  @override
  Future<int> countStampedAchieved() async =>
      (await byStatuses(<WishStatus>{WishStatus.fulfilled})).length;

  @override
  Future<Set<int>> occupiedSlots() async {
    final List<db.WishRow> rows = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.childId.equals(_childId) &
              t.releasedAt.isNull() &
              t.treeSlot.isNotNull()))
        .get();
    return rows
        .map((db.WishRow r) => r.treeSlot)
        .whereType<int>()
        .toSet();
  }

  @override
  Future<Wish?> byId(String id) async {
    final db.WishRow? row = await (_db.select(_db.wishes)
          ..where((db.$WishesTable t) =>
              t.id.equals(id) & t.childId.equals(_childId)))
        .getSingleOrNull();
    return row == null ? null : _toWish(row);
  }

  @override
  Future<void> save(Wish wish) =>
      _db.into(_db.wishes).insertOnConflictUpdate(_toCompanion(wish));

  @override
  Future<void> deleteAll() =>
      (_db.delete(_db.wishes)..where((db.$WishesTable t) => t.childId.equals(_childId))).go();

  static Wish _toWish(db.WishRow r) => Wish(
        id: r.id,
        childId: r.childId,
        text: r.wishText,
        category: WishCategory.values[r.category],
        status: WishStatus.values[r.status],
        createdAt: r.createdAt,
        committedAt: r.committedAt,
        commitDueDate: r.commitDueDate,
        fulfilledAt: r.fulfilledAt,
        fulfillSource: r.fulfillSource,
        abandonedAt: r.abandonedAt,
        parentSeenAt: r.parentSeenAt,
        remindedAt: r.remindedAt,
        parentReply: r.parentReply,
        replacedText: r.replacedText,
        treeSlot: r.treeSlot,
        targetMode: WishGoalMode.values[r.targetMode],
        targetValue: r.targetValue,
        progressValue: r.progressValue,
        tagKey: r.tagKey,
        taggedAt: r.taggedAt,
        releasedAt: r.releasedAt,
      );

  static db.WishesCompanion _toCompanion(Wish w) => db.WishesCompanion(
        id: Value(w.id),
        childId: Value(w.childId),
        wishText: Value(w.text),
        category: Value(w.category.index),
        status: Value(w.status.index),
        createdAt: Value(w.createdAt),
        committedAt: Value(w.committedAt),
        commitDueDate: Value(w.commitDueDate),
        fulfilledAt: Value(w.fulfilledAt),
        fulfillSource: Value(w.fulfillSource),
        abandonedAt: Value(w.abandonedAt),
        parentSeenAt: Value(w.parentSeenAt),
        remindedAt: Value(w.remindedAt),
        parentReply: Value(w.parentReply),
        replacedText: Value(w.replacedText),
        treeSlot: Value(w.treeSlot),
        targetMode: Value(w.targetMode.index),
        targetValue: Value(w.targetValue),
        progressValue: Value(w.progressValue),
        tagKey: Value(w.tagKey),
        taggedAt: Value(w.taggedAt),
        releasedAt: Value(w.releasedAt),
      );
}
