/// M4 成长项打卡领域层测试：TaskCheckInService（§4.4 / §4.5）。
///
/// 口径（用户拍板，冻结）：
///  - **联动项**（requiresFocus == true）不能手动打卡；专注达标后由
///    [TaskCheckInService.settleFocusLinked] **自动结算**（直接打勾并入账）；
///  - **非联动项**（requiresFocus == false）手动打卡 → 落 **pending**（待家长核销），
///    当期**不发阳光**；家长 [TaskCheckInService.verifyCheckIn] 通过后才入账，
///    [TaskCheckInService.rejectCheckIn] 驳回则不入账；
///  - **pending 不占当日额度**：只有真正入账（verify / 自动结算）才计入当日已发合计；
///  - 入账按**成长奖励自身当日累计净额**封顶：`grant = max(0, min(reward,
///    kTaskCheckinDailyCap - 当日已发打卡阳光))`（2026-09-23 起取消分段软顶，
///    且**只读 `task_checkin` 自己的账目** —— 专注与家长赠予不占这个额度）；
///  - 奖励固定为 [Task.effectiveSunlightReward]（联动项 = 专注分钟 × 40%，不再叠加完美日系数）。
///
/// 纯 Dart：所有仓储以内存 Fake 实现，不依赖 Drift / Flutter，故用
/// `package:test/test.dart`（可在 `dart test` 与 `flutter test` 下运行）。
library task_checkin_test;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
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

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

/// 内存任务 / 打卡仓储，同时实现家长核销能力接口 [CheckInAdminRepository]。
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

  // ── CheckInAdminRepository（家长端核销，M4）─────────────────────────────

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

  /// CAS（内存等价实现）：仅当仍是 [from] 时写回；读-判-写之间无 await → 原子。
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
    );
    return true;
  }
}

class _MemorySunlightRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  /// 预置一条当日的 earn 记录（构造「当日已发阳光」的前置态）。
  ///
  /// [refType] 默认 `focus_session`（多数用例构造的是专注产出）；要构造
  /// 「当日已发**成长奖励**」的额度前置态请传 `task_checkin` —— 2026-09-23 起
  /// 成长奖励的每日上限**只按自己的账目**核算，专注/家长赠予都挤不动它。
  void seedEarn(
    String key,
    double gross,
    double net,
    DateTime ts, {
    String refType = 'focus_session',
  }) {
    entries.add(SunlightEntry(
      id: 'seed-${entries.length}',
      ts: ts,
      type: SunlightType.earn,
      gross: gross,
      net: net,
      balanceAfter: net,
      refType: refType,
      refId: 'seed',
      dayKey: key,
    ));
  }

  /// 预置「当日已发成长奖励」净额（成长奖励日上限核算的前置态）。
  void seedCheckInNet(String key, double net, DateTime ts) =>
      seedEarn(key, net, net, ts, refType: 'task_checkin');

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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

class _MemoryFocusRepo implements FocusRepository {
  final List<FocusSession> sessions = <FocusSession>[];

  /// 追加一次已完成的专注会话（planned/actual 允许不等以构造完成率）。
  void addSession({
    required double actualMin,
    required int plannedMin,
    required DateTime start,
  }) {
    sessions.add(FocusSession(
      id: 's-${sessions.length}',
      start: start,
      end: start.add(Duration(seconds: (actualMin * 60).round())),
      plannedMin: plannedMin,
      actualFocusMin: actualMin,
      status: FocusStatus.completed,
      sunlightEarned: 0,
      createdAt: start,
    ));
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
      if (_isValid(s)) days.add(dayKey(s.start));
    }
    return days.length;
  }

  @override
  Future<FocusStats> totalStats() async {
    double minutes = 0;
    final Set<String> days = <String>{};
    for (final FocusSession s in sessions) {
      minutes += s.actualFocusMin;
      if (_isValid(s)) days.add(dayKey(s.start));
    }
    return FocusStats(
      totalFocusMinutes: minutes,
      totalSessions: sessions.length,
      totalValidDays: days.length,
    );
  }

  bool _isValid(FocusSession s) {
    final double completion =
        s.plannedMin == 0 ? 0.0 : s.actualFocusMin / s.plannedMin;
    return s.actualFocusMin >= kValidFocusMinutes &&
        completion >= kCompletionRateThreshold;
  }
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
  Future<void> saveSettings(AppSettings settings) async => value = settings;
}

// ── 组装辅助 ────────────────────────────────────────────────────────────────

Task _task({
  required String id,
  bool requiresFocus = false,
  int reward = 12,
  int minFocus = 15,
  String? repeatRule, // null / 'daily' 视为「每天该做」；'weekly' 为非每日
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
  _MemoryTaskRepo tasks,
  _MemorySunlightRepo ledger,
  _MemoryFocusRepo focus,
}) _make() {
  final _MemoryTaskRepo tasks = _MemoryTaskRepo();
  final _MemorySunlightRepo ledger = _MemorySunlightRepo();
  final _MemoryFocusRepo focus = _MemoryFocusRepo();
  final TaskCheckInService svc = TaskCheckInService(
    tasks: tasks,
    ledger: ledger,
    focus: focus,
    settings: _MemorySettingsRepo(),
  );
  return (svc: svc, tasks: tasks, ledger: ledger, focus: focus);
}

void main() {
  final DateTime day = DateTime(2026, 9, 22, 9, 0); // 周二 09:00

  group('非联动项：手动打卡落 pending（当期不发阳光）', () {
    test('首次打卡：status=pending、granted=0、账本零新增、sunlightGross=12', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');

      final TaskCheckInOutcome out = await ctx.svc.checkIn(task: t, now: day);

      expect(out.status, CheckInStatus.pending);
      expect(out.reward, 12);
      expect(out.granted, 0);
      expect(out.cappedByDailyCap, isFalse);
      expect(out.perfectDayBonus, isFalse);
      expect(out.checkInId, isNotEmpty);

      // 关键：当期绝不写账本、不产生余额。
      expect(ctx.ledger.entries, isEmpty);
      expect(await ctx.ledger.balance(), 0);

      final CheckIn c = ctx.tasks.checkIns.single;
      expect(c.taskId, 't1');
      expect(c.status, CheckInStatus.pending);
      expect(c.sunlightGross, 12); // 应发在 pending 阶段即可展示
      expect(c.sunlightGranted, 0); // 实发为 0
      expect(c.sessionId, isNull);
      expect(c.resolvedAt, isNull);
    });

    test('同一成长项同日重复打卡 → 抛 TaskCheckInException，不重复落库', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);

      await expectLater(
        () => ctx.svc.checkIn(task: t, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, hasLength(1));
      expect(ctx.ledger.entries, isEmpty);
    });

    test('完美日（当日有 ≥15 分钟专注）：reward 仍为固定 12（不再乘 ×1.5），pending 仍不入账',
        () async {
      final ctx = _make();
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final Task t = _task(id: 't1');

      final TaskCheckInOutcome out = await ctx.svc.checkIn(task: t, now: day);

      expect(out.perfectDayBonus, isTrue);
      expect(out.reward, closeTo(12.0, 1e-9));
      expect(out.granted, 0); // 尚未核销 → 不入账
      expect(ctx.tasks.checkIns.single.sunlightGross, closeTo(12.0, 1e-9));
      expect(ctx.tasks.checkIns.single.sunlightGranted, 0);
      expect(ctx.ledger.entries, isEmpty);
    });
  });

  group('联动项：不可手动打卡，专注达标自动结算', () {
    test('requiresFocus=true 手动打卡 → 抛 TaskCheckInException，不写任何记录', () async {
      final ctx = _make();
      final Task t = _task(id: 'f1', requiresFocus: true, minFocus: 15);

      await expectLater(
        () => ctx.svc.checkIn(task: t, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });

    test('settleFocusLinked 达标：status=verified、当期入账、sessionId 关联', () async {
      final ctx = _make();
      final Task t = _task(id: 'f1', requiresFocus: true, minFocus: 15, reward: 12);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      final TaskCheckInOutcome out =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);

      expect(out.status, CheckInStatus.verified);
      // 联动 15 分钟项奖励固定 = round(15×0.4)=6（不再叠加完美日系数）。
      expect(out.reward, closeTo(6.0, 1e-9));
      expect(out.granted, closeTo(6.0, 1e-9));
      expect(out.perfectDayBonus, isTrue);

      final CheckIn c = ctx.tasks.checkIns.single;
      expect(c.status, CheckInStatus.verified);
      expect(c.sessionId, s.id); // 关联到满足门槛的会话
      expect(c.sunlightGranted, closeTo(6.0, 1e-9));

      expect(ctx.ledger.entries, hasLength(1));
      final SunlightEntry e = ctx.ledger.entries.single;
      expect(e.refType, 'task_checkin');
      expect(e.refId, c.id);
      expect(e.gross, closeTo(6.0, 1e-9));
      expect(e.net, closeTo(6.0, 1e-9));
      expect(await ctx.ledger.balance(), closeTo(6.0, 1e-9));
    });

    test('settleFocusLinked 不达标（专注 < minFocus）→ status=rejected，不写记录不写账本',
        () async {
      final ctx = _make();
      final Task t = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      ctx.focus.addSession(actualMin: 10, plannedMin: 20, start: day); // 10 < 15
      final FocusSession s = ctx.focus.sessions.single;

      final TaskCheckInOutcome out =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);

      expect(out.status, CheckInStatus.rejected);
      expect(out.checkInId, isEmpty);
      expect(out.granted, 0);
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });

    test('settleFocusLinked 幂等：同日再次结算返回既有结果，不重复入账', () async {
      final ctx = _make();
      final Task t = _task(id: 'f1', requiresFocus: true, minFocus: 15, reward: 12);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      final TaskCheckInOutcome out1 =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);
      final TaskCheckInOutcome out2 =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);

      expect(out2.checkInId, out1.checkInId);
      expect(out2.status, CheckInStatus.verified);
      expect(out2.granted, closeTo(out1.granted, 1e-9));
      expect(ctx.tasks.checkIns, hasLength(1));
      expect(ctx.ledger.entries, hasLength(1));
      expect(await ctx.ledger.balance(), closeTo(out1.granted, 1e-9));
    });

    test('settleFocusLinked 用于非联动项 → 抛 TaskCheckInException', () async {
      final ctx = _make();
      final Task t = _task(id: 'n1', requiresFocus: false);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: t, session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });
  });

  group('家长端核销：pendingCheckIns / verify / reject', () {
    test('pendingCheckIns 列出全部待核销并附带成长项名、按 completedAt 升序', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);

      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day.add(const Duration(minutes: 1)));

      final List<PendingCheckIn> pending = await ctx.svc.pendingCheckIns();
      expect(pending, hasLength(2));
      expect(pending.first.checkIn.taskId, 't1');
      expect(pending.first.task?.name, '任务t1');
      expect(pending.last.checkIn.taskId, 't2');
    });

    test('pendingCheckIns 不含已核销 / 已驳回记录', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);
      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day.add(const Duration(minutes: 1)));
      await ctx.svc.verifyCheckIn(ctx.tasks.checkIns[0].id, day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns[1].id, now: day);

      expect(await ctx.svc.pendingCheckIns(), isEmpty);
    });

    test('verifyCheckIn：pending → verified、账本入账、granted/resolvedAt 落库', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      expect(ctx.ledger.entries, isEmpty);

      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);

      expect(out.status, CheckInStatus.verified);
      expect(out.granted, 12);
      expect(ctx.ledger.entries, hasLength(1));
      final SunlightEntry e = ctx.ledger.entries.single;
      expect(e.refType, 'task_checkin');
      expect(e.refId, id);
      expect(e.gross, 12);
      expect(e.net, 12);
      expect(await ctx.ledger.balance(), 12);

      final CheckIn c = (await ctx.tasks.checkInById(id))!;
      expect(c.status, CheckInStatus.verified);
      expect(c.sunlightGranted, 12);
      expect(c.resolvedAt, isNotNull);
    });

    test('verifyCheckIn 二次调用 → 抛异常且不重复入账（防重，这是钱）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.verifyCheckIn(id, day);

      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, hasLength(1)); // 关键：无二次入账
      expect(await ctx.ledger.balance(), 12);
    });

    test('verifyCheckIn 记录不存在 → 抛异常', () async {
      final ctx = _make();
      await expectLater(
        () => ctx.svc.verifyCheckIn('missing', day),
        throwsA(isA<TaskCheckInException>()),
      );
    });

    test('rejectCheckIn：pending → rejected、不入账、记录理由、不能再核销', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      await ctx.svc.rejectCheckIn(id, note: '还没有完成', now: day);

      final CheckIn c = (await ctx.tasks.checkInById(id))!;
      expect(c.status, CheckInStatus.rejected);
      expect(c.parentNote, '还没有完成');
      expect(c.sunlightGranted, 0);
      expect(c.resolvedAt, isNotNull);
      expect(ctx.ledger.entries, isEmpty);

      // 已驳回 → 不能再核销（钱不能二次发）。
      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, isEmpty);
    });

    test('rejectCheckIn 只对 pending 生效：已核销记录 → 抛异常', () async {
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
  });

  group('软顶：核销时按打卡原始日补差额 / 封顶；pending 不占额度', () {
    test('pending 不占当日 earn 合计：核销前 earnGross=0，逐条核销后累加', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);

      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day);
      expect(await ctx.ledger.earnGrossOnDay(dayKey(day)), 0); // 两条都还没核销
      expect(ctx.ledger.entries, isEmpty);

      final String id1 = ctx.tasks.checkIns[0].id;
      final String id2 = ctx.tasks.checkIns[1].id;
      await ctx.svc.verifyCheckIn(id1, day);
      expect(await ctx.ledger.earnGrossOnDay(dayKey(day)), 12);
      await ctx.svc.verifyCheckIn(id2, day);
      expect(await ctx.ledger.earnGrossOnDay(dayKey(day)), 24);
    });

    test('当日已发成长奖励 55：再核销 12 全额发放（55+12=67 < 79）', () async {
      final ctx = _make();
      ctx.ledger.seedCheckInNet(dayKey(day), 55, day);
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);

      // 2026-09-23 口径：成长奖励日上限 79，额度内 1:1 全额发放，不再按分段打薄。
      expect(out.reward, 12);
      expect(out.granted, closeTo(12, 1e-9));
      expect(out.cappedByDailyCap, isFalse);

      expect(ctx.ledger.entries, hasLength(2));
      final SunlightEntry e = ctx.ledger.entries.last;
      expect(e.gross, 12);
      expect(e.net, closeTo(12, 1e-9));
      expect(await ctx.ledger.balance(), closeTo(67, 1e-9));
    });

    test('当日已发成长奖励 75：核销 12 只补 4（撞 79 上限，capped=true）', () async {
      final ctx = _make();
      ctx.ledger.seedCheckInNet(dayKey(day), 75, day);
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);

      expect(out.reward, 12);
      expect(out.granted, closeTo(4, 1e-9));
      expect(out.cappedByDailyCap, isTrue);
      expect(await ctx.ledger.balance(), closeTo(79, 1e-9));
    });

    test('当日成长奖励已触顶（79）：核销 granted=0、capped=true，账本仍新增 gross=12/net=0',
        () async {
      final ctx = _make();
      ctx.ledger.seedCheckInNet(dayKey(day), kTaskCheckinDailyCap, day);
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);

      expect(out.reward, 12);
      expect(out.granted, 0);
      expect(out.cappedByDailyCap, isTrue);

      // 账本仍新增一条（可追溯「核销过但被上限拦住」）。
      expect(ctx.ledger.entries, hasLength(2));
      final SunlightEntry e = ctx.ledger.entries.last;
      expect(e.type, SunlightType.earn);
      expect(e.gross, 12);
      expect(e.net, 0);
      expect(await ctx.ledger.balance(), closeTo(79.0, 1e-9));
    });

    // 回归（2026-09-23 解耦）：这正是本次修掉的 bug ——
    // 旧口径下「当日 earn 合计」把专注与家长赠予也算进去，专注打满 79 或家长
    // 送一笔，就会把孩子当天所有成长打卡奖励挤成 0（家长核销了也一分不得）。
    test('回归：专注拿满 + 家长赠予都不挤占成长奖励额度', () async {
      final ctx = _make();
      ctx.ledger.seedEarn(dayKey(day), 120, 120, day); // 专注拿满（高年段）
      ctx.ledger.seedEarn(dayKey(day), 100, 100, day,
          refType: 'parent_gift'); // 家长赠予
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final TaskCheckInOutcome out = await ctx.svc.verifyCheckIn(id, day);

      expect(out.reward, 12);
      expect(out.granted, closeTo(12, 1e-9),
          reason: '成长奖励不占专注额度，专注/赠予再高也不能把它挤成 0');
      expect(out.cappedByDailyCap, isFalse);
      expect(await ctx.ledger.balance(), closeTo(232, 1e-9));
    });
  });

  group('今日任务板 board()', () {
    test('完成度派生：total / doneCount / allDone（pending 也算已提交）', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);

      TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.total, 2);
      expect(b.doneCount, 0);
      expect(b.allDone, isFalse);

      await ctx.svc.checkIn(task: t1, now: day); // pending
      b = await ctx.svc.board(day);
      expect(b.doneCount, 1); // 待核销也算「已提交」
      expect(b.allDone, isFalse);

      await ctx.svc.verifyCheckIn(ctx.tasks.checkIns.single.id, day);
      b = await ctx.svc.board(day);
      expect(b.doneCount, 1); // 核销后仍是已提交

      await ctx.svc.checkIn(task: t2, now: day);
      b = await ctx.svc.board(day);
      expect(b.doneCount, 2);
      expect(b.allDone, isTrue);
    });

    test('board 标注 pendingVerification：非联动项打卡后 true；联动项恒 false & focusSatisfied',
        () async {
      final ctx = _make();
      final Task n1 = _task(id: 'n1'); // 非联动
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.addAll(<Task>[n1, f1]);

      await ctx.svc.checkIn(task: n1, now: day); // → pending

      final TodayTaskBoard b = await ctx.svc.board(day);
      final TaskCheckInItem iN =
          b.items.firstWhere((TaskCheckInItem i) => i.task.id == 'n1');
      expect(iN.done, isTrue);
      expect(iN.pendingVerification, isTrue);

      final TaskCheckInItem iF =
          b.items.firstWhere((TaskCheckInItem i) => i.task.id == 'f1');
      expect(iF.done, isFalse);
      expect(iF.pendingVerification, isFalse);
      expect(iF.focusSatisfied, isFalse); // 当日无专注
    });

    test('联动项自动结算后：board 显示已提交且无需核销、focusSatisfied=true', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.add(f1);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);

      final TodayTaskBoard b = await ctx.svc.board(day);
      final TaskCheckInItem iF = b.items.single;
      expect(iF.done, isTrue);
      expect(iF.pendingVerification, isFalse); // verified 不算待核销
      expect(iF.focusSatisfied, isTrue);
    });

    test('混合：2 daily + 1 weekly，只打完 2 daily → allDone=true，weekly 不卡完美日', () async {
      final ctx = _make();
      final Task d1 = _task(id: 'd1', repeatRule: null); // null 视为每天该做
      final Task d2 = _task(id: 'd2', repeatRule: 'daily');
      final Task w1 = _task(id: 'w1', repeatRule: 'weekly');
      ctx.tasks.store.addAll(<Task>[d1, d2, w1]);

      TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.items.length, 3); // 列表仍列全部任务（weekly 也要能打卡）
      expect(b.total, 2); // 完成度只算 daily
      expect(b.weeklyCount, 1);
      expect(b.doneCount, 0);
      expect(b.allDone, isFalse);

      await ctx.svc.checkIn(task: d1, now: day);
      await ctx.svc.checkIn(task: d2, now: day);

      b = await ctx.svc.board(day);
      expect(b.total, 2);
      expect(b.doneCount, 2);
      expect(b.allDone, isTrue); // 关键：weekly 未打卡也不该阻止完美日
      expect(b.items.length, 3);
      expect(b.weeklyCount, 1);
    });

    test('混合：2 daily 只打完 1 个 → allDone=false', () async {
      final ctx = _make();
      final Task d1 = _task(id: 'd1', repeatRule: 'daily');
      final Task d2 = _task(id: 'd2', repeatRule: 'daily');
      final Task w1 = _task(id: 'w1', repeatRule: 'weekly');
      ctx.tasks.store.addAll(<Task>[d1, d2, w1]);

      await ctx.svc.checkIn(task: d1, now: day);

      final TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.total, 2);
      expect(b.doneCount, 1);
      expect(b.allDone, isFalse);
    });

    test('weekly 成长项仍可打卡（落 pending）', () async {
      final ctx = _make();
      final Task w1 = _task(id: 'w1', repeatRule: 'weekly');
      ctx.tasks.store.add(w1);

      final TaskCheckInOutcome out = await ctx.svc.checkIn(task: w1, now: day);

      expect(out.status, CheckInStatus.pending);
      expect(ctx.tasks.checkIns.single.taskId, 'w1');
    });

    test('边界：全部都是 weekly、一个都没打 → total=0、allDone=false（不除零、不误判完成）',
        () async {
      final ctx = _make();
      final Task w1 = _task(id: 'w1', repeatRule: 'weekly');
      final Task w2 = _task(id: 'w2', repeatRule: 'weekly');
      ctx.tasks.store.addAll(<Task>[w1, w2]);

      final TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.items.length, 2);
      expect(b.total, 0);
      expect(b.doneCount, 0);
      expect(b.weeklyCount, 2);
      expect(b.allDone, isFalse);
    });
  });

  group('完美日联动：末项提交置 isPerfectDay', () {
    test('全部 daily 提交后 → outcome.allTasksDone=true 且 CheckIn.isPerfectDay=true', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);

      final TaskCheckInOutcome out1 = await ctx.svc.checkIn(task: t1, now: day);
      expect(out1.allTasksDone, isFalse);

      final TaskCheckInOutcome out2 = await ctx.svc.checkIn(task: t2, now: day);
      expect(out2.allTasksDone, isTrue);

      expect(ctx.tasks.checkIns.first.isPerfectDay, isFalse);
      expect(ctx.tasks.checkIns.last.isPerfectDay, isTrue);
      expect(ctx.tasks.checkIns.last.taskId, 't2');
    });

    test('联动项自动结算也算已提交 → 与另一 daily 一起判完美日', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[f1, t2]);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      // 先自动结算联动项：还差 t2 → 未完美。
      final TaskCheckInOutcome of =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(of.allTasksDone, isFalse);

      // 再提交 t2 → 两个 daily 都提交 → 完美日。
      final TaskCheckInOutcome ot = await ctx.svc.checkIn(task: t2, now: day);
      expect(ot.allTasksDone, isTrue);
      expect(ctx.tasks.checkIns.last.isPerfectDay, isTrue);
      expect(ctx.tasks.checkIns.last.taskId, 't2');
    });

    test('混合：打完全部 daily → isPerfectDay=true（weekly 未打也为 true）', () async {
      final ctx = _make();
      final Task d1 = _task(id: 'd1', repeatRule: 'daily');
      final Task d2 = _task(id: 'd2', repeatRule: 'daily');
      final Task w1 = _task(id: 'w1', repeatRule: 'weekly');
      ctx.tasks.store.addAll(<Task>[d1, d2, w1]);

      final TaskCheckInOutcome o1 = await ctx.svc.checkIn(task: d1, now: day);
      expect(o1.allTasksDone, isFalse);
      expect(ctx.tasks.checkIns.last.isPerfectDay, isFalse);

      final TaskCheckInOutcome o2 = await ctx.svc.checkIn(task: d2, now: day);
      expect(o2.allTasksDone, isTrue); // 只差 weekly（未打）也判完美日
      expect(ctx.tasks.checkIns.last.isPerfectDay, isTrue);

      // weekly 补打卡不影响完美日结论（仍为 true）。
      final TaskCheckInOutcome o3 = await ctx.svc.checkIn(task: w1, now: day);
      expect(o3.allTasksDone, isTrue);
      expect(ctx.tasks.checkIns.last.isPerfectDay, isTrue);
      expect(ctx.tasks.checkIns.last.taskId, 'w1');
    });
  });

  group('新经济规则：联动项奖励 40% 封顶（修复 1）', () {
    test('rewardCapFor / effectiveSunlightReward 口径', () {
      expect(Task.rewardCapFor(10), 4); // round(10 × 0.4)
      expect(Task.rewardCapFor(15), 6); // round(15 × 0.4)
      expect(Task.rewardCapFor(20), 8);
      expect(Task.rewardCapFor(40), 16);
      expect(Task.rewardCapFor(1), 1); // round(0.4) = 0 → 至少 1

      final Task linked =
          _task(id: 'f', requiresFocus: true, minFocus: 15, reward: 12);
      expect(linked.rewardCap, 6);
      expect(linked.effectiveSunlightReward, 6); // 固定 = round(15×0.4)=6（家长设值不参与）

      final Task linkedUnderCap =
          _task(id: 'f2', requiresFocus: true, minFocus: 15, reward: 5);
      expect(linkedUnderCap.effectiveSunlightReward, 6); // 固定 6，与家长设 5 无关

      final Task manual =
          _task(id: 'n', requiresFocus: false, minFocus: 15, reward: 12);
      expect(manual.effectiveSunlightReward, 12); // 非联动不受封顶影响
    });

    test('联动 10 分钟 + 设 40：无完美日（会话 10 分钟）→ reward==4、granted==4', () async {
      final ctx = _make();
      final Task t = _task(id: 'f10', requiresFocus: true, minFocus: 10, reward: 40);
      ctx.focus.addSession(actualMin: 10, plannedMin: 10, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      final TaskCheckInOutcome out =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);

      expect(out.perfectDayBonus, isFalse); // 10 < 15 → 非完美日
      expect(out.reward, closeTo(4.0, 1e-9)); // 生效值 = min(40, 4)
      expect(out.granted, closeTo(4.0, 1e-9));
      expect(await ctx.ledger.balance(), closeTo(4.0, 1e-9));
    });

    test('联动 15 分钟 + 设 12：奖励固定封顶 6（不再乘完美日系数）', () async {
      final ctx = _make();
      final Task t = _task(id: 'f15', requiresFocus: true, minFocus: 15, reward: 12);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      final TaskCheckInOutcome out =
          await ctx.svc.settleFocusLinked(task: t, session: s, now: day);

      expect(out.perfectDayBonus, isTrue);
      expect(out.reward, closeTo(6.0, 1e-9)); // 生效值固定 = round(15×0.4)=6
      expect(out.granted, closeTo(6.0, 1e-9));
    });

    test('非联动 15 分钟设 12：不受封顶 → checkIn reward==12', () async {
      final ctx = _make();
      final Task t = _task(id: 'n', requiresFocus: false, minFocus: 15, reward: 12);

      final TaskCheckInOutcome out = await ctx.svc.checkIn(task: t, now: day);

      expect(out.reward, 12);
      expect(ctx.tasks.checkIns.single.sunlightGross, 12);
    });
  });

  group('修复 2（P0）：并发双核销只能入账一次', () {
    test('两次并发 verifyCheckIn：仅一次成功，账本仅 1 条、余额仅 +12、granted 记一份',
        () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      Future<Object?> attempt() async {
        try {
          return await ctx.svc.verifyCheckIn(id, day);
        } catch (e) {
          return e;
        }
      }

      final List<Object?> results =
          await Future.wait(<Future<Object?>>[attempt(), attempt()]);

      expect(results.whereType<TaskCheckInOutcome>().length, 1);
      expect(results.whereType<TaskCheckInException>().length, 1);

      final List<SunlightEntry> rows = ctx.ledger.entries
          .where((SunlightEntry e) => e.refType == 'task_checkin')
          .toList();
      expect(rows, hasLength(1)); // 关键：无第二次入账
      expect(await ctx.ledger.balance(), 12);

      final CheckIn c = (await ctx.tasks.checkInById(id))!;
      expect(c.status, CheckInStatus.verified);
      expect(c.sunlightGranted, 12); // 只记一份
    });
  });

  group('修复 3（P1）：一次专注会话只能解锁一个成长项', () {
    test('同一 FocusSession 依次结算两个联动项：第二个抛异常且无新增打卡行', () async {
      final ctx = _make();
      final Task a = _task(id: 'a', requiresFocus: true, minFocus: 10, reward: 40);
      final Task b = _task(id: 'b', requiresFocus: true, minFocus: 10, reward: 40);
      ctx.tasks.store.addAll(<Task>[a, b]);
      ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      final FocusSession s = ctx.focus.sessions.single;

      await ctx.svc.settleFocusLinked(task: a, session: s, now: day);

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: b, session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );

      // 只有 a 落了一行；b 当日无打卡行。
      expect(ctx.tasks.checkIns.map((CheckIn c) => c.taskId).toList(),
          <String>['a']);
    });
  });

  group('修复 4（P1）：跨天专注不得结算今天的成长项', () {
    test('session.start 为昨天 → 抛异常且不产生任何打卡行', () async {
      final ctx = _make();
      final Task t = _task(id: 'f', requiresFocus: true, minFocus: 10);
      ctx.focus.addSession(
        actualMin: 20,
        plannedMin: 20,
        start: day.subtract(const Duration(days: 1)),
      );
      final FocusSession s = ctx.focus.sessions.single;

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: t, session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });
  });

  group('修复 5/6（P2）：驳回不算完成 + 驳回后当日可重做', () {
    test('驳回后 board 该项 done=false/allDone=false；重做成功后 done=true', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);

      await ctx.svc.checkIn(task: t, now: day);
      final String firstId = ctx.tasks.checkIns.single.id;
      await ctx.svc.rejectCheckIn(firstId, note: '还没做', now: day);

      TodayTaskBoard b = await ctx.svc.board(day);
      final TaskCheckInItem i = b.items.single;
      expect(i.done, isFalse); // rejected 不算「做到」
      expect(i.pendingVerification, isFalse);
      expect(b.doneCount, 0);
      expect(b.allDone, isFalse);

      // 驳回后允许重做 → 新增一行，不改旧行（旧行保留审计痕迹）。
      final TaskCheckInOutcome out2 = await ctx.svc.checkIn(
        task: t,
        now: day.add(const Duration(minutes: 5)),
      );
      expect(out2.status, CheckInStatus.pending);
      expect(ctx.tasks.checkIns, hasLength(2)); // 旧 rejected 行仍在

      b = await ctx.svc.board(day);
      expect(b.items.single.done, isTrue); // 命中新行的 pending
      expect(b.allDone, isTrue);
    });
  });

  group('修复 7（P2）：打卡总数只数已核销', () {
    test('pending 不计入 totalCheckInCount；verifyCheckIn 后才 +1', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      expect(await ctx.tasks.totalCheckInCount(), 0); // pending 不算

      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.verifyCheckIn(id, day);
      expect(await ctx.tasks.totalCheckInCount(), 1); // 已核销才算
    });
  });

  group('DAO 层（内存 Drift）：CAS 与统计口径（修复 2/7 的 SQL 事实源）', () {
    late db.AppDatabase database;

    setUp(() {
      database = db.AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('resolveCheckInIfStatus：首次 true、二次 false（SQL 级 CAS，仅 pending→verified 生效）',
        () async {
      final DateTime at = DateTime(2026, 9, 22, 9, 0);
      await database.taskDao.insertCheckIn(db.CheckInsCompanion(
        id: const Value('c1'),
        taskId: const Value('t1'),
        date: Value(at),
        completedAt: Value(at),
        isPerfectDay: const Value(false),
        status: Value(CheckInStatus.pending.index),
        sunlightGross: const Value(12.0),
        sunlightGranted: const Value(0.0),
      ));

      final int first = await database.taskDao.resolveCheckInIfStatus(
        id: 'c1',
        fromStatus: CheckInStatus.pending.index,
        toStatus: CheckInStatus.verified.index,
        sunlightGranted: 12.0,
        resolvedAt: at,
      );
      // 已非 pending → 第二次抢占失败（受影响 0 行；并发双核销的第二笔据此放弃入账）。
      final int second = await database.taskDao.resolveCheckInIfStatus(
        id: 'c1',
        fromStatus: CheckInStatus.pending.index,
        toStatus: CheckInStatus.verified.index,
        sunlightGranted: 12.0,
        resolvedAt: at,
      );

      expect(first, 1); // 受影响 1 行 = 抢占成功
      expect(second, 0); // 受影响 0 行 = 抢占失败

      final db.CheckIn? c = await database.taskDao.checkInById('c1');
      expect(c!.status, CheckInStatus.verified.index);
      expect(c.sunlightGranted, 12.0);
    });

    test('countCheckInsByStatus：只数指定状态（pending 不计入 verified）', () async {
      final DateTime at = DateTime(2026, 9, 22, 9, 0);
      await database.taskDao.insertCheckIn(db.CheckInsCompanion(
        id: const Value('p1'),
        taskId: const Value('t1'),
        date: Value(at),
        completedAt: Value(at),
        isPerfectDay: const Value(false),
        status: Value(CheckInStatus.pending.index),
      ));
      await database.taskDao.insertCheckIn(db.CheckInsCompanion(
        id: const Value('v1'),
        taskId: const Value('t2'),
        date: Value(at),
        completedAt: Value(at),
        isPerfectDay: const Value(false),
        status: Value(CheckInStatus.verified.index),
      ));

      expect(
        await database.taskDao
            .countCheckInsByStatus(CheckInStatus.verified.index),
        1,
      );
      expect(
        await database.taskDao
            .countCheckInsByStatus(CheckInStatus.pending.index),
        1,
      );
    });
  });

  group('修复 8（P0 补充）：写路径串行化闸门（额度并发绕过 / 连点双打卡）', () {
    test('两条不同记录并发核销：当日成长奖励净额不突破 kTaskCheckinDailyCap', () async {
      final ctx = _make();
      // 预置「已发成长奖励」70：只剩 9 额度，两条各 12 的核销必然互相抢额度。
      ctx.ledger.seedCheckInNet(dayKey(day), 70, day);
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);
      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day);
      final String id1 = ctx.tasks.checkIns[0].id;
      final String id2 = ctx.tasks.checkIns[1].id;

      final List<TaskCheckInOutcome> outs =
          await Future.wait(<Future<TaskCheckInOutcome>>[
        ctx.svc.verifyCheckIn(id1, day),
        ctx.svc.verifyCheckIn(id2, day),
      ]);
      expect(outs, hasLength(2)); // 两条不同记录都应成功（CAS 不冲突）

      final double net = await ctx.ledger
          .netByRefTypeOnDay(TaskCheckInService.checkInRefType, dayKey(day));
      // 关键不变式：并发核销绝不能把当日成长奖励总额顶穿上限。
      expect(net, lessThanOrEqualTo(kTaskCheckinDailyCap + 1e-9),
          reason: '上限被突破：net=$net > cap=$kTaskCheckinDailyCap');
      // 串行化后恰好落满 79（第二条只补 9，余下 3 不发）。
      expect(net, closeTo(kTaskCheckinDailyCap, 1e-9));
      final double grantedSum =
          outs.fold(0.0, (double a, TaskCheckInOutcome o) => a + o.granted);
      expect(grantedSum, closeTo(kTaskCheckinDailyCap - 70, 1e-9));
    });

    test('连点两次「我做到了」：仅 1 条 pending，另一次抛 TaskCheckInException', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');

      Future<Object?> attempt() async {
        try {
          return await ctx.svc.checkIn(task: t, now: day);
        } catch (e) {
          return e;
        }
      }

      final List<Object?> results =
          await Future.wait(<Future<Object?>>[attempt(), attempt()]);

      expect(results.whereType<TaskCheckInOutcome>().length, 1);
      expect(results.whereType<TaskCheckInException>().length, 1);
      final List<CheckIn> rows =
          ctx.tasks.checkIns.where((CheckIn c) => c.taskId == 't1').toList();
      expect(rows, hasLength(1)); // 不再出现两条同名 pending
      expect(rows.single.status, CheckInStatus.pending);
    });

    test('闸门不吞异常：并发中失败的那次原样抛 TaskCheckInException（文案不变）', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      Future<Object?> attempt(Future<Object?> Function() f) async {
        try {
          return await f();
        } catch (e) {
          return e;
        }
      }

      final List<Object?> results = await Future.wait(<Future<Object?>>[
        attempt(() => ctx.svc.verifyCheckIn(id, day)),
        attempt(() => ctx.svc.verifyCheckIn('missing-id', day)),
      ]);

      expect(results.whereType<TaskCheckInOutcome>().length, 1);
      final List<TaskCheckInException> errs =
          results.whereType<TaskCheckInException>().toList();
      expect(errs, hasLength(1));
      expect(errs.single.message, '找不到这条记录，可能已被删除');
    });
  });
}
