import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';

/// 任务/打卡仓储抽象（§2.1 / §3.1）。
abstract class TaskRepository {
  Future<List<Task>> tasks();
  Future<void> saveTask(Task task);
  Future<void> deleteTaskById(String id);
  Future<void> checkIn(CheckIn checkIn);
  Future<List<CheckIn>> checkInsOfDay(String dayKey);

  /// 累计打卡次数（全部任务、全历史，§3.3）。M4 打卡领域层聚合用。
  Future<int> totalCheckInCount();
}

/// 打卡核销（家长端）能力扩展接口（M4）。
///
/// 与 [TaskRepository] **刻意分离**：若把下列方法直接加到 [TaskRepository]，
/// 则所有 `implements TaskRepository` 的实现者（含测试里的轻量 Fake）都必须
/// 跟进实现，牵动面大。真实实现 [TaskLocalRepository] 同时实现本接口；
/// [TaskCheckInService] 通过能力探测（`is CheckInAdminRepository`）使用，
/// 仅家长端核销路径需要它。
abstract class CheckInAdminRepository {
  /// 按主键读取单条打卡；不存在返回 null。
  Future<CheckIn?> checkInById(String id);

  /// 指定核销状态的打卡，按 completedAt 升序（家长端待核销列表用）。
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status);

  /// 插入或更新打卡记录（家长核销 / 驳回写回，按主键冲突合并）。
  Future<void> updateCheckIn(CheckIn checkIn);

  /// CAS 写回核销结果：**仅当记录仍是 [from] 状态**时生效。
  /// 返回 true = 本次抢占成功（调用方**才可**入账）；false = 已被并发处理，调用方必须放弃入账。
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  });
}
