/// R6-P0-01 门控基座回归：领域 5 条 →fulfilled 路径全部经 `_tryComplete`。
///
/// 用纯 Dart fake 把「有未 verified 成长任务」的愿望推到 ripe，逐条证明
/// status 不改、不进池、不发伪造的达成埋点；再用「全部 verified」与
/// 「无任务愿望」两组反例证明门控没有误伤。第 6 条（data 事务）路径
/// 由 `test/qa/wish_growth_loop_qa_test.dart` 在真实 drift 库上覆盖。
library wish_gate_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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

String _read(String path) => File(path).readAsStringSync();

class _Wishes implements WishRepository {
  final Map<String, Wish> rows = <String, Wish>{};

  @override
  Future<List<Wish>> mounted() async => rows.values
      .where((Wish w) =>
          w.releasedAt == null &&
          (w.status == WishStatus.pending ||
              w.status == WishStatus.tagged ||
              w.status == WishStatus.committed))
      .toList();

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
  Future<int> countStampedAchieved() async => rows.values
      .where((Wish w) => w.status == WishStatus.fulfilled)
      .length;

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

class _WishTasks implements WishTaskRepository {
  final Map<String, Task> tasks = <String, Task>{};
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async =>
      tasks.values.where((Task t) => t.wishId == wishId).toList();

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
    final Task? task = tasks[taskId];
    if (task != null) tasks[taskId] = task.copyWith(wishId: wishId);
  }

  @override
  Future<void> unassignWish({required String taskId}) async {
    final Task? task = tasks[taskId];
    if (task != null) tasks[taskId] = task.copyWith(wishId: Task.kClear);
  }
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

void main() {
  final DateTime now = DateTime(2026, 11, 22, 9);
  late _Wishes wishes;
  late _WishTasks wishTasks;
  late _Tracking tracking;
  late WishOrchestrationService service;

  Wish seedWish({
    String id = 'w1',
    int targetValue = 10,
    int progressValue = 0,
  }) =>
      Wish(
        id: id,
        childId: kChildIdDefault,
        text: '想要一个小飞机',
        createdAt: DateTime(2026, 11, 20),
        treeSlot: 0,
        targetValue: targetValue,
        progressValue: progressValue,
      );

  Task seedTask({String id = 't1', String? wishId, String? repeatRule}) => Task(
        id: id,
        name: '了解飞机为什么能起飞',
        subject: TaskSubject.general,
        requiresFocus: false,
        minFocusMin: 15,
        sunlightReward: 0,
        isCustom: true,
        repeatRule: repeatRule,
        wishId: wishId,
      );

  CheckIn seedCheckIn({
    String id = 'c1',
    String taskId = 't1',
    CheckInStatus status = CheckInStatus.verified,
    double? actualFocusMin,
    DateTime? completedAt,
  }) =>
      CheckIn(
        id: id,
        taskId: taskId,
        date: completedAt ?? now,
        completedAt: completedAt ?? now,
        isPerfectDay: false,
        status: status,
        actualFocusMin: actualFocusMin,
      );

  setUp(() {
    wishes = _Wishes();
    wishTasks = _WishTasks();
    tracking = _Tracking();
    service = WishOrchestrationService(
      wishes: wishes,
      wishTasks: wishTasks,
      account: AccountService(),
      tracking: tracking,
    );
  });

  group('R6-P0-01① 未完成任务 ⇒ 各 →fulfilled 入口全堵', () {
    test('selfFulfill：留树、source 不写、不发达成埋点', () async {
      wishes.rows['w1'] = seedWish();
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      final Wish result =
          await service.selfFulfill(id: 'w1', now: now);

      expect(result.status, WishStatus.pending);
      expect(result.fulfillSource, isNull);
      expect(result.fulfilledAt, isNull);
      expect(result.treeSlot, 0, reason: '仍挂树');
      expect((await service.poolWishes()), isEmpty, reason: '不进达成池');
      expect(tracking.events, isEmpty, reason: '门控拦截不得发 selfFulfilled');
      expect(await service.stampedAchievedCount(), 0);
    });

    test('fulfill：家长直接实现同样被门控，且不发 fulfilled 埋点', () async {
      wishes.rows['w1'] = seedWish();
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      final Wish result = await service.fulfill(id: 'w1', now: now);

      expect(result.status, WishStatus.pending);
      expect(result.fulfillSource, isNull);
      expect(tracking.events, isEmpty, reason: '门控拦截不得发 fulfilled');
    });

    test('setGoal：下调致 ripe 被拦，但目标值照常保存', () async {
      wishes.rows['w1'] = seedWish(targetValue: 30, progressValue: 30);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      final Wish result = await service.setGoal(
        wishId: 'w1',
        mode: WishGoalMode.focusMinutes,
        targetValue: 10,
        now: now,
      );

      expect(result.targetValue, 30, reason: '下调被钳制到已完成量');
      expect(result.status, WishStatus.pending, reason: '门控拦住，不写 fulfilled');
      expect(result.fulfillSource, isNull);
      expect(
        tracking.events
            .where((TrackingEvent e) => e.payload['kind'] == 'goalSet')
            .length,
        1,
        reason: 'goalSet 事件照常发（非达成事件）',
      );
    });

    test('advanceProgress：ripe 被拦，但进度照常累加', () async {
      wishes.rows['w1'] = seedWish(targetValue: 10);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      final Wish result = await service.advanceProgress(
        wishId: 'w1',
        delta: 10,
        now: now,
      );

      expect(result.progressValue, 10, reason: '进度推进不受门控影响');
      expect(result.status, WishStatus.pending);
      expect(result.fulfillSource, isNull);
    });

    test('registerCheckIn：ripe 被拦，进度照常累加', () async {
      wishes.rows['w1'] = seedWish(targetValue: 10);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      // 注意：打卡流水故意只作为入参传入，没有入库 —— 门控读的是仓储中的
      // 现存打卡，这条尚未核销 ⇒ 任务未完成。真实回调链里 verifyCheckIn
      // 会先 CAS 落库再回调，故不会出现这种「已核销但查不到」的状态。
      final Task focusTask = seedTask(wishId: 'w1').copyWith(
        requiresFocus: true,
      );
      final Wish result = await service.registerCheckIn(
        wishId: 'w1',
        checkIn: seedCheckIn(actualFocusMin: 10),
        task: focusTask,
        now: now,
      );

      expect(result.progressValue, 10);
      expect(result.status, WishStatus.pending);
      expect(result.fulfillSource, isNull);
    });
  });

  group('R6-P0-01③ 放行与逐字节不变', () {
    test('全部现存任务 verified ⇒ advanceProgress 成真、来源 progress', () async {
      wishes.rows['w1'] = seedWish(targetValue: 10);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
      wishTasks.checkIns.add(seedCheckIn());

      final Wish result = await service.advanceProgress(
        wishId: 'w1',
        delta: 10,
        now: now,
      );

      expect(result.status, WishStatus.fulfilled);
      expect(result.fulfillSource, kWishFulfillSourceProgress);
      expect(result.treeSlot, isNull);
      expect(result.fulfilledAt, now);
      expect(await service.stampedAchievedCount(), 1, reason: '盖章含本次达成');
    });

    test('被删除的任务不计入：tasks 表里没有 ⇒ 不拦', () async {
      wishes.rows['w1'] = seedWish(targetValue: 10);
      // 没有任何任务行（物理删除后 tasksOfWish 不返回）⇒ 门控放行。
      final Wish result = await service.advanceProgress(
        wishId: 'w1',
        delta: 10,
        now: now,
      );
      expect(result.status, WishStatus.fulfilled);
    });

    test('无任务愿望仍自助达成，source=Child、埋点原样', () async {
      wishes.rows['w1'] = seedWish();

      final Wish result =
          await service.selfFulfill(id: 'w1', now: now);

      expect(result.status, WishStatus.fulfilled);
      expect(result.fulfillSource, kWishFulfillSourceChild);
      expect(result.treeSlot, isNull);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.single.payload['kind'], 'selfFulfilled');
    });

    test('无任务愿望 fulfill 原样来源 ParentAction', () async {
      wishes.rows['w1'] = seedWish();

      final Wish result = await service.fulfill(id: 'w1', now: now);

      expect(result.status, WishStatus.fulfilled);
      expect(result.fulfillSource, kWishFulfillSourceParentAction);
      expect(tracking.events.single.payload['kind'], 'fulfilled');
    });
  });

  group('R7-P0-01④⑤⑦ 显式进池 putIntoPool（玄参真机反馈）', () {
    test('手动任务型 targetValue==0：全 verified ⇒ 不经目标闸门进池、source=progress、盖章+1、清树位、发 fulfilled',
        () async {
      // targetValue==0 是根因场景：registerCheckIn:640 的 hasGoalTarget 闸门会拦，
      // 但 putIntoPool 绕过该闸门，仅经 _tryComplete → _complete 唯一收口。
      wishes.rows['w1'] = seedWish(targetValue: 0);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1'); // 手动任务（requiresFocus=false）
      wishTasks.checkIns.add(seedCheckIn(taskId: 't1')); // verified

      final Wish result = await service.putIntoPool(id: 'w1', now: now);

      expect(result.status, WishStatus.fulfilled);
      expect(result.fulfillSource, kWishFulfillSourceProgress,
          reason: 'source=progress，不误挂「我自己做到的」徽标');
      expect(result.treeSlot, isNull, reason: '清树位');
      expect(result.fulfilledAt, now);
      expect(await service.stampedAchievedCount(), 1, reason: '盖章 +1');
      expect((await service.poolWishes()).map((Wish w) => w.id),
          contains('w1'), reason: '进达成池');
      expect(tracking.events, hasLength(1));
      expect(tracking.events.single.payload['kind'], 'fulfilled');
    });

    test('targetValue==0 家长确认后 registerCheckIn 仍被闸门拦（不自动进池）——翻案只由显式按钮补',
        () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');

      final Wish result = await service.registerCheckIn(
        wishId: 'w1',
        checkIn: seedCheckIn(taskId: 't1'),
        task: seedTask(wishId: 'w1'),
        now: now,
      );

      expect(result.status, WishStatus.pending,
          reason: 'targetValue==0 命中 hasGoalTarget 闸门，v0.1 自动进池未生效');
      expect(result.fulfillSource, isNull);
    });

    test('门控未过（有未 verified 任务）⇒ putIntoPool 不改 status、不发埋点', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);
      wishTasks.tasks['t1'] = seedTask(wishId: 'w1');
      wishTasks.tasks['t2'] = seedTask(id: 't2', wishId: 'w1');
      // 只 t1 verified，t2 无打卡 ⇒ wishTasksAllDone == false
      wishTasks.checkIns.add(seedCheckIn(taskId: 't1'));

      final Wish result = await service.putIntoPool(id: 'w1', now: now);

      expect(result.status, WishStatus.pending, reason: '门控拦住');
      expect(result.fulfillSource, isNull);
      expect(result.treeSlot, 0);
      expect(tracking.events, isEmpty, reason: '门控拦截不发 fulfilled');
      expect(await service.stampedAchievedCount(), 0);
    });

    test('无任务愿望 putIntoPool 放行（tasks 为空 ⇒ 门控不拦），同 fulfill 收口', () async {
      wishes.rows['w1'] = seedWish(targetValue: 0);

      final Wish result = await service.putIntoPool(id: 'w1', now: now);

      expect(result.status, WishStatus.fulfilled);
      expect(result.fulfillSource, kWishFulfillSourceProgress);
      expect(tracking.events.single.payload['kind'], 'fulfilled');
    });
  });

  group('R6-P0-01②④ 冻结契约', () {
    test('wishTasksAllDone 判据定义唯一且只落在 wish_progress.dart', () {
      final String progress = _read('lib/domain/services/wish_progress.dart');
      expect(progress.contains('bool wishTasksAllDone({'), isTrue);
      expect(
        'bool wishTasksAllDone({'.allMatches(progress).length,
        1,
        reason: '同一文件里也只能有一处定义',
      );
      for (final String path in <String>[
        'lib/domain/services/wish_orchestration_service.dart',
        'lib/data/local/repositories/task_local_repository.dart',
        'lib/presentation/child/pages/wish_tree_page.dart',
      ]) {
        expect(
          _read(path).contains('bool wishTasksAllDone({'),
          isFalse,
          reason: '$path 不得散写第二份判据',
        );
      }
      // 两处收口都必须调用同一纯函数。
      expect(
        _read('lib/domain/services/wish_orchestration_service.dart')
            .contains('wishTasksAllDone('),
        isTrue,
      );
      expect(
        _read('lib/data/local/repositories/task_local_repository.dart')
            .contains('wishTasksAllDone('),
        isTrue,
        reason: '第 6 条 data 事务路径必须挂门控',
      );
    });

    test('WishStatus 6 态 index / schemaVersion / 达成来源常量冻结', () {
      expect(WishStatus.values.map((WishStatus s) => s.index).toList(),
          <int>[0, 1, 2, 3, 4, 5]);
      expect(kWishFulfillSourceParentAction, 'parentAction');
      expect(kWishFulfillSourceProgress, 'progress');
      expect(kWishFulfillSourceChild, 'child');
      final String database =
          _read('lib/data/local/database/app_database.dart');
      expect(database.contains('int get schemaVersion => 32;'), isTrue);
    });
  });
}
