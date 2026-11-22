/// R6-P0-01~05 端到端复验（许愿树 · 成长任务闭环）。
///
/// 跑在真实 in-memory drift 库 + 真实仓储 / 服务装配上，重点取证：
///  - 第 6 条达成路径（data 事务 `settleWishFocus`）的门控：未完成任务时
///    只累加进度、不写 fulfilled；全部任务完成后才成真；
///  - 孩子「我做到了」→ pending → 家长 `verifyCheckIn` → `registerCheckIn`
///    门控 → fulfilled 的完整闭环，0 阳光 / 0 账本；
///  - 多任务必须全部核销；撤销退档留痕；盖章与「我自己做到的」徽标口径；
///  - 家长待确认卡的买礼物提示 + 收藏箱派生隐藏。
library wish_growth_loop_qa_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
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
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';

String _read(String path) => File(path).readAsStringSync();

final DateTime kNow = DateTime(2026, 11, 22, 10);

Task _task({
  required String id,
  required bool focus,
  String? wishId,
  int min = 15,
}) =>
    Task(
      id: id,
      name: id == 'tm1' ? '了解飞机为什么能起飞' : id,
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: min,
      sunlightReward: 12,
      isCustom: true,
      wishId: wishId,
    );

FocusSession _session(String id, double minutes) {
  final DateTime at = kNow;
  return FocusSession(
    id: id,
    start: at.subtract(Duration(minutes: minutes.round())),
    end: at,
    plannedMin: minutes.round(),
    actualFocusMin: minutes,
    status: FocusStatus.completed,
    sunlightEarned: minutes,
    createdAt: at,
  );
}

class _Tracking implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];

  @override
  Future<void> track(TrackingEvent event) async => events.add(event);

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      events.where((TrackingEvent e) => e.type == type).toList();

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
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
}

Future<_Fixture> _fixture() async {
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
    onWishCheckInVerified: (Task task, CheckIn checkIn, DateTime now) =>
        orchestration.registerCheckIn(
      wishId: task.wishId ?? '',
      checkIn: checkIn,
      task: task,
      now: now,
    ),
  );
  return _Fixture(
    database,
    tasks,
    wishes,
    ledger,
    orchestration,
    checkIns,
    tracking,
  );
}

Future<Wish> _seedWish(
  _Fixture f, {
  required String id,
  required String text,
  WishGoalMode mode = WishGoalMode.taskCount,
  int target = 1,
}) async {
  final Wish wish = Wish(
    id: id,
    childId: kChildIdDefault,
    text: text,
    createdAt: DateTime(2026, 11, 20),
    treeSlot: 0,
    targetMode: mode,
    targetValue: target,
  );
  await f.wishes.save(wish);
  return wish;
}

void main() {
  group('R6-P0-01 第 6 条路径：data 事务门控（真实 drift）', () {
    test('专注刷满进度但另一任务未完成时不得成真；全部完成后才进池', () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(
        f,
        id: 'w_focus',
        text: '想看火箭上天',
        mode: WishGoalMode.focusMinutes,
        target: 15,
      );
      await f.tasks.saveTask(_task(id: 'tf1', focus: true, wishId: 'w_focus'));
      await f.tasks.saveTask(_task(id: 'tf2', focus: true, wishId: 'w_focus'));

      final Task first = (await f.tasks.wishTaskById('tf1'))!;
      await f.checkIns.settleWishFocusTask(
        task: first,
        session: _session('s1', 20),
        now: kNow,
      );
      Wish wish = (await f.wishes.byId('w_focus'))!;
      expect(wish.progressValue, 15, reason: '进度照常累加');
      expect(wish.status, WishStatus.pending, reason: 'tf2 未完成 ⇒ 门控拦住');
      expect(wish.fulfillSource, isNull);
      expect(wish.treeSlot, 0, reason: '仍挂树');
      expect(await f.orchestration.poolWishes(), isEmpty);

      final Task second = (await f.tasks.wishTaskById('tf2'))!;
      await f.checkIns.settleWishFocusTask(
        task: second,
        session: _session('s2', 20),
        now: kNow,
      );
      wish = (await f.wishes.byId('w_focus'))!;
      expect(wish.status, WishStatus.fulfilled);
      expect(wish.fulfillSource, kWishFulfillSourceProgress);
      expect(wish.treeSlot, isNull, reason: '成真释放挂载位');
      expect(await f.ledger.all(), isEmpty, reason: '愿望任务全程 0 阳光');
      expect(await f.orchestration.stampedAchievedCount(), 1);
    });
  });

  group('R6-P0-02/03 孩子提交 → 家长确认闭环', () {
    test('checkIn 落 pending（0 阳光）→ verifyCheckIn → fulfilled(source=progress)',
        () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(f, id: 'w_plane', text: '想要一个小飞机');
      await f.tasks.saveTask(
        _task(id: 'tm1', focus: false, wishId: 'w_plane'),
      );
      final Task task = (await f.tasks.wishTaskById('tm1'))!;

      // ① 孩子「我做到了」
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      expect(child.status, CheckInStatus.pending);
      expect(child.reward, 0.0);
      expect(child.granted, 0.0);
      expect(child.perfectDayBonus, isFalse);
      expect(child.allTasksDone, isFalse);
      expect((await f.wishes.byId('w_plane'))!.status, WishStatus.pending,
          reason: '提交不等于达成');

      final List<PendingCheckIn> pending = await f.checkIns.pendingCheckIns();
      expect(pending, hasLength(1));
      expect(pending.single.task?.wishId, 'w_plane');
      expect(pending.single.checkIn.status, CheckInStatus.pending);

      // ② 家长确认
      final TaskCheckInOutcome parent =
          await f.checkIns.verifyCheckIn(child.checkInId, kNow);
      expect(parent.status, CheckInStatus.verified);
      expect(parent.granted, 0.0, reason: '家长确认也不发阳光');
      expect(await f.ledger.all(), isEmpty, reason: '不写阳光账本');

      final Wish wish = (await f.wishes.byId('w_plane'))!;
      expect(wish.status, WishStatus.fulfilled);
      expect(wish.fulfillSource, kWishFulfillSourceProgress);
      expect(wish.treeSlot, isNull);
      expect(await f.orchestration.stampedAchievedCount(), 1);
      expect(WishPoolTile.isSelfFulfilled(wish), isFalse,
          reason: 'source=progress ⇒ 不显示「我自己做到的」徽标');
      expect(await f.checkIns.pendingCheckIns(), isEmpty);
    });

    test('多任务：只核销一条不进池，全部核销才成真', () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(
        f,
        id: 'w_multi',
        text: '想去科技馆',
        target: 2,
      );
      await f.tasks.saveTask(_task(id: 'tm1', focus: false, wishId: 'w_multi'));
      await f.tasks.saveTask(_task(id: 'tm2', focus: false, wishId: 'w_multi'));
      final Task t1 = (await f.tasks.wishTaskById('tm1'))!;
      final Task t2 = (await f.tasks.wishTaskById('tm2'))!;

      final TaskCheckInOutcome c1 = await f.checkIns.checkIn(task: t1, now: kNow);
      await f.checkIns.verifyCheckIn(c1.checkInId, kNow);
      expect((await f.wishes.byId('w_multi'))!.status, WishStatus.pending,
          reason: 'tm2 仍 verified 缺失 ⇒ 门控拦住');

      final TaskCheckInOutcome c2 = await f.checkIns.checkIn(task: t2, now: kNow);
      await f.checkIns.verifyCheckIn(c2.checkInId, kNow);
      final Wish wish = (await f.wishes.byId('w_multi'))!;
      expect(wish.status, WishStatus.fulfilled);
      expect(wish.progressValue, 2);
    });
  });

  group('R7-P0-01 手动任务型 targetValue==0：翻案 + 显式进池（真实 drift）', () {
    test('家长确认后不自动进池（闸门拦），显式 putIntoPool 才进池 + 盖章 + 清树位 + 埋点',
        () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(
        f,
        id: 'w_manual',
        text: '想要一个小飞机',
        mode: WishGoalMode.taskCount,
        target: 0, // 根因场景：targetValue==0
      );
      await f.tasks.saveTask(
        _task(id: 'tm1', focus: false, wishId: 'w_manual'),
      );
      final Task task = (await f.tasks.wishTaskById('tm1'))!;

      // 孩子「我做到了」→ pending
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      // 家长确认 → verified。手动任务型被 registerCheckIn:640 闸门拦，不自动进池。
      final TaskCheckInOutcome parent =
          await f.checkIns.verifyCheckIn(child.checkInId, kNow);
      expect(parent.status, CheckInStatus.verified);

      Wish wish = (await f.wishes.byId('w_manual'))!;
      expect(wish.status, WishStatus.pending,
          reason: '翻案：targetValue==0 家长确认后不自动进池');
      expect(wish.treeSlot, 0, reason: '仍挂树，等待显式进池');

      // 显式「放进愿望池」→ 领域薄入口经 _tryComplete → _complete 收口。
      final Wish pooled = await f.orchestration.putIntoPool(
        id: 'w_manual',
        now: kNow,
      );
      expect(pooled.status, WishStatus.fulfilled);
      expect(pooled.fulfillSource, kWishFulfillSourceProgress,
          reason: 'source=progress，不误挂「我自己做到的」徽标');
      expect(pooled.treeSlot, isNull, reason: '清树位');
      expect(await f.orchestration.stampedAchievedCount(), 1, reason: '盖章 +1');
      expect(WishPoolTile.isSelfFulfilled(pooled), isFalse);
      expect(
        f.tracking.events.any(
          (TrackingEvent e) =>
              e.payload['kind'] == 'fulfilled' && e.payload['wish_id'] == 'w_manual',
        ),
        isTrue,
        reason: '发达成埋点',
      );
    });

    test('撤销退档后 task 仍 verified：putIntoPool 可再次进池（Q4 预期非漏洞）',
        () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(f, id: 'w_undo2', text: '想去海边', target: 0);
      await f.tasks.saveTask(
        _task(id: 'tm1', focus: false, wishId: 'w_undo2'),
      );
      final Task task = (await f.tasks.wishTaskById('tm1'))!;
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      await f.checkIns.verifyCheckIn(child.checkInId, kNow);
      await f.orchestration.putIntoPool(id: 'w_undo2', now: kNow);
      expect((await f.wishes.byId('w_undo2'))!.status, WishStatus.fulfilled);

      // 撤销 → pending，task 打卡仍 verified
      await f.orchestration.undoFulfill(id: 'w_undo2', now: kNow);
      final List<CheckIn> rows = await f.tasks.checkInsOfDay('2026-11-22');
      expect(rows.single.status, CheckInStatus.verified,
          reason: '退档不清打卡');

      // 再显式进池：门控仍通过
      final Wish again = await f.orchestration.putIntoPool(
        id: 'w_undo2',
        now: kNow,
      );
      expect(again.status, WishStatus.fulfilled,
          reason: 'Q4：task 仍 verified ⇒ 可再进池，预期非漏洞');
    });
  });

  group('R6-P0-05 盖章 / 撤销退档 / 徽标口径', () {
    test('撤销：fulfilled→pending + 挂回树 + wishUndo(parent) + 盖章回退', () async {
      final _Fixture f = await _fixture();
      addTearDown(f.database.close);
      await _seedWish(f, id: 'w_undo', text: '想要一个小飞机');
      await f.tasks.saveTask(
        _task(id: 'tm1', focus: false, wishId: 'w_undo'),
      );
      final Task task = (await f.tasks.wishTaskById('tm1'))!;
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kNow);
      await f.checkIns.verifyCheckIn(child.checkInId, kNow);
      expect(await f.orchestration.stampedAchievedCount(), 1);

      final Wish reverted =
          await f.orchestration.undoFulfill(id: 'w_undo', now: kNow);
      expect(reverted.status, WishStatus.pending);
      expect(reverted.treeSlot, 0, reason: '挂回树');
      expect(reverted.releasedAt, isNull);
      expect(reverted.fulfilledAt, kNow, reason: '审计留痕不清空');
      expect(reverted.fulfillSource, kWishFulfillSourceProgress,
          reason: '撤销不清空来源留痕');
      expect(await f.orchestration.stampedAchievedCount(), 0,
          reason: '盖章回退');
      expect(
        f.tracking.events.any(
          (TrackingEvent e) =>
              e.name == TrackingEventNames.wishUndo &&
              e.payload['actor'] == 'parent',
        ),
        isTrue,
        reason: '撤销必须写 wishUndo(actor=parent) 留痕',
      );
      // 任务打卡保持 verified 作为历史留痕；再次确认闭环属预期。
      final List<CheckIn> rows = await f.tasks.checkInsOfDay('2026-11-22');
      expect(rows.single.status, CheckInStatus.verified);
    });
  });

  group('R6-P1 文案与冻结契约', () {
    test('仅新增 2 条 key，且 zh/en 齐备、复用既有 key', () {
      final String zh = _read('lib/l10n/app_zh.arb');
      final String en = _read('lib/l10n/app_en.arb');
      for (final String key in <String>[
        'wishTaskSubmitConfirm',
        'parentWishTaskBuyGift',
      ]) {
        expect(zh.contains('"$key"'), isTrue, reason: 'zh 缺 $key');
        expect(en.contains('"$key"'), isTrue, reason: 'en 缺 $key');
      }
      for (final String reused in <String>[
        'wishTaskDidIt',
        'wishTaskPending',
        'wishDetailRealized',
      ]) {
        expect(zh.contains('"$reused"'), isTrue);
        expect(en.contains('"$reused"'), isTrue);
      }
      expect(en.contains('Confirming makes the wish come true'), isTrue);
      expect(zh.contains('请给小朋友买'), isTrue);
    });

    test('第 6 条路径门控确实写在 data 事务方法内', () {
      final String src =
          _read('lib/data/local/repositories/task_local_repository.dart');
      expect(src.contains('Future<bool> settleWishFocus({'), isTrue);
      expect(src.contains('_wishTasksAllDoneInTx('), isTrue);
      expect(src.contains('wishTasksAllDone(tasks: tasks'), isTrue);
    });
  });

  // ── 家长端 widget：买礼物提示 + 收藏箱派生隐藏 ───────────────────────────
  group('R6-P0-03① / R6-P0-04 家长待确认卡', () {
    Future<ProviderContainer> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      final AccountService account = AccountService(
        children: ChildProfileLocalRepository(database),
        settings: SettingsLocalRepository(database),
        prefs: sp,
      );
      await account.initialize();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      );
      addTearDown(() {
        container.dispose();
        database.close();
      });
      return container;
    }

    Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
      for (int i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('愿望任务卡显示「请给小朋友买：{愿望文本}」；进箱后隐藏',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final ProviderContainer container = await boot();

      final TaskLocalRepository tasks =
          container.read(taskRepositoryProvider) as TaskLocalRepository;
      await tasks.saveTask(
        _task(id: 'tm1', focus: false, wishId: 'w_plane'),
      );
      await container.read(wishRepositoryProvider).save(Wish(
            id: 'w_plane',
            childId: kChildIdDefault,
            text: '想要一个小飞机',
            createdAt: DateTime(2026, 11, 20),
            treeSlot: 0,
            targetValue: 1,
            targetMode: WishGoalMode.taskCount,
          ));
      final Task task = (await tasks.wishTaskById('tm1'))!;
      await container.read(taskCheckInServiceProvider).checkIn(
            task: task,
            now: kNow,
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ParentTodayPage())),
        ),
      );
      await pumpFrames(tester);

      expect(
        find.text('确认后愿望将实现 · 请给小朋友买：想要一个小飞机'),
        findsOneWidget,
        reason: '家长待确认愿望卡必须展示买礼物提示',
      );

      // 愿望进收藏箱 ⇒ 派生隐藏（tasks 表零写入）。
      await container.read(wishOrchestrationServiceProvider).collectToBox(
            id: 'w_plane',
            now: kNow,
          );
      await pumpFrames(tester);
      expect(
        find.text('确认后愿望将实现 · 请给小朋友买：想要一个小飞机'),
        findsNothing,
        reason: '父愿望在箱 ⇒ 关联任务从待确认段消失',
      );

      // 拿出收藏箱 ⇒ 自动重现。
      await container.read(wishOrchestrationServiceProvider).restoreFromBox(
            id: 'w_plane',
            now: kNow,
          );
      await pumpFrames(tester);
      expect(
        find.text('确认后愿望将实现 · 请给小朋友买：想要一个小飞机'),
        findsOneWidget,
        reason: '拿出后自动重现，pending 打卡原样保留',
      );
    });
  });
}
