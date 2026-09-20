/// 经济计算工具：软顶公式（§4.5）、分龄换算（K 仅作用于消耗侧）。
/// 对应架构设计 §3.2（软顶可追溯）、§4.5（公式③）。
library math_ext;

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 软顶（每日产出上限）计算骨架。
///
/// 设计铁律（§3.2）：产出侧不乘 K；单一 append-only 账本 `sunlight_ledger`，
/// 每条 earn 同时记 `gross=S` 与 `net=有效阳光`，`day_key` 可日聚合，审计可还原
/// 「原始 S=162 → 实得 79」。
///
/// 公式（§4.5 公式③，分段；数值全部引用 prd_params 常量，防孪生）：
///   S ≤ kSoftCapSeg1          → 有效 = S
///   kSoftCapSeg1<S≤kSoftCapSeg2 → 有效 = 60 + (S-60)*0.5
///   kSoftCapSeg2<S≤kSoftCapSeg3 → 有效 = 75 + (S-90)*0.2
///   S > kSoftCapSeg3          → 有效 = kSoftCapDailyMax（79）
double computeSoftCap(double rawS) {
  if (rawS <= kSoftCapSeg1) return rawS;
  if (rawS <= kSoftCapSeg2) {
    return kSoftCapSeg1 + (rawS - kSoftCapSeg1) * kSoftCapSeg2Rate;
  }
  // 第二段末累计值（60 + 30*0.5 = 75），由常量推导，不写死。
  const double accumulatedToSeg2 =
      kSoftCapSeg1 + (kSoftCapSeg2 - kSoftCapSeg1) * kSoftCapSeg2Rate;
  if (rawS <= kSoftCapSeg3) {
    return accumulatedToSeg2 + (rawS - kSoftCapSeg2) * kSoftCapSeg3Rate;
  }
  return kSoftCapDailyMax; // 软顶封顶
}

/// 分龄换算骨架：消耗侧定价乘 K（分龄系数）。
///
/// K 仅作用于消耗侧（§0 产出侧不乘 K）。此处返回「含 K 的消耗成本」，
/// 真实 K 由 `Settings.ageTier` + `redemption_service` 在 M2 落地。
double applyAgeTierK(double baseCost, double k) => baseCost * k;

/// 免确认月度自动放行上限（C5）：
/// `min(固定天花板 100/40, 月池 × 25%)`。
///
/// 天花板默认引用 prd_params 常量（[kAutoApproveCapCeilingHigh]/[kAutoApproveCapCeilingLow]）；
/// 骨架阶段统一用 min，M2 按 `ageTier` 分流。
double autoApproveMonthlyCap(
  double monthlyPoolBudget, {
  double? ceilingHigh,
  double? ceilingLow,
}) {
  final double hi = ceilingHigh ?? kAutoApproveCapCeilingHigh.toDouble();
  final double lo = ceilingLow ?? kAutoApproveCapCeilingLow.toDouble();
  final double capFromPool = monthlyPoolBudget * kAutoApprovePoolRatio;
  // 占位：实际按 ageTier 选 100（高）或 40（低），此处取较小者保守。
  final double ceiling = hi < lo ? hi : lo;
  return capFromPool < ceiling ? capFromPool : ceiling;
}
