/// 护眼统计 UI 测试（玄参 2026-10-09）：
///  · 家长报告页新增「护眼统计」卡（完成 / 跳过 / 时长 / 跳过率）；
///  · 孩子端「我的」页新增「累计护眼」tile（账本口径）。
library eye_care_stats_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_report_page.dart';

/// ── 假仓储 ────────────────────────────────────────────────────────────────

class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({this.eyeCareCount = 0});

  final int eyeCareCount;

  @override
  Future<double> balance() async => 100;

  @override
  Future<int> countByRefType(String refType) async =>
      refType == kEyeCareRefType ? eyeCareCount : 0;

  @override
  Future<double> append(SunlightEntry entry) async => 100;

  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeEyeCareLogRepository implements EyeCareLogRepository {
  _FakeEyeCareLogRepository({
    this.skipped = 0,
    this.skippedWatchedSeconds = 0,
  });

  final int skipped;
  final int skippedWatchedSeconds;

  @override
  Future<int> countByResult(EyeCareResultType type) async =>
      type == EyeCareResultType.skipped ? skipped : 0;

  @override
  Future<int> watchedSecondsByResult(EyeCareResultType type) async =>
      type == EyeCareResultType.skipped ? skippedWatchedSeconds : 0;

  @override
  Future<void> append(EyeCareLog log) async {}
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 120,
        totalSessions: 8,
        totalValidDays: 3,
      );
}

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];

  @override
  Future<void> saveTask(Task task) async {}

  @override
  Future<void> deleteTaskById(String id) async {}

  @override
  Future<void> checkIn(CheckIn checkIn) async {}

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];

  @override
  Future<int> totalCheckInCount() async => 5;
}

class _FakePlantRepository implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];

  @override
  Future<Plant?> plant(String id) async => null;

  @override
  Future<void> savePlant(Plant plant) async {}

  @override
  Future<void> deletePlant(String id) async {}

  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

/// 报告服务桩：绕过 28+7 次查询，直接回一份零值报告（护眼数据走独立 provider）。
class _StubReportService extends FocusReportService {
  _StubReportService() : super(focus: _FakeFocusRepository());

  @override
  Future<FocusReport> buildReport(DateTime now) async => FocusReport(
        generatedAt: now,
        last7Days: <DailyFocusPoint>[],
        weeklyFocusMinutes: 0,
        validFocusDaysLast7: 0,
        stabilityScore: 0,
        weeklyValidDayTrend: <int>[0, 0, 0, 0],
      );
}

/// 报告页测试台：先挂一个空 home，再 push 报告页（绕开初始构建即查库）。
Future<void> _pumpReportPage(
  WidgetTester tester, {
  required int eyeCareCompleted,
  required int eyeCareSkipped,
  required int skippedWatchedSeconds,
}) async {
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      focusReportServiceProvider.overrideWithValue(_StubReportService()),
      sunlightRepositoryProvider.overrideWithValue(
        _FakeSunlightRepository(eyeCareCount: eyeCareCompleted),
      ),
      eyeCareLogRepositoryProvider.overrideWithValue(
        _FakeEyeCareLogRepository(
          skipped: eyeCareSkipped,
          skippedWatchedSeconds: skippedWatchedSeconds,
        ),
      ),
    ],
    child: MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()),
    ),
  ));
      navKey.currentState!.push<Object?>(MaterialPageRoute<Object?>(
    builder: (_) => const ParentReportPage(),
  ));
  // _load 是多段异步（报告 + 账本 + 护眼记录）：有界步进 pump 直到加载完成。
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('护眼统计').evaluate().isNotEmpty) break;
  }
}

void main() {
  group('家长报告 · 护眼统计卡', () {
    testWidgets('显示完成次数（账本口径）/ 跳过次数 / 时长 / 跳过率',
        (tester) async {
      // 12 次完成 ×63s = 756s；跳过 3 次共看了 40s → 总 796s ≈ 13.3 分钟；
      // 跳过率 3/15 = 20%。
      await _pumpReportPage(
        tester,
        eyeCareCompleted: 12,
        eyeCareSkipped: 3,
        skippedWatchedSeconds: 40,
      );

      // ListView 懒构建：护眼统计区在视口折叠线以下，先滚动到位再断言。
      await tester.scrollUntilVisible(
        find.text('护眼统计'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('护眼统计'), findsOneWidget);
      expect(find.text('12 次'), findsOneWidget, reason: '完成护眼 = 账本口径');
      expect(find.text('3 次'), findsOneWidget, reason: '跳过次数 = eye_care_logs');
      expect(find.text('13.3 分钟'), findsOneWidget,
          reason: '12×63s + 跳过 40s = 796s ≈ 13.3 分钟');
      expect(find.text('20%'), findsOneWidget, reason: '3 / (12+3) = 20%');
      expect(find.textContaining('有 3 次护眼被跳过'), findsOneWidget);
    });

    testWidgets('零数据：显示 0 次 + 占位符「—」，不给误导数字', (tester) async {
      await _pumpReportPage(
        tester,
        eyeCareCompleted: 0,
        eyeCareSkipped: 0,
        skippedWatchedSeconds: 0,
      );

      await tester.scrollUntilVisible(
        find.text('护眼统计'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('0 次'), findsNWidgets(2));
      expect(find.text('—'), findsNWidgets(2), reason: '时长与跳过率无数据显示 —');
      expect(find.textContaining('被跳过'), findsNothing);
    });
  });

  group('孩子端「我的」· 累计护眼', () {
    testWidgets('显示账本口径的累计护眼次数', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
          plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
          sunlightRepositoryProvider.overrideWithValue(
            _FakeSunlightRepository(eyeCareCount: 7),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
      ));
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('累计护眼').evaluate().isNotEmpty) break;
      }

      expect(find.text('累计护眼'), findsOneWidget);
      expect(find.text('7 次'), findsOneWidget);
    });
  });
}
