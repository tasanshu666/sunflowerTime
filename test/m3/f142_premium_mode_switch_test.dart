/// F142 · 🐞「会员模式（仅调试）」开关的证据性测试 —— **双内存源修复**的回归守卫。
///
/// ## 修复前的真 Bug（玄参真机复现）
/// 家长设置页打开「会员模式」开关 → 回花园页点「扩容花盆」→ 仍被拦「需升级解锁」。
///
/// 根因：权益态在运行期有**两个独立内存源**
///  ① `entitlementProvider`（UI 层判定：按钮亮不亮 / 报告段取不取数据）；
///  ② `MatrixEntitlementService._current`（领域层判定：`can()` / `quotaOf()`）。
/// 旧 `debugSetPremiumUnlock` 只写了 ①，于是 UI 把扩容按钮点亮，一按就落到域层
/// `quotaOf(gardenPotCapacity)`，仍按 free 的 4 盆上限拒绝 → 「看着是会员，一按就被打回」。
///
/// ## 本文件锁四件事
///  ① **真实入口端到端**（🔴 本项目铁律：不许只测服务、不测入口）：
///     真实 `GardenPage` + **真实 `plantGrowthServiceProvider`/`entitlementServiceProvider`**
///     （**不注入任何 tier 参数**）→ 开开关 → 点真实的扩容格 → 确认卡 → 断言数据库容量 +1；
///  ② **反向用例**：开关关闭时同一入口**必须被拒**（真实页面上连扩容格都不渲染 = UI 门控生效，
///     且域层直接调用抛 `PlantOperationException`、容量不变）；
///  ③ **不落库**：`debugSetPremiumUnlock` 执行后票据仓储 `read()` 仍是 `free`
///     且 `write()` 从未被调用（证明只写内存态、重启即失效）；
///  ④ **能力接口**：`MatrixEntitlementService` 实现 `DebugEntitlementOverride`
///     （否则 `is` 探测会静默跳过 → 又退回 bug）。
///
/// ⚠️ 全程禁用 `pumpAndSettle`：花园页木牌呼吸 / 阳光气泡是无限动画，会永不返回。
library f142_premium_mode_switch_test;

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

/// 手机视口（iPhone 17）：本测试不关心平板分流，取仓库既有手机基准。
const Size _kPhone = Size(402, 874);

/// 初始容量 **6 盆**：> 免费档上限 4、< 买断档上限 12。
///
/// 这个值刻意选在「免费档已经超限」的区间 —— 正是玄参真机复现态：
/// 免费档下扩容格**根本不渲染**（`_capacity >= _potCapLimit`），
/// 只有会员态下才出现 → 一个值同时证明「UI 门控」与「域层上限」两条链路。
const int _kSeedPotCapacity = 6;

/// 阳光余额：远大于扩容价（低年段 160 / 高年段 400），避免「阳光不足」分支干扰。
const double _kSeedBalance = 999;

/// 票据仓储假件：只记内存 + **统计写入次数**（「不落库」断言的观测点）。
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

  /// 建库 + 造数（容量 6 盆 / 余额 999）+ 设视口，返回可直接挂载真实花园页的容器。
  ///
  /// 只覆盖「基础设施三件套」（prefs / drift 库 / 账号服务）——
  /// `plantGrowthServiceProvider` 与 `entitlementServiceProvider` **一律走真实装配**，
  /// 这才能证伪「调试开关只写了一半」。
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

    // 余额种子：走真实账本仓储（与 `_appendSpend` 同一条写入路径）。
    final DateTime now = DateTime.now();
    await SunlightLocalRepository(database, account: account).append(
      SunlightEntry(
        id: 'seed-f142-balance',
        ts: now,
        type: SunlightType.earn,
        gross: _kSeedBalance,
        net: _kSeedBalance,
        balanceAfter: _kSeedBalance,
        refType: 'seed',
        refId: 'f142',
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
    // 模拟「外壳停在花园 tab 且在前台」（花园页的可见性判据）。
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;
  }

  /// 有界 pump（花园页含无限动画，禁用 `pumpAndSettle`）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 挂载**真实** `GardenPage`（内嵌形态，与外壳 tab 内一致）。
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

  /// 抽干本帧期间的**全部**异常（`takeException` 一次只取一条）。
  List<Object> drainExceptions(WidgetTester tester) {
    final List<Object> all = <Object>[];
    for (int i = 0; i < 20; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      all.add(e);
    }
    return all;
  }

  /// 当前库里的花盆容量。
  Future<int> capacityInDb() async =>
      (await settingsRepository.getSettings()).gardenPotCapacity;

  group('① 真实入口端到端：开关打开 → 花园页真的能扩容', () {
    testWidgets('点真实扩容格 → 确认卡 → 容量 6 → 7（域层不再按 free 拦）',
        (WidgetTester tester) async {
      await boot(tester);
      // 【真实入口】开关在挂载前打开，等价于「家长设置页拨开后回到花园页」。
      debugSetPremiumUnlockIn(container, true);

      await pumpGarden(tester);

      // UI 层：会员态 ⇒ 扩容格渲染出来（免费档下这个格子不存在）。
      expect(find.byType(ExpandPotSlot), findsOneWidget,
          reason: '会员态下花园页必须出现「扩容」格（UI 门控已放开）');

      // 扩容器在第 3 行、草地滚动区底部 → 先滚到可见再点（否则 tap 会打到上层木牌）。
      await tester.ensureVisible(find.byType(ExpandPotSlot));
      await pumpFrames(tester, frames: 8);
      await tester.tap(find.byType(ExpandPotSlot));
      await pumpFrames(tester, frames: 12);

      // 真实确认卡（F135 统一卡壳）：标题逐字断言，防「点了个寂寞」。
      expect(find.text('要给花园腾一个花盆吗？'), findsOneWidget,
          reason: '点扩容格必须弹出确认卡，否则下面点确认是空操作');
      expect(await capacityInDb(), _kSeedPotCapacity,
          reason: '确认前不得扣费 / 改容量');

      await tester.tap(find.text('确定，扣除'));
      await pumpFrames(tester, frames: 24);

      // 🔴 核心断言：域层真的放行（修复前此处会抛「已达当前档位容量上限（4 盆）」）。
      expect(await capacityInDb(), _kSeedPotCapacity + 1,
          reason: '会员态下扩容必须成功：容量 $_kSeedPotCapacity → '
              '${_kSeedPotCapacity + 1}（修复前域层仍按 free 的 4 盆拒绝）');
      expect(drainExceptions(tester), isEmpty,
          reason: '扩容链路不得抛任何异常（含 PlantOperationException）');

      // 反向证据：免费档上限（4）此刻确实「被绕过」，说明走的是买断档 12。
      final EntitlementService svc = container.read(entitlementServiceProvider);
      expect(svc.quotaOf(FeatureKey.gardenPotCapacity),
          kPremiumGardenPotQuota,
          reason: '开关打开后域层配额必须 = 买断档 $kPremiumGardenPotQuota');
    });
  });

  group('② 反向用例：开关关闭 → 同一入口必须被拒', () {
    testWidgets('免费档（容量已 6 > 上限 4）→ 扩容格不渲染 = UI 门控生效',
        (WidgetTester tester) async {
      await boot(tester);
      // 刻意**不**开开关（默认 free）。
      await pumpGarden(tester);

      expect(find.byType(ExpandPotSlot), findsNothing,
          reason: '免费档容量已超 4 盆上限 ⇒ 花园页不得渲染扩容格（C69：只拦新增）');
      expect(drainExceptions(tester), isEmpty);
    });

    testWidgets('域层同场景直接调用 → 抛配额异常、容量不变', (WidgetTester tester) async {
      await boot(tester);
      // 真实 provider 装配下的域层服务（不注入任何 tier 参数）。
      final PlantGrowthService svc = container.read(plantGrowthServiceProvider);

      await expectLater(
        svc.expandPot(DateTime.now()),
        throwsA(isA<PlantOperationException>()),
        reason: '免费档已超上限 ⇒ 域层必须拒绝扩容',
      );
      expect(await capacityInDb(), _kSeedPotCapacity,
          reason: '被拒后容量必须原样保留（C69：绝不压低已有盆位）');
    });
  });

  group('③ 不落库：调试开关只写内存态', () {
    test('debugSetPremiumUnlockIn(true) 后票据仓储 read() 仍 free、write() 未被调',
        () async {
      final _RecordingEntitlementRepository repository =
          _RecordingEntitlementRepository();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          entitlementRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(c.dispose);

      debugSetPremiumUnlockIn(c, true);

      // 内存态：UI 源 + 领域源双双变买断。
      expect(c.read(debugPremiumUnlockProvider), isTrue);
      expect(c.read(entitlementProvider).isPremium, isTrue,
          reason: 'UI 源（entitlementProvider）必须同步');
      expect(
        c.read(entitlementServiceProvider).quotaOf(FeatureKey.gardenPotCapacity),
        kPremiumGardenPotQuota,
        reason: '领域源（服务私有内存态）必须同步 —— 这正是 F142 的修复点',
      );

      // 持久化：一个字都没写。
      expect(repository.writeCount, 0,
          reason: '调试开关**绝不**调 repository.write（不写票据）');
      expect(repository.clearCount, 0,
          reason: '关闭态走 Entitlement.free 覆盖内存，不需要 clear 票据');
      final Entitlement persisted = await repository.read();
      expect(persisted, Entitlement.free,
          reason: '仓储里读回的仍是 free ⇒ 重启 App 即失效');

      // 关回：两源一起回 free，仍不落库。
      debugSetPremiumUnlockIn(c, false);
      expect(c.read(debugPremiumUnlockProvider), isFalse);
      expect(c.read(entitlementProvider), Entitlement.free);
      expect(
        c.read(entitlementServiceProvider).quotaOf(FeatureKey.gardenPotCapacity),
        kFreeGardenPotQuota,
        reason: '关掉后领域源必须回到免费额度',
      );
      expect(repository.writeCount, 0, reason: '关开关同样不落库');
    });
  });

  group('④ 能力接口：MatrixEntitlementService 实现 DebugEntitlementOverride', () {
    test('isA<DebugEntitlementOverride>（断言失败 ⇒ debugSetPremiumUnlock 会静默跳过）',
        () {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          entitlementRepositoryProvider
              .overrideWithValue(_RecordingEntitlementRepository()),
        ],
      );
      addTearDown(c.dispose);

      final EntitlementService svc = c.read(entitlementServiceProvider);

      expect(svc, isA<MatrixEntitlementService>());
      expect(svc, isA<DebugEntitlementOverride>(),
          reason: '生产实现必须实现调试覆盖接口，否则 `is` 探测静默跳过 → '
              '退回「看着是会员、一按就被打回」的 bug');
      // 直接调用也生效（接口契约本身）。
      (svc as DebugEntitlementOverride).debugOverrideCurrent(Entitlement.lifetime());
      expect(svc.quotaOf(FeatureKey.gardenPotCapacity), kPremiumGardenPotQuota);
    });
  });
}
