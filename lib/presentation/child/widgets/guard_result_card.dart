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
/// ## 奖励说明行（B13.2 玄参裁定：**不再算账**）
/// 旧版有券时固定输出「花了 N 阳光，拿回 N 阳光，券还能省 N 阳光」
/// （R2 缓解，把账摆在明面上）。玄参 2026-11-11 真机复验拍板：
/// **算账行移除**，有 buff 增益券时直接写 [AppLocalizations.guard_result_rare]
/// （「恭喜获得稀有奖励！」）；无掉落档沿用 [AppLocalizations.guard_result_nothing]
/// （「这次什么都没捡到，但菜保住了」）。`guard_result_compare` 同步退役。
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
    show guardDropName;
import 'package:sunflower_time/core/i18n/species_l10n.dart'
    show speciesNameOrNull;
import 'package:sunflower_time/domain/entities/guard_chest.dart'
    show GuardSeedKind;
import 'package:sunflower_time/domain/entities/guard_drop.dart'
    show GuardDropKind, GuardDropKindX;
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';

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
///
/// ## 被偷行（B4，守卫战 v2 §5.3 裁决 B）
/// [stolenSun] = 本场**账本实扣额**（`recordBattleTheft` 的返回值，不是 sim
/// 原始值 —— 余额钳制 / 互斥去重都可能让实扣 < sim 值）。契约：**卡面 N 恒
/// == 账本 `guard_stolen` 行**。`stolenSun <= 0` 时**整行不渲染**（「偷走 0
/// 阳光」与「券还能省 0 阳光」同罪 —— QA 抓过的句式，绝不出现）；
/// 超时 / 降级路径不传即缺省 0，行为与 v1 逐位一致。
Future<GuardClaimOutcome?> showGuardResultCard(
  BuildContext context, {
  required GuardTodayView view,
  required AppLocalizations l10n,
  required Future<GuardClaimOutcome> Function() onCollect,
  int stolenSun = 0,
  bool showPremiumHint = false,
  double uiScale = 1.0,
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
      child: GuardResultCard(
        view: view,
        l10n: l10n,
        onCollect: onCollect,
        stolenSun: stolenSun,
        showPremiumHint: showPremiumHint,
        uiScale: uiScale,
      ),
    ),
  );
}

/// 结算卡本体（纯展示 + 一个「收下」动作）。
class GuardResultCard extends StatefulWidget {
  /// 卡片根 Key。
  static const Key cardKey = Key('guardResultCard');

  /// 「收下」按钮 Key（测试据此点击；也据此断言「只发一次」）。
  static const Key collectButtonKey = Key('guardResultCollect');

  /// 胜利战士立绘（B12 新增；玄参「结算卡没有用向日葵胜利的图片」）。
  static const Key winArtKey = Key('guardResultWinArt');

  /// 阳光奖励卡（B13：奖励卡区左卡，`assets/rewards/sunlight.png`）。
  static const Key sunRewardKey = Key('guardResultSunReward');

  /// 道具券奖励卡（B13：奖励卡区右卡，占位素材 —— 等玄参美术）。
  static const Key voucherRewardKey = Key('guardResultVoucherReward');

  /// 第二张券卡（B13.5 双券；Guard-B13.11 起只出现在**高级宝箱**里）。
  static const Key bonusVoucherRewardKey = Key('guardResultBonusVoucherReward');

  /// 植物碎片奖励卡（Guard-B13.11 高级宝箱专属；普通档不渲染）。
  static const Key fragmentRewardKey = Key('guardResultFragmentReward');

  /// 种子奖励卡（Guard-B13.11 高级宝箱专属；普通档不渲染）。
  static const Key seedRewardKey = Key('guardResultSeedReward');

  /// 入场缩放层（0.86 → 1.0，`Curves.easeOutBack`，320ms）。
  ///
  /// 测试读法：`tester.widget<ScaleTransition>(find.byKey(scaleKey))
  ///   .scale.value` —— 起始 ≈0.86，`pump(320ms)` 后 ≈1.0。
  static const Key scaleKey = Key('guardResultScale');

  /// 「完整版有高级宝箱」引导行（B13.16；free 档 + 打赢才渲染）。
  static const Key premiumHintKey = Key('guardResultPremiumHint');

  /// 入场缩放时长。单位：ms（⚠️ 与路由过渡 [kGuardBattleToResultMs] 是两条
  /// 时间轴：路由负责「关卡 → 卡片出现」，本动画负责「卡片从小放大」）。
  static const int entryScaleMs = 320;

  /// 战果快照（贼 / 必得阳光 / 掉落档 / 成本）。
  final GuardTodayView view;

  /// 页级 scope 内解析好的文案。
  final AppLocalizations l10n;

  /// 点「收下」时执行的动作（= `GuardService.claim`）。
  final Future<GuardClaimOutcome> Function() onCollect;

  /// 本场账本实扣的被偷额（☀；<= 0 时不渲染被偷行 —— 见文件头契约）。
  final int stolenSun;

  /// 是否显示「完整版有高级宝箱」引导行（B13.16 玄参：打赢的文案里加
  /// 「完整版还会有高级宝箱掉落，奖励会更丰富」提示）。
  ///
  /// 宿主（今日页）按权益档判定：**free 档才传 true**（premium 用户本来就能
  /// 掉高级宝箱，再提示就矛盾了）。卡内渲染条件 = 本参数 && `stolenSun <= 0`
  /// （打赢 = 没被偷；被偷/撤退不打广告）。
  final bool showPremiumHint;

  /// 平板放大倍率（手机 1.0、iPad 11″ 1.3 / 13″ 1.6，同 `uiScaleOf`）。
  ///
  /// 🔴 B13.16（玄参 2026-11-12 iPad 截图反馈「结算卡狭长、没适应平板」）：
  /// 卡宽上限 340 与立绘 / 奖励图高度（88 / 84 / 44）都是手机常量 ⇒ iPad 上
  /// 卡是 340 宽的窄长条。本倍率作用于**几何**（卡宽上限、立绘 / 图标高度），
  /// 文字仍走系统 textScaler 不乘（防双乘）；手机默认 1.0 逐位零回归。
  final double uiScale;

  const GuardResultCard({
    super.key,
    required this.view,
    required this.l10n,
    required this.onCollect,
    this.stolenSun = 0,
    this.showPremiumHint = false,
    this.uiScale = 1.0,
  });

  @override
  State<GuardResultCard> createState() => _GuardResultCardState();
}

class _GuardResultCardState extends State<GuardResultCard>
    with SingleTickerProviderStateMixin {
  /// 入场缩放 / 淡入控制器（0.86 → 1.0，320ms）。
  ///
  /// 🔴 为什么自带控制器而不是用 `showGeneralDialog` 的 `animation`：
  ///  · 结算卡也会被**直接挂载**（QA 的卡面文案用例、`guard_today_flow_test` ⑧），
  ///    那条路径上没有路由动画 —— 自驱动才能保证「任何挂载方式都有入场」；
  ///  · 路由过渡时长（200ms）与卡面缩放时长（320ms）本就不同，混用会互相牵制。
  /// 控制器一次性播放（不 loop）⇒ 不会留下永久 ticker，测试 `pumpAndSettle`
  /// 也能自己停下来。
  late final AnimationController _entryCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: GuardResultCard.entryScaleMs),
  );

  /// 缩放曲线：`easeOutBack` 的轻微过冲（1.0 → ≈1.02）让卡片「弹」出来。
  late final Animation<double> _entryScale = _entryCtrl.drive(
    Tween<double>(begin: 0.86, end: 1.0).chain(
      CurveTween(curve: Curves.easeOutBack),
    ),
  );

  /// 淡入曲线：只从 0.55 起（「轻微」—— 纯淡入会让卡片先隐形再出现，
  /// 观感是「闪了一下」而不是「弹出来」）。
  late final Animation<double> _entryFade = _entryCtrl.drive(
    Tween<double>(begin: 0.55, end: 1.0).chain(
      CurveTween(curve: Curves.easeOut),
    ),
  );

  /// 领取在飞闸门：连点只会触发一次 `claim()`（幂等之外的第二道防线 ——
  /// 领域层的幂等是「不会重复发」，这里是「不会重复请求」）。
  bool _submitting = false;

  /// 失败提示（余额不足等**正常业务分支**：不抛异常、不关卡，就地告诉孩子）。
  String? _error;

  @override
  void initState() {
    super.initState();
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

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
    // 🔴 2026-11-12 玄参裁定：怪物同场交叉后，出场的怪不再恒等于贼种，
    //    标题改通用文案（l10n guard_result_title），不再指名 guardThiefName。
    final bool isZh =
        Localizations.localeOf(context).languageCode.startsWith('zh');
    // 🔴 Guard-B13.11：高级宝箱的附加奖励各占一张卡；普通宝箱**一张都不渲染**
    //    （绝不出现「空槽」或「+0 片」这种把孩子当傻子的占位）。
    final bool premium = view.isPremiumChest;
    final bool hasFragment = view.chestFragmentQty > 0;
    final bool hasSeed =
        view.chestSeedKind.hasSeed && view.chestSeedSpeciesId != null;
    // 稀有说明框判据（B13.2 玄参「不再算账」口径不变，只是判据从「有券」扩成
    // 「有券 **或** 高级宝箱附加奖」—— 碎片 / 种子同样是稀有奖励）。
    final bool hasRare = view.dropKind.hasVoucher ||
        view.bonusDropKind.hasVoucher ||
        hasFragment ||
        hasSeed;

    // 🔴 入场：卡片从 0.86 放大到 1.0（`easeOutBack` 轻微过冲）+ 轻微淡入。
    //    `Transform` 不参与布局 ⇒ 0.86 时卡片占位不变，宿主布局零抖动。
    return ScaleTransition(
      key: GuardResultCard.scaleKey,
      scale: _entryScale,
      child: FadeTransition(
        opacity: _entryFade,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                key: GuardResultCard.cardKey,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                constraints:
                    BoxConstraints(maxWidth: 340 * widget.uiScale),
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
                child: ListView(
                  // 🔴 B12：`Column` → `shrinkWrap` ListView。B12 给卡面补了
                  // 88pt 胜利立绘 + 12pt 间距后，「320×568 + en + 1.3×」最坏
                  // 组合（QA V5-2）底部溢出 26px —— Column 装不下就是硬溢出；
                  // shrinkWrap ListView 在内容 ≤ 可用高时**贴内容高**（与原
                  // Column 逐位一致），装不下时变成**内部滚动**，永不 overflow。
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    // ① 标题（通用：花园守卫成功，赶走了贪吃的小动物）
                    Text(
                      t.guard_result_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B4A00),
                      ),
                    ),
                    // ①′ 胜利战士立绘（B12）；高度随平板倍率（B13.16）。
                    SizedBox(
                      key: GuardResultCard.winArtKey,
                      height: 88 * widget.uiScale,
                      child: GuardArt.soldierWin(),
                    ),
                    const SizedBox(height: 12),
                    // ② 奖励卡区分组标题。
                    Text(
                      t.guard_result_rewards,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A5A00),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ②′ 第一行奖励卡：阳光 + 主券 + 第二张券（最多 **3** 张）。
                    //
                    // 🔴 B13.1：`stretch` 在 shrinkWrap ListView 里会拿到**无界
                    // 纵向约束** ⇒「BoxConstraints forces an infinite height」硬崩
                    // （本轮 31 连爆的根因）。套 `IntrinsicHeight` 把高度钉到子卡
                    // intrinsic 高，同一行的奖励卡仍然等高。
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: _sunRewardCard(t, view, premium)),
                          if (view.dropKind.hasVoucher) ...<Widget>[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _voucherRewardCard(
                                key: GuardResultCard.voucherRewardKey,
                                kind: view.dropKind,
                                t: t,
                                isZh: isZh,
                              ),
                            ),
                          ],
                          // 🔴 P3：第二张券卡必须与**第一张不同种**才渲染。
                          //
                          // 当前靠派生层不变量（`_pickOtherVoucher`：`bonusDropKind`
                          // 恒 != `dropKind`）保证两张券不会撞车，所以下面的
                          // `!=` 分支今天走不到 —— 但那是**派生层的**不变量，
                          // 表现层不该白拿它当护身符：派生逻辑一旦放宽（例如将来
                          // 允许「同种券叠两次」），这里就会画出两张一模一样的
                          // 券卡（孩子看到「浇水券」「浇水券」，以为白送了两张）。
                          // 去重条件放**表现层**，是让「画两张一样的券」在任何上游
                          // 改动下都不可达 —— 防御性判断，不是当前可达路径。
                          if (view.bonusDropKind != view.dropKind &&
                              view.bonusDropKind.hasVoucher) ...<Widget>[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _voucherRewardCard(
                                key: GuardResultCard.bonusVoucherRewardKey,
                                kind: view.bonusDropKind,
                                t: t,
                                isZh: isZh,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // ②″ 第二行：碎片 / 种子（**高级宝箱专属**，最多 2 张卡）。
                    //
                    // 🔴 为什么另起一行而不是塞进第一行：奖励卡上限从 3 涨到 5，
                    // 5 个 `Expanded` 在 320pt 屏 + 1.3× 字号下必然挤爆（QA V5-2
                    // 老坑）。两行各自 ≤3 张，与改造前的行内密度完全一致。
                    if (hasFragment || hasSeed) ...<Widget>[
                      const SizedBox(height: 8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (hasFragment)
                              Expanded(child: _fragmentRewardCard(t, view)),
                            if (hasFragment && hasSeed) const SizedBox(width: 8),
                            if (hasSeed) Expanded(child: _seedRewardCard(t, view)),
                          ],
                        ),
                      ),
                    ],
                    // ②‴ 被偷行（B4）：本场有怪到门口且账本实扣 > 0 才渲染。
                    //    🔴 0 不渲染（「偷走 0 阳光」= QA 抓过的「省 0 阳光」同罪）。
                    if (widget.stolenSun > 0) ...<Widget>[
                      const SizedBox(height: 10),
                      _ResultLine(
                        icon: Icons.directions_run,
                        color: const Color(0xFFB3261E),
                        text: t.guard_result_stolen(widget.stolenSun),
                      ),
                    ],
                    // ③ 奖励说明（B13.2 玄参裁定，不算账）：
                    //    有券 / 碎片 / 种子 ⇒「恭喜获得稀有奖励！」；
                    //    其余 ⇒「这次什么都没捡到，但菜保住了」。
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: hasRare
                            ? const Color(0xFFFFF3D6)
                            : const Color(0xFFF6F1E7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hasRare ? t.guard_result_rare : t.guard_result_nothing,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight:
                              hasRare ? FontWeight.w700 : FontWeight.w400,
                          color: hasRare
                              ? const Color(0xFF8A5A00)
                              : const Color(0xFF8A7A66),
                        ),
                      ),
                    ),
                    if (widget.showPremiumHint &&
                        widget.stolenSun <= 0) ...<Widget>[
                      const SizedBox(height: 8),
                      // 🔴 B13.16（玄参）：打赢的文案里给免费用户一句完整版引导 ——
                      //    premium 档宿主不传（他们自己就能掉高级宝箱）；被偷 /
                      //    撤退也不传（打了败仗还推销，观感差）。
                      Container(
                        key: GuardResultCard.premiumHintKey,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.l10n.guard_result_premium_hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF4A6B8A),
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
        ),
      ),
    );
  }

  /// 阳光奖励卡（数字 = **实际到账额** [GuardTodayView.winSunToGrant]）。
  ///
  /// 🔴 卡面 N **恒等于**账本 `guard_win` 行的 gross（V3 口径扫描钉死）。
  /// 高级宝箱在这里显示翻倍后的数字，并用一行小字说明「为什么是 8 而不是 4」——
  /// 否则孩子会以为卡面算错了。
  Widget _sunRewardCard(
    AppLocalizations t,
    GuardTodayView view,
    bool premium,
  ) {
    return Container(
      key: GuardResultCard.sunRewardKey,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8A600), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Image.asset(
            'assets/rewards/sunlight.png',
            height: 44 * widget.uiScale,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(height: 44),
          ),
          const SizedBox(height: 4),
          Text(
            '+${view.winSunToGrant}',
            style: const TextStyle(
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB37400),
            ),
          ),
          Text(
            t.guard_result_reward_sun,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              color: Color(0xFF8A7A66),
            ),
          ),
          if (premium) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              t.guard_result_premium_chest,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB37400),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// buff 券卡（主券 / 高级宝箱的第二张券共用同一个款式）。
  Widget _voucherRewardCard({
    required Key key,
    required GuardDropKind kind,
    required AppLocalizations t,
    required bool isZh,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F3EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3D8B7D), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 🔴 B13.7：券卡美术 84 高；B13.8 素材二次裁切后原比 276:294；
          //    高度随平板倍率（B13.16，宽由 AspectRatio 联动）。
          SizedBox(
            height: 84 * widget.uiScale,
            child: AspectRatio(
              aspectRatio: 276 / 294,
              child: GuardArt.voucherCard(kind, isZh: isZh),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            guardDropName(kind, t),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E6B60),
            ),
          ),
        ],
      ),
    );
  }

  /// 植物碎片卡（高级宝箱专属）。
  Widget _fragmentRewardCard(AppLocalizations t, GuardTodayView view) {
    return Container(
      key: GuardResultCard.fragmentRewardKey,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6A5ACD), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Image.asset(
            'assets/rewards/fragment.png',
            height: 44 * widget.uiScale,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(height: 44),
          ),
          const SizedBox(height: 4),
          Text(
            '+${view.chestFragmentQty}',
            style: const TextStyle(
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4B3FA8),
            ),
          ),
          Text(
            t.guard_result_reward_fragment,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              color: Color(0xFF6B6482),
            ),
          ),
        ],
      ),
    );
  }

  /// 种子卡（高级宝箱专属）：普通档 / 精英档两张不同素材，名字用物种名。
  Widget _seedRewardCard(AppLocalizations t, GuardTodayView view) {
    final String speciesId = view.chestSeedSpeciesId ?? '';
    // 物种名走既有 `species_l10n`（**绝不新造物种名**）；未知 id 兜底成空串 ——
    // 此时宁可显示「种子」也不显示 `species_xxx` 这种内部 id。
    final String speciesName = speciesNameOrNull(speciesId, t) ?? '';
    return Container(
      key: GuardResultCard.seedRewardKey,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6A9A3F), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Image.asset(
            view.chestSeedKind == GuardSeedKind.premium
                ? 'assets/rewards/seed_premium.png'
                : 'assets/rewards/seed_common.png',
            height: 44 * widget.uiScale,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(height: 44),
          ),
          const SizedBox(height: 4),
          const Text(
            '×1',
            style: TextStyle(
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4E7A2A),
            ),
          ),
          Text(
            speciesName.isEmpty
                ? t.guard_result_reward_seed
                : t.guard_result_seed(speciesName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              color: Color(0xFF6B7A5A),
            ),
          ),
        ],
      ),
    );
  }
}
/// 结算卡里的一行（图标 + 文案）。文案由调用方格式化，本类只管排版。
class _ResultLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _ResultLine({
    required this.icon,
    required this.color,
    required this.text,
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
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8A7A66),
            ),
          ),
        ),
      ],
    );
  }
}
