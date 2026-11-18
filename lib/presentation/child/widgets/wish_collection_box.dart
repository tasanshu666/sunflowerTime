/// 愿望收藏箱区块（A-T04 / Q35-A / A24.7 / A19.4）。
///
/// - **排序 = `createdAt` 倒序**（Q35-A 定稿：越晚收进来的越靠前，"用来回忆"）。
///   🔴 与树上（`treeSlot` 升序）/ 达成池（`fulfilledAt` 倒序）两段口径**互不干扰**；
///   仓储 `boxed()` 已按 `createdAt` 倒序返回，本 widget **只读展示、不再重排**。
/// - 每条显示「许愿日期」（[WishCollectionTile]），空段显示 `wishTreeEmptyBox`。
/// - 标题角标 = 收藏条数（与三段 tab 上的角标同源，由调用方传入同一计数）。
///
/// 纯展示 widget，不读 provider、不写数据；文案经 [t] 参数传入。
library wish_collection_box;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_collection_tile.dart';

/// 收藏箱区块。
class WishCollectionBox extends StatelessWidget {
  const WishCollectionBox({
    super.key,
    required this.wishes,
    required this.t,
    this.onRestore,
    this.highlightWishId,
  });

  /// 收藏箱条目（入参顺序即展示顺序，仓储已按 `createdAt` 倒序）。
  final List<Wish> wishes;
  final AppLocalizations t;

  /// 单条「取回」回调（页面判额度、弹引导、落库）。
  final ValueChanged<Wish>? onRestore;

  /// 「看看它」跳转高亮的愿望 id（A36.3，纯视觉）。
  final String? highlightWishId;

  @override
  Widget build(BuildContext context) {
    if (wishes.isEmpty) {
      return Padding(
        key: const Key('wish_collection_empty'),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            t.wishTreeEmptyBox,
            style: const TextStyle(fontSize: 15, color: Color(0xFF8A7A66)),
          ),
        ),
      );
    }
    return Column(
      key: const Key('wish_collection_box'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final Wish wish in wishes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WishCollectionTile(
              wish: wish,
              t: t,
              highlight: highlightWishId == wish.id,
              onRestore: onRestore == null ? null : () => onRestore!(wish),
            ),
          ),
      ],
    );
  }
}
