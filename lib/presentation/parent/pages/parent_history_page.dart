/// 家长端「记录」页（C54 建页 · C55 加「按天 / 按周 / 按月」统计）。
///
/// 两块历史（自上而下）：
///  · **成长任务完成记录**：按成长项聚合「完成次数」+ 期间内首次 / 最近完成时间；
///  · **奖励兑换记录**：按奖励聚合「兑换次数」+ 期间内首次 / 最近兑换时间 + 累计消耗阳光。
///
/// 统计口径（C55，玄参 2026-10-10 需求「按天 / 按周 / 按月统计，方便查看」）：
///  · 顶部 `日 / 周 / 月` 切换 + `◀ 期间 ▶` 导航，两块历史**同时**按所选期间过滤聚合；
///  · 周以**周一**为起点；月为自然月；日/周/月均取半开区间 `[start, end)`；
///  · 不能翻到未来（下一期间起点 > 现在时禁用 ▶）。
///
/// 口径（冻结）：
///  · 只统计**已核销**的事实 —— 打卡 `status == verified`（联动项自动结算 / 家长核销通过）
///    与兑换 `status == verified`；pending（待家长确认）与 rejected（已驳回）**不计入**。
///  · 相同内容按 `taskId` / `templateId` 分组计数（这正是玄参要的「相同内容统计次数」）。
///  · 分组在页内做（数据量小、单孩子单机），**不新增 DAO / 不改表结构 / 不动既有接口**。
///
/// 排版纪律：本页作为「记录」tab 内嵌渲染，**不自带 Scaffold / AppBar**（外层
/// `ParentHomePage` 已提供顶部栏），与「今日 / 奖励 / 设置」三页保持一致。
library parent_history_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 记录页统计粒度。
enum _Period {
  /// 按天（自然日）。
  day('日'),

  /// 按周（周一为一周之始）。
  week('周'),

  /// 按月（自然月）。
  month('月');

  const _Period(this.label);

  /// 切换器上的短标签。
  final String label;
}

/// 家长端「记录」页：成长任务完成记录 + 奖励兑换记录（按内容统计次数）。
class ParentHistoryPage extends ConsumerStatefulWidget {
  const ParentHistoryPage({super.key, this.now});

  /// 注入「当前时刻」（仅测试用；生产为 null → 取系统时间）。
  final DateTime? now;

  @override
  ConsumerState<ParentHistoryPage> createState() => _ParentHistoryPageState();
}

class _ParentHistoryPageState extends ConsumerState<ParentHistoryPage> {
  late Future<_RawData> _future;

  /// 当前统计粒度（默认「日」）。
  _Period _period = _Period.day;

  /// 期间锚点（其所在日 / 周 / 月即当前查看的区间；归一到当地 0 点）。
  DateTime _anchor = _today();

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _anchor = _dayOf(_now);
    _future = _load();
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 重新拉取（块体闭包，避免把 Future 返回给 setState）。
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 切换粒度：保持「当前所在区间」不跳，只在同一锚点上换粒度。
  void _switchPeriod(_Period p) {
    if (p == _period) return;
    setState(() => _period = p);
  }

  void _shift(int delta) {
    setState(() => _anchor = _prevOrNext(_period, _anchor, delta));
  }

  /// 期间起点：日=当天 0 点；周=本周一 0 点；月=本月 1 日 0 点。
  static DateTime _startOf(_Period p, DateTime anchor) {
    switch (p) {
      case _Period.day:
        return _dayOf(anchor);
      case _Period.week:
        return _dayOf(anchor).subtract(Duration(days: anchor.weekday - 1));
      case _Period.month:
        return DateTime(anchor.year, anchor.month, 1);
    }
  }

  /// 期间结束（不含）：半开区间右端。
  static DateTime _endOf(_Period p, DateTime start) {
    switch (p) {
      case _Period.day:
        return start.add(const Duration(days: 1));
      case _Period.week:
        return start.add(const Duration(days: 7));
      case _Period.month:
        return DateTime(start.year, start.month + 1, 1);
    }
  }

  static DateTime _prevOrNext(_Period p, DateTime anchor, int delta) {
    final DateTime start = _startOf(p, anchor);
    if (delta > 0) {
      return _endOf(p, start);
    }
    switch (p) {
      case _Period.day:
        return start.subtract(const Duration(days: 1));
      case _Period.week:
        return start.subtract(const Duration(days: 7));
      case _Period.month:
        return DateTime(start.year, start.month - 1, 1);
    }
  }

  /// 并发拉取「已核销打卡 + 已核销兑换 + 成长项表 + 奖励模板表」，原始数据缓存后按粒度聚合。
  Future<_RawData> _load() async {
    final List<CheckIn> checkIns =
        await ref.read(taskCheckInServiceProvider).verifiedCheckIns();
    final List<RedemptionRequest> requests =
        await ref.read(rewardRepositoryProvider).verifiedRequests();
    final List<Task> tasks = await ref.read(taskRepositoryProvider).tasks();
    final List<RewardTemplate> templates =
        await ref.read(rewardRepositoryProvider).templates();
    return _RawData(
      checkIns: checkIns,
      requests: requests,
      taskById: <String, Task>{for (final Task t in tasks) t.id: t},
      tplById: <String, RewardTemplate>{
        for (final RewardTemplate t in templates) t.id: t,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RawData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_RawData> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('加载失败：${snap.error}'),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          );
        }

        final _RawData raw = snap.data!;
        final DateTime start = _startOf(_period, _anchor);
        final DateTime end = _endOf(_period, start);
        final _PeriodView view = _aggregate(raw, start, end);
        final bool canNext = !_endOf(_period, start).isAfter(_now);

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _PeriodBar(
                value: _period,
                onChanged: _switchPeriod,
              ),
              const SizedBox(height: 12),
              _PeriodNav(
                label: _label(_period, start, end),
                onPrev: () => _shift(-1),
                onNext: canNext ? () => _shift(1) : null,
              ),
              const SizedBox(height: 14),
              _SummaryCard(view: view),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.checklist,
                iconColor: Colors.green.shade600,
                title: '成长任务完成记录',
                tail: '共 ${view.totalTaskCount} 次',
              ),
              if (view.taskRows.isEmpty)
                const _EmptyHint(text: '本期间还没有成长项完成记录')
              else
                for (final _TaskHistoryRow row in view.taskRows) ...<Widget>[
                  _TaskHistoryTile(row: row),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 12),
              _SectionHeader(
                icon: Icons.card_giftcard,
                iconColor: Colors.deepOrange.shade400,
                title: '奖励兑换记录',
                tail:
                    '共 ${view.totalRewardCount} 次 · 消耗 ${view.totalRewardCost} 阳光',
              ),
              if (view.rewardRows.isEmpty)
                const _EmptyHint(text: '本期间还没有奖励兑换记录')
              else
                for (final _RewardHistoryRow row in view.rewardRows) ...<Widget>[
                  _RewardHistoryTile(row: row),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        );
      },
    );
  }

  /// 在 `[start, end)` 内聚合两块历史（页内计算，不触库）。
  _PeriodView _aggregate(_RawData raw, DateTime start, DateTime end) {
    bool inRange(DateTime t) =>
        !t.isBefore(start) && t.isBefore(end);

    // ── 成长任务：按 taskId 分组计数 ──────────────────────────────
    final Map<String, List<CheckIn>> byTask = <String, List<CheckIn>>{};
    for (final CheckIn c in raw.checkIns) {
      if (!inRange(c.completedAt)) continue;
      (byTask[c.taskId] ??= <CheckIn>[]).add(c);
    }
    final List<_TaskHistoryRow> taskRows = byTask.entries.map(
      (MapEntry<String, List<CheckIn>> e) {
        final List<CheckIn> rows = List<CheckIn>.of(e.value)
          ..sort((CheckIn a, CheckIn b) =>
              a.completedAt.compareTo(b.completedAt));
        final Task? task = raw.taskById[e.key];
        return _TaskHistoryRow(
          task: task,
          name: task?.name ?? '（已删除的成长项）',
          count: rows.length,
          firstAt: rows.first.completedAt,
          lastAt: rows.last.completedAt,
        );
      },
    ).toList()
      ..sort(_byCountThenLast<_TaskHistoryRow>(
        (r) => r.count,
        (r) => r.lastAt,
      ));

    // ── 奖励兑换：按 templateId 分组计数 ──────────────────────────
    final Map<String, List<RedemptionRequest>> byTpl =
        <String, List<RedemptionRequest>>{};
    for (final RedemptionRequest r in raw.requests) {
      if (!inRange(_at(r))) continue;
      (byTpl[r.templateId] ??= <RedemptionRequest>[]).add(r);
    }
    final List<_RewardHistoryRow> rewardRows = byTpl.entries.map(
      (MapEntry<String, List<RedemptionRequest>> e) {
        final List<RedemptionRequest> rows =
            List<RedemptionRequest>.of(e.value)
              ..sort((RedemptionRequest a, RedemptionRequest b) =>
                  _at(a).compareTo(_at(b)));
        final RewardTemplate? tpl = raw.tplById[e.key];
        final int cost = rows.fold<int>(
          0,
          (int sum, RedemptionRequest r) => sum + r.cost,
        );
        return _RewardHistoryRow(
          template: tpl,
          name: tpl?.name ?? '（已删除的奖励）',
          count: rows.length,
          costSum: cost,
          firstAt: _at(rows.first),
          lastAt: _at(rows.last),
        );
      },
    ).toList()
      ..sort(_byCountThenLast<_RewardHistoryRow>(
        (r) => r.count,
        (r) => r.lastAt,
      ));

    return _PeriodView(taskRows: taskRows, rewardRows: rewardRows);
  }

  /// 兑换时刻口径：优先核销时间，回落到申请时间。
  static DateTime _at(RedemptionRequest r) => r.verifiedAt ?? r.requestedAt;

  /// 排序：次数多的在前；次数相同则「最近一次」近的在前。
  static int Function(T, T) _byCountThenLast<T>(
    int Function(T) countOf,
    DateTime Function(T) lastOf,
  ) {
    return (T a, T b) {
      final int byCount = countOf(b).compareTo(countOf(a));
      if (byCount != 0) return byCount;
      return lastOf(b).compareTo(lastOf(a));
    };
  }

  /// 期间标题：今天 / 昨天 / 具体日；周区间；年月。
  String _label(_Period p, DateTime start, DateTime end) {
    final DateFormat md = DateFormat('M月d日');
    final DateTime today = _dayOf(_now);
    switch (p) {
      case _Period.day:
        if (start == today) return '今天 · ${md.format(start)}';
        if (start == today.subtract(const Duration(days: 1))) {
          return '昨天 · ${md.format(start)}';
        }
        return DateFormat('yyyy年M月d日').format(start);
      case _Period.week:
        final DateTime last = end.subtract(const Duration(days: 1));
        return '${DateFormat('yyyy年M月d日').format(start)} ～ ${md.format(last)}';
      case _Period.month:
        return '${start.year} 年 ${start.month} 月';
    }
  }
}

/// 原始（未按期间过滤）数据快照：拉取一次，切换粒度时只做页内聚合。
class _RawData {
  final List<CheckIn> checkIns;
  final List<RedemptionRequest> requests;
  final Map<String, Task> taskById;
  final Map<String, RewardTemplate> tplById;

  const _RawData({
    required this.checkIns,
    required this.requests,
    required this.taskById,
    required this.tplById,
  });
}

/// 单期间聚合结果。
class _PeriodView {
  final List<_TaskHistoryRow> taskRows;
  final List<_RewardHistoryRow> rewardRows;

  const _PeriodView({required this.taskRows, required this.rewardRows});

  /// 本期间完成次数（所有成长项求和）。
  int get totalTaskCount =>
      taskRows.fold<int>(0, (int s, _TaskHistoryRow r) => s + r.count);

  /// 本期间兑换次数（所有奖励求和）。
  int get totalRewardCount =>
      rewardRows.fold<int>(0, (int s, _RewardHistoryRow r) => s + r.count);

  /// 本期间消耗阳光（已核销兑换的成本求和）。
  int get totalRewardCost =>
      rewardRows.fold<int>(0, (int s, _RewardHistoryRow r) => s + r.costSum);
}

/// 单个成长项的历史聚合行。
class _TaskHistoryRow {
  /// 关联成长项；已被家长删除时为 null（名称回落占位）。
  final Task? task;
  final String name;
  final int count;
  final DateTime firstAt;
  final DateTime lastAt;

  const _TaskHistoryRow({
    required this.task,
    required this.name,
    required this.count,
    required this.firstAt,
    required this.lastAt,
  });
}

/// 单个奖励的历史聚合行。
class _RewardHistoryRow {
  /// 关联奖励模板；已被家长删除时为 null（名称回落占位）。
  final RewardTemplate? template;
  final String name;
  final int count;
  final int costSum;
  final DateTime firstAt;
  final DateTime lastAt;

  const _RewardHistoryRow({
    required this.template,
    required this.name,
    required this.count,
    required this.costSum,
    required this.firstAt,
    required this.lastAt,
  });
}

/// 粒度切换器：日 / 周 / 月。
class _PeriodBar extends StatelessWidget {
  final _Period value;
  final ValueChanged<_Period> onChanged;

  const _PeriodBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final Color active = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (final _Period p in _Period.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: p == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: p == value
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    p.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          p == value ? FontWeight.bold : FontWeight.w500,
                      color: p == value ? active : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 期间导航：◀ 当前期间 ▶（未来不可翻）。
class _PeriodNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _PeriodNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一期间',
          onPressed: onPrev,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一期间',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// 顶部汇总卡：一眼看到「本期间完成 / 兑换 / 消耗」。
class _SummaryCard extends StatelessWidget {
  final _PeriodView view;

  const _SummaryCard({required this.view});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SummaryStat(
              emoji: '✅',
              value: '${view.totalTaskCount}',
              label: '本期完成成长项',
            ),
          ),
          Container(width: 1, height: 44, color: Colors.grey.shade200),
          Expanded(
            child: _SummaryStat(
              emoji: '🎁',
              value: '${view.totalRewardCount}',
              label: '本期兑换奖励',
            ),
          ),
          Container(width: 1, height: 44, color: Colors.grey.shade200),
          Expanded(
            child: _SummaryStat(
              emoji: '☀',
              value: '${view.totalRewardCost}',
              label: '本期消耗阳光',
            ),
          ),
        ],
      ),
    );
  }
}

/// 汇总卡内的一格：emoji + 大数字 + 说明。
class _SummaryStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;

  const _SummaryStat({
    required this.emoji,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// 分区标题：图标 + 标题 + 右侧汇总尾注。
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String tail;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.tail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            tail,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// 空态提示。
class _EmptyHint extends StatelessWidget {
  final String text;

  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(text, style: TextStyle(color: Colors.grey.shade500)),
        ),
      );
}

/// 单条成长项历史：图标 + 名称 + 「完成 N 次」徽章 + 期间内首次/最近时间。
class _TaskHistoryTile extends StatelessWidget {
  final _TaskHistoryRow row;

  const _TaskHistoryTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final ({Color bg, Color fg}) cat = macaronColorById(row.task?.id ?? row.name);
    final String range = _rangeLabel(row.firstAt, row.lastAt);
    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _IconBlock(
            bg: cat.bg,
            asset: row.task == null ? null : growthIconAssetFor(row.task!),
            emoji: row.task?.category.icon ?? '📦',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  range,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CountBadge(text: '完成 ${row.count} 次', bg: cat.bg, fg: cat.fg),
        ],
      ),
    );
  }
}

/// 单条奖励历史：图标 + 名称 + 「兑换 N 次」徽章 + 期间内首次/最近时间 + 累计消耗。
class _RewardHistoryTile extends StatelessWidget {
  final _RewardHistoryRow row;

  const _RewardHistoryTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final ({Color bg, Color fg}) cat =
        macaronColorById(row.template?.id ?? row.name);
    final String range = _rangeLabel(row.firstAt, row.lastAt);
    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _IconBlock(
            bg: cat.bg,
            asset:
                row.template == null ? null : rewardIconAssetFor(row.template!),
            emoji: row.template?.contentCategory.icon ?? '🎁',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$range · 消耗 ${row.costSum} 阳光',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CountBadge(text: '兑换 ${row.count} 次', bg: cat.bg, fg: cat.fg),
        ],
      ),
    );
  }
}

/// 圆角图标块（美术资源缺失时回退 emoji）。
class _IconBlock extends StatelessWidget {
  final Color bg;
  final String? asset;
  final String emoji;

  const _IconBlock({required this.bg, required this.asset, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: asset == null
            ? Center(child: Text(emoji, style: const TextStyle(fontSize: 26)))
            : Image.asset(
                asset!,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
      ),
    );
  }
}

/// 次数徽章。
class _CountBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _CountBadge({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      );
}

/// 时间区间文案：只完成过一次 → 「某日」；多次 → 「首次 X ～ 最近 Y」。
String _rangeLabel(DateTime first, DateTime last) {
  final DateFormat fmt = DateFormat('yyyy-MM-dd');
  final String f = fmt.format(first);
  final String l = fmt.format(last);
  if (f == l) return f;
  return '首次 $f ～ 最近 $l';
}
