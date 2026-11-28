/// QA · Android 分支支付宝购买入口与六态文案（widget 级，零平台依赖）。
library premium_alipay_entry_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';

class _FakeRepo implements EntitlementRepository {
  Entitlement stored = Entitlement.free;
  int writeCount = 0;

  @override
  Future<Entitlement> read() async => stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    writeCount++;
    stored = entitlement;
  }

  @override
  Future<void> clear() async => stored = Entitlement.free;
}

class _FakeApi implements AlipayApi {
  _FakeApi({required this.redeems});

  final List<RedeemData> redeems;
  int redeemIndex = 0;

  @override
  Future<CreateOrderData> createOrder({
    required String platform,
    required String appVersion,
    required String deviceHash,
  }) async =>
      const CreateOrderData(
        outTradeNo: 'SF261128WH00101',
        claimToken: 'cccccccccccccccccccccccccccccccc',
        orderString: 'signed-order-string',
      );

  @override
  Future<RedeemData> redeem({
    required String outTradeNo,
    required String claimToken,
  }) async {
    if (redeemIndex >= redeems.length) {
      return const RedeemData(status: RedeemStatus.pending);
    }
    return redeems[redeemIndex++];
  }
}

class _FakePending implements PendingOrderStore {
  PendingOrder? stored;

  @override
  Future<void> save(PendingOrder pending) async => stored = pending;

  @override
  Future<PendingOrder?> load() async => stored;

  @override
  Future<void> clear() async => stored = null;
}

class _FakeBridge implements AlipayPayBridge {
  _FakeBridge(this.status);

  final String status;

  @override
  Future<AlipayPayResult> pay(String orderString) async =>
      AlipayPayResult(resultStatus: status);

  @override
  Future<bool> isInstalled() async => true;
}

class _FakeActivator implements RedeemCodeActivator {
  _FakeActivator(this.repo);

  final _FakeRepo repo;

  @override
  Future<RedeemActivationResult> activate(String code) async {
    // 模拟 `RedeemCodeActivator.activate()` 的真实副作用：先落库再返回 activated。
    await repo.write(
      Entitlement.lifetime(
        acquiredAt: DateTime.utc(2026, 11, 28),
        productId: 'lifetime',
        redeemSerial: 1024,
      ),
      jws: null,
    );
    return RedeemActivationResult.activated;
  }
}

void main() {
  final AppLocalizationsZh t = AppLocalizationsZh();

  setUp(() {
    redeemCodeEntryEnabledResolver = () => true;
    alipayEntryEnabledResolver = () => true;
  });
  tearDown(() {
    redeemCodeEntryEnabledResolver = defaultRedeemCodeEntryEnabled;
    alipayEntryEnabledResolver = defaultAlipayEntryEnabled;
  });

  ({ProviderContainer container, _FakeRepo repo, _FakePending pending}) buildEnv({
    List<RedeemData> redeems = const <RedeemData>[
      RedeemData(
        status: RedeemStatus.issued,
        redeemCode: 'x',
        serial: 1024,
      ),
    ],
    String payStatus = '9000',
  }) {
    final _FakeRepo repo = _FakeRepo();
    final _FakePending pending = _FakePending();
    final MatrixEntitlementService service = MatrixEntitlementService(
      repository: repo,
      clock: () => DateTime.utc(2026, 11, 28),
    );
    final AlipayUnlockController controller = AlipayUnlockController(
      api: _FakeApi(redeems: redeems),
      pending: pending,
      bridge: _FakeBridge(payStatus),
      activator: _FakeActivator(repo),
      delay: (Duration d) async {},
    );
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      entitlementServiceProvider.overrideWithValue(service),
      alipayUnlockControllerProvider.overrideWithValue(controller),
    ]);
    addTearDown(container.dispose);
    return (container: container, repo: repo, pending: pending);
  }

  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ParentPremiumPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Android：主按钮为支付宝购买，激活码降为次级，无恢复购买',
      (WidgetTester tester) async {
    final env = buildEnv();
    await pumpPage(tester, env.container);

    expect(find.text(t.parent_premium_alipay_btn_buy), findsOneWidget);
    expect(find.byKey(kPremiumMainButtonKey), findsOneWidget);
    expect(find.byKey(kPremiumAlipayCodeEntryKey), findsOneWidget);
    expect(find.byKey(kPremiumAlipayReclaimKey), findsOneWidget);
    expect(find.byKey(kPremiumRestoreButtonKey), findsNothing);
    expect(find.text(t.parent_premium_alipay_note_refund), findsOneWidget);
  });

  testWidgets('Android：支付成功 → 刷新 entitlementProvider → 已解锁态',
      (WidgetTester tester) async {
    final env = buildEnv();
    await pumpPage(tester, env.container);
    await tester.tap(find.byKey(kPremiumMainButtonKey));
    await tester.pumpAndSettle();

    expect(env.repo.writeCount, 1);
    expect(
      env.container.read(entitlementProvider).isPremium,
      isTrue,
      reason: 'unlocked 后必须刷新 entitlementProvider',
    );
    expect(find.text(t.parent_premium_btn_unlocked_done), findsOneWidget);
    expect(find.byKey(kPremiumAlipayCodeEntryKey), findsNothing);
  });

  testWidgets('Android：6001 取消 → 继续支付 + 待支付文案', (WidgetTester tester) async {
    final env = buildEnv(payStatus: '6001');
    await pumpPage(tester, env.container);
    await tester.tap(find.byKey(kPremiumMainButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(t.parent_premium_alipay_btn_continue), findsOneWidget);
    expect(find.text(t.parent_premium_alipay_phase_awaiting), findsOneWidget);
    expect(env.repo.writeCount, 0);
  });

  testWidgets('Android：202 pending 轮询上限 → 按钮禁用 + 已支付待发码文案',
      (WidgetTester tester) async {
    final env = buildEnv(
      redeems: List<RedeemData>.filled(12, const RedeemData(
        status: RedeemStatus.pending,
      )),
    );
    await pumpPage(tester, env.container);
    await tester.tap(find.byKey(kPremiumMainButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(t.parent_premium_alipay_phase_paid), findsWidgets);
    final ButtonStyleButton button =
        tester.widget<ButtonStyleButton>(find.byKey(kPremiumMainButtonKey));
    expect(button.onPressed, isNull, reason: '轮询中主按钮必须禁用');
    expect(find.byKey(kPremiumAlipayPhaseKey), findsOneWidget);
  });

  testWidgets('Android：200 unpaid → 重新下单 + 超时文案', (WidgetTester tester) async {
    final env = buildEnv(
      redeems: const <RedeemData>[
        RedeemData(status: RedeemStatus.unpaid),
      ],
    );
    await pumpPage(tester, env.container);
    await tester.tap(find.byKey(kPremiumMainButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(t.parent_premium_alipay_btn_reorder), findsOneWidget);
    expect(find.text(t.parent_premium_alipay_phase_expired), findsOneWidget);
    expect(env.pending.stored, isNull);
  });

  testWidgets('Android：重新领取入口可补单解锁', (WidgetTester tester) async {
    final env = buildEnv();
    // 先预置 pending：模拟「已付款未解锁」后重新进页面。
    await env.pending.save(PendingOrder(
      outTradeNo: 'SF261128WH00101',
      claimToken: 'cccccccccccccccccccccccccccccccc',
      createdAt: DateTime.utc(2026, 11, 28, 9),
    ));
    await pumpPage(tester, env.container);
    await tester.tap(find.byKey(kPremiumAlipayReclaimKey));
    await tester.pumpAndSettle();

    expect(env.repo.writeCount, 1);
    expect(env.container.read(entitlementProvider).isPremium, isTrue);
  });

  testWidgets('Android：POOL_EXHAUSTED 不解锁、给客服文案', (WidgetTester tester) async {
    final env = buildEnv();
    // 通过 API 返回错误模拟池空：controller 在 start 阶段即失败，不唤起收银台。
    final AlipayUnlockController failing = AlipayUnlockController(
      api: _PoolEmptyApi(),
      pending: _FakePending(),
      bridge: _FakeBridge('9000'),
      activator: _FakeActivator(env.repo),
    );
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      entitlementServiceProvider.overrideWithValue(MatrixEntitlementService(
        repository: env.repo,
      )),
      alipayUnlockControllerProvider.overrideWithValue(failing),
    ]);
    addTearDown(container.dispose);
    await pumpPage(tester, container);
    await tester.tap(find.byKey(kPremiumMainButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(t.parent_premium_alipay_err_pool), findsOneWidget);
    expect(find.text(t.parent_premium_alipay_phase_awaiting), findsOneWidget);
  });
}

/// 池空 API（订单创建即 503 POOL_EXHAUSTED）。
class _PoolEmptyApi implements AlipayApi {
  @override
  Future<CreateOrderData> createOrder({
    required String platform,
    required String appVersion,
    required String deviceHash,
  }) async =>
      const CreateOrderData(
        error: AlipayFailure(code: AlipayErrorCode.poolExhausted),
      );

  @override
  Future<RedeemData> redeem({
    required String outTradeNo,
    required String claimToken,
  }) async =>
      const RedeemData(status: RedeemStatus.pending);
}
