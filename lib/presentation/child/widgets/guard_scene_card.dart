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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart'
    show guardUltimateServiceProvider;
import 'package:sunflower_time/core/i18n/app_locale_controller.dart'
    show AppLocaleController;
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattlePhase, GuardBattleScript, GuardBattleSnapshot;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/platform/audio_service.dart'
    show AudioService;
import 'package:sunflower_time/presentation/shared/premium_gate.dart'
    show onGuardUltimateTap;
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeItem, showGoldNoticeDialog;
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_intro_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_energy_bar.dart'
    show GuardUltimateEnergyBar;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show canStartFxStage, guardUltimateCastSfxForLocale;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_help_dialog.dart'
    show showGuardUltimateHelpDialog;

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
  ///
  /// 🔴 注意：此 Key 落在**右簇插槽容器**上（B13.5 口径：命中盒占满槽位
  /// `rightClusterSize × uiScale`，不随内里 40 视觉钮缩），用于「点击 / 命中区」
  /// 断言；**视觉钮尺寸**请用 [startButtonVisualKey]。
  static const Key startButtonKey = Key('guardSceneStartButton');

  /// 「开始守卫」**视觉钮** Key（内层 `SizedBox(40 × uiScale)`；B13.5：
  /// 实际可见的红底圆角方）。平板验收据此确认视觉尺寸随 [uiScale] 放大
  /// （iPad 11″ 40 → 52 / 13″ → 64）。
  static const Key startButtonVisualKey = Key('guardSceneStartButtonVisual');

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

  /// 免费档「第 2 颗能量点」锁标点按弹出的**提示卡** Key（B13.8，C81 模式：
  /// 只提示、不跳转 —— 孩子端无购买入口）。widget 测试断言用。
  static const Key energyLockedHintKey = Key('guardEnergyLockedHint');

  /// 战士受击闪烁的不透明度曲线（**纯函数，可单测**；B13.26）。
  ///
  /// `t ∈ [0,1]`（受击后归一化时长）：
  /// * 起手最深 `1 − [kGuardSoldierHitFlashDepth]`（0.45）；
  /// * 在 [kGuardSoldierHitFlashPulses]（2）个整周期内明暗往返（`cos` 波）；
  /// * 包络 `(1 − t)` 线性回亮 ⇒ 结束时**恰好回到 1.0**（无收尾跳变）；
  /// * 零随机（确定性要求），与怪的受击闪动 `hitFlashAlphaAt` 同构。
  /// 越界 `t` 自动钳在 [0,1]。
  static double soldierHitAlphaAt(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    final double blink = 0.5 +
        0.5 * math.cos(2 * math.pi * kGuardSoldierHitFlashPulses * clamped);
    return 1.0 - kGuardSoldierHitFlashDepth * (1.0 - clamped) * blink;
  }

  /// 当前守卫快照（由页面 `ref.watch(guardTodayProvider)` 传入）。
  ///
  /// 🔴 B13.8 能量档位制：档位从 [GuardTodayView.isPremium] 读（领域层单点
  /// 透传，表现层不摸权益 provider）。免费档（false）：第 1 颗照常（攒满 /
  /// 未攒满态），第 2 颗恒显示**锁标**（不可点亮），点按弹 C81 提示
  /// 卡（B13.9：锁标下的小字已删 —— 卡内回归零文本）；付费档（true）：两颗都照常。
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
  ///
  /// 🔴 B13.26：第二参 = 本场**是否参与过攻击**（开火或大招清怪，L4 field
  /// 判定后透传；🔴 C128：只用大招通关的场不再误标「未参战」）。页面据此
  /// 在 `claim()` 里短路必得阳光。卡只转发。
  final void Function(int stolenSun, bool didAttack)? onBattleFinished;

  /// 调试剧本覆盖（B5a，仅 kDebugMode 有非空值；页面从
  /// `debugGuardBattleScriptOverrideProvider` 读来透传，本卡只转发）。
  final GuardBattleScript? debugScriptOverride;

  /// 开火手柄（B7）：**页面**持有并注入 —— 阳光胶囊在卡外，它要能开火。
  ///
  /// 为 null 时卡内自建一个（保活 widget 级测试与「卡自己也能开火」的旧用法）。
  final GuardBattleHandle? battleHandle;

  /// **平板 UI 放大倍率**（来自 `uiScaleOf`，手机 = 1.0）。
  ///
  /// 🔴 守卫卡此前未走平板适配，iPad 上被拉成全宽窄带、房子/战士/按钮还是
  /// 手机尺寸。本值在今日页由 `uiScaleOf(context)` 注入，使卡内几何与卡高
  /// 等比放大（`GuardCardLayout` 据此乘同倍率）。默认 1.0 ⇒ 手机零回归。
  final double uiScale;

  /// 大招能量快照（由页面 `ref.watch(guardUltimateEnergyProvider)` 注入；
  /// 缺省 empty ⇒ 无 ProviderScope 的旧 widget 测试零改动、能量条显示两格空）。
  final UltimateEnergy ultimateEnergy;

  /// 大招是否已解锁（由页面经中性 helper 派生后注入；缺省 false ⇒ 免费档 🔒）。
  /// 🔴 孩子端只吃 bool，不读任何权益 provider（门控下沉 shared 层）。
  final bool ultimateUnlocked;

  const GuardSceneCard({
    super.key,
    required this.view,
    required this.dayKey,
    required this.childId,
    this.onStart,
    this.onBattleFinished,
    this.debugScriptOverride,
    this.battleHandle,
    this.uiScale = 1.0,
    this.ultimateEnergy = UltimateEnergy.empty,
    this.ultimateUnlocked = false,
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

  /// 战士**受击**演出的起点（战局时间轴 ms，快照钟；null = 不在受击演出中）。
  ///
  /// 🔴 B13.26（玄参 2026-11-16：怪接触战士要有受击反馈）：由 L4 field 的
  /// `theft` 事件触发。时长 [kGuardSoldierHitFlashMs]（800ms）内切受击姿态
  /// `soldier_hit.png` + 闪烁 [kGuardSoldierHitFlashPulses] 次（曲线
  /// [GuardSceneCard.soldierHitAlphaAt]，纯函数、零随机）；到点回站立。
  /// 时钟用**快照 elapsedMs**：战斗进行中每帧经 `onSnapshot` setState 刷新
  /// ⇒ 姿态随钟自动收尾，无需 Timer；终局后快照冻结，演出随之定格（随后
  /// 结算卡上屏，肉眼不可见，可接受）。
  int? _hitStartMs;

  // ── 大招 cast 段（战士本体原位 27 帧 + cast 音轨；玄参 2026-11-20）───────
  /// 是否正在播战士本体释放动作（true 时 `_soldierArt` 切到 `soldierUltimate` 帧）。
  bool _soldierCasting = false;

  /// 重复释放的重播令牌（同一场多次放大招每次都从头播 27 帧）。
  int _castPlayToken = 0;

  /// cast 段「动作播完」/「音轨播完」两路完成信号（两者都到才进 fx 段）。
  bool _castFramesDone = false;
  bool _castAudioDone = false;

  /// cast 音轨计时器（与帧序列同起点、同 [kUltimateFxDurationMs] 长度）。
  ///
  /// 🔴 AudioService 只提供 fire-and-forget 的 `playSfxPaths`，没有完成回调；
  /// 用同长度的 Timer 作为音轨收尾信号，与帧 `onComplete` 走 `Future.wait`
  /// 同款判据（[canStartFxStage]），而不是「猜一个 delay 抢跑 fx 段」。
  Timer? _castAudioTimer;

  /// 2026-11-24 真机反馈 4：cast 第 2 秒提前通知 field 挂 fx 段的计时器。
  ///
  /// 只驱动**表现层**挂 fx widget，不喂 sim、不进 sim 时间轴；sim 的
  /// `castUltimate` 仍在点击后下一帧立即执行。cast 帧继续播满 4s。
  Timer? _fxStartTimer;

  /// fx 段提前启动通知的闸门：一次大招只发一次（timer 与收尾判据共用）。
  bool _fxStageStarted = false;

  @override
  void dispose() {
    _attackTimer?.cancel();
    _castAudioTimer?.cancel();
    _fxStartTimer?.cancel();
    _fxStageStarted = false;
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

  /// 怪到门（`theft` 事件）⇒ 战士受击 [kGuardSoldierHitFlashMs] 毫秒
  /// （受击姿态 + 闪烁；再次受击从头重播 —— 与攻击帧刷新同口径）。
  ///
  /// 音效由 L4 field 自己播（[_playSoldierHitSfx]），本卡只管姿态。
  void _flashSoldierHit() {
    if (!mounted) return;
    setState(() => _hitStartMs = _battleSnap?.elapsedMs ?? 0);
  }

  /// 点战士：门控放行后扣 1 格并请求 sim 清场（中性链路，零权益 token）。
  /// 扣格是 async：先 await 服务落库，再启动 cast 段 + 请战斗层下一帧清场。
  Future<void> _castUltimate() async {
    // cast 段未播完时重复点击：直接吞掉（避免两段演出互相掐断 / 重复扣格）。
    // ⚠️ 这里**不取消** `_fxStartTimer`：本轮 cast 仍在进行，吞掉一次多余点击
    // 不应把「第 2 秒提前挂 fx」推迟到 4s 收尾兜底。真正的状态清理放在
    // `dispose` 与下面「新一轮 cast 真正启动」处（防上一轮残留计时器串场）。
    if (_soldierCasting) return;
    // 🔴 只在**点击时**读 provider（裸 MaterialApp 的旧 widget 测试不点战士 ⇒
    //    不触碰 ProviderScope，零改动通过）。生产容器里正常扣格。
    //    防御：即便中性 helper 在无 ProviderScope 的裸宿主中被直接放行，也只
    //    no-op，不把 StateError 冒泡成 widget 测试失败。
    final ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return;
    }
    await container.read(guardUltimateServiceProvider).spendCell();
    if (!mounted) return;
    // ── cast 段启动：战士本体原位 27 帧 + cast 音轨，同起点、同长 ──────────
    // 新一轮先清上一轮的提前启动计时器 / 闸门（重开战局卡 State 不重建）。
    _fxStartTimer?.cancel();
    _fxStartTimer = null;
    _fxStageStarted = false;
    _castFramesDone = false;
    _castAudioDone = false;
    setState(() {
      _soldierCasting = true;
      _castPlayToken++;
    });
    // 🔴 cast 音轨按生效语言二选一（与 GuardArt.soldierUltimateCast 的帧目录
    // 同一判据）；fx 音轨中英通用，跟着 cast 播完再上树。
    final String castSfx = guardUltimateCastSfxForLocale(
      AppLocaleController.current.languageCode == 'en',
    );
    AudioService.instance.playSfxPaths(<String>[castSfx]);
    _castAudioTimer?.cancel();
    _castAudioTimer = Timer(
      const Duration(milliseconds: kUltimateFxDurationMs),
      _onCastAudioDone,
    );
    // 🔴 2026-11-24 真机反馈 4：cast 第 2 秒就通知 field 挂 fx 段，总演出 6s。
    // 与 cast 音轨 Timer **并列**起跑；不 cancel `_castAudioTimer`（音轨继续到 4s），
    // 也不动 `_soldierCasting`（战士 cast 帧继续播满 4s）。
    _fxStartTimer = Timer(
      const Duration(milliseconds: kUltimateFxCastLeadMs),
      _onFxStartDue,
    );
    // sim 清场请求（下一帧 tick 执行 castUltimate；锚点在 cast 前抓取）。
    _battleHandle.requestUltimate();
  }

  /// cast 帧序列播完（`FrameSequencePlayer.onComplete`）⇒ 记动作完成信号。
  void _onCastFrameDone() {
    _castFramesDone = true;
    _maybeEnterFxStage();
  }

  /// cast 音轨计时到点 ⇒ 记音轨完成信号。
  void _onCastAudioDone() {
    _castAudioDone = true;
    _maybeEnterFxStage();
  }

  /// cast 第 [kUltimateFxCastLeadMs] 到点 ⇒ 通知 field 提前挂 fx 段。
  ///
  /// 🔴 全文件**唯一**的 `_battleHandle.notifyUltimateCastDone()` 发点：
  /// timer 到点走这里，cast 4s 收尾判据也兜底走这里。[_fxStageStarted]
  /// 闸门保证一次大招只通知一次。只驱动表现层，不碰 sim / 不进 sim 时间轴，
  /// 也不停 cast 帧与 cast 音轨（两者继续播满 4s）。
  void _onFxStartDue() {
    if (_fxStageStarted || !mounted) return;
    _fxStageStarted = true;
    _fxStartTimer?.cancel();
    _fxStartTimer = null;
    _battleHandle.notifyUltimateCastDone();
  }

  /// cast 段 4s 收尾判据：**动作播完 + 音轨播完两者都完成**。
  ///
  /// 仅负责把 `_soldierCasting` 收回 false（战士恢复待机）；提前挂 fx 的通知
  /// 由 [_onFxStartDue] 发出，这里只做兜底调用（timer 异常漏发时仍不卡演出）。
  ///
  /// 任一路先到只记信号、不落收尾（玄参「动作/音效被卡断」的根因就是
  /// 旧实现 `Future.delayed(duration~/2)` 抢跑 fx 音轨）。fx 段已在 cast 第 2 秒
  /// 经 [_onFxStartDue] 提前挂树，本判据只做 cast 段 4s 收尾 + 通知兜底。
  void _maybeEnterFxStage() {
    if (!_soldierCasting || !mounted) return;
    if (!canStartFxStage(
      castFramesDone: _castFramesDone,
      castAudioDone: _castAudioDone,
    )) {
      return;
    }
    _castAudioTimer?.cancel();
    setState(() => _soldierCasting = false);
    // 兜底：正常路径 timer 已在第 2 秒发过通知，这里被闸门吞掉；
    // 只有 timer 异常漏发时才会在此补发，保证全文件仍只有一处 notify。
    _onFxStartDue();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final GuardTodayView view = widget.view;
    final bool actionable = view.isActionable && widget.onStart != null;
    final bool fighting = view.mode == GuardPillMode.fighting;
    // 大招能量 + 门控 bool 由页面注入（build 期零 ProviderScope 依赖）——
    // 孩子端只吃实体 + bool，零权益 token。
    final UltimateEnergy ultimateEnergy = widget.ultimateEnergy;
    final bool ultimateUnlocked = widget.ultimateUnlocked;
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
        // 🔴 卡高不随字号 / 屏宽缩放（设计 §6.4；窄卡只缩卡内元素），
        //    但随平板 [uiScale] 放大（iPad 11″ 1.3 / 13″ 1.6）⇒ 卡不再是一条
        //    全宽窄带（见 [GuardCardLayout.cardHeight]）。
        height: kGuardSceneCardHeight * widget.uiScale,
        // 🔴 B8/A4：**不要外框** —— 卡根就是一个 SizedBox：没有 Container、
        // 没有 decoration（无描边、无圆角、无底色）、没有 ClipRRect。
        // 草地板自己就是卡的背景并铺满整张卡（玄参：「不要下面的框」）。
        child: LayoutBuilder(
          // 卡宽由外部撑满（今日页用 OverflowBox 撑成满宽贴边）⇒ 用
          // LayoutBuilder 拿真实宽度，再派生唯一会变的那件事：通道宽度。
          builder: (BuildContext context, BoxConstraints constraints) {
            final GuardCardLayout layout =
                GuardCardLayout(constraints.maxWidth, widget.uiScale);

            return Stack(
              // 🔴 C130（玄参「你不要给我切割」）：卡根不再裁切 —— cast 段绘制框
              // 补偿后约 169.41pt（超出卡高 112，上下各溢出 ~8.5/49pt），光效帧
              // 本就铺满 720² 画布，若 hardEdge 会把光效切出硬边。改 Clip.none
              // 让 cast 光效越界绘制；卡内其余子层全部 Positioned 在界内、
              // 战斗层 / fx 层各自自裁，行为零变化。实测：卡底以下光效带几乎
              // 为空（27 帧 alpha>128 占比 0~5% 淡火花），不会压脏下方统计卡；
              // 卡顶以上还有 ~8.5pt 超出 ListView 视口顶边（卡顶 == 视口顶），
              // 该带仍被视口裁掉 —— 见报告；若玄参目检仍觉顶部有硬边，下一步
              // 是给 ListView 开 clipBehavior: none（本报告已预留该选项）。
              clipBehavior: Clip.none,
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
                      onTap: () => showGuardIntroDialog(
                        context,
                        t,
                        isPremium: widget.view.isPremium,
                      ),
                      child: const _HouseSlot(key: GuardSceneCard.houseKey),
                    ),
                  ),
                ),

                // ── 能量点 ×2（B8 回归：房子右侧 / 栅栏上方，亮·灭两态）───
                // 位置由 layout 算，垂直**不越出房顶一个直径** ⇒ 不需要额外
                // 顶部空间（这也是卡高能压到 108 的原因）。
                // 🔴 B13.8 档位制：免费档第 2 颗不可点亮，点按弹 C81 提示卡（无购买入口）；
                //    付费档两颗照常亮/灭。
                //    🔴 C139：该颗的「锁标」已改为**灰色虚线空槽**，与战士头顶大招能量条的
                //    免费档空槽同一视觉语言。仅显示层变更：免费档权限 / 能量累计 /
                //    点按提示逻辑一概不动（卡内仍零文本）。
                for (int i = 0; i < 2; i++)
                  Positioned.fromRect(
                    rect: layout.energyDotRect(i),
                    child: _EnergyDot(
                      key: GuardSceneCard.energyDotKey(i),
                      lit: !widget.view.isPremium
                          ? (i == 0 && view.energyAvailable >= 1)
                          : i < view.energyAvailable,
                      locked: !widget.view.isPremium && i == 1,
                      uiScale: widget.uiScale,
                      onTap: (!widget.view.isPremium && i == 1)
                          ? () => _showEnergyLockedHint(t)
                          : null,
                    ),
                  ),
                // （B13.9：原「会员双能量」小字已删 —— 卡内零文本纪律恢复，
                //    v3 零文本守卫不再豁免。）

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
                  child: Semantics(
                    button: true,
                    label: ultimateUnlocked
                        ? t.guard_ultimate_energy_semantics(
                            '${ultimateEnergy.filledCells}', '${ultimateEnergy.fractionMin}')
                        : '${t.guard_ultimate_energy_semantics('${ultimateEnergy.filledCells}', '${ultimateEnergy.fractionMin}')} ${t.guard_ultimate_lock_semantics}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 🔴 C62：不出现 onTap: null —— 门控判定全在中性 helper 内；
                      //    非战斗态 onAllowed 为空（P0-04② no-op），但免费档
                      //    任何态点战士仍走买断引导（helper 内部先判门控）。
                      onTap: () {
                        // 🔴 玄参 2026-11-20：待机态点战士 = 弹**居中用法说明卡**
                        // （免费 / 买断都弹，先讲玩法；不是轻提示）；仅战斗态才
                        // 走门控 helper（免费 → 买断引导 / 有能量 → 释放 /
                        // 无能量 → 1s 淡出轻提示）。C62：onTap 恒非 null。
                        if (!fighting) {
                          _showUltimateHelp(t);
                          return;
                        }
                        onGuardUltimateTap(
                          context,
                          hasEnergy: ultimateEnergy.filledCells > 0,
                          onAllowed: _castUltimate,
                        );
                      },
                      child: SizedBox(
                        key: GuardSceneCard.soldierKey,
                        child: OverflowBox(
                          alignment: Alignment.center,
                          // 🔴 C130：cast 段绘制框按实体占比补偿放大到
                          // [GuardCardLayout.ultimateCastPaintHeight]
                          // （390 屏 169.41²，保持正方形画布），使战士实体渲染高
                          // 逐位 = 待机；其余姿态维持原口径（宽 = 横向溢出宽
                          // [GuardCardLayout.soldierDrawWidth]、高 = 布局框高）。
                          // OverflowBox 只放行尺寸、不裁切；越界绘制由卡根
                          // Stack Clip.none 放行（见上）。
                          minWidth: _soldierCasting
                              ? layout.ultimateCastPaintHeight
                              : layout.soldierDrawWidth,
                          maxWidth: _soldierCasting
                              ? layout.ultimateCastPaintHeight
                              : layout.soldierDrawWidth,
                          minHeight: _soldierCasting
                              ? layout.ultimateCastPaintHeight
                              : layout.soldierRect.height,
                          maxHeight: _soldierCasting
                              ? layout.ultimateCastPaintHeight
                              : layout.soldierRect.height,
                          child: _soldierArt(fighting, layout),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── 战士头顶大招能量条（两格 / 百分比 / 点亮 / 🔒，零 token）──
                // 能量条 widget 自己按全卡宽 LayoutBuilder 定位到 soldierRect 上方
                // （GuardCardLayout.ultimateBarRect），与旧能量点并存不复用。
                Positioned.fill(
                  child: IgnorePointer(
                    child: GuardUltimateEnergyBar(
                      energy: ultimateEnergy,
                      unlocked: ultimateUnlocked,
                      uiScale: widget.uiScale,
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
                      // 🔴 B13.26：怪到门（theft）⇒ 战士受击 800ms 姿态 + 闪烁
                      // （战士在本卡渲染，音效由 field 自己播）。
                      onSoldierHit: _flashSoldierHit,
                      // 平板放大倍率透传（与卡同把尺子）。
                      uiScale: widget.uiScale,
                      // B4：终局把 sim 的被偷合计 + 是否参与攻击透传给页面
                      // （取数链路 sim 报告 → 页面 → 结算卡 / claim；本卡只
                      // 转发、不落账）。
                      onFinished: (int stolenSun, bool didAttack) =>
                          widget.onBattleFinished?.call(stolenSun, didAttack),
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
                //
                // 🔴 玄参最终裁定（三套口径收敛）：旗帜**唯一**判据 =
                // 「今天完成过一次守卫」= `status == claimed`，与能量 / 阳光
                // 完全无关。`view.isActionable` 覆盖所有未 claimed 的有贼态
                // （pendingFree / pendingPaid / freeRide）⇒ 一律画可点开始钮；
                // 只有 claimed 走到下面的旗帜分支；fighting ⇒ 留空占位。
                Positioned.fromRect(
                  rect: layout.rightClusterRect,
                  child: actionable
                      ? _startButton(t, widget.uiScale)
                      : (view.mode == GuardPillMode.claimed
                          // 🔴 B13：徽章含文字（旗子 +「成功守卫」），右簇槽位是
                          // 紧约束（窄卡内容区仅 ~30×40），文字会换行溢出 ——
                          // 用 FittedBox(scaleDown) 让整块徽章**等比缩**进槽位，
                          // 任何语言 / 字号 / 卡宽都不溢出（美术素材到位后整块替换）。
                          ? Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _claimedBadge(t, widget.uiScale),
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

  // ── 能量档位提示卡（B13.8 / C81 模式）─────────────────────────────────

  /// 免费档点锁标能量点 → 弹「完整版每天 2 颗能量点」提示卡（B13.9 措辞统一：
  /// 项目标准口径是**完整版**，不叫会员）。
  ///
  /// 🔴 C81 纪律：**只提示、不跳转** —— 孩子端零购买入口（T12 源码守卫钉死，
  /// 本文件连购买页路由字符串都不能出现）。走孩子端统一通知卡壳
  /// `GoldNoticeDialog`（与详情卡锁标提示卡同一先例：锁标徽 + 一句正文、
  /// 没有标题）；文案由本卡（L10nScope 之内）取好传入，`confirmLabel`
  /// 显式传（F157 纪律）。
  void _showEnergyLockedHint(AppLocalizations t) {
    showGoldNoticeDialog(
      context,
      dialogKey: GuardSceneCard.energyLockedHintKey,
      badgeIcon: Icons.lock,
      items: const <GoldNoticeItem>[],
      footerText: t.guard_energy_locked_hint,
      confirmLabel: t.prd_level_detail_ok,
    );
  }

  /// 待机态点战士 → 弹**屏幕居中**的大招用法说明卡（玄参 2026-11-20 拍板：
  /// 「居中卡片 + 知道了按钮」，不是轻提示）。免费 / 买断都弹 —— 先讲玩法，
  /// 买断引导仍只在**战斗态**点战士的路径里（门控下沉白名单文件，口径 12 不变）。
  void _showUltimateHelp(AppLocalizations t) {
    showGuardUltimateHelpDialog(
      context,
      title: t.guard_ultimate_help_title,
      body: t.guard_ultimate_help_body(
        '$kMinPerUltimateCell',
        '$kMaxUltimateCells',
      ),
      confirmLabel: t.guard_ultimate_help_confirm,
      // 仅免费档在正文下方追加灰色小字；买断档不出现（玄参真机反馈 1）。
      premiumHint: widget.view.isPremium ? null : t.guard_ultimate_help_premium_hint,
    );
  }

  // ── 常驻战士的四态素材 ─────────────────────────────────────────────────

  /// 待机 / 战斗 / 开火 / 受击四态（玄参 B7 原话逐条落地 + B13.26 受击）：
  /// * 开火后 [kGuardSoldierAttackFlashMs] 内 ⇒ 攻击静态；
  /// * **受击 [kGuardSoldierHitFlashMs] 内 ⇒ 受击静态 + 闪烁**（受击优先：
  ///   攻击帧进行中同时被贴，按玄参「受击要有反馈」的语义先演受击）；
  /// * 战斗进行中 ⇒ **静止站立**（`soldier_stand.webp` 定格，不循环 —— 不闲晃）；
  /// * 待机 / 战斗收场（Victory / Retreat）⇒ 待机 19 帧**循环**。
  Widget _soldierArt(bool fighting, GuardCardLayout layout) {
    // 🔴 玄参 2026-11-20：cast 段 = **战士本体原位**播 soldier_ultimate 27 帧，
    // 不另起形象、不移到怪物区；播完 onComplete 驱动两段串行推进。
    // 优先级高于攻击 / 受击 / 站立（放大招时不再被其它姿态覆盖）。
    //
    // 🔴 C130（玄参「你不要给我切割」「放大招战士变小了」）：未裁切 720² 画布
    // 经 OverflowBox 放大到 [GuardCardLayout.ultimateCastPaintHeight]，再按
    // [GuardCardLayout.ultimateCastAlignOffset] 平移，使**战士实体中心**逐位
    // 落回 [GuardCardLayout.soldierRect] 中心（实体底边也踩回基线）—— 不因
    // 画布变大而偏移。Transform.translate 只影响绘制、不消耗布局（与 B11
    // 质心配准同一手法）。
    if (_soldierCasting) {
      return Transform.translate(
        offset: layout.ultimateCastAlignOffset,
        child: GuardArt.soldierUltimateCast(
          playToken: _castPlayToken,
          onComplete: _onCastFrameDone,
        ),
      );
    }
    final bool over = fighting &&
        _battleSnap != null &&
        _battleSnap!.phaseId != GuardBattlePhase.fighting.id;
    // 受击窗口判定（快照钟，见 [_hitStartMs]）：800ms 内 ⇒ 姿态 + 闪烁。
    bool hit = false;
    double hitAlpha = 1.0;
    final int? hitStart = _hitStartMs;
    if (fighting && hitStart != null && _battleSnap != null) {
      final int ageMs = _battleSnap!.elapsedMs - hitStart;
      if (ageMs >= 0 && ageMs < kGuardSoldierHitFlashMs) {
        hit = true;
        hitAlpha =
            GuardSceneCard.soldierHitAlphaAt(ageMs / kGuardSoldierHitFlashMs);
      }
    }
    // 🔴 B12：战斗进行中的「站立」改用**专用站立静态** `soldier_stand.webp`
    // （玄参：「攻击情况下，站立动作用单独的那张站立待机图片，而不是动作帧
    // 里面的图片」）。待机动画帧只保留给非战斗态与收场后循环。
    // 🔴 B13.26：**恒包 Opacity**（不闪时 opacity = 1.0）—— 不翻转树结构
    // （B13.20c 教训：条件挂层会让 _GuardSequence State 重建、闪一帧兜底色块）。
    return Opacity(
      opacity: hitAlpha,
      child: GuardArt.soldier(
        // 开火瞬间 = 攻击静态；受击 = 受击静态（优先）；战斗进行中 = 站立
        // 静态；其余（含收场后）= 循环。
        hit: hit,
        attack: _attacking,
        stand: fighting && !_attacking && !hit && !over,
        animate: !fighting || over,
      ),
    );
  }

  // ── 右簇主按钮（待机态）────────────────────────────────────────────────

  /// 「开始守卫」= **图标钮**（B6 收窄，B7 保留）。
  ///
  /// 🔴 为什么不是文字按钮：`Start guard` 在 en 下曾占 188.8pt（吃掉 53% 卡宽）。
  /// 图标钮不随文案宽度变化 ⇒ 通道宽度在待机 / 战斗两态之间完全一致。
  /// 可读性由卡的 `Semantics.label` 承担（不参与布局，故不会被截断）。
  ///
  /// 🔴 B13.21（玄参 2026-11-14「开始攻击的按钮下面写上 4 个小字，开始守卫」）：
  /// 图标正下方补一行 **9pt 小字**（复用 `guard_scene_start` 文案，zh「开始守卫」
  /// 逐字不动）。⚠️ 小字**不参与通道宽度**：外层槽位容器（[GuardSceneCard.startButtonKey]）
  /// 与图标槽（[GuardSceneCard.startButtonVisualKey]）尺寸逐位不变 —— v2 ①
  /// 「开始钮尺寸 == rightClusterSize」断言与 tablet 倍率测试口径都不受影响；
  /// en 文案偏宽由 `FittedBox(scaleDown)` 就槽宽收缩（绝不溢出、绝不换行撑高）。
  Widget _startButton(AppLocalizations t, double uiScale) {
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
          // 🔴 平板：40 按 [uiScale] 放大（iPad 11″ → 52 / 13″ → 64），与卡同倍率。
          // 🔴 B13.21 补丁：Column（图标 + 小字）整体包 `FittedBox(scaleDown)`
          // —— 窄卡（320 屏）下槽位缩到 54.4pt，56pt 的「图标 + 小字」原生
          // 会溢出 1.6px（⑤ 溢出护栏当场抓住）；FittedBox 让整组内容就槽高
          // 等比收缩（390 卡 / 平板槽位充足 ⇒ 不缩、尺寸逐位不变）。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  key: GuardSceneCard.startButtonVisualKey,
                  width: 40 * uiScale,
                  height: 40 * uiScale,
                  child: GuardArt.startButton(),
                ),
                SizedBox(height: 3 * uiScale),
                // 提示小字：字号随 uiScale（与图标同倍率，手机 1.0 逐位零回归）。
                Text(
                  t.guard_scene_start,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9 * uiScale,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8A5A00),
                  ),
                ),
              ],
            ),
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
  Widget _claimedBadge(AppLocalizations t, double uiScale,
      {bool isFreeRide = false}) {
    return Semantics(
      label: isFreeRide ? t.guard_pill_free_ride : t.guard_scene_done,
      child: SizedBox(
        key: GuardSceneCard.claimedBadgeKey,
        // 🔴 平板：徽章整块按 [uiScale] 放大（iPad 11″ 64 → 83.2 / 13″ → 102.4），
        // 与卡同倍率；右簇插槽也同步放大 ⇒ FittedBox(scaleDown) 仍只做安全钳。
        width: 64 * uiScale,
        height: 64 * uiScale,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // 胜利旗帜（10 帧循环动画）—— 与战士同高（60），贴左下。
            Positioned(
              left: 0,
              bottom: 0,
              child: SizedBox(
                width: GuardCardLayout.soldierHeight * uiScale,
                height: GuardCardLayout.soldierHeight * uiScale,
                child: GuardArt.claimFlag(),
              ),
            ),
            // 「成功守卫」—— 右上角小标签（白投影兜可读性）。
            // 🔴 文字不动 [uiScale]：平板已由系统 textScaler 等比放大，避免双乘。
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

/// C139：免费档第 2 颗能量点的「灰色虚线空槽」参数 —— 与战士头顶大招能量条
/// 免费档完全一致（灰 0xFF9E9E9E / dash 4-3 / 线宽 1.2）。
const Color _kLockedEnergyDashColor = Color(0xFF9E9E9E);
const double _kLockedEnergyDashWidth = 4.0;
const double _kLockedEnergyDashSpace = 3.0;
const double _kLockedEnergyDashStroke = 1.2;

/// 能量点（B8 回归）：两态圆点 —— 亮 = 金色实心 + 深金描边，灭 = 空心灰环。
///
/// 🔴 B13.8 档位制：[locked] = 免费档的第 2 颗 —— C139 起改画**灰色虚线空槽**
/// （与战士头顶能量条免费档同款灰 / dash 4-3 / 线宽 1.2），不再是锁标；仍可点
/// （弹 C81 提示卡），其余两态不可点。权限 / 能量规则完全不变。
///
/// 🔴 为什么圆点本体不用 `Icon`/`Text`：卡内文本护栏要求圆点本身不出现 `Text`
/// （大字号撑破卡的唯一入口）；虚线由 [CustomPaint] 纯绘制，天然免疫。
class _EnergyDot extends StatelessWidget {
  const _EnergyDot({
    super.key,
    required this.lit,
    this.locked = false,
    this.uiScale = 1.0,
    this.onTap,
  });

  /// 是否点亮（免费档 = 第 1 颗攒满；付费档 = `index < energyAvailable`）。
  final bool lit;

  /// 锁标态（B13.8：免费档第 2 颗；灰环 + 🔒，可点）。
  final bool locked;

  /// **平板 UI 放大倍率**（手机 = 1.0）：虚线描边按此放大，与卡同倍率。
  final double uiScale;

  /// 点按回调（仅锁标态非 null）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // C139：免费档第 2 颗（locked）只画灰色虚线空槽，与头顶能量条免费档同款；
    // 不再叠锁标、也不画灰环实心壳（避免「虚线 + 实线」双重轮廓）。亮/灭两态原样。
    Widget dot = locked
        ? CustomPaint(
            painter: _DashedEnergyDotPainter(
              color: _kLockedEnergyDashColor,
              strokeWidth: _kLockedEnergyDashStroke * uiScale,
              dashWidth: _kLockedEnergyDashWidth * uiScale,
              dashSpace: _kLockedEnergyDashSpace * uiScale,
            ),
          )
        : DecoratedBox(
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
    if (onTap != null) {
      // 免费档第 2 颗可点（C81 ①：只弹提示卡）；热区即整个点槽位。逻辑未变。
      dot = Semantics(
        button: true,
        enabled: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: dot,
        ),
      );
    }
    return dot;
  }
}

/// C139：免费档第 2 颗能量点的虚线圆画师（Flutter 无内置 dashed border，不新增依赖）。
///
/// 与 `guard_ultimate_energy_bar` 的虚线画师同构（RRect + extractPath 逐段），
/// 但本处槽位是正方形 ⇒ radius = 短边/2 即为正圆虚线。
class _DashedEnergyDotPainter extends CustomPainter {
  const _DashedEnergyDotPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.shortestSide / 2 - strokeWidth / 2;
    if (radius <= 0) return;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset(strokeWidth / 2, strokeWidth / 2) &
              Size(size.width - strokeWidth, size.height - strokeWidth),
          Radius.circular(radius),
        ),
      );
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedEnergyDotPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashWidth != oldDelegate.dashWidth ||
      dashSpace != oldDelegate.dashSpace;
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
