/// 「记录」页 · 独立 widget 验证（C54 建页 / C55 加「按天 / 按周 / 按月」统计）。
///
/// 验收点：
///  · **按天 / 按周 / 按月**切换：同一份已核销数据在不同粒度下重新聚合；
///  · 期间导航：`◀` 可回看历史期间，`▶` 不可翻到未来；
///  · **相同内容统计次数**：同一成长项 / 同一奖励聚合为一行计数；
///  · 汇总卡按「本期」口径（完成 / 兑换 / 消耗阳光）；
///  · 已核销打卡（verified）与已核销兑换（verified）为唯一数据源；
///  · 空态文案正确。
///
/// 说明：为了确定性，页面注入 `now = 2026-10-10 20:00`（周六，本周为 10-05 ~ 10-11）。
/// 只覆盖历史页本身所需的 Provider，其余本页不读，故不注入。
library parent_history_page_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_history_page.dart';

/// 固定「现在」：2026-10-10（周六）20:00。
final DateTime _now = DateTime(2026, 10, 10, 20);

// ───────────────────────────────────────────────────────────────────────────
// 假仓储
// ───────────────────────────────────────────────────────────────────────────

const AppSettings _lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _lowSettings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 0;
  @override
  Future<double> balance() async => 0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
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
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

/// 假任务仓储：实现两接口，按 status 过滤返回打卡（模拟真实 `checkInsByStatus`）。
class _FakeTaskRepository implements TaskRepository, CheckInAdminRepository {
  _FakeTaskRepository({this.tasks_ = const <Task>[], this.checkIns = const <CheckIn>[]});

  final List<Task> tasks_;
  final List<CheckIn> checkIns;

  @override
  Future<List<Task>> tasks() async => tasks_;
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];
  @override
  Future<int> totalCheckInCount() async => 0;

  @override
  Future<CheckIn?> checkInById(String id) async => null;
  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async =>
      checkIns.where((CheckIn c) => c.status == status).toList();
  @override
  Future<void> updateCheckIn(CheckIn checkIn) async {}
  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async =>
      false;
}

class _FakeRewardRepository implements RewardRepository {
  _FakeRewardRepository({
    this.verified = const <RedemptionRequest>[],
    this.templates_ = const <RewardTemplate>[],
  });

  final List<RedemptionRequest> verified;
  final List<RewardTemplate> templates_;

  @override
  Future<List<RewardTemplate>> templates() async => templates_;
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async => verified;
  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];
  @override
  Future<void> updateRequest(RedemptionRequest r) async {}
  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;
  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

// ───────────────────────────────────────────────────────────────────────────
// 数据构造
// ───────────────────────────────────────────────────────────────────────────

const Task _taskRead = Task(
  id: 't_read',
  name: '阅读20分钟',
  subject: TaskSubject.chinese,
  category: TaskCategory.learning,
  requiresFocus: false,
  minFocusMin: 15,
  sunlightReward: 12,
  isCustom: false,
);

const Task _taskMath = Task(
  id: 't_math',
  name: '练习数学口算',
  subject: TaskSubject.math,
  category: TaskCategory.learning,
  requiresFocus: false,
  minFocusMin: 15,
  sunlightReward: 10,
  isCustom: false,
);

CheckIn _verified(String id, String taskId, DateTime at) => CheckIn(
      id: id,
      taskId: taskId,
      date: at,
      completedAt: at,
      isPerfectDay: false,
      status: CheckInStatus.verified,
      sunlightGross: 12,
      sunlightGranted: 12,
    );

const RewardTemplate _tplSnack = RewardTemplate(
  id: 'r_snack',
  name: '小零食',
  category: RewardCategory.parentHandled,
  contentCategory: RewardContentCategory.snacks,
  baseCost: 20,
  frequencyLimitPerWeek: 1,
);

const RewardTemplate _tplCartoon = RewardTemplate(
  id: 'r_cartoon',
  name: '看一集动画片',
  category: RewardCategory.selfService,
  contentCategory: RewardContentCategory.entertainment,
  baseCost: 30,
  frequencyLimitPerWeek: 1,
);

RedemptionRequest _redeemed(String id, String tplId, int cost, DateTime at) =>
    RedemptionRequest(
      id: id,
      childId: 'single-child',
      templateId: tplId,
      requestedAt: at,
      cost: cost,
      status: RequestStatus.verified,
      verifiedAt: at,
    );

List<Override> _overrides({
  required TaskRepository taskRepo,
  required RewardRepository rewardRepo,
}) =>
    <Override>[
      taskRepositoryProvider.overrideWithValue(taskRepo),
      rewardRepositoryProvider.overrideWithValue(rewardRepo),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
    ];

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides, {
  DateTime? now,
}) async {
  // 加高画布：记录页列表较长（粒度条 + 期间导航 + 汇总 + 两块历史），
  // 默认 800×600 会让下半天花板外的行不构建、find.text 找不到。
  await tester.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: ParentHistoryPage(now: now ?? _now)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('按天 / 按周 / 按月切换：同一数据在不同粒度重新聚合，期间标题正确',
      (WidgetTester tester) async {
    final _FakeTaskRepository taskRepo = _FakeTaskRepository(
      tasks_: const <Task>[_taskRead, _taskMath],
      checkIns: <CheckIn>[
        // 今天（10-10，周六）
        _verified('c1', 't_read', DateTime(2026, 10, 10, 9)),
        _verified('c2', 't_read', DateTime(2026, 10, 10, 15)),
        _verified('c3', 't_math', DateTime(2026, 10, 10, 10)),
        // 本周内（非今天）
        _verified('c4', 't_read', DateTime(2026, 10, 6, 9)),
        // 本月内（上周）
        _verified('c5', 't_read', DateTime(2026, 10, 2, 9)),
        // 上月 → 任何粒度都不计入（除非继续往前翻）
        _verified('c6', 't_read', DateTime(2026, 9, 20, 9)),
      ],
    );
    final _FakeRewardRepository rewardRepo = _FakeRewardRepository(
      templates_: const <RewardTemplate>[_tplSnack, _tplCartoon],
      verified: <RedemptionRequest>[
        _redeemed('r1', 'r_snack', 20, DateTime(2026, 10, 10, 18)),
        _redeemed('r2', 'r_snack', 20, DateTime(2026, 10, 6, 18)),
        _redeemed('r3', 'r_cartoon', 30, DateTime(2026, 10, 8, 18)),
        _redeemed('r4', 'r_snack', 20, DateTime(2026, 10, 3, 18)),
        _redeemed('r5', 'r_snack', 20, DateTime(2026, 9, 15, 18)),
      ],
    );

    await _pump(
      tester,
      _overrides(taskRepo: taskRepo, rewardRepo: rewardRepo),
    );

    // ── 默认「日」：只统计今天 ──────────────────────────────
    expect(find.text('今天 · 10月10日'), findsOneWidget);
    expect(find.text('本期完成成长项'), findsOneWidget);
    expect(find.text('完成 2 次'), findsOneWidget); // 阅读
    expect(find.text('完成 1 次'), findsOneWidget); // 口算
    expect(find.text('共 3 次'), findsOneWidget);
    expect(find.text('兑换 1 次'), findsOneWidget); // 小零食
    expect(find.text('共 1 次 · 消耗 20 阳光'), findsOneWidget);

    // ── 切「周」：10-05 ~ 10-11 ─────────────────────────────
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月5日 ～ 10月11日'), findsOneWidget);
    expect(find.text('完成 3 次'), findsOneWidget); // 阅读 3
    expect(find.text('完成 1 次'), findsOneWidget); // 口算 1
    expect(find.text('共 4 次'), findsOneWidget);
    expect(find.text('兑换 2 次'), findsOneWidget); // 小零食 2
    expect(find.text('兑换 1 次'), findsOneWidget); // 动画片 1
    expect(find.text('共 3 次 · 消耗 70 阳光'), findsOneWidget);

    // ── 切「月」：整月 ──────────────────────────────────────
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(find.text('2026 年 10 月'), findsOneWidget);
    expect(find.text('完成 4 次'), findsOneWidget); // 阅读 4
    expect(find.text('完成 1 次'), findsOneWidget); // 口算 1
    expect(find.text('共 5 次'), findsOneWidget);
    expect(find.text('兑换 3 次'), findsOneWidget); // 小零食 3
    expect(find.text('兑换 1 次'), findsOneWidget); // 动画片 1
    expect(find.text('共 4 次 · 消耗 90 阳光'), findsOneWidget);
  });

  testWidgets('期间导航：◀ 回看昨天；▶ 未来不可翻（今天时禁用）',
      (WidgetTester tester) async {
    final _FakeTaskRepository taskRepo = _FakeTaskRepository(
      tasks_: const <Task>[_taskRead],
      checkIns: <CheckIn>[
        _verified('c1', 't_read', DateTime(2026, 10, 10, 9)),
        _verified('c2', 't_read', DateTime(2026, 10, 9, 9)), // 昨天
      ],
    );

    await _pump(
      tester,
      _overrides(taskRepo: taskRepo, rewardRepo: _FakeRewardRepository()),
    );

    // 今天：1 次。
    expect(find.text('今天 · 10月10日'), findsOneWidget);
    expect(find.text('完成 1 次'), findsOneWidget);

    // ▶ 禁用（不能翻到未来）→ 点不动，仍是今天。
    await tester.tap(find.byTooltip('下一期间'));
    await tester.pumpAndSettle();
    expect(find.text('今天 · 10月10日'), findsOneWidget);

    // ◀ 回看昨天：命中 1 次。
    await tester.tap(find.byTooltip('上一期间'));
    await tester.pumpAndSettle();
    expect(find.text('昨天 · 10月9日'), findsOneWidget);
    expect(find.text('完成 1 次'), findsOneWidget);

    // ◀ 再回看（10-08）：无记录 → 空态。
    await tester.tap(find.byTooltip('上一期间'));
    await tester.pumpAndSettle();
    expect(find.text('本期间还没有成长项完成记录'), findsOneWidget);
    expect(find.text('本期间还没有奖励兑换记录'), findsOneWidget);
    expect(find.text('共 0 次'), findsOneWidget);
    expect(find.text('共 0 次 · 消耗 0 阳光'), findsOneWidget);
  });

  testWidgets('空态：无任何记录时两块历史各自给出提示，汇总全为 0',
      (WidgetTester tester) async {
    await _pump(
      tester,
      _overrides(
        taskRepo: _FakeTaskRepository(),
        rewardRepo: _FakeRewardRepository(),
      ),
    );

    expect(find.text('本期间还没有成长项完成记录'), findsOneWidget);
    expect(find.text('本期间还没有奖励兑换记录'), findsOneWidget);
    expect(find.text('共 0 次'), findsOneWidget);
    expect(find.text('共 0 次 · 消耗 0 阳光'), findsOneWidget);
    expect(find.text('本期完成成长项'), findsOneWidget);
    expect(find.text('本期兑换奖励'), findsOneWidget);
    expect(find.text('本期消耗阳光'), findsOneWidget);
  });

  testWidgets('只统计已核销：待核销 / 已驳回的打卡不计入历史',
      (WidgetTester tester) async {
    final _FakeTaskRepository taskRepo = _FakeTaskRepository(
      tasks_: const <Task>[_taskRead],
      checkIns: <CheckIn>[
        _verified('c1', 't_read', DateTime(2026, 10, 10, 9)),
        // pending（待家长确认）不应计入。
        CheckIn(
          id: 'c2',
          taskId: 't_read',
          date: DateTime(2026, 10, 10, 10),
          completedAt: DateTime(2026, 10, 10, 10),
          isPerfectDay: false,
          status: CheckInStatus.pending,
          sunlightGross: 12,
        ),
        // rejected（已驳回）不应计入。
        CheckIn(
          id: 'c3',
          taskId: 't_read',
          date: DateTime(2026, 10, 10, 11),
          completedAt: DateTime(2026, 10, 10, 11),
          isPerfectDay: false,
          status: CheckInStatus.rejected,
          sunlightGross: 12,
        ),
      ],
    );

    await _pump(
      tester,
      _overrides(
        taskRepo: taskRepo,
        rewardRepo: _FakeRewardRepository(),
      ),
    );

    // 3 条打卡里只有 1 条 verified → 只计 1 次。
    expect(find.text('完成 1 次'), findsOneWidget);
    expect(find.text('完成 3 次'), findsNothing);
    expect(find.text('共 1 次'), findsOneWidget);
  });
}
