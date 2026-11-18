/// QA 独立复验 · 许愿树 A-T05 家长端 + `setGoal` 首次设定 P0 修复（严过关）。
///
/// 与工程师 / 既有 QA 文件**不重复**，只打**差分 / 失败路径 / 同源性**：
///
///  A · P0 首次设定（独立判据，不引用实现常量）：
///    · targetValue==0 首设 15 分钟 / 5 条任务 ⇒ 成功 + 落库 + `goalSet` 事件；
///    · 首设时 `progressValue` 已 >0 也必须放行（旧实现 cap=0 会全拒，工程师
///      4 条用例未覆盖「进度先行」这条脏数据路径）；
///    · **护栏没被削弱**：40/40 → 61 拒（cap=min(60,120)=60）/ 55 过；
///      60/20 → 90 拒（progress 边 60 生效，ratio 边 90 放行 ⇒ 单边验证）；
///    · 拒绝时零副作用（行 / 事件 / onChanged 全不变）。
///  B · v0.7.0 家长可撤销：计数 −1 + 印章 floor 退档（9→8，跨 /3 边界 3→2）、
///    留痕保留、不删行、挂载位满落收藏箱、失败路径（非 fulfilled 抛错）、
///    孩子端无撤销入口（源码守卫）、`wish_undo` 埋点 payload 精确。
///  C · UI 与领域判定**同源**：`judgeGoalChange`（oldTarget>0 才判护栏）与
///    `setGoal` 在首设 / 已有目标两类上结论逐值一致（同一组参数双断言钉死）。
///  D · **家长端真实路径**：`WishTaskEditor` 在 targetValue==0 的愿望上提交 ⇒
///    `target_value` 落库 + 任务归属写入 + mode0 强制专注型 + `goalSet`。
///  E · **真实 Drift 库**（NativeDatabase.memory + 真实仓储，非 Fake）：家长三动作
///    + 手动核销后 `sunlight_ledgers` 行数与余额**逐位不变**；mode0 行为型核销
///    不推进进度（R8）。
///
/// 期望值一律写死（按规格自算），不 import 实现常量造期望。
library wish_parent_qa_test;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/wish_task_editor.dart';

// ── 自包含 Fake（不 import 工程 / 既有 QA 的测试文件）────────────────────────

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

class QaWishTaskRepo implements WishTaskRepository {
  final List<({String taskId, String wishId})> assigned =
      <({String taskId, String wishId})>[];

  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async =>
      const <Task>[];

  @override
  Future<List<CheckIn>> checkInsOfTaskIds(
          {required List<String> taskIds}) async =>
      const <CheckIn>[];

  @override
  Future<void> assignWish({
    required String taskId,
    required String wishId,
  }) async =>
      assigned.add((taskId: taskId, wishId: wishId));

  @override
  Future<void> unassignWish({required String taskId}) async {}
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

/// `WishTaskEditor` 写新任务用的仓储（只关心 saveTask）。
class QaTaskRepo implements TaskRepository {
  final Map<String, Task> rows = <String, Task>{};

  @override
  Future<List<Task>> tasks() async => rows.values.toList();

  @override
  Future<void> saveTask(Task task) async => rows[task.id] = task;

  @override
  Future<void> deleteTaskById(String id) async => rows.remove(id);

  @override
  Future<void> checkIn(CheckIn checkIn) async {}

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async =>
      const <CheckIn>[];

  @override
  Future<int> totalCheckInCount() async => 0;
}

/// 真实库计数（**逐位不变**的硬证据）。
Future<int> _countRows(db.AppDatabase database, String table) async {
  final QueryRow row = await database
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.data['c'] as int;
}

void main() {
  final DateTime now = DateTime(2026, 11, 17, 12);
  final AccountService account = AccountService();

  late QaWishRepo wishes;
  late QaWishTaskRepo wishTasks;
  late QaTrackingRepo tracking;
  late WishOrchestrationService service;
  int changes = 0;

  Wish seedWish({
    String id = 'w',
    WishStatus status = WishStatus.pending,
    WishGoalMode mode = WishGoalMode.focusMinutes,
    int targetValue = 0,
    int progressValue = 0,
    int? treeSlot,
    DateTime? releasedAt,
    DateTime? fulfilledAt,
    String? fulfillSource,
  }) =>
      Wish(
        id: id,
        childId: account.childId,
        text: 'qa 愿望 $id',
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

  setUp(() {
    wishes = QaWishRepo();
    wishTasks = QaWishTaskRepo();
    tracking = QaTrackingRepo();
    changes = 0;
    service = WishOrchestrationService(
      wishes: wishes,
      wishTasks: wishTasks,
      account: account,
      tracking: tracking,
      onChanged: () => changes++,
      idFactory: () => 'qa-${tracking.events.length}',
      isPremium: () => false,
      focusLevelOf: () => 0,
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // A · P0：setGoal 首次设定（targetValue == 0）
  // ═══════════════════════════════════════════════════════════════════════
  group('A · P0 首次设定必须放行', () {
    test('A1 targetValue=0 首设专注 15 分钟 ⇒ 成功、落库、发 goalSet', () async {
      wishes.rows['w'] = seedWish(treeSlot: 0);
      final Wish out = await service.setGoal(
        wishId: 'w',
        mode: WishGoalMode.focusMinutes,
        targetValue: 15,
        now: now,
      );
      expect(out.targetValue, 15);
      expect(out.targetMode, WishGoalMode.focusMinutes);
      // 落库（不是只在返回值上）
      expect(wishes.rows['w']!.targetValue, 15);
      expect(changes, 1, reason: 'onChanged 必须触发（家长端借此刷新）');
      final Iterable<TrackingEvent> goalEvents = tracking.events
          .where((TrackingEvent e) => e.payload['kind'] == 'goalSet');
      expect(goalEvents, hasLength(1), reason: '首设必须发 goalSet 事件');
      expect(goalEvents.first.payload['wish_id'], 'w');
    });

    test('A2 targetValue=0 首设任务条数 5（上行边界）⇒ 成功、落库', () async {
      wishes.rows['w'] = seedWish(treeSlot: 0);
      final Wish out = await service.setGoal(
        wishId: 'w',
        mode: WishGoalMode.taskCount,
        targetValue: 5,
        now: now,
      );
      expect(out.targetValue, 5);
      expect(out.targetMode, WishGoalMode.taskCount);
      expect(wishes.rows['w']!.targetValue, 5);
      expect(
        tracking.events.where((TrackingEvent e) => e.payload['kind'] == 'goalSet'),
        hasLength(1),
      );
    });

    test('A3 首设时进度已 >0 也必须放行（旧实现 cap=0 ⇒ 全拒）', () async {
      // 脏数据 / 先推进后设目标：target=0 但 progress=8。
      // 旧口径 cap = min(0*1.5, 8*3) = 0 ⇒ 请求 20 必被拒（整条链路不可用）。
      wishes.rows['w'] = seedWish(treeSlot: 0, progressValue: 8);
      final Wish out = await service.setGoal(
        wishId: 'w',
        mode: WishGoalMode.focusMinutes,
        targetValue: 20,
        now: now,
      );
      expect(out.targetValue, 20, reason: '首设不看历史进度，必须放行');
      expect(out.progressValue, 8, reason: '设目标不得回退已有进度');
      expect(wishes.rows['w']!.targetValue, 20);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // A′ · 护栏没被削弱（自算期望，不调 upscaleAllowed 造期望）
  // ═══════════════════════════════════════════════════════════════════════
  group("A' · 上调护栏仍然生效（自算 cap，写死边界值）", () {
    test('A4 已有目标 40 / 进度 40：61 拒（cap=min(60,120)=60），55 过', () async {
      wishes.rows['w'] = seedWish(treeSlot: 0, targetValue: 40, progressValue: 40);

      // cap = min(40*1.5, 40*3) = min(60, 120) = 60 ⇒ 61 必须拒。
      await expectLater(
        service.setGoal(
          wishId: 'w',
          mode: WishGoalMode.focusMinutes,
          targetValue: 61,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
      // 55 <= 60 ⇒ 必须放行。
      final Wish ok = await service.setGoal(
        wishId: 'w',
        mode: WishGoalMode.focusMinutes,
        targetValue: 55,
        now: now,
      );
      expect(ok.targetValue, 55);
      expect(wishes.rows['w']!.targetValue, 55);
    });

    test('A5 已有目标 60 / 进度 20：90 拒（progress 边 60 生效，ratio 边 90 放行）',
        () async {
      wishes.rows['w'] = seedWish(treeSlot: 0, targetValue: 60, progressValue: 20);
      // ratio 边 = 60*1.5 = 90（允许），progress 边 = 20*3 = 60（不允许）
      // ⇒ cap=60 ⇒ 取 min 后 90 必须被拒（单边验证 progress 那条没被删掉）。
      await expectLater(
        service.setGoal(
          wishId: 'w',
          mode: WishGoalMode.focusMinutes,
          targetValue: 90,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
      expect(wishes.rows['w']!.targetValue, 60, reason: '拒绝不得落库');
      // 恰好 60 不改值（unchanged 语义），61 仍拒。
      await expectLater(
        service.setGoal(
          wishId: 'w',
          mode: WishGoalMode.focusMinutes,
          targetValue: 61,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('A6 拒绝时零副作用：行不变、事件不增、onChanged 不触发', () async {
      wishes.rows['w'] = seedWish(treeSlot: 0, targetValue: 40, progressValue: 40);
      final Wish before = wishes.rows['w']!;
      final int eventsBefore = tracking.events.length;
      final int changesBefore = changes;
      await expectLater(
        service.setGoal(
          wishId: 'w',
          mode: WishGoalMode.focusMinutes,
          targetValue: 100,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
      final Wish after = wishes.rows['w']!;
      expect(after.targetValue, before.targetValue);
      expect(after.targetMode, before.targetMode);
      expect(tracking.events.length, eventsBefore, reason: '拒绝不得发事件');
      expect(changes, changesBefore, reason: '拒绝不得通知刷新');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C · UI 判据与领域判定同源（钉死，防将来再次漂移）
  // ═══════════════════════════════════════════════════════════════════════
  group('C · UI 与领域同源', () {
    test('C1 oldTarget=0 ⇒ UI/increase ⇔ 领域放行（多值钉死）', () async {
      for (final ({WishGoalMode mode, int value}) c in <({
        WishGoalMode mode,
        int value
      })>[
        (mode: WishGoalMode.focusMinutes, value: 10),
        (mode: WishGoalMode.focusMinutes, value: 600),
        (mode: WishGoalMode.taskCount, value: 1),
        (mode: WishGoalMode.taskCount, value: 5),
      ]) {
        // ① UI 判据：首次设定（oldTarget == 0）不得走护栏 ⇒ increase。
        final GoalChangeVerdict verdict = judgeGoalChange(
          oldTarget: 0,
          requestedTarget: c.value,
          progressValue: 0,
        );
        expect(verdict.kind, GoalChangeKind.increase,
            reason: '首设 UI 必须是 increase: ${c.mode}/${c.value}');

        // ② 领域判定：同参数不得抛错。
        wishes.rows['w'] = seedWish(treeSlot: 0);
        final Wish out = await service.setGoal(
          wishId: 'w',
          mode: c.mode,
          targetValue: c.value,
          now: now,
        );
        expect(out.targetValue, c.value,
            reason: '领域必须放行: ${c.mode}/${c.value}');
      }
    });

    test('C2 已有目标 ⇒ UI rejected ⇔ 领域 StateError（同一组参数双断言）', () async {
      for (final ({int oldT, int progress, int request, bool reject}) c in <({
        int oldT,
        int progress,
        int request,
        bool reject
      })>[
        (oldT: 40, progress: 40, request: 61, reject: true),
        (oldT: 40, progress: 40, request: 55, reject: false),
        (oldT: 60, progress: 20, request: 90, reject: true),
        (oldT: 10, progress: 3, request: 12, reject: true),
      ]) {
        final GoalChangeVerdict verdict = judgeGoalChange(
          oldTarget: c.oldT,
          requestedTarget: c.request,
          progressValue: c.progress,
          rejectReason: 'rejected',
        );
        expect(verdict.kind == GoalChangeKind.rejected, c.reject,
            reason: 'UI 判据不符: ${c.oldT}/${c.progress} -> ${c.request}');

        wishes.rows['w'] = seedWish(
          treeSlot: 0,
          targetValue: c.oldT,
          progressValue: c.progress,
        );
        final Future<Wish> act = service.setGoal(
          wishId: 'w',
          mode: WishGoalMode.focusMinutes,
          targetValue: c.request,
          now: now,
        );
        if (c.reject) {
          await expectLater(act, throwsA(isA<StateError>()),
              reason: '领域判定与 UI 不同源: '
                  '${c.oldT}/${c.progress} -> ${c.request}');
        } else {
          expect((await act).targetValue, c.request,
              reason: '领域判定与 UI 不同源（应放行）');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B · v0.7.0 家长可撤销（undoFulfill）
  // ═══════════════════════════════════════════════════════════════════════
  group('B · 家长撤销（唯一反向边）', () {
    test('B1 9 条已达成撤销 1 条：计数 9→8、印章 floor(9/3)=3 → floor(8/3)=2 退档',
        () async {
      for (int i = 0; i < 9; i++) {
        wishes.rows['f$i'] = seedWish(
          id: 'f$i',
          status: WishStatus.fulfilled,
          fulfilledAt: now,
          fulfillSource: 'child',
        );
      }
      expect(await service.stampedAchievedCount(), 9);
      final Wish reverted = await service.undoFulfill(id: 'f8', now: now);

      final int stamped = await service.stampedAchievedCount();
      expect(stamped, 8, reason: '盖章计数必须 −1');
      // 印章档位 = floor(stamped/3)：9→3、8→2（跨过 /3 边界才算真退档）。
      expect(9 ~/ 3, 3);
      expect(stamped ~/ 3, 2, reason: '印章数必须退档 3 → 2');
      expect(WishOrchestrationService.poolMilestoneCount(stamped), 2);

      // 留痕不清空 + 状态回树上 + 重新分配挂载位 + 不删行。
      expect(reverted.status, WishStatus.pending);
      expect(reverted.fulfilledAt, now, reason: 'C69：audit 留痕不得清空');
      expect(reverted.fulfillSource, 'child', reason: 'C69：来源留痕不得清空');
      expect(reverted.releasedAt, isNull);
      expect(reverted.treeSlot, 0, reason: '退回树上要占一个挂载位');
      expect(wishes.rows.length, 9, reason: 'C69：撤销不得删行');
    });

    test('B2 树上挂载位已满 ⇒ 撤销落收藏箱（releasedAt 非空 + 无挂载位）+ 不删行',
        () async {
      // 免费档 0 级额度 = 1：已有 1 条在树上 ⇒ 撤销后无法再挂 ⇒ 落收藏箱。
      wishes.rows['m'] = seedWish(id: 'm', treeSlot: 0);
      wishes.rows['f'] = seedWish(
        id: 'f',
        status: WishStatus.fulfilled,
        fulfilledAt: now,
        fulfillSource: 'child',
      );
      final Wish reverted = await service.undoFulfill(id: 'f', now: now);
      expect(reverted.status, WishStatus.pending);
      expect(reverted.releasedAt, now, reason: '挂载位满 ⇒ 落收藏箱');
      expect(reverted.treeSlot, isNull);
      expect((await service.boxedWishes()).map((Wish w) => w.id), contains('f'));
      expect(wishes.rows.length, 2, reason: 'C69：不删行');
      expect(wishes.rows['m']!.treeSlot, 0, reason: '既有挂载愿望不得被动');
    });

    test('B3 失败路径：pending 撤销必须抛错；孩子端无撤销入口（源码守卫）',
        () async {
      wishes.rows['p'] = seedWish(id: 'p', treeSlot: 0);
      await expectLater(
        service.undoFulfill(id: 'p', now: now),
        throwsA(isA<StateError>()),
        reason: '只有 fulfilled 才有反向边',
      );
      expect(tracking.events, isEmpty, reason: '失败不得留下 wish_undo 埋点');
      // 孩子端 UI 层不得出现 undoFulfill（撤销只归家长端）。
      final List<File> childFiles = Directory('lib/presentation/child')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(childFiles, isNotEmpty);
      for (final File f in childFiles) {
        expect(f.readAsStringSync().contains('undoFulfill'), isFalse,
            reason: '孩子端不得触发撤销：${f.path}');
      }
    });

    test('B4 撤销埋点：恰好 1 条 wish_undo，payload 精确', () async {
      wishes.rows['w'] = seedWish(
        status: WishStatus.fulfilled,
        fulfilledAt: now,
        fulfillSource: 'child',
      );
      await service.undoFulfill(id: 'w', now: now);
      final List<TrackingEvent> undoEvents = tracking.events
          .where((TrackingEvent e) => e.name == 'wish_undo')
          .toList();
      expect(undoEvents, hasLength(1));
      expect(undoEvents.single.payload, <String, dynamic>{
        'wish_id': 'w',
        'actor': 'parent',
      });
      expect(undoEvents.single.type, TrackingType.metric);
      expect(tracking.events.length, 1, reason: '撤销只发这一条埋点');
    });

    // GAP-1（已加固）：`undoFulfill` 原先复用通用状态机断言，而
    // `tagged → pending`（untag）/ `committed → pending`（解承诺）在状态机里
    // **本身就是合法边** ⇒ 对「非 fulfilled」调用撤销不抛错，还会写出一条
    // `wish_undo`，使审计出现「一次从未发生的退回已达成」。
    // 规格（PRD「其他任何越级 / 反向迁移仍一律抛错」、设计「唯一合法反向边
    // fulfilled→pending」）要求撤销只承载这一条边。
    // 现已在服务层加显式守卫（`if (wish.status != WishStatus.fulfilled) throw`），
    // 本用例翻转为**正向断言**，防止守卫将来被误删或退回旧实现。
    test('B5 撤销只对 fulfilled 生效：tagged / committed 必须抛错且零埋点', () async {
      for (final WishStatus illegal in <WishStatus>[
        WishStatus.tagged,
        WishStatus.committed,
        WishStatus.pending,
        WishStatus.replaced,
        WishStatus.abandoned,
      ]) {
        wishes.rows['x'] = seedWish(id: 'x', status: illegal, treeSlot: 1);
        final int before = tracking.events.length;
        await expectLater(
          service.undoFulfill(id: 'x', now: now),
          throwsA(isA<StateError>()),
          reason: '非 fulfilled 状态 $illegal 不得撤销（唯一反向边只有 fulfilled→pending）',
        );
        expect(wishes.rows['x']!.status, illegal, reason: '拒绝时状态不得改变');
        expect(tracking.events.length, before, reason: '拒绝时不得发出 wish_undo 埋点');
      }

      // 对照组：fulfilled 仍可撤销（守卫没有误伤唯一合法路径）。
      wishes.rows['ok'] = seedWish(
        id: 'ok',
        status: WishStatus.fulfilled,
        fulfilledAt: now,
        fulfillSource: 'child',
      );
      final Wish reverted = await service.undoFulfill(id: 'ok', now: now);
      expect(reverted.status, WishStatus.pending);
      expect(
        tracking.events.where((TrackingEvent e) => e.name == 'wish_undo'),
        hasLength(1),
        reason: '合法撤销必须发出恰好一条 wish_undo',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // D · 家长端真实路径（WishTaskEditor 弹层提交）
  // ═══════════════════════════════════════════════════════════════════════
  group('D · 家长端真实路径', () {
    testWidgets('D1 targetValue=0 愿望 ⇒ 编辑器提交 ⇒ target_value 落库 + 任务归属写入',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final QaWishRepo repo = QaWishRepo();
      final QaWishTaskRepo taskRepoForWish = QaWishTaskRepo();
      final QaTrackingRepo track = QaTrackingRepo();
      final QaTaskRepo taskRepo = QaTaskRepo();
      final WishOrchestrationService svc = WishOrchestrationService(
        wishes: repo,
        wishTasks: taskRepoForWish,
        account: account,
        tracking: track,
        isPremium: () => false,
        focusLevelOf: () => 0,
      );
      // 家长端看到的愿望：还没设目标。
      repo.rows['w'] = seedWish(treeSlot: 0);

      bool? dialogResult;
      int savedCalls = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          wishOrchestrationServiceProvider.overrideWithValue(svc),
          taskRepositoryProvider.overrideWithValue(taskRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<bool>(
                      context: ctx,
                      builder: (BuildContext _) => WishTaskEditor(
                        wish: repo.rows['w']!,
                        onSaved: () => savedCalls++,
                      ),
                    );
                  },
                  child: const Text('open-editor'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();
      expect(find.byType(WishTaskEditor), findsOneWidget);

      // 切到「任务」页签并填一条任务（默认草稿名为空 ⇒ 不写）。
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('parent_wish_task_name_0')), '整理书桌');
      await tester.pumpAndSettle();

      // 提交（AlertDialog actions 里唯一的 FilledButton）。
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ));
      await tester.pumpAndSettle();

      // ① 弹层提交成功并被关闭。
      expect(dialogResult, isTrue, reason: '提交应 pop(true)');
      expect(savedCalls, 1, reason: 'onSaved 必须回调（页面刷新）');
      // ② 目标落库：mode0 默认值 30（10~600 区间的产品默认），且是首设。
      expect(repo.rows['w']!.targetValue, 30, reason: '首设必须写进 target_value');
      expect(repo.rows['w']!.targetMode, WishGoalMode.focusMinutes);
      // ③ goalSet 事件发出。
      expect(
        track.events.where((TrackingEvent e) => e.payload['kind'] == 'goalSet'),
        hasLength(1),
      );
      // ④ 任务落库并归属该愿望；mode0 强制专注型（R8）。
      expect(taskRepo.rows, hasLength(1));
      final Task created = taskRepo.rows.values.single;
      expect(created.name, '整理书桌');
      expect(created.wishId, 'w');
      expect(created.requiresFocus, isTrue, reason: 'mode0 下不给行为型任务');
      // ⑤ 归属写入走 assignTasks（只写 tasks.wish_id）。
      expect(taskRepoForWish.assigned.map((r) => r.wishId), contains('w'));
      expect(taskRepoForWish.assigned.map((r) => r.taskId),
          contains(created.id));
      // ⑥ 一动作不丢数据：愿望行数不变。
      expect(repo.rows.length, 1);
    });

    testWidgets('D2 mode1（任务条数口径）增删任务必须二次确认（取消 ⇒ 不加草稿）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final QaWishRepo repo = QaWishRepo();
      final WishOrchestrationService svc = WishOrchestrationService(
        wishes: repo,
        wishTasks: QaWishTaskRepo(),
        account: account,
        tracking: QaTrackingRepo(),
        isPremium: () => false,
        focusLevelOf: () => 0,
      );
      // 已是「任务条数」口径（分母与任务条数耦合 ⇒ R3 要求二次确认）。
      repo.rows['w'] = seedWish(
        treeSlot: 0,
        mode: WishGoalMode.taskCount,
        targetValue: 3,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          wishOrchestrationServiceProvider.overrideWithValue(svc),
          taskRepositoryProvider.overrideWithValue(QaTaskRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: ctx,
                    builder: (BuildContext _) => WishTaskEditor(
                      wish: repo.rows['w']!,
                      onSaved: () {},
                    ),
                  ),
                  child: const Text('open-editor'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent_wish_task_name_0')), findsOneWidget);

      // 点「+ 添加任务」⇒ 必须先弹二次确认（AlertDialog 由 1 张变 2 张）。
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('parent_wish_task_add')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNWidgets(2),
          reason: 'mode1 增删任务必须先二次确认（R3）');

      // 取消 ⇒ 草稿数不变（不新增第 2 行）。
      await tester.tap(find
          .descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(TextButton),
          )
          .first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent_wish_task_name_1')), findsNothing,
          reason: '取消后不得新增任务草稿');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // E · 真实 Drift 库：经济零改动（不是 Fake，是真实仓储 + 真实账本）
  // ═══════════════════════════════════════════════════════════════════════
  group('E · 真实库经济零改动', () {
    test('E1 三动作 + 手动核销后 sunlight_ledgers 行数/余额逐位不变', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      await database.customSelect('SELECT 1').get(); // 建表
      addTearDown(() async => database.close());

      final TaskLocalRepository tasks = TaskLocalRepository(database);
      final WishLocalRepository wishRepo = WishLocalRepository(database);
      final SunlightLocalRepository ledger = SunlightLocalRepository(database);
      final TrackingLocalRepository trackingRepo =
          TrackingLocalRepository(database);
      final SettingsLocalRepository settings = SettingsLocalRepository(database);
      final FocusLocalRepository focus = FocusLocalRepository(database);

      int seq = 0;
      final WishOrchestrationService wishSvc = WishOrchestrationService(
        wishes: wishRepo,
        wishTasks: tasks,
        account: account,
        tracking: trackingRepo,
        idFactory: () => 'qa-real-${seq++}',
        isPremium: () => false,
        focusLevelOf: () => 0,
      );

      final DateTime t0 = DateTime(2026, 11, 17, 10);
      // ① 孩子许愿。
      final Wish created = await wishSvc.createWish(
        text: '想要一只小仓鼠',
        category: WishCategory.other,
        now: t0,
      );
      // ② 家长首设目标（P0 路径）—— 真实 drift 落库。
      final Wish goalSet = await wishSvc.setGoal(
        wishId: created.id,
        mode: WishGoalMode.focusMinutes,
        targetValue: 15,
        now: t0,
      );
      expect(goalSet.targetValue, 15);
      expect((await wishSvc.wishById(created.id))!.targetValue, 15,
          reason: '真实库 target_value 必须落库');

      // ③ 布置一条行为型愿望任务（mode0 下手动核销路径）。
      const String taskId = 'qa-real-wish-task';
      const Task wishTask = Task(
        id: taskId,
        name: '整理书桌',
        subject: TaskSubject.general,
        requiresFocus: false,
        minFocusMin: 15,
        sunlightReward: 5,
        isCustom: true,
        wishId: 'placeholder',
      );
      await tasks.saveTask(Task(
        id: wishTask.id,
        name: wishTask.name,
        subject: wishTask.subject,
        requiresFocus: wishTask.requiresFocus,
        minFocusMin: wishTask.minFocusMin,
        sunlightReward: wishTask.sunlightReward,
        isCustom: wishTask.isCustom,
        wishId: created.id,
      ));
      await wishSvc.assignTasks(
        wishId: created.id,
        taskIds: <String>[taskId],
        now: t0,
      );

      // 基线快照（**逐位**对比用）。
      final int ledgerRowsBefore = await _countRows(database, 'sunlight_ledgers');
      final double balanceBefore = await ledger.balance();
      final int wishRowsBefore = await _countRows(database, 'wishes');
      final int taskRowsBefore = await _countRows(database, 'tasks');
      // 碎片余额（premium_fragments）也必须在基线里。
      final int fragmentRowsBefore =
          await _countRows(database, 'premium_fragments');

      // ④ 家长三动作：贴标签 + 温柔回复 / 直接实现 / 撤销。
      await wishSvc.tagWithReply(
        id: created.id,
        tag: WishTag.needMoreTime,
        reply: '再等等，我们一起想办法',
        now: t0,
      );
      // 贴标签后：愿望仍在树上且仍占 1 个挂载位（不丢数据）。
      final List<Wish> mountedAfterTag = await wishSvc.mountedWishes();
      expect(mountedAfterTag.map((Wish w) => w.id), contains(created.id),
          reason: '贴标签后愿望必须还在树上');
      expect(mountedAfterTag.single.treeSlot, isNotNull,
          reason: '贴标签后仍占 1 个挂载位');
      await wishSvc.fulfill(id: created.id, now: t0);
      final Wish undone = await wishSvc.undoFulfill(id: created.id, now: t0);
      expect(undone.status, WishStatus.pending);
      expect(undone.fulfillSource, 'parentAction', reason: 'C69：留痕不清空');
      expect(undone.fulfilledAt, isNotNull, reason: 'C69：留痕不清空');

      // ⑤ 孩子打卡 → 家长手动核销（走既有 check_ins 流水）。
      final TaskCheckInService checkInSvc = TaskCheckInService(
        tasks: tasks,
        ledger: ledger,
        focus: focus,
        settings: settings,
        wishTasks: tasks,
        onWishEvent: (String wishId, WishEventKind kind, DateTime at) {},
        onWishCheckInVerified: (Task task, CheckIn checkIn, DateTime at) =>
            wishSvc.registerCheckIn(
          wishId: task.wishId ?? '',
          checkIn: checkIn,
          task: task,
          now: at,
        ),
      );
      // 读侧隔离（A16.4 ⑦-d）：愿望任务不进 `tasks()`，只能经 tasksOfWish 取。
      final Task reloadedTask = (await tasks.tasksOfWish(wishId: created.id))
          .firstWhere((Task t) => t.id == taskId);
      final TaskCheckInOutcome pendingOut =
          await checkInSvc.checkIn(task: reloadedTask, now: t0);
      expect(pendingOut.status, CheckInStatus.pending);
      expect(pendingOut.granted, 0.0, reason: '许愿任务当期不发阳光');
      final TaskCheckInOutcome verifiedOut =
          await checkInSvc.verifyCheckIn(pendingOut.checkInId, t0);
      expect(verifiedOut.granted, 0.0, reason: '许愿任务核销不发阳光（G14）');

      // ⑥ 经济逐位不变。
      expect(await _countRows(database, 'sunlight_ledgers'), ledgerRowsBefore,
          reason: 'C69/G14：账本行数必须逐位不变');
      expect(await ledger.balance(), balanceBefore,
          reason: 'C69/G14：余额必须逐位不变');
      expect(await _countRows(database, 'premium_fragments'),
          fragmentRowsBefore,
          reason: 'C69/G14：碎片余额必须逐位不变');
      // ⑦ 数据不丢。
      expect(await _countRows(database, 'wishes'), wishRowsBefore,
          reason: '三动作 / 撤销不得删行');
      expect(await _countRows(database, 'tasks'), taskRowsBefore,
          reason: '布置任务不得删行');
      // ⑧ mode0 下行为型任务核销不推进进度（R8）。
      expect((await wishSvc.wishById(created.id))!.progressValue, 0,
          reason: 'mode0 下行为型任务不计分');
      // ⑨ SunlightRepository 无新增写方法（源码守卫：账本写入只在既有链路）。
      final List<String> ledgerApi = File(
              'lib/domain/repositories/sunlight_repository.dart')
          .readAsStringSync()
          .split('\n')
          .where((String l) => l.trimLeft().startsWith('Future<'))
          .toList();
      expect(ledgerApi, isNotEmpty);
      expect(ledgerApi.where((String l) => l.contains('wish')), isEmpty,
          reason: '许愿链路不得给账本新增方法');
    });
  });
}
