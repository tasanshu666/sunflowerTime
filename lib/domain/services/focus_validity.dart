/// 「有效专注」的**单一真源**（纯函数，零 IO、零副作用）。
///
/// ## 为什么必须新建这个文件（而不是再抄一份）
/// 判定口径 `actualFocusMin ≥ kValidFocusMinutes 且完成率 ≥ kCompletionRateThreshold`
/// 目前在仓库里有 **3 份独立实现**，且 `plannedMin == 0`（自由专注）时口径**不一致**：
///
/// | 位置 | `plannedMin == 0` 时的行为 |
/// |---|---|
/// | `data/local/repositories/focus_local_repository.dart` `_isValidSession` | **算无效**（完成率取 0.0） |
/// | `domain/services/focus_report_service.dart` `_isWfd` | 算有效（完成率取 1.0） |
/// | `domain/services/plant_growth_service.dart` `_isWfd` | 算有效（完成率取 1.0） |
///
/// 🔴 **那三处一律不动**：`implements FocusRepository` 的测试假实现有近百个，
/// 动仓储接口 / 改既有行为会大面积变红。守卫玩法（`GuardService.energyAvailable`）
/// 只消费本文件的纯函数，于是「第四份拷贝」不会出现，而旧路径保持逐位不变。
///
/// ## 口径（决策 D5）
/// 1. `actualFocusMin < kValidFocusMinutes`（15）→ **无效**（先判时长，任何分支都不例外）；
/// 2. `plannedMin == 0`（自由专注，没有设定时长）→ **有效**（只看时长，因为
///    「完成率 = 实际 / 计划」在计划为 0 时无定义；把它判无效等于「自由专注永远
///    换不到能量」，与「自由专注算有效专注」这条既有产品口径冲突）；
/// 3. `plannedMin > 0` → 还要求 `actualFocusMin / plannedMin ≥ kCompletionRateThreshold`（0.90）。
///
/// 边界：恰好 15 分钟算有效（`≥`）；恰好 90% 完成率算有效（`≥`）。
library focus_validity;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';

/// 这次专注算不算「有效专注」（可用于发守卫能量 / 记 WFD）。
///
/// 纯函数：同样的 [FocusSession] 恒给出同样的结果，不读时钟、不读仓储。
/// 注意 **不看** `status`：`shortAborted` 的实际时长必然 < [kMinFocusMinutes]，
/// 天然被第 1 条挡掉；而历史数据里可能有 `completed` 但实际时长不足的脏行，
/// 靠时长判定比靠枚举更稳。
bool isValidFocusSession(FocusSession s) {
  // ① 时长下限：先判，任何分支都不例外。
  if (s.actualFocusMin < kValidFocusMinutes) return false;

  // ② 自由专注（未设时长）只看时长 —— 决策 D5。
  if (s.plannedMin <= 0) return true;

  // ③ 有计划时长：完成率门槛（含等号，恰好 90% 算有效）。
  return s.actualFocusMin / s.plannedMin >= kCompletionRateThreshold;
}

/// 一组会话里**有效**的那些（顺序原样保留，不做去重 / 排序）。
///
/// 守卫玩法用它算能量：`clamp(有效次数, 0, kGuardEnergyDailyMax) − 已消耗点数`。
/// 🔴 **不要**用 `sessions.length` 代替本函数：那是「今日专注 N 次」的展示口径
/// （含 3 分钟就放弃的会话），拿它发能量等于「点开专注 3 秒退出就能刷满能量」。
List<FocusSession> validFocusSessionsOf(Iterable<FocusSession> sessions) {
  final List<FocusSession> result = <FocusSession>[];
  for (final FocusSession s in sessions) {
    if (isValidFocusSession(s)) result.add(s);
  }
  return result;
}
