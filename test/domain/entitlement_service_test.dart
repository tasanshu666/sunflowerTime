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
    test('未 load：内存态默认 free；判定读矩阵（未收紧放行 / 收紧项拦截）', () {
      final MatrixEntitlementService svc = MatrixEntitlementService(
        repository: _FakeEntitlementRepository(),
      );
      expect(svc.current.tier, EntitlementTier.free);
      // 未收紧能力：free 放行且不限。
      expect(svc.can(FeatureKey.parentReport), isTrue);
      expect(svc.quotaOf(FeatureKey.parentReport), kUnlimitedQuota);
      // 阶段 4 收紧能力：free 关闭 / 有额度。
      expect(svc.can(FeatureKey.oneClickCare), isFalse);
      expect(svc.can(FeatureKey.deepReport), isFalse);
      expect(svc.quotaOf(FeatureKey.gardenPotCapacity), kFreeGardenPotQuota);
      expect(svc.quotaOf(FeatureKey.taskTemplateCount), kFreeTaskQuota);
      expect(svc.quotaOf(FeatureKey.rewardTemplateCount), kFreeRewardQuota);
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

  group('门控矩阵阶段 4 + C80 + C90：免费边界（收紧 7 项 / 其余放开）', () {
    const Set<FeatureKey> tightened = <FeatureKey>{
      FeatureKey.oneClickCare,
      FeatureKey.gardenPotCapacity,
      FeatureKey.taskTemplateCount,
      FeatureKey.rewardTemplateCount,
      FeatureKey.deepReport,
      // C80：称号专属属性 —— 本仓第一个真实生效的布尔收紧键。
      FeatureKey.titlePerks,
      // C90 期 1：多孩子档案 —— free 1 / premium 3，只拦新增（C69）。
      FeatureKey.multiChildProfile,
    };

    test('矩阵覆盖全部 FeatureKey', () {
      expect(kEntitlementMatrix.keys.toSet(), FeatureKey.values.toSet());
    });

    test('未收紧能力 free 与 premium 判定 / 额度仍等价且放行', () {
      for (final FeatureKey f in FeatureKey.values
          .where((FeatureKey f) => !tightened.contains(f))) {
        expect(featureAllowedFor(f, EntitlementTier.free), isTrue,
            reason: '$f 未被阶段 4 收紧，免费应放行');
        expect(
          featureAllowedFor(f, EntitlementTier.free),
          featureAllowedFor(f, EntitlementTier.premium),
          reason: '$f free/premium 判定应等价',
        );
        expect(
          featureQuotaFor(f, EntitlementTier.free),
          featureQuotaFor(f, EntitlementTier.premium),
          reason: '$f free/premium 额度应等价',
        );
      }
    });

    test('收紧能力：free 关闭或有额度上限（买断更宽）', () {
      expect(featureAllowedFor(FeatureKey.oneClickCare, EntitlementTier.free),
          isFalse);
      expect(featureAllowedFor(FeatureKey.deepReport, EntitlementTier.free),
          isFalse);
      // C80：称号属性 free 关闭 / premium 放开（布尔型，双向 unlimited）。
      expect(featureAllowedFor(FeatureKey.titlePerks, EntitlementTier.free),
          isFalse);
      expect(featureAllowedFor(FeatureKey.titlePerks, EntitlementTier.premium),
          isTrue);
      expect(featureQuotaFor(FeatureKey.titlePerks, EntitlementTier.free),
          kUnlimitedQuota);
      expect(featureQuotaFor(FeatureKey.titlePerks, EntitlementTier.premium),
          kUnlimitedQuota);
      // 花盆：free=4 / premium=12（皆有限，买断更宽）。
      expect(featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.free),
          kFreeGardenPotQuota);
      expect(
          featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.premium),
          kPremiumGardenPotQuota);
      // 任务 / 奖励：free 有限额度 / premium 不限（哨兵 -1）。
      expect(featureQuotaFor(FeatureKey.taskTemplateCount, EntitlementTier.free),
          kFreeTaskQuota);
      expect(
          featureQuotaFor(FeatureKey.taskTemplateCount, EntitlementTier.premium),
          kUnlimitedQuota);
      expect(
          featureQuotaFor(FeatureKey.rewardTemplateCount, EntitlementTier.free),
          kFreeRewardQuota);
      expect(
          featureQuotaFor(
              FeatureKey.rewardTemplateCount, EntitlementTier.premium),
          kUnlimitedQuota);
      // C90 期 1：孩子档案 free 1 / premium 3（只拦新增，C69）。
      expect(featureQuotaFor(FeatureKey.multiChildProfile, EntitlementTier.free),
          kFreeChildProfileCount);
      expect(
          featureQuotaFor(FeatureKey.multiChildProfile, EntitlementTier.premium),
          kPremiumChildProfileCount);
    });

    test('quotaAllowsAdd：达到 / 超过额度一律拦新增', () {
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.free, 4),
        isTrue,
      );
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.free, 5),
        isFalse,
      );
      expect(
        quotaAllowsAdd(FeatureKey.taskTemplateCount, EntitlementTier.premium, 99),
        isTrue,
      );
      expect(
        quotaAllowsAdd(FeatureKey.oneClickCare, EntitlementTier.free, 0),
        isFalse,
      );
    });
  });
}
