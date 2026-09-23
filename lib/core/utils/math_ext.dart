/// 经济计算工具：专注阳光的有效值（§4.5）、分龄换算（K 仅作用于消耗侧）。
/// 对应架构设计 §3.2（可追溯）、§4.5（公式③）。
library math_ext;

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 专注阳光的有效值（2026-09-23 口径，取代原「分段软顶」）。
///
/// 设计铁律（§3.2）：产出侧不乘 K；单一 append-only 账本 `sunlight_ledger`，
/// 每条 earn 同时记 `gross=原始` 与 `net=有效`，`day_key` 可日聚合，审计可还原
/// 「原始 162 → 实得 120（年段额度用完）」。
///
/// 公式（玄参 2026-09-23 拍板）：
///   专注 1 分钟 = 1 阳光（`kSunlightPerFocusMinute = 1.0`，见引擎），
///   唯一约束是**今日剩余额度**（年段日上限 − 今日已入账专注阳光）：
///     有效 = min(本场专注阳光, 今日剩余额度)
///
/// 为什么取消原分段打薄（0–60 全额 / 60–90 计 50% / 90–110 计 20% / 硬顶 79）：
/// 分段的**第一段就是 60 分钟全额**，因此「封顶值跟随年段」与「分段打薄」在数学上
/// 不能共存 —— 一旦把封顶降到年段值，超过年段值的部分必然是零收益，打薄没有中间
/// 地带。而旧口径下高年段孩子专注满 120 分钟只能拿到 79 阳光，「120」是摸不到的
/// 天花板；故按玄参裁定改为 1:1 + 年段硬封顶。
///
/// [remainingAllowance] 由调用方从**账本**（`refType='focus_session'` 的当日净额）
/// 派生，保证「额度消耗」只有一个真源。成长奖励 / 家长赠予是独立 refType，
/// 不占本额度。
double effectiveFocusSunlight({
  required double focusSunlight,
  required double remainingAllowance,
}) {
  if (focusSunlight <= 0 || remainingAllowance <= 0) return 0;
  return focusSunlight < remainingAllowance ? focusSunlight : remainingAllowance;
}

/// 免确认周自动放行上限（C5）：
/// `min(固定天花板 100/40, 周池 × 25%)`。
///
/// 天花板默认引用 prd_params 常量（[kAutoApproveCapCeilingHigh]/[kAutoApproveCapCeilingLow]）；
/// 骨架阶段统一用 min，M2 按 `ageTier` 分流。
double autoApprovePoolCap(
  double poolBudget, {
  double? ceilingHigh,
  double? ceilingLow,
}) {
  final double hi = ceilingHigh ?? kAutoApproveCapCeilingHigh.toDouble();
  final double lo = ceilingLow ?? kAutoApproveCapCeilingLow.toDouble();
  final double capFromPool = poolBudget * kAutoApprovePoolRatio;
  // 占位：实际按 ageTier 选 100（高）或 40（低），此处取较小者保守。
  final double ceiling = hi < lo ? hi : lo;
  return capFromPool < ceiling ? capFromPool : ceiling;
}
