/// 【QA 独立验证 · C83】购买页**吸底回归**（真实视口 400×800, dpr=1）。
///
/// 背景（历史 → C83）：改版后购买页主按钮原先排在 `ListView` 末尾，在真实手机视口下
/// 必须滚动 ≈480pt 才看得到「立即解锁」，家长首屏直接看不到买断入口。C83 把
/// **主按钮 + 「恢复购买」入口**搬进 `Scaffold.bottomNavigationBar` 吸底。
///
/// 本测试因此由「证明确需滚动」翻转为**吸底回归**，在真实手机视口下死守 5 条：
///   ① 初始（scrollOffset == 0）主按钮 [kPremiumMainButtonKey] **完整可见**，
///      且全树**唯一**（防「挪进底栏但没从列表删」造成重复 Key）；
///   ② 把列表滚到最底后主按钮**仍完整可见**，且全局 y 与初始相差 < 1.0pt
///      （即真正吸底、不随滚动位移）；
///   ③ 「恢复购买」入口 [kPremiumRestoreButtonKey] 初始视口即完整可见
///      （Apple 对可恢复内购的硬性要求，不得藏进滚动区）；
///   ④ 全程 `tester.takeException()` 为空（零 RenderFlex overflow / 零布局异常）；
///   ⑤ 主按钮不越出视口、其底边不压住恢复按钮（RenderBox 全局矩形比较）。
library premium_page_viewport_test;

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

/// 真实视口尺寸（logical pt；dpr = 1）。
const Size _kViewport = Size(400, 800);

const String _storePrice = r'HK$88.00';

/// 假 IAP 适配器（零平台依赖：绝不触碰真实 `in_app_purchase` / StoreKit）。
class _FakeIapAdapter implements IapAdapter {
  bool available = true;
  String price = _storePrice;

  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    if (!available) return const <IapProduct>[];
    return <IapProduct>[
      IapProduct(
        id: kIapProductIdLifetime,
        title: 'Lifetime',
        description: 'unlock all',
        price: price,
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
  _FakeRepo({Entitlement? initial}) : _stored = initial ?? Entitlement.free;

  Entitlement _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

/// 在**真实** 400×800 / dpr=1 视口下挂载购买页（不做任何放大，保持真机口径）。
Future<void> _pumpRealViewport(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = _kViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ParentPremiumPage()),
    ),
  );
}

void main() {
  testWidgets('C83 真实视口 400×800：主按钮吸底常驻可见 + 零 overflow',
      (WidgetTester tester) async {
    final _FakeIapAdapter adapter = _FakeIapAdapter();
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
    addTearDown(container.dispose);
    addTearDown(adapter.dispose);

    // 逐帧收集异常（overflow 会在布局/paint 阶段以 FlutterError 抛给 takeException）。
    final List<Object> exceptions = <Object>[];
    void collectException() {
      final Object? ex = tester.takeException();
      if (ex != null) exceptions.add(ex);
    }

    await _pumpRealViewport(tester, container);
    collectException();

    // 等商品拉取完成（加载圈消失 → 吸底栏才渲染）。
    bool ready = false;
    for (int i = 0; i < 120; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        ready = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
      collectException();
    }
    expect(ready, isTrue, reason: '真实视口下商品也应正常返回（400×800）');

    // ── ① 初始（未滚动）主按钮完整可见 + 全树唯一 ──────────────────────────
    expect(find.byKey(kPremiumMainButtonKey), findsOneWidget,
        reason: '主按钮必须全树唯一（不得既留在 ListView 又放进吸底栏）');
    expect(_scrollOffset(tester), 0.0,
        reason: '断言前提：此时列表尚未滚动（scrollOffset 必须为 0）');
    expect(_fullyVisible(tester, kPremiumMainButtonKey), isTrue,
        reason: '吸底后主按钮必须**首屏完整可见**，无需任何滚动（C83 核心行为）');

    // ── ③ 恢复购买入口初始视口即完整可见（Apple 硬性要求） ────────────────
    expect(find.byKey(kPremiumRestoreButtonKey), findsOneWidget,
        reason: '「恢复购买」入口必须唯一且存在（Apple 对可恢复内购硬性要求）');
    expect(_fullyVisible(tester, kPremiumRestoreButtonKey), isTrue,
        reason: '「恢复购买」入口必须首屏完整可见，不得藏进滚动区');

    // ── ⑤ 主按钮不越出视口、底边不压住恢复按钮 ────────────────────────────
    final Rect btn0 = _globalRect(tester, kPremiumMainButtonKey);
    final Rect restore0 = _globalRect(tester, kPremiumRestoreButtonKey);
    expect(btn0.top, greaterThanOrEqualTo(0.0),
        reason: '主按钮上边不得越出视口顶部');
    expect(btn0.bottom, lessThanOrEqualTo(_kViewport.height),
        reason: '主按钮下边不得越出视口底部');
    expect(restore0.bottom, lessThanOrEqualTo(_kViewport.height),
        reason: '恢复按钮下边不得越出视口底部');
    expect(btn0.bottom, lessThanOrEqualTo(restore0.top + 0.01),
        reason: '主按钮底边不得压住/重叠恢复按钮（应为「主按钮在上、恢复在下」）');
    expect(btn0.left, greaterThanOrEqualTo(0.0),
        reason: '主按钮左边不得越出视口左侧');
    expect(btn0.right, lessThanOrEqualTo(_kViewport.width),
        reason: '主按钮右边不得越出视口右侧');

    // ── ② 滚到最底：主按钮仍完整可见且全局 y 不变（真正吸底） ──────────────
    double prevOffset = _scrollOffset(tester);
    for (int i = 0; i < 40; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 30));
      collectException();
      final double now = _scrollOffset(tester);
      if ((now - prevOffset).abs() < 0.5) break; // 触底（已无可滚动余量）
      prevOffset = now;
    }
    final double finalOffset = _scrollOffset(tester);
    expect(finalOffset, greaterThan(200.0),
        reason: '列表内容必须确实长于视口并被滚动过（否则本用例没有检验力）');

    expect(find.byKey(kPremiumMainButtonKey), findsOneWidget,
        reason: '滚动到最底后主按钮仍应唯一存在');
    expect(_fullyVisible(tester, kPremiumMainButtonKey), isTrue,
        reason: '滚动到最底后主按钮必须**仍完整可见**（吸底不得被列表顶出视口）');

    final Rect btn1 = _globalRect(tester, kPremiumMainButtonKey);
    final Rect restore1 = _globalRect(tester, kPremiumRestoreButtonKey);
    expect((btn1.top - btn0.top).abs(), lessThan(1.0),
        reason: '主按钮全局 y 不得随列表滚动变化（吸底后应恒定），'
            '实测位移 ${(btn1.top - btn0.top).abs().toStringAsFixed(2)}pt');
    expect((restore1.top - restore0.top).abs(), lessThan(1.0),
        reason: '恢复按钮全局 y 不得随列表滚动变化（吸底后应恒定）');
    expect(btn1.bottom, lessThanOrEqualTo(restore1.top + 0.01),
        reason: '滚动后主按钮与恢复按钮仍不得重叠');
    expect(btn1.bottom, lessThanOrEqualTo(_kViewport.height),
        reason: '滚动后主按钮仍不得越出视口底部');

    // ── ④ 全程零异常（零 RenderFlex overflow） ─────────────────────────────
    expect(exceptions, isEmpty,
        reason: '真实视口渲染全程不得出现 RenderFlex overflow / 任何布局异常：'
            '${exceptions.join('\n')}');
  });
}

/// 控件是否**完整**落在 [_kViewport] 之内（四条边都不越界）。
bool _fullyVisible(WidgetTester tester, Key key) {
  final Finder f = find.byKey(key);
  if (f.evaluate().isEmpty) return false;
  final Rect r = _globalRect(tester, key);
  return r.top >= 0 &&
      r.bottom <= _kViewport.height &&
      r.left >= 0 &&
      r.right <= _kViewport.width;
}

/// 控件在全局坐标系下的矩形（用于跨组件比较位置关系）。
Rect _globalRect(WidgetTester tester, Key key) {
  final RenderBox box = tester.renderObject<RenderBox>(find.byKey(key));
  final Offset topLeft = box.localToGlobal(Offset.zero);
  return Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    box.size.width,
    box.size.height,
  );
}

/// 页面列表的当前滚动偏移（真实视口下只有一个 `Scrollable`：body 的 ListView）。
double _scrollOffset(WidgetTester tester) {
  final ScrollableState state =
      tester.state<ScrollableState>(find.byType(Scrollable).first);
  return state.position.pixels;
}
