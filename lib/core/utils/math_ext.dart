/// 经济计算工具：专注阳光的有效值（§4.5）。对应架构设计 §3.2（可追溯）、§4.5（公式③）。
library math_ext;

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

/// 🔴 **已随 C90-C 删除**：原 `autoApprovePoolCap`（C5 免确认上限 = min(天花板, 池×25%)）
/// —— 自动放行功能整体移除；本注释仅为防「按旧文档找函数」的迷路指针。
