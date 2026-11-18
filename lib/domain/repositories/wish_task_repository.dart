/// Read-side capability extension for wish-linked tasks and check-ins.
///
/// Kept separate from `TaskRepository` so the 31 existing implementations
/// (including test fakes) do not need to change. The real local task
/// repository implements both interfaces with one mapping path.
library wish_task_repository;

import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/task.dart';

abstract class WishTaskRepository {
  /// All tasks assigned to [wishId] for the current child.
  Future<List<Task>> tasksOfWish({required String wishId});

  /// All check-ins for the given task ids (current child only).
  Future<List<CheckIn>> checkInsOfTaskIds({required List<String> taskIds});

  /// Write side: set `tasks.wish_id` only.
  Future<void> assignWish({required String taskId, required String wishId});

  /// Write side: clear `tasks.wish_id` only.
  Future<void> unassignWish({required String taskId});
}

/// Optional read bridge for wish-linked tasks (A-T03).
///
/// Kept separate from [WishTaskRepository] so existing test fakes implementing
/// that interface stay source-compatible. Injections are optional: when absent
/// the caller silently degrades to the legacy behaviour.
abstract class WishTaskReadBridge {
  /// Look up one wish-linked task by its existing `tasks.id`.
  ///
  /// Returns null when the task is missing, belongs to another child, or is a
  /// plain growth task (`wish_id == null`).
  Future<Task?> wishTaskById(String taskId);

  /// All tasks for the current child, including wish-linked rows.
  ///
  /// Parent-side pending check-ins need this: behaviour-type wish tasks must be
  /// visible for verification even though the daily board filters them out.
  Future<List<Task>> allTasksIncludingWish();
}

/// Optional atomic writer for wish focus settlement (A18 R20 / A16.4-e).
///
/// The single transaction writes both the `check_ins` row and the owning
/// wish's `progress_value` (plus in-transaction fulfilment when ripe), so a
/// failed progress write can never leave a "checked-in but not credited" row.
/// Implementations must be pure data adapters; no Flutter dependency here.
abstract class WishFocusSettlementWriter {
  /// Atomically persist [checkIn] and credit [creditedMinutes] to the wish.
  ///
  /// Returns true when the wish became fulfilled inside this transaction.
  Future<bool> settleWishFocus({
    required String wishId,
    required CheckIn checkIn,
    required int creditedMinutes,
    required DateTime now,
  });
}
