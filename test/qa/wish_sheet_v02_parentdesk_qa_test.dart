/// QA 独立差分复验 · 弹层三缺陷真修（**真实 ParentTodayPage 路径**，非测试自造 showDialog）。
///
/// ## 🟢 v0.2 保留项 · v0.3 沿用（**不是待删资产**）
/// 文件名里的 `v02` 只表示"这条用例首次写于 v0.2 批次"。v0.3 回退的是**推送
/// 机制**（`shared_to_parent` / `schemaVersion 33` / `wishShareRevision`），而
/// 「贴标签 + 温柔回复」弹层是 v0.3 **明确保留**的功能（PRD §2 保留项）。
/// 架构 §3 曾把它列入"删除 5 个 v0.2 测试文件"，经团队负责人裁决**保留**：
/// 它是目前**唯一**真渲染覆盖该生产路径的用例，删掉是覆盖倒退。
/// 文件内**零引用** `sharedToParent` / `schemaVersion 33` / `migration_v33`，
/// 可长期留在仓库作为钉子（`wish_rollback_v03_qa_test.dart` 有断言守住这一点）。
///
/// 工程师 `test/parent/wish_action_sheet_test.dart` 的 barrier 用例是测试自己
/// 传 `barrierDismissible: false` 给 `showDialog`，证明不了生产 `_openTag()`
/// 真这么写；「留在家长端」也没在真实路由里验。本文件：
///   ① 真库插一条树上愿望（v0.3：家长端全量可见，无需授权字段）→ 真渲染 ParentTodayPage →
///      **点生产卡片上的 `parent_wish_action_tag` 按钮**进弹层；
///   ② 语义树两标题各 1 次、标签下拉 items=6 无 null（真 widget 渲染）；
///   ③ 点遮罩空白：弹层仍在、路由仍 `/parent`、**未触发 context.go('/')**；
///   ④ 点「取消」：无异常、路由仍 `/parent`、弹层关闭。
library wish_sheet_v02_parentdesk_qa_test; // v0.2 保留项 · v0.3 沿用

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
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AppLocalizations zh = AppLocalizationsZh();
  late db.AppDatabase database;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    database = db.AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
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
        iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
      ],
    );
    router = GoRouter(
      initialLocation: '/parent',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Center(child: Text('ROOT_HOME'))),
        ),
        GoRoute(
          path: '/parent',
          builder: (_, __) => const ParentTodayPage(),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    container.dispose();
    database.close();
  });

  Future<void> seedShared() async {
    final WishLocalRepository repo = WishLocalRepository(database);
    await repo.save(Wish(
      id: 'shared_wish',
      childId: kChildIdDefault,
      text: '孩子愿意分享的愿望',
      createdAt: DateTime(2026, 11, 18),
      status: WishStatus.pending,
      treeSlot: 0,
    ));
  }

  Future<void> pumpFrames(WidgetTester tester, {int n = 20}) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> openSheetViaProductionButton(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await pumpFrames(tester);
    expect(router.state.uri.path, '/parent');
    final Finder tagButton = find.byKey(const Key('parent_wish_action_tag'));
    expect(tagButton, findsOneWidget,
        reason: '真库 1 条已授权愿望 ⇒ 家长端今日页渲染贴标签按钮');
    await tester.tap(tagButton);
    await pumpFrames(tester);
    expect(find.byKey(const Key('parent_wish_action_sheet')), findsOneWidget,
        reason: '点生产按钮弹出 ParentWishActionSheet');
  }

  testWidgets('真渲染弹层：两标题各 1 次、标签 items=6 无 null 项',
      (WidgetTester tester) async {
    await seedShared();
    await openSheetViaProductionButton(tester);

    expect(find.text(zh.parent_wish_tag_hint), findsOneWidget,
        reason: '「选一个标签（可以跳过）」语义树恰好 1 次');
    expect(find.text(zh.parent_wish_reply_preset), findsOneWidget,
        reason: '「预设回复」语义树恰好 1 次');

    await tester.tap(find.byKey(const Key('parent_wish_tag_picker')));
    await pumpFrames(tester, n: 6);
    expect(find.byType(DropdownMenuItem<WishTag?>), findsNWidgets(6),
        reason: '标签下拉 6 项 = 枚举数，无 +1');
    expect(
      find.ancestor(
        of: find.text(zh.shared_cancel),
        matching: find.byType(DropdownMenuItem<WishTag?>),
      ),
      findsNothing,
      reason: '取消不再作为 value:null 的下拉项混入',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点遮罩：弹层不关闭、路由仍 /parent、未触发 context.go("/")',
      (WidgetTester tester) async {
    await seedShared();
    await openSheetViaProductionButton(tester);

    // 点弹层外的空白遮罩（生产 _openTag 的 barrierDismissible:false 生效）。
    await tester.tapAt(const Offset(4, 4));
    await pumpFrames(tester, n: 6);

    expect(find.byKey(const Key('parent_wish_action_sheet')), findsOneWidget,
        reason: '点遮罩不得关闭弹层');
    expect(router.state.uri.path, '/parent',
        reason: '不得落到 PopScope 的 context.go("/") 把家长踢出');
    expect(find.text('ROOT_HOME'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「取消」：无异常、弹层关闭、留在家长端今日页',
      (WidgetTester tester) async {
    await seedShared();
    await openSheetViaProductionButton(tester);

    await tester.tap(find.text(zh.shared_cancel));
    // 弹层 dismiss 有退场动画，需要有界 pump 覆盖（家长页无无限动画）。
    await pumpFrames(tester, n: 40);

    expect(find.byKey(const Key('parent_wish_action_sheet')), findsNothing,
        reason: '取消后弹层关闭');
    expect(router.state.uri.path, '/parent',
        reason: '取消后仍在家长 space');
    expect(find.text('ROOT_HOME'), findsNothing,
        reason: '不得因 pop(false) 契约冲突被踢到根路由');
    expect(tester.takeException(), isNull,
        reason: '取消不得抛 NoSuchMethodError / 未捕获异常');
  });
}
