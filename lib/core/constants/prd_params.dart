library prd_params;

/// 《向日葵专注 SunFocus》PRD 参数单点（防孪生）。
///
/// 总纪律（口径裁定表 v1 总纪律 #2）：所有可调数值集中于此，逐条注释对应
/// PRD / 裁定 节号。任何文件出现第二个相同含义的字面量即为缺陷。
/// 口径巡检清单（MVP执行规划_v2 §7）数字全部须来自本文件。
///
/// 冲突裁决优先级：MVP执行规划_v2 > 口径裁定表_v1 > 开发计划 v1.0 > 验证计划 > PRD v2.0。

// ───────────────────────────────────────────────────────────────────────────
// C3「有效专注」同名不同义：两个不同用途的常量，不互相引用、不出现字面量 5/15/0.9
// ───────────────────────────────────────────────────────────────────────────

/// WFD：一个有效专注日（验证计划 §3.3 / PRD §8.3 北极星口径）
const int kValidFocusMinutes = 15;

/// 单次有效专注门槛（C3：§6.2；实际专注 < 5 分钟记 shortAborted、无产出）。
/// 与 [kValidFocusMinutes]=15 不互引、不共用——前者是「一次专注」下限，后者是「一天」口径。
const int kMinFocusMinutes = 5;

/// WFD：完成率门槛（同上）。completion_rate = actual_focus_min / duration_setting
const double kCompletionRateThreshold = 0.90;

// ───────────────────────────────────────────────────────────────────────────
// C5 免确认月上限 vs 可调月池（口径裁定表 v1 C5）
// 公式：monthlyAutoApproveCap = min(固定天花板, 当前月池 × 25%)
//       固定天花板：高年级 100 / 低年级 40
// 写死的 100/40 是天窗（上限），不是恒定值；池调低时上限随之降到 月池×25%。
// ───────────────────────────────────────────────────────────────────────────

/// 免确认单笔价上限 · 高年级（PRD §4.8 E6：单笔 ≤ 高 130）
const int kAutoApproveMaxCostHigh = 130;

/// 免确认单笔价上限 · 低年级（PRD §4.8 E6：单笔 ≤ 低 50）
const int kAutoApproveMaxCostLow = 50;

/// 月累计自动放行天花板 · 高年级（口径裁定 C5：固定天花板高 100）
const int kAutoApproveCapCeilingHigh = 100;

/// 月累计自动放行天花板 · 低年级（口径裁定 C5：固定天花板低 40）
const int kAutoApproveCapCeilingLow = 40;

/// 月池 25% 上限比例（口径裁定 C5：`月累计自动放行 ≤ 当月池 × 25%`）
const double kAutoApprovePoolRatio = 0.25;

/// 周阳光池默认预算 · 高年级（PRD §4.8 E9：400 阳光/周）
const int kPoolBudgetDefaultHigh = 400;

/// 周阳光池默认预算 · 低年级（PRD §4.8 E9：160 阳光/周）
const int kPoolBudgetDefaultLow = 160;

/// 周阳光池**可调下限**（玄参 2026-09-22 拍板：家长可自由调节，区间 50–500）。
///
/// 用于取代此前只写在 UI 里的裸字面量 50（`pool_indicator.dart`）。
const int kWeeklyPoolBudgetMin = 50;

/// 周阳光池**可调上限**（玄参 2026-09-22 拍板：原 1200 太大，收敛到 500）。
///
/// 注意与 [kMonthlyPoolMax]（月池遗留 1200）**不是同一回事**，勿混用。
const int kWeeklyPoolBudgetMax = 500;

/// 月度池可调下限（PRD §4.8 E9：100–1,200）
const int kMonthlyPoolMin = 100;

/// 月度池可调上限（PRD §4.8 E9：100–1,200）
const int kMonthlyPoolMax = 1200;

// ───────────────────────────────────────────────────────────────────────────
// 口径巡检清单其它数字（预留，供 M1+ 引用，避免裸字面量；S1–S3 暂不全部使用）
// ───────────────────────────────────────────────────────────────────────────

/// 成长奖励（成长项打卡）的**每日阳光上限**。
///
/// 玄参 2026-09-23 拍板：成长奖励**不占专注额度**，单独封顶。
///
/// 背景（口径变更，勿按旧文档理解）：此前专注与成长奖励共用一个「分段软顶」
/// （0–60 全额 / 60–90 计 50% / 90–110 计 20% / 硬顶 79），导致**专注拿满当天，
/// 孩子所有成长打卡奖励被挤成 0**，与「成长奖励不算在内」正好相反。本次同时：
///   · 专注侧**取消分段打薄**，改为 1 分钟 = 1 阳光，仅由年段日上限硬截断
///     （见 [kDailyFocusCapLow] / [kDailyFocusCapMid] / [kDailyFocusCapHigh]）；
///   · 成长奖励侧改为**按自身当日累计净额**直接封顶本值，与专注、家长赠予互不影响。
///
/// 取值沿用原软顶硬顶 79，保持奖励力度连续（不改数值，只改作用范围）。
const double kTaskCheckinDailyCap = 79;

/// 有效专注成长速度系数（PRD §4.6 H2：当日有效专注 ≥15min → ×1.3，否则 ×1.0）
const double kGrowthFactorFocused = 1.3;

/// 夜间边界默认（PRD §6.1 H5：唯一值，默认 21:00，家长可放到 21:30–22:00）
const int kNightBoundaryDefaultHour = 21;

/// 夜间边界可调档位（[时, 分]）：默认 21:00，家长端设置页下拉选择（PRD §6.1）。
const List<List<int>> kNightBoundaryOptions = <List<int>>[
  <int>[20, 30],
  <int>[21, 0],
  <int>[21, 30],
  <int>[22, 0],
];

/// 每日专注上限（分钟）：低年段（6–8 岁）。
///
/// 玄参 2026-09-22 拍板把三档改为「年龄越大、上限越高」：低 60 / 中 90 / 高 120。
/// （原实现是低=中=90、高=60，即高年段反而更少；PRD §6.1 的旧值 60/90 已据此作废。）
const int kDailyFocusCapLow = 60;

/// 每日专注上限（分钟）：中年段（9–10 岁）。
const int kDailyFocusCapMid = 90;

/// 每日专注上限（分钟）：高年段（11–12 岁）。
const int kDailyFocusCapHigh = 120;

// ───────────────────────────────────────────────────────────────────────────
// M2 经济与商店核销 · 基础层常量（T-A，§0 D5 / C1 / D4）
// ───────────────────────────────────────────────────────────────────────────

/// Plan B 单孩子固定 childId（§7.6 单点；AccountService.currentChildId 返回）。
const String kChildIdDefault = 'single-child';

/// 待核销 48h 兜底提示时长（小时，D5）。≥ 该时长未核销展示兜底文案。
const int kPendingReminderHours = 48;

/// 待核销 48h 兜底文案（D5 原文）。
const String kPendingReminderText = '这次的阳光奖励还在等你确认哦～';

/// 冷却默认每周限领次数（D4：每奖励每周限领 1 次）。
const int kCooldownWeeklyDefault = 1;

// ───────────────────────────────────────────────────────────────────────────
// M3 植物养成 / 家长赠予 常量（U1，数值直引 PRD §4.5 / §4.6；禁止裸字面量）
// ───────────────────────────────────────────────────────────────────────────

/// 家长阳光赠予 · 日上限（PRD §4.5：当日赠予 ≤ 20 阳光）。
const int kParentGiftDaily = 20;

/// 家长阳光赠予 · 月上限（PRD §4.5：当月赠予 ≤ 150 阳光）。
const int kParentGiftMonthly = 150;

/// 浇水消耗（M3 修订：**固定 5 阳光/次**，不再按年龄分档；口径由玄参大人 2026-09-21 拍板）。
const int kPlantWaterCost = 5;

/// 施肥消耗（M3 修订：**固定 10 阳光/次**，不再按年龄分档）。
const int kPlantFertilizeCost = 10;

/// 单株每日浇水次数上限（M3 修订：每天最多浇 3 次）。
const int kPlantWaterMaxPerDay = 3;

/// 单株每日施肥次数上限（M3 修订：每天最多施 1 次）。
const int kPlantFertilizeMaxPerDay = 1;

/// 两次浇水的最小间隔（分钟）：不能连续浇水（M3 修订）。
const int kPlantWaterIntervalMinutes = 30;

/// 花盆扩容消耗 · 高年段（PRD §4.6，解锁 +1 盆）。
const int kPlantPotExpandCostHigh = 400;

/// 花盆扩容消耗 · 低年段（PRD §4.6）。
const int kPlantPotExpandCostLow = 160;

/// 救回按钮已取消（2026-09-23 玄参大人拍板）：枯萎后只能靠养护动作恢复，
/// 不再有付费救回。故 `kPlantReviveCostLow` / `kPlantReviveCostHigh` 已删除。

/// 未浇水触发枯萎的天数（PRD §4.6 H2：3 天未浇水 → wilting；
/// 玄参大人 2026-09-23 由 7 天收紧为 3 天）。
const int kPlantWiltDays = 3;

/// 枯萎恢复判定阈值（天）：wilting 持续超过此天数视为「重度枯萎」，需「3 浇 + 1 施」才能恢复；
/// 未满则浇水 1 次即可恢复（玄参大人 2026-09-23 拍板，替代原付费救回）。
const int kPlantWiltRecoverHardDays = 3;

/// 重度枯萎恢复所需浇水次数（自 wiltedAt 起在账本累计的 `plant_water` 条数）。
const int kPlantWiltRecoverHardWater = 3;

/// 重度枯萎恢复所需施肥次数（自 wiltedAt 起在账本累计的 `plant_fertilize` 条数）。
const int kPlantWiltRecoverHardFertilize = 1;

/// 枯萎后触发死亡的天数（PRD §4.6 H2：wilting 再 7 天 → dead）。
const int kPlantDeathDays = 7;

/// 死亡返还比例 —— **已废止**（玄参 2026-09-27 拍板「死亡全损」）。
///
/// 植株死亡**不退还任何资源**（阳光不退、碎片不退），故 `kPlantDeathRefundRate` 已删除。
/// 历史账本中 `plant_death_refund` 行只读、不再产生新行（见 `child_sunlight_history_page`）。
/// 取而代之的「首购优惠」不在此处：某物种（阳光价 > 0，如月光兰）**首次**获取按阳光价、
/// 之后一律按档位碎片价，判据为阳光账本 `plant_plant` + `refId=物种 id`（见领域层 `plantCost`）。

/// 花园初始花盆容量（PRD §4.6 / §3.1 settings.garden_pot_capacity 默认）。
const int kGardenPotCapacityDefault = 4;

/// 花园最大花盆容量（PRD §4.6 解锁上限）。
const int kGardenPotCapacityMax = 12;

/// 每阶段成长所需时长（小时）· 普通植物（§3.1 plant_species，V2）。
///
/// 玄参大人 2026-09-22 拍板：完全不养护正好 **30 天**长成 → 3 阶段 × 10 天 = 240 小时/阶段。
const double kPlantGrowthHoursPerStageDefault = 240.0;

/// 每阶段成长所需时长（小时）· 精品植物（legendary，如仙人掌，V2）。
///
/// 同批拍板：精品植物不养护 **60 天**长成 → 3 阶段 × 20 天 = 480 小时/阶段。
const double kPlantGrowthHoursPerStagePremium = 480.0;

/// 浇水固定进度增量（当前阶段 0..1，绝对比例，非「剩余比例」）。
/// 玄参大人 2026-09-22 改口径：每次 +1%，每天最多 [kPlantWaterMaxPerDay] 次 → 每天至多 +3%。
const double kPlantWaterProgressGain = 0.01;

/// 施肥固定进度增量（当前阶段 0..1，绝对比例）。
///
/// 玄参大人 2026-09-22 定为 +5%；**2026-09-25 调为 +3%** —— 原话「施肥增长 5% 的进度有点快」。
/// 每天最多 [kPlantFertilizeMaxPerDay] 次 → 每天 +3%。
const double kPlantFertilizeProgressGain = 0.03;

/// 真实时间自动成长缩放系数（V2 起 = 1.0，不再额外缓速）。
///
/// 旧值 0.2 是为了压住「24 小时/阶段」带来的秒开花；V2 里
/// [kPlantGrowthHoursPerStageDefault] / [kPlantGrowthHoursPerStagePremium] 已经是
/// 「不养护也要 N 天长成」的**真实目标时长**，故不再额外缩放。
/// 每天最大推进 = 自动 24h/240h = 10% + 养护（3×1% + 3%）= 6% → 16%/阶段·天，
/// 勤快养护可把 30 天缩短到约 19 天（2026-09-25 施肥 5%→3% 后由 18%/17 天调整）。
const double kPlantAutoGrowthScale = 1.0;

/// 成长进度浮点容差（判定「本阶段长满 1.0」时允许的下限误差）。
///
/// `24h / 240h` 累加 10 次在 IEEE754 下是 0.9999999999999999 而非 1.0，严格
/// `>= 1.0` 会把「正好 10 天一阶段 / 30 天长成」推成 11 天 / 31 天。故用 1e-9
/// 容差判定，跨阶段时把残留的 -1e-16 归零。
const double kGrowthEpsilon = 1e-9;

/// 花期时长（天）：成株盛开后保持「盛开」状态的天数（玄参大人 2026-09-23 拍板循环玩法）。
///
/// 自然逻辑：盛开不能一直保持，花期结束后花朵凋谢、退回成株(growing)，
/// 由时间（自动成长）或养护（浇水/施肥）把进度重新养满后再度盛开。
/// 调小→花谢更快、循环更频；调大→花保持更久。
const int kBloomDurationDays = 3;

/// 花谢后进度回落下限（0..1）：花朵凋谢时 growthProgress 回退到的位置（玄参大人 2026-09-23 拍板）。
///
/// 不为 0 的原因：adult 阶段进度由自动成长每日回填（普通植物约 10%/天、精品约 5%/天），
/// 回落到该下限后需重新养满至 1.0 才能再盛开，从而制造一个可见的「休整期」
/// （普通植物约 (1-下限)/0.10 天，精品约 (1-下限)/0.05 天）。0.5 → 普通约 5 天 / 精品约 10 天。
const double kBloomWiltProgressFloor = 0.5;

// ───────────────────────────────────────────────────────────────────────────
// 成株后循环玩法 Batch 1（玄参大人拍板）：复开花节奏 + 花期双阶段奖励 + 精品碎片。
//
// 单点收口（宪法总纪律 #2）：下列增量 / 概率 / 区间 / 阈值全部集中于此，
// 任何服务或页面不得出现第二个相同含义的字面量。普通/精品双档差异化：
//   · 档位判定依据 [PlantSpecies.isPremium]（精品 = rare + legendary，见 `plant_species.dart`）；
//   · 复开花节奏：普通 7/14 天，精品 ×1.5（≈10.4/21 天）；
//   · 花期：普通 [kBloomDurationDays]（3 天），精品 [kBloomDurationDaysPremium]（4.5 天）。
//
// 校验口径（花谢回落下限 [kBloomWiltProgressFloor] = 0.5）：
//   普通 不养护 = 0.5 / 0.036 ≈ 14 天；满养护 = 0.5 / (0.036 + 3×0.008 + 0.012) ≈ 7 天。
//   精品 不养护 = 0.5 / (0.036 ÷ 1.5) ≈ 21 天；满养护 = 0.5 / (0.048 ÷ 1.5) ≈ 10.4 天。
// ───────────────────────────────────────────────────────────────────────────

/// 复开花期间**自动回填**速率（普通植物，进度/天）。独立于首长成的
/// [kPlantGrowthHoursPerStageDefault] 推导值（10%/天），使复开花节奏与物种解耦。
const double kRebloomAutoProgressPerDay = 0.036;

/// 复开花期间**每次浇水**进度增量（普通植物）。日 3 次 → 0.024/天。
const double kRebloomWaterProgressGain = 0.008;

/// 复开花期间**每次施肥**进度增量（普通植物）。日 1 次 → 0.012/天。
const double kRebloomFertilizeProgressGain = 0.012;

/// 精品植物复开花周期倍率：上述所有复开花增量 **÷ 本值**（节奏 ×1.5）。
/// 自动 0.036÷1.5 = 0.024/天；养护合计 (0.024+0.012)÷1.5 = 0.024/天。
const double kRebloomPremiumCycleMultiplier = 1.5;

/// 花期时长（天）· 精品植物。普通植物沿用 [kBloomDurationDays]（3 天）。
const double kBloomDurationDaysPremium = 4.5;

/// 开花瞬间**保底**基础阳光（100% 必给）· 普通植物。
const int kBloomInstantSunlight = 6;

/// 开花瞬间**保底**基础阳光（100% 必给）· 精品植物。
const int kBloomInstantSunlightPremium = 10;

/// 开花瞬间惊喜 · 精品碎片概率 · 普通植物（掉 1 片）。
const double kBloomInstantFragmentRate = 0.15;

/// 开花瞬间惊喜 · 精品碎片概率 · 精品植物（60% 掉 2 片 / 40% 掉 1 片）。
/// 玄参 2026-09-25 修订（变更 C）：精品档概率两阶段对齐，碎片 20%。
const double kBloomInstantFragmentRatePremium = 0.20;

/// 开花瞬间惊喜 · 精品碎片「掉 2 片」的条件概率 · 精品植物（否则掉 1 片）。
const double kBloomInstantFragmentDoubleRatePremium = 0.60;

/// 开花瞬间惊喜 · 本档物种种子概率 · 普通植物（掉普通物种种子）。
const double kBloomInstantSeedRate = 0.05;

/// 开花瞬间惊喜 · 本档物种种子概率 · 精品植物（掉精品物种种子）。
/// 玄参 2026-09-25 修订（变更 C）：精品档概率两阶段对齐，种子 10%。
const double kBloomInstantSeedRatePremium = 0.10;

/// 开花瞬间惊喜 · 大额阳光概率 · 普通植物。
const double kBloomInstantBonusRate = 0.20;

/// 开花瞬间惊喜 · 大额阳光概率 · 精品植物。
const double kBloomInstantBonusRatePremium = 0.25;

/// 大额阳光区间 · 普通植物（含端点）。
const int kBloomBonusSunlightMin = 10;
const int kBloomBonusSunlightMax = 20;

/// 大额阳光区间 · 精品植物（含端点）。
const int kBloomBonusSunlightMinPremium = 15;
const int kBloomBonusSunlightMaxPremium = 25;

/// 第二段奖励（花开后掉落待收集）的延迟（小时）。
///
/// 玄参 2026-09-25 修订（变更 A）：由 24h 改为 **48h**；第二段奖励不再是 tick 自动发放，
/// 而是到期后在花盆旁掉落气泡，由小朋友**手动点击收集**（见 `PlantGrowthService.collectBloomReward`）。
const int kBloomRewardDelayHours = 48;

/// 第二段奖励 · 精品碎片概率 · 普通植物（掉 1 片）。
///
/// 玄参 2026-09-26 拍板（普通档两阶段统一）：第二段碎片率由 0.10 提到 **0.15**，
/// 与开花瞬间档一致（瞬间/第二段两阶段统一为「碎片 15% / 普通种子 5% / 大额 20% / 兜底 60%」）。
const double kBloomSecondPhaseFragmentRate = 0.15;

/// 第二段奖励 · 精品碎片概率 · 精品植物（50% 掉 2 片 / 50% 掉 1 片）。
/// 玄参 2026-09-25 修订（变更 C）：精品档概率两阶段对齐，碎片 20%（数值不变，仅口径对齐）。
const double kBloomSecondPhaseFragmentRatePremium = 0.20;

/// 第二段奖励 · 精品碎片「掉 2 片」的条件概率 · 精品植物（否则掉 1 片）。
const double kBloomSecondPhaseFragmentDoubleRatePremium = 0.50;

/// 第二段奖励 · 本档物种种子概率 · 普通植物。
const double kBloomSecondPhaseSeedRate = 0.05;

/// 第二段奖励 · 本档物种种子概率 · 精品植物。
/// 玄参 2026-09-25 修订（变更 C）：精品档概率两阶段对齐，种子 10%（原 12%）。
const double kBloomSecondPhaseSeedRatePremium = 0.10;

/// 第二段奖励 · 大额阳光概率 · 普通植物。
const double kBloomSecondPhaseBonusRate = 0.20;

/// 第二段奖励 · 大额阳光概率 · 精品植物。
const double kBloomSecondPhaseBonusRatePremium = 0.25;

/// 第二段奖励 · 基础阳光区间 · 普通植物（含端点）。
const int kBloomSecondPhaseBaseSunlightMin = 3;
const int kBloomSecondPhaseBaseSunlightMax = 6;

/// 第二段奖励 · 基础阳光区间 · 精品植物（含端点）。
const int kBloomSecondPhaseBaseSunlightMinPremium = 6;
const int kBloomSecondPhaseBaseSunlightMaxPremium = 10;

/// 初始免费物种 id（向日葵）：阳光价 / 碎片价均为 0，任何孩子首颗可白嫖。
///
/// 玄参 2026-09-27 物种表改版：定价派生里它是「免费」的唯一特例（普通档其余物种按
/// [kSpeciesFragmentCostCommon] 收碎片），故单点收口于此常量，供 `plant_seed.dart`
/// 与领域层 `PlantGrowthService.plantCost`、花园页前置校验共用，杜绝裸字面量。
const String kStarterSpeciesId = 'species_sunflower';

/// 物种种植价 · 碎片 · **普通档**（番茄 / 草莓）。
///
/// 玄参 2026-09-27 物种表改版：按物种计价，普通档物种在物种列表**直接兑换并种下**
/// 需消耗 6 片精品碎片（取代原「满 8 片手动解锁精品物种」旧体系）。
const int kSpeciesFragmentCostCommon = 6;

/// 物种种植价 · 阳光 · **普通档**（番茄 / 草莓）。
///
/// 玄参 2026-09-28 计价模型拍板：普通档物种**二选一** —— **400 阳光** 或
/// **6 碎片**（[kSpeciesFragmentCostCommon]）兑换种下。此常量对应「用阳光兑换」分支；
/// 精英档（[kSpeciesFragmentCostPremium]）仅碎片、起始物种（[kStarterSpeciesId]）免费。
const int kSpeciesSunlightCostCommon = 400;

/// 物种种植价 · 碎片 · **精英档**（星辰花 / 虹影蕨 / 珊瑚岭兰 / 翡翠绣球 / 月光兰）。
///
/// 玄参 2026-09-27 物种表改版 + 2026-09-28 计价模型：精英档（= `rare`，见
/// `PlantSpecies.isPremium`）物种兑换**仅碎片**，需消耗 10 片精品碎片。
/// 月光兰（精英）不再走阳光价（旧的 [kSpeciesMoonOrchidSunlightCost] 已废弃）。
const int kSpeciesFragmentCostPremium = 10;

/// 重复种子自动分解 · 植物碎片数 · **普通档**（玄参 2026-09-29 拍板）。
///
/// 口径：种子掉落**允许重复**（不再排除已持券物种）；结算（手动收集 / 花谢兜底）时若
/// 该物种已持免费种植券 → 种子**自动分解**为 [kDuplicateSeedDecomposeFragmentsCommon]
/// 片植物碎片入账（券不重复写）。派生文案见花园页 `_outcomeParts`，勿散落字面量。
const int kDuplicateSeedDecomposeFragmentsCommon = 3;

/// 重复种子自动分解 · 植物碎片数 · **精英档**（玄参 2026-09-29 拍板）。
///
/// 精英档（= `rare`，见 `PlantSpecies.isPremium`）重复种子自动分解为 5 片
/// （[kSpeciesFragmentCostPremium] 为种植价，勿混用）。
const int kDuplicateSeedDecomposeFragmentsPremium = 5;

/// 账本 refType · 开花瞬间奖励（保底 + 惊喜 roll）。
const String kBloomRewardRefType = 'bloom_reward';

/// 账本 refType · 第二段（花开后掉落）奖励。
///
/// ⚠️ 常量名已随 Batch1 修订统一为 `SecondPhase`；但**字符串值 `'bloom_reward_24h'` 冻结不改**——
/// 它已写入历史账本，改名会破坏对既有记录的按 refType 对账（此值仅作写入标记，当前无运行时查询依赖）。
const String kBloomSecondPhaseRefType = 'bloom_reward_24h';

/// 待发奖励的**阶段**标识（落 `pending_bloom_rewards.reward_kind`）· **开花瞬间**。
///
/// 玄参 2026-09-26 变更 B：开花瞬间奖励不再即时入账，改为写入一条 `due = bloomedAt`
/// 的待收集记录（即刻可收集气泡），点击后才入账；花谢前未点则兜底自动到账。
/// 第二段（花开 48h 后掉落）阶段沿用 [kBloomRewardKindNormal] / [kBloomRewardKindPremium]
/// （该两值同时兼作第二段的档位标识，与历史行一致）。
const String kBloomRewardPhaseInstant = 'instant';

/// 第二段待发奖励的档位标识（落 `pending_bloom_rewards.reward_kind`）· 普通。
const String kBloomRewardKindNormal = 'normal';

/// 第二段待发奖励的档位标识 · 精品。
const String kBloomRewardKindPremium = 'premium';

// ───────────────────────────────────────────────────────────────────────────
// M3 任务模板配置常量（T05，§4.4 / §8.2）。禁止裸字面量。
// ───────────────────────────────────────────────────────────────────────────

/// 任务最少专注分钟默认值（§8.3 对齐 WFD 门槛 15）。
const int kTaskMinFocusDefault = 15;

/// 任务阳光奖励默认值（§4.4；用户 2026-09-21 拍板：非联动项默认 8 ☀）。
const int kTaskRewardDefault = 8;

/// 任务阳光奖励下限（§4.4 区间 5–15）。
const int kTaskRewardMin = 5;

/// 任务阳光奖励上限（§4.4；用户 2026-09-21 拍板：非联动项最大 15 ☀）。
const int kTaskRewardMax = 15;

/// 联动成长项奖励阳光比例上限：奖励 ≤ 最少专注分钟 × 40%（用户 2026-09-21 拍板）。
const double kTaskRewardRatio = 0.4;

// ───────────────────────────────────────────────────────────────────────────
// P0 · B 纪念册里程碑（§8.3 毕业纪念册）：类型标识 + 触发阈值单点收口。
// 玄参 2026-09-23 拍板采用以下 4 类；类型标识即 `milestone_event` 的 payload['type']，
// 阈值即「累计统计达到多少时视为新跨过该里程碑」。MemoirService 只引用本段常量，
// 禁止在服务或页面里写裸字面量（阈值与标识均在此单点收口）。
// ───────────────────────────────────────────────────────────────────────────

/// 里程碑 1「首个有效专注日」：类型标识。
const String kMilestoneFirstValidFocusDayType = 'first_valid_focus_day';

/// 里程碑 1 阈值：累计有效专注日数 ≥ 本值即达成（首个有效专注日 = 1）。
const int kMilestoneFirstValidFocusDayDays = 1;

/// 里程碑 2「累计专注满 600 分钟」：类型标识。
const String kMilestoneFocusTotal600MinType = 'focus_total_600min';

/// 里程碑 2 阈值：累计专注分钟数 ≥ 本值即达成（600 分钟 = 10 小时）。
const int kMilestoneFocusTotal600MinMinutes = 600;

/// 里程碑 3「累计有效专注日满 30 天」：类型标识。
const String kMilestoneValidDays30Type = 'valid_days_30';

/// 里程碑 3 阈值：累计有效专注日数 ≥ 本值即达成（30 天）。
const int kMilestoneValidDays30Days = 30;

/// 里程碑 4「首株植物开花」：类型标识。
const String kMilestoneFirstBloomType = 'first_bloom';

/// 里程碑 4 阈值：累计开花植物数 ≥ 本值即达成（首株开花 = 1）。
const int kMilestoneFirstBloomCount = 1;

// ───────────────────────────────────────────────────────────────────────────
// 序列帧动效与花园氛围音（玄参 2026-09-28 素材落地）。禁止裸字面量。
//
// 素材契约（`docs/美术资源_序列帧与音频命名规范_v1.md` + 交付实况）：
//   · 序列帧目录 `assets/fx/grow/{物种}/{过渡名}/frame001..N.png`（三位零填充）与
//     `assets/fx/care/{water|fertilize}/frame001..N.png`；
//   · **每帧时长 = 音频时长 / 帧数**（玄参口径：「动画帧的播放速度与对应的音频时间
//     保持一致」）——下列时长常量来自对交付 mp3 的 ffprobe 实测（192kbps）；
//   · 花园氛围音 `assets/audio/bgm/background.mp3`（10s），花园 tab 每
//     [kGardenAmbientIntervalSeconds] 秒播一次、离开即停（玄参拍板）。
// ───────────────────────────────────────────────────────────────────────────

/// 序列帧文件名起始编号（三位零填充，`frame001.png` 起）。
const int kFxFirstFrameNumber = 1;

/// 序列帧文件名位数（`frame001` → 3 位零填充）。
const int kFxFrameDigits = 3;

/// 每组序列帧的帧数（本次交付五组均为 25 帧；后续组数不同时在此按组拆分）。
const int kFxFrameCount = 25;

/// 成长过渡帧 · 播放时长（毫秒）· 种子→幼苗（= 音频 4.10s，25 帧 ≈164ms/帧）。
const int kGrowSeedToSproutDurationMs = 4100;

/// 成长过渡帧 · 播放时长（毫秒）· 幼苗→成株（= 音频 4.10s）。
const int kGrowSproutToAdultDurationMs = 4100;

/// 成长过渡帧 · 播放时长（毫秒）· 成株→盛开（= 音频 4.10s）。
const int kGrowAdultToBloomedDurationMs = 4100;

/// 浇水效果帧 · 播放时长（毫秒）（= 音频 2.90s，25 帧 ≈116ms/帧）。
const int kCareWaterDurationMs = 2900;

/// 施肥效果帧 · 播放时长（毫秒）（= 音频 3.06s，25 帧 ≈122ms/帧）。
const int kCareFertilizeDurationMs = 3056;

// ── 除草 / 除虫效果帧（2026-10-03 玄参交付，27 帧 720×720）─────────────────
// 交互口径（玄参 2026-10-03）：点干扰物 → 播效果帧 + 音效（帧速 = 音频时长）→
// 播完干扰物渐变消失 → 花盆上方弹「XX成功，阳光+N」飘字（自下而上飘动淡出）。

/// 除草效果帧 · 帧数（`assets/fx/care/weed/` 27 帧；⚠️ 与 [kFxFrameCount] 25 不同组）。
const int kCareWeedFrameCount = 27;

/// 除虫效果帧 · 帧数（`assets/fx/care/pest/` 27 帧）。
const int kCarePestFrameCount = 27;

/// 除草效果帧 · 播放时长（毫秒）（= `care_weed.mp3` 4.10s，27 帧 ≈152ms/帧）。
const int kCareWeedDurationMs = 4101;

/// 除虫效果帧 · 播放时长（毫秒）（= `care_pest.mp3` 4.10s，27 帧 ≈152ms/帧）。
const int kCarePestDurationMs = 4101;

/// 除草效果帧 · 落点横向锚点（帧内比例；left = 盆心x − anchorX × 帧宽）。
///
/// 2026-10-03 玄参三轮微调：0.5 → 0.42 → **0.36**（逐轮「往右一点」= anchorX 减小）。
const double kCareWeedAnchorX = 0.36;

/// 除虫效果帧 · 落点横向锚点（口径同 [kCareWeedAnchorX]）。
///
/// 2026-10-03 玄参三轮微调：0.5 → 0.40 → **0.34**（药团/罐子逐轮右移，高度已定稿）。
const double kCarePestAnchorX = 0.34;

/// 除草效果帧 · 落点纵向锚点（帧内 y 比例，1.0 = 帧底贴盆口线）。
///
/// 2026-10-03 玄参两轮微调：1.0（铲子悬空）→ 0.56（落进盆土）→ **0.64**
/// （「往上一点」= anchorY 增大 = 帧上移）。
const double kCareWeedAnchorY = 0.64;

/// 除虫效果帧 · 落点纵向锚点（口径同 [kCareWeedAnchorY]）。
const double kCarePestAnchorY = 0.52;

/// 除虫效果帧 · 上下往复摆动幅度（逻辑像素，0 = 不摆）。
///
/// 玄参 2026-10-03：「喷在花盆土的位置，**或者上下来回喷一下**」——两条都做：
/// 帧整体下沉对准盆土，再叠加 ±[kCarePestBobPx] 的上下往复（两个来回），
/// 呈现「来回喷」的动感。除草是插入动作不摆。
const double kCarePestBobPx = 8;

/// 除虫效果帧 · 上下往复摆动次数（播放全程内的完整来回数）。
const double kCarePestBobCycles = 2;

/// 除草 / 除虫飘字 · 上飘总时长（毫秒）：弹出后自下而上飘动并淡出，走完自移除。
const int kClearHintRiseMs = 1600;

/// 除草 / 除虫飘字 · 上飘总距离（逻辑像素，向上为负）。
const double kClearHintRiseDistance = 36;

/// 播完效果帧后干扰物（杂草 / 蝗虫）**渐变消失**的时长（毫秒）：
/// 数据已写库，UI 先淡出该浮标再刷新草地（玄参口径「播放完杂草渐变消失」）。
const int kPestFadeOutMs = 300;

/// 成长过渡动画播完后的渐隐时长（毫秒）——玄参口径「播放完就可以直接渐变消失」。
const int kFxDisplayFadeOutMs = 300;

// ── 专注页向日葵序列帧（玄参 2026-09-29 素材落地）────────────────────────────
// 目录：`assets/fx/focus/sunflower/{idle|collect|settle|return}/frame001..N.png`
//（三位零填充、从 001 起，播放顺序 = 文件名字典序）；目录常量见
// `frame_sequence_player.dart` 的 kFocus*FxDir。
// 每帧时长 = 音频时长 / 帧数（时长常量来自交付 mp3 的 afinfo 实测）。

/// 专注页 · 常态 idle 循环帧数（玄参 2026-09-30 替换 idle 为「向日葵看书」序列，由 46 增至 60 帧；5fps = 200ms/帧）。
const int kFocusIdleFrameCount = 60;

/// 专注页 · 1/3 进度收集阳光帧数（40 帧）。
const int kFocusCollectFrameCount = 40;

/// 专注页 · 结算庆祝帧数（36 帧）。
const int kFocusSettleFrameCount = 36;

/// 专注页 · 回来（欢迎）帧数（30 帧）。
const int kFocusReturnFrameCount = 30;

/// idle 循环单圈时长（毫秒）——玄参指定 5fps（200ms/帧），60 帧整圈 = 12000ms（12s），
/// 慢节奏不抢注意力。
const int kFocusIdleLoopDurationMs = 12000;

/// 收集阳光帧 · 播放时长（毫秒）= `focus_collect.mp3` 10.08s（40 帧 ≈252ms/帧）。
const int kFocusCollectDurationMs = 10083;

/// 结算庆祝帧 · 播放时长（毫秒）= `focus_settle.mp3` 6.09s（36 帧 ≈169ms/帧）。
const int kFocusSettleDurationMs = 6087;

/// 回来帧 · 播放时长（毫秒）= `welcome_back.mp3` 5.09s（30 帧 ≈170ms/帧）。
const int kFocusReturnDurationMs = 5094;

/// 自由专注 · 随光报信间隔（分钟）。
///
/// 自由模式（玄参 2026-09-30 拍板）：不预设时长、孩子自己决定何时结束、软件不做
/// 到时提醒；计时与产出照常，防沉迷底线（离席打断 / 日上限结算截断）不变。
/// 无计划时长的 1/3 进度无处安放，lvl2「收集阳光」改为**每满该间隔**触发一次。
const int kFreeFocusCollectIntervalMinutes = 15;

/// 专注页 · 收集阳光 / 欢迎回来 切换时的**交叉淡入淡出**时长（毫秒）。
///
/// 玄参 2026-09-30 反馈 idle↔collect/welcome 切换生硬突兀：舞台改为 idle 常驻底层、
/// 切换时在新相位之上叠层做交叉淡入（idle 渐隐、新相位渐显），播完再交叉淡出回 idle，
/// 使画面过渡平滑（不再硬切）。250ms 足够柔和不拖沓。
const int kFocusTransientCrossfadeMs = 250;

/// 专注页 · 「今日额度用完」轻提示卡驻留时长（秒）。
///
/// 玄参 2026-09-30 拍板：自由专注（无计划时长）下额度用完，不再新增额度看护
/// 定时器轮询——复用专注页既有秒级 tick 判定一次，命中后在**屏幕左上角**轻弹
/// 一张小卡（远离居中的向日葵，不遮挡），驻留本时长后自动淡出，**整场只弹一次**；
/// 超额的完整说明放在结算页（见 `settle_page.dart`）。
const int kFocusQuotaHintSeconds = 8;

/// 专注页向日葵舞台边长（逻辑像素）。
///
/// 玄参 2026-09-30 反馈「向日葵需要缩小显示」：横屏逻辑高约 360dp，原 320 几乎
/// 占满全高，收敛为 220（约占屏高 61%，时间区与底部提示各留出空间）。
const double kFocusStageSize = 220;

/// 欢迎回来最短离席门槛（秒）——玄参 2026-09-30 反馈「欢迎回来太灵敏，
/// 不在专注界面立刻触发」：离席 < 此值（默认 30s，如息屏几秒又亮）恢复在场时
/// 不弹「欢迎回来」、不播欢迎音，仅静默恢复（避免误触）。
const int kWelcomeBackMinAbsentSeconds = 30;

/// 成长过渡动画相对花盆格的放大倍数（居中放大演出，玄参拍板「居中放大演出」）。
const double kGrowFxScale = 1.4;

/// 花园氛围音资源路径（BGM 目录，玄参 2026-09-28 交付）。
const String kGardenAmbientAsset = 'assets/audio/bgm/background.mp3';

/// 花园氛围音播放间隔（秒）：进入花园立即播一次，之后每隔 N 秒再播一次。
const int kGardenAmbientIntervalSeconds = 30;

// ── 花园格几何（与 `garden_pot.dart` / `care_effect_overlay.dart` 共享）──────
// ⚠️ 只此一份：养护效果帧要按「盆口（根部）」精确定位，必须复用与花盆格完全相同的
// 布局参数。改这里 = 改花园格布局，务必同步跑 widget 测试与真机目检。

/// 美术图统一画布宽高比（高 / 宽 = 2000 / 1200 = 5/3，宪法 C13）。
const double kGardenArtAspect = 2000 / 1200;

/// 美术图宽占格宽比例。
const double kGardenArtWidthRatio = 0.86;

/// 花盆图下方「进度条 + 标签」区的固定高度（三类格子共用，保证同行盆底对齐）。
const double kGardenPotFooterHeight = 32;

/// 格子横向内边距。
const double kGardenCellHorizontalPad = 2;

/// 格子纵向内边距（上下各 4）。
const double kGardenCellVerticalPad = 4;

/// **盆口（土面 / 植物根部）在植物画布高度上的比例**。
///
/// 实测依据：`assets/pots/pot.png`（1200×2000）内容 alpha bbox y = 1318~2000 →
/// 1318 / 2000 = 0.659。浇水 / 施肥效果必须落在这条线上（玄参口径「落在植物根部，
/// 而不是花盆底部」）。
const double kPotRimYFraction = 0.659;

// ── 养护效果帧落点锚点（实测 `assets/fx/care/*` 得出）──────────────────────
// 效果帧是 720×720 纯效果层：水壶 / 肥料袋在画布上方偏右，水柱 / 肥粒自左上往右下
// 流到画布**底边**（实测底部内容横向中心：water ≈ 0.21、fertilize ≈ 0.31）。
// 播放时把「落点」对齐盆口：帧底边 = 盆口 y，横向按锚点回推左边缘 →
// 水 / 肥恰好浇在植物根部，壶则自然位于植株上方偏右。

/// 浇水：水流末端在帧画布上的横向比例（相对帧宽）。
const double kCareWaterAnchorX = 0.21;

/// 施肥：肥粒末端在帧画布上的横向比例（相对帧宽）。
const double kCareFertilizeAnchorX = 0.31;

/// 效果落点在帧画布上的纵向比例（1.0 = 画布底边）。
const double kCareFxAnchorY = 1.0;

/// 效果帧显示宽度 = 格宽 × 本值（玄参口径：略大于格宽、允许越出格子边界）。
const double kCareFxWidthRatio = 1.15;

// ── 成长演出「中央焦点卡片」几何（玄参 2026-09-29 拍板）─────────────────────

/// 中央卡片宽度 = 屏幕短边 × 本值。
const double kGrowFxCardWidthRatio = 0.78;

/// 中央卡片圆角半径。
const double kGrowFxCardRadius = 24;

// ── 杂草 / 害虫（花园干扰物玩法，玄参 2026-09-30 拍板，口径 C26）────────────
// 每株**活的**植物每天各自 roll 一次：杂草 [kGardenWeedRate] / 害虫 [kGardenPestRate]
// 互相独立、**可同时出现**（同一天同一盆可以既有草又有虫）。
//  · 杂草 / 害虫只在其出现的**当天**有效：次日每日 roll 时自动清掉（不会永久卡成长）；
//  · 存在期间该株**成长暂停**（当天不涨进度），点掉图标即恢复；
//  · 拔草 +[kGardenWeedReward] 阳光 / 除虫 +[kGardenPestReward] 阳光，走账本入账。

/// 杂草出现概率（每株每天独立 roll；口径 C26）。
const double kGardenWeedRate = 0.40;

/// 害虫出现概率（每株每天独立 roll，与 [kGardenWeedRate] 互不排斥 → 可同时出现）。
const double kGardenPestRate = 0.25;

/// 拔草奖励阳光。
const double kGardenWeedReward = 1;

/// 除虫奖励阳光。
const double kGardenPestReward = 2;

/// 账本 `refType`：拔草。
/// ⚠️ 字符串值**一经写入即冻结**（append-only 对账源）：改名只能改常量名，
/// 不改本值，否则历史行与新行的 tag 分裂。新增 refType 必须同步
/// `child_sunlight_history_page.dart` 的 `_refLabels`，否则孩子端显示「其他」。
const String kGardenWeedRefType = 'plant_weed';

/// 账本 `refType`：除虫（冻结约束同 [kGardenWeedRefType]）。
const String kGardenPestRefType = 'plant_pest';

/// 杂草 emoji（**回退**：`kGardenWeedAsset` 图片加载失败时显示）。
const String kGardenWeedEmoji = '🌿';

/// 害虫 emoji（**回退**：`kGardenPestAsset` 图片加载失败时显示）。
const String kGardenPestEmoji = '🦗';

/// 杂草美术图（2026-10-03 玄参提供；**长在花盆里面**——盆口土面上，裸图直贴无白底）。
/// 加载失败回退 [kGardenWeedEmoji]，`assets/garden/` 已按目录登记进包。
const String kGardenWeedAsset = 'assets/garden/weed.png';

/// 蝗虫美术图（2026-10-03 玄参提供；**趴在花盆上**——盆身位置，横构图）。
/// 加载失败回退 [kGardenPestEmoji]。
const String kGardenPestAsset = 'assets/garden/pest.png';

// ───────────────────────────────────────────────────────────────────────────
// C28 少儿护眼休息（20-20-20 变体·特色功能，玄参 2026-10-03 初稿 / 2026-10-04 收口）
//
// 单点纪律（宪法总纪律 #2）：护眼的**节奏 / 时长 / 奖励 / 提示文案**全部收口在这里，
// 任何页面不得再出现第二个相同含义的字面量（尤其「63」「+2」「20 分钟」「10 分钟」
// 与那句「不可跳过」）。
//
// 三条口径锚点（口径裁定表 v1 C28，2026-10-05 素材定稿修订）：
//  · 场内「累计注视每满 N 分钟」＝一次护眼，护眼期间**计时暂停**、不计入专注时长、不产光；
//  · 场末「距上次护眼之后的本段注视 ≥ [kEyeCareSessionEndMinutes] 分钟」→ **结算页之前**
//    插一次护眼卡（先护眼、后领奖励，防孩子为拿奖励跳过护眼）；
//  · **单次护眼总时长固定，家长端不设、不可调**（玄参 2026-10-04 拍板砍掉设置项；
//    2026-10-05 交付 5 段素材定稿节奏：10+10+8+10×3+5 = 63s，见 [kEyeCarePlaylist]）。
// ───────────────────────────────────────────────────────────────────────────

/// 护眼提醒**总开关**默认值（家长端默认开）。
const bool kEyeCareEnabledDefault = true;

/// 护眼触发**间隔**（分钟）默认值：场内累计注视每满 20 分钟 → 一次护眼。
const int kEyeCareIntervalMinDefault = 20;

/// 护眼触发间隔**合法下限**（分钟）：家长端下拉档位不能低于此值。
const int kEyeCareIntervalMinMin = 5;

/// 护眼触发间隔**合法上限**（分钟）。
const int kEyeCareIntervalMinMax = 60;

/// 家长端「护眼触发间隔」可选档位（分钟，含默认值 20）。
const List<int> kEyeCareIntervalOptions = <int>[5, 10, 15, 20, 30];

/// 是否**允许孩子跳过**护眼卡默认值（默认允许；跳过不发奖励）。
const bool kEyeCareSkipAllowedDefault = true;

/// 单次护眼**总时长**（秒）——固定值，**家长端不设、不可调**（玄参 2026-10-04 拍板；
/// 2026-10-05 素材定稿由 60 → **63**：5 段素材的排布 10+10+8+10×3+5 = 63s）。
///
/// 显示倒计时用；真实播放总长 = [kEyeCarePlaylist] 各段 `durationMs` 之和（≈63.7s，
/// 以音频实长为准，见 [kEyeCarePlaylistTotalMs]）。
const int kEyeCareDurationSeconds = 63;

/// 护眼卡**播放列表**（2026-10-05 玄参交付素材定稿）：5 套素材按序排 7 个槽位——
/// ①闭眼转眼球(10s) → ②再来一次(10s) → ③远眺提示(8s) → ④远眺×3(10s) → ⑤结束(5s)。
///
/// 每段 = 一组序列帧（`assets/fx/eyecare/<dir>/frame001..N.png`，720×720 整幅画面
/// 带背景、不归一化）+ 一段配音 mp3；**帧速 = 帧数 ÷ 音频时长**（项目既有契约）。
/// ⚠️ 段④ `look` 在列表中出现 3 次（同一套素材连播，不是三份拷贝）。
class EyeCareSegment {
  /// 帧目录（`assets/fx/eyecare/` 下，禁止改动——与交付目录一一对应）。
  final String dir;

  /// 配音 mp3 asset 路径。
  final String sfxAsset;

  /// 本段帧数（已核：交付无缺号，见护栏测试）。
  final int frameCount;

  /// 本段播放时长（毫秒）= 配音实长（afinfo 实测，帧速 = 帧数 ÷ 时长）。
  final int durationMs;

  /// 屏幕阶段标题（配音已含口令，这里只做简短同步字幕）。
  final String label;

  const EyeCareSegment({
    required this.dir,
    required this.sfxAsset,
    required this.frameCount,
    required this.durationMs,
    required this.label,
  });
}

/// 段① 闭眼 + 转眼球提示（`eyecare_close.mp3` 10.16s，67 帧）。
const EyeCareSegment kEyeCareSegClose = EyeCareSegment(
  dir: 'assets/fx/eyecare/close',
  sfxAsset: 'assets/audio/sfx/eyecare_close.mp3',
  frameCount: 67,
  durationMs: 10162,
  label: '闭上眼睛，转动眼球',
);

/// 段② 再来一次转眼球（`eyecare_doitagain.mp3` 10.08s，67 帧）。
const EyeCareSegment kEyeCareSegAgain = EyeCareSegment(
  dir: 'assets/fx/eyecare/doitagain',
  sfxAsset: 'assets/audio/sfx/eyecare_doitagain.mp3',
  frameCount: 67,
  durationMs: 10083,
  label: '再来一次，转动眼球',
);

/// 段③ 远眺提示（`eyecare_lookTip.mp3` 8.10s，53 帧）。
const EyeCareSegment kEyeCareSegLookTip = EyeCareSegment(
  dir: 'assets/fx/eyecare/lookTip',
  sfxAsset: 'assets/audio/sfx/eyecare_lookTip.mp3',
  frameCount: 53,
  durationMs: 8098,
  label: '睁开眼睛，望向远处',
);

/// 段④ 远眺本体（`eyecare_look.mp3` 10.08s，67 帧）——播放列表复用 3 次。
const EyeCareSegment kEyeCareSegLook = EyeCareSegment(
  dir: 'assets/fx/eyecare/look',
  sfxAsset: 'assets/audio/sfx/eyecare_look.mp3',
  frameCount: 67,
  durationMs: 10083,
  label: '望着远处，放松眼睛',
);

/// 段⑤ 结束提示（`eyecare_done.mp3` 5.09s，33 帧）。
const EyeCareSegment kEyeCareSegDone = EyeCareSegment(
  dir: 'assets/fx/eyecare/done',
  sfxAsset: 'assets/audio/sfx/eyecare_done.mp3',
  frameCount: 33,
  durationMs: 5094,
  label: '眼睛休息好啦！',
);

/// 护眼 63s 播放列表（7 个槽位；顺序即播放顺序，玄参 2026-10-05 拍板）。
const List<EyeCareSegment> kEyeCarePlaylist = <EyeCareSegment>[
  kEyeCareSegClose,
  kEyeCareSegAgain,
  kEyeCareSegLookTip,
  kEyeCareSegLook,
  kEyeCareSegLook,
  kEyeCareSegLook,
  kEyeCareSegDone,
];

/// 播放列表真实总时长（毫秒）= 各段 `durationMs` 之和（63.7s；显示口径取
/// [kEyeCareDurationSeconds] = 63s，两者差 <1s，以播放列表收尾为准）。
const int kEyeCarePlaylistTotalMs = 10162 + 10083 + 8098 + 10083 * 3 + 5094;

/// 完整完成一次护眼的**奖励阳光**（玄参 2026-10-03 拍板：+2）。
const int kEyeCareRewardSunlight = 2;

/// 场末（结算页之前）插入护眼卡的**本段注视门槛**（分钟）：≥ 该值才打断，
/// 本段 < 该值不打断（交给「每 2 场休 10 分钟」大休息兜底）。
const int kEyeCareSessionEndMinutes = 10;

/// 账本 `refType`：护眼完成。
/// ⚠️ 字符串值**一经写入即冻结**（append-only 对账源）：改名只能改常量名，不改本值，
/// 否则历史行与新行的 tag 分裂。新增 refType 必须同步 `child_sunlight_history_page.dart`
/// 的 `_refLabels`（现在指向 [kEyeCareRefLabel]「护眼」），否则孩子端显示「其他」。
const String kEyeCareRefType = 'eye_care_break';

/// 孩子端阳光来源里 `eye_care_break` 的显示文案（单点）。
const String kEyeCareRefLabel = '护眼';

/// 「不可跳过」提示文案（**单点收口，便于后期改词**）：家长关掉「允许跳过」时点跳过、
/// 以及护眼卡期间按系统返回键被拦截时，都弹这一句。
const String kEyeCareNotSkippableText = '不可跳过，请爱护眼睛';

/// 允许跳过时点「跳过」的**二次确认**文案（确认才生效，取消＝回护眼卡继续休息）。
const String kEyeCareSkipConfirmText = '跳过就没有小阳光啦，真的要跳过吗？';

/// 护眼卡主按钮文案（完成的唯一入口，"不可跳过"时也是唯一出路）。
const String kEyeCareFinishLabel = '完成休息';

/// 护眼卡副按钮文案（**恒存在**——家长关「允许跳过」时点了无效并弹提示，而非隐藏）。
const String kEyeCareSkipLabel = '跳过';
