/// 【C84 回归】购买页两处「玄参拍板」修复的守卫。
///
/// 背景（C83 验收遗留，2026-10-17 玄参拍板「都改」）：
///   ① **恢复购买按钮可点范围 34pt → 44pt**（Apple HIG 最小点按尺寸）。
///      只放大「隐形可点范围」+ 横向 padding 8→16，字仍 13pt，视觉几乎无变化。
///      ⚠️ `tapTargetSize: shrinkWrap` 必须保留，否则 Material 会再垫到 48pt，
///      底栏白多 4pt，并破坏 `premium_sticky_cta_test` 的「高度 = 内容之和」不变量。
///   ② **F121：英雄卡两枚胶囊 `Row` → `Wrap`**。320pt 窄屏（iPhone SE 1 代 / 5s
///      口径）下「未解锁」+「一次买断 · 永久」并排需 195pt、可用 177pt，
///      首帧即报 `RenderFlex overflowed by 18 pixels on the right`。
///
/// 本文件守两件事：
///   · **A** 恢复入口真实渲染尺寸 ≥ 44×44pt（不是「源码里写了 44」这种字符串守卫）；
///   · **B** 320×568 / 375×667 真实视口（含 1.3× 文字缩放）下购买页**零 RenderFlex
///     溢出**，且吸底主按钮仍完整可见 —— 防 F121 复发。
library premium_a11y_narrow_test;

import 'dart:async';

import 'package:flutter/gestures.dart';
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

/// 即时返回商品的假适配器（本文件不需要「加载中」态，C83 已另有闸门用例）。
class _FakeIapAdapter implements IapAdapter {
  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async =>
      <IapProduct>[
        const IapProduct(
          id: kIapProductIdLifetime,
          title: 'Lifetime',
          description: 'unlock all',
          price: r'HK$88.00',
        ),
      ];

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

({ProviderContainer container, _FakeIapAdapter adapter}) _buildEnv() {
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
  return (container: container, adapter: adapter);
}

/// 指定视口（逻辑像素，dpr = 1）+ 可选文字缩放。
Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container, {
  required Size viewport,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = viewport;
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

/// 有界 pump 直到商品返回（主按钮出现）。
Future<bool> _pumpUntilLoaded(WidgetTester tester, {int maxFrames = 120}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return find.byKey(kPremiumMainButtonKey).evaluate().isNotEmpty;
}

void main() {
  testWidgets('C84 恢复入口可点范围 ≥ 44pt（Apple HIG 最小点按尺寸）',
      (WidgetTester tester) async {
    final ({ProviderContainer container, _FakeIapAdapter adapter}) env =
        _buildEnv();
    addTearDown(env.container.dispose);
    addTearDown(env.adapter.dispose);

    await _pumpPage(tester, env.container, viewport: const Size(400, 800));
    expect(await _pumpUntilLoaded(tester), isTrue,
        reason: '断言前提：商品应已返回、吸底栏应渲染');

    final Finder restore = find.byKey(kPremiumRestoreButtonKey);
    expect(restore, findsOneWidget, reason: 'Apple 硬性要求：恢复入口必须存在');

    final Size size = tester.getSize(restore);
    expect(size.height, greaterThanOrEqualTo(44.0),
        reason: '🔴 恢复入口的可点高度必须 ≥ 44pt（HIG），实测 ${size.height}pt；'
            'C83 时为 34pt，手指易点偏');
    expect(size.width, greaterThanOrEqualTo(44.0),
        reason: '🔴 恢复入口的可点宽度必须 ≥ 44pt（HIG），实测 ${size.width}pt');

    // 点按范围必须真能被命中：在按钮矩形**四角内侧 1pt** 处各做一次命中测试，
    // 全部命中才算「可点范围确实变大了」（防止只是视觉容器变大、命中区没变）。
    final Offset topLeft = tester.getTopLeft(restore);
    final Offset bottomRight = tester.getBottomRight(restore);
    final List<Offset> probes = <Offset>[
      topLeft + const Offset(1, 1),
      Offset(bottomRight.dx - 1, topLeft.dy + 1),
      Offset(topLeft.dx + 1, bottomRight.dy - 1),
      bottomRight - const Offset(1, 1),
    ];
    for (final Offset p in probes) {
      final HitTestResult r = HitTestResult();
      WidgetsBinding.instance.hitTestInView(r, p, tester.view.viewId);
      final bool hitButton = r.path.any(
        (HitTestEntry e) =>
            e.target is RenderObject &&
            _isInsideRestoreButton(e.target as RenderObject, restore),
      );
      expect(hitButton, isTrue,
          reason: '恢复入口在 $p 处应可命中（44pt 可点范围必须在四个角都生效）');
    }
    expect(tester.takeException(), isNull, reason: '不得有布局异常');
  });

  // 320×568 = iPhone SE 1 代 / 5s 口径（F121 复现视口）；
  // 375×667 = iPhone SE 2/3 口径；两者再叠加平板口径 1.3× 文字缩放。
  for (final ({Size viewport, double scale}) cfg in <({
    Size viewport,
    double scale
  })>[
    (viewport: const Size(320, 568), scale: 1.0),
    (viewport: const Size(375, 667), scale: 1.0),
    (viewport: const Size(320, 568), scale: 1.3),
  ]) {
    final String label =
        '${cfg.viewport.width.toInt()}×${cfg.viewport.height.toInt()} @${cfg.scale}×';
    testWidgets('C84 F121 守卫：$label 零溢出且吸底主按钮完整可见',
        (WidgetTester tester) async {
      final ({ProviderContainer container, _FakeIapAdapter adapter}) env =
          _buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(
        tester,
        env.container,
        viewport: cfg.viewport,
        textScale: cfg.scale,
      );
      expect(await _pumpUntilLoaded(tester), isTrue,
          reason: '$label：断言前提，商品应已返回');

      // ① 首帧零溢出 —— F121 就是首帧即现的 `RenderFlex overflowed by 18 pixels`。
      expect(tester.takeException(), isNull,
          reason: '$label：🔴 不得出现 RenderFlex overflow（F121 回归）');

      // ② 两个胶囊都要在树里（Wrap 换行后仍须各一份，不得被裁掉/替换）。
      expect(find.text('未解锁'), findsOneWidget, reason: '$label：状态胶囊必须存在');
      expect(find.text('一次买断 · 永久'), findsOneWidget,
          reason: '$label：金胶囊必须存在');

      // ③ 吸底主按钮仍完整可见、不越出视口。
      final Finder main = find.byKey(kPremiumMainButtonKey);
      expect(main, findsOneWidget, reason: '$label：主按钮必须唯一存在');
      final Rect btn = tester.getRect(main);
      expect(btn.top, greaterThanOrEqualTo(0.0),
          reason: '$label：主按钮不得越出视口顶部（top=${btn.top}）');
      expect(btn.bottom, lessThanOrEqualTo(cfg.viewport.height),
          reason: '$label：主按钮不得被视口底部裁掉（bottom=${btn.bottom} / '
              '视口 ${cfg.viewport.height}）');

      // ④ 恢复入口也在视口内（不因小屏被挤出屏幕）。
      final Rect restore = tester.getRect(find.byKey(kPremiumRestoreButtonKey));
      expect(restore.bottom, lessThanOrEqualTo(cfg.viewport.height),
          reason: '$label：恢复入口不得被裁掉（bottom=${restore.bottom}）');

      // ⑤ 滚到底也不得冒出新异常（列表尾部元素在 320 宽下同样要能布局）。
      for (int i = 0; i < 20; i++) {
        if (find.byType(ListView).evaluate().isEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$label：🔴 滚动到底过程中不得出现 RenderFlex overflow');
      expect(find.text('购买前请知悉'), findsOneWidget,
          reason: '$label：应能滚到说明卡（列表尾部可布局）');
    });
  }
}

/// 该渲染对象是否位于 [restore] 这棵子树内。
bool _isInsideRestoreButton(RenderObject target, Finder restore) {
  final Element? element = _elementOf(restore);
  if (element == null) return false;
  RenderObject? node = target;
  while (node != null) {
    if (identical(node, element.renderObject)) return true;
    final RenderObject? parent = node.parent;
    node = parent;
  }
  return false;
}

Element? _elementOf(Finder finder) {
  final Iterable<Element> found = finder.evaluate();
  return found.isEmpty ? null : found.first;
}
