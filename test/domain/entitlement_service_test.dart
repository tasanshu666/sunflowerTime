/// 权益服务纯逻辑单测（付费墙 · 阶段 1）。
///
/// 用**内存假仓储**驱动，零平台依赖：验证默认 free / 票据判定 / 额度查询 /
/// 购买写入 / 恢复三分支 / 门控矩阵驱动。
library entitlement_service_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';

/// 内存假仓储（纯逻辑单测用，零平台依赖）。
class _FakeEntitlementRepository implements EntitlementRepository {
  Entitlement _stored;
  bool throwOnRead;
  String? lastJws;
  int clearCount = 0;

  _FakeEntitlementRepository({Entitlement? initial, this.throwOnRead = false})
      : _stored = initial ?? Entitlement.free;

  Entitlement get stored => _stored;

  @override
  Future<Entitlement> read() async {
    if (throwOnRead) throw StateError('安全区不可用（测试注入）');
    return _stored;
  }

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    _stored = entitlement;
    lastJws = jws;
  }

  @override
  Future<void> clear() async {
    _stored = Entitlement.free;
    clearCount++;
  }
}

void main() {
  group('Entitlement 实体：默认值必须 free', () {
    test('无参构造 → free，非 premium，字段为空', () {
      const Entitlement e = Entitlement();
      expect(e.tier, EntitlementTier.free);
      expect(e.isPremium, isFalse);
      expect(e.acquiredAt, isNull);
      expect(e.productId, isNull);
      expect(e, Entitlement.free);
    });

    test('lifetime 工厂 → premium', () {
      final Entitlement e = Entitlement.lifetime(
        productId: kIapProductIdLifetime,
        acquiredAt: DateTime(2026, 1, 2),
      );
      expect(e.isPremium, isTrue);
      expect(e.productId, kIapProductIdLifetime);
      expect(e.acquiredAt, DateTime(2026, 1, 2));
    });

    test('copyWith 与相等性', () {
      const Entitlement free = Entitlement.free;
      final Entitlement p = free.copyWith(
        tier: EntitlementTier.premium,
        productId: 'x',
      );
      expect(p.isPremium, isTrue);
      expect(p.productId, 'x');
      expect(p, Entitlement.lifetime(productId: 'x'));
    });
  });

  group('MatrixEntitlementService：判定', () {
    test('未 load：内存态默认 free；阶段 1 矩阵全放开 → can 全 true', () {
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
      );
      expect(svc.current.tier, EntitlementTier.free);
      for (final FeatureKey f in FeatureKey.values) {
        expect(svc.can(f), isTrue,
            reason: '阶段 1 free 也应放行 $f（行为零变化）');
        expect(svc.quotaOf(f), kUnlimitedQuota);
      }
    });

    test('load 空仓储 → free', () async {
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
      );
      final Entitlement e = await svc.load();
      expect(e.tier, EntitlementTier.free);
      expect(svc.current.tier, EntitlementTier.free);
    });

    test('load 已购仓储 → premium', () async {
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(
          initial: Entitlement.lifetime(productId: kIapProductIdLifetime),
        ),
      );
      final Entitlement e = await svc.load();
      expect(e.isPremium, isTrue);
      expect(svc.can(FeatureKey.oneClickCare), isTrue);
    });

    test('purchaseLifetime：写入 premium 票据并刷新内存态', () async {
      final _FakeEntitlementRepository repo = _FakeEntitlementRepository();
      final DateTime fixed = DateTime(2026, 5, 6, 7, 8, 9);
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: repo,
        clock: () => fixed,
      );

      await svc.purchaseLifetime();

      expect(svc.current.isPremium, isTrue);
      expect(svc.current.productId, kIapProductIdLifetime);
      expect(svc.current.acquiredAt, fixed);
      expect(repo.stored.isPremium, isTrue);
      expect(repo.stored.productId, kIapProductIdLifetime);
    });

    test('restore：三分支', () async {
      final MatrixEntitlementService restoredSvc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(
          initial: Entitlement.lifetime(productId: kIapProductIdLifetime),
        ),
      );
      expect(await restoredSvc.restore(), RestoreResult.restored);
      expect(restoredSvc.current.isPremium, isTrue);

      final MatrixEntitlementService emptySvc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
      );
      expect(await emptySvc.restore(), RestoreResult.nothingToRestore);
      expect(emptySvc.current.isPremium, isFalse);

      final MatrixEntitlementService failingSvc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(throwOnRead: true),
      );
      expect(await failingSvc.restore(), RestoreResult.failed);
    });

    test('自定义矩阵：free 关闭某项 → can=false（证明判定真读矩阵）', () async {
      final Map<FeatureKey, FeatureRule> matrix = <FeatureKey, FeatureRule>{
        FeatureKey.oneClickCare: const FeatureRule(
          key: FeatureKey.oneClickCare,
          freeEnabled: false,
          freeQuota: 0,
          premiumQuota: kUnlimitedQuota,
        ),
      };
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
        matrix: matrix,
      );
      await svc.load();
      expect(svc.can(FeatureKey.oneClickCare), isFalse);
      expect(svc.quotaOf(FeatureKey.oneClickCare), 0);

      await svc.purchaseLifetime();
      expect(svc.can(FeatureKey.oneClickCare), isTrue);
      expect(svc.quotaOf(FeatureKey.oneClickCare), kUnlimitedQuota);
    });

    test('未登记的能力点：放行 + 不限额度（安全侧）', () async {
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
        matrix: const <FeatureKey, FeatureRule>{},
      );
      await svc.load();
      expect(svc.can(FeatureKey.parentReport), isTrue);
      expect(svc.quotaOf(FeatureKey.parentReport), kUnlimitedQuota);
    });
  });

  group('门控矩阵阶段 1：免费行为 = 现状（全放开）', () {
    test('矩阵覆盖全部 FeatureKey', () {
      expect(kEntitlementMatrix.keys.toSet(), FeatureKey.values.toSet());
    });

    test('每个能力点 free 与 premium 判定/额度等价', () {
      for (final FeatureKey f in FeatureKey.values) {
        expect(featureAllowedFor(f, EntitlementTier.free), isTrue,
            reason: '$f 阶段 1 免费应放行');
        expect(
          featureAllowedFor(f, EntitlementTier.free),
          featureAllowedFor(f, EntitlementTier.premium),
          reason: '$f free/premium 判定应等价（阶段 1 未启用门控）',
        );
        expect(
          featureQuotaFor(f, EntitlementTier.free),
          featureQuotaFor(f, EntitlementTier.premium),
          reason: '$f free/premium 额度应等价（阶段 1 未启用门控）',
        );
      }
    });
  });
}
