/// 激活码序号（serial）落票据 · 回归测试（Android 官网直供版）。
///
/// 背景：`activate()` 成功后原本只写了 `acquiredAt` + `productId`，**serial 丢了** ——
/// App 不知道自己是被哪枚码解锁的，售后对账 / 黑名单 / 区分「官网码 vs iOS IAP」全无抓手。
/// 本文件把「serial 真的进了安全区、且冷启动能读回来」钉死。
///
/// 测试手法：**真实** `SecureEntitlementStore` + MethodChannel 假钥匙串
/// （与 `test/qa/entitlement_ticket_validation_test.dart` 同一套做法）—— 断言的是
/// 键值 map 里的真实副作用，而不是只测内存态；这样「以为落库了其实只改了内存」的
/// 假绿 bug 才会被抓到。
library redeem_serial_ticket_test;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart'
    show kDebugSimulatedProductId;
import 'package:sunflower_time/data/local/repositories/entitlement_local_repository.dart';
import 'package:sunflower_time/data/local/secure_entitlement_store.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';

/// `flutter_secure_storage` 9.x 的平台通道。
const MethodChannel _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// 最小假 IapClient：只为驱动 `restore()` 的 **restored** 分支（写票据时 serial 必须为 null）。
class _FakeIapClient implements IapClient {
  @override
  Stream<IapEvent> get events => const Stream<IapEvent>.empty();

  @override
  Future<List<IapProduct>> loadProducts() async => const <IapProduct>[];

  @override
  Future<IapPurchaseResult> buyLifetime() async => IapPurchaseResult.success;

  @override
  Future<IapRestoreResult> restore() async => IapRestoreResult.restored;

  @override
  String? get lastJws => 'jws.header.payload.signature';
}

/// 测试密钥对（固定 seed ⇒ 可复现；与生产公钥常量解耦）。
final Uint8List _kSeed = Uint8List.fromList(
  List<int>.generate(32, (int i) => (i * 13 + 7) & 0xFF),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 假钥匙串：键 → 值。所有落库断言都直接看这张表。
  final Map<String, String> keychain = <String, String>{};

  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  /// 签一枚有效码（默认 serial 1024，便于断言）。
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

  setUp(() {
    keychain.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
      final Map<dynamic, dynamic> args = call.arguments is Map
          ? call.arguments as Map<dynamic, dynamic>
          : <dynamic, dynamic>{};
      switch (call.method) {
        case 'read':
          return keychain[args['key'] as String];
        case 'write':
          keychain[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          keychain.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          keychain.clear();
          return null;
        case 'containsKey':
          return keychain.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.of(keychain);
        case 'isProtectedDataAvailable':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, null));

  group('① 激活码路径：serial 真落库，且冷启动仍在', () {
    test('activate 成功 → 钥匙串写入 serial；新仓储 read() 后仍是同一 serial',
        () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      final MatrixEntitlementService service = MatrixEntitlementService(
        repository: EntitlementLocalRepository(store),
        clock: () => DateTime(2026, 11, 25, 10, 20, 30),
        redeemVerifier: RedeemCodeVerifier(publicKeyBase64: publicKeyBase64),
      );

      final RedeemActivationResult result = await service.activate(await issue(1024));

      expect(result, RedeemActivationResult.activated);
      // ① 真实副作用：钥匙串里出现了 serial 键
      expect(keychain[kSecureRedeemSerial], '1024',
          reason: 'activate 必须把签发序号落库（不是只改内存态）');
      expect(keychain[kSecureIapProductId], kIapProductIdLifetime);
      expect(keychain.containsKey(kSecureIapJws), isFalse,
          reason: '激活码没有 Apple JWS，不该凭空写一个');

      // ② 冷启动：全新 store + 全新仓储，只能靠钥匙串重建
      final Entitlement cold =
          await EntitlementLocalRepository(SecureEntitlementStore()).read();

      expect(cold.isPremium, isTrue, reason: '冷启动必须仍是会员');
      expect(cold.redeemSerial, 1024, reason: '🔴 冷启动后 serial 必须还在');
      expect(cold.acquiredAt, DateTime(2026, 11, 25, 10, 20, 30));
      // 内存态与票据同向
      expect(service.current.redeemSerial, 1024);
    });

    test('二次激活（alreadyPremium）不重写票据，serial 保持不变', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      final MatrixEntitlementService service = MatrixEntitlementService(
        repository: EntitlementLocalRepository(store),
        redeemVerifier: RedeemCodeVerifier(publicKeyBase64: publicKeyBase64),
      );
      final String code = await issue(2048);

      expect(await service.activate(code), RedeemActivationResult.activated);
      expect(keychain[kSecureRedeemSerial], '2048');

      expect(await service.activate(code), RedeemActivationResult.alreadyPremium);
      expect(keychain[kSecureRedeemSerial], '2048', reason: '幂等：不覆盖原 serial');
    });
  });

  group('② IAP 路径：serial 恒为 null（来源可区分）', () {
    test('purchaseLifetime（无 iap 的本地票据路径）→ 不写 serial 键', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      final MatrixEntitlementService service = MatrixEntitlementService(
        repository: EntitlementLocalRepository(store),
      );

      await service.purchaseLifetime();

      expect(keychain[kSecureIapProductId], kIapProductIdLifetime);
      expect(keychain.containsKey(kSecureRedeemSerial), isFalse,
          reason: 'IAP 路径绝不能写激活码序号（否则来源无法区分）');
      expect(await store.readRedeemSerial(), isNull);
      final Entitlement read =
          await EntitlementLocalRepository(SecureEntitlementStore()).read();
      expect(read.isPremium, isTrue);
      expect(read.redeemSerial, isNull);
    });

    test('restore（restored 分支）→ 写票据时 serial 仍为 null', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      final MatrixEntitlementService service = MatrixEntitlementService(
        repository: EntitlementLocalRepository(store),
        iap: _FakeIapClient(),
      );

      expect(await service.restore(), RestoreResult.restored);

      expect(keychain.containsKey(kSecureRedeemSerial), isFalse);
      expect(await store.readRedeemSerial(), isNull);
      expect(keychain[kSecureIapJws], 'jws.header.payload.signature',
          reason: 'IAP 恢复必须落 JWS（原有行为不得回归）');
      expect(service.current.redeemSerial, isNull);
    });
  });

  group('③ writeTicket(redeemSerial: null) 不覆写既有 serial', () {
    test('先写 1024，再用 IAP 写一次 → 读回来还是 1024', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      await store.writeTicket(
        productId: kIapProductIdLifetime,
        jws: null,
        acquiredAt: DateTime(2026, 11, 25),
        redeemSerial: 1024,
      );
      expect(await store.readRedeemSerial(), 1024);

      // IAP 覆盖写入（redeemSerial 不传 = null）
      await store.writeTicket(
        productId: kIapProductIdLifetime,
        jws: 'jws2',
        acquiredAt: DateTime(2026, 11, 26),
      );

      expect(await store.readRedeemSerial(), 1024,
          reason: 'null 语义 = 不覆写（与 jws 一致）：serial 是对账凭据，误删代价更大');
      expect(keychain[kSecureIapJws], 'jws2', reason: '其余字段照常更新');
      expect(keychain[kSecureIapAcquiredAt], contains('2026-11-26'));
    });

    test('新设备第一次就用 IAP 写入（从未有 serial）→ 键不存在、读回 null', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      await store.writeTicket(
        productId: kIapProductIdLifetime,
        jws: 'jws',
        acquiredAt: DateTime(2026, 11, 25),
      );
      expect(keychain.containsKey(kSecureRedeemSerial), isFalse);
      expect(await store.readRedeemSerial(), isNull);
    });
  });

  group('④ readRedeemSerial 面对脏数据一律 null（绝不抛）', () {
    test('"abc" / 空串 / 无键 → null；带空白的合法值能 trim 出来', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();

      expect(await store.readRedeemSerial(), isNull, reason: '无键 → null');

      keychain[kSecureRedeemSerial] = 'abc';
      expect(await store.readRedeemSerial(), isNull, reason: '非数字 → null');

      keychain[kSecureRedeemSerial] = '';
      expect(await store.readRedeemSerial(), isNull, reason: '空串 → null');

      keychain[kSecureRedeemSerial] = '  1024  ';
      expect(await store.readRedeemSerial(), 1024, reason: '空白应被 trim');

      keychain[kSecureRedeemSerial] = '12.5';
      expect(await store.readRedeemSerial(), isNull, reason: '小数 → null');
    });

    test('clear() 连 serial 键一起删（否则换票后残留旧号）', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      await store.writeTicket(
        productId: kIapProductIdLifetime,
        jws: null,
        acquiredAt: DateTime(2026, 11, 25),
        redeemSerial: 4096,
      );
      expect(keychain.length, 3, reason: 'productId / acquiredAt / redeemSerial');

      await store.clear();

      expect(keychain, isEmpty, reason: 'clear 必须删净四件套');
      expect(await store.readRedeemSerial(), isNull);
    });
  });

  group('⑤ 实体与仓储语义', () {
    test('Entitlement：lifetime 透传 / copyWith 保留 / free 恒 null', () {
      expect(Entitlement.free.redeemSerial, isNull);

      final Entitlement e =
          Entitlement.lifetime(productId: kIapProductIdLifetime, redeemSerial: 7);
      expect(e.redeemSerial, 7);
      expect(e.copyWith(tier: EntitlementTier.premium).redeemSerial, 7,
          reason: 'copyWith 未传 → 保留原值（null 表示不修改）');
      expect(e.copyWith(redeemSerial: 8).redeemSerial, 8);
      // 相等性把 serial 纳入比较：防止「来源不同但被判相等」
      expect(e == Entitlement.lifetime(productId: kIapProductIdLifetime),
          isFalse);
    });

    test('白名单外的 productId（带 serial 的脏票据）→ free 且不泄漏 serial', () async {
      final SecureEntitlementStore store = SecureEntitlementStore();
      await store.writeTicket(
        productId: kDebugSimulatedProductId,
        jws: 'jws',
        acquiredAt: DateTime(2026, 11, 25),
        redeemSerial: 1024,
      );

      final Entitlement e = await EntitlementLocalRepository(store).read();

      expect(e.isPremium, isFalse, reason: '白名单逻辑一个字都不许动');
      expect(e.redeemSerial, isNull, reason: '判 free 时不得带回 serial');
      expect(e, Entitlement.free);
      expect(keychain[kSecureRedeemSerial], '1024',
          reason: 'C69：脏票据只判 free，不静默删数据');
    });
  });
}
