/// 收藏箱单条卡片（A-T04 / Q35-A / A24.7）——收藏箱段的**回忆条目**。
///
/// 五要素（规格 A24.7 收藏箱段）：原文 / 🔴 **许愿日期**（Q35-A 补）/ 进度（保留）/
/// 标签 / 「取回」按钮。按 [wishDisplayDate] 单点格式化日期，测试可直接调用。
///
/// - 取回按钮 [onRestore] 由页面接线：**额度满时仍可点**（灰态可点 ⇒ 弹引导，
///   C69「先过额度校验、被拒不删数据」）——本 widget 不自行判额度、不写库。
/// - 纯展示 widget，文案经 [t] 传入；判据（果实态 / 进度）复用领域层纯函数。
library wish_collection_tile;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 收藏箱单条。
class WishCollectionTile extends StatelessWidget {
  const WishCollectionTile({
    super.key,
    required this.wish,
    required this.t,
    this.onRestore,
    this.highlight = false,
  });

  final Wish wish;
  final AppLocalizations t;

  /// 「取回」按钮回调（由页面判额度：满则弹引导、不删数据）。
  final VoidCallback? onRestore;

  /// 「历史今日 · 看看它」跳转高亮（纯视觉描边，A36.3）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('wish_collection_tile_${wish.id}'),
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                wishCategoryEmoji(wish.category),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  wish.text,
                  key: Key('wish_collection_text_${wish.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (wish.isTagged)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '🎗 ${t.wishTreeTagRibbon}',
                style: const TextStyle(
                  fontSize: 12,
                  color: kWishTagRibbonFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            t.wishTreeWishDate(wishDisplayDate(wish.createdAt)),
            key: Key('wish_collection_date_${wish.id}'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A66)),
          ),
          const SizedBox(height: 8),
          WishProgressBar(
            mode: wish.targetMode,
            targetValue: wish.targetValue,
            progressValue: wish.progressValue,
            showLabel: true,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: Key('wish_collection_restore_${wish.id}'),
              onPressed: onRestore,
              child: Text(t.wishRestoreFromBox),
            ),
          ),
        ],
      ),
    );
  }
}
