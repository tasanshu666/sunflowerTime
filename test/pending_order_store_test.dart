/// pending 凭据安全区存储复验（打桩 MethodChannel，零真实平台依赖）。
library pending_order_store_test;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/data/local/pending_order_store.dart';
import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> memory = <String, String>{};
  final List<String> deleted = <String>[];

  setUp(() {
    memory.clear();
    deleted.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final Map<dynamic, dynamic> args =
          (call.arguments as Map?) ?? <dynamic, dynamic>{};
      final String key = '${args['key'] ?? ''}';
      switch (call.method) {
        case 'write':
          memory[key] = '${args['value'] ?? ''}';
          return null;
        case 'read':
          return memory[key];
        case 'delete':
          deleted.add(key);
          memory.remove(key);
          return null;
        case 'deleteAll':
          throw StateError('deleteAll 绝不能被调用（会清掉 PIN / 权益票据）');
        default:
          return null;
      }
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('save/load 三键往返一致，createdAt 精确到毫秒', () async {
    final PendingOrderStoreImpl store = PendingOrderStoreImpl();
    final DateTime createdAt = DateTime.utc(2026, 11, 28, 9, 30, 12, 345);
    await store.save(PendingOrder(
      outTradeNo: 'SF261128WH00101',
      claimToken: 'a' * 32,
      createdAt: createdAt,
    ));

    expect(memory[kPendingOrderOutTradeNoKey], 'SF261128WH00101');
    expect(memory[kPendingOrderClaimTokenKey], 'a' * 32);
    expect(memory[kPendingOrderCreatedAtKey], createdAt.toIso8601String());

    final PendingOrder? loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.outTradeNo, 'SF261128WH00101');
    expect(loaded.claimToken, 'a' * 32);
    expect(loaded.createdAt, createdAt);
  });

  test('clear 只删本功能三键，不 deleteAll / 不动 PIN', () async {
    memory['kSecurePinHash'] = 'pin-hash';
    memory['iap.productId'] = 'lifetime';
    final PendingOrderStoreImpl store = PendingOrderStoreImpl();
    await store.save(PendingOrder(
      outTradeNo: 'o',
      claimToken: 'c',
      createdAt: DateTime.utc(2026),
    ));
    await store.clear();

    expect(deleted.toSet(), <String>{
      kPendingOrderOutTradeNoKey,
      kPendingOrderClaimTokenKey,
      kPendingOrderCreatedAtKey,
    });
    expect(memory['kSecurePinHash'], 'pin-hash');
    expect(memory['iap.productId'], 'lifetime');
    expect(await store.load(), isNull);
  });

  test('脏数据 / 平台异常 → null 或静默成功，绝不裸抛', () async {
    final PendingOrderStoreImpl store = PendingOrderStoreImpl();
    expect(await store.load(), isNull);

    memory[kPendingOrderOutTradeNoKey] = 'o';
    memory[kPendingOrderClaimTokenKey] = 'c';
    memory[kPendingOrderCreatedAtKey] = 'not-a-date';
    final PendingOrder? dirty = await store.load();
    expect(dirty, isNotNull);
    expect(dirty!.createdAt, DateTime.fromMillisecondsSinceEpoch(0));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      throw StateError('secure storage unavailable');
    });
    await store.save(PendingOrder(
      outTradeNo: 'o',
      claimToken: 'c',
      createdAt: DateTime.utc(2026),
    ));
    expect(await store.load(), isNull);
    await store.clear();
  });
}
