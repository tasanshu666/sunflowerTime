/// 待收集奖励记录（成株后循环玩法 Batch 1 / 玄参 2026-09-27「掉落即定奖」）。
///
/// 开花时写入**两条**记录（玄参 2026-09-26 变更 B：开花瞬间奖励也改为「掉落 + 手动收集」）：
///  · 开花瞬间：[rewardKind] = [kBloomRewardPhaseInstant]，`dueAt = bloomedAt`（即刻可收集）；
///  · 第二段：[rewardKind] = [kBloomRewardKindNormal]/[kBloomRewardKindPremium]（兼作档位），
///    `dueAt = bloomedAt + 48h`。
/// 到期后不再自动发放，而是在花盆旁掉落**奖励图标**，由小朋友**手动点击收集**。
/// 兜底：若对应花朵在收集前花谢 / 枯萎（不再盛开）或植物消失，则 `tickAll` 自动结算发放，
/// 保证奖励不丢失（`PlantGrowthService` 中 `_autoSettleUncollectibleRewards`）。
/// 领取后置 `claimed = true` 状态守卫，保证**每条仅发一次**。
///
/// ## 掉落即定奖（2026-09-27）：三列奖励内容
/// 登记 pending 时**当场 roll** 出奖励内容写入 [rewardSunlight] / [rewardFragments] /
/// [rewardSpeciesId]，结算（点击 / 兜底）时**照单发放**、不再 roll。UI 依据这三列渲染头顶图标。
///
/// ⚠️ **零值哨兵不变式**：历史行（本字段能力上线前登记的）三列必为 `0/0/null`，约定
/// **`0/0/null` = 「未预先定奖」**。任何真实奖励都至少有一列非零/非空（保底基础阳光恒 ≥1，
/// 故 [rewardSunlight] ≥1），二者不冲突。`_settlePendingReward` 命中该哨兵时退回旧「结算时现场
/// roll」路径并**回写**本行，保证老 pending 奖励金额不减、不多给。
///
/// 纯 Dart、零 Flutter 依赖。
class PendingBloomReward {
  /// 主键（uuid；每次新记录都生成唯一值）。
  final String id;

  /// 所属植物 id（对账 / 归属用）。
  final String plantId;

  /// 应发放（可收集）时刻。
  final DateTime dueAt;

  /// 阶段 + 档位标识（见类文档）：开花瞬间 = `'instant'`；第二段 = `'normal'` / `'premium'`。
  final String rewardKind;

  /// 是否已发放 / 已领取（true 后不再重复结算）。
  final bool claimed;

  /// 预先定好的入账阳光（片 / ☀；0 = 无阳光，或「未预先定奖」哨兵之一）。
  final int rewardSunlight;

  /// 预先定好的**植物碎片**片数（0 = 无碎片，或「未预先定奖」哨兵之一）。
  final int rewardFragments;

  /// 预先定好的掉落种子物种 id（null = 无种子，或「未预先定奖」哨兵之一）。
  final String? rewardSpeciesId;

  const PendingBloomReward({
    required this.id,
    required this.plantId,
    required this.dueAt,
    required this.rewardKind,
    this.claimed = false,
    this.rewardSunlight = 0,
    this.rewardFragments = 0,
    this.rewardSpeciesId,
  });

  /// 是否**已预先定奖**（非「零值哨兵」`0/0/null`）。命中哨兵者结算时退回现场 roll。
  bool get hasPreAssignedReward =>
      rewardSunlight != 0 || rewardFragments != 0 || rewardSpeciesId != null;

  /// 不可变副本（调试图标化「让奖励现在可领取」改写 `dueAt` 时须保留奖励内容）。
  PendingBloomReward copyWith({
    String? id,
    String? plantId,
    DateTime? dueAt,
    String? rewardKind,
    bool? claimed,
    int? rewardSunlight,
    int? rewardFragments,
    String? rewardSpeciesId,
  }) =>
      PendingBloomReward(
        id: id ?? this.id,
        plantId: plantId ?? this.plantId,
        dueAt: dueAt ?? this.dueAt,
        rewardKind: rewardKind ?? this.rewardKind,
        claimed: claimed ?? this.claimed,
        rewardSunlight: rewardSunlight ?? this.rewardSunlight,
        rewardFragments: rewardFragments ?? this.rewardFragments,
        rewardSpeciesId: rewardSpeciesId ?? this.rewardSpeciesId,
      );
}
