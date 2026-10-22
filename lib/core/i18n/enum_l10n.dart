/// 枚举 → 文案（i18n B3 · T02）：领域层枚举**只留语义**，展示名一律经本文件取。
///
/// ## 为什么存在
/// 迁移前 [TaskCategoryX.label] / [RewardContentCategoryX.label] / `Task.subjectLabel`
/// 把中文写死在 `lib/domain/**` —— 英文环境下孩子端 / 家长端仍是中文，且违反
/// 「domain 层零 CJK」纪律。本文件是这三个枚举**唯一**的文案出口：
///  · [taskCategoryLabel] / [rewardContentCategoryLabel]：分类分区头（成长页 / 商店页）；
///  · [taskSubjectLabel]：科目名（**复用**既有 `parent_task_edit_subject_*` key，
///    零新增键，与家长端编辑器同源，不会出现两套译名）；
///  · [taskDisplaySubject]：科目展示名（自定义科目取用户输入原文，空则「自定义」）。
///
/// 🔴 纪律：枚举的 `icon`（emoji）留在 domain —— 它不是文案（各语言一致），
/// 迁移只针对**可翻译字符串**。
library enum_l10n;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 成长项分类名（学习 / 运动 / 生活 / 习惯 / 其他）。
///
/// 顺序与原 `TaskCategoryX.label` 的 switch 一致；`switch` 覆盖全部枚举值，
/// 新增枚举成员时编译器会在此处报错（不留静默兜底）。
String taskCategoryLabel(TaskCategory category, AppLocalizations t) {
  switch (category) {
    case TaskCategory.other:
      return t.shared_task_category_other;
    case TaskCategory.learning:
      return t.shared_task_category_learning;
    case TaskCategory.sports:
      return t.shared_task_category_sports;
    case TaskCategory.life:
      return t.shared_task_category_life;
    case TaskCategory.habit:
      return t.shared_task_category_habit;
  }
}

/// 奖励内容分类名（零食 / 游玩 / 娱乐 / 玩具 / 阅读 / 其他）。
String rewardContentCategoryLabel(RewardContentCategory category, AppLocalizations t) {
  switch (category) {
    case RewardContentCategory.other:
      return t.shared_reward_content_other;
    case RewardContentCategory.snacks:
      return t.shared_reward_content_snacks;
    case RewardContentCategory.play:
      return t.shared_reward_content_play;
    case RewardContentCategory.entertainment:
      return t.shared_reward_content_entertainment;
    case RewardContentCategory.toys:
      return t.shared_reward_content_toys;
    case RewardContentCategory.books:
      return t.shared_reward_content_books;
  }
}

/// 科目名（语文 / 数学 / 英语 / 通用 / 自定义）。
///
/// 🔴 **复用**家长端编辑器既有 key（`parent_task_edit_subject_chinese` 等）
/// + 孩子端 `child_entry_custom`，**零新增键** —— 同一科目全 App 只有一套译名。
String taskSubjectLabel(TaskSubject subject, AppLocalizations t) {
  switch (subject) {
    case TaskSubject.chinese:
      return t.parent_task_edit_subject_chinese;
    case TaskSubject.math:
      return t.parent_task_edit_subject_math;
    case TaskSubject.english:
      return t.parent_task_edit_subject_english;
    case TaskSubject.general:
      return t.parent_task_edit_subject_general;
    case TaskSubject.custom:
      return t.child_entry_custom;
  }
}

/// 成长项的**展示科目名**（替代已删除的 `Task.subjectLabel` getter）。
///
/// 语义与迁移前逐字节一致：
///  · `subject == custom` 且 [Task.customSubject] 去空白后非空 → **原样**回显用户输入
///    （家长自己写的科目名不翻译）；
///  · 否则 → 该科目的固定名（custom 但空白时回落「自定义」）。
String taskDisplaySubject(Task task, AppLocalizations t) {
  if (task.subject == TaskSubject.custom) {
    final String name = (task.customSubject ?? '').trim();
    return name.isEmpty ? t.child_entry_custom : name;
  }
  return taskSubjectLabel(task.subject, t);
}
