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
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

/// 奖励分类中文标签（单点展示用；不发明新常量）。
String categoryLabel(RewardCategory category) {
  switch (category) {
    case RewardCategory.selfService:
      return '自服务';
    case RewardCategory.parentHandled:
      return '家长经手';
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
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认核销？'),
        content: Text(
          '确认为「${widget.template.name}」核销 ${widget.request.cost} 阳光？\n'
          '核销后将立即从孩子阳光中扣除，且不可撤销。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认核销'),
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
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认拒绝？'),
        content: Text(
          '拒绝「${widget.template.name}」(${widget.request.cost} 阳光）将不核销，'
          '阳光原路返回孩子（不扣除）。\n此操作不可撤销。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认拒绝'),
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
        const SnackBar(content: Text('已确认兑换 🎉 阳光已扣除')),
      );
      widget.onResolved?.call(); // 触发父列表刷新（卡消失）
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('核销失败：$e')),
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
        const SnackBar(content: Text('已拒绝核销，阳光已原路返回 🌞')),
      );
      widget.onResolved?.call(); // 触发父列表刷新（卡消失）
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拒绝失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final RedemptionRequest req = widget.request;
    final RewardTemplate tpl = widget.template;
    final bool isQueued = req.status == RequestStatus.queued;
    final bool isPending = req.status == RequestStatus.pending;
    final bool overdue = DateTime.now().difference(req.requestedAt) >
        const Duration(hours: kPendingReminderHours);
    final String requestedText =
        DateFormat('yyyy-MM-dd HH:mm').format(req.requestedAt);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
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
                    '${req.cost} 阳光',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '分类：${categoryLabel(tpl.category)} · 申请于 $requestedText',
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
                  '排队第 ${req.queuePosition ?? '?'} 位 · 下月自动释放',
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
                  kPendingReminderText,
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isPending && !_busy ? _confirmAndVerify : null,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isQueued ? '下月自动释放' : '确认兑换'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: !_busy ? _confirmAndReject : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                child: const Text('拒绝'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
