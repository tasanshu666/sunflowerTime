/// 奖励卡（M2 T-E，§4.1 商店页可复用展示组件）。
///
/// 纯展示组件：所有异步（冷却查询、submit）由 StorePage 预算好
/// [onCooldown] / [submitting] 后传入，卡内不做任何异步。
library reward_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';

class RewardCard extends StatelessWidget {
  final RewardTemplate template;
  final int costForTier;
  final bool onCooldown;
  final bool hasActiveRequest; // 已有未核销申请（待家长核销）
  final int pendingCount; // 该模板待核销笔数（>=2 时显示 +N）
  final bool submitting;
  final VoidCallback? onRedeem;

  const RewardCard({
    super.key,
    required this.template,
    required this.costForTier,
    this.onCooldown = false,
    this.hasActiveRequest = false,
    this.pendingCount = 0,
    this.submitting = false,
    this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool disabled = onCooldown || hasActiveRequest;

    // 卡片内联提示：已有待核销申请时展示「待家长核销 / 代家长核销 +N」。
    final String? inlineHint = hasActiveRequest
        ? (pendingCount > 1 ? '代家长核销 +$pendingCount' : '待家长核销')
        : (onCooldown ? '本周已领' : null);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    template.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                // 「需家长端核销」仅作提示文字：低调灰字 + 小 ⓘ 图标，明确不可点。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      template.category == RewardCategory.selfService
                          ? '自服务'
                          : '需家长端核销',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 2),
                    Tooltip(
                      message: template.category == RewardCategory.selfService
                          ? '孩子能自己完成（如多看一集），但为防滥用，兑换后仍要家长在「今日」里确认放行，确认后才扣阳光。'
                          : '这类奖励需家长在现实里兑现（如买零食、安排出游）。孩子兑换后会进入你的「今日」Tab，由你点「确认兑换」核实后才会扣阳光。',
                      child: Icon(Icons.info_outline,
                          size: 14, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
            if (inlineHint != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  inlineHint,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$costForTier 阳光',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 明显的「兑换」按钮：主色填充、圆角、加宽，带 ⚡ 图标。
                ElevatedButton.icon(
                  onPressed: disabled || submitting ? null : onRedeem,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 16),
                  label: const Text('兑换'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
