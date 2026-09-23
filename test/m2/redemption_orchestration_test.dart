/// 兑换编排服务测试（§4.1–4.3）：submit / verify / releaseQueue 全路径。
///
/// 纯 Dart：所有仓储以 Fake 实现，不依赖 Drift / Flutter。
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:test/test.dart';

// ── Fakes ────────────────────────────────────────────────────────────────

class FakeRewardRepository implements RewardRepository {
  final Map<String, RewardTemplate> templates_ = {};
  final Map<String, RedemptionRequest> requests = {};
  final Map<String, int> cooldown = {};

  void addTemplate(RewardTemplate t) => templates_[t.id] = t;

  @override
  Future<List<RewardTemplate>> templates() async => templates_.values.toList();

  @override
  Future<void> saveTemplate(RewardTemplate t) async => templates_[t.id] = t;

  @override
  Future<void> deleteTemplate(String id) async => templates_.remove(id);

  @override
  Future<void> createRequest(RedemptionRequest r) async {
    requests[r.id] = r;
    // 模拟真实仓储：落申请即 bump 本周冷却计数（D4）。
    cooldown[r.templateId] = (cooldown[r.templateId] ?? 0) + 1;
  }

  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async => requests.values
      .where((r) =>
          r.status == RequestStatus.pending || r.status == RequestStatus.queued)
      .toList();

  @override
  Future<List<RedemptionRequest>> verifiedRequests() async => requests.values
      .where((r) => r.status == RequestStatus.verified)
      .toList();

  @override
  Future<List<RedemptionRequest>> rejectedRequests() async => requests.values
      .where((r) => r.status == RequestStatus.rejected)
      .toList();

  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      requests.values
          .where((r) => r.status == RequestStatus.queued)
          .toList();

  @override
  Future<void> updateRequest(RedemptionRequest r) async => requests[r.id] = r;

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async =>
      cooldown[templateId] ?? 0;

  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {
    final int current = cooldown[templateId] ?? 0;
    cooldown[templateId] = (current - 1).clamp(0, current);
  }
}

class FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  final Map<String, WeeklyPool> store = {};
  @override
  Future<WeeklyPool?> get(String weekKey) async => store[weekKey];
  @override
  Future<void> upsert(WeeklyPool pool) async => store[pool.weekKey] = pool;
  @override
  List<String> weeksBetween(String fromKey, String toKey) => [fromKey, toKey];
}

class FakeSunlightRepository implements SunlightRepository {
  double balance_ = 0;
  final List<SunlightEntry> entries = [];
  @override
  Future<double> append(SunlightEntry e) async {
    balance_ += e.net;
    entries.add(e);
    return balance_;
  }

  @override
  Future<double> balance() async => balance_;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.from(entries);
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
}

class FakeTrackingRepository implements TrackingRepository {
  final List<TrackingEvent> events = [];
  @override
  Future<void> track(TrackingEvent e) async => events.add(e);
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      events.where((e) => e.type == t).toList();
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class FakeSettingsRepository implements SettingsRepository {
  final AppSettings _settings;
  FakeSettingsRepository(this._settings);
  @override
  Future<AppSettings> getSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class FakeAccountService implements AccountService {
  @override
  String get childId => kChildIdDefault;
  @override
  String currentChildId() => kChildIdDefault;
  @override
  Future<void> ensureChild() => throw UnsupportedError('x');
  @override
  Never signIn() => throw UnsupportedError('x');
  @override
  Never linkFamily() => throw UnsupportedError('x');
  @override
  Never syncProfile() => throw UnsupportedError('x');
}

// ── 组装辅助 ───────────────────────────────────────────────────────────────

RedemptionOrchestrationService build({
  required FakeRewardRepository reward,
  required FakeWeeklyPoolRepository poolRepo,
  required FakeSunlightRepository ledger,
  required FakeTrackingRepository tracking,
  required FakeSettingsRepository settings,
}) {
  final poolService = WeeklyPoolService(poolRepo, settings, tracking);
  return RedemptionOrchestrationService(
    reward: reward,
    pools: poolService,
    ledger: ledger,
    tracking: tracking,
    account: FakeAccountService(),
    settings: settings,
  );
}

const lowSettings = AppSettings(
  ageTier: AgeTier.low,
  dailyFocusCap: 90,
  dailyAppCapMinutes: 30,
  restAfterSessions: 2,
  restMinutes: 10,
  taskSunlight: 12,
  poolBudget: 160,
);

void main() {
  group('RedemptionOrchestrationService.submit', () {
    test('(a) 低档小额 parentHandled → 自动放行 verified + 扣账本 + 埋 reward_redeem_request',
        () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final settings = FakeSettingsRepository(lowSettings);
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: settings,
      );

      final res = await svc.submit(
        'seed_snack',
        AgeTier.low,
        DateTime(2026, 9, 15),
      );

      expect(res.outcome, SubmitOutcome.verified);
      expect(res.autoApproved, isTrue);
      expect(res.cost, 20);
      expect(ledger.entries, hasLength(1));
      expect(ledger.entries.first.net, -20);
      expect(ledger.entries.first.type, SunlightType.redeem);
      expect(
        tracking.events.any((e) => e.name == TrackingEventNames.rewardRedeemRequest),
        isTrue,
      );
      // 周池 autoReleased 累计
      expect(
        (await svc.pendingList()),
        isEmpty,
      ); // pendingList 仅含 pending/queued，verified 不在内
    });

    test('(b) selfService 类 → 待核销 pending（C5③）', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_extra_episode',
        name: '多看一集动画片',
        category: RewardCategory.selfService,
        baseCost: 50,
        frequencyLimitPerWeek: 1,
      ));
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );

      final res = await svc.submit(
        'seed_extra_episode',
        AgeTier.low,
        DateTime(2026, 9, 15),
      );
      expect(res.outcome, SubmitOutcome.pending);
      expect(res.autoApproved, isFalse);
      expect(ledger.entries, isEmpty); // pending 不提前扣账本
    });

    test('(c) 冷却：首次提交后同模板再提交 → rejectedCooldown，无新申请、无 reward_*',
        () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      final first = await svc.submit(
        'seed_snack',
        AgeTier.low,
        DateTime(2026, 9, 15),
      );
      expect(first.outcome, SubmitOutcome.verified);

      final second = await svc.submit(
        'seed_snack',
        AgeTier.low,
        DateTime(2026, 9, 16),
      );
      expect(second.outcome, SubmitOutcome.rejectedCooldown);
      expect(reward.requests.length, 1); // 无新申请
      // 仅首次提交了 reward_redeem_request（verified 分支），第二次未埋 reward_*
      expect(
        tracking.events.where((e) => e.name == TrackingEventNames.rewardRedeemRequest).length,
        1,
      );
    });

    test('(d) 余额不足 → rejectedBalance，无申请、无账本扣减', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      final ledger = FakeSunlightRepository()..balance_ = 0; // < cost(20)
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      final res = await svc.submit(
        'seed_snack',
        AgeTier.low,
        DateTime(2026, 9, 15),
      );
      expect(res.outcome, SubmitOutcome.rejectedBalance);
      expect(reward.requests, isEmpty);
      expect(ledger.entries, isEmpty);
      expect(
        tracking.events.any((e) => e.name == TrackingEventNames.rewardRedeemRequest),
        isFalse,
      );
    });
  });

  group('RedemptionOrchestrationService.verify', () {
    test('(e) pending 核销 → verified + 扣账本 + 埋 reward_verified（within_48h 正确）',
        () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_extra_episode',
        name: '多看一集动画片',
        category: RewardCategory.selfService,
        baseCost: 50,
        frequencyLimitPerWeek: 1,
      ));
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      final reqAt = DateTime(2026, 9, 15, 10, 0);
      final submitted = await svc.submit('seed_extra_episode', AgeTier.low, reqAt);
      expect(submitted.outcome, SubmitOutcome.pending);
      final requestId = submitted.requestId!;

      // 1 小时后核销
      final verifyAt = reqAt.add(const Duration(hours: 1));
      await svc.verify(requestId, verifyAt);

      final req = reward.requests[requestId]!;
      expect(req.status, RequestStatus.verified);
      expect(req.verifiedAt, verifyAt);
      expect(ledger.entries, hasLength(1));
      expect(ledger.entries.first.net, -50);

      final verifiedEvent = tracking.events
          .firstWhere((e) => e.name == TrackingEventNames.rewardVerified);
      expect(verifiedEvent.payload['within_48h'], isTrue);
      expect(verifiedEvent.payload['amount'], 50);
      expect(verifiedEvent.payload['tier'], 'low');
      // is_small = cost <= 50 → 50<=50 为 true
      expect(verifiedEvent.payload['is_small'], isTrue);
    });

    test('(e2) 超过 48h 核销 → within_48h=false', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_extra_episode',
        name: '多看一集动画片',
        category: RewardCategory.selfService,
        baseCost: 50,
        frequencyLimitPerWeek: 1,
      ));
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: FakeSunlightRepository()..balance_ = 100,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );
      final reqAt = DateTime(2026, 9, 15, 10, 0);
      final submitted = await svc.submit('seed_extra_episode', AgeTier.low, reqAt);
      final verifyAt = reqAt.add(const Duration(hours: 49));
      await svc.verify(submitted.requestId!, verifyAt);
      final ev = tracking.events
          .firstWhere((e) => e.name == TrackingEventNames.rewardVerified);
      expect(ev.payload['within_48h'], isFalse);
    });
  });

  group('RedemptionOrchestrationService.releaseQueue', () {
    test('(f1) 次周新周池充足 → queued 释放为 verified + 扣账本', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      // 手动注入一条 queued 请求（上周）
      reward.requests['q1'] = RedemptionRequest(
        id: 'q1',
        childId: kChildIdDefault,
        templateId: 'seed_snack',
        requestedAt: DateTime(2026, 8, 31),
        cost: 20,
        status: RequestStatus.queued,
        autoApproved: false,
        queuePosition: 1,
      );
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      final report = await svc.releaseQueue('2026-08-31', DateTime(2026, 9, 1));
      expect(report.released, 1);
      expect(report.deferred, 0);
      expect(reward.requests['q1']!.status, RequestStatus.verified);
      expect(ledger.entries, hasLength(1));
      expect(ledger.entries.first.type, SunlightType.queueRelease);
      expect(ledger.entries.first.net, -20);
    });

    test('(f2) 余额不足 → queued 顺延下周（deferred）', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      reward.requests['q1'] = RedemptionRequest(
        id: 'q1',
        childId: kChildIdDefault,
        templateId: 'seed_snack',
        requestedAt: DateTime(2026, 8, 31),
        cost: 20,
        status: RequestStatus.queued,
        autoApproved: false,
        queuePosition: 1,
      );
      final ledger = FakeSunlightRepository()..balance_ = 0; // 余额不足
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );

      final report = await svc.releaseQueue('2026-08-31', DateTime(2026, 9, 1));
      expect(report.released, 0);
      expect(report.deferred, 1);
      expect(reward.requests['q1']!.status, RequestStatus.queued); // 仍排队
      expect(ledger.entries, isEmpty);
    });

    test('(f3) 新周池已满 → queued 顺延下周（deferred）', () async {
      final reward = FakeRewardRepository();
      reward.addTemplate(const RewardTemplate(
        id: 'seed_snack',
        name: '小零食',
        category: RewardCategory.parentHandled,
        baseCost: 20,
        frequencyLimitPerWeek: 1,
      ));
      reward.requests['q1'] = RedemptionRequest(
        id: 'q1',
        childId: kChildIdDefault,
        templateId: 'seed_snack',
        requestedAt: DateTime(2026, 8, 31),
        cost: 20,
        status: RequestStatus.queued,
        autoApproved: false,
        queuePosition: 1,
      );
      // 预置已用满的当周池
      final poolRepo = FakeWeeklyPoolRepository();
      poolRepo.store['2026-08-31'] =
          WeeklyPool(weekKey: '2026-08-31', budget: 160, used: 160);
      final svc = build(
        reward: reward,
        poolRepo: poolRepo,
        ledger: FakeSunlightRepository()..balance_ = 100,
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );

      final report = await svc.releaseQueue('2026-08-31', DateTime(2026, 9, 1));
      expect(report.released, 0);
      expect(report.deferred, 1);
    });
  });

  group('RedemptionOrchestrationService.reject（家长拒绝回流）', () {
    RewardTemplate animTpl() => const RewardTemplate(
          id: 'seed_extra_episode',
          name: '选今晚动画片',
          category: RewardCategory.selfService,
          baseCost: 60,
          frequencyLimitPerWeek: 1,
        );

    test('(g1) pending 拒绝 → rejected，退出待处理列表，不写账本、余额分毫未动', () async {
      final reward = FakeRewardRepository()..addTemplate(animTpl());
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      final submitted = await svc.submit(
        'seed_extra_episode',
        AgeTier.low,
        DateTime(2026, 9, 20, 22, 50),
      );
      expect(submitted.outcome, SubmitOutcome.pending);
      expect(ledger.entries, isEmpty); // pending 阶段从未扣账本

      await svc.reject(submitted.requestId!, DateTime(2026, 9, 20, 23, 10));

      final req = reward.requests[submitted.requestId!]!;
      expect(req.status, RequestStatus.rejected);
      expect(req.verifiedAt, isNull);
      // 核心不变式：拒绝 = 从不做扣减，故账本始终为空、余额不变（阳光「原路返回」）
      expect(ledger.entries, isEmpty);
      expect(await ledger.balance(), 100);
      // 退出家长端待处理列表（卡应消失）
      expect(await svc.pendingList(), isEmpty);

      final ev = tracking.events
          .firstWhere((e) => e.name == TrackingEventNames.rewardRejected);
      expect(ev.payload['source'], 'pending');
      expect(ev.payload['amount'], 60);
    });

    test('(g2) queued 拒绝 → rejected，source=queued，仍不扣账本', () async {
      final reward = FakeRewardRepository();
      reward.requests['q1'] = RedemptionRequest(
        id: 'q1',
        childId: kChildIdDefault,
        templateId: 'seed_extra_episode',
        requestedAt: DateTime(2026, 8, 31),
        cost: 20,
        status: RequestStatus.queued,
        autoApproved: false,
        queuePosition: 1,
      );
      final ledger = FakeSunlightRepository()..balance_ = 100;
      final tracking = FakeTrackingRepository();
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: ledger,
        tracking: tracking,
        settings: FakeSettingsRepository(lowSettings),
      );

      await svc.reject('q1', DateTime(2026, 9, 20, 23, 10));

      expect(reward.requests['q1']!.status, RequestStatus.rejected);
      expect(ledger.entries, isEmpty);
      final ev = tracking.events
          .firstWhere((e) => e.name == TrackingEventNames.rewardRejected);
      expect(ev.payload['source'], 'queued');
    });

    test('(g3) 已核销的申请再拒绝 → 抛 StateError（核销/拒绝互斥）', () async {
      final reward = FakeRewardRepository()..addTemplate(animTpl());
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: FakeSunlightRepository()..balance_ = 100,
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );

      final submitted = await svc.submit(
        'seed_extra_episode',
        AgeTier.low,
        DateTime(2026, 9, 20, 22, 50),
      );
      await svc.verify(submitted.requestId!, DateTime(2026, 9, 20, 23, 0));

      await expectLater(
        () => svc.reject(submitted.requestId!, DateTime(2026, 9, 20, 23, 10)),
        throwsA(isA<StateError>()),
      );
    });

    test('(g4) 拒绝回流 → 本周冷却计数回退 1（可兑换次数不因被拒而减少，第4轮第3点）',
        () async {
      final reward = FakeRewardRepository()..addTemplate(RewardTemplate(
            id: 'seed_popsicle',
            name: '吃冰棍儿',
            category: RewardCategory.parentHandled,
            baseCost: 40,
            frequencyLimitPerWeek: 3, // 每周可兑换 3 次
          ));
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: FakeSunlightRepository()..balance_ = 200,
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );

      // 孩子落单 2 次（孩子端恒传 forcePending:true）→ 冷却计数 2（剩余 1）。
      final r1 = await svc.submit(
          'seed_popsicle', AgeTier.low, DateTime(2026, 9, 20, 22, 50),
          forcePending: true);
      final r2 = await svc.submit(
          'seed_popsicle', AgeTier.low, DateTime(2026, 9, 20, 22, 55),
          forcePending: true);
      expect(r1.outcome, SubmitOutcome.pending);
      expect(r2.outcome, SubmitOutcome.pending);
      expect(await reward.cooldownCount('seed_popsicle', CooldownPeriod.weekly),
          2);

      // 家长拒绝第 1 笔 → 冷却计数应回退为 1，可兑换次数恢复（3 - 1 = 2）。
      await svc.reject(r1.requestId!, DateTime(2026, 9, 20, 23, 10));
      expect(await reward.cooldownCount('seed_popsicle', CooldownPeriod.weekly),
          1);
      // 被拒的这笔不再计入待处理列表。
      expect(await svc.pendingList(),
          hasLength(1)); // 仅剩 r2
    });
  });

  group('pendingList', () {
    test('按 requested_at 升序返回 pending + queued', () async {
      final reward = FakeRewardRepository();
      reward.requests['b'] = RedemptionRequest(
        id: 'b',
        childId: kChildIdDefault,
        templateId: 't',
        requestedAt: DateTime(2026, 9, 2),
        cost: 10,
        status: RequestStatus.queued,
      );
      reward.requests['a'] = RedemptionRequest(
        id: 'a',
        childId: kChildIdDefault,
        templateId: 't',
        requestedAt: DateTime(2026, 9, 1),
        cost: 10,
        status: RequestStatus.pending,
      );
      reward.requests['v'] = RedemptionRequest(
        id: 'v',
        childId: kChildIdDefault,
        templateId: 't',
        requestedAt: DateTime(2026, 9, 3),
        cost: 10,
        status: RequestStatus.verified, // 不应出现
      );
      final svc = build(
        reward: reward,
        poolRepo: FakeWeeklyPoolRepository(),
        ledger: FakeSunlightRepository(),
        tracking: FakeTrackingRepository(),
        settings: FakeSettingsRepository(lowSettings),
      );
      final list = await svc.pendingList();
      expect(list.map((r) => r.id).toList(), ['a', 'b']); // verified 被排除
    });
  });
}
