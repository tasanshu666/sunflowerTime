import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';

/// 成株后循环玩法 Batch 1 的数据访问抽象（精品碎片货币 / 已解锁物种 / 第二段待收集奖励）。
///
/// 与 [PlantRepository] 分离（接口隔离）：本接口只承载「开花奖励 × 长期收集」相关的
/// 账户级账目，植物实例的增删改查仍归 [PlantRepository]。真实实现由 `PlantLocalRepository`
/// 一并提供（同一 `AppDatabase`）。
abstract class BloomRewardRepository {
  /// 精品碎片当前余额（玩家级货币，单例行；无记录视为 0）。
  Future<int> premiumFragmentBalance();

  /// 写入精品碎片余额（覆盖式，单例行 upsert）。
  Future<void> setPremiumFragmentBalance(int balance);

  /// 已解锁物种 id 集合（语义：**持有的免费种植券**；种子 / 碎片解锁均记账于此）。
  ///
  /// 玄参 2026-09-27 物种表改版后，「一朵种子掉落」= 该物种一张**免费种植券**，
  /// 种植时消耗券（见 [consumeUnlock]），不扣碎片 / 阳光。
  Future<Set<String>> unlockedSpeciesIds();

  /// 写入一张免费种植券（幂等，按 speciesId 主键冲突合并）。
  Future<void> unlockSpecies(String speciesId);

  /// 消耗一张免费种植券（删除该 speciesId 记录；**不存在则无副作用**，删除 0 行不报错）。
  Future<void> consumeUnlock(String speciesId);

  /// 写入一条待收集奖励记录（**幂等 upsert**：按 [PendingBloomReward.id] 冲突合并）。
  ///
  /// ⚠️ 契约要求**同 id 覆盖写安全**（不是裸 INSERT）：调用方可能以同 id 重写 `dueAt`
  /// （如调试面板让奖励「现在可领取」）。内存实现与 Drift 实现都必须按 upsert 语义实现，
  /// 否则真实库会抛 `UNIQUE constraint failed`（历史缺陷，2026-09-26）。
  Future<void> insertPendingBloomReward(PendingBloomReward reward);

  /// 读取所有「已到期且未发放」的待发奖励（`dueAt <= now && claimed == false`）。
  Future<List<PendingBloomReward>> pendingBloomRewardsDue(DateTime now);

  /// 标记某条待发奖励为已发放（幂等：已发放再标记无副作用）。
  Future<void> markPendingBloomRewardClaimed(String id);

  /// 回写某条待发奖励的「奖励内容」（v12 掉落即定奖）。
  ///
  /// 用途：历史行（三列零值哨兵 `0/0/null` = 未预先定奖）在**首次结算**时退回「现场 roll」，
  /// 把 roll 结果顺手回填该行（**不改 `claimed`**——领取状态由 [markPendingBloomRewardClaimed] 负责）。
  Future<void> updatePendingRewardContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  });
}
