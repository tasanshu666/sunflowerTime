/// 本地任务 / 打卡仓储（实现 domain 接口，§2.1 / §3.1）。
///
/// 真实 Drift 实现，替换 M0 的 `TaskLocalRepositoryStub`（M3 T01）。
/// M4：额外实现家长核销能力接口 [CheckInAdminRepository]。
library task_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';

/// 本地任务 / 打卡仓储（实现 domain 接口，§2.1 / §3.1）。
///
/// 真实 Drift 实现，替换 M0 的 `TaskLocalRepositoryStub`（M3 T01）。
/// M4：额外实现家长核销能力接口 [CheckInAdminRepository]。
///
/// C90 期 2：任务与打卡数据按「当前孩子」隔离 —— 写入落 [AccountService.childId]，
/// 读取全口径按 childId 过滤（成长任务每个孩子各一套；家长端待核销 / 今日打卡 /
/// 累计计数均只算当前孩子）。🔴 仓储接口签名一律不变（过滤在实现内部完成）；
/// [AccountService] 可选（null → 按 kChildIdDefault，既有单测零改动）。
class TaskLocalRepository
    implements
        TaskRepository,
        CheckInAdminRepository,
        WishTaskRepository,
        WishTaskReadBridge,
        WishFocusSettlementWriter {
  final db.AppDatabase _db;
  final AccountService? _account;

  TaskLocalRepository(this._db, {AccountService? account})
      : _account = account;

  /// 当前孩子的 childId（C90 期 2：写入落标 + 读取过滤统一收口）。
  String get _childId => _account?.childId ?? kChildIdDefault;

  @override
  Future<List<Task>> tasks() async =>
      (await _db.taskDao.allTasks(childId: _childId)).map(_toTask).toList();

  @override
  Future<void> saveTask(Task task) =>
      _db.taskDao.upsertTask(_toTaskCompanion(task), childId: _childId);

  @override
  Future<void> deleteTaskById(String id) =>
      _db.taskDao.deleteTaskById(id, childId: _childId);

  @override
  Future<void> checkIn(CheckIn checkIn) =>
      _db.taskDao.insertCheckIn(_toCheckInCompanion(checkIn),
          childId: _childId);

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async =>
      (await _db.taskDao.checkInsOfDay(dayKey, childId: _childId))
          .map(_toCheckIn)
          .toList();

  @override
  Future<int> totalCheckInCount() => _db.taskDao.countCheckInsByStatus(
      CheckInStatus.verified.index,
      childId: _childId);

  // ── CheckInAdminRepository（家长端核销，M4）──────────────────────────────
  @override
  Future<CheckIn?> checkInById(String id) async {
    final db.CheckIn? row =
        await _db.taskDao.checkInById(id, childId: _childId);
    return row == null ? null : _toCheckIn(row);
  }

  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async =>
      (await _db.taskDao.checkInsByStatus(status.index, childId: _childId))
          .map(_toCheckIn)
          .toList();

  @override
  Future<void> updateCheckIn(CheckIn checkIn) =>
      _db.taskDao.updateCheckIn(_toCheckInCompanion(checkIn),
          childId: _childId);

  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async =>
      await _db.taskDao.resolveCheckInIfStatus(
        id: id,
        fromStatus: from.index,
        toStatus: to.index,
        sunlightGranted: sunlightGranted,
        resolvedAt: resolvedAt,
        parentNote: parentNote,
        childId: _childId,
      ) == 1;
  // ── WishTaskRepository（能力扩展，零重复映射）──────────────────────────
  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async {
    final List<db.Task> rows = await (_db.select(_db.tasks)
          ..where((db.$TasksTable t) =>
              t.childId.equals(_childId) & t.wishId.equals(wishId)))
        .get();
    return rows.map(_toTask).toList();
  }

  @override
  Future<List<CheckIn>> checkInsOfTaskIds({
    required List<String> taskIds,
  }) async {
    if (taskIds.isEmpty) return <CheckIn>[];
    final List<db.CheckIn> rows = await (_db.select(_db.checkIns)
          ..where((db.$CheckInsTable t) =>
              t.childId.equals(_childId) & t.taskId.isIn(taskIds)))
        .get();
    return rows.map(_toCheckIn).toList();
  }

  @override
  Future<void> assignWish({
    required String taskId,
    required String wishId,
  }) =>
      (_db.update(_db.tasks)
            ..where((db.$TasksTable t) =>
                t.id.equals(taskId) & t.childId.equals(_childId)))
          .write(db.TasksCompanion(wishId: Value(wishId)));

  @override
  Future<void> unassignWish({required String taskId}) =>
      (_db.update(_db.tasks)
            ..where((db.$TasksTable t) =>
                t.id.equals(taskId) & t.childId.equals(_childId)))
          .write(const db.TasksCompanion(wishId: Value<String?>(null)));

  // ── A-T03 读 / 写桥接（可选能力，保持既有接口签名不变）──────────────────

  @override
  Future<Task?> wishTaskById(String taskId) async {
    final db.Task? row = await (_db.select(_db.tasks)
          ..where((db.$TasksTable t) =>
              t.id.equals(taskId) &
              t.childId.equals(_childId) &
              t.wishId.isNotNull()))
        .getSingleOrNull();
    return row == null ? null : _toTask(row);
  }

  @override
  Future<List<Task>> allTasksIncludingWish() async =>
      (await _db.taskDao.allTasks(childId: _childId, includeWishTasks: true))
          .map(_toTask)
          .toList();

  /// 🔴 A18 R20 / A16.4-e：打卡落库与愿望进度推进**同一事务**。
  ///
  /// mode 0（focusMinutes）才计分；未设目标（target_value == 0）照记流水但不推进
  /// （R6）。成熟判定复用领域纯函数 [fruitStageOf]，事务内直接写 fulfilled，
  /// 避免「打卡成功但进度没涨」的半写。
  @override
  Future<bool> settleWishFocus({
    required String wishId,
    required CheckIn checkIn,
    required int creditedMinutes,
    required DateTime now,
  }) =>
      _db.transaction(() async {
        // ① 先写流水（与成长任务共用同一张 check_ins 表 / 同一映射函数）。
        await _db.taskDao.insertCheckIn(_toCheckInCompanion(checkIn),
            childId: _childId);

        // ② 同一事务内读愿望、累加进度、判成熟。
        final db.WishRow? wish = await (_db.select(_db.wishes)
              ..where((db.$WishesTable t) =>
                  t.id.equals(wishId) & t.childId.equals(_childId)))
            .getSingleOrNull();
        if (wish == null ||
            wish.targetMode != WishGoalMode.focusMinutes.index ||
            wish.targetValue == 0 ||
            creditedMinutes <= 0) {
          return false;
        }
        final int advanced = wish.progressValue + creditedMinutes;
        final int next = advanced < wish.progressValue
            ? wish.progressValue
            : advanced; // R11 单调不减（负数脏数据防御）。
        final bool ripe = fruitStageOf(
                targetValue: wish.targetValue,
                progressValue: next) ==
            WishFruitStage.ripe;
        final db.WishesCompanion companion = db.WishesCompanion(
          progressValue: Value(next),
          status: ripe
              ? Value(WishStatus.fulfilled.index)
              : const Value.absent(),
          fulfilledAt: ripe ? Value(now) : const Value.absent(),
          fulfillSource: ripe
              ? const Value<String>(kWishFulfillSourceProgress)
              : const Value.absent(),
          treeSlot: ripe ? const Value<int?>(null) : const Value.absent(),
          parentSeenAt: ripe
              ? Value(wish.parentSeenAt ?? now)
              : const Value.absent(),
        );
        await (_db.update(_db.wishes)
              ..where((db.$WishesTable t) =>
                  t.id.equals(wishId) & t.childId.equals(_childId)))
            .write(companion);
        return ripe;
      });
}

/// [db.Task] → 领域 [Task]。
Task _toTask(db.Task r) => Task(
      id: r.id,
      name: r.name,
      subject: TaskSubject.values[r.subject],
      customSubject: r.customSubject,
      category: TaskCategory.values[r.category],
      requiresFocus: r.requiresFocus,
      minFocusMin: r.minFocusMin,
      sunlightReward: r.sunlightReward,
      repeatRule: r.repeatRule,
      isCustom: r.isCustom,
      wishId: r.wishId,
    );

/// 领域 [Task] → [db.TasksCompanion]。
db.TasksCompanion _toTaskCompanion(Task t) => db.TasksCompanion(
      id: Value(t.id),
      name: Value(t.name),
      subject: Value(t.subject.index),
      customSubject: Value(t.customSubject),
      category: Value(t.category.index),
      requiresFocus: Value(t.requiresFocus),
      minFocusMin: Value(t.minFocusMin),
      sunlightReward: Value(t.sunlightReward),
      repeatRule: Value(t.repeatRule),
      isCustom: Value(t.isCustom),
      wishId: Value(t.wishId),
    );

/// [db.CheckIn] → 领域 [CheckIn]。
CheckIn _toCheckIn(db.CheckIn r) => CheckIn(
      id: r.id,
      taskId: r.taskId,
      date: r.date,
      completedAt: r.completedAt,
      sessionId: r.sessionId,
      isPerfectDay: r.isPerfectDay,
      status: CheckInStatus.values[r.status],
      sunlightGross: r.sunlightGross,
      sunlightGranted: r.sunlightGranted,
      resolvedAt: r.resolvedAt,
      parentNote: r.parentNote,
      actualFocusMin: r.actualFocusMin,
    );

/// 领域 [CheckIn] → [db.CheckInsCompanion]。
db.CheckInsCompanion _toCheckInCompanion(CheckIn c) => db.CheckInsCompanion(
      id: Value(c.id),
      taskId: Value(c.taskId),
      date: Value(c.date),
      completedAt: Value(c.completedAt),
      sessionId: Value(c.sessionId),
      isPerfectDay: Value(c.isPerfectDay),
      status: Value(c.status.index),
      sunlightGross: Value(c.sunlightGross),
      sunlightGranted: Value(c.sunlightGranted),
      resolvedAt: Value(c.resolvedAt),
      parentNote: Value(c.parentNote),
      // F143（v30）：实际专注分钟 —— null = 未记录（历史行 / 非联动项）。
      actualFocusMin: Value(c.actualFocusMin),
    );
