/// 向日葵守卫 · **大招用法说明卡**（玄参 2026-11-20 真机验收拍板）。
///
/// 待机态点战士 → **屏幕居中卡片 + 「知道了」按钮**（不是轻提示）：讲清
/// 「专注攒能量 → 战斗中点战士放大招 → 无视闪避清空当前怪物」。
///
/// 🔴 弹窗纪律：builder 挂在根 Navigator（页级 `L10nScope` 之外），文案由调用方
/// 在页内取好经参数槽位传入，本文件零中文硬编码、零权益 token。
/// 形态照 `garden_page._showGardenHelp` 的先例：`showGeneralDialog` + Center +
/// fade/scale 0.92→1.0（200ms）+ 点遮罩可关 + 定宽（iPad 不窄长条）。
///
/// 玄参真机反馈 1：标题措辞改「技能」、顶部图标从 🌻 emoji 换成战士站立
/// UI 形象（`GuardArt.soldierStand`）；免费档在正文下追加灰色小字提示，
/// 文案同样经 [premiumHint] 槽位由调用方传入（本文件仍零中文硬编码）。
library guard_ultimate_help_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;

/// 说明卡根 Key（widget 测试断言「待机态点战士弹说明卡」用）。
const Key guardUltimateHelpKey = Key('guardUltimateHelpCard');

/// 「知道了」按钮 Key（测试点它关闭用）。
const Key guardUltimateHelpConfirmKey = Key('guardUltimateHelpConfirm');

/// 弹出大招用法说明卡（居中，点「知道了」或遮罩关闭）。
///
/// [title] / [body] / [confirmLabel] / [premiumHint] 全部已本地化，由调用方经
/// `l10nOf` 取好传入。[premiumHint] 为空时不渲染该行（买断档）。
Future<void> showGuardUltimateHelpDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String? premiumHint,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (
      BuildContext dialogCtx,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return LayoutBuilder(
        builder: (BuildContext layoutCtx, BoxConstraints viewport) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (viewport.maxHeight - 48).clamp(0.0, double.infinity),
                ),
                child: SizedBox(
                  key: guardUltimateHelpKey,
                  // 定宽：手机 390 → 330；iPad → 460（与花园说明卡同口径）。
                  width: viewport.maxWidth < 520
                      ? 330.0
                      : 460.0,
                  child: DecoratedBox(
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
                    child: _GuardUltimateHelpCard(
                      title: title,
                      body: body,
                      confirmLabel: confirmLabel,
                      premiumHint: premiumHint,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
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
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 说明卡内容（图标 + 标题 + 正文 + 可选免费提示 + 「知道了」按钮；零权益、零跳转）。
class _GuardUltimateHelpCard extends StatelessWidget {
  const _GuardUltimateHelpCard({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.premiumHint,
  });

  final String title;
  final String body;
  final String confirmLabel;

  /// 免费档专属灰色小字（买断档为 null ⇒ 整行不渲染）。
  final String? premiumHint;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 战士 UI 形象替代原 🌻 emoji：60 逻辑像素、contain，缺图回退
            // 太阳图标（不用 emoji，保持零中文硬编码 + 缺图不崩）。
            SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                GuardArt.soldierStand,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.sunny,
                  size: 44,
                  color: Color(0xFF6B5A3E),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B5A3E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF7A6E58),
              ),
            ),
            // 免费档专属小字：正文与按钮之间，12pt 灰色居中。
            if (premiumHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  premiumHint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A8F78),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              key: guardUltimateHelpConfirmKey,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }
}
