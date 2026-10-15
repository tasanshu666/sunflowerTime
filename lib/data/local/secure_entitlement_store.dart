/// 系统安全区存储封装 —— 权益票据（付费墙 · 阶段 1）。
///
/// 与 [`SecureStore`]（家长 PIN）同款做法：只封装 `flutter_secure_storage` 的读写，
/// 不掺业务判定。
///
/// ⚠️ 存三件事，**绝不能只存一个布尔值**：
///   · `iap.productId`：商品 ID（判定「是否已购」与「购的哪个商品」）；
///   · `iap.jws`：**Apple 签名的交易 JWS 原文**（唯一可离线复验的购买凭据；
///     只存 `purchased=true` 会在换机 / 越狱 / 篡改场景失去唯一凭据，也难排查）；
///   · `iap.acquiredAt`：购买时间（**仅展示用**，不参与任何门控判定）。
library secure_entitlement_store;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 商品 ID 键（对应 App Store 非消耗型商品）。
const String kSecureIapProductId = 'iap.productId';

/// Apple 签名交易 JWS 原文键（复验凭据）。
const String kSecureIapJws = 'iap.jws';

/// 购买时间（ISO-8601 字符串，仅展示）。
const String kSecureIapAcquiredAt = 'iap.acquiredAt';

/// 权益票据安全区存储（薄封装，仅读写原始键值）。
class SecureEntitlementStore {
  final FlutterSecureStorage _storage;

  SecureEntitlementStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// 读取已购商品 ID（无票据 / 平台不可用 → null）。
  Future<String?> readProductId() async =>
      _storage.read(key: kSecureIapProductId);

  /// 读取 Apple 签名交易 JWS 原文（无 → null）。
  Future<String?> readJws() async => _storage.read(key: kSecureIapJws);

  /// 读取购买时间原始字符串（ISO-8601；无 → null）。
  Future<String?> readAcquiredAtRaw() async =>
      _storage.read(key: kSecureIapAcquiredAt);

  /// 写入票据三件套。
  ///
  /// [jws] 为 null / 空串时**不覆写**既有 JWS（避免丢失已存的复验凭据）。
  Future<void> writeTicket({
    required String productId,
    required String? jws,
    required DateTime acquiredAt,
  }) async {
    await _storage.write(key: kSecureIapProductId, value: productId);
    if (jws != null && jws.isNotEmpty) {
      await _storage.write(key: kSecureIapJws, value: jws);
    }
    await _storage.write(
      key: kSecureIapAcquiredAt,
      value: acquiredAt.toIso8601String(),
    );
  }

  /// 清除票据三件套。
  Future<void> clear() async {
    await _storage.delete(key: kSecureIapProductId);
    await _storage.delete(key: kSecureIapJws);
    await _storage.delete(key: kSecureIapAcquiredAt);
  }
}
