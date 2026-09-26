/// 养护成功的一次性视觉反馈（浇水 / 施肥），叠在花园页对应花盆格之上。
///
/// ## 行为
///  · 纯代码粒子（[CustomPaint] / [Stack]），总时长 ≤ [kCareEffectDurationMs] 毫秒，**有限**，
///    可被 `pumpAndSettle()` 正常结束（测试硬要求），绝不引入无限循环动画；
///  · **浇水**：数颗水滴从植物上方落下 → 到盆口处消失（带小水花），植物轻微左右摇摆；
///  · **施肥**：金色 / 暖黄闪光粒子在盆上方闪烁上浮（类阳光闪烁），植物轻微弹跳；
///  · **共同反馈**：植物图小幅 elasticOut 缩放弹跳（幅度小，别夸张）。
///  · 所有动效参数收敛到文件顶部命名常量，**禁止散在 build 里**。
///
/// ## 序列帧预留接口（2026-09：先代码后序列帧）
/// [frames] 为可选参数（默认 null）：传入「帧 asset 路径列表」时，改为逐帧轮播
/// `Image.asset(frame)` 替代代码粒子（整层叠加在花盆之上，覆盖植物区）。
/// 未来序列帧命名约定：放 `assets/plants/fx_water_01.png` / `fx_water_02.png` … 式命名，
/// 最终命名以 `docs/植物成长动画方案_种子到成株_v1.md` 为准（产品经理编写中，本轮按此风格预留）。
/// **本轮不新增任何 png 资产、不改 pubspec。**
library care_effect_overlay;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';

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

/// 浇水 + 共同：植物左右摇摆幅度（弧度，约 3.4°，别夸张）。
const double kPlantSwayAngle = 0.06;

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

/// 共同：弹性缩放幅度（±6%，别夸张）。
const double kPlantBounceScale = 0.06;

/// 施肥：植物轻微弹跳的位移上限（逻辑像素）。
const double kPlantBounceTranslate = 6.0;

/// 植物图占格宽比例（与花园格一致，保证叠加层与原植物对齐）。
const double kPlantArtWidthRatio = 0.86;

/// 植物图宽高比（宽:高 = 3:5，与美术画布 1200×2000 一致）。
const double kPlantArtAspect = 5 / 3;

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

  /// 被养护的植物（用于叠加一层「会弹跳的植物图副本」，让植物本身看起来在动）。
  /// 为 null 时仅播放粒子，不绘制植物副本（测试可空构造）。
  final Plant? plant;

  /// [plant] 对应的物种（与 [plant] 配对传入）。
  final PlantSpecies? species;

  /// 序列帧接口（预留）：非 null 时逐帧轮播这些 asset 替代代码粒子。
  /// 列表顺序即播放顺序；本轮恒为 null（不新增 png 资产）。
  final List<String>? frames;

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
    duration: const Duration(milliseconds: kCareEffectDurationMs),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
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
                  _frameLayer(w, h) // 序列帧路径（预留）
                else ...<Widget>[
                  _plantLayer(w, h), // 植物弹跳副本（在粒子下方）
                  _particleLayer(w, h), // 代码粒子
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 序列帧路径（预留接口）：逐帧轮播 `Image.asset(frame)` 替代代码粒子。
  ///
  /// 资源缺失时不崩（errorBuilder 兜底空），但本轮不会传入 frames。
  Widget _frameLayer(double w, double h) {
    final List<String> frames = widget.frames!;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final int idx =
            (_ctrl.value * frames.length).floor().clamp(0, frames.length - 1);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Image.asset(
              frames[idx],
              width: w,
              height: h,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  /// 植物图层：在格顶居中绘制植物图副本（与底层同图），施加 elasticOut 缩放 + 摇摆 / 弹跳。
  ///
  /// 与底层原植物像素对齐，静止时完全覆盖、看不出重影；动画期间副本轻微形变，
  /// 视觉上即「植物在弹跳 / 摇摆」。无 [plant] 时不绘制（仅粒子）。
  Widget _plantLayer(double w, double h) {
    if (widget.plant == null || widget.species == null) {
      return const SizedBox.shrink();
    }
    final double artW = w * kPlantArtWidthRatio;
    // 高度不超过「格高 - 底部标签区（约 40）」，避免溢出格框。
    final double artH = (artW * kPlantArtAspect).clamp(0, h - 40);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final double t = _ctrl.value;
        // 共同：从略小弹性回弹到 1.0（elasticOut）。
        final double scale = Tween<double>(begin: 1 - kPlantBounceScale, end: 1.0)
            .evaluate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
        double angle = 0;
        double ty = 0;
        if (widget.type == CareEffectType.water) {
          // 浇水：左右摇摆，随时间衰减。
          angle = math.sin(t * 3 * math.pi) * kPlantSwayAngle * (1 - t);
        } else {
          // 施肥：轻微向上弹跳，随时间衰减。
          ty = -math.sin(t * math.pi) * kPlantBounceTranslate * (1 - t);
        }
        return Positioned(
          top: 0,
          left: (w - artW) / 2,
          width: artW,
          height: artH,
          child: Transform.translate(
            offset: Offset(0, ty),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: PlantArtwork(
                  plant: widget.plant!,
                  species: widget.species!,
                  size: artW,
                ),
              ),
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
