/// App 内支付宝 HTTP 客户端（Android-only 实例化）。
///
/// 严格按 `server/app/main.py` **逐字实读**的接口契约（增量架构设计 §5）：
///  - `POST /v1/order/create`：body 只有 `platform` / `app_version` / `device_hash`，
///    **绝不含 amount**（服务端 `CreateOrderRequest.extra="ignore"`，金额由服务端定死）；
///  - `GET /v1/order/redeem`：query 带 `out_trade_no` / `claim_token`；
///    三态必须区分 `200 issued` / `202 pending` / `200 unpaid`；
///  - 统一信封 `{ok,data,error,message}` + `X-Request-Id` 透出；
///  - **失败返回错误对象，不裸抛**：网络 / 超时 / 脏 JSON 都收敛成带错误码的数据对象。
library alipay_api_client;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sunflower_time/core/constants/alipay_endpoints.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart'
    show
        AlipayApi,
        AlipayErrorCode,
        AlipayFailure,
        CreateOrderData,
        RedeemData,
        RedeemStatus;

/// `AlipayApi` 的 HTTP 实现。
///
/// [client] 可注入（`package:http/testing.dart` 的 `MockClient`）⇒ 单测零真实网络。
class AlipayApiClient implements AlipayApi {
  AlipayApiClient({
    http.Client? client,
    String baseUrl = kAlipayApiBaseUrl,
    Duration timeout = kAlipayRequestTimeout,
  })  : _http = client ?? http.Client(),
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _timeout = timeout;

  final http.Client _http;
  final String _baseUrl;
  final Duration _timeout;

  @override
  Future<CreateOrderData> createOrder({
    required String platform,
    required String appVersion,
    required String deviceHash,
  }) async {
    try {
      final Uri uri = Uri.parse('$_baseUrl$kAlipayCreateOrderPath');
      final http.Response response = await _http
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            // 🔴 body 只有三个键——Amount 绝不进包 / 绝不回传。
            body: jsonEncode(<String, String>{
              'platform': platform,
              'app_version': appVersion,
              'device_hash': deviceHash,
            }),
          )
          .timeout(_timeout);

      final _Envelope envelope = _parseEnvelope(response);
      if (!envelope.ok) {
        return CreateOrderData(
          error: _failureOf(envelope),
          requestId: envelope.requestId,
        );
      }
      final Map<String, dynamic> data = envelope.data ?? <String, dynamic>{};
      return CreateOrderData(
        outTradeNo: _stringOf(data['out_trade_no']),
        claimToken: _stringOf(data['claim_token']),
        orderString: _stringOf(data['order_string']),
        amount: _stringOf(data['amount']),
        expiresIn: _intOf(data['expires_in']) ?? kAlipayOrderTtlSeconds,
        requestId: envelope.requestId,
      );
    } catch (_) {
      // 超时 / DNS / TLS / 脏响应：统一 NETWORK_ERROR（行为同 429）。
      return const CreateOrderData(
        error: AlipayFailure(code: AlipayErrorCode.networkError),
      );
    }
  }

  @override
  Future<RedeemData> redeem({
    required String outTradeNo,
    required String claimToken,
  }) async {
    try {
      final Uri uri = Uri.parse('$_baseUrl$kAlipayRedeemPath').replace(
        queryParameters: <String, String>{
          'out_trade_no': outTradeNo,
          'claim_token': claimToken,
        },
      );
      final http.Response response =
          await _http.get(uri, headers: const <String, String>{
        'Accept': 'application/json',
      }).timeout(_timeout);

      final _Envelope envelope = _parseEnvelope(response);
      if (!envelope.ok) {
        return RedeemData(
          error: _failureOf(envelope),
          requestId: envelope.requestId,
        );
      }

      final Map<String, dynamic> data = envelope.data ?? <String, dynamic>{};
      final String status = _stringOf(data['status']);
      switch (status) {
        case 'issued':
          return RedeemData(
            status: RedeemStatus.issued,
            redeemCode: _stringOf(data['redeem_code']),
            serial: _intOf(data['serial']),
            requestId: envelope.requestId,
          );
        case 'pending':
          // 服务端 202 pending；这里按 status 字符串判定，对 200/202 都容错。
          return RedeemData(
            status: RedeemStatus.pending,
            requestId: envelope.requestId,
          );
        case 'unpaid':
          return RedeemData(
            status: RedeemStatus.unpaid,
            requestId: envelope.requestId,
          );
        default:
          return RedeemData(
            error: AlipayFailure(
              code: AlipayErrorCode.malformedResponse,
              requestId: envelope.requestId,
            ),
            requestId: envelope.requestId,
          );
      }
    } catch (_) {
      return const RedeemData(
        error: AlipayFailure(code: AlipayErrorCode.networkError),
      );
    }
  }

  /// 统一信封解析（**不抛**：脏响应返回 `ok:false` + `malformedResponse`）。
  _Envelope _parseEnvelope(http.Response response) {
    final String? requestId = response.headers['x-request-id'];
    // 🔴 必须按 UTF-8 解 bodyBytes，不能用 response.body：后者在无 Content-Type
    // charset 时按 latin1 解码，会把服务端中文 message 变成乱码并让 jsonDecode 抛错。
    final String raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    final Map<String, dynamic>? body = _decodeObject(raw);
    if (body == null) {
      return _Envelope(
        ok: false,
        error: 'MALFORMED_RESPONSE',
        message: 'invalid json envelope',
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
    final bool ok = body['ok'] is bool && body['ok'] as bool;
    if (!ok) {
      return _Envelope(
        ok: false,
        error: _stringOf(body['error']),
        message: _stringOf(body['message']),
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
    return _Envelope(
      ok: true,
      data: body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : <String, dynamic>{},
      requestId: requestId,
      statusCode: response.statusCode,
    );
  }

  /// 服务端 `error` → 客户端内部错误码（§5.5）；未知码按 HTTP 状态兜底。
  AlipayFailure _failureOf(_Envelope envelope) {
    final AlipayErrorCode code = _mapError(
      envelope.error,
      envelope.statusCode,
    );
    return AlipayFailure(
      code: code,
      requestId: envelope.requestId,
      message: envelope.message ?? '',
    );
  }
}

/// 解析后的响应信封（内部数据类）。
class _Envelope {
  const _Envelope({
    required this.ok,
    this.data,
    this.error,
    this.message,
    this.requestId,
    this.statusCode = 200,
  });

  final bool ok;
  final Map<String, dynamic>? data;
  final String? error;
  final String? message;
  final String? requestId;
  final int statusCode;
}

/// 错误码映射（服务端 `error` 优先，HTTP 状态兜底）。
AlipayErrorCode _mapError(String? error, int statusCode) {
  switch (error) {
    case 'POOL_EXHAUSTED':
      return AlipayErrorCode.poolExhausted;
    case 'RATE_LIMITED':
      return AlipayErrorCode.rateLimited;
    case 'ORDER_NOT_FOUND':
      return AlipayErrorCode.orderNotFound;
    case 'CLAIM_TOKEN_MISMATCH':
      return AlipayErrorCode.claimTokenMismatch;
    case 'BAD_REQUEST':
      return AlipayErrorCode.badRequest;
    case 'SERVER_ERROR':
      return AlipayErrorCode.serverError;
    case 'MALFORMED_RESPONSE':
      return AlipayErrorCode.malformedResponse;
  }
  return switch (statusCode) {
    503 => AlipayErrorCode.poolExhausted,
    429 => AlipayErrorCode.rateLimited,
    404 => AlipayErrorCode.orderNotFound,
    403 => AlipayErrorCode.claimTokenMismatch,
    400 => AlipayErrorCode.badRequest,
    500 => AlipayErrorCode.serverError,
    _ => AlipayErrorCode.malformedResponse,
  };
}

/// 安全 JSON → Map 解析（失败返回 null，绝不抛）。
Map<String, dynamic>? _decodeObject(String body) {
  try {
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _stringOf(Object? value) => value == null ? '' : '$value';

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
