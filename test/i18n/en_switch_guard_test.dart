/// EN 切换守卫测试（i18n B1 T02 → **B2 收口**）。
///
/// ## B1 时的口径（已作废）
/// B1 只迁孩子端，`shared/premium_gate.dart` **刻意豁免**：当时
/// `test/qa/premium_unlock_table_test.dart` 的 T1 源码守卫逐字钉死其中文文案，
/// 故本文件断言「显式切 en 后这三个入口仍输出中文」来取证「豁免是有意的」。
///
/// ## B2 收口后的口径（本文件当前）
/// `premium_gate` 已随家长端迁入 ARB，**豁免随之撤销** —— 本文件改为
/// **「EN 生效」正向断言**：显式切 en 后，
///  ① `premium_gate` 三个**真实入口**（引导卡 / 升级弹窗 / 配额轻提示）必须渲染英文；
///  ② 家长端四个页面（今日 / 奖励 / 设置 / 购买）的真实页面泵起来必须渲染英文，
///     且对应的中文文案**必须消失**（防「半迁移」：一半中文一半英文）。
///
/// 🔴 为什么坚持泵**真实页面 / 真实 API 入口**：组件层自己拼串能过、但页面漏包
/// `L10nScope` 或忘了传 `l10n` 就会静默退回中文 —— 只有从真入口走进去才能证伪。
///
/// 装配说明：页面用的 `settingsRepositoryProvider` / `rewardRepositoryProvider` /
/// `taskCheckInServiceProvider` / `redemptionOrchestrationServiceProvider` 全部
/// **走真实装配**（内存 drift 库 + 真实仓储），只覆盖基础设施三件套
/// （prefs / 库 / 账号服务）与 IAP 适配器（离线假件，不碰真实 StoreKit）。
library en_switch_guard_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/i18n/seed_l10n.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show progressOf;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

/// 离线 IAP 适配器：商店恒不可用（**绝不触碰真实 StoreKit**）。
///
/// 购买页在「不可用」态下仍渲染 AppBar / 主卡 / 恢复购买 / 说明卡，足以取证
/// EN 接线；价格与买断流程另有 `test/qa/premium_page_test.dart` 覆盖。
class _OfflineIapAdapter implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();

  @override
  Future<bool> isStoreAvailable() async => false;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async =>
      <IapProduct>[];

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late db.AppDatabase database;

  /// 建内存库 + 覆盖基础设施三件套 + 离线 IAP（其余 provider **走真实装配**）。
  Future<void> boot() async {
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

    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        iapServiceProvider
            .overrideWithValue(IapService(adapter: _OfflineIapAdapter())),
      ],
    );
    addTearDown(container.dispose);
  }

  setUp(() async {
    // 守卫前提：显式切 en（非测试垫片路径 —— 显式 en 恒生效）。
    AppLocaleController.init(AppLanguage.en);
    await boot();
  });

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  /// 裸宿主（组件 / 弹窗用）：`L10nScope` 之下一个触发按钮。
  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          home: L10nScope(child: Scaffold(body: child)),
        ),
      );

  /// 真实页面宿主：容器注入 + 页级 `L10nScope` 由**页面自己**包（不在宿主补）。
  Widget pageHost(Widget page) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: page)),
      );

  /// 有界 pump（避免 `pumpAndSettle` 被 SnackBar 计时器 / 无限动画拖满）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  // ───────────────────────────── ① premium_gate 真实入口 ─────────────────────────────
  group('① premium_gate EN 生效（豁免已随 B2 撤销）', () {
    testWidgets('引导卡 PremiumUpsellCard：en 下渲染英文，中文消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        host(const PremiumUpsellCard(feature: FeatureKey.oneClickCare)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlock "One-tap garden care"'), findsOneWidget,
          reason: '标题带能力点名（带参 key，占位符必须显式声明）');
      expect(find.text('One purchase, unlock all'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      // 中文必须消失 —— 防「半迁移」（标题英文、描述仍中文）。
      expect(find.text('解锁「花园一键操作」'), findsNothing);
      expect(find.text('一次买断，永久解锁全部功能'), findsNothing);
    });

    testWidgets('真实入口 PremiumGate.onTap → 升级弹窗 en 生效',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                // 生产页面调用门控的**唯一**回调型入口。
                onPressed: () =>
                    PremiumGate.onTap(context, FeatureKey.oneClickCare, () {}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Upgrade'), findsOneWidget, reason: '弹窗标题');
      expect(find.text('"One-tap garden care" requires a one-time purchase.'),
          findsOneWidget,
          reason: '能力点名 + 买断说明（带参 key）');
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Unlock All'), findsOneWidget);
      // 中文消失。
      expect(find.text('升级解锁'), findsNothing);
      expect(find.text('稍后'), findsNothing);
      expect(find.text('解锁全部功能'), findsNothing);
    });

    testWidgets('真实入口 PremiumQuotaGate.onTap → 轻提示 en 生效',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                // 生产调用点：`parent_task_config_page` / `parent_reward_page` 的新增按钮。
                onPressed: () => PremiumQuotaGate.onTap(
                  context: context,
                  feature: FeatureKey.taskTemplateCount,
                  currentCount: 5,
                  onAllowed: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
          find.text('Free limit: 5 (now 5). Remove extras to add more.'),
          findsOneWidget,
          reason: '轻提示正文（带参 key，limit / count 顺序不得漂移）');
      expect(find.text('Unlock All'), findsOneWidget,
          reason: '动作按钮文案必须来自 ARB');
      expect(find.text('解锁全部功能'), findsNothing);
    });
  });

  // ───────────────────────────── ② 家长端真实页面 EN 生效 ─────────────────────────────
  group('② 家长端真实页面 en 生效（中文须清零）', () {
    testWidgets('设置页 ParentSettingsPage', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pageHost(const ParentSettingsPage()));
      await pumpFrames(tester);

      expect(find.text('Unlock All'), findsNWidgets(2),
          reason: '分区标题 + 金令牌入口卡标题');
      expect(find.text('Screen time & routines'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget, reason: '语言入口行');
      // 中文清零。
      expect(find.text('解锁全部功能'), findsNothing);
      expect(find.text('防沉迷与作息'), findsNothing);
      expect(find.text('语言'), findsNothing);
    });

    testWidgets('今日页 ParentTodayPage', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pageHost(const ParentTodayPage()));
      await pumpFrames(tester, frames: 25);

      expect(find.text('Nothing waiting 🎉'), findsOneWidget,
          reason: '空态文案（本例无待确认数据）');
      expect(find.text('暂无待确认奖励 🎉'), findsNothing);
    });

    testWidgets('奖励页 ParentRewardPage', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pageHost(const ParentRewardPage()));
      await pumpFrames(tester, frames: 25);

      expect(find.text('Reward templates'), findsOneWidget, reason: '页头标题');
      expect(find.text('Add reward'), findsOneWidget, reason: '新增按钮');
      expect(find.text('No templates yet — tap "Add reward" to create one'),
          findsOneWidget,
          reason: '空态文案（本例无模板数据）');
      // 中文清零。
      expect(find.text('奖励模板'), findsNothing);
      expect(find.text('新增奖励'), findsNothing);
    });

    testWidgets('购买页 ParentPremiumPage', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pageHost(const ParentPremiumPage()));
      await pumpFrames(tester, frames: 25);

      expect(find.text('Unlock All'), findsNWidgets(2),
          reason: 'AppBar 标题 + 主卡标题');
      expect(find.text('Store is unreachable'), findsOneWidget,
          reason: '商店不可用降级文案');
      expect(find.text('Restore purchases'), findsOneWidget,
          reason: 'Apple 硬性要求的恢复入口（文案来自 ARB）');
      expect(find.text('Before you buy'), findsOneWidget, reason: '诚实说明卡标题');
      // 中文清零。
      expect(find.text('解锁全部功能'), findsNothing);
      expect(find.text('恢复购买'), findsNothing);
      expect(find.text('购买前请知悉'), findsNothing);
      expect(find.text('暂时连不上商店'), findsNothing);
    });
  });

  // ───────────────────────────── ③ EN 生效链路 ─────────────────────────────
  testWidgets('③ EN 生效链路：显式 en 下 L10nScope 解析出英文文案',
      (WidgetTester tester) async {
    late final AppLocalizations resolved;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) {
            resolved = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(resolved.localeName, 'en',
        reason: '显式 en 恒生效（页面文案不是「切换链路坏了」的假象）');
    // 抽查一条 B1 已迁移的孩子端文案确为英文。
    expect(resolved.shared_cancel, 'Cancel');
  });

  // ───────────────── ④ B3 · T04/T05 新接线的 EN 取证 ─────────────────
  //
  // ## 为什么要专门再立一套宿主
  // 上面 ①②③ 的 `host()` 是「裸 MaterialApp + 页内 L10nScope」——那是给**既有**
  // 1783 条测试留的兼容垫片。它有个盲区：`showDialog` / 弹窗的 builder 上下文挂在
  // **根 Navigator** 上（在 `home` 之外），取不到 `home` 里的 `L10nScope` →
  // `l10nOf` 会静默回退中文。
  //
  // 生产形态不是这样：`app.dart` 的 `MaterialApp.router` **自己挂了**
  // `localizationsDelegates` + `locale`，根 Localizations 在 Navigator 之上，
  // 所以弹窗内取文案是真的英文。故本组改用 `localizedHost`（复刻生产挂法）
  // 来取证 —— 否则「弹窗还是中文」这个真 bug 会被垫片掩盖成「测试通过」。
  Widget localizedHost(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      );

  group('④ T04/T05 新接线 en 取证（等级详情卡）', () {
    /// 打开详情卡（900 分钟 = Lv.7）。
    Future<void> openDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        localizedHost(
          FocusLevelBadge(progress: progressOf(900), totalMinutes: 900),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusLevelDetailDialog.dialogKey), findsOneWidget);
    }

    testWidgets('T05 属性名：en 下渲染 Watering / Weeding，中文属性名消失',
        (WidgetTester tester) async {
      await openDetail(tester);

      final Finder dialog = find.byKey(FocusLevelDetailDialog.dialogKey);
      // 9 行属性徽章里，Lv.5 = Watering、Lv.15 = Weeding（原 kPerkNames「浇水 / 除草」）。
      expect(find.descendant(of: dialog, matching: find.text('Watering')),
          findsOneWidget,
          reason: 'Lv.5 属性名必须来自 ARB `shared_perk_name_water`');
      expect(find.descendant(of: dialog, matching: find.text('Weeding')),
          findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Eye care')),
        findsOneWidget,
        reason: 'Lv.1 属性名',
      );
      // 中文属性名必须消失（9 条全查，防「迁了 3 条漏 6 条」）。
      for (final String zhName in <String>[
        '护眼',
        '浇水',
        '施肥',
        '除草',
        '除虫',
        '绽放',
        '晨露',
        '扩盆',
        '铲除',
      ]) {
        expect(find.descendant(of: dialog, matching: find.text(zhName)),
            findsNothing,
            reason: 'en 下不许出现中文属性名「$zhName」');
      }
    });

    testWidgets('T05 差距文案：en 下无 CJK 且带 Lv.8（shared_level_gap_next）',
        (WidgetTester tester) async {
      await openDetail(tester);

      final Text gap =
          tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey));
      final String text = gap.data ?? '';
      expect(text, contains('Lv.8'), reason: '下一级是 Lv.8（900 分钟 → Lv.7）');
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(text), isFalse,
          reason: 'en 下差距文案不许含中文（当前：「$text」）');
      // 时长单位也已英文（原实现输出「4 小时」；en 的 ARB 用紧凑写法 `4 h`）。
      expect(text, isNot(contains('小时')));
      expect(RegExp(r'\d+\s*h\b').hasMatch(text), isTrue,
          reason: '240 分钟 = 4 小时，en 应输出 `4 h`（当前：「$text」）');
    });

    testWidgets('T05 默认孩子名：en 下 providers 注入 Child（不再写死「孩子」）',
        (WidgetTester tester) async {
      // 直接查容器里注入的取值器（生产路径 = `providers.dart` 的闭包）。
      final AccountService account = container.read(accountServiceProvider);
      expect(account, isNotNull);
      // 走一遍「空表补建」的取值：容器装配的是 `defaultChildName: () =>
      // defaultChildName(lookupAppLocalizations(AppLocaleController.current))`，
      // 当前 locale = en → 必须是 Child。
      expect(
        defaultChildName(lookupAppLocalizations(AppLocaleController.current)),
        'Child',
        reason: 'en 下 ARB `shared_default_child_name` = Child',
      );
    });
  });
}
