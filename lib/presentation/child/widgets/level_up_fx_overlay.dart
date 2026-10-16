/// C74 · 升级演出浮层（设计 §5.24.6 / 口径 C74 §6 **修订二**：每次升级都播）。
///
/// ## 什么时候播（🔑 C74 §6 修订二，2026-10-14 玄参拍板；C78 经济层删除）
/// ~~原「31 次普通升级零演出」作废~~ —— 玄参交付了两套序列帧与两支音效，改为：
///  · **称号节点**（1/5/10/15/20/25/30/35/40）：`5leveUp` 41 帧 + `5_level_up.mp3`
///    + **解锁专属属性**（C78：零阳光、零账本行；卡内不显示阳光行）；
///  · **普通升级**（另外 31 次）：`defaultLevelUp` 36 帧 + `default_level_up.mp3`
///    + 卡内不显示阳光行。
///
/// 🔴 **C78（2026-10-15）**：称号节点不再发阳光（原「9 节点共 102☀」废止）；
/// 历史已发阳光不追回，账本 append-only 只停发、不清理、不写负向对冲行。
///
/// ## 素材与节奏
///  · 帧数**不写死**：运行期 [resolveFxFrames] 读 AssetManifest 实测（三级回退）；
///  · 播放时长 = 对应音频实测时长（帧速 = 帧数 ÷ 音频时长，C28 先例：
///    default 36/3.579 ≈ **10.06 fps**、5 级 41/4.180 ≈ **9.81 fps**）；
///  · **定格末帧**（[holdLastFrame]）而不是「播完即收」：依据 C22「结算动画播一次
///    定格末帧」先例 —— 演出卡要在停留段保持画面（避免末帧闪空），整卡淡出由
///    `FxCardEnvelope` 统一处理；
///  · 播前 `precacheFxFrames`（先 `rootBundle.load` 试探再解码，缺失静默跳过）。
///
/// ## 复用点
///  · 卡体 `FxCardShell`（奶油渐变 + 暖黄描边 + 胶囊标题 + 圆角 + 外发光）；
///  · 包络 `FxCardEnvelope`（弹入 `kGrowFxEnterMs` 360 → 停留（= 播放时长）
///    → 淡出 `kFxDisplayFadeOutMs` 300）；
///  · 浮层骨架：`Overlay.of(rootOverlay: true)` + `Positioned.fill + Center +
///    IgnorePointer`（🔴 **不走页面根 Stack**：C32 已实证根 Stack 居中在真机贴底）。
///
/// ## 交互纪律（Q-G）
/// 全程 `IgnorePointer`、**不拦截返回键**、无跳过按钮（升级是庆祝，不是强制流程）。
///
/// ⚠️ 普通升级的演出频次比称号节点高得多（40 级全升完播 39 场）→ in-flight 闸门
/// 必须只放行一场（快速连升时叠帧/叠音），跨多级一次结算也**只播一场**。
library level_up_fx_overlay;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show titleOfLevel;
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/fx_card_shell.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 本轮演出该用哪一套素材（**纯判定**，可单测）。
enum LevelUpFxKind {
  /// 称号节点：5 级素材 + 属性解锁。
  titleNode,

  /// 普通升级：default 素材。
  ordinary,
}

/// 一轮结算 → 演出种类；**不该播返回 null**（未升级 / 老用户首用静默）。
///
/// 🔑 判定顺序刻意如此：`granted` 优先（称号节点结算成功即入列，C78 后金额恒 0），
/// 其次才看 `leveledUp`（普通升级）。
LevelUpFxKind? levelUpFxKindOf(FocusLevelSettleResult result) {
  if (result.firstUseSilent) return null;
  if (result.granted.isNotEmpty) return LevelUpFxKind.titleNode;
  if (result.leveledUp) return LevelUpFxKind.ordinary;
  return null;
}

/// 一套升级演出的**素材规格**（纯数据，可单测）。
class LevelUpFxSpec {
  const LevelUpFxSpec({
    required this.dir,
    required this.durationMs,
    required this.cue,
    required this.fallbackFrameCount,
    required this.frameExt,
  });

  /// 序列帧目录。
  final String dir;

  /// 播放时长（毫秒）= 对应音频实测时长。
  final int durationMs;

  /// 配音 cue。
  final AudioCue cue;

  /// AssetManifest 读不到时的**兜底**帧数（不是真值）。
  final int fallbackFrameCount;

  /// 帧扩展名。
  final String frameExt;

  /// 帧速（fps，= 帧数 ÷ 音频时长；仅供展示/测试，播放不直接用）。
  ///
  /// 用 [fallbackFrameCount] 估算：default ≈ 10.06 / 5 级 ≈ 9.81。
  double get fps => fallbackFrameCount / (durationMs / 1000);

  /// 本轮演出包络总时长（弹入 + 停留（= 播放）+ 淡出，毫秒）—— 兜底定时器用。
  int get totalMs => kGrowFxEnterMs + durationMs + kFxDisplayFadeOutMs;
}

/// 称号节点规格：41 帧 / 4.18s / `5_level_up.mp3`。
const LevelUpFxSpec kLevelUpTitleFxSpec = LevelUpFxSpec(
  dir: kLevelUpTitleFxDir,
  durationMs: kLevelUpTitleFxDurationMs,
  cue: AudioCue.levelUpFive,
  fallbackFrameCount: kLevelUpTitleFrameCount,
  frameExt: kLevelUpFxFrameExt,
);

/// 普通升级规格：36 帧 / 3.58s / `default_level_up.mp3`。
const LevelUpFxSpec kLevelUpDefaultFxSpec = LevelUpFxSpec(
  dir: kLevelUpDefaultFxDir,
  durationMs: kLevelUpDefaultFxDurationMs,
  cue: AudioCue.levelUpDefault,
  fallbackFrameCount: kLevelUpDefaultFrameCount,
  frameExt: kLevelUpFxFrameExt,
);

/// 演出种类 → 素材规格（纯函数）。
LevelUpFxSpec levelUpFxSpecOf(LevelUpFxKind kind) => switch (kind) {
      LevelUpFxKind.titleNode => kLevelUpTitleFxSpec,
      LevelUpFxKind.ordinary => kLevelUpDefaultFxSpec,
    };

/// 演出卡 Key（widget 测试断言「只播一场 / 已移除」用）。
const Key kLevelUpFxCardKey = Key('levelUpFxCard');

/// 本轮演出包络总时长（弹入 + 停留 + 淡出，毫秒）—— 调用方做定时器兜底用。
///
/// ⚠️ 保留是为了兼容既有调用；实际时长**随素材变化**，请用
/// `levelUpFxSpecOf(kind).totalMs`。
int get kLevelUpFxTotalMs =>
    kGrowFxEnterMs + kLevelUpFxHoldMs + kFxDisplayFadeOutMs;

/// 造一个升级演出浮层 entry（插入 / 保存 / 移除由**调用方**负责）。
///
/// 用法（今日页 `_showLevelUpFx`，与 `garden_page._showBatchHint` 同款）：
/// ```dart
/// final OverlayEntry entry = levelUpFxOverlayEntry(
///   result: settleResult,
///   frames: await resolveFxFrames(...),
///   onComplete: _removeLevelUpFx,
/// );
/// Overlay.of(context, rootOverlay: true).insert(entry);
/// ```
///
/// 🔴 插入权在调用方（页面需持有 entry 才能在 dispose 时移除）。
/// [frames] 由调用方**先解析好**再传入（解析是 async，不能在 builder 里做）。
OverlayEntry levelUpFxOverlayEntry({
  required FocusLevelSettleResult result,
  required List<String> frames,
  VoidCallback? onComplete,
}) {
  return OverlayEntry(
    builder: (BuildContext _) => Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: LevelUpFxOverlay(
            result: result,
            frames: frames,
            onComplete: onComplete,
          ),
        ),
      ),
    ),
  );
}

/// 播一场升级演出（**自建 entry、播完自摘**；无页面生命周期的场景用，如调试入口）。
///
/// 今日页走自己的 `_showLevelUpFx`（页面持有 entry 以便 dispose 时移除）；本函数是
/// 同一套素材/音效/解析逻辑的**无宿主版**，供「我的页调试区」这类一次性入口复用。
///
/// ⚠️ 不做 in-flight 闸门（调用点自己保证不连点）；播完由 `onComplete` 自摘，
/// 不会泄漏浮层。
Future<void> showLevelUpFxAuto(
  BuildContext context,
  FocusLevelSettleResult result,
) async {
  final LevelUpFxKind? kind = levelUpFxKindOf(result);
  if (kind == null || !context.mounted) return;
  final LevelUpFxSpec spec = levelUpFxSpecOf(kind);
  final List<String> frames = await resolveFxFrames(
    spec.dir,
    ext: spec.frameExt,
    fallbackCount: spec.fallbackFrameCount,
  );
  if (!context.mounted) return;
  late final OverlayEntry entry;
  entry = levelUpFxOverlayEntry(
    result: result,
    frames: frames,
    onComplete: () => entry.remove(),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
}

/// 升级演出卡（FxCardShell + 序列帧主视觉 + 文字 + 进出场包络）。
///
/// 直接 `pumpWidget(LevelUpFxOverlay(...))` 也能独立渲染（widget 测试用）。
class LevelUpFxOverlay extends StatefulWidget {
  const LevelUpFxOverlay({
    super.key,
    required this.result,
    required this.frames,
    this.onComplete,
  });

  /// 本轮结算结果（由 [levelUpFxKindOf] 判定播哪一套）。
  final FocusLevelSettleResult result;

  /// 已解析好的序列帧路径列表（空列表 ⇒ 只显示文字部分，不崩）。
  final List<String> frames;

  /// 演出（停留 + 淡出）全部结束回调，供调用方移除本浮层。
  final VoidCallback? onComplete;

  @override
  State<LevelUpFxOverlay> createState() => _LevelUpFxOverlayState();
}

class _LevelUpFxOverlayState extends State<LevelUpFxOverlay>
    with TickerProviderStateMixin {
  late final FxCardEnvelope _envelope = FxCardEnvelope(
    vsync: this,
    onComplete: () => widget.onComplete?.call(),
  );

  /// 本场演出的停留时长（= 素材播放时长）；`initState` 里定下来不再变。
  late final int _holdMs = () {
    final LevelUpFxKind? kind = levelUpFxKindOf(widget.result);
    return kind == null
        ? kLevelUpFxHoldMs
        : levelUpFxSpecOf(kind).durationMs;
  }();

  @override
  void initState() {
    super.initState();
    final LevelUpFxKind? kind = levelUpFxKindOf(widget.result);
    if (kind != null) {
      // 严格走既有 SFX 通道（含 ducking / 并发代际闸门 C66）；缺素材静默跳过。
      AudioService.instance.playSfx(levelUpFxSpecOf(kind).cue);
    }
    _envelope.startEnter();
    _envelope.scheduleAutoFadeOut(_holdMs);
  }

  @override
  void dispose() {
    _envelope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LevelUpFxKind? kind = levelUpFxKindOf(widget.result);
    return KeyedSubtree(
      key: kLevelUpFxCardKey,
      child: _envelope.wrap(
        FxCardShell(
          title: kind == LevelUpFxKind.titleNode
              ? kLevelUpFxTitle
              : kLevelUpFxLevelTitle,
          child: _LevelUpContent(result: widget.result, frames: widget.frames),
        ),
      ),
    );
  }
}

/// 卡内容：**序列帧主视觉**（居中）+ 等级/称号文案 +（称号节点才显示）属性行。
///
/// 主视觉区从「纯大号徽章」改为序列帧动画：帧播完**定格末帧**（C22 先例），
/// 整卡淡出由 [FxCardEnvelope] 处理。帧列表为空时回退到静态大徽章（不崩）。
///
/// **C80**：改 [ConsumerWidget] —— `watch` [entitlementProvider] 判定
/// `FeatureKey.titlePerks`；免费档属性行**置灰 + 🔒付费解锁尾缀**（P0-7），
/// 付费档与 C78 现状逐字节一致。不加点击跳转（演出是瞬时 overlay，转化入口
/// 由详情卡承担）。
class _LevelUpContent extends ConsumerWidget {
  const _LevelUpContent({required this.result, required this.frames});

  final FocusLevelSettleResult result;
  final List<String> frames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double s = uiScaleOf(context);
    // C80：付费是否解锁称号专属属性（矩阵单点判定，与详情卡 / provider 同源）。
    final bool perkUnlocked = featureAllowedFor(
        FeatureKey.titlePerks, ref.watch(entitlementProvider).tier);
    final LevelUpFxKind? kind = levelUpFxKindOf(result);
    final int durationMs =
        kind == null ? kLevelUpFxHoldMs : levelUpFxSpecOf(kind).durationMs;
    final bool isTitleNode = kind == LevelUpFxKind.titleNode;

    final List<LevelGrant> granted = result.granted;
    final bool empty = granted.isEmpty;
    final LevelGrant top = empty
        ? const LevelGrant(level: 0, amount: 0)
        : granted.last;
    // 称号节点显示本轮**最高新称号**；普通升级显示**当前等级**的称号（可能是
    // 更早节点解锁的那个 —— 等级与称号已解耦，C74 §3）。
    final int shownLevel = empty ? result.currentLevel : top.level;
    final int titles = result.titlesGained;
    final int levels = result.levelsGained;

    // C77：本轮「最高新称号」的专属属性（= 已解锁节点属性累积，与域层同源）。
    final PlantPerk perk = perkOfLevel(shownLevel);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── 主视觉：序列帧（缺失回退静态徽章）──────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(kGrowFxInnerRadius),
          child: SizedBox(
            width: kLevelUpFxStageSize * s,
            height: kLevelUpFxStageSize * s,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.08),
                  radius: 0.72,
                  colors: <Color>[kGrowFxGlowCore, kGrowFxGlowEdge],
                ),
              ),
              child: frames.isEmpty
                  ? Center(
                      child: LevelBadgeCircle(
                        level: shownLevel,
                        diameter: kLevelUpFxBadgeDiameter * s,
                        isMax: shownLevel >= kFocusLevelMaxLevel,
                        labelFontSize: kLevelUpFxLevelFontSize,
                      ),
                    )
                  : FrameSequencePlayer(
                      frames: frames,
                      durationMs: durationMs,
                      // 🔑 定格末帧（C22 先例）：停留段保持画面，避免末帧闪空；
                      // 整卡淡出由 FxCardEnvelope 统一处理，故本播放器不渐隐。
                      holdLastFrame: true,
                      fadeOutMs: 0,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$kLevelBadgeTextPrefix$shownLevel · ${titleOfLevel(shownLevel)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: kLevelUpFxTitleFontSize,
            fontWeight: FontWeight.w800,
            color: Color(0xFF6B563F),
          ),
        ),
        // 副标题：称号节点说「连升 N 个称号！」，普通升级说「连升 N 级！」。
        if (titles > 1 || (!isTitleNode && levels > 1)) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            titles > 1
                ? kLevelUpFxMultiTemplate.replaceAll('{n}', '$titles')
                : kLevelUpFxLevelMultiTemplate.replaceAll('{n}', '$levels'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB07A00),
            ),
          ),
        ],
        // 🔴 **C78 后恒隐藏**：`totalSunlight` 恒 0（称号节点零阳光、零账本行），
        // 保留条件式仅为兼容旧夹具；显示「+0 ☀」是错的，绝不放开。
        if (isTitleNode && result.totalSunlight > 0) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                'assets/rewards/sunlight.png',
                width: kLevelUpFxSunIconSize * s,
                height: kLevelUpFxSunIconSize * s,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.wb_sunny,
                  color: const Color(0xFFE8A600),
                  size: kLevelUpFxSunIconSize * s,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '+${result.totalSunlight}',
                style: const TextStyle(
                  fontSize: kLevelUpFxAmountFontSize,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD98F00),
                ),
              ),
            ],
          ),
        ],
        // C77：称号节点追加「本称号专属：…」行（普通升级**不显示** —— 无新称号）；
        // 文案由 [perkSummaryTextOf] + 模板单点装配（不写页面内 if-else 拼 9 种）。
        // C80：免费档同文案置灰（与详情卡锁态同源色）+「 · 🔒付费解锁」尾缀
        // （PM 裁定措辞）；付费档与 C78 现状一致。不加点击跳转（P0-7）。
        if (isTitleNode && !perk.isNone) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            kLevelUpFxPerkTemplate
                    .replaceAll('{text}', perkSummaryTextOf(perk)) +
                (perkUnlocked ? '' : kLevelUpFxPerkLockedSuffix),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: perkUnlocked
                  ? const Color(0xFF8A5A00) // C78 现状：暖棕
                  : const Color(0xFFB0A08C), // C80 免费锁标：置灰（同详情卡）
            ),
          ),
        ],
      ],
    );
  }
}
