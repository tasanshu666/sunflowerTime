/// 付费门控接线 · 阶段 4 验收测试（含**证据性测试**）。
///
/// 本文件把阶段 4 的免费边界**钉死**，并对红线 C69（额度超限**只拦新增、绝不删
/// 已存数据**）给出**可证伪的证据**——不是「跑通了」，而是「观测到未删除」：
///
///  1. 单点判定：[`quotaAllowsAdd`] 的 free / premium 边界（达到 / 超过额度一律拦新增）；
///  2. 任务页证据：免费版**预置 9 条**成长项 → 触发「新增成长项」→ 断言：
///       · 条数仍 = 9；· `deleteTaskById` 调用次数 == 0；· `saveTask` == 0；· 编辑器未打开；
///  3. 奖励页证据：免费版**预置 6 条**奖励 → 触发「新增奖励」→ 断言同上（删除 / 保存 == 0）；
///  4. 花盆证据：免费档 + 存量已满 12 盆 → `expandPot` 抛异常、容量**仍 = 12**、
///     已有植物**未被删除**（盆位可用）；对照 premium 档同场景可扩容（证明是配额拦截而非整体坏死）；
///  5. 源码守卫：家长端「新增」入口一律走 [`PremiumQuotaGate.onTap`]（不置空回调，C62）；
///     孩子端页面**不出现**任何购买入口 / 价格 / `/parent/premium`。
library phase4_gating_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

AppSettings _settingsWithPotCapacity(int capacity) => AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 60,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: capacity,
    );

// ── 造数 ─────────────────────────────────────────────────────────────────────

Task _task(int i) => Task(
      id: 'task_$i',
      name: '成长项 $i',
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 8,
      isCustom: true,
    );

RewardTemplate _reward(int i) => RewardTemplate(
      id: 'reward_$i',
      name: '奖励 $i',
      category: RewardCategory.parentHandled,
      baseCost: 30,
      frequencyLimitPerWeek: 3,
    );

// ── 任务仓储间谍（计数删除 / 保存调用次数）────────────────────────────────────

class _SpyTaskRepository implements TaskRepository {
  _SpyTaskRepository(this.store);

  final List<Task> store;
  int saveCount = 0;
  int deleteCount = 0;

  @override
  Future<List<Task>> tasks() async => List<Task>.of(store);

  @override
  Future<void> saveTask(Task task) async {
    saveCount++;
    store.removeWhere((Task t) => t.id == task.id);
    store.add(task);
  }

  @override
  Future<void> deleteTaskById(String id) async {
    deleteCount++;
    store.removeWhere((Task t) => t.id == id);
  }

  @override
  Future<void> checkIn(CheckIn checkIn) async {}

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async =>
      const <CheckIn>[];

  @override
  Future<int> totalCheckInCount() async => 0;
}

// ── 奖励仓储间谍 ─────────────────────────────────────────────────────────────

class _SpyRewardRepository implements RewardRepository {
  _SpyRewardRepository(this.store);

  final List<RewardTemplate> store;
  int saveCount = 0;
  int deleteCount = 0;

  @override
  Future<List<RewardTemplate>> templates() async =>
      List<RewardTemplate>.of(store);

  @override
  Future<void> saveTemplate(RewardTemplate t) async {
    saveCount++;
    store.removeWhere((RewardTemplate e) => e.id == t.id);
    store.add(t);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    deleteCount++;
    store.removeWhere((RewardTemplate e) => e.id == id);
  }

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async =>
      0;

  // 本测试不打桩的成员（兑换申请相关）一律抛异常，避免被误用。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在本测试中打桩');
}

// ── 设置仓储 Fake ────────────────────────────────────────────────────────────

class _FakeSettings implements SettingsRepository {
  _FakeSettings(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async => _settings = settings;
}

// ── 周阳光池相关 Fake（供奖励页渲染 WeeklyPoolCard）───────────────────────────

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;

  @override
  Future<void> upsert(WeeklyPool pool) async {}

  @override
  List<String> weeksBetween(String fromKey, String toKey) => const <String>[];
}

/// 固定返回池数据的周池服务（避免奖励页渲染时触达真实 Drift）。
///
/// `WeeklyPoolService` 构造要求 `TrackingRepository`；本测试用例不触发写埋点，
/// 用一个「实现该接口、所有方法走 noSuchMethod」的空壳即可（见 [_NoopTracking]）。
class _StaticWeeklyPoolService extends WeeklyPoolService {
  _StaticWeeklyPoolService(SettingsRepository settings)
      : super(_FakeWeeklyPoolRepository(), settings, _NoopTracking());

  @override
  Future<WeeklyPool> pool(String weekKey) async =>
      WeeklyPool(weekKey: weekKey, budget: 160);
  // C90-C 同日二次修订：`updateBudget` 已随「本周预算调整」控件删除一并移除，
  // 原 Fake 覆写不再需要。
}

/// `TrackingRepository` 空壳（仅满足构造签名，方法不被调用）。
class _NoopTracking implements TrackingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

// ── 权益仓储 Fake（供 MatrixEntitlementService）──────────────────────────────

class _FakeEntitlementRepository implements EntitlementRepository {
  _FakeEntitlementRepository([this._stored = Entitlement.free]);

  Entitlement _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

// ── 植物 / 账本 / 专注 / 开花奖励 Fake（仅 expandPot 路径需要）────────────────

class _FakePlantRepository implements PlantRepository {
  _FakePlantRepository(this._plants);

  final List<Plant> _plants;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在本测试中打桩');
}

/// 账本 Fake：余额充足（扩容扣费够用），记录 append 以便断言。
class _FakeSunlightRepository implements SunlightRepository {
  final List<SunlightEntry> appended = <SunlightEntry>[];

  @override
  Future<double> balance() async => 100000.0;

  @override
  Future<double> append(SunlightEntry entry) async {
    appended.add(entry);
    return balance();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在本测试中打桩');
}

class _FakeFocusRepository implements FocusRepository {
  /// C77（2026-10-15）：`expandPot` 缺省 perk 时内部走 [PlantGrowthService.currentPerk]
  /// → 本仓储的 `totalStats()`（域层新依赖）。返回 0 分钟 = Lv.0 = 无称号加成，
  /// 扩容价取**基础价** —— 与「测试只验配额拦截，不验属性」的本文件意图一致。
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在本测试中打桩');
}

class _FakeBloomRewardRepository implements BloomRewardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在本测试中打桩');
}

/// 构造一个注入了指定档位权益服务的 [PlantGrowthService]。
Future<PlantGrowthService> _buildGrowthService({
  required _FakeSettings settings,
  required EntitlementTier tier,
  required _FakePlantRepository plants,
  _FakeSunlightRepository? ledger,
}) async {
  final MatrixEntitlementService ent = MatrixEntitlementService(
    repository: _FakeEntitlementRepository(
      tier == EntitlementTier.premium
          ? Entitlement.lifetime()
          : Entitlement.free,
    ),
  );
  await ent.load();
  return PlantGrowthService(
    plants: plants,
    focus: _FakeFocusRepository(),
    ledger: ledger ?? _FakeSunlightRepository(),
    settings: settings,
    bloomRewards: _FakeBloomRewardRepository(),
    entitlement: ent,
  );
}

void main() {
  final String root = _projectRoot();

  // ── 1. 单点判定 ───────────────────────────────────────────────────────────
  group('单点判定 quotaAllowsAdd：达到/超过额度一律拦新增', () {
    test('任务：free 阈值 5 —— 4 放行、5 拦、9 拦；premium 不限', () {
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.free, 4),
        isTrue,
      );
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.free, 5),
        isFalse,
      );
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.free, 9),
        isFalse,
      );
      expect(
        quotaAllowsAdd(
            FeatureKey.taskTemplateCount, EntitlementTier.premium, 99),
        isTrue,
      );
    });

    test('奖励：free 阈值 5；premium 不限', () {
      expect(
        quotaAllowsAdd(FeatureKey.rewardTemplateCount, EntitlementTier.free, 4),
        isTrue,
      );
      expect(
        quotaAllowsAdd(FeatureKey.rewardTemplateCount, EntitlementTier.free, 5),
        isFalse,
      );
      expect(
        quotaAllowsAdd(
            FeatureKey.rewardTemplateCount, EntitlementTier.premium, 50),
        isTrue,
      );
    });

    test('花盆：free 上限 = 基础容量 4；premium = 12', () {
      expect(kFreeGardenPotQuota, 4);
      expect(kPremiumGardenPotQuota, 12);
      expect(
        quotaAllowsAdd(FeatureKey.gardenPotCapacity, EntitlementTier.free, 3),
        isTrue,
      );
      expect(
        quotaAllowsAdd(FeatureKey.gardenPotCapacity, EntitlementTier.free, 4),
        isFalse,
      );
      expect(
        quotaAllowsAdd(FeatureKey.gardenPotCapacity, EntitlementTier.free, 12),
        isFalse,
      );
      expect(
        quotaAllowsAdd(
            FeatureKey.gardenPotCapacity, EntitlementTier.premium, 11),
        isTrue,
      );
      expect(
        quotaAllowsAdd(
            FeatureKey.gardenPotCapacity, EntitlementTier.premium, 12),
        isFalse,
      );
    });

    test('整项被关闭的能力：free 一律不放行（一键操作）', () {
      expect(
        quotaAllowsAdd(FeatureKey.oneClickCare, EntitlementTier.free, 0),
        isFalse,
      );
      expect(
        quotaAllowsAdd(FeatureKey.oneClickCare, EntitlementTier.premium, 0),
        isTrue,
      );
    });
  });

  // ── 2. 任务页证据性测试 ────────────────────────────────────────────────────
  group('🔴 证据 · 任务页：免费预置 9 条，新增被拦且不删任何数据', () {
    testWidgets('预置 9 → 点新增 → 仍 9 条、deleteTaskById==0、saveTask==0、编辑器未开',
        (WidgetTester tester) async {
      final List<Task> store =
          List<Task>.generate(9, (int i) => _task(i), growable: true);
      final _SpyTaskRepository spy = _SpyTaskRepository(store);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
            taskRepositoryProvider.overrideWithValue(spy),
          ],
          child: const MaterialApp(
            home: ParentTaskConfigPage(embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 前置：确为 9 条（否则断言失去意义）。
      expect(find.text('9 项'), findsOneWidget, reason: '前置：应展示 9 条成长项');

      await tester.tap(find.text('新增成长项'));
      await tester.pumpAndSettle();

      // 证据：条数不变、未删除、未保存、编辑器未打开。
      expect(find.text('9 项'), findsOneWidget, reason: '被拦后条数必须仍 = 9');
      expect(spy.store.length, 9, reason: 'C69：仓储条目数不得因被拦而改变');
      expect(spy.deleteCount, 0, reason: 'C69 红线：门控绝不删除任何已存数据');
      expect(spy.saveCount, 0, reason: '被拦时不得写入新条目');
      expect(find.byType(TaskEditorDialog), findsNothing,
          reason: '被拦时不应打开新增编辑器');

      // 分因提示（C62：不静默失败）。
      expect(find.textContaining('免费版最多 5'), findsOneWidget);
      expect(find.textContaining('免费上限 5'), findsOneWidget);
    });

    testWidgets('未达上限（3 条）→ 点新增 → 打开编辑器（对照，证明放行路径未坏）',
        (WidgetTester tester) async {
      final List<Task> store =
          List<Task>.generate(3, (int i) => _task(i), growable: true);
      final _SpyTaskRepository spy = _SpyTaskRepository(store);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
            taskRepositoryProvider.overrideWithValue(spy),
          ],
          child: const MaterialApp(
            home: ParentTaskConfigPage(embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('新增成长项'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditorDialog), findsOneWidget,
          reason: '未达上限应正常打开新增编辑器');
      expect(spy.deleteCount, 0);
    });
  });

  // ── 3. 奖励页证据性测试 ────────────────────────────────────────────────────
  group('🔴 证据 · 奖励页：免费预置 6 条，新增被拦且不删任何数据', () {
    testWidgets('预置 6 → 点新增 → 仍 6 条、deleteTemplate==0、saveTemplate==0、编辑器未开',
        (WidgetTester tester) async {
      final List<RewardTemplate> store = List<RewardTemplate>.generate(
          6, (int i) => _reward(i),
          growable: true);
      final _SpyRewardRepository spy = _SpyRewardRepository(store);
      final _FakeSettings settings = _FakeSettings(_settingsWithPotCapacity(12));

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
            rewardRepositoryProvider.overrideWithValue(spy),
            settingsRepositoryProvider.overrideWithValue(settings),
            weeklyPoolServiceProvider
                .overrideWithValue(_StaticWeeklyPoolService(settings)),
          ],
          child: const MaterialApp(home: Scaffold(body: ParentRewardPage())),
        ),
      );
      await tester.pumpAndSettle();

      // 前置：确为 6 条。
      expect(spy.store.length, 6, reason: '前置：应预置 6 条奖励');

      await tester.tap(find.text('新增奖励'));
      await tester.pumpAndSettle();

      // 证据：条数不变、未删除、未保存。对话框标题也叫「新增奖励」，
      // 被拦时不弹出 → 该文案仍只有按钮一处。
      expect(spy.store.length, 6, reason: 'C69：仓储条目数不得因被拦而改变');
      expect(spy.deleteCount, 0, reason: 'C69 红线：门控绝不删除任何已存数据');
      expect(spy.saveCount, 0, reason: '被拦时不得写入新模板');
      expect(find.text('新增奖励'), findsOneWidget,
          reason: '被拦时不应弹出「新增奖励」对话框（否则会出现第二处文案）');

      expect(find.textContaining('免费版最多 5'), findsOneWidget);
      expect(find.textContaining('免费上限 5'), findsOneWidget);
    });
  });

  // ── 4. 花盆证据性测试（域层 expandPot）─────────────────────────────────────
  group('🔴 证据 · 花盆：free + 存量已满 12 → 仅扩容被拦、容量与植物保留', () {
    test('free 档 + 已满 12 盆 → expandPot 抛异常、容量仍 12、植物未被删', () async {
      final _FakeSettings settings = _FakeSettings(_settingsWithPotCapacity(12));
      final _FakePlantRepository plants = _FakePlantRepository(<Plant>[
        for (int i = 0; i < 12; i++)
          Plant(
            id: 'p$i',
            speciesId: 's$i',
            potIndex: i,
            stage: PlantStage.sprout,
            stageStartedAt: DateTime(2026, 1, 1),
            growthFactor: 1.0,
            status: PlantStatus.growing,
            plantedAt: DateTime(2026, 1, 1),
          ),
      ]);
      final PlantGrowthService svc = await _buildGrowthService(
        settings: settings,
        tier: EntitlementTier.free,
        plants: plants,
      );

      await expectLater(
        svc.expandPot(DateTime(2026, 1, 5, 10)),
        throwsA(isA<PlantOperationException>()),
      );

      // 证据 1：扩容被拦后容量仍 = 12（绝不压低存量盆位）。
      final AppSettings after = await settings.getSettings();
      expect(after.gardenPotCapacity, 12,
          reason: 'C69：被拦后已有盆位容量必须原样保留 = 12');
      // 证据 2：已有植物未被删除（盆位可用）。
      expect((await plants.plants()).length, 12,
          reason: 'C69：门控 / 扩容拦截绝不影响已有植物');
    });

    test('对照：premium 档 + 11 盆 → expandPot 成功、容量 → 12（证明是配额拦截）',
        () async {
      final _FakeSettings settings = _FakeSettings(_settingsWithPotCapacity(11));
      final _FakeSunlightRepository ledger = _FakeSunlightRepository();
      final PlantGrowthService svc = await _buildGrowthService(
        settings: settings,
        tier: EntitlementTier.premium,
        plants: _FakePlantRepository(<Plant>[]),
        ledger: ledger,
      );

      await svc.expandPot(DateTime(2026, 1, 5, 10));

      expect((await settings.getSettings()).gardenPotCapacity, 12,
          reason: 'premium 档同场景应能扩容到 12');
      expect(ledger.appended, hasLength(1),
          reason: '扩容应产生一条扣费账本记录');
    });
  });

  // ── 5. 源码守卫 ────────────────────────────────────────────────────────────
  group('源码守卫：门控入口单点收口 + 孩子端无购买入口', () {
    test('家长端两个「新增」页均走 PremiumQuotaGate.onTap（不置空回调）', () {
      for (final String rel in <String>[
        'lib/presentation/parent/pages/parent_task_config_page.dart',
        'lib/presentation/parent/pages/parent_reward_page.dart',
      ]) {
        final String src = File('$root/$rel').readAsStringSync();
        expect(src.contains('PremiumQuotaGate.onTap'), isTrue,
            reason: '$rel 的新增入口必须走 PremiumQuotaGate.onTap（C62：不可点≠onTap:null）');
        expect(src.contains('PremiumQuotaGate.allows'), isTrue,
            reason: '$rel 应据 allows 决定按钮置灰（视觉）');
      }
    });

    test('孩子端花园页：一键 FAB 受档位门控，且不出现购买入口 / 价格', () {
      final String src = File(
        '$root/lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      expect(src.contains('_oneClickUnlocked'), isTrue,
          reason: '一键 FAB 出现条件应叠加档位门控（free 隐藏）');
      expect(src.contains('FeatureKey.oneClickCare'), isTrue);
      expect(src.contains('/parent/premium'), isFalse,
          reason: '孩子端不得出现购买页入口');
      expect(src.contains('buyLifetime'), isFalse,
          reason: '孩子端不得触发购买');
    });

    test('报告段门控：判定单点落在 focus_report_section，旧独立页已删除', () {
      // C87（2026-10-17）：旧独立报告页 `parent_report_page.dart` 曾是**有意保留的
      // 孤儿页**（不路由到）。玄参拍板删除后，这里改为**反向断言**：
      // 孤儿页不得复活 —— 一旦有人把老页捞回来，这条守卫立刻红。
      expect(
        File('$root/lib/presentation/parent/pages/parent_report_page.dart')
            .existsSync(),
        isFalse,
        reason: 'C87：孤儿页已删除，不得复活（报告内容唯一实现在 focus_report_section）',
      );

      // 报告段的门控必须真的接上了：判定走矩阵单点 `featureAllowedFor`。
      final String wired = File(
        '$root/lib/presentation/parent/widgets/focus_report_section.dart',
      ).readAsStringSync();
      expect(wired.contains('FeatureKey.deepReport'), isTrue,
          reason: 'C76 裁定 #1：月报 / 年报 / 近 4 周稳定性 / 热力图四处必须归 deepReport');
      expect(wired.contains('featureAllowedFor'), isTrue,
          reason: '判定必须走门控矩阵单点 featureAllowedFor，不得散落 isPremium 旁路');
    });
  });
}
