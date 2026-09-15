import 'package:sunflower_time/domain/entities/enums.dart';

/// 任务模板（§3.1 task）。3 内置 + 自定义（§4.4 / §8.2）。
class Task {
  final String id;
  final String name;
  final TaskSubject subject;
  final bool requiresFocus; // 是否需要 ≥15 分钟专注
  final int minFocusMin; // 默认 15
  final int sunlightReward; // 默认 12，区间 5–40
  final String? repeatRule; // 周/日重复规则（占位）
  final bool isCustom;

  const Task({
    required this.id,
    required this.name,
    required this.subject,
    required this.requiresFocus,
    required this.minFocusMin,
    required this.sunlightReward,
    this.repeatRule,
    required this.isCustom,
  });
}
