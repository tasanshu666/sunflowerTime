/// 核销卡（§3.1 / §4.3 / §5 T-F）：家长端「今日」tab 中每条待处理申请的呈现与处理入口。
///
/// 交互纪律（§4.3）：核销 ≤ 2 步——看到卡 → 点「确认兑换」→ **弹窗二次确认** →
/// 调 `RedemptionOrchestrationService.verify(requestId, now)`。成功后出现正向反馈并
/// 由父列表刷新使卡消失。
///
/// 家长可**拒绝**（某些奖励无法在现实中兑现）：点「拒绝」→ **弹窗二次确认** →
/// 调 `reject(requestId, now)`，状态置 rejected，阳光原路返回（pending/queued 从未扣账本，
/// 故无需回写 ledger）。
///
/// queued 请求：只能次月 `releaseQueue` 释放，不能手动核销 —— 禁用「确认兑换」按钮并显示
/// 「下月自动释放」，但仍可「拒绝」（不释放）。
///
/// 48h 兜底（D5）：`now - requestedAt > kPendingReminderHours` 时展示 kPendingReminderText。
library verification_card;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 奖励分类展示标签（单点展示用；不发明新常量；i18n B2：文案经 [AppLocalizations]）。
String categoryLabel(RewardCategory category, AppLocalizations t) {
  switch (category) {
    case RewardCategory.selfService:
      return t.parent_verify_cat_self_service;
    case RewardCategory.parentHandled:
      return t.parent_verify_cat_parent_handled;
  }
}

/// 核销卡：渲染单条待处理/排队申请，并提供「确认兑换 / 拒绝」两个处理入口。
class VerificationCard extends ConsumerStatefulWidget {
  final RedemptionRequest request;
  final RewardTemplate template;

  /// 处理后（核销或拒绝）的回调（由父列表用于刷新，使该卡消失）。
  final VoidCallback? onResolved;

  const VerificationCard({
    super.key,
    required this.request,
    required this.template,
    this.onResolved,
  });

  @override
  ConsumerState<VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<VerificationCard> {
  bool _busy = false;

  /// 点「确认兑换」后先弹窗二次确认，避免误触直接扣阳光（家长端防错）。
  Future<void> _confirmAndVerify() async {
    if (_busy || widget.request.status != RequestStatus.pending) return;
    // 弹窗纪律：文案在页级 scope 内（State 上下文）取好再传入 builder。
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_verify_confirm_title),
        content: Text(t.parent_verify_confirm_body(
          widget.template.name,
          widget.request.cost,
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_verify_confirm_ok),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _verify();
  }

  /// 点「拒绝」后先弹窗二次确认：拒绝 = 不核销、阳光原路返回（不扣）。
  Future<void> _confirmAndReject() async {
    if (_busy) return;
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_verify_reject_title),
        content: Text(t.parent_verify_reject_body(
          widget.template.name,
          widget.request.cost,
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_verify_reject_ok),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _reject();
  }

  /// 核销一笔 pending 请求（§4.3）。
  Future<void> _verify() async {
    if (_busy || widget.request.status != RequestStatus.pending) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(redemptionOrchestrationServiceProvider)
          .verify(widget.request.id, DateTime.now());
      if (!mounted) return;
      // 正向反馈：由祖先 ScaffoldMessenger 承接，卡消失后仍可见。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10nOf(context).parent_verify_verified_snack)),
      );
      // 同步孩子端：递增经济修订号 → 孩子端商店重算（待核销数↓、卡片解除禁用、余额↓）。
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call(); // 触发父列表刷新（卡消失）
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).parent_verify_verify_fail_snack(e))),
      );
    }
  }

  /// 拒绝一笔待处理请求（§4.3 家长拒绝）：不核销、阳光原路返回。
  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(redemptionOrchestrationServiceProvider)
          .reject(widget.request.id, DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).parent_verify_rejected_snack)),
      );
      // 同步孩子端：递增经济修订号 → 孩子端商店重算（待核销数↓、卡片解除「待家长核销」禁用态）。
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call(); // 触发父列表刷新（卡消失）
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).parent_verify_reject_fail_snack(e))),
      );
    }
  }

  /// 家长强制立即释放一笔排队请求（A3）：跳过等次月，余额/月池充足时立即放行。
  Future<void> _forceRelease() async {
    if (_busy || widget.request.status != RequestStatus.queued) return;
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_verify_release_title),
        content: Text(t.parent_verify_release_body(
          widget.template.name,
          widget.request.cost,
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_verify_release_ok),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(redemptionOrchestrationServiceProvider)
          .forceRelease(widget.request.id, DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).parent_verify_released_snack)),
      );
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call();
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(l10nOf(context).parent_verify_release_state_fail_snack(e))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10nOf(context).parent_verify_release_fail_snack(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final RedemptionRequest req = widget.request;
    final RewardTemplate tpl = widget.template;
    final bool isQueued = req.status == RequestStatus.queued;
    final bool isPending = req.status == RequestStatus.pending;
    final bool overdue = DateTime.now().difference(req.requestedAt) >
        const Duration(hours: kPendingReminderHours);
    final String requestedText =
        DateFormat('yyyy-MM-dd HH:mm').format(req.requestedAt);

    return Container(
      decoration: creamCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    tpl.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t.parent_verify_cost(req.cost),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.parent_verify_meta(categoryLabel(tpl.category, t), requestedText),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (isQueued) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t.parent_verify_queue_note(req.queuePosition ?? '?'),
                  style: TextStyle(color: Colors.blue.shade800),
                ),
              ),
            ] else if (isPending && overdue) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  // 48h 兜底提醒（D5）：文案单点走 ARB（zh 值与原 core 常量逐字一致）。
                  t.prd_pending_reminder,
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            // 左右并排：拒绝（次级/破坏性，左）+ 确认兑换（主操作，右），中间留 12 间距。
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: !_busy ? _confirmAndReject : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    child: Text(t.parent_today_btn_reject),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isPending
                        ? _confirmAndVerify
                        : (isQueued && !_busy ? _forceRelease : null),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isQueued
                            ? t.parent_verify_release_ok
                            : t.parent_verify_confirm_ok),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
