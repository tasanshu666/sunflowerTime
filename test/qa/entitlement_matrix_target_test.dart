/// 门控矩阵目标值登记守卫（付费墙 · 阶段 3 登记 → 阶段 4 启用）。
///
/// 阶段 3 本批**只登记**免费边界目标值；阶段 4 已把其中 5 项**收紧为真实门控**。
/// 本测试把两件事钉死：
///  1. **防漂移**：登记的花盆目标值必须**引用** `prd_params.dart` 的容量常量
///     （若有人另写死 `4` / `12`，一旦 PRD 调整基础容量即两处漂移）；
///  2. **防边界漂移**：阶段 4 收紧的 5 项，其 free / premium 的开关与额度**必须**等于
///     约定边界（若有人手滑改动，本测试立即变红）；其余键（`parentReport` +
///     4 个未实现键）**必须**保持免费放开。
library entitlement_matrix_target_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

/// 阶段 4 **已收紧**的能力点（其余保持免费放开）。
const Set<FeatureKey> _tightenedInPhase4 = <FeatureKey>{
  FeatureKey.oneClickCare,
  FeatureKey.gardenPotCapacity,
  FeatureKey.taskTemplateCount,
  FeatureKey.rewardTemplateCount,
  FeatureKey.deepReport,
};

/// 「功能尚未实现」的键：🔴 本批**不接门控**（Apple 3.1.1/2.3.1 拒审风险），
/// 必须行文等于现状（等价放行）。
const Set<FeatureKey> _notImplementedKeys = <FeatureKey>{
  FeatureKey.multiChildProfile,
  FeatureKey.exportShare,
  FeatureKey.memoirExport,
  FeatureKey.familySharing,
};

void main() {
  group('免费边界目标值登记', () {
    test('任务 / 奖励 / 孩子档案 目标值 = 5 / 5 / 1', () {
      expect(kFreeTaskQuota, 5);
      expect(kFreeRewardQuota, 5);
      expect(kFreeChildProfileCount, 1);
    });

    test('花盆目标值引用 prd_params 容量常量（防漂移）', () {
      expect(kFreeGardenPotQuota, kGardenPotCapacityDefault,
          reason: '免费花盆目标值必须引用 prd_params 的基础容量，不得写死 4');
      expect(kPremiumGardenPotQuota, kGardenPotCapacityMax,
          reason: '买断花盆目标值必须引用 prd_params 的最大容量，不得写死 12');
    });
  });

  group('新增能力点已登记且矩阵全覆盖', () {
    test('全部 FeatureKey 均登记', () {
      expect(kEntitlementMatrix.keys.toSet(), FeatureKey.values.toSet(),
          reason: '门控矩阵必须覆盖全部 FeatureKey');
    });
  });

  group('🔴 阶段 4 收紧项 = 精确边界（防漂移）', () {
    test('一键操作：free 关闭 / premium 放开', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.oneClickCare]!;
      expect(r.freeEnabled, isFalse, reason: 'D3：free 隐藏一键 FAB');
      expect(r.premiumEnabled, isTrue);
    });

    test('花盆容量：free = 基础容量 / premium = 解锁上限', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.gardenPotCapacity]!;
      expect(r.freeEnabled, isTrue);
      expect(r.freeQuota, kFreeGardenPotQuota);
      expect(r.premiumQuota, kPremiumGardenPotQuota);
    });

    test('任务模板：free = kFreeTaskQuota / premium 不限', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.taskTemplateCount]!;
      expect(r.freeEnabled, isTrue);
      expect(r.freeQuota, kFreeTaskQuota);
      expect(r.premiumQuota, kUnlimitedQuota);
    });

    test('奖励模板：free = kFreeRewardQuota / premium 不限', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.rewardTemplateCount]!;
      expect(r.freeEnabled, isTrue);
      expect(r.freeQuota, kFreeRewardQuota);
      expect(r.premiumQuota, kUnlimitedQuota);
    });

    test('深度报告：free 关闭 / premium 放开', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.deepReport]!;
      expect(r.freeEnabled, isFalse);
      expect(r.premiumEnabled, isTrue);
    });
  });

  group('🔴 未收紧项必须保持免费放开', () {
    test('家长报告页保持免费开启（兑现 C69「近 7 天报告」）', () {
      final FeatureRule r = kEntitlementMatrix[FeatureKey.parentReport]!;
      expect(r.freeEnabled, isTrue);
      expect(r.freeQuota, kUnlimitedQuota);
    });

    test('4 个未实现键行文 = 现状（等价放行，不接门控）', () {
      for (final FeatureKey f in _notImplementedKeys) {
        final FeatureRule r = kEntitlementMatrix[f]!;
        expect(r.freeEnabled, isTrue,
            reason: '$f 功能未实现，本批不得收紧（Apple 3.1.1/2.3.1）');
        expect(r.freeQuota, kUnlimitedQuota,
            reason: '$f 功能未实现，free 额度必须不限');
        expect(
          featureAllowedFor(f, EntitlementTier.free),
          featureAllowedFor(f, EntitlementTier.premium),
          reason: '$f free/premium 判定应等价（未接门控）',
        );
      }
    });

    test('收紧集合与登记集合互补（防漏登记）', () {
      final Set<FeatureKey> expectedOpen = FeatureKey.values
          .where((FeatureKey f) => !_tightenedInPhase4.contains(f))
          .toSet();
      for (final FeatureKey f in expectedOpen) {
        if (f == FeatureKey.parentReport ||
            _notImplementedKeys.contains(f)) {
          continue;
        }
        // 兜底：任何既非「已收紧」也未在上列白名单的能力点，都应检查是否被意外关闭。
        expect(
          featureAllowedFor(f, EntitlementTier.free) ||
              _tightenedInPhase4.contains(f),
          isTrue,
          reason: '$f 未被声明为阶段 4 收紧项，不应被关闭',
        );
      }
    });
  });
}
