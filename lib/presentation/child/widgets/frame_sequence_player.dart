/// 序列帧资产契约与通用播放器（2026-09-28 玄参素材落地）。
///
/// ## 资产契约（目录即接口，详见 `docs/美术资源_序列帧与音频命名规范_v1.md`）
///  · 成长过渡帧：`assets/fx/grow/{物种}/{过渡名}/frame001..N.png`（**三位零填充**，
///    从 001 起，播放顺序 = 文件名字典序）；
///  · 养护效果帧：`assets/fx/care/{water|fertilize}/frame001..N.png`（纯效果层，
///    透明底、不含盆与植物 —— 播放时叠加在植物静态图**之上**，植物本体保持可见）；
///  · 帧数统一 [kFxFrameCount]（本次交付五组均 25 帧）。
///
/// ## 播放口径（玄参拍板）
///  · **每帧时长 = 音频时长 / 帧数**（「动画帧的播放速度与对应的音频时间保持一致」），
///    时长常量在 `prd_params.dart`（grow 三段各 4100ms、water 2900ms、fertilize 3056ms）；
///  · 成长过渡：居中放大演出（[kGrowFxScale] 倍格宽），播完后 [kFxDisplayFadeOutMs]
///    渐隐消失，切回静态图；
///  · 养护效果：底层植物静态图保持不动，效果帧叠加其上，播完渐隐移除。
///
/// 实现：单一 [AnimationController] 驱动，播放段按进度取帧号，收尾段做透明度渐隐；
/// 总时长有限（= 播放 + 渐隐），可被 `pumpAndSettle()` 正常结束（测试硬要求）。
library frame_sequence_player;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 成长过渡名（= `assets/fx/grow/{物种}/` 下的子目录名）。
enum GrowTransition {
  /// 种子破土 → 幼苗。
  seedToSprout('seed_to_sprout'),

  /// 幼苗长高 → 成株。
  sproutToAdult('sprout_to_adult'),

  /// 成株绽放 → 盛开。
  adultToBloomed('adult_to_bloomed');

  const GrowTransition(this.dirName);

  /// 目录名（素材交付目录，禁止改动）。
  final String dirName;

  /// 该过渡的播放时长（毫秒，= 对应音频时长）。
  int get durationMs {
    switch (this) {
      case GrowTransition.seedToSprout:
        return kGrowSeedToSproutDurationMs;
      case GrowTransition.sproutToAdult:
        return kGrowSproutToAdultDurationMs;
      case GrowTransition.adultToBloomed:
        return kGrowAdultToBloomedDurationMs;
    }
  }
}

/// 拼一组序列帧的 asset 路径列表（`{dir}/frame001.png` … 共 [count] 张）。
///
/// 纯函数（无 IO），命名契约唯一真源：三位零填充、从 [kFxFirstFrameNumber] 起。
List<String> fxFrameAssets(String dir, int count) {
  return List<String>.generate(count, (int i) {
    final int n = kFxFirstFrameNumber + i;
    return '$dir/frame${n.toString().padLeft(kFxFrameDigits, '0')}.png';
  });
}

/// 成长过渡帧目录（`assets/fx/grow/{物种}/{过渡名}`）。
String growFxDir(String speciesDir, GrowTransition t) =>
    'assets/fx/grow/$speciesDir/${t.dirName}';

/// 浇水效果帧目录。
const String kCareWaterFxDir = 'assets/fx/care/water';

/// 施肥效果帧目录。
const String kCareFertilizeFxDir = 'assets/fx/care/fertilize';

/// 预热一组序列帧到 ImageCache（消除「画面一闪一闪」的换帧白屏）。
///
/// 逐帧 `Image.asset` 换帧时会重新解码 720×720 PNG（异步）→ 旧图已丢弃则白屏闪烁
/// （玄参 2026-09-29 实测反馈）。播放前把整组帧解码进缓存即可消除。
///
/// ⚠️ **必须先用 `rootBundle.load` 试探**：对不存在的资源，`precacheImage` 会经
/// image resource service **上报断言**（`try/catch` 与 `catchError` 都拦不住 →
/// 测试直接变红）；而 `rootBundle.load` 的缺失错误是普通 Future error，可被捕获。
/// 故这里「先探存在、再预解码」，缺失者静默跳过（显示侧由 errorBuilder 兜底）。
///
/// 失败一律静默：预热只是性能/观感优化，最坏退回原行为。
Future<void> precacheFxFrames(BuildContext context, List<String> frames) async {
  for (final String f in frames) {
    try {
      final ByteData data = await rootBundle.load(f);
      if (data.lengthInBytes == 0) continue;
      if (!context.mounted) return; // 组件已卸载：不再预热（避免跨 async 用 context）
      await precacheImage(AssetImage(f), context);
    } catch (_) {
      // 资源缺失 / 解码失败：静默跳过。
    }
  }
}

/// 播放进度 → 帧下标（纯函数，便于无副作用单测）。
///
/// [t] ∈ [0,1) 为播放段进度；末帧钳到 `count - 1`。
int frameIndexFor(double t, int count) =>
    (t * count).floor().clamp(0, count - 1);

/// 序列帧一次性播放器：按序轮播 [frames]，播完 [fadeOutMs] 渐隐后回调 [onComplete]。
///
/// 布局：外层给多大就画多大（[SizedBox.expand] + [BoxFit.contain]，帧画布 720×720
/// 方形；「居中放大 / 底对齐」等几何编排由调用方用 [Positioned] 决定，本组件不掺和）。
/// `Image.asset` 均显式传宽高（loose 约束下无宽高会按原图尺寸撑爆 —— 项目硬规则）。
class FrameSequencePlayer extends StatefulWidget {
  const FrameSequencePlayer({
    super.key,
    required this.frames,
    required this.durationMs,
    this.fadeOutMs = kFxDisplayFadeOutMs,
    this.onComplete,
  });

  /// 帧asset 路径列表（顺序即播放顺序）。
  final List<String> frames;

  /// 播放段总时长（毫秒）= 对应音频时长。
  final int durationMs;

  /// 播完后的渐隐时长（毫秒）；0 表示播完立即消失。
  final int fadeOutMs;

  /// 整段（播放 + 渐隐）结束回调，供调用方移除本组件。
  final VoidCallback? onComplete;

  @override
  State<FrameSequencePlayer> createState() => _FrameSequencePlayerState();
}

class _FrameSequencePlayerState extends State<FrameSequencePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.durationMs + widget.fadeOutMs),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    unawaited(precacheFxFrames(context, widget.frames));
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onComplete?.call();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext context, Widget? _) {
          final double t = _ctrl.value;
          // 播放段：t ∈ [0, playEnd) 取帧；渐隐段：停在末帧并线性淡出。
          final double playEnd =
              widget.durationMs / (widget.durationMs + widget.fadeOutMs);
          final double opacity = t >= playEnd
              ? (1 - (t - playEnd) / (1 - playEnd)).clamp(0.0, 1.0)
              : 1.0;
          final int idx = frameIndexFor(
            (t / (playEnd == 0 ? 1 : playEnd)).clamp(0.0, 0.999),
            widget.frames.length,
          );
          return SizedBox.expand(
            child: Opacity(
              opacity: opacity,
              child: Image.asset(
                widget.frames[idx],
                fit: BoxFit.contain,
                // ⚠️ 2026-09-29 玄参实测「一闪一闪」：换帧时旧图被立即丢弃、新图异步
                // 解码 → 白屏闪烁。保留旧帧直到新帧就绪（另见 [didChangeDependencies]
                // 的整组预解码）。
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}
