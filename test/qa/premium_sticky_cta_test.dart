/// 【QA 独立验证 · C83】购买页**吸底 CTA 结构守卫**。
///
/// 与 `premium_page_viewport_test`（真实视口几何回归）互补，本文件守**结构 + 缩放纪律**：
///   ① 加载中（商品未返回）→ `Scaffold.bottomNavigationBar` **必须为 null**，且主按钮 /
///      恢复入口都不存在（避免先闪一下「暂不可购买」再跳成真实价格）；
///   ② 商品返回后 → `bottomNavigationBar` **非 null**，主按钮 / 恢复入口各
///      `findsOneWidget`（防「挪进底栏但没从列表删」造成重复 Key）；
///   ③ 两个按钮都在**底栏子树内**、且**不在** `ListView` 子树内（证明真的搬走了）；
///   ④ 底栏根是 `SafeArea`、内部 `Column` 为 `MainAxisSize.min`
///      （**高度由内容撑开**，无写死高度）；
///   ⑤ 平板口径 textScaler 1.3× + 400 宽下 `takeException()` 为空（不溢出），
///      且底栏高度随之增长（再次证明是内容撑开而非固定高度）。
///
/// C83 补丁（QA 变异测试后加固，两处曾实测漏检）：
///   · **补丁 A**：② 之前先 `_scrollToBottom`。`ListView(children:)` 懒构建，
///     视口外的列表尾部从未 build → 重复 Key 会假绿（M1 变异实测全绿）；
///   · **补丁 B**：`_expectContentDrivenBar` 断言
///     `Column 高 == 主按钮高 + 6 + 恢复按钮高`（容差 0.5pt）。
///     「写死高度 ≥ 内容」既不溢出、也不破坏 `h2 >= h1` 相对比较，但必破坏本等式
///     （`SizedBox(height: 96)` 变异实测原本全绿）。
library premium_sticky_cta_test;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';

/// 闸门式假适配器：`queryProducts` 卡在 [gate] 上，可**确定性**停在「加载中」态。
class _GatedIapAdapter implements IapAdapter {
  /// 商品查询闸门：`complete()` 后商品才返回。
  final Completer<void> gate = Completer<void>();

  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    await gate.future;
    return <IapProduct>[
      const IapProduct(
        id: kIapProductIdLifetime,
        title: 'Lifetime',
        description: 'unlock all',
        price: r'HK$88.00',
      ),
    ];
  }

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}

  Future<void> dispose() => _controller.close();
}

/// 内存假票据仓储（零平台依赖）。
class _FakeRepo implements EntitlementRepository {
  Entitlement _stored = Entitlement.free;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

/// 装配：假适配器 + 真 [IapService] + 域服务（注入内存仓储）。
({ProviderContainer container, _GatedIapAdapter adapter}) _buildEnv() {
  final _GatedIapAdapter adapter = _GatedIapAdapter();
  final IapService svc = IapService(
    adapter: adapter,
    restoreGrace: const Duration(milliseconds: 40),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      iapServiceProvider.overrideWithValue(svc),
      entitlementServiceProvider.overrideWithValue(
        MatrixEntitlementService(repository: _FakeRepo(), iap: svc),
      ),
    ],
  );
  return (container: container, adapter: adapter);
}

/// 真实手机视口 400×800，可选注入文字缩放（模拟平板 ×1.3 口径）。
Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ParentPremiumPage(),
      ),
    ),
  );
}

/// 取吸底栏的高度（`Scaffold.bottomNavigationBar` 那个 widget 的渲染尺寸）。
double _bottomBarHeight(WidgetTester tester) {
  final Scaffold s = tester.widget<Scaffold>(find.byType(Scaffold));
  final Widget? bar = s.bottomNavigationBar;
  if (bar == null) return 0;
  return tester.getSize(find.byWidget(bar)).height;
}

/// 有界 pump 直到商品返回（主按钮出现）。
Future<bool> _pumpUntilLoaded(WidgetTester tester, {int maxFrames = 120}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty;
}

/// 把 ListView 滚到最底（触底即停，最多 20 次）。
///
/// 🔴 **必须**在「唯一性」断言之前调用：`ListView(children:)` 是**懒构建**的，
/// 视口下方（且超出 `cacheExtent`）的 children 根本不会被 build，`find.byKey`
/// 也就找不到 —— 若列表尾部残留一份重复 Key，不滚到底会**假绿**。
/// （C83 补丁 A：变异测试曾实测此漏检。）
Future<void> _scrollToBottom(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    if (find.byType(ListView).evaluate().isEmpty) return;
    final double before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 30));
    final double after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    if ((after - before).abs() < 0.5) return; // 触底
  }
}

/// 断言底栏高度**由内容撑开**（C83 补丁 B）。
///
/// 等式：底栏内唯一 [Column] 的高度 **==** 「主按钮高 + 6 + 恢复按钮高」（容差 0.5pt）。
/// 该等式只在「无外部写死高度 / 无紧约束」时成立 ——
/// 写死 `SizedBox(height: 96)` 这类**恰好大于内容**的高度不会溢出、也不会改变
/// 「1.3× 不比 1.0× 更矮」的相对比较（两边同时被抬高），但**一定**破坏本等式。
void _expectContentDrivenBar(WidgetTester tester, {required String scale}) {
  final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  final Widget? bar = scaffold.bottomNavigationBar;
  expect(bar, isNotNull, reason: '$scale：底栏必须存在（bottomNavigationBar 非 null）');
  final Finder columnFinder = find.descendant(
    of: find.byWidget(bar!),
    matching: find.byType(Column),
  );
  expect(columnFinder, findsOneWidget, reason: '$scale：底栏内应恰有一个 Column');
  final double columnH = tester.getSize(columnFinder).height;
  final double btnH = tester.getSize(find.byKey(kPremiumMainButtonKey)).height;
  final double restoreH =
      tester.getSize(find.byKey(kPremiumRestoreButtonKey)).height;
  expect(columnH, closeTo(btnH + 6 + restoreH, 0.5),
      reason: '$scale：🔴 底栏高度必须由内容撑开 —— Column 高($columnH) 应等于 '
          '主按钮($btnH) + 6 + 恢复按钮($restoreH) = ${btnH + 6 + restoreH}；'
          '不等即说明存在外部写死高度或紧约束（如 SizedBox(height: N) / 未写 '
          'heightFactor: 1 的 Align）');
}

void main() {
  testWidgets('C83 结构守卫：底栏唯一承载主按钮 + 恢复入口，加载中不渲染底栏',
      (WidgetTester tester) async {
    final ({ProviderContainer container, _GatedIapAdapter adapter}) env =
        _buildEnv();
    addTearDown(env.container.dispose);
    addTearDown(env.adapter.dispose);

    await _pumpPage(tester, env.container);

    // ── ① 加载中：底栏不渲染，两个 Key 都不存在（不闪「暂不可购买」） ──────
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: '断言前提：闸门未开，页面应停在加载中');
    final Scaffold loadingScaffold =
        tester.widget<Scaffold>(find.byType(Scaffold));
    expect(loadingScaffold.bottomNavigationBar, isNull,
        reason: '加载中（_loading == true）底栏必须为 null，避免闪一下「暂不可购买」');
    expect(find.byKey(kPremiumMainButtonKey), findsNothing,
        reason: '加载中不应渲染主按钮');
    expect(find.byKey(kPremiumRestoreButtonKey), findsNothing,
        reason: '加载中不应渲染恢复入口');
    expect(tester.takeException(), isNull, reason: '加载中不得有布局异常');

    // 放行商品查询 → 进入未解锁正常态。
    env.adapter.gate.complete();
    expect(await _pumpUntilLoaded(tester), isTrue,
        reason: '商品返回后主按钮应出现（吸底栏渲染）');

    // ── ② 底栏非 null，两 Key 各唯一 ─────────────────────────────────────
    // 🔴 补丁 A：先滚到最底，逼 ListView 把**全部** children 真实 build 一遍。
    // 否则列表尾部（视口外且超出 cacheExtent）的重复 Key 不会被构建，
    // `findsOneWidget` / 「不在 ListView 子树内」两条断言都会假绿。
    await _scrollToBottom(tester);
    expect(tester.takeException(), isNull,
        reason: '滚到底过程中不得出现布局异常');
    final double scrolledOffset = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(scrolledOffset, greaterThan(0.0),
        reason: '断言前提：列表必须确实被滚动过（否则补丁 A 没有检验力）');

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNotNull,
        reason: 'C83：主按钮 / 恢复入口必须挂在 Scaffold.bottomNavigationBar 槽位');
    expect(find.byKey(kPremiumMainButtonKey), findsOneWidget,
        reason: '主按钮必须全树唯一（防「挪进底栏但没从列表删」造成重复 Key）');
    expect(find.byKey(kPremiumRestoreButtonKey), findsOneWidget,
        reason: '恢复入口必须全树唯一');
    expect(find.text('恢复购买'), findsOneWidget,
        reason: 'Apple 硬性要求：文案必须是「恢复购买」，且不得出现两份');

    // ── ③ 按钮在底栏子树内、且已从 ListView 移出 ──────────────────────────
    final Widget bar = scaffold.bottomNavigationBar!;
    expect(
      find.descendant(
        of: find.byWidget(bar),
        matching: find.byKey(kPremiumMainButtonKey),
      ),
      findsOneWidget,
      reason: '主按钮必须位于 bottomNavigationBar 子树内',
    );
    expect(
      find.descendant(
        of: find.byWidget(bar),
        matching: find.byKey(kPremiumRestoreButtonKey),
      ),
      findsOneWidget,
      reason: '恢复入口必须位于 bottomNavigationBar 子树内',
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byKey(kPremiumMainButtonKey),
      ),
      findsNothing,
      reason: '主按钮必须已从 ListView 移除（不得列表里再留一份）',
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byKey(kPremiumRestoreButtonKey),
      ),
      findsNothing,
      reason: '恢复入口必须已从 ListView 移除（不得列表里再留一份）',
    );

    // ── ④ 底栏根为 SafeArea、内部 Column 用 mainAxisSize.min（内容撑高） ──
    expect(bar, isA<SafeArea>(),
        reason: '底栏根必须是 SafeArea（top: false），避开底部安全区');
    final Finder columnFinder = find.descendant(
      of: find.byWidget(bar),
      matching: find.byType(Column),
    );
    expect(columnFinder, findsOneWidget,
        reason: '底栏内应恰有一个 Column（主按钮 + 恢复按钮）');
    expect(tester.widget<Column>(columnFinder).mainAxisSize, MainAxisSize.min,
        reason: '🔴 底栏 Column 必须 mainAxisSize.min：高度由内容撑开，'
            '写死高度会在平板 textScaler 1.3× 下溢出');
    expect(tester.takeException(), isNull, reason: '正常态不得有布局异常');
  });

  testWidgets('C83 缩放纪律：平板口径 textScaler 1.3× 下底栏不溢出且随内容增高',
      (WidgetTester tester) async {
    // 基准：1.0×
    final ({ProviderContainer container, _GatedIapAdapter adapter}) base =
        _buildEnv();
    base.adapter.gate.complete();
    addTearDown(base.container.dispose);
    addTearDown(base.adapter.dispose);

    await _pumpPage(tester, base.container);
    expect(await _pumpUntilLoaded(tester), isTrue, reason: '基准态应加载完成');
    final double h1 = _bottomBarHeight(tester);
    expect(h1, greaterThan(0.0), reason: '底栏高度应大于 0');
    // 补丁 B（1.0× 基准）：底栏高度必须由内容撑开。
    _expectContentDrivenBar(tester, scale: '1.0×');
    expect(tester.takeException(), isNull, reason: '1.0× 下不得溢出');

    // 叠加：1.3×（与平板 `kTabletUiScale` 同口径）
    final ({ProviderContainer container, _GatedIapAdapter adapter}) scaled =
        _buildEnv();
    scaled.adapter.gate.complete();
    addTearDown(scaled.container.dispose);
    addTearDown(scaled.adapter.dispose);

    await _pumpPage(tester, scaled.container, textScale: 1.3);
    expect(await _pumpUntilLoaded(tester), isTrue, reason: '1.3× 态应加载完成');
    final double h2 = _bottomBarHeight(tester);

    // 补丁 B（1.3×）：写死高度在这里必然露馅 —— 内容变高后等式不再成立。
    _expectContentDrivenBar(tester, scale: '1.3×');
    expect(tester.takeException(), isNull,
        reason: '🔴 textScaler 1.3× 下底栏不得出现 RenderFlex overflow');
    expect(h2, greaterThanOrEqualTo(h1),
        reason: '底栏高度必须由内容撑开（1.3× 不得比 1.0× 更矮）：'
            '1.0×=$h1, 1.3×=$h2');
    expect(h2, lessThan(0.5 * 800),
        reason: '底栏不得吞掉半个屏幕（实测 1.3× 高 ${h2}pt）');
  });
}
