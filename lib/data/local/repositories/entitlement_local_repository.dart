/// 本地权益仓储（实现 domain 接口，付费墙 · 阶段 1）。
///
/// 薄封装 [`SecureEntitlementStore`]：把安全区三件套（productId / jws / acquiredAt）
/// 组装成 [Entitlement] 实体，反之亦然。组装口径单点收口于此。
library entitlement_local_repository;

import 'package:sunflower_time/data/local/secure_entitlement_store.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';

class EntitlementLocalRepository implements EntitlementRepository {
  final SecureEntitlementStore _store;

  EntitlementLocalRepository(this._store);

  @override
  Future<Entitlement> read() async {
    try {
      final String? productId = await _store.readProductId();
      if (productId == null || productId.isEmpty) {
        return Entitlement.free; // 无票据 → 安全默认 free
      }
      final String? acquiredRaw = await _store.readAcquiredAtRaw();
      return Entitlement.lifetime(
        productId: productId,
        acquiredAt: acquiredRaw == null ? null : DateTime.tryParse(acquiredRaw),
      );
    } catch (_) {
      // 安全区不可用（测试环境 / 平台异常）→ 安全侧回退 free，绝不抛。
      // 回退 free 只会「少解锁」，不会误放付费能力，符合安全默认原则。
      return Entitlement.free;
    }
  }

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    if (!entitlement.isPremium || entitlement.productId == null) {
      await clear(); // 写入 free / 缺 productId → 视为清除，避免脏票据
      return;
    }
    await _store.writeTicket(
      productId: entitlement.productId!,
      jws: jws,
      acquiredAt: entitlement.acquiredAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> clear() => _store.clear();
}
