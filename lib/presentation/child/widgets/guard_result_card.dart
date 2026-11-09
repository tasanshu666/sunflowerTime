/// 「守卫战报」结算卡（第三批，PRD §3.10 / §8.3）。
///
/// ## 🔴 `claim()` 必须在**这里**调用（产品硬约束，不是代码偏好）
/// | 阶段 | 谁触发 | 写不写账本 |
/// |---|---|---|
/// | `resolve()` | 今日页 `_reload` | ❌ 只算 |
/// | 战斗动画 | 孩子看完 / 跳过 | ❌ 只回放 |
/// | **`claim()`** | **本卡「收下」按钮** | ✅ 唯一入口 |
///
/// 「看了战报就算领取」会让**跳过动画**也拿到奖励 —— 奖励就与孩子的动作脱钩了。
/// 把发放推迟到「收下」，才能同时满足两件事：
///  · 跳过动画**不改变**奖励内容（落骰在 `resolve()` 时已定死，动画只是回放）；
///  · 孩子的动作（点收下）才是记账触发点，账本不会因为「打开过页面」多出脏行。
///
/// 幂等由 `GuardService.claim()` 自己保证（状态层 + 账本层 + 写入层三层，见
/// `guard_service.dart` 文件头）：本卡即使被重复点也只发一次 —— 且按钮在
/// in-flight 期间置灰，正常路径根本点不了第二次。
///
/// ## 比较说明（R2 缓解，**有券时必须有**）
/// 孩子最容易困惑的是「**花了 5 阳光，怎么只拿回 2 阳光？**」。
/// 光看「拿回 2」会得出「亏了」的错误结论；实际账是：
/// `−5（请阿葵）+ 2（必得）+ 券面值（今天养护能省）`。
/// 故**有券时**固定输出一行 [AppLocalizations.guard_result_compare]，
/// 把三个数摆在明面上 —— 这不是可选装饰，是 PRD 风险登记 R2 的缓解措施。
///
/// ## 🔴 无掉落档（18%）**整行不渲染**（第三批收口修正的真 bug）
/// 无道具档的券面值是 0，若照常套模板会渲染出
/// **「花了 5 阳光，拿回 3 阳光，券还能省 0 阳光」** —— 孩子读到的是
/// 「我白打了」。故本卡在 `dropKind == none` 时**不渲染比较行**：
/// 「今天没有券」这层语义已经由 [AppLocalizations.guard_result_nothing]
/// （这次什么都没捡到，但菜保住了）承担，不需要再补一句数字化兜底。
/// ⚠️ 代价：无券档也不再说「花了/拿回」—— 是否要为该档单独补一条
/// 「只讲花费与收获」的文案，留待第四批连同 buff chip 一起定（已上报）。
///
/// ## 文案从页面传进来
/// 与 `guard_battle_overlay.dart` 同因（builder 上下文在页级 `L10nScope` 之外）。
library guard_result_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/enum_l10n.dart'
    show guardDropName, guardThiefName;
import 'package:sunflower_time/domain/entities/guard_drop.dart' show GuardDropKindX;
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';

/// 弹出结算卡，并在孩子点「收下」时**执行 [onCollect]**（= `GuardService.claim`）。
///
/// 返回值：
///  · 非 null —— 孩子点了「收下」并拿到了 `claim()` 的结果（成功或失败都在里面）。
///  · `null` —— 仅剩「claim 连续抛异常后孩子用系统返回强行离开」这一条极端路径；
///    正常情况下**不可能出现**：🔴 卡根上有 `PopScope(canPop: false)`（2026-11-09
///    玄参真机：「结算卡说获得浇水券、回花园却没有」的候选根因）—— 原先系统返回键 /
///    返回手势能直接关卡且**不领取**，而卡面上已经承诺「获得浇水券」，孩子离开后券
///    就凭空消失了（文案与事实不一致 + 现象恰与「没点收下的那几次不显示」吻合）。
///    锁死后「看到预告 ⇒ 必然点收下 ⇒ 必然 claim」。
///
/// [onCollect] 由调用方注入而不是本文件 import `GuardService`：结算卡只管
/// 「什么时候发」，不关心「怎么发」；`claim()` 的幂等与账本口径全部留在领域层。
Future<GuardClaimOutcome?> showGuardResultCard(
  BuildContext context, {
  required GuardTodayView view,
  required AppLocalizations l10n,
  required Future<GuardClaimOutcome> Function() onCollect,
}) {
  return showGeneralDialog<GuardClaimOutcome>(
    context: context,
    barrierDismissible: false,
    barrierLabel: l10n.guard_result_collect,
    barrierColor: const Color(0xB31B1206),
    // 战斗 → 结算的过渡时长（跳过后直接落到本卡，观感上不能「瞬切」）。
    transitionDuration: const Duration(milliseconds: kGuardBattleToResultMs),
    pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) =>
        // 🔴 `canPop: false`：系统返回键 / 返回手势不得关卡（先例：
        // `rest_page.dart` / `settle_page.dart`）。唯一的离开方式是「收下」，
        // 领取语义由它触发（PRD：孩子的动作才是记账触发点）。
        PopScope(
      canPop: false,
      child: GuardResultCard(view: view, l10n: l10n, onCollect: onCollect),
    ),
  );
}

/// 结算卡本体（纯展示 + 一个「收下」动作）。
class GuardResultCard extends StatefulWidget {
  /// 卡片根 Key。
  static const Key cardKey = Key('guardResultCard');

  /// 「收下」按钮 Key（测试据此点击；也据此断言「只发一次」）。
  static const Key collectButtonKey = Key('guardResultCollect');

  /// 战果快照（贼 / 必得阳光 / 掉落档 / 成本）。
  final GuardTodayView view;

  /// 页级 scope 内解析好的文案。
  final AppLocalizations l10n;

  /// 点「收下」时执行的动作（= `GuardService.claim`）。
  final Future<GuardClaimOutcome> Function() onCollect;

  const GuardResultCard({
    super.key,
    required this.view,
    required this.l10n,
    required this.onCollect,
  });

  @override
  State<GuardResultCard> createState() => _GuardResultCardState();
}

class _GuardResultCardState extends State<GuardResultCard> {
  /// 领取在飞闸门：连点只会触发一次 `claim()`（幂等之外的第二道防线 ——
  /// 领域层的幂等是「不会重复发」，这里是「不会重复请求」）。
  bool _submitting = false;

  /// 失败提示（余额不足等**正常业务分支**：不抛异常、不关卡，就地告诉孩子）。
  String? _error;

  Future<void> _handleCollect() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final GuardClaimOutcome outcome = await widget.onCollect();
      if (!mounted) return;
      if (!outcome.ok) {
        // 唯一会走到这里的正常分支是 `insufficientBalance`（余额在这几秒里被
        // 别处花掉了）。此时账本**分毫未动**，卡留在原地即可。
        setState(() {
          _submitting = false;
          _error = widget.l10n.guard_pill_no_balance(widget.view.payDeficit);
        });
        return;
      }
      Navigator.of(context).pop(outcome);
    } catch (_) {
      // 账本 / prefs 崩了也不把孩子卡死：放开闸门让他能再点一次
      // （`claim()` 的三层幂等保证不会重复发）。
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = widget.l10n;
    final GuardTodayView view = widget.view;
    final String thiefName =
        view.thief == null ? '' : guardThiefName(view.thief!, t);
    final bool hasVoucher = view.dropKind.hasVoucher;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            key: GuardResultCard.cardKey,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF1),
              borderRadius: BorderRadius.circular(26),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ① 标题：赶走了馋光鼠
                Text(
                  t.guard_result_title(thiefName),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B4A00),
                  ),
                ),
                const SizedBox(height: 16),
                // ② 收获：拿回 2 阳光 ＋ 掉落 / 无掉落
                _ResultLine(
                  icon: Icons.wb_sunny,
                  color: const Color(0xFFE8890C),
                  text: t.guard_result_gain(view.winSun),
                  emphasize: true,
                ),
                const SizedBox(height: 8),
                _ResultLine(
                  icon: hasVoucher ? Icons.confirmation_num : Icons.check_circle,
                  color: hasVoucher
                      ? const Color(0xFF3D8B7D)
                      : const Color(0xFF73A45C),
                  text: hasVoucher
                      ? t.guard_result_drop(guardDropName(view.dropKind, t))
                      : t.guard_result_nothing,
                ),
                // ③ 比较说明（R2 缓解）：**只有今天真有券时才渲染**。
                //    🔴 无掉落档整行不渲染 —— 否则会写出「券还能省 0 阳光」，
                //    读起来是「我白打了」（第三批收口修正）。
                if (hasVoucher) ...<Widget>[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t.guard_result_compare(
                        view.payCost,
                        view.winSun,
                        view.voucherSaving,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Color(0xFF8A5A00),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // ④ 收下 → `claim()`（唯一记账入口）
                FilledButton(
                  key: GuardResultCard.collectButtonKey,
                  onPressed: _submitting ? null : _handleCollect,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8A600),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          t.guard_result_collect,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 结算卡里的一行（图标 + 文案）。文案由调用方格式化，本类只管排版。
class _ResultLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool emphasize;

  const _ResultLine({
    required this.icon,
    required this.color,
    required this.text,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        // 🔴 必须可收缩（F127 教训）：`Expanded` + 两行省略，
        // 320 屏 + 1.3 字号下也不会把卡撑破。
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasize ? 16 : 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? const Color(0xFF4A3410) : const Color(0xFF8A7A66),
            ),
          ),
        ),
      ],
    );
  }
}
