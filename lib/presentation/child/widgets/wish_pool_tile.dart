/// 达成所愿池条目（A-T04 / A22.1 / A24.7）。
///
/// - 每条显示「**许愿日期 → 实现日期**」两段时间（`wishTreePoolDateRange`）；
/// - **双轨来源标识**（C136 需求 3，玄参 2026-11-25 真机反馈）：
///   `fulfillSource == kWishFulfillSourceChild`（孩子自己点「实现了」）→ 🌟
///   「我自己做到的」；其余来源（`progress` 家长确认任务达成 / `parentAction`
///   家长直接实现 / 历史 `null`）→ 🤝「爸爸妈妈帮我做到的」。两个标识都带
///   Tooltip + Semantics 文案（A24.7 ⑧ / V12）；
/// - 🔴 **不计入里程碑盖章数**（V12：章数只按 status == fulfilled 计）；本条只展示
///   页级算好的 `milestoneCount`。
///
/// 纯展示 widget：不读 provider、不写状态；日期走 [wishDisplayDate] 单点。
/// [highlight] 用于「历史今日 · 看看它」跳转高亮（A36.3，纯视觉描边）。
library wish_pool_tile;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_scene.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 达成池单条。
class WishPoolTile extends StatelessWidget {
  const WishPoolTile({
    super.key,
    required this.wish,
    required this.t,
    this.milestoneCount = 0,
    this.highlight = false,
  });

  final Wish wish;
  final AppLocalizations t;

  /// 里程碑盖章总数（页级从 `stampedAchievedCount` 读好传入，只读展示）。
  final int milestoneCount;

  /// 「看看它」跳转高亮（纯视觉描边，无循环动画）。
  final bool highlight;

  /// 是否「我自己做到的」（判据单点，导出便于测试）。
  static bool isSelfFulfilled(Wish wish) =>
      wish.fulfillSource == kWishFulfillSourceChild;

  /// 是否「爸爸妈妈帮我做到的」——[isSelfFulfilled] 的**互补轨**（C136 需求 3）。
  ///
  /// 玄参 2026-11-25 真机反馈原文：「愿望池里面的愿望，每个卡片右边有个小星星
  /// 是干啥的？想要小飞机那个实现的愿望还没有小星星，这是什么机制？」——
  /// 旧实现只有 `source == child`（孩子自己点「实现了」）才挂 🌟，
  /// `progress`（家长确认任务达成）/ `parentAction`（家长直接实现）什么都不挂，
  /// 于是同一屏里「有的卡有星、有的没有」，孩子以为是随机奖励。
  ///
  /// 现改**双轨**：自己做到 → 🌟（key 不变）；其余来源（含历史数据的
  /// `fulfillSource == null`）→ 🤝 + 语义标签「爸爸妈妈帮我做到的」。
  /// 取互补而非白名单，是为了让**每一张**池卡都有解释 —— 露一个没有标识的卡
  /// 就还是会回到玄参这次问的那个问题。
  static bool isParentHelped(Wish wish) => !isSelfFulfilled(wish);

  @override
  Widget build(BuildContext context) {
    final String wishDate = wishDisplayDate(wish.createdAt);
    final String fulfilledDate = wishDisplayDate(
      wish.fulfilledAt ?? wish.createdAt,
    );
    return Container(
      key: Key('wish_pool_tile_${wish.id}'),
      decoration: highlight
          ? creamCardDecoration().copyWith(
              border: Border.all(color: const Color(0xFFE8A600), width: 2),
            )
          : creamCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 玄参 2026-11-19 美术接入：达成奖杯 emoji → 达成蛋 PNG（缺失回退 emoji）。
              Image.asset(
                WishTreeArt.eggDone,
                width: 34,
                height: 34,
                fit: BoxFit.contain,
                key: const Key('wish_pool_done_egg'),
                errorBuilder: (_, __, ___) => const Text(
                  '🏆',
                  style: TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  wish.text,
                  key: const Key('wish_pool_text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // C136 需求 3（玄参真机反馈）：双轨来源标识，每张池卡都有解释。
              //  · 自己做到 → 🌟（key 保持 `wish_pool_self_badge` 不变）
              //  · 其余来源 → 🤝（新 key `wish_pool_parent_badge`，家长帮忙达成）
              // Tooltip + Semantics label 同时给：家长长按能看懂，读屏也能念出来。
              _sourceBadge(t),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.wishTreePoolDateRange(wishDate, fulfilledDate),
            key: const Key('wish_pool_date_range'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A66)),
          ),
          if (milestoneCount > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              t.wishTreeMilestone(milestoneCount),
              key: const Key('wish_pool_milestone'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8D6E00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 来源标识徽标（C136 需求 3）：🌟「我自己做到的」/ 🤝「爸爸妈妈帮我做到的」。
  ///
  /// 两个标识都带 [Tooltip] 与 [Semantics] label（文案全部走 ARB，zh + en 双份）：
  /// 只挂一个 emoji 时孩子和读屏都读不出含义 —— 这正是玄参这次问「小星星是干啥的」
  /// 的根因。`excludeFromSemantics` 只留在 [Tooltip] 上（label 由外层
  /// [Semantics] 单点给出），避免读屏把同一句念两遍。
  Widget _sourceBadge(AppLocalizations t) {
    // 🔴 判据单点：只经 [isParentHelped]（其内部即 `!isSelfFulfilled`）。
    // 不在这里自写 `isSelfFulfilled(wish) ? … : …` 三元 —— 否则「来源→标识」
    // 的判据会分成 UI 一份、公开纯函数一份（QA C136 M4 变异实证：改
    // `isParentHelped` 时 UI 用例全绿、改了个寂寞）。
    final bool parentHelped = isParentHelped(wish);
    final String label =
        parentHelped ? t.wishParentFulfilledBadge : t.wishSelfFulfilledBadge;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Semantics(
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Text(
            parentHelped ? '🤝' : '🌟',
            key: Key(parentHelped
                ? 'wish_pool_parent_badge'
                : 'wish_pool_self_badge'),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
