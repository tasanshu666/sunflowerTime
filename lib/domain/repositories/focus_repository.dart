import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';

/// 专注会话仓储抽象（§2.1）。
abstract class FocusRepository {
  Future<void> saveSession(FocusSession session);
  Future<List<FocusSession>> sessionsOfDay(String dayKey);
  Future<int> countValidFocusDaysLastWeek(DateTime now);

  /// 全量专注统计（累计分钟 / 会话数 / 有效日，§3.3）。M4 打卡领域层聚合用。
  Future<FocusStats> totalStats();
}

/// 专注会话「范围查询」能力接口（专注报告改造 v2 · 热力图 / 月年聚合用）。
///
/// 与 [FocusRepository] **刻意分离**：直接给本体加方法会牵动全仓 57 个
/// `implements FocusRepository`（含 56 个测试桩）编译失败 —— Dart 的 `implements`
/// 语义下，即便新方法带默认实现，实现类仍须显式实现它。
///
/// 真实现 [FocusLocalRepository]（`lib/data/local/repositories/`）同时实现本接口，
/// 消费方通过 `is FocusRangeQuery` **能力探测**使用（先例：`CheckInAdminRepository`，
/// 见 `task_repository.dart:17-23` 的同款纪律注释）：
/// 有本接口 → 一次范围查询后在 Dart 内聚合；无本接口（老桩 / 其它实现）→ 逐日回退。
abstract class FocusRangeQuery {
  /// 半开区间 [from, to) 内全部会话，按 `start` 升序
  /// （同一开始时刻再按 `id` 升序，保证输出确定性）。
  Future<List<FocusSession>> sessionsBetween(DateTime from, DateTime to);
}
