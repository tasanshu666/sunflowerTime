/// 权益服务（付费墙 · 阶段 1）——**抽象接口 + 纯逻辑判定实现**。
///
/// 设计约束：
/// - **纯 Dart，零平台依赖**：本文件不 import flutter / 任何插件，判定实现只依赖
///   Repository 抽象与门控矩阵常量，可直接被 `package:test` 单测（内存假仓储即可）。
/// - 判定逻辑（[can] / [quotaOf]）委托门控矩阵单点收口
///   （`entitlement_matrix.dart` 的 `featureAllowedFor` / `featureQuotaFor`），
///   不在此处写第二份 tier 比较。
///
/// 与阶段 2 的边界：真正的 StoreKit 购买 / 校验 / JWS 由平台层 `iap_service.dart`
/// 承担，本阶段 `purchaseLifetime` 只负责**把一份本地票据落库并刷新内存态**，
/// 使上层（Provider / Gate）与后续阶段可以无感接入。
library entitlement_service;

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';

/// 权益服务接口（架构 §「门控单点收口」）。
///
/// 生命周期：`load()` 一次初始化内存态 → 门控点同步查 [can] / [quotaOf]；
/// 购买 / 恢复成功后调用 [refresh] 或由本服务的购买方法自行刷新。
abstract class EntitlementService {
  /// 读取票据并载入内存态（返回载入后的权益）。
  Future<Entitlement> load();

  /// 重新读取票据刷新内存态（购买 / 恢复 / 外部变更后调用）。
  Future<void> refresh();

  /// 执行一次性永久买断（写入本地票据并刷新内存态）。
  Future<void> purchaseLifetime();

  /// 恢复购买。
  Future<RestoreResult> restore();

  /// 当前档位下，能力点 [f] 是否可用（同步；未 `load()` 时按 free 判定）。
  bool can(FeatureKey f);

  /// 当前档位下，能力点 [f] 的额度（[kUnlimitedQuota] = 不限）。
  int quotaOf(FeatureKey f);
}

/// 基于**本地票据 + 门控矩阵**的纯逻辑判定实现。
///
/// - 内存态 [_current] 默认 [Entitlement.free]（安全默认，构造即可用，不触平台）；
/// - 判定完全由注入的 [matrix]（默认 [`kEntitlementMatrix`]）驱动；
/// - [clock] 可注入以便单测固定时间（默认系统时钟）。
///
/// ⚠️ 阶段 1 矩阵全放开，故对 free 用户 [can] 亦返回 true —— 行为零变化。
class MatrixEntitlementService implements EntitlementService {
  MatrixEntitlementService({
    required EntitlementRepository repository,
    IapClient? iap,
    Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
    DateTime Function()? clock,
  })  : _repository = repository,
        _iap = iap,
        _matrix = matrix,
        _clock = clock ?? DateTime.now;

  final EntitlementRepository _repository;

  /// 内购客户端（可选）。
  ///
  /// - 为 null 时（阶段 1 契约 / 纯逻辑单测）[purchaseLifetime] / [restore] 退化为
  ///   「只操作本地票据」，行为与阶段 1 **逐字节一致**；
  /// - 非 null 时（阶段 2 接线）走真实商店链路，且**失败 / 取消一律安全返回**
  ///   （保持 free、不落库、不抛）——兑现离线优先红线。
  final IapClient? _iap;

  final Map<FeatureKey, FeatureRule> _matrix;
  final DateTime Function() _clock;

  Entitlement _current = Entitlement.free;

  /// 当前内存态权益（未 `load()` 时为 [Entitlement.free]）。
  Entitlement get current => _current;

  @override
  Future<Entitlement> load() async {
    _current = await _repository.read();
    return _current;
  }

  @override
  Future<void> refresh() async {
    _current = await _repository.read();
  }

  @override
  Future<void> purchaseLifetime() async {
    final IapClient? iap = _iap;
    String? jws;
    if (iap != null) {
      // 阶段 2：走真实商店链路。
      final IapPurchaseResult result = await iap.buyLifetime();
      if (result != IapPurchaseResult.success) {
        // 取消 / 失败：保持 free，不落库、不抛（失败安全）。
        return;
      }
      jws = iap.lastJws;
    }
    final Entitlement purchased = Entitlement.lifetime(
      acquiredAt: _clock(),
      productId: kIapProductIdLifetime,
    );
    await _repository.write(purchased, jws: jws);
    _current = purchased;
  }

  @override
  Future<RestoreResult> restore() async {
    final IapClient? iap = _iap;
    if (iap != null) {
      // 阶段 2：走真实商店恢复链路；三种结局各自映射，绝不抛。
      switch (await iap.restore()) {
        case IapRestoreResult.restored:
          final Entitlement restored = Entitlement.lifetime(
            acquiredAt: _clock(),
            productId: kIapProductIdLifetime,
          );
          await _repository.write(restored, jws: iap.lastJws);
          _current = restored;
          return RestoreResult.restored;
        case IapRestoreResult.nothingToRestore:
          return RestoreResult.nothingToRestore;
        case IapRestoreResult.failed:
          return RestoreResult.failed;
      }
    }
    // 阶段 1 契约（未接线内购）：只以本地票据判定。
    try {
      final Entitlement restored = await _repository.read();
      _current = restored;
      return restored.isPremium
          ? RestoreResult.restored
          : RestoreResult.nothingToRestore;
    } catch (_) {
      // 读取异常 ≠ 未购买：如实上报 failed，让 UI 提示重试而非谎报未购。
      return RestoreResult.failed;
    }
  }

  @override
  bool can(FeatureKey f) =>
      featureAllowedFor(f, _current.tier, matrix: _matrix);

  @override
  int quotaOf(FeatureKey f) =>
      featureQuotaFor(f, _current.tier, matrix: _matrix);
}
