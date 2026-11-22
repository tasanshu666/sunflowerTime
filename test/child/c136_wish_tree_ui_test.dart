/// C136 需求 2 / 3 / 4（玄参 2026-11-25 真机反馈）的孩子端 UI 回归。
///
/// ## 玄参原话
/// 2.「许愿树里面愿望池和收藏箱，点击后弹出来的卡片，卡片宽度没有对 ipad 进行适配，
///    现在显示的有点窄啊」；
/// 3.「愿望池里面的愿望，每个卡片右边有个小星星是干啥的？想要小飞机那个实现的愿望
///    还没有小星星，这是什么机制？」→ 拍板口径：保留 🌟「我自己做到的」，
///    并给「家长帮忙达成」的补一个标识（双轨）；
/// 4.「点击树上的愿望后，展开的卡片 点击放进收藏箱，这个卡片不会自动消失，还能再
///    继续点击换个愿望或者实现了的按钮，这不合理，在收藏箱里的愿望，就只能取回」。
///
/// ## 本文件守什么
///  · 需求 2：`wishListDialogWidth` 纯函数真值表 + **真实弹窗**在 iPad 834 上必须是
///    600 且为 **tight** 约束（`SizedBox(width:)`，只给 maxWidth 会收缩成内容固有宽）；
///  · 需求 3：池 tile 双轨标识（child → 🌟 / progress、parentAction、null → 🤝），
///    两个标识都带 Tooltip + Semantics 文案；
///  · 需求 4：详情卡点「放进收藏箱」后**自动关闭**，愿望真的进了收藏箱；
///    收藏箱里只能「取回」（树上入口不复存在）。
library c136_wish_tree_ui_test;

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
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart'
    show kGardenHelpDialogMaxWidth;
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';

/// 双轨标识的语义文案（与 ARB zh 值一致，独立写死便于取证）。
const String _kSelfBadgeCopy = '我自己做到的';
const String _kParentBadgeCopy = '爸爸妈妈帮我做到的';

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

/// 静默设置（不改库、不读盘）：只为避免真设置仓储在测试里产生额外异步。
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

/// 真 DI 装配（照 `wish_detail_dialog_geometry_test` 的同款，只覆盖基础设施 + IAP）。
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

/// 固定视口后挂真 `WishTreePage`，等异步数据就绪（有界帧，禁 pumpAndSettle）。
Future<void> _pumpTree(
  WidgetTester tester, {
  required ProviderContainer container,
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: WishTreePage()),
  ));
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 造一条已达成（在愿望池）的愿望。
Wish _poolWish(String id, String? source) => Wish(
      id: id,
      childId: kChildIdDefault,
      text: '想要一架小飞机',
      status: WishStatus.fulfilled,
      createdAt: DateTime.now().subtract(const Duration(days: 6)),
      fulfilledAt: DateTime.now().subtract(const Duration(days: 1)),
      fulfillSource: source,
    );

/// 把池 tile 单独挂起来（纯展示 widget，不读 provider）。
Future<void> _pumpTile(WidgetTester tester, Wish wish) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 342,
          child: WishPoolTile(wish: wish, t: AppLocalizationsZh()),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// 徽标的某个祖先 [Semantics] 是否带 [label]。
///
/// 不取「最近的那个」：`Tooltip` 内部也会塞一层 [Semantics]（`excludeFromSemantics`
/// 时只是没有 tooltip 字段，label 仍为 null）。故遍历全部祖先按 label 命中。
bool _hasSemanticsLabel(WidgetTester tester, Finder of, String label) {
  final Iterable<Semantics> all =
      tester.widgetList<Semantics>(find.ancestor(of: of, matching: find.byType(Semantics)));
  return all.any((Semantics s) => s.properties.label == label);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AudioService.instance.resetForTest());

  // ── 需求 2 ────────────────────────────────────────────────────────────────
  group('需求 2 · wishListDialogWidth 纯函数（池 / 箱弹窗宽度）', () {
    test('手机视口：逐点等于旧实现的「视口 − insetPadding(48)」', () {
      // 旧实现 390 − 48 = 342（< 420，maxWidth 根本不生效）⇒ 手机观感零变化。
      expect(wishListDialogWidth(390), 342.0);
      expect(wishListDialogWidth(428), 380.0);
      expect(wishListDialogWidth(390), lessThan(420.0));
    });

    test('平板视口：封顶 600（复用花园同一个上限常量，不再是 420）', () {
      expect(wishListDialogWidth(834), 600.0, reason: 'iPad 11″');
      expect(wishListDialogWidth(1032), 600.0, reason: 'iPad 13″');
      expect(wishListDialogWidth(648), 600.0, reason: '临界点 648 - 48 = 600');
      expect(wishListDialogWidth(647), 599.0);
      expect(wishListDialogWidth(834), greaterThan(420.0),
          reason: '必须明显宽于旧的硬编码 420');
    });

    test('上限复用 kGardenHelpDialogMaxWidth（禁止孪生 600）', () {
      expect(kGardenHelpDialogMaxWidth, 600.0);
      expect(wishListDialogWidth(1032), kGardenHelpDialogMaxWidth);
    });

    test('极端窄视口钳到 0，绝不返回负宽', () {
      expect(wishListDialogWidth(48), 0.0);
      expect(wishListDialogWidth(0), 0.0);
      expect(wishListDialogWidth(-100), 0.0);
    });
  });

  group('需求 2 · 真实弹窗宽度（生产 _openListDialog，iPad 真的变宽）', () {
    testWidgets('iPad 834：愿望池弹窗宽 600，且宽度是 tight 约束',
        (WidgetTester tester) async {
      final ProviderContainer c = await _boot();
      await WishLocalRepository(c.read(appDatabaseProvider))
          .save(_poolWish('w_pool_ipad', kWishFulfillSourceProgress));
      await _pumpTree(tester, container: c, viewport: const Size(834, 1194));

      await tester.tap(find.byKey(const Key('wish_scene_pool_button')));
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final Finder dialog = find.byKey(const Key('wish_pool_dialog'));
      expect(dialog, findsOneWidget, reason: '点「愿望池」必须弹出居中卡片');
      expect(tester.getSize(dialog).width, 600.0,
          reason: 'iPad 上必须按屏宽定宽，而不是内容固有宽或硬编码 420');

      // 🔴 只量宽不足以区分 tight / 松约束：本弹窗内容是
      // SingleChildScrollView + Column(min)，松 maxWidth 时也可能被内容撑开。
      // 直接读生产 SizedBox 那一层的宽度属性（nearest ancestor）。
      final SizedBox box = tester.widget<SizedBox>(
        find
            .ancestor(of: dialog, matching: find.byType(SizedBox))
            .first,
      );
      expect(box.width, 600.0,
          reason: '必须是 SizedBox(width:) 的 tight 约束（ConstrainedBox(maxWidth) 是假修）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone 390：收藏箱弹窗宽 342，与旧实现逐点一致',
        (WidgetTester tester) async {
      final ProviderContainer c = await _boot();
      await _pumpTree(tester, container: c, viewport: const Size(390, 844));

      await tester.tap(find.byKey(const Key('wish_scene_box_button')));
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final Finder dialog = find.byKey(const Key('wish_box_dialog'));
      expect(dialog, findsOneWidget);
      expect(tester.getSize(dialog).width, 342.0,
          reason: '390 − 48 = 342，手机端不得有任何宽度变化');
      expect(tester.takeException(), isNull);
    });

    test('源码守卫：池 / 箱弹窗用 tight 宽度，详情卡仍是 420', () {
      final String src =
          File('lib/presentation/child/pages/wish_tree_page.dart')
              .readAsStringSync();
      expect(src.contains('width: wishListDialogWidth(screen.width),'), isTrue,
          reason: '必须把纯函数结果交给 SizedBox(width:) 做 tight 约束');
      expect(src.contains('maxWidth: wishListDialogWidth('), isFalse,
          reason: 'maxWidth 是松约束，正是玄参这次反馈「还是窄」的根因');
      // 写死的 420 只剩树上详情卡一处（玄参没提，保持不动）。
      final int literal420 = src
          .split('\n')
          .where((String line) => line.trim() == 'maxWidth: 420,')
          .length;
      expect(literal420, 1,
          reason: '池 / 箱弹窗不得再出现 maxWidth: 420（只留树上详情卡那一处）');
    });
  });

  // ── 需求 3 ────────────────────────────────────────────────────────────────
  group('需求 3 · 愿望池 tile 双轨来源标识', () {
    test('判据互补：child 是自己做到，其余来源都算家长助力', () {
      expect(WishPoolTile.isSelfFulfilled(_poolWish('a', kWishFulfillSourceChild)),
          isTrue);
      expect(WishPoolTile.isParentHelped(_poolWish('a', kWishFulfillSourceChild)),
          isFalse);
      for (final String? source in <String?>[
        kWishFulfillSourceProgress,
        kWishFulfillSourceParentAction,
        null,
      ]) {
        final Wish w = _poolWish('b', source);
        expect(WishPoolTile.isSelfFulfilled(w), isFalse, reason: 'source=$source');
        expect(WishPoolTile.isParentHelped(w), isTrue, reason: 'source=$source');
      }
    });

    testWidgets('child 来源：🌟 + 原 key + 语义「我自己做到的」',
        (WidgetTester tester) async {
      await _pumpTile(tester, _poolWish('w_self', kWishFulfillSourceChild));

      final Finder badge = find.byKey(const Key('wish_pool_self_badge'));
      expect(badge, findsOneWidget);
      expect(tester.widget<Text>(badge).data, '🌟');
      expect(find.byKey(const Key('wish_pool_parent_badge')), findsNothing);

      final Tooltip tip = tester.widget<Tooltip>(
        find.ancestor(of: badge, matching: find.byType(Tooltip)).first,
      );
      expect(tip.message, _kSelfBadgeCopy);
      expect(_hasSemanticsLabel(tester, badge, _kSelfBadgeCopy), isTrue,
          reason: '只挂 emoji 孩子/读屏都读不懂，必须有语义文案');
    });

    for (final String source in <String>[
      kWishFulfillSourceProgress,
      kWishFulfillSourceParentAction,
    ]) {
      testWidgets('$source 来源：🤝 + 新 key + 语义「爸爸妈妈帮我做到的」',
          (WidgetTester tester) async {
        await _pumpTile(tester, _poolWish('w_par_$source', source));

        final Finder badge = find.byKey(const Key('wish_pool_parent_badge'));
        expect(badge, findsOneWidget,
            reason: '玄参：「想要小飞机那个实现的愿望还没有小星星」—— 必须也有标识');
        expect(tester.widget<Text>(badge).data, '🤝');
        expect(find.byKey(const Key('wish_pool_self_badge')), findsNothing);

        final Tooltip tip = tester.widget<Tooltip>(
          find.ancestor(of: badge, matching: find.byType(Tooltip)).first,
        );
        expect(tip.message, _kParentBadgeCopy);
        expect(_hasSemanticsLabel(tester, badge, _kParentBadgeCopy), isTrue);
      });
    }

    testWidgets('历史数据（fulfillSource == null）：也有标识，不出现「无标识」卡',
        (WidgetTester tester) async {
      await _pumpTile(tester, _poolWish('w_legacy', null));
      expect(find.byKey(const Key('wish_pool_parent_badge')), findsOneWidget);
      expect(find.byKey(const Key('wish_pool_self_badge')), findsNothing);
      // 日期行照旧（纯展示逻辑未动）。
      expect(find.byKey(const Key('wish_pool_date_range')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 需求 4 ────────────────────────────────────────────────────────────────
  group('需求 4 · 放进收藏箱后详情卡自动关闭', () {
    testWidgets('点「放进收藏箱」：卡片消失，愿望真的进了收藏箱',
        (WidgetTester tester) async {
      final ProviderContainer c = await _boot();
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime.now().subtract(const Duration(days: 2)),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await _pumpTree(tester, container: c, viewport: const Size(390, 844));

      final Finder card = find.byKey(Key('wish_card_${wish.id}'));
      expect(card, findsOneWidget, reason: '真实愿望卡必须出现');
      await tester.tap(card);
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(kWishDetailDialogKey), findsOneWidget);

      // 收进收藏箱前的「树上入口」确实存在（供对照的既有行为）。
      expect(find.byKey(const Key('wish_detail_change')), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_collect')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wish_detail_collect')));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.byKey(kWishDetailDialogKey), findsNothing,
          reason: '落库成功后详情卡必须自动关闭（玄参需求 4）');
      // 关掉后孩子没法再点「换个愿望」/「实现了」—— 收藏箱状态只能「取回」。
      expect(find.byKey(const Key('wish_detail_change')), findsNothing);
      expect(find.byKey(const Key('wish_detail_self_fulfill')), findsNothing);

      final List<Wish> boxed =
          await c.read(wishOrchestrationServiceProvider).boxedWishes();
      expect(boxed.map((Wish w) => w.id).toList(), <String>[wish.id],
          reason: '必须真的落库进收藏箱，而不是只关卡片');
      expect(tester.takeException(), isNull);
    });

    test('源码守卫：onCollect 落库成功后 pop，失败不关', () {
      final String src =
          File('lib/presentation/child/pages/wish_tree_page.dart')
              .readAsStringSync();
      expect(src.contains('await _collect(wish);'), isTrue);
      expect(src.contains('if (ctx.mounted) Navigator.of(ctx).pop();'), isTrue);
      // 范式与既有 onRealized 一致：先落库、再有条件关闭。
      final int collect = src.indexOf('onCollect: () async {');
      expect(collect, greaterThan(0), reason: 'onCollect 必须是 async 闭包');
      final String body = src.substring(collect, src.indexOf('onChange:', collect));
      expect(body.contains('if (ctx.mounted) Navigator.of(ctx).pop();'), isTrue);
      expect(body.contains('catch (_)'), isTrue,
          reason: '落库失败必须保持卡片不动，不能误关');
    });
  });
}
