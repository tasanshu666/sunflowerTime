/// 花园页**天气动效层**（[GardenWeatherFx]）· 组件级测试
/// （第十批 2026-11-08 / 第十一批「太淡看不出来」 / **第十二批 2026-11-08
/// 「循环跳变 / 小雨看不出 / 暴雨像小雨 / 热浪看不出」之后更新口径**）。
///
/// ## 玄参口径
/// 本文件只钉**硬约束**，不钉像素：
///  · **① 9 型都在场**：每型都能画出粒子层，粒子数 ≤ 新上限
///    （晴 5 / 微风 18 / 云影 4 / 小雨 70 / 暴雨 140 / 干旱 24 / 大风 30 / 极寒 44），
///    且**远 / 近两层都在**，单帧绘制对象 ≤ 220；
///  · **② 日型 null ⇒ 整层不在场**（降级态：不建 controller、不画、不占层）；
///  · **③ 绝不挡交互**：`IgnorePointer.ignoring` 恒 true，且**真实点击探针**能穿透；
///  · **④ 可关停**：`animate == false` 时**不创建** `AnimationController`
///    （`transientCallbackCount == 0`、画固定静态进度）；`animate == true` 时进度推进
///    （**有界 `pump`**，绝不用 `pumpAndSettle`）；
///  · **⑤ 粒子固定种子** + 逐形状 α 上限；
///  · **⑥ 挂载守卫**：花园页根 Stack 里确实挂了 `GardenWeatherFx`（源码守卫）；
///  · **⑦ 循环无跳变**（第十二批新增，最高优先级）：所有循环元素在 `cycle 0 / 1`
///    以及两端 0.4% 内**整颗在屏外** —— 回绕发生在看不见的地方；
///  · **⑧ 云影错相位**（第十二批新增）：4 片相位 0/0.25/0.5/0.75，任何 t 屏内都有云；
///  · **⑨ 热浪波纹参数**（第十二批新增）：振幅 / 波长 / α / 数量都在施工单区间；
///  · **⑩ 小雨 vs 暴雨区分度**（第十二批新增）：条数、长度、粗细、斜角、速度、
///    雨雾 / 暗角层层递进。
///
/// ## 口径纪律
/// 期望值写死（上限数字来自玄参施工单），不引用实现常量自证。
library garden_weather_fx_test;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_fx.dart';

/// 判定「现在这一帧，这颗元素是否**完全看不见**」。
///
/// 第十三批口径：回绕点必须落在这里（`true`）⇒ 屏内看不到瞬移。
/// 判据是 [GardenWeatherFxGeometry.sample] 的 `isVisible`（几何 + 透明度斜坡同源），
/// 而不是「几何上是否出界」—— 云影带 3σ 光晕、α 斜坡也要算进去。
bool invisibleAt(GardenWeatherFxParticle p, Size size, double cycle) {
  return !GardenWeatherFxGeometry.sample(
    p,
    layer: size,
    cycle: cycle,
  ).isVisible;
}

void main() {
  /// 最小宿主：**不套 MaterialApp / Scaffold**（它们自带动画与 CustomPaint，
  /// 会污染 `transientCallbackCount` 与 `find.byType(CustomPaint)` 的断言）。
  Widget host(WeatherKind? kind, {bool animate = false}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 360,
          height: 480,
          child: Stack(
            children: <Widget>[
              // 底层：模拟「花盆 / 卡片」—— FX 必须让它照常被点到。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
              ),
              // 上层：动效层（真的在最上面，才有「挡不挡」的意义）。
              Positioned.fill(
                child: GardenWeatherFx(kind: kind, animate: animate),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 读 FX 层里的绘制器（唯一一个 `CustomPaint`，且在 FX 子树内）。
  GardenWeatherFxPainter painterOf(WidgetTester tester) {
    final Finder f = find.descendant(
      of: find.byKey(kGardenWeatherFxKey),
      matching: find.byType(CustomPaint),
    );
    return tester.widget<CustomPaint>(f).painter! as GardenWeatherFxPainter;
  }

  testWidgets('① 9 种日型都在场，粒子数 ≤ 第十二批上限，且远/近两层都在',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 上限写死（第十二批施工单：晴 5 / 微风 18 / 云影 4 / 小雨 70 / 暴雨 140 /
    // 干旱 24 / 大风 30 / 极寒 44）。
    const Map<WeatherKind, int> cap = <WeatherKind, int>{
      WeatherKind.sunny: 5,
      WeatherKind.breeze: 18,
      WeatherKind.cloudy: 4,
      WeatherKind.overcast: 4,
      WeatherKind.lightRain: 70,
      WeatherKind.rainstorm: 140,
      WeatherKind.drought: 24,
      WeatherKind.wind: 30,
      WeatherKind.cold: 44,
    };

    for (final WeatherKind kind in WeatherKind.values) {
      await tester.pumpWidget(host(kind));
      await tester.pump();

      expect(find.byKey(kGardenWeatherFxKey), findsOneWidget,
          reason: '$kind 必须有动效层（玄参：静态显示感觉差劲）');
      final GardenWeatherFxPainter painter = painterOf(tester);
      expect(painter.particleCount, greaterThan(0),
          reason: '$kind 必须真的有粒子（不能是空层）');
      expect(painter.particleCount, lessThanOrEqualTo(cap[kind]!),
          reason: '$kind 粒子数必须 ≤ ${cap[kind]}（第十二批放大后的硬上限）');
      expect(painter.kind, kind, reason: '绘制器按当日日型画');

      // 🔴 放大手法之一：**远 / 近双层**必须都在（否则又退回「一层很淡」）。
      final Set<GardenWeatherFxLayer> layers = buildGardenWeatherFxParticles(kind)
          .map((GardenWeatherFxParticle p) => p.layer)
          .toSet();
      expect(layers, contains(GardenWeatherFxLayer.far),
          reason: '$kind 必须有远层粒子（小而快、α 低）');
      expect(layers, contains(GardenWeatherFxLayer.near),
          reason: '$kind 必须有近层粒子（大而慢、α 高）');

      // 🔴 性能红线：单帧绘制对象（粒子 + 水花 + 光束 + 雨雾 + 暗角）≤ 220。
      expect(painter.drawableUpperBound, lessThanOrEqualTo(220),
          reason: '$kind 单帧绘制对象必须 ≤ 220（含派生水花）');
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('①b 雨系：水花上限按施工单（小雨 16 / 暴雨 28），且不生成长驻对象',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(WeatherKind.lightRain));
    await tester.pump();
    final GardenWeatherFxPainter light = painterOf(tester);
    expect(light.splashCap, 16, reason: '小雨同屏水花 ≤ 16');
    expect(light.drawableUpperBound, 86, reason: '小雨 70 雨丝 + 16 水花');

    await tester.pumpWidget(host(WeatherKind.rainstorm));
    await tester.pump();
    final GardenWeatherFxPainter storm = painterOf(tester);
    expect(storm.splashCap, 28, reason: '暴雨同屏水花 ≤ 28');
    expect(storm.particleCount, 140, reason: '暴雨雨丝 140 条');
    expect(storm.drawableUpperBound, 170,
        reason: '暴雨 140 雨丝 + 28 水花 + 雨雾 1 + 暗角 1 = 170（≤ 220）');

    // 水花是**绘制期派生**：粒子表里不能出现「水花粒子」（否则等于常驻对象）。
    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.lightRain,
      WeatherKind.rainstorm,
    ]) {
      final List<GardenWeatherFxParticle> ps =
          buildGardenWeatherFxParticles(kind);
      expect(ps.length, kind == WeatherKind.lightRain ? 70 : 140,
          reason: '$kind 粒子表只含雨丝，不含水花');
      expect(ps.every((GardenWeatherFxParticle p) =>
              p.shape == GardenWeatherFxShape.rain),
          isTrue,
          reason: '$kind 粒子表不得混入水花 / 其他形状');
    }

    // 干型没有水花。
    expect(buildGardenWeatherFxParticles(WeatherKind.sunny).length, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('② 日型为 null ⇒ 整层不在场（不建层 / 不画笔）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(null));
    await tester.pump();

    expect(find.byKey(kGardenWeatherFxKey), findsNothing,
        reason: '日型 null ⇒ 动效层不在树里（降级态不画氛围）');
    expect(
      find.descendant(
        of: find.byType(GardenWeatherFx),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
      reason: '日型 null ⇒ 连 CustomPaint 都不建',
    );
    // 也不许偷偷挂动画。
    expect(tester.binding.transientCallbackCount, 0,
        reason: '日型 null ⇒ 无 controller（零帧调度）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('③ 绝不挡交互：IgnorePointer 恒 true + 真实点击穿透到下层',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(WeatherKind.rainstorm));
    await tester.pump();

    taps = 0;
    final IgnorePointer gate =
        tester.widget<IgnorePointer>(find.byKey(kGardenWeatherFxKey));
    expect(gate.ignoring, isTrue,
        reason: 'FX 层必须忽略指针（玄参：雨雪不许遮挡点击）');

    // 🔴 真实探针：点在「FX 覆盖区域的正中心」，命中必须落到下层按钮上。
    await tester.tapAt(const Offset(195, 200));
    await tester.pump();
    expect(taps, 1, reason: '点 FX 覆盖区中心必须打到下层（FX 不吞点击）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('④ animate:false 不驱动动画（0 帧调度 + 固定静态进度）；animate:true 随时间推进',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // ── animate:false：不建 controller ⇒ 没有 transient frame callback ──
    // （用水花最密的暴雨：静态分支也必须真的走一遍水花绘制，且零帧。）
    await tester.pumpWidget(host(WeatherKind.rainstorm));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'animate:false ⇒ 不创建 AnimationController（沿用 garden_sign_hotspot 的关停机制）');
    final double p0 = painterOf(tester).progress;
    expect(p0, kGardenWeatherFxStaticProgress,
        reason: 'animate:false ⇒ 画固定静态进度（可截图、可复现）');
    await tester.pump(const Duration(seconds: 2));
    expect(painterOf(tester).progress, p0, reason: 'animate:false ⇒ 进度不随时间变');

    // ── animate:true：单 controller 循环，进度随帧推进 ──
    await tester.pumpWidget(host(WeatherKind.cold, animate: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'animate:true ⇒ controller.repeat() 在调度帧（有界 pump，禁 pumpAndSettle）');

    final double a0 = painterOf(tester).progress;
    await tester.pump(const Duration(milliseconds: 900));
    final double a1 = painterOf(tester).progress;
    expect(a1, isNot(a0), reason: '动效必须在动（进度随时间变化）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('④b 全型都真的画得出来（含光束 / 雨雾 / 暗角 / 水花 / 热浪分支），无异常',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    for (final WeatherKind kind in WeatherKind.values) {
      // 动画分支：pump 到水花 / 光束都在动的时刻。
      await tester.pumpWidget(host(kind, animate: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull,
          reason: '$kind（animate:true）绘制不得抛异常');

      // 🔴 拆树再建：既验证 dispose 安全，也让下一型拿到全新 State
      //（`SingleTickerProviderStateMixin` 一生只允许建一个 ticker，
      //  同 State 反复开关是另一种用法，这里不测）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // 静态分支：同一套绘制代码走 `animate:false`（固定 0.35，仍需画完所有分支）。
      await tester.pumpWidget(host(kind));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$kind（animate:false）静态绘制不得抛异常');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('⑤ 粒子固定种子：同日型两次生成逐位一致（不会每帧重新洗牌）',
      (WidgetTester tester) async {
    // 逐形状 α 上限（第十二批：叶片抬到 0.65、暴雨近层雨丝 0.62）。
    double ceilingOf(GardenWeatherFxShape shape) => switch (shape) {
          GardenWeatherFxShape.snow => 0.85,
          GardenWeatherFxShape.leaf => 0.65,
          GardenWeatherFxShape.rain => 0.62,
          GardenWeatherFxShape.windLine => 0.60,
          GardenWeatherFxShape.orb => 0.45,
          GardenWeatherFxShape.heatWave => 0.45,
          GardenWeatherFxShape.heat => 0.40,
          GardenWeatherFxShape.cloud => 0.20,
        };

    for (final WeatherKind kind in WeatherKind.values) {
      final List<GardenWeatherFxParticle> a =
          buildGardenWeatherFxParticles(kind);
      final List<GardenWeatherFxParticle> b =
          buildGardenWeatherFxParticles(kind);
      expect(a.length, b.length, reason: '$kind 粒子数稳定');
      for (int i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x, reason: '$kind 第 $i 颗 x 必须固定');
        expect(a[i].y, b[i].y, reason: '$kind 第 $i 颗 y 必须固定');
        expect(a[i].size, b[i].size, reason: '$kind 第 $i 颗 size 必须固定');
        expect(a[i].speed, b[i].speed, reason: '$kind 第 $i 颗 speed 必须固定');
        expect(a[i].phase, b[i].phase, reason: '$kind 第 $i 颗 phase 必须固定');
        expect(a[i].alpha, b[i].alpha, reason: '$kind 第 $i 颗 alpha 必须固定');
        expect(a[i].shape, b[i].shape, reason: '$kind 第 $i 颗形状必须固定');
        expect(a[i].layer, b[i].layer, reason: '$kind 第 $i 颗层归属必须固定');
        // α 上限：雪花最高 0.85（纯白大雪花），其他形状不得压过前景。
        expect(a[i].alpha, lessThanOrEqualTo(ceilingOf(a[i].shape)),
            reason: '$kind 第 $i 颗不透明度必须保守（≤${ceilingOf(a[i].shape)}）');
      }
    }
  });

  test('⑥ 挂载守卫：花园页根 Stack 里确实挂了 GardenWeatherFx（覆盖整屏）', () {
    final String src =
        File('lib/presentation/child/pages/garden_page.dart').readAsStringSync();
    expect(src.contains('kind: todayWeather.kind'), isTrue,
        reason: '花园页必须按当日日型挂载动效层（否则组件再对也看不到效果）');
    expect(src.contains("import 'package:sunflower_time/presentation/child/"
            "widgets/garden_weather_fx.dart';"),
        isTrue,
        reason: '花园页必须 import 动效层组件');
    // 🔴 第十三批根因 B：层高必须是**整屏**，不能停在花园菜地上沿
    //（停在 0.64 屏高 ⇒ 雪花/雨丝在屏幕中间被裁掉 ⇒「飘着飘着不见了」）。
    expect(src.contains('height: gardenPotAreaBottom(size),'), isFalse,
        reason: 'FX 层不得再用 gardenPotAreaBottom 当高度（实测只有屏高 64%）');
    expect(src.contains('groundY: gardenPotAreaBottom(size),'), isTrue,
        reason: '雨滴落地线仍应是花园菜地上沿（水花不该沉到屏幕最底）');
  });

  // ───────────────────────── 第十二批新增 ─────────────────────────

  test('⑦ 循环无跳变：所有循环元素在回绕两端（cycle 0 / 1）都完全看不见', () {
    // 三种画布尺寸都要成立（小屏的余量最紧）。
    const List<Size> canvases = <Size>[
      Size(360, 480),
      Size(390, 600),
      Size(768, 900),
    ];

    for (final Size size in canvases) {
      for (final WeatherKind kind in WeatherKind.values) {
        for (final GardenWeatherFxParticle p
            in buildGardenWeatherFxParticles(kind)) {
          if (p.shape == GardenWeatherFxShape.orb) continue;
          // 回绕点本身
          expect(invisibleAt(p, size, 0.0), isTrue,
              reason: '$kind/${p.shape} @$size：cycle=0 必须看不见（否则回绕可见）');
          expect(invisibleAt(p, size, 1.0), isTrue,
              reason: '$kind/${p.shape} @$size：cycle=1 必须看不见（否则回绕可见）');
          // 两端 0.4% 内（≈ 1~3px 位移）也必须还看不见 —— 防「只差一点点」。
          expect(invisibleAt(p, size, 0.004), isTrue,
              reason: '$kind/${p.shape} @$size：cycle≈0 附近仍看不见');
          expect(invisibleAt(p, size, 0.996), isTrue,
              reason: '$kind/${p.shape} @$size：cycle≈1 附近仍看不见');
        }
      }
    }
  });

  test('⑦b 云影行程 = 屏宽 + 云宽 + 2×3σ（不是 1.5 屏宽），屏内轨迹单调连续', () {
    const Size size = Size(390, 480);
    final Rect visible = Offset.zero & size;
    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.cloudy,
      WeatherKind.overcast,
    ]) {
      final List<GardenWeatherFxParticle> clouds = buildGardenWeatherFxParticles(
              kind)
          .where((GardenWeatherFxParticle p) =>
              p.shape == GardenWeatherFxShape.cloud)
          .toList();
      expect(clouds.length, 4, reason: '$kind 云影 4 片');

      for (final GardenWeatherFxParticle c in clouds) {
        final double w = c.size * size.width;
        const double halo = 2 * GardenWeatherFxGeometry.cloudHalo;
        final double x0 = GardenWeatherFxGeometry.horizontalCenterX(
          w,
          visible,
          0,
          halo: GardenWeatherFxGeometry.cloudHalo,
        );
        final double x1 = GardenWeatherFxGeometry.horizontalCenterX(
          w,
          visible,
          1,
          halo: GardenWeatherFxGeometry.cloudHalo,
        );
        // 行程必须真的覆盖「整朵云（含模糊光晕）完全出去」。
        expect(x1 - x0, greaterThan(size.width + w + halo),
            reason: '$kind 云影行程必须 > 屏宽 + 云宽 + 两侧光晕（不要为省时间缩短）');
        expect(x0 + (w + halo) / 2, lessThan(0),
            reason: '$kind 云影起点：光晕右缘已在屏左外');
        expect(x1 - (w + halo) / 2, greaterThan(size.width),
            reason: '$kind 云影终点：光晕左缘已在屏右外');

        // 屏内轨迹单调右移，且五等分采样点间隔均匀（无跳变）。
        double previous = x0;
        for (int i = 1; i <= 5; i++) {
          final double x = GardenWeatherFxGeometry.horizontalCenterX(
            w,
            visible,
            i / 5,
            halo: GardenWeatherFxGeometry.cloudHalo,
          );
          expect(x, greaterThan(previous), reason: '$kind 云影必须单调右移');
          expect((x - previous) - (x1 - x0) / 5, closeTo(0, 0.001),
              reason: '$kind 云影每段位移必须均匀（匀速 = 不卡顿）');
          previous = x;
        }
      }
    }
  });

  test('⑧ 云影 4 片相位 0/0.25/0.5/0.75 错开，且任何 t 屏内都有云（无空窗）', () {
    const Size size = Size(390, 480);
    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.cloudy,
      WeatherKind.overcast,
    ]) {
      final List<GardenWeatherFxParticle> clouds = buildGardenWeatherFxParticles(
              kind)
          .where((GardenWeatherFxParticle p) =>
              p.shape == GardenWeatherFxShape.cloud)
          .toList();
      expect(
        clouds.map((GardenWeatherFxParticle p) => p.phase).toSet(),
        <double>{0.0, 0.25, 0.5, 0.75},
        reason: '$kind 云影必须 4 片错相位（第十二批①：消除「一起消失」的空窗）',
      );

      for (int step = 0; step <= 100; step++) {
        final double t = step / 100;
        bool visible = false;
        for (final GardenWeatherFxParticle c in clouds) {
          // 🔴 第十三批：相位由**整数圈数**映射（与绘制完全同一个函数）。
          final double cycle = GardenWeatherFxGeometry.cycleOf(c, t);
          if (GardenWeatherFxGeometry.sample(
            c,
            layer: size,
            cycle: cycle,
          ).isVisible) {
            visible = true;
            break;
          }
        }
        expect(visible, isTrue,
            reason: '$kind t=$t 屏内必须有云影（任何时刻都不能空）');
      }
    }
  });

  test('⑨ 干旱热浪：10 条正弦气流线（振幅 6~14 / 波长 40~70 / α 0.35~0.45）'
      '+ 12 暖尘 + 2 暖光斑', () {
    final List<GardenWeatherFxParticle> ps =
        buildGardenWeatherFxParticles(WeatherKind.drought);
    expect(ps.length, 24, reason: '干旱粒子总数 24（施工单 22~24）');

    final List<GardenWeatherFxParticle> waves = ps
        .where((GardenWeatherFxParticle p) =>
            p.shape == GardenWeatherFxShape.heatWave)
        .toList();
    expect(waves.length, 10, reason: '施工单：8~10 条向上飘的波纹气流线');
    for (final GardenWeatherFxParticle w in waves) {
      expect(w.amplitude, inInclusiveRange(6, 14), reason: '振幅 6~14pt');
      expect(w.size, inInclusiveRange(40, 70), reason: '波长 40~70pt');
      expect(w.alpha, inInclusiveRange(0.35, 0.45), reason: '气流线 α 峰值 0.35~0.45');
      expect(w.stroke, greaterThanOrEqualTo(1.5),
          reason: '描边不能细到看不见（≥1.5pt）');
      // 近层要比远层慢（0.10~0.18 屏高/周期量级）。
      expect(w.speed, inInclusiveRange(0.08, 0.14),
          reason: '速度慢：一周期约走 0.11~0.20 屏高');
    }
    // 远 / 近两层都必须是气流线（双层的意义）。
    expect(
      waves.map((GardenWeatherFxParticle p) => p.layer).toSet().length,
      2,
      reason: '气流线必须远 / 近两层都有',
    );

    final List<GardenWeatherFxParticle> dust = ps
        .where((GardenWeatherFxParticle p) => p.shape == GardenWeatherFxShape.heat)
        .toList();
    expect(dust.length, 12, reason: '施工单：保留 8~12 个上升暖尘点');
    for (final GardenWeatherFxParticle d in dust) {
      expect(d.size, inInclusiveRange(3, 9), reason: '暖尘半径 3~9pt');
    }

    final List<GardenWeatherFxParticle> orbs = ps
        .where((GardenWeatherFxParticle p) => p.shape == GardenWeatherFxShape.orb)
        .toList();
    expect(orbs.length, 2, reason: '施工单：2 个脉动暖光斑');
    for (final GardenWeatherFxParticle o in orbs) {
      expect(o.size / 2, inInclusiveRange(50, 84), reason: '暖光斑半径 r 50~84');
      expect(o.alpha, inInclusiveRange(0.14, 0.20), reason: '暖光斑 α 0.14~0.20');
    }
  });

  test('⑩ 小雨 vs 暴雨：条数 / 长度 / 粗细 / 斜角 / 速度 / 氛围层层递进', () {
    final List<GardenWeatherFxParticle> light =
        buildGardenWeatherFxParticles(WeatherKind.lightRain);
    final List<GardenWeatherFxParticle> storm =
        buildGardenWeatherFxParticles(WeatherKind.rainstorm);

    expect(light.length, 70);
    expect(storm.length, 140);
    expect(storm.length, greaterThan(light.length * 1.8),
        reason: '暴雨条数必须明显多于小雨（倾盆体感）');

    List<GardenWeatherFxParticle> nearOf(List<GardenWeatherFxParticle> ps) => ps
        .where((GardenWeatherFxParticle p) =>
            p.layer == GardenWeatherFxLayer.near)
        .toList();
    final List<GardenWeatherFxParticle> lightNear = nearOf(light);
    final List<GardenWeatherFxParticle> stormNear = nearOf(storm);

    double avg(List<GardenWeatherFxParticle> ps, double Function(GardenWeatherFxParticle) f) =>
        ps.fold<double>(0, (double s, GardenWeatherFxParticle p) => s + f(p)) /
        ps.length;
    double avgAngleDegrees(List<GardenWeatherFxParticle> ps) =>
        avg(ps, (GardenWeatherFxParticle p) => p.slant) * 180 / math.pi;

    // 近层长度：小雨 ≈34，暴雨 44~56（≥ 1.3 倍且下限就比小雨长）。
    expect(avg(stormNear, (GardenWeatherFxParticle p) => p.size),
        greaterThan(avg(lightNear, (GardenWeatherFxParticle p) => p.size) * 1.3),
        reason: '暴雨近层雨丝必须明显更长');
    expect(stormNear.map((GardenWeatherFxParticle p) => p.size).reduce(math.min),
        greaterThan(lightNear.map((GardenWeatherFxParticle p) => p.size).reduce(math.max)),
        reason: '暴雨最短的近层雨丝也要长过小雨最长的近层雨丝');
    // 粗细：2.6 → 3.2
    expect(avg(stormNear, (GardenWeatherFxParticle p) => p.stroke),
        greaterThan(avg(lightNear, (GardenWeatherFxParticle p) => p.stroke)),
        reason: '暴雨雨丝更粗');
    // 斜角：6~8° → 14~16°（明显斜打）
    expect(avgAngleDegrees(light), inInclusiveRange(6, 8),
        reason: '小雨斜角 6~8°');
    expect(avgAngleDegrees(storm), inInclusiveRange(14, 16),
        reason: '暴雨斜角 14~16°（明显斜打）');
    // 速度：暴雨近层最慢的一根也快过小雨近层最快的一根。
    expect(stormNear.map((GardenWeatherFxParticle p) => p.speed).reduce(math.min),
        greaterThan(lightNear.map((GardenWeatherFxParticle p) => p.speed).reduce(math.max)),
        reason: '暴雨下落更快（扑面感）');
    // 远层也不要退回「细到看不见」。
    expect(light.map((GardenWeatherFxParticle p) => p.stroke).reduce(math.min),
        greaterThanOrEqualTo(1.2));
  });
}

/// 真实点击探针的命中计数（③ 用）。
int taps = 0;
