import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';

/// [BloomRewardRepository] 的**内存实现**（无持久化）。
///
/// 用途：纯 Dart 单测 / 预览等无需 Drift 的场景（生产由 `PlantLocalRepository` 提供
/// 真实持久化实现，见 `core/di/providers.dart`）。行为与真实实现保持一致：
/// 碎片余额单例覆盖、物种解锁幂等、第二段待收集奖励按到期 + 未发放过滤。
class InMemoryBloomRewardRepository implements BloomRewardRepository {
  int _fragmentBalance = 0;
  final Set<String> _unlocked = <String>{};
  final List<PendingBloomReward> _pending = <PendingBloomReward>[];

  @override
  Future<int> premiumFragmentBalance() async => _fragmentBalance;

  @override
  Future<void> setPremiumFragmentBalance(int balance) async =>
      _fragmentBalance = balance;

  @override
  Future<Set<String>> unlockedSpeciesIds() async => Set<String>.of(_unlocked);

  @override
  Future<void> unlockSpecies(String speciesId) async {
    _unlocked.add(speciesId);
  }

  @override
  Future<void> consumeUnlock(String speciesId) async {
    _unlocked.remove(speciesId);
  }

  @override
  Future<void> insertPendingBloomReward(PendingBloomReward reward) async {
    _pending.removeWhere((PendingBloomReward r) => r.id == reward.id);
    _pending.add(reward);
  }

  @override
  Future<List<PendingBloomReward>> pendingBloomRewardsDue(DateTime now) async =>
      _pending
          .where((PendingBloomReward r) =>
              !r.claimed && !r.dueAt.isAfter(now))
          .toList();

  @override
  Future<void> markPendingBloomRewardClaimed(String id) async {
    for (int i = 0; i < _pending.length; i++) {
      if (_pending[i].id == id) {
        // 保留奖励内容（v12 掉落即定奖），仅翻转 claimed。
        _pending[i] = _pending[i].copyWith(claimed: true);
      }
    }
  }

  @override
  Future<void> deletePendingBloomReward(String id) async {
    _pending.removeWhere((PendingBloomReward r) => r.id == id);
  }

  @override
  Future<void> updatePendingRewardContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  }) async {
    for (int i = 0; i < _pending.length; i++) {
      if (_pending[i].id == id) {
        _pending[i] = _pending[i].copyWith(
          rewardSunlight: rewardSunlight,
          rewardFragments: rewardFragments,
          rewardSpeciesId: rewardSpeciesId,
        );
      }
    }
  }
}
