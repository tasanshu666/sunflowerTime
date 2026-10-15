import 'package:sunflower_time/domain/entities/entitlement.dart';

/// 权益票据持久化抽象（付费墙 · 阶段 1）。
///
/// 领域层只依赖本接口；具体实现（系统安全区 / 未来的云校验）在 data 层。
/// **读 / 写 / 清三个语义，读写均以实体 [Entitlement] 交互**，不暴露原始字符串，
/// 避免调用方各自解析票据格式。
abstract class EntitlementRepository {
  /// 读取当前权益票据；无票据 / 数据异常时返回 [Entitlement.free]（安全默认）。
  ///
  /// 返回实体而非原始字符串：tier / productId / acquiredAt 的组装口径由实现收口。
  Future<Entitlement> read();

  /// 写入权益票据。
  ///
  /// [jws] 为 Apple 签名交易 JWS 原文（校验凭据；阶段 2 由 IAP 平台层提供）。
  /// 传 free 实体（或 productId 为 null）时等价于清除票据。
  Future<void> write(Entitlement entitlement, {String? jws});

  /// 清除票据（退出 / 重置 / 家长清除数据用）。
  Future<void> clear();
}
