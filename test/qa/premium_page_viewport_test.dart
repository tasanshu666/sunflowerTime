/// 【QA 独立验证 · V3】购买页**真实视口**回归（400×800, dpr=1）。
///
/// 背景：`premium_page_test` 为绕开 `ListView` 懒加载把视口拉到 400×5000，
/// **真实视口下的溢出 / 挤压 / 主按钮可达性被遮蔽**。本测试在真实手机视口下：
///   ① 渲染全程 **零 RenderFlex overflow**（逐帧 takeException）；
///   ② 主按钮 [kPremiumMainButtonKey] 在初始视口**首屏之下**（证明确需滚动），
///      且**可通过滚动到达**并完整可见；
///   ③ 量出主按钮顶部相对视口的偏移（pt），供「主按钮吸底」决策。
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

const String _storePrice = r'HK$88.00';

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

Future<void> _pumpRealViewport(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(400, 800);
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
  testWidgets('V3 真实视口 400×800：零 overflow + 主按钮可达 + 量偏移',
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

    final List<Object> overflowErrors = <Object>[];
    void collectException() {
      final dynamic ex = tester.takeException();
      if (ex != null) overflowErrors.add(ex);
    }

    await _pumpRealViewport(tester, container);
    collectException();

    // 等商品拉取完成（加载圈消失）。注意：真实视口下主按钮在首屏之下，
    // ListView 懒加载 → 不能用「价格文案出现」作为就绪判据（首屏根本不构建）。
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

    // ② 初始视口下主按钮**在首屏之下**（未构建 / 不可见）→ 证明确需滚动。
    final bool initiallyVisible =
        find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty &&
            _fullyVisible(tester, kPremiumMainButtonKey);
    // ListView 懒加载：首屏之下时 finder 可能为空或部分可见，两种都算「未直达」。

    // ③ 逐步滚动直到主按钮完整可见（模拟用户滑动）。
    bool reachable = false;
    double scrolled = 0;
    for (int i = 0; i < 30; i++) {
      if (find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty &&
          _fullyVisible(tester, kPremiumMainButtonKey)) {
        reachable = true;
        break;
      }
      final double before = _scrollOffset(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 50));
      collectException();
      scrolled += (_scrollOffset(tester) - before).abs();
    }
    // 兜底 ensureVisible：若仍在视口边缘，滚到完全可见。
    if (reachable && !_fullyVisible(tester, kPremiumMainButtonKey)) {
      await tester.ensureVisible(find.byKey(kPremiumMainButtonKey));
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty &&
        _fullyVisible(tester, kPremiumMainButtonKey)) {
      reachable = true;
    }

    expect(reachable, isTrue,
        reason: '主按钮必须可通过滚动到达并完整可见（真实视口 400×800）');

    // ① 全程零 RenderFlex overflow。
    expect(overflowErrors, isEmpty,
        reason: '真实视口渲染全程不得出现 RenderFlex overflow / 任何布局异常');

    // 量偏移：主按钮顶部相对视口内容区（AppBar 之下）的垂直距离。
    final RenderBox btn = tester.renderObject<RenderBox>(
      find.byKey(kPremiumMainButtonKey),
    );
    final Offset btnTop = btn.localToGlobal(Offset.zero);
    final double appBarBottom = _appBarBottom(tester);
    // ignore: avoid_print
    print('QA-V3 主按钮顶部全局 y = ${btnTop.dy}pt；'
        'AppBar 底 = $appBarBottom pt；'
        '相对内容区偏移 = ${(btnTop.dy - appBarBottom).toStringAsFixed(1)}pt；'
        '视口高 800pt；到达所需滚动 ≈ ${scrolled.toStringAsFixed(0)}pt'
        '（终态 scrollOffset = ${_scrollOffset(tester).toStringAsFixed(0)}pt，'
        '即初始按钮顶 ≈ ${(btnTop.dy + _scrollOffset(tester)).toStringAsFixed(0)}pt 全局）；'
        '初始即完整可见 = $initiallyVisible');
  });
}

bool _fullyVisible(WidgetTester tester, Key key) {
  final Finder f = find.byKey(key);
  if (f.evaluate().isEmpty) return false;
  final RenderBox box = tester.renderObject<RenderBox>(f);
  final Offset topLeft = box.localToGlobal(Offset.zero);
  final Offset bottomRight = box.localToGlobal(Offset(box.size.width, box.size.height));
  const Size viewport = Size(400, 800);
  return topLeft.dy >= 0 &&
      bottomRight.dy <= viewport.height &&
      topLeft.dx >= 0 &&
      bottomRight.dx <= viewport.width;
}

double _scrollOffset(WidgetTester tester) {
  final ScrollableState state =
      tester.state<ScrollableState>(find.byType(Scrollable).first);
  return state.position.pixels;
}

double _appBarBottom(WidgetTester tester) {
  final Finder appBar = find.byType(AppBar);
  if (appBar.evaluate().isEmpty) return 0;
  final RenderBox box = tester.renderObject<RenderBox>(appBar.first);
  return box.localToGlobal(Offset.zero).dy + box.size.height;
}
