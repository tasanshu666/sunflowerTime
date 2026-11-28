/// App 内支付宝解锁状态机（Android 官网直供版）——**纯 Dart，零 Flutter / 零 http /
/// 零 MethodChannel**。
///
/// ## 为什么它是「真源」
/// 增量架构设计 §4.1 把本文件标为真源：六态 enum、三个端口抽象、数据载体与编排
/// 控制器全部单点定义在此。data / platform 层只 `implements` 端口，UI 只驱动控制器。
///
/// ## 六态（§3.1）
/// `awaitingPayment` → `paidAwaitingCode` → `issuing` → `unlocked`，
/// 另有 `expired`（超时关单）与 `duplicate`（幂等回读，不重复写票据）。
///
/// ## 三条不可破的红线
///  1. **同步结果不是发货依据**：`resultStatus=9000` 只当「可能已付」信号，
///     必须轮询服务端 `redeem` 拿到码并通过既有 `RedeemCodeActivator.activate()` 验签落库；
///  2. **失败安全**：平台 / 网络 / 验签失败一律返回错误对象，**绝不裸抛**；
///  3. **不碰既有解锁通道**：只复用 `RedeemCodeActivator`，不改 `IapClient` 契约 /
///     `purchaseLifetime` / `restore` / `can` / `quotaOf`。
///
/// [clock] 与 [delay] 可注入，单测能用假时钟 / 零延迟秒级跑完整状态机与轮询退避。
library alipay_unlock_controller;

import 'package:sunflower_time/core/constants/alipay_endpoints.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart'
    show RedeemActivationResult, RedeemCodeActivator;

/// 解锁流程的六个用户可见状态（文案 key 由 ARB 收口，见 §3.1）。
enum AlipayUnlockPhase {
  /// 待支付：订单已创建 / 用户取消 / 网络失败回到本态。
  awaitingPayment,

  /// 已支付待发码：同步「可能已付」或 `redeem` 202 pending，后台轮询中。
  paidAwaitingCode,

  /// 发码中：拿到 `redeem_code`，正在本地验签 + 写安全区（按钮禁用防重）。
  issuing,

  /// 已解锁：`activate()` 返回 `activated`。
  unlocked,

  /// 超时关单：`redeem` 200 unpaid / 404 / 403 / 本地 TTL 到期。
  expired,

  /// 重复回调（幂等）：`activate()` 返回 `alreadyPremium`，不重复写票据。
  duplicate,
}

/// 客户端内部错误码（服务端 `error` 字段 + 网络层异常的统一映射，§5.5）。
enum AlipayErrorCode {
  /// 网络层异常（超时 / DNS / TLS）——客户端内部码，非服务端返回；行为同 429。
  networkError,

  /// 429 RATE_LIMITED：保持当前态，退避 ≥7s。
  rateLimited,

  /// 503 POOL_EXHAUSTED：不调起支付宝，联系客服。
  poolExhausted,

  /// 404 ORDER_NOT_FOUND：转人工。
  orderNotFound,

  /// 403 CLAIM_TOKEN_MISMATCH：不重试，联系客服。
  claimTokenMismatch,

  /// 400 BAD_REQUEST：固定 android 不该发生，报 bug。
  badRequest,

  /// 500 SERVER_ERROR：可重试 1–2 次。
  serverError,

  /// 验签失败 / 落库失败：保留 pending，保持 `paidAwaitingCode`。
  verificationFailed,

  /// 6001 用户取消：回待支付，保留 pending 供下次补单。
  payCanceled,

  /// 6002 / 4000 / 其它同步失败：回待支付，可重试。
  payFailed,

  /// 非 Android 平台（`AlipayBridge` 硬门控返回 unsupported）。
  unsupported,

  /// 重入保护：上一轮还在跑，新调用直接返回本码，不重复下单。
  busy,

  /// 没有 pending 订单（`resumePending` 时安全区为空）。
  noPendingOrder,

  /// 服务端信封 / 必填字段解析失败。
  malformedResponse,
}

/// 结构化失败对象（data 层「失败返回错误对象」的载体，**不是异常**）。
class AlipayFailure {
  const AlipayFailure({
    required this.code,
    this.requestId,
    this.message = '',
  });

  /// 统一内部错误码。
  final AlipayErrorCode code;

  /// 服务端 `X-Request-Id`，透出给客服排障用。
  final String? requestId;

  /// 服务端 `message`（**仅排障，App 不解析、不展示**）。
  final String message;

  @override
  String toString() => 'AlipayFailure($code, requestId: $requestId)';
}

/// `POST /v1/order/create` 成功数据。
///
/// 失败时 [error] 非空且各字段为空串 / 默认值——调用方先看 [error]，不靠异常。
class CreateOrderData {
  const CreateOrderData({
    this.outTradeNo = '',
    this.claimToken = '',
    this.orderString = '',
    this.amount = '',
    this.expiresIn = kAlipayOrderTtlSeconds,
    this.error,
    this.requestId,
  });

  final String outTradeNo;
  final String claimToken;

  /// RSA2 签好的下单串：原样喂给支付宝 SDK，不解析、不修改。
  final String orderString;

  /// 服务端金额串 `"49.90"`，仅展示校验用，客户端**从不回传**。
  final String amount;

  /// 订单有效期（秒）。
  final int expiresIn;

  /// 失败对象（null = 成功）。
  final AlipayFailure? error;

  /// `X-Request-Id`。
  final String? requestId;

  /// 必填字段是否齐全（下单成功的判据）。
  bool get isValid =>
      outTradeNo.isNotEmpty &&
      claimToken.isNotEmpty &&
      orderString.isNotEmpty;
}

/// `GET /v1/order/redeem` 的三态之一。
enum RedeemStatus {
  /// 200 + `{status:"issued"}`：已发码（幂等：同订单永远同码同 serial）。
  issued,

  /// 202 + `{status:"pending"}`：回调可能还在路上，重试。
  pending,

  /// 200 + `{status:"unpaid"}`：未付款 / 已超时关单。
  unpaid,
}

/// `GET /v1/order/redeem` 返回数据（失败时 [error] 非空）。
class RedeemData {
  const RedeemData({
    this.status = RedeemStatus.unpaid,
    this.redeemCode,
    this.serial,
    this.error,
    this.requestId,
  });

  final RedeemStatus status;
  final String? redeemCode;
  final int? serial;
  final AlipayFailure? error;
  final String? requestId;

  /// 成功拿到码（可进入 `issuing`）。
  bool get isIssued =>
      error == null && status == RedeemStatus.issued && (redeemCode?.isNotEmpty ?? false);
}

/// 安全区里保存的**最小补单凭据**（只有三键，见 design §4.1）。
///
/// 🔴 不存 `order_string`：支付宝唤起串是一次性签名数据，补单走 `redeem` 而非重付。
class PendingOrder {
  const PendingOrder({
    required this.outTradeNo,
    required this.claimToken,
    required this.createdAt,
  });

  final String outTradeNo;
  final String claimToken;
  final DateTime createdAt;

  /// 本地 TTL 兜底：创建时间距今 ≥ [expiresIn] 秒即视为关单。
  bool isExpired(int expiresIn, DateTime now) =>
      now.difference(createdAt).inSeconds >= expiresIn;
}

/// 支付宝 SDK 同步返回结果的归一化载体。
class AlipayPayResult {
  const AlipayPayResult({
    required this.resultStatus,
    this.memo,
    this.result,
  });

  /// 归一化后的 `resultStatus`（已剥掉 `{` / `}` 容错）。
  final String resultStatus;
  final String? memo;
  final String? result;

  /// 同步返回中「可能已付」的五种码（§1.4）：**只作信号，不作发货依据**。
  static const Set<String> kMayPaidStatuses = <String>{
    '9000',
    '8000',
    '6004',
    '6006',
    '5000',
  };

  /// 从 MethodChannel 的原始 Map 构造（对用户 / 插件的脏输出做容错）。
  ///
  /// `{}` / `{9000}` 这类带花括号的返回会被剥成 `9000`；空串 / null 收敛为 `4000`。
  factory AlipayPayResult.fromMap(Map<String, dynamic> map) {
    String normalize(Object? value) {
      String text = (value ?? '').toString().trim();
      if (text.startsWith('{')) text = text.substring(1);
      if (text.endsWith('}')) text = text.substring(0, text.length - 1);
      text = text.trim();
      return text.isEmpty ? '4000' : text;
    }

    return AlipayPayResult(
      resultStatus: normalize(map['resultStatus']),
      memo: map['memo']?.toString(),
      result: map['result']?.toString(),
    );
  }

  /// 是否「可能已付」→ 进入轮询。
  bool get isMayPaid => kMayPaidStatuses.contains(resultStatus);

  /// 是否用户中途取消（6001，无异步通知）。
  bool get isCanceled => resultStatus == '6001';

  /// 是否失败 / 未安装 / 异常（6002 / 4000 / 其它）。
  bool get isFailed => !isMayPaid && !isCanceled;
}

/// 控制器对外返回的结果（失败也返回结果对象，永不裸抛）。
class AlipayUnlockResult {
  const AlipayUnlockResult({
    required this.phase,
    this.serial,
    this.duplicate = false,
    this.error,
    this.requestId,
  });

  /// 首次解锁成功。
  factory AlipayUnlockResult.unlocked({int? serial}) => AlipayUnlockResult(
        phase: AlipayUnlockPhase.unlocked,
        serial: serial,
      );

  /// 幂等回读：同一码同一 serial，不重复写票据。
  factory AlipayUnlockResult.duplicate({int? serial}) => AlipayUnlockResult(
        phase: AlipayUnlockPhase.duplicate,
        serial: serial,
        duplicate: true,
      );

  /// 回到待支付（同步失败 / 取消 / pool 空）。
  factory AlipayUnlockResult.awaiting({AlipayErrorCode? error, String? requestId}) =>
      AlipayUnlockResult(
        phase: AlipayUnlockPhase.awaitingPayment,
        error: error,
        requestId: requestId,
      );

  /// 仍待发码（轮询上限内 202 / 退避耗尽）。
  factory AlipayUnlockResult.polling({AlipayErrorCode? error, String? requestId}) =>
      AlipayUnlockResult(
        phase: AlipayUnlockPhase.paidAwaitingCode,
        error: error,
        requestId: requestId,
      );

  /// 超时关单。
  factory AlipayUnlockResult.expired({
    AlipayErrorCode? error,
    String? requestId,
  }) =>
      AlipayUnlockResult(
        phase: AlipayUnlockPhase.expired,
        error: error,
        requestId: requestId,
      );

  /// 通用失败（可指定落点状态）。
  factory AlipayUnlockResult.failed({
    required AlipayErrorCode error,
    required AlipayUnlockPhase phase,
    String? requestId,
  }) =>
      AlipayUnlockResult(
        phase: phase,
        error: error,
        requestId: requestId,
      );

  final AlipayUnlockPhase phase;
  final int? serial;
  final bool duplicate;
  final AlipayErrorCode? error;
  final String? requestId;

  /// `unlocked` / `duplicate` 都算「已解锁」（UI 刷新 entitlementProvider）。
  bool get isUnlocked =>
      phase == AlipayUnlockPhase.unlocked || phase == AlipayUnlockPhase.duplicate;

  /// 是否成功（无错误对象）。
  bool get isOk => error == null;
}

/// 端口①：下单 + 领取（data 层实现，Android-only 实例化）。
abstract interface class AlipayApi {
  /// `POST /v1/order/create`（body 只有 platform / app_version / device_hash，**绝不含 amount**）。
  Future<CreateOrderData> createOrder({
    required String platform,
    required String appVersion,
    required String deviceHash,
  });

  /// `GET /v1/order/redeem`（轮询就是这个接口，无独立 status 接口）。
  Future<RedeemData> redeem({
    required String outTradeNo,
    required String claimToken,
  });
}

/// 端口②：pending 凭据的安全区持久化。
abstract interface class PendingOrderStore {
  Future<void> save(PendingOrder pending);
  Future<PendingOrder?> load();
  Future<void> clear();
}

/// 端口③：唤起支付宝 App（platform 层实现，`Platform.isAndroid` 硬门控）。
abstract interface class AlipayPayBridge {
  Future<AlipayPayResult> pay(String orderString);
  Future<bool> isInstalled();
}

/// 六态编排控制器（纯 Dart 状态机）。
///
/// 依赖全部是抽象端口；[clock] / [delay] 注入后可在毫秒级跑完 12 次 7s 轮询。
/// 所有公开方法都带**重入闸门**：上一轮未结束的新调用返回 `busy`，绝不重复下单。
class AlipayUnlockController {
  AlipayUnlockController({
    required AlipayApi api,
    required PendingOrderStore pending,
    required AlipayPayBridge bridge,
    required RedeemCodeActivator activator,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  })  : _api = api,
        _pending = pending,
        _bridge = bridge,
        _activator = activator,
        _clock = clock ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  final AlipayApi _api;
  final PendingOrderStore _pending;
  final AlipayPayBridge _bridge;
  final RedeemCodeActivator _activator;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  AlipayUnlockPhase _phase = AlipayUnlockPhase.awaitingPayment;
  int _pollCount = 0;
  bool _running = false;

  /// 当前状态（UI 文案单点来源）。
  AlipayUnlockPhase get phase => _phase;

  /// 本轮已轮询次数（测试 / 排障用）。
  int get pollCount => _pollCount;

  /// 完整购买流程：下单 → 存 pending → 唤起收银台 → 同步信号 → 轮询发码。
  Future<AlipayUnlockResult> start({
    required String deviceHash,
    required String appVersion,
  }) =>
      _run(() async {
        _setPhase(AlipayUnlockPhase.awaitingPayment);
        _pollCount = 0;

        final CreateOrderData order = await _api.createOrder(
          platform: kAlipayPlatformAndroid,
          appVersion: appVersion,
          deviceHash: deviceHash,
        );
        final AlipayFailure? createError = order.error;
        if (createError != null) {
          // 503 池空绝不调起支付宝；其余也回待支付，由 UI 给对应提示。
          _setPhase(AlipayUnlockPhase.awaitingPayment);
          return AlipayUnlockResult.failed(
            error: createError.code,
            phase: AlipayUnlockPhase.awaitingPayment,
            requestId: createError.requestId,
          );
        }
        if (!order.isValid) {
          return AlipayUnlockResult.failed(
            error: AlipayErrorCode.malformedResponse,
            phase: AlipayUnlockPhase.awaitingPayment,
            requestId: order.requestId,
          );
        }

        await _pending.save(
          PendingOrder(
            outTradeNo: order.outTradeNo,
            claimToken: order.claimToken,
            createdAt: _clock(),
          ),
        );

        final AlipayPayResult payResult = await _bridge.pay(order.orderString);
        return _onPayResult(payResult);
      });

  /// 回前台 / 「已付款但未解锁？重新领取」：从安全区读 pending 立即补查一次。
  Future<AlipayUnlockResult> resumePending() =>
      _run(() async {
        final PendingOrder? pending = await _pending.load();
        if (pending == null ||
            pending.outTradeNo.isEmpty ||
            pending.claimToken.isEmpty) {
          _setPhase(AlipayUnlockPhase.awaitingPayment);
          return AlipayUnlockResult.failed(
            error: AlipayErrorCode.noPendingOrder,
            phase: AlipayUnlockPhase.awaitingPayment,
          );
        }
        if (pending.isExpired(kAlipayOrderTtlSeconds, _clock())) {
          _setPhase(AlipayUnlockPhase.expired);
          await _pending.clear();
          return AlipayUnlockResult.expired();
        }
        _pollCount = 0;
        _setPhase(AlipayUnlockPhase.paidAwaitingCode);
        return _pollRedeem(pending: pending);
      });

  /// UI 的通用重试：语义等同补单（有 pending 就查，没有就回待支付）。
  Future<AlipayUnlockResult> retry() => resumePending();

  /// 同步返回码映射（§1.4）：9000 也**只**进轮询，绝不直接解锁。
  Future<AlipayUnlockResult> _onPayResult(AlipayPayResult result) async {
    if (result.isMayPaid) {
      _setPhase(AlipayUnlockPhase.paidAwaitingCode);
      return _pollRedeem();
    }
    _setPhase(AlipayUnlockPhase.awaitingPayment);
    return AlipayUnlockResult.awaiting(
      error: result.isCanceled
          ? AlipayErrorCode.payCanceled
          : AlipayErrorCode.payFailed,
    );
  }

  /// 轮询：首次立即 → 7s 间隔 → 最多 12 次；429 / 网络异常同样退避 7s。
  Future<AlipayUnlockResult> _pollRedeem({PendingOrder? pending}) async {
    final PendingOrder? order = pending ?? await _pending.load();
    if (order == null) {
      return AlipayUnlockResult.failed(
        error: AlipayErrorCode.noPendingOrder,
        phase: AlipayUnlockPhase.paidAwaitingCode,
      );
    }

    for (int i = 0; i < kAlipayMaxPollCount; i++) {
      _pollCount = i + 1;
      final RedeemData data = await _api.redeem(
        outTradeNo: order.outTradeNo,
        claimToken: order.claimToken,
      );
      final AlipayFailure? failure = data.error;
      if (failure != null) {
        switch (failure.code) {
          case AlipayErrorCode.rateLimited:
          case AlipayErrorCode.networkError:
            if (i + 1 < kAlipayMaxPollCount) {
              await _delay(kAlipayPollInterval);
              continue;
            }
            return AlipayUnlockResult.polling(
              error: failure.code,
              requestId: failure.requestId,
            );
          case AlipayErrorCode.serverError:
            // 500 可重试 1–2 次；耗尽后如实报错，保持当前态。
            if (i + 1 < kAlipayMaxPollCount) {
              await _delay(kAlipayPollInterval);
              continue;
            }
            return AlipayUnlockResult.failed(
              error: AlipayErrorCode.serverError,
              phase: AlipayUnlockPhase.paidAwaitingCode,
              requestId: failure.requestId,
            );
          case AlipayErrorCode.claimTokenMismatch:
          case AlipayErrorCode.orderNotFound:
            _setPhase(AlipayUnlockPhase.expired);
            await _pending.clear();
            return AlipayUnlockResult.expired(
              error: failure.code,
              requestId: failure.requestId,
            );
          case AlipayErrorCode.poolExhausted:
          case AlipayErrorCode.badRequest:
            _setPhase(AlipayUnlockPhase.awaitingPayment);
            return AlipayUnlockResult.failed(
              error: failure.code,
              phase: AlipayUnlockPhase.awaitingPayment,
              requestId: failure.requestId,
            );
          default:
            return AlipayUnlockResult.failed(
              error: failure.code,
              phase: AlipayUnlockPhase.paidAwaitingCode,
              requestId: failure.requestId,
            );
        }
      }

      switch (data.status) {
        case RedeemStatus.issued:
          _setPhase(AlipayUnlockPhase.issuing);
          final RedeemActivationResult activation =
              await _activator.activate(data.redeemCode ?? '');
          if (activation == RedeemActivationResult.activated ||
              activation == RedeemActivationResult.alreadyPremium) {
            final bool duplicate =
                activation == RedeemActivationResult.alreadyPremium;
            _setPhase(duplicate
                ? AlipayUnlockPhase.duplicate
                : AlipayUnlockPhase.unlocked);
            await _pending.clear();
            return duplicate
                ? AlipayUnlockResult.duplicate(serial: data.serial)
                : AlipayUnlockResult.unlocked(serial: data.serial);
          }
          // 验签 / 落库失败：绝不谎报「码无效」，保留 pending 回 paidAwaitingCode。
          _setPhase(AlipayUnlockPhase.paidAwaitingCode);
          return AlipayUnlockResult.failed(
            error: AlipayErrorCode.verificationFailed,
            phase: AlipayUnlockPhase.paidAwaitingCode,
            requestId: data.requestId,
          );
        case RedeemStatus.pending:
          if (i + 1 < kAlipayMaxPollCount) {
            await _delay(kAlipayPollInterval);
            continue;
          }
          // 上限后不无限轮询，提示「重新领取」，状态仍是 paidAwaitingCode。
          return AlipayUnlockResult.polling(requestId: data.requestId);
        case RedeemStatus.unpaid:
          // 服务端只在「已超时 / 未付款」时返回 200 unpaid（main.py._is_expired），
          // 故直接进 expired；同时本地 TTL 在 resumePending 也兜一层。
          _setPhase(AlipayUnlockPhase.expired);
          await _pending.clear();
          return AlipayUnlockResult.expired(requestId: data.requestId);
      }
    }
    // for 循环每个分支都已返回；此行仅为满足编译器穷尽性。
    return AlipayUnlockResult.polling();
  }

  /// 重入闸门：上一轮未结束时返回 busy，不重复下单 / 不重复轮询。
  Future<AlipayUnlockResult> _run(
    Future<AlipayUnlockResult> Function() body,
  ) async {
    if (_running) {
      return AlipayUnlockResult.failed(
        error: AlipayErrorCode.busy,
        phase: _phase,
      );
    }
    _running = true;
    try {
      return await body();
    } catch (_) {
      // 终极失败安全：端口契约已保证不抛，这里再兜一层（绝不把异常抛给 UI）。
      return AlipayUnlockResult.failed(
        error: AlipayErrorCode.serverError,
        phase: _phase,
      );
    } finally {
      _running = false;
    }
  }

  void _setPhase(AlipayUnlockPhase next) => _phase = next;
}
