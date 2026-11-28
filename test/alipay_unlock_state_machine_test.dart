/// 六态状态机全迁移 / resultStatus 全谱 / 退避与超时复验（纯 Dart，秒级跑完）。
library alipay_unlock_state_machine_test;

import 'dart:collection';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/alipay_endpoints.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';

/// 可编排的假下单 / 领取端口。
class _FakeApi implements AlipayApi {
  _FakeApi({
    CreateOrderData? order,
    Iterable<RedeemData> redeemResults = const <RedeemData>[],
  })  : _order = order ?? _validOrder,
        _queue = Queue<RedeemData>.from(redeemResults);

  static const CreateOrderData _validOrder = CreateOrderData(
    outTradeNo: 'SF261128WH00101',
    claimToken: 'cccccccccccccccccccccccccccccccc',
    orderString: 'signed-order-string',
    amount: '49.90',
    expiresIn: 900,
  );

  CreateOrderData _order;
  final Queue<RedeemData> _queue;
  final List<String> redeemCalls = <String>[];
  int createCalls = 0;

  void setOrder(CreateOrderData order) => _order = order;
  void enqueue(RedeemData data) => _queue.addLast(data);

  @override
  Future<CreateOrderData> createOrder({
    required String platform,
    required String appVersion,
    required String deviceHash,
  }) async {
    createCalls++;
    expect(platform, 'android');
    return _order;
  }

  @override
  Future<RedeemData> redeem({
    required String outTradeNo,
    required String claimToken,
  }) async {
    redeemCalls.add('$outTradeNo:$claimToken');
    if (_queue.isEmpty) {
      return const RedeemData(status: RedeemStatus.pending);
    }
    return _queue.removeFirst();
  }
}

/// 内存假 pending 存储。
class _FakePending implements PendingOrderStore {
  PendingOrder? stored;

  @override
  Future<void> save(PendingOrder pending) async => stored = pending;

  @override
  Future<PendingOrder?> load() async => stored;

  @override
  Future<void> clear() async => stored = null;
}

/// 可编排同步返回码的假桥。
class _FakeBridge implements AlipayPayBridge {
  _FakeBridge(this.status);

  String status;
  int calls = 0;

  @override
  Future<AlipayPayResult> pay(String orderString) async {
    calls++;
    return AlipayPayResult(resultStatus: status);
  }

  @override
  Future<bool> isInstalled() async => true;
}

/// 可编排激活结果的假激活器。
class _FakeActivator implements RedeemCodeActivator {
  RedeemActivationResult next = RedeemActivationResult.activated;
  final List<String> codes = <String>[];

  @override
  Future<RedeemActivationResult> activate(String code) async {
    codes.add(code);
    return next;
  }
}

void main() {
  late _FakeApi api;
  late _FakePending pending;
  late _FakeBridge bridge;
  late _FakeActivator activator;
  late List<Duration> delays;
  late DateTime now;
  late AlipayUnlockController controller;

  AlipayUnlockController build({
    List<RedeemData> redeems = const <RedeemData>[],
    String payStatus = '9000',
    DateTime Function()? clock,
  }) {
    api = _FakeApi(redeemResults: redeems);
    pending = _FakePending();
    bridge = _FakeBridge(payStatus);
    activator = _FakeActivator();
    delays = <Duration>[];
    now = DateTime.utc(2026, 11, 28, 10);
    return AlipayUnlockController(
      api: api,
      pending: pending,
      bridge: bridge,
      activator: activator,
      clock: clock ?? () => now,
      delay: (Duration d) async {
        delays.add(d);
      },
    );
  }

  Future<AlipayUnlockResult> start() => controller.start(
        deviceHash: 'dddddddddddddddddddddddddddddddd',
        appVersion: '1.1.0+2107',
      );

  RedeemData issued([String code = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', int serial = 1024]) => RedeemData(
        status: RedeemStatus.issued,
        redeemCode: code,
        serial: serial,
      );

  const RedeemData waiting = RedeemData(status: RedeemStatus.pending);
  const RedeemData unpaid = RedeemData(status: RedeemStatus.unpaid);

  group('入口与下单', () {
    test('503 POOL_EXHAUSTED → awaitingPayment 且不调起支付宝', () async {
      controller = build();
      api.setOrder(const CreateOrderData(
        error: AlipayFailure(code: AlipayErrorCode.poolExhausted),
      ));
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.awaitingPayment);
      expect(result.error, AlipayErrorCode.poolExhausted);
      expect(bridge.calls, 0);
      expect(api.redeemCalls, isEmpty);
    });

    test('order_string 脏响应（缺字段）→ malformedResponse，不唤起收银台', () async {
      controller = build();
      api.setOrder(const CreateOrderData(orderString: ''));
      final AlipayUnlockResult result = await start();
      expect(result.error, AlipayErrorCode.malformedResponse);
      expect(bridge.calls, 0);
    });

    test('下单成功即写入 pending 三要素', () async {
      // 用 202 pending 让流程停在轮询态，pending 不会被解锁路径清掉。
      controller = build(redeems: const <RedeemData>[
        RedeemData(status: RedeemStatus.pending),
      ]);
      await start();
      expect(pending.stored?.outTradeNo, 'SF261128WH00101');
      expect(pending.stored?.claimToken, 'cccccccccccccccccccccccccccccccc');
      expect(pending.stored?.createdAt, DateTime.utc(2026, 11, 28, 10));
    });
  });

  group('resultStatus 全谱（§1.4）', () {
    for (final String status in <String>['9000', '8000', '6004', '6006', '5000']) {
      test('$status → paidAwaitingCode 轮询（绝不直接解锁）', () async {
        controller = build(redeems: <RedeemData>[issued()], payStatus: status);
        final AlipayUnlockResult result = await start();
        expect(result.phase, AlipayUnlockPhase.unlocked);
        expect(controller.phase, AlipayUnlockPhase.unlocked);
        expect(api.redeemCalls, hasLength(1));
        expect(activator.codes, hasLength(1));
      });
    }

    for (final String status in <String>['6001', '6002', '4000', '9999', '']) {
      test('$status → awaitingPayment 且不轮询', () async {
        controller = build(payStatus: status);
        final AlipayUnlockResult result = await start();
        expect(result.phase, AlipayUnlockPhase.awaitingPayment);
        expect(
          result.error,
          status == '6001'
              ? AlipayErrorCode.payCanceled
              : AlipayErrorCode.payFailed,
        );
        expect(api.redeemCalls, isEmpty);
        expect(bridge.calls, 1);
      });
    }

    test('脏同步返回 {9000} / {} 容错归一化', () {
      expect(
        AlipayPayResult.fromMap(<String, dynamic>{'resultStatus': '{9000}'})
            .resultStatus,
        '9000',
      );
      expect(
        AlipayPayResult.fromMap(<String, dynamic>{'resultStatus': '{9000}'})
            .isMayPaid,
        isTrue,
      );
      expect(
        AlipayPayResult.fromMap(<String, dynamic>{'resultStatus': '{}'})
            .resultStatus,
        '4000',
      );
      expect(
        const AlipayPayResult(resultStatus: '9000').isMayPaid,
        isTrue,
      );
      expect(
        const AlipayPayResult(resultStatus: '6001').isCanceled,
        isTrue,
      );
    });
  });

  group('轮询与退避', () {
    test('首次立即 + 7s 间隔 + 12 次上限，仍 pending 保持 paidAwaitingCode', () async {
      controller = build(
        redeems: List<RedeemData>.filled(kAlipayMaxPollCount, waiting),
      );
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.paidAwaitingCode);
      expect(controller.pollCount, kAlipayMaxPollCount);
      expect(api.redeemCalls, hasLength(kAlipayMaxPollCount));
      expect(delays, hasLength(kAlipayMaxPollCount - 1));
      expect(delays.every((Duration d) => d == kAlipayPollInterval), isTrue);
    });

    test('429 RATE_LIMITED 退避 ≥7s 后重试', () async {
      controller = build(redeems: <RedeemData>[
        const RedeemData(error: AlipayFailure(code: AlipayErrorCode.rateLimited)),
        issued(),
      ]);
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.unlocked);
      expect(delays, <Duration>[kAlipayPollInterval]);
      expect(delays.first.inSeconds >= 7, isTrue);
    });

    test('NETWORK_ERROR 与 RATE_LIMITED 同策略', () async {
      controller = build(redeems: <RedeemData>[
        const RedeemData(error: AlipayFailure(code: AlipayErrorCode.networkError)),
        issued(),
      ]);
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.unlocked);
      expect(delays, <Duration>[kAlipayPollInterval]);
    });

    test('200 unpaid → expired 并清 pending', () async {
      controller = build(redeems: <RedeemData>[unpaid]);
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.expired);
      expect(pending.stored, isNull);
    });

    test('404 / 403 → expired 且不重试', () async {
      for (final AlipayErrorCode code in <AlipayErrorCode>[
        AlipayErrorCode.orderNotFound,
        AlipayErrorCode.claimTokenMismatch,
      ]) {
        controller = build(redeems: <RedeemData>[
          RedeemData(error: AlipayFailure(code: code)),
        ]);
        final AlipayUnlockResult result = await start();
        expect(result.phase, AlipayUnlockPhase.expired);
        expect(result.error, code);
        expect(api.redeemCalls, hasLength(1));
      }
    });

    test('503 POOL_EXHAUSTED 轮询途中回落 awaitingPayment，不调起支付宝', () async {
      controller = build(redeems: <RedeemData>[
        const RedeemData(error: AlipayFailure(code: AlipayErrorCode.poolExhausted)),
      ]);
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.awaitingPayment);
      expect(result.error, AlipayErrorCode.poolExhausted);
    });
  });

  group('发码 / 激活三分支', () {
    test('issued + activated → unlocked，serial 来自服务端', () async {
      controller = build(redeems: <RedeemData>[issued('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', 2048)]);
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.unlocked);
      expect(result.serial, 2048);
      expect(result.isUnlocked, isTrue);
      expect(activator.codes, <String>['xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx']);
      expect(pending.stored, isNull);
      expect(controller.phase, AlipayUnlockPhase.unlocked);
    });

    test('issued + alreadyPremium → duplicate，serial 与首次一致', () async {
      controller = build(redeems: <RedeemData>[issued('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', 2048)]);
      activator.next = RedeemActivationResult.alreadyPremium;
      final AlipayUnlockResult result = await start();
      expect(result.phase, AlipayUnlockPhase.duplicate);
      expect(result.duplicate, isTrue);
      expect(result.serial, 2048);
      expect(pending.stored, isNull);
    });

    for (final RedeemActivationResult failure in <RedeemActivationResult>[
      RedeemActivationResult.malformedCode,
      RedeemActivationResult.invalidCode,
      RedeemActivationResult.notConfigured,
      RedeemActivationResult.failed,
    ]) {
      test('验签/落库失败 $failure → paidAwaitingCode 且保留 pending', () async {
        controller = build(redeems: <RedeemData>[issued()]);
        activator.next = failure;
        final AlipayUnlockResult result = await start();
        expect(result.phase, AlipayUnlockPhase.paidAwaitingCode);
        expect(result.error, AlipayErrorCode.verificationFailed);
        expect(pending.stored, isNotNull);
      });
    }
  });

  group('resumePending / TTL / 重入', () {
    test('无 pending → failed(noPendingOrder)，回待支付', () async {
      controller = build();
      final AlipayUnlockResult result = await controller.resumePending();
      expect(result.phase, AlipayUnlockPhase.awaitingPayment);
      expect(result.error, AlipayErrorCode.noPendingOrder);
    });

    test('pending 超 TTL → expired 并清理', () async {
      controller = build();
      await pending.save(PendingOrder(
        outTradeNo: 'o',
        claimToken: 'c',
        createdAt: DateTime.utc(2026, 11, 28, 9, 0),
      ));
      now = DateTime.utc(2026, 11, 28, 10, 0);
      final AlipayUnlockResult result = await controller.resumePending();
      expect(result.phase, AlipayUnlockPhase.expired);
      expect(pending.stored, isNull);
      expect(api.redeemCalls, isEmpty);
    });

    test('回前台补单立即 redeem 一次并解锁', () async {
      controller = build(redeems: <RedeemData>[issued()]);
      await pending.save(PendingOrder(
        outTradeNo: 'o',
        claimToken: 'c',
        createdAt: now,
      ));
      final AlipayUnlockResult result = await controller.resumePending();
      expect(result.phase, AlipayUnlockPhase.unlocked);
      expect(api.redeemCalls, hasLength(1));
      expect(delays, isEmpty);
    });

    test('重入闸门：未结束的重复 start 返回 busy，不重复下单', () async {
      controller = build(redeems: <RedeemData>[issued()]);
      await pending.save(PendingOrder(
        outTradeNo: 'o',
        claimToken: 'c',
        createdAt: now,
      ));
      // 用 resumePending 持锁：先起一个不 await 的调用。
      final Future<AlipayUnlockResult> first = controller.resumePending();
      final AlipayUnlockResult second = await controller.start(
        deviceHash: 'd',
        appVersion: 'v',
      );
      expect(second.error, AlipayErrorCode.busy);
      await first;
      expect(api.createCalls, 0);
    });

    test('retry 语义等同补单', () async {
      controller = build(redeems: <RedeemData>[issued()]);
      await pending.save(PendingOrder(
        outTradeNo: 'o',
        claimToken: 'c',
        createdAt: now,
      ));
      final AlipayUnlockResult result = await controller.retry();
      expect(result.phase, AlipayUnlockPhase.unlocked);
    });
  });
}
