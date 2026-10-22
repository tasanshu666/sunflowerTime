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
///
/// ## i18n B3 · T05：模板里**没有 name**
/// 迁移前 `kSeedTasks` 是 `List<Task>`，`Task.name` 直接存中文（「完成学校作业」…），
/// 英文用户首屏任务板整排中文。现在拆成 [TaskSeedTemplate]（**只留结构化字段**）
/// + [ensureTaskSeed] 的 `nameOf` 回调：
/// ```dart
/// await ensureTaskSeed(repo, nameOf: (String id) => taskSeedName(id, l10n));
/// ```
/// 名字由调用方按当前语言给（[main] 冷启动注入；见 `core/i18n/seed_l10n.dart`）。
/// **老库里的中文行不动**（播种只在表空时发生）—— 换语言不改写用户数据。
library task_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

/// 一条任务种子模板（**不含 name**：名字由调用方按语言注入）。
///
/// [id] 同时是 `Task.id`（`seed_task_*`）与 ARB key 的派生依据
/// （`seed_l10n.dart` 的 `taskSeedName(id, l10n)` 用同一套 id switch）。
class TaskSeedTemplate {
  /// 种子 id（= 落库后的任务 id，`seed_task_*`；ARB key 与之一一对应）。
  final String id;

  /// 科目（自定义科目标题不参与种子）。
  final TaskSubject subject;

  /// 分类（学习 / 运动 / 生活）。
  final TaskCategory category;

  /// 是否联动专注（true → 需累计 `minFocusMin` 分钟有效专注才可提交）。
  final bool requiresFocus;

  /// 联动专注门槛分钟数（`requiresFocus=false` 时仅占位、不生效）。
  final int minFocusMin;

  /// 完成奖励阳光数。
  final int sunlightReward;

  /// 重复规则字符串（'daily' / 'weekly' / null）。
  final String? repeatRule;

  const TaskSeedTemplate({
    required this.id,
    required this.subject,
    required this.category,
    required this.requiresFocus,
    required this.minFocusMin,
    required this.sunlightReward,
    required this.repeatRule,
  });

  /// 装配成可落库的 [Task]：**唯一**缺的字段是 name，由调用方给本地化值。
  ///
  /// `isCustom = false`：种子任务不算用户自定义（家长可改可删，但 UI 分类上不是
  /// 「我加的任务」）。
  Task toTask({required String name}) => Task(
        id: id,
        name: name,
        subject: subject,
        category: category,
        requiresFocus: requiresFocus,
        minFocusMin: minFocusMin,
        sunlightReward: sunlightReward,
        repeatRule: repeatRule,
        isCustom: false,
      );
}

/// 5 条默认成长任务（阶段 4 精简版；玄参 2026-10-14 拍板保留清单）。
///
/// 保留：完成学校作业 / 练习数学口算 / 阅读 20 分钟 / 1分钟跳绳170个以上 / 帮助家长打扫卫生。
/// 去掉：指读英语20分钟 / 早上听英语听力15分钟 / 放学后优先完成作业 / 10个俯卧撑+10个仰卧起坐。
///
/// 🔴 顺序即 UI 展示序，**永不重排**（重排会让 ARB 的 9 / 5 条索引对齐关系错位，
/// 也让「老库 + 新库」的对比测试失去意义）。
const List<TaskSeedTemplate> kTaskSeedTemplates = <TaskSeedTemplate>[
  TaskSeedTemplate(
    id: 'seed_task_homework',
    subject: TaskSubject.general,
    category: TaskCategory.learning,
    requiresFocus: true,
    minFocusMin: 20,
    sunlightReward: 8,
    repeatRule: 'daily',
  ),
  TaskSeedTemplate(
    id: 'seed_task_math',
    subject: TaskSubject.math,
    category: TaskCategory.learning,
    requiresFocus: true,
    minFocusMin: 15,
    sunlightReward: 6,
    repeatRule: 'daily',
  ),
  TaskSeedTemplate(
    id: 'seed_task_read',
    subject: TaskSubject.chinese,
    category: TaskCategory.learning,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 8,
    repeatRule: 'daily',
  ),
  TaskSeedTemplate(
    id: 'seed_task_rope_skip',
    subject: TaskSubject.general,
    category: TaskCategory.sports,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 10,
    repeatRule: 'daily',
  ),
  TaskSeedTemplate(
    id: 'seed_task_chores',
    subject: TaskSubject.general,
    category: TaskCategory.life,
    requiresFocus: false,
    minFocusMin: 15,
    sunlightReward: 5,
    repeatRule: 'daily',
  ),
];

/// 首次启动播种：若当前无任何任务模板则逐条写入（幂等，不覆盖既有数据）。
///
/// [nameOf] 是**必传**的（i18n B3 · T05）：种子名必须由调用方按当前语言给出，
/// 例如 `(String id) => taskSeedName(id, lookupAppLocalizations(locale))`。
/// 匿名回退（"id 直接当名字"）只放在 `seed_l10n.dart` 的未知 id 分支里 ——
/// 让「调用方忘了注入」变成**编译错误**而不是静默的中文上屏。
Future<void> ensureTaskSeed(
  TaskRepository repo, {
  required String Function(String seedId) nameOf,
}) async {
  if ((await repo.tasks()).isEmpty) {
    for (final TaskSeedTemplate tpl in kTaskSeedTemplates) {
      await repo.saveTask(tpl.toTask(name: nameOf(tpl.id)));
    }
  }
}
