/// 会员票据校验回归（C125-4 / C126-5）。
///
/// 根因：覆盖安装不清钥匙串，iPad13 模拟器残留 3 条假票据（productId /
/// jws / acquiredAt）；旧 `read()` 只要 productId 非空就无条件发终身会员。
/// 本文件钉死：
///  1. 合法 lifetime 商品号 → premium（上架默认路径不回归）；
///  2. 调试假号 `debug.simulated.unlock` / 任意伪造号 → free，且**三键原样保留**
///     （C69 不删数据）；
///  3. `clear()` 确实删三键，删除后 read → free。
///
/// 用**真实** `SecureEntitlementStore` + MethodChannel 假后端，断言真实副作用
/// （键值 map），而非只测返回值。
library entitlement_ticket_validation_test;

import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart'
    show kDebugSimulatedProductId;
import 'package:sunflower_time/data/local/repositories/entitlement_local_repository.dart';
import 'package:sunflower_time/data/local/secure_entitlement_store.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

/// `flutter_secure_storage` 9.x 的平台通道（见 platform_interface 源码）。
const MethodChannel _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 假钥匙串：键 → 值。所有断言都直接看这张表（真实副作用）。
  final Map<String, String> keychain = <String, String>{};

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

  /// 真实写入三件套（含 JWS），便于断言「未被删除」。
  Future<SecureEntitlementStore> seedTicket(String productId) async {
    final SecureEntitlementStore store = SecureEntitlementStore();
    await store.writeTicket(
      productId: productId,
      jws: 'jws.header.payload.signature',
      acquiredAt: DateTime(2026, 10, 30, 12, 34, 56),
    );
    return store;
  }

  group('票据白名单', () {
    test('合法 lifetime 商品号 → premium（productId / 时间正确）', () async {
      final SecureEntitlementStore store =
          await seedTicket(kIapProductIdLifetime);

      final Entitlement e = await EntitlementLocalRepository(store).read();

      expect(e.tier, EntitlementTier.premium, reason: '正式买断路径必须仍解锁');
      expect(e.productId, kIapProductIdLifetime);
      expect(e.acquiredAt, DateTime(2026, 10, 30, 12, 34, 56));
    });

    test('调试假票据号 → free，且三键原样保留（C69 不删数据）', () async {
      final SecureEntitlementStore store =
          await seedTicket(kDebugSimulatedProductId);
      expect(keychain.length, 3, reason: '前置：三件套已真实落库');

      final Entitlement e = await EntitlementLocalRepository(store).read();

      expect(e.tier, EntitlementTier.free, reason: '假票据绝不能解锁');
      expect(keychain[kSecureIapProductId], kDebugSimulatedProductId,
          reason: '非法票据只判 free，不删 productId');
      expect(keychain[kSecureIapJws], 'jws.header.payload.signature',
          reason: 'JWS 不删');
      expect(keychain[kSecureIapAcquiredAt], isNotNull, reason: '时间不删');
    });

    test('任意伪造商品号（形似买断 id）→ free，且不删票据', () async {
      const String forged = 'com.sunflowertime.app.premium.lifetime.fake';
      final SecureEntitlementStore store = await seedTicket(forged);

      final Entitlement e = await EntitlementLocalRepository(store).read();

      expect(e.tier, EntitlementTier.free, reason: '白名单是精确相等，不做前缀匹配');
      expect(keychain[kSecureIapProductId], forged);
      expect(keychain.length, 3);
    });

    test('无票据 → free（上架默认路径）', () async {
      final Entitlement e =
          await EntitlementLocalRepository(SecureEntitlementStore()).read();
      expect(e, Entitlement.free);
    });

    test('clear() 删三键；随后 read() 为 free', () async {
      final SecureEntitlementStore store =
          await seedTicket(kIapProductIdLifetime);
      final EntitlementLocalRepository repo = EntitlementLocalRepository(store);

      await repo.clear();

      expect(keychain, isEmpty, reason: 'clear 必须删净 productId / jws / acquiredAt');
      expect(await repo.read(), Entitlement.free);
    });
  });
}
