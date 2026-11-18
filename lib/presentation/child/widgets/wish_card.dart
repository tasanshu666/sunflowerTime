/// 树上愿望卡（A-T04 / A22.1 / A24.7）——「树上」段单条卡片。
///
/// ## 纪律
///  - 纯展示 widget：不读 provider、不写状态机。判据（果实阶段 / 过期提醒 /
///    进度）全部复用领域层纯函数与 [WishProgressBar]，本文件只排版 + 取 ARB 文案。
///  - 文案经 [t]（调用方在页级 `L10nScope` 内取好）传入，故可直接放进任意测试宿主。
///  - [animate] 开关仅为 API 一致（本卡无循环动画），关掉不改变内容。
///
/// 关键判据导出为顶层纯函数（[wishCategoryEmoji] / [wishDisplayDate] /
/// [wishFruitStageLabel]），测试可直接调用、不依赖 pump。
library wish_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 卡片圆角（与 [creamCardDecoration] 一致）。
const double kWishCardRadius = 22;

/// 标签缎带底色 / 字色 —— **非红色**（A24.7 ⑨：不用警示红）。
const Color kWishTagRibbonBg = Color(0xFFFFF1C2);
const Color kWishTagRibbonFg = Color(0xFF8D6E00);

/// 愿望分类图标（emoji 是符号不走 ARB；switch 穷尽 6 类）。
String wishCategoryEmoji(WishCategory category) => switch (category) {
      WishCategory.other => '🌱',
      WishCategory.gift => '🎁',
      WishCategory.experience => '🎈',
      WishCategory.toy => '🧸',
      WishCategory.growth => '🌟',
      WishCategory.companionship => '💛',
    };

/// 稳定日期文案（`yyyy-MM-dd`，复用 [dayKey] 单点，避免第二套格式）。
String wishDisplayDate(DateTime date) => dayKey(date);

/// 果实阶段文案（4 态穷尽）。`ripe` 理论上不出现在树上（成真即出池），
/// 仅为 switch 穷尽保留，取「我自己做到的」徽标文案作兜底。
String wishFruitStageLabel(WishFruitStage stage, AppLocalizations t) =>
    switch (stage) {
      WishFruitStage.none => t.wishNoTargetYet,
      WishFruitStage.waiting => t.wishFruitWaiting,
      WishFruitStage.growing => t.wishFruitGrowing,
      WishFruitStage.ripe => t.wishSelfFulfilledBadge,
    };

/// 果实阶段图标（emoji 符号，各语言一致）。
String wishFruitEmoji(WishFruitStage stage) => switch (stage) {
      WishFruitStage.none => '⏳',
      WishFruitStage.waiting => '🌰',
      WishFruitStage.growing => '🌱',
      WishFruitStage.ripe => '🏆',
    };

/// 树上单条愿望卡。
class WishCard extends StatelessWidget {
  const WishCard({
    super.key,
    required this.wish,
    required this.t,
    required this.taskCount,
    required this.waitDays,
    this.milestoneCount = 0,
    this.onTap,
    this.animate = false,
    this.highlight = false,
  });

  final Wish wish;
  final AppLocalizations t;

  /// 归属任务条数（读侧派生，不落愿望列）。
  final int taskCount;

  /// 已等待天数（由页级用 `WishOrchestrationService.waitingDays` 算好）。
  final int waitDays;

  /// 已盖章数（达成池里程碑；树上只读展示）。
  final int milestoneCount;

  final VoidCallback? onTap;

  /// API 一致开关；本卡无循环动画，`false` 与 `true` 内容一致。
  final bool animate;

  /// 「历史今日 · 看看它」跳转高亮（纯视觉描边，A36.3）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final WishFruitStage stage = fruitStageOf(
      targetValue: wish.targetValue,
      progressValue: wish.progressValue,
    );
    final bool stale = waitDays >= kWishPendingAgeWarnDays;
    return InkWell(
      key: Key('wish_card_${wish.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(kWishCardRadius),
      child: Container(
        decoration: highlight
            ? creamCardDecoration().copyWith(
                border: Border.all(color: const Color(0xFFE8A600), width: 2),
              )
            : creamCardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
                    key: const Key('wish_card_text'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  wishFruitEmoji(stage),
                  style: const TextStyle(fontSize: 22),
                ),
              ],
            ),
            if (wish.isTagged) ...<Widget>[
              const SizedBox(height: 8),
              _tagRibbon(),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  t.wishTreeWaitDays(waitDays),
                  key: const Key('wish_card_wait_days'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A66),
                  ),
                ),
                if (stale) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    t.wishTreeStaleHint,
                    key: const Key('wish_card_stale'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB26A00),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  t.wishTreeTaskBadge(taskCount),
                  key: const Key('wish_card_task_badge'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A66),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              wishFruitStageLabel(stage, t),
              key: const Key('wish_card_fruit_stage'),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B4E12),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            WishProgressBar(
              mode: wish.targetMode,
              targetValue: wish.targetValue,
              progressValue: wish.progressValue,
              animate: animate,
            ),
            if (milestoneCount > 0) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  t.wishTreeMilestone(milestoneCount),
                  key: const Key('wish_card_milestone'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8D6E00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 非红色缎带 + 回信全文（空态走占位，默认展开）。
  Widget _tagRibbon() => Container(
        key: const Key('wish_card_tag_ribbon'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kWishTagRibbonBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '🎗 ${t.wishTreeTagRibbon}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kWishTagRibbonFg,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              wish.parentReply ?? t.wishTreeReplyEmpty,
              key: const Key('wish_card_reply'),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF5D4200),
              ),
            ),
          ],
        ),
      );
}
