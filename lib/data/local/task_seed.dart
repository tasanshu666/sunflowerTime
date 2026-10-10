/// 任务模板种子（M3 T05 内置模板 / C52 默认版重写，玄参 2026-10-10 截图拍板）。
///
/// 口径：repeatRule 取 'daily'（每天）/ 'weekly'（每周）/ null（不重复）；
/// 联动专注项 `requiresFocus=true` 且 `minFocusMin` 按玄参默认版（作业 20 / 口算 15）；
/// 非联动项 `minFocusMin` 保持字段默认 15（不生效、仅占位）。
library task_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

/// 9 条默认成长任务（C52 默认版，玄参 2026-10-10 截图拍板）。
const List<Task> kSeedTasks = <Task>[
  Task(
    id: 'seed_task_homework',
    name: '完成学校作业',
    subject: TaskSubject.general,
    category: TaskCategory.learning,
    requiresFocus: true,
    minFocusMin: 20,
    sunlightReward: 8,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_read',
    name: '阅读 20 分钟',
    subject: TaskSubject.chinese,
    category: TaskCategory.learning,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 8,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_math',
    name: '练习数学口算',
    subject: TaskSubject.math,
    category: TaskCategory.learning,
    requiresFocus: true,
    minFocusMin: 15,
    sunlightReward: 6,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_english_read',
    name: '指读英语20分钟',
    subject: TaskSubject.english,
    category: TaskCategory.learning,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 8,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_english_listen',
    name: '早上听英语听力15分钟',
    subject: TaskSubject.english,
    category: TaskCategory.learning,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 6,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_rope_skip',
    name: '1分钟跳绳170个以上',
    subject: TaskSubject.general,
    category: TaskCategory.sports,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 10,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_homework_first',
    name: '放学后优先完成作业',
    subject: TaskSubject.general,
    category: TaskCategory.learning,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 5,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_pushup',
    name: '10个俯卧撑+10个仰卧起坐',
    subject: TaskSubject.general,
    category: TaskCategory.sports,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 5,
    repeatRule: 'daily',
    isCustom: false,
  ),
  Task(
    id: 'seed_task_chores',
    name: '帮助家长打扫卫生',
    subject: TaskSubject.general,
    category: TaskCategory.life,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 5,
    repeatRule: 'daily',
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
