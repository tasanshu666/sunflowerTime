/// 专注报告领域服务（M3 T04 基线 + 专注报告改造 v2 扩展，§8.3 北极星口径 / §3.3 有效专注日）。
///
/// 纯 Dart、零 Flutter 依赖，可被 `flutter test` 直接单测。依赖接口而非实现。
///
/// 两套能力共存（v2 只增不删）：
///   · [buildReport]：M3 既有「近 7 日 + 近 4 周稳定性」报告，**签名与行为一字未改**
///     （报告页与 56 个既有测试桩依赖它）；
///   · [buildPeriodReport] / [trailingDays] / [heatmapDays]：v2 的「日 / 周 / 月 / 年」
///     半开区间报告与日历热力图，取数走 [FocusRangeQuery] **能力探测**：
///     有则一次范围查询 + Dart 内按日分桶；无则回退逐日 [FocusRepository.sessionsOfDay]，
///     **两条路径输出逐字段等价**（见 `test/m4/focus_report_period_test.dart`）。
///
/// WFD 判定口径与 [PlantGrowthService] / M1/M2 完全一致：
///   actualFocusMin ≥ [kValidFocusMinutes] 且 完成率 ≥ [kCompletionRateThreshold]。
///
/// ⚠️ 既有不一致（本批只记录、不修）：`FocusLocalRepository._isValidSession` 在
/// `plannedMin == 0` 时返回 `0.0`，本服务的 [_isWfd] 返回 `1.0`（无计划时长 = 自由专注，
/// 视为 100% 完成）。**报告一律用 [_isWfd]**，不改动仓储那个私有方法。
library focus_report_service;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/report_period.dart';
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

/// 趋势桶（周 = 7 根日柱 / 月 = 按周 4~5 根 / 年 = 12 根月柱）。
///
/// [start] 含、[end] 不含（半开区间），与所在 [PeriodReport] 同口径。
/// 同一报告内全部桶首尾相接、无缝、恰好铺满 `[PeriodReport.start, PeriodReport.end)`，
/// 故 `buckets.map(focusMinutes).sum == totalFocusMinutes`。
class PeriodBucket {
  /// 桶标签：`周一`…`周日` / `第1周` / `1月`…`12月`。
  final String label;

  /// 桶起点（含）。
  final DateTime start;

  /// 桶终点（不含）。
  final DateTime end;

  /// 桶内累计专注分钟。
  final double focusMinutes;

  const PeriodBucket({
    required this.label,
    required this.start,
    required this.end,
    required this.focusMinutes,
  });
}

/// 单周期报告（专注报告改造 v2 · C76）。
class PeriodReport {
  /// 周期粒度（日 / 周 / 月 / 年）。
  final ReportPeriod period;

  /// 区间起点（含）。
  final DateTime start;

  /// 区间终点（不含）。
  final DateTime end;

  /// 是否为「进行中」周期（区间还没走完）：`end > 今天 00:00 + 1 天`。
  final bool isInProgress;

  /// 区间累计专注分钟。
  final double totalFocusMinutes;

  /// 区间内有效专注日数。
  final int validFocusDays;

  /// 「平均每日」的分母：进行中 = 已过天数（含今天）；历史 = 整区间天数。
  final int dayCount;

  /// 平均每日专注分钟（`totalFocusMinutes / dayCount`，`dayCount <= 0` 时为 0）。
  final double avgFocusMinutesPerDay;

  /// 最好的一天（分钟最多；并列取最早；全区皆 0 → null）。
  final DailyFocusPoint? bestDay;

  /// 区间内逐日序列（升序，**补零值日**，长度 = 区间自然日数）。
  final List<DailyFocusPoint> days;

  /// 趋势桶（规则见 [FocusReportService.buildPeriodReport]）。
  final List<PeriodBucket> buckets;

  /// 区间内最长连续有效专注日。
  final int longestStreak;

  const PeriodReport({
    required this.period,
    required this.start,
    required this.end,
    required this.isInProgress,
    required this.totalFocusMinutes,
    required this.validFocusDays,
    required this.dayCount,
    required this.avgFocusMinutesPerDay,
    required this.bestDay,
    required this.days,
    required this.buckets,
    required this.longestStreak,
  });
}

/// 周内日标签（索引 = `DateTime.weekday - 1`，周一起始）。
const List<String> _kWeekdayLabels = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 专注报告服务（周/日专注分布、有效专注日、稳定性趋势、v2 周期报告）。
class FocusReportService {
  final FocusRepository _focus;

  FocusReportService({required FocusRepository focus}) : _focus = focus;

  /// 构建报告（以 [now] 为基准日）。按日拉取会话聚合，约 28+7 次本地查询，
  /// 仅在进入报告页时触发，非热路径，可接受。
  ///
  /// 🔴 M3 既有能力：**签名与行为一字未改**（报告页与 56 个既有测试桩依赖它）。
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

  /// 构建「日 / 周 / 月 / 年」单周期报告（C76）。
  ///
  /// 取数**只调 [_dailyPoints] 一次**（月 / 年也不逐日多次查询）：有
  /// [FocusRangeQuery] 能力时是一次范围查询，否则是「区间天数」次逐日查询。
  /// 趋势桶由已取到的 [PeriodReport.days] 在内存分组求和，**无额外查询**。
  ///
  /// 分母口径（DR3 拍板）：进行中区间按「已过天数」（含今天），历史区间按「整区间天数」。
  /// [now] 仅用于判定「进行中」与分母，缺省 = `DateTime.now()`（便于测试注入）。
  Future<PeriodReport> buildPeriodReport({
    required ReportPeriod period,
    required DateTime anchor,
    DateTime? now,
  }) async {
    final DateTime start = period.startOf(anchor);
    final DateTime end = period.endOf(anchor);
    final List<DailyFocusPoint> days = await _dailyPoints(start, end);

    final DateTime today = startOfDay(now ?? DateTime.now());
    final bool isInProgress = end.isAfter(today.add(const Duration(days: 1)));

    final int intervalDays = end.difference(start).inDays;
    int dayCount;
    if (isInProgress) {
      int passed = today.difference(start).inDays + 1;
      if (passed < 0) {
        // 区间起点在未来（不该出现，防御性夹取）。
        passed = 0;
      } else if (passed > intervalDays) {
        passed = intervalDays;
      }
      dayCount = passed;
    } else {
      dayCount = intervalDays;
    }

    final double total =
        days.fold(0.0, (double a, DailyFocusPoint p) => a + p.focusMinutes);

    return PeriodReport(
      period: period,
      start: start,
      end: end,
      isInProgress: isInProgress,
      totalFocusMinutes: total,
      validFocusDays: days.where((DailyFocusPoint p) => p.isWfd).length,
      dayCount: dayCount,
      avgFocusMinutesPerDay: dayCount <= 0 ? 0.0 : total / dayCount,
      bestDay: _bestDayOf(days),
      days: days,
      buckets: _bucketsOf(period: period, start: start, end: end, days: days),
      longestStreak: _longestStreakOf(days),
    );
  }

  /// 以 [lastDay] 结尾、向前 [count] 天的逐日序列（升序，含零值日）。
  ///
  /// 日档趋势图用（近 7 日）。[count] <= 0 → 空列表。
  Future<List<DailyFocusPoint>> trailingDays({
    required DateTime lastDay,
    int count = 7,
  }) async {
    if (count <= 0) return <DailyFocusPoint>[];
    final DateTime last = startOfDay(lastDay);
    final DateTime first = DateTime(last.year, last.month, last.day - (count - 1));
    return _dailyPoints(first, DateTime(last.year, last.month, last.day + 1));
  }

  /// 近 [days] 天日历热力图数据（升序，含零值日；末位 = [today] 当天）。
  ///
  /// 与 [trailingDays] 同口径，只是默认窗口为一年（365 天）。
  Future<List<DailyFocusPoint>> heatmapDays({
    required DateTime today,
    int days = 365,
  }) =>
      trailingDays(lastDay: today, count: days);

  // ─────────────────────────────────────────────────────────────────────────
  // 取数：快路径（范围查询）/ 回退路径（逐日）
  // ─────────────────────────────────────────────────────────────────────────

  /// 逐日聚合（升序、含零值日）。半开区间 [from, to)：两者都应是**日边界**。
  ///
  /// 两条路径输出**逐字段等价**（`dayKey` / `date` / `focusMinutes` /
  /// `sessionCount` / `isWfd`）：
  ///  · **快路径**（`_focus is FocusRangeQuery`）：1 次 [FocusRangeQuery.sessionsBetween]，
  ///    在 Dart 内按 `dayKey(start)` 分桶；分区 [from, to) 由整日拼成，
  ///    故「某日全部会话」与 [FocusRepository.sessionsOfDay] 的取数集合完全相同；
  ///  · **回退路径**：逐日 [FocusRepository.sessionsOfDay]（既有能力，零改动兼容）。
  ///
  /// `focusMinutes` 求和口径与 [buildReport] 一致（直接累加 `actualFocusMin`）；
  /// `isWfd` = 当日任一会话满足 [_isWfd]。
  Future<List<DailyFocusPoint>> _dailyPoints(DateTime from, DateTime to) async {
    final DateTime firstDay = startOfDay(from);
    final List<DateTime> days = <DateTime>[];
    for (DateTime d = firstDay;
        d.isBefore(to);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    if (days.isEmpty) return <DailyFocusPoint>[];

    if (_focus is FocusRangeQuery) {
      final List<FocusSession> sessions =
          await (_focus as FocusRangeQuery).sessionsBetween(firstDay, to);
      final Map<String, List<FocusSession>> byDay =
          <String, List<FocusSession>>{};
      for (final FocusSession s in sessions) {
        byDay.putIfAbsent(dayKey(s.start), () => <FocusSession>[]).add(s);
      }
      final List<DailyFocusPoint> points = <DailyFocusPoint>[];
      for (final DateTime d in days) {
        points.add(_pointOf(d, byDay[dayKey(d)] ?? const <FocusSession>[]));
      }
      return points;
    }

    final List<DailyFocusPoint> points = <DailyFocusPoint>[];
    for (final DateTime d in days) {
      final List<FocusSession> sessions = await _focus.sessionsOfDay(dayKey(d));
      points.add(_pointOf(d, sessions));
    }
    return points;
  }

  /// 把「某日 + 该日会话」压成一个 [DailyFocusPoint]（两条取数路径共用同一口径）。
  DailyFocusPoint _pointOf(DateTime day, List<FocusSession> sessions) {
    final double mins =
        sessions.fold(0.0, (double a, FocusSession s) => a + s.actualFocusMin);
    return DailyFocusPoint(
      dayKey: dayKey(day),
      date: day,
      focusMinutes: mins,
      sessionCount: sessions.length,
      isWfd: sessions.any(_isWfd),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 派生指标
  // ─────────────────────────────────────────────────────────────────────────

  /// 最好的一天：分钟最多者；并列取**最早**（[days] 已升序，严格大于才替换）；
  /// 全区皆 0（或空）→ null。
  static DailyFocusPoint? _bestDayOf(List<DailyFocusPoint> days) {
    DailyFocusPoint? best;
    for (final DailyFocusPoint d in days) {
      if (d.focusMinutes <= 0) continue;
      if (best == null || d.focusMinutes > best.focusMinutes) best = d;
    }
    return best;
  }

  /// 区间内最长连续有效专注日（单次扫描，断一天即归零）。
  static int _longestStreakOf(List<DailyFocusPoint> days) {
    int longest = 0;
    int current = 0;
    for (final DailyFocusPoint d in days) {
      if (d.isWfd) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  }

  /// 趋势桶（规则见 [buildPeriodReport] 文档）。
  ///
  /// 不变式：`buckets` 首尾相接、无缝隙、恰好铺满 `[start, end)`，故
  /// `Σbuckets.focusMinutes == totalFocusMinutes`（前提 [days] 覆盖同一区间）。
  List<PeriodBucket> _bucketsOf({
    required ReportPeriod period,
    required DateTime start,
    required DateTime end,
    required List<DailyFocusPoint> days,
  }) {
    // 逐日分钟索引（桶分组求和用；日期键与 days 完全一致）。
    final Map<String, double> minutesOfDay = <String, double>{};
    for (final DailyFocusPoint d in days) {
      minutesOfDay[d.dayKey] = d.focusMinutes;
    }

    switch (period) {
      case ReportPeriod.day:
        // 日档不画趋势桶（UI 用 trailingDays 的近 7 日序列）。
        return <PeriodBucket>[];
      case ReportPeriod.week:
        // 7 根日柱：周一…周日（label 由日期自身 weekday 派生，不依赖下标巧合）。
        final List<PeriodBucket> weekBuckets = <PeriodBucket>[];
        for (int i = 0; i < 7; i++) {
          final DateTime d = DateTime(start.year, start.month, start.day + i);
          final DateTime next = DateTime(d.year, d.month, d.day + 1);
          weekBuckets.add(PeriodBucket(
            label: _kWeekdayLabels[d.weekday - 1],
            start: d,
            end: next,
            focusMinutes: minutesOfDay[dayKey(d)] ?? 0.0,
          ));
        }
        return weekBuckets;
      case ReportPeriod.month:
        // 按周分组（**周一起始**切，首 / 末桶可不足 7 天）→ 自然月内 4~5 根。
        final List<PeriodBucket> monthBuckets = <PeriodBucket>[];
        DateTime cursor = start;
        while (cursor.isBefore(end)) {
          final DateTime weekStart = startOfWeek(cursor);
          DateTime bucketEnd =
              DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
          if (bucketEnd.isAfter(end)) bucketEnd = end;
          double sum = 0.0;
          for (DateTime d = cursor;
              d.isBefore(bucketEnd);
              d = DateTime(d.year, d.month, d.day + 1)) {
            sum += minutesOfDay[dayKey(d)] ?? 0.0;
          }
          monthBuckets.add(PeriodBucket(
            label: '第${monthBuckets.length + 1}周',
            start: cursor,
            end: bucketEnd,
            focusMinutes: sum,
          ));
          cursor = bucketEnd;
        }
        return monthBuckets;
      case ReportPeriod.year:
        // 12 根月柱：`1月`…`12月`，起止用自然月边界（跨年时 end 归一化到次年 1 月 1 日）。
        final List<PeriodBucket> yearBuckets = <PeriodBucket>[];
        for (int m = 1; m <= 12; m++) {
          final DateTime monthStart = DateTime(start.year, m, 1);
          final DateTime monthEnd = DateTime(start.year, m + 1, 1);
          double sum = 0.0;
          for (DateTime d = monthStart;
              d.isBefore(monthEnd);
              d = DateTime(d.year, d.month, d.day + 1)) {
            sum += minutesOfDay[dayKey(d)] ?? 0.0;
          }
          yearBuckets.add(PeriodBucket(
            label: '$m月',
            start: monthStart,
            end: monthEnd,
            focusMinutes: sum,
          ));
        }
        return yearBuckets;
    }
  }

  /// 有效专注日判定（与 plant_growth_service / M1·M2 口径一致）。
  static bool _isWfd(FocusSession s) {
    if (s.actualFocusMin < kValidFocusMinutes) return false;
    final double completion =
        s.plannedMin == 0 ? 1.0 : s.actualFocusMin / s.plannedMin;
    return completion >= kCompletionRateThreshold;
  }
}
