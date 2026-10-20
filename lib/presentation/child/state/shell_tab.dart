/// 孩子端外壳「当前 tab 索引（记忆）」+「外壳是否在台前」（F71 / F138）。
///
/// ## 一、为什么要拆成两个 provider（F138，玄参 2026-10-19 反馈）
///
/// **故障现象**：花园页 → 家长天地 → 退出家长天地 → 孩子端落在「今日」tab，
/// **但能一直听到花园背景音乐**（每 30s 补播一次，无限循环）。
///
/// **故障链**：
///  1. 家长天地入口是 `context.go('/parent')`（`parent_entry_action.dart`）——
///     `go` 会**替换整条路由栈** → 整个 `ChildShellPage` 被销毁重建；
///  2. 旧实现把 [childShellTabIndexProvider] 当成「**当前可见 tab**」的唯一真源，
///     外壳销毁时**没人清理**它（仍是孩子离开前的 2=花园）；
///  3. 新外壳的 `_index` 是局部变量、初值 0（今日）→ **provider(2) 与真实可见 tab(0) 分叉**；
///  4. 花园页（`IndexedStack` 会把 5 个子页全部 build）读 provider 判定自己「可见」
///     → `_syncAmbientTimer()` → 立刻起播 + 每 30 秒
///     （`kGardenAmbientIntervalSeconds`）补播一次。
///
/// **根因是语义混用**：一个变量同时承担「记忆（上次/当前选中的 tab）」与
/// 「可见性判据（这一刻是否有人在看）」两种职责 —— 前者要**跨外壳卸载存活**
/// （F138 口径 B：退出家长天地回原 tab），后者必须**随外壳上下台变化**。
///
/// ## 二、新语义（两者都保留，各司其职）
///
/// * [childShellTabIndexProvider] = **记忆**：上次 / 当前选中的 tab 索引，
///   初值 0，**跨外壳卸载存活**（外壳 `initState` 用它恢复上次 tab；
///   结算页返回前把它归 0，保证「专注结束回今日」口径不被恢复逻辑改变）。
/// * [childShellOnStageProvider] = **此刻外壳是否在台前**（有外壳挂载并上屏）。
///   外壳 `initState` 置 true、`dispose` 置 false（均**延后一微任务**发布，
///   见 `child_shell_page._publishOnStage` 的原因说明）。
///
/// **可见性统一判据** = `外壳在台前 && tabIndex == 本页下标`。
/// 三处消费者（花园氛围音 / 今日页升级演出 / `ChildTabAutoRefresh`）全部按此判定，
/// 不再各自解释 tab 索引的含义。
///
/// ⚠️ 独立文件避免 child_shell_page ↔ garden_page 循环导入。
library shell_tab;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 孩子端外壳**选中/记忆**的 tab 索引（0=今日 1=成长 2=花园 3=商店 4=我的）。
///
/// ⚠️ **语义已修正（F138）**：本 provider 是「记忆」，**不是**「当前可见 tab」。
/// 判可见性必须与 [childShellOnStageProvider] 联合使用
/// （`onStage && tabIndex == 本页下标`）——单看本值会让「外壳已销毁 / 已下台」
/// 的花园页误判自己可见，从而在今日 tab 上无限补播背景音乐。
final StateProvider<int> childShellTabIndexProvider = StateProvider<int>((_) => 0);

/// 孩子端外壳此刻是否**在台前**（已挂载且未被销毁/替换）。
///
/// * 初值 `false` = 「没有外壳在屏上」；
/// * 外壳 `initState` → `true`；`dispose` → `false`；
/// * 与 [childShellTabIndexProvider] 联合构成唯一可见性判据。
///
/// ⚠️ 为什么不能只靠 [childShellTabIndexProvider]：家长天地是 `context.go('/parent')`
/// （替换整条路由栈）→ 外壳被销毁，索引记忆仍留着孩子离开前的值；若把记忆当可见性，
/// 重建出来的花园页会「以为自己被看着」而持续起播背景音（F138 真机 bug）。
final StateProvider<bool> childShellOnStageProvider =
    StateProvider<bool>((_) => false);

/// 花园 tab 在外壳 `_tabs` 中的下标（与 `child_shell_page._tabs` 顺序一致）。
const int kChildTabIndexOfGarden = 2;

/// 其余各 tab 下标（C68 补齐：`ChildTabAutoRefresh` 需要每页声明自己的下标）。
/// ⚠️ 必须与 `child_shell_page._tabs` 的 **顺序/长度**一致；增删 tab 时同步改这里。
const int kChildTabIndexOfToday = 0;
const int kChildTabIndexOfGrowth = 1;
const int kChildTabIndexOfStore = 3;
const int kChildTabIndexOfProfile = 4;

/// 外壳 tab 总数（C68：`_tabs` 长度，供一致性断言用）。
const int kChildTabCount = 5;
