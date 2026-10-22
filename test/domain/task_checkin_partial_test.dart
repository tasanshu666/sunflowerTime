/// F143（玄参 2026-10-20 拍板）：**联动成长项按专注时长比例结算** 领域层测试。
///
/// ## 口径（不可更改）
///  · **向下取整**（floor，全整数秒级运算 `~/`）；
///  · **最低门槛 5 分钟**：实际专注 < 300 秒 → 不结算、不落打卡、0 奖励
///    （保持既有 `rejected` 语义）；
///  · **5 分钟 ≤ 实际 < 任务门槛** → 按比例结算，**算完成**（落 `verified` 打卡）；
///  · 实际 ≥ 门槛 → 全额（现状逻辑，不走比例）；
///  · 公式（先乘后除，避免浮点误差）：
///    `granted = max(1, actualSeconds * full ~/ thresholdSeconds)`；
///    `completionPercent = floor(actualSeconds * 100 / thresholdSeconds)` ∈ [1, 99]。
///
/// 用例覆盖验收对照表 4:59 / 5 / 10 / 15 / 19:59 / 20 / 30 各档，外加日上限截断组合、
/// sessionUsed、幂等、门槛 < 5 分钟的历史配置，以及**源码守卫**（5 分钟硬门槛常量 = 300、
/// rejected 分支必须在 partial 分支之前）。
///
/// 纯 Dart：仓储全部为内存 Fake（`package:test/test.dart`），不依赖 Drift / Flutter。
library task_checkin_partial_test;

import 'dart:io';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

// ── 内存 Fake 仓储（口径与 test/m4/task_checkin_test.dart 一致）────────────────

/// 内存任务 / 打卡仓储（同时实现家长核销能力接口 [CheckInAdminRepository]）。
class _MemoryTaskRepo implements TaskRepository, CheckInAdminRepository {
  final List<Task> store = <Task>[];
  final List<CheckIn> checkIns = <CheckIn>[];

  @override
  Future<List<Task>> tasks() async => List<Task>.of(store);

  @override
  Future<void> saveTask(Task task) async {
    store.removeWhere((Task t) => t.id == task.id);
    store.add(task);
  }

  @override
  Future<void> deleteTaskById(String id) async =>
      store.removeWhere((Task t) => t.id == id);

  @override
  Future<void> checkIn(CheckIn checkIn) async => checkIns.add(checkIn);

  @override
  Future<List<CheckIn>> checkInsOfDay(String key) async =>
      checkIns.where((CheckIn c) => dayKey(c.date) == key).toList();

  @override
  Future<int> totalCheckInCount() async =>
      checkIns.where((CheckIn c) => c.status == CheckInStatus.verified).length;

  @override
  Future<CheckIn?> checkInById(String id) async {
    for (final CheckIn c in checkIns) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async {
    final List<CheckIn> hits =
        checkIns.where((CheckIn c) => c.status == status).toList();
    hits.sort((CheckIn a, CheckIn b) => a.completedAt.compareTo(b.completedAt));
    return hits;
  }

  @override
  Future<void> updateCheckIn(CheckIn checkIn) async {
    final int idx = checkIns.indexWhere((CheckIn c) => c.id == checkIn.id);
    if (idx >= 0) {
      checkIns[idx] = checkIn;
    } else {
      checkIns.add(checkIn);
    }
  }

  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async {
    final int idx = checkIns.indexWhere((CheckIn c) => c.id == id);
    if (idx < 0) return false;
    final CheckIn c = checkIns[idx];
    if (c.status != from) return false;
    checkIns[idx] = CheckIn(
      id: c.id,
      taskId: c.taskId,
      date: c.date,
      completedAt: c.completedAt,
      sessionId: c.sessionId,
      isPerfectDay: c.isPerfectDay,
      status: to,
      sunlightGross: c.sunlightGross,
      sunlightGranted: sunlightGranted,
      resolvedAt: resolvedAt,
      parentNote: parentNote,
      actualFocusMin: c.actualFocusMin,
    );
    return true;
  }
}

class _MemorySunlightRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  /// 预置「当日已发**成长奖励**」净额（成长奖励日上限核算的前置态）。
  void seedCheckInNet(String key, double net, DateTime ts) {
    entries.add(SunlightEntry(
      id: 'seed-${entries.length}',
      ts: ts,
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: TaskCheckInService.checkInRefType,
      refId: 'seed',
      dayKey: key,
    ));
  }

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async =>
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.from(entries);

  @override
  Future<double> dayNet(String key) async => entries
      .where((SunlightEntry e) => e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> earnGrossOnDay(String key) async => entries
      .where(
          (SunlightEntry e) => e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String key) async => entries
      .where(
          (SunlightEntry e) => e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => entries
      .where((SunlightEntry e) => e.refType == refType && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String key) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _MemoryFocusRepo implements FocusRepository {
  final List<FocusSession> sessions = <FocusSession>[];

  /// 追加一次已完成的专注会话；[actualSeconds] 用**秒**表达，避免浮点分钟歧义
  /// （4:59 = 299 秒、19:59 = 1199 秒）。
  FocusSession addSession({
    required int actualSeconds,
    required int plannedMin,
    required DateTime start,
    String id = 's-1',
  }) {
    final FocusSession s = FocusSession(
      id: id,
      start: start,
      end: start.add(Duration(seconds: actualSeconds)),
      plannedMin: plannedMin,
      actualFocusMin: actualSeconds / 60.0,
      status: FocusStatus.completed,
      sunlightEarned: 0,
      createdAt: start,
    );
    sessions.add(s);
    return s;
  }

  @override
  Future<void> saveSession(FocusSession session) async => sessions.add(session);

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      sessions.where((FocusSession s) => dayKey(s.start) == key).toList();

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemorySettingsRepo implements SettingsRepository {
  AppSettings value = const AppSettings(
    ageTier: AgeTier.low,
    dailyFocusCap: kDailyFocusCapLow,
    dailyAppCapMinutes: 30,
    restAfterSessions: 2,
    restMinutes: 10,
    taskSunlight: 12,
    poolBudget: kPoolBudgetDefaultLow,
  );

  @override
  Future<AppSettings> getSettings() async => value;

  @override
  Future<void> saveSettings(AppSettings s) async => value = s;
}

/// 联动成长项：20 分钟门槛 → 满额 = `20 × 40%` = 8 阳光（[Task.effectiveSunlightReward]）。
Task _linkedTask({String id = 't_focus', int minFocusMin = 20}) => Task(
      id: id,
      name: 'Focused reading',
      subject: TaskSubject.general,
      requiresFocus: true,
      minFocusMin: minFocusMin,
      sunlightReward: Task.rewardCapFor(minFocusMin),
      isCustom: true,
    );

void main() {
  late _MemoryTaskRepo tasks;
  late _MemorySunlightRepo ledger;
  late _MemoryFocusRepo focus;
  late TaskCheckInService service;
  late DateTime now;
  late String day;

  setUp(() {
    tasks = _MemoryTaskRepo();
    ledger = _MemorySunlightRepo();
    focus = _MemoryFocusRepo();
    service = TaskCheckInService(
      tasks: tasks,
      ledger: ledger,
      focus: focus,
      settings: _MemorySettingsRepo(),
    );
    now = DateTime.now();
    day = dayKey(now);
  });

  /// 用给定秒数结算一个联动项，返回结算结果。
  Future<TaskCheckInOutcome> settle({
    required int actualSeconds,
    Task? task,
    int plannedMin = 20,
  }) async {
    final Task t = task ?? _linkedTask();
    final FocusSession s = focus.addSession(
      actualSeconds: actualSeconds,
      plannedMin: plannedMin,
      start: now,
    );
    return service.settleFocusLinked(task: t, session: s, now: now);
  }

  group('F143 验收对照表（20 分钟门槛 = 满额 8 阳光）', () {
    test('① 4:59（299 秒）→ rejected：不结算、不落打卡、0 奖励', () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 299);

      expect(o.status, CheckInStatus.rejected, reason: '< 5 分钟保持现状 rejected 语义');
      expect(o.partial, isFalse);
      expect(o.completionPercent, 0);
      expect(o.granted, 0);
      expect(o.reward, 0);
      expect(o.checkInId, isEmpty, reason: '未达标不落打卡记录');
      expect(tasks.checkIns, isEmpty, reason: '一行都不许落库');
      expect(ledger.entries, isEmpty, reason: '不入账');
    });

    test('② 5:00（300 秒）→ partial：granted = max(1, floor(300×8/1200)) = 2，25%',
        () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 300);

      expect(o.partial, isTrue);
      expect(o.status, CheckInStatus.verified, reason: '部分完成**算完成**，落 verified 打卡');
      expect(o.completionPercent, 25);
      expect(o.reward, 2, reason: 'floor(300*8/1200) = 2');
      expect(o.granted, 2);
      expect(o.cappedByDailyCap, isFalse);
      expect(o.checkInId, isNotEmpty);

      final CheckIn row = tasks.checkIns.single;
      expect(row.status, CheckInStatus.verified);
      expect(row.sunlightGross, 2);
      expect(row.sunlightGranted, 2);
      expect(row.actualFocusMin, closeTo(5.0, 1e-9),
          reason: '实际专注分钟必须落库（卡片/家长端展示「实际 5 分钟」）');
      expect(row.sessionId, isNotNull, reason: '占住该 session');
      expect(ledger.entries.single.net, 2, reason: '账本与打卡同一口径');
    });

    test('③ 10 分钟 → 4 阳光、50%', () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 600);

      expect(o.partial, isTrue);
      expect(o.granted, 4, reason: 'floor(600*8/1200) = 4');
      expect(o.completionPercent, 50);
    });

    test('④ 15 分钟 → 6 阳光、75%', () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 900);

      expect(o.partial, isTrue);
      expect(o.granted, 6, reason: 'floor(900*8/1200) = 6');
      expect(o.completionPercent, 75);
    });

    test('⑤ 19:59（1199 秒）→ floor(1199×8/1200) = 7、99%（向下取整不四舍五入）',
        () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 1199);

      expect(o.partial, isTrue);
      expect(o.granted, 7, reason: '1199*8 ~/ 1200 = 9592 ~/ 1200 = 7');
      expect(o.completionPercent, 99, reason: '119900 ~/ 1200 = 99（不是 100）');
    });

    test('⑥ 20 分钟（满门槛）→ 全额 8、partial=false、100%', () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 1200);

      expect(o.partial, isFalse, reason: '达门槛走现状全额逻辑，不算部分完成');
      expect(o.granted, 8);
      expect(o.reward, 8);
      expect(o.completionPercent, 100);
      expect(tasks.checkIns.single.actualFocusMin, closeTo(20.0, 1e-9),
          reason: '全额完成也写实际专注分钟（家长端展示「实际 20 分钟」）');
    });

    test('⑦ 30 分钟（超门槛）→ 仍是全额 8（不超发）', () async {
      final TaskCheckInOutcome o = await settle(actualSeconds: 1800);

      expect(o.partial, isFalse);
      expect(o.granted, 8, reason: '超过门槛不加价');
      expect(o.completionPercent, 100);
    });
  });

  group('F143 边界与既有守卫', () {
    test('⑧ 日上限截断 × 部分完成：当日已发 79 → granted = 1、capped = true', () async {
      ledger.seedCheckInNet(day, 79, now);

      final TaskCheckInOutcome o = await settle(actualSeconds: 600); // 应发 4

      expect(o.partial, isTrue);
      expect(o.reward, 4, reason: '应发仍是按比例的 4');
      expect(o.granted, 1, reason: 'min(4, 80-79) = 1');
      expect(o.cappedByDailyCap, isTrue);
      expect(tasks.checkIns.single.sunlightGranted, 1);
      expect(tasks.checkIns.single.actualFocusMin, closeTo(10.0, 1e-9));
    });

    test('⑨ 同一 session 不能连续结算两个成长项（partial 也占住 session）', () async {
      final Task a = _linkedTask(id: 't_a');
      final Task b = _linkedTask(id: 't_b');
      final FocusSession s = focus.addSession(
        actualSeconds: 600,
        plannedMin: 20,
        start: now,
      );

      final TaskCheckInOutcome first =
          await service.settleFocusLinked(task: a, session: s, now: now);
      expect(first.partial, isTrue);

      await expectLater(
        () => service.settleFocusLinked(task: b, session: s, now: now),
        throwsA(isA<TaskCheckInException>().having(
          (TaskCheckInException e) => e.code,
          'code',
          TaskCheckInError.sessionUsed,
        )),
      );
      expect(tasks.checkIns.length, 1, reason: '第二个成长项一行都不许落库');
    });

    test('⑩ 同一任务当日重复结算幂等：返回同一 checkInId、不新增行', () async {
      final Task t = _linkedTask();
      final FocusSession s = focus.addSession(
        actualSeconds: 600,
        plannedMin: 20,
        start: now,
      );

      final TaskCheckInOutcome first =
          await service.settleFocusLinked(task: t, session: s, now: now);
      final TaskCheckInOutcome second =
          await service.settleFocusLinked(task: t, session: s, now: now);

      expect(second.checkInId, first.checkInId);
      expect(second.granted, first.granted);
      expect(second.partial, isTrue, reason: '幂等返回必须从既有记录反推出 partial');
      expect(second.completionPercent, 50, reason: '完成度同样从 actualFocusMin 反算');
      expect(tasks.checkIns.length, 1, reason: '不新增行');
      expect(ledger.entries.length, 1, reason: '不重复入账');
    });

    test('⑪ 门槛 < 5 分钟（历史 / 导入配置）：实际 ≥ 门槛即全额，不受 5 分钟下限影响',
        () async {
      // 3 分钟门槛 → 满额 = round(3 × 40%) = 1 阳光。
      final Task t = _linkedTask(minFocusMin: 3);
      expect(t.effectiveSunlightReward, 1);

      final TaskCheckInOutcome o = await settle(
        actualSeconds: 240, // 4 分钟 ≥ 3 分钟门槛
        task: t,
        plannedMin: 3,
      );

      expect(o.partial, isFalse, reason: '已达门槛 → 全额，不走比例');
      expect(o.granted, 1);
      expect(o.completionPercent, 100);
    });

    test('⑪-b 门槛 < 5 分钟但实际同时低于门槛与 5 分钟 → rejected', () async {
      final Task t = _linkedTask(minFocusMin: 3);
      final TaskCheckInOutcome o = await settle(
        actualSeconds: 120, // 2 分钟 < 3 分钟门槛，且 < 5 分钟
        task: t,
        plannedMin: 3,
      );

      expect(o.status, CheckInStatus.rejected);
      expect(o.partial, isFalse);
      expect(tasks.checkIns, isEmpty);
    });
  });

  group('F143 源码守卫（防口径被悄悄改回「必须满额」）', () {
    /// 服务源码（唯一真源）。
    final String src =
        File('lib/domain/services/task_checkin_service.dart').readAsStringSync();

    test('⑮ 5 分钟硬门槛常量存在且 = 300 秒', () {
      expect(
        RegExp(r'const\s+int\s+kPartialSettleMinSeconds\s*=\s*300\s*;')
            .hasMatch(src),
        isTrue,
        reason: '5 分钟 = 300 秒必须单点收口；改成 15 分钟 = 900 会让'
            '「提前结束按比例」失效',
      );
    });

    test('⑯ `_settleFocusLinked` 里先用常量判定，且 rejected 分支在 partial 分支之前',
        () {
      final int start =
          src.indexOf('Future<TaskCheckInOutcome> _settleFocusLinked(');
      final int end = src.indexOf('Future<List<PendingCheckIn>> pendingCheckIns()');
      expect(start, greaterThan(0), reason: '找不到 _settleFocusLinked 实现体');
      expect(end, greaterThan(start));
      final String body = src.substring(start, end);

      expect(body.contains('kPartialSettleMinSeconds'), isTrue,
          reason: '硬门槛常量必须在结算实现里被真正使用（不能只声明）');

      final int rejectedAt = body.indexOf('F143 ①');
      final int partialAt = body.indexOf('F143 ②');
      expect(rejectedAt, greaterThan(0), reason: '找不到 rejected 分支标记');
      expect(partialAt, greaterThan(rejectedAt),
          reason: 'rejected（< 5 分钟）判定必须在 partial（按比例）判定之前');

      // 分支顺序还必须在「sessionUsed 守卫」之前定出 partial/percent ——
      // 否则部分完成会绕过 session 占用检查（一次专注换多份奖励）。
      expect(body.indexOf('TaskCheckInError.sessionUsed'), greaterThan(partialAt),
          reason: 'partial 判定必须在 sessionUsed 守卫之前完成');
    });
  });
}
