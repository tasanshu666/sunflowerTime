/// 内购平台层单测（付费墙 · 阶段 2）。
///
/// 用**记录型假适配器**（[_FakeIapAdapter]）驱动，零平台依赖：验证
/// 购买三态（成功 / 取消 / 失败）+ 商店不可用安全降级 + 恢复三态
/// （restored / nothingToRestore / failed）+ 与 [MatrixEntitlementService] 的接线。
///
/// 红线圈：商店不可用 / 插件抛错时**绝不崩**，一律以结果对象返回。
library iap_service_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';

/// 记录型假适配器：可配置「可用性 / 抛错 / 发出的消息」，离线驱动全部三态。
class _FakeIapAdapter implements IapAdapter {
  _FakeIapAdapter({this.available = true});

  bool available;
  bool throwOnBuy = false;
  bool throwOnRestore = false;

  /// 购买 / 恢复时发出的消息（null = 不发消息）。
  IapMessage? buyMessage;
  IapMessage? restoreMessage;

  int buyCalls = 0;
  int restoreCalls = 0;

  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    return <IapProduct>[
      const IapProduct(
        id: kIapProductIdLifetime,
        title: 'Lifetime',
        description: 'unlock all',
        price: r'$9.99',
      ),
    ];
  }

  @override
  Future<void> startLifetimePurchase(String productId) async {
    buyCalls++;
    if (throwOnBuy) throw StateError('buy boom');
    final IapMessage? m = buyMessage;
    if (m != null) _controller.add(m);
  }

  @override
  Future<void> startRestore() async {
    restoreCalls++;
    if (throwOnRestore) throw StateError('restore boom');
    final IapMessage? m = restoreMessage;
    if (m != null) _controller.add(m);
  }

  Future<void> dispose() => _controller.close();
}

/// 内存假票据仓储（零平台依赖）。
class _FakeRepo implements EntitlementRepository {
  _FakeRepo({Entitlement? initial}) : _stored = initial ?? Entitlement.free;

  Entitlement _stored;
  String? lastJws;
  int writeCount = 0;

  Entitlement get stored => _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    _stored = entitlement;
    lastJws = jws;
    writeCount++;
  }

  @override
  Future<void> clear() async {
    _stored = Entitlement.free;
  }
}

/// 收集事件流（广播流需先订阅再触发）。
List<IapEvent> _collect(Stream<IapEvent> stream) {
  final List<IapEvent> out = <IapEvent>[];
  stream.listen(out.add);
  return out;
}

void main() {
  group('IapService · 购买三态', () {
    test('购买成功 → success、lastJws 落定、发 IapSucceeded 事件', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..buyMessage = const IapMessage(
          state: IapMessageState.purchased,
          productId: kIapProductIdLifetime,
          jws: 'JWS-abc',
        );
      final IapService svc = IapService(adapter: adapter);
      final List<IapEvent> events = _collect(svc.events);

      final IapPurchaseResult result = await svc.buyLifetime();
      await pumpEventQueue(); // 广播流事件异步投递：断言前先排空微任务

      expect(result, IapPurchaseResult.success);
      expect(adapter.buyCalls, 1);
      expect(svc.lastJws, 'JWS-abc');
      expect(events.whereType<IapSucceeded>(), hasLength(1));
      await adapter.dispose();
    });

    test('用户取消 → canceled（非错误），发 IapCanceled 事件，不崩', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..buyMessage = const IapMessage(
          state: IapMessageState.canceled,
          productId: kIapProductIdLifetime,
        );
      final IapService svc = IapService(adapter: adapter);
      final List<IapEvent> events = _collect(svc.events);

      final IapPurchaseResult result = await svc.buyLifetime();
      await pumpEventQueue();

      expect(result, IapPurchaseResult.canceled);
      expect(svc.lastJws, isNull);
      expect(events.whereType<IapCanceled>(), hasLength(1));
      await adapter.dispose();
    });

    test('插件抛错 → failed（安全返回，不裸抛）', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()..throwOnBuy = true;
      final IapService svc = IapService(adapter: adapter);
      final List<IapEvent> events = _collect(svc.events);

      final IapPurchaseResult result = await svc.buyLifetime();
      await pumpEventQueue();

      expect(result, IapPurchaseResult.failed);
      expect(events.whereType<IapFailed>(), isNotEmpty);
      await adapter.dispose();
    });

    test('商店不可用 → failed；loadProducts 空；restore failed（离线优先红线）',
        () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter(available: false);
      final IapService svc = IapService(adapter: adapter);
      final List<IapEvent> events = _collect(svc.events);

      expect(await svc.buyLifetime(), IapPurchaseResult.failed);
      expect(await svc.loadProducts(), isEmpty);
      expect(await svc.restore(), IapRestoreResult.failed);
      await pumpEventQueue();
      expect(events.whereType<IapFailed>(), isNotEmpty);
      // 商店不可用时不得调用底层购买 / 恢复。
      expect(adapter.buyCalls, 0);
      expect(adapter.restoreCalls, 0);
      await adapter.dispose();
    });

    test('loadProducts：商店可用 → 返回商品详情', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter();
      final IapService svc = IapService(adapter: adapter);

      final List<IapProduct> products = await svc.loadProducts();

      expect(products, hasLength(1));
      expect(products.first.id, kIapProductIdLifetime);
      expect(products.first.price, r'$9.99');
      await adapter.dispose();
    });
  });

  group('IapService · 恢复三态', () {
    test('恢复成功 → restored、lastJws 落定', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..restoreMessage = const IapMessage(
          state: IapMessageState.restored,
          productId: kIapProductIdLifetime,
          jws: 'JWS-restore',
        );
      final IapService svc = IapService(adapter: adapter);

      expect(await svc.restore(), IapRestoreResult.restored);
      expect(svc.lastJws, 'JWS-restore');
      await adapter.dispose();
    });

    test('无购买历史 → nothingToRestore（宽限窗口内无 restored 消息）', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter(); // 不发任何消息
      final IapService svc = IapService(
        adapter: adapter,
        restoreGrace: const Duration(milliseconds: 30),
      );

      expect(await svc.restore(), IapRestoreResult.nothingToRestore);
      await adapter.dispose();
    });

    test('恢复查询抛错 → failed', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()..throwOnRestore = true;
      final IapService svc = IapService(adapter: adapter);

      expect(await svc.restore(), IapRestoreResult.failed);
      await adapter.dispose();
    });
  });

  group('MatrixEntitlementService ⇄ IapService 接线', () {
    test('购买成功 → 票据落库（含 JWS）→ tier 变 premium', () async {
      final _FakeRepo repo = _FakeRepo();
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..buyMessage = const IapMessage(
          state: IapMessageState.purchased,
          productId: kIapProductIdLifetime,
          jws: 'JWS-wire',
        );
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: repo,
        iap: IapService(adapter: adapter),
      );

      await svc.purchaseLifetime();

      expect(svc.current.isPremium, isTrue);
      expect(repo.stored.isPremium, isTrue);
      expect(repo.stored.productId, kIapProductIdLifetime);
      expect(repo.lastJws, 'JWS-wire');
      expect(repo.writeCount, 1);
      await adapter.dispose();
    });

    test('用户取消 → tier 不变、不落库、不崩', () async {
      final _FakeRepo repo = _FakeRepo();
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..buyMessage = const IapMessage(
          state: IapMessageState.canceled,
          productId: kIapProductIdLifetime,
        );
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: repo,
        iap: IapService(adapter: adapter),
      );

      await svc.purchaseLifetime();

      expect(svc.current.isPremium, isFalse);
      expect(repo.stored.isPremium, isFalse);
      expect(repo.writeCount, 0);
      await adapter.dispose();
    });

    test('商店不可用 / 抛错 → 安全降级保持 free', () async {
      final _FakeRepo repo = _FakeRepo();
      final _FakeIapAdapter adapter = _FakeIapAdapter(available: false);
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: repo,
        iap: IapService(adapter: adapter),
      );

      await svc.purchaseLifetime(); // 商店不可用 → failed → 保持 free

      expect(svc.current.isPremium, isFalse);
      expect(repo.writeCount, 0);

      adapter.available = true;
      adapter.throwOnBuy = true;
      await svc.purchaseLifetime(); // 抛错 → failed → 保持 free

      expect(svc.current.isPremium, isFalse);
      expect(repo.writeCount, 0);
      await adapter.dispose();
    });

    test('恢复：restored → premium；nothingToRestore → 保持 free；failed → failed',
        () async {
      final _FakeRepo repo = _FakeRepo();
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..restoreMessage = const IapMessage(
          state: IapMessageState.restored,
          productId: kIapProductIdLifetime,
          jws: 'JWS-r',
        );
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: repo,
        iap: IapService(adapter: adapter),
      );

      expect(await svc.restore(), RestoreResult.restored);
      expect(svc.current.isPremium, isTrue);
      expect(repo.stored.isPremium, isTrue);
      expect(repo.lastJws, 'JWS-r');

      // 无历史：清空消息 + 短宽限 → nothingToRestore，保持现状（不回退已恢复态）。
      adapter.restoreMessage = null;
      final MatrixEntitlementService svc2 = MatrixEntitlementService(
        repository: _FakeRepo(),
        iap: IapService(
          adapter: adapter,
          restoreGrace: const Duration(milliseconds: 30),
        ),
      );
      expect(await svc2.restore(), RestoreResult.nothingToRestore);
      expect(svc2.current.isPremium, isFalse);

      // 抛错 → failed。
      adapter.throwOnRestore = true;
      expect(await svc2.restore(), RestoreResult.failed);
      await adapter.dispose();
    });

    test('未接线内购（iap == null）→ 阶段 1 行为：直接落库 premium', () async {
      final _FakeRepo repo = _FakeRepo();
      final MatrixEntitlementService svc =
          MatrixEntitlementService(repository: repo);

      await svc.purchaseLifetime();

      expect(svc.current.isPremium, isTrue);
      expect(repo.stored.isPremium, isTrue);
    });
  });

  group('IapService · 单例 resetForTest', () {
    test('instance 可重置并换入假适配器（跨用例隔离）', () async {
      final _FakeIapAdapter adapter = _FakeIapAdapter()
        ..buyMessage = const IapMessage(
          state: IapMessageState.purchased,
          productId: kIapProductIdLifetime,
          jws: 'JWS-singleton',
        );
      IapService.instance.resetForTest(adapter: adapter);

      final IapPurchaseResult r = await IapService.instance.buyLifetime();
      expect(r, IapPurchaseResult.success);
      expect(IapService.instance.lastJws, 'JWS-singleton');

      IapService.instance.resetForTest(); // 复位（清空遗留状态 + 断开假适配器）
      expect(IapService.instance.lastJws, isNull);
      await adapter.dispose();
    });
  });
}
