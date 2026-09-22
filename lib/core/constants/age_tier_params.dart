/// 三档 AgeTier 参数单点（D2 唯一真源，§1.3 / §3.2）。
///
/// 取代 `redemption_service` / `settings_local_repository` 中散落的
/// `ageTier == AgeTier.high ? A : B` 三元。任何业务代码禁止再写该三元，
/// 一律查本文件的 `kAgeTierParams` / `ageTierK` / `capFor` / `tierForAge`。
///
/// 决策锁定（§0 D2 / U1）：
///  · 分龄 K = [低 1.0 / 中 1.2 / 高 1.5]
///  · 分档 = 6–8 / 9–10 / 11–12 岁
///  · U1：中档(9–10 岁) 的 C5 阈值/天花板/周阳光池默认/每日上限 **全部沿用低档值**
///    （50 / 40 / 160 / 90），仅 K=1.2 区分；不发明新数字（符合单点纪律）。
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
  final int ageMax; // 年龄区间上限（含）
  final double k; // 分龄系数 K（仅作用消耗侧）
  final int autoApproveMaxCost; // C5① 单笔候选阈值
  final int autoApproveCapCeiling; // C5② 固定天花板（低 40 / 高 100）
  final int poolBudgetDefault; // 周阳光池默认（低 160 / 高 400）
  final int dailyFocusCap; // 每日专注上限（低 90 / 高 60）

  const AgeTierParams({
    required this.ageMin,
    required this.ageMax,
    required this.k,
    required this.autoApproveMaxCost,
    required this.autoApproveCapCeiling,
    required this.poolBudgetDefault,
    required this.dailyFocusCap,
  });
}

/// 三档参数映射（D2 唯一真源）。
const Map<AgeTier, AgeTierParams> kAgeTierParams = {
  AgeTier.low: AgeTierParams(
    ageMin: 6,
    ageMax: 8,
    k: 1.0,
    autoApproveMaxCost: kAutoApproveMaxCostLow, // 50
    autoApproveCapCeiling: kAutoApproveCapCeilingLow, // 40
    poolBudgetDefault: kPoolBudgetDefaultLow, // 160
    dailyFocusCap: kDailyFocusCapLow, // 90
  ),
  AgeTier.mid: AgeTierParams(
    ageMin: 9,
    ageMax: 10,
    k: 1.2,
    // U1：中档全部沿用低档取值（不发明新数字），仅 K 区分。
    autoApproveMaxCost: kAutoApproveMaxCostLow, // 50
    autoApproveCapCeiling: kAutoApproveCapCeilingLow, // 40
    poolBudgetDefault: kPoolBudgetDefaultLow, // 160
    dailyFocusCap: kDailyFocusCapLow, // 90
  ),
  AgeTier.high: AgeTierParams(
    ageMin: 11,
    ageMax: 12,
    k: 1.5,
    autoApproveMaxCost: kAutoApproveMaxCostHigh, // 130
    autoApproveCapCeiling: kAutoApproveCapCeilingHigh, // 100
    poolBudgetDefault: kPoolBudgetDefaultHigh, // 400
    dailyFocusCap: kDailyFocusCapHigh, // 60
  ),
};

/// 由年龄推导档位（越界取最近端点）。
AgeTier tierForAge(int age) {
  if (age <= 8) return AgeTier.low;
  if (age <= 10) return AgeTier.mid;
  return AgeTier.high;
}

/// 档位对应的分龄系数 K（消耗侧乘子）。
double ageTierK(AgeTier tier) => kAgeTierParams[tier]!.k;

/// C5② 周自动放行上限 = min(固定天花板, 周池 × 25%)（§3.2 capFor）。
int capFor(AgeTier tier, int budget) {
  final AgeTierParams p = kAgeTierParams[tier]!;
  final int fromPool = (budget * kAutoApprovePoolRatio).floor();
  return fromPool < p.autoApproveCapCeiling ? fromPool : p.autoApproveCapCeiling;
}
