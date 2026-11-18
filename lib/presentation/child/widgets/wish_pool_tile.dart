/// 达成所愿池条目（A-T04 / A22.1 / A24.7）。
///
/// - 每条显示「**许愿日期 → 实现日期**」两段时间（`wishTreePoolDateRange`）；
/// - 「我自己做到的」徽标：判据 = `fulfillSource == kWishFulfillSourceChild`（单一来源常量），
///   用于区分「自己实现」与家长直接实现 / 进度达成（A24.7 ⑧ / V12）；
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
              const Text('🏆', style: TextStyle(fontSize: 22)),
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
              if (isSelfFulfilled(wish))
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    '🌟',
                    key: Key('wish_pool_self_badge'),
                    style: TextStyle(fontSize: 18),
                  ),
                ),
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
}
