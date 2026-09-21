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
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
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
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;
  @override
  Future<void> upsert(WeeklyPool pool) async {}
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

    // 初始：右上角「待核销 60」，卡片停在「待家长核销」禁用态（兑换不可点）。
    expect(find.text('待核销 60'), findsOneWidget);
    expect(find.text('待家长核销'), findsOneWidget);
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
    expect(find.text('待家长核销'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '兑换'))
          .onPressed,
      isNotNull,
    );
  });
}
