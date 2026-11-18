/// A-T03 独立复验（QA · 严过关）。
///
/// 与工程师 18 条 guard **刻意不同**：这里不重跑「文件存在 / 期望值取自生产 helper」
/// 的自证式断言，而是把最高风险的**失败路径**和**差分行为**跑在真实 in-memory drift
/// 库上：
///  - 成长任务 `?task=` 主链路的经济行为必须仍然成立（隔离不能污染主链路）；
///  - `settleWishFocusTask` 必须拒绝成长任务（helper 入口闸门）；
///  - 愿望行为型任务「打卡 → 家长核销」全路径的经济隔离 + 待核销可见性；
///  - 真实 `_emit` 产出的 `event_id`（期望值**独立拼字符串**，不调用生产 helper）；
///  - 专注结算成熟时同事务写 progress / fulfill_source / 释放 tree_slot；
///  - 通知触发时机与可选接口的源码护栏。
library wish_wiring_qa_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';

String _read(String path) => File(path).readAsStringSync();

Task _task({
  required String id,
  required bool focus,
  String? wishId,
  int min = 15,
  int reward = 12,
}) =>
    Task(
      id: id,
      name: id,
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: min,
      sunlightReward: reward,
      isCustom: false,
      wishId: wishId,
    );

FocusSession _session({
  required String id,
  required double minutes,
  DateTime? now,
}) {
  final DateTime at = now ?? DateTime(2026, 11, 21, 10);
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

/// 记录 `onWishEvent` 回调的观测值（独立于生产 helper）。
class _ObservedEvent {
  const _ObservedEvent(this.wishId, this.kind, this.at);

  final String wishId;
  final WishEventKind kind;
  final DateTime at;

  @override
  String toString() => '$wishId/${kind.name}/${at.millisecondsSinceEpoch}';
}

TaskCheckInService _service({
  required db.AppDatabase database,
  required TaskLocalRepository tasks,
  required SunlightLocalRepository ledger,
  List<_ObservedEvent>? events,
  List<String>? verifiedTaskIds,
}) =>
    TaskCheckInService(
      tasks: tasks,
      ledger: ledger,
      focus: FocusLocalRepository(database),
      settings: SettingsLocalRepository(database),
      wishTasks: tasks,
      wishFocusWriter: tasks,
      onWishEvent: events == null
          ? null
          : (String wishId, WishEventKind kind, DateTime now) {
              events.add(_ObservedEvent(wishId, kind, now));
            },
      onWishCheckInVerified: verifiedTaskIds == null
          ? null
          : (Task task, CheckIn checkIn, DateTime now) async {
              verifiedTaskIds.add(task.id);
            },
    );

Future<db.AppDatabase> _freshDb() async => db.AppDatabase(NativeDatabase.memory());

Future<Wish> _seedWish(
  WishLocalRepository wishes, {
  required String id,
  int target = 30,
  WishGoalMode mode = WishGoalMode.focusMinutes,
  int? treeSlot,
}) async {
  final Wish wish = Wish(
    id: id,
    childId: kChildIdDefault,
    text: 'QA 愿望 $id',
    createdAt: DateTime(2026, 11, 1),
    treeSlot: treeSlot,
    targetValue: target,
    targetMode: mode,
  );
  await wishes.save(wish);
  return wish;
}

ProviderContainer _container(db.AppDatabase database, SharedPreferences sp) =>
    ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(sp),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA-1 差分：成长任务 ?task= 主链路照常发阳光，愿望任务隔离为零', () async {
    // Arrange：同一库里各放一条成长 / 愿望任务，基线账本为空。
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final TaskLocalRepository tasks = TaskLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final WishLocalRepository wishes = WishLocalRepository(database);
    final TaskCheckInService service = _service(
        database: database, tasks: tasks, ledger: ledger);
    await _seedWish(wishes, id: 'w_diff');
    await tasks.saveTask(_task(id: 'tg_diff', focus: true));
    await tasks.saveTask(_task(id: 'tw_diff', focus: true, wishId: 'w_diff'));
    expect(await ledger.all(), isEmpty);

    // Act A：既有 ?task= 主链路（settleFocusLinked）—— 必须照常发阳光。
    final Task growthTask = (await tasks.tasks()).single;
    final TaskCheckInOutcome growth = await service.settleFocusLinked(
      task: growthTask,
      session: _session(id: 's_growth', minutes: 20),
      now: DateTime(2026, 11, 21, 9),
    );
    // Act B：愿望任务独立分支 —— 必须零阳光。
    final Task wishTask = (await tasks.wishTaskById('tw_diff'))!;
    final TaskCheckInOutcome wish = await service.settleWishFocusTask(
      task: wishTask,
      session: _session(id: 's_qa_diff', minutes: 20),
      now: DateTime(2026, 11, 21, 10),
    );

    // Assert：主链路经济行为完全保留（隔离没有反向污染）。
    expect(growth.status, CheckInStatus.verified);
    expect(growth.reward, greaterThan(0));
    expect(growth.granted, greaterThan(0));
    expect(await ledger.balance(), growth.granted);
    // Assert：愿望分支零经济产出，且不影响刚建立的主链路账本。
    expect(wish.status, CheckInStatus.verified);
    expect(wish.reward, 0.0);
    expect(wish.granted, 0.0);
    expect(wish.perfectDayBonus, isFalse);
    expect((await ledger.all()).length, 1,
        reason: '只有成长任务一条账本，愿望分支不得写账');
    final List<CheckIn> rows = (await tasks.checkInsOfDay('2026-11-21'))
      ..sort((CheckIn a, CheckIn b) => a.date.compareTo(b.date));
    expect(rows.length, 2);
    expect(rows.firstWhere((CheckIn c) => c.taskId == growthTask.id).sunlightGross,
        growth.reward);
    final CheckIn wishRow = rows.firstWhere((CheckIn c) => c.taskId == wishTask.id);
    expect(wishRow.sunlightGross, 0.0);
    expect(wishRow.sunlightGranted, 0.0);
    expect(wishRow.isPerfectDay, isFalse);
  });

  test('QA-2 失败路径：settleWishFocusTask 拒绝成长任务（notLinked）且不落任何记录', () async {
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final TaskLocalRepository tasks = TaskLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final TaskCheckInService service = _service(
        database: database, tasks: tasks, ledger: ledger);
    await tasks.saveTask(_task(id: 'tg_plain', focus: true));
    final Task plain = (await tasks.tasks()).single;

    TaskCheckInException? thrown;
    try {
      await service.settleWishFocusTask(
        task: plain,
        session: _session(id: 's_plain', minutes: 20),
        now: DateTime(2026, 11, 21, 11),
      );
    } on TaskCheckInException catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull);
    expect(thrown!.code, TaskCheckInError.notLinked,
        reason: '唯一 helper 判定必须把成长任务挡在愿望结算入口之外');
    expect(await tasks.checkInsOfDay('2026-11-21'), isEmpty);
    expect(await ledger.all(), isEmpty);
  });

  test('QA-3 核销路径差分：愿望行为任务待核销可见 + 核销零账本；成长任务照常入账', () async {
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final TaskLocalRepository tasks = TaskLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final WishLocalRepository wishes = WishLocalRepository(database);
    final List<String> verifiedTaskIds = <String>[];
    final TaskCheckInService service = _service(
      database: database,
      tasks: tasks,
      ledger: ledger,
      verifiedTaskIds: verifiedTaskIds,
    );
    await _seedWish(wishes, id: 'w_behav', target: 3, mode: WishGoalMode.taskCount);
    await tasks.saveTask(_task(id: 'tg_manual', focus: false));
    await tasks.saveTask(
        _task(id: 'tw_manual', focus: false, wishId: 'w_behav'));

    // 两类任务各自手动打卡（pending）。
    final Task growthTask = (await tasks.tasks()).single;
    final Task wishTask = (await tasks.wishTaskById('tw_manual'))!;
    final TaskCheckInOutcome gPending = await service.checkIn(
        task: growthTask, now: DateTime(2026, 11, 21, 9));
    final TaskCheckInOutcome wPending = await service.checkIn(
        task: wishTask, now: DateTime(2026, 11, 21, 9, 1));
    expect(gPending.reward, greaterThan(0));
    expect(wPending.reward, 0.0, reason: '愿望行为任务打卡当期不发阳光');

    // 家长待核销：成长项在前、愿望任务在后 —— 行为型愿望任务不能被读侧过滤吞掉。
    final List<PendingCheckIn> pending = await service.pendingCheckIns();
    expect(pending.length, 2);
    expect(pending.first.checkIn.id, gPending.checkInId);
    expect(pending.first.task?.wishId, isNull);
    expect(pending.last.checkIn.id, wPending.checkInId);
    expect(pending.last.task?.wishId, 'w_behav');

    // 基线：核销前账本 / 余额。
    final int ledgerBefore = (await ledger.all()).length;
    final double balanceBefore = await ledger.balance();

    // Act：先核销成长任务（必须入账），再核销愿望任务（必须零账本）。
    final TaskCheckInOutcome gVerified = await service.verifyCheckIn(
        gPending.checkInId, DateTime(2026, 11, 21, 12));
    final TaskCheckInOutcome wVerified = await service.verifyCheckIn(
        wPending.checkInId, DateTime(2026, 11, 21, 12, 1));

    // Assert：成长链路逐项入账；愿望链路完全隔离且只回调进度桥接。
    expect(gVerified.status, CheckInStatus.verified);
    expect(gVerified.granted, greaterThan(0));
    expect(wVerified.status, CheckInStatus.verified);
    expect(wVerified.reward, 0.0);
    expect(wVerified.granted, 0.0);
    expect(await ledger.balance(), balanceBefore + gVerified.granted);
    expect((await ledger.all()).length, ledgerBefore + 1,
        reason: '愿望任务核销不得写第二条账本');
    expect(verifiedTaskIds, <String>['tw_manual']);

    final List<CheckIn> all = await tasks.checkInsOfDay('2026-11-21');
    final CheckIn wishRow = all.firstWhere((CheckIn c) => c.id == wPending.checkInId);
    expect(wishRow.status, CheckInStatus.verified);
    expect(wishRow.sunlightGross, 0.0);
    expect(wishRow.sunlightGranted, 0.0);
  });

  test('QA-4 真实 _emit：event_id 逐位等于 <wishId>#<kind>#<millis>（独立拼期望）', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    await _seedWish(WishLocalRepository(database), id: 'w_emit', treeSlot: 0);
    await TaskLocalRepository(database)
        .saveTask(_task(id: 'ta_emit', focus: false));

    final DateTime t1 = DateTime(2026, 11, 21, 13, 0, 0, 123);
    final DateTime t2 = DateTime(2026, 11, 21, 13, 0, 0, 456);
    final DateTime t3 = DateTime(2026, 11, 21, 13, 5, 0, 789);
    final WishOrchestrationService services =
        c.read(wishOrchestrationServiceProvider);

    // Act：走真实编排服务（含新装配的 emitCrossEndEvent 与既有 _emit 路径）。
    await services.emitCrossEndEvent(
        wishId: 'w_emit', kind: WishEventKind.taskVerified, now: t1);
    await services.emitCrossEndEvent(
        wishId: 'w_emit', kind: WishEventKind.taskVerified, now: t2);
    await services.assignTasks(
        wishId: 'w_emit', taskIds: <String>['ta_emit'], now: t3);

    final List<TrackingEvent> events = await c
        .read(trackingRepositoryProvider)
        .eventsOfType(TrackingType.metric);
    expect(events.length, 3);

    // Assert：期望 id 由测试自己拼字符串，绝不复用生产 wishEventIdOf。
    final Set<String> actualIds = <String>{
      for (final TrackingEvent e in events) e.payload['event_id'] as String,
    };
    final Set<String> expectedIds = <String>{
      'w_emit#taskVerified#${t1.millisecondsSinceEpoch}',
      'w_emit#taskVerified#${t2.millisecondsSinceEpoch}',
      'w_emit#taskAssigned#${t3.millisecondsSinceEpoch}',
    };
    expect(actualIds.length, 3, reason: '同 kind 两次必须是两个不同 id');
    expect(actualIds, expectedIds);
    for (final TrackingEvent e in events) {
      expect(e.payload['wish_id'], 'w_emit');
      expect(e.payload['kind'], isA<String>());
      expect(e.name,
          e.payload['kind'] == 'taskVerified'
              ? TrackingEventNames.wishTaskVerified
              : TrackingEventNames.wishParentAction);
    }
  });

  test('QA-5 成熟配置：专注结算同事务写 progress / fulfill_source=progress / 释放 tree_slot',
      () async {
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final TaskLocalRepository tasks = TaskLocalRepository(database);
    final SunlightLocalRepository ledger = SunlightLocalRepository(database);
    final WishLocalRepository wishes = WishLocalRepository(database);
    final List<_ObservedEvent> events = <_ObservedEvent>[];
    final TaskCheckInService service = _service(
        database: database,
        tasks: tasks,
        ledger: ledger,
        events: events);
    // 目标 15 分钟、当前 0、挂树槽位 3：credited=min(20,15)=15 ⇒ 恰好成熟。
    await _seedWish(
      wishes,
      id: 'w_ripe',
      target: 15,
      mode: WishGoalMode.focusMinutes,
      treeSlot: 3,
    );
    await tasks.saveTask(_task(id: 'tw_ripe', focus: true, wishId: 'w_ripe', min: 15));
    final Task wishTask = (await tasks.wishTaskById('tw_ripe'))!;
    final DateTime now = DateTime(2026, 11, 21, 14);

    final TaskCheckInOutcome outcome = await service.settleWishFocusTask(
      task: wishTask,
      session: _session(id: 's_ripe', minutes: 20),
      now: now,
    );

    expect(outcome.status, CheckInStatus.verified);
    // 直接读 drift 行，验证写侧落在同一事务里的真实结果。
    final List<db.WishRow> ripeRows = await (database.select(database.wishes)
          ..where((db.$WishesTable t) => t.id.equals('w_ripe')))
        .get();
    final db.WishRow row = ripeRows.single;
    expect(row.progressValue, 15);
    expect(row.status, WishStatus.fulfilled.index);
    expect(row.fulfillSource, kWishFulfillSourceProgress);
    expect(row.treeSlot, isNull, reason: '成熟必须释放挂载位');
    expect(row.fulfilledAt, now);
    // 成熟只发一条 fulfilled，进度推进本身不产事件。
    expect(events.map((e) => e.kind).toList(),
        <WishEventKind>[WishEventKind.fulfilled]);
    expect(events.single.wishId, 'w_ripe');
    // 经济隔离在成熟路径同样成立。
    expect(await ledger.all(), isEmpty);
    final List<CheckIn> rows = await tasks.checkInsOfDay('2026-11-21');
    expect(rows.single.sessionId, 's_ripe');
    expect(rows.single.sunlightGross, 0.0);
    expect(rows.single.sunlightGranted, 0.0);
    expect(rows.single.actualFocusMin, 20.0);
  });

  test('QA-6 失败路径：即使 advanceProgress 把愿望推成熟也不产跨端事件', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = await _freshDb();
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    final WishLocalRepository wishes = WishLocalRepository(database);
    await _seedWish(wishes, id: 'w_adv', target: 10, treeSlot: 1);
    await wishes.save((await wishes.byId('w_adv'))!.copyWith(progressValue: 9));
    final TrackingLocalRepository tracking = TrackingLocalRepository(database);
    expect(await tracking.eventsOfType(TrackingType.metric), isEmpty);

    final Wish updated =
        await c.read(wishOrchestrationServiceProvider).advanceProgress(
      wishId: 'w_adv',
      delta: 5,
      now: DateTime(2026, 11, 21, 15),
    );

    expect(updated.progressValue, 14);
    expect(updated.status, WishStatus.fulfilled,
        reason: 'advanceProgress 自身仍要做成熟判定');
    expect(await tracking.eventsOfType(TrackingType.metric), isEmpty,
        reason: '进度推进不产跨端事件（含推成熟这一次）');
  });

  test('QA-7 源码守卫：愿望通知只有两处触发，修订号监听只走 legacy 三条', () {
    final String src = _read('lib/presentation/child/pages/child_shell_page.dart');

    // 修订号监听体：只调 _checkLegacyNotices，绝不调 _checkAllNotices / _checkWishNotices。
    final int listener = src.indexOf('ref.listen(economyRevisionProvider');
    final String listenerBody =
        src.substring(listener, src.indexOf('});', listener));
    expect(listenerBody.contains('_checkLegacyNotices'), isTrue);
    expect(listenerBody.contains('_checkAllNotices'), isFalse);
    expect(listenerBody.contains('_checkWishNotices'), isFalse,
        reason: '家长端操作引发修订号变化时不得弹愿望卡挡住家长');

    // 调用点恰好两处：首帧 postFrame（经 _checkAllNotices）+ didPopNext。
    expect('_checkWishNotices();'.allMatches(src).length, 2,
        reason: '_checkWishNotices 只允许两个调用点');
    final int post = src.indexOf('addPostFrameCallback');
    final String postBody = src.substring(post, src.indexOf('});', post));
    expect(postBody.contains('_checkAllNotices()'), isTrue);
  });

  test('QA-9 源码守卫：专注页愿望分支先过有效专注闸门，再按 sessionId 精确结算', () {
    final String focus =
        _read('lib/presentation/child/pages/focus_page.dart');
    final int start = focus.indexOf('// ── A-T03：愿望任务结算');
    expect(start, greaterThanOrEqualTo(0), reason: '愿望结算钩子必须存在');
    final int end = focus.indexOf('if (!mounted) return;', start);
    expect(end, greaterThan(start));
    final String branch = focus.substring(start, end);

    // 值 = 既有 tasks.id，必须经读桥接二次确认 wishId != null。
    expect(branch.contains('wishTaskById(wishTaskId)'), isTrue);
    expect(branch.contains('wishTask.wishId == null'), isTrue);
    // 精确锚定真实落库会话，绝不自造；先过 isValidFocusSession 再结算。
    expect(branch.contains('settlement.sessionId'), isTrue);
    expect(branch.contains('isValidFocusSession(session)'), isTrue,
        reason: '10 分钟 / 计划 20 分钟这类会话能过服务层 5 分钟闸门，'
            '必须靠专注页的有效专注闸门挡住');
    expect(branch.contains('settleWishFocusTask('), isTrue,
        reason: '必须走独立愿望结算入口，不得复用 settleFocusLinked');
    // 无效专注 / 异常一律静默降级为 skipped，不得抛错页。
    expect(branch.contains('wishTaskSettleSkipped = true'), isTrue);
    expect(branch.contains('catch (_)'), isTrue);
  });

  test('QA-8 源码守卫：可选桥接是独立接口，WishTaskRepository 4 方法签名未动（29 Fake 零改动）',
      () {
    final String src =
        _read('lib/domain/repositories/wish_task_repository.dart');
    final int start = src.indexOf('abstract class WishTaskRepository');
    final int end = src.indexOf('abstract class WishTaskReadBridge');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final String iface = src.substring(start, end);
    for (final String method in <String>[
      'tasksOfWish',
      'checkInsOfTaskIds',
      'assignWish',
      'unassignWish',
    ]) {
      expect(iface.contains(method), isTrue, reason: '既有方法 $method 被改动');
    }
    for (final String method in <String>[
      'wishTaskById',
      'allTasksIncludingWish',
      'settleWishFocus',
    ]) {
      expect(iface.contains(method), isFalse,
          reason: 'A-T03 新能力不得塞进 WishTaskRepository（会打断 29 个 Fake）');
    }
    expect(src.contains('abstract class WishTaskReadBridge'), isTrue);
    expect(src.contains('abstract class WishFocusSettlementWriter'), isTrue);

    final String service =
        _read('lib/domain/services/task_checkin_service.dart');
    final int ctor = service.indexOf('TaskCheckInService({');
    final String ctorBody =
        service.substring(ctor, service.indexOf('})  : _tasks', ctor));
    for (final String param in <String>[
      'WishTaskReadBridge? wishTasks',
      'WishFocusSettlementWriter? wishFocusWriter',
      'void Function(String wishId, WishEventKind kind, DateTime now)?',
      'onWishCheckInVerified,',
    ]) {
      expect(ctorBody.contains(param), isTrue, reason: '可选注入 $param 缺失');
    }
    expect(ctorBody.contains('required WishTaskReadBridge'), isFalse);
    expect(ctorBody.contains('required WishFocusSettlementWriter'), isFalse);
  });
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}
