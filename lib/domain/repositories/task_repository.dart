import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';

/// 任务/打卡仓储抽象（§2.1 / §3.1）。
abstract class TaskRepository {
  Future<List<Task>> tasks();
  Future<void> saveTask(Task task);
  Future<void> checkIn(CheckIn checkIn);
  Future<List<CheckIn>> checkInsOfDay(String dayKey);
}
