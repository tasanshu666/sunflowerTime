/// 成长项打卡领域服务 TaskCheckInService（M4，§4.4 / §4.5）。
///
/// 口径（用户拍板，冻结）：
///  - **联动项**（[Task.requiresFocus] == true）：从成长项「开始专注」→ 专注达标 →
///    [settleFocusLinked] **自动结算**：直接打勾并当期入账（孩子无需点击）。
///  - **非联动项**（requiresFocus == false）：孩子手动 [checkIn] → 落 **pending**
///    （待家长核销），**当期不发阳光**；家长 [verifyCheckIn] 通过后才入账，
///    [rejectCheckIn] 驳回则不入账。
///  - **按自身当日累计净额封顶**：入账时
///    `grant = max(0, min(reward, kTaskCheckinDailyCap - 当日已发打卡阳光))`
///    （[kTaskCheckinDailyCap] = 79，唯一定义在 prd_params）。
///  - ⚠️ **成长奖励不占专注额度**（玄参 2026-09-23 拍板）：核算只读
///    `refType='task_checkin'` 自己的当日净额，**不再**读当日全部 `earn` 的
///    gross/net。旧口径下专注拿满（或家长赠予）会把当日 earn 合计顶到旧的
///    「分段软顶」硬顶 79，导致孩子当天所有成长打卡奖励被挤成 0 —— 与
///    「成长奖励不算在内」正好相反（该术语已作废，此处仅用于说明历史行为）。
///  - ⚠️ 同时**取消了「分段打薄」**：专注侧改为 1 分钟 = 1 阳光 + 年段日上限硬截断
///    （见 `SunlightService`）。故本文件不再复用任何分段公式，[kTaskCheckinDailyCap]
///    就是成长奖励唯一的日上限。
///  - **pending 不占额度**：只有真正入账（verify / 自动结算）才计入当日已发合计；
///    否则家长迟迟不核销会把当日额度白占掉。
///  - **写路径串行化**：所有会写库 / 写账本的入口（[checkIn] / [settleFocusLinked] /
///    [verifyCheckIn] / [rejectCheckIn]）在本服务内经异步互斥闸门排队执行，保证彼此
///    不交错——额度差额是「读当日累计 → 算差额 → 写账本」的非原子序列，CAS 只保证
///    **同一条记录**不被重复核销，管不住**两条不同记录**互相插队绕过上限；孩子连点
///    两次打卡也会各插一行 pending。只读入口（[board] / [pendingCheckIns]）不加闸门。
///  - **完美日（徽章）**：当日存在 ≥ 一次 `actualFocusMin >= kValidFocusMinutes(15)` 的专注
///    即命中；但**不再**乘到阳光上（[kPerfectDayCoefficient] 已从奖励公式移除，见
///    [_rewardFor]），完美日只作为「今日成长项全部提交」的庆祝徽章，不影响发放数额。
///
/// 完美日（`isPerfectDay`）判定：按「当日该做的成长项**都已提交**」——联动项自动结算算已提交、
/// 非联动项打卡算已提交（**不管家长是否已核销**）。理由：完美日是即时情绪反馈，不能等家长
/// 核销才庆祝；且完美日本身不发钱（PRD 为累计制徽章）。
///
/// 完美日判定降级说明：PRD §4.4 原文要求「同日**同科**专注 + 打卡」，但 [FocusSession]
/// 无科目字段，专注会话与任务科目在本轮数据模型里无法建立同科关联；故降级为
/// 「当日存在 ≥15 分钟专注」即命中系数（仅放宽「同科」维度）。
///
/// 术语约定（M4 文案口径）：本文件类名 / 字段名 / 文件名沿用 `Task` 术语，**仅面向用户的
/// 可见文案**使用「成长」口径（成长项 / 做到）。账本标识 `refType='task_checkin'` 是
/// **数据标识（非文案）**，改动会对不上历史账本，一律不动。
library task_checkin_service;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

/// 打卡领域异常（校验不通过时抛出；消息面向孩子端可直接展示）。
class TaskCheckInException implements Exception {
  /// 面向孩子的提示文案。
  final String message;

  const TaskCheckInException(this.message);

  @override
  String toString() => message;
}

/// 今日任务板单项：任务 + 是否已提交 + 专注条件 + 是否在等家长核销。
class TaskCheckInItem {
  /// 任务模板。
  final Task task;

  /// 今日是否已提交（`verified` 或 `pending` 都算 true）。
  final bool done;

  /// 今日已提交但仍在等家长核销（即存在 `status == pending` 的打卡）。
  final bool pendingVerification;

  /// 专注条件是否满足：非联动项恒为 true；联动项要求当日存在
  /// `actualFocusMin >= task.minFocusMin` 的会话。
  final bool focusSatisfied;

  /// 未完成且被阻塞时的原因文案；无阻塞为 null。
  ///
  /// M4 起：联动项没有可点的按钮（表现层用 [Task.requiresFocus] 渲染「开始专注」），
  /// 非联动项本就不阻塞，故该字段当前恒为 null，仅保留以备将来规则扩展。
  final String? blockedReason;

  /// 是否属于「每天该做」的任务（`repeatRule == null || repeatRule == 'daily'`）。
  ///
  /// 「完美日」判定只统计这一类；`'weekly'` 任务仍列出、仍可打卡
  /// （数据模型无「星期几」信息，无法判断周任务今天该不该做）。
  final bool isDaily;

  const TaskCheckInItem({
    required this.task,
    required this.done,
    required this.pendingVerification,
    required this.focusSatisfied,
    this.blockedReason,
    required this.isDaily,
  });
}

/// 今日任务板：任务列表 + 完成度派生量。
///
/// 语义约定（务必注意）：[total] / [doneCount] / [allDone] 描述的是
/// 「**今日必做任务（每天该做，即 isDaily）的进度**」，**不是**列表可见行数。
/// `'weekly'` 行仍会出现在 [items] 中（供孩子打卡），但**不计入**上述派生量，
/// 以免一个无法判断该哪天做的周任务把「完美日」永远卡死。
class TodayTaskBoard {
  /// 今日任务项（含已完成与未完成；**含** weekly 行）。
  final List<TaskCheckInItem> items;

  const TodayTaskBoard({required this.items});

  /// 今日必做（每天该做）任务总数（不含 weekly）。
  int get total => items.where((i) => i.isDaily).length;

  /// 今日必做任务中已完成的数量（不含 weekly）。
  int get doneCount => items.where((i) => i.isDaily && i.done).length;

  /// 每周任务数量（供表现层分区展示；不计入完成度）。
  int get weeklyCount => items.where((i) => !i.isDaily).length;

  /// 今日必做任务是否全部完成（必做数为 0 时视为未完成，避免空板误判为「全完成」）。
  bool get allDone => total > 0 && doneCount == total;
}

/// 一次打卡 / 结算的结果。
class TaskCheckInOutcome {
  /// 生成的打卡记录 id（未达标的联动结算为空串，见 [settleFocusLinked]）。
  final String checkInId;

  /// 本次任务应发阳光（基础奖励，未过上限；完美日系数已不再叠加）。
  final double reward;

  /// 本次实际入账阳光；**pending 时为 0**。
  final double granted;

  /// 是否被上限削减（实际到手 < 应得奖励）。
  final bool cappedByDailyCap;

  /// 本次是否命中完美日（仅徽章含义，不影响阳光数额）。
  final bool perfectDayBonus;

  /// 打卡后「今日必做（每天该做）任务」是否全部提交（用于 CheckIn.isPerfectDay）。
  /// 只统计 daily 任务；weekly 任务不计入（见 TodayTaskBoard 注释）。
  final bool allTasksDone;

  /// 核销状态：联动项自动结算 / 家长核销 → verified；非联动项手动打卡 → pending。
  final CheckInStatus status;

  const TaskCheckInOutcome({
    required this.checkInId,
    required this.reward,
    required this.granted,
    required this.cappedByDailyCap,
    required this.perfectDayBonus,
    required this.allTasksDone,
    required this.status,
  });
}

/// 家长端待核销条目（附带 task 以便展示名称；任务可能已被删除 → `task == null`）。
class PendingCheckIn {
  /// 待核销的打卡记录。
  final CheckIn checkIn;

  /// 关联的成长项；任务已删除时为 null。
  final Task? task;

  const PendingCheckIn({required this.checkIn, this.task});
}

/// 成长项打卡领域服务（见文件头口径说明）。
class TaskCheckInService {
  TaskCheckInService({
    required TaskRepository tasks,
    required SunlightRepository ledger,
    required FocusRepository focus,
    required SettingsRepository settings,
    Uuid? idGenerator,
  })  : _tasks = tasks,
        _ledger = ledger,
        _focus = focus,
        _settings = settings,
        _uuid = idGenerator ?? const Uuid();

  final TaskRepository _tasks;
  final SunlightRepository _ledger;
  final FocusRepository _focus;
  final SettingsRepository _settings;
  final Uuid _uuid;

  /// 成长项打卡的账本标识（**数据标识**，非文案：改动会对不上历史账本，一律不动）。
  ///
  /// 单点收口：涨额核算、记账、防重校验都引用本常量，避免三处各写一份字面量。
  static const String checkInRefType = 'task_checkin';

  /// 串行化闸门：所有写路径（打卡 / 专注结算 / 核销 / 驳回）在此排队执行。
  ///
  /// 必要性：上限差额是「读当日累计 → 算差额 → 写账本」的非原子序列；CAS 只保证
  /// **同一条记录**不被重复核销，管不住**两条不同记录**互相插队把上限绕过
  /// （两个打卡并发核销，各自都读到同一份 grantedSoFar，各自补满差额）。
  /// 同理，孩子连点两次「我做到了」会各插一行 pending，导致家长看到两条同名待确认、
  /// 核销出双份阳光。单设备单 isolate，进程内排队即可根治。
  Future<void> _gate = Future<void>.value();

  /// 排队执行 [action]，保证写路径互不交错；无论成功失败，闸门都会放行后续调用。
  Future<T> _serialized<T>(Future<T> Function() action) {
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _gate;
    _gate = done.future;
    return previous.then<T>((_) => action()).whenComplete(done.complete);
  }

  /// 注入的设置仓储（冻结契约保留；供后续按设置驱动打卡规则扩展，如
  /// `AppSettings.taskSunlight` 作为任务默认奖励的兜底）。
  SettingsRepository get settings => _settings;

  /// 家长核销能力（真实实现 [TaskLocalRepository] 同时实现该接口）。
  ///
  /// 刻意用能力探测而非把方法直接挂到 [TaskRepository]：避免牵动所有既有实现
  /// （含测试里的轻量 Fake）。仅家长端核销路径（[pendingCheckIns] / [verifyCheckIn] /
  /// [rejectCheckIn]）需要本能力。
  CheckInAdminRepository get _admin {
    if (_tasks is! CheckInAdminRepository) {
      throw StateError(
        '任务仓储未实现 CheckInAdminRepository，无法进行家长端核销',
      );
    }
    return _tasks as CheckInAdminRepository;
  }

  /// 今日任务板：列出全部任务并标注提交 / 待核销 / 专注条件（§4.4）。
  ///
  /// 只读入口，**不加**串行化闸门（避免把读也串起来拖慢界面）。
  Future<TodayTaskBoard> board(DateTime now) async {
    final String day = dayKey(now);
    final List<Task> allTasks = await _tasks.tasks();
    final List<CheckIn> checkIns = await _tasks.checkInsOfDay(day);
    final List<FocusSession> sessions = await _focus.sessionsOfDay(day);

    final Map<String, List<CheckIn>> byTask = <String, List<CheckIn>>{};
    for (final CheckIn c in checkIns) {
      (byTask[c.taskId] ??= <CheckIn>[]).add(c);
    }

    final List<TaskCheckInItem> items = allTasks.map((Task t) {
      final CheckIn? c = _activeCheckIn(byTask[t.id] ?? const <CheckIn>[]);
      // rejected 不算「做到」：被驳回的项不应计入完成度（修复 5）。
      final bool done = c != null && c.status != CheckInStatus.rejected;
      final bool pendingVerification =
          c != null && c.status == CheckInStatus.pending;
      final bool focusSatisfied = !t.requiresFocus ||
          _bestQualifyingSession(sessions, t.minFocusMin) != null;
      return TaskCheckInItem(
        task: t,
        done: done,
        pendingVerification: pendingVerification,
        focusSatisfied: focusSatisfied,
        blockedReason: null, // 见 TaskCheckInItem.blockedReason 注释
        isDaily: _isDailyTask(t),
      );
    }).toList();

    return TodayTaskBoard(items: items);
  }

  /// 非联动项：孩子手动打卡（冻结契约）。
  ///
  /// - `task.requiresFocus == true` → 抛 [TaskCheckInException]（联动项不能手动点）；
  /// - 今日重复 → 抛 [TaskCheckInException]；
  /// - 通过 → 落 **pending** 打卡记录（`sunlightGross = reward`、`sunlightGranted = 0`），
  ///   **当期不发阳光、不写账本**；家长 [verifyCheckIn] 通过后才入账。
  ///
  /// 经串行化闸门执行：连点两次只会成功一次（第二次读到已落库的 pending 行 → 抛异常）。
  Future<TaskCheckInOutcome> checkIn({
    required Task task,
    required DateTime now,
  }) =>
      _serialized(() => _checkIn(task: task, now: now));

  /// [checkIn] 的实现体（由闸门串行调用）。
  Future<TaskCheckInOutcome> _checkIn({
    required Task task,
    required DateTime now,
  }) async {
    // 联动项必须走专注自动结算，不允许手动点。
    if (task.requiresFocus) {
      throw const TaskCheckInException('这个成长项要在专注里自动完成哦');
    }

    final String day = dayKey(now);

    // 同一成长项同日不可重复打卡；但**被驳回**后允许重做（修复 6：
    // 只有 pending / verified 才算「已提交」，rejected 放行新增一行）。
    final List<CheckIn> todayCheckIns = await _tasks.checkInsOfDay(day);
    final CheckIn? active = _activeCheckIn(_forTask(todayCheckIns, task.id));
    if (active != null && active.status != CheckInStatus.rejected) {
      throw const TaskCheckInException('这个成长项今天已经做到啦');
    }

    final List<FocusSession> todaySessions = await _focus.sessionsOfDay(day);
    final double reward = _rewardFor(task, todaySessions);
    final bool perfectDayBonus = _isPerfectDayToday(todaySessions);
    final bool allTasksDone = await _allDailySubmitted(todayCheckIns, task.id);

    final String checkInId = _uuid.v4();

    // 落 pending：当期不发阳光（sunlightGranted = 0），只记应发 [sunlightGross]。
    await _tasks.checkIn(CheckIn(
      id: checkInId,
      taskId: task.id,
      date: now,
      completedAt: now,
      sessionId: null,
      isPerfectDay: allTasksDone,
      status: CheckInStatus.pending,
      sunlightGross: reward,
      sunlightGranted: 0.0,
    ));

    return TaskCheckInOutcome(
      checkInId: checkInId,
      reward: reward,
      granted: 0.0,
      cappedByDailyCap: false, // pending 阶段尚未核销，未计算上限
      perfectDayBonus: perfectDayBonus,
      allTasksDone: allTasksDone,
      status: CheckInStatus.pending,
    );
  }

  /// 联动项：专注结束后自动结算（冻结契约）。
  ///
  /// - `task.requiresFocus != true` → 抛 [TaskCheckInException]（内部调用，正常不触发）；
  /// - 今日该成长项已有打卡 → **幂等**：直接返回既有结果，不重复计账；
  /// - `session.actualFocusMin < task.minFocusMin` → **不达标**：不写任何记录，
  ///   返回 `status == rejected` 的结果（让表现层区分「没达标（正常）」与「真出错（抛异常）」）；
  /// - 达标 → 写 `verified` 打卡（`sessionId = session.id`）并按当日上限差额入账。
  ///
  /// 经串行化闸门执行，与核销路径互不交错。
  Future<TaskCheckInOutcome> settleFocusLinked({
    required Task task,
    required FocusSession session,
    required DateTime now,
  }) =>
      _serialized(
        () => _settleFocusLinked(task: task, session: session, now: now),
      );

  /// [settleFocusLinked] 的实现体（由闸门串行调用）。
  Future<TaskCheckInOutcome> _settleFocusLinked({
    required Task task,
    required FocusSession session,
    required DateTime now,
  }) async {
    if (!task.requiresFocus) {
      throw const TaskCheckInException('非联动成长项不能走专注结算');
    }

    final String day = dayKey(now);

    // 跨天守卫（修复 4）：会话不在今天 → 拒绝结算今天的成长项，不写任何记录。
    if (dayKey(session.start) != day) {
      throw const TaskCheckInException('这次专注不在今天，不能结算今天的成长项');
    }

    final List<CheckIn> todayCheckIns = await _tasks.checkInsOfDay(day);

    // 幂等：今日已有该成长项**有效**打卡（非 rejected）→ 返回既有结果，不重复结算。
    // existing 若为 rejected 则视为「无有效记录」，继续往下走结算（与修复 6 的重做规则一致）。
    final CheckIn? existing = _activeCheckIn(_forTask(todayCheckIns, task.id));
    if (existing != null && existing.status != CheckInStatus.rejected) {
      final List<FocusSession> sessions = await _focus.sessionsOfDay(day);
      return TaskCheckInOutcome(
        checkInId: existing.id,
        reward: existing.sunlightGross,
        granted: existing.sunlightGranted,
        cappedByDailyCap: existing.status == CheckInStatus.verified &&
            existing.sunlightGranted + 1e-9 < existing.sunlightGross,
        perfectDayBonus: _isPerfectDayToday(sessions),
        allTasksDone: existing.isPerfectDay,
        status: existing.status,
      );
    }

    // 不达标：不结算，返回 rejected（表现层据此提示「再专注一会儿」，非错误）。
    if (session.actualFocusMin < task.minFocusMin) {
      return const TaskCheckInOutcome(
        checkInId: '',
        reward: 0,
        granted: 0,
        cappedByDailyCap: false,
        perfectDayBonus: false,
        allTasksDone: false,
        status: CheckInStatus.rejected,
      );
    }

    // 会话复用守卫（修复 3）：当日已存在同一 sessionId 的 verified 打卡 →
    // 说明这次专注已解锁过别的成长项，禁止「一次专注换多份奖励」，不写任何记录。
    final bool sessionAlreadyUsed = todayCheckIns.any((CheckIn c) =>
        c.sessionId == session.id && c.status == CheckInStatus.verified);
    if (sessionAlreadyUsed) {
      throw const TaskCheckInException('这次专注已经结算过成长项啦');
    }

    final List<FocusSession> sessions = await _focus.sessionsOfDay(day);
    final double reward = _rewardFor(task, sessions);
    final bool perfectDayBonus = _isPerfectDayToday(sessions);
    final bool allTasksDone = await _allDailySubmitted(todayCheckIns, task.id);
    final String checkInId = _uuid.v4();
    final ({double grant, bool capped}) rewardCap =
        await _dailyRewardGrant(day, reward);

    // 先落打卡记录（重复口径的事实源），再落账本。
    await _tasks.checkIn(CheckIn(
      id: checkInId,
      taskId: task.id,
      date: now,
      completedAt: now,
      sessionId: session.id,
      isPerfectDay: allTasksDone,
      status: CheckInStatus.verified,
      sunlightGross: reward,
      sunlightGranted: rewardCap.grant,
    ));
    await _appendLedger(checkInId, day, now, reward, rewardCap.grant);

    return TaskCheckInOutcome(
      checkInId: checkInId,
      reward: reward,
      granted: rewardCap.grant,
      cappedByDailyCap: rewardCap.capped,
      perfectDayBonus: perfectDayBonus,
      allTasksDone: allTasksDone,
      status: CheckInStatus.verified,
    );
  }

  /// 家长端：全部待核销（**不限今日**，避免积压几天就看不到），按 completedAt 升序。
  ///
  /// 只读入口，**不加**串行化闸门。
  Future<List<PendingCheckIn>> pendingCheckIns() async {
    final List<CheckIn> rows =
        await _admin.checkInsByStatus(CheckInStatus.pending);
    final List<Task> allTasks = await _tasks.tasks();
    final Map<String, Task> byId = <String, Task>{
      for (final Task t in allTasks) t.id: t,
    };
    return rows
        .map((CheckIn c) => PendingCheckIn(checkIn: c, task: byId[c.taskId]))
        .toList();
  }

  /// 家长端：核销通过（冻结契约）。
  ///
  /// **只对 `pending` 生效**（对 verified / rejected 抛错，防止重复入账——这是钱）。
  /// 通过后：按**打卡原始日**的上限差额入账、填 `sunlightGranted`、status 置 verified。
  ///
  /// 经串行化闸门执行：两条不同记录并发核销时，第二次会读到第一次已入账后的当日累计，
  /// 从而只补真实差额，不会各自补满把上限顶穿。
  Future<TaskCheckInOutcome> verifyCheckIn(String checkInId, DateTime now) =>
      _serialized(() => _verifyCheckIn(checkInId, now));

  /// [verifyCheckIn] 的实现体（由闸门串行调用）。
  Future<TaskCheckInOutcome> _verifyCheckIn(String checkInId, DateTime now) async {
    final CheckIn? c = await _admin.checkInById(checkInId);
    if (c == null) {
      throw const TaskCheckInException('找不到这条记录，可能已被删除');
    }
    if (c.status != CheckInStatus.pending) {
      throw const TaskCheckInException('这条记录已经处理过啦，不能重复核销');
    }

    // 上限按「打卡原始日」核算：pending 期间未入账，故不被当日 earn 合计占用。
    final String day = dayKey(c.date);
    final double reward = c.sunlightGross;
    final ({double grant, bool capped}) rewardCap =
        await _dailyRewardGrant(day, reward);

    // CAS 抢状态（修复 2，P0）：仅当记录仍是 pending 时写回；抢占成功才可入账。
    // 抢占失败 = 已被并发处理（家长连点两次），必须放弃入账，否则余额翻倍。
    final bool won = await _admin.resolveCheckInIfStatus(
      id: checkInId,
      from: CheckInStatus.pending,
      to: CheckInStatus.verified,
      sunlightGranted: rewardCap.grant,
      resolvedAt: now,
    );
    if (!won) {
      throw const TaskCheckInException('这条记录刚刚已经被处理过了');
    }
    await _appendLedger(checkInId, day, now, reward, rewardCap.grant);

    return TaskCheckInOutcome(
      checkInId: checkInId,
      reward: reward,
      granted: rewardCap.grant,
      cappedByDailyCap: rewardCap.capped,
      perfectDayBonus: _isPerfectDayToday(await _focus.sessionsOfDay(day)),
      allTasksDone: c.isPerfectDay,
      status: CheckInStatus.verified,
    );
  }

  /// 家长端：驳回（冻结契约）。
  ///
  /// **只对 `pending` 生效**；驳回后 status 置 rejected、记录 [note]，不入账。
  ///
  /// 经串行化闸门执行。
  Future<void> rejectCheckIn(
    String checkInId, {
    String? note,
    required DateTime now,
  }) =>
      _serialized(() => _rejectCheckIn(checkInId, note: note, now: now));

  /// [rejectCheckIn] 的实现体（由闸门串行调用）。
  Future<void> _rejectCheckIn(
    String checkInId, {
    String? note,
    required DateTime now,
  }) async {
    final CheckIn? c = await _admin.checkInById(checkInId);
    if (c == null) {
      throw const TaskCheckInException('找不到这条记录，可能已被删除');
    }
    if (c.status != CheckInStatus.pending) {
      throw const TaskCheckInException('这条记录已经处理过啦，不能重复处理');
    }
    // CAS 抢状态（修复 2，P0）：与 verifyCheckIn 同一口径；抢占失败即放弃入账。
    final bool won = await _admin.resolveCheckInIfStatus(
      id: checkInId,
      from: CheckInStatus.pending,
      to: CheckInStatus.rejected,
      sunlightGranted: 0.0,
      resolvedAt: now,
      parentNote: note,
    );
    if (!won) {
      throw const TaskCheckInException('这条记录刚刚已经被处理过了');
    }
  }

  // ── 内部工具 ────────────────────────────────────────────────────────────

  /// 是否为「每天该做」的任务：`repeatRule == null` 或 `'daily'`。
  ///
  /// `'weekly'`（及未知值）视为非每日；单点收口，避免字面量孪生。
  bool _isDailyTask(Task t) => t.repeatRule == null || t.repeatRule == 'daily';

  /// 同一成长项当日可能有多行（被驳回后可再次提交）→ 取「最新一条非 rejected」；
  /// 若全是 rejected，返回最新一条（供表现层显示「已驳回」，但**不计入**完成）。
  CheckIn? _activeCheckIn(List<CheckIn> rows) {
    if (rows.isEmpty) return null;
    final List<CheckIn> sorted = List<CheckIn>.of(rows)
      ..sort((CheckIn a, CheckIn b) => a.completedAt.compareTo(b.completedAt));
    CheckIn? newestNonRejected;
    for (final CheckIn c in sorted) {
      if (c.status != CheckInStatus.rejected) newestNonRejected = c;
    }
    return newestNonRejected ?? sorted.last;
  }

  /// 某个成长项当日的全部打卡行。
  List<CheckIn> _forTask(List<CheckIn> all, String taskId) =>
      all.where((CheckIn c) => c.taskId == taskId).toList();

  /// 本次应发阳光 = 基础奖励（[Task.effectiveSunlightReward]）。
  ///
  /// 口径（用户 2026-09-21 拍板）：**不再叠加完美日系数**。原先 `×1.5` 乘到钱上，
  /// 导致「孩子端任务卡预览 / 结算页 / 家长端待确认卡」三处数值对不上（见 ②/④ 反馈）。
  /// 完美日仅作为「今日成长项全部提交」徽章庆祝（见 [TaskCheckInOutcome.allTasksDone]），
  /// 不影响阳光数额。
  double _rewardFor(Task task, List<FocusSession> sessions) {
    return task.effectiveSunlightReward.toDouble();
  }

  /// 当日是否命中完美日系数：存在 ≥ 一次 `actualFocusMin >= kValidFocusMinutes` 的专注。
  bool _isPerfectDayToday(List<FocusSession> sessions) =>
      sessions.any((FocusSession s) => s.actualFocusMin >= kValidFocusMinutes);

  /// 当日「该做的成长项」（daily）是否都已提交（含 [extraTaskId] 预演）。
  Future<bool> _allDailySubmitted(
    List<CheckIn> todayCheckIns,
    String extraTaskId,
  ) async {
    final List<Task> allTasks = await _tasks.tasks();
    // 被驳回的打卡不顶替「已提交」：先剔除 rejected，再取 taskId 集合（修复 5）。
    final Set<String> submitted = todayCheckIns
        .where((CheckIn c) => c.status != CheckInStatus.rejected)
        .map((CheckIn c) => c.taskId)
        .toSet()
      ..add(extraTaskId);
    final List<Task> daily = allTasks.where(_isDailyTask).toList();
    return daily.isNotEmpty && daily.every((Task t) => submitted.contains(t.id));
  }

  /// 当日满足「实际专注 ≥ [thresholdMin]」的最佳（时长最长）会话；无则 null。
  FocusSession? _bestQualifyingSession(
    List<FocusSession> sessions,
    int thresholdMin,
  ) {
    FocusSession? best;
    for (final FocusSession s in sessions) {
      if (s.actualFocusMin >= thresholdMin) {
        if (best == null || s.actualFocusMin > best.actualFocusMin) {
          best = s;
        }
      }
    }
    return best;
  }

  /// 当日成长奖励额度差额（2026-09-23 口径）：
  /// `grant = max(0, min(reward, kTaskCheckinDailyCap - 当日已发打卡阳光))`。
  ///
  /// **只看打卡自己的账目**（[checkInRefType]）。此前读的是当日**全部 earn** 的
  /// gross/net，导致专注拿满当天（或家长赠予当天）孩子所有成长打卡奖励被挤成 0 ——
  /// 与「成长奖励不占专注额度」正好相反（玄参 2026-09-23 拍板解耦）。
  Future<({double grant, bool capped})> _dailyRewardGrant(
    String day,
    double reward,
  ) async {
    if (reward <= 0) return (grant: 0.0, capped: false);
    final double grantedSoFar =
        await _ledger.netByRefTypeOnDay(checkInRefType, day);
    final double remaining = kTaskCheckinDailyCap - grantedSoFar;
    final double grant =
        remaining <= 0 ? 0.0 : (reward < remaining ? reward : remaining);
    return (grant: grant, capped: grant < reward - 1e-9);
  }

  /// 写一条阳光账本（`refType = [checkInRefType]`，`refId=checkInId`）。
  Future<void> _appendLedger(
    String refId,
    String day,
    DateTime ts,
    double gross,
    double net,
  ) async {
    // 二次防重入账：同一 checkInId 当日已记账 → 直接跳过（CAS 已拦一层，此处兜底）。
    if (await _ledger
            .countByRefTypeAndRefIdOnDay(checkInRefType, refId, day) >
        0) {
      return;
    }
    final double balanceBefore = await _ledger.balance();
    await _ledger.append(SunlightEntry(
      id: _uuid.v4(),
      ts: ts,
      type: SunlightType.earn,
      gross: gross,
      net: net,
      balanceAfter: balanceBefore + net,
      refType: checkInRefType,
      refId: refId,
      dayKey: day,
    ));
  }
}
