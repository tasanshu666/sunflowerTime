/// QA 独立对抗性验证 V1–V10（用户拍板的 8 条经济规则 + 成长奖励额度缺口）。
///
/// 本文件是 **QA 视角的独立复现**，不依赖也不修改任何 lib/ 源码，不依赖 Drift /
/// Flutter（纯 Dart 内存 Fake，`dart test` 亦可跑）。断言的是**修复后的正确行为**：
/// 绿 = 护栏生效；红 = 该条修复未闭环（最小复现即为用例本身）。
///
/// 被测：lib/domain/services/task_checkin_service.dart
///       lib/domain/entities/task.dart（effectiveSunlightReward / rewardCapFor）
///       lib/core/constants/prd_params.dart（kTaskCheckinDailyCap）
///       lib/domain/repositories/task_repository.dart（CheckInAdminRepository CAS）
library adversarial_v1_v10_test;

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

// ── 内存 Fake 仓储（镜像真实仓储语义，自包含）────────────────────────────────

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

  /// 对齐真实仓储（修复 7）：只数 verified。
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

  /// 预置「当日已发成长奖励」净额（成长奖励日上限核算的前置态，2026-09-23 口径）。
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

  /// 当日 `refType='task_checkin'` 账本条数。
  int taskCheckInLedgerCount(String key) => entries
      .where((SunlightEntry e) =>
          e.refType == 'task_checkin' && e.dayKey == key)
      .length;
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

/// 并发调用一个 Future，把「成功」与「抛错」都收敛为字符串，便于 Future.wait。
Future<String> _probe(Future<void> Function() action) =>
    action().then((_) => 'ok', onError: (Object _) => 'err');

void main() {
  final DateTime day = DateTime(2026, 9, 22, 9, 0); // 周二 09:00
  final DateTime day2 = DateTime(2026, 9, 23, 9, 0); // 次日

  // ════════════════════════════════════════════════════════════════════════
  group('V1 并发同记录核销（防双倍入账 · P0 CAS）', () {
    test('V1 同时两次 verifyCheckIn(同一 id) → 恰好 1 成功 1 抛错、账本仅 1 条', () async {
      final ctx = _make();
      final Task t = _task(id: 't1'); // 非联动，reward 12
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;

      final List<String> r = await Future.wait(<Future<String>>[
        _probe(() => ctx.svc.verifyCheckIn(id, day)),
        _probe(() => ctx.svc.verifyCheckIn(id, day)),
      ]);

      expect(r.where((String s) => s == 'ok').length, 1, reason: '应恰好一次抢占成功');
      expect(r.where((String s) => s == 'err').length, 1, reason: '另一次应抛 TaskCheckInException');
      // 当日 task_checkin 账本仅 1 条。
      expect(ctx.ledger.taskCheckInLedgerCount(dayKey(day)), 1);
      // 余额只增加 1 份 reward。
      expect(await ctx.ledger.balance(), closeTo(12.0, 1e-9));
      // 该打卡 sunlightGranted 只有一份。
      expect(ctx.tasks.checkIns.single.sunlightGranted, closeTo(12.0, 1e-9));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V2 并发不同记录核销（额度差额非原子 · 第 8 项闸门靶子）', () {
    test('V2 额度余量只够一份 → 并发核销两条不同 pending，当日成长奖励净额 ≤ kTaskCheckinDailyCap',
        () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1'); // reward 12
      final Task t2 = _task(id: 't2'); // reward 12
      ctx.tasks.store.addAll(<Task>[t1, t2]);
      // 当日已发成长奖励 70 → 只剩 9 额度，只够一份「补差额」。
      ctx.ledger.seedCheckInNet(dayKey(day), 70, day);

      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day);
      final String id1 = ctx.tasks.checkIns[0].id;
      final String id2 = ctx.tasks.checkIns[1].id;

      final List<String> r = await Future.wait(<Future<String>>[
        _probe(() => ctx.svc.verifyCheckIn(id1, day)),
        _probe(() => ctx.svc.verifyCheckIn(id2, day)),
      ]);
      // 两条不同记录，均应成功（CAS 针对不同 id，各能抢占）。
      expect(r.where((String s) => s == 'ok').length, 2);

      final double net = await ctx.ledger
          .netByRefTypeOnDay(TaskCheckInService.checkInRefType, dayKey(day));
      // 核心不变量：当日成长奖励净额合计不得超过 kTaskCheckinDailyCap。
      // 未加串行闸门时：两条同时读 grantedSoFar=70 → 各补 9 → net=88 > 79。
      // （2026-09-23 前这里断言的是「当日全部 earn 过分段软顶」，该口径已作废。）
      expect(net, lessThanOrEqualTo(kTaskCheckinDailyCap + 1e-9),
          reason: '成长奖励上限被突破：net=$net > cap=$kTaskCheckinDailyCap');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V3 连点两次打卡（同非联动项 · 只落 1 条 pending）', () {
    test('V3 同时两次 checkIn(同一 task) → 仅 1 条 pending 行，另一次抛错', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);

      final List<String> r = await Future.wait(<Future<String>>[
        _probe(() => ctx.svc.checkIn(task: t, now: day)),
        _probe(() => ctx.svc.checkIn(task: t, now: day)),
      ]);

      expect(r.where((String s) => s == 'ok').length, 1, reason: '应仅一次打卡成功');
      expect(r.where((String s) => s == 'err').length, 1, reason: '另一次应抛 TaskCheckInException');
      // 当日该 task 只有 1 条打卡行。
      expect(
        ctx.tasks.checkIns.where((CheckIn c) => c.taskId == 't1').length,
        1,
        reason: '不应出现两条同名 pending（家长会看到两条）',
      );
      expect(ctx.tasks.checkIns.single.status, CheckInStatus.pending);
      // 家长端待核销也只有 1 条。
      expect(await ctx.svc.pendingCheckIns(), hasLength(1));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V4 一次专注只解锁一个联动项（会话复用守卫）', () {
    test('V4 同一 FocusSession 依次 settle 两个联动项 → 第二次抛错、无打卡/账本', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 10);
      final Task f2 = _task(id: 'f2', requiresFocus: true, minFocus: 10);
      ctx.tasks.store.addAll(<Task>[f1, f2]);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);

      final TaskCheckInOutcome o1 =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(o1.status, CheckInStatus.verified);

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: f2, session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );

      // 第二个任务当日无打卡行、无账本条目。
      expect(ctx.tasks.checkIns.where((CheckIn c) => c.taskId == 'f2'), isEmpty);
      expect(ctx.tasks.checkIns, hasLength(1));
      expect(ctx.ledger.entries, hasLength(1));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V5 跨天守卫（昨天专注不结算今天成长项）', () {
    test('V5 session.start=昨天 → 抛错、不产生打卡行/账本条目', () async {
      final ctx = _make();
      final Task f1 = _task(id: 'f1', requiresFocus: true, minFocus: 15);
      ctx.tasks.store.add(f1);
      // 会话发生在 day（昨天），now 为 day2（今天）。
      final FocusSession s =
          ctx.focus.addSession(actualMin: 30, plannedMin: 30, start: day);

      await expectLater(
        () => ctx.svc.settleFocusLinked(task: f1, session: s, now: day2),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.tasks.checkIns, isEmpty);
      expect(ctx.ledger.entries, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V6 rejected 语义（不算完成 / 可重做 / 不凑完美日）', () {
    test('V6a 驳回后 board：done=false、allDone=false；重做成功后 done=true', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns.single.id, now: day);

      final TodayTaskBoard b1 = await ctx.svc.board(day);
      expect(b1.items.single.done, isFalse);
      expect(b1.allDone, isFalse);

      // 被驳回后当日可重做。
      final TaskCheckInOutcome again = await ctx.svc.checkIn(task: t, now: day);
      expect(again.status, CheckInStatus.pending);

      final TodayTaskBoard b2 = await ctx.svc.board(day);
      expect(b2.items.single.done, isTrue);
    });

    test('V6b 完美日不被 rejected 顶掉：1 驳回 + 1 已提交 → allDone=false', () async {
      final ctx = _make();
      final Task t1 = _task(id: 't1');
      final Task t2 = _task(id: 't2');
      ctx.tasks.store.addAll(<Task>[t1, t2]);
      await ctx.svc.checkIn(task: t1, now: day);
      await ctx.svc.checkIn(task: t2, now: day);
      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns[0].id, now: day); // 驳回 t1

      final TodayTaskBoard b = await ctx.svc.board(day);
      expect(b.total, 2);
      expect(b.doneCount, 1);
      expect(b.allDone, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V7 40% 封顶边界', () {
    test('V7a rewardCapFor: 5/10/15/20/30/60 分钟 → 2/4/6/8/12/24', () {
      expect(Task.rewardCapFor(5), 2);
      expect(Task.rewardCapFor(10), 4);
      expect(Task.rewardCapFor(15), 6);
      expect(Task.rewardCapFor(20), 8);
      expect(Task.rewardCapFor(30), 12);
      expect(Task.rewardCapFor(60), 24);
    });

    test('V7b 联动项实际发放不超过上限；非联动项完全不受影响', () async {
      final ctx = _make();
      // 联动：minFocus 10（cap 4）、家长设 40 → 生效 4；session 10min（<15 不命中完美日）。
      final Task f1 =
          _task(id: 'f1', requiresFocus: true, minFocus: 10, reward: 40);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 10, plannedMin: 10, start: day);
      final TaskCheckInOutcome o =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(o.reward, closeTo(4.0, 1e-9), reason: '联动项应被封顶到 4');
      expect(await ctx.ledger.balance(), closeTo(4.0, 1e-9));

      // 非联动：minFocus 15、家长设 12 → 仍 12（不受 40% 封顶）。
      final _MemTaskRepo tRepo = _MemTaskRepo();
      final _MemSunlightRepo lRepo = _MemSunlightRepo();
      final TaskCheckInService svc2 = TaskCheckInService(
        tasks: tRepo,
        ledger: lRepo,
        focus: _MemFocusRepo(),
        settings: _MemSettingsRepo(),
      );
      final TaskCheckInOutcome o2 =
          await svc2.checkIn(task: _task(id: 'n1', minFocus: 15, reward: 12), now: day);
      expect(o2.reward, 12, reason: '非联动项不受封顶，仍 12');
    });

    test('V7c 联动项固定 = 专注分钟×40%：15min → 6（不再叠加完美日系数）', () async {
      final ctx = _make();
      final Task f1 =
          _task(id: 'f1', requiresFocus: true, minFocus: 15, reward: 12);
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day); // ≥15 命中完美日
      final TaskCheckInOutcome o =
          await ctx.svc.settleFocusLinked(task: f1, session: s, now: day);
      expect(o.reward, closeTo(6.0, 1e-9), reason: 'base=6，固定奖励，完美日仅徽章不加成');
      expect(o.granted, closeTo(6.0, 1e-9));
    });

    test('V7d 联动 20min/设18 → 8（固定 = 分钟×40%，完美日仅徽章不加成）', () {
      final Task t = _task(id: 'f2', requiresFocus: true, minFocus: 20, reward: 18);
      expect(t.effectiveSunlightReward, 8);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V8 统计口径（totalCheckInCount 只数 verified）', () {
    test('V8 只有 pending 时不变；verify 后 +1；reject 不计入', () async {
      final ctx = _make();
      ctx.tasks.store.addAll(
          <Task>[_task(id: 't1'), _task(id: 't2'), _task(id: 't3')]);

      await ctx.svc.checkIn(task: _task(id: 't1'), now: day);
      await ctx.svc.checkIn(task: _task(id: 't2'), now: day);
      await ctx.svc.checkIn(task: _task(id: 't3'), now: day);

      // 3 条 pending → 只数 verified → 0。
      expect(await ctx.tasks.totalCheckInCount(), 0);

      await ctx.svc.verifyCheckIn(ctx.tasks.checkIns[0].id, day);
      expect(await ctx.tasks.totalCheckInCount(), 1);

      await ctx.svc.rejectCheckIn(ctx.tasks.checkIns[1].id, now: day);
      expect(await ctx.tasks.totalCheckInCount(), 1, reason: 'rejected 不计入');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  group('V9 越界与异常路径', () {
    test('V9a 对 verified 再次 verify/reject → 抛错且不新增账本', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.verifyCheckIn(id, day);
      expect(ctx.ledger.entries, hasLength(1));

      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      await expectLater(
        () => ctx.svc.rejectCheckIn(id, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, hasLength(1), reason: '重复处理不得新增账本');
    });

    test('V9b 对 rejected 再次 verify/reject → 抛错且不入账', () async {
      final ctx = _make();
      final Task t = _task(id: 't1');
      ctx.tasks.store.add(t);
      await ctx.svc.checkIn(task: t, now: day);
      final String id = ctx.tasks.checkIns.single.id;
      await ctx.svc.rejectCheckIn(id, now: day);

      await expectLater(
        () => ctx.svc.verifyCheckIn(id, day),
        throwsA(isA<TaskCheckInException>()),
      );
      await expectLater(
        () => ctx.svc.rejectCheckIn(id, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
      expect(ctx.ledger.entries, isEmpty);
    });

    test('V9c checkIn 传联动项 → 抛错', () async {
      final ctx = _make();
      await expectLater(
        () => ctx.svc.checkIn(task: _task(id: 'f1', requiresFocus: true), now: day),
        throwsA(isA<TaskCheckInException>()),
      );
    });

    test('V9d settleFocusLinked 传非联动项 → 抛错', () async {
      final ctx = _make();
      final FocusSession s =
          ctx.focus.addSession(actualMin: 20, plannedMin: 20, start: day);
      await expectLater(
        () => ctx.svc.settleFocusLinked(
            task: _task(id: 'n1', requiresFocus: false), session: s, now: day),
        throwsA(isA<TaskCheckInException>()),
      );
    });

    test('V9e verifyCheckIn 传不存在 id → 抛「找不到这条记录」', () async {
      final ctx = _make();
      await expectLater(
        () => ctx.svc.verifyCheckIn('no-such-id', day),
        throwsA(
          isA<TaskCheckInException>().having(
              (TaskCheckInException e) => e.message, 'message', contains('找不到')),
        ),
      );
    });
  });
}
