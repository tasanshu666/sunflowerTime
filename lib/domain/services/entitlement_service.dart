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
import 'package:sunflower_time/core/constants/redeem_public_key.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';

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

/// 🐞 **仅调试**：把内存态权益**原地**覆盖（不落库、不写票据，重启即失效）。
///
/// ## 为什么需要这条独立接口（F142 真 Bug 修复）
///
/// 权益态在运行期存在**两个独立内存源**：
///  1. `entitlementProvider`（`core/di/providers.dart`）—— **UI 层**门控读取的唯一来源
///     （花园页扩容按钮亮不亮、报告段要不要取热力图…）；
///  2. [`MatrixEntitlementService`] 的私有字段 `_current` —— **领域层**判定
///     （[EntitlementService.can] / [EntitlementService.quotaOf]）读取的唯一来源
///     （`PlantGrowthService.expandPot` 的花盆容量上限就卡在这里）。
///
/// 旧版调试开关只写了 ①（外加开关布尔值），完全没碰 ②：于是 UI 把扩容按钮点亮，
/// 一按就落到域层 `quotaOf(gardenPotCapacity)`，仍按 `free` 的 4 盆判定 →
/// 「看着是会员，一按就被打回」（玄参真机复现）。
///
/// ## 为什么是**独立接口**而不是加进 [EntitlementService]
///
/// [EntitlementService] 有测试 Fake（`test/m3/plant_perk_gating_test.dart` 的
/// `_FixedTierEntitlementService implements EntitlementService`）。给它加方法会让
/// 所有 Fake 编译失败。故沿用本项目既有的**能力扩展模式**（如
/// `implements FocusRangeQuery`）：调用方用 `is DebugEntitlementOverride` 做能力探测，
/// 不实现本接口的 Fake 自动降级为「无调试能力」，零编译影响。
abstract interface class DebugEntitlementOverride {
  /// 把内存态权益覆盖为 [entitlement]（**同步、原地**）。
  ///
  /// 🔴 与 [EntitlementService.purchaseLifetime] 的区别：本方法**绝不调**
  /// `_repository.write`，不产生任何票据、不触碰安全区存储 —— 纯调试态，
  /// 进程重启（或任意一次 [EntitlementService.load] / [EntitlementService.refresh]）
  /// 即被真实票据覆盖回真实档位。
  void debugOverrideCurrent(Entitlement entitlement);
}

/// 激活码激活的结果（Android 官网直供版 · 六态，失败原因分得足够细以给对提示语）。
///
/// 与 [RedeemCodeError]（验签层四态）的映射由 [RedeemCodeActivator.activate] 收口：
/// 验签层的 [RedeemCodeError.malformed] → [malformedCode]，
/// [RedeemCodeError.badSignature] / [RedeemCodeError.unsupportedVersion] → [invalidCode]，
/// [RedeemCodeError.notConfigured] → [notConfigured]。
enum RedeemActivationResult {
  /// 首次激活成功：票据已落库，内存态已切 premium。
  activated,

  /// 当前已是 premium（幂等返回，**不重复写票据**）。
  alreadyPremium,

  /// 验签失败：签名不匹配 / 版本不受支持 —— 码本身不对（或已被改成无效）。
  invalidCode,

  /// 格式 / 编码错误：长度不对、不是 Base64URL 等 —— 用户大概率没复制全。
  malformedCode,

  /// 客户端公钥未配置（发布事故，不是用户的错）。
  notConfigured,

  /// 落库异常：票据没写成功，内存态**保持 free**（不半成功）。
  failed,
}

/// 🔑 **激活码激活能力**（Android 官网直供版）—— 与 [DebugEntitlementOverride] 同款的
/// **能力扩展模式**，理由完全一致：
///
/// [EntitlementService] 在测试里有 29 个 Fake 实现（见 [DebugEntitlementOverride] 的
/// 说明）。给它加方法 → 全部 Fake 编译失败。故此处**新开一个独立
/// `abstract interface class`**，由 [`MatrixEntitlementService`] 额外 `implements`；
/// 调用方用 `is RedeemCodeActivator` 做运行时能力探测，不实现本接口的 Fake 自动降级为
/// 「无激活能力」（UI 侧退化成「请稍后重试」），零编译影响、零行为变化。
///
/// ## 为什么不是「购买」（`purchaseLifetime`）的一个分支
///
/// `purchaseLifetime` 走的是**商店链路**（StoreKit / Play Billing），失败即静默保持
/// free；激活码是**离线验签 + 落库**，且需要把「为什么失败」如实报给用户（格式错 vs
/// 签名错 vs 未配置的提示语完全不同）。两者的返回值语义不一样，混在一个无返回值的
/// 方法里会丢掉这些信息，故单独成接口。
abstract interface class RedeemCodeActivator {
  /// 用一枚激活码解锁 premium（**绝不抛异常**）。
  ///
  /// 语义契约：
  ///  1. 已是 premium → [RedeemActivationResult.alreadyPremium]（幂等，**不写票据**）；
  ///  2. 验签不通过 → 按原因返回 [RedeemActivationResult.malformedCode] /
  ///     [RedeemActivationResult.invalidCode] / [RedeemActivationResult.notConfigured]，
  ///     **票据不变、内存态不变**；
  ///  3. 验签通过 → 写入 `Entitlement.lifetime(...)` 票据并刷新内存态 →
  ///     [RedeemActivationResult.activated]；
  ///  4. 落库抛异常 → [RedeemActivationResult.failed]，且内存态**保持 free**。
  Future<RedeemActivationResult> activate(String code);
}

/// 基于**本地票据 + 门控矩阵**的纯逻辑判定实现。
///
/// - 内存态 [_current] 默认 [Entitlement.free]（安全默认，构造即可用，不触平台）；
/// - 判定完全由注入的 [matrix]（默认 [`kEntitlementMatrix`]）驱动；
/// - [clock] 可注入以便单测固定时间（默认系统时钟）。
///
/// ⚠️ 阶段 1 矩阵全放开，故对 free 用户 [can] 亦返回 true —— 行为零变化。
///
/// F142：额外实现 [DebugEntitlementOverride]，让仅调试用的「会员模式」开关
/// （`debugSetPremiumUnlock`）能同时覆盖**领域层**判定源。
///
/// Android 官网直供版：额外实现 [RedeemCodeActivator]，用**离线验签的激活码**替代
/// IAP 完成解锁（iOS 链路一字未动，仍走 [_iap]）。
class MatrixEntitlementService
    implements EntitlementService, DebugEntitlementOverride, RedeemCodeActivator {
  MatrixEntitlementService({
    required EntitlementRepository repository,
    IapClient? iap,
    Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
    DateTime Function()? clock,
    RedeemCodeVerifier? redeemVerifier,
  })  : _repository = repository,
        _iap = iap,
        _matrix = matrix,
        _clock = clock ?? DateTime.now,
        _injectedRedeemVerifier = redeemVerifier;

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

  /// 测试 / 高阶层注入的验签器（可为 null → 用生产公钥常量惰性构造）。
  ///
  /// 🔴 惰性铁律：生产路径下**只有真的调用 [activate] 时**才构造验签器
  /// （构造本身很便宜，但这与既有 `iap` 的「构造不触平台」纪律保持一致）。
  final RedeemCodeVerifier? _injectedRedeemVerifier;

  /// 惰性构造的生产验签器缓存（公钥取 [kRedeemPublicKeyBase64]）。
  RedeemCodeVerifier? _lazyRedeemVerifier;

  /// 生效的验签器：注入优先，否则用生产公钥常量惰性构造。
  ///
  /// 公钥为空串时 [RedeemCodeVerifier.verify] 自然返回 `notConfigured` ——
  /// 故「未配置公钥」不需要额外的分支判断，也不会有任何误放。
  RedeemCodeVerifier get _redeemVerifier =>
      _injectedRedeemVerifier ??
      (_lazyRedeemVerifier ??=
          RedeemCodeVerifier(publicKeyBase64: kRedeemPublicKeyBase64));

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

  /// 🐞 仅调试：把内存态 [_current] 原地覆盖为 [entitlement]。
  ///
  /// 🔴 **与 [purchaseLifetime] 的关键区别**：本方法**不调 `_repository.write`**，
  /// 不写票据、不碰安全区存储；因此它只会影响**当前进程**的判定结果
  /// （[can] / [quotaOf] 立即生效），重启即失效。
  @override
  void debugOverrideCurrent(Entitlement entitlement) {
    _current = entitlement;
  }

  /// 🔑 用激活码解锁 premium（Android 官网直供版；**全程不抛异常**）。
  ///
  /// 与 [purchaseLifetime] 的分工：
  ///  · [purchaseLifetime] = 商店链路（StoreKit / Play Billing），失败静默保持 free；
  ///  · 本方法 = **离线验签 + 本地落库**，失败必须把原因如实交回 UI（提示语不同）。
  ///
  /// 顺序（每一步都是上一步的守卫）：
  ///  1. 已是 premium → [RedeemActivationResult.alreadyPremium]（幂等；**绝不重复写票据**，
  ///     避免无谓的安全区写放大，也避免覆盖掉最初的 `acquiredAt`）；
  ///  2. 验签（[RedeemCodeVerifier.verify]，自身不抛）→ 按四类原因映射；
  ///  3. 通过 → 写票据（`jws: null`：激活码没有 Apple JWS，凭据是**已验签的码本身**；
  ///     `redeemSerial: serial`：把签发序号一并落库，供售后对账 / 区分来源），
  ///     写成功后才刷新内存态 —— 顺序刻意如此：**先落库、后改内存**，
  ///     保证「内存态 premium ⇒ 票据一定已持久化」，重启不会退回 free；
  ///  4. 落库抛异常 → [RedeemActivationResult.failed]，内存态**保持 free**（不半成功）。
  @override
  Future<RedeemActivationResult> activate(String code) async {
    try {
      if (_current.isPremium) {
        return RedeemActivationResult.alreadyPremium;
      }

      final RedeemCodeResult result = await _redeemVerifier.verify(code);
      switch (result) {
        case RedeemCodeValid(:final int serial):
          final Entitlement activated = Entitlement.lifetime(
            acquiredAt: _clock(),
            productId: kIapProductIdLifetime,
            // 把签发序号一并落库（售后对账 / 区分「官网码」与「iOS IAP」）；
            // 这是**唯一**会写 redeemSerial 的路径，IAP 两个方法保持 null。
            redeemSerial: serial,
          );
          try {
            await _repository.write(activated, jws: null);
          } catch (_) {
            // 落库失败：内存态保持 free（绝不半成功 —— 否则重启即「掉档」）。
            return RedeemActivationResult.failed;
          }
          _current = activated;
          return RedeemActivationResult.activated;
        case RedeemCodeInvalid(error: final RedeemCodeError error):
          switch (error) {
            case RedeemCodeError.malformed:
              return RedeemActivationResult.malformedCode;
            case RedeemCodeError.badSignature:
            case RedeemCodeError.unsupportedVersion:
              return RedeemActivationResult.invalidCode;
            case RedeemCodeError.notConfigured:
              return RedeemActivationResult.notConfigured;
          }
      }
    } catch (_) {
      // 兜底（验签器已保证不抛）：任何意外都报 failed，绝不抛给 UI。
      return RedeemActivationResult.failed;
    }
  }
}
