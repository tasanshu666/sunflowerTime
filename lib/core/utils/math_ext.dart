/// 经济计算工具：软顶公式（§4.5）、分龄换算（K 仅作用于消耗侧）。
/// 对应架构设计 §3.2（软顶可追溯）、§4.5（公式③）。
library math_ext;

import 'package:sunflower_time/core/constants/app_constants.dart';

/// 软顶（每日产出上限）计算骨架。
///
/// 设计铁律（§3.2）：产出侧不乘 K；单一 append-only 账本 `sunlight_ledger`，
/// 每条 earn 同时记 `gross=S` 与 `net=有效阳光`，`day_key` 可日聚合，审计可还原
/// 「原始 S=162 → 实得 79」。
///
/// 公式（§4.5 公式③，分段）：
///   S ≤ 60   → 有效 = S
///   60<S≤90  → 有效 = 60 + (S-60)*0.5
///   90<S≤110 → 有效 = 75 + (S-90)*0.2
///   S >110   → 有效 = 79（封顶，与口径巡检清单 `79` 对应）
double computeSoftCap(double rawS) {
  if (rawS <= 60) return rawS;
  if (rawS <= 90) return 60 + (rawS - 60) * 0.5;
  if (rawS <= 110) return 75 + (rawS - 90) * 0.2;
  return 79; // 软顶封顶
}

/// 分龄换算骨架：消耗侧定价乘 K（分龄系数）。
///
/// K 仅作用于消耗侧（§0 产出侧不乘 K）。此处返回「含 K 的消耗成本」，
/// 真实 K 由 `Settings.ageTier` + `redemption_service` 在 M2 落地。
double applyAgeTierK(double baseCost, double k) => baseCost * k;

/// 免确认月度自动放行上限（C5）：
/// `min(固定天花板 100/40, 月池 × 25%)`。
double autoApproveMonthlyCap(double monthlyPoolBudget, {double ceilingHigh = 100, double ceilingLow = 40}) {
  final capFromPool = monthlyPoolBudget * kAutoConfirmMonthlyPct;
  // 高年段取 100/低年段 40 为天花板；骨架阶段统一用 min，M2 按 ageTier 分流。
  final ceiling = ceilingHigh < ceilingLow ? ceilingHigh : ceilingLow; // 占位：实际按 ageTier 选 100 或 40
  final chosen = ceiling == ceilingHigh ? ceilingHigh : ceilingLow;
  return (capFromPool < chosen ? capFromPool : chosen);
}
