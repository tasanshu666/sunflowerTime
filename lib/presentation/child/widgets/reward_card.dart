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

    // C47（玄参 2026-10-09）：卡片高度与成长页任务卡对齐（≈88pt）——
    // padding 14→12、图标 56→64（与成长页一致）、右列两行收紧
    //（价格胶囊 v6→4 / 兑换按钮压到 32pt 高 / 行距 8→6）。
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
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 左侧图标块：优先美术图标（按奖励名关键词映射，见 growth_icons），
          // 加载失败回退马卡龙色块 + emoji 占位。
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
          // 兑换按钮（C47d，玄参 2026-10-09：「再大一些，可以跟左边的图标大小保持一致」）
          // 定为 **64×64 方正按钮**（= 左侧图标块尺寸），按钮内上下两行：
          // 上排「☀ 图标 + 价格」、下排「兑换」。高度与图标一致 → 卡片总高仍 ≈88pt
          //（与成长页任务卡对齐），只是按钮更饱满好点。
          // 保持 ElevatedButton + 文案「兑换」不变（既有测试按类型/文案断言可点性）。
          SizedBox(
            width: 64,
            height: 64,
            child: ElevatedButton(
              onPressed: submitting ? null : onRedeem,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // 阳光素材图标 + 价格数字（C47：价格文字换阳光 UI 图标）。
                            Image.asset(
                              'assets/rewards/sunlight.png',
                              width: 17,
                              height: 17,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.wb_sunny,
                                  color: Color(0xFFE8A600),
                                  size: 17),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$costForTier',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF8D6E00),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '兑换',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
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
