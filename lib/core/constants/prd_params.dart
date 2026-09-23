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

/// 死亡返还比例（仅与养护挂钩，绝不因专注表现杀死；PRD §4.6）。
const double kPlantDeathRefundRate = 0.30;

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
/// 玄参大人 2026-09-22 改口径：每次 +5%，每天最多 [kPlantFertilizeMaxPerDay] 次 → 每天 +5%。
const double kPlantFertilizeProgressGain = 0.05;

/// 真实时间自动成长缩放系数（V2 起 = 1.0，不再额外缓速）。
///
/// 旧值 0.2 是为了压住「24 小时/阶段」带来的秒开花；V2 里
/// [kPlantGrowthHoursPerStageDefault] / [kPlantGrowthHoursPerStagePremium] 已经是
/// 「不养护也要 N 天长成」的**真实目标时长**，故不再额外缩放。
/// 每天最大推进 = 自动 24h/240h = 10% + 养护（3×1% + 5%）= 8% → 18%/阶段·天，
/// 勤快养护可把 30 天缩短到约 17 天。
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
