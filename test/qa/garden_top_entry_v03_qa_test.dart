/// QA 独立差分复验 · v0.3 花园右上角「图标 + 下方单行文字」簇（R3-P0-11）。
///
/// ## 为什么必须多档 uiScale + 真实 GardenPage
/// 玄参反馈 5 的根因是「`top` 用未缩放常量算，而图标实渲染高 = 常量 × uiScale」
/// ⇒ 平板必然压住下方元素。**只在一个屏幕尺寸下量一次是抓不到这个 bug 类别的**。
/// 本文件把**真实 GardenPage** 在 `uiScaleOf` 实际可达的三档下渲染并逐档量矩形：
/// 1.0（手机）/ 1.3（iPad 11″）/ 1.6（iPad 13″ 钳顶）。
///
/// ## 反假绿要点
///  - 不能用 `pumpAndSettle`（花园有无限呼吸动画）⇒ 全程有界 `pump`；
///  - 「点文字能点」不做源码守卫，而是**真 tap 文字节点**看路由/弹层反应；
///  - 「旧热点已删」用 `findsNothing(kWishTreeHotspotKey)`，不是 grep。
library garden_top_entry_v03_qa_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_top_entry_cluster.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';
import 'package:sunflower_time/shared/responsive.dart';

class _OfflineIap implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();
  @override
  Future<bool> isStoreAvailable() async => false;
  @override
  Future<List<IapProduct>> queryProducts(Set<String> ids) async =>
      <IapProduct>[];
  @override
  Future<void> startLifetimePurchase(String id) async {}
  @override
  Future<void> startRestore() async {}
}

class _QuietSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        soundOn: false,
        bgmOn: false,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
      iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
      settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return container;
}

/// 真实 GoRouter（这样 `context.push('/wish-tree')` 才能被观测到）。
Future<GoRouter> _mountGarden(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final GoRouter router = GoRouter(
    initialLocation: '/garden',
    routes: <RouteBase>[
      GoRoute(
        path: '/garden',
        builder: (BuildContext context, GoRouterState state) =>
            const GardenPage(),
      ),
      GoRoute(
        path: '/wish-tree',
        builder: (BuildContext context, GoRouterState state) => const Scaffold(
          body: Center(child: Text('WISH_TREE_ROUTE')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  // 花园有无限呼吸动画 ⇒ 有界 pump。
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioService.instance.resetForTest();

  /// `uiScaleOf` 实际可达的三档：手机 / iPad 11″ / iPad 13″（钳到 1.6）。
  final List<({String name, Size size, double expectScale})> scales =
      <({String name, Size size, double expectScale})>[
    (name: '1.0 (手机 390×844)', size: const Size(390, 844), expectScale: 1.0),
    (name: '1.3 (iPad 11″ 834×1194)', size: const Size(834, 1194), expectScale: 1.3),
    (name: '1.6 (iPad 13″ 1032×1376)', size: const Size(1032, 1376), expectScale: 1.6),
  ];

  for (final ({String name, Size size, double expectScale}) s in scales) {
    group('⑥ uiScale ${s.name}', () {
      testWidgets('天气块与许愿树块纵向不重叠（间距 ≥ 8dp），且各自图标-文字间距 = 4dp',
          (WidgetTester tester) async {
        tester.view.physicalSize = s.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final ProviderContainer c = await _boot();
        await _mountGarden(tester, c);

        // 真值自证：本档的 uiScale 确实是预期档位（防"设了尺寸但没生效"）。
        final BuildContext ctx = tester.element(find.byType(GardenPage));
        expect(uiScaleOf(ctx), closeTo(s.expectScale, 0.001),
            reason: '本档 uiScale 应为 ${s.expectScale}');

        final Finder badge = find.byKey(kGardenWeatherBadgeIconKey);
        final Finder weatherLabel = find.byKey(kGardenWeatherLabelKey);
        final Finder entryIcon = find.byKey(kWishTreeWeatherEntryKey);
        final Finder entryLabel = find.byKey(kWishTreeWeatherEntryLabelKey);

        expect(badge, findsOneWidget, reason: '天气徽标必须在');
        expect(weatherLabel, findsOneWidget, reason: '天气名文字必须在');
        expect(entryIcon, findsOneWidget, reason: '许愿树入口必须在');
        expect(entryLabel, findsOneWidget, reason: '许愿树入口文字必须在');

        final Rect badgeR = tester.getRect(badge);
        final Rect weatherLabelR = tester.getRect(weatherLabel);
        final Rect entryIconR = tester.getRect(entryIcon);
        final Rect entryLabelR = tester.getRect(entryLabel);

        // ① 图标与自己的文字间距 = kGardenTopLabelGap（4dp），与 uiScale 无关。
        expect(
          weatherLabelR.top - badgeR.bottom,
          closeTo(kGardenTopLabelGap, 1.0),
          reason: '天气徽标↔天气名 间距必须是 ${kGardenTopLabelGap}dp'
              '（实测 ${weatherLabelR.top - badgeR.bottom}）',
        );
        expect(
          entryLabelR.top - entryIconR.bottom,
          closeTo(kGardenTopLabelGap, 1.0),
          reason: '许愿树图标↔文字 间距必须是 ${kGardenTopLabelGap}dp'
              '（实测 ${entryLabelR.top - entryIconR.bottom}）',
        );

        // ①′ 玄参 v0.3 真机反馈 1：短标签「许愿树」居中且完整（无省略号）。
        final Text wishLabelText = tester.widget<Text>(entryLabel);
        expect(wishLabelText.data, '许愿树');
        expect(wishLabelText.textAlign, TextAlign.center);
        expect(wishLabelText.data!.contains('…'), isFalse);
        expect((entryLabelR.center.dx - entryIconR.center.dx).abs(),
            lessThanOrEqualTo(2.0),
            reason: '标签中心 x 与图标中心 x 偏差须 ≤2px');

        // ② 天气块（徽标顶 → 天气名底）与许愿树块（图标顶 → 文字底）不相交。
        final Rect weatherBlock =
            Rect.fromLTRB(weatherLabelR.left, badgeR.top,
                weatherLabelR.right, weatherLabelR.bottom);
        final Rect wishBlock = Rect.fromLTRB(
            entryLabelR.left, entryIconR.top, entryLabelR.right, entryLabelR.bottom);
        expect(
          entryIconR.top - weatherLabelR.bottom,
          greaterThanOrEqualTo(8.0),
          reason: '🔴 玄参反馈 5：uiScale=${s.expectScale} 时下方入口不得被压住，'
              '纵向间距须 ≥8dp（实测 ${entryIconR.top - weatherLabelR.bottom}）',
        );
        expect(weatherBlock.overlaps(wishBlock), isFalse,
            reason: '天气块 $weatherBlock 与许愿树块 $wishBlock 不得相交');

        // ③ 同 right 锚定（簇内右对齐，无额外水平内边距）。
        expect((entryIconR.right - badgeR.right).abs(), lessThan(2.0),
            reason: '入口图标右缘必须与徽标右缘对齐（同 right 锚点）');

        // ④ 触控热区 ≥ 44×44（图标本体 + 整簇）。
        expect(entryIconR.width, greaterThanOrEqualTo(44),
            reason: '许愿树入口宽 ${entryIconR.width} < 44');
        expect(entryIconR.height, greaterThanOrEqualTo(44),
            reason: '许愿树入口高 ${entryIconR.height} < 44');
        expect(badgeR.width, greaterThanOrEqualTo(44),
            reason: '天气徽标宽 ${badgeR.width} < 44');
        expect(badgeR.height, greaterThanOrEqualTo(44),
            reason: '天气徽标高 ${badgeR.height} < 44');
        for (final Element e
            in find.byType(WishTopEntryCluster).evaluate().toList()) {
          final Rect r = tester.getRect(find.byWidget(e.widget));
          expect(r.width, greaterThanOrEqualTo(44),
              reason: '整簇热区宽 ${r.width} < 44');
          expect(r.height, greaterThanOrEqualTo(44),
              reason: '整簇热区高 ${r.height} < 44');
        }

        // ⑤ 调试入口顺排在簇尾，不与许愿树文字重叠。
        final Finder debug = find.byType(BloomDebugEntry);
        if (debug.evaluate().isNotEmpty) {
          final Rect debugR = tester.getRect(debug);
          expect(debugR.top, greaterThanOrEqualTo(entryLabelR.bottom),
              reason: 'BloomDebugEntry 必须在许愿树文字之下（实测 '
                  '${debugR.top - entryLabelR.bottom}）');
        }

        expect(tester.takeException(), isNull,
            reason: 'uiScale=${s.expectScale} 下不得出现任何布局/渲染异常');
      });

      testWidgets('旧左下角热点 WishTreeHotspot 在真实树里 findsNothing',
          (WidgetTester tester) async {
        tester.view.physicalSize = s.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final ProviderContainer c = await _boot();
        await _mountGarden(tester, c);

        expect(find.byKey(kWishTreeHotspotKey), findsNothing,
            reason: 'R3-P0-01：左下角旧热点必须整体删除（花园页只留右上角唯一入口）');
        // 全树里也不得有第二个许愿树 push 入口的可点节点。
        expect(find.byKey(kWishTreeWeatherEntryKey), findsOneWidget,
            reason: '右上角入口必须存在且唯一');
      });
    });
  }

  group('⑥ 点文字等同点图标（真 tap，不是源码守卫）', () {
    testWidgets('点「许愿树」文字 ⇒ 路由真的到 /wish-tree', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final GoRouter router = await _mountGarden(tester, c);
      expect(router.state.uri.path, '/garden');

      await tester.tap(find.byKey(kWishTreeWeatherEntryLabelKey));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(router.state.uri.path, '/wish-tree',
          reason: '🔴 R3-P0-11⑤：点文字必须等同点图标（整簇一个热区）');
      expect(find.text('WISH_TREE_ROUTE'), findsOneWidget);
    });

    testWidgets('点天气文字 ⇒ 天气弹窗真的打开（同样整簇一个热区）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final GoRouter router = await _mountGarden(tester, c);

      await tester.tap(find.byKey(kGardenWeatherLabelKey));
      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      // 天气弹窗打开 ⇒ 仍留在 /garden，但出现了弹窗内容（Dialog 类型）。
      expect(router.state.uri.path, '/garden',
          reason: '天气是弹窗，不该换路由');
      expect(find.byType(Dialog), findsWidgets,
          reason: '点天气文字必须打开天气弹窗（证明文字在热区内）');
    });
  });
}
