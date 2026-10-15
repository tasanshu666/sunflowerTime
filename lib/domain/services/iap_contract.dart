/// 内购平台契约（付费墙 · 阶段 2）——**纯 Dart，零 Flutter / 插件依赖**。
///
/// 设计约束（对齐 `entitlement_service.dart` 的域层纪律）：
/// - 本文件位于 `lib/domain/`，**不得 import flutter / in_app_purchase**，可被
///   `flutter test` / `package:test` 直接单测（注入假实现即可）。
/// - 上层（域服务 / Provider / UI）**只依赖本文件的抽象与值对象**，绝不直接触碰
///   `in_app_purchase` 插件类型 —— 插件的全部细节收敛在
///   `lib/platform/iap_service.dart` 的实现里（依赖倒置）。
/// - 所有可能失败的路径均以**结果对象 / 枚举**表达（成功 / 取消 / 失败三态），
///   绝不裸抛：离线优先红线 —— 商店不可用、未登录、网络异常都不得让 App 崩溃。
library iap_contract;

/// 商品展示信息（纯 Dart 值对象；把插件 `ProductDetails` 归一化后向上暴露）。
///
/// 只保留 UI 展示与判定「是不是本商品」所需的最小字段；不透出 rawPrice /
/// currencyCode 等插件细节，避免上层被动依赖插件字段。
class IapProduct {
  /// 商品 ID（与 App Store Connect / Play Console 登记一致；见 `iap_product_ids.dart`）。
  final String id;

  /// 展示标题（商店本地化，随账号区域变化）。
  final String title;

  /// 展示描述。
  final String description;

  /// 已本地化的价格串（含货币符号，如 `$9.99`）。
  final String price;

  const IapProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  /// 仅在已知商品 ID、无展示信息时使用的兜底构造（用于「已购但查不到商品」等场景）。
  factory IapProduct.placeholder(String id) => IapProduct(
        id: id,
        title: id,
        description: '',
        price: '',
      );

  /// 不可变副本。
  IapProduct copyWith({
    String? id,
    String? title,
    String? description,
    String? price,
  }) =>
      IapProduct(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        price: price ?? this.price,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IapProduct &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.price == price;

  @override
  int get hashCode => Object.hash(id, title, description, price);

  @override
  String toString() => 'IapProduct(id: $id, price: $price)';
}

/// 一次性买断的购买结果（三态）。**失败 / 取消都不抛**，由调用方按枚举分支处理。
enum IapPurchaseResult {
  /// 购买成功（票据有效；调用方应落库并刷新权益）。
  success,

  /// 用户主动取消（不做任何变更，也非错误）。
  canceled,

  /// 购买失败（商店不可用 / 网络异常 / 平台报错等）。
  failed,
}

/// 恢复购买的三种结局（语义与域层「恢复结果」枚举一致；此处独立枚举，避免域层反向依赖）。
enum IapRestoreResult {
  /// 平台返回了有效票据 → 恢复成功。
  restored,

  /// 平台无任何有效票据（无购买历史 / 未登录同一账号）。
  nothingToRestore,

  /// 查询过程出错（商店不可用 / 网络异常），UI 应提示「稍后重试」而非谎报未购。
  failed,
}

/// 内购事件（**成功 / 取消 / 失败三态**；广播流，UI 与业务可并列订阅）。
///
/// 与购买 / 恢复方法的返回值互补：方法返回的是「本次调用的结论」，事件流覆盖
/// 「任意时机的票据变动」（含 App 启动时补投递的历史交易、商店侧发起等）。
sealed class IapEvent {
  const IapEvent();
}

/// 购买 / 恢复成功。
class IapSucceeded extends IapEvent {
  /// 成功的商品 ID（未知时为 null）。
  final String? productId;

  /// Apple 签名交易 JWS 原文（复验凭据；不可用时为 null）。
  final String? jws;

  const IapSucceeded({this.productId, this.jws});

  @override
  String toString() => 'IapSucceeded(productId: $productId)';
}

/// 用户取消。
class IapCanceled extends IapEvent {
  const IapCanceled();

  @override
  String toString() => 'IapCanceled()';
}

/// 失败（附带原因，便于排查 / 提示）。
class IapFailed extends IapEvent {
  /// 失败原因（自由文本；平台错误串 / 内部标记）。
  final String reason;

  const IapFailed(this.reason);

  @override
  String toString() => 'IapFailed($reason)';
}

/// 内购客户端抽象（**上层唯一依赖点**）。
///
/// 实现见 `lib/platform/iap_service.dart` 的 `IapService`（生产）。
/// 测试可注入任意假实现，无需触碰真实商店。
abstract class IapClient {
  /// 购买 / 恢复事件流（广播；成功 / 取消 / 失败三态）。
  Stream<IapEvent> get events;

  /// 查询本轮买断商品详情（商店不可用 / 查询失败 → 返回**空列表**，绝不抛）。
  Future<List<IapProduct>> loadProducts();

  /// 执行一次性永久买断。
  ///
  /// 返回三态结果：成功 / 取消 / 失败。**任何失败路径都返回 [IapPurchaseResult.failed]
  /// 而非抛出**（离线优先红线）。成功时 [lastJws] 已更新为本次票据的 JWS。
  Future<IapPurchaseResult> buyLifetime();

  /// 恢复购买（换机 / 重装 / 多设备同一账号）。
  Future<IapRestoreResult> restore();

  /// 最近一次成功（购买 / 恢复）拿到的 JWS 原文（落库复验凭据）；无则 null。
  String? get lastJws;
}
