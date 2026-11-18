/// Independent QA re-verification for wish-domain A-T02.
///
/// These cases are deliberately written from the spec (A18/A19/A20.1/A36.0)
/// rather than copied from the engineer's suite. The focus is on differential
/// gaps the engineer's own tests do not actually exercise:
///   - real `selfFulfill` chain (engineer only seeded fulfilled rows);
///   - post-undo milestone *demotion* 8 -> 2 (engineer used 10 rows so 10->9
///     never crosses a /3 boundary, hiding demotion);
///   - post-undo audit-trail retention (fulfilledAt / fulfillSource kept);
///   - targetValue==0 "no-write" strong assertion (events/changes stay empty);
///   - cross-child guard on multiple entry points;
///   - upscale guard on the `setGoal` integration path, not just the pure fn;
///   - source-level single-point guards.
library wish_domain_qa_test;

import 'dart:io';

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

// ── self-contained fakes (do not import the engineer's test file) ──────────
class QaWishRepo implements WishRepository {
  final Map<String, Wish> rows = <String, Wish>{};

  @override
  Future<List<Wish>> mounted() async => rows.values
      .where((Wish w) =>
          (w.status == WishStatus.pending ||
              w.status == WishStatus.tagged ||
              w.status == WishStatus.committed) &&
          w.releasedAt == null)
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

class QaWishTaskRepo implements WishTaskRepository {
  final Map<String, Task> tasks = <String, Task>{};
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async =>
      tasks.values.where((Task t) => t.wishId == wishId).toList();

  @override
  Future<List<CheckIn>> checkInsOfTaskIds({required List<String> taskIds}) async =>
      checkIns.where((CheckIn c) => taskIds.contains(c.taskId)).toList();

  @override
  Future<void> assignWish({required String taskId, required String wishId}) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: wishId);
  }

  @override
  Future<void> unassignWish({required String taskId}) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: Task.kClear);
  }
}

class QaTrackingRepo implements TrackingRepository {
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
  final DateTime now = DateTime(2026, 11, 17, 12);
  late QaWishRepo wishes;
  late QaWishTaskRepo wishTasks;
  late QaTrackingRepo tracking;
  late WishOrchestrationService service;
  late String child;
  int changes = 0;

  Wish seed({
    String id = 'w',
    String? childId,
    WishStatus status = WishStatus.pending,
    WishGoalMode mode = WishGoalMode.focusMinutes,
    int targetValue = 100,
    int progressValue = 0,
    int? treeSlot = 0,
    DateTime? releasedAt,
    DateTime? fulfilledAt,
    String? fulfillSource,
  }) =>
      Wish(
        id: id,
        childId: childId ?? child,
        text: 'qa wish',
        status: status,
        createdAt: DateTime(2026, 11, 1),
        treeSlot: treeSlot,
        targetMode: mode,
        targetValue: targetValue,
        progressValue: progressValue,
        releasedAt: releasedAt,
        fulfilledAt: fulfilledAt,
        fulfillSource: fulfillSource,
      );

  Task seedTask({
    String id = 't',
    String? wishId,
    bool requiresFocus = true,
    int minFocusMin = 30,
  }) =>
      Task(
        id: id,
        name: 'qa task',
        subject: TaskSubject.general,
        requiresFocus: requiresFocus,
        minFocusMin: minFocusMin,
        sunlightReward: 0,
        isCustom: false,
        wishId: wishId,
      );

  CheckIn seedCheckIn({
    String id = 'c',
    String taskId = 't',
    CheckInStatus status = CheckInStatus.verified,
    double? actualFocusMin = 15,
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
    wishes = QaWishRepo();
    wishTasks = QaWishTaskRepo();
    tracking = QaTrackingRepo();
    changes = 0;
    child = AccountService().childId;
    service = WishOrchestrationService(
      wishes: wishes,
      wishTasks: wishTasks,
      account: AccountService(),
      tracking: tracking,
      onChanged: () => changes++,
      idFactory: () => 'qa-id-${tracking.events.length}',
      isPremium: () => false,
      focusLevelOf: () => 0,
    );
  });

  group('QA · v0.7.0 盖章口径与撤销（差分自证）', () {
    test('QA1 真实 selfFulfill ×10：计数=10、印章=3、source=child、留痕写入', () async {
      // Arrange: 10 pending wishes with a goal (not pre-seeded as fulfilled).
      for (int i = 0; i < 10; i++) {
        wishes.rows['w$i'] = seed(id: 'w$i', treeSlot: i);
      }
      // Act: go through the real self-fulfil chain, not fake rows.
      for (int i = 0; i < 10; i++) {
        await service.selfFulfill(id: 'w$i', now: now);
      }
      // Assert.
      final int stamped = await service.stampedAchievedCount();
      expect(stamped, 10, reason: '10 child self-fulfils must all be stamped');
      expect(WishOrchestrationService.poolMilestoneCount(stamped), 3);
      for (int i = 0; i < 10; i++) {
        final Wish w = wishes.rows['w$i']!;
        expect(w.status, WishStatus.fulfilled);
        expect(w.fulfillSource, kWishFulfillSourceChild);
        expect(w.fulfilledAt, now);
        expect(w.treeSlot, isNull, reason: 'fulfil releases the tree slot');
      }
    });

    test('QA2 撤销 2 次：计数 10→8、印章 3→2 真退档 + 留痕保留 + 不删行', () async {
      // Arrange: 10 fulfilled rows -> stamp=10, milestone=floor(10/3)=3.
      for (int i = 0; i < 10; i++) {
        wishes.rows['w$i'] = seed(
          id: 'w$i',
          status: WishStatus.fulfilled,
          treeSlot: null,
          fulfilledAt: now,
          fulfillSource: kWishFulfillSourceChild,
        );
      }
      expect(await service.stampedAchievedCount(), 10);
      expect(WishOrchestrationService.poolMilestoneCount(10), 3);
      // Act: undo one -> 9 (still milestone 3), undo another -> 8 (milestone 2).
      await service.undoFulfill(id: 'w9', now: now);
      final int afterOne = await service.stampedAchievedCount();
      expect(afterOne, 9);
      expect(WishOrchestrationService.poolMilestoneCount(afterOne), 3);
      await service.undoFulfill(id: 'w8', now: now);
      final int afterTwo = await service.stampedAchievedCount();
      // Assert: this is the demotion the engineer's 10-row test never reaches.
      expect(afterTwo, 8);
      expect(WishOrchestrationService.poolMilestoneCount(afterTwo), 2,
          reason: 'floor(8/3)=2 must demote from 3');
      final Wish reverted = wishes.rows['w9']!;
      expect(reverted.status, WishStatus.pending);
      expect(reverted.fulfilledAt, now, reason: 'C69: audit trail kept');
      expect(reverted.fulfillSource, kWishFulfillSourceChild,
          reason: 'C69: source trail kept');
      expect(wishes.rows['w9'], isNotNull, reason: 'C69: row not deleted');
    });

    test('QA3 撤销写 wishUndo 埋点（wish_undo / actor=parent）', () async {
      wishes.rows['w'] = seed(
        status: WishStatus.fulfilled,
        treeSlot: null,
        fulfilledAt: now,
        fulfillSource: kWishFulfillSourceChild,
      );
      await service.undoFulfill(id: 'w', now: now);
      expect(TrackingEventNames.wishUndo, 'wish_undo');
      final Iterable<TrackingEvent> undoEvents = tracking.events
          .where((TrackingEvent e) => e.name == TrackingEventNames.wishUndo);
      expect(undoEvents, hasLength(1));
      expect(undoEvents.first.payload['actor'], 'parent');
      expect(undoEvents.first.payload['wish_id'], 'w');
    });

    test('QA4 反向边仅家长显式：无 parentUndo 的 fulfilled→pending 抛错', () {
      // The child side / any non-parent path has no parentUndo flag => must throw.
      expect(
        () => WishOrchestrationService.assertTransition(
          WishStatus.fulfilled,
          WishStatus.pending,
        ),
        throwsA(isA<StateError>()),
      );
      // The one legal reverse edge is explicitly parent-tagged.
      expect(
        () => WishOrchestrationService.assertTransition(
          WishStatus.fulfilled,
          WishStatus.pending,
          parentUndo: true,
        ),
        returnsNormally,
      );
    });
  });

  group('QA · 失败路径与守卫', () {
    test('QA5 targetValue==0「我做到了」强拒不落库（行/埋点/通知全不变）', () async {
      final Wish original = seed(targetValue: 0);
      wishes.rows['w'] = original;
      await expectLater(
        service.selfFulfill(id: 'w', now: now),
        throwsA(isA<StateError>()),
      );
      // Nothing may be persisted, emitted, or signalled.
      expect(wishes.rows['w'], same(original));
      expect(wishes.rows['w']!.status, WishStatus.pending);
      expect(wishes.rows['w']!.fulfilledAt, isNull);
      expect(wishes.rows['w']!.fulfillSource, isNull);
      expect(tracking.events, isEmpty);
      expect(changes, 0);
    });

    test('QA6 跨孩子守卫覆盖多个写入口且消息 ASCII', () async {
      wishes.rows['foreign'] = seed(
        id: 'foreign',
        childId: 'child-other',
        targetValue: 100,
      );
      final List<Future<void> Function()> calls = <Future<void> Function()>[
        () => service.fulfill(id: 'foreign', now: now),
        () => service.undoFulfill(id: 'foreign', now: now),
        () => service.advanceProgress(wishId: 'foreign', delta: 1, now: now),
        () => service.tagWithReply(
            id: 'foreign', tag: WishTag.needMoreTime, now: now),
      ];
      for (final Future<void> Function() call in calls) {
        try {
          await call();
          fail('expected cross-child StateError');
        } on StateError catch (e) {
          expect(e.message.codeUnits.every((int c) => c < 128), isTrue,
              reason: 'guard message must be ASCII, got: ${e.message}');
          expect(e.message, contains('cross-child wish'));
        }
      }
    });

    test('QA7 终态不可逆：fulfilled/replaced/abandoned 出发一律抛 StateError', () {
      for (final WishStatus terminal in <WishStatus>[
        WishStatus.fulfilled,
        WishStatus.replaced,
        WishStatus.abandoned,
      ]) {
        for (final WishStatus to in WishStatus.values) {
          expect(
            () => WishOrchestrationService.assertTransition(terminal, to),
            throwsA(isA<StateError>()),
            reason: '$terminal -> $to must be rejected',
          );
        }
      }
    });
  });

  group('QA · 进度模型关键不变式', () {
    test('QA8 mode0 分子 floor + 任务 minFocusMin 双向封顶 + 非聚焦任务 0', () {
      // floor(45.9)=45, capped by minFocusMin=30 => 30.
      expect(
        creditedFocusMinutesOf(
          seedTask(minFocusMin: 30),
          seedCheckIn(actualFocusMin: 45.9),
        ),
        30,
      );
      // minFocusMin=60 does not inflate beyond floor(45.9)=45.
      expect(
        creditedFocusMinutesOf(
          seedTask(minFocusMin: 60),
          seedCheckIn(actualFocusMin: 45.9),
        ),
        45,
      );
      // Non-focus task and null minutes score zero.
      expect(
        creditedFocusMinutesOf(
          seedTask(requiresFocus: false),
          seedCheckIn(actualFocusMin: 45.9),
        ),
        0,
      );
      expect(
        creditedFocusMinutesOf(
          seedTask(),
          seedCheckIn(actualFocusMin: null),
        ),
        0,
      );
      // mode1: verified task row counts exactly 1; pending counts 0.
      expect(
        progressDeltaOf(
          mode: WishGoalMode.taskCount,
          task: seedTask(),
          checkIn: seedCheckIn(status: CheckInStatus.verified),
        ),
        1,
      );
      expect(
        progressDeltaOf(
          mode: WishGoalMode.taskCount,
          task: seedTask(),
          checkIn: seedCheckIn(status: CheckInStatus.pending),
        ),
        0,
      );
    });

    test('QA9 setGoal 集成路径：上调超限被拒且数据不变 / PRD 60→90 放行', () async {
      // taskCount mode 3 -> 5 with progress 2: cap = min(floor(3*1.5), 2*3) = 4.
      wishes.rows['w'] = seed(
        mode: WishGoalMode.taskCount,
        targetValue: 3,
        progressValue: 2,
      );
      final Wish before = wishes.rows['w']!;
      await expectLater(
        service.setGoal(
            wishId: 'w',
            mode: WishGoalMode.taskCount,
            targetValue: 5,
            now: now),
        throwsA(isA<StateError>()),
      );
      expect(wishes.rows['w'], same(before));
      expect(tracking.events, isEmpty);

      // PRD instance: focus mode 60 -> 90 with progress 50 is allowed.
      wishes.rows['w2'] = seed(
        id: 'w2',
        mode: WishGoalMode.focusMinutes,
        targetValue: 60,
        progressValue: 50,
      );
      final Wish ok = await service.setGoal(
          wishId: 'w2',
          mode: WishGoalMode.focusMinutes,
          targetValue: 90,
          now: now);
      expect(ok.targetValue, 90);
      expect(ok.status, WishStatus.pending, reason: 'not ripe yet');
    });

    test('QA10 分子单调不减：负 delta 不回退；同 session 拒、异 session 累加', () async {
      // Negative delta must never decrease progress (R11).
      wishes.rows['w'] = seed(targetValue: 100, progressValue: 20);
      final Wish afterNeg = await service.advanceProgress(
          wishId: 'w', delta: -100, now: now);
      expect(afterNeg.progressValue, 20);

      // Same sessionId with a different check-in id is rejected (R16).
      wishes.rows['m'] = seed(id: 'm', targetValue: 100, progressValue: 0);
      wishTasks.tasks['t'] = seedTask(wishId: 'm');
      wishTasks.checkIns.add(seedCheckIn(id: 'c1', sessionId: 's1'));
      await expectLater(
        service.registerCheckIn(
          wishId: 'm',
          checkIn: seedCheckIn(id: 'c2', sessionId: 's1'),
          task: wishTasks.tasks['t']!,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
      expect(wishes.rows['m']!.progressValue, 0);

      // A distinct sessionId is allowed and accumulates.
      final Wish advanced = await service.registerCheckIn(
        wishId: 'm',
        checkIn: seedCheckIn(id: 'c3', sessionId: 's2'),
        task: wishTasks.tasks['t']!,
        now: now,
      );
      expect(advanced.progressValue, 15);
    });
  });

  group('QA · 源码级单点/纯净守卫', () {
    test('QA11 数值/事件/判据单点与领域纯净', () {
      // Milestone step single point.
      expect(kWishPoolMilestoneStep, 3);
      // Fulfill-source literal single point: only once in prd_params.dart.
      final String params =
          File('lib/core/constants/prd_params.dart').readAsStringSync();
      expect(RegExp(r"const String kWishFulfillSourceChild = 'child';")
          .hasMatch(params), isTrue);
      // Undo event single source.
      expect(TrackingEventNames.wishUndo, 'wish_undo');
      final String names = File('lib/core/constants/tracking_event_names.dart')
          .readAsStringSync();
      expect(RegExp(r"wishUndo = 'wish_undo'").hasMatch(names), isTrue);
      expect(names.contains("'wish_undo'"), isTrue);

      // K26: progressDeltaOf has exactly two mode branches, no default.
      final String progress =
          File('lib/domain/services/wish_progress.dart').readAsStringSync();
      final int start = progress.indexOf('int progressDeltaOf');
      final int switchAt = progress.indexOf('switch (mode)', start);
      final int braceStart = progress.indexOf('{', switchAt);
      int depth = 0;
      int end = braceStart;
      for (int i = braceStart; i < progress.length; i++) {
        if (progress[i] == '{') depth++;
        if (progress[i] == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      final String body = progress.substring(braceStart, end + 1);
      final int caseCount =
          RegExp(r'case WishGoalMode\.\w+').allMatches(body).length;
      expect(caseCount, 2, reason: 'K26: exactly two reachable branches');
      expect(RegExp(r'\bdefault\b').hasMatch(body), isFalse,
          reason: 'K26: no default fallback');

      // Only one FeatureKey.wishSlot registration in the enum.
      final String ent =
          File('lib/domain/entities/entitlement.dart').readAsStringSync();
      final int enumStart = ent.indexOf('enum FeatureKey');
      final int enumEnd = ent.indexOf('}', enumStart);
      final String enumBody = ent.substring(enumStart, enumEnd);
      expect(RegExp(r'\bwishSlot\b').allMatches(enumBody).length, 1,
          reason: 'only one wishSlot FeatureKey, no second daily-limit key');

      // Economy isolation helper exists as the single judgement (G14).
      expect(WishOrchestrationService.isWishLinkedTask(seedTask(wishId: 'w')),
          isTrue);
      expect(WishOrchestrationService.isWishLinkedTask(seedTask()), isFalse);
    });
  });
}
