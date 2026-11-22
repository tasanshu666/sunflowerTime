/// 大招**第二段**演出组件（P0-06 / P0-07 / A12）：怪物聚集区 27 帧纯特效 + fx 音轨。
///
/// 🔴 **纯渲染层**：不进 sim / 结算 / seed（确定性零破口，架构 §8-S9）。
/// 由 `guard_battle_field` 在「cast 第 2 秒」（`kUltimateFxCastLeadMs`）提前挂到
/// [anchor]（怪物聚集区，经 `GuardCardLayout.ultimateFxAnchor` 换算），
/// 播完 [onComplete] 自行移除。
///
/// ## 🔴 玄参 2026-11-20 验收 / 2026-11-24 真机反馈 4（8s → 6s）
/// * **cast 段**已搬到 `GuardArt.soldierUltimateCast` —— 战士本体在**原位置**播
///   27 帧释放动作（战场上不再凭空多出一个大号战士）；本组件**只含 fx 段**，
///   帧素材 1470×630 是纯特效、不含任何战士形象（确认无 cast 帧混入）。
/// * **启动时机**：由卡侧 `kUltimateFxCastLeadMs`（cast 第 2 秒）提前驱动上树；
///   cast 帧仍播满 4s，两段重叠 2s，总演出 6s。cast 段正常收尾时的判据调用
///   仅作兜底（同一处闸门去重），不会二次挂树。
/// * **音轨对齐**：fx 音轨在本组件 `initState` 随 fx 帧**同起点**启动，帧时长 =
///   [kUltimateFxDurationMs]（≈ 音轨时长）⇒ 帧播完时音轨也收尾。走叠加池
///   [AudioService.playSfxPathsOverlap]，不掐断尚未播完的 cast 音轨。
/// * 素材缺失时 `FrameSequencePlayer` 自带回退，不白屏不 crash。
library guard_ultimate_fx;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardSceneCardHeight,
        kUltimateFxCastSfx,
        kUltimateFxCastSfxZh,
        kUltimateFxDurationMs,
        kUltimateFxEffectDir,
        kUltimateFxEffectFrames,
        kUltimateFxVisualCenterY;
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart'
    show FrameSequencePlayer, fxFrameAssets, kGrowFxFrameExt;

/// 大招音效资源路径（真源在 `prd_params.dart`，与 `pubspec.yaml` / 转换脚本契约一致）。
///
/// cast 音轨两版（中英各一）由调用方按生效语言选；fx 音轨中英通用。
const String kGuardUltimateCastSfx = kUltimateFxCastSfx;
const String kGuardUltimateCastSfxZh = kUltimateFxCastSfxZh;
const String kGuardUltimateFxSfx = 'assets/audio/sfx/guard_ultimate_fx.mp3';

/// cast 音轨按生效语言二选一（纯函数，可单测；fx 音轨通用不参与）。
String guardUltimateCastSfxForLocale(bool isEn) =>
    isEn ? kGuardUltimateCastSfx : kGuardUltimateCastSfxZh;

/// fx 段「技能效果落地 ⇒ 小怪同步被清除」的触发帧（**0 基**帧下标，= 第 14 帧
/// `frame014`）。🔴 2026-11-24 真机反馈 4：新素材（27 帧，光效落地整体后移）
/// 的视觉爆发/重音落在 `frame012~019`，旧第 7 帧（`frame007`）怪会在半空提前消失。
/// 改选 0 基 **13**（= `frame014`，≈13/27×4000ms ≈ 1926ms）作清怪触发帧，
/// 让「怪消失」与「特效真正落地」同帧。
///
/// 用 0 基下标与 [FrameSequencePlayer.onFrameReached] 的 `index` 同口径；
/// 调用方按 `index >= kUltimateFxKillTriggerFrame` 判定（掉帧跳号也不漏触发）。
const int kUltimateFxKillTriggerFrame = 13;

/// 大招 fx 素材宽高比（1470×630 ≈ 2.333）；绘制盒按「视觉高 = 守卫卡高」反推宽。
const double kUltimateFxAspectRatio = 1470 / 630;

/// 大招两段严格串行的**推进判据**（纯函数，可单测）。
///
/// 只有 cast 段的「27 帧动作播完」**且**「cast 音轨播完」都为 true，才允许
/// 启动 fx 段。任一段未收尾即抢跑 ⇒ 玄参实测的「动作和音效被卡断」。
/// `guard_scene_card.dart` 的 `_enterFxStage` 状态机调用本函数。
bool canStartFxStage({
  required bool castFramesDone,
  required bool castAudioDone,
}) =>
    castFramesDone && castAudioDone;

/// 大招 fx 段演出：27 帧横向纯特效，锚点 [anchor]（卡内坐标，怪物聚集区，
/// 非战士脚下，P0-07）。cast 段已搬走，本组件不再渲染任何战士形象。
class GuardUltimateFx extends StatefulWidget {
  const GuardUltimateFx({
    required this.anchor,
    required this.uiScale,
    this.onComplete,
    this.onEffectFrame,
    super.key,
  });

  /// fx 特效锚点（卡内坐标；横向通道怪物聚集区，非战士脚下，P0-07）。
  final Offset anchor;

  /// 平板放大倍率。
  final double uiScale;

  /// fx 段结束回调（供父层移除本组件）。
  final VoidCallback? onComplete;

  /// fx 段播到 [kUltimateFxKillTriggerFrame]（技能效果落地）时回调**一次**。
  ///
  /// 由战斗层消费：此刻才把缓存的 `ultimateKill` 事件记入死亡账本 ⇒ 小怪
  /// 从「存活行走」切到「转身逃跑 + 淡出」，与技能特效同步（玄参 2026-11-21
  /// 「先播技能特效，效果出来那一刻怪才消失」）。纯表现层回调，sim 不感知。
  final VoidCallback? onEffectFrame;

  /// fx 段播放器 Key（测试断言「fx 不在 soldierRect 中心」时定位）。
  static const Key fxKey = Key('guardUltimateFxStage');

  @override
  State<GuardUltimateFx> createState() => _GuardUltimateFxState();
}

class _GuardUltimateFxState extends State<GuardUltimateFx> {
  /// 段二：大招特效帧（27 帧，1470×630，横向铺在通道；**纯特效无战士**）。
  late final List<String> _fxFrames = fxFrameAssets(
    kUltimateFxEffectDir,
    kUltimateFxEffectFrames,
    ext: kGrowFxFrameExt,
  );

  /// 效果落地帧回调闸门：整段只触发一次（同一场重播由父层换 ValueKey 重建）。
  bool _effectFired = false;

  @override
  void initState() {
    super.initState();
    // 🔴 fx 音轨随 fx 段起点播（cast 第 2 秒已提前上树；没有抢跑 delay）。
    // 走叠加池而非单播放器：cast 音轨还有 ~2s 没播完，不能被后起的 fx 掐断。
    // fire-and-forget，失败静默降级，绝不影响战局确定性。
    AudioService.instance.playSfxPathsOverlap(kGuardUltimateFxSfx);
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 2026-11-21（玄参「技能特效帧有点小」）：旧绘制盒 w=h=120×uiScale、
    // Positioned(width=240, height=120)，素材 1470×630 按 contain 由**宽**决定
    // 缩放 ⇒ 视觉高 ≈ 240/2.333 = 103pt < 卡高 112（卡高常量
    // [kGuardSceneCardHeight] = 14+88+10）。改为「视觉高 = 守卫卡高」：
    // 绘制盒高 h = 卡高×uiScale，宽 w = h×素材宽高比（≈261×uiScale；比旧的
    // 240 略宽，正好不再卡住高度），contain 下高由盒高驱动 ⇒ 视觉高逐位 = 卡高。
    // 横向略溢出由父层 Stack（Clip.hardEdge）自然裁边，特效是横向法阵，边缘
    // 本就淡出，裁掉不损观感。
    //
    // 🔴 2026-11-21（玄参「技能特效有点靠下，没看清」）：fx 素材的 alpha 加权
    // 视觉重心在帧高 68%~79%，不是几何中心。旧 `top = anchor.dy - h/2` 把
    // 几何中心放在怪物中心 ⇒ 视觉重心压到卡底。按 [kUltimateFxVisualCenterY]
    // 上移 ~0.18h（≈20pt），左 / 宽 / 高 / uiScale 一律不动。
    final double h = kGuardSceneCardHeight * widget.uiScale;
    final double w = h * kUltimateFxAspectRatio;
    return Stack(
      children: <Widget>[
        // fx 特效帧（横向铺在通道，1470×630 按比例，宽大于高；锚 = 怪物聚集区）。
        Positioned(
          key: GuardUltimateFx.fxKey,
          left: widget.anchor.dx - w / 2,
          top: widget.anchor.dy - kUltimateFxVisualCenterY * h,
          width: w,
          height: h,
          child: FrameSequencePlayer(
            frames: _fxFrames,
            durationMs: kUltimateFxDurationMs,
            fadeOutMs: 0,
            fit: BoxFit.contain,
            onFrameReached: (int index) {
              if (_effectFired ||
                  index < kUltimateFxKillTriggerFrame) {
                return;
              }
              _effectFired = true;
              widget.onEffectFrame?.call();
            },
            onComplete: widget.onComplete,
          ),
        ),
      ],
    );
  }
}
