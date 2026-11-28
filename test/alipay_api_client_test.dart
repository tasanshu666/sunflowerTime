/// App 内支付宝 HTTP 客户端契约复验（无真实网络依赖）。
///
/// 逐条对齐增量架构设计 §5：`order/create` body 无 amount、redeem 三态、
/// 五种服务端错误码映射、`X-Request-Id` 透出、网络 / 脏响应失败安全。
library alipay_api_client_test;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/alipay_endpoints.dart';
import 'package:sunflower_time/data/remote/alipay_api_client.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart';

const String _base = 'https://api.example.test';

http.Response _json(
  int status,
  Map<String, dynamic> body, {
  String? requestId,
}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{
        // http.Response 无 charset 时按 latin1 编码 body → 中文 message 会抛 ArgumentError。
        'Content-Type': 'application/json; charset=utf-8',
        if (requestId != null) 'x-request-id': requestId,
      },
    );

void main() {
  group('AlipayApiClient.createOrder', () {
    test('body 只有 platform/app_version/device_hash，绝不含 amount', () async {
      http.Request? captured;
      final MockClient client = MockClient((http.Request request) async {
        captured = request;
        return _json(200, <String, dynamic>{
          'ok': true,
          'data': <String, dynamic>{
            'out_trade_no': 'SF261126WH00101',
            'claim_token': 'a' * 32,
            'order_string': 'app_id=...&sign=...',
            'amount': '49.90',
            'expires_in': 900,
          },
        }, requestId: 'rid-create');
      });
      final CreateOrderData data = await AlipayApiClient(
        client: client,
        baseUrl: _base,
      ).createOrder(
        platform: kAlipayPlatformAndroid,
        appVersion: '1.1.0+2107',
        deviceHash: 'd' * 32,
      );

      expect(captured, isNotNull);
      expect(captured!.url.path, kAlipayCreateOrderPath);
      expect(captured!.method, 'POST');
      final Map<String, dynamic> body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), <String>{
        'platform',
        'app_version',
        'device_hash',
      });
      expect(body.containsKey('amount'), isFalse);
      expect(body['platform'], 'android');
      expect(data.error, isNull);
      expect(data.outTradeNo, 'SF261126WH00101');
      expect(data.claimToken, 'a' * 32);
      expect(data.orderString, 'app_id=...&sign=...');
      expect(data.amount, '49.90');
      expect(data.expiresIn, 900);
      expect(data.requestId, 'rid-create');
    });

    test('503 POOL_EXHAUSTED 映射为错误对象（不抛）', () async {
      final MockClient client = MockClient((http.Request request) async => _json(
            503,
            <String, dynamic>{
              'ok': false,
              'error': 'POOL_EXHAUSTED',
              // http.Response 构造器固定按 latin1 编码 body，测试夹具保持 ASCII。
              'message': 'pool exhausted',
            },
            requestId: 'rid-503',
          ));
      final CreateOrderData data = await AlipayApiClient(
        client: client,
        baseUrl: _base,
      ).createOrder(
        platform: 'android',
        appVersion: '1.1.0',
        deviceHash: 'h',
      );
      expect(data.error?.code, AlipayErrorCode.poolExhausted);
      expect(data.error?.requestId, 'rid-503');
      expect(data.outTradeNo, isEmpty);
      expect(data.orderString, isEmpty);
    });

    test('网络异常 → NETWORK_ERROR，不裸抛', () async {
      final MockClient client =
          MockClient((http.Request request) async => throw StateError('offline'));
      final CreateOrderData data = await AlipayApiClient(
        client: client,
        baseUrl: _base,
      ).createOrder(
        platform: 'android',
        appVersion: '1.1.0',
        deviceHash: 'h',
      );
      expect(data.error?.code, AlipayErrorCode.networkError);
    });
  });

  group('AlipayApiClient.redeem 三态', () {
    AlipayApiClient clientFor(
      Future<http.Response> Function(http.Request) handler,
    ) =>
        AlipayApiClient(client: MockClient(handler), baseUrl: _base);

    test('200 issued → 同码同 serial', () async {
      http.Request? captured;
      final AlipayApiClient api = clientFor((http.Request request) async {
        captured = request;
        return _json(200, <String, dynamic>{
          'ok': true,
          'data': <String, dynamic>{
            'status': 'issued',
            'redeem_code': 'x' * 92,
            'serial': 1024,
          },
        });
      });
      final RedeemData data = await api.redeem(
        outTradeNo: 'SF261126WH00101',
        claimToken: 'c' * 32,
      );
      expect(captured!.url.path, kAlipayRedeemPath);
      expect(captured!.url.queryParameters['out_trade_no'], 'SF261126WH00101');
      expect(captured!.url.queryParameters['claim_token'], 'c' * 32);
      expect(data.error, isNull);
      expect(data.status, RedeemStatus.issued);
      expect(data.redeemCode, 'x' * 92);
      expect(data.serial, 1024);
    });

    test('202 pending 与 200 unpaid 必须区分', () async {
      int call = 0;
      final AlipayApiClient api = clientFor((http.Request request) async {
        call++;
        return call == 1
            ? _json(202, <String, dynamic>{
                'ok': true,
                'data': <String, dynamic>{'status': 'pending'},
              })
            : _json(200, <String, dynamic>{
                'ok': true,
                'data': <String, dynamic>{'status': 'unpaid'},
              });
      });
      final RedeemData pending = await api.redeem(
        outTradeNo: 'o',
        claimToken: 'c',
      );
      final RedeemData unpaid = await api.redeem(
        outTradeNo: 'o',
        claimToken: 'c',
      );
      expect(pending.status, RedeemStatus.pending);
      expect(unpaid.status, RedeemStatus.unpaid);
    });

    test('五种错误码 + 未知码按 HTTP 状态兜底', () async {
      const Map<String, int> cases = <String, int>{
        'POOL_EXHAUSTED': 503,
        'RATE_LIMITED': 429,
        'ORDER_NOT_FOUND': 404,
        'CLAIM_TOKEN_MISMATCH': 403,
        'BAD_REQUEST': 400,
        'SERVER_ERROR': 500,
      };
      const List<AlipayErrorCode> expected = <AlipayErrorCode>[
        AlipayErrorCode.poolExhausted,
        AlipayErrorCode.rateLimited,
        AlipayErrorCode.orderNotFound,
        AlipayErrorCode.claimTokenMismatch,
        AlipayErrorCode.badRequest,
        AlipayErrorCode.serverError,
      ];
      int index = 0;
      final AlipayApiClient api = clientFor((http.Request request) async {
        final String error = cases.keys.toList()[index];
        final int status = cases.values.toList()[index];
        index++;
        return _json(status, <String, dynamic>{
          'ok': false,
          'error': error,
          'message': 'msg',
        });
      });
      for (final AlipayErrorCode code in expected) {
        final RedeemData data = await api.redeem(
          outTradeNo: 'o',
          claimToken: 'c',
        );
        expect(data.error?.code, code, reason: 'error=$code');
        expect(data.status, RedeemStatus.unpaid);
      }
      index = 0;
      final AlipayApiClient fallback = clientFor((http.Request request) async {
        index++;
        return _json(index == 1 ? 429 : 503, <String, dynamic>{
          'ok': false,
          'error': 'UNKNOWN_FROM_SERVER',
          'message': '',
        });
      });
      expect(
        (await fallback.redeem(outTradeNo: 'o', claimToken: 'c')).error?.code,
        AlipayErrorCode.rateLimited,
      );
      expect(
        (await fallback.redeem(outTradeNo: 'o', claimToken: 'c')).error?.code,
        AlipayErrorCode.poolExhausted,
      );
    });

    test('X-Request-Id 透出；脏 JSON 不裸抛', () async {
      final AlipayApiClient withId = clientFor((http.Request request) async =>
          _json(429, <String, dynamic>{
            'ok': false,
            'error': 'RATE_LIMITED',
            'message': 'slow down',
          }, requestId: 'rid-429'));
      final RedeemData limited = await withId.redeem(
        outTradeNo: 'o',
        claimToken: 'c',
      );
      expect(limited.requestId, 'rid-429');
      expect(limited.error?.requestId, 'rid-429');

      final AlipayApiClient dirty = clientFor((http.Request request) async =>
          http.Response('{not-json', 200));
      final RedeemData broken = await dirty.redeem(
        outTradeNo: 'o',
        claimToken: 'c',
      );
      expect(broken.error?.code, AlipayErrorCode.malformedResponse);
    });
  });
}
