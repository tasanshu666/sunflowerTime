/// A-T02 orchestration tests: state machine, gates, C69, child isolation.
library wish_orchestration_service_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';

class FakeWishRepository implements WishRepository {
  final Map<String, Wish> rows = <String, Wish>{};

  @override
  Future<List<Wish>> mounted() async => rows.values
      .where((Wish w) =>
          w.status == WishStatus.pending ||
          w.status == WishStatus.tagged ||
          w.status == WishStatus.committed)
      .where((Wish w) => w.releasedAt == null)
      .toList()
    ..sort((Wish a, Wish b) => (a.treeSlot ?? 0).compareTo(b.treeSlot ?? 0));

  @override
  Future<List<Wish>> pool() async => rows.values
      .where((Wish w) =>
          w.status == WishStatus.fulfilled || w.status == WishStatus.replaced)
      .toList();

  @override
  Future<List<Wish>> boxed() async =>
      rows.values.where((Wish w) => w.releasedAt != null).toList();

  @override
  Future<List<Wish>> abandoned() async =>
      rows.values.where((Wish w) => w.status == WishStatus.abandoned).toList();

  @override
  Future<List<Wish>> byStatuses(Set<WishStatus> statuses) async =>
      rows.values.where((Wish w) => statuses.contains(w.status)).toList();

  @override
  Future<int> countByStatuses(Set<WishStatus> statuses) async =>
      (await byStatuses(statuses)).length;

  @override
  Future<int> countStampedAchieved() async =>
      rows.values.where((Wish w) => w.status == WishStatus.fulfilled).length;

  @override
  Future<Set<int>> occupiedSlots() async => rows.values
      .where((Wish w) => w.releasedAt == null && w.treeSlot != null)
      .map((Wish w) => w.treeSlot!)
      .toSet();

  @override
  Future<Wish?> byId(String id) async => rows[id];

  @override
  Future<void> save(Wish wish) async => rows[wish.id] = wish;

  @override
  Future<void> deleteAll() async => rows.clear();
}

class FakeWishTaskRepository implements WishTaskRepository {
  final Map<String, Task> tasks = <String, Task>{};
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async => tasks.values
      .where((Task t) => t.wishId == wishId)
      .toList();

  @override
  Future<List<CheckIn>> checkInsOfTaskIds({
    required List<String> taskIds,
  }) async =>
      checkIns.where((CheckIn c) => taskIds.contains(c.taskId)).toList();

  @override
  Future<void> assignWish({
    required String taskId,
    required String wishId,
  }) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: wishId);
  }

  @override
  Future<void> unassignWish({required String taskId}) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: Task.kClear);
  }
}

class FakeTrackingRepository implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];

  @override
  Future<void> track(TrackingEvent event) async => events.add(event);

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      events.where((TrackingEvent e) => e.type == type).toList();

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

void main() {
  final DateTime now = DateTime(2026, 11, 17, 9);
  late FakeWishRepository wishes;
  late FakeWishTaskRepository wishTasks;
  late FakeTrackingRepository tracking;
  late WishOrchestrationService service;
  int changes = 0;

  Wish seedWish({
    String id = 'w1',
    String childId = kChildIdDefault,
    WishStatus status = WishStatus.pending,
    int targetValue = 30,
    int progressValue = 0,
    int? treeSlot = 0,
    DateTime? releasedAt,
    String? fulfillSource,
    DateTime? fulfilledAt,
  }) =>
      Wish(
        id: id,
        childId: childId,
        text: 'a wish',
        status: status,
        createdAt: DateTime(2026, 11, 10),
        treeSlot: treeSlot,
        targetValue: targetValue,
        progressValue: progressValue,
        releasedAt: releasedAt,
        fulfillSource: fulfillSource,
        fulfilledAt: fulfilledAt,
      );

  Task seedTask({String id = 't1', String? wishId}) => Task(
        id: id,
        name: 'task',
        subject: TaskSubject.general,
        requiresFocus: true,
        minFocusMin: 15,
        sunlightReward: 0,
        isCustom: false,
        wishId: wishId,
      );

  CheckIn seedCheckIn({
    String id = 'c1',
    String taskId = 't1',
    CheckInStatus status = CheckInStatus.verified,
    double? actualFocusMin = 15.0,
    String? sessionId,
    DateTime? completedAt,
  }) =>
      CheckIn(
        id: id,
        taskId: taskId,
        date: completedAt ?? now,
        completedAt: completedAt ?? now,
        sessionId: sessionId,
        isPerfectDay: false,
        status: status,
        actualFocusMin: actualFocusMin,
      );

  setUp(() {
    wishes = FakeWishRepository();
    wishTasks = FakeWishTaskRepository();
    tracking = FakeTrackingRepository();
    changes = 0;
    service = WishOrchestrationService(
      wishes: wishes,
      wishTasks: wishTasks,
      account: AccountService(),
      tracking: tracking,
      onChanged: () => changes++,
      idFactory: () => 'id-${wishes.rows.length}-${tracking.events.length}',
      isPremium: () => false,
      focusLevelOf: () => 0,
    );
  });

  group('愿望状态机', () {
    test('pending -> tagged 合法', () async {
      wishes.rows['w1'] = seedWish();
      final Wish w = await service.tagWithReply(
          id: 'w1', tag: WishTag.needMoreTime, reply: 'later', now: now);
      expect(w.status, WishStatus.tagged);
      expect(w.tagKey, 'needMoreTime');
      expect(w.parentReply, 'later');
    });

    test('tagged -> pending 合法且回信保留', () async {
      wishes.rows['w1'] = seedWish(status: WishStatus.tagged);
      final Wish w = await service.untag(id: 'w1', now: now);
      expect(w.status, WishStatus.pending);
      expect(w.tagKey, isNull);
      expect(w.parentReply, isNull);
    });

    test('pending -> fulfilled 合法（家长直接实现）', () async {
      wishes.rows['w1'] = seedWish();
      final Wish w = await service.fulfill(
          id: 'w1', reply: 'well done', now: now);
      expect(w.status, WishStatus.fulfilled);
      expect(w.fulfillSource, kWishFulfillSourceParentAction);
      expect(w.treeSlot, isNull);
    });

    test('tagged -> fulfilled 合法（孩子自助）', () async {
      wishes.rows['w1'] = seedWish(status: WishStatus.tagged);
      final Wish w = await service.selfFulfill(id: 'w1', now: now);
      expect(w.status, WishStatus.fulfilled);
      expect(w.fulfillSource, kWishFulfillSourceChild);
    });

    test('tagged -> abandoned 合法', () async {
      wishes.rows['w1'] = seedWish(status: WishStatus.tagged);
      final Wish w = await service.abandon(id: 'w1', now: now);
      expect(w.status, WishStatus.abandoned);
      expect(w.abandonedAt, now);
    });

    test('fulfilled -> pending 家长撤销合法（唯一反向边）', () async {
      wishes.rows['w1'] = seedWish(
          status: WishStatus.fulfilled,
          treeSlot: null,
          fulfillSource: kWishFulfillSourceChild,
          fulfilledAt: now);
      final Wish w = await service.undoFulfill(id: 'w1', now: now);
      expect(w.status, WishStatus.pending);
      expect(w.fulfilledAt, now);
      expect(w.fulfillSource, kWishFulfillSourceChild);
      expect(tracking.events.last.name, TrackingEventNames.wishUndo);
    });

    test('非法：pending -> abandoned 抛 StateError', () async {
      wishes.rows['w1'] = seedWish();
      await expectLater(service.abandon(id: 'w1', now: now),
          throwsA(isA<StateError>()));
    });

    test('非法：fulfilled -> tagged 抛 StateError', () async {
      wishes.rows['w1'] =
          seedWish(status: WishStatus.fulfilled, treeSlot: null);
      await expectLater(
          service.tagWithReply(
              id: 'w1', tag: WishTag.overBudget, now: now),
          throwsA(isA<StateError>()));
    });

    test('非法：replaced/abandoned 任何迁移抛 StateError', () {
      for (final WishStatus from in <WishStatus>[
        WishStatus.replaced,
        WishStatus.abandoned,
      ]) {
        for (final WishStatus to in WishStatus.values) {
          expect(
              () => WishOrchestrationService.assertTransition(from, to),
              throwsA(isA<StateError>()),
              reason: '$from -> $to');
        }
      }
    });
  });

  group('任务状态机与日重置', () {
    setUp(() {
      wishes.rows['w1'] = seedWish();
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
    });

    test('pending 派生', () async {
      expect(
          await service.effectiveStatusOf(
              wishId: 'w1',
              task: wishTasks.tasks['t1']!,
              checkIns: <CheckIn>[],
              now: now),
          WishTaskStage.pending);
    });

    test('awaitingVerify 派生（pending 优先）', () async {
      expect(
          await service.effectiveStatusOf(
              wishId: 'w1',
              task: wishTasks.tasks['t1']!,
              checkIns: <CheckIn>[seedCheckIn(status: CheckInStatus.pending)],
              now: now),
          WishTaskStage.awaitingVerify);
    });

    test('done 派生（once 窗口）', () async {
      expect(
          await service.effectiveStatusOf(
              wishId: 'w1',
              task: wishTasks.tasks['t1']!,
              checkIns: <CheckIn>[seedCheckIn()],
              now: now),
          WishTaskStage.done);
    });

    test('愿望终态 => closed 派生且 tasks 行保留', () async {
      wishes.rows['w1'] =
          seedWish(status: WishStatus.fulfilled, treeSlot: null);
      expect(
          await service.effectiveStatusOf(
              wishId: 'w1',
              task: wishTasks.tasks['t1']!,
              checkIns: <CheckIn>[seedCheckIn()],
              now: now),
          WishTaskStage.closed);
      expect(wishTasks.tasks['t1'], isNotNull);
    });

    test('daily 次日重开（注入 now）', () async {
      final Task daily = seedTask().copyWith(repeatRule: 'daily');
      expect(
          await service.effectiveStatusOf(
              wishId: 'w1',
              task: daily,
              checkIns: <CheckIn>[seedCheckIn()],
              now: DateTime(2026, 11, 18, 8)),
          WishTaskStage.pending);
    });
  });

  group('闸门 / C69 / 隔离', () {
    test('C69：额度满只拦新增，存量逐条保留', () async {
      wishes.rows['w1'] = seedWish();
      await expectLater(
          service.createWish(
              text: 'second wish',
              category: WishCategory.toy,
              now: now,
              maxTextLength: kWishTextMaxLengthZh),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1'], isNotNull);
      expect((await service.mountedWishes()).length, 1);
    });

    test('低等级额度 = 1，等级提升后放行', () async {
      wishes.rows['w1'] = seedWish();
      final WishOrchestrationService lv40 = WishOrchestrationService(
        wishes: wishes,
        wishTasks: wishTasks,
        account: AccountService(),
        tracking: tracking,
        idFactory: () => 'lv40',
        isPremium: () => false,
        focusLevelOf: () => 40,
      );
      expect(await lv40.currentWishSlotQuota(), 10);
      final Wish created = await lv40.createWish(
          text: 'another wish',
          category: WishCategory.gift,
          now: now,
          maxTextLength: kWishTextMaxLengthZh);
      expect(created.treeSlot, 1);
      expect(wishes.rows['w1']!.status, WishStatus.pending);
    });

    test('跨孩子守卫抛 ASCII StateError', () async {
      wishes.rows['other'] = seedWish(childId: 'child-other');
      try {
        await service.selfFulfill(id: 'other', now: now);
        fail('expected StateError');
      } on StateError catch (e) {
        expect(e.message.codeUnits.every((int c) => c < 128), isTrue);
        expect(e.message, contains('cross-child wish'));
      }
    });

    test('自助达成：无目标值也放行（落库 / 进池 / 盖章含 child）', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      final Wish w = await service.selfFulfill(id: 'w1', now: now);
      expect(w.status, WishStatus.fulfilled);
      expect(w.fulfillSource, kWishFulfillSourceChild);
      expect(w.treeSlot, isNull);
      expect((await service.poolWishes()).map((Wish x) => x.id), contains('w1'));
      expect(await service.stampedAchievedCount(), 1,
          reason: 'child 自助达成也盖章');
      expect(tracking.events.single.payload['kind'], 'selfFulfilled');
      expect(changes, 1);
    });

    test('自助达成：收藏箱内被拒', () async {
      wishes.rows['w1'] = seedWish(releasedAt: now);
      await expectLater(service.selfFulfill(id: 'w1', now: now),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1']!.releasedAt, now);
    });

    test('自助达成 10 次 ⇒ 盖章计数 +10、印章数按 floor/3 退档', () async {
      for (int i = 0; i < 10; i++) {
        wishes.rows['w$i'] = seedWish(
            id: 'w$i',
            status: WishStatus.fulfilled,
            treeSlot: null,
            fulfilledAt: now,
            fulfillSource: kWishFulfillSourceChild);
      }
      final int stamped = await service.stampedAchievedCount();
      expect(stamped, 10);
      expect(WishOrchestrationService.poolMilestoneCount(stamped), 3);
    });

    test('自助达成不改 progressValue、不产生 check_in', () async {
      wishes.rows['w1'] = seedWish(progressValue: 7);
      final Wish w = await service.selfFulfill(id: 'w1', now: now);
      expect(w.progressValue, 7);
      expect(wishTasks.checkIns, isEmpty);
    });

    test('家长撤销：树上满 ⇒ 落收藏箱（不删行）', () async {
      wishes.rows['w1'] = seedWish(
          status: WishStatus.fulfilled,
          treeSlot: null,
          fulfilledAt: now,
          fulfillSource: kWishFulfillSourceChild);
      wishes.rows['w2'] = seedWish(id: 'w2');
      final Wish w = await service.undoFulfill(id: 'w1', now: now);
      expect(w.status, WishStatus.pending);
      expect(w.releasedAt, now);
      expect(w.treeSlot, isNull);
      expect(wishes.rows['w1'], isNotNull);
    });
  });

  group('目标 / 任务 / 进度写入', () {
    setUp(() {
      wishes.rows['w1'] = seedWish();
    });

    test('setGoal 是 target_mode/target_value 唯一写入口', () async {
      final Wish w = await service.setGoal(
          wishId: 'w1',
          mode: WishGoalMode.taskCount,
          targetValue: 3,
          now: now);
      expect(w.targetMode, WishGoalMode.taskCount);
      expect(w.targetValue, 3);
      expect(w.progressValue, 0);
    });

    test('setGoal 下调钳制到已完成量并立即成真', () async {
      wishes.rows['w1'] = seedWish(progressValue: 18);
      final Wish w = await service.setGoal(
          wishId: 'w1',
          mode: WishGoalMode.focusMinutes,
          targetValue: 10,
          now: now);
      expect(w.targetValue, 18);
      expect(w.status, WishStatus.fulfilled);
      expect(w.fulfillSource, kWishFulfillSourceProgress);
    });

    test('setGoal 超护栏拒绝且数据不变', () async {
      wishes.rows['w1'] = seedWish(targetValue: 3, progressValue: 2);
      await expectLater(
          service.setGoal(
              wishId: 'w1',
              mode: WishGoalMode.taskCount,
              targetValue: 5,
              now: now),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1']!.targetValue, 3);
    });

    // 🔴 P0 回归：首次设定（targetValue == 0，未设目标的唯一判据）必须放行。
    // 旧实现把上调护栏无条件套在 0 → N 上，cap = min(0*1.5, 0*3) = 0，
    // 导致家长第一次给孩子设目标 100% 抛 StateError，"设定目标 + 布置任务"
    // 整条链路不可用。期望值写死，不引用常量或护栏函数。
    test('setGoal 首次设定目标（原值 0 → 15 分钟）必须成功', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      final Wish w = await service.setGoal(
          wishId: 'w1',
          mode: WishGoalMode.focusMinutes,
          targetValue: 15,
          now: now);
      expect(w.targetValue, 15);
      expect(w.targetMode, WishGoalMode.focusMinutes);
      expect(w.progressValue, 0);
      expect(w.status, WishStatus.pending);
      expect(
        tracking.events
            .where((TrackingEvent e) => e.payload['kind'] == 'goalSet')
            .length,
        1,
      );
    });

    test('setGoal 首次设定目标（口径 1：原值 0 → 5 条）必须成功', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      final Wish w = await service.setGoal(
          wishId: 'w1',
          mode: WishGoalMode.taskCount,
          targetValue: 5,
          now: now);
      expect(w.targetValue, 5);
      expect(w.targetMode, WishGoalMode.taskCount);
      expect(w.progressValue, 0);
    });

    test('setGoal 已有目标的上调护栏不被削弱（cap = min(原×1.5, 已完成×3)）',
        () async {
      // 原目标 40、已完成 20 ⇒ cap = min(60, 60) = 60。
      wishes.rows['w1'] = seedWish(targetValue: 40, progressValue: 20);
      await expectLater(
          service.setGoal(
              wishId: 'w1',
              mode: WishGoalMode.focusMinutes,
              targetValue: 61,
              now: now),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1']!.targetValue, 40);

      final Wish w = await service.setGoal(
          wishId: 'w1',
          mode: WishGoalMode.focusMinutes,
          targetValue: 55,
          now: now);
      expect(w.targetValue, 55);
      expect(w.progressValue, 20);
    });

    test('setGoal 原目标 60、已完成 20 ⇒ 上调到 90 被拒（> 已完成×3）', () async {
      wishes.rows['w1'] = seedWish(targetValue: 60, progressValue: 20);
      await expectLater(
          service.setGoal(
              wishId: 'w1',
              mode: WishGoalMode.focusMinutes,
              targetValue: 90,
              now: now),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1']!.targetValue, 60);
    });

    test('assignTasks 只写 tasks.wish_id，不碰目标/进度', () async {
      wishTasks.tasks['t1'] = seedTask();
      await service.assignTasks(
          wishId: 'w1', taskIds: <String>['t1'], now: now);
      expect(wishTasks.tasks['t1']!.wishId, 'w1');
      expect(wishes.rows['w1']!.targetValue, 30);
      expect(wishes.rows['w1']!.progressValue, 0);
    });

    test('registerCheckIn 同一 session 二次被拒', () async {
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
      wishTasks.checkIns.add(seedCheckIn(id: 'c1', sessionId: 's1'));
      await expectLater(
          service.registerCheckIn(
              wishId: 'w1',
              checkIn: seedCheckIn(id: 'c2', sessionId: 's1'),
              task: wishTasks.tasks['t1']!,
              now: now),
          throwsA(isA<StateError>()));
      expect(wishes.rows['w1']!.progressValue, 0);
    });

    test('registerCheckIn 进度满自动成真且来源 progress', () async {
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
      final Task longFocus = seedTask().copyWith(minFocusMin: 30);
      final Wish w = await service.registerCheckIn(
          wishId: 'w1',
          checkIn: seedCheckIn(id: 'c9', actualFocusMin: 30),
          task: longFocus,
          now: now);
      expect(w.progressValue, 30);
      expect(w.status, WishStatus.fulfilled);
      expect(w.fulfillSource, kWishFulfillSourceProgress);
    });

    test('未设目标时 registerCheckIn 不推进', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
      final Wish w = await service.registerCheckIn(
          wishId: 'w1',
          checkIn: seedCheckIn(),
          task: wishTasks.tasks['t1']!,
          now: now);
      expect(w.progressValue, 0);
    });

    test('并发 createWish 串行分配不同槽位（R17）', () async {
      final WishOrchestrationService wide = WishOrchestrationService(
        wishes: wishes,
        wishTasks: wishTasks,
        account: AccountService(),
        tracking: tracking,
        onChanged: () => changes++,
        focusLevelOf: () => 40,
      );
      final List<Future<Wish>> futures = <Future<Wish>>[
        for (int i = 0; i < 3; i++)
          wide.createWish(
              text: 'wish number $i',
              category: WishCategory.other,
              now: now,
              maxTextLength: kWishTextMaxLengthZh),
      ];
      final List<Wish> created = await Future.wait(futures);
      expect(created.map((Wish w) => w.treeSlot).toSet().length, 3);
      expect(changes, 3);
    });
  });

  group('读侧派生量', () {
    test('parentDeskList 提醒置顶 + 等待天数降序', () async {
      wishes.rows['a'] = seedWish(
          id: 'a',
          treeSlot: 0,
          fulfilledAt: null);
      wishes.rows['b'] = Wish(
        id: 'b',
        childId: kChildIdDefault,
        text: 'older',
        createdAt: DateTime(2026, 11, 1),
        treeSlot: 1,
        remindedAt: now,
      );
      final List<Wish> list = await service.parentDeskList(now);
      expect(list.first.id, 'b');
    });

    test('软门槛 = 至少 1 株植物', () {
      expect(WishOrchestrationService.softGateSatisfied(0), isFalse);
      expect(WishOrchestrationService.softGateSatisfied(1), isTrue);
    });
  });
}
