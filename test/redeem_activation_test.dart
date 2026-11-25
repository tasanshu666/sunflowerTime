/// 激活码激活域服务单测（Android 官网直供版）。
///
/// 用**记录型假仓储** + **固定测试密钥对**驱动 `MatrixEntitlementService.activate`，
/// 零平台依赖、零真实密码学密钥：
///  · 首次激活 → 票据落库 + 内存态 premium；
///  · 二次激活 → alreadyPremium 且**不重复写票据**（写入次数钉死）；
///  · 验签失败 / 格式错 / 公钥未配置 → 不写票据、保持 free；
///  · 仓储写抛异常 → failed 且**内存态保持 free**（绝不半成功）。
library redeem_activation_test;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';

/// 记录型假仓储：数清 `write` 次数（幂等断言的唯一取证方式）。
class _RecordingEntitlementRepository implements EntitlementRepository {
  _RecordingEntitlementRepository({
    Entitlement? initial,
    this.throwOnWrite = false,
  }) : _stored = initial ?? Entitlement.free;

  Entitlement _stored;

  /// 注入落库异常（模拟安全区不可用）。
  bool throwOnWrite;

  /// `write` 被调用的次数（🔴 幂等断言的取证口径）。
  int writeCount = 0;

  /// 最近一次写入是否带 JWS（激活码路径必须为 null —— 没有 Apple 票据）。
  String? lastJws;

  /// 当前仓储里的票据。
  Entitlement get stored => _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    writeCount++;
    if (throwOnWrite) throw StateError('secure storage unavailable (test)');
    _stored = entitlement;
    lastJws = jws;
  }

  @override
  Future<void> clear() async {
    _stored = Entitlement.free;
  }
}

/// 测试密钥对（固定 seed ⇒ 可复现；与生产公钥常量无关）。
final Uint8List _kTestSeed = Uint8List.fromList(
  List<int>.generate(32, (int i) => (i * 5 + 1) & 0xFF),
);

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  /// 签一枚有效码。
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
    keyPair = await algorithm.newKeyPairFromSeed(_kTestSeed);
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64.encode(publicKey.bytes);
  });

  /// 装配：假仓储 + 注入测试公钥的验签器 + 固定时钟。
  ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
      buildService({
    _RecordingEntitlementRepository? repository,
    Entitlement? initial,
    bool throwOnWrite = false,
    String? publicKeyOverride,
  }) {
    final _RecordingEntitlementRepository repo = repository ??
        _RecordingEntitlementRepository(
          initial: initial,
          throwOnWrite: throwOnWrite,
        );
    final MatrixEntitlementService service = MatrixEntitlementService(
      repository: repo,
      clock: () => DateTime(2026, 12, 25, 9, 30),
      redeemVerifier: RedeemCodeVerifier(
        publicKeyBase64: publicKeyOverride ?? publicKeyBase64,
      ),
    );
    return (service: service, repo: repo);
  }

  test('能力探测：MatrixEntitlementService 实现 RedeemCodeActivator', () {
    final MatrixEntitlementService service = buildService().service;
    expect(service, isA<RedeemCodeActivator>(),
        reason: 'UI 靠 is RedeemCodeActivator 做能力探测，必须命中');
    expect(service, isA<EntitlementService>());
  });

  group('activate：成功路径', () {
    test('首次激活 → activated：票据落库 + 内存态 premium', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      final String code = await issue(1001);

      final RedeemActivationResult result = await env.service.activate(code);

      expect(result, RedeemActivationResult.activated);
      expect(env.repo.writeCount, 1, reason: '激活成功必须恰好写一次票据');
      expect(env.repo.stored.isPremium, isTrue);
      expect(env.repo.stored.productId, kIapProductIdLifetime,
          reason: '商品 ID 必须走单点常量，不写死字符串');
      expect(env.repo.stored.acquiredAt, DateTime(2026, 12, 25, 9, 30),
          reason: 'acquiredAt 取注入时钟');
      expect(env.repo.lastJws, isNull,
          reason: '激活码没有 Apple JWS，落库时必须是 null');
      expect(env.service.current.isPremium, isTrue);
      // 内存态与票据同向（两个内存源的领域层这一侧）。
      expect(env.service.current, env.repo.stored);
    });

    test('带分组连字符 / 空白的粘贴形态同样能激活', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      final String formatted = formatRedeemCodeForDisplay(await issue(2002));
      expect(await env.service.activate(' $formatted '),
          RedeemActivationResult.activated);
      expect(env.service.current.isPremium, isTrue);
    });
  });

  group('activate：幂等（绝不重复写票据）', () {
    test('二次激活 → alreadyPremium，写入次数仍为 1', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      final String code = await issue(3003);

      expect(await env.service.activate(code), RedeemActivationResult.activated);
      expect(env.repo.writeCount, 1);

      expect(await env.service.activate(code),
          RedeemActivationResult.alreadyPremium);
      expect(env.repo.writeCount, 1, reason: '幂等：已 premium 不得再写票据');
      expect(env.service.current.isPremium, isTrue);
    });

    test('票据本来就 premium（如重装后重新输入）→ 直接 alreadyPremium，零写入', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService(
        initial: Entitlement.lifetime(
          acquiredAt: DateTime(2026, 1, 1),
          productId: kIapProductIdLifetime,
        ),
      );
      await env.service.load();

      final RedeemActivationResult result =
          await env.service.activate(await issue(4004));

      expect(result, RedeemActivationResult.alreadyPremium);
      expect(env.repo.writeCount, 0);
      expect(env.repo.stored.acquiredAt, DateTime(2026, 1, 1),
          reason: '原票据的 acquiredAt 不得被覆盖');
    });
  });

  group('activate：失败路径（票据不变、内存态保持 free）', () {
    test('验签失败（篡改字符）→ invalidCode，零写入、保持 free', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      final String code = await issue(5005);
      final String tampered =
          '${code.substring(0, code.length - 1)}${code.endsWith('A') ? 'B' : 'A'}';

      final RedeemActivationResult result =
          await env.service.activate(tampered);

      expect(result, RedeemActivationResult.invalidCode);
      expect(env.repo.writeCount, 0);
      expect(env.repo.stored.isPremium, isFalse);
      expect(env.service.current.isPremium, isFalse);
    });

    test('版本号不支持 → invalidCode（与「格式错」区分开）', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      final Uint8List payload =
          buildRedeemCodePayload(serial: 6006, version: 0x02);
      final Signature signature =
          await algorithm.sign(payload, keyPair: keyPair);
      final String futureCode = encodeRedeemCode(assembleRedeemCode(
        payload: payload,
        signatureBytes: signature.bytes,
      ));

      expect(await env.service.activate(futureCode),
          RedeemActivationResult.invalidCode);
      expect(env.repo.writeCount, 0);
      expect(env.service.current.isPremium, isFalse);
    });

    test('格式错误（乱码 / 长度不对）→ malformedCode，零写入、保持 free', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();

      expect(await env.service.activate(''),
          RedeemActivationResult.malformedCode);
      expect(await env.service.activate('hello-world'),
          RedeemActivationResult.malformedCode);
      expect(await env.service.activate(List<String>.filled(92, '*').join()),
          RedeemActivationResult.malformedCode);

      expect(env.repo.writeCount, 0);
      expect(env.service.current.isPremium, isFalse);
    });

    test('公钥未配置 → notConfigured（不写票据、不谎报「码无效」）', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService(publicKeyOverride: '');

      final RedeemActivationResult result =
          await env.service.activate(await issue(7007));

      expect(result, RedeemActivationResult.notConfigured);
      expect(env.repo.writeCount, 0);
      expect(env.service.current.isPremium, isFalse);
    });

    test('落库抛异常 → failed，且内存态保持 free（绝不半成功）', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService(throwOnWrite: true);

      final RedeemActivationResult result =
          await env.service.activate(await issue(8008));

      expect(result, RedeemActivationResult.failed);
      expect(env.repo.writeCount, 1, reason: '确实尝试过写入');
      expect(env.service.current.isPremium, isFalse,
          reason: '写库失败后内存态必须还是 free，否则重启即掉档');
      expect(env.repo.stored.isPremium, isFalse);
    });

    test('落库抛异常后重试成功 → activated（失败不污染后续）', () async {
      final _RecordingEntitlementRepository repo =
          _RecordingEntitlementRepository(throwOnWrite: true);
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService(repository: repo);
      final String code = await issue(9009);

      expect(await env.service.activate(code), RedeemActivationResult.failed);
      repo.throwOnWrite = false;
      expect(await env.service.activate(code), RedeemActivationResult.activated);
      expect(env.service.current.isPremium, isTrue);
      expect(env.repo.writeCount, 2);
    });
  });

  group('与 iOS 链路互不干扰', () {
    test('activate 不触碰 IapClient（不注入 iap 也能解锁）', () async {
      // buildService 从不注入 `iap`：若 activate 走了商店链路，这里必然失败。
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      expect(await env.service.activate(await issue(1234)),
          RedeemActivationResult.activated);
    });

    test('purchaseLifetime 行为不受影响（无 iap 时仍只写本地票据）', () async {
      final ({MatrixEntitlementService service, _RecordingEntitlementRepository repo})
          env = buildService();
      await env.service.purchaseLifetime();
      expect(env.repo.writeCount, 1);
      expect(env.repo.stored.isPremium, isTrue);
      expect(env.repo.lastJws, isNull);
    });
  });
}
