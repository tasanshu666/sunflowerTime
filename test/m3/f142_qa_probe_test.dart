/// F142 · QA 独立探针（严过关 / Round 1）——不复用工程师用例场景，独立复现真机 Bug。
///
/// ## 与 `f142_premium_mode_switch_test.dart` 的差异（独立性声明）
/// 工程师用例 seed 容量 **6**（免费档已超限区间）；本探针 seed 容量 **4** = 免费档
/// 上限**恰好卡线**——这是玄参真机复现的原生态：免费档容量 4 = 上限 4，扩容格不渲染；
/// 开关打开后 UI 源（entitlementProvider）变 premium → 上限变 12 → 扩容格渲染出来，
/// 但若领域源（MatrixEntitlementService._current）没被写，`expandPot` 仍按 4 拒绝
/// →「按钮亮着、一按就被拒」。容量 4→5 是最小复现。
///
/// ## 本探针锁五件事
///  ① 反向基线：免费档容量 4 → 真实 UI 无扩容格 + 域层直接调用抛异常 + 容量不变；
///  ② 正向 E2E：开关打开 → 真实 GardenPage 点扩容格 → 确认卡 → DB 容量 4 → 5；
///  ③ 第二双源排查：`titlePerks`（UI: providers.dart currentPlantPerkProvider；
///     域: plant_growth_service.dart currentPerk() 的 can(FeatureKey.titlePerks)）
///     在开关打开后域层必须同步放行（修 F142 后不应再有「只生效一半」的双源功能）；
///  ④ 关回：两源一起回 free；
///  ⑤ 不落库：仓储 write/clear 从未被调用。
///
/// ⚠️ 全程禁用 `pumpAndSettle`（花园页含无限动画）。
library f142_qa_probe_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

/// 手机视口（iPhone 17 基准）。
const Size _kPhone = Size(402, 874);

/// 初始容量 **4 盆** = 免费档上限（`kFreeGardenPotQuota`），真机 Bug 原生态。
const int _kSeedPotCapacity = 4;

/// 阳光余额：远大于扩容价（低年段 160），避免「阳光不足」分支干扰。
const double _kSeedBalance = 999;

/// 票据仓储假件：统计写入（「不落库」断言观测点）。
class _RecordingEntitlementRepository implements EntitlementRepository {
  Entitlement stored = Entitlement.free;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<Entitlement> read() async => stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    writeCount++;
    stored = entitlement;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    stored = Entitlement.free;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late db.AppDatabase database;
  late SettingsLocalRepository settingsRepository;

  /// 建库 + 造数（容量 4 / 余额 999）+ 设视口 + 返回真实装配容器。
  ///
  /// 只覆盖基础设施三件套（prefs / drift 库 / 账号服务）；
  /// `plantGrowthServiceProvider` 与 `entitlementServiceProvider` 一律走真实装配。
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = _kPhone * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();

    settingsRepository = SettingsLocalRepository(database);
    await settingsRepository.saveSettings(
      const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: _kSeedPotCapacity,
      ),
    );

    // 余额种子：走真实账本仓储（与 expandPot 的 _appendSpend 同一条写入路径）。
    final DateTime now = DateTime.now();
    await SunlightLocalRepository(database, account: account).append(
      SunlightEntry(
        id: 'seed-f142qa-balance',
        ts: now,
        type: SunlightType.earn,
        gross: _kSeedBalance,
        net: _kSeedBalance,
        balanceAfter: _kSeedBalance,
        refType: 'seed',
        refId: 'f142qa',
        dayKey: dayKey(now),
      ),
    );

    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
      ],
    );
    addTearDown(container.dispose);
    // 模拟「外壳停在花园 tab 且在前台」（花园页可见性判据）。
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;
  }

  /// 有界 pump（花园页含无限动画，禁用 pumpAndSettle）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpGarden(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// 抽干本帧期间的异常。
  List<Object> drainExceptions(WidgetTester tester) {
    final List<Object> all = <Object>[];
    for (int i = 0; i < 20; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      all.add(e);
    }
    return all;
  }

  Future<int> capacityInDb() async =>
      (await settingsRepository.getSettings()).gardenPotCapacity;

  group('F142-QA 探针 A · 反向基线：免费档容量 4（恰好卡线）必须被拦', () {
    testWidgets('UI 门控：扩容格为**锁定态**（4 ≥ 免费上限 4，点了也不扩容）',
        (WidgetTester tester) async {
      await boot(tester);
      // 不开开关。
      await pumpGarden(tester);

      // F166（玄参 2026-10-29 改判 D4）：格子**渲染**（提示花园可再大），
      // 但锁定 —— 「门控仍然生效」从「没有格子」改由 `unlockable == false` 表达。
      expect(find.byType(ExpandPotSlot), findsOneWidget,
          reason: '免费档满 4 → 渲染锁定加盆格（F166）');
      expect(
        tester.widget<ExpandPotSlot>(find.byType(ExpandPotSlot)).unlockable,
        isFalse,
        reason: '免费档满 4 ⇒ 绝不可扩容（本条是 F142 的门控本体）',
      );
      expect(drainExceptions(tester), isEmpty);
    });

    testWidgets('域层闸门：expandPot 抛配额异常、DB 容量不变', (WidgetTester tester) async {
      await boot(tester);
      final PlantGrowthService svc = container.read(plantGrowthServiceProvider);

      await expectLater(
        svc.expandPot(DateTime.now()),
        throwsA(isA<PlantOperationException>()),
        reason: '容量 4 = 免费上限 ⇒ 域层必须拒绝（这是 F142 修复前开关打开后的真实现象）',
      );
      expect(await capacityInDb(), _kSeedPotCapacity);
    });
  });

  group('F142-QA 探针 B · 正向 E2E：开关打开 → 真实 UI 扩容 4 → 5', () {
    testWidgets('真实 GardenPage 点扩容格 → 确认卡 → DB 容量 +1',
        (WidgetTester tester) async {
      await boot(tester);
      // 【真实入口】家长设置页拨开关的等价操作（ProviderContainer 版唯一转换点）。
      debugSetPremiumUnlockIn(container, true);

      await pumpGarden(tester);

      // UI 源已放开：扩容格渲染出来（免费档下这个格子不存在）。
      expect(find.byType(ExpandPotSlot), findsOneWidget,
          reason: '会员态下必须出现扩容格（UI 门控放开）');

      await tester.ensureVisible(find.byType(ExpandPotSlot));
      await pumpFrames(tester, frames: 8);
      await tester.tap(find.byType(ExpandPotSlot));
      await pumpFrames(tester, frames: 12);

      // 真实确认卡：标题逐字断言，防「点了个寂寞」。
      expect(find.text('要给花园腾一个花盆吗？'), findsOneWidget,
          reason: '点扩容格必须弹出确认卡');
      expect(await capacityInDb(), _kSeedPotCapacity,
          reason: '确认前不得扣费 / 改容量');

      await tester.tap(find.text('确定，扣除'));
      await pumpFrames(tester, frames: 24);

      // 🔴 核心断言（F142 修复点）：域层按买断档 12 放行，容量 4 → 5。
      // 修复前此处抛「花园已达当前档位容量上限（4 盆），解锁可扩容」。
      expect(await capacityInDb(), _kSeedPotCapacity + 1,
          reason: '会员模式下从真实 UI 入口扩容必须成功：容量 4 → 5');
      expect(drainExceptions(tester), isEmpty,
          reason: '扩容链路不得抛任何异常（含 PlantOperationException）');
      expect(drainExceptions(tester), isEmpty);
    });
  });

  group('F142-QA 探针 C · 第二双源排查：titlePerks 的域层防线必须同步放行', () {
    test('开关打开后 can(titlePerks) 域层为 true；关回后 false；全程不落库', () async {
      final _RecordingEntitlementRepository repository =
          _RecordingEntitlementRepository();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          entitlementRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(c.dispose);

      final EntitlementService svc = c.read(entitlementServiceProvider);

      // 基线：free 档域层拒绝 titlePerks（plant_growth_service.currentPerk 的防线）。
      expect(svc.can(FeatureKey.titlePerks), isFalse,
          reason: 'free 档域层 must 拒绝称号属性（双源②的基线态）');

      debugSetPremiumUnlockIn(c, true);

      // 🔴 双源②：领域源被同步覆盖 → titlePerks 域层放行（否则称号属性
      // 「UI 显示专属、域层拿不到」= 第二个只生效一半的双源功能）。
      expect(svc.can(FeatureKey.titlePerks), isTrue,
          reason: '开关打开后域层 can(titlePerks) 必须同步放行（titlePerks 双源验证）');
      expect(c.read(entitlementProvider).isPremium, isTrue,
          reason: 'UI 源同步（titlePerks 的 UI 侧判定源）');
      expect(
        svc.quotaOf(FeatureKey.gardenPotCapacity),
        kPremiumGardenPotQuota,
        reason: '领域源 gardenPotCapacity 配额 = 买断档（双源①验证）',
      );
      expect(repository.writeCount, 0, reason: '不落库');

      // 关回：两源一起回 free。
      debugSetPremiumUnlockIn(c, false);
      expect(svc.can(FeatureKey.titlePerks), isFalse);
      expect(
        svc.quotaOf(FeatureKey.gardenPotCapacity),
        kFreeGardenPotQuota,
        reason: '关掉后两源都必须回免费档',
      );
      expect(repository.writeCount, 0);
      expect(repository.clearCount, 0);
    });
  });
}
