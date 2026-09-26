/// 奖励卡（M2 T-E，§4.1 商店页可复用展示组件）。
///
/// 纯展示组件：所有异步（冷却查询、submit）由 StorePage 预算好
/// [submitting] / [onRedeem] 后传入，卡内不做任何异步。
///
/// [weeklyLimit] 为该模板「每周可兑换次数」上限（来自 RewardTemplate.frequencyLimitPerWeek）；
/// [weeklyUsed] 为本周已领次数（来自 cooldownCount）。卡片展示「剩余次数」= limit - used：
///   · limit<=0              → 「不限次数」；
///   · remaining>=2          → 「可兑换次数为 N」；
///   · remaining==1          → 「仅可兑换 1 次」；
///   · remaining==0（领完）  → 隐藏（由卡片禁用态 / 「本周已领」承载）。
/// 注意：冷却放行逻辑在 StorePage / RedemptionOrchestrationService 侧，本卡只负责展示文案。
library reward_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

class RewardCard extends StatelessWidget {
  final RewardTemplate template;
  final int costForTier;
  final int weeklyLimit; // 该模板每周可兑换次数上限（frequencyLimitPerWeek；<=0 不限）
  final int weeklyUsed; // 本周已领次数（cooldownCount）；卡片展示 = limit - used 的剩余次数
  final bool submitting;
  final VoidCallback? onRedeem;

  const RewardCard({
    super.key,
    required this.template,
    required this.costForTier,
    this.weeklyLimit = 0,
    this.weeklyUsed = 0,
    this.submitting = false,
    this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // 每周可兑换次数提示：按「剩余次数」（limit - used）动态渲染，领完则隐藏。
    final Widget? weeklyHint = _weeklyLimitHint(theme);

    // 每行条目左侧彩色圆角图标块（马卡龙色底 + emoji 占位图标），按模板稳定轮换。
    final Color iconBg = macaronColorById(template.id).bg;

    // 暖色儿童风：纯白大圆角卡 + 极柔和阴影；左侧彩色图标块 + 胶囊价格标签。
    return Container(
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 左侧彩色圆角图标块（马卡龙色底 + 深字色图标）。
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(template.contentCategory.icon,
                      style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      template.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 底部行：价格胶囊 + 每周可兑换次数提示（收进行内，Flexible 包裹防溢出）+ 兑换按钮。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 价格胶囊标签（暖黄底深字）。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1C2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$costForTier 阳光',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8D6E00),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 每周可兑换次数提示（领完即 null → 隐藏）；Flexible 包裹避免窄屏溢出。
              if (weeklyHint != null) Flexible(child: weeklyHint),
              const Spacer(),
              // 明显的「兑换」按钮：主色填充、圆角、加宽，带 ⚡ 图标。
              // 保持 ElevatedButton + 文案「兑换」不变（既有测试按类型/文案断言可点性）。
              ElevatedButton.icon(
                onPressed: submitting ? null : onRedeem,
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
    );
  }

  /// 每周可兑换次数提示文案部件（按「剩余次数」动态渲染）。
  ///
  /// 口径（与用户原话一致）：limit<=0「不限次数」；remaining>=2「可兑换次数为 N」；
  /// remaining==1「仅可兑换 1 次」；remaining==0（领完）→ 返回 null 隐藏，
  /// 由卡片禁用态 / 「本周已领」承载，避免重复。
  Widget? _weeklyLimitHint(ThemeData theme) {
    final String? text = weeklyRedeemLabel(weeklyLimit, weeklyUsed);
    if (text == null) return null;
    return Row(
      children: <Widget>[
        Icon(Icons.repeat, size: 14, color: Colors.blueGrey.shade400),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.blueGrey.shade600),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
