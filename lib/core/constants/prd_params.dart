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

/// 月度池默认值 · 高年级（PRD §4.8 E9：400 阳光/月）
const int kMonthlyPoolDefaultHigh = 400;

/// 月度池默认值 · 低年级（PRD §4.8 E9：160 阳光/月）
const int kMonthlyPoolDefaultLow = 160;

/// 月度池可调下限（PRD §4.8 E9：100–1,200）
const int kMonthlyPoolMin = 100;

/// 月度池可调上限（PRD §4.8 E9：100–1,200）
const int kMonthlyPoolMax = 1200;

// ───────────────────────────────────────────────────────────────────────────
// 口径巡检清单其它数字（预留，供 M1+ 引用，避免裸字面量；S1–S3 暂不全部使用）
// ───────────────────────────────────────────────────────────────────────────

/// 日软顶硬顶（PRD §4.5：当日原始产出 S>110 时日上限 79）
const double kSoftCapDailyMax = 79;

/// 软顶第一段上限（PRD §4.5：0–60 计 100%）
const int kSoftCapSeg1 = 60;

/// 软顶第二段上限（PRD §4.5：60–90 计 50%）
const int kSoftCapSeg2 = 90;

/// 软顶第三段上限（PRD §4.5：90–110 计 20%）
const int kSoftCapSeg3 = 110;

/// 软顶第二段计入比例（PRD §4.5：60–90 段 50%）
const double kSoftCapSeg2Rate = 0.5;

/// 软顶第三段计入比例（PRD §4.5：90–110 段 20%）
const double kSoftCapSeg3Rate = 0.2;

/// 有效专注成长速度系数（PRD §4.6 H2：当日有效专注 ≥15min → ×1.3，否则 ×1.0）
const double kGrowthFactorFocused = 1.3;

/// 夜间边界默认（PRD §6.1 H5：唯一值，默认 21:00，家长可放到 21:30–22:00）
const int kNightBoundaryDefaultHour = 21;

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
