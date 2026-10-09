/// 奖励卡（M2 T-E，§4.1 商店页可复用展示组件）。
///
/// 纯展示组件：所有异步（冷却查询、submit）由 StorePage 预算好
/// [submitting] / [onRedeem] 后传入，卡内不做任何异步。
///
/// [weeklyLimit] 为该模板「每周可兑换次数」上限（来自 RewardTemplate.frequencyLimitPerWeek）；
/// [weeklyUsed] 为本周已领次数（来自 cooldownCount）。卡片展示「剩余次数」= limit - used：
///   · limit<=0              → 「不限次数」；
///   · remaining>=1          → 「周限 N 次」（N = 剩余可兑换次数）；
///   · remaining==0（领完）  → 隐藏（由卡片禁用态 / 「本周已领」承载）。
/// 注意：冷却放行逻辑在 StorePage / RedemptionOrchestrationService 侧，本卡只负责展示文案。
library reward_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
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
    final Widget? weeklyHint = _weeklyLimitHint();

    // 每行条目左侧彩色圆角图标块（马卡龙色底 + emoji 占位图标），按模板稳定轮换。
    final Color iconBg = macaronColorById(template.id).bg;

    // 暖色儿童风（C45 与今日页卡片语言统一）：暖白渐变 + 淡金描边 + 柔和暖影；
    // 左图标 + 中段文案 + 右价格/兑换。
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Colors.white, Color(0xFFFDF3DD)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x26E8A600)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F8A5A00),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 左侧图标块（C44）：优先美术图标（按奖励名关键词映射，见 growth_icons），
          // 加载失败回退马卡龙色块 + emoji 占位（与成长卡 56 对齐）。
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              // 素材自带圆角卡底（512² 方形），cover 满铺圆角块。
              child: Image.asset(
                rewardIconAssetFor(template),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(template.contentCategory.icon,
                      style: const TextStyle(fontSize: 32)),
                ),
              ),
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
                // 限次提示（领完即 null → 隐藏）；纯文字小字，无图标。
                if (weeklyHint != null) weeklyHint,
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 右侧：价格胶囊 + 兑换按钮（垂直堆叠，mainAxisSize.min 不撑高卡片）。
          Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 8),
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
  /// 口径（玄参已确认）：limit<=0「不限次数」；remaining>=1「周限 N 次」；
  /// remaining==0（领完）→ 返回 null 隐藏，由卡片禁用态 / 「本周已领」承载。
  Widget? _weeklyLimitHint() {
    final String? text = weeklyRedeemLabel(weeklyLimit, weeklyUsed);
    if (text == null) return null;
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
    );
  }
}
