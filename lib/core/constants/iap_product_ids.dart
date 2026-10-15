/// 内购商品 ID **单点**（付费墙 · 阶段 1）。
///
/// ⚠️ 商品 ID 必须与 App Store Connect 中登记的一致；改价 / 换商品只改此处，
/// 业务代码一律引用常量，禁止字面量（§7 口径巡检清单）。
///
/// 口径（团队已定）：先上海外区 App Store，**仅一次性永久买断**、非消耗型
/// （Non-Consumable），不做订阅、不做消耗品。
library iap_product_ids;

/// 永久买断商品 ID（Non-Consumable，一次性买断）。
///
/// 命名约定：`<bundleId>.<suffix>`，与 `com.sunflowertime.app` 包名对齐。
const String kIapProductIdLifetime =
    'com.sunflowertime.app.premium.lifetime';
