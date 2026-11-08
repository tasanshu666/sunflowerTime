/// 花园天气动效 · **帧连续性探针**（第十三批 2026-11-08 玄参复测：
/// 「云影 / 叶片 / 雪花都在同一个地方跳变，从左边走到右边又突然出现在左边」）。
///
/// ## 这个文件在钉什么
/// 玄参描述的是**肉眼可见的瞬移**，所以这里不钉「像素长什么样」，而是直接把
/// **时间 → 坐标**这条链路当被测对象：
///  · **⑪ 整圈扫描**：每个形状以 1/2000 步进扫过 cycle 0..1，断言元素**在可见区内**时
///    相邻两帧位移 ≤ 理论速度 × 1.5（跳变必然是数十~上千倍）；元素**完全看不见**时
///    （透明度斜坡已归零 / 整体出界）不追究位移 —— 这正是「出入场淡入淡出」的验收口径。
///  · **⑫ 云影**：任意 cycle 至少 1 片可见 + 中心位移连续。
///  · **⑬ 相位闭合**：`f(1) ≡ f(0)`。**这是旧实现真正翻车的地方**：旧相位是
///    `frac(phase + progress × speed)`，speed 是小数（0.014~2.0 圈 / 12s），
///    controller 由 1 回 0 时相位从 `frac(phase + speed)` 跳回 `frac(phase)` ⇒
///    位置瞬移 `frac(speed) × 行程`。实测（层 390×542.4，相邻两帧）：云影 36.0 / 17.0pt、
///    叶片 283.7pt、风线 371.0pt、小雨 534.3pt、暴雨 593.9pt、雪花 487.3pt、热浪 747.9pt，
///    而正常一帧只有 0.05~0.6pt ⇒ **同一个根因**，与横飘还是下落无关。
///  · **⑭ 玄参点名采样**：云 / 叶 / 雪在接缝两侧（0.98 / 0.995 / 0.9999 / 0 / 0.0001 /
///    0.005）的坐标逐个打印并断言过缝那一对连续。
///
/// 坐标全部来自生产代码的 [GardenWeatherFxGeometry.sample]（绘制用的同一个函数），
/// 探针不复制任何公式 ⇒ 改了生产实现的几何，这里会真的红。
library garden_weather_fx_continuity_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_fx.dart';

/// 扫一个 cycle 的步数（玄参施工单：1/2000）。
const int kProbeSteps = 2000;

/// 「算可见」的透明度下限。
///
/// 低于这个值时光晕/描边在真实合成后 < 2/255，肉眼就是「没有」。施工单允许
/// 「元素完全不可见（α≈0）时任意位移」，这里把 α≈0 量化成 0.02。
const double kVisibleAlpha = 0.02;

/// 抽样屏尺寸：手机竖屏两档 + 最小平板。
const List<Size> kProbeCanvases = <Size>[
  Size(390, 844),
  Size(360, 780),
  Size(768, 1024),
];

/// 一颗粒子走完**一个 cycle** 的总距离（= cycle 0 与 1 的中心距）。
double travelOf(GardenWeatherFxParticle p, Size layer) {
  final GardenWeatherFxSample a =
      GardenWeatherFxGeometry.sample(p, layer: layer, cycle: 0);
  final GardenWeatherFxSample b =
      GardenWeatherFxGeometry.sample(p, layer: layer, cycle: 1);
  return (b.center - a.center).distance;
}

/// 各形状的「附加摆动幅度」（正弦起伏 / 呼吸 / 横向摆动的峰峰值）。
///
/// 这部分位移不进 [travelOf]（它只算 cycle 0→1 的中心距），但确实存在于逐帧位移里，
/// 所以判定阈值要把它算进去 —— 否则「完全靠摆动动起来」的光斑会被误判成跳变。
double wobbleOf(GardenWeatherFxShape shape) => switch (shape) {
      GardenWeatherFxShape.orb => 24, // 漂移 14 + 呼吸 10
      GardenWeatherFxShape.leaf => 12,
      GardenWeatherFxShape.snow => 12,
      GardenWeatherFxShape.heat => 10,
      GardenWeatherFxShape.cloud => 0,
      GardenWeatherFxShape.rain => 0,
      GardenWeatherFxShape.windLine => 0,
      GardenWeatherFxShape.heatWave => 0,
    };

/// 单步理论位移上限 = （行程 + 摆动）/ 步数 × 1.5 + 1pt 余量。
double stepLimitOf(GardenWeatherFxParticle p, Size layer) =>
    (travelOf(p, layer) + wobbleOf(p.shape)) * p.cycles / kProbeSteps * 1.5 +
    1.0;

/// 该样本是否「肉眼可见」。
bool visible(GardenWeatherFxSample s, Rect view) =>
    s.opacity >= kVisibleAlpha && s.bounds.overlaps(view);

/// 探针主体：返回这个元素在**可见区内**相邻两帧的最大位移。
double worstVisibleStep(
  GardenWeatherFxParticle p,
  Size layer, {
  Rect? visibleRect,
}) {
  final Rect view = GardenWeatherFxGeometry.visibleOf(layer, visibleRect);
  double worst = 0;
  GardenWeatherFxSample? prev;
  for (int k = 0; k <= kProbeSteps; k++) {
    final GardenWeatherFxSample s = GardenWeatherFxGeometry.sample(
      p,
      layer: layer,
      cycle: k / kProbeSteps,
      visible: view,
    );
    if (prev != null && visible(prev, view) && visible(s, view)) {
      final double d = (s.center - prev.center).distance;
      if (d > worst) worst = d;
    }
    prev = s;
  }
  return worst;
}

/// **接缝探针**：进度 1 → 0 那一帧的位移（这才是玄参看到的跳变的真正位置）。
///
/// 步长取「**1/2000 个 cycle**」对应的进度（`1 / (2000 × 圈数)`），与 ⑪ 的循环内
/// 步长同粒度 —— 这样慢元素（雪花 30 圈）与快元素（暴雨 120 圈）的判定同等严格，
/// 也不会因为步长比「出场淡出区」还粗而误伤正常回绕。
/// 两端都可见时才追究 —— 若这一对正好压在元素自己的回绕点上（不可见），跳过。
double seamStep(
  GardenWeatherFxParticle p,
  Size layer, {
  Rect? visibleRect,
}) {
  final Rect view = GardenWeatherFxGeometry.visibleOf(layer, visibleRect);
  final double z = 1.0 / (kProbeSteps * p.cycles);
  final GardenWeatherFxSample a = GardenWeatherFxGeometry.sample(
    p,
    layer: layer,
    cycle: GardenWeatherFxGeometry.cycleOf(p, 1 - z),
    visible: view,
  );
  final GardenWeatherFxSample b = GardenWeatherFxGeometry.sample(
    p,
    layer: layer,
    cycle: GardenWeatherFxGeometry.cycleOf(p, z),
    visible: view,
  );
  if (!visible(a, view) || !visible(b, view)) return 0;
  return (b.center - a.center).distance;
}

/// 接缝单步的理论上限（跨 2 × 1/2000 个 cycle）。
double seamLimitOf(GardenWeatherFxParticle p, Size layer) =>
    (travelOf(p, layer) + wobbleOf(p.shape)) * 2 / kProbeSteps * 1.5 + 1.0;

void main() {
  test('⑪ 整圈扫描（1/2000）：可见区内相邻帧位移 ≤ 理论速度 × 1.5', () {
    for (final Size size in kProbeCanvases) {
      for (final WeatherKind kind in WeatherKind.values) {
        final List<GardenWeatherFxParticle> ps =
            buildGardenWeatherFxParticles(kind);
        for (int i = 0; i < ps.length; i++) {
          final GardenWeatherFxParticle p = ps[i];
          final double worst = worstVisibleStep(p, size);
          final double limit = stepLimitOf(p, size);
          expect(worst, lessThanOrEqualTo(limit),
              reason: '$kind #$i/${p.shape} @$size：可见区内相邻帧位移 '
                  '${worst.toStringAsFixed(2)}pt 超过上限 ${limit.toStringAsFixed(2)}pt '
                  '（整圈行程 ${travelOf(p, size).toStringAsFixed(1)}pt）'
                  '—— 这就是玄参看到的跳变');
          // 🔴 接缝（controller 由 1 回 0）：旧实现就是在这里把相位打断的。
          final double seam = seamStep(p, size);
          final double seamLimit = seamLimitOf(p, size);
          expect(seam, lessThanOrEqualTo(seamLimit),
              reason: '$kind #$i/${p.shape} @$size：进度 1→0 那一帧位移 '
                  '${seam.toStringAsFixed(2)}pt 超过上限 '
                  '${seamLimit.toStringAsFixed(2)}pt（周期接缝处相位不闭合）');
        }
      }
    }
  });

  test('⑫ 云影：任意 cycle 至少 1 片可见，且可见帧的中心位移连续', () {
    for (final Size size in kProbeCanvases) {
      final Rect view = Offset.zero & size;
      for (final WeatherKind kind in <WeatherKind>[
        WeatherKind.cloudy,
        WeatherKind.overcast,
      ]) {
        final List<GardenWeatherFxParticle> clouds =
            buildGardenWeatherFxParticles(kind)
                .where((GardenWeatherFxParticle p) =>
                    p.shape == GardenWeatherFxShape.cloud)
                .toList();
        expect(clouds.length, 4, reason: '$kind 必须 4 片云影');

        for (int k = 0; k <= kProbeSteps; k++) {
          final double t = k / kProbeSteps;
          bool any = false;
          for (final GardenWeatherFxParticle c in clouds) {
            final GardenWeatherFxSample s = GardenWeatherFxGeometry.sample(
              c,
              layer: size,
              cycle: GardenWeatherFxGeometry.cycleOf(c, t),
              visible: view,
            );
            if (visible(s, view)) {
              any = true;
              break;
            }
          }
          expect(any, isTrue,
              reason: '$kind @$size t=$t：任何时刻都必须有云影可见（不能出现空窗）');
        }

        for (final GardenWeatherFxParticle c in clouds) {
          final double limit = stepLimitOf(c, size);
          expect(worstVisibleStep(c, size), lessThanOrEqualTo(limit),
              reason: '$kind 云影中心位移必须连续（不丝滑 = 回绕点被看见）');
        }
      }
    }
  });

  test('⑬ 相位闭合 f(1) ≡ f(0)：整数圈数 ⇒ controller 回 0 时位置逐位相同', () {
    const Size size = Size(390, 844);
    final Rect view = Offset.zero & size;
    for (final WeatherKind kind in WeatherKind.values) {
      for (final GardenWeatherFxParticle p
          in buildGardenWeatherFxParticles(kind)) {
        expect(GardenWeatherFxGeometry.cycleOf(p, 1.0),
            closeTo(GardenWeatherFxGeometry.cycleOf(p, 0.0), 1e-12),
            reason: '$kind/${p.shape}：cycle(1) 必须等于 cycle(0)');
        final GardenWeatherFxSample a = GardenWeatherFxGeometry.sample(
            p, layer: size, cycle: GardenWeatherFxGeometry.cycleOf(p, 0.0), visible: view);
        final GardenWeatherFxSample b = GardenWeatherFxGeometry.sample(
            p, layer: size, cycle: GardenWeatherFxGeometry.cycleOf(p, 1.0), visible: view);
        expect((a.center - b.center).distance, lessThanOrEqualTo(1e-9),
            reason: '$kind/${p.shape}：接缝两侧坐标必须逐位相同（旧实现这里瞬移 '
                'frac(speed) × 行程）');
      }
    }
  });

  test('⑭ 玄参点名采样：云 / 叶 / 雪在接缝两侧的坐标（过缝那一对必须连续）', () {
    const Size size = Size(390, 844);
    final Rect view = Offset.zero & size;
    const Map<WeatherKind, GardenWeatherFxShape> named =
        <WeatherKind, GardenWeatherFxShape>{
      WeatherKind.cloudy: GardenWeatherFxShape.cloud,
      WeatherKind.breeze: GardenWeatherFxShape.leaf,
      WeatherKind.cold: GardenWeatherFxShape.snow,
    };
    // 玄参施工单点名的六个 t（0.9999 → 0 即 controller 由 1 回 0 的那一帧）。
    const List<double> seam = <double>[
      0.98,
      0.995,
      0.9999,
      0.0,
      0.0001,
      0.005,
    ];
    for (final MapEntry<WeatherKind, GardenWeatherFxShape> e
        in named.entries) {
      final GardenWeatherFxParticle p = buildGardenWeatherFxParticles(e.key)
          .firstWhere((GardenWeatherFxParticle q) => q.shape == e.value);
      final List<Offset> path = <Offset>[
        for (final double t in seam)
          GardenWeatherFxGeometry.sample(
            p,
            layer: size,
            cycle: GardenWeatherFxGeometry.cycleOf(p, t),
            visible: view,
          ).center,
      ];
      // 打表（报告里引用这些数字）。
      for (int i = 0; i < seam.length; i++) {
        // ignore: avoid_print
        print('SEAM ${e.key.name}/${e.value.name} t=${seam[i]} '
            'x=${path[i].dx.toStringAsFixed(3)} y=${path[i].dy.toStringAsFixed(3)}');
      }
      // 🔴 过缝那一对（0.9999 → 0.0）必须只剩「1/10000 圈」的正常位移；
      //    唯一例外是**这一对正好跨过元素自己的回绕点**（相位 0 的云就是这种），
      //    此时两端都必须完全看不见 —— 回绕发生在看不见的时候才是合法的。
      final double seamJump = (path[3] - path[2]).distance;
      // 0.0001 的进度 = 0.0001 × 圈数 个 cycle。
      final double perStep = travelOf(p, size) * p.cycles * 0.0001;
      final GardenWeatherFxSample a = GardenWeatherFxGeometry.sample(
        p,
        layer: size,
        cycle: GardenWeatherFxGeometry.cycleOf(p, seam[2]),
        visible: view,
      );
      final GardenWeatherFxSample b = GardenWeatherFxGeometry.sample(
        p,
        layer: size,
        cycle: GardenWeatherFxGeometry.cycleOf(p, seam[3]),
        visible: view,
      );
      final bool invisibleWrap = !visible(a, view) && !visible(b, view);
      if (!invisibleWrap) {
        expect(seamJump, lessThanOrEqualTo(perStep * 1.5 + 0.5),
            reason: '${e.key}/${e.value}：接缝 0.9999 → 0 位移 '
                '${seamJump.toStringAsFixed(3)}pt（理论 ${perStep.toStringAsFixed(3)}pt）'
                '—— 旧实现这里是 '
                '${(travelOf(p, size) * (p.speed % 1)).toStringAsFixed(1)}pt 级瞬移');
      } else {
        expect(a.opacity, 0,
            reason: '${e.key}/${e.value}：跨回绕点时必须是「看不见」的状态');
      }
    }
  });

  test('⑮ 主循环 = 参考周期 × 整数倍；每颗粒子的圈数都是正整数且来自 speed', () {
    expect(
      kGardenWeatherFxLoopPeriod.inSeconds,
      kGardenWeatherFxPeriod.inSeconds * kGardenWeatherFxLoopFactor,
      reason: '主循环必须是参考周期的整数倍（否则「整数圈数」无从谈起）',
    );
    for (final WeatherKind kind in WeatherKind.values) {
      for (final GardenWeatherFxParticle p
          in buildGardenWeatherFxParticles(kind)) {
        expect(p.cycles, greaterThanOrEqualTo(1),
            reason: '$kind/${p.shape}：圈数至少 1（0 圈 = 静止）');
        final double nominal = p.speed * kGardenWeatherFxLoopFactor;
        expect((p.cycles - nominal).abs(), lessThanOrEqualTo(0.5),
            reason: '$kind/${p.shape}：圈数必须来自 round(speed × 60)，不许手改速度');
      }
    }
  });

  test('⑯ 雪花：纵向不再是「层底裁切」，而是整屏 + 底部余量', () {
    // 第十三批根因 B 的数值口径：可见区高 844 时，雪花的回绕点必须在屏底**以下**。
    const Size size = Size(390, 844);
    for (final GardenWeatherFxParticle p in buildGardenWeatherFxParticles(
            WeatherKind.cold)
        .where((GardenWeatherFxParticle p) =>
            p.shape == GardenWeatherFxShape.snow)) {
      final double y0 = GardenWeatherFxGeometry.sample(
        p,
        layer: size,
        cycle: 0,
      ).center.dy;
      final double y1 = GardenWeatherFxGeometry.sample(
        p,
        layer: size,
        cycle: 1,
      ).center.dy;
      expect(y1, greaterThan(size.height + p.size * 0.5),
          reason: '雪花终点必须在屏底之下（≥ 半个自身 + 边距），否则会在屏内消失');
      expect(y0, lessThan(-p.size * 0.5),
          reason: '雪花起点必须在屏顶之上');
      // 行程必须覆盖整屏（旧实现只到 0.64 屏高）。
      expect(y1 - y0, greaterThan(size.height),
          reason: '纵向行程必须 > 屏高（旧实现用层高 542pt，差 301pt）');
    }
  });

  test('⑰ 兼容性：把可见区参数化成「比层更矮的花园带」也不会露出回绕点', () {
    // 施工单要求 visibleRect **参数化、不许写死**：这里显式传一个更小的可见区，
    // 断言几何仍以它为准（回绕点落在它的外面）。
    const Size layer = Size(390, 844);
    const Rect gardenBand = Rect.fromLTWH(0, 0, 390, 542.4);
    for (final WeatherKind kind in WeatherKind.values) {
      for (final GardenWeatherFxParticle p
          in buildGardenWeatherFxParticles(kind)) {
        if (p.shape == GardenWeatherFxShape.orb) continue;
        for (final double c in <double>[0.0, 1.0]) {
          final GardenWeatherFxSample s = GardenWeatherFxGeometry.sample(
            p,
            layer: layer,
            cycle: c,
            visible: gardenBand,
          );
          expect(s.opacity, 0,
              reason: '$kind/${p.shape} @cycle=$c：必须落在传入的可见区之外');
        }
        // 屏内（这条带内）的位移仍连续。
        final double worst = worstVisibleStep(p, layer, visibleRect: gardenBand);
        final double limit = travelOf(p, layer) / kProbeSteps * 1.5 + 1.0;
        expect(worst, lessThanOrEqualTo(limit),
            reason: '$kind/${p.shape}：参数化可见区下仍必须连续');
      }
    }
  });
}
