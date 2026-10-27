/// 种子模板 / 默认孩子名的本地化出口（i18n B3 · T05）。
///
/// ## 为什么存在
/// 迁移前「种子数据的 name 就是文案」：
///  · `data/local/task_seed.dart` 的 `kSeedTasks[i].name`（完成学校作业 / 练习数学口算 …）；
///  · `data/local/repositories/reward_seed.dart` 的 `kSeedRewardTemplates[i].name`（小零食 …）；
///  · `domain/services/account_service.dart` 里 `repo.create('孩子', …)`。
///
/// 三者都只在**首次启动空表时**写入 DB —— 一旦落库就是用户数据，之后**永不改写**
/// （C69 / F109 口径：只增不删、不改既有行）。所以英文用户装上 App，首屏任务板就是
/// 一排中文。
///
/// ## 设计取舍（⚠️ 与「改 name」的取舍要看清）
/// **不改 DB 里已有的行**，而是把「播种时取什么名字」交给调用方注入：
///  · [ensureTaskSeed] / [ensureRewardSeed] 收一个 `nameOf(seedId)` 回调；
///  · [main] 冷启动注入 `taskSeedName` / `rewardSeedName`（按当前语言）；
///  · 已装用户的老行**原样保留**（中文字节序不变，见
///    `test/i18n/seed_locale_test.dart` ③）。
///
/// 因此：**换语言不会改写历史数据**，只会影响「此后新播种的行」。这是刻意取舍 ——
/// 用户的档案 / 任务可以自己改名，App 不该在切语言时覆写用户数据。
///
/// ## F154 补充（2026-10-26 玄参拍板）
/// DB 不动的前提下，**显示层**已让预制种子行的名字跟随当前语言（见文件尾的
/// [taskDisplayName] / [rewardDisplayName]）—— 英文用户不会再看到「完成学校作业 /
/// 小零食」；家长改过名的行原样显示，用户数据仍然优先。
library seed_l10n;

import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 5 条默认**成长任务**的种子 id（顺序 = `kTaskSeedTemplates` 的顺序）。
///
/// 与 `data/local/task_seed.dart` 一一对应；单独列在这里是为了让本文件零数据层依赖。
const List<String> kTaskSeedIds = <String>[
  'seed_task_homework',
  'seed_task_math',
  'seed_task_read',
  'seed_task_rope_skip',
  'seed_task_chores',
];

/// 5 条默认**奖励模板**的种子 id（顺序 = `kSeedRewardTemplates` 的顺序）。
///
/// ⚠️ 注意这里的 id 是**历史 id**（`seed_snack` 而不是 `seed_reward_snack`）：
/// 它们已经是老库里的主键，改名等于制造重复记录。ARB key 与 id **不同名**
/// （ARB 侧统一带 `seed_reward_` 前缀以便检索），映射在 [rewardSeedName] 里。
const List<String> kRewardSeedIds = <String>[
  'seed_snack',
  'seed_extra_play',
  'seed_cartoon',
  'seed_toy',
  'seed_weekend_outing',
];

/// 任务种子 id → 当前语言的任务名。
///
/// 未知 id 回退到 `id` 本身（而不是空串）：种子名缺失时「任务标题是 id」在 UI 上
/// 可被立刻发现，而空标题会让任务板看起来像渲染坏了。
String taskSeedName(String seedId, AppLocalizations t) {
  switch (seedId) {
    case 'seed_task_homework':
      return t.seed_task_homework;
    case 'seed_task_math':
      return t.seed_task_math;
    case 'seed_task_read':
      return t.seed_task_read;
    case 'seed_task_rope_skip':
      return t.seed_task_rope_skip;
    case 'seed_task_chores':
      return t.seed_task_chores;
    default:
      return seedId;
  }
}

/// 奖励种子 id → 当前语言的奖励名（未知 id 回退 `id`，理由同 [taskSeedName]）。
///
/// 🔴 switch 的是**落库 id**（`seed_snack` …），返回的是**ARB key**
/// （`seed_reward_snack` …）—— 两者刻意不同名（见 [kRewardSeedIds] 的说明）。
String rewardSeedName(String seedId, AppLocalizations t) {
  switch (seedId) {
    case 'seed_snack':
      return t.seed_reward_snack;
    case 'seed_extra_play':
      return t.seed_reward_extra_play;
    case 'seed_cartoon':
      return t.seed_reward_cartoon;
    case 'seed_toy':
      return t.seed_reward_toy;
    case 'seed_weekend_outing':
      return t.seed_reward_weekend_outing;
    default:
      return seedId;
  }
}

/// 默认孩子档案的名字（原 `account_service.dart` 里的 `'孩子'` 字面量）。
///
/// zh = 「孩子」/ en = `Child`；只在**空表补建默认档案**时用一次。
String defaultChildName(AppLocalizations t) => t.shared_default_child_name;

// ── 预制内容显示名映射（F154，玄参 2026-10-26 拍板）──────────────────────
//
// 口径变更：此前「换语言不改写用户数据」= 英文用户看到 DB 里的中文种子行
//（「完成学校作业 / 小零食」）。玄参拍板：**预制任务 / 奖励的显示名要跟随
// 当前语言**（英文模式下一律英文，不许出现汉语）。
//
// 实现走**显示层映射**（与 `species_l10n.dart` 的 `speciesNameOr` 同构），
// **不改 DB**：
//  · 种子行（id ∈ kTaskSeedIds / kRewardSeedIds）**且**存储名仍等于该种子
//    「任一语言的默认名」→ 按当前语言显示（zh 行在 en 下显示英文名，反之亦然）；
//  · 存储名不等于任何语言的默认名 → 家长改过名，**原样显示**（用户数据优先）；
//  · 非种子 id（自定义任务 / 奖励）→ 原样显示。
//
// ⚠️ 新增语言时必须同步 [isPresetTaskSeedName] / [isPresetRewardSeedName]
// 里的实例清单，否则新语言的种子行在其它语言下会退化成「原样显示」。
// ⚠️ 图标关键词匹配（`growth_icons.dart`）继续用 DB 原名，不走本映射 ——
// 关键词表是中文，用显示名匹配会让 en 首启用户丢图标。

/// [seedId] 的存储名是否仍是预制默认名（任一语言；家长改过名 → false）。
bool isPresetTaskSeedName(String seedId, String storedName) {
  return storedName == taskSeedName(seedId, AppLocalizationsZh()) ||
      storedName == taskSeedName(seedId, AppLocalizationsEn());
}

/// 奖励版 [isPresetTaskSeedName]，语义同上。
bool isPresetRewardSeedName(String tplId, String storedName) {
  return storedName == rewardSeedName(tplId, AppLocalizationsZh()) ||
      storedName == rewardSeedName(tplId, AppLocalizationsEn());
}

/// 任务显示名：预制种子行跟随当前语言，其余（自定义 / 改过名）原样。
String taskDisplayName(String taskId, String storedName, AppLocalizations t) {
  if (kTaskSeedIds.contains(taskId) && isPresetTaskSeedName(taskId, storedName)) {
    return taskSeedName(taskId, t);
  }
  return storedName;
}

/// 奖励显示名：语义同 [taskDisplayName]。
String rewardDisplayName(
  String tplId,
  String storedName,
  AppLocalizations t,
) {
  if (kRewardSeedIds.contains(tplId) &&
      isPresetRewardSeedName(tplId, storedName)) {
    return rewardSeedName(tplId, t);
  }
  return storedName;
}
