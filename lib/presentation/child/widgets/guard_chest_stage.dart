/// 花园守卫 · **宝箱演出层**（Guard-B13.11 T03 / B13.12 改落点；设计 §7.3 / §7.4 / §7.5）。
///
/// ## 它负责什么（以及刻意不负责什么）
/// 三个纯表现阶段，**一行存档都不写**：
/// ```text
/// drop    600ms   从卡顶之外（边长+余量 = 78pt）加速落进卡内 → 轻微回弹 → 落定（kGuardChestDropMs），
///                 **落地那一刻**（fall 段结束，value 跨过
///                 [kGuardChestDropFallRatio]，240ms —— 画面砸地的那一帧）播
///                 **落地音效** `guardChestLand`（音量 [kGuardChestLandVolume] = 0.5）
/// idle    无限    呼吸 ±2pt / 轻转 ±1.5°、下方「点一下打开」、**卡内任意处**可开、
///                 8s 无操作自动开（kGuardChestAutoOpenMs）
/// opening 5000ms  30 帧依次播（166.7ms/帧），**同时**播开箱音效（音量 0.5），
///                 播完停末帧并回调 [GuardChestStage.onOpened]
/// ```
/// 🔴 **经济结果与本层无关**：宝箱档位 / 碎片 / 种子在 `GuardService.resolve()`
/// 时已一次性落盘（见 `domain/services/guard_chest.dart`）。本层只决定「演哪个档
/// 的动画」，即便演出重复播放（重进 App 再进今日页）也不会多发一片碎片。
///
/// ## 🔴 为什么「只占场景卡那一块」（B13.12，玄参第六轮反馈）
/// 玄参原话：「宝箱现在设计的是浮现在整个屏幕画面的最上面，我想的是只出现在
/// **小怪进攻的位置**就可以了，不用全屏。」
///
/// 「小怪进攻的位置」在几何上**就是场景卡**：`kGuardSceneCardHeight` = 112pt，
/// 而战斗层 `GuardBattleField` 占满整张卡面（L4），小怪的车道 / 到门判定全部
/// 发生在卡内（见 `GuardCardLayout.channelLeft`）。故本层的口径改为：
/// * 本 widget 自身就是一个 **112pt 高的「卡」**（宽 = 父给的卡宽）—— 落地、
///   呼吸、开箱全部在这块矩形内完成；
/// * 弹层仍走 `showGeneralDialog`（`PopScope(canPop:false)` + 不可关 barrier
///   才是「必演不可跳过」的唯一可靠载体，见下），但页面侧把本层**塞进
///   `Positioned.fromRect(场景卡的真实矩形)`** 里，且外面再套一层 `ClipRect`：
///   卡外既不画、也不吃点击。
///
/// 于是既保住了「不可跳过」的路由语义，又满足「只在卡内演」的观感 ——
/// 全屏铺满 + 全屏热区（旧实现）已**删除**，不再存在第二条摆放口径。
///
/// ## 落点为什么在「插旗的位置」（B13.14，玄参第九轮反馈）
/// 玄参原话（2026-11-12 截图反馈）：「宝箱的掉落点放到**插旗的位置**就行了。」
///
/// 「插旗的位置」= 右簇槽位（`GuardCardLayout.rightClusterRect`）—— 战斗胜利
/// 领取后「已完成守卫」旗帜徽章就在这一格。故落点口径定为：
/// * **宝箱中心 = `rightClusterRect.center` − 15pt**（B13.15 玄参「太靠右了，
///   再往左挪 15pt」；390 卡实测 `chest.left = 302`，宝箱占 [302, 368]）；
/// * 钳制放宽到「不出卡」（`cardWidth − side`）；
/// * 演出期（resolved 态）右簇槽位渲染 `SizedBox.shrink()`（既不是开始钮也
///   不是旗帜），宝箱盖在这一格上**零视觉冲突**（B13.13 已核实
///   `guard_scene_card.dart:334` 的三分支）。
///
/// 沿革：B13.12 对齐 `soldierRect.right`（218.17，玄参「太靠中间」）→
/// B13.13 对齐 `channelRight`（276）→ B13.14 对齐右簇槽位中心（312）→
/// **B13.15 左移 15pt（302）+ 缩小 66 + 贴地 96**。
///
/// 卡内几何**全部派生**自 `GuardCardLayout`（唯一真源，与卡的绘制 / 战斗层共用）：
/// * 底边 = 卡底 112 − 16（B13.15「好像没有落地」：24 → 16，下移 8pt）= **96**
///   （草地之上、「点一下打开」提示带 y ≥ 98 之下）。
/// ⇒ 宝箱就出现在「胜利旗帜会插上的那一格」略偏左，贴着地面，而不是随手居中。
///
/// ## 🔴 不可跳过（玄参裁定）
/// 没有「跳过」按钮、没有长按 / 双击捷径、`PopScope(canPop: false)` 由
/// [showGuardChestOverlay] 统一兜住（系统返回键 / 返回手势无效）。
/// 孩子只有两条路：**点一下卡内** 或 **等 8 秒**。
///
/// ## 测试纪律（踩过的坑，写死在这里）
/// idle 期有**无限**呼吸 `AnimationController` + 8s `Timer` ⇒ 调用方
/// **绝不 `pumpAndSettle()`**（会一路推进到 5s 播完、断言全乱），统一定长
/// `pump(Duration)`。[GuardChestStage.dispose] 里 `_autoOpenTimer?.cancel()`
/// 是硬要求（漏了 = `tester` 结束时报 "A Timer is still pending"）。
library guard_chest_stage;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

/// 音效播放入口（可注入）。
///
/// 为什么不在本文件里直接 `AudioService.instance.playSfx`：headless 测试环境没有
/// 音频后端，且「音量到底传了 0.5 还是 0.6」是玄参拍板过的口径（Q-04）——
/// 留一个可注入的缝，测试才能**逐位**钉住 `volume`，而不是「看起来调用了」。
typedef GuardChestSfxPlayer = void Function(AudioCue cue, {double volume});

/// 宝箱演出的三个阶段（纯表现层，不落盘）。
enum GuardChestPhase {
  /// 从卡顶之外落进卡内（[kGuardChestDropMs]）。
  drop,

  /// 落地静止 + 呼吸 + 等待点击 / 8s 超时。
  idle,

  /// 开箱动画（[kGuardChestOpenMs]）+ 开箱音效。
  opening,
}

/// 宝箱演出层（drop / idle / opening 三阶段 + **卡内**热区 + 8s 自动开）。
///
/// 🔴 本 widget 的尺寸契约 = **一张场景卡**：宽 = 父约束的卡宽、高恒
/// [kGuardSceneCardHeight]（112pt），并在父约束里**顶部对齐**。所有内部几何
/// 都按这块矩形算（见 [chestRectOf]），因此它既可以塞进 `Positioned.fromRect`
/// 的弹层里，也可以被单测直接挂在 `Scaffold.body` 里（此时它就是屏幕顶部一条
/// 112pt 的带子）。
class GuardChestStage extends StatefulWidget {
  /// 本层根 Key（页面级测试断言「宝箱演出已上屏」+ 量「只占卡那一块」）。
  ///
  /// 它挂在**卡矩形本体**上（宽 × 112），不是全屏 —— 这正是 B13.12 的口径。
  static const Key stageKey = Key('guardChestStage');

  /// **静止宝箱本体** Key（`drop` / `idle` 期的静态图）。
  ///
  /// 🔴 开箱动画起播后本节点**消失**（换成 [openPlayerKey]）—— 测试据此断言
  /// 「宝箱态已结束」，不再靠「图片还在不在」这种模糊判据。
  static const Key chestKey = Key('guardChestBox');

  /// 「点一下打开」提示 Key（idle 期淡入）。
  static const Key tapHintKey = Key('guardChestTapHint');

  /// 高级宝箱角标 Key（普通档不渲染）。
  static const Key premiumBadgeKey = Key('guardChestPremiumBadge');

  /// 开箱动画播放器 Key（`opening` 期）。
  static const Key openPlayerKey = Key('guardChestOpenPlayer');

  /// **卡内**点击热区 Key（`behavior: opaque`，点卡内任意处都能开）。
  ///
  /// 🔴 B13.12：热区 = 卡矩形。卡外点击既不开箱、也不穿透（弹层的
  /// `ModalBarrier` 吸收），见 [showGuardChestOverlay]。
  static const Key tapCatcherKey = Key('guardChestTapCatcher');

  /// 演哪一档（普通 / 高级）。**只影响素材与角标**，不影响任何奖励数值。
  final GuardChestTier tier;

  /// 页级 scope 内解析好的文案（dialog 上下文在页级 `L10nScope` 之外，
  /// 与 `guard_result_card.dart` 同因：文案必须由调用方传进来）。
  final AppLocalizations l10n;

  /// 30 帧播完（= 5s 到点）时**恰好一次**。
  ///
  /// 调用方负责收场（页面：`Navigator.pop()` → 弹结算卡）。本层不做导航：
  /// 它也可能被单独挂在 widget 测试的普通 `Scaffold` 里（没有可 pop 的路由）。
  final VoidCallback onOpened;

  /// 音效播放入口；null ⇒ [AudioService.instance] 的 `playSfx`。
  final GuardChestSfxPlayer? playSfx;

  /// 是否启用 8s 无操作自动开箱（生产恒 true；测试可关以断言「不点就不开」）。
  final bool autoOpen;

  const GuardChestStage({
    super.key,
    required this.tier,
    required this.l10n,
    required this.onOpened,
    this.playSfx,
    this.autoOpen = true,
  });

  /// 落下阶段的纵向位移（pt）。纯函数式推导（`t ∈ [0,1]` 为
  /// [kGuardChestDropMs] 的进度），便于逐帧断言「单调上升 + 落定归零」。
  ///
  /// 三段：
  ///  · `t < 0.40`（240ms）：从 [kGuardChestCardDropStartDy]（−78）**加速**落到 0
  ///    （二次曲线，末尾速度最大 —— 自由落体观感）；
  ///  · `0.40 ≤ t < 0.65`（240→390ms，150ms）：一次轻微回弹（正弦半波，
  ///    最大抬升 [kGuardChestDropBouncePt]，远小于 78pt 的落差）；
  ///  · `t ≥ 0.65`：归零收尾（剩下的 210ms 里叠落定挤压，见 [squashScale]）。
  static double dropOffsetDy(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    if (clamped < kGuardChestDropFallRatio) {
      final double p = clamped / kGuardChestDropFallRatio;
      return kGuardChestCardDropStartDy * (1 - p * p);
    }
    if (clamped < kGuardChestDropBounceEndRatio) {
      final double p = (clamped - kGuardChestDropFallRatio) /
          (kGuardChestDropBounceEndRatio - kGuardChestDropFallRatio);
      return -kGuardChestDropBouncePt * math.sin(math.pi * p);
    }
    return 0;
  }

  /// 落地挤压：回弹段横向轻微「蹲一下」（1.0 → 1.06 → 1.0），落定后不再变。
  ///
  /// 只改**横向**缩放（纵向由回弹位移负责），两者叠加才是「踩到地上」的观感。
  static double squashScale(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    if (clamped < kGuardChestDropFallRatio) return 1.0;
    if (clamped >= kGuardChestDropBounceEndRatio) return 1.0;
    final double p = (clamped - kGuardChestDropFallRatio) /
        (kGuardChestDropBounceEndRatio - kGuardChestDropFallRatio);
    return 1 + 0.06 * math.sin(math.pi * p);
  }

  /// 宝箱方框边长（**卡内口径**）。单位：pt。
  ///
  /// = [kGuardChestCardBoxSide]（66，B13.15 缩小）× `GuardCardLayout.scale`
  /// ⇒ 宽卡 **66** / 窄卡（卡宽 ≤ 380）×0.85 = **56.1**，与卡内其他元素
  /// 同一缩法（「只缩元素、不缩卡高」）。
  static double boxSideOf(double cardWidth) =>
      kGuardChestCardBoxSide * GuardCardLayout(cardWidth).scale;

  /// 宝箱静止时的**底边** y（卡内局部坐标）。单位：pt。
  ///
  /// = 卡高 112 − [kGuardChestCardBottomInset] 16 = **96**（B13.15 贴地：
  /// 原 88 太高「像没落地」）—— 草地上、卡底「点一下打开」提示带（y ≥ 98）
  /// 之下，箱子像「蹲在花园地上」。
  static double boxBottomOf() =>
      kGuardSceneCardHeight - kGuardChestCardBottomInset;

  /// 宝箱静止时的方框（**卡内局部坐标**，`+x` 右、`+y` 下）。
  ///
  /// 横向（B13.14/B13.15）：**中心 = `rightClusterRect.center` − 15pt** =
  /// 「插旗的位置」（战斗胜利领取后旗帜徽章所在格）再向左挪 15pt
  /// （[kGuardChestCardCenterShiftPt]，玄参裁定「太靠右了」），并钳到不出卡
  /// （`cardWidth − side`）。390 卡实测：`Rect.fromLTWH(302, 30, 66, 66)`
  /// （沿革：218.17 → 276 → 312 → 302；边长 76 → 66，底边 88 → 96 贴地）。
  /// 演出期右簇槽位为空（resolved 态渲染 `SizedBox.shrink()`），盖过无冲突。
  static Rect chestRectOf(double cardWidth) {
    final GuardCardLayout layout = GuardCardLayout(cardWidth);
    final double side = boxSideOf(cardWidth);
    final double maxLeft = math.max(cardWidth - side, 0);
    double left = layout.rightClusterRect.center.dx -
        kGuardChestCardCenterShiftPt -
        side / 2;
    if (left > maxLeft) left = maxLeft;
    if (left < 0) left = 0;
    return Rect.fromLTWH(left, boxBottomOf() - side, side, side);
  }

  /// 「点一下打开」提示带（**卡内局部坐标**）。
  ///
  /// 🔴 B13.15：宝箱底边贴地（96）后卡底只剩 16pt（含草地带 10），原派生式
  /// （inset − padBottom − 2 = 4pt）装不下 10pt 文案 ⇒ 改为**固定贴卡底**：
  /// y = 99，高 10（y ∈ [99, 109]，底距卡底 3pt），与箱底留 3pt 间隙；
  /// 跨过倒计时细线（y=102）与草地上部 —— 观感是「插在草地上的小牌子」，
  /// 棕色 700 字压浅绿草地可读（渲染层 FittedBox scaleDown 兜住 en 长文案）。
  static Rect hintRectOf(double cardWidth) {
    final Rect chest = chestRectOf(cardWidth);
    return Rect.fromLTWH(
      chest.left,
      kGuardSceneCardHeight - 13,
      chest.width,
      10,
    );
  }

  @override
  State<GuardChestStage> createState() => _GuardChestStageState();
}

class _GuardChestStageState extends State<GuardChestStage>
    with TickerProviderStateMixin {
  /// 落下控制器（600ms，一次性）。
  late final AnimationController _dropCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kGuardChestDropMs),
  );

  /// 呼吸控制器（1.6s/圈，idle 起无限循环）。
  late final AnimationController _breathCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kGuardChestIdleBreathMs),
  );

  /// 8s 无操作自动开箱（🔴 `dispose` 必须 cancel）。
  Timer? _autoOpenTimer;

  /// 当前阶段（只有这三个值；「结算卡」是页面的事，本层不认识）。
  GuardChestPhase _phase = GuardChestPhase.drop;

  /// 开箱闸门：点击 / 超时 / 重复点击都收敛到同一次 [_open]（幂等，§7.4）。
  bool _opening = false;

  /// 播完闸门：[onOpened] 只回调一次（`AnimationController` 的 completed 在某些
  /// 重建路径上可能重复到达，双保险）。
  bool _finished = false;

  /// 提示是否已「亮起」（`AnimatedOpacity` 负责 0.9s 淡入，无需额外 Timer）。
  bool _hintShown = false;

  /// 帧列表（AssetManifest 实测；未解析完 = 空 ⇒ 先显示静态图）。
  List<String> _frames = const <String>[];

  @override
  void initState() {
    super.initState();
    _dropCtrl.addStatusListener(_onDropStatus);
    // 🔴 落地音效的触发器（B13.13）：挂在**逐帧** listener 上 —— fall 段结束
    //    （value 跨过 [kGuardChestDropFallRatio]，240ms）就是视觉「砸到地上」
    //    的那一帧，音效必须播在这里。不能挂在 statusListener 的 completed 上：
    //    那是 600ms（回弹 + 收尾都走完），声音会比画面晚 360ms —— 玄参真机
    //    实测「落地声音慢了一些」的根因。
    _dropCtrl.addListener(_onDropTick);
    _dropCtrl.forward();
    // 🔴 8s 从**挂载**起算（不是「落地后起算」）：玄参的语义是「宝箱出现后
    //    8 秒没人理就自己开」。多算掉的 600ms 落在「箱子还在掉」的窗口里，
    //    对孩子完全无感；从落地起算反而会让「自动开」比设计晚 0.6s。
    if (widget.autoOpen) {
      _autoOpenTimer = Timer(
        const Duration(milliseconds: kGuardChestAutoOpenMs),
        _open,
      );
    }
    unawaited(_loadFrames());
  }

  /// 解析本档帧列表并预热（开箱那一刻不该再等解码）。
  ///
  /// `resolveFxFrames` 自带三级回退（清单实测 → 契约推导 30 帧 → 空），
  /// 因此 [_frames] 解析完成后**必然非空**（`kGuardChestFrameCount` = 30 > 0）；
  /// 这正是不需要「开箱兜底定时器」的原因 —— 与「多留一个 Timer 会让 widget
  /// 测试报 pending timer」的教训做权衡后的选择。
  Future<void> _loadFrames() async {
    final List<String> frames = await GuardArt.chestFrames(widget.tier);
    if (!mounted) return;
    setState(() => _frames = frames);
    if (frames.isNotEmpty) unawaited(precacheFxFrames(context, frames));
  }

  /// 落地音效是否已播（`_onDropTick` 的单次闸门；value 跨阈值可能连续多帧触发）。
  bool _landSfxPlayed = false;

  /// 逐帧监听：`drop` 期 value 跨过 fall 段终点（0.40 × 600ms = **240ms**）的
  /// 那一帧播**落地音效** —— 画面上箱子刚好砸到地（之后是 150ms 轻微回弹）。
  ///
  /// 🔴 B13.13 音画对齐：旧实现播在 completed（600ms），玄参真机实测
  /// 「落地声音慢了一些」—— 360ms 的差值就是回弹 + 收尾两段。本方法在
  /// 240ms 播，误差 ≤ 1 帧（16ms）。
  void _onDropTick() {
    if (_landSfxPlayed || _phase != GuardChestPhase.drop) return;
    if (_dropCtrl.value < kGuardChestDropFallRatio) return;
    _landSfxPlayed = true;
    // 音量 0.5（[kGuardChestLandVolume]，2026-11-12 玄参 B13.13 裁定：
    // 落地音与开箱音统一压到 0.5，首版的 1.0 真机听感偏大）。
    // 走可注入的 [GuardChestSfxPlayer] 接缝，测试逐位钉住音量。
    (widget.playSfx ?? AudioService.instance.playSfx)(
      AudioCue.guardChestLand,
      volume: kGuardChestLandVolume,
    );
  }

  void _onDropStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted || _phase != GuardChestPhase.drop) return;
    setState(() {
      _phase = GuardChestPhase.idle;
      // 提示 0.9s 淡入（§7.4）—— 不额外开 Timer，交给 `AnimatedOpacity`。
      _hintShown = true;
    });
    _breathCtrl.repeat();
  }

  /// 点击 / 超时 / 重复点击的**唯一**入口（幂等）。
  void _open() {
    if (_opening || _finished) return;
    _opening = true;
    _autoOpenTimer?.cancel();
    _autoOpenTimer = null;
    _breathCtrl.stop();
    if (!mounted) return;
    setState(() => _phase = GuardChestPhase.opening);
    // 🔴 音画同时起播（§7.5）：音量 0.5（Q-04 已裁定），与 5s 动画同一刻。
    (widget.playSfx ?? AudioService.instance.playSfx)(
      AudioCue.guardChestOpen,
      volume: kGuardChestOpenVolume,
    );
  }

  /// 30 帧播完（= 5s）→ 停末帧 + 回调一次。
  void _onOpenComplete() {
    if (_finished) return;
    _finished = true;
    widget.onOpened();
  }

  @override
  void dispose() {
    // 🔴 硬要求：不 cancel 会让 widget 测试报 "A Timer is still pending"。
    _autoOpenTimer?.cancel();
    _dropCtrl.removeStatusListener(_onDropStatus);
    _dropCtrl.removeListener(_onDropTick);
    _dropCtrl.dispose();
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 兜底宽度：极少数宿主（未给有限宽约束）时退回屏宽，绝不让 LayoutBuilder
    // 拿到 infinity 去算几何。
    final double screenWidth = MediaQuery.sizeOf(context).width;
    return Material(
      // 透明 Material：让文字 / 图标有默认的 DefaultTextStyle 与主题，
      // 同时**不遮住花园**（玄参要「宝箱掉在菜地里」的观感）。
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double cardWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : screenWidth;
          final Rect chest = GuardChestStage.chestRectOf(cardWidth);
          final Rect hint = GuardChestStage.hintRectOf(cardWidth);
          final bool opening = _phase == GuardChestPhase.opening;

          // 🔴 尺寸契约：**一张场景卡**（宽 = 卡宽、高恒 112），在父约束里顶部对齐。
          //    弹层那边用 `Positioned.fromRect(场景卡矩形)` 把它摆到卡的位置。
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: GuardChestStage.stageKey,
              width: cardWidth,
              height: kGuardSceneCardHeight,
              // 🔴 严格卡内：回弹 / 呼吸 / 高级档光晕任何溢出都不许画到卡外。
              child: ClipRect(
                child: GestureDetector(
                  // 热区（§7.4）**只在卡矩形内**：3~8 岁的孩子不会精确点到箱子上，
                  // 但也不许一点就把卡外的今日页互动堵住（B13.12）。
                  key: GuardChestStage.tapCatcherKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: _open,
                  child: Stack(
                    children: <Widget>[
                      // 宝箱本体（落下 → 静止；开箱起播后整体让位给播放器）。
                      if (!opening)
                        Positioned.fromRect(
                          rect: chest,
                          child: AnimatedBuilder(
                            animation: Listenable.merge(
                              <Listenable>[_dropCtrl, _breathCtrl],
                            ),
                            builder: (BuildContext context, Widget? child) {
                              final bool dropping =
                                  _phase == GuardChestPhase.drop;
                              final double dy = dropping
                                  ? GuardChestStage.dropOffsetDy(_dropCtrl.value)
                                  : 0;
                              final double squash = dropping
                                  ? GuardChestStage.squashScale(_dropCtrl.value)
                                  : 1;
                              // 呼吸：±2pt 上下浮动 + 轻微旋转（§7.4；仅观感）。
                              final double breathe = _phase == GuardChestPhase.idle
                                  ? _breathCtrl.value
                                  : 0;
                              final double bob =
                                  -2 * math.sin(2 * math.pi * breathe);
                              final double tilt = 1.5 *
                                  math.pi /
                                  180 *
                                  math.sin(2 * math.pi * breathe);
                              return Transform.translate(
                                offset: Offset(0, dy + bob),
                                child: Transform.rotate(
                                  angle: tilt,
                                  child: Transform.scale(
                                    scaleX: squash,
                                    scaleY: 2 - squash,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: _ChestBox(
                              key: GuardChestStage.chestKey,
                              tier: widget.tier,
                              side: chest.width,
                              l10n: widget.l10n,
                            ),
                          ),
                        ),
                      // 「点一下打开」（0.9s 淡入；**无倒计时数字** —— 8s 自动开
                      // 对孩子应是「惊喜」而不是「倒计时压力」）。
                      if (!opening)
                        Positioned.fromRect(
                          rect: hint,
                          child: AnimatedOpacity(
                            key: GuardChestStage.tapHintKey,
                            opacity: _hintShown ? 1 : 0,
                            duration: const Duration(milliseconds: 900),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.l10n.guard_chest_tap_hint,
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B4A00),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 开箱动画（30 帧 / 5s；播完停末帧直到结算卡出现）。
                      if (opening && _frames.isNotEmpty)
                        Positioned.fromRect(
                          rect: chest,
                          child: SizedBox(
                            key: GuardChestStage.openPlayerKey,
                            width: chest.width,
                            height: chest.height,
                            child: FrameSequencePlayer(
                              frames: _frames,
                              durationMs: kGuardChestOpenMs,
                              // 定格末帧：播完不许渐隐（否则「箱子消失 → 卡弹出」
                              // 之间会露出一帧空花园，观感是闪屏）。
                              holdLastFrame: true,
                              fadeOutMs: 0,
                              fit: BoxFit.contain,
                              onComplete: _onOpenComplete,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 宝箱本体（静态首帧 + 高级档光晕 / 角标）。
///
/// 拆成独立 StatelessWidget 的原因：呼吸 / 落下动画每秒重建 60 次，把静态子树
/// 交给 `AnimatedBuilder` 的 `child` 参数缓存（只在档位 / 边长变化时重建）。
///
/// 🔴 B13.12：「点一下打开」提示已从本 widget 移出（卡内纵向预算只有 112pt，
/// 提示带由 [GuardChestStage.hintRectOf] 单独定位），本类只管宝箱那一格方框。
class _ChestBox extends StatelessWidget {
  const _ChestBox({
    super.key,
    required this.tier,
    required this.side,
    required this.l10n,
  });

  final GuardChestTier tier;
  final double side;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool premium = tier.isPremium;
    return Stack(
      // 高级档光晕画到方框外 1.02 倍：本层不裁，交给卡矩形的 ClipRect 统一兜。
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        // 🔴 高级宝箱的视觉区分（§7.3 之外的产品要求）：一层**主题色**光晕 +
        //    右上角「高级」角标。不新造色卡，全部取自 `colorScheme`。
        if (premium)
          Container(
            width: side * 1.02,
            height: side * 1.02,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  scheme.primary.withValues(alpha: 0.34),
                  scheme.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        SizedBox(
          width: side,
          height: side,
          // 语义：读屏知道这是一颗「可以打开的宝箱」（§7.4 热区 1）。
          child: Semantics(
            button: true,
            label: premium
                ? l10n.guard_chest_name_premium
                : l10n.guard_chest_name_normal,
            child: GuardArt.chestStill(tier),
          ),
        ),
        if (premium)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              key: GuardChestStage.premiumBadgeKey,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                l10n.guard_chest_name_premium,
                style: TextStyle(
                  // B13.12：方框从 179pt 收到 76pt ⇒ 角标字号 11 → 9，
                  // 否则「高级宝箱」四个字会吃掉半个箱子（文案本身不改）。
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 在 [pageContext]（今日页）的子树里量**场景卡的实际矩形**（全局坐标）。
///
/// ## 为什么「量」而不是「算」
/// 卡在屏上的位置由今日页排版决定（`sceneGap` = 0.40 × 屏高 − 26pt 上移、
/// ListView 滚动、`OverflowBox` 满宽贴边…）。在宝箱这边复写一遍公式，
/// 玄参一调首页排版就会**静默错位** —— 故直接问真实的 `RenderBox`。
///
/// 判据只用一件事：[GuardSceneCard.cardKey]（卡的根 SizedBox，高恒 112）。
/// 找不到 / 还没布局（`hasSize == false`）⇒ null，由调用方走兜底。
Rect? guardSceneCardRectOf(BuildContext pageContext) {
  Rect? found;

  void visit(Element element) {
    if (found != null) return;
    if (element.widget.key == GuardSceneCard.cardKey) {
      final RenderObject? render = element.renderObject;
      if (render is RenderBox && render.attached && render.hasSize) {
        found = render.localToGlobal(Offset.zero) & render.size;
      }
      return;
    }
    element.visitChildren(visit);
  }

  // `BuildContext` 在 widget / State / Builder 里恒为 `Element`；
  // 其它实现（例如测试里的假 context）没有子树可走 ⇒ 直接兜底。
  if (pageContext is Element) pageContext.visitChildren(visit);
  return found;
}

/// 弹出**宝箱演出**（只覆盖场景卡那一块、透明遮罩、不可跳过），5s 播完即返回。
///
/// 返回 `Future<void>`：完成 = 30 帧播完（调用方随后弹结算卡）。
///
/// ## 为什么这里才做导航
/// [GuardChestStage] 自己不做导航（它要能在纯 widget 测试里单独挂）；
/// 「播完 → pop」这条路由语义归调用方（本函数）。
///
/// ## 🔴 只占卡那一块（B13.12）
/// * 卡矩形在**打开弹层之前**量好（[guardSceneCardRectOf]）—— `pageBuilder`
///   的 context 在另一个 Overlay 分支上，那时已经看不到今日页的子树；
/// * 弹层内容 = `Stack[ Positioned.fromRect(卡矩形, ClipRect(宝箱层)) ]`：
///   卡外**既不画也不吃点击**；点击落到透明 `ModalBarrier` 上被吸收 ⇒ 不开箱、
///   也不穿透到今日页（孩子误触卡外不会点到统计卡 / 开始专注）。
/// * [cardRect] 是给测试用的显式接缝（生产恒走自动测量）。
///
/// ## 不可跳过
/// · `barrierDismissible: false` ⇒ 点遮罩不关卡；
/// · `PopScope(canPop: false)` ⇒ 系统返回键 / 返回手势无效（先例：
///   `guard_result_card.dart` 的结算卡，玄参 2026-11-09 真机事故的修法）。
Future<void> showGuardChestOverlay(
  BuildContext context, {
  required GuardChestTier tier,
  required AppLocalizations l10n,
  GuardChestSfxPlayer? playSfx,
  bool autoOpen = true,
  Rect? cardRect,
}) {
  final Rect? rect = cardRect ?? guardSceneCardRectOf(context);
  if (rect == null) {
    // 防御路径（生产上今日页的场景卡必然在树里）：退化成「屏幕顶部一条卡高」
    // —— 仍然守住「不许铺满全屏」这一条玄参口径，并留一条日志便于定位。
    debugPrint('[Guard] 没量到场景卡矩形：宝箱退化为屏幕顶部一条 112pt 带');
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: l10n.guard_chest_tap_hint,
    // 🔴 无暗色遮罩（§7.3）：花园保持可见。
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: kGuardBattleToResultMs),
    pageBuilder: (BuildContext dialogContext, Animation<double> _,
        Animation<double> __) {
      return PopScope(
        canPop: false,
        child: _ChestOverlayBody(
          cardRect: rect,
          tier: tier,
          l10n: l10n,
          playSfx: playSfx,
          autoOpen: autoOpen,
          onOpened: () {
            // 播完 → 关闭本层（页面 await 到返回后立刻弹结算卡）。
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      );
    },
  );
}

/// 弹层内容：把宝箱层**摆进场景卡矩形**（卡外零热区、零绘制）。
class _ChestOverlayBody extends StatelessWidget {
  const _ChestOverlayBody({
    required this.cardRect,
    required this.tier,
    required this.l10n,
    required this.playSfx,
    required this.autoOpen,
    required this.onOpened,
  });

  /// 场景卡矩形（全局坐标）；null ⇒ 走 [fallbackRectOf]。
  final Rect? cardRect;

  final GuardChestTier tier;
  final AppLocalizations l10n;
  final GuardChestSfxPlayer? playSfx;
  final bool autoOpen;
  final VoidCallback onOpened;

  /// 兜底矩形：屏幕顶部一条**卡高**的带子（**绝不铺满全屏**）。
  static Rect fallbackRectOf(Size screen) =>
      Rect.fromLTWH(0, 0, screen.width, kGuardSceneCardHeight);

  @override
  Widget build(BuildContext context) {
    final Rect rect = cardRect ?? fallbackRectOf(MediaQuery.sizeOf(context));
    return Stack(
      children: <Widget>[
        // 🔴 宝箱层只占卡矩形这一块。卡外的点击由透明 `ModalBarrier` 吸收
        //    （既不开箱、也不穿透），卡外零绘制（ClipRect 双保险）。
        Positioned.fromRect(
          rect: rect,
          child: ClipRect(
            child: GuardChestStage(
              tier: tier,
              l10n: l10n,
              playSfx: playSfx,
              autoOpen: autoOpen,
              onOpened: onOpened,
            ),
          ),
        ),
      ],
    );
  }
}
