/// 本地任务 / 打卡仓储（实现 domain 接口，§2.1 / §3.1）。
///
/// 真实 Drift 实现，替换 M0 的 `TaskLocalRepositoryStub`（M3 T01）。
/// M4：额外实现家长核销能力接口 [CheckInAdminRepository]。
library task_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

class TaskLocalRepository implements TaskRepository, CheckInAdminRepository {
  final db.AppDatabase _db;

  TaskLocalRepository(this._db);

  @override
  Future<List<Task>> tasks() async =>
      (await _db.taskDao.allTasks()).map(_toTask).toList();

  @override
  Future<void> saveTask(Task task) =>
      _db.taskDao.upsertTask(_toTaskCompanion(task));

  @override
  Future<void> deleteTaskById(String id) => _db.taskDao.deleteTaskById(id);

  @override
  Future<void> checkIn(CheckIn checkIn) =>
      _db.taskDao.insertCheckIn(_toCheckInCompanion(checkIn));

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async =>
      (await _db.taskDao.checkInsOfDay(dayKey)).map(_toCheckIn).toList();

  @override
  Future<int> totalCheckInCount() =>
      _db.taskDao.countCheckInsByStatus(CheckInStatus.verified.index);

  // ── CheckInAdminRepository（家长端核销，M4）──────────────────────────────
  @override
  Future<CheckIn?> checkInById(String id) async {
    final db.CheckIn? row = await _db.taskDao.checkInById(id);
    return row == null ? null : _toCheckIn(row);
  }

  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async =>
      (await _db.taskDao.checkInsByStatus(status.index))
          .map(_toCheckIn)
          .toList();

  @override
  Future<void> updateCheckIn(CheckIn checkIn) =>
      _db.taskDao.updateCheckIn(_toCheckInCompanion(checkIn));

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
      ) == 1;
}

/// [db.Task] → 领域 [Task]。
Task _toTask(db.Task r) => Task(
      id: r.id,
      name: r.name,
      subject: TaskSubject.values[r.subject],
      customSubject: r.customSubject,
      requiresFocus: r.requiresFocus,
      minFocusMin: r.minFocusMin,
      sunlightReward: r.sunlightReward,
      repeatRule: r.repeatRule,
      isCustom: r.isCustom,
    );

/// 领域 [Task] → [db.TasksCompanion]。
db.TasksCompanion _toTaskCompanion(Task t) => db.TasksCompanion(
      id: Value(t.id),
      name: Value(t.name),
      subject: Value(t.subject.index),
      customSubject: Value(t.customSubject),
      requiresFocus: Value(t.requiresFocus),
      minFocusMin: Value(t.minFocusMin),
      sunlightReward: Value(t.sunlightReward),
      repeatRule: Value(t.repeatRule),
      isCustom: Value(t.isCustom),
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
    );
