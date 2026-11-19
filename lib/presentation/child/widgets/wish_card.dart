/// 树上愿望卡（A-T04 / A22.1 / A24.7 + **v0.3.0 三态渲染**）——「树上」段单条卡片。
///
/// ## 三态（v0.3.0 / R3-P0-05 / D5）—— 判据**不在本文件**
/// 卡片只读调用方传入的 [face]（由领域纯函数 `wishTreeFaceOf` 单出口算出）；
/// 本文件**禁止**再散写 `tagKey == null && parentReply == null` 这类条件。
///
/// | 态 | 渲染 |
/// |---|---|
/// | [WishTreeFace.hanging] S1 | 原文 + 许愿日期 + 等待天数 + **不可点击**轻提示 |
/// | [WishTreeFace.parentResponded] S2 | 原文 + 家长回信（空则兜底句）；**无**徽标 / 果实阶段 / 进度条 |
/// | [WishTreeFace.hasWays] S3 | 原文 + 「小办法 {n} 个」徽标 + 单句成长引导 + 进度条 |
///
/// ## 纪律
///  - 纯展示 widget：不读 provider、不写状态机。
///  - 文案经 [t]（调用方在页级 `L10nScope` 内取好）传入，故可直接放进任意测试宿主。
///  - 🔴 **分类 emoji 已删除**（R3-P0-03③）：v0.3.0 起愿望无分类输入，
///    历史数据的 `category` 列仍在，但界面不再渲染 emoji。
///  - 🔴 孩子端一律叫「**小办法**」，不出现「任务」二字（D2）。
library wish_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 卡片圆角（与 [creamCardDecoration] 一致）。
const double kWishCardRadius = 22;

/// 标签缎带底色 / 字色 —— **非红色**（A24.7 ⑨：不用警示红）。
const Color kWishTagRibbonBg = Color(0xFFFFF1C2);
const Color kWishTagRibbonFg = Color(0xFF8D6E00);

/// 稳定日期文案（`yyyy-MM-dd`，复用 [dayKey] 单点，避免第二套格式）。
String wishDisplayDate(DateTime date) => dayKey(date);

/// 果实阶段文案（4 态穷尽）。`ripe` 理论上不出现在树上（成真即出池），
/// 仅为 switch 穷尽保留，取「我自己做到的」徽标文案作兜底。
///
/// ⚠️ v0.3.0：S1 / S2 **不再渲染**本文案（R3-P0-05②③ 明确不显示
/// 「等爸爸妈妈设定目标」）；仅 S3 的进度区使用。
String wishFruitStageLabel(WishFruitStage stage, AppLocalizations t) =>
    switch (stage) {
      WishFruitStage.none => t.wishNoTargetYet,
      WishFruitStage.waiting => t.wishFruitWaiting,
      WishFruitStage.growing => t.wishFruitGrowing,
      WishFruitStage.ripe => t.wishSelfFulfilledBadge,
    };

/// 果实阶段图标（emoji 符号，各语言一致）。仅 S3 使用。
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
    this.face = WishTreeFace.hanging,
    this.milestoneCount = 0,
    this.onTap,
    this.animate = false,
    this.highlight = false,
  });

  final Wish wish;
  final AppLocalizations t;

  /// 关联「小办法」条数（读侧派生，不落愿望列）。
  final int taskCount;

  /// 已等待天数（由页级用 `WishOrchestrationService.waitingDays` 算好）。
  final int waitDays;

  /// 三态（唯一判据 `wishTreeFaceOf` 的返回值，由页级算出后下发）。
  final WishTreeFace face;

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
                // 果实 emoji 只在 S3（家长已布置小办法）出现；S1/S2 不显示。
                if (face == WishTreeFace.hasWays) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    wishFruitEmoji(stage),
                    style: const TextStyle(fontSize: 22),
                  ),
                ],
              ],
            ),
            // 许愿日期 + 等待天数（三态共有）。
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  wishDisplayDate(wish.createdAt),
                  key: const Key('wish_card_created_date'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A66),
                  ),
                ),
                const SizedBox(width: 8),
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
                // 「小办法 n 个」徽标只在 S3 出现（S1/S2 明确不显示）。
                if (face == WishTreeFace.hasWays)
                  Text(
                    t.wishWayCountBadge(taskCount),
                    key: const Key('wish_card_task_badge'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A7A66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            ..._faceBody(stage),
          ],
        ),
      ),
    );
  }

  /// 按三态追加主体（S1 轻提示 / S2 回信 / S3 单句成长引导 + 进度）。
  List<Widget> _faceBody(WishFruitStage stage) {
    switch (face) {
      case WishTreeFace.hanging:
        // S1：一条**不可点击**的轻提示（12~13sp 灰）。不带 InkWell / GestureDetector，
        // 也没有 onTap（R3-P0-07⑤ 断言该提示不可点击）。
        // P2-01：挂树满 [kWishStateHintDays] 天后自动隐藏（不出现替代催促文案）。
        if (waitDays >= kWishStateHintDays) return const <Widget>[];
        return <Widget>[
          const SizedBox(height: 8),
          Text(
            t.wishStateHangingHint,
            key: const Key('wish_card_hanging_hint'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8A7A66),
            ),
          ),
        ];
      case WishTreeFace.parentResponded:
        // S2：家长回信（空则兜底句）；**不显示**徽标 / 果实阶段 / 进度条。
        final String? reply = wish.parentReply;
        return <Widget>[
          const SizedBox(height: 8),
          Container(
            key: const Key('wish_card_parent_reply_box'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kWishTagRibbonBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              (reply != null && reply.isNotEmpty)
                  ? reply
                  : t.wishStateParentWorking,
              key: const Key('wish_card_parent_reply'),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF5D4200),
              ),
            ),
          ),
        ];
      case WishTreeFace.hasWays:
        // S3：v0.4（玄参）将原两行「你的愿望可以通过这些小办法实现哦」+
        // 「等爸爸妈妈设定目标」合并为单句「去成长里面实现你的愿望吧」。
        // 徽标（卡级）、进度条、里程碑均保持不变。
        return <Widget>[
          const SizedBox(height: 8),
          Text(
            t.wishGoGrowthHint,
            key: const Key('wish_card_way_title'),
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
        ];
    }
  }
}
