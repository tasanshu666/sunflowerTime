/// 家长端今日页 · 许愿树区块的**单条愿望卡**（A21.4 / A-T05）。
///
/// 纯展示 widget：所有写操作经回调上抛给页面（页面组2/组3 接真实弹层与领域
/// 调用），本卡不读任何 provider、不发埋点 —— 便于 widget 测试直接构造数据。
///
/// 卡片内容：愿望原文（2 行截断）+ 许愿日期 + 等待天数 + 进度条（有目标时，
/// 复用孩子端 [WishProgressBar] 绝对量文案）+ 标签缎带（非红色）+ 家长三动作
/// 按钮（恰好 3 个）+ 名下待核销任务的「核销 / 驳回」按钮。
library parent_wish_card;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/i18n/wish_l10n.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';

/// 单条愿望卡。
class ParentWishCard extends StatelessWidget {
  const ParentWishCard({
    super.key,
    required this.wish,
    this.waitDays = 0,
    this.tasks = const <Task>[],
    this.checkIns = const <CheckIn>[],
    this.pending = const <PendingCheckIn>[],
    required this.onSetup,
    required this.onFulfill,
    required this.onTag,
    this.onVerify,
    this.onReject,
  });

  final Wish wish;
  final int waitDays;
  final List<Task> tasks;
  final List<CheckIn> checkIns;
  final List<PendingCheckIn> pending;

  /// 动作 ①：设定目标 + 布置任务（打开 WishTaskEditor）。
  final VoidCallback onSetup;

  /// 动作 ②：直接实现（确认后 fulfill）。
  final VoidCallback onFulfill;

  /// 动作 ③：贴标签 + 温柔回复（打开 ParentWishActionSheet）。
  final VoidCallback onTag;

  /// 名下待核销任务的核销 / 驳回（走既有 check_ins 流水）。
  final void Function(PendingCheckIn item)? onVerify;
  final void Function(PendingCheckIn item)? onReject;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final String date = DateFormat('yyyy-MM-dd').format(wish.createdAt);
    final String? tagName = wish.tagKey == null
        ? null
        : _tagText(wish.tagKey!, t);
    final int done = wish.progressValue;
    final int target = wish.targetValue;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            wish.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.wishTreeWishDate(date)} · ${t.wishTreeWaitDays(waitDays)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (tagName != null) ...<Widget>[
            const SizedBox(height: 8),
            _TagRibbon(text: tagName),
            if (wish.parentReply != null && wish.parentReply!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  wish.parentReply!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8D6E00)),
                ),
              ),
          ],
          if (hasGoalTarget(target)) ...<Widget>[
            const SizedBox(height: 10),
            WishProgressBar(
              mode: wish.targetMode,
              targetValue: target,
              progressValue: done,
            ),
          ],
          if (pending.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            for (final PendingCheckIn item in pending)
              _PendingWishTaskTile(
                item: item,
                t: t,
                onVerify: onVerify,
                onReject: onReject,
              ),
          ],
          const SizedBox(height: 10),
          // 对外三动作恰好 3 个按钮（A7.3 措辞对照表 / V15）。
          Row(
            key: const Key('parent_wish_actions'),
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('parent_wish_action_setup'),
                  onPressed: onSetup,
                  child: Text(
                    t.parent_wish_action_setup,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  key: const Key('parent_wish_action_fulfill'),
                  onPressed: onFulfill,
                  child: Text(
                    t.parent_wish_action_fulfill,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  key: const Key('parent_wish_action_tag'),
                  onPressed: onTag,
                  child: Text(
                    t.parent_wish_action_tag,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// tagKey 落库用枚举 name（text 列）；脏数据回退 null，不抛错。
  static String? _tagText(String key, AppLocalizations t) {
    for (final WishTag tag in WishTag.values) {
      if (tag.name == key) return wishTagText(tag, t);
    }
    return null;
  }
}

/// 非红色标签缎带（淡琥珀，照孩子端 kWishTagRibbonBg/Fg）。
class _TagRibbon extends StatelessWidget {
  const _TagRibbon({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1C2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8D6E00),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 名下待核销任务行（照 `_PendingCheckInTile` 的交互范式；驳回原因由页面弹层采集）。
class _PendingWishTaskTile extends StatelessWidget {
  const _PendingWishTaskTile({
    required this.item,
    required this.t,
    this.onVerify,
    this.onReject,
  });

  final PendingCheckIn item;
  final AppLocalizations t;
  final void Function(PendingCheckIn item)? onVerify;
  final void Function(PendingCheckIn item)? onReject;

  @override
  Widget build(BuildContext context) {
    final String name = item.task?.name ?? t.parent_today_deleted_task;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('🌟 $name', style: const TextStyle(fontSize: 13))),
          TextButton(
            key: Key('parent_wish_reject_${item.checkIn.id}'),
            onPressed: onReject == null ? null : () => onReject!(item),
            child: Text(t.parent_wish_reject),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: Key('parent_wish_verify_${item.checkIn.id}'),
            onPressed: onVerify == null ? null : () => onVerify!(item),
            child: Text(t.parent_wish_verify),
          ),
        ],
      ),
    );
  }
}
