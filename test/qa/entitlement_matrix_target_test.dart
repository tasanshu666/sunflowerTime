/// 门控矩阵目标值登记守卫（付费墙 · 阶段 3）。
///
/// 目的：本批**只登记免费边界目标值、不收紧行为**。本测试把两件事钉死：
///  1. **防漂移**：登记的花盆目标值必须**引用** `prd_params.dart` 的容量常量
///     （若有人另写死 `4` / `12`，一旦 PRD 调整基础容量即两处漂移）；
///  2. **防提前收紧**：本批所有 `freeEnabled` 必须仍为 `true`、`freeQuota` 必须仍为
///     `kUnlimitedQuota`（行为零变化）——若有人手滑把某处 `freeEnabled` 置 false，
///     本测试立即变红。
library entitlement_matrix_target_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

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

  group('阶段 3 登记的新增能力点', () {
    test('新增 5 个 FeatureKey 已登记且矩阵全覆盖', () {
      for (final FeatureKey f in <FeatureKey>[
        FeatureKey.multiChildProfile,
        FeatureKey.deepReport,
        FeatureKey.exportShare,
        FeatureKey.memoirExport,
        FeatureKey.familySharing,
      ]) {
        expect(kEntitlementMatrix.containsKey(f), isTrue,
            reason: '$f 应在门控矩阵中登记（否则取值时未登记=放行，阶段4 无法收紧）');
      }
      expect(kEntitlementMatrix.keys.toSet(), FeatureKey.values.toSet(),
          reason: '门控矩阵必须覆盖全部 FeatureKey');
    });
  });

  group('🔴 本批不得收紧（行为零变化）', () {
    test('全部能力点 freeEnabled 仍为 true', () {
      for (final MapEntry<FeatureKey, FeatureRule> e
          in kEntitlementMatrix.entries) {
        expect(e.value.freeEnabled, isTrue,
            reason: '${e.key} 本批必须仍为免费开放（防手滑提前收紧）');
      }
    });

    test('全部能力点 freeQuota 仍为 kUnlimitedQuota', () {
      for (final MapEntry<FeatureKey, FeatureRule> e
          in kEntitlementMatrix.entries) {
        expect(e.value.freeQuota, kUnlimitedQuota,
            reason: '${e.key} 本批 free 额度必须仍为不限（防手滑提前收紧）');
      }
    });

    test('free 与 premium 判定 / 额度等价（阶段 3 == 现状）', () {
      for (final FeatureKey f in FeatureKey.values) {
        expect(
          featureAllowedFor(f, EntitlementTier.free),
          featureAllowedFor(f, EntitlementTier.premium),
          reason: '$f free/premium 判定应等价（本批未启用门控）',
        );
        expect(
          featureQuotaFor(f, EntitlementTier.free),
          featureQuotaFor(f, EntitlementTier.premium),
          reason: '$f free/premium 额度应等价（本批未启用门控）',
        );
      }
    });
  });
}
