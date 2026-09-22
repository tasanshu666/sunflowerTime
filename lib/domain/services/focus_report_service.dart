/// 专注报告领域服务（M3 T04，§8.3 北极星口径 / §3.3 有效专注日）。
///
/// 纯 Dart、零 Flutter 依赖，可被 `flutter test` 直接单测。依赖接口而非实现。
/// 复用 [FocusRepository.sessionsOfDay] 按日聚合（不改仓储接口，避免动到 M2 测试桩），
/// WFD 判定口径与 [PlantGrowthService] / M1/M2 完全一致：
///   actualFocusMin ≥ [kValidFocusMinutes] 且 完成率 ≥ [kCompletionRateThreshold]。
library focus_report_service;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';

/// 单日专注聚合点（用于 7 日分布图与稳定性趋势）。
class DailyFocusPoint {
  final String dayKey;
  final DateTime date;
  final double focusMinutes; // 当日累计有效专注分钟
  final int sessionCount; // 当日专注场次
  final bool isWfd; // 当日是否构成有效专注日

  const DailyFocusPoint({
    required this.dayKey,
    required this.date,
    required this.focusMinutes,
    required this.sessionCount,
    required this.isWfd,
  });
}

/// 专注报告聚合结果（本地计算，无需远端）。
class FocusReport {
  final DateTime generatedAt;
  final List<DailyFocusPoint> last7Days; // 近 7 日，升序（旧→新）
  final double weeklyFocusMinutes; // 近 7 日累计专注分钟
  final int validFocusDaysLast7; // 近 7 日有效专注日数（0–7）
  final double stabilityScore; // 稳定性 0..1（近 4 周有效专注日占比均值）
  final List<int> weeklyValidDayTrend; // 近 4 周各周有效专注日数（旧→新）

  const FocusReport({
    required this.generatedAt,
    required this.last7Days,
    required this.weeklyFocusMinutes,
    required this.validFocusDaysLast7,
    required this.stabilityScore,
    required this.weeklyValidDayTrend,
  });
}

/// 专注报告服务（周/日专注分布、有效专注日、稳定性趋势）。
class FocusReportService {
  final FocusRepository _focus;

  FocusReportService({required FocusRepository focus}) : _focus = focus;

  /// 构建报告（以 [now] 为基准日）。按日拉取会话聚合，约 28+7 次本地查询，
  /// 仅在进入报告页时触发，非热路径，可接受。
  Future<FocusReport> buildReport(DateTime now) async {
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 近 7 日分布（旧→新）。
    final List<DailyFocusPoint> last7Days = <DailyFocusPoint>[];
    for (int i = 6; i >= 0; i--) {
      final DateTime d = today.subtract(Duration(days: i));
      final List<FocusSession> sessions = await _focus.sessionsOfDay(dayKey(d));
      final double mins =
          sessions.fold(0.0, (double a, FocusSession s) => a + s.actualFocusMin);
      final bool wfd = sessions.any(_isWfd);
      last7Days.add(DailyFocusPoint(
        dayKey: dayKey(d),
        date: d,
        focusMinutes: mins,
        sessionCount: sessions.length,
        isWfd: wfd,
      ));
    }

    final double weeklyFocusMinutes =
        last7Days.fold(0.0, (double a, DailyFocusPoint p) => a + p.focusMinutes);
    final int validFocusDaysLast7 =
        last7Days.where((DailyFocusPoint p) => p.isWfd).length;

    // 近 4 周各周有效专注日数（每周 7 天，旧→新）。
    final List<int> weeklyValidDayTrend = <int>[];
    for (int w = 3; w >= 0; w--) {
      int count = 0;
      for (int i = 0; i < 7; i++) {
        final DateTime d = today.subtract(Duration(days: w * 7 + i));
        final List<FocusSession> sessions =
            await _focus.sessionsOfDay(dayKey(d));
        if (sessions.any(_isWfd)) count++;
      }
      weeklyValidDayTrend.add(count);
    }

    final double stabilityScore = weeklyValidDayTrend.isEmpty
        ? 0.0
        : weeklyValidDayTrend.reduce((int a, int b) => a + b) /
            (weeklyValidDayTrend.length * 7);

    return FocusReport(
      generatedAt: now,
      last7Days: last7Days,
      weeklyFocusMinutes: weeklyFocusMinutes,
      validFocusDaysLast7: validFocusDaysLast7,
      stabilityScore: stabilityScore,
      weeklyValidDayTrend: weeklyValidDayTrend,
    );
  }

  /// 有效专注日判定（与 plant_growth_service / M1·M2 口径一致）。
  static bool _isWfd(FocusSession s) {
    if (s.actualFocusMin < kValidFocusMinutes) return false;
    final double completion =
        s.plannedMin == 0 ? 1.0 : s.actualFocusMin / s.plannedMin;
    return completion >= kCompletionRateThreshold;
  }
}
