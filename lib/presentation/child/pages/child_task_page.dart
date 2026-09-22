/// 孩子端「成长」tab（M4 / §4.4 今日成长卡 + 打卡 / 专注联动）。
///
/// 渲染规则（M4 冻结口径，按 [Task.requiresFocus] 单点互斥，**同一行绝不并存
/// 「开始专注」与「我做到了」两个动作**）：
///  - **联动项**（requiresFocus == true）：只给「开始专注 · 需 N 分钟」——从本项进入专注、
///    达标后由专注页 [TaskCheckInService.settleFocusLinked] **自动结算**，孩子**没有**可点的
///    打卡按钮（无从刷分）；已完成 → 「已完成 ✓」只读。
///  - **非联动项**（requiresFocus == false）：只给「我做到了」——调用 [TaskCheckInService.checkIn]
///    落 **待家长确认**（当期不发阳光）；待确认中 → 「等家长确认」只读；已核销 → 「已做到 ✓」。
///
/// 全部阳光 / 软顶 / 联动结算 / 核销逻辑均由 [TaskCheckInService] 负责，本页**不自行实现**
/// 任何阳光计算或状态推断，只按服务给出的 [TaskCheckInItem] 字段渲染并给反馈。
library child_task_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

/// 孩子端「成长」：今日成长项列表。
class ChildTaskPage extends ConsumerStatefulWidget {
  const ChildTaskPage({super.key});

  @override
  ConsumerState<ChildTaskPage> createState() => _ChildTaskPageState();
}

class _ChildTaskPageState extends ConsumerState<ChildTaskPage> {
  TodayTaskBoard? _board;
  bool _loading = true;
  String? _error;
  String? _busyTaskId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final TodayTaskBoard board =
          await ref.read(taskCheckInServiceProvider).board(DateTime.now());
      if (!mounted) return;
      setState(() {
        _board = board;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 非联动项手动打卡：调服务 → 反馈 → 自增经济修订号令今日卡/商店/花园同步。
  ///
  /// 联动项不会走到这里（其按钮是「开始专注」，走专注页自动结算）。
  Future<void> _checkIn(Task task) async {
    if (_busyTaskId != null) return; // 串行闸门，避免连点重复打卡
    setState(() => _busyTaskId = task.id);
    try {
      final TaskCheckInOutcome outcome = await ref
          .read(taskCheckInServiceProvider)
          .checkIn(task: task, now: DateTime.now());
      if (!mounted) return;
      await _feedback(outcome);
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload();
    } on TaskCheckInException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('打卡失败：$e');
    } finally {
      if (mounted) setState(() => _busyTaskId = null);
    }
  }

  /// 按 [TaskCheckInOutcome] 给出孩子友好反馈（M4）。
  ///
  /// 非联动项手动打卡 → `status == pending`、`granted == 0`：**当期不发阳光**，
  /// 故此处不再出现「+X 阳光」，改为告知孩子「等家长确认就会发」（核销属家长端流程）。
  Future<void> _feedback(TaskCheckInOutcome o) async {
    if (o.allTasksDone) {
      // 当日全部成长项已提交（pending 也算已提交）→ 完美日庆祝。
      // 口径（与服务层一致）：完美日是即时情绪反馈，**不等家长核销**。
      await _celebratePerfectDay();
    }
    if (o.status == CheckInStatus.pending) {
      _snack('已经告诉爸爸妈妈啦，等他们确认就发阳光 🌻');
    } else if (o.granted <= 0) {
      _snack('今日阳光已达上限 ${kSoftCapDailyMax.toInt()}，明天再来');
    } else if (o.cappedBySoftCap) {
      _snack('太棒了！+${_fmtSun(o.granted)} 阳光'
          '（今日阳光已达上限，本次只到账 ${_fmtSun(o.granted)}）');
    } else {
      _snack('太棒了！+${_fmtSun(o.granted)} 阳光');
    }
  }

  /// 阳光数值展示：整数则不带小数，否则保留 1 位。
  String _fmtSun(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _celebratePerfectDay() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('🌻 今日成长项全部完成！'),
        content: const Text('你今天把全部成长项都做完啦，获得「完美日」标记！'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('太棒啦'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('加载失败：$_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    final TodayTaskBoard board = _board!;
    if (board.items.isEmpty) {
      return const Center(
        child: Text('今天没有成长项，去玩吧 🌻', style: TextStyle(fontSize: 16)),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 进度口径 = 仅「今日必做（isDaily）」的**已提交**数：doneCount/total 由
                // [TodayTaskBoard] 保证只统计 isDaily 项（pending 亦算已提交）。
                Text(
                  '今日成长 ${board.doneCount}/${board.total}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                // 若不与每周成长项同屏，用一行小字补充说明，避免孩子误以为漏做。
                if (board.weeklyCount > 0) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '另有每周成长 ${board.weeklyCount} 项',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(child: _taskList(board)),
      ],
    );
  }

  /// 列表分区渲染（§4.4）：`每日成长`（isDaily）与 `每周成长`（非 isDaily）。
  ///
  /// 分区仅影响展示分组，**不改变可交互性**——每周成长项与每日成长项走同一套动作
  /// （联动项同样可进入专注自动结算 / 非联动项同样可「我做到了」）。
  /// `weeklyCount == 0` 时「每周成长」整段不渲染。
  Widget _taskList(TodayTaskBoard board) {
    final List<TaskCheckInItem> daily = board.items
        .where((TaskCheckInItem i) => i.isDaily)
        .toList(growable: false);
    final List<TaskCheckInItem> weekly = board.items
        .where((TaskCheckInItem i) => !i.isDaily)
        .toList(growable: false);

    final List<Widget> children = <Widget>[];
    void addSection(String title, List<TaskCheckInItem> items) {
      if (items.isEmpty) return; // 空段整体不渲染（含标题）
      if (children.isNotEmpty) children.add(const SizedBox(height: 16));
      children.add(_sectionHeader(title));
      for (final TaskCheckInItem item in items) {
        children.add(const SizedBox(height: 10));
        children.add(_taskTile(item));
      }
    }

    addSection('每日成长', daily);
    addSection('每周成长', weekly);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: children,
    );
  }

  /// 分区标题（左侧小标题）。
  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.blueGrey,
          ),
        ),
      );

  Widget _taskTile(TaskCheckInItem item) {
    final bool busy = _busyTaskId == item.task.id;
    // 图标：待确认（橙）> 已完成（绿）> 未完成（联动=计时器 / 非联动=清单）。
    final IconData icon;
    final Color iconColor;
    if (item.pendingVerification) {
      icon = Icons.hourglass_top;
      iconColor = Colors.orange;
    } else if (item.done) {
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else if (item.task.requiresFocus) {
      icon = Icons.timer_outlined;
      iconColor = Colors.blueGrey;
    } else {
      icon = Icons.assignment_outlined;
      iconColor = Colors.blueGrey;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.task.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    item.task.requiresFocus
                        ? '${item.task.subjectLabel} · 需专注 ${item.task.minFocusMin} 分钟 · +${item.task.effectiveSunlightReward} ☀'
                        : '${item.task.subjectLabel} · +${item.task.effectiveSunlightReward} ☀',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildAction(item, busy),
          ],
        ),
      ),
    );
  }

  /// 行内操作区（M4 冻结口径）：按 [Task.requiresFocus] 单点互斥，
  /// **同一行绝不并存放「开始专注」与「我做到了」**。
  Widget _buildAction(TaskCheckInItem item, bool busy) {
    // ① 待家长确认：常态仅出现在非联动项；联动项若出现即契约外异常，显式渲染不静默。
    if (item.pendingVerification) {
      return TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top, size: 18),
        label: const Text('等家长确认'),
        style: TextButton.styleFrom(disabledForegroundColor: Colors.orange),
      );
    }

    // ② 已提交（verified）→ 只读态。
    if (item.done) {
      return TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check),
        label: Text(item.task.requiresFocus ? '已完成 ✓' : '已做到 ✓'),
      );
    }

    // ③ 未提交 → 联动项只给「开始专注」（达标自动结算，孩子无可点打卡按钮）；
    //    非联动项只给「我做到了」（落待家长确认，家长核销后才发阳光）。
    if (item.task.requiresFocus) {
      return FilledButton(
        onPressed: () => context.go(
          '/focus?minutes=${item.task.minFocusMin}&dnd=1&task=${item.task.id}',
        ),
        child: Text('开始专注 · 需 ${item.task.minFocusMin} 分钟'),
      );
    }
    return FilledButton(
      onPressed: busy ? null : () => _checkIn(item.task),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('我做到了'),
    );
  }
}
