/// 一次开花奖励的**实际发放结果**（玄参 2026-09-27「奖励物图标化 + 掉落即定奖」）。
///
/// 背景：旧实现「点击时才 roll」，结果只在服务内部用完即弃（返回 void），UI 无法知道
/// 到底掉了什么，只能吐模糊的「到手啦」。本对象把结果**显式回传**给调用方（花园页），
/// 以便头顶图标 / 提示文案由真实数据驱动。
///
/// 设计要点：
///  · **掉落即定奖**：奖励内容在「登记 pending」时（新盛开）就 roll 好并落库（见 `PendingBloomRewards`
///    的 `reward_sunlight / reward_fragments / reward_species_id` 三列），结算时**照单发放**、不再二次 roll；
///  · 历史行（三列为零值哨兵 `0/0/null`）在结算时退回「现场 roll」并回写，保证老 pending 奖励不丢；
///  · [sunlight] / [fragments] / [seedSpeciesId] 三者互斥关系随档位概率表（可能同时有阳光 + 碎片 /
///    阳光 + 种子；不会同时有碎片与种子）。
///
/// 纯 Dart、零 Flutter 依赖。
class BloomRewardOutcome {
  /// 本次入账阳光（可能为 0，如纯碎片 / 纯种子档）。
  final int sunlight;

  /// 本次入账**植物碎片**片数（0 = 无）。对用户显示为「植物碎片」，
  /// 内部标识符沿用 premium fragment（见 `prd_params` 注释）。
  final int fragments;

  /// 掉落种子的物种 id（null = 无）。落地为该物种一张**免费种植券**。
  final String? seedSpeciesId;

  /// 是否属于「开花瞬间」阶段（true）还是「第二段（花开 48h 后）」（false）——用于文案。
  final bool isInstantPhase;

  /// 是否由**花谢兜底自动到账**（true）而非小朋友手动点击收集（false）——用于文案。
  final bool autoSettled;

  /// 重复种子被自动分解时，**被分解的种子**物种 id（null = 本次不是重复种子分解）。
  ///
  /// 玄参 2026-09-29 口径：结算时若种子对应物种已持免费种植券 → 种子自动分解为
  /// 植物碎片（普通 3 / 精英 5，见 `prd_params`），此时 [seedSpeciesId] 为 null、
  /// [fragments] = 分解所得片数，本字段记录「分解前是哪颗种子」供 UI 提示文案。
  /// **瞬态字段，不落库**（pending 三列仍只存原始定奖内容，分解是结算规则）。
  final String? decomposedSeedSpeciesId;

  const BloomRewardOutcome({
    this.sunlight = 0,
    this.fragments = 0,
    this.seedSpeciesId,
    this.isInstantPhase = false,
    this.autoSettled = false,
    this.decomposedSeedSpeciesId,
  });

  /// 不可变副本（用于把「结算时现场 roll」的结果标记为 [autoSettled] 等）。
  BloomRewardOutcome copyWith({
    int? sunlight,
    int? fragments,
    String? seedSpeciesId,
    bool? isInstantPhase,
    bool? autoSettled,
    String? decomposedSeedSpeciesId,
  }) =>
      BloomRewardOutcome(
        sunlight: sunlight ?? this.sunlight,
        fragments: fragments ?? this.fragments,
        seedSpeciesId: seedSpeciesId ?? this.seedSpeciesId,
        isInstantPhase: isInstantPhase ?? this.isInstantPhase,
        autoSettled: autoSettled ?? this.autoSettled,
        decomposedSeedSpeciesId:
            decomposedSeedSpeciesId ?? this.decomposedSeedSpeciesId,
      );

  /// 是否含任何实际奖励（阳光 / 碎片 / 种子）。用于 UI 判断是否需要渲染图标。
  bool get hasAnyReward =>
      sunlight > 0 || fragments > 0 || seedSpeciesId != null;

  @override
  String toString() =>
      'BloomRewardOutcome(sunlight: $sunlight, fragments: $fragments, '
      'seed: $seedSpeciesId, decomposedSeed: $decomposedSeedSpeciesId, '
      'instant: $isInstantPhase, auto: $autoSettled)';
}
