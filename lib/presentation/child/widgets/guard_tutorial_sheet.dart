/// 守卫战 v2 · **教学浮层 A**（设计文档 §7-B2 / PRD §6：推荐「A 为主 + C 兜底」）。
///
/// ## 什么时候弹
/// 每天**首次**进战斗前（`GuardTodayView.needsTutorial`，读当日存档的
/// `tutorialSeen`）；关闭时由页面调 `GuardService.markTutorialSeen()` 落盘 ——
/// 跨天新存档缺省 false，故「每天至多一次」由存档生命周期天然保证。
///
/// ## B6 形态修订（玄参 2026-11-10：底部抽屉 → 屏幕居中卡片）
/// 原实现是 `showModalBottomSheet`（「从下面弹出来」就是它）；玄参要求在
/// **屏幕居中**展示。照 `child_avatar.dart` 的既有先例改成居中卡片，
/// 转场用 **fade + scale(0.92→1.0)**（200ms `easeOutCubic`），
/// 与「一张卡片浮现在眼前」的观感一致（底部抽屉的位移感会让人以为是菜单）。
///
/// ## i18n 铁律（不变）
/// dialog / bottom sheet 的 builder 上下文都在页级 [L10nScope] **之外** ——
/// 浮层内**严禁**直调 `AppLocalizations.of`，文案由调用方取好经 [l10n] 槽位
/// 传入（与 `guard_result_card` 同构）。改 `showDialog` 不改变这条约束。
library guard_tutorial_sheet;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 教学浮层根 Key（测试据此断言「出现 / 不出现 / 居中」）。
const Key kGuardTutorialSheetKey = Key('guardTutorialSheet');

/// 教学**卡片**本体的 Key（B6：测试据此断言「屏幕居中」—— 根 Key 落在
/// StatelessWidget 上会解析成整屏 SafeArea，量不出卡片位置）。
const Key kGuardTutorialCardKey = Key('guardTutorialCard');

/// 「知道了」按钮 Key（测试据此关闭浮层）。
const Key kGuardTutorialOkKey = Key('guardTutorialOk');

/// 弹教学浮层（Future 在浮层关闭后完成；点遮罩/返回也算看过 —— 教学不是
/// 强制阅读，孩子合上就算教过了，方向偏向不拦截战斗）。
Future<void> showGuardTutorialSheet({
  required BuildContext context,
  required AppLocalizations l10n,
}) {
  return showGeneralDialog<void>(
    context: context,
    // 点遮罩 / 系统返回即关（与 `showDialog` 默认一致）。
    barrierDismissible: true,
    // 无障碍：遮罩需要一个名字（读屏「关闭」）。
    barrierLabel: l10n.guard_tutorial_ok,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (
      BuildContext pageCtx,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return GuardTutorialSheet(key: kGuardTutorialSheetKey, l10n: l10n);
    },
    transitionBuilder: (
      BuildContext transitionCtx,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          // 0.92 → 1.0：只够「浮现」的暗示，不做夸张弹跳（孩子端不做眩技）。
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 教学浮层内容（纯展示；文案全部来自 [l10n] 槽位）。
///
/// 形态 = **屏幕居中卡片**（米色底 / 大圆角 / 最大宽 420，平板不铺满）。
class GuardTutorialSheet extends StatelessWidget {
  const GuardTutorialSheet({super.key, required this.l10n});

  /// 页级 scope 内解析好的文案（🔴 不得在浮层内自取）。
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          // 320pt 窄屏也给左右留 20pt（内容最宽 280 ⇒ 不溢出）。
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              key: kGuardTutorialCardKey,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEF),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.guard_tutorial_title,
                      key: const Key('guardTutorialTitle'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.guard_tutorial_body,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // 付费价来自常量（PRD 改价只改 prd_params，文案自动跟）。
                      l10n.guard_tutorial_paid_hint(kGuardPayCost),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        key: kGuardTutorialOkKey,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          l10n.guard_tutorial_ok,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
