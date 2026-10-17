/// 专注报告改造 v2 · 数据层单测（C76 周期口径 / 聚合 / 快慢路径等价性）。
///
/// 覆盖：
///  1. 周期边界（半开区间 / 周一起始 / 闰年 / `_mondayOf` 复用后 `weekKey` 不变）；
///  2. 聚合（累计分钟 / 有效专注日 / 平均每日 / 最好的一天 / 最长连续）；
///  3. 进行中 vs 历史的分母口径（DR3）；
///  4. 趋势桶（日空 / 周 7 根 / 月 4~5 根无缝 / 年 12 根求和一致）；
///  5. 🔴 快路径（[FocusRangeQuery]）与回退路径（逐日）**逐字段等价** + 查询次数证据；
///  6. `heatmapDays` / `trailingDays` 窗口与零值补位；
///  7. 守卫：`FocusRepository` 本体未加方法（能力接口独立）。
///
/// 同时回归 `buildReport`（M3 既有能力，签名与行为一字未改）。
library focus_report_period_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/report_period.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';

// ───────────────────────────────────────────────────────────────────────────
// 测试夹具
// ───────────────────────────────────────────────────────────────────────────

/// 构造一条专注会话（默认「计划 30 分钟且实际做满」= 有效专注）。
FocusSession _s(
  String id,
  DateTime start, {
  int plannedMin = 30,
  double actualFocusMin = 30,
}) {
  return FocusSession(
    id: id,
    start: start,
    end: start.add(Duration(minutes: actualFocusMin.round())),
    plannedMin: plannedMin,
    actualFocusMin: actualFocusMin,
    status: FocusStatus.completed,
    sunlightEarned: actualFocusMin,
    createdAt: start,
  );
}

/// 解析 `yyyy-MM-dd` 为当日 0 点（与仓储 `_parseDay` 同语义）。
DateTime _parseDayKey(String key) {
  final List<String> parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// 会话排序：`start` 升序，同刻再按 `id` 升序（与 `sessionsBetween` 契约一致）。
int _byStartThenId(FocusSession a, FocusSession b) {
  final int byStart = a.start.compareTo(b.start);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}

/// 内存专注仓储 —— **只实现 [FocusRepository]**（= 全仓 56 个既有测试桩的形态），
/// 用于验证「无范围查询能力」时的逐日回退路径。
class _MemRepo implements FocusRepository {
  _MemRepo(this.sessions);

  final List<FocusSession> sessions;

  /// `sessionsOfDay` 调用计数（回退路径查询次数证据）。
  int sessionsOfDayCalls = 0;

  /// `sessionsBetween` 调用计数（本类不实现该能力，恒为 0）。
  int sessionsBetweenCalls = 0;

  @override
  Future<void> saveSession(FocusSession session) async {
    sessions.add(session);
  }

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async {
    sessionsOfDayCalls++;
    final DateTime dayStart = _parseDayKey(dayKey);
    final DateTime dayEnd =
        DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    return sessions
        .where((FocusSession s) =>
            !s.start.isBefore(dayStart) && s.start.isBefore(dayEnd))
        .toList()
      ..sort(_byStartThenId);
  }

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async {
    final DateTime from = startOfDay(now).subtract(const Duration(days: 6));
    final DateTime to = startOfDay(now).add(const Duration(days: 1));
    final Set<String> days = <String>{};
    for (final FocusSession s in sessions) {
      if (s.start.isBefore(from) || !s.start.isBefore(to)) continue;
      if (s.actualFocusMin >= 15) days.add(dayKey(s.start));
    }
    return days.length;
  }

  @override
  Future<FocusStats> totalStats() async => FocusStats(
        totalFocusMinutes: sessions.fold(
            0.0, (double a, FocusSession s) => a + s.actualFocusMin),
        totalSessions: sessions.length,
        totalValidDays: sessions.map((FocusSession s) => dayKey(s.start)).toSet().length,
      );
}

/// 内存专注仓储 —— **同时实现 [FocusRangeQuery]**（= 真实现 `FocusLocalRepository`
/// 的形态），用于验证快路径「1 次范围查询 + Dart 内分桶」。
class _MemRangeRepo extends _MemRepo implements FocusRangeQuery {
  _MemRangeRepo(super.sessions);

  @override
  Future<List<FocusSession>> sessionsBetween(DateTime from, DateTime to) async {
    sessionsBetweenCalls++;
    return sessions
        .where((FocusSession s) =>
            !s.start.isBefore(from) && s.start.isBefore(to))
        .toList()
      ..sort(_byStartThenId);
  }
}

/// 2026-10 主数据集（含 1 日两场 / 无效场次 / 连续有效日），并**刻意**放入
/// 上月最后一秒与次月第一秒，用于验证半开区间边界不串月。
///
/// 逐日分钟：10-01=40 · 10-02=5 · 10-03=20 · 10-04=40 · 10-05=40 · 10-06=60 ·
/// 10-07=5 · 10-08=15 · 10-09=20，其余为 0 → 月累计 **245**。
/// 有效专注日（`_isWfd`）：10-01 / 04 / 05 / 06 / 08 / 09 = **6** 天，最长连续 **3**。
List<FocusSession> _octoberDataset() => <FocusSession>[
      // ── 边界外：上月最后一秒 / 次月第一秒（都不该进 2026-10）──
      _s('edge-prev', DateTime(2026, 9, 30, 23, 59, 59), plannedMin: 100, actualFocusMin: 100),
      _s('edge-next', DateTime(2026, 11, 1), plannedMin: 100, actualFocusMin: 100),
      // ── 10-01：两场，日累计 40，WFD ──
      _s('a1', DateTime(2026, 10, 1, 9), plannedMin: 30, actualFocusMin: 30),
      _s('a2', DateTime(2026, 10, 1, 20), plannedMin: 30, actualFocusMin: 10),
      // ── 10-02：5 分钟 < 15 → 非 WFD ──
      _s('b1', DateTime(2026, 10, 2, 9), plannedMin: 30, actualFocusMin: 5),
      // ── 10-03：20/30 完成率 0.667 < 0.9 → 非 WFD ──
      _s('c1', DateTime(2026, 10, 3, 9), plannedMin: 30, actualFocusMin: 20),
      // ── 10-04 ~ 10-06：连续 3 天 WFD ──
      _s('d1', DateTime(2026, 10, 4, 9), plannedMin: 40, actualFocusMin: 40),
      _s('e1', DateTime(2026, 10, 5, 9), plannedMin: 40, actualFocusMin: 40),
      _s('f1', DateTime(2026, 10, 6, 9), plannedMin: 60, actualFocusMin: 60),
      // ── 10-07：5 分钟 → 断档（最长连续因此 = 3）──
      _s('g1', DateTime(2026, 10, 7, 9), plannedMin: 30, actualFocusMin: 5),
      // ── 10-08 ~ 10-09：再连续 2 天 ──
      _s('h1', DateTime(2026, 10, 8, 9), plannedMin: 15, actualFocusMin: 15),
      _s('i1', DateTime(2026, 10, 9, 9), plannedMin: 20, actualFocusMin: 20),
    ];

/// 逐字段比较两份 [PeriodReport]（等价性断言的唯一入口，避免漏比字段）。
void _expectReportsEqual(PeriodReport a, PeriodReport b, String tag) {
  expect(a.period, b.period, reason: '$tag.period');
  expect(a.start, b.start, reason: '$tag.start');
  expect(a.end, b.end, reason: '$tag.end');
  expect(a.isInProgress, b.isInProgress, reason: '$tag.isInProgress');
  expect(a.totalFocusMinutes, b.totalFocusMinutes, reason: '$tag.total');
  expect(a.validFocusDays, b.validFocusDays, reason: '$tag.validFocusDays');
  expect(a.dayCount, b.dayCount, reason: '$tag.dayCount');
  expect(a.avgFocusMinutesPerDay, b.avgFocusMinutesPerDay, reason: '$tag.avg');
  expect(a.longestStreak, b.longestStreak, reason: '$tag.longestStreak');
  expect(a.days.length, b.days.length, reason: '$tag.days.length');
  for (int i = 0; i < a.days.length; i++) {
    expect(a.days[i].dayKey, b.days[i].dayKey, reason: '$tag.days[$i].dayKey');
    expect(a.days[i].date, b.days[i].date, reason: '$tag.days[$i].date');
    expect(a.days[i].focusMinutes, b.days[i].focusMinutes,
        reason: '$tag.days[$i].focusMinutes');
    expect(a.days[i].sessionCount, b.days[i].sessionCount,
        reason: '$tag.days[$i].sessionCount');
    expect(a.days[i].isWfd, b.days[i].isWfd, reason: '$tag.days[$i].isWfd');
  }
  expect(a.bestDay?.dayKey, b.bestDay?.dayKey, reason: '$tag.bestDay.dayKey');
  expect(a.bestDay?.focusMinutes, b.bestDay?.focusMinutes,
      reason: '$tag.bestDay.focusMinutes');
  expect(a.buckets.length, b.buckets.length, reason: '$tag.buckets.length');
  for (int i = 0; i < a.buckets.length; i++) {
    expect(a.buckets[i].label, b.buckets[i].label, reason: '$tag.buckets[$i].label');
    expect(a.buckets[i].start, b.buckets[i].start, reason: '$tag.buckets[$i].start');
    expect(a.buckets[i].end, b.buckets[i].end, reason: '$tag.buckets[$i].end');
    expect(a.buckets[i].focusMinutes, b.buckets[i].focusMinutes,
        reason: '$tag.buckets[$i].focusMinutes');
  }
}

/// 逐字段比较两份 [DailyFocusPoint] 序列。
void _expectPointsEqual(
    List<DailyFocusPoint> a, List<DailyFocusPoint> b, String tag) {
  expect(a.length, b.length, reason: '$tag.length');
  for (int i = 0; i < a.length; i++) {
    expect(a[i].dayKey, b[i].dayKey, reason: '$tag[$i].dayKey');
    expect(a[i].date, b[i].date, reason: '$tag[$i].date');
    expect(a[i].focusMinutes, b[i].focusMinutes, reason: '$tag[$i].focusMinutes');
    expect(a[i].sessionCount, b[i].sessionCount, reason: '$tag[$i].sessionCount');
    expect(a[i].isWfd, b[i].isWfd, reason: '$tag[$i].isWfd');
  }
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // 1. 周期边界（半开区间 / 周一起始 / 闰年）
  // ═════════════════════════════════════════════════════════════════════════
  group('周期边界', () {
    test('月：含 1 日 00:00、不含次月 1 日（10-31 23:59 属本月，11-01 00:00 不属）', () {
      final DateTime anchor = DateTime(2026, 10, 31, 23, 59);
      final DateTime start = ReportPeriod.month.startOf(anchor);
      final DateTime end = ReportPeriod.month.endOf(anchor);

      expect(start, DateTime(2026, 10, 1));
      expect(end, DateTime(2026, 11, 1));
      // 10-31 23:59 落在 [start, end) 内
      expect(anchor.isBefore(start), isFalse);
      expect(anchor.isBefore(end), isTrue);
      // 11-01 00:00 不落在区间内（半开区间上界不含）
      expect(DateTime(2026, 11, 1).isBefore(end), isFalse);
      // 月末次日 0 点回落到下个月
      expect(ReportPeriod.month.startOf(DateTime(2026, 11, 1)),
          DateTime(2026, 11, 1));
    });

    test('年：含 1 月 1 日、不含次年 1 月 1 日', () {
      final DateTime anchor = DateTime(2026, 12, 31, 23, 59);
      final DateTime start = ReportPeriod.year.startOf(anchor);
      final DateTime end = ReportPeriod.year.endOf(anchor);

      expect(start, DateTime(2026, 1, 1));
      expect(end, DateTime(2027, 1, 1));
      expect(DateTime(2026, 1, 1).isBefore(start), isFalse);
      expect(DateTime(2027, 1, 1).isBefore(end), isFalse);
      expect(DateTime(2026, 12, 31, 23, 59).isBefore(end), isTrue);
    });

    test('年（C89 闰年 2028）：含 2 月 29 日与 12 月 31 日，不含 2029-01-01', () {
      // 🔴 锚点故意落在闰年：若把年终点改回 `Duration(days: 365)` 定长推算，
      // end = 2028-12-31 → 12-31 23:59 不再早于 end，本例必红。
      final DateTime anchor = DateTime(2028, 12, 31, 23, 59);
      final DateTime start = ReportPeriod.year.startOf(anchor);
      final DateTime end = ReportPeriod.year.endOf(anchor);

      expect(start, DateTime(2028, 1, 1));
      expect(end, DateTime(2029, 1, 1));
      expect(DateTime(2028, 2, 29).isBefore(end), isTrue);
      expect(DateTime(2028, 12, 31, 23, 59).isBefore(end), isTrue);
      expect(DateTime(2029, 1, 1).isBefore(end), isFalse);
    });

    test('周：周一为始；周日锚点回落到本周一（C55）', () {
      final DateTime sunday = DateTime(2026, 10, 4, 18, 30);
      expect(sunday.weekday, DateTime.sunday);

      final DateTime start = ReportPeriod.week.startOf(sunday);
      expect(start, DateTime(2026, 9, 28));
      expect(start.weekday, DateTime.monday);
      expect(ReportPeriod.week.endOf(sunday), DateTime(2026, 10, 5));

      // 同一周内任意锚点得到同一区间
      expect(ReportPeriod.week.startOf(DateTime(2026, 9, 28, 0, 0)), start);
      expect(ReportPeriod.week.startOf(DateTime(2026, 9, 30, 8, 0)), start);
      expect(ReportPeriod.week.startOf(DateTime(2026, 10, 4, 23, 59)), start);
    });

    test('闰年：2024-02-29 归 2024-02；2023-03-01 归 2023-03 不串月', () {
      expect(ReportPeriod.month.startOf(DateTime(2024, 2, 29)),
          DateTime(2024, 2, 1));
      expect(ReportPeriod.month.endOf(DateTime(2024, 2, 29)),
          DateTime(2024, 3, 1));
      // 2024-02 = 29 天，2023-02 = 28 天（禁止 Duration(days: 30) 的直接证据）
      expect(
          ReportPeriod.month
              .endOf(DateTime(2024, 2, 10))
              .difference(DateTime(2024, 2, 1))
              .inDays,
          29);
      expect(
          ReportPeriod.month
              .endOf(DateTime(2023, 2, 10))
              .difference(DateTime(2023, 2, 1))
              .inDays,
          28);
      // 2023-03-01 属 2023-03，不属 2023-02
      expect(ReportPeriod.month.startOf(DateTime(2023, 3, 1)),
          DateTime(2023, 3, 1));
      expect(ReportPeriod.month.endOf(DateTime(2023, 3, 1)),
          DateTime(2023, 4, 1));
      // 闰年整年 366 天
      expect(
          ReportPeriod.year
              .endOf(DateTime(2024, 6, 1))
              .difference(DateTime(2024, 1, 1))
              .inDays,
          366);
    });

    test('core 纯函数：startOfDay / startOfWeek / startOfMonth / startOfYear', () {
      final DateTime t = DateTime(2026, 10, 17, 13, 45, 30);
      expect(startOfDay(t), DateTime(2026, 10, 17));
      expect(startOfWeek(t), DateTime(2026, 10, 12));
      expect(startOfMonth(t), DateTime(2026, 10, 1));
      expect(startOfYear(t), DateTime(2026, 1, 1));
    });

    test('_mondayOf 复用 startOfWeek 后 weekKey / previousWeekKey 结果不变', () {
      // 2026-09-07 与 2026-08-31 都是周一（文档示例值，改动前后必须一致）
      expect(weekKey(DateTime(2026, 9, 7)), '2026-09-07');
      expect(weekKey(DateTime(2026, 9, 13, 23, 59)), '2026-09-07'); // 周日 → 周一
      expect(weekKey(DateTime(2026, 10, 4, 18)), '2026-09-28');
      expect(previousWeekKey(DateTime(2026, 9, 7)), '2026-08-31');
      expect(previousWeekKey(DateTime(2026, 10, 4)), '2026-09-21');
      // 与 startOfWeek 逐日对齐（消除孪生后的等价性）
      for (int i = 0; i < 21; i++) {
        final DateTime d = DateTime(2026, 9, 1 + i, 7, 15);
        expect(weekKey(d), dayKey(startOfWeek(d)), reason: 'dayKey($d)');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2. 聚合指标（月）
  // ═════════════════════════════════════════════════════════════════════════
  group('月聚合', () {
    test('累计分钟 / 有效专注日 / 平均每日 / 最好的一天 / 最长连续 / 补零', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(_octoberDataset()));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 1),
        now: DateTime(2026, 10, 31, 23, 59),
      );

      expect(report.start, DateTime(2026, 10, 1));
      expect(report.end, DateTime(2026, 11, 1));
      expect(report.isInProgress, isFalse);
      // 区间逐日补零：整月 31 天
      expect(report.days.length, 31);
      expect(report.days.first.dayKey, '2026-10-01');
      expect(report.days.last.dayKey, '2026-10-31');

      // 边界会话不进本月：245 = 40+5+20+40+40+60+5+15+20
      expect(report.totalFocusMinutes, 245);
      expect(report.validFocusDays, 6);
      expect(report.dayCount, 31);
      expect(report.avgFocusMinutesPerDay, closeTo(245 / 31, 1e-9));
      expect(report.longestStreak, 3); // 10-04 / 05 / 06
      expect(report.bestDay, isNotNull);
      expect(report.bestDay!.dayKey, '2026-10-06');
      expect(report.bestDay!.focusMinutes, 60);

      // 单日细节：10-01 两场共 40 分钟且构成 WFD
      final DailyFocusPoint oct1 = report.days.first;
      expect(oct1.focusMinutes, 40);
      expect(oct1.sessionCount, 2);
      expect(oct1.isWfd, isTrue);

      // 无效场次日：有分钟但不是 WFD
      final DailyFocusPoint oct2 = report.days[1];
      expect(oct2.focusMinutes, 5);
      expect(oct2.sessionCount, 1);
      expect(oct2.isWfd, isFalse);

      final DailyFocusPoint oct3 = report.days[2];
      expect(oct3.focusMinutes, 20);
      expect(oct3.isWfd, isFalse); // 20/30 = 0.667 < 0.9

      // 无数据日补零
      final DailyFocusPoint oct20 = report.days[19];
      expect(oct20.dayKey, '2026-10-20');
      expect(oct20.focusMinutes, 0);
      expect(oct20.sessionCount, 0);
      expect(oct20.isWfd, isFalse);

      // 逐日升序且 dates 为当日 0 点
      for (int i = 0; i < report.days.length; i++) {
        expect(report.days[i].date, DateTime(2026, 10, 1 + i));
        expect(report.days[i].dayKey, dayKey(DateTime(2026, 10, 1 + i)));
      }
    });

    test('bestDay：并列取最早', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('x1', DateTime(2026, 11, 3, 9), plannedMin: 40, actualFocusMin: 40),
          _s('x2', DateTime(2026, 11, 7, 9), plannedMin: 40, actualFocusMin: 40),
          _s('x3', DateTime(2026, 11, 9, 9), plannedMin: 10, actualFocusMin: 10),
        ]),
      );
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 11, 1),
        now: DateTime(2026, 11, 30),
      );

      expect(report.totalFocusMinutes, 90);
      expect(report.bestDay!.dayKey, '2026-11-03'); // 与 11-07 并列 40 → 取最早
    });

    test('bestDay：全区为 0 → null；各项指标归零', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(<FocusSession>[]));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 1),
        now: DateTime(2026, 10, 31),
      );

      expect(report.days.length, 31);
      expect(report.totalFocusMinutes, 0);
      expect(report.validFocusDays, 0);
      expect(report.longestStreak, 0);
      expect(report.bestDay, isNull);
      expect(report.avgFocusMinutesPerDay, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 3. 进行中 vs 历史的分母口径（DR3）
  // ═════════════════════════════════════════════════════════════════════════
  group('平均每日分母', () {
    test('进行中：now=2026-10-17 / 10 月 → dayCount == 17', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('p1', DateTime(2026, 10, 1, 9), plannedMin: 60, actualFocusMin: 60),
        ]),
      );
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 1),
        now: DateTime(2026, 10, 17, 9, 30),
      );

      expect(report.isInProgress, isTrue);
      expect(report.dayCount, 17);
      expect(report.totalFocusMinutes, 60);
      expect(report.avgFocusMinutesPerDay, closeTo(60 / 17, 1e-9));
      // 逐日序列仍补满整月（趋势图需要完整横轴）
      expect(report.days.length, 31);
    });

    test('历史：anchor=2020-10-01 → dayCount == 31', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('q1', DateTime(2020, 10, 10, 9), plannedMin: 62, actualFocusMin: 62),
        ]),
      );
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2020, 10, 1),
        now: DateTime(2026, 10, 17),
      );

      expect(report.isInProgress, isFalse);
      expect(report.dayCount, 31);
      expect(report.totalFocusMinutes, 62);
      expect(report.avgFocusMinutesPerDay, closeTo(62 / 31, 1e-9));
    });

    test('区间起点在未来 → dayCount 夹到 0、平均为 0', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(<FocusSession>[]));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 12, 1),
        now: DateTime(2026, 10, 17),
      );

      expect(report.isInProgress, isTrue);
      expect(report.dayCount, 0);
      expect(report.avgFocusMinutesPerDay, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 4. 趋势桶
  // ═════════════════════════════════════════════════════════════════════════
  group('趋势桶', () {
    test('日档：buckets 为空（趋势图用 trailingDays）', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(_octoberDataset()));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.day,
        anchor: DateTime(2026, 10, 6),
        now: DateTime(2026, 10, 17),
      );

      expect(report.buckets, isEmpty);
      expect(report.days.length, 1);
      expect(report.totalFocusMinutes, 60);
    });

    test('周档：7 根日柱，label 周一…周日，求和 == 总分钟', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(_octoberDataset()));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.week,
        anchor: DateTime(2026, 10, 1), // 周四 → 本周 = 09-28 ~ 10-05
        now: DateTime(2026, 10, 17),
      );

      expect(report.start, DateTime(2026, 9, 28));
      expect(report.end, DateTime(2026, 10, 5));
      expect(report.buckets.length, 7);
      expect(
        report.buckets.map((PeriodBucket b) => b.label).toList(),
        <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
      );
      // 桶边界逐日相接
      for (int i = 0; i < 7; i++) {
        expect(report.buckets[i].start, DateTime(2026, 9, 28 + i));
        expect(report.buckets[i].end, DateTime(2026, 9, 29 + i));
        expect(report.buckets[i].start.isBefore(report.buckets[i].end), isTrue);
      }
      // 09-28~10-05 内：09-30 23:59 = 100（上月最后一天，属本周）/ 10-01 = 40 /
      // 10-02 = 5 / 10-03 = 20 / 10-04 = 40
      expect(report.buckets[0].focusMinutes, 0); // 09-28 周一
      expect(report.buckets[1].focusMinutes, 0); // 09-29 周二
      expect(report.buckets[2].focusMinutes, 100); // 09-30 周三
      expect(report.buckets[3].label, '周四');
      expect(report.buckets[3].focusMinutes, 40);
      expect(report.buckets[4].focusMinutes, 5); // 10-02 周五
      expect(report.buckets[5].focusMinutes, 20); // 10-03 周六
      expect(report.buckets[6].focusMinutes, 40); // 10-04 周日
      final double sum = report.buckets
          .fold(0.0, (double a, PeriodBucket b) => a + b.focusMinutes);
      expect(sum, report.totalFocusMinutes);
      expect(report.totalFocusMinutes, 205); // 100 + 40 + 5 + 20 + 40
    });

    test('月档：4~5 根、首尾桶日期连续无缝、求和 == 总分钟', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRangeRepo(_octoberDataset()));
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.month,
        anchor: DateTime(2026, 10, 1),
        now: DateTime(2026, 10, 31),
      );

      expect(report.buckets.length >= 4 && report.buckets.length <= 5, isTrue,
          reason: '月档按周分组应得 4~5 根，实测 ${report.buckets.length}');
      // 2026-10-01 是周四 → 首桶 10-01~10-05(4 天)，后续 7 天 ×3 + 6 天 = 5 桶
      expect(report.buckets.length, 5);
      expect(report.buckets.first.start, DateTime(2026, 10, 1));
      expect(report.buckets.first.end, DateTime(2026, 10, 5));
      expect(report.buckets.last.start, DateTime(2026, 10, 26));
      expect(report.buckets.last.end, DateTime(2026, 11, 1));
      expect(
        report.buckets.map((PeriodBucket b) => b.label).toList(),
        <String>['第1周', '第2周', '第3周', '第4周', '第5周'],
      );

      // 连续无缝：b[i].end == b[i+1].start
      for (int i = 0; i + 1 < report.buckets.length; i++) {
        expect(report.buckets[i].end, report.buckets[i + 1].start,
            reason: '桶 $i → ${i + 1} 不得有缝隙');
      }
      // 首桶起点 == 区间起点、末桶终点 == 区间终点
      expect(report.buckets.first.start, report.start);
      expect(report.buckets.last.end, report.end);

      final double sum = report.buckets
          .fold(0.0, (double a, PeriodBucket b) => a + b.focusMinutes);
      expect(sum, report.totalFocusMinutes);
      expect(report.totalFocusMinutes, 245);
      // 10-01~10-04 都在首桶
      expect(report.buckets.first.focusMinutes, 40 + 5 + 20 + 40);
    });

    test('年档：12 根月柱、label 1月…12月、求和 == 总分钟', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('y1', DateTime(2026, 1, 15, 9), plannedMin: 30, actualFocusMin: 30),
          _s('y2', DateTime(2026, 10, 6, 9), plannedMin: 60, actualFocusMin: 60),
          _s('y3', DateTime(2026, 12, 20, 9), plannedMin: 45, actualFocusMin: 45),
        ]),
      );
      final PeriodReport report = await service.buildPeriodReport(
        period: ReportPeriod.year,
        anchor: DateTime(2026, 6, 15),
        now: DateTime(2026, 12, 31),
      );

      expect(report.start, DateTime(2026, 1, 1));
      expect(report.end, DateTime(2027, 1, 1));
      expect(report.buckets.length, 12);
      expect(
        report.buckets.map((PeriodBucket b) => b.label).toList(),
        <String>[
          '1月', '2月', '3月', '4月', '5月', '6月', //
          '7月', '8月', '9月', '10月', '11月', '12月',
        ],
      );
      expect(report.buckets.first.start, DateTime(2026, 1, 1));
      expect(report.buckets.last.end, DateTime(2027, 1, 1));
      for (int i = 0; i < 12; i++) {
        expect(report.buckets[i].start, DateTime(2026, i + 1, 1));
        expect(report.buckets[i].end, DateTime(2026, i + 2, 1));
        if (i + 1 < 12) {
          expect(report.buckets[i].end, report.buckets[i + 1].start);
        }
      }
      expect(report.buckets[0].focusMinutes, 30); // 1 月
      expect(report.buckets[9].focusMinutes, 60); // 10 月
      expect(report.buckets[11].focusMinutes, 45); // 12 月
      expect(report.buckets[5].focusMinutes, 0); // 6 月无数据

      final double sum = report.buckets
          .fold(0.0, (double a, PeriodBucket b) => a + b.focusMinutes);
      expect(sum, report.totalFocusMinutes);
      expect(report.totalFocusMinutes, 135);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 5. 🔴 快慢路径等价性（性能核心）
  // ═════════════════════════════════════════════════════════════════════════
  group('快慢路径等价性', () {
    test('同一数据集：FocusRangeQuery 快路径与逐日回退逐字段相等（含 days / buckets）',
        () async {
      final List<FocusSession> sessions = _octoberDataset();
      final _MemRangeRepo fastRepo = _MemRangeRepo(sessions);
      final _MemRepo slowRepo = _MemRepo(sessions);
      final FocusReportService fastService =
          FocusReportService(focus: fastRepo);
      final FocusReportService slowService =
          FocusReportService(focus: slowRepo);

      final DateTime anchor = DateTime(2026, 10, 17);
      final DateTime now = DateTime(2026, 10, 17, 12);
      for (final ReportPeriod period in <ReportPeriod>[
        ReportPeriod.day,
        ReportPeriod.week,
        ReportPeriod.month,
        ReportPeriod.year,
      ]) {
        fastRepo.sessionsBetweenCalls = 0;
        fastRepo.sessionsOfDayCalls = 0;
        slowRepo.sessionsBetweenCalls = 0;
        slowRepo.sessionsOfDayCalls = 0;

        final PeriodReport fast = await fastService.buildPeriodReport(
            period: period, anchor: anchor, now: now);
        final PeriodReport slow = await slowService.buildPeriodReport(
            period: period, anchor: anchor, now: now);

        _expectReportsEqual(fast, slow, '$period');

        // 查询次数证据：快路径恒 1 次范围查询；回退路径 = 区间天数次逐日查询。
        expect(fastRepo.sessionsBetweenCalls, 1, reason: '$period 快路径只查 1 次');
        expect(fastRepo.sessionsOfDayCalls, 0, reason: '$period 快路径不得逐日查询');
        expect(slowRepo.sessionsBetweenCalls, 0);
        expect(slowRepo.sessionsOfDayCalls, slow.days.length,
            reason: '$period 回退路径逐日查 ${slow.days.length} 次');
      }
    });

    test('heatmapDays / trailingDays 快慢路径逐日相等', () async {
      final List<FocusSession> sessions = _octoberDataset();
      final FocusReportService fastService =
          FocusReportService(focus: _MemRangeRepo(sessions));
      final FocusReportService slowService =
          FocusReportService(focus: _MemRepo(sessions));

      final DateTime today = DateTime(2026, 10, 17);
      _expectPointsEqual(
        await fastService.trailingDays(lastDay: today),
        await slowService.trailingDays(lastDay: today),
        'trailingDays',
      );
      _expectPointsEqual(
        await fastService.heatmapDays(today: today),
        await slowService.heatmapDays(today: today),
        'heatmapDays',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 6. heatmapDays / trailingDays 窗口
  // ═════════════════════════════════════════════════════════════════════════
  group('逐日序列窗口', () {
    test('heatmapDays(days: 365)：长度 365、末位 = today、无数据补 0', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('t1', DateTime(2026, 10, 17, 8), plannedMin: 30, actualFocusMin: 30),
        ]),
      );
      final List<DailyFocusPoint> points =
          await service.heatmapDays(today: DateTime(2026, 10, 17, 15, 30));

      expect(points.length, 365);
      final DateTime expectedFirst =
          DateTime(2026, 10, 17).subtract(const Duration(days: 364));
      expect(points.first.date, expectedFirst);
      expect(points.first.dayKey, dayKey(expectedFirst));
      expect(points.last.date, DateTime(2026, 10, 17));
      expect(points.last.dayKey, '2026-10-17');
      // 窗口内无数据日补 0 且非 WFD
      for (final DailyFocusPoint p in points) {
        if (p.dayKey == '2026-10-17') continue;
        expect(p.focusMinutes, 0);
        expect(p.sessionCount, 0);
        expect(p.isWfd, isFalse);
      }
      expect(points.last.focusMinutes, 30);
      expect(points.last.isWfd, isTrue);
      // 严格升序、日期连续
      for (int i = 0; i + 1 < points.length; i++) {
        expect(points[i].date.isBefore(points[i + 1].date), isTrue);
        expect(points[i + 1].date,
            DateTime(points[i].date.year, points[i].date.month,
                points[i].date.day + 1));
      }
    });

    test('trailingDays(count: 7)：长度 7、末位 = lastDay', () async {
      final FocusReportService service = FocusReportService(
        focus: _MemRangeRepo(<FocusSession>[
          _s('t2', DateTime(2026, 10, 17, 8), plannedMin: 30, actualFocusMin: 30),
          _s('t3', DateTime(2026, 10, 11, 8), plannedMin: 20, actualFocusMin: 20),
        ]),
      );
      final List<DailyFocusPoint> points =
          await service.trailingDays(lastDay: DateTime(2026, 10, 17, 9));

      expect(points.length, 7);
      expect(points.first.dayKey, '2026-10-11');
      expect(points.last.dayKey, '2026-10-17');
      expect(points.first.focusMinutes, 20);
      expect(points.last.focusMinutes, 30);
      expect(points[1].focusMinutes, 0); // 10-12 补零
      expect(points[1].isWfd, isFalse);
    });

    test('count <= 0 → 空列表（不做无意义查询）', () async {
      final _MemRangeRepo repo = _MemRangeRepo(_octoberDataset());
      final FocusReportService service = FocusReportService(focus: repo);
      expect(await service.trailingDays(lastDay: DateTime(2026, 10, 17), count: 0),
          isEmpty);
      expect(repo.sessionsBetweenCalls, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 7. 守卫 + M3 既有能力回归
  // ═════════════════════════════════════════════════════════════════════════
  group('守卫', () {
    test('FocusRepository 本体未加方法：范围查询是独立能力接口（类型断言）', () {
      final FocusRepository plain = _MemRepo(<FocusSession>[]);
      final FocusRepository ranged = _MemRangeRepo(<FocusSession>[]);

      expect(plain is FocusRangeQuery, isFalse,
          reason: '只实现 FocusRepository 的桩不应被判定为具备范围查询能力');
      expect(ranged is FocusRangeQuery, isTrue);

      // 服务对「无范围查询能力」的仓储走逐日回退，不因缺接口而抛错。
      expect(
        () => FocusReportService(focus: plain).buildPeriodReport(
          period: ReportPeriod.month,
          anchor: DateTime(2026, 10, 1),
          now: DateTime(2026, 10, 17),
        ),
        returnsNormally,
      );
    });

    test('buildReport（M3 既有能力）签名与行为未改：近 7 日 + 近 4 周趋势', () async {
      final FocusReportService service =
          FocusReportService(focus: _MemRepo(_octoberDataset()));
      final FocusReport report = await service.buildReport(DateTime(2026, 10, 17, 12));

      expect(report.last7Days.length, 7);
      expect(report.last7Days.first.dayKey, '2026-10-11');
      expect(report.last7Days.last.dayKey, '2026-10-17');
      expect(report.generatedAt, DateTime(2026, 10, 17, 12));
      // 近 7 日（10-11 ~ 10-17）无会话 → 全 0
      expect(report.weeklyFocusMinutes, 0);
      expect(report.validFocusDaysLast7, 0);
      // 近 4 周（旧→新）：09-20~26=0 / 09-27~10-03=2（09-30 + 10-01）/
      // 10-04~10=5 / 10-11~17=0
      expect(report.weeklyValidDayTrend, <int>[0, 2, 5, 0]);
      expect(report.stabilityScore, closeTo(7 / 28, 1e-9));
    });
  });
}
