/// Wish orchestration: the single writer of wish state transitions.
///
/// Pure Dart by design: every IO collaborator is an injected interface and
/// every operation receives `DateTime now`. All errors use ASCII English
/// messages because they are developer-facing invariants, never UI copy.
library wish_orchestration_service;

import 'dart:async';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';

/// The only legal non-terminal -> terminal and reverse edges.
const Set<WishStatus> _treeStatuses = <WishStatus>{
  WishStatus.pending,
  WishStatus.tagged,
  WishStatus.committed,
};

class WishOrchestrationService {
  WishOrchestrationService({
    required WishRepository wishes,
    required WishTaskRepository wishTasks,
    required AccountService account,
    required TrackingRepository tracking,
    void Function()? onChanged,
    String Function()? idFactory,
    bool Function()? isPremium,
    int Function()? focusLevelOf,
  })  : _wishes = wishes,
        _wishTasks = wishTasks,
        _account = account,
        _tracking = tracking,
        _onChanged = onChanged,
        _idFactory = idFactory ?? _defaultIdFactory,
        _isPremium = isPremium ?? _defaultIsPremium,
        _focusLevelOf = focusLevelOf ?? _defaultFocusLevel;

  final WishRepository _wishes;
  final WishTaskRepository _wishTasks;
  final AccountService _account;
  final TrackingRepository _tracking;
  final void Function()? _onChanged;
  final String Function() _idFactory;
  final bool Function() _isPremium;
  final int Function() _focusLevelOf;

  /// Serial gate (R17): every write is queued behind the previous one.
  Future<void> _gate = Future<void>.value();

  static String _defaultIdFactory() =>
      DateTime.now().microsecondsSinceEpoch.toString();
  static bool _defaultIsPremium() => false;
  static int _defaultFocusLevel() => 0;

  /// The one helper used to keep wish-linked tasks out of the economy (G14).
  static bool isWishLinkedTask(Task task) => task.wishId != null;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _gate;
    _gate = done.future;
    return previous.then<T>((_) => action()).whenComplete(done.complete);
  }

  void _changed() => _onChanged?.call();

  /// Cross-child guard (ASCII message only).
  void _guardCurrentChild(Wish wish) {
    final String current = _account.childId;
    if (wish.childId != current) {
      throw StateError('cross-child wish: ${wish.id} belongs to '
          '${wish.childId}, current child is $current');
    }
  }

  Future<Wish> _requireWish(String id) async {
    final Wish? wish = await _wishes.byId(id);
    if (wish == null) throw StateError('wish not found: $id');
    _guardCurrentChild(wish);
    return wish;
  }

  /// State machine. [parentUndo] is the single reverse edge (v0.7.0).
  static void assertTransition(
    WishStatus from,
    WishStatus to, {
    bool parentUndo = false,
  }) {
    if (parentUndo && from == WishStatus.fulfilled && to == WishStatus.pending) {
      return;
    }
    final bool legal = switch (from) {
      WishStatus.pending =>
        to == WishStatus.tagged ||
            to == WishStatus.fulfilled ||
            to == WishStatus.committed,
      WishStatus.tagged =>
        to == WishStatus.pending ||
            to == WishStatus.fulfilled ||
            to == WishStatus.abandoned,
      WishStatus.committed =>
        to == WishStatus.pending ||
            to == WishStatus.fulfilled ||
            to == WishStatus.replaced,
      WishStatus.fulfilled ||
      WishStatus.replaced ||
      WishStatus.abandoned =>
        false,
    };
    if (!legal) {
      throw StateError('illegal wish transition: ${from.name} -> ${to.name}');
    }
  }

  // ── reads ────────────────────────────────────────────────────────────────
  Future<List<Wish>> mountedWishes() async => _wishes.mounted();

  Future<List<Wish>> poolWishes() async => _wishes.pool();

  Future<List<Wish>> boxedWishes() async => _wishes.boxed();

  Future<List<Wish>> abandonedWishes() async => _wishes.abandoned();

  Future<int> mountedCount() async => (await _wishes.mounted()).length;

  Future<int> achievedCount() async =>
      (await _wishes.byStatuses(<WishStatus>{
        WishStatus.fulfilled,
        WishStatus.replaced,
      }))
          .length;

  /// Milestone stamp count = count(status = fulfilled), child source included.
  Future<int> stampedAchievedCount() => _wishes.countStampedAchieved();

  static int poolMilestoneCount(int stampedAchievedCount) =>
      stampedAchievedCount ~/ kWishPoolMilestoneStep;

  static bool softGateSatisfied(int plantCount) =>
      plantCount >= kWishSoftGateMinPlants;

  static int waitingDays(DateTime createdAt, DateTime now) =>
      startOfDay(now).difference(startOfDay(createdAt)).inDays;

  Future<Wish?> wishById(String id) async {
    final Wish wish = await _requireWish(id);
    return wish;
  }

  /// Parent desk: reminded first, then longest waiting first.
  Future<List<Wish>> parentDeskList(DateTime now) async {
    final List<Wish> rows = (await _wishes.byStatuses(_treeStatuses))
        .where((Wish w) => w.releasedAt == null)
        .toList();
    rows.sort((Wish a, Wish b) {
      final int reminded = (b.remindedAt == null ? 0 : 1) -
          (a.remindedAt == null ? 0 : 1);
      if (reminded != 0) return reminded;
      final int byWait = waitingDays(b.createdAt, now) -
          waitingDays(a.createdAt, now);
      if (byWait != 0) return byWait;
      return a.id.compareTo(b.id);
    });
    return rows;
  }

  Future<int> currentWishSlotQuota() async => wishSlotQuotaFor(
        focusLevel: _focusLevelOf(),
        isPremium: _isPremium(),
      );

  Future<List<Task>> tasksOf({
    required String wishId,
    required DateTime now,
  }) async {
    await _requireWish(wishId);
    return _wishTasks.tasksOfWish(wishId: wishId);
  }

  /// Daily reset is a read-side derivation: the repeat window key changes at
  /// local midnight. Terminal wishes expose `closed` without touching a column.
  Future<WishTaskStage> effectiveStatusOf({
    required String wishId,
    required Task task,
    required List<CheckIn> checkIns,
    required DateTime now,
  }) async {
    final Wish wish = await _requireWish(wishId);
    if (wish.isTerminal) return WishTaskStage.closed;
    return wishTaskStageOf(task: task, checkIns: checkIns, now: now);
  }

  WishWorkCategory sectionOf({
    required Wish wish,
    required List<Task> tasks,
    required List<CheckIn> checkIns,
  }) {
    if (hasPendingCheckIn(wish: wish, checkIns: checkIns)) {
      return WishWorkCategory.pendingVerify;
    }
    if (needsParentSetup(wish: wish, tasks: tasks)) {
      return WishWorkCategory.needsSetup;
    }
    if (isSelfProgressing(wish: wish)) {
      return WishWorkCategory.selfProgressing;
    }
    return WishWorkCategory.collapsed;
  }

  bool hasPendingCheckIn({
    required Wish wish,
    required List<CheckIn> checkIns,
  }) {
    final Set<String> taskIds = checkIns
        .where((CheckIn c) => c.status == CheckInStatus.pending)
        .map((CheckIn c) => c.taskId)
        .toSet();
    return taskIds.isNotEmpty;
  }

  bool needsParentSetup({
    required Wish wish,
    required List<Task> tasks,
  }) =>
      !hasGoalTarget(wish.targetValue) ||
      tasks.every((Task t) => t.wishId != wish.id);

  bool isSelfProgressing({required Wish wish}) =>
      hasGoalTarget(wish.targetValue) && wish.progressValue > 0;

  // ── writes ───────────────────────────────────────────────────────────────
  Future<Wish> createWish({
    required String text,
    required WishCategory category,
    required DateTime now,
  }) =>
      _serialized(() async {
        final String clean = text.trim();
        final int length = clean.runes.length;
        if (length < kWishTextMinLength || length > kWishTextMaxLength) {
          throw StateError('wish text length out of range');
        }
        final DateTime cutoff =
            now.subtract(const Duration(days: kWishDuplicateLookbackDays));
        final List<Wish> all = await _wishes.byStatuses(WishStatus.values.toSet());
        for (final Wish w in all) {
          if (w.text != clean) continue;
          if (_treeStatuses.contains(w.status) ||
              !w.createdAt.isBefore(cutoff)) {
            throw StateError('duplicate wish text');
          }
        }
        final int currentCount = (await _wishes.mounted()).length;
        final int level = _focusLevelOf();
        final bool premium = _isPremium();
        if (!quotaAllowsAddWishSlot(
          focusLevel: level,
          isPremium: premium,
          currentCount: currentCount,
        )) {
          throw StateError('wish slot quota exceeded');
        }
        final int slot = _allocateSlot(await _wishes.occupiedSlots());
        final Wish created = Wish(
          id: _idFactory(),
          childId: _account.childId,
          text: clean,
          category: category,
          status: WishStatus.pending,
          createdAt: now,
          treeSlot: slot,
        );
        await _wishes.save(created);
        _changed();
        return created;
      });

  int _allocateSlot(Set<int> occupied) {
    int slot = 0;
    while (occupied.contains(slot)) {
      slot++;
    }
    return slot;
  }

  /// The ONLY writer of `target_mode` / `target_value` (G12).
  Future<Wish> setGoal({
    required String wishId,
    required WishGoalMode mode,
    required int targetValue,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(wishId);
        if (wish.releasedAt != null) {
          throw StateError('cannot set goal while wish is in the box');
        }
        final int min = mode == WishGoalMode.focusMinutes
            ? kWishGoalFocusMinutesMin
            : kWishGoalTaskCountMin;
        final int max = mode == WishGoalMode.focusMinutes
            ? kWishGoalFocusMinutesMax
            : kWishGoalTaskCountMax;
        if (targetValue < min || targetValue > max) {
          throw StateError('goal target out of range');
        }
        int next = targetValue;
        if (next < wish.targetValue) {
          next = clampedGoalAfterDecrease(
            requestedTarget: next,
            progressValue: wish.progressValue,
          );
        } else if (wish.targetValue > 0 &&
            next > wish.targetValue &&
            !upscaleAllowed(
              oldTarget: wish.targetValue,
              requestedTarget: next,
              progressValue: wish.progressValue,
            )) {
          // 上调护栏只约束「已有目标」的调整（R5 / PRD Q21）。
          // 首次设定（targetValue == 0，未设目标的唯一判据）必须放行：
          // 此时 cap = min(0*1.5, progress*3) = 0，若不过滤会把家长的
          // 第一次设目标全部拒掉，使「设定目标 + 布置任务」整条链路不可用。
          // 与 UI 判据（wish_task_editor.dart 的 oldTarget > 0 前置）同源。
          throw StateError('goal upscale exceeds guard');
        }
        Wish updated = wish.copyWith(targetMode: mode, targetValue: next);
        if (fruitStageOf(
                targetValue: next, progressValue: wish.progressValue) ==
            WishFruitStage.ripe) {
          updated = _complete(updated, kWishFulfillSourceProgress, now);
        }
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.goalSet, now);
        _changed();
        return updated;
      });

  /// Only writes `tasks.wish_id`; never touches goal or progress columns.
  Future<List<String>> assignTasks({
    required String wishId,
    required List<String> taskIds,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(wishId);
        if (wish.isTerminal) {
          throw StateError('cannot assign tasks to a closed wish');
        }
        if (taskIds.length > kWishTaskMaxCount) {
          throw StateError('wish task count exceeded');
        }
        for (final String taskId in taskIds) {
          await _wishTasks.assignWish(taskId: taskId, wishId: wishId);
        }
        await _emit(wish, WishEventKind.taskAssigned, now);
        _changed();
        return taskIds;
      });

  Future<Wish> fulfill({
    required String id,
    String? reply,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        assertTransition(wish.status, WishStatus.fulfilled);
        final Wish updated = _complete(
          wish.copyWith(parentReply: reply ?? wish.parentReply),
          kWishFulfillSourceParentAction,
          now,
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.fulfilled, now);
        _changed();
        return updated;
      });

  /// Child self-fulfilment. v0.7.0 anti-abuse gate: a goal must exist; a
  /// boxed wish never renders the button; 100% progress is NOT a precondition.
  Future<Wish> selfFulfill({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        if (!hasGoalTarget(wish.targetValue)) {
          throw StateError('self fulfill requires a goal target');
        }
        if (wish.releasedAt != null) {
          throw StateError('self fulfill is unavailable in the box');
        }
        assertTransition(wish.status, WishStatus.fulfilled);
        final Wish updated = _complete(wish, kWishFulfillSourceChild, now);
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.selfFulfilled, now);
        _changed();
        return updated;
      });

  /// v0.7.0 parent undo: the single legal reverse edge. History is preserved.
  Future<Wish> undoFulfill({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        // 唯一合法反向边只对「已达成」生效（PRD：其他任何越级 / 反向迁移仍一律抛错）。
        // 不能只依赖 assertTransition：`tagged → pending`（取消标签）与
        // `committed → pending`（解除承诺）本身就是合法边，会让撤销作用在
        // 非达成愿望上静默成功，并写出一条「从未发生的退回已达成」审计埋点。
        if (wish.status != WishStatus.fulfilled) {
          throw StateError('undo requires a fulfilled wish');
        }
        assertTransition(wish.status, WishStatus.pending, parentUndo: true);
        final int level = _focusLevelOf();
        final bool premium = _isPremium();
        final int mounted = (await _wishes.mounted()).length;
        final bool canRemount = quotaAllowsAddWishSlot(
          focusLevel: level,
          isPremium: premium,
          currentCount: mounted,
        );
        final Wish reverted = wish.copyWith(
          status: WishStatus.pending,
          treeSlot: canRemount
              ? _allocateSlot(await _wishes.occupiedSlots())
              : Wish.kClear,
          releasedAt: canRemount ? Wish.kClear : now,
        );
        await _wishes.save(reverted);
        await _tracking.track(TrackingEvent(
          id: _idFactory(),
          name: TrackingEventNames.wishUndo,
          type: TrackingType.metric,
          ts: now,
          payload: <String, dynamic>{'wish_id': id, 'actor': 'parent'},
        ));
        _changed();
        return reverted;
      });

  Wish _complete(Wish wish, String source, DateTime now) {
    assertTransition(wish.status, WishStatus.fulfilled);
    return wish.copyWith(
      status: WishStatus.fulfilled,
      fulfilledAt: now,
      fulfillSource: source,
      treeSlot: Wish.kClear,
      parentSeenAt: wish.parentSeenAt ?? now,
    );
  }

  Future<Wish> tagWithReply({
    required String id,
    required WishTag tag,
    String? reply,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        assertTransition(wish.status, WishStatus.tagged);
        final Wish updated = wish.copyWith(
          status: WishStatus.tagged,
          tagKey: tag.name,
          taggedAt: now,
          parentReply: reply ?? wish.parentReply,
          parentSeenAt: now,
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.tagged, now);
        _changed();
        return updated;
      });

  Future<Wish> untag({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        assertTransition(wish.status, WishStatus.pending);
        final Wish updated = wish.copyWith(
          status: WishStatus.pending,
          tagKey: Wish.kClear,
          taggedAt: Wish.kClear,
          parentSeenAt: now,
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.untagged, now);
        _changed();
        return updated;
      });

  Future<Wish> collectToBox({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        if (wish.releasedAt != null) return wish;
        final Wish updated = wish.copyWith(
          releasedAt: now,
          treeSlot: Wish.kClear,
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.released, now);
        _changed();
        return updated;
      });

  Future<Wish> restoreFromBox({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        if (wish.releasedAt == null) return wish;
        final int mounted = (await _wishes.mounted()).length;
        if (!quotaAllowsAddWishSlot(
          focusLevel: _focusLevelOf(),
          isPremium: _isPremium(),
          currentCount: mounted,
        )) {
          throw StateError('wish slot quota exceeded');
        }
        final Wish updated = wish.copyWith(
          releasedAt: Wish.kClear,
          treeSlot: _allocateSlot(await _wishes.occupiedSlots()),
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.restored, now);
        _changed();
        return updated;
      });

  Future<Wish> abandon({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        assertTransition(wish.status, WishStatus.abandoned);
        final Wish updated = wish.copyWith(
          status: WishStatus.abandoned,
          abandonedAt: now,
          treeSlot: Wish.kClear,
        );
        await _wishes.save(updated);
        await _emit(updated, WishEventKind.abandoned, now);
        _changed();
        return updated;
      });

  Future<Wish> markParentSeen({
    required String id,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(id);
        final Wish updated = wish.copyWith(parentSeenAt: now);
        await _wishes.save(updated);
        _changed();
        return updated;
      });

  /// Progress advance (R11 / R16 / R18). The same session can never be
  /// settled twice; the monotonic clamp protects every rollback path.
  Future<Wish> registerCheckIn({
    required String wishId,
    required CheckIn checkIn,
    required Task task,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(wishId);
        if (wish.isTerminal) return wish;
        if (!hasGoalTarget(wish.targetValue)) return wish;
        final List<CheckIn> existing = await _wishTasks.checkInsOfTaskIds(
          taskIds: <String>[task.id],
        );
        if (checkIn.sessionId != null) {
          for (final CheckIn prior in existing) {
            if (prior.id != checkIn.id && prior.sessionId == checkIn.sessionId) {
              throw StateError('session already used');
            }
          }
        }
        final int delta = progressDeltaOf(
          mode: wish.targetMode,
          task: task,
          checkIn: checkIn,
        );
        if (delta <= 0) return wish;
        final int next = wish.progressValue + delta;
        Wish updated = wish.copyWith(
          progressValue: next < wish.progressValue ? wish.progressValue : next,
        );
        if (fruitStageOf(
                targetValue: updated.targetValue,
                progressValue: updated.progressValue) ==
            WishFruitStage.ripe) {
          updated = _complete(updated, kWishFulfillSourceProgress, now);
        }
        await _wishes.save(updated);
        await _emit(
          updated,
          checkIn.status == CheckInStatus.verified
              ? WishEventKind.taskVerified
              : WishEventKind.taskRejected,
          now,
        );
        _changed();
        return updated;
      });

  /// Direct progress delta used by the settlement bridge. R11 keeps the
  /// value monotonic; R18 routes the ripe check through the single judgement.
  Future<Wish> advanceProgress({
    required String wishId,
    required int delta,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(wishId);
        if (wish.isTerminal || !hasGoalTarget(wish.targetValue)) return wish;
        final int next = wish.progressValue + delta;
        Wish updated = wish.copyWith(
          progressValue: next < wish.progressValue ? wish.progressValue : next,
        );
        if (fruitStageOf(
                targetValue: updated.targetValue,
                progressValue: updated.progressValue) ==
            WishFruitStage.ripe) {
          updated = _complete(updated, kWishFulfillSourceProgress, now);
        }
        await _wishes.save(updated);
        _changed();
        return updated;
      });

  /// Tracking names come from the single constant class (A7.3).
  String _trackingNameOf(WishEventKind kind) {
    switch (kind) {
      case WishEventKind.taskAssigned:
      case WishEventKind.goalSet:
      case WishEventKind.fulfilled:
      case WishEventKind.tagged:
      case WishEventKind.untagged:
      case WishEventKind.taskRejected:
      case WishEventKind.committed:
      case WishEventKind.replaced:
        return TrackingEventNames.wishParentAction;
      case WishEventKind.taskVerified:
        return TrackingEventNames.wishTaskVerified;
      case WishEventKind.abandoned:
        return TrackingEventNames.wishAbandoned;
      case WishEventKind.selfFulfilled:
        return TrackingEventNames.wishFulfilled;
      case WishEventKind.released:
      case WishEventKind.restored:
        return TrackingEventNames.wishTreeOpen;
    }
  }

  Future<void> _emit(
    Wish wish,
    WishEventKind kind,
    DateTime now,
  ) async {
    await _tracking.track(TrackingEvent(
      id: _idFactory(),
      name: _trackingNameOf(kind),
      type: TrackingType.metric,
      ts: now,
      payload: <String, dynamic>{
        'wish_id': wish.id,
        // 🔴 A23.2：事件 id 由单点拼装，孩子端据此与已读集合做差集。
        'kind': kind.name,
        'event_id': wishEventIdOf(wish.id, kind.name, now.millisecondsSinceEpoch),
      },
    ));
  }

  /// Emit a cross-end event for a wish that was completed inside another
  /// service's transaction (A18 R20 focus settlement).
  ///
  /// Progress-driven settlement intentionally emits nothing except the single
  /// `fulfilled` event; callers must not emit `taskVerified` for focus tasks.
  Future<void> emitCrossEndEvent({
    required String wishId,
    required WishEventKind kind,
    required DateTime now,
  }) =>
      _serialized(() async {
        final Wish wish = await _requireWish(wishId);
        await _emit(wish, kind, now);
        _changed();
      });
}
