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
///
/// ➕ 第四件（Android 官网直供版 · 激活码路径专有）：
///   · `iap.redeemSerial`：激活码签发序号（售后对账 / 区分「官网码」与「iOS IAP」；
///     IAP 路径**不写**此键，故 iOS 用户钥匙串里永远没有它）。
///   ⚠️ 刻意**不升 `schemaVersion`**：本存储是 `FlutterSecureStorage` 的键值对，
///   不是 Drift 表，加一个 key 与数据库迁移无关（`schemaVersion` 保持 32 不动）。
library secure_entitlement_store;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 商品 ID 键（对应 App Store 非消耗型商品）。
const String kSecureIapProductId = 'iap.productId';

/// Apple 签名交易 JWS 原文键（复验凭据）。
const String kSecureIapJws = 'iap.jws';

/// 购买时间（ISO-8601 字符串，仅展示）。
const String kSecureIapAcquiredAt = 'iap.acquiredAt';

/// 激活码签发序号键（十进制字符串；**仅激活码路径写入**）。
///
/// 键名沿用 `iap.` 前缀 = 「这张票据的四件套」在钥匙串里仍是一组，排查时一眼看全。
const String kSecureRedeemSerial = 'iap.redeemSerial';

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

  /// 读取激活码签发序号（**Android 官网直供版**）。
  ///
  /// 返回语义：无此键 / 空串 / 非数字（`"abc"`）/ 安全区不可用 → **一律 null**，
  /// **绝不抛**（失败安全红线：脏票据只该「少显示一行小字」，绝不能让读票据炸掉冷启动）。
  Future<int?> readRedeemSerial() async {
    try {
      final String? raw = await _storage.read(key: kSecureRedeemSerial);
      if (raw == null || raw.isEmpty) return null;
      return int.tryParse(raw.trim());
    } catch (_) {
      // 安全区不可用（测试环境 / 平台异常）→ null，不抛。
      return null;
    }
  }

  /// 写入票据四件套。
  ///
  /// [jws] 为 null / 空串时**不覆写**既有 JWS（避免丢失已存的复验凭据）。
  ///
  /// [redeemSerial] 语义与 [jws] **一致**：null 时**不覆写**既有值。
  /// 为什么选「不覆写」而不是「null 即删除」：
  ///  · 这是与既有 `jws` 参数同一套约定的自然延伸（同一个方法里两套语义最易出错）；
  ///  · serial 是**售后对账凭据**，误删比「多留一个旧号」代价大得多：客服反查时
  ///    没有号就只能靠用户回忆；
  ///  · 实际不存在「IAP 覆盖激活码票据」的场景（`activate` 只在 Android 调、
  ///    `purchaseLifetime`/`restore` 只在 iOS/桌面调），故不会出现来源失真。
  /// 想真正清空 serial 只有一条路：[clear]（整张票据一起删）。
  Future<void> writeTicket({
    required String productId,
    required String? jws,
    required DateTime acquiredAt,
    int? redeemSerial,
  }) async {
    await _storage.write(key: kSecureIapProductId, value: productId);
    if (jws != null && jws.isNotEmpty) {
      await _storage.write(key: kSecureIapJws, value: jws);
    }
    await _storage.write(
      key: kSecureIapAcquiredAt,
      value: acquiredAt.toIso8601String(),
    );
    if (redeemSerial != null) {
      await _storage.write(key: kSecureRedeemSerial, value: '$redeemSerial');
    }
  }

  /// 清除票据四件套（含激活码序号）。
  Future<void> clear() async {
    await _storage.delete(key: kSecureIapProductId);
    await _storage.delete(key: kSecureIapJws);
    await _storage.delete(key: kSecureIapAcquiredAt);
    await _storage.delete(key: kSecureRedeemSerial);
  }
}
