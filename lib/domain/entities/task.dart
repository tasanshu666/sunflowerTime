import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

/// 任务模板（§3.1 task）。3 内置 + 自定义（§4.4 / §8.2）。
///
/// M3 修订：科目支持自定义——[subject] 取 [TaskSubject.custom] 时，科目名存
/// [customSubject]（自由文本）；其余情况 [customSubject] 为 null。
class Task {
  final String id;
  final String name;
  final TaskSubject subject;
  final String? customSubject; // 自定义科目名（subject==custom 时生效）
  final TaskCategory category; // 内容分类（学习/运动/生活/其他），默认 other = 历史/未分类安全默认
  final bool requiresFocus; // 是否需要 ≥15 分钟专注
  final int minFocusMin; // 默认 15
  final int sunlightReward; // 默认 12，区间 5–40
  final String? repeatRule; // 周/日重复规则（占位）
  final bool isCustom;

  const Task({
    required this.id,
    required this.name,
    required this.subject,
    this.customSubject,
    required this.requiresFocus,
    required this.minFocusMin,
    required this.sunlightReward,
    this.repeatRule,
    required this.isCustom,
    this.category = TaskCategory.other,
  });

  /// 给定「最少专注分钟」，返回奖励阳光上限（分钟 × [kTaskRewardRatio]，至少 1）。
  /// 编辑器与实体共用同一口径，禁止各处复写公式。
  static int rewardCapFor(int minFocusMin) {
    final int c = (minFocusMin * kTaskRewardRatio).round();
    return c < 1 ? 1 : c;
  }

  /// 本成长项的奖励阳光上限（见 [rewardCapFor]）。
  int get rewardCap => rewardCapFor(minFocusMin);

  /// 实际生效的奖励阳光（口径：用户 2026-09-21 拍板，冻结）：
  /// - 联动项（requiresFocus == true）→ **固定 = 最少专注分钟 × 40%（[rewardCap]）**，
  ///   不再取家长手填值、也不叠加完美日系数，保证「孩子端 / 结算页 / 家长端」三处一致；
  /// - 非联动项 → 家长设定值（[sunlightReward]，区间见 [kTaskRewardMin] / [kTaskRewardMax]）。
  int get effectiveSunlightReward => requiresFocus ? rewardCap : sunlightReward;

  /// 科目展示名：内置科目取固定名，自定义取 [customSubject]（空白则回落「自定义」）。
  ///
  /// 单点收口：禁止在 UI 层再写一份 switch（避免内置科目名出现第二处字面量）。
  String get subjectLabel {
    switch (subject) {
      case TaskSubject.chinese:
        return '语文';
      case TaskSubject.math:
        return '数学';
      case TaskSubject.english:
        return '英语';
      case TaskSubject.general:
        return '通用';
      case TaskSubject.custom:
        final String name = (customSubject ?? '').trim();
        return name.isEmpty ? '自定义' : name;
    }
  }

  /// 内容分类中文名（学习/运动/生活/其他），单点收口（UI 层不要再写 switch）。
  String get categoryLabel => category.label;

  /// 内容分类占位图标（emoji）。
  String get categoryIcon => category.icon;
}
