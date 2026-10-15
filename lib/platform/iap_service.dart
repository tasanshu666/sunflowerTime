/// 内购平台层（付费墙 · 阶段 2）——StoreKit / Play Billing 的**唯一接入点**。
///
/// 职责边界（架构 §「门控单点收口」+ 依赖倒置）：
/// - 本文件是**唯一** import `in_app_purchase` 的地方；上层（域服务 / Provider / UI）
///   只依赖 `iap_contract.dart` 的纯 Dart 抽象与值对象。
/// - 对外暴露 `IapService`（单例）+ 一组**通过 `iap_service.dart` 转出**的契约类型
///   （`export` 了 `iap_contract.dart`），调用方 import 本文件即可拿到全部结果类型。
/// - **失败安全（离线优先红线）**：商店不可用、未登录、网络异常、平台抛错——
///   一律以结果对象（成功 / 取消 / 失败）返回，**绝不裸抛**、绝不让 App 崩。
/// - **构造不触平台**：单例构造、Provider 登记均**不解析插件**；插件接入发生在
///   首次 `loadProducts` / `buyLifetime` / `restore`（惰性）。
library iap_service;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import 'package:in_app_purchase/in_app_purchase.dart' as iap;

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';

// 向上转出纯 Dart 契约：调用方 import 本文件即可获得 IapProduct / IapEvent / 结果枚举。
export 'package:sunflower_time/domain/services/iap_contract.dart';

/// 恢复购买的**宽限窗口**默认值。
///
/// `restorePurchases()` 只表示「恢复请求已发出」，历史票据经插件 `purchaseStream`
/// **异步**回流。故在请求返回后再等本窗口：窗口内收到 `restored` → 恢复成功；
/// 窗口内无 → 判为 `nothingToRestore`（无购买历史）。测试可注入更短窗口。
const Duration kIapRestoreGraceDefault = Duration(milliseconds: 1500);

/// 单次购买 / 恢复调用的**超时**上限（收到终态消息即返回，正常不触发）。
const Duration kIapPurchaseTimeoutDefault = Duration(minutes: 5);

/// 平台层**归一化**后的购买消息状态（把插件 `PurchaseStatus` 收敛为平台内部枚举）。
enum IapMessageState {
  /// 交易挂起（如 Ask to Buy 待家长批准）；不产生对外事件，继续等待终态。
  pending,

  /// 购买成功。
  purchased,

  /// 恢复成功（历史票据）。
  restored,

  /// 用户取消。
  canceled,

  /// 出错。
  error,
}

/// 平台层归一化后的购买消息（`IapAdapter` 与 `IapService` 之间的内部契约）。
class IapMessage {
  /// 归一化状态。
  final IapMessageState state;

  /// 商品 ID（错误且无商品上下文时可为空串）。
  final String productId;

  /// 票据 JWS 原文（成功 / 恢复时可用，否则 null）。
  final String? jws;

  /// 错误描述（仅 [IapMessageState.error] 时有值）。
  final String? error;

  const IapMessage({
    required this.state,
    required this.productId,
    this.jws,
    this.error,
  });
}

/// 平台适配缝（**可注入假实现用于测试**）。
///
/// 把 `in_app_purchase` 的能力收敛成 4 个方法 + 1 条消息流：真实实现见
/// [InAppPurchaseAdapter]；测试注入记录型假实现即可离线驱动全部三态。
abstract class IapAdapter {
  /// 商店是否可用（未登录 / 无网络 / 平台不支持 → false）。
  Future<bool> isStoreAvailable();

  /// 查询商品详情（失败 → 空列表，绝不抛）。
  Future<List<IapProduct>> queryProducts(Set<String> productIds);

  /// 发起一次性买断；**结果经 [messages] 异步回流**（本方法完成仅表示请求已发出）。
  Future<void> startLifetimePurchase(String productId);

  /// 发起恢复购买；**结果经 [messages] 异步回流**；无历史时须发
  /// [IapMessageState.pending] 之外的空流（由 [IapService] 的宽限窗口判 `nothingToRestore`）。
  Future<void> startRestore();

  /// 平台购买消息流（广播）。`IapService` 订阅它并把消息翻译为对外 [IapEvent]。
  Stream<IapMessage> get messages;
}

/// 内购平台服务（生产单例）。
///
/// - 只实现 [IapClient]（纯 Dart 契约）；插件细节全部封装在 [IapAdapter] 实现里。
/// - [events]：把平台消息翻译为对外三态事件（广播）。
/// - 购买 / 恢复方法**返回结果枚举**，失败 / 取消一律安全返回、绝不抛。
class IapService implements IapClient {
  /// 构造点（测试可注入假 [adapter] 与更短 [restoreGrace]）。
  ///
  /// ⚠️ 构造**不解析插件**：真实 [InAppPurchaseAdapter] 仅在首次真正使用时惰性构建。
  IapService({
    IapAdapter? adapter,
    Duration restoreGrace = kIapRestoreGraceDefault,
    Duration purchaseTimeout = kIapPurchaseTimeoutDefault,
  })  : _adapterOverride = adapter,
        _restoreGrace = restoreGrace,
        _purchaseTimeout = purchaseTimeout;

  /// 全局单例（生产使用；构造安全，不触平台）。
  static final IapService _instance = IapService();

  /// 生产单例入口。
  static IapService get instance => _instance;

  /// 测试注入的适配器（可选）。
  final IapAdapter? _adapterOverride;

  final Duration _restoreGrace;
  final Duration _purchaseTimeout;

  /// 惰性解析的适配器（注入优先，否则真实实现）。
  IapAdapter? _adapterInstance;

  IapAdapter get _adapter =>
      _adapterInstance ??= (_adapterOverride ?? InAppPurchaseAdapter());

  StreamController<IapEvent> _events = StreamController<IapEvent>.broadcast();

  StreamSubscription<IapMessage>? _sub;
  Completer<IapPurchaseResult>? _pendingBuy;
  Completer<IapRestoreResult>? _pendingRestore;
  String? _lastJws;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  String? get lastJws => _lastJws;

  /// 惰性订阅平台消息（首次使用才订阅；构造期不触平台）。
  void _ensureSubscribed() {
    if (_sub != null) return;
    try {
      _sub = _adapter.messages.listen(
        _onMessage,
        onError: (Object e) => _emit(IapFailed('$e')),
      );
    } catch (e) {
      // 平台消息流不可用：退化为「无事件」，购买 / 恢复各自超时安全返回。
      _log('subscribe failed: $e');
    }
  }

  @override
  Future<List<IapProduct>> loadProducts() async {
    try {
      final bool available = await _adapter.isStoreAvailable();
      if (!available) return const <IapProduct>[];
      return await _adapter.queryProducts(<String>{kIapProductIdLifetime});
    } catch (_) {
      return const <IapProduct>[]; // 商店不可用 / 查询异常 → 空列表，绝不抛
    }
  }

  @override
  Future<IapPurchaseResult> buyLifetime() async {
    _ensureSubscribed();
    try {
      final bool available = await _adapter.isStoreAvailable();
      if (!available) {
        _emit(const IapFailed('store_unavailable'));
        return IapPurchaseResult.failed;
      }
      final Completer<IapPurchaseResult> completer =
          Completer<IapPurchaseResult>();
      _pendingBuy = completer;
      // 商品 ID 来自单点常量，禁止硬编码字符串。
      await _adapter.startLifetimePurchase(kIapProductIdLifetime);
      return await completer.future.timeout(
        _purchaseTimeout,
        onTimeout: () {
          _log('buy timeout after ${_purchaseTimeout.inSeconds}s');
          return IapPurchaseResult.failed;
        },
      );
    } catch (e) {
      // 商店不可用 / 发起失败 / 平台抛错 → 安全失败，绝不裸抛。
      _emit(IapFailed('$e'));
      return IapPurchaseResult.failed;
    } finally {
      _pendingBuy = null;
    }
  }

  @override
  Future<IapRestoreResult> restore() async {
    _ensureSubscribed();
    try {
      final bool available = await _adapter.isStoreAvailable();
      if (!available) {
        _emit(const IapFailed('store_unavailable'));
        return IapRestoreResult.failed;
      }
      final Completer<IapRestoreResult> completer =
          Completer<IapRestoreResult>();
      _pendingRestore = completer;
      await _adapter.startRestore();
      // 宽限窗口：期间收到 restored → 恢复成功；窗口内无 → 无购买历史。
      return await completer.future.timeout(
        _restoreGrace,
        onTimeout: () => IapRestoreResult.nothingToRestore,
      );
    } catch (e) {
      _emit(IapFailed('$e'));
      return IapRestoreResult.failed;
    } finally {
      _pendingRestore = null;
    }
  }

  /// 把平台消息翻译为对外事件，并完成在途的购买 / 恢复调用。
  void _onMessage(IapMessage m) {
    switch (m.state) {
      case IapMessageState.pending:
        return; // 挂起：不产生终态事件，继续等待
      case IapMessageState.purchased || IapMessageState.restored:
        if (m.jws != null && m.jws!.isNotEmpty) _lastJws = m.jws;
        _emit(IapSucceeded(productId: m.productId, jws: m.jws));
        _completeBuy(IapPurchaseResult.success);
        _completeRestore(IapRestoreResult.restored);
      case IapMessageState.canceled:
        _emit(const IapCanceled());
        _completeBuy(IapPurchaseResult.canceled);
      case IapMessageState.error:
        _emit(IapFailed(m.error ?? 'unknown'));
        _completeBuy(IapPurchaseResult.failed);
        _completeRestore(IapRestoreResult.failed);
    }
  }

  void _completeBuy(IapPurchaseResult r) {
    final Completer<IapPurchaseResult>? c = _pendingBuy;
    if (c != null && !c.isCompleted) c.complete(r);
  }

  void _completeRestore(IapRestoreResult r) {
    final Completer<IapRestoreResult>? c = _pendingRestore;
    if (c != null && !c.isCompleted) c.complete(r);
  }

  /// 安全推送事件（流已关闭时静默忽略）。
  void _emit(IapEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  /// 仅供测试：把单例恢复到「接近全新构造」的状态（并可选换入假适配器）。
  ///
  /// ⚠️ [IapService.instance] 是**跨用例复用**的全局单例：上一个用例遗留的订阅 /
  /// 在途 Completer / 事件流必须清空，否则会污染后续用例（与 `AudioService.resetForTest`
  /// 同款纪律）。本方法**同步**、不 await 任何来自旧 Zone 的 Future。
  @visibleForTesting
  void resetForTest({IapAdapter? adapter}) {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = null;
    _pendingBuy = null;
    _pendingRestore = null;
    _lastJws = null;
    _adapterInstance = adapter; // null → 下次访问按 override / 默认重建
    unawaited(_events.close());
    _events = StreamController<IapEvent>.broadcast();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[IAP] $msg');
  }
}

/// 基于 `in_app_purchase` 的**真实适配器**（生产默认）。
///
/// 把插件类型（`PurchaseDetails` / `ProductDetails` / `PurchaseStatus`）收敛为
/// 平台内部契约 [IapMessage] / [IapProduct]；调用方（[IapService]）不感知插件。
class InAppPurchaseAdapter implements IapAdapter {
  /// 可注入插件实例（测试用）；默认惰性取 [iap.InAppPurchase.instance]。
  InAppPurchaseAdapter({iap.InAppPurchase? iapInstance})
      : _iap = iapInstance;

  iap.InAppPurchase? _iap;

  iap.InAppPurchase get _instance => _iap ??= iap.InAppPurchase.instance;

  final StreamController<IapMessage> _messages =
      StreamController<IapMessage>.broadcast();
  StreamSubscription<List<iap.PurchaseDetails>>? _sub;

  /// 幂等订阅插件购买流，并把票据「完成」（`completePurchase`）以免重复投递。
  void _ensureAttached() {
    if (_sub != null) return;
    try {
      _sub = _instance.purchaseStream.listen(
        (List<iap.PurchaseDetails> list) {
          for (final iap.PurchaseDetails p in list) {
            _messages.add(_toMessage(p));
            unawaited(_completeIfNeeded(p));
          }
        },
        onError: (Object e) => _messages.add(
          IapMessage(state: IapMessageState.error, productId: '', error: '$e'),
        ),
      );
    } catch (_) {
      // 平台不可用：不订阅（[IapService] 侧各自安全返回）。
    }
  }

  /// 交易已交付 → 通知商店完成（iOS 未完成交易会被反复重投递，必须调用）。
  Future<void> _completeIfNeeded(iap.PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    if (p.status != iap.PurchaseStatus.purchased &&
        p.status != iap.PurchaseStatus.restored) {
      return;
    }
    try {
      await _instance.completePurchase(p);
    } catch (_) {
      // 完成失败：交由来电重试 / 下次启动补投递，静默降级。
    }
  }

  @override
  Stream<IapMessage> get messages {
    _ensureAttached();
    return _messages.stream;
  }

  @override
  Future<bool> isStoreAvailable() async {
    try {
      _ensureAttached();
      return await _instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    try {
      final iap.ProductDetailsResponse resp =
          await _instance.queryProductDetails(productIds);
      return resp.productDetails
          .map(_toProduct)
          .toList(growable: false);
    } catch (_) {
      return const <IapProduct>[];
    }
  }

  @override
  Future<void> startLifetimePurchase(String productId) async {
    final iap.ProductDetailsResponse resp =
        await _instance.queryProductDetails(<String>{productId});
    if (resp.productDetails.isEmpty) {
      throw StateError('product not found: $productId');
    }
    await _instance.buyNonConsumable(
      purchaseParam: iap.PurchaseParam(productDetails: resp.productDetails.first),
    );
  }

  @override
  Future<void> startRestore() => _instance.restorePurchases();

  /// 释放适配器（单例生产路径通常不需调用；测试或窗口销毁时可清理）。
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _messages.close();
  }

  static IapProduct _toProduct(iap.ProductDetails d) => IapProduct(
        id: d.id,
        title: d.title,
        description: d.description,
        price: d.price,
      );

  static IapMessage _toMessage(iap.PurchaseDetails p) {
    switch (p.status) {
      case iap.PurchaseStatus.pending:
        return IapMessage(
          state: IapMessageState.pending,
          productId: p.productID,
        );
      case iap.PurchaseStatus.purchased:
        return IapMessage(
          state: IapMessageState.purchased,
          productId: p.productID,
          jws: _jwsOf(p),
        );
      case iap.PurchaseStatus.restored:
        return IapMessage(
          state: IapMessageState.restored,
          productId: p.productID,
          jws: _jwsOf(p),
        );
      case iap.PurchaseStatus.canceled:
        return IapMessage(
          state: IapMessageState.canceled,
          productId: p.productID,
        );
      case iap.PurchaseStatus.error:
        return IapMessage(
          state: IapMessageState.error,
          productId: p.productID,
          error: p.error?.message ?? 'purchase_error',
        );
    }
  }

  /// 取票据服务端复验串（JWS 原文）；空串视作无。
  static String? _jwsOf(iap.PurchaseDetails p) {
    final String v = p.verificationData.serverVerificationData;
    return v.isEmpty ? null : v;
  }
}
