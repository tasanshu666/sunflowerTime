/// 家长端今日页 · 许愿树区块（A21.1 / A21.4 / A-T05）。
///
/// 范式照抄 `_PendingCheckInsCard`：`creamCardDecoration()` + `Padding(16)` +
/// 标题行 `Icon + Expanded(Text) + 计数`。空列表 ⇒ 整卡（含标题）不渲染。
///
/// ## 三段 + 折叠（A21.4 / V14）
/// 互斥分段，优先级 待我核销 > 待我安排 > 进行中 > 折叠；唯一判据来自
/// 领域层 [WishOrchestrationService.sectionOf]，本 widget 不现写条件。
/// 默认只展示前三段，折叠段收进「查看全部 N 条」。
///
/// ## 「孩子说做到了」撤销分区（v0.7.0 / A19.5 护栏①）
/// 列出孩子自助达成（fulfillSource 为 child 来源）的愿望，每条「退回树上」
/// 经二次确认调 `undoFulfill`（全状态机唯一合法反向边）。仅家长端显式操作。
///
/// 纯展示：写操作经回调上抛给页面接线，便于 widget 测试直接构造数据。
library wish_tree_section;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/widgets/parent_wish_card.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 一条愿望的分组数据：愿望本体 + 名下任务 + 待核销打卡。
class WishDeskEntry {
  const WishDeskEntry({
    required this.wish,
    this.tasks = const <Task>[],
    this.checkIns = const <CheckIn>[],
    this.pending = const <PendingCheckIn>[],
  });

  final Wish wish;
  final List<Task> tasks;
  final List<CheckIn> checkIns;
  final List<PendingCheckIn> pending;
}

/// 家长端今日页许愿树区块。
class WishTreeSection extends StatefulWidget {
  const WishTreeSection({
    super.key,
    required this.entries,
    required this.service,
    this.selfFulfilled = const <Wish>[],
    required this.onSetup,
    required this.onFulfill,
    required this.onTag,
    required this.onVerify,
    required this.onReject,
    required this.onUndo,
  });

  /// 树上愿望（已 `parentDeskList` 排序：提醒置顶 + 等待天数降序）。
  final List<WishDeskEntry> entries;

  /// 分段判据单点（领域服务）。
  final WishOrchestrationService service;

  /// 孩子自助达成（fulfillSource 为 child 来源）的愿望，供撤销分区。
  final List<Wish> selfFulfilled;

  final void Function(WishDeskEntry entry) onSetup;
  final void Function(WishDeskEntry entry) onFulfill;
  final void Function(WishDeskEntry entry) onTag;
  final void Function(PendingCheckIn item) onVerify;
  final void Function(PendingCheckIn item) onReject;

  /// 撤销：孩子说做到了 → 退回树上（二次确认在页面接线处完成）。
  final void Function(Wish wish) onUndo;

  @override
  State<WishTreeSection> createState() => _WishTreeSectionState();
}

class _WishTreeSectionState extends State<WishTreeSection> {
  bool _showAll = false;

  /// 唯一分段编排：委托模块级 [partitionWishDesk]（互斥且完备）。
  ({
    List<WishDeskEntry> verify,
    List<WishDeskEntry> setup,
    List<WishDeskEntry> progress,
    List<WishDeskEntry> collapsed,
  }) _split() =>
      partitionWishDesk(service: widget.service, entries: widget.entries);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final ({List<WishDeskEntry> verify, List<WishDeskEntry> setup,
            List<WishDeskEntry> progress, List<WishDeskEntry> collapsed}) parts =
        _split();

    // 空列表 ⇒ 整张卡（含标题 + 撤销分区）都不渲染。
    if (widget.entries.isEmpty && widget.selfFulfilled.isEmpty) {
      return const SizedBox.shrink();
    }

    final int total = widget.entries.length;
    return Container(
      key: const Key('parent_wish_tree_section'),
      decoration: creamCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.park, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.parent_wish_tree_title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(t.parent_today_count(total),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (parts.verify.isNotEmpty)
              _section(
                t: t,
                title: t.parent_wish_section_verify,
                entries: parts.verify,
              ),
            if (parts.setup.isNotEmpty)
              _section(
                t: t,
                title: t.parent_wish_section_setup,
                entries: parts.setup,
              ),
            if (parts.progress.isNotEmpty)
              _section(
                t: t,
                title: t.parent_wish_section_progress,
                entries: parts.progress,
              ),
            if (parts.collapsed.isNotEmpty)
              _collapsed(t: t, entries: parts.collapsed),
            if (widget.selfFulfilled.isNotEmpty)
              _selfFulfilledSection(t: t),
          ],
        ),
      ),
    );
  }

  /// 单个分段：小标题 + 若干愿望卡。
  Widget _section({
    required AppLocalizations t,
    required String title,
    required List<WishDeskEntry> entries,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8D6E00),
              )),
          for (final WishDeskEntry entry in entries)
            _card(t: t, entry: entry),
        ],
      ),
    );
  }

  /// 折叠段：默认收起；「查看全部 N 条」展开后逐条只读展示。
  Widget _collapsed({
    required AppLocalizations t,
    required List<WishDeskEntry> entries,
  }) {
    final int n = entries.length; // 折叠计数 = 折叠集合条数（A21.4）。
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!_showAll)
            TextButton(
              key: const Key('parent_wish_view_all'),
              onPressed: () => setState(() => _showAll = true),
              child: Text(t.parent_wish_view_all(n)),
            )
          else
            for (final WishDeskEntry entry in entries)
              _card(t: t, entry: entry, readOnly: true),
        ],
      ),
    );
  }

  /// 「✨ 孩子说做到了」撤销分区。
  Widget _selfFulfilledSection({required AppLocalizations t}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(t.parent_wish_self_fulfilled_title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
              )),
          for (final Wish wish in widget.selfFulfilled)
            _UndoableWishTile(
              wish: wish,
              t: t,
              onUndo: () => widget.onUndo(wish),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required AppLocalizations t,
    required WishDeskEntry entry,
    bool readOnly = false,
  }) {
    if (readOnly) {
      // 折叠段只读：复用卡片但动作按钮不触发写（onSetup/onFulfill/onTag 空实现）。
      return ParentWishCard(
        wish: entry.wish,
        waitDays: WishOrchestrationService.waitingDays(
            entry.wish.createdAt, DateTime.now()),
        tasks: entry.tasks,
        checkIns: entry.checkIns,
        pending: entry.pending,
        onSetup: () {},
        onFulfill: () {},
        onTag: () {},
      );
    }
    return ParentWishCard(
      wish: entry.wish,
      waitDays:
          WishOrchestrationService.waitingDays(entry.wish.createdAt, DateTime.now()),
      tasks: entry.tasks,
      checkIns: entry.checkIns,
      pending: entry.pending,
      onSetup: () => widget.onSetup(entry),
      onFulfill: () => widget.onFulfill(entry),
      onTag: () => widget.onTag(entry),
      onVerify: widget.onVerify,
      onReject: widget.onReject,
    );
  }
}

/// 撤销分区单条：愿望短名 + 「退回树上」（二次确认在页面接线处完成）。
class _UndoableWishTile extends StatelessWidget {
  const _UndoableWishTile({
    required this.wish,
    required this.t,
    required this.onUndo,
  });

  final Wish wish;
  final AppLocalizations t;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              wish.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: Key('parent_wish_undo_${wish.id}'),
            onPressed: onUndo,
            child: Text(t.parent_wish_undo),
          ),
        ],
      ),
    );
  }
}

/// A-T05 分段纯函数：便于 widget 测试独立断言四段互斥且完备、折叠计数 = 折叠集合条数。
///
/// 判据完全交给领域层 [WishOrchestrationService.sectionOf]，本函数只做归类。
({
  List<WishDeskEntry> verify,
  List<WishDeskEntry> setup,
  List<WishDeskEntry> progress,
  List<WishDeskEntry> collapsed,
}) partitionWishDesk({
  required WishOrchestrationService service,
  required List<WishDeskEntry> entries,
}) {
  final List<WishDeskEntry> verify = <WishDeskEntry>[];
  final List<WishDeskEntry> setup = <WishDeskEntry>[];
  final List<WishDeskEntry> progress = <WishDeskEntry>[];
  final List<WishDeskEntry> collapsed = <WishDeskEntry>[];
  for (final WishDeskEntry entry in entries) {
    switch (service.sectionOf(
      wish: entry.wish,
      tasks: entry.tasks,
      checkIns: entry.checkIns,
    )) {
      case WishWorkCategory.pendingVerify:
        verify.add(entry);
      case WishWorkCategory.needsSetup:
        setup.add(entry);
      case WishWorkCategory.selfProgressing:
        progress.add(entry);
      case WishWorkCategory.collapsed:
        collapsed.add(entry);
    }
  }
  return (
    verify: verify,
    setup: setup,
    progress: progress,
    collapsed: collapsed,
  );
}
