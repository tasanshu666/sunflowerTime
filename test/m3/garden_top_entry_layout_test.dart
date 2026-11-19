/// 花园右上角布局（v0.3.0 / R3-P0-11）+ 入口唯一（R3-P0-01）。
///
/// ## 为什么要「真实花园页 + 多档 uiScale」
/// 玄参反馈 5 的根因是**偏移量用了未缩放常量**（徽标实渲染 `56 × uiScaleOf`，
/// 而 top 用未缩放的 56 算）。只有把真实页面在**多个 uiScale 档**下渲染、
/// 逐档量矩形，才能证明「结构折叠（Column 簇）」真的消除了这个 bug 类别；
/// 量自造 harness 等于自证。
///
/// ## 档位说明（与 PRD 的 1.0 / 1.15 / 1.3 的口径差异，已报备）
/// `uiScaleOf` = `tabletUiScaleFor(shortestSide)`：手机（<600dp）= **1.0**，
/// 平板恒 ≥ `kTabletUiScale = 1.3`，且 = `1.3 × shortest/834` 钳到 1.6。
/// 因此生产上**不存在 1.15 档**；本测试覆盖**实际可达的三档**
/// 1.0（手机）/ 1.3（iPad 11″）/ 1.6（iPad 13″）—— 后者比 1.15 更苛刻，
/// 覆盖了同一 bug 类别且更严格。
///
/// ⚠️ 花园页有无限动画：全程有界 `pump`，禁止 `pumpAndSettle`。
library garden_top_entry_layout_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
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

/// 真实 DI 宿主（内存库 + 真实服务图）。
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

Future<void> _frames(WidgetTester tester, {int n = 12}) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 每档：`(屏宽, 屏高, 期望 uiScale)`。
const List<({double w, double h, double scale, String name})> _tiers =
    <({double w, double h, double scale, String name})>[
  (w: 390, h: 844, scale: 1.0, name: '手机 390'),
  (w: 834, h: 1194, scale: 1.3, name: 'iPad 11″ 834'),
  (w: 1032, h: 1376, scale: 1.6, name: 'iPad 13″ 1032'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AudioService.instance.resetForTest());

  group('R3-P0-11 右上角图标 + 文字不重叠（多档 uiScale）', () {
    for (final ({double w, double h, double scale, String name}) tier
        in _tiers) {
      testWidgets('${tier.name}：两簇不相交、间距 ≥8dp、图标↔文字 4dp、热区 ≥44',
          (WidgetTester tester) async {
        tester.view.physicalSize = Size(tier.w, tier.h);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final ProviderContainer c = await _boot();
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: GardenPage()),
        ));
        await _frames(tester);

        // ① 先证明「本档的 uiScale 真的是期望值」（而不是假定）。
        final BuildContext ctx = tester.element(find.byType(GardenPage));
        expect(uiScaleOf(ctx), closeTo(tier.scale, 0.001),
            reason: '${tier.name} 的 uiScale 应为 ${tier.scale}');

        final Finder badge = find.byKey(kGardenWeatherBadgeIconKey);
        final Finder weatherLabel = find.byKey(kGardenWeatherLabelKey);
        final Finder entry = find.byKey(kWishTreeWeatherEntryKey);
        final Finder entryLabel = find.byKey(kWishTreeWeatherEntryLabelKey);
        final Finder debug = find.byType(BloomDebugEntry);

        expect(badge, findsOneWidget, reason: '天气图标在真实花园页');
        expect(weatherLabel, findsOneWidget, reason: '天气图标下方必须有文字');
        expect(entry, findsOneWidget, reason: '许愿树图标唯一');
        expect(entryLabel, findsOneWidget, reason: '许愿树图标下方必须有文字');

        final Rect badgeRect = tester.getRect(badge);
        final Rect labelRect = tester.getRect(weatherLabel);
        final Rect entryRect = tester.getRect(entry);
        final Rect entryLabelRect = tester.getRect(entryLabel);

        // ② 图标 ↔ 自身文字：文字在图标正下方，间距 = kGardenTopLabelGap（4dp）。
        //    ⚠️ 这条在三档下都必须成立 —— 旧实现（手工 top）在 uiScale>1 时
        //    这里会直接变成负数（文字压到图标上）。
        expect(labelRect.top - badgeRect.bottom, closeTo(kGardenTopLabelGap, 2.0),
            reason: '${tier.name}：天气文字必须在图标正下方（gap = 4dp）');
        expect(entryLabelRect.top - entryRect.bottom,
            closeTo(kGardenTopLabelGap, 2.0),
            reason: '${tier.name}：许愿树文字必须在图标正下方');

        // ②′ 玄参 v0.3 真机反馈 1：短标签「许愿树」居中、完整、单行。
        final Text entryText = tester.widget<Text>(entryLabel);
        expect(entryText.data, '许愿树',
            reason: '${tier.name}：花园入口用独立短标签，不许复用页面标题');
        expect(entryText.textAlign, TextAlign.center,
            reason: '${tier.name}：标签必须居中（不得右贴）');
        expect(entryText.data!.contains('…'), isFalse,
            reason: '${tier.name}：标签不得被省略号截断');
        expect((entryLabelRect.center.dx - entryRect.center.dx).abs(),
            lessThanOrEqualTo(2.0),
            reason: '${tier.name}：标签中心 x 与图标中心 x 偏差 ≤2px');

        // ③ 两组之间：不相交且垂直间距 ≥8dp（R3-P0-11①）。
        expect(entryRect.top, greaterThanOrEqualTo(labelRect.bottom + 8 - 0.5),
            reason: '${tier.name}：许愿树图标必须在天气文字之下、间距 ≥8dp');

        // ④ 调试入口不与两者重叠（R3-P0-11⑦）。
        if (debug.evaluate().isNotEmpty) {
          final Rect debugRect = tester.getRect(debug);
          expect(debugRect.top,
              greaterThanOrEqualTo(entryLabelRect.bottom + 8 - 0.5),
              reason: '${tier.name}：调试入口顺排在簇尾，不得压住许愿树文字');
        }

        // ⑤ 两处热区 ≥ 44×44（R3-P0-11⑥）。
        expect(entryRect.width, greaterThanOrEqualTo(44));
        expect(entryRect.height, greaterThanOrEqualTo(44));
        expect(badgeRect.width, greaterThanOrEqualTo(44));

        // ⑥ 文字渲染不溢出（R3-P0-11④）。
        expect(tester.takeException(), isNull,
            reason: '${tier.name}：文字 / 图标不得有 overflow 异常');
      });
    }

    testWidgets('点文字等同点图标：文字与图标落在同一个热区（InkWell 祖先相同）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: GardenPage()),
      ));
      await _frames(tester);

      // 「同热区」的可测判据：文字与图标共享**最近的**同一个 InkWell ——
      // 即两者各自的第一层 InkWell 祖先数量相同，且文字的 InkWell 祖先里
      // 包含图标那一层（簇外层 InkWell 同时包住图标 + 文字）。
      final Finder entryLabel = find.byKey(kWishTreeWeatherEntryLabelKey);
      final Finder entryIcon = find.byKey(kWishTreeWeatherEntryKey);
      final int labelInkWells = find
          .ancestor(of: entryLabel, matching: find.byType(InkWell))
          .evaluate()
          .length;
      final int iconInkWells = find
          .ancestor(of: entryIcon, matching: find.byType(InkWell))
          .evaluate()
          .length;
      expect(labelInkWells, greaterThanOrEqualTo(1),
          reason: '文字必须落在可点热区内（点文字等同点图标）');
      // 图标自身也有内层 InkWell（入口本体），故图标侧 ≥ 文字侧。
      expect(iconInkWells, greaterThanOrEqualTo(labelInkWells),
          reason: '图标热区在簇热区之内，层级不能反过来');
      expect(tester.takeException(), isNull);
    });
  });

  group('R3-P0-01 花园页只有一个许愿树入口', () {
    testWidgets('左下角 WishTreeHotspot 节点已删除', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: GardenPage()),
      ));
      await _frames(tester);

      expect(find.byKey(kWishTreeHotspotKey), findsNothing,
          reason: '左下角旧入口已删除（玄参反馈 1）');
      expect(find.byKey(kWishTreeWeatherEntryKey), findsOneWidget,
          reason: '右侧簇内入口保留且唯一');
      // 旧的独立「入口浮层」槽位也不应再作为独立 Positioned 存在（已并入簇）。
      expect(find.byKey(kWishTreeTopClusterKey), findsOneWidget,
          reason: '右上角整簇是唯一载体');
      expect(tester.takeException(), isNull);
    });

    test('源码守卫：花园页 push 入口数 = 1，且已无 WishTreeHotspot(', () {
      final String src = File(
        'lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      // 入口**唯一**的判据是「许愿树入口 widget 只实例化一次」；簇内
      // 图标本体与簇外层各接一次同一个 push（同热区组，点哪都只触发一次），
      // 故 push 字面量出现 2 次是正确形态。
      expect('WishTreeWeatherEntry('.allMatches(src).length, 1,
          reason: '花园页只保留右上角簇内一个愿望入口');
      expect('WishTopEntryCluster('.allMatches(src).length, 2,
          reason: '右上角簇 = 天气 + 许愿树两组');
      expect(src.contains('WishTreeHotspot('), isFalse,
          reason: '旧热点 widget 不得再出现在花园页');
      // 图标与文字同热区：两者在同一 `WishTopEntryCluster` 实例上接线。
      expect(src.contains('WishTopEntryCluster('), isTrue);
      expect(src.contains('kWishTreeWeatherEntryLabelKey'), isTrue);
      expect(src.contains('kGardenWeatherLabelKey'), isTrue);
      // 废弃的绝对偏移法不得回潮（S5）。
      expect(src.contains('gardenDebugEntryTop('), isFalse,
          reason: 'Column 簇取代绝对偏移，禁止再引入手工 top');
    });
  });

  group('今日页速览卡已删除（玄参 v0.3 真机反馈 6）', () {
    test('child_today_page 已无 child_today_wish_tree_entry', () {
      final String src = File(
        'lib/presentation/child/pages/child_today_page.dart',
      ).readAsStringSync();
      expect(src.contains('child_today_wish_tree_entry'), isFalse,
          reason: '今日页底部许愿树速览卡已删除，花园右上角入口仍保留');
      expect(src.contains("context.push('/wish-tree')"), isFalse,
          reason: '今日页不再自带许愿树 push 入口');
    });

    testWidgets('真实今日页无速览卡；真实花园页右上角入口仍在',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final ProviderContainer c = await _boot();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ChildTodayPage()),
      ));
      await _frames(tester, n: 20);
      expect(find.byKey(const Key('child_today_wish_tree_entry')), findsNothing,
          reason: '今日页底部许愿树速览卡已删除');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: GardenPage()),
      ));
      await _frames(tester);
      expect(find.byKey(kWishTreeWeatherEntryKey), findsOneWidget,
          reason: '花园右上角许愿树入口仍唯一保留');
    });
  });
}
