/// 孩子端「今日」tab（M3 导航重构 / §5 信息架构：今日状态卡）。
///
/// 内容（§5）：阳光池 / 今日专注 / 今日必做进度（仅 isDaily）+ 「开始专注」主按钮。
/// 数据随 [economyRevisionProvider] 变化重新拉取 —— 孩子打卡或家长核销后回到
/// 「今日」能看到最新进度（否则 IndexedStack 保活导致数值不刷新）。
///
/// 纪律：不自行实现任何阳光 / 软顶 / 打卡业务逻辑，任务进度取自
/// [TaskCheckInService.board]（与「任务」tab 同源）。
library child_today_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

/// 孩子端「今日」状态卡。
class ChildTodayPage extends ConsumerStatefulWidget {
  const ChildTodayPage({super.key});

  @override
  ConsumerState<ChildTodayPage> createState() => _ChildTodayPageState();
}

class _ChildTodayPageState extends ConsumerState<ChildTodayPage> {
  double _balance = 0;
  double _focusMinutes = 0;
  int _focusCount = 0;
  int _taskDone = 0;
  int _taskTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final DateTime now = DateTime.now();
      final double balance =
          await ref.read(sunlightRepositoryProvider).balance();
      final List<FocusSession> sessions =
          await ref.read(focusRepositoryProvider).sessionsOfDay(dayKey(now));
      final double focusMinutes = sessions.fold(
          0.0, (double a, FocusSession s) => a + s.actualFocusMin);
      final TodayTaskBoard board =
          await ref.read(taskCheckInServiceProvider).board(now);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _focusMinutes = focusMinutes;
        _focusCount = sessions.length;
        _taskDone = board.doneCount;
        _taskTotal = board.total;
        _loading = false;
      });
    } catch (_) {
      // 今日卡属概览，任一查询失败不阻塞（保留上次值）。
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 经济修订号变化（打卡 / 核销 / 兑换）→ 重新拉取，保证数字同步。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload();
    });

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _StatCard(
          icon: Icons.wb_sunny,
          color: const Color(0xFFE8A600),
          label: '我的阳光',
          value: '${_balance.toInt()}',
          unit: '☀',
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.timer,
          color: Colors.teal,
          label: '今日专注',
          value: '${_focusMinutes.round()} 分钟',
          unit: '· $_focusCount 次',
        ),
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.checklist,
          color: Colors.indigo,
          // 口径与「任务」tab 一致：仅「今日必做（isDaily）」。doneCount/total
          // 由 [TodayTaskBoard] 保证只统计 isDaily 项，故此处即必做进度。
          label: '今日成长',
          value: '$_taskDone / $_taskTotal',
          unit: _taskTotal > 0 && _taskDone >= _taskTotal ? '全部完成 🌻' : '',
        ),
        const SizedBox(height: 28),
        // 引导：只有从「成长」tab 的具体成长项进入专注，达标后才会自动结算该项阳光
        // （本题的「开始专注」是自由专注入口，不带成长项，故不会触发联动结算）。
        const Text(
          '想赚成长阳光？从「成长」里点具体项目开始专注 🌻',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.go('/entry'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始专注'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

/// 单张状态卡（图标 + 标签 + 主数值 + 次要单位）。
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          value,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                        if (unit.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(unit,
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
