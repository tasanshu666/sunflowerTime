/// 任务模板种子（M3 T05）：3 内置 + 自定义（§4.4 / §8.2）。
///
/// 口径：默认关联专注、最少 15 分钟、阳光奖励 12、repeatRule 取
/// 'daily'（每天）/ 'weekly'（每周）/ null（不重复）。
library task_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

/// 3 条内置任务模板（首次进入任务配置页若为空则写入）。
const List<Task> kSeedTasks = <Task>[
  Task(
    id: 'seed_task_homework',
    name: '完成学校作业',
    subject: TaskSubject.general,
    category: TaskCategory.learning, // 种子项默认归类「学习」（玄参大人可后续在编辑器改）
    requiresFocus: true,
    minFocusMin: 15,
    sunlightReward: 12,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_read',
    name: '阅读 20 分钟',
    subject: TaskSubject.chinese,
    category: TaskCategory.learning, // 阅读 → 学习
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 12,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_math',
    name: '练习数学口算',
    subject: TaskSubject.math,
    category: TaskCategory.learning, // 数学口算 → 学习
    requiresFocus: true,
    minFocusMin: 15,
    sunlightReward: 12,
    repeatRule: 'weekly',
    isCustom: false,
  ),
];

/// 首次启动播种：若当前无任何任务模板则逐条写入（幂等，不覆盖既有数据）。
Future<void> ensureTaskSeed(TaskRepository repo) async {
  if ((await repo.tasks()).isEmpty) {
    for (final Task t in kSeedTasks) {
      await repo.saveTask(t);
    }
  }
}
