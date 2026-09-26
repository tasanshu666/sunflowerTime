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

/// 暖奶油底（与养护面板 / 商店一致，形成分层暖色风格）。
const Color _kCream = Color(0xFFFBF4E4);

/// 完成进度环的橙色。
const Color _kProgressOrange = Color(0xFFFF8A3D);

/// 完成态胶囊：浅绿底深绿字。
const Color _kDoneBg = Color(0xFFD9F2DD);
const Color _kDoneFg = Color(0xFF2E7D32);

/// 待办 / 可行动胶囊：暖黄底深字。
const Color _kTodoBg = Color(0xFFFFF1C2);
const Color _kTodoFg = Color(0xFF8D6E00);

/// 待确认胶囊：暖橙底深橙字。
const Color _kWaitBg = Color(0xFFFFE0B2);
const Color _kWaitFg = Color(0xFFE65100);

/// 马卡龙图标块色底（按条目轮换 3-4 种明快色）。
const List<Color> _macaronBg = <Color>[
  Color(0xFFFFD9E0),
  Color(0xFFFFF1C2),
  Color(0xFFD9F2DD),
  Color(0xFFD9E8FF),
];

/// 马卡龙图标块对应的深字色（保证对比度）。
const List<Color> _macaronFg = <Color>[
  Color(0xFFC2185B),
  Color(0xFF8D6E00),
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
];

/// 橙色进度环 + 中央百分比（有限、静态绘制，不引入动画）。
Widget _progressRing(double value) {
  final int pct = (value.clamp(0.0, 1.0) * 100).round();
  return SizedBox(
    width: 56,
    height: 56,
    child: Stack(
      alignment: Alignment.center,
      children: <Widget>[
        CircularProgressIndicator(
          value: value.clamp(0.0, 1.0),
          strokeWidth: 6,
          backgroundColor: const Color(0xFFFFE0B2),
          color: _kProgressOrange,
        ),
        Text(
          '$pct%',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _kProgressOrange,
          ),
        ),
      ],
    ),
  );
}

/// 胶囊状态块（可点 / 只读均可）：圆角胶囊 + 图标 + 文案，颜色由调用方按状态给。
///
/// [fullWidth] = true 时铺满整行（内容居中），用于卡片「下段」通栏操作胶囊；
/// 默认 false 时为内容宽度的紧凑胶囊。
Widget _statusCapsule({
  required String text,
  required IconData icon,
  required Color bg,
  required Color fg,
  Widget? leading,
  VoidCallback? onTap,
  bool fullWidth = false,
}) {
  final Widget inner = Container(
    width: fullWidth ? double.infinity : null,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: <Widget>[
        if (leading != null)
          leading
        else
          Icon(icon, size: 16, color: fg),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
        ),
      ],
    ),
  );
  if (onTap == null) return inner;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: inner,
  );
}

/// 按条目状态返回状态图标（与原布局口径一致）。
IconData _statusIcon(TaskCheckInItem item) {
  if (item.pendingVerification) return Icons.hourglass_top;
  if (item.done) return Icons.check_circle;
  if (item.task.requiresFocus) return Icons.timer_outlined;
  return Icons.assignment_outlined;
}

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
      // 口径（2026-09-23）：这是**成长奖励**自己的日上限，与专注的每日专注上限
      // （低 60 / 中 90 / 高 120 分钟）无关，故文案不再说「今日阳光已达上限」。
      _snack('今天的成长奖励已经拿满 ${kTaskCheckinDailyCap.toInt()} 啦，明天再来');
    } else if (o.cappedByDailyCap) {
      _snack('太棒了！+${_fmtSun(o.granted)} 阳光'
          '（今日成长奖励已达上限，本次只到账 ${_fmtSun(o.granted)}）');
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
    // 暖奶油底（与养护面板 / 商店一致，所有状态都铺底）。
    if (_loading) {
      return const ColoredBox(
        color: _kCream,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return ColoredBox(
        color: _kCream,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('加载失败：$_error'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final TodayTaskBoard board = _board!;
    if (board.items.isEmpty) {
      return const ColoredBox(
        color: _kCream,
        child: Center(
          child: Text('今天没有成长项，去玩吧 🌻', style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return ColoredBox(
      color: _kCream,
      child: Column(
        children: <Widget>[
          _header(board),
          Expanded(child: _taskList(board)),
        ],
      ),
    );
  }

  /// 顶部「今日成长 x/y + 橙色进度环」头部：白卡 + 左侧进度环 + 右侧大号完成数。
  ///
  /// 完成度数据来自现成 [TodayTaskBoard]（doneCount/total 仅统计 isDaily 项），
  /// **不新增任何领域查询**。文案沿用，未改写。
  Widget _header(TodayTaskBoard board) {
    final double ratio = board.total > 0 ? board.doneCount / board.total : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            // 橙色进度环 + 中央百分比。
            _progressRing(ratio),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 完成数用大号粗体强调。
                  Text(
                    '今日成长 ${board.doneCount}/${board.total}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
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
          ],
        ),
      ),
    );
  }

  /// 列表分区渲染（M5）：按成长项内容分类（学习/运动/生活/其他）作 FIRST-LEVEL 分区头，
  /// 每个分区下列出该分类下的成长项卡片；每张卡片自带「每日/每周」徽标（见 [_taskTile]）。
  ///
  /// 分区仅影响展示分组，**不改变可交互性**——分类只是孩子视角的收纳方式，动作逻辑
  /// （联动项进入专注 / 非联动项「我做到了」）完全不变。空分类整段不渲染（含标题）。
  /// 条目索引跨分区递增，保证彩色图标块稳定轮换且不重复。
  Widget _taskList(TodayTaskBoard board) {
    final List<TaskCheckInItem> items = board.items;

    final List<Widget> children = <Widget>[];
    int index = 0; // 跨分区递增，保证彩色图标块稳定轮换且不重复。
    for (final TaskCategory cat in kTaskCategoryOrder) {
      final List<TaskCheckInItem> group = items
          .where((TaskCheckInItem i) => i.task.category == cat)
          .toList(growable: false);
      if (group.isEmpty) continue; // 空分类整体不渲染（含标题）
      if (children.isNotEmpty) children.add(const SizedBox(height: 16));
      children.add(_sectionHeader(cat.label, cat.icon));
      for (final TaskCheckInItem item in group) {
        children.add(const SizedBox(height: 10));
        children.add(_taskTile(item, index++));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: children,
    );
  }

  /// 分区标题（左侧占位图标 emoji + 分类名）。
  Widget _sectionHeader(String title, String icon) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          children: <Widget>[
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),
      );

  /// 每日/每周 小徽标（孩子一眼区分「今天要做」与「本周做」）。
  Widget _dailyBadge(bool isDaily) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isDaily ? _kTodoBg : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isDaily ? '每日' : '每周',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDaily ? _kTodoFg : Colors.blue.shade700,
          ),
        ),
      );

  /// 单条成长项：白卡 + 左侧彩色圆角图标块（马卡龙色底 + 状态图标）+ 胶囊状态。
  ///
  /// 两段式布局（修复窄屏挤压）：
  ///  · 上段 = 图标块 + 标题/信息（信息独占整行宽，不再被右侧胶囊挤成逐字换行）；
  ///  · 下段 = 操作胶囊通栏铺满整行，与卡片等宽、内容居中。
  Widget _taskTile(TaskCheckInItem item, int index) {
    final bool busy = _busyTaskId == item.task.id;
    final IconData statusIcon = _statusIcon(item);
    final Color blockBg = _macaronBg[index % _macaronBg.length];
    final Color blockFg = _macaronFg[index % _macaronFg.length];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 上段：图标块 + 标题/信息（信息独占整行宽 → 单行放下，标题不再逐字断行）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 左侧彩色圆角图标块（马卡龙色底 + 状态图标），尺寸原样 42x42。
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: blockBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, color: blockFg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        _dailyBadge(item.isDaily),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(item.task.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
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
            ],
          ),
          const SizedBox(height: 10),
          // 下段：操作胶囊通栏（铺满整行，内容居中），与卡片等宽、不挤压上段文字。
          _buildAction(item, busy, fullWidth: true),
        ],
      ),
    );
  }

  /// 行内操作区（M4 冻结口径）：按 [Task.requiresFocus] 单点互斥，
  /// **同一行绝不并存放「开始专注」与「我做到了」**。统一改为胶囊状态块。
  ///
  /// [fullWidth] = true 时胶囊通栏铺满整行（卡片「下段」用）；默认紧凑胶囊。
  Widget _buildAction(TaskCheckInItem item, bool busy, {bool fullWidth = false}) {
    // ① 待家长确认：常态仅出现在非联动项；联动项若出现即契约外异常，显式渲染不静默。
    if (item.pendingVerification) {
      return _statusCapsule(
        text: '等家长确认',
        icon: Icons.hourglass_top,
        bg: _kWaitBg,
        fg: _kWaitFg,
        fullWidth: fullWidth,
      );
    }

    // ② 已提交（verified）→ 只读态。
    if (item.done) {
      return _statusCapsule(
        text: item.task.requiresFocus ? '已完成 ✓' : '已做到 ✓',
        icon: Icons.check,
        bg: _kDoneBg,
        fg: _kDoneFg,
        fullWidth: fullWidth,
      );
    }

    // ③ 未提交 → 联动项只给「开始专注」（达标自动结算，孩子无可点打卡按钮）；
    //    非联动项只给「我做到了」（落待家长确认，家长核销后才发阳光）。
    if (item.task.requiresFocus) {
      return _statusCapsule(
        text: '开始专注 · 需 ${item.task.minFocusMin} 分钟',
        icon: Icons.timer_outlined,
        bg: _kTodoBg,
        fg: _kTodoFg,
        fullWidth: fullWidth,
        onTap: () => context.go(
          '/focus?minutes=${item.task.minFocusMin}&dnd=1&task=${item.task.id}',
        ),
      );
    }
    return _statusCapsule(
      text: '我做到了',
      icon: Icons.check_circle,
      bg: _kTodoBg,
      fg: _kTodoFg,
      fullWidth: fullWidth,
      // 提交中：用转圈占位、不可点（防连点重复打卡）。
      leading: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: busy ? null : () => _checkIn(item.task),
    );
  }
}
