/// 任务模板种子（M3 T05 内置模板 / C52 默认版重写 / 阶段 4 精简为 5 条）。
///
/// 口径：repeatRule 取 'daily'（每天）/ 'weekly'（每周）/ null（不重复）；
/// 联动专注项 `requiresFocus=true` 且 `minFocusMin` 按玄参默认版（作业 20 / 口算 15）；
/// 非联动项 `minFocusMin` 保持字段默认 15（不生效、仅占位）。
///
/// 阶段 4（玄参拍板）：**由 9 条精简为 5 条**，对齐免费档任务上限 `kFreeTaskQuota`（5），
/// 避免新装免费用户一上来即超限「永远无法新增」。保留后分类 = 学习 3 / 运动 1 / 生活 1。
/// ⚠️ 存量用户数据**原样保留**（C69 / F109）：仅当表为空时才播种，绝不删改既有行；
/// 亦**不新增 schemaVersion 迁移**（onUpgrade 的 `from < N` 闸门升到 24 后永不重跑）。
library task_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

/// 5 条默认成长任务（阶段 4 精简版；玄参 2026-10-14 拍板保留清单）。
///
/// 保留：完成学校作业 / 练习数学口算 / 阅读 20 分钟 / 1分钟跳绳170个以上 / 帮助家长打扫卫生。
/// 去掉：指读英语20分钟 / 早上听英语听力15分钟 / 放学后优先完成作业 / 10个俯卧撑+10个仰卧起坐。
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
