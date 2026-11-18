/// 愿望任务卡（A-T04 / A22.3 / A24.6 ①）。
///
/// 照 `child_task_page._taskTile` 的**暖白渐变 + 淡金描边 + 柔和暖影**范式；
/// 判定单点 = [Task.requiresFocus]（同一行绝不并存放「去专注」与「我做到了」）：
///  - **专注型**：「去专注」两行方盒（照 `_focusBox`）——点击**先弹** `showChildConfirmCard`
///    （F177 / C105 硬契约），确认后才
///    `context.go('/focus?minutes=...&dnd=1&wishTask=<tasks.id>')`；取消即止。
///  - **手动型**：「我做到了」方盒——同样先弹确认（防误触），确认后回调 [onDidIt]
///    交给领域层核销（本 widget 不自行落库）。
///  - 🌟 **愿望任务徽标 + 归属愿望短名**（A24.6 ①）：判定 = `task.wishId != null`。
///
/// 本 widget 不读 provider：文案由调用方在页级 scope 内取好经参数传入（弹窗 builder
/// 上下文在 scope 外的铁律）。`animate` 保留开关仅为 API 一致，无动画。
library wish_task_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:go_router/go_router.dart';

/// 暖白渐变（与 `child_task_page._taskTile` 逐位一致）。
const List<Color> kWishTaskCardGradient = <Color>[
  Colors.white,
  Color(0xFFFDF3DD),
];

/// 归属愿望短名最大码点数（超出以省略号结尾）。
const int kWishTitleShortRunes = 8;

/// 把愿望文本截成短名（按码点，emoji 不被截半）。判据单点，测试可直接调用。
String wishTaskShortTitle(String text) {
  final int count = text.runes.length;
  if (count <= kWishTitleShortRunes) return text;
  return '${String.fromCharCodes(text.runes.take(kWishTitleShortRunes))}…';
}

/// 🌟「愿望任务」徽标 + 归属愿望短名（A24.6 ① / child_task_page.dart:621）。
///
/// 独立成 widget 便于既有成长页按 `task.wishId != null` 条件插入——
/// 普通成长任务（`wishId == null`）**不渲染本 widget，逐字节不变**。
/// 文案 `wishTaskBadgeOfWish(短名)` 由调用方在 scope 内取好经参数传入。
class WishTaskBadge extends StatelessWidget {
  const WishTaskBadge({
    super.key,
    required this.wishTitle,
    required this.label,
  });

  /// 归属愿望短名（已由调用方经 [wishTaskShortTitle] 截断）。
  final String wishTitle;

  /// 完整文案（`t.wishTaskBadgeOfWish(短名)`）。
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        '🌟 $label',
        key: const Key('wish_task_badge'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF8D6E00),
        ),
      );
}

/// 愿望任务卡。
class WishTaskCard extends StatelessWidget {
  const WishTaskCard({
    super.key,
    required this.task,
    required this.wishTitle,
    required this.focusActionLabel,
    required this.didItLabel,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.startFocusLabel,
    required this.cancelLabel,
    required this.doneLabel,
    required this.pendingLabel,
    this.done = false,
    this.pending = false,
    this.onDidIt,
  });

  /// 任务模板（复用 `tasks` 表的一行）。
  final Task task;

  /// 归属愿望短名（读侧现算，不落列）。
  final String wishTitle;

  /// 「去专注」/「我做到了」方盒主文案。
  final String focusActionLabel;
  final String didItLabel;

  /// 确认卡标题 / 正文（专注型带分钟数占位已由调用方填好）。
  final String confirmTitle;
  final String confirmMessage;
  final String startFocusLabel;
  final String cancelLabel;
  final String doneLabel;
  final String pendingLabel;

  /// 今日已完成 / 待家长确认（只读态）。
  final bool done;
  final bool pending;

  /// 手动型「我做到了」确认后的回调（领域层核销由调用方负责）。
  final VoidCallback? onDidIt;

  @override
  Widget build(BuildContext context) {
    final bool showFocus = task.requiresFocus;
    return Container(
      key: Key('wish_task_card_${task.id}'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: kWishTaskCardGradient,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 🌟 愿望任务徽标（非红色）+ 归属愿望短名。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (task.wishId != null)
                  Text(
                    '🌟 $wishTitle',
                    key: const Key('wish_task_badge'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8D6E00),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  task.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (done || pending)
            _statusCapsule(pending ? '⏳' : '✓', pending ? pendingLabel : doneLabel)
          else if (showFocus)
            _focusBox(context)
          else
            _didItBox(context),
        ],
      ),
    );
  }

  /// 只读状态胶囊（完成 / 待确认）。
  Widget _statusCapsule(String icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD9F2DD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$icon $label',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2E7D32),
          ),
        ),
      );

  /// 专注型「去专注」两行方盒（照 `_focusBox`）。
  Widget _focusBox(BuildContext context) => InkWell(
        key: const Key('wish_task_go_focus'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onFocusTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1C2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                focusActionLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8D6E00),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${task.minFocusMin} min',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8D6E00),
                ),
              ),
            ],
          ),
        ),
      );

  /// 手动型「我做到了」方盒。
  Widget _didItBox(BuildContext context) => InkWell(
        key: const Key('wish_task_did_it'),
        borderRadius: BorderRadius.circular(12),
        onTap: onDidIt == null ? null : () => _onDidItTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1C2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            didItLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8D6E00),
            ),
          ),
        ),
      );

  /// 误触保护：先弹确认卡，取消（`ok != true`）绝不进专注。
  Future<void> _onFocusTap(BuildContext context) async {
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: confirmTitle,
      message: confirmMessage,
      confirmLabel: startFocusLabel,
      cancelLabel: cancelLabel,
    );
    if (ok != true) return;
    if (!context.mounted) return;
    // 🔴 值 = 既有 tasks.id；与 `?task=` 互斥判定已在 app_router 内。
    context.go(
      '/focus?minutes=${task.minFocusMin}&dnd=1&wishTask=${task.id}',
    );
  }

  Future<void> _onDidItTap(BuildContext context) async {
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: confirmTitle,
      message: didItLabel,
      confirmLabel: didItLabel,
      cancelLabel: cancelLabel,
    );
    if (ok != true) return;
    onDidIt?.call();
  }
}
