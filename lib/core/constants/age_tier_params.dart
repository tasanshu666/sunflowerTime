/// 三档 AgeTier 参数单点（D2 唯一真源，§1.3 / §3.2；**C90-C 修订**）。
///
/// 取代 `redemption_service` / `settings_local_repository` 中散落的
/// `ageTier == AgeTier.high ? A : B` 三元。任何业务代码禁止再写该三元，
/// 一律查本文件的 `kAgeTierParams` / `ageTierK` / `tierForAge`。
///
/// 决策锁定（§0 D2 / U1；⚠️ **C90-C 修订（玄参 2026-10-18 拍板）**）：
///  · 分龄 K = [低 1.0 / 中 1.2 / 高 1.5]（不参与定价，仅档位参数留存）；
///  · **年级分界统一（12 岁归中）**：**≤8 低 / 9–12 中 / ≥13 高**
///    （原 6–8 / 9–10 / 11–12 口径作废）；
///  · 🔴 **自动放行（C5 双条件）全删**：原 `autoApproveMaxCost` /
///    `autoApproveCapCeiling` 字段与 `capFor()` 已随 C90-C 移除，兑换一律
///    由家长显式核销（见 `redemption_service.dart` 修订注释）；
///  · 周阳光池默认额度：低 **300** / 中 **600** / 高**默认不设上限**
///    （高年级用 [kWeeklyPoolBudgetUnlimited] 哨兵，兑换只受阳光余额约束；
///    **同日二次修订（玄参）**：家长端手动设额入口已删除，预算按年级默认值走）。
///
/// 2026-09-21 决策：K **不再参与定价**。家长端直接设定价格、孩子端直接显示家长设定的价格，
/// 显示价 = 扣费价 = baseCost。`k` 字段与 [ageTierK] 保留为档位参数单点（供分档展示等用途），
/// 但生产定价链路（store_page / RedemptionOrchestrationService）**不得再调用**。
library age_tier_params;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

/// 单档参数包（§3.2 AgeTierParams）。
class AgeTierParams {
  final int ageMin; // 年龄区间下限（含）
  final int ageMax; // 年龄区间上限（含；高档为信息性上界，语义上是「≥ ageMin」）
  final double k; // 分龄系数 K（仅档位参数留存，不参与定价）
  final int poolBudgetDefault; // 周阳光池默认额度（低 300 / 中 600 / 高不限额哨兵）
  final int dailyFocusCap; // 每日专注上限（低 60 / 中 90 / 高 120，2026-09-22 拍板）

  const AgeTierParams({
    required this.ageMin,
    required this.ageMax,
    required this.k,
    required this.poolBudgetDefault,
    required this.dailyFocusCap,
  });
}

/// 三档参数映射（D2 唯一真源；C90-C 修订：分界 ≤8 / 9–12 / ≥13）。
const Map<AgeTier, AgeTierParams> kAgeTierParams = {
  AgeTier.low: AgeTierParams(
    ageMin: 6,
    ageMax: 8,
    k: 1.0,
    poolBudgetDefault: kPoolBudgetDefaultLow, // 300（C90-C：160 → 200 → 300，同日二次修订）
    dailyFocusCap: kDailyFocusCapLow, // 60（2026-09-22：低年段降为 60）
  ),
  AgeTier.mid: AgeTierParams(
    ageMin: 9,
    ageMax: 12, // C90-C：9–12 岁（12 岁归中）
    k: 1.2,
    // C90-C：周池默认不再沿用低档值，独立为 400（同日二次修订 → 600）；每日专注上限 90 不变。
    poolBudgetDefault: kPoolBudgetDefaultMid, // 600
    dailyFocusCap: kDailyFocusCapMid, // 90（三档阶梯的中间档）
  ),
  AgeTier.high: AgeTierParams(
    ageMin: 13, // C90-C：≥13 岁（12 岁归中后高档从 13 起）
    ageMax: 18, // 信息性上界（tierForAge 对 >18 同样归 high）
    k: 1.5,
    // C90-C：高年级建档时周池**不预置额度**（默认不限额，兑换只受阳光余额约束）。
    poolBudgetDefault: kWeeklyPoolBudgetUnlimited, // 0 = 不设上限哨兵
    dailyFocusCap: kDailyFocusCapHigh, // 120（2026-09-22：高年段升为 120）
  ),
};

/// 由年龄推导档位（越界取最近端点；**C90-C 修订：≤8 低 / 9–12 中 / ≥13 高**）。
AgeTier tierForAge(int age) {
  if (age <= 8) return AgeTier.low;
  if (age <= 12) return AgeTier.mid;
  return AgeTier.high;
}

/// 档位对应的分龄系数 K（消耗侧乘子；仅档位参数留存，不参与定价）。
double ageTierK(AgeTier tier) => kAgeTierParams[tier]!.k;

/// 🔴 **已随 C90-C 删除**：原 `capFor(tier, budget)`（C5② 周自动放行上限）——
/// 自动放行功能整体移除，无需上限计算；本注释仅为防「按旧文档找函数」的迷路指针。
