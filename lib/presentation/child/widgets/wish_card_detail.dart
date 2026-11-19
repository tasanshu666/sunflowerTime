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
/// ## v0.3.0 三态（R3-P0-05 / D5）
/// 判据唯一来自 [WishCardDetail.face]（领域纯函数 `wishTreeFaceOf` 的结果）：
///  - S1：只显原文 + 日期 + 等待天数 + **不可点击**轻提示，**不显**果实阶段 / 进度条；
///  - S2：显家长回信（空则兜底句），**不显**果实阶段 / 进度条；
///  - S3：显 S3 标题 + 「小办法 n 个」+ 果实阶段 + 进度条。
///
/// 🔴 分类 emoji 已删除（R3-P0-03③）；v0.2 的 `shareAction` 插槽已删除。
///
/// 纯展示 widget：不读 provider；判据（果实态 / 目标闸门）复用领域层纯函数；
/// 文案经 [t] 参数（调用方在页级 scope 内取好）传入，可直接挂任意测试宿主。
library wish_card_detail;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
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
    this.face = WishTreeFace.hanging,
    this.canSelfFulfill = false,
    this.onCollectToBox,
    this.onChangeWish,
    this.onSelfFulfill,
  });

  final Wish wish;
  final AppLocalizations t;
  final int waitDays;
  final int taskCount;

  /// 三态（唯一判据 `wishTreeFaceOf` 的结果，由页级算出后下发）。
  final WishTreeFace face;

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
          Text(
            wish.text,
            key: const Key('wish_detail_text'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
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
          // ── 三态主体（S3 才显示果实阶段 / 进度条；S1 只显轻提示） ──────────
          ..._faceBody(stage),
          const SizedBox(height: 14),
          // ── 背面：S2/S3 显示回信区（S1 不显示，避免「还没回信」的催促感） ────
          if (face != WishTreeFace.hanging) _backSide(),
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

  /// 三态主体（S1 轻提示 / S2 回信 / S3 标题 + 果实阶段 + 进度）。
  ///
  /// ⚠️ 回信区（[_backSide]）由调用方按「非 S1」条件单独装配，避免 S1 出现
  /// 「爸爸妈妈还没回信」这种变相催促。
  List<Widget> _faceBody(WishFruitStage stage) {
    switch (face) {
      case WishTreeFace.hanging:
        // S1：一条**不可点击**的轻提示（无 InkWell / GestureDetector / onTap）。
        if (waitDays >= kWishStateHintDays) return const <Widget>[];
        return <Widget>[
          const SizedBox(height: 10),
          Text(
            t.wishStateHangingHint,
            key: const Key('wish_detail_hanging_hint'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
          ),
        ];
      case WishTreeFace.parentResponded:
        // S2：兜底句（有回信时回信在 [_backSide] 显示）；**不显**果实阶段与进度条。
        final String? reply = wish.parentReply;
        if (reply != null && reply.isNotEmpty) return const <Widget>[];
        return <Widget>[
          const SizedBox(height: 10),
          Text(
            t.wishStateParentWorking,
            key: const Key('wish_detail_parent_working'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
          ),
        ];
      case WishTreeFace.hasWays:
        // S3：标题 + 小办法计数 + 果实阶段 + 进度条。
        return <Widget>[
          const SizedBox(height: 10),
          Text(
            t.wishWayTitle,
            key: const Key('wish_detail_way_title'),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B4E12),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.wishWayCountBadge(taskCount),
            key: const Key('wish_detail_way_count'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A66)),
          ),
          const SizedBox(height: 8),
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
        ];
    }
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
