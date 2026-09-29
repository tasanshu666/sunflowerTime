/// 养护成功的一次性视觉反馈（浇水 / 施肥），叠在花园页对应花盆格之上。
///
/// ## 行为
///  · 纯代码粒子（[CustomPaint] / [Stack]），总时长 ≤ [kCareEffectDurationMs] 毫秒，**有限**，
///    可被 `pumpAndSettle()` 正常结束（测试硬要求），绝不引入无限循环动画；
///  · **浇水**：数颗水滴从植物上方落下 → 到盆口处消失（带小水花）；
///  · **施肥**：金色 / 暖黄闪光粒子在盆上方闪烁上浮（类阳光闪烁）；
///  · **花盆 / 植物本体完全静止**：不施加任何弹跳 / 缩放 / 位移 / 摇摆 transform，
///    玄参大人要求花盆不能动，动效只保留水滴 / 闪光粒子 + 植物静态展示。
///  · 所有动效参数收敛到文件顶部命名常量，**禁止散在 build 里**。
///
/// ## 序列帧接口（2026-09-28 玄参素材落地，正式启用）
/// [frames] 非 null 时改为逐帧轮播效果帧（`assets/fx/care/{water|fertilize}/frameNNN.png`，
/// 三位零填充），**直接叠加在底层真实植物之上**（overlay 透明、不遮挡、不再自绘
/// 植物副本 —— 2026-09-28 玄参实测「花盆上下移动」根因即副本错位，已删）：
/// 帧为 720×720 方形画布，底对齐格子底边、宽度 = 格宽，`BoxFit.contain` 绘制。
/// 帧时长由 [durationMs] 指定（= 对应音频时长，「帧速与音频一致」，
/// 常量在 `prd_params.dart`）。命名契约见 `docs/美术资源_序列帧与音频命名规范_v1.md`
/// 与 `frame_sequence_player.dart`。
library care_effect_overlay;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

/// 养护动效类型。
enum CareEffectType { water, fertilize }

// ── 动效参数（命名常量集中区，禁止散在 build 里）─────────────────────
/// 总时长（毫秒）：≤ 1500，保证动画有限、可被 pumpAndSettle 结束。
const int kCareEffectDurationMs = 1400;

/// 浇水：水滴数。
const int kWaterDropCount = 6;

/// 浇水：水滴半径（逻辑像素）。
const double kWaterDropRadius = 4.0;

/// 浇水：水滴起始 y（相对格高比例，格顶略下方）。
const double kWaterDropStartYRatio = 0.02;

/// 浇水：水滴消失 y（相对格高比例，盆口附近）。
const double kWaterDropEndYRatio = 0.80;

/// 浇水：每颗水滴错峰起始（相对总进度，0~1）。
const double kWaterDropStagger = 0.10;

/// 浇水：单颗水滴下落所占总进度跨度。
const double kWaterDropSpan = 0.55;

/// 施肥：闪光粒子数。
const int kFertilizeSparkCount = 7;

/// 施肥：闪光粒子半径（逻辑像素）。
const double kFertilizeSparkRadius = 5.0;

/// 施肥：闪光上浮距离（相对格高比例）。
const double kFertilizeSparkRiseRatio = 0.45;

/// 施肥：每颗闪光错峰起始（相对总进度，0~1）。
const double kFertilizeSparkStagger = 0.08;

/// 施肥：单颗闪烁所占总进度跨度。
const double kFertilizeSparkSpan = 0.5;

/// 马卡龙色底（图标块 / 闪光等浅色填充用）。
const List<Color> kMacaronBg = <Color>[
  Color(0xFFFFD9E0),
  Color(0xFFFFF1C2),
  Color(0xFFD9F2DD),
  Color(0xFFD9E8FF),
];

/// 马卡龙色对应的深字色（保证对比度）。
const List<Color> kMacaronFg = <Color>[
  Color(0xFFC2185B),
  Color(0xFF8D6E00),
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
];

/// 浇水水滴的颜色。
const Color kWaterColor = Color(0xFF4FC3F7);

/// 施肥闪光的颜色（暖金）。
const Color kFertilizeColor = Color(0xFFFFD54F);

/// 养护成功一次性动画叠加层。
///
/// 由花园页在「对应花盆格」的位置用 [Positioned] 包住本组件播放；播放结束（动画完成）
/// 通过 [onComplete] 通知花园页移除自身。**所有动效参数来自文件顶部常量。**
class CareEffectOverlay extends StatefulWidget {
  /// 动效类型（浇水 / 施肥）。
  final CareEffectType type;

  /// 被养护的植物（**仅作上下文透传**，本组件不再自绘植物副本 —— 2026-09-28 起
  /// 效果直接叠加在底层真实植物之上）。可为 null（测试可空构造）。
  final Plant? plant;

  /// [plant] 对应的物种（与 [plant] 配对传入，仅透传）。
  final PlantSpecies? species;

  /// 序列帧接口：非 null 时逐帧轮播这些 asset，**叠加在植物层之上**（植物不消失）。
  /// 列表顺序即播放顺序；null 时走代码粒子。
  final List<String>? frames;

  /// 播放总时长（毫秒）。传帧时 = 对应音频时长（kCareWaterDurationMs /
  /// kCareFertilizeDurationMs）；代码粒子路径用默认 [kCareEffectDurationMs]。
  final int durationMs;

  /// 动画播放完成（有限时长到达）回调，供花园页移除叠加层。
  final VoidCallback? onComplete;

  /// 所在格子宽（花园页传入，用于粒子坐标系）；缺省时按父约束取。
  final double? width;

  /// 所在格子高；缺省时按父约束取。
  final double? height;

  const CareEffectOverlay({
    super.key,
    required this.type,
    this.plant,
    this.species,
    this.frames,
    this.durationMs = kCareEffectDurationMs,
    this.onComplete,
    this.width,
    this.height,
  });

  @override
  State<CareEffectOverlay> createState() => _CareEffectOverlayState();
}

class _CareEffectOverlayState extends State<CareEffectOverlay>
    with SingleTickerProviderStateMixin {
  /// 唯一动画控制器：有限时长，结束后发 [AnimationStatus.completed]。
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.durationMs),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  /// 预解码全部帧到 ImageCache（消除首播切帧卡顿 / 闪烁）。
  ///
  /// 逐帧 `Image.asset` 会在每次换帧时**重新解码 PNG**（720×720），首播尤其明显。
  /// 这里在播放前把整组帧预热进缓存；失败静默（最坏退回原行为，不崩）。
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final List<String>? fs = widget.frames;
    if (fs == null || fs.isEmpty) return;
    unawaited(precacheFxFrames(context, fs));
  }

  void _onStatus(AnimationStatus status) {
    // 有限时长到达 → 通知外层移除（不在此 dispose 控制器，留给外层 setState 后再走 dispose）。
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
    // 一次性透明反馈层：不拦截点击（IgnorePointer），让底层花盆在动画期间仍可被点。
    //
    // ⚠️ 2026-09-28 玄参实测反馈「花盆还会上下移动」：根因是旧版在 overlay 里又画了
    // 一张**带盆植物静态副本**（贴格顶、宽度比例与底层格内植物不一致）→ 播放瞬间
    // 出现第二个错位花盆，看起来花盆跳动。已删除副本层 —— 底层植物本就完整可见，
    // 效果帧/粒子直接叠加其上，**花盆 / 植物零 transform、绝不移动**。
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double w = widget.width ?? c.maxWidth;
          final double h = widget.height ?? c.maxHeight;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (widget.frames != null && widget.frames!.isNotEmpty)
                  _frameLayer(w, h) // 效果帧叠加层
                else
                  _particleLayer(w, h), // 代码粒子
              ],
            ),
          );
        },
      ),
    );
  }

  /// 效果帧叠加层（正式启用）：按**落点**精确定位 —— 水流 / 肥粒的末端恰好落在
  /// 植物根部（盆口），而不是花盆底部（玄参 2026-09-29 实测反馈「落在花盆底部」）。
  ///
  /// 几何（与 [garden_pot] 共用同一套常量，见 `prd_params.dart`）：
  ///  · 帧宽 `f = 内框宽 × [kCareFxWidthRatio]`（允许越出格子边界，玄参拍板）；
  ///  · 落点锚点：帧内横向 `[kCareWaterAnchorX]` / `[kCareFertilizeAnchorX]`、
  ///    纵向 `[kCareFxAnchorY]`（= 画布底边），实测自 `assets/fx/care/*`；
  ///  · 盆口 y：植物图底边 - 图高 × (1 - [kPotRimYFraction])。
  /// 末 10% 进度整体渐隐，避免「壶/袋」瞬间消失的跳变；资源缺失不崩。
  Widget _frameLayer(double w, double h) {
    final List<String> frames = widget.frames!;
    final double anchorX = widget.type == CareEffectType.water
        ? kCareWaterAnchorX
        : kCareFertilizeAnchorX;
    // 格内框（格子 Padding 与 garden_pot 一致）。
    final double innerW = w - 2 * kGardenCellHorizontalPad;
    final double innerH = h - 2 * kGardenCellVerticalPad;
    final double artW = innerW * kGardenArtWidthRatio;
    final double artH = artW * kGardenArtAspect;
    // 植物图底边（Column 贴底 + 底部文案区）→ 盆口（根部）y。
    final double artBottom = kGardenCellVerticalPad + innerH - kGardenPotFooterHeight;
    final double rootY = artBottom - artH * (1 - kPotRimYFraction);
    final double rootX = w / 2;
    final double f = innerW * kCareFxWidthRatio;
    final double left = rootX - anchorX * f;
    final double top = rootY - kCareFxAnchorY * f;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final int idx =
            (_ctrl.value * frames.length).floor().clamp(0, frames.length - 1);
        // 末 10% 渐隐（时长随总时长缩放；kCareWater 2900ms → 约 290ms）。
        final double t = _ctrl.value;
        final double alpha =
            t < 0.9 ? 1.0 : (1 - (t - 0.9) / 0.1).clamp(0.0, 1.0);
        return Positioned(
          left: left,
          top: top,
          width: f,
          height: f,
          child: Opacity(
            opacity: alpha,
            child: Image.asset(
              frames[idx],
              width: f,
              height: f,
              fit: BoxFit.contain,
              // ⚠️ 2026-09-29 玄参实测「画面一闪一闪」：逐帧切换 asset 时旧图会被
              // 立即丢弃、新图异步解码 → 中间白屏。gaplessPlayback 保留旧帧直到新帧
              // 就绪（配合 [didChangeDependencies] 的 precache），彻底消除闪烁。
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  /// 粒子图层：浇水水滴 / 施肥闪光，由同一控制器驱动，有限时长。
  Widget _particleLayer(double w, double h) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        return CustomPaint(
          size: Size(w, h),
          painter: _CareParticlesPainter(
            type: widget.type,
            progress: _ctrl.value,
          ),
        );
      },
    );
  }
}

/// 养护粒子绘制器：[CareEffectOverlay] 的 [CustomPaint] 后端。
///
/// 纯函数式绘制：给定 [type] + [progress]（0~1）即出图，便于无副作用单测。
class _CareParticlesPainter extends CustomPainter {
  final CareEffectType type;
  final double progress;

  const _CareParticlesPainter({required this.type, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (type == CareEffectType.water) {
      _paintWater(canvas, size);
    } else {
      _paintFertilize(canvas, size);
    }
  }

  /// 浇水：数颗水滴从格顶落到盆口（随进度错峰），到盆口处画小水花。
  void _paintWater(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint dropPaint = Paint()..color = kWaterColor;
    final Paint tailPaint = Paint()
      ..color = kWaterColor.withOpacity(0.5);
    final Paint splashPaint = Paint()
      ..color = kWaterColor.withOpacity(0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < kWaterDropCount; i++) {
      final double local =
          ((progress - i * kWaterDropStagger) / kWaterDropSpan).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // 每颗水滴固定横向偏移（确定性，避免随机导致测试抖动）。
      final double x = w * (0.5 + 0.18 * math.sin(i * 1.7));
      final double y = h *
          (kWaterDropStartYRatio +
              (kWaterDropEndYRatio - kWaterDropStartYRatio) * local);
      // 水滴：圆头 + 短尾（下落越快尾越长）。
      canvas.drawCircle(Offset(x, y), kWaterDropRadius, dropPaint);
      canvas.drawLine(
        Offset(x, y - kWaterDropRadius),
        Offset(x, y - kWaterDropRadius - 5 * (1 - local)),
        tailPaint,
      );
      // 到盆口（local≈1）时画小水花（四条短线）。
      if (local > 0.9) {
        final double s = (local - 0.9) / 0.1;
        for (int k = 0; k < 4; k++) {
          final double a = math.pi / 2 + (k - 1.5) * 0.5;
          canvas.drawLine(
            Offset(x, y),
            Offset(x + math.cos(a) * 8 * s, y - math.sin(a) * 8 * s),
            splashPaint,
          );
        }
      }
    }
  }

  /// 施肥：金色闪光粒子在盆上方闪烁上浮（类阳光闪烁），随进度错峰、淡入淡出。
  void _paintFertilize(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double baseY = h * 0.78;
    for (int i = 0; i < kFertilizeSparkCount; i++) {
      final double local =
          ((progress - i * kFertilizeSparkStagger) / kFertilizeSparkSpan)
              .clamp(0.0, 1.0);
      if (local <= 0) continue;
      final double cx = w * (0.5 + 0.22 * math.cos(i * 2.3));
      final double cy =
          baseY - h * kFertilizeSparkRiseRatio * local;
      // 闪烁：sin 包络让粒子在中段最亮、两端淡出。
      final double alpha = math.sin(local * math.pi);
      final Paint p = Paint()
        ..color = kFertilizeColor.withOpacity(alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(cx, cy),
        kFertilizeSparkRadius * (0.6 + 0.4 * alpha),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CareParticlesPainter old) =>
      old.type != type || (old.progress - progress).abs() > 1e-6;
}
