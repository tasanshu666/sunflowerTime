/// 愿望卡详情页（A-T04 / A24.7 / A22.1）——树上点卡片后的**背面**。
///
/// ## 正面 / 背面（测试断言 ⑤ / ⑩）
///  - 正文：原文 / 许愿日期 / 进度条；🔴 玄参 iPad13 反馈：详情不再显示
///    「等了 N 天」与回信区（含「暂时做不到」缎带）；
///  - 底部两个次级按钮「换个愿望」「放进收藏箱」（A24.7 ⑨，短文案）；
///  - 主按钮「实现了」（愿望级，与任务级不同）：
///    玄参 iPad13 拍板后**目标值不再是闸门**；调用方按
///    `releasedAt == null && !isTerminal && 详情里没有其它达成入口` 传入
///    [canSelfFulfill]。不满足时不渲染；点击**先弹二次确认**，
///    取消不落库（[onSelfFulfill] 只在确认后触发）。
///
/// ## v0.3.0 三态（R3-P0-05 / D5）
/// 判据唯一来自 [WishCardDetail.face]（领域纯函数 `wishTreeFaceOf` 的结果）：
///  - S1：只显原文 + 日期 + **不可点击**轻提示；
///  - S2：仅兜底句（回信正文不再在详情展示）；
///  - S3：只显单句成长引导 `wishGoGrowthHint` + 进度条
///    （旧标题 / 「小办法 n 个」/ 果实阶段行均不再渲染）。
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
    this.confirmMessage,
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

  /// 「实现了」入口开关，由调用方按
  /// `releasedAt == null && !isTerminal && 没有其它达成入口` 算好。
  final bool canSelfFulfill;

  /// 二次确认卡文案（页面 scope 内取好传入）。
  final String confirmTitle;

  /// 确认卡正文（可选；null 时确认卡只显示标题，避免同一句话出现两遍）。
  ///
  /// 玄参 2026-11-20 iPad13 拍板：树上「实现了」确认卡改为单句祝贺标题，
  /// 页面调用点不再传本参数；其它宿主仍可传值，正文照旧显示。
  final String? confirmMessage;
  final String confirmLabel;
  final String cancelLabel;

  final VoidCallback? onCollectToBox;
  final VoidCallback? onChangeWish;
  final VoidCallback? onSelfFulfill;

  @override
  Widget build(BuildContext context) {
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
          // ── 三态主体（S3 只显单句成长引导 + 进度条；S1 只显轻提示） ────────
          ..._faceBody(),
          const SizedBox(height: 16),
          // ── 主按钮「实现了」（愿望级；唯一入口由调用方保证） ────────────────
          if (canSelfFulfill)
            FilledButton.icon(
              key: const Key('wish_detail_self_fulfill'),
              onPressed: onSelfFulfill == null
                  ? null
                  : () => _confirmThen(context, onSelfFulfill!),
              icon: const Icon(Icons.emoji_events_outlined),
              label: Text(t.wishDetailRealized),
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
                  child: Text(t.wishDetailChangeWishShort),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('wish_detail_collect'),
                  onPressed: onCollectToBox,
                  child: Text(t.wishDetailCollectShort),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 三态主体（S1 轻提示 / S2 兜底句 / S3 单句成长引导 + 进度条）。
  ///
  /// 🔴 玄参 iPad13 反馈：详情不再渲染等待天数 / 回信区 / 果实阶段 /
  /// 「小办法 n 个」计数；S3 只保留单句 [AppLocalizations.wishGoGrowthHint]
  /// 与进度条，key `wish_detail_way_title` 复用保持测试锚点稳定。
  List<Widget> _faceBody() {
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
        // S2：兜底句；回信正文 / 回信区已按玄参反馈从详情移除。
        // **不显**果实阶段与进度条。
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
        // S3：v0.4 单句成长引导 + 进度条（旧标题 / 计数 / 果实阶段行全部下线）。
        return <Widget>[
          const SizedBox(height: 10),
          Text(
            t.wishGoGrowthHint,
            key: const Key('wish_detail_way_title'),
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
