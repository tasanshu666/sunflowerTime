/// QA 独立复验：Android 激活码入口与弹框的**窄屏 / 大字号**布局守卫。
///
/// 为什么单独守这一条：`test/qa/premium_a11y_narrow_test.dart` 守的是 **iOS 口径**
/// （商店价格 + 恢复购买 + 4 条 note）。Android 分支换成了「输入激活码解锁」主按钮、
/// 3 条 note、以及一个**全新的弹框**（标题 + 3 行提示 + 输入框 + 粘贴按钮 + 2 个动作
/// 按钮）—— 这些从来没在 320pt 窄屏下被跑过。商业产品上线前必须确认不溢出。
library premium_redeem_code_a11y_test;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';

/// 即时返回商品的假适配器（Android 分支根本不查商店，这里只是让
/// [iapServiceProvider] 能解析，避免 provider 抛出）。
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

/// 内存假票据仓储。
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

/// 测试密钥对（固定 seed）。
final Uint8List _kSeed =
    Uint8List.fromList(List<int>.generate(32, (int i) => (i * 17 + 41) & 0xFF));

void main() {
  late String publicKeyBase64;

  setUpAll(() async {
    final SimpleKeyPair kp =
        await Ed25519().newKeyPairFromSeed(_kSeed);
    publicKeyBase64 = base64.encode((await kp.extractPublicKey()).bytes);
  });

  ({ProviderContainer container, _FakeIapAdapter adapter}) buildEnv() {
    final _FakeIapAdapter adapter = _FakeIapAdapter();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        iapServiceProvider.overrideWithValue(IapService(adapter: adapter)),
        entitlementServiceProvider.overrideWithValue(
          MatrixEntitlementService(
            repository: _FakeRepo(),
            redeemVerifier:
                RedeemCodeVerifier(publicKeyBase64: publicKeyBase64),
          ),
        ),
      ],
    );
    return (container: container, adapter: adapter);
  }

  /// 指定逻辑视口 + 文字缩放。
  Future<void> pumpPage(
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

  Future<bool> pumpUntilEntry(WidgetTester tester, {int maxFrames = 120}) async {
    for (int i = 0; i < maxFrames; i++) {
      if (find.text('输入激活码解锁').evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 10));
    }
    return find.text('输入激活码解锁').evaluate().isNotEmpty;
  }

  /// 每个用例都强制 Android 口径，并在结束还原（避免污染全局单例）。
  void useAndroidRuntime() {
    redeemCodeEntryEnabledResolver = () => true;
    addTearDown(
        () => redeemCodeEntryEnabledResolver = defaultRedeemCodeEntryEnabled);
  }

  for (final ({Size viewport, double scale}) cfg in <({
    Size viewport,
    double scale
  })>[
    (viewport: const Size(320, 568), scale: 1.0), // iPhone SE 1 代口径（最窄）
    (viewport: const Size(320, 568), scale: 1.3), // 最窄 + 大字号
    (viewport: const Size(360, 640), scale: 1.3), // 低端安卓常见口径
    (viewport: const Size(412, 915), scale: 1.0), // 主流安卓
  ]) {
    final String label =
        '${cfg.viewport.width.toInt()}×${cfg.viewport.height.toInt()} '
        '@${cfg.scale}×';

    testWidgets('Android 分支 $label：页面零溢出，激活码主按钮完整可见', (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeIapAdapter adapter}) env =
          buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await pumpPage(tester, env.container,
          viewport: cfg.viewport, textScale: cfg.scale);
      expect(await pumpUntilEntry(tester), isTrue,
          reason: '$label：Android 主按钮应渲染出来');

      expect(tester.takeException(), isNull,
          reason: '🔴 $label：Android 页不得有 RenderFlex 溢出 / 布局异常');

      final Rect btn = tester.getRect(find.byKey(kPremiumMainButtonKey));
      expect(btn.width, greaterThan(0));
      expect(btn.left, greaterThanOrEqualTo(0));
      expect(btn.right, lessThanOrEqualTo(cfg.viewport.width + 0.5),
          reason: '$label：主按钮右边界 ${btn.right} 超出视口宽 ${cfg.viewport.width}');
      expect(btn.bottom, lessThanOrEqualTo(cfg.viewport.height + 0.5),
          reason: '$label：吸底主按钮底边 ${btn.bottom} 超出视口高');

      // 恢复购买在 Android 上必须消失，且消失后不得留下空洞 / 溢出
      expect(find.text('恢复购买'), findsNothing);
    });

    testWidgets('Android 分支 $label：激活码弹框零溢出且确认按钮可命中',
        (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeIapAdapter adapter}) env =
          buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await pumpPage(tester, env.container,
          viewport: cfg.viewport, textScale: cfg.scale);
      expect(await pumpUntilEntry(tester), isTrue);

      await tester.tap(find.byKey(kPremiumMainButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(kPremiumRedeemCodeFieldKey), findsOneWidget,
          reason: '$label：弹框必须打开');
      expect(tester.takeException(), isNull,
          reason: '🔴 $label：弹框不得有布局溢出（提示文案 + 输入框 + 3 个按钮挤在一起）');

      // 确认按钮必须真实存在且可点（不是被挤到屏幕外）
      final Finder confirm = find.byKey(kPremiumRedeemCodeConfirmKey);
      expect(confirm, findsOneWidget);
      final Rect r = tester.getRect(confirm);
      expect(r.width, greaterThan(0));
      expect(r.bottom, lessThanOrEqualTo(cfg.viewport.height + 0.5),
          reason: '$label：确认按钮底边 ${r.bottom} 超出视口');
      expect(r.right, lessThanOrEqualTo(cfg.viewport.width + 0.5),
          reason: '$label：确认按钮右边 ${r.right} 超出视口');

      // 取消弹框，排空可能残留的动画
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(kPremiumRedeemCodeFieldKey), findsNothing);
    });
  }

  testWidgets('Android 说明卡是 3 条（note_1 + note_android + note_3），不是 4 条',
      (WidgetTester tester) async {
    useAndroidRuntime();
    final ({ProviderContainer container, _FakeIapAdapter adapter}) env =
        buildEnv();
    addTearDown(env.container.dispose);
    addTearDown(env.adapter.dispose);

    // 视口调高：说明卡在列表下方，ListView 懒加载会在 400×900 下根本不构建它
    // （首次尝试即踩到这个坑：find 到 0 个 widget）。
    await pumpPage(tester, env.container, viewport: const Size(400, 3000));
    expect(await pumpUntilEntry(tester), isTrue);
    await tester.pump();

    expect(find.textContaining('官网直供'), findsOneWidget,
        reason: 'Android 必须换成官网付款 → 收激活码的说明');
    expect(find.textContaining('Apple ID'), findsNothing,
        reason: 'Apple ID 恢复说明在安卓上不成立，必须不出现');
    expect(find.textContaining('App Store'), findsNothing,
        reason: 'App Store 收款说明在安卓上不成立，必须不出现');
    expect(tester.takeException(), isNull);
  });
}
