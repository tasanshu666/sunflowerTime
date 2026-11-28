/// 幂等与验签失败复验：复用既有 `RedeemCodeActivator`，**断言票据写次数 == 1**。
library alipay_idempotency_test;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';

/// 记录写入次数的内存票据仓储。
class _FakeRepo implements EntitlementRepository {
  _FakeRepo();

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
  _FakeApi(this.code, this.serial);

  final String code;
  final int serial;
  int redeemCalls = 0;

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
    redeemCalls++;
    // 通知重放 / 重复点击：服务端永远回读同一码同一 serial。
    return RedeemData(
      status: RedeemStatus.issued,
      redeemCode: code,
      serial: serial,
    );
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
  @override
  Future<AlipayPayResult> pay(String orderString) async =>
      const AlipayPayResult(resultStatus: '9000');

  @override
  Future<bool> isInstalled() async => true;
}

void main() {
  const int serial = 1024;
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;
  late String validCode;

  setUpAll(() async {
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPairFromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + 3) & 0xFF)),
    );
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64.encode(publicKey.bytes);
    final Uint8List payload = buildRedeemCodePayload(serial: serial);
    final Signature signature = await algorithm.sign(payload, keyPair: keyPair);
    validCode = encodeRedeemCode(assembleRedeemCode(
      payload: payload,
      signatureBytes: signature.bytes,
    ));
  });

  ({AlipayUnlockController controller, _FakeRepo repo, _FakeApi api, _FakePending pending})
      buildEnv({required String code, String publicKey = ''}) {
    final _FakeRepo repo = _FakeRepo();
    final _FakeApi api = _FakeApi(code, serial);
    final _FakePending pending = _FakePending();
    final MatrixEntitlementService service = MatrixEntitlementService(
      repository: repo,
      clock: () => DateTime.utc(2026, 11, 28),
      redeemVerifier: RedeemCodeVerifier(publicKeyBase64: publicKey),
    );
    final AlipayUnlockController controller = AlipayUnlockController(
      api: api,
      pending: pending,
      bridge: _FakeBridge(),
      activator: service,
      clock: () => DateTime.utc(2026, 11, 28, 0, 1),
      delay: (Duration d) async {},
    );
    return (
      controller: controller,
      repo: repo,
      api: api,
      pending: pending
    );
  }

  Future<AlipayUnlockResult> start(AlipayUnlockController controller) =>
      controller.start(deviceHash: 'dddddddddddddddddddddddddddddddd', appVersion: '1.1.0+2107');

  test('重复 redeem 同码同 serial；重复 activate 第二次 alreadyPremium；票据只写 1 次',
      () async {
    final env = buildEnv(code: validCode, publicKey: publicKeyBase64);
    final AlipayUnlockResult first = await start(env.controller);
    expect(first.phase, AlipayUnlockPhase.unlocked);
    expect(first.serial, serial);
    expect(env.repo.writeCount, 1);
    expect(env.repo.stored.redeemSerial, serial);
    expect(env.repo.stored.isPremium, isTrue);

    // 同一订单再次走完整流程（模拟 App 重启 / 通知重放）。
    final AlipayUnlockResult second = await start(env.controller);
    expect(second.phase, AlipayUnlockPhase.duplicate);
    expect(second.serial, serial);
    expect(second.isUnlocked, isTrue);
    expect(env.repo.writeCount, 1, reason: 'alreadyPremium 绝不重复写票据');
    expect(env.repo.stored.redeemSerial, serial);
    expect(env.api.redeemCalls, 2);
    expect(env.pending.stored, isNull);
  });

  test('resumePending 重放同一码同样只写 1 次票据', () async {
    final env = buildEnv(code: validCode, publicKey: publicKeyBase64);
    await start(env.controller);
    // 手工放回 pending 模拟「写库成功但进程被杀前未来得及清理」。
    await env.pending.save(PendingOrder(
      outTradeNo: 'SF261128WH00101',
      claimToken: 'cccccccccccccccccccccccccccccccc',
      createdAt: DateTime.utc(2026, 11, 28),
    ));
    final AlipayUnlockResult replay = await env.controller.resumePending();
    expect(replay.phase, AlipayUnlockPhase.duplicate);
    expect(replay.serial, serial);
    expect(env.repo.writeCount, 1);
  });

  test('四种验签失败均不解锁、不清 pending、不裸抛', () async {
    // ① 未配置公钥 → notConfigured
    final noKey = buildEnv(code: validCode, publicKey: '');
    expect(
      (await start(noKey.controller)).error,
      AlipayErrorCode.verificationFailed,
    );
    expect(noKey.repo.writeCount, 0);
    expect(noKey.repo.stored.isPremium, isFalse);
    expect(noKey.pending.stored, isNotNull);

    // ② 篡改码 → badSignature
    final tampered = buildEnv(
      code: validCode[0] == 'A'
          ? 'B${validCode.substring(1)}'
          : 'A${validCode.substring(1)}',
      publicKey: publicKeyBase64,
    );
    expect(
      (await start(tampered.controller)).error,
      AlipayErrorCode.verificationFailed,
    );
    expect(tampered.repo.writeCount, 0);
    expect(tampered.pending.stored, isNotNull);

    // ③ 长度不对 → malformed
    final malformed = buildEnv(code: 'abc', publicKey: publicKeyBase64);
    expect(
      (await start(malformed.controller)).error,
      AlipayErrorCode.verificationFailed,
    );
    expect(malformed.repo.writeCount, 0);
    expect(malformed.pending.stored, isNotNull);

    // ④ 未来版本 → unsupportedVersion
    final SimpleKeyPair other = await algorithm.newKeyPairFromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 5 + 1) & 0xFF)),
    );
    final SimplePublicKey otherPublic = await other.extractPublicKey();
    final Signature otherSignature = await algorithm.sign(
      buildRedeemCodePayload(serial: serial, version: 2),
      keyPair: other,
    );
    final String futureCode = encodeRedeemCode(assembleRedeemCode(
      payload: buildRedeemCodePayload(serial: serial, version: 2),
      signatureBytes: otherSignature.bytes,
    ));
    final future = buildEnv(
      code: futureCode,
      publicKey: base64.encode(otherPublic.bytes),
    );
    expect(
      (await start(future.controller)).error,
      AlipayErrorCode.verificationFailed,
    );
    expect(future.repo.writeCount, 0);
    expect(future.repo.stored.isPremium, isFalse);
    expect(future.pending.stored, isNotNull);
  });
}
