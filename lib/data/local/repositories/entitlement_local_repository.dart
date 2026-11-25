/// 本地权益仓储（实现 domain 接口，付费墙 · 阶段 1）。
///
/// 薄封装 [`SecureEntitlementStore`]：把安全区三件套（productId / jws / acquiredAt）
/// 组装成 [Entitlement] 实体，反之亦然。组装口径单点收口于此。
library entitlement_local_repository;

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
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

      // 🔴 C125-4 / C126-5 健壮性修复：productId 必须**精确等于**合法买断商品 ID。
      // 旧实现「非空即 lifetime」会把覆盖安装后钥匙串残留的调试假票据
      // （`debug.simulated.unlock`）或任意脏字符串当成已购，冷启动直接误放会员
      // （iPad13 模拟器实证：3 条残留票据让免费设备变会员）。
      // 只做**判定**，不删除票据（C69：不静默删用户数据）——脏票据原样留着，
      // 由调试面板的「清除会员票据」入口显式清理，或由正式购买流程覆盖。
      if (productId != kIapProductIdLifetime) {
        return Entitlement.free;
      }

      // 边界说明（JWS）：`iap.jws` 已由 `SecureEntitlementStore` 落库，但项目当前
      // **没有离线签名校验实现**，且本 App 单机无后端、不联网复验；本轮只做
      // productId 白名单，能挡住「伪造 / 残留的未知商品号」，挡不住越狱后把
      // productId 改写成合法 id 的定向篡改。该剩余风险已登记；后续若接入
      // StoreKit 复验，就在本函数同一处补 JWS 校验（判定收敛点不扩散）。
      final String? acquiredRaw = await _store.readAcquiredAtRaw();
      // 激活码序号（Android 官网直供版）：无此键 → null（iOS IAP / 免费用户）。
      // 只在**白名单校验通过之后**才读，脏票据不必去碰这个键。
      final int? redeemSerial = await _store.readRedeemSerial();
      return Entitlement.lifetime(
        productId: productId,
        acquiredAt: acquiredRaw == null ? null : DateTime.tryParse(acquiredRaw),
        redeemSerial: redeemSerial,
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
      // 激活码路径才有值；IAP 路径为 null（store 侧「null 不覆写」）。
      redeemSerial: entitlement.redeemSerial,
    );
  }

  @override
  Future<void> clear() => _store.clear();
}
