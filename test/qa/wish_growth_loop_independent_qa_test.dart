/// QA 严过关（Yan）· 许愿树成长任务闭环【独立验证】
///
/// 与工程师自测 (`wish_growth_loop_qa_test.dart` / `wish_gate_test.dart`) 完全独立
/// 编写：全部跑在**真实 in-memory Drift 库 + 真实仓储 / 真实服务装配**上，不复用
/// 对方的 Fake 与断言。核心取证：
///  - 断言 1：6 条 →fulfilled 路径在「存在未 verified 关联任务」时全堵，
///    特别是第 6 条 data 事务 `settleWishFocus`（专注刷进度）不可绕过；
///  - 断言 2：孩子 pending → 家长 verifyCheckIn → fulfilled 闭环；并给出
///    「传 pending 快照 vs 传 verified 快照」的**同进程对照**，证明工程师
///    那条 verified 快照回调修复是必要的；
///  - 断言 3：收藏箱联动，孩子「许愿」栏 / 家长「待确认」两处派生隐藏与恢复，
///    tasks / check_ins 原始行零写入；
///  - 断言 4：按钮语义（我做到了 / 树上愿望级入口消失 / 无任务愿望不变）；
///  - 断言 5：盖章、撤销退档留痕、达成池徽标口径；
///  - 断言 6：普通成长任务与无任务愿望零回归。
///
/// 配套受控变异脚本见本轮 QA 报告：临时摘掉任一门控后，对应用例必须转红。
library wish_growth_loop_independent_qa_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
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
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';

String _src(String path) => File(path).readAsStringSync();

final DateTime kNow = DateTime(2026, 11, 22, 10, 30);

// ── 测试数据工厂（独立于工程师用例的字段取值）─────────────────────────────

Task _task(
  String id, {
  required String? wishId,
  required bool focus,
  int minFocusMin = 20,
  int reward = 12,
  String? repeatRule,
}) =>
    Task(
      id: id,
      name: '任务-$id',
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: minFocusMin,
      sunlightReward: reward,
      isCustom: true,
      repeatRule: repeatRule,
      wishId: wishId,
    );

Wish _wish(
  String id, {
  required String text,
  WishGoalMode mode = WishGoalMode.taskCount,
  int target = 1,
  int progress = 0,
}) =>
    Wish(
      id: id,
      childId: kChildIdDefault,
      text: text,
      createdAt: DateTime(2026, 11, 18),
      treeSlot: 0,
      targetMode: mode,
      targetValue: target,
      progressValue: progress,
    );

FocusSession _session(String id, double minutes) => FocusSession(
      id: id,
      start: kNow.subtract(Duration(minutes: minutes.round())),
      end: kNow,
      plannedMin: minutes.round(),
      actualFocusMin: minutes,
      status: FocusStatus.completed,
      sunlightEarned: minutes,
      createdAt: kNow,
    );

CheckIn _checkIn(
  String id,
  String taskId, {
  CheckInStatus status = CheckInStatus.verified,
  DateTime? completedAt,
  double? actualFocusMin,
  String? sessionId,
  double gross = 0.0,
}) =>
    CheckIn(
      id: id,
      taskId: taskId,
      date: completedAt ?? kNow,
      completedAt: completedAt ?? kNow,
      sessionId: sessionId,
      isPerfectDay: false,
      status: status,
      sunlightGross: gross,
      sunlightGranted: 0.0,
      actualFocusMin: actualFocusMin,
    );

class _Tracking implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];

  @override
  Future<void> track(TrackingEvent event) async => events.add(event);

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      events.where((TrackingEvent e) => e.type == type).toList();

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';

  List<String> get kinds => events
      .expand((TrackingEvent e) => e.payload['kind'] == null
          ? <String>[e.name]
          : <String>[e.payload['kind'] as String])
      .toList();
}

class _Fixture {
  _Fixture(
    this.database,
    this.tasks,
    this.wishes,
    this.ledger,
    this.orchestration,
    this.checkIns,
    this.tracking,
  );

  final db.AppDatabase database;
  final TaskLocalRepository tasks;
  final WishLocalRepository wishes;
  final SunlightLocalRepository ledger;
  final WishOrchestrationService orchestration;
  final TaskCheckInService checkIns;
  final _Tracking tracking;

  Future<void> seedWish(Wish w) => wishes.save(w);
  Future<void> seedTask(Task t) => tasks.saveTask(t);
}

Future<_Fixture> _fx() async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final TaskLocalRepository tasks = TaskLocalRepository(database);
  final WishLocalRepository wishes = WishLocalRepository(database);
  final SunlightLocalRepository ledger = SunlightLocalRepository(database);
  final _Tracking tracking = _Tracking();
  final WishOrchestrationService orchestration = WishOrchestrationService(
    wishes: wishes,
    wishTasks: tasks,
    account: AccountService(),
    tracking: tracking,
  );
  final TaskCheckInService checkIns = TaskCheckInService(
    tasks: tasks,
    ledger: ledger,
    focus: FocusLocalRepository(database),
    settings: SettingsLocalRepository(database),
    wishTasks: tasks,
    wishFocusWriter: tasks,
    // 与 providers.dart:547 的生产接线一致：跨端 fulfilled 事件经编排服务发。
    onWishEvent: (String wishId, WishEventKind kind, DateTime now) =>
        orchestration.emitCrossEndEvent(
      wishId: wishId,
      kind: kind,
      now: now,
    ),
    onWishCheckInVerified: (Task task, CheckIn checkIn, DateTime now) =>
        orchestration.registerCheckIn(
      wishId: task.wishId ?? '',
      checkIn: checkIn,
      task: task,
      now: now,
    ),
  );
  addTearDown(database.close);
  return _Fixture(
      database, tasks, wishes, ledger, orchestration, checkIns, tracking);
}

/// 直接读原始表行（绕过领域映射），用于证明「展示层派生 = 零写入」。
Future<String> _rawRows(_Fixture f, String table) async {
  final List<Object> rows = table == 'tasks'
      ? await f.database.select(f.database.tasks).get()
      : await f.database.select(f.database.checkIns).get();
  return rows.map((Object r) => r.toString()).join('\n§\n');
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // 断言 1：门控全能堵（6 条路径，真实 Drift）
  // ═══════════════════════════════════════════════════════════════════════
  group('断言1 · 第 6 条路径 settleWishFocus（真实 Drift 事务）', () {
    test('专注刷满 ripe 但另有关联任务未 verified ⇒ 只加进度不成真、不进池、不发事件',
        () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('w6', text: '想造一架小飞机',
          mode: WishGoalMode.focusMinutes, target: 15));
      await f.seedTask(
          _task('f6', wishId: 'w6', focus: true, minFocusMin: 15));
      await f.seedTask(_task('m6', wishId: 'w6', focus: false));

      final Task focusTask = (await f.tasks.wishTaskById('f6'))!;
      await f.checkIns.settleWishFocusTask(
        task: focusTask,
        session: _session('sess-6', 40),
        now: kNow,
      );

      final Wish got = (await f.wishes.byId('w6'))!;
      expect(got.progressValue, 15, reason: '进度照常累加，门控不阻止结算');
      expect(got.status, WishStatus.pending, reason: 'm6 未 verified，必须留树');
      expect(got.fulfillSource, isNull);
      expect(got.fulfilledAt, isNull);
      expect(got.treeSlot, 0, reason: '仍占挂载位');
      expect(await f.orchestration.poolWishes(), isEmpty, reason: '不进池');
      expect(await f.orchestration.stampedAchievedCount(), 0);
      expect(f.tracking.kinds, isEmpty, reason: '门控拦下不得发 fulfilled');
      expect(await f.ledger.all(), isEmpty, reason: '愿望任务 0 阳光');

      // 补上 m6 的 verified 流水后，同一愿望才允许成真（证明不是"永远堵死"）。
      await f.tasks.checkIn(_checkIn('c-m6', 'm6'));
      final Wish after = await f.orchestration.advanceProgress(
          wishId: 'w6', delta: 0, now: kNow);
      expect(after.status, WishStatus.fulfilled);
      expect(after.fulfillSource, kWishFulfillSourceProgress);
      expect(await f.orchestration.poolWishes(), hasLength(1));
    });

    test('全部专注任务都结算成 verified 才进池（第 6 条放行分支）', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('w6b', text: '想去月球',
          mode: WishGoalMode.focusMinutes, target: 20));
      await f.seedTask(_task('f1', wishId: 'w6b', focus: true));
      await f.seedTask(_task('f2', wishId: 'w6b', focus: true));

      await f.checkIns.settleWishFocusTask(
        task: (await f.tasks.wishTaskById('f1'))!,
        session: _session('sess-a', 30),
        now: kNow,
      );
      expect((await f.wishes.byId('w6b'))!.status, WishStatus.pending);

      await f.checkIns.settleWishFocusTask(
        task: (await f.tasks.wishTaskById('f2'))!,
        session: _session('sess-b', 30),
        now: kNow,
      );
      final Wish got = (await f.wishes.byId('w6b'))!;
      expect(got.status, WishStatus.fulfilled);
      expect(got.fulfillSource, kWishFulfillSourceProgress);
      expect(got.treeSlot, isNull);
      // 生产接线 onWishEvent 是 unawaited 入队（providers.dart:547）⇒ 等其冲刷。
      for (int i = 0;
          i < 20 && !f.tracking.kinds.contains('fulfilled');
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(f.tracking.kinds.where((String k) => k == 'fulfilled'), hasLength(1),
          reason: '事务内成真只发一条 fulfilled 跨端事件');
      expect(await f.ledger.all(), isEmpty);
    });
  });

  group('断言1 · 领域 5 条路径（真实 Drift 支撑的仓储）', () {
    // 每条路径都在「1 条 verified + 1 条未 verified」的同款初态上取动作。
    Future<_Fixture> seeded() async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wd', text: '想知道飞机为什么能起飞',
          mode: WishGoalMode.focusMinutes, target: 10, progress: 10));
      await f.seedTask(_task('done', wishId: 'wd', focus: true));
      await f.seedTask(_task('todo', wishId: 'wd', focus: true));
      await f.tasks.checkIn(_checkIn('c-done', 'done', actualFocusMin: 10));
      return f;
    }

    final List<MapEntry<String, Future<Wish> Function(_Fixture)>> paths =
        <MapEntry<String, Future<Wish> Function(_Fixture)>>[
      MapEntry<String, Future<Wish> Function(_Fixture)>(
          'selfFulfill', (f) => f.orchestration.selfFulfill(id: 'wd', now: kNow)),
      MapEntry<String, Future<Wish> Function(_Fixture)>(
          'fulfill', (f) => f.orchestration.fulfill(id: 'wd', now: kNow)),
      MapEntry<String, Future<Wish> Function(_Fixture)>(
          'advanceProgress',
          (f) => f.orchestration.advanceProgress(
              wishId: 'wd', delta: 5, now: kNow)),
      MapEntry<String, Future<Wish> Function(_Fixture)>(
          'setGoal(下调致 ripe)',
          (f) => f.orchestration.setGoal(
              wishId: 'wd',
              mode: WishGoalMode.focusMinutes,
              targetValue: 10,
              now: kNow)),
      MapEntry<String, Future<Wish> Function(_Fixture)>(
          'registerCheckIn',
          (f) => f.orchestration.registerCheckIn(
              wishId: 'wd',
              task: _task('todo', wishId: 'wd', focus: true),
              checkIn: _checkIn('c-live', 'todo',
                  actualFocusMin: 5, sessionId: 'live-session'),
              now: kNow)),
    ];

    for (final MapEntry<String, Future<Wish> Function(_Fixture)> path
        in paths) {
      test('${path.key}：ripe 也不得成真（todo 未 verified）', () async {
        final _Fixture f = await seeded();
        final Wish result = await path.value(f);
        expect(result.status, WishStatus.pending,
            reason: '${path.key} 必须被门控拦住');
        expect(result.fulfillSource, isNull);
        expect(result.fulfilledAt, isNull);
        expect(result.treeSlot, 0);
        expect((await f.wishes.byId('wd'))!.status, WishStatus.pending);
        expect(await f.orchestration.poolWishes(), isEmpty);
        expect(await f.orchestration.stampedAchievedCount(), 0);
        expect(f.tracking.kinds, isNot(contains('fulfilled')),
            reason: '拦截后不得发 fulfilled 达成埋点');
        expect(f.tracking.kinds, isNot(contains('selfFulfilled')),
            reason: '拦截后不得发 selfFulfilled 达成埋点');
        if (path.key != 'registerCheckIn') {
          expect(f.tracking.kinds, isNot(contains('taskVerified')),
              reason: '非核销路径不应发 taskVerified');
        }
      });
    }

    test('判据定义唯一：全 lib 只有 wish_progress.dart 一处实现', () {
      final String pure = _src('lib/domain/services/wish_progress.dart');
      expect('bool wishTasksAllDone({'.allMatches(pure), hasLength(1));
      for (final String p in <String>[
        'lib/domain/services/wish_orchestration_service.dart',
        'lib/data/local/repositories/task_local_repository.dart',
        'lib/presentation/child/pages/wish_tree_page.dart',
        'lib/presentation/child/pages/child_task_page.dart',
        'lib/presentation/parent/pages/parent_today_page.dart',
      ]) {
        expect(_src(p).contains('bool wishTasksAllDone({'), isFalse,
            reason: '$p 不得散写第二份判据');
      }
      expect(
        _src('lib/domain/services/wish_orchestration_service.dart')
            .contains('wishTasksAllDone('),
        isTrue,
      );
      expect(
        _src('lib/data/local/repositories/task_local_repository.dart')
            .contains('wishTasksAllDone('),
        isTrue,
        reason: '第 6 条 data 事务必须挂同一判据',
      );
    });

    test('判据纯函数语义：无任务/一次性/每天/pending/删除任务', () {
      final Task once = _task('once', wishId: 'w', focus: false);
      final Task daily = _task('daily', wishId: 'w', focus: false,
          repeatRule: 'daily');
      expect(wishTasksAllDone(tasks: const <Task>[], checkIns: const <CheckIn>[],
          now: kNow), isTrue, reason: '无任务愿望不拦');
      expect(
        wishTasksAllDone(tasks: <Task>[once],
            checkIns: <CheckIn>[_checkIn('v', 'once')], now: kNow),
        isTrue,
      );
      expect(
        wishTasksAllDone(tasks: <Task>[once],
            checkIns: <CheckIn>[_checkIn('p', 'once',
                status: CheckInStatus.pending)],
            now: kNow),
        isFalse,
        reason: 'pending 未确认为未完成',
      );
      expect(
        wishTasksAllDone(tasks: <Task>[daily],
            checkIns: <CheckIn>[_checkIn('v2', 'daily',
                completedAt: kNow.subtract(const Duration(days: 1)))],
            now: kNow),
        isFalse,
        reason: '每天任务昨日 verified 不算今日完成',
      );
      expect(
        wishTasksAllDone(tasks: <Task>[daily],
            checkIns: <CheckIn>[_checkIn('v3', 'daily')], now: kNow),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 2：家长确认真闭环 + verified 快照回调必要性对照
  // ═══════════════════════════════════════════════════════════════════════
  group('断言2 · 孩子 pending → 家长确认 → fulfilled', () {
    test('全链路：0 阳光 / source=progress / 盖章+1 / 进池 / 无我自己做到徽标',
        () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wp', text: '想要一个小飞机'));
      await f.seedTask(_task('mp', wishId: 'wp', focus: false));
      final Task task = (await f.tasks.wishTaskById('mp'))!;

      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      expect(child.status, CheckInStatus.pending);
      expect(child.reward, 0.0);
      expect(child.granted, 0.0);
      expect((await f.wishes.byId('wp'))!.status, WishStatus.pending,
          reason: '提交不等于实现');

      final List<PendingCheckIn> pending = await f.checkIns.pendingCheckIns();
      expect(pending, hasLength(1));
      expect(pending.single.task?.wishId, 'wp');

      final TaskCheckInOutcome parent =
          await f.checkIns.verifyCheckIn(child.checkInId, kNow);
      expect(parent.status, CheckInStatus.verified);
      expect(parent.granted, 0.0, reason: '家长确认仍 0 阳光');
      expect(await f.ledger.all(), isEmpty, reason: '不写阳光账本');

      final Wish got = (await f.wishes.byId('wp'))!;
      expect(got.status, WishStatus.fulfilled);
      expect(got.fulfillSource, kWishFulfillSourceProgress);
      expect(got.treeSlot, isNull);
      expect(await f.orchestration.poolWishes(), hasLength(1));
      expect(await f.orchestration.stampedAchievedCount(), 1);
      expect(WishPoolTile.isSelfFulfilled(got), isFalse,
          reason: 'progress 来源不显示「我自己做到的」');
      expect(f.tracking.kinds, contains('taskVerified'));
      expect(f.tracking.kinds, isNot(contains('taskRejected')));
      expect(await f.checkIns.pendingCheckIns(), isEmpty);
    });

    test('对照：传 pending 快照给 registerCheckIn 不会推进愿望（证明 verified 快照修复必要）',
        () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wsnap', text: '想要一个小飞机'));
      await f.seedTask(_task('msnap', wishId: 'wsnap', focus: false));
      final Task task = (await f.tasks.wishTaskById('msnap'))!;
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      final CheckIn pendingSnapshot = (await f.tasks.checkInById(child.checkInId))!;
      expect(pendingSnapshot.status, CheckInStatus.pending);

      // 模拟"修复前"：把 CAS 前读到的 pending 对象直接回调编排服务。
      final Wish beforeFix = await f.orchestration.registerCheckIn(
        wishId: 'wsnap',
        task: task,
        checkIn: pendingSnapshot,
        now: kNow,
      );
      expect(beforeFix.status, WishStatus.pending,
          reason: 'pending 快照 ⇒ progressDeltaOf=0 ⇒ 愿望不推进');
      expect(beforeFix.progressValue, 0);
      expect(await f.orchestration.poolWishes(), isEmpty);

      // 模拟"修复后"：verifyCheckIn 的 CAS 会先把 verified 行落库，再把
      // verified 快照回调编排服务（门控读的就是这份落库结果）。
      final CheckIn verifiedSnapshot = CheckIn(
        id: pendingSnapshot.id,
        taskId: pendingSnapshot.taskId,
        date: pendingSnapshot.date,
        completedAt: pendingSnapshot.completedAt,
        sessionId: pendingSnapshot.sessionId,
        isPerfectDay: pendingSnapshot.isPerfectDay,
        status: CheckInStatus.verified,
        sunlightGross: pendingSnapshot.sunlightGross,
        sunlightGranted: pendingSnapshot.sunlightGranted,
        resolvedAt: kNow,
        parentNote: pendingSnapshot.parentNote,
        actualFocusMin: pendingSnapshot.actualFocusMin,
      );
      // CAS 是原地改同一行，用 updateCheckIn 模拟（同 id 走 insert 会撞主键）。
      await f.tasks.updateCheckIn(verifiedSnapshot);
      final Wish afterFix = await f.orchestration.registerCheckIn(
        wishId: 'wsnap',
        task: task,
        checkIn: verifiedSnapshot,
        now: kNow,
      );
      expect(afterFix.status, WishStatus.fulfilled,
          reason: 'verified 快照 ⇒ progress +1 ⇒ 门控通过');
      expect(afterFix.fulfillSource, kWishFulfillSourceProgress);
    });

    test('多任务：只确认一条不成真，两条都确认才进池', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wm', text: '想去科技馆', target: 2));
      await f.seedTask(_task('m1', wishId: 'wm', focus: false));
      await f.seedTask(_task('m2', wishId: 'wm', focus: false));
      final Task t1 = (await f.tasks.wishTaskById('m1'))!;
      final Task t2 = (await f.tasks.wishTaskById('m2'))!;

      final TaskCheckInOutcome c1 = await f.checkIns.checkIn(task: t1, now: kNow);
      await f.checkIns.verifyCheckIn(c1.checkInId, kNow);
      expect((await f.wishes.byId('wm'))!.status, WishStatus.pending,
          reason: 'm2 未确认');

      final TaskCheckInOutcome c2 = await f.checkIns.checkIn(task: t2, now: kNow);
      await f.checkIns.verifyCheckIn(c2.checkInId, kNow);
      final Wish got = (await f.wishes.byId('wm'))!;
      expect(got.status, WishStatus.fulfilled);
      expect(got.progressValue, 2);
      expect(await f.orchestration.stampedAchievedCount(), 1);
    });

    test('家长驳回：愿望不成真，孩子可重做', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wr', text: '想要一本绘本'));
      await f.seedTask(_task('mr', wishId: 'wr', focus: false));
      final Task task = (await f.tasks.wishTaskById('mr'))!;
      final TaskCheckInOutcome c = await f.checkIns.checkIn(task: task, now: kNow);
      await f.checkIns.rejectCheckIn(c.checkInId, note: '再想想', now: kNow);
      expect((await f.wishes.byId('wr'))!.status, WishStatus.pending);
      expect(await f.orchestration.poolWishes(), isEmpty);
      // 驳回后同一任务可再次提交。
      final TaskCheckInOutcome again =
          await f.checkIns.checkIn(task: task, now: kNow);
      expect(again.status, CheckInStatus.pending);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 3：收藏箱联动
  // ═══════════════════════════════════════════════════════════════════════
  group('断言3 · 收藏箱派生隐藏 / 恢复 / 零写入', () {
    test('进箱隐藏、拿出恢复；tasks 与 check_ins 原始行逐字节不变', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wbox', text: '想要一个小飞机'));
      await f.seedTask(_task('mbox', wishId: 'wbox', focus: false));
      // 再放一条普通成长任务作为对照。
      await f.seedTask(_task('normal', wishId: null, focus: false));
      final Task task = (await f.tasks.wishTaskById('mbox'))!;
      final TaskCheckInOutcome c = await f.checkIns.checkIn(task: task, now: kNow);

      final String tasksBefore = await _rawRows(f, 'tasks');
      final String checkInsBefore = await _rawRows(f, 'checkIns');
      final Map<String, Wish> wishById = <String, Wish>{
        'wbox': (await f.wishes.byId('wbox'))!,
      };

      expect(isWishTaskVisible(task: task, wishById: wishById), isTrue);
      await f.orchestration.collectToBox(id: 'wbox', now: kNow);
      final Wish boxed = (await f.wishes.byId('wbox'))!;
      expect(boxed.releasedAt, kNow);
      expect(boxed.status, WishStatus.pending, reason: '收藏箱是正交维度');
      final Map<String, Wish> boxedMap = <String, Wish>{'wbox': boxed};
      expect(isWishTaskVisible(task: task, wishById: boxedMap), isFalse);

      // 家长「待确认」段使用与页面同源的过滤式（parent_today_page.dart:172）。
      final List<PendingCheckIn> parentVisible =
          (await f.checkIns.pendingCheckIns()).where((PendingCheckIn item) {
        final Task? t = item.task;
        return t == null || isWishTaskVisible(task: t, wishById: boxedMap);
      }).toList();
      expect(parentVisible, isEmpty, reason: '家长待确认段隐藏');

      // 孩子「许愿」栏同源过滤式（child_task_page.dart:615）。
      final List<Task> childWishColumn =
          (await f.tasks.allTasksIncludingWish()).where(
        (Task t) =>
            (t.wishId != null || t.category == TaskCategory.wish) &&
            isWishTaskVisible(task: t, wishById: boxedMap),
      ).toList();
      expect(childWishColumn.map((Task t) => t.id), isNot(contains('mbox')),
          reason: '许愿栏隐藏箱中愿望任务');
      // 普通成长任务本来就在自己的分类栏（wishId==null 分支），逐字节不变。
      final Task ordinary = (await f.tasks.allTasksIncludingWish())
          .singleWhere((Task t) => t.id == 'normal');
      expect(ordinary.wishId, isNull);
      expect(isWishTaskVisible(task: ordinary, wishById: boxedMap), isTrue,
          reason: '普通成长任务恒可见');

      expect(await _rawRows(f, 'tasks'), tasksBefore, reason: 'tasks 表零写入');
      expect(await _rawRows(f, 'checkIns'), checkInsBefore,
          reason: 'pending 打卡原样保留、零写入');

      // 拿出收藏箱 ⇒ 自动恢复，仍零写入。
      await f.orchestration.restoreFromBox(id: 'wbox', now: kNow);
      final Wish restored = (await f.wishes.byId('wbox'))!;
      final Map<String, Wish> restoredMap = <String, Wish>{'wbox': restored};
      expect(restored.releasedAt, isNull);
      expect(isWishTaskVisible(task: task, wishById: restoredMap), isTrue);
      expect(await f.checkIns.pendingCheckIns(), hasLength(1),
          reason: 'pending 原样回到家长待确认');
      final CheckIn again = (await f.tasks.checkInById(c.checkInId))!;
      expect(again.status, CheckInStatus.pending);
      expect(await _rawRows(f, 'tasks'), tasksBefore);
      expect(await _rawRows(f, 'checkIns'), checkInsBefore);
    });

    test('两处展示层都调用同一纯函数；无任务愿望不受收藏影响', () {
      final String child = _src('lib/presentation/child/pages/child_task_page.dart');
      final String parent =
          _src('lib/presentation/parent/pages/parent_today_page.dart');
      final String detail = _src('lib/presentation/child/pages/wish_tree_page.dart');
      expect(child.contains('isWishTaskVisible('), isTrue);
      expect(parent.contains('isWishTaskVisible('), isTrue);
      expect(detail.contains('isWishTaskVisible('), isTrue);
      expect('bool isWishTaskVisible({'.allMatches(
          _src('lib/domain/services/wish_progress.dart')), hasLength(1));

      final Task ordinary = _task('plain', wishId: null, focus: false);
      expect(isWishTaskVisible(task: ordinary, wishById: const <String, Wish>{}),
          isTrue);
      expect(
        isWishTaskVisible(
          task: _task('orphan', wishId: 'missing', focus: false),
          wishById: const <String, Wish>{},
        ),
        isTrue,
        reason: '父愿望缺失时安全默认可见',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 4：按钮语义
  // ═══════════════════════════════════════════════════════════════════════
  group('断言4 · 按钮语义与唯一入口', () {
    test('wishRealizeEntryOf：有任务愿望无愿望级直接进池入口', () {
      expect(
        wishRealizeEntryOf(onTree: true, tasks: <Task>[
          _task('m', wishId: 'w', focus: false),
        ]),
        WishRealizeEntry.firstManualTask,
        reason: '手动愿望任务承载达成入口',
      );
      expect(
        wishRealizeEntryOf(onTree: true, tasks: <Task>[
          _task('f', wishId: 'w', focus: true),
        ]),
        WishRealizeEntry.none,
        reason: '纯专注愿望任务由专注结算闭环，愿望级入口消失',
      );
      expect(
        wishRealizeEntryOf(onTree: true, tasks: const <Task>[]),
        WishRealizeEntry.wishCard,
        reason: '无任务愿望保持 v0.5 自助实现（Q2 逐字节不变）',
      );
      expect(
        wishRealizeEntryOf(onTree: false, tasks: const <Task>[]),
        WishRealizeEntry.none,
      );
    });

    test('文案接线：任务卡用 wishTaskDidIt；愿望级主按钮仍是 wishDetailRealized', () {
      final String tree = _src('lib/presentation/child/pages/wish_tree_page.dart');
      expect(tree.contains('didItLabel: t.wishTaskDidIt'), isTrue);
      expect(tree.contains('confirmLabel: t.wishDetailRealized'), isTrue);
      expect(tree.contains('pendingLabel: t.wishTaskPending'), isTrue);
      expect(tree.contains('t.wishTaskSubmitConfirm'), isTrue);
      final String zh = _src('lib/l10n/app_zh.arb');
      final String en = _src('lib/l10n/app_en.arb');
      expect(zh.contains('"wishTaskDidIt": "我做到了"'), isTrue);
      expect(en.contains('"wishTaskDidIt": "I did it"'), isTrue);
      expect(zh.contains('"wishDetailRealized": "实现了"'), isTrue);
      expect(zh.contains('"parentWishTaskBuyGift"'), isTrue);
      expect(en.contains('"parentWishTaskBuyGift"'), isTrue);
    });

    testWidgets('手动愿望任务卡渲染「我做到了」；取消不落库、确认才提交一次',
        (WidgetTester tester) async {
      int didIt = 0;
      final Task task = _task('wish-btn', wishId: 'w', focus: false);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WishTaskCard(
            task: task,
            wishTitle: '小飞机',
            focusActionLabel: '去专注',
            didItLabel: '我做到了',
            confirmTitle: '我做到了',
            confirmMessage: '提交后等爸爸妈妈确认，通过后愿望就实现啦',
            startFocusLabel: '开始专注',
            cancelLabel: '取消',
            doneLabel: '已完成',
            pendingLabel: '等家长确认',
            onDidIt: () => didIt++,
          ),
        ),
      ));
      expect(find.text('我做到了'), findsOneWidget);
      expect(find.text('实现了'), findsNothing);

      await tester.tap(find.byKey(const Key('wish_task_did_it')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child_confirm_card_surface')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(didIt, 0, reason: '取消不落任何记录');

      await tester.tap(find.byKey(const Key('wish_task_did_it')));
      await tester.pumpAndSettle();
      // 确认卡标题与按钮都叫「我做到了」⇒ 取最后一个（按钮）。
      await tester.tap(find.descendant(
        of: find.byKey(const Key('child_confirm_card_surface')),
        matching: find.text('我做到了'),
      ).last);
      await tester.pumpAndSettle();
      expect(didIt, 1, reason: '确认才提交，且恰好一次');
    });

    test('家长卡片买礼物提示由 wishText 派生', () {
      final String parent =
          _src('lib/presentation/parent/pages/parent_today_page.dart');
      expect(parent.contains('t.parentWishTaskBuyGift('), isTrue);
      expect(_src('lib/l10n/app_zh.arb').contains('请给小朋友买：{wishText}'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 断言 5 / 6：口径回归与零回归
  // ═══════════════════════════════════════════════════════════════════════
  group('断言5 · 盖章 / 撤销退档 / 徽标', () {
    test('撤销：fulfilled→pending + 挂回树 + wishUndo(parent) + 盖章回退', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wu', text: '想要一个小飞机'));
      await f.seedTask(_task('mu', wishId: 'wu', focus: false));
      final Task task = (await f.tasks.wishTaskById('mu'))!;
      final TaskCheckInOutcome c = await f.checkIns.checkIn(task: task, now: kNow);
      await f.checkIns.verifyCheckIn(c.checkInId, kNow);
      expect(await f.orchestration.stampedAchievedCount(), 1);

      final Wish reverted =
          await f.orchestration.undoFulfill(id: 'wu', now: kNow);
      expect(reverted.status, WishStatus.pending);
      expect(reverted.treeSlot, isNotNull, reason: '挂回树');
      expect(reverted.releasedAt, isNull);
      expect(reverted.fulfilledAt, kNow, reason: '审计留痕保留');
      expect(reverted.fulfillSource, kWishFulfillSourceProgress,
          reason: '来源留痕不清空');
      expect(await f.orchestration.stampedAchievedCount(), 0, reason: '盖章回退');
      expect(
        f.tracking.events.any((TrackingEvent e) =>
            e.name == TrackingEventNames.wishUndo &&
            e.payload['actor'] == 'parent'),
        isTrue,
      );
      // 历史 verified 打卡保留；再次闭环属预期。
      final CheckIn kept = (await f.tasks.checkInById(c.checkInId))!;
      expect(kept.status, CheckInStatus.verified);
    });
  });

  group('断言6 · 零回归', () {
    test('无任务愿望：selfFulfill 仍 source=child、发 selfFulfilled', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wn', text: '想要一只小狗'));
      final Wish got = await f.orchestration.selfFulfill(id: 'wn', now: kNow);
      expect(got.status, WishStatus.fulfilled);
      expect(got.fulfillSource, kWishFulfillSourceChild);
      expect(got.treeSlot, isNull);
      expect(f.tracking.kinds, contains('selfFulfilled'));
      expect(await f.orchestration.stampedAchievedCount(), 1);
      expect(WishPoolTile.isSelfFulfilled(got), isTrue);
    });

    test('无任务愿望：fulfill 仍 source=parentAction', () async {
      final _Fixture f = await _fx();
      await f.seedWish(_wish('wn2', text: '想去海边'));
      final Wish got = await f.orchestration.fulfill(id: 'wn2', now: kNow);
      expect(got.status, WishStatus.fulfilled);
      expect(got.fulfillSource, kWishFulfillSourceParentAction);
      expect(f.tracking.kinds, contains('fulfilled'));
    });

    test('普通成长任务(wishId==null)：照常 12 阳光入账、不触发愿望回调', () async {
      final _Fixture f = await _fx();
      await f.seedTask(_task('gn', wishId: null, focus: false, reward: 12));
      // wishTaskById 只查 wishId!=null 的行；普通成长任务须走 tasks()。
      final Task task = (await f.tasks.tasks()).singleWhere((Task t) => t.id == 'gn');
      final TaskCheckInOutcome c = await f.checkIns.checkIn(task: task, now: kNow);
      expect(c.reward, 12.0, reason: '普通成长任务奖励口径不变');
      expect(c.granted, 0.0, reason: '提交当期仍不发');

      final TaskCheckInOutcome v = await f.checkIns.verifyCheckIn(c.checkInId, kNow);
      expect(v.granted, 12.0, reason: '家长核销后按原口径入账');
      expect(await f.ledger.all(), hasLength(1));
      expect(f.tracking.kinds, isEmpty, reason: '无 wishId 不走愿望达成回调');
      expect(await f.orchestration.poolWishes(), isEmpty);
    });

    test('冻结契约：6 态 index / schemaVersion 32 / 3 来源常量不变', () {
      expect(WishStatus.values.map((WishStatus s) => s.index).toList(),
          <int>[0, 1, 2, 3, 4, 5]);
      expect(kWishFulfillSourceParentAction, 'parentAction');
      expect(kWishFulfillSourceProgress, 'progress');
      expect(kWishFulfillSourceChild, 'child');
      expect(_src('lib/data/local/database/app_database.dart')
          .contains('int get schemaVersion => 32;'), isTrue);
    });

    test('家长待确认卡在真相册里存在愿望分支与买礼物提示', () {
      final String parent =
          _src('lib/presentation/parent/pages/parent_today_page.dart');
      expect(parent.contains('wishById'), isTrue);
      expect(parent.contains('parentWishTaskBuyGift'), isTrue);
    });
  });
}
