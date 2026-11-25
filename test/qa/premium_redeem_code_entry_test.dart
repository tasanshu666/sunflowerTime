/// Android 官网直供版 · 付费页「输入激活码」入口复验（QA）。
///
/// 与 `test/qa/premium_page_test.dart` 的分工：那边守 **iOS / IAP 口径**（商店价格、
/// 购买三态、恢复购买、Apple 硬性入口），本文件守 **Android 激活码口径**。
///
/// 平台怎么切的：`flutter_test` 会把 `defaultTargetPlatform` 硬钉成 android（不代表真实
/// 设备），故页面用 `redeemCodeEntryEnabledResolver` 这个**可替换解析器**做判定。
/// 本文件 setUp 里把它替换成恒 true，模拟「跑在 Android 真机上」；tearDown 还原，
/// 避免污染其它用例（同 `externalLinkOpener` 的纪律）。
library premium_redeem_code_entry_test;

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

/// 商店价格（仅 iOS / IAP 分支用）。
const String _kStorePrice = r'HK$88.00';

/// 内存假票据仓储（记录写入次数，零平台依赖）。
class _FakeRepo implements EntitlementRepository {
  _FakeRepo({Entitlement? initial}) : _stored = initial ?? Entitlement.free;

  Entitlement _stored;

  /// `write` 次数（幂等取证）。
  int writeCount = 0;

  Entitlement get stored => _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    writeCount++;
    _stored = entitlement;
  }

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

/// 离线假适配器：商店恒可用且返回固定价格（只服务 iOS 分支的对照组用例）。
class _FakeIapAdapter implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async =>
      <IapProduct>[
        const IapProduct(
          id: kIapProductIdLifetime,
          title: 'Lifetime',
          description: 'unlock all',
          price: _kStorePrice,
        ),
      ];

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}
}

/// 测试密钥对（固定 seed ⇒ 可复现；与生产公钥常量无关）。
final Uint8List _kSeed = Uint8List.fromList(
  List<int>.generate(32, (int i) => (i * 11 + 5) & 0xFF),
);

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  /// 装配：假仓储 + 注入测试公钥的域服务 + （可选）可用商店。
  ({ProviderContainer container, _FakeRepo repo}) buildEnv({
    Entitlement? initial,
  }) {
    final _FakeRepo repo = _FakeRepo(initial: initial);
    final IapService iap = IapService(adapter: _FakeIapAdapter());
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        iapServiceProvider.overrideWithValue(iap),
        entitlementRepositoryProvider.overrideWithValue(repo),
        entitlementServiceProvider.overrideWithValue(
          MatrixEntitlementService(
            repository: repo,
            iap: iap,
            clock: () => DateTime(2026, 6, 1),
            redeemVerifier:
                RedeemCodeVerifier(publicKeyBase64: publicKeyBase64),
          ),
        ),
      ],
    );
    return (container: container, repo: repo);
  }

  /// 泵起付费页（视口调高，避免 ListView 懒加载导致控件未构建）。
  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ParentPremiumPage()),
      ),
    );
    await tester.pump();
  }

  /// 有界 pump（避免 SnackBar 计时器把 pumpAndSettle 拖满）。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready, {
    int maxFrames = 120,
  }) async {
    for (int i = 0; i < maxFrames; i++) {
      if (ready()) return;
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// 排空 SnackBar 计时器。
  Future<void> drainSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  /// 签一枚有效激活码。
  Future<String> issue(int serial) async {
    final Uint8List payload = buildRedeemCodePayload(serial: serial);
    final Signature signature = await algorithm.sign(payload, keyPair: keyPair);
    return encodeRedeemCode(assembleRedeemCode(
      payload: payload,
      signatureBytes: signature.bytes,
    ));
  }

  setUpAll(() async {
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPairFromSeed(_kSeed);
    publicKeyBase64 = base64.encode((await keyPair.extractPublicKey()).bytes);
  });

  /// 每个用例前把解析器切成「Android 真机」。
  void useAndroidRuntime() {
    redeemCodeEntryEnabledResolver = () => true;
    addTearDown(() => redeemCodeEntryEnabledResolver = defaultRedeemCodeEntryEnabled);
  }

  group('Android 分支：入口与文案', () {
    testWidgets('主按钮即「输入激活码解锁」：不查商店、无降级卡、无「恢复购买」',
        (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('输入激活码解锁').evaluate().isNotEmpty);

      expect(find.text('输入激活码解锁'), findsOneWidget,
          reason: 'Android 主按钮文案必须是激活码入口');
      expect(find.text('立即解锁 · $_kStorePrice'), findsNothing,
          reason: 'Android 不查商店，主按钮不该出现商店价格');
      expect(find.text('恢复购买'), findsNothing,
          reason: 'Android 没有 Play Billing 交易可恢复，不要给必然失败的入口');
      expect(find.text('暂时连不上商店'), findsNothing,
          reason: 'Android 跳过商店查询，不应落到离线降级态');
      expect(find.textContaining('官网直供'), findsOneWidget,
          reason: '说明卡应换成「官网付款 → 收到激活码」的安卓口径');
    });

    testWidgets('已解锁：主按钮为「已解锁 · 感谢支持」，不再提示输入', (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv(
        initial: Entitlement.lifetime(
          acquiredAt: DateTime(2026, 1, 1),
          productId: kIapProductIdLifetime,
        ),
      );
      addTearDown(env.container.dispose);
      // 载入票据 → UI 读 entitlementProvider（真实冷启动由 main.dart 负责）。
      env.container.read(entitlementProvider.notifier).state =
          await env.container.read(entitlementServiceProvider).load();

      await pumpPage(tester, env.container);
      await tester.pump();

      expect(find.text('已解锁 · 感谢支持'), findsOneWidget);
      expect(find.text('输入激活码解锁'), findsNothing);
    });
  });

  group('Android 分支：激活流程', () {
    testWidgets('点主按钮 → 弹框 → 有效码 → 解锁成功 + 提示 + 票据落库', (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);
      final String code = await issue(1234);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('输入激活码解锁').evaluate().isNotEmpty);

      await tester.tap(find.byKey(kPremiumMainButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(kPremiumRedeemCodeFieldKey), findsOneWidget,
          reason: '点主按钮必须弹出激活码输入框');

      await tester.enterText(find.byKey(kPremiumRedeemCodeFieldKey), code);
      await tester.tap(find.byKey(kPremiumRedeemCodeConfirmKey));
      await pumpUntil(
        tester,
        () => env.container.read(entitlementProvider).isPremium,
        maxFrames: 200,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isTrue,
          reason: '激活成功必须刷新 UI 侧权益源');
      expect(env.repo.stored.isPremium, isTrue, reason: '票据必须落库');
      expect(env.repo.stored.productId, kIapProductIdLifetime);
      expect(env.repo.writeCount, 1);
      expect(find.text('已解锁 · 感谢支持'), findsOneWidget);
      expect(find.textContaining('已解锁，感谢支持'), findsOneWidget,
          reason: '成功也给 SnackBar 正反馈');

      await drainSnack(tester);
    });

    testWidgets('乱码 → 提示「激活码格式不对」，仍未解锁', (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('输入激活码解锁').evaluate().isNotEmpty);

      await tester.tap(find.byKey(kPremiumMainButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
          find.byKey(kPremiumRedeemCodeFieldKey), 'not-a-real-code');
      await tester.tap(find.byKey(kPremiumRedeemCodeConfirmKey));
      await pumpUntil(
          tester, () => find.text('激活码格式不对，请完整复制').evaluate().isNotEmpty);

      expect(find.text('激活码格式不对，请完整复制'), findsOneWidget);
      expect(env.container.read(entitlementProvider).isPremium, isFalse);
      expect(env.repo.writeCount, 0);

      await drainSnack(tester);
    });

    testWidgets('取消弹框 → 不激活、无票据写入', (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('输入激活码解锁').evaluate().isNotEmpty);

      await tester.tap(find.byKey(kPremiumMainButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(kPremiumRedeemCodeFieldKey), findsNothing);
      expect(env.container.read(entitlementProvider).isPremium, isFalse);
      expect(env.repo.writeCount, 0);
    });

    testWidgets('弹框内「从剪贴板粘贴」在测试宿主（空剪贴板）给友好提示、不崩',
        (WidgetTester tester) async {
      useAndroidRuntime();
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('输入激活码解锁').evaluate().isNotEmpty);

      await tester.tap(find.byKey(kPremiumMainButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('从剪贴板粘贴'));
      // 读剪贴板走平台通道（测试宿主没有 → Future 永不完成），页面用
      // kPremiumClipboardTimeout 兜底；这里把假时钟推过超时点。
      await tester.pump(kPremiumClipboardTimeout + const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('剪贴板里没有文字'), findsOneWidget,
          reason: '空剪贴板 / 通道缺失必须给提示，而不是点了没反应（更不能挂死）');
      expect(env.repo.writeCount, 0);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await drainSnack(tester);
    });
  });

  group('对照组：非 Android（iOS / IAP 口径）零变化', () {
    testWidgets('解析器为 false → 仍是商店价格 + 恢复购买入口', (WidgetTester tester) async {
      // 不替换解析器：默认实现读 dart:io，测试宿主是 macOS → false。
      expect(redeemCodeEntryEnabledResolver(), isFalse,
          reason: '测试宿主不应被误判成 Android（否则 18 个既有 iOS 守卫会红）');
      final ({ProviderContainer container, _FakeRepo repo}) env = buildEnv();
      addTearDown(env.container.dispose);

      await pumpPage(tester, env.container);
      await pumpUntil(
          tester, () => find.text('立即解锁 · $_kStorePrice').evaluate().isNotEmpty);

      expect(find.text('立即解锁 · $_kStorePrice'), findsOneWidget);
      expect(find.text('恢复购买'), findsOneWidget);
      expect(find.text('输入激活码解锁'), findsNothing,
          reason: 'iOS 绝不能出现激活码入口（会绕过 Apple IAP → 拒审）');
    });
  });
}
