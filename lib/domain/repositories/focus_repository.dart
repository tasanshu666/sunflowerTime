import 'package:sunflower_time/domain/entities/focus_session.dart';

/// 专注会话仓储抽象（§2.1）。
abstract class FocusRepository {
  Future<void> saveSession(FocusSession session);
  Future<List<FocusSession>> sessionsOfDay(String dayKey);
  Future<int> countValidFocusDaysLastWeek(DateTime now);
}
