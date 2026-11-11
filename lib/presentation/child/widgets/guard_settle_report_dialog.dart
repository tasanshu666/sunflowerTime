/// 次日结算报告弹窗（B13.4，玄参 2026-11-11 拍板）。
///
/// ## 背景（玄参原话）
/// 「如果小朋友今日没有上线，没有打……第二天制作一个弹窗提示吗？」
/// → **接受建议**：做弹窗；**不做**「自动扣能量豆代打」（违背 PRD
/// 「孩子的动作才是记账触发点」，且代打让守卫失去意义）。
///
/// ## 机制
/// 昨天 `pending`（没打）的存档，今天首次刷新今日页时由 `GuardService.expire()`
/// **静默结算**（扣阳光 + 扣成长）——账务早已闭环，本弹窗只负责**把这件事告诉
/// 孩子**（纯信息展示，零账务逻辑）。`expire()` 幂等（同一天第二次调用返回
/// `none`）⇒ 弹窗天然**一天最多一次**，无需额外「已看过」持久化标记。
///
/// ## 三种新闻（可叠加）
/// * 被偷阳光（`stolenSun > 0`）；* 成长被偷吃的株数（`growthTargets > 0`）；
/// * fighting 补发（昨天打了但没收奖励 ⇒ `grantedWinSun > 0`，好消息）。
///
/// ## 已知边界（可接受降级）
/// 结算与弹窗同链路：若结算那次恰逢守卫链路超时 / 异常（页面按「没有守卫」
/// 降级），本次报告不弹——**账不丢**（结算在 domain 已落账），只是少一次提示；
/// 存档已清，之后也不会再弹。与「链路失败 ⇒ 视同没有守卫」的既有纪律一致。
library guard_settle_report_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/services/guard_service.dart'
    show GuardExpireOutcome;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 结算结果里有没有「值得告诉孩子」的事（纯函数，便于单测）。
bool guardSettleHasNews(GuardExpireOutcome outcome) {
  return outcome.settled &&
      (outcome.stolenSun > 0 ||
          outcome.growthTargets > 0 ||
          outcome.grantedWinSun > 0);
}

/// 弹出次日结算报告（没有新闻 ⇒ 空操作、不弹）。
///
/// [context] 必须在 `MaterialApp` 内；l10n 由调用方传入（弹窗上下文在页级
/// L10nScope 之外，与 `showGuardIntroDialog` 同因）。
Future<void> showGuardSettleReport(
  BuildContext context,
  AppLocalizations l10n,
  GuardExpireOutcome outcome,
) {
  if (!guardSettleHasNews(outcome)) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.guard_settle_ok,
    barrierColor: const Color(0xB31B1206),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) {
      final AppLocalizations t = l10n;
      final List<String> lines = <String>[
        if (outcome.stolenSun > 0) t.guard_settle_body_sun(outcome.stolenSun),
        if (outcome.growthTargets > 0)
          t.guard_settle_body_growth(outcome.growthTargets),
        if (outcome.grantedWinSun > 0)
          t.guard_settle_body_win(outcome.grantedWinSun),
      ];
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              key: const Key('guardSettleReport'),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF1),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ① 标题
                    Text(
                      t.guard_settle_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B4A00),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ② 结算明细（最多三行）
                    for (final String line in lines) ...<Widget>[
                      Text(
                        line,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF4A3410),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 8),
                    // ③ 引导语
                    Text(
                      t.guard_settle_foot,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3D8B3D),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // ④ 确认
                    FilledButton(
                      key: const Key('guardSettleOk'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE8A600),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        t.guard_settle_ok,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
