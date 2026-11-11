/// 守卫战 v2 · **守卫场景卡**（设计文档 §6.3 布局 v4 裁定，B8 重排）。
///
/// ## 插在哪
/// `ChildTodayPage` 的 `ListView` **第 0 项**（替换 v1 的 44pt 胶囊位）；
/// [GuardTodayView.isVisible] == false（`absent`）时**整个 widget 不进树**
/// （调用方负责不插）—— 零占位是调用方的契约，与 v1 胶囊逐位同口径。
///
/// ## 布局 v4（玄参 2026-11-10 第三轮真机复验；几何全部来自 `guard_card_layout`）
/// ```text
/// ┌──────────────────────────────────────────────────────────────┐ y=0
/// │    ○ ○   ← 能量点（房子右侧、栅栏上方，18pt，亮/灭两态）        │
/// │  🏠 房子（contain 完整可见）  🧑‍🚀 战士（栅栏外）  ←←← 怪   (▶)  │
/// │ ▬▬▬▬▬▬▬▬▬▬▬ 倒计时细线（战斗态，4pt）▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ │ y=108
/// └──────────────────────────────────────────────────────────────┘
/// ```
/// ### v3 → v4 的四处改动
/// * **卡高 160 → 108**（玄参「上方大片空白」）：卡高 = 房顶高度 + 底衬；
/// * **能量点回归**：两个 18pt 圆点放回「房子右侧、栅栏上方」，亮/灭两态
///   （`view.energyAvailable`），垂直不越出房顶一个直径 ⇒ **不再把卡撑高**；
/// * **战士挪到栅栏外**：`soldierRect.left = 房子右缘 + 2`（v3 是压进房子 6pt；
///   B8 的 6pt 在 B9 改成 2pt —— 裁边前的 6pt 肉眼是 23pt，见下）；
/// * **去外框**：卡根不再有描边 / 圆角 / `ClipRRect` —— 草地板自己铺满整张卡，
///   今日页再用 `OverflowBox` 把它撑成**满宽贴边**（横向白赚 32pt 通道）。
///
/// ### 仍然保留的 v3 减法
/// * ❌ 顶部状态条幅：**状态信息只活在 [statusSemanticsKey] 的 label**；
/// * ❌ 卡内开火大圆钮：开火由页面右上的**阳光胶囊**触发（[GuardBattleHandle]）；
/// * ✅ 「开始守卫」图标钮（右簇唯一元素，战斗中该格**留空但占位** ⇒
///   通道宽度不会因为按钮消失而跳变）；
/// * ✅ 倒计时是卡片**底部**一条 4pt 细线。
///
/// ### 尺寸（字面量由测试钉住）
/// 卡高 108 / 房子 88（宽≈156，contain）/ 战士 **78**（B9；裁边后标称=视觉，
/// 绘制框 130 允许横向溢出）/ 小怪 44 / 子弹 12 / 能量点 18；卡宽 ≤ 380pt 时
/// 卡内元素整体 ×0.85（卡高不变；B8.1 阈值 340→380，修掉「360 屏通道比 320 屏
/// 还窄」的倒挂）。
///
/// ### B9（玄参第四轮）在本文件落了什么
/// * **C2**：战士按 `BoxFit.fitHeight` 绘制 + `OverflowBox` 横向溢出（不裁 /
///   不缩 / 不用 contain）—— 素材已按实体裁边，78 就是肉眼 78pt；
/// * **C4**：能量点锚点改房子中轴（`houseRect.center.dx`），不再吊在战士头顶。
///
/// ## 🔴 布局抗溢出（F127 教训）
/// 尺寸预算按最窄卡（320 屏 ⇒ 卡宽 320，×0.85）定，通道仍有 ≈56pt；卡内
/// **除战斗演出（终局横幅 / MISS）外零文本**（状态文案全部退出到
/// `Semantics.label`），故大字号 / 英文长文案都不再能撑破卡；
/// 卡高固定 [kGuardSceneCardHeight]，绝不用 `FittedBox` / 压 `fontSize`。
library guard_scene_card;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattlePhase, GuardBattleScript, GuardBattleSnapshot;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_intro_dialog.dart';

/// 守卫场景卡（纯展示 + 「开始守卫」回调，**不碰任何服务 / 账本**；
/// 教学浮层与确认卡由页面在回调里编排 —— 与 v1 胶囊同一接线形状）。
class GuardSceneCard extends StatefulWidget {
  /// 卡片根 Key（度量护栏：存在 / 不存在 / 高度 108 / **无描边无圆角**）。
  static const Key cardKey = Key('guardSceneCard');

  /// 第 [index] 个能量点的 Key（B8 回归；0 = 左、1 = 右）。
  static Key energyDotKey(int index) => Key('guardEnergyDot$index');

  /// L1 草地板 Key（断言「底衬宽 = 卡宽，横向可拉伸」）。
  static const Key backdropKey = Key('guardSceneBackdrop');

  /// 房子位 Key（断言「contain 完整可见 + 宽高比 ≈ 1.7746」）。
  static const Key houseKey = Key('guardSceneHouse');

  /// 战士位 Key（B7：**卡内 L3 常驻**，待机态也在树 —— 旧实现在 L4 战斗层）。
  ///
  /// 键面值沿用 `guardBattleSoldier`（历史名），避免任何按字符串查找的旧探针失联。
  static const Key soldierKey = Key('guardBattleSoldier');

  /// 「开始守卫」按钮 Key（页面级流程测试据此点击）。
  static const Key startButtonKey = Key('guardSceneStartButton');

  /// 「已完成守卫」徽标（B12 新增；claimed 态的右簇方块标识）。
  static const Key claimedBadgeKey = Key('guardSceneClaimedBadge');

  /// 倒计时细线 Key（战斗态卡底；绑 sim 剩余窗口）。
  static const Key countdownKey = Key('guardSceneCountdown');

  /// 状态语义节点 Key（B7：卡内**零文本**，状态只经这里对读屏可见）。
  ///
  /// 测试读法（不需要开启 semantics 树）：
  /// `tester.widget<Semantics>(find.byKey(GuardSceneCard.statusSemanticsKey))
  ///    .properties.label`
  static const Key statusSemanticsKey = Key('guardSceneStatusSemantics');

  /// 当前守卫快照（由页面 `ref.watch(guardTodayProvider)` 传入）。
  final GuardTodayView view;

  /// 「开始守卫」回调；为 null 或 [GuardTodayView.isActionable] 为 false 时不可点。
  final VoidCallback? onStart;

  /// 战局归属的自然日（sim seed 入参；页面传当日 dayKey，fighting 态必传）。
  final String dayKey;

  /// 战局归属的孩子（sim seed 入参；页面传当前 childId，fighting 态必传）。
  final String childId;

  /// 终局回调（Victory / Retreat 后由 L4 战斗层触发，页面接结算卡流）。
  ///
  /// B4 起携带本场实际被偷合计（sim 终局 `stolenSun`，由 L4 field 透传；
  /// 页面据此调 `recordBattleTheft` 落账后再弹结算卡）。卡只转发，不落账。
  final ValueChanged<int>? onBattleFinished;

  /// 调试剧本覆盖（B5a，仅 kDebugMode 有非空值；页面从
  /// `debugGuardBattleScriptOverrideProvider` 读来透传，本卡只转发）。
  final GuardBattleScript? debugScriptOverride;

  /// 开火手柄（B7）：**页面**持有并注入 —— 阳光胶囊在卡外，它要能开火。
  ///
  /// 为 null 时卡内自建一个（保活 widget 级测试与「卡自己也能开火」的旧用法）。
  final GuardBattleHandle? battleHandle;

  const GuardSceneCard({
    super.key,
    required this.view,
    required this.dayKey,
    required this.childId,
    this.onStart,
    this.onBattleFinished,
    this.debugScriptOverride,
    this.battleHandle,
  });

  @override
  State<GuardSceneCard> createState() => _GuardSceneCardState();
}

class _GuardSceneCardState extends State<GuardSceneCard> {
  /// 开火手柄（页面注入则共用，否则自建）。
  late final GuardBattleHandle _battleHandle =
      widget.battleHandle ?? GuardBattleHandle();

  /// 最近一份战斗快照（绑倒计时细线 + 派生战士姿态；fighting 态才有）。
  GuardBattleSnapshot? _battleSnap;

  /// 是否处于「开火后 300ms 攻击帧」窗口（纯演出，不进 sim 时间轴）。
  bool _attacking = false;

  /// 攻击帧窗口的收尾定时器（[kGuardSoldierAttackFlashMs] 后回站立）。
  Timer? _attackTimer;

  @override
  void dispose() {
    _attackTimer?.cancel();
    super.dispose();
  }

  /// 开火被受理 ⇒ 战士切攻击帧 [kGuardSoldierAttackFlashMs] 毫秒（连点则重播）。
  void _flashAttack() {
    _attackTimer?.cancel();
    if (!mounted) return;
    setState(() => _attacking = true);
    _attackTimer = Timer(
      const Duration(milliseconds: kGuardSoldierAttackFlashMs),
      () {
        if (mounted) setState(() => _attacking = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final GuardTodayView view = widget.view;
    final bool actionable = view.isActionable && widget.onStart != null;
    final bool fighting = view.mode == GuardPillMode.fighting;
    // 倒计时细线：绑 sim 剩余窗口（0..1，终局冻结在结束值）。
    final double countdownValue = fighting
        ? (_battleSnap?.remainingWindowMs ?? kGuardBattleWindowMs) /
            kGuardBattleWindowMs
        : 1.0;

    return Semantics(
      key: GuardSceneCard.statusSemanticsKey,
      button: actionable,
      enabled: actionable,
      // 🔴 B7：卡内零文本 ⇒ 状态只经这一层对读屏可见（不占布局，恒不截断）。
      label: _semanticsOf(view, t),
      child: SizedBox(
        key: GuardSceneCard.cardKey,
        // 🔴 卡高不随字号 / 屏宽缩放（设计 §6.4；窄卡只缩卡内元素）。
        height: kGuardSceneCardHeight,
        // 🔴 B8/A4：**不要外框** —— 卡根就是一个 SizedBox：没有 Container、
        // 没有 decoration（无描边、无圆角、无底色）、没有 ClipRRect。
        // 草地板自己就是卡的背景并铺满整张卡（玄参：「不要下面的框」）。
        child: LayoutBuilder(
          // 卡宽由外部撑满（今日页用 OverflowBox 撑成满宽贴边）⇒ 用
          // LayoutBuilder 拿真实宽度，再派生唯一会变的那件事：通道宽度。
          builder: (BuildContext context, BoxConstraints constraints) {
            final GuardCardLayout layout =
                GuardCardLayout(constraints.maxWidth);

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                // ── L1 草地板（程序化、横向无限拉伸 + 透明素材兜底）──────
                const Positioned.fill(
                  child: _GrassBackdrop(key: GuardSceneCard.backdropKey),
                ),

                // ── 房子（contain 完整可见；固定尺寸，跨屏宽逐位不变）────
                // 🔴 B13：点房子 = 打开**玩法说明**弹窗（玄参「点击左侧的花园
                // 在中间弹出来玩法说明介绍」）。Semantics 承担读屏入口文案。
                Positioned.fromRect(
                  rect: layout.houseRect,
                  child: Semantics(
                    button: true,
                    label: t.guard_intro_open,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showGuardIntroDialog(context, t),
                      child: const _HouseSlot(key: GuardSceneCard.houseKey),
                    ),
                  ),
                ),

                // ── 能量点 ×2（B8 回归：房子右侧 / 栅栏上方，亮·灭两态）───
                // 位置由 layout 算，垂直**不越出房顶一个直径** ⇒ 不需要额外
                // 顶部空间（这也是卡高能压到 108 的原因）。
                for (int i = 0; i < 2; i++)
                  Positioned.fromRect(
                    rect: layout.energyDotRect(i),
                    child: _EnergyDot(
                      key: GuardSceneCard.energyDotKey(i),
                      lit: i < view.energyAvailable,
                    ),
                  ),

                // ── L3 战士（B7 常驻 + B8 挪到栅栏外 + B9 裁边后放大）──────
                // 🔴 B9/C2：`soldierRect` 是 **78×78 的布局框**（跑道按它算，
                // 攻击帧的长兵器不许拖累通道）；素材绘制框更宽
                // （[GuardCardLayout.soldierDrawWidth] = 130），由 OverflowBox
                // 以战士中心**居中溢出**：待机 75.9 宽落在框内、攻击 114.4 宽
                // 左右各溢出 ~18pt 也**不被裁**（只用 300ms，压在房子 / 跑道上
                // 正是玄参要的重叠）。三态都按 `BoxFit.fitHeight` 画 ⇒ 高度恒定
                // 78pt，绝不会出现「一开火就变小」。
                Positioned.fromRect(
                  rect: layout.soldierRect,
                  child: SizedBox(
                    key: GuardSceneCard.soldierKey,
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minWidth: layout.soldierDrawWidth,
                      maxWidth: layout.soldierDrawWidth,
                      minHeight: layout.soldierRect.height,
                      maxHeight: layout.soldierRect.height,
                      child: _soldierArt(fighting),
                    ),
                  ),
                ),

                // ── L4 战斗层（fighting 态；ticker 喂 sim，本层不做战局判断）──
                if (fighting)
                  Positioned.fill(
                    child: GuardBattleField(
                      dayKey: widget.dayKey,
                      childId: widget.childId,
                      handle: _battleHandle,
                      onSnapshot: (GuardBattleSnapshot snap) {
                        if (mounted) setState(() => _battleSnap = snap);
                      },
                      // 开火受理 ⇒ 常驻战士切 300ms 攻击帧（战士在本卡渲染）。
                      onFireAccepted: _flashAttack,
                      // B4：终局把 sim 的被偷合计透传给页面（取数链路
                      // sim 报告 → 页面 → 结算卡；本卡只转发、不落账）。
                      onFinished: (int stolenSun) =>
                          widget.onBattleFinished?.call(stolenSun),
                      // B5a：调试剧本覆盖（仅 debug 有非空值；null = 真实派生）。
                      debugScriptOverride: widget.debugScriptOverride,
                    ),
                  ),

                // ── 卡底倒计时细线（战斗态；怪的水平带在它之上，不会压线）──
                if (fighting)
                  Positioned.fromRect(
                    rect: layout.countdownRect,
                    child: SizedBox(
                      key: GuardSceneCard.countdownKey,
                      child: LinearProgressIndicator(
                        value: countdownValue.clamp(0.0, 1.0),
                        minHeight: GuardCardLayout.countdownHeight,
                      ),
                    ),
                  ),

                // ── 右簇：开始钮（战斗态该格留空但**照样占位**）────────────
                // 🔴 B12：claimed（战斗胜利且已收下）⇒ 该格显示「已完成守卫」
                // 徽标（玄参：「战斗完成后，在右边显示已完成守卫的方块标识」）。
                // 图标块不占文本 ⇒ 不违反「卡内零文本」纪律；语义由 Semantics 承担。
                Positioned.fromRect(
                  rect: layout.rightClusterRect,
                  child: actionable
                      ? _startButton(t)
                      : (view.mode == GuardPillMode.claimed
                          // 🔴 B13：徽章含文字（旗子 +「成功守卫」），右簇槽位是
                          // 紧约束（窄卡内容区仅 ~30×40），文字会换行溢出 ——
                          // 用 FittedBox(scaleDown) 让整块徽章**等比缩**进槽位，
                          // 任何语言 / 字号 / 卡宽都不溢出（美术素材到位后整块替换）。
                          ? Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _claimedBadge(t),
                              ),
                            )
                          : const SizedBox.shrink()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── 常驻战士的三态素材 ─────────────────────────────────────────────────

  /// 待机 / 战斗 / 开火三态（玄参 B7 原话逐条落地）：
  /// * 开火后 [kGuardSoldierAttackFlashMs] 内 ⇒ 攻击静态；
  /// * 战斗进行中 ⇒ **静止站立**（idle frame001 定格，不循环 —— 不闲晃）；
  /// * 待机 / 战斗收场（Victory / Retreat）⇒ 待机 19 帧**循环**。
  Widget _soldierArt(bool fighting) {
    final bool over = fighting &&
        _battleSnap != null &&
        _battleSnap!.phaseId != GuardBattlePhase.fighting.id;
    // 🔴 B12：战斗进行中的「站立」改用**专用站立静态** `soldier_stand.webp`
    // （玄参：「攻击情况下，站立动作用单独的那张站立待机图片，而不是动作帧
    // 里面的图片」）。待机动画帧只保留给非战斗态与收场后循环。
    return GuardArt.soldier(
      // 开火瞬间 = 攻击静态；战斗进行中 = 站立静态；其余（含收场后）= 循环。
      attack: _attacking,
      stand: fighting && !_attacking && !over,
      animate: !fighting || over,
    );
  }

  // ── 右簇主按钮（待机态）────────────────────────────────────────────────

  /// 「开始守卫」= **图标钮**（B6 收窄，B7 保留）。
  ///
  /// 🔴 为什么不是文字按钮：`Start guard` 在 en 下曾占 188.8pt（吃掉 53% 卡宽）。
  /// 图标钮不随文案宽度变化 ⇒ 通道宽度在待机 / 战斗两态之间完全一致。
  /// 可读性由卡的 `Semantics.label` 承担（不参与布局，故不会被截断）。
  Widget _startButton(AppLocalizations t) {
    return Semantics(
      button: true,
      label: t.guard_scene_start,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onStart,
        child: Container(
          key: GuardSceneCard.startButtonKey,
          alignment: Alignment.center,
          // 🔴 B13.5：玄参「开始按钮改为40」+ 新素材「开始战斗UI.jpg」（红底
          // 圆角方 + 双太阳矛）—— 素材已在 GuardArt 单点覆盖。**外层 Key 容器
          // 仍占满槽位**：① 命中盒 ≥ 44pt 不缩；② v2 ①「按钮尺寸 ==
          // rightClusterSize」的断言口径不变。要再调大小只动这个 40。
          child: SizedBox(
            width: 40,
            height: 40,
            child: GuardArt.startButton(),
          ),
        ),
      ),
    );
  }

  /// 「已完成守卫」徽标（B12 新增；B13.4 重设计）。
  /// 触发条件 = `mode == claimed`（战斗胜利且奖励已收下）。
  ///
  /// 🔴 **B13.4（玄参）**：去掉绿边圆角外框；旗帜放大到**与战士同尺寸**
  /// （[GuardCardLayout.soldierHeight] = 60）；「成功守卫」文字挪到**右上角**。
  /// 版式 = 64×64 Stack：旗帜贴左下（60×60），文字贴右上（10pt 绿字 +
  /// 白色投影，压在草地 / 花丛上也要可读）。外层调用处的
  /// `Center + FittedBox(scaleDown)` 保留 —— 槽位再窄也只会等比缩、不溢出。
  Widget _claimedBadge(AppLocalizations t) {
    return Semantics(
      label: t.guard_scene_done,
      child: SizedBox(
        key: GuardSceneCard.claimedBadgeKey,
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // 胜利旗帜（10 帧循环动画）—— 与战士同高（60），贴左下。
            Positioned(
              left: 0,
              bottom: 0,
              child: SizedBox(
                width: GuardCardLayout.soldierHeight,
                height: GuardCardLayout.soldierHeight,
                child: GuardArt.claimFlag(),
              ),
            ),
            // 「成功守卫」—— 右上角小标签（白投影兜可读性）。
            Positioned(
              top: 0,
              right: 0,
              child: Text(
                t.guard_scene_done,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3D8B3D),
                  shadows: <Shadow>[
                    Shadow(color: Colors.white, blurRadius: 2),
                    Shadow(color: Colors.white, blurRadius: 2, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 文案映射（复用 v1 胶囊的 6 态口径，absent 不进树、空串兜底）──────────

  /// 读屏标签 = 状态文案（+ 尾标）。卡内**不再渲染文本**，本方法就是状态的
  /// 唯一出口（玄参：「状态信息只保留在 Semantics.label」）。
  static String _semanticsOf(GuardTodayView view, AppLocalizations t) {
    final String label = _labelOf(view, t);
    final String? trailing = _trailingOf(view);
    if (label.isEmpty) return label;
    return trailing == null ? label : '$label（$trailing）';
  }

  static String _labelOf(GuardTodayView view, AppLocalizations t) {
    switch (view.mode) {
      case GuardPillMode.absent:
        return '';
      case GuardPillMode.pendingFree:
        return t.guard_pill_pending_free;
      case GuardPillMode.pendingPaid:
        return t.guard_pill_pending;
      case GuardPillMode.freeRide:
        return t.guard_pill_free_ride;
      case GuardPillMode.fighting:
        return t.guard_pill_fighting;
      case GuardPillMode.claimed:
        return t.guard_pill_claimed;
    }
  }

  static String? _trailingOf(GuardTodayView view) {
    switch (view.mode) {
      case GuardPillMode.pendingPaid:
        // 数字来自常量，不写死 5（PRD 改价时只改 prd_params）。
        return '−$kGuardPayCost ☀';
      case GuardPillMode.claimed:
        return '✓';
      case GuardPillMode.pendingFree:
      case GuardPillMode.freeRide:
      case GuardPillMode.fighting:
      case GuardPillMode.absent:
        return null;
    }
  }
}

/// 房子位：`contain` 完整可见（固定矩形由布局给），缺失回退渐变。
class _HouseSlot extends StatelessWidget {
  const _HouseSlot({super.key});

  @override
  Widget build(BuildContext context) => ClipRect(child: GuardArt.house());
}

/// 能量点（B8 回归）：两态圆点 —— 亮 = 金色实心 + 深金描边，灭 = 空心灰环。
///
/// 🔴 为什么用 `Container` 而不是 `Icon`/`Text`：卡内**零文本**的护栏要求
/// 卡面不出现任何 `Text`（大字号撑破卡的唯一入口）；圆点是纯色块，天然免疫。
class _EnergyDot extends StatelessWidget {
  const _EnergyDot({super.key, required this.lit});

  /// 是否点亮（`index < view.energyAvailable`）。
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? const Color(0xFFFFC93C) : const Color(0x00000000),
        border: Border.all(
          color: lit ? const Color(0xFFE8A600) : const Color(0x66A08C6A),
          width: lit ? 2 : 1.5,
        ),
        boxShadow: lit
            ? const <BoxShadow>[
                BoxShadow(color: Color(0x33E8A600), blurRadius: 6)
              ]
            : null,
      ),
    );
  }
}

/// L1 草地板：**程序化**（渐变 + 草叶纹理），横向可无限拉伸。
///
/// 为什么不用位图：玄参后续可能换美术素材，但此刻必须有一块「怎么拉都不变形、
/// 不会被 cover 裁切」的底 —— 位图在 iPad 992pt 宽卡上只会被裁成巨型局部
/// （B6 诊断：1.77:1 的图铺 7:1 的卡，覆盖率只剩 25%）。
///
/// 第二个职责：house.webp 是带 alpha 的抠图（37.6% 像素全透明），旧实现
/// 透明处直接透出页面底色 —— 这层渐变把兜底做在卡内。
class _GrassBackdrop extends StatelessWidget {
  const _GrassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // 上 = 天空奶油、中 = 草地浅绿、下 = 草地深绿（与今日页奶油绿同族）。
          colors: <Color>[Color(0xFFFFF9E8), Color(0xFFDCEFC4), Color(0xFFB9DDA0)],
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(painter: _GrassBladesPainter()),
    );
  }
}

/// 草叶纹理：按**固定 18pt 步长**沿 x 重复 ⇒ 与卡宽无关、横向可无限拉伸。
class _GrassBladesPainter extends CustomPainter {
  const _GrassBladesPainter();

  /// 草叶间距。单位：pt。
  static const double step = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0x2E4E7A2A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double baseY = size.height - 12;
    int i = 0;
    for (double x = 6; x < size.width; x += step) {
      // 三档高度循环：高度只与序号有关 ⇒ 同一 x 在任何卡宽下都画同一根。
      final double h = switch (i % 3) { 0 => 9.0, 1 => 6.0, _ => 7.5 };
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - h), paint);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _GrassBladesPainter oldDelegate) => false;
}
