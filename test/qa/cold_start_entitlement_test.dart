/// 冷启动权益落票据测试（付费墙 · 阶段 4 · P1 修复回归保护）。
///
/// 背景：`main()` 在 `runApp` 前调用 [hydrateEntitlement]，把安全区票据读入
/// `entitlementProvider`。**不落票据 → 已购用户冷启动被判 free（买了也不解锁）**，
/// 是本批回归风险最高项，此前零测试。
///
/// 本测试直接驱动顶层 [hydrateEntitlement]（`main()` 顶层逻辑无法在测试宿主直接跑），
/// 覆盖三分支：已购→lifetime、无票据→free、仓储抛异常→不抛且保持 free。
library cold_start_entitlement_test;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/main.dart';

/// 内存假票据仓储（可注入 lifetime 票据 / 读失败）。
class _FakeEntitlementRepository implements EntitlementRepository {
  _FakeEntitlementRepository(this._stored, {this.throwOnRead = false});

  Entitlement _stored;
  final bool throwOnRead;

  @override
  Future<Entitlement> read() async {
    if (throwOnRead) throw StateError('测试注入：安全区读失败');
    return _stored;
  }

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

ProviderContainer _containerWith(_FakeEntitlementRepository repo) =>
    ProviderContainer(
      overrides: <Override>[
        entitlementRepositoryProvider.overrideWithValue(repo),
      ],
    );

void main() {
  group('P1 冷启动：hydrateEntitlement 落票据', () {
    test('已购（lifetime）票据冷启动 → entitlementProvider 读到 lifetime（非 free）',
        () async {
      final ProviderContainer container = _containerWith(
        _FakeEntitlementRepository(
          Entitlement.lifetime(productId: 'lifetime.test'),
        ),
      );
      addTearDown(container.dispose);

      // 前置：未 hydrate 前默认 free（这正是 P1 要修的「买了也被判 free」）。
      expect(container.read(entitlementProvider).tier, EntitlementTier.free,
          reason: '前置：冷启动未落票据时默认 free');

      await hydrateEntitlement(container);

      final Entitlement e = container.read(entitlementProvider);
      expect(e.isPremium, isTrue,
          reason: 'P1：已购用户冷启动必须读到 lifetime，而不是 free');
      expect(e.tier, EntitlementTier.premium);
      expect(e.productId, 'lifetime.test');
    });

    test('无票据冷启动 → 保持 free（安全默认）', () async {
      final ProviderContainer container =
          _containerWith(_FakeEntitlementRepository(Entitlement.free));
      addTearDown(container.dispose);

      await hydrateEntitlement(container);

      expect(container.read(entitlementProvider).tier, EntitlementTier.free);
    });

    test('仓储抛异常 → 不抛、保持 free（不阻塞启动）', () async {
      final ProviderContainer container = _containerWith(
        _FakeEntitlementRepository(Entitlement.free, throwOnRead: true),
      );
      addTearDown(container.dispose);

      // 不应抛出。
      await hydrateEntitlement(container);

      expect(container.read(entitlementProvider).tier, EntitlementTier.free,
          reason: '读失败按 free 继续，绝不阻塞启动');
    });
  });
}
