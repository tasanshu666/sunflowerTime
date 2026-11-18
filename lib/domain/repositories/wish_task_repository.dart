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
