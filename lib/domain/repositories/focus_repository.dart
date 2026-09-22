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
