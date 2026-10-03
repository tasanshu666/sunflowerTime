/// `resolveRewardAsset` 种子分档图解析（2026-10-03 玄参提供普通/精英种子分档图）。
///
/// 口径（C20 修订）：按物种档位优先取 `seed_premium.png`（精英）/ `seed_common.png`
/// （普通）；档位图缺失回退通用 `seed.png`；再缺失回退内置 `Icons.eco`（resolve 返回 null）。
/// 碎片 / 阳光解析不受本次改动影响，一并护栏。
library reward_asset_resolve_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';

void main() {
  const Set<String> full = <String>{
    'assets/rewards/sunlight.png',
    'assets/rewards/fragment.png',
    'assets/rewards/seed.png',
    'assets/rewards/seed_common.png',
    'assets/rewards/seed_premium.png',
  };
  // 只有通用图（分档图尚未放齐的历史状态）。
  const Set<String> legacy = <String>{'assets/rewards/seed.png'};

  RewardIconSpec seedSpec(bool? premium) => RewardIconSpec(
        kind: RewardIconKind.seed,
        seedSpeciesId: 'species_x',
        seedIsPremium: premium,
      );

  group('种子分档图解析（C20 修订：普通/精英分图）', () {
    test('精英档 → seed_premium.png', () {
      expect(
        resolveRewardAsset(seedSpec(true), full),
        'assets/rewards/seed_premium.png',
      );
    });

    test('普通档 → seed_common.png', () {
      expect(
        resolveRewardAsset(seedSpec(false), full),
        'assets/rewards/seed_common.png',
      );
    });

    test('档位未知（null，未传 isPremiumOf）→ 通用 seed.png', () {
      expect(
        resolveRewardAsset(seedSpec(null), full),
        'assets/rewards/seed.png',
      );
    });

    test('分档图缺失 → 回退通用 seed.png', () {
      expect(
        resolveRewardAsset(seedSpec(true), legacy),
        'assets/rewards/seed.png',
      );
      expect(
        resolveRewardAsset(seedSpec(false), legacy),
        'assets/rewards/seed.png',
      );
    });

    test('全部缺失 → null（回退内置 Icons.eco）', () {
      expect(resolveRewardAsset(seedSpec(true), const <String>{}), isNull);
      expect(resolveRewardAsset(seedSpec(false), const <String>{}), isNull);
    });
  });

  group('碎片 / 阳光解析护栏（不受分档改动影响）', () {
    test('fragment / sunlight 按固定路径解析、缺失回退 null', () {
      const RewardIconSpec frag = RewardIconSpec(
        kind: RewardIconKind.fragment,
        badge: '×3',
      );
      const RewardIconSpec sun = RewardIconSpec(
        kind: RewardIconKind.sunlight,
        badge: '+10',
      );
      expect(resolveRewardAsset(frag, full), 'assets/rewards/fragment.png');
      expect(resolveRewardAsset(sun, full), 'assets/rewards/sunlight.png');
      expect(resolveRewardAsset(frag, const <String>{}), isNull);
      expect(resolveRewardAsset(sun, const <String>{}), isNull);
    });

    test('礼包恒回 null（内置 Icons.card_giftcard）', () {
      expect(
        resolveRewardAsset(
          const RewardIconSpec(kind: RewardIconKind.gift),
          full,
        ),
        isNull,
      );
    });
  });

  group('rewardIconSpecsFor 档位派生', () {
    /// 构造一条「种子奖励」pending（阳光 / 碎片为 0，只掉种子）。
    PendingBloomReward seedPending() => PendingBloomReward(
          id: 'p1',
          plantId: 'plant1',
          dueAt: DateTime(2026, 10, 4),
          rewardKind: kBloomRewardKindNormal,
          claimed: false,
          rewardSunlight: 0,
          rewardFragments: 0,
          rewardSpeciesId: 'species_x',
        );

    test('isPremiumOf 提供时 → seedIsPremium 透传档位', () {
      final List<RewardIconSpec> specs = rewardIconSpecsFor(
        seedPending(),
        isPremiumOf: (String id) => true,
      );
      expect(specs.single.kind, RewardIconKind.seed);
      expect(specs.single.seedIsPremium, isTrue);
    });

    test('不给 isPremiumOf → seedIsPremium 为 null（走通用图）', () {
      final List<RewardIconSpec> specs = rewardIconSpecsFor(seedPending());
      expect(specs.single.seedIsPremium, isNull);
    });

    test('RewardIconSpec 相等性含新字段 seedIsPremium', () {
      expect(seedSpec(true), equals(seedSpec(true)));
      expect(seedSpec(true).hashCode, seedSpec(true).hashCode);
      expect(seedSpec(true), isNot(equals(seedSpec(false))));
      expect(seedSpec(true), isNot(equals(seedSpec(null))));
    });
  });
}
