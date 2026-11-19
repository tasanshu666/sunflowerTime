/// A-T03 专注 / 核销链路守卫（验收 ⑪~⑱）。
///
/// 经济与读侧隔离跑在真实 in-memory drift 库上（不是空 Map 占位断言）：
/// 愿望任务结算前后逐位比较阳光账本、余额、check_ins、完美日、周月池、今日必做。
library wish_focus_settlement_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

String _read(String path) => File(path).readAsStringSync();

Task _task({
  required String id,
  required bool focus,
  String? wishId,
  int min = 15,
}) =>
    Task(
      id: id,
      name: id,
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: min,
      sunlightReward: 12,
      isCustom: false,
      wishId: wishId,
    );

FocusSession _session({
  required String id,
  required double minutes,
  DateTime? now,
}) {
  final DateTime at = now ?? DateTime(2026, 11, 20, 10);
  return FocusSession(
    id: id,
    start: at.subtract(Duration(minutes: minutes.round())),
    end: at,
    plannedMin: 20,
    actualFocusMin: minutes,
    status: FocusStatus.completed,
    sunlightEarned: minutes,
    createdAt: at,
  );
}

class _Fixture {
  _Fixture(this.database, this.tasks, this.wishes, this.ledger, this.service);

  final db.AppDatabase database;
  final TaskLocalRepository tasks;
  final WishLocalRepository wishes;
  final SunlightLocalRepository ledger;
  final TaskCheckInService service;
}

Future<_Fixture> _fixture() async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final TaskLocalRepository tasks = TaskLocalRepository(database);
  final SunlightLocalRepository ledger = SunlightLocalRepository(database);
  final TaskCheckInService service = TaskCheckInService(
    tasks: tasks,
    ledger: ledger,
    focus: FocusLocalRepository(database),
    settings: SettingsLocalRepository(database),
    wishTasks: tasks,
    wishFocusWriter: tasks,
  );
  return _Fixture(database, tasks, WishLocalRepository(database), ledger, service);
}

Future<void> _seedWish(_Fixture f, {int target = 30}) => f.wishes.save(Wish(
      id: 'w1',
      childId: kChildIdDefault,
      text: '想去动物园',
      createdAt: DateTime(2026, 11, 1),
      treeSlot: 0,
      targetValue: target,
      targetMode: WishGoalMode.focusMinutes,
    ));

void main() {
  test('⑪ 双参都带：?task= 优先，wishTaskId 丢弃 + warning + 埋点', () {
    final String src = _read('lib/shared/app_router.dart');
    expect(src.contains("queryParameters['wishTask']"), isTrue);
    expect(src.contains('final bool wishTaskConflict = hasTask && hasWishTask;'),
        isTrue);
    expect(src.contains('wishTaskId: wishTaskConflict ? null : wishTaskId'),
        isTrue);
    expect(src.contains('TrackingEventNames.wishFocusConflict'), isTrue);
    expect(src.contains("log('wish_focus_conflict"), isTrue);
    final String focus = _read(
        'lib/presentation/child/pages/focus_page.dart');
    expect(focus.contains('final String? wishTaskId;'), isTrue);
  });

  test('⑫ 只带 ?wishTask=：走愿望任务分支（不发阳光）', () async {
    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await _seedWish(f);
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1'));
    final Task outcomeTask = (await f.tasks.wishTaskById('tw'))!;
    final TaskCheckInOutcome outcome = await f.service.settleWishFocusTask(
      task: outcomeTask,
      session: _session(id: 's1', minutes: 20),
      now: DateTime(2026, 11, 20, 10),
    );
    expect(outcome.status, CheckInStatus.verified);
    expect(outcome.reward, 0.0);
    expect(outcome.granted, 0.0);
    expect(outcome.perfectDayBonus, isFalse);
  });

  test('⑬ 有效专注：推进进度 + 落 check_ins（sessionId 锚）', () async {
    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await _seedWish(f);
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1', min: 30));
    final Task outcomeTask = (await f.tasks.wishTaskById('tw'))!;
    await f.service.settleWishFocusTask(
      task: outcomeTask,
      session: _session(id: 's_anchor', minutes: 20),
      now: DateTime(2026, 11, 20, 10),
    );
    final Wish updated = (await f.wishes.byId('w1'))!;
    // 真量独立计算：floor(实际分钟) 且封顶 min_focus_min=30 ⇒ 20。
    expect(updated.progressValue, 20);
    final List<CheckIn> rows =
        await f.tasks.checkInsOfDay('2026-11-20');
    expect(rows.length, 1);
    expect(rows.single.sessionId, 's_anchor');
    expect(rows.single.actualFocusMin, 20.0);
    expect(rows.single.sunlightGross, 0.0);
    expect(rows.single.sunlightGranted, 0.0);
  });

  test('⑭ 无效专注（短退）：不推进、不写任何记录', () async {
    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await _seedWish(f);
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1'));
    final Task outcomeTask = (await f.tasks.wishTaskById('tw'))!;
    final TaskCheckInOutcome outcome = await f.service.settleWishFocusTask(
      task: outcomeTask,
      session: _session(id: 's_short', minutes: 3),
      now: DateTime(2026, 11, 20, 10),
    );
    expect(outcome.status, CheckInStatus.rejected);
    expect(outcome.checkInId, '');
    expect((await f.wishes.byId('w1'))!.progressValue, 0);
    expect(await f.tasks.checkInsOfDay('2026-11-20'), isEmpty);
  });

  test('⑮ 同一 session 两次：第二次不重复计入（R16）', () async {
    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await _seedWish(f, target: 100);
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1', min: 40));
    final Task outcomeTask = (await f.tasks.wishTaskById('tw'))!;
    final FocusSession session = _session(id: 's_once', minutes: 20);
    await f.service.settleWishFocusTask(
        task: outcomeTask, session: session, now: DateTime(2026, 11, 20, 10));
    TaskCheckInOutcome? second;
    try {
      second = await f.service.settleWishFocusTask(
          task: outcomeTask,
          session: session,
          now: DateTime(2026, 11, 20, 10, 1));
    } on TaskCheckInException catch (e) {
      expect(e.code, TaskCheckInError.sessionUsed);
    }
    if (second != null) expect(second.checkInId.isNotEmpty, isTrue);
    // 幂等返回既有记录：不得新增第二行、进度不得二次累加。
    expect((await f.tasks.checkInsOfDay('2026-11-20')).length, 1);
    expect((await f.wishes.byId('w1'))!.progressValue, 20);
  });

  test('⑯ 既有 ?task= 链路逐字节不变（回归断言）', () {
    final String src = _read(
        'lib/presentation/child/pages/focus_page.dart');
    final int start = src.indexOf('    // M4：联动成长项自动结算');
    final int end = src.indexOf('    // ── A-T03：愿望任务结算', start);
    final String legacy = src.substring(start, end);
    expect(legacy.contains('.settleFocusLinked('), isTrue);
    expect(legacy.contains('taskId: taskId,'), isFalse);
    expect(legacy.contains('wishTask'), isFalse,
        reason: '成长任务分支里不得插入愿望任务分支');
    expect(legacy.contains('ref.read(taskRepositoryProvider).tasks()'), isTrue);
    expect(legacy.contains('settlement.sessionId'), isTrue);
    expect(legacy.contains('economyRevisionProvider.notifier).state++'), isTrue);
  });

  test('⑰ 经济隔离：账本/余额/check_ins/完美日/周月池/今日必做逐位不变', () async {
    // 源码守卫：判定收敛到唯一 helper（G14），5 处隔离点全部复用它。
    final String src = _read('lib/domain/services/task_checkin_service.dart');
    final int literals = src
        .split('\n')
        .where((String line) =>
            line.contains('task.wishId != null') &&
            !line.trimLeft().startsWith('///'))
        .length;
    expect(literals, 1, reason: 'wishId 判定只允许出现在唯一 helper 里');
    expect(
        src.contains('static bool _isWishLinkedTask(Task task) => '
            'task.wishId != null'),
        isTrue);
    expect('_isWishLinkedTask('.allMatches(src).length, greaterThanOrEqualTo(6));

    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await _seedWish(f);
    await f.tasks.saveTask(_task(id: 'tg', focus: false));
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1'));

    // 基线：先跑一次既有成长任务打卡，建立非空账本 / 流水。
    await f.service.checkIn(
        task: _task(id: 'tg', focus: false), now: DateTime(2026, 11, 20, 9));
    final List<Object?> ledgerBefore = (await f.ledger.all()).map((e) => <Object?>[
          e.id,
          e.gross,
          e.net,
          e.balanceAfter,
          e.refType,
          e.refId,
        ]).toList();
    final double balanceBefore = await f.ledger.balance();
    final int checkInsBefore = (await f.tasks.checkInsOfDay('2026-11-20')).length;
    final int monthlyBefore =
        (await f.database.select(f.database.monthlyPools).get()).length;

    // 用今天的日期取今日必做（board 内部 dayKey(now)）。
    final DateTime now = DateTime(2026, 11, 20, 10);
    final int boardTotalBefore = (await f.service.board(now)).total;

    final Task outcomeTask = (await f.tasks.wishTaskById('tw'))!;
    await f.service.settleWishFocusTask(
      task: outcomeTask,
      session: _session(id: 's_iso', minutes: 20),
      now: now,
    );

    expect((await f.ledger.all()).map((e) => <Object?>[
          e.id,
          e.gross,
          e.net,
          e.balanceAfter,
          e.refType,
          e.refId,
        ]).toList(),
        ledgerBefore);
    expect(await f.ledger.balance(), balanceBefore);
    final List<CheckIn> after = await f.tasks.checkInsOfDay('2026-11-20');
    expect(after.length, checkInsBefore + 1); // 只有愿望任务那一条流水
    expect(after.last.isPerfectDay, isFalse);
    expect(
        (await f.database.select(f.database.monthlyPools).get()).length,
        monthlyBefore);
    final int boardTotalAfter = (await f.service.board(now)).total;
    expect(boardTotalAfter, boardTotalBefore);
    // v0.3 验收 5(c)：board 现在显式包含愿望任务，愿望任务核销后也会进
    // 「已做」计数 ⇒ 原本为 false 的 allDone 在两件事都做完后变 true。
    expect((await f.service.board(now)).allDone, isTrue,
        reason: 'board 含愿望任务：tg 已打卡 + tw 已核销 ⇒ 全做完了');
  });

  test('⑱ 读侧隔离：allTasks 默认排除愿望任务，3 个既有调用点零改动', () async {
    final _Fixture f = await _fixture();
    addTearDown(f.database.close);
    await f.tasks.saveTask(_task(id: 'tg', focus: false));
    await f.tasks.saveTask(_task(id: 'tw', focus: true, wishId: 'w1'));

    final List<db.Task> defaultRows =
        await f.database.taskDao.allTasks(childId: kChildIdDefault);
    final List<db.Task> allRows = await f.database.taskDao.allTasks(
        childId: kChildIdDefault, includeWishTasks: true);
    expect(defaultRows.map((db.Task t) => t.id), <String>['tg']);
    expect(allRows.map((db.Task t) => t.id).toSet(), <String>{'tg', 'tw'});
    expect((await f.tasks.tasks()).map((Task t) => t.id), <String>['tg']);

    // 源码守卫：既有 3 个调用点不得传 includeWishTasks: true（含 task=371/657/815）。
    final String repo = _read('lib/data/local/repositories/task_local_repository.dart');
    final int tasksCall = repo.indexOf('Future<List<Task>> tasks() async');
    final String tasksBody =
        repo.substring(tasksCall, repo.indexOf('\n  @override', tasksCall));
    expect(tasksBody.contains('allTasks(childId: _childId)'), isTrue);
    expect(tasksBody.contains('includeWishTasks: true'), isFalse);
    final String service =
        _read('lib/domain/services/task_checkin_service.dart');
    for (final String marker in <String>[
      'Future<TodayTaskBoard> board(DateTime now)',
      'Future<bool> _allDailySubmitted(',
    ]) {
      final int start = service.indexOf(marker);
      final String body = service.substring(start, start + 1100);
      // v0.3 验收 5(c)：只有 board 改为「优先走 WishTaskReadBridge，
      // 拿不到 bridge 才降级 _tasks.tasks()」；其余既有调用点零改动。
      expect(
        marker.contains('board(')
            ? (body.contains('allTasksIncludingWish()') &&
                body.contains('_tasks.tasks()'))
            : body.contains('_tasks.tasks()'),
        isTrue,
        reason: marker,
      );
      expect(body.contains('includeWishTasks: true'), isFalse, reason: marker);
    }
    // 例外只在桥接实现里显式开启（家长待核销）。
    expect(repo.contains('includeWishTasks: true'), isTrue);
  });
}
