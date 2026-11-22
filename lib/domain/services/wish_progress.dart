/// Wish progress model: pure functions only (A18 R1~R20, K26 two-branch rule).
///
/// This file deliberately has no Flutter / drift / IO imports. The only
/// judgement entry that dispatches on [WishGoalMode] is [progressDeltaOf],
/// which has exactly two reachable switch cases and no default.
library wish_progress;

import 'dart:math' as math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';

/// Derived task stage. `notScheduled` is a frozen P1 placeholder and is
/// unreachable in this release. `closed` is the v0.5.1 read-side derivation for
/// tasks belonging to a terminal wish (no column is written).
enum WishTaskStage {
  awaitingVerify,
  done,
  notScheduled,
  pending,
  closed,
}

/// Immutable progress snapshot (pure derivation, never persisted).
class WishProgress {
  final WishGoalMode mode;
  final int targetValue;
  final int progressValue;

  const WishProgress({
    this.mode = WishGoalMode.focusMinutes,
    this.targetValue = 0,
    this.progressValue = 0,
  });

  /// Null when no goal has been set (R6).
  int? get percent => percentOf(
        mode: mode,
        targetValue: targetValue,
        progressValue: progressValue,
      );

  bool get isComputable => hasGoalTarget(targetValue);

  /// Business completion is decided by `wishes.status`, never by this flag;
  /// the flag only describes the numeric goal.
  bool get isComplete => isComputable && progressValue >= targetValue;

  int get remainingValue => isComputable
      ? math.max(0, targetValue - progressValue)
      : 0;

  WishProgress copyWith({
    WishGoalMode? mode,
    int? targetValue,
    int? progressValue,
  }) =>
      WishProgress(
        mode: mode ?? this.mode,
        targetValue: targetValue ?? this.targetValue,
        progressValue: progressValue ?? this.progressValue,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WishProgress &&
          other.mode == mode &&
          other.targetValue == targetValue &&
          other.progressValue == progressValue;

  @override
  int get hashCode => Object.hash(mode, targetValue, progressValue);
}

/// Single source of the "goal is set" judgement (R6 / A36.0 gate 2).
bool hasGoalTarget(int targetValue) => targetValue != 0;

/// True when a focus minute value is valid for settlement.
bool isValidFocusMinutes(int minutes) => minutes >= 0;

/// Progress percentage: `null` when the denominator is zero (R1), otherwise
/// `min(100, floor(progress * 100 / target))`.
int? percentOf({
  required WishGoalMode mode,
  required int targetValue,
  required int progressValue,
}) {
  if (!hasGoalTarget(targetValue)) return null;
  final int raw =
      (progressValue * kWishProgressPercentMax) ~/ targetValue;
  return math.min(kWishProgressPercentMax, raw);
}

/// Fruit stage: pure derivation from exactly two numbers.
WishFruitStage fruitStageOf({
  required int targetValue,
  required int progressValue,
}) {
  if (!hasGoalTarget(targetValue)) return WishFruitStage.none;
  if (progressValue >= targetValue) return WishFruitStage.ripe;
  if (progressValue <= 0) return WishFruitStage.waiting;
  return WishFruitStage.growing;
}

/// Minutes credited by a single check-in in focus-minute mode (R7 / V6):
/// non-focus tasks score zero; focus minutes are floored and capped by the
/// task's `minFocusMin`.
int creditedFocusMinutesOf(Task task, CheckIn checkIn) {
  if (!task.requiresFocus) return 0;
  final int actual = (checkIn.actualFocusMin ?? 0).floor();
  return math.min(actual, task.minFocusMin);
}

/// The ONLY mode-dispatching judgement (K26: exactly two reachable branches,
/// no third case, no default, no silent fallback).
int progressDeltaOf({
  required WishGoalMode mode,
  required Task task,
  required CheckIn checkIn,
}) {
  switch (mode) {
    case WishGoalMode.focusMinutes:
      if (checkIn.status != CheckInStatus.verified) return 0;
      return creditedFocusMinutesOf(task, checkIn);

    case WishGoalMode.taskCount:
      if (checkIn.status != CheckInStatus.verified) return 0;
      return 1;
  }
}

/// Recompute the current completed amount from raw rows. Used by consistency
/// assertions only: the business source of truth remains `progress_value`.
int recomputeProgressValue({
  required WishGoalMode mode,
  required List<Task> tasks,
  required List<CheckIn> checkIns,
}) {
  int total = 0;
  for (final CheckIn c in checkIns) {
    Task? matched;
    for (final Task t in tasks) {
      if (t.id == c.taskId) {
        matched = t;
        break;
      }
    }
    if (matched == null) continue;
    total += progressDeltaOf(mode: mode, task: matched, checkIn: c);
  }
  return total;
}

/// Window key for the repeat rule. `once` uses one constant key (lifetime),
/// `daily` uses the existing `dayKey`, `weekly` uses the existing `weekKey`.
/// All three share the same downstream "window already completed?" check.
String _repeatWindowKeyOf({
  required String? repeatRule,
  required DateTime now,
}) {
  if (repeatRule == 'daily') return dayKey(now);
  if (repeatRule == 'weekly') return weekKey(now);
  return 'once';
}

/// Derived task stage (A19.3). Pending verification always wins; otherwise
/// the repeat window decides between `done` and `pending`. `notScheduled`
/// is never returned in this release.
WishTaskStage wishTaskStageOf({
  required Task task,
  required List<CheckIn> checkIns,
  required DateTime now,
}) {
  final List<CheckIn> own = <CheckIn>[
    for (final CheckIn c in checkIns)
      if (c.taskId == task.id) c,
  ];
  for (final CheckIn c in own) {
    if (c.status == CheckInStatus.pending) return WishTaskStage.awaitingVerify;
  }

  final String windowKey = _repeatWindowKeyOf(
    repeatRule: task.repeatRule,
    now: now,
  );
  for (final CheckIn c in own) {
    if (c.status != CheckInStatus.verified) continue;
    final String completedKey = _repeatWindowKeyOf(
      repeatRule: task.repeatRule,
      now: c.completedAt,
    );
    if (completedKey == windowKey) return WishTaskStage.done;
  }
  return WishTaskStage.pending;
}

/// Fulfilment precondition (R6-P0-01): are **all currently existing** tasks of
/// a wish finished?
///
/// - No tasks at all ⇒ `true` (a wish without growth tasks is never gated).
/// - Every task must derive to [WishTaskStage.done] via the single existing
///   stage judgement [wishTaskStageOf] (once: at least one verified check-in;
///   daily/weekly: a verified check-in in the current repeat window).
/// - Deleted tasks are physically removed from `tasks`, so they are absent
///   from [tasks] and automatically excluded from the judgement.
///
/// Pure and IO-free: the caller owns data fetching. The domain orchestration
/// service uses `WishTaskRepository`; the data-layer transaction uses its own
/// in-transaction queries. Both share this **one** implementation.
bool wishTasksAllDone({
  required List<Task> tasks,
  required List<CheckIn> checkIns,
  required DateTime now,
}) {
  if (tasks.isEmpty) return true;
  return tasks.every(
    (Task task) => wishTaskStageOf(task: task, checkIns: checkIns, now: now) ==
        WishTaskStage.done,
  );
}

/// Collection-box derived visibility (R6-P0-04): should a task be rendered?
///
/// - Ordinary growth task (`wishId == null`) ⇒ always `true` (byte-for-byte
///   unchanged legacy behaviour).
/// - Wish task ⇒ visible only while its parent wish has no `releasedAt`.
///   A missing parent is treated as visible (safe default). Terminal-state
///   greying is a separate concern owned by `effectiveStatusOf`.
bool isWishTaskVisible({
  required Task task,
  required Map<String, Wish> wishById,
}) {
  final String? wishId = task.wishId;
  if (wishId == null) return true;
  final Wish? parent = wishById[wishId];
  return parent == null || parent.releasedAt == null;
}

/// Downward goal change is clamped to the already-completed amount (R4).
int clampedGoalAfterDecrease({
  required int requestedTarget,
  required int progressValue,
}) =>
    math.max(requestedTarget, progressValue);

/// Upward goal change guard (R5 / PRD Q21): the increment must be at most
/// 50% of the old goal AND the new goal at most 3x the completed amount.
bool upscaleAllowed({
  required int oldTarget,
  required int requestedTarget,
  required int progressValue,
}) {
  if (requestedTarget <= oldTarget) return true;
  final int maxByRatio =
      (oldTarget * (1 + kWishTargetUpscaleMaxRatioPerEdit)).floor();
  final int maxByProgress = progressValue * kWishTargetUpscaleMaxFactor;
  final int cap = math.min(maxByRatio, maxByProgress);
  return requestedTarget <= cap;
}
