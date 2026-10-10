/// 家长端·任务配置页（M3 T05，§4.4 / §8.2）。
///
/// 学习任务模板增删改：列表展示所有模板（内置 + 自定义），支持新增 / 编辑 / 删除，
/// 自动打卡关联专注（requiresFocus）。模板落 [TaskRepository]，打卡经 [TaskRepository.checkIn]。
library parent_task_config_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 任务配置页：家长管理学习任务模板。
///
/// [embedded] = true 时作为家长端「任务」tab 的内容渲染（不叠加 AppBar，避免双层
/// 标题栏 + 两个返回箭头）；false 时保留独立路由页形态（`/parent/tasks`）。
class ParentTaskConfigPage extends ConsumerStatefulWidget {
  const ParentTaskConfigPage({super.key, this.embedded = false});

  /// 是否以内嵌 tab 形态渲染（无独立 AppBar）。
  final bool embedded;

  @override
  ConsumerState<ParentTaskConfigPage> createState() =>
      _ParentTaskConfigPageState();
}

class _ParentTaskConfigPageState extends ConsumerState<ParentTaskConfigPage> {
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _tasks = await ref.read(taskRepositoryProvider).tasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openEditor({Task? initial}) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => TaskEditorDialog(
        initial: initial,
        onSave: (Task t) async {
          await ref.read(taskRepositoryProvider).saveTask(t);
        },
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _delete(Task t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除成长项？'),
        content: Text('确定删除「${t.name}」？已生成的打卡记录会保留。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(taskRepositoryProvider).deleteTaskById(t.id);
      await _reload();
    }
  }

  String _repeatLabel(String? rule) {
    switch (rule) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      default:
        return '不重复';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 内嵌（任务 tab）时不叠加第二层 AppBar：外层家长端 AppBar 已在顶部。
      appBar: widget.embedded ? null : AppBar(title: const Text('成长配置')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: '新增成长项',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? const Center(child: Text('还没有成长项，点右下角新增一个吧'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext ctx, int i) {
                    final Task t = _tasks[i];
                    final ({Color bg, Color fg}) cat = macaronColorById(t.id);
                    return Container(
                      decoration: creamCardDecoration(),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          // C48（玄参 2026-10-10）：图标与孩子端成长页同款 UI 素材
                          //（联动项一律 focus 闹钟，见 growth_icons），失败回退色块 + emoji。
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: cat.bg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                growthIconAssetFor(t),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(t.category.icon,
                                      style: const TextStyle(fontSize: 28)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  t.name,
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: <Widget>[
                                    pillLabel(
                                      text: t.categoryLabel,
                                      bg: cat.bg,
                                      fg: cat.fg,
                                    ),
                                    pillLabel(
                                      text: t.subjectLabel,
                                      bg: Colors.grey.shade100,
                                      fg: Colors.grey.shade700,
                                    ),
                                    // C48：「N 阳光」→ 数字 + 阳光 UI 图标。
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1C2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Text(
                                            '${t.effectiveSunlightReward}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF8D6E00),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Image.asset(
                                            'assets/rewards/sunlight.png',
                                            width: 13,
                                            height: 13,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.wb_sunny,
                                              color: Color(0xFFE8A600),
                                              size: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (t.requiresFocus)
                                      pillLabel(
                                        text: '专注 ${t.minFocusMin} 分',
                                        bg: Colors.teal.shade50,
                                        fg: Colors.teal.shade700,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Colors.blueGrey),
                                tooltip: '编辑',
                                onPressed: () => _openEditor(initial: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: '删除',
                                onPressed: () => _delete(t),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
