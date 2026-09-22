/// M4 领域层**对抗性验证**：TaskCheckInService + CheckInAdminRepository。
///
/// 目的：以「攻击者视角」试图打破冻结不变量，并证实 / 证伪 handed-off 的 A–D 攻击面。
/// **纯 Dart 内存 Fake**，不依赖 Drift / Flutter（`dart test` 亦可跑）。
///
/// 演进（重要）：
///  - 初版：发现 4 个攻击面漏洞 + 1 个竞态（P0）。彼时用「characterization」写法
///    （断言当时的**错误**行为，绿 = 漏洞坐实）。
///  - 现版：engineer 已落地修复（CAS 原子核销 / sessionId 去重 / 跨天守卫 / rejected
///    不算完成且可重做 / totalCheckInCount 只数 verified），本文件**转为回归套件**：
///    断言**修复后的正确行为**（绿 = 护栏生效）。
///
/// 组织：
///  一、不变量护栏（护栏有效）
///  二、攻击面回归（修复已落地：原漏洞现被拦住）
///  三、新经济规则 40% 封顶（对抗边界）
///  四、残留对抗（仍未闭环，待加固 / 待口径）
///
/// 被测：lib/domain/services/task_checkin_service.dart
///       lib/domain/repositories/task_repository.dart（CheckInAdminRepository）
///       lib/domain/entities/task.dart（effectiveSunlightReward）
library adversarial_task_checkin_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
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

// ── 内存 Fake 仓储（自包含；镜像真实仓储语义）──────────────────────────────

class _MemTaskRepo implements TaskRepository, CheckInAdminRepository {
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

  /// 对齐真实仓储：只数 `verified`（修复 7）。
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
    final int i = checkIns.indexWhere((CheckIn c) => c.id == checkIn.id);
    if (i >= 0) {
      checkIns[i] = checkIn;
    } else {
      checkIns.add(checkIn);
    }
  }

  /// CAS：读-判-写之间无 await → 单线程下即原子（镜像 DAO 的条件 UPDATE）。
  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async {
    final int i = checkIns.indexWhere((CheckIn c) => c.id == id);
    if (i < 0 || checkIns[i].status != from) return false;
    final CheckIn c = checkIns[i];
    checkIns[i] = CheckIn(
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
    );
    return true;
  }
}

class _MemSunlightRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  void seedEarn(String key, double gross, double net, DateTime ts) {
    entries.add(SunlightEntry(
      id: 'seed-${entries.length}',
      ts: ts,
      type: SunlightType.earn,
      gross: gross,
      net: net,
      balanceAfter: net,
      refType: 'focus_session',
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
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String key) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  /// 真实语义：按 refType + refId + dayKey 计数（服务层二次防重入账用）。
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String key) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String r, String i) async => null;
}

class _MemFocusRepo implements FocusRepository {
  final List<FocusSession> sessions = <FocusSession>[];

  FocusSession addSession({
    required double actualMin,
    required int plannedMin,
    required DateTime start,
    String? id,
  }) {
    final FocusSession s = FocusSession(
      id: id ?? 's-${sessions.length}',
      start: start,
      end: start.add(Duration(seconds: (actualMin * 60).round())),
      plannedMin: plannedMin,
      actualFocusMin: actualMin,
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
  Future<int> countValidFocusDaysLastWeek(DateTime now) async {
    final Set<String> days = <String>{};
    for (final FocusSession s in sessions) {
      if (_valid(s)) days.add(dayKey(s.start));
    }
    return days.length;
  }

  @override
  Future<FocusStats> totalStats() async {
    double minutes = 0;
    final Set<String> days = <String>{};
    for (final FocusSession s in sessions) {
      minutes += s.actualFocusMin;
      if (_valid(s)) days.add(dayKey(s.start));
    }
    return FocusStats(
      totalFocusMinutes: minutes,
      totalSessions: sessions.length,
      totalValidDays: days.length,
    );
  }

  bool _valid(FocusSession s) {
    final double completion =
        s.plannedMin == 0 ? 0.0 : s.actualFocusMin / s.plannedMin;
    return s.actualFocusMin >= kValidFocusMinutes &&
        completion >= kCompletionRateThreshold;
  }
}

class _MemSettingsRepo implements SettingsRepository {
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

// ── 组装辅助 ────────────────────────────────────────────────────────────────

Task _task({
  required String id,
  bool requiresFocus = false,
  int reward = 12,
  int minFocus = 15,
  String? repeatRule,
}) =>
    Task(
      id: id,
      name: '任务$id',
      subject: TaskSubject.general,
      requiresFocus: requiresFocus,
      minFocusMin: minFocus,
      sunlightReward: reward,
      repeatRule: repeatRule,
      isCustom: false,
    );

({
  TaskCheckInService svc,
  _MemTaskRepo tasks,
  _MemSunlightRepo ledger,
  _MemFocusRepo focus,
}) _make() {
  final _MemTaskRepo tasks = _MemTaskRepo();
  final _MemSunlightRepo ledger = _MemSunlightRepo();
  final _MemFocusRepo focus = _MemFocusRepo();
  final TaskCheckInService svc = TaskCheckInService(
    tasks: tasks,
    ledger: ledger,
    focus: focus,
    settings: _MemSettingsRepo(),
  );
  return (svc: svc, tasks: tasks, ledger: ledger, focus: focus);
}

/// 联动项有效奖励：`min(reward, round(minFocus×0.4 且 ≥1))`（固定值，不再乘完美日系数）。
double _linkedReward(int reward, int minFocus, {bool perfectDay = false}) {
  final double base = Task.rewardCapFor(minFocus) < reward
      ? Task.rewardCapFor(minFocus).toDouble()
      : reward.toDouble();
  return base; // 完美日仅作徽章，不再影响奖励数额
}

void main() {
  final DateTime day = DateTime(2026, 9, 22, 9, 0); // 周二 09:00
  final DateTime day2 = DateTime(2026, 9, 23, 9, 0); // 次日

  // ════════════════════════════════════════════════════════════════════════
  // 一、不变量护栏（断言护栏有效）
  // ════════════════════════════════════════════════════════════════════════
  group('不变量护栏（断言护栏有效）', () {
    test('I1 verifyCheckIn 二次调用 → 抛错且账本仅 1 条（防重复核销）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      await ctx.svc.verifyCheckIn(id, day);
      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, hasLength(1));
      expect(await ctx.ledger.balance(), 12);
    });

    test('I2 已驳回记录不能再 verify（抛错、不入账）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.rejectCheckIn(id, now: day);

      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, isEmpty);
    });

    test('I3 已核销记录不能再 reject（抛错）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.verifyCheckIn(id, day);

      await expectLater(
        () => ctx.svc.rejectCheckIn(id, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, hasLength(1));
    });

    test('I4 pending 不入账：多条 pending → 余额 0、当日 earn 合计 0', () async {
      final ctx = _make();
      ctx.tasks.store.addAll(<Task>[_task(id: 't1'), _task(id: 't2')]);
      await ctx.svc.checkIn(task: _task(id: 't1'), now: day);
      await ctx.svc.checkIn(task: _task(id: 't2'), now: day);

      expect(ctx.tasks.checkIns, hasLength(2));
      expect(ctx.tasks.checkIns.every((CheckIn c) => c.sunlightGranted == 0),
          isTrue);
      expect(ctx.ledger.entries, isEmpty);
      expect(await ctx.ledger.balance(), 0);
      expect(await ctx.ledger.earnGrossOnDay(dayKey(day)), 0);
    });

    test('I5 联动项不可手动打卡（checkIn 抛错、不落记录）', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true);
      await expectLater(
        () => ctx.svc.checkIn(task: f1, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
    });

    test('I6 非联动项不可走 settleFocusLinked（抛错）', () async {
      final ctx = _make();
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      await expectLater(
        () => ctx.svc.settleFocusLinked(
            task: _task(id: 'n1', requiresFocus: false), session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
    });

    test('I7 settleFocusLinked 不达标 → rejected、不写记录、不写账本', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 10, plannedMin: 20, start: day);

      final TaskCheckInOutcome out =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);

      expect(out.status, CheckInStatus.rejected);
      expect(out.checkInId, isEmpty);
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });

    test('I8 settleFocusLinked 幂等：同 task 同日两次 → 1 记录 / 1 账本', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);

      final TaskCheckInOutcome a =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      final TaskCheckInOutcome b =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);

      expect(b.checkInId, a.checkInId);
      expect(ctx.tasks.checkIns, hasLength(1));
      expect(ctx.ledger.entries, hasLength(1));
    });

    test('I9 软顶只补差额：当日已发 55 → 核销 12 只补 8.5', () async {
      final ctx = _make();
      ctx.ledger.seedEarn(dayKey(day), 55, 55, day);
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final TaskCheckInOutcome out =
          await ctx.svc.verifyCheckIn(ctx.tasks.checkIns.single.id, day);

      expect(out.granted, closeTo(8.5, 1e-9));
      expect(out.cappedBySoftCap, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 二、攻击面回归（修复已落地：原漏洞现被拦住）
  // ════════════════════════════════════════════════════════════════════════
  group('攻击面回归（修复生效）', () {
    // 原 ⚠️A：一场专注解锁多个联动项 → 现被 sessionId 复用守卫拦住。
    test('A｜同一场专注结算第二个联动项 → 抛错且不新增打卡/账本', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      final Task f2 = _task(id: 'f2', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.addAll(<Task>[f1, f2]);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);

      final TaskCheckInOutcome o1 =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(o1.status, CheckInStatus.verified);
      // 联动项奖励固定 = round(15×0.4)=6（不再乘完美日系数）
      expect(o1.reward, closeTo(6.0, 1e-9));

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: f2, session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );

      expect(ctx.tasks.checkIns, hasLength(1)); // f2 无新增行
      expect(ctx.ledger.entries, hasLength(1));
      expect(await ctx.ledger.balance(), closeTo(6.0, 1e-9));
    });

    test('A｜边界：换一场专注（不同 sessionId）当天仍可解锁第二个联动项', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      final Task f2 = _task(id: 'f2', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.addAll(<Task>[f1, f2]);
      final FocusSession s1 = ctx.focus
          .addSession(actualMin: 20, plannedMin: 20, start: day, id: 's1');
      final FocusSession s2 = ctx.focus.addSession(
          actualMin: 20,
          plannedMin: 20,
          start: day.add(const Duration(minutes: 30)),
          id: 's2');

      await ctx.svc.settleFocusLinked(task: f1, session: s1, now: day);
      final TaskCheckInOutcome o2 =
          await ctx.svc.settleFocusLinked(task: f2, session: s2, now: day);

      expect(o2.status, CheckInStatus.verified);
      expect(ctx.tasks.checkIns, hasLength(2));
      expect(ctx.tasks.checkIns.map((CheckIn c) => c.sessionId).toSet(),
          <String>{'s1', 's2'});
      // 6 + 6 = 12（未触软顶，不再乘完美日系数）
      expect(await ctx.ledger.balance(), closeTo(12.0, 1e-9));
    });

    // 原 ⚠️B：totalCheckInCount 统计全部状态 → 现只数 verified。
    test('B｜totalCheckInCount 只数 verified：1 verified + 1 pending + 1 rejected → 1',
        () async {
      final ctx = _make();
      ctx.tasks.store.addAll(
          <Task>[_task(id: 't1'), _task(id: 't2'), _task(id: 't3')]);
      await ctx.svc.checkIn(task: _task(id: 't1'), now: day);
      await ctx.svc.checkIn(task: _task(id: 't2'), now: day);
      await ctx.svc.checkIn(task: _task(id: 't3'), now: day);
      await ctx.svc.verifyCheckIn(ctx.tasks.checkIns[0].id, day); // verified
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns[1].id, now: day); // rejected

      expect(ctx.tasks.checkIns, hasLength(3));
      expect(await ctx.tasks.totalCheckInCount(), 1);
    });

    // 原 ⚠️D1：rejected 被当 done → 现不算完成。
    test('D1｜rejected 不计入 done（board 该项 done=false）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns.single.id, now: day);

      final TodayTaskBoard b = await ctx.svc.board(day);
      final TaskCheckInItem i = b.items.single;
      expect(i.done, isFalse); // 修复前为 true
      expect(i.pendingVerification, isFalse);
    });

    // 原 ⚠️D2：rejected 后卡死 → 现允许同日重做。
    test('D2｜rejected 后同日可重新打卡：新增 pending 行、board 转 done', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns.single.id, now: day);

      final TaskCheckInOutcome again = await ctx.svc.checkIn(task: t, now: day);
      expect(again.status, CheckInStatus.pending);
      expect(ctx.tasks.checkIns, hasLength(2)); // rejected + pending

      final TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.items.single.done, isTrue); // 取最新非 rejected 行
      expect(b.items.single.pendingVerification, isTrue);
    });

    // 原 ⚠️D3：rejected 凑完美日 → 现不计入 allDone。
    test('D3｜rejected 不顶替「已提交」：2 daily 之一被驳回 → doneCount=1、allDone=false',
        () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);
      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns[0].id, now: day); // 驳回 t1

      final TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.total, 2);
      expect(b.doneCount, 1); // 修复前为 2
      expect(b.allDone, isFalse); // 修复前为 true
    });

    // 原 ⚠️F：跨天旧会话结算今天 → 现抛错、不写记录。
    test('F｜跨天：用昨日的专注会话结算今天的联动项 → 抛错、零副作用', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.add(f1);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 30, plannedMin: 30, start: day); // 昨天
      await expectLater(
        () => ctx.svc.settleFocusLinked(task: f1, session: s, now: day2),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });

    // 原 ⚠️CONC（P0）：并发核销重复入账 → 现 CAS 保证仅一次。
    test('CONC｜并发两次 verifyCheckIn：仅一次成功、账本仅 1 条、余额仅 +12', () async {
      final ctx = _make();
      final Task t = _task(id: 't1'); // 非联动，reward 12
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final Future<String> f1 = ctx.svc
          .verifyCheckIn(id, day)
          .then((_) => 'ok', onError: (Object _) => 'err');
      final Future<String> f2 = ctx.svc
          .verifyCheckIn(id, day)
          .then((_) => 'ok', onError: (Object _) => 'err');
      final List<String> r = await Future.wait(<Future<String>>[f1, f2]);

      expect(r.where((String s) => s == 'ok').length, 1); // 仅一次成功
      expect(r.where((String s) => s == 'err').length, 1); // 另一条抛错
      expect(ctx.ledger.entries, hasLength(1));
      expect(await ctx.ledger.balance(), closeTo(12.0, 1e-9));
    });

    test('CONC｜并发 verify + reject 互斥：只按先到者定性，绝不变「verified 又 rejected」',
        () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final Future<String> fv = ctx.svc
          .verifyCheckIn(id, day)
          .then((_) => 'verify', onError: (Object _) => 'err');
      final Future<String> fr = ctx.svc
          .rejectCheckIn(id, now: day)
          .then((_) => 'reject', onError: (Object _) => 'err');
      final List<String> r = await Future.wait(<Future<String>>[fv, fr]);

      // 恰好一个成功；另一条因 CAS 失败抛错。
      expect(r.where((String s) => s != 'err').length, 1);
      final CheckIn c = (await ctx.tasks.checkInById(id))!;
      // 若 verify 先到：verified + 入账；若 reject 先到：rejected + 不入账。二者互斥。
      if (c.status == CheckInStatus.verified) {
        expect(ctx.ledger.entries, hasLength(1));
      } else {
        expect(c.status, CheckInStatus.rejected);
        expect(ctx.ledger.entries, isEmpty);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 三、新经济规则 40% 封顶（对抗边界）
  // ════════════════════════════════════════════════════════════════════════
  group('联动项 40% 封顶（对抗边界）', () {
    test('rewardCapFor：round(minFocus×0.4)，下限夹到 ≥1', () {
      expect(Task.rewardCapFor(15), 6);
      expect(Task.rewardCapFor(45), 18);
      expect(Task.rewardCapFor(1), 1); // round(0.4)=0 → 夹 1
      expect(Task.rewardCapFor(0), 1); // 防御性下限
      expect(Task.rewardCapFor(3), 1); // round(1.2)=1
    });

    test('联动项 effectiveSunlightReward = 固定 专注分钟×40%（不再取家长设值）；非联动原值', () {
      expect(
          _task(id: 'a', requiresFocus: true, minFocus: 15, reward: 40)
              .effectiveSunlightReward,
          6); // round(15×0.4)，家长设 40 不参与
      expect(
          _task(id: 'b', requiresFocus: true, minFocus: 15, reward: 5)
              .effectiveSunlightReward,
          6); // 固定 6，与家长设 5 无关
      expect(
          _task(id: 'c', requiresFocus: true, minFocus: 45, reward: 12)
              .effectiveSunlightReward,
          18); // round(45×0.4)，家长设 12 不参与
      expect(
          _task(id: 'd', requiresFocus: false, minFocus: 15, reward: 40)
              .effectiveSunlightReward,
          40); // 非联动不封顶
    });

    test('联动项结算走封顶值：15min/设12 → 固定 6（不再乘完美日系数）', () async {
      final ctx = _make();
      final Task f1 =
          _task(id: 'f1', requiresFocus: true, minFocus: 15, reward: 12);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final TaskCheckInOutcome o =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(o.reward, closeTo(_linkedReward(12, 15), 1e-9));
      expect(o.reward, closeTo(6.0, 1e-9));
      expect(o.granted, closeTo(6.0, 1e-9));
    });

    test('封顶只作用于联动项：非联动项 15min/设12 → 打卡仍 12（但 pending 不发）',
        () async {
      final ctx = _make();
      final Task n1 =
          _task(id: 'n1', requiresFocus: false, minFocus: 15, reward: 12);
      final TaskCheckInOutcome o = await ctx.svc.checkIn(task: n1, now: day);
      expect(o.reward, 12);
      expect(o.granted, 0); // pending
    });

    test('对抗：软顶仍在封顶值之上再削（联动固定 6，当日已发 76 → 只补软顶差）',
        () async {
      final ctx = _make();
      final Task f1 =
          _task(id: 'f1', requiresFocus: true, minFocus: 15, reward: 12);
      // 当日已发 76（net=76, gross=76）。
      ctx.ledger.seedEarn(dayKey(day), 76, 76, day);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final TaskCheckInOutcome o =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      // computeSoftCap(76+6=82)=60+(82-60)*0.5=71 → grant=71-76 <0 → 0
      expect(o.reward, closeTo(6.0, 1e-9));
      expect(o.granted, 0);
      expect(o.cappedBySoftCap, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 四、残留对抗（仍未闭环）
  // ════════════════════════════════════════════════════════════════════════
  group('残留对抗（待加固 / 待口径）', () {
    // C：任务删除后其 pending 仍可核销入账（engineer 未纳入本轮修复）。
    test('C｜任务删除后 pending 仍可核销入账（task==null 孤儿记录）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.tasks.deleteTaskById('t1');

      final List<PendingCheckIn> pending = await ctx.svc.pendingCheckIns();
      expect(pending, hasLength(1));
      expect(pending.single.task, isNull);

      // 记录当前行为：仍照常入账 12。
      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);
      expect(out.status, CheckInStatus.verified);
      expect(await ctx.ledger.balance(), 12);
    });

    // 残留对抗：`sessionAlreadyUsed` 守卫是「取快照 → 判 → 写」跨 await。
    // 理论上非原子；本用例用 40 次并发**反复尝试**触发双入账，并断言契约不变量。
    // 实测：本环境 40/40 均未双入账（守卫快照判定在实测微任务调度下未破）。
    // 若未来某环境/改动使其非原子，本用例将变红（即暴露真实 TOCTOU）→ 需加原子唯一守卫。
    test('R｜并发结算「同一 session」+「不同联动项」（40 次）：至多入账 1 条', () async {
      const int trials = 40;
      int bothWon = 0;
      for (int i = 0; i < trials; i++) {
        final ctx = _make();
        final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
        final Task f2 = _task(id: 'f2', requiresFocus: true, minFocus: 15);
        ctx.tasks.store.addAll(<Task>[f1, f2]);
        final FocusSession s = ctx.focus
            .addSession(actualMin: 20, plannedMin: 20, start: day, id: 's-$i');

        final Future<String> a = ctx.svc
            .settleFocusLinked(task: f1, session: s, now: day)
            .then((_) => 'ok', onError: (Object _) => 'err');
        final Future<String> b = ctx.svc
            .settleFocusLinked(task: f2, session: s, now: day)
            .then((_) => 'ok', onError: (Object _) => 'err');
        final List<String> r = await Future.wait(<Future<String>>[a, b]);
        final int okCount = r.where((String x) => x == 'ok').length;

        // 恒真不变量：成功次数 == 账本条数（无半写、无幽灵账本）。
        expect(ctx.ledger.entries.length, okCount, reason: 'trial $i: r=$r');
        // 契约（session 复用守卫）：同一 session 至多入账一次 → 至多 1 条账本。
        expect(ctx.ledger.entries.length, lessThanOrEqualTo(1),
            reason: 'trial $i: r=$r');
        expect(okCount, greaterThanOrEqualTo(1)); // 至少一次成功
        if (okCount == 2) bothWon++;
      }
      expect(bothWon, 0, reason: 'session 复用守卫双入账（TOCTOU）被触发'); // 实测 0
    });
  });
}
