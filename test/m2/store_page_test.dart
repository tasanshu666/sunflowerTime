/// 商店页 widget 测试（§2.6 / §4.1，项目首个 widget 测试，补 M1 空白）。
///
/// 用 `ProviderScope` overrides 注入假实现，使 `StorePage` 无需真实 DB 即可渲染：
///  · `redemptionOrchestrationServiceProvider` → 假实现，`submit()` 返回固定
///    `SubmitResult(outcome: verified, requestId:'x', cost:20, autoApproved:true)`；
///  · `rewardRepositoryProvider` → 假实现，`templates()` 返回 2 条中文种子（含 name、
///    baseCost、category）；
///  · `settingsRepositoryProvider` → 假实现，`getSettings()` 返回低年段默认设置；
///  · `sunlightRepositoryProvider` → 假实现，`balance()` 返回 999.0。
///
/// 沙箱 `flutter test` 被阻断、且需真实 Flutter 环境；此处仅保证 `flutter analyze`
/// 通过并由用户机验收。
library store_page_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';

/// 低年段默认设置（AppSettings 部分字段为 required，集中提供）。
const _lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

class _FakeRewardRepository implements RewardRepository {
  static const List<RewardTemplate> _seeds = <RewardTemplate>[
    RewardTemplate(
      id: 'tpl_snack',
      name: '小零食',
      category: RewardCategory.parentHandled,
      baseCost: 20,
      frequencyLimitPerWeek: 1,
    ),
    RewardTemplate(
      id: 'tpl_extra_episode',
      name: '多看一集动画片',
      category: RewardCategory.selfService,
      baseCost: 50,
      frequencyLimitPerWeek: 1,
    ),
  ];

  @override
  Future<List<RewardTemplate>> templates() async => _seeds;
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async => <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];
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

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _lowSettings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({this.balanceValue = 999.0});

  /// 账本余额（C62 卡片置灰用例用；默认 999 与既有断言一致）。
  final double balanceValue;

  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => balanceValue;
  @override
  Future<double> dayNet(String dayKey) async => 0;
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

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  _FakeWeeklyPoolRepository({this.pool});

  /// 当周池（null = 无行 → `pool()` 返回默认预算占位池，room = poolBudget）。
  final WeeklyPool? pool;

  @override
  Future<WeeklyPool?> get(String weekKey) async => pool;
  @override
  Future<void> upsert(WeeklyPool value) async {}
  @override
  List<String> weeksBetween(String fromKey, String toKey) => <String>[
    fromKey,
    toKey,
  ];
}

/// 假编排服务：仅覆写 submit，返回固定 verified 结果（页面渲染不依赖真实落库）。
class _FakeRedemptionOrchestrationService
    extends RedemptionOrchestrationService {
  _FakeRedemptionOrchestrationService()
      : super(
          reward: _FakeRewardRepository(),
          pools: WeeklyPoolService(
            _FakeWeeklyPoolRepository(),
            _FakeSettingsRepository(),
            _FakeTrackingRepository(),
          ),
          ledger: _FakeSunlightRepository(),
          tracking: _FakeTrackingRepository(),
          account: AccountService(),
          settings: _FakeSettingsRepository(),
        );

  @override
  Future<SubmitResult> submit(
    String templateId,
    AgeTier ageTier,
    DateTime now, {
    bool forcePending = false,
  }) async =>
      const SubmitResult(
        outcome: SubmitOutcome.verified,
        requestId: 'x',
        cost: 20,
        autoApproved: true,
      );
}

/// 可变假仓储：测试中动态增删 pending，用于验证「经济修订号自增 → 商店重算」。
class _MutableRewardRepository implements RewardRepository {
  final List<RedemptionRequest> pending = <RedemptionRequest>[];

  static const List<RewardTemplate> _seeds = <RewardTemplate>[
    RewardTemplate(
      id: 'tpl_extra_episode',
      name: '选今晚动画片',
      category: RewardCategory.selfService,
      baseCost: 60,
      frequencyLimitPerWeek: 1,
    ),
  ];

  @override
  Future<List<RewardTemplate>> templates() async => _seeds;
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      List<RedemptionRequest>.of(pending);
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];
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

void main() {
  testWidgets('StorePage 渲染：标题「阳光商店」+ 种子奖励可见', (tester) async {
    final reward = _FakeRewardRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          redemptionOrchestrationServiceProvider
              .overrideWithValue(_FakeRedemptionOrchestrationService()),
          rewardRepositoryProvider.overrideWithValue(reward),
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
          // C62：商店页需读当周池余量（只读 pool()）→ 必须注入假池仓储与假埋点仓储。
          weeklyPoolRepositoryProvider
              .overrideWithValue(_FakeWeeklyPoolRepository()),
          trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
        ],
        child: MaterialApp(home: const StorePage()),
      ),
    );
    await tester.pumpAndSettle();

    // AppBar 标题渲染正确。
    expect(find.text('阳光商店'), findsOneWidget);
    // 种子奖励名（中文）经 rewardRepositoryProvider 注入并渲染。
    expect(find.text('小零食'), findsWidgets);
    expect(find.text('多看一集动画片'), findsWidgets);
  });

  testWidgets('家长端处理后同步：economyRevision 自增 → 商店重算（待核销归零、兑换解除禁用）',
      (tester) async {
    final reward = _MutableRewardRepository()
      ..pending.add(RedemptionRequest(
        id: 'r1',
        childId: 'c1',
        templateId: 'tpl_extra_episode',
        requestedAt: DateTime(2026, 9, 20, 22, 50),
        cost: 60,
        status: RequestStatus.pending,
      ));

    final container = ProviderContainer(
      overrides: <Override>[
        redemptionOrchestrationServiceProvider
            .overrideWithValue(_FakeRedemptionOrchestrationService()),
        rewardRepositoryProvider.overrideWithValue(reward),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        // C62：商店页需读当周池余量（只读 pool()）→ 必须注入假池仓储与假埋点仓储。
        weeklyPoolRepositoryProvider
            .overrideWithValue(_FakeWeeklyPoolRepository()),
        trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StorePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 初始：余额处展示「待核销 60」，卡片停在禁用态（兑换不可点）。
    expect(find.text('待核销 60'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '兑换'))
          .onPressed,
      isNull,
    );

    // 模拟家长端「拒绝」：数据变更 + 经济修订号自增（与 VerificationCard 行为一致）。
    reward.pending.clear();
    container.read(economyRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();

    // 重算后：待核销归零（>0 才渲染），卡片恢复可兑换。
    expect(find.text('待核销 60'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '兑换'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('C68：切回商店 tab → 自动重算（**无**任何页面内动作、**无**经济号自增）',
      (tester) async {
    // 本用例是 C68 的**真实页面端到端**接线验证（机制本身见
    // test/m3/child_tab_refresh_test.dart）：数据在背面变了，但页面收不到任何
    // 经济信号 —— 这正是玄参 2026-10-14 反馈的场景（08:00 晨露到期 / 家长端改了
    // 数据），修复前必须靠「点开花盆再关掉」之类的页面内动作才被动刷新。
    final reward = _MutableRewardRepository()
      ..pending.add(RedemptionRequest(
        id: 'r1',
        childId: 'c1',
        templateId: 'tpl_extra_episode',
        requestedAt: DateTime(2026, 9, 20, 22, 50),
        cost: 60,
        status: RequestStatus.pending,
      ));

    final container = ProviderContainer(
      overrides: <Override>[
        redemptionOrchestrationServiceProvider
            .overrideWithValue(_FakeRedemptionOrchestrationService()),
        rewardRepositoryProvider.overrideWithValue(reward),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        weeklyPoolRepositoryProvider
            .overrideWithValue(_FakeWeeklyPoolRepository()),
        trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StorePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待核销 60'), findsOneWidget);

    // 外壳当前停在「今日」→ 商店不可见（默认 tab 索引 0）。
    expect(container.read(childShellTabIndexProvider), kChildTabIndexOfToday);

    // 背面数据变化，但**不**自增 economyRevision（模拟「无经济信号的陈旧」）。
    reward.pending.clear();
    await tester.pumpAndSettle();
    expect(find.text('待核销 60'), findsOneWidget,
        reason: '没有任何刷新触发 → 仍是旧快照（这就是修复前的真实表现）');

    // 切走再切回 → 外壳 tab 索引变化 → C68 方案 A 自动重算。
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfStore;
    await tester.pumpAndSettle();

    expect(find.text('待核销 60'), findsNothing,
        reason: 'C68：切回商店 tab 必须自动重算，不依赖任何页面内动作');
  });

  testWidgets('C62：可用阳光不足 → 卡片置灰 + 内联「阳光不足」', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          redemptionOrchestrationServiceProvider
              .overrideWithValue(_FakeRedemptionOrchestrationService()),
          rewardRepositoryProvider.overrideWithValue(_MutableRewardRepository()),
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          // 余额 30 < 卡片价 60 → 可用阳光不足
          sunlightRepositoryProvider
              .overrideWithValue(_FakeSunlightRepository(balanceValue: 30)),
          weeklyPoolRepositoryProvider
              .overrideWithValue(_FakeWeeklyPoolRepository()),
          trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
        ],
        child: const MaterialApp(home: StorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阳光不足'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '兑换'))
          .onPressed,
      isNull,
      reason: 'C62：买不起必须置灰（且已内联说明原因，非静默失败）',
    );
  });

  testWidgets('C62：当周池已满（余额充足）→ 卡片置灰 + 内联「本周额度已满」',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          redemptionOrchestrationServiceProvider
              .overrideWithValue(_FakeRedemptionOrchestrationService()),
          rewardRepositoryProvider.overrideWithValue(_MutableRewardRepository()),
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          // 余额充足（999），但周池余量 0 < 卡片价 60 → 超池
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
          weeklyPoolRepositoryProvider.overrideWithValue(
            _FakeWeeklyPoolRepository(
              pool: const WeeklyPool(weekKey: '2026-09-14', budget: 160, used: 160),
            ),
          ),
          trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
        ],
        child: const MaterialApp(home: StorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本周额度已满'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '兑换'))
          .onPressed,
      isNull,
    );
  });
}
