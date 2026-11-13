/// 枚举 → 文案（i18n B3 · T02）：领域层枚举**只留语义**，展示名一律经本文件取。
///
/// ## 为什么存在
/// 迁移前 [TaskCategoryX.label] / [RewardContentCategoryX.label] / `Task.subjectLabel`
/// 把中文写死在 `lib/domain/**` —— 英文环境下孩子端 / 家长端仍是中文，且违反
/// 「domain 层零 CJK」纪律。本文件是这三个枚举**唯一**的文案出口：
///  · [taskCategoryLabel] / [rewardContentCategoryLabel]：分类分区头（成长页 / 商店页）；
///  · [taskSubjectLabel]：科目名（**复用**既有 `parent_task_edit_subject_*` key，
///    零新增键，与家长端编辑器同源，不会出现两套译名）；
///  · [taskDisplaySubject]：科目展示名（自定义科目取用户输入原文，空则「自定义」）；
///  · [guardThiefName] / [guardDropName]：花园守卫的贼名 / 券名（第三批新增）。
///
/// 🔴 纪律：枚举的 `icon`（emoji）留在 domain —— 它不是文案（各语言一致），
/// 迁移只针对**可翻译字符串**。
library enum_l10n;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
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

/// 花园守卫 · 偷菜贼的展示名（馋光鼠 / 食叶虫 / 贪婪鼬）。
///
/// 🔴 **中文名必须在这里取，绝不出现在 `lib/domain/**`**：
/// `guard_thief.dart` 只用稳定 ASCII [GuardThiefSpec.id] 与 [GuardThiefSpec.emoji]
/// （emoji 是符号不是文案），中文由本函数按当前 locale 给
/// —— `test/i18n/no_han_in_domain_test.dart` 钉死 domain 层零 CJK。
///
/// `switch` 覆盖全部枚举值（新增贼种时编译器在此报错，不留静默兜底）。
String guardThiefName(GuardThiefKind kind, AppLocalizations t) {
  switch (kind) {
    case GuardThiefKind.sunRat:
      return t.guard_thief_name_sun_rat;
    case GuardThiefKind.leafBug:
      return t.guard_thief_name_leaf_bug;
    case GuardThiefKind.sneakThief:
      return t.guard_thief_name_sneak_thief;
  }
}

/// 花园守卫 · 掉落券的展示名（浇水券 / 劳动券 / 施肥券 / 专注加餐券 / 专注放大券 /
/// 免费浇水券 / 免费施肥券 / 免费浇水×3 / 免费施肥×2 —— B13.20 起券库 9 种）。
///
/// 「无道具档」（[GuardDropKind.none]）**没有名字**：它是一条「今天没有券」的
/// 数据，任何展示位都该走 `guard_result_nothing` 这类文案，而不是给它编一个名字
/// —— 故本函数对 `none` 返回**空串**，调用方应先判 [GuardDropKindX.hasVoucher]。
String guardDropName(GuardDropKind kind, AppLocalizations t) {
  switch (kind) {
    case GuardDropKind.waterVoucher:
      return t.guard_drop_name_water_voucher;
    case GuardDropKind.laborVoucher:
      return t.guard_drop_name_labor_voucher;
    case GuardDropKind.fertilizeVoucher:
      return t.guard_drop_name_fertilize_voucher;
    case GuardDropKind.focusMeal:
      return t.guard_drop_name_focus_meal;
    case GuardDropKind.focusBoost:
      return t.guard_drop_name_focus_boost;
    case GuardDropKind.freeWater:
      return t.guard_drop_name_free_water;
    case GuardDropKind.freeFertilize:
      return t.guard_drop_name_free_fertilize;
    case GuardDropKind.freeWater3:
      return t.guard_drop_name_free_water_3;
    case GuardDropKind.freeFertilize2:
      return t.guard_drop_name_free_fertilize_2;
    case GuardDropKind.none:
      return '';
  }
}
