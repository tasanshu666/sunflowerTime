/// 待支付订单凭据的安全区存储（Android 官网直供版补单用）。
///
/// 只存 `pending_order.{out_trade_no,claim_token,created_at}` 三键
/// （增量架构设计 §4.1）——**不存 order_string**：唤起串是一次性签名数据，
/// 补单走 `redeem` 而非重新支付。
///
/// 🔴 **失败安全**：安全区不可用 / 平台异常 / 脏数据一律返回 null 或静默成功，
/// **绝不裸抛**（脏 pending 只该让「重新领取」不可用，绝不能拖垮启动 / 支付流程）；
/// `clear()` 只删自己这三键，**绝不 deleteAll**（会连带清掉 PIN 与权益票据）。
library pending_order_store;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart'
    show PendingOrder, PendingOrderStore;

/// out_trade_no 键。
const String kPendingOrderOutTradeNoKey = 'pending_order.out_trade_no';

/// claim_token 键（16 字节 hex，必须存安全区）。
const String kPendingOrderClaimTokenKey = 'pending_order.claim_token';

/// 创建时间键（ISO-8601）。
const String kPendingOrderCreatedAtKey = 'pending_order.created_at';

/// `PendingOrderStore` 的安全区实现。
class PendingOrderStoreImpl implements PendingOrderStore {
  /// [storage] 可注入（测试可用打桩的 `FlutterSecureStorage`）；默认构造不触平台。
  PendingOrderStoreImpl([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// 保存三键；任一写失败静默吞掉（失败安全：补单能力降级但不崩）。
  @override
  Future<void> save(PendingOrder pending) async {
    try {
      await _storage.write(
        key: kPendingOrderOutTradeNoKey,
        value: pending.outTradeNo,
      );
      await _storage.write(
        key: kPendingOrderClaimTokenKey,
        value: pending.claimToken,
      );
      await _storage.write(
        key: kPendingOrderCreatedAtKey,
        value: pending.createdAt.toIso8601String(),
      );
    } catch (_) {
      // 安全区不可用（测试宿主 / 系统异常）→ 静默降级，不抛。
    }
  }

  /// 读取三键；缺任一必填键 / 时间脏 → null。
  @override
  Future<PendingOrder?> load() async {
    try {
      final List<String?> raw = await Future.wait<String?>(<Future<String?>>[
        _storage.read(key: kPendingOrderOutTradeNoKey),
        _storage.read(key: kPendingOrderClaimTokenKey),
        _storage.read(key: kPendingOrderCreatedAtKey),
      ]);
      final String outTradeNo = raw[0] ?? '';
      final String claimToken = raw[1] ?? '';
      if (outTradeNo.isEmpty || claimToken.isEmpty) return null;
      final DateTime createdAt =
          DateTime.tryParse(raw[2] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return PendingOrder(
        outTradeNo: outTradeNo,
        claimToken: claimToken,
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// 只删除本功能的三键（**绝不 deleteAll**：PIN / 权益票据必须原样保留）。
  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: kPendingOrderOutTradeNoKey);
      await _storage.delete(key: kPendingOrderClaimTokenKey);
      await _storage.delete(key: kPendingOrderCreatedAtKey);
    } catch (_) {
      // 失败安全：清不掉下次会被新订单覆写，不影响主链路。
    }
  }
}
