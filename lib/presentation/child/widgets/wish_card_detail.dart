/// 愿望卡详情页（A-T04 / A24.7 / A22.1）——树上点卡片后的**背面**。
///
/// ## 正面 / 背面（测试断言 ⑤ / ⑩）
///  - 正面：原文 / 许愿日期 / 等待天数 / 进度条；
///  - 背面：家长回信区 **空态也展示占位文案**（不隐藏整块）、有标签时**非红色缎带**；
///  - 底部两个次级按钮「换一个愿望」「放进愿望收藏箱」（A24.7 ⑨）；
///  - 主按钮「我做到了」（愿望级，与任务级不同）：
///    🔴 入口闸门 = `hasGoalTarget(targetValue)` 且 `releasedAt == null`；
///    不满足时**不渲染**（由调用方经 [canSelfFulfill] 传入），点击**先弹二次确认**，
///    取消不落库（[onSelfFulfill] 只在确认后触发）。
///
/// 纯展示 widget：不读 provider；判据（果实态 / 目标闸门）复用领域层纯函数；
/// 文案经 [t] 参数（调用方在页级 scope 内取好）传入，可直接挂任意测试宿主。
library wish_card_detail;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 愿望卡详情页。
class WishCardDetail extends StatelessWidget {
  const WishCardDetail({
    super.key,
    required this.wish,
    required this.t,
    required this.waitDays,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.confirmLabel,
    required this.cancelLabel,
    this.taskCount = 0,
    this.canSelfFulfill = false,
    this.onCollectToBox,
    this.onChangeWish,
    this.onSelfFulfill,
  });

  final Wish wish;
  final AppLocalizations t;
  final int waitDays;
  final int taskCount;

  /// 「我做到了」入口闸门结果，由调用方按
  /// `hasGoalTarget(targetValue) && releasedAt == null && !isTerminal` 算好。
  final bool canSelfFulfill;

  /// 二次确认卡文案（页面 scope 内取好传入）。
  final String confirmTitle;
  final String confirmMessage;
  final String confirmLabel;
  final String cancelLabel;

  final VoidCallback? onCollectToBox;
  final VoidCallback? onChangeWish;
  final VoidCallback? onSelfFulfill;

  @override
  Widget build(BuildContext context) {
    final WishFruitStage stage = fruitStageOf(
      targetValue: wish.targetValue,
      progressValue: wish.progressValue,
    );
    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ── 正面 ──────────────────────────────────────────────────────────
          Row(
            children: <Widget>[
              Text(
                wishCategoryEmoji(wish.category),
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  wish.text,
                  key: const Key('wish_detail_text'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.wishTreeWishDate(wishDisplayDate(wish.createdAt)),
            key: const Key('wish_detail_wish_date'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
          ),
          const SizedBox(height: 4),
          Text(
            t.wishTreeWaitDays(waitDays),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
          ),
          const SizedBox(height: 10),
          Text(
            wishFruitStageLabel(stage, t),
            key: const Key('wish_detail_fruit_stage'),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B4E12),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          WishProgressBar(
            mode: wish.targetMode,
            targetValue: wish.targetValue,
            progressValue: wish.progressValue,
          ),
          if (taskCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              t.wishTreeTaskBadge(taskCount),
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A66)),
            ),
          ],
          // ── 背面：标签缎带（非红）+ 回信全文（空态占位，不隐藏） ────────────
          const SizedBox(height: 14),
          _backSide(),
          const SizedBox(height: 16),
          // ── 主按钮「我做到了」（愿望级，闸门不满足不渲染） ──────────────────
          if (canSelfFulfill)
            FilledButton.icon(
              key: const Key('wish_detail_self_fulfill'),
              onPressed: onSelfFulfill == null
                  ? null
                  : () => _confirmThen(context, onSelfFulfill!),
              icon: const Icon(Icons.emoji_events_outlined),
              label: Text(t.wishSelfFulfill),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (canSelfFulfill) const SizedBox(height: 10),
          // ── 两个次级按钮 ────────────────────────────────────────────────────
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('wish_detail_change'),
                  onPressed: onChangeWish,
                  child: Text(t.wishTreeChangeWish),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('wish_detail_collect'),
                  onPressed: onCollectToBox,
                  child: Text(t.wishCollectToBox),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 背面区：有标签 → 非红色缎带 + 回信全文；无标签 → 回信占位（仍展示）。
  Widget _backSide() => Container(
        key: const Key('wish_detail_back'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: wish.isTagged ? kWishTagRibbonBg : const Color(0xFFF6F1E6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (wish.isTagged)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '🎗 ${t.wishTreeTagRibbon}',
                  key: const Key('wish_detail_tag_ribbon'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kWishTagRibbonFg,
                  ),
                ),
              ),
            Text(
              wish.parentReply ?? t.wishTreeReplyEmpty,
              key: const Key('wish_detail_reply'),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF5D4200),
              ),
            ),
          ],
        ),
      );

  /// 误触保护：先弹确认卡，`ok != true` 绝不落库。
  Future<void> _confirmThen(BuildContext context, VoidCallback action) async {
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: confirmTitle,
      message: confirmMessage,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
    if (ok != true) return;
    if (!context.mounted) return;
    action();
  }
}
