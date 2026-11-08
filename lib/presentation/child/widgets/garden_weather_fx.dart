/// 花园页**天气动效层**（第十批 2026-11-08 玄参：「静态显示感觉差劲」；
/// 第十一批「太淡看不出来，要加大加多」；**第十二批 2026-11-08 玄参复看 4 项问题**）。
///
/// ## 职责（纯表现，零业务）
/// 按今日日型画一层氛围粒子：晴=光斑呼吸 + 斜扫光束、微风=叶片横飘、多云/阴=云影横移、
/// 小雨/暴雨=雨丝下落 + 触底水花（暴雨另有雨雾底层 + 暗角）、干旱=上飘的热气波纹 +
/// 暖尘 + 暖光斑、大风=横向风线 + 快飘叶片、极寒=三档纯白雪花飘落自转。
/// **不读天气、不读钟、不读账本**：日型由页面 `todayWeatherProvider` 快照传进来
/// （A2-1 / A3 §13 源码守卫不变）。
///
/// ## 第十二批修的 4 件事（玄参原话 → 手法）
///  · **① 循环跳变**（「乌云投影移到最后突然回到刚开始，卡顿一下」）：三种横向运动都
///    存在「行程两端仍在屏内，周期末瞬移回起点」。现在全部经 [GardenWeatherFxGeometry]
///    按「自身尺寸 + 屏宽 + 两侧安全边距」走完 —— `cycle == 0` 与 `cycle == 1` 时元素
///    **整颗在屏外**，回绕发生在看不见的地方。云影另加 4 片 `0.25` 错相位，
///    任何时刻屏内都有云、不会一起消失。
///  · **② 小雨看不出来**：40 → 70 条（远 40 长 18/粗 1.2，近 30 长 34/粗 2.6），
///    斜角 6~8°，水花 16。
///  · **③ 暴雨像小雨**：85 → 140 条（近层长 44~56 / 粗 3.2 / 速度 1.6~2.0），
///    斜角 14~16° 明显斜打 + 整屏极淡雨雾底层（α ≤ 0.10）+ 暗角 α ≤ 0.12 + 水花 28。
///  · **④ 热浪看不出来**：抽象颗粒改成 **10 条上飘正弦气流线**（振幅 6~14pt、
///    波长 40~70pt、波峰随 t 滚动），保留 12 个暖尘点 + 2 个脉动暖光斑。
///
/// ## 第十三批（2026-11-08 玄参复测：「云影 / 叶片 / 雪花**都在同一个地方**跳变，
/// 从左边走到右边又突然出现在左边，不丝滑」）—— 真正的根因与三处修法
///
/// ### 根因 A（**真凶**）：`cycle = (phase + t · speed) % 1` 在 controller 由 1 回 0 时**不闭合**
/// `speed` 是「每 12s 走几圈」的小数（0.014 / 0.058 / 0.32 / 0.6 …）。t 从 1 掉回 0 的
/// 那一帧，相位从 `frac(phase + speed)` 直接跳回 `frac(phase)` —— 位置瞬移
/// `speed × 行程`。实测（390×844，[t=1 → 0] 相邻两帧）：云影 36.0pt / 17.0pt、
/// 叶片 283.7pt、风线 371.0pt、雨丝 534~594pt、雪花 487.3pt、热浪 747.9pt。
/// 对照：正常一帧只有 0.05~0.6pt ⇒ 跳变是正常速度的 **数十~上千倍**。
/// 这正是玄参说的「都是同一个问题」：**周期接缝处的相位断裂**，与元素是横飘还是下落无关。
/// ⇒ 修法：**每个元素的圈数必须是整数**。控制器周期拉长到
/// [kGardenWeatherFxLoopPeriod]（12s × [kGardenWeatherFxLoopFactor] = 12 分钟），
/// 每颗粒子的 `cycles = round(speed × 60)`（最少 1 圈），于是
/// `cycle(t=1) = frac(phase + cycles) = frac(phase) = cycle(t=0)`，**逐位闭合**，
/// 而行程速度几乎不变（圈数取整带来的偏差 ≤ 半圈 / 12 分钟）。
///
/// ### 根因 B：FX 层 rect 只有屏高的 **64%**，雪花/雨丝在**屏幕中间**就被裁掉
/// 挂载点当年写的是 `height: gardenPotAreaBottom(size)`（背景菜地上沿）。实测
/// （`getRect(kGardenWeatherFxKey)` vs `Scaffold` body）：390×844 → 层高 542.4、
/// 差 **301.6pt（35.7% 屏高）**；360×780 → 500.9/780，差 278.9（35.8%）；
/// 430×932 → 598.7/932，差 333.3（35.8%）；768×1024 → 749.0/1024，差 275.0（26.9%）。
/// 层底以上的雪片被 `clipRect` 硬切 ⇒ 「飘着飘着突然没了」（再叠上根因 A 就是「跳一下」）。
/// ⇒ 修法：层高直接覆盖**整屏**（`height: size.height`），纵向行程以
/// [GardenWeatherFxGeometry] 的**可见区 rect**（可参数化，默认 = 层 rect）为基准，
/// 两端各留 `自身尺寸 + [kGardenWeatherFxWrapMargin]` 的屏幕外余量；雨滴「落地」
/// 仍钉在背景菜地上沿（页面传入 `groundY`），水花不会被推到屏幕外的底栏后面。
///
/// ### 根因 C：模糊 / 描边的视觉尺寸没算进余量
/// 云影用 `MaskFilter.blur(sigma=10)`，可见光晕约 3σ = 30pt，而余量只有
/// [kGardenWeatherFxWrapMargin] = 12 ⇒ 几何上「整颗已出屏」时光晕还挂在屏内。
/// ⇒ 修法：云影的行程两端各再加 [GardenWeatherFxGeometry.cloudHalo]（= 3σ）。
///
/// ### 兜底：**进出视野的透明度斜坡**（所有循环元素）
/// 每类元素按「包围盒到可见区边缘的距离」算 α：进入侧 `8%` 视野宽/高处从 0 → 1，
/// 离开侧同理从 1 → 0（斜坡长度至少半个元素尺寸，大云影按「已露出比例」淡入）。
/// 这样即使将来某个元素因参数变化把回绕点落进可见区，肉眼看到的也是「淡出→淡入」
/// 而不是硬切。**斜坡只作用在该元素的运动轴上**（横飘只看 x、下落 / 上浮只看 y），
/// 否则贴着屏幕左边的雪花会被误判成「正在入场」而整体偏暗。
///
/// ## 三条硬约束（原样保留）
///  · 🔴 **绝不挡交互**：整层 `IgnorePointer`（`ignoring` 恒 true）。
///  · 🔴 **绝不重绘整页**：`RepaintBoundary` 隔离 + **单个** `AnimationController` 驱动
///    一个 `CustomPainter`（`repaint:` 直连 controller ⇒ 每帧只走 paint，不 rebuild
///    组件树）。随机数用**按日型 + 层号固定的种子**（同一日型每帧起点一致，不会闪烁）。
///  · 🔴 **无限循环动画必须可关**：[animate] 沿用仓库既有机制（`garden_sign_hotspot.dart`
///    的 `animate` 开关 —— `AnimationController?` 为 null 即「不创建、不启动」，`dispose`
///    用 `?.`）。`animate == false` 时**纯静态一张图、零帧重绘**。
///
/// ## 挂载位置（见 `garden_page.dart` 根 Stack）
/// 背景图**之上**、植物网格 / 卡片**之下**：雨雪落在草地与花盆后方，不遮挡文字与点击。
/// 范围 = **整屏**（第十三批根因 B：原来只到 `gardenPotAreaBottom`，雪花在屏幕中间
/// 被裁掉）。横飘元素仍只掠过上方 66% 的「活动带」，雨滴的落地线由 `groundY` 指定。
///
/// ## 性能口径（第十三批复核）
///  · 单帧 draw 对象上限 [kGardenWeatherFxMaxDrawables] = 220（暴雨最重：
///    140 雨丝 + 28 水花 + 雨雾 1 + 暗角 1 ≈ 170；其余日型远低于此）。
///    全是线段 / 圆 / 一条渐变矩形，Flutter 侧压力小。
///  · **不每帧 new 渐变**：光斑 / 光束 / 暗角 / 雨雾 / 热浪波纹的 shader 按
///    「量化尺寸 + α」缓存；**Paint / Path / MaskFilter 全部复用**，稳态下无 Paint 分配。
///  · 第十三批新增的几何样本 [GardenWeatherFxSample] 是每帧每颗可见粒子一个**小的
///    不可变记录**（center + bounds + opacity）。量级与旧实现每帧现算的 `Rect` / `Offset`
///    相同（旧实现每颗也要 new 2~3 个），不影响 60fps；换来的是「绘制坐标」与
///    「探针断言坐标」**同源**，跳变不可能再藏起来。
///  · **不每帧做文字布局**：本层**零文字**；热浪波纹的 `Path` 复用同一个实例。
library garden_weather_fx;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';

/// 动效层根节点（`IgnorePointer`）的稳定 Key —— 测试按它断言「在场 / 不在场」，
/// 也用它读 `IgnorePointer.ignoring`（本层永不吞点击）。
const Key kGardenWeatherFxKey = ValueKey<String>('garden_weather_fx');

/// 每类元素「进场 / 离场」的**参考**周期 = **12s**（`speed` 字段的单位：
/// 每 12s 走过的圈数）。⚠️ 它**不是** controller 的周期（见 [kGardenWeatherFxLoopPeriod]）。
const Duration kGardenWeatherFxPeriod = Duration(seconds: 12);

/// controller 的真实循环周期 = 12s × [kGardenWeatherFxLoopFactor] = **12 分钟**。
///
/// 🔴 第十三批根因 A：controller 由 1 回 0 时 `cycle` 必须闭合 ⇒ 每颗粒子的圈数
/// 必须是**整数**。云影要「慢到看不出在动」（≈0.014~0.058 圈 / 12s），只有把主循环
/// 拉长到分钟级，取整后才不会把速度改掉一个数量级（最慢的一档 12 分钟 1 圈）。
const Duration kGardenWeatherFxLoopPeriod = Duration(minutes: 12);

/// 主循环 = 参考周期的多少倍（= 12min / 12s = 60）。粒子圈数 =
/// `round(speed × 本值)`，最少 1 圈。
///
/// ⚠️ 常量表达式里不能读 `Duration.inSeconds`，故写死 60 —— 与上面两个
/// `Duration` 常量的比值必须一致（测试直接断言 `loop / period == 本值`）。
const int kGardenWeatherFxLoopFactor = 60;


/// `animate == false` 时使用的**静态快照进度**（定值 ⇒ 同一帧永远同一张图）。
const double kGardenWeatherFxStaticProgress = 0.35;

/// 循环元素入场 / 出场的安全边距（px）。
///
/// 🔴 第十二批①的根因就是「没有这条边距」：元素在两头还留在屏内就回绕。
/// 现在所有循环元素在 `cycle == 0` 与 `cycle == 1` 时都**整颗**位于屏外 ≥ 这个距离。
const double kGardenWeatherFxWrapMargin = 12;

/// **单帧绘制对象硬上限** = 220。
///
/// 第十二批「暴雨要做出倾盆感」（140 雨丝 + 28 水花 + 雨雾 + 暗角 ≈ 170），
/// 其余日型远低于此。这条是性能红线，测试直接断言。
const int kGardenWeatherFxMaxDrawables = 220;

/// 各日型的**粒子数上限**（硬上限，测试逐型断言）。
///
/// 第十二批新值（括号为第十一批旧值）：晴 5、微风 14→18、云影 4、小雨 40→70、
/// 暴雨 85→140、干旱 22→24（10 气流线 + 12 暖尘 + 2 暖光斑）、大风 24→30
/// （风线 24 + 叶 6）、极寒 44。
/// **水花不落在这里**（帧内派生、非常驻对象，见 [GardenWeatherFxPainter.splashCap]）。
const Map<WeatherKind, int> kGardenWeatherFxParticleCap = <WeatherKind, int>{
  WeatherKind.sunny: 5, // 光斑
  WeatherKind.breeze: 18, // 叶片（旧 14）
  WeatherKind.cloudy: 4, // 云影
  WeatherKind.overcast: 4, // 云影
  WeatherKind.lightRain: 70, // 雨丝（旧 40）
  WeatherKind.rainstorm: 140, // 雨丝（旧 85）
  WeatherKind.drought: 24, // 气流线 10 + 暖尘 12 + 暖光斑 2（旧 22）
  WeatherKind.wind: 30, // 风线 24 + 叶片 6（旧 24）
  WeatherKind.cold: 44, // 雪花
};

/// 粒子形状（绘制分支）。
enum GardenWeatherFxShape {
  /// 晴 / 干旱点缀：淡金光斑，缓慢漂移 + 呼吸。
  orb,

  /// 微风 / 大风：小叶片横向飘 + 轻微上下起伏。
  leaf,

  /// 多云 / 阴：淡灰云影缓慢横移（阴天更暗更慢）。
  cloud,

  /// 小雨 / 暴雨：雨丝下落（带斜角），触底生成水花。
  rain,

  /// 干旱：上升的暖尘点（半径 = [GardenWeatherFxParticle.size]）。
  heat,

  /// 干旱：向上飘的**正弦气流线**（波长 = [size]，振幅 = [amplitude]）。
  heatWave,

  /// 大风：较快横向风线。
  windLine,

  /// 极寒：纯白雪花飘落（圆 + 三根枝 + 自转，不引入任何彩色）。
  snow,
}

/// 粒子所属层（决定观感权重；雨系近层更快，其余近层更慢更大）。
enum GardenWeatherFxLayer {
  /// 远层：小、快、α 低 —— 背景氛围。
  far,

  /// 近层：大、慢、α 高 —— 主体（雨系为「更快更长」）。
  near,
}

/// 一颗粒子（**归一化坐标**，绘制时乘画布尺寸）。
@immutable
class GardenWeatherFxParticle {
  /// 构造。
  const GardenWeatherFxParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.alpha,
    required this.shape,
    required this.layer,
    required this.color,
    this.stroke = 1.0,
    this.slant = 0,
    this.amplitude = 0,
    this.sizeIsFractionOfWidth = false,
    this.cycles = 1,
  });

  /// 归一化起点 x（0..1；横向循环元素不使用，位移完全由 cycle 决定）。
  final double x;

  /// 归一化起点 y（0..1）。
  final double y;

  /// 尺寸：线段长度 / 圆半径 / 雪花直径 / 云影直径（云影按画布宽的**比例**解释）/
  /// 热浪波长。
  final double size;

  /// 一个周期内走过的**圈数**（相对 12s 参考周期 [kGardenWeatherFxPeriod]）。
  ///
  /// 仅作**观感参数**（速度档位 / 水花寿命换算）；真正驱动相位的是 [cycles]。
  final double speed;

  /// 一个主循环（[kGardenWeatherFxLoopPeriod]）内走过的**整圈数**。
  ///
  /// 🔴 第十三批根因 A 的修法：必须是**整数**，否则 controller 由 1 回 0 时
  /// `frac(phase + cycles)` ≠ `frac(phase)` ⇒ 整颗元素瞬移。生成时由
  /// `round(speed × kGardenWeatherFxLoopFactor)` 得到（最少 1 圈），
  /// 所以速度档位与 [speed] 几乎一致（偏差 ≤ 半圈 / 12 分钟）。
  final int cycles;

  /// 相位偏移（0..1），保证粒子不同步。
  final double phase;

  /// 本色不透明度。
  final double alpha;

  /// 绘制分支。
  final GardenWeatherFxShape shape;

  /// 远 / 近层（决定 α 与速度档位，生成时已固化到字段里）。
  final GardenWeatherFxLayer layer;

  /// 本颗粒子的颜色（自带，绘制时不再查配置表）。
  final Color color;

  /// 线宽（雨丝 / 风线 / 气流线）；其他形状忽略。
  final double stroke;

  /// 斜角（弧度，雨丝用；正值 = 向右下）。
  final double slant;

  /// 热浪气流线的**横向振幅**（pt），其他形状为 0。
  final double amplitude;

  /// true ⇒ [size] 解释为「画布宽的比例」（云影用）。
  final bool sizeIsFractionOfWidth;
}

/// 一个**图层**的粒子配置（远 / 近各一条，混合形状也可多条）。
@immutable
class _FxLayer {
  const _FxLayer({
    required this.shape,
    required this.count,
    required this.color,
    required this.sizeMin,
    required this.sizeMax,
    required this.speedMin,
    required this.speedMax,
    required this.alphaMin,
    required this.alphaMax,
    this.layer = GardenWeatherFxLayer.far,
    this.strokeMin = 1.0,
    this.strokeMax = 1.0,
    this.slantDegrees = 0,
    this.amplitudeMin = 0,
    this.amplitudeMax = 0,
    this.sizeIsFractionOfWidth = false,
  });

  final GardenWeatherFxShape shape;
  final int count;
  final Color color;
  final double sizeMin;
  final double sizeMax;
  final double speedMin;
  final double speedMax;
  final double alphaMin;
  final double alphaMax;
  final GardenWeatherFxLayer layer;
  final double strokeMin;
  final double strokeMax;

  /// 雨丝斜角（度）。
  final double slantDegrees;

  /// 热浪气流线振幅区间（pt）。
  final double amplitudeMin;
  final double amplitudeMax;

  /// true ⇒ [size] 解释为「画布宽的比例」（云影用）。
  final bool sizeIsFractionOfWidth;
}

/// 单个日型的完整特效配置（多层粒子 + 全局氛围开关）。
@immutable
class _FxConfig {
  const _FxConfig({
    required this.layers,
    this.splashCap = 0,
    this.sunBeam = false,
    this.mist = false,
    this.vignette = false,
  });

  final List<_FxLayer> layers;

  /// 同时存在的**水花**上限（0 = 不生成）。
  final int splashCap;

  /// 晴天斜扫光束。
  final bool sunBeam;

  /// 暴雨整屏雨雾底层。
  final bool mist;

  /// 暴雨暗角。
  final bool vignette;

  /// 本型粒子总数（= 各层 count 之和）。
  int get count => layers.fold<int>(0, (int sum, _FxLayer l) => sum + l.count);
}

/// 一颗元素在某个相位下的**几何样本**（中心 + 包围盒 + 进出视野的透明度系数）。
///
/// 绘制与「帧连续性探针」共用同一个来源 ⇒ 探针断言的就是真正画出来的坐标。
@immutable
class GardenWeatherFxSample {
  /// 构造。
  const GardenWeatherFxSample({
    required this.center,
    required this.bounds,
    required this.opacity,
  });

  /// 元素中心（层坐标）。
  final Offset center;

  /// 元素包围盒（层坐标；云影含 3σ 模糊光晕扩张）。
  final Rect bounds;

  /// 进出视野的透明度系数（0..1）；1 = 完整体色。
  final double opacity;

  /// 完全不可见 ⇒ 这一帧不画、探针也不追究位移。
  bool get isVisible => opacity > 0;
}

/// **循环几何**（纯函数，绘制与测试共用）：入场 / 出场点都在**可见区**外。
///
/// 🔴 第十三批的三条硬口径（缺一条就会重新出现「跳变」）：
///  · **① 相位闭合**：`cycle = frac(phase + cycles · progress)`，[GardenWeatherFxParticle.cycles]
///    是**整数** ⇒ controller 由 1 回 0 时位置逐位相同（见文件头「根因 A」）；
///  · **② 可见区为基准**：所有行程都从 [visible]（默认 = 层 rect，可参数化）算，
///    而不是从「层 rect」算 —— 层比可见区矮时（第十三批根因 B）回绕点会落到屏幕中间；
///  · **③ 余量含视觉尺寸**：横向按「半个元素 + 3σ 模糊晕 + [kGardenWeatherFxWrapMargin]」，
///    纵向按「自身尺寸 + [kGardenWeatherFxWrapMargin]」。
///
/// 另外提供 [edgeOpacityX] / [edgeOpacityY]：按「包围盒到可见区边缘的距离」算进出场
/// 透明度斜坡（进入侧 8% 视野宽/高处 0→1，离开侧同理），确保任何残余回绕点看到的
/// 都是「淡出→淡入」而不是硬切。
@visibleForTesting
class GardenWeatherFxGeometry {
  const GardenWeatherFxGeometry._();

  /// 云影的模糊 sigma（与 `GardenWeatherFxPainter` 的 `MaskFilter` 必须一致）。
  static const double cloudBlurSigma = 10;

  /// 模糊光晕的可见扩张 ≈ 3σ（几何余量要把它算进去，否则「已出屏」时光晕还在屏内）。
  static const double cloudHalo = cloudBlurSigma * 3;

  /// 进出场透明度斜坡长度 = 视野宽 / 高的 8%。
  static const double edgeRampFraction = 0.08;

  /// 横飘元素（云影 / 叶片 / 风线 / 光斑 / 暖尘）的活动带 = 视野上方 66%。
  ///
  /// 与「FX 层曾经只有屏高 64%」的历史观感对齐：横飘元素只掠过植物区，
  /// 雨雪才落满整屏（第十三批根因 B 的修法只放开纵向）。
  static const double airBandFraction = 0.66;

  /// 有效可见区（[visible] 为 null ⇒ 退化为层 rect，即「层 = 可见区」的挂载形态）。
  static Rect visibleOf(Size layer, Rect? visible) =>
      visible ?? (Offset.zero & layer);

  /// **时间（主循环进度 0..1）→ 循环相位（0..1）**。
  ///
  /// 🔴 [GardenWeatherFxParticle.cycles] 是整数 ⇒ `f(1) ≡ f(0)`，接缝**逐位闭合**。
  /// 旧实现是 `frac(phase + progress · speed)`（speed 为小数）⇒ 接缝瞬移
  /// `frac(speed) × 行程`，实测云影 36pt / 叶片 284pt / 雪花 487pt / 热浪 748pt。
  static double cycleOf(GardenWeatherFxParticle p, double progress) =>
      (p.phase + p.cycles * progress) % 1.0;

  /// 横飘元素活动带的高度。
  static double airBandHeight(Rect visible) =>
      visible.height * airBandFraction;

  /// 横向运动元素的**中心 x**；[extent] = 元素横向尺寸，[halo] = 模糊光晕扩张。
  static double horizontalCenterX(
    double extent,
    Rect visible,
    double cycle, {
    double halo = 0,
  }) {
    final double half = extent * 0.5 + halo;
    final double start = visible.left - half - kGardenWeatherFxWrapMargin;
    final double end = visible.right + half + kGardenWeatherFxWrapMargin;
    return start + (end - start) * cycle;
  }

  /// 风线的**左端 x**（[length] = 线长）。
  static double windLineLeftX(double length, Rect visible, double cycle) =>
      horizontalCenterX(length, visible, cycle) - length * 0.5;

  /// 雨丝**上端 y**（下端 = y + cos(slant)·size）。
  static double rainTopY(
    GardenWeatherFxParticle p,
    Rect visible,
    double cycle,
  ) {
    final double dy = math.cos(p.slant) * p.size;
    final double start = visible.top - (dy + kGardenWeatherFxWrapMargin);
    final double end = visible.bottom + kGardenWeatherFxWrapMargin;
    return start + (end - start) * cycle;
  }

  /// 雨丝**下端抵达「地面线」**时的 cycle（水花起点）。
  ///
  /// [groundY] 由页面传入（背景菜地上沿）—— 层现在覆盖整屏，但「落地」这件事
  /// 仍发生在草地上，水花不该被推到屏幕最底（那里会被底栏挡掉）。
  static double rainGroundCycle(
    GardenWeatherFxParticle p,
    Rect visible,
    double groundY,
  ) {
    final double dy = math.cos(p.slant) * p.size;
    final double start = visible.top - (dy + kGardenWeatherFxWrapMargin);
    final double end = visible.bottom + kGardenWeatherFxWrapMargin;
    final double travel = end - start;
    if (travel <= 0) return 0;
    final double cycle = (groundY - dy - start) / travel;
    return cycle.clamp(0.0, 1.0);
  }

  /// 雪花**中心 y**（横向半径 = size / 2）。
  static double snowCenterY(
    GardenWeatherFxParticle p,
    Rect visible,
    double cycle,
  ) {
    final double r = p.size * 0.5;
    final double start = visible.top - (r + kGardenWeatherFxWrapMargin);
    final double end = visible.bottom + r + kGardenWeatherFxWrapMargin;
    return start + (end - start) * cycle;
  }

  /// 热浪气流线的高度（视野高固定比例）。
  static double heatWaveLength(Rect visible) => visible.height * 0.50;

  /// 热浪气流线的**下端 y**（整条 = [heatWaveLength] 高）。
  static double heatWaveBottomY(Rect visible, double cycle) {
    final double len = heatWaveLength(visible);
    final double start = visible.bottom + len + kGardenWeatherFxWrapMargin;
    final double end = visible.top - kGardenWeatherFxWrapMargin;
    return start + (end - start) * cycle;
  }

  /// 暖尘点**中心 y**（半径 = particle.size）。
  static double heatDustCenterY(
    GardenWeatherFxParticle p,
    Rect visible,
    double cycle,
  ) {
    final double r = p.size;
    final double start = visible.bottom + r + kGardenWeatherFxWrapMargin;
    final double end = visible.top - r - kGardenWeatherFxWrapMargin;
    return start + (end - start) * cycle;
  }

  /// 横向进出场斜坡：包围盒「已进入可见区的宽度 / 斜坡长度」。
  static double edgeOpacityX(Rect bounds, Rect visible) {
    final double ramp = math.max(
      visible.width * edgeRampFraction,
      math.max(bounds.width * 0.5, 1e-6),
    );
    final double enter = (bounds.right - visible.left) / ramp;
    final double leave = (visible.right - bounds.left) / ramp;
    return (enter < leave ? enter : leave).clamp(0.0, 1.0);
  }

  /// 纵向进出场斜坡（雨 / 雪 / 暖尘 / 热浪）。
  static double edgeOpacityY(Rect bounds, Rect visible) {
    final double ramp = math.max(
      visible.height * edgeRampFraction,
      math.max(bounds.height * 0.5, 1e-6),
    );
    final double enter = (bounds.bottom - visible.top) / ramp;
    final double leave = (visible.bottom - bounds.top) / ramp;
    return (enter < leave ? enter : leave).clamp(0.0, 1.0);
  }

  /// 造一颗元素的几何样本（绘制与探针的唯一坐标来源）。
  ///
  /// [visible] 缺省 = 层 rect（「层 = 可见区」的挂载形态）。
  static GardenWeatherFxSample sample(
    GardenWeatherFxParticle p, {
    required Size layer,
    required double cycle,
    Rect? visible,
  }) {
    final Rect v = visibleOf(layer, visible);
    final double band = airBandHeight(v);
    final Offset origin = Offset(v.left, v.top);

    switch (p.shape) {
      case GardenWeatherFxShape.orb:
        // 光斑：正弦闭路漂移（起止同位），没有「回绕点」这回事。
        final double angle = cycle * 2 * math.pi;
        final Offset center = Offset(
          origin.dx + p.x * v.width + math.sin(angle) * 14,
          origin.dy + p.y * band * 0.75 + math.cos(angle) * 10,
        );
        final double radius =
            (p.size * 0.5 * (0.85 + 0.15 * math.sin(angle))).abs();
        final Rect bounds = Rect.fromCircle(center: center, radius: radius);
        return GardenWeatherFxSample(
          center: center,
          bounds: bounds,
          opacity: 1,
        );

      case GardenWeatherFxShape.leaf:
        // 叶片：屏左外 → 屏右外 + 上下起伏（正弦整周期 ⇒ 接缝闭合）。
        final double ang = cycle * 2 * math.pi;
        final Offset center = Offset(
          horizontalCenterX(p.size, v, cycle),
          origin.dy + p.y * band + math.sin(ang) * 12,
        );
        final Rect bounds = Rect.fromCenter(
          center: center,
          width: p.size,
          height: p.size,
        );
        return GardenWeatherFxSample(
          center: center,
          bounds: bounds,
          opacity: edgeOpacityX(bounds, v),
        );

      case GardenWeatherFxShape.cloud:
        // 云影：整个（含 3σ 光晕）都在屏外才回绕。
        final double w = p.size * v.width;
        final Offset center = Offset(
          horizontalCenterX(w, v, cycle, halo: cloudHalo),
          origin.dy + p.y * band,
        );
        final Rect bounds = Rect.fromCenter(
          center: center,
          width: w + 2 * cloudHalo,
          height: w * 0.34 + 2 * cloudHalo,
        );
        return GardenWeatherFxSample(
          center: center,
          bounds: bounds,
          opacity: edgeOpacityX(bounds, v),
        );

      case GardenWeatherFxShape.rain:
        final double dy = math.cos(p.slant) * p.size;
        final double dx = math.sin(p.slant) * p.size;
        final Offset start = Offset(
          origin.dx + p.x * v.width,
          rainTopY(p, v, cycle),
        );
        final Offset end = Offset(start.dx + dx, start.dy + dy);
        final Rect bounds =
            Rect.fromPoints(start, end).inflate(math.max(p.stroke, 0.5));
        return GardenWeatherFxSample(
          center: Offset(
            (start.dx + end.dx) * 0.5,
            (start.dy + end.dy) * 0.5,
          ),
          bounds: bounds,
          opacity: edgeOpacityY(bounds, v),
        );

      case GardenWeatherFxShape.heat:
        // 暖尘：自下而上（两端都在屏外）+ 横向摆动。
        final double sway = math.sin(cycle * 2 * math.pi);
        final Offset center = Offset(
          origin.dx + p.x * v.width + sway * 10,
          heatDustCenterY(p, v, cycle),
        );
        final Rect bounds = Rect.fromCircle(center: center, radius: p.size);
        return GardenWeatherFxSample(
          center: center,
          bounds: bounds,
          opacity: edgeOpacityY(bounds, v),
        );

      case GardenWeatherFxShape.heatWave:
        final double len = heatWaveLength(v);
        final double bottom = heatWaveBottomY(v, cycle);
        final double x = origin.dx + p.x * v.width;
        return GardenWeatherFxSample(
          center: Offset(x, bottom - len * 0.5),
          bounds: Rect.fromLTRB(
            x - p.amplitude,
            bottom - len,
            x + p.amplitude,
            bottom,
          ),
          opacity: edgeOpacityY(
            Rect.fromLTRB(x - p.amplitude, bottom - len, x + p.amplitude, bottom),
            v,
          ),
        );

      case GardenWeatherFxShape.windLine:
        final double left = windLineLeftX(p.size, v, cycle);
        final double y = origin.dy + p.y * band;
        final Rect bounds = Rect.fromLTRB(
          left,
          y - math.max(p.stroke, 0.5),
          left + p.size,
          y + math.max(p.stroke, 0.5),
        );
        return GardenWeatherFxSample(
          center: Offset(left + p.size * 0.5, y),
          bounds: bounds,
          opacity: edgeOpacityX(bounds, v),
        );

      case GardenWeatherFxShape.snow:
        // 雪花：横向摆动 = **整数个正弦周期**（2 圈）⇒ 与下落相位解耦且接缝闭合。
        final double r = p.size * 0.5;
        final Offset center = Offset(
          origin.dx + p.x * v.width + math.sin(cycle * 4 * math.pi) * 12,
          snowCenterY(p, v, cycle),
        );
        final Rect bounds = Rect.fromCircle(center: center, radius: r);
        return GardenWeatherFxSample(
          center: center,
          bounds: bounds,
          opacity: edgeOpacityY(bounds, v),
        );
    }
  }
}

/// 9 型映射表（**穷举**：加第 10 种日型时 `_configOf` 编译期报错，逼着补配置）。
///
/// 色彩纪律：只复用在用色 / 低饱和中性色；雪花**纯白**（第八批已验收口径）。
/// α 单颗最高 0.85（极寒大雪花），其余形状 ≤ 0.65（第十二批把叶片抬到 0.65 以便读出）。
const Map<WeatherKind, _FxConfig> _configs = <WeatherKind, _FxConfig>{
  // ── 晴：5 个光斑（远 2 小 + 近 3 大）+ 一道缓慢斜扫光束（α 0.16）──
  WeatherKind.sunny: _FxConfig(
    sunBeam: true,
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.orb,
        count: 2,
        color: Color(0xFFFFE9A8), // 复用木牌呼吸光晕色，不新造色
        sizeMin: 40,
        sizeMax: 60,
        speedMin: 0.26,
        speedMax: 0.38,
        alphaMin: 0.26,
        alphaMax: 0.34,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.orb,
        count: 3,
        color: Color(0xFFFFE9A8),
        sizeMin: 60,
        sizeMax: 90,
        speedMin: 0.16,
        speedMax: 0.26,
        alphaMin: 0.34,
        alphaMax: 0.44,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 微风：18 片深绿叶（远 10 小快淡 + 近 8 大慢浓），α 抬到 0.65 ──
  WeatherKind.breeze: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.leaf,
        count: 10,
        // 🔴 深绿（不是浅草绿）：浅绿叶片落在草地上等于隐形。
        color: Color(0xFF2E5D24),
        sizeMin: 7,
        sizeMax: 10,
        speedMin: 0.52,
        speedMax: 0.74,
        alphaMin: 0.38,
        alphaMax: 0.48,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.leaf,
        count: 8,
        color: Color(0xFF2E5D24),
        sizeMin: 12,
        sizeMax: 18,
        speedMin: 0.28,
        speedMax: 0.46,
        alphaMin: 0.55,
        alphaMax: 0.65,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 多云：4 片云影（远 2 + 近 2，相位 0/0.25/0.5/0.75 错开），α 0.10~0.16 ──
  //    速度按层固定（同层同速 ⇒ 0.25 相位差恒定，任何时刻都有云在屏内）。
  WeatherKind.cloudy: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.cloud,
        count: 2,
        color: Color(0xFF5A6470), // 中性灰（低 alpha 读作「淡灰云影」）
        sizeMin: 0.46,
        sizeMax: 0.58,
        speedMin: 0.058,
        speedMax: 0.058,
        alphaMin: 0.10,
        alphaMax: 0.12,
        sizeIsFractionOfWidth: true,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.cloud,
        count: 2,
        color: Color(0xFF5A6470),
        sizeMin: 0.66,
        sizeMax: 0.86,
        speedMin: 0.030,
        speedMax: 0.030,
        alphaMin: 0.13,
        alphaMax: 0.16,
        layer: GardenWeatherFxLayer.near,
        sizeIsFractionOfWidth: true,
      ),
    ],
  ),
  // ── 阴：4 片更深更慢的云影（比多云暗一档、慢一半），α 0.12~0.20 ──
  WeatherKind.overcast: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.cloud,
        count: 2,
        color: Color(0xFF4A5460), // 比多云更深一档（阴天更闷）
        sizeMin: 0.50,
        sizeMax: 0.62,
        speedMin: 0.026,
        speedMax: 0.026,
        alphaMin: 0.12,
        alphaMax: 0.15,
        sizeIsFractionOfWidth: true,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.cloud,
        count: 2,
        color: Color(0xFF4A5460),
        sizeMin: 0.70,
        sizeMax: 0.90,
        speedMin: 0.014,
        speedMax: 0.014,
        alphaMin: 0.16,
        alphaMax: 0.20,
        layer: GardenWeatherFxLayer.near,
        sizeIsFractionOfWidth: true,
      ),
    ],
  ),
  // ── 小雨：70 条细密雨幕（远 40 长 18/粗 1.2 + 近 30 长 34/粗 2.6）+ 水花 16 ──
  WeatherKind.lightRain: _FxConfig(
    splashCap: 16,
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.rain,
        count: 40,
        color: Color(0xFF9EC8E8),
        sizeMin: 18,
        sizeMax: 18,
        speedMin: 0.60,
        speedMax: 0.90,
        alphaMin: 0.35,
        alphaMax: 0.45,
        strokeMin: 1.2,
        strokeMax: 1.2,
        slantDegrees: 6,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.rain,
        count: 30,
        color: Color(0xFF9EC8E8),
        sizeMin: 34,
        sizeMax: 34,
        speedMin: 0.85,
        speedMax: 1.15,
        alphaMin: 0.45,
        alphaMax: 0.60,
        strokeMin: 2.6,
        strokeMax: 2.6,
        slantDegrees: 8,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 暴雨：140 条倾盆雨幕 + 14~16° 斜打 + 雨雾底层 + 暗角 + 水花 28 ──
  WeatherKind.rainstorm: _FxConfig(
    splashCap: 28,
    mist: true,
    vignette: true,
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.rain,
        count: 60,
        color: Color(0xFF8FBBDD),
        sizeMin: 22,
        sizeMax: 22,
        speedMin: 1.20,
        speedMax: 1.50,
        alphaMin: 0.38,
        alphaMax: 0.48,
        strokeMin: 1.4,
        strokeMax: 1.4,
        slantDegrees: 14,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.rain,
        count: 80,
        color: Color(0xFF8FBBDD),
        sizeMin: 44,
        sizeMax: 56,
        speedMin: 1.60,
        speedMax: 2.00,
        alphaMin: 0.50,
        alphaMax: 0.62,
        strokeMin: 3.2,
        strokeMax: 3.2,
        slantDegrees: 16,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 干旱：10 条上飘正弦气流线 + 12 颗暖尘 + 2 个脉动暖光斑 ──
  WeatherKind.drought: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.heatWave,
        count: 4,
        color: Color(0xFFFFE0B2), // 暖黄（远层更淡）
        sizeMin: 40, // 波长
        sizeMax: 70,
        speedMin: 0.08,
        speedMax: 0.11,
        alphaMin: 0.35,
        alphaMax: 0.40,
        strokeMin: 1.6,
        strokeMax: 1.6,
        amplitudeMin: 6,
        amplitudeMax: 10,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.heat,
        count: 8,
        color: Color(0xFFFFB74D), // 暖橙
        sizeMin: 3,
        sizeMax: 5,
        speedMin: 0.14,
        speedMax: 0.20,
        alphaMin: 0.20,
        alphaMax: 0.28,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.heatWave,
        count: 6,
        color: Color(0xFFFFB74D),
        sizeMin: 46, // 波长
        sizeMax: 66,
        speedMin: 0.10,
        speedMax: 0.13,
        alphaMin: 0.35,
        alphaMax: 0.45,
        strokeMin: 2.4,
        strokeMax: 2.4,
        amplitudeMin: 9,
        amplitudeMax: 14,
        layer: GardenWeatherFxLayer.near,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.heat,
        count: 4,
        color: Color(0xFFFFB74D),
        sizeMin: 6,
        sizeMax: 9,
        speedMin: 0.10,
        speedMax: 0.16,
        alphaMin: 0.28,
        alphaMax: 0.36,
        layer: GardenWeatherFxLayer.near,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.orb,
        count: 2,
        color: Color(0xFFFFB74D),
        sizeMin: 100, // 半径 = size/2 ⇒ r 50~84
        sizeMax: 168,
        speedMin: 0.10,
        speedMax: 0.16,
        alphaMin: 0.14,
        alphaMax: 0.20,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 大风：24 条风线（远 18 短 + 近 6 长亮）+ 6 片快飘叶 ──
  WeatherKind.wind: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.windLine,
        count: 18,
        color: Color(0xFFB8C6B0), // 灰绿：风的「线稿」观感
        sizeMin: 26,
        sizeMax: 46,
        speedMin: 0.90,
        speedMax: 1.20,
        alphaMin: 0.35,
        alphaMax: 0.44,
        strokeMin: 1.4,
        strokeMax: 1.4,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.windLine,
        count: 6,
        color: Color(0xFFB8C6B0),
        sizeMin: 56,
        sizeMax: 90,
        speedMin: 0.80,
        speedMax: 1.05,
        alphaMin: 0.48,
        alphaMax: 0.58,
        strokeMin: 2.4,
        strokeMax: 2.4,
        layer: GardenWeatherFxLayer.near,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.leaf,
        count: 6,
        color: Color(0xFF2E5D24),
        sizeMin: 8,
        sizeMax: 13,
        speedMin: 0.90,
        speedMax: 1.30,
        alphaMin: 0.40,
        alphaMax: 0.52,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
  // ── 极寒：44 片纯白雪花，三档尺寸（小 8 / 中 14 / 大 20pt）──
  WeatherKind.cold: _FxConfig(
    layers: <_FxLayer>[
      _FxLayer(
        shape: GardenWeatherFxShape.snow,
        count: 20,
        color: Colors.white,
        sizeMin: 8,
        sizeMax: 8,
        speedMin: 0.32,
        speedMax: 0.45,
        alphaMin: 0.55,
        alphaMax: 0.66,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.snow,
        count: 14,
        color: Colors.white,
        sizeMin: 14,
        sizeMax: 14,
        speedMin: 0.24,
        speedMax: 0.34,
        alphaMin: 0.66,
        alphaMax: 0.76,
      ),
      _FxLayer(
        shape: GardenWeatherFxShape.snow,
        count: 10,
        color: Colors.white,
        sizeMin: 20,
        sizeMax: 20,
        speedMin: 0.16,
        speedMax: 0.26,
        alphaMin: 0.76,
        alphaMax: 0.85,
        layer: GardenWeatherFxLayer.near,
      ),
    ],
  ),
};

/// 日型 → 配置（穷举 `switch`，无 default ⇒ 加日型编译期即报错）。
_FxConfig _configOf(WeatherKind kind) => switch (kind) {
      WeatherKind.sunny => _configs[WeatherKind.sunny]!,
      WeatherKind.breeze => _configs[WeatherKind.breeze]!,
      WeatherKind.cloudy => _configs[WeatherKind.cloudy]!,
      WeatherKind.overcast => _configs[WeatherKind.overcast]!,
      WeatherKind.lightRain => _configs[WeatherKind.lightRain]!,
      WeatherKind.drought => _configs[WeatherKind.drought]!,
      WeatherKind.wind => _configs[WeatherKind.wind]!,
      WeatherKind.cold => _configs[WeatherKind.cold]!,
      WeatherKind.rainstorm => _configs[WeatherKind.rainstorm]!,
    };

/// 按日型生成粒子表（**远层在前、近层在后**，绘制顺序 = 远到近）。
///
/// 🔴 种子 = `0x5AF0 + kind.index * 97 + layerIndex * 7919`（**固定**）：同一日型每次
///    生成结果逐位相同，粒子不会在每次 rebuild 时「重新洗牌」跳位；也让测试可复现。
/// 🔴 云影相位**强制 0 / 0.25 / 0.5 / 0.75**（4 片错开）：不是随机值 —— 随机相位
///    无法保证「任何时刻屏内都有云」，错相位才能消除玄参说的「一起消失」空窗。
/// 🔴 热浪气流线的 x / 相位**也按 10 等分铺开**（横向 0.05..0.95、纵向 0.0..0.9）：
///    随机摆放会出现「左边三条、右边全空」的观感（第十二批首版就是这样）。
@visibleForTesting
List<GardenWeatherFxParticle> buildGardenWeatherFxParticles(WeatherKind kind) {
  final _FxConfig c = _configOf(kind);
  final List<GardenWeatherFxParticle> out = <GardenWeatherFxParticle>[];
  int cloudSeq = 0;
  int waveSeq = 0;
  for (int li = 0; li < c.layers.length; li++) {
    final _FxLayer layer = c.layers[li];
    final math.Random rnd = math.Random(0x5AF0 + kind.index * 97 + li * 7919);
    final double slant = layer.slantDegrees * math.pi / 180;
    final bool horizontalDriven = layer.shape == GardenWeatherFxShape.cloud ||
        layer.shape == GardenWeatherFxShape.leaf ||
        layer.shape == GardenWeatherFxShape.windLine;
    for (int i = 0; i < layer.count; i++) {
      final bool isCloud = layer.shape == GardenWeatherFxShape.cloud;
      final bool isWave = layer.shape == GardenWeatherFxShape.heatWave;
      final int waveSlot = waveSeq;
      if (isWave) waveSeq++;
      final double speed =
          layer.speedMin + rnd.nextDouble() * (layer.speedMax - layer.speedMin);
      out.add(GardenWeatherFxParticle(
        // 横向循环元素的 x 完全由 cycle 决定（从屏外进入、从屏外离开），
        // 这里置 0 以免出现「两套位移叠加」。其余形状保留随机横向起点。
        x: horizontalDriven
            ? 0
            : isWave
                ? (((waveSlot * 7) % 10) + 0.5) / 10
                : (layer.shape == GardenWeatherFxShape.rain
                    ? -0.02 + rnd.nextDouble() * 1.04
                    : 0.02 + rnd.nextDouble() * 0.96),
        y: rnd.nextDouble(),
        size: layer.sizeMin + rnd.nextDouble() * (layer.sizeMax - layer.sizeMin),
        speed: speed,
        // 🔴 整数圈数（第十三批根因 A）：接缝闭合的**充要条件**。
        cycles: math.max(
          1,
          (speed * kGardenWeatherFxLoopFactor).round(),
        ),
        phase: isCloud
            ? (cloudSeq++ % 4) * 0.25
            : isWave
                ? waveSlot / 10
                : rnd.nextDouble(),
        alpha: layer.alphaMin +
            rnd.nextDouble() * (layer.alphaMax - layer.alphaMin),
        shape: layer.shape,
        layer: layer.layer,
        color: layer.color,
        stroke: layer.strokeMin +
            rnd.nextDouble() * (layer.strokeMax - layer.strokeMin),
        slant: slant,
        amplitude: layer.amplitudeMin +
            rnd.nextDouble() * (layer.amplitudeMax - layer.amplitudeMin),
        sizeIsFractionOfWidth: layer.sizeIsFractionOfWidth,
      ));
    }
  }
  return out;
}

/// 花园页天气**动效层**（`IgnorePointer` + `RepaintBoundary` + 单 `CustomPainter`）。
///
/// [kind] 为 `null` ⇒ **整层不在场**（返回零尺寸 widget，不建 controller、
/// 不画任何东西 —— 测试与「无天气数据的降级态」共用这条口径）。
class GardenWeatherFx extends StatefulWidget {
  /// 构造。
  const GardenWeatherFx({
    super.key,
    required this.kind,
    this.animate = true,
    this.groundY,
  });

  /// 今日日型（页面从 `todayWeatherProvider` 快照传入；`null` = 不渲染）。
  final WeatherKind? kind;

  /// 是否驱动动画。
  ///
  /// `false` ⇒ **不创建、不启动** `AnimationController`，画一张
  /// [kGardenWeatherFxStaticProgress] 时刻的静态图（零帧重绘）。
  /// 机制与 `garden_sign_hotspot.dart` 的 `animate` 开关**逐字同构**（仓库既有做法）。
  final bool animate;

  /// 「地面线」在本层坐标里的 y（页面传 `gardenPotAreaBottom`）：雨滴在这里溅水花。
  ///
  /// 第十三批：本层高度覆盖**整屏**（雨雪要落满花园、不许在屏幕中间被裁掉），
  /// 但「落地」仍发生在背景菜地上沿 —— 不传 = 退化为层底缘。
  final double? groundY;

  @override
  State<GardenWeatherFx> createState() => _GardenWeatherFxState();
}

class _GardenWeatherFxState extends State<GardenWeatherFx>
    with SingleTickerProviderStateMixin {
  /// 循环控制器；`animate == false` 或 `kind == null` 时为 null（不创建 / 不启动）。
  AnimationController? _controller;

  /// 当前日型 + 粒子表（日型变化时重建；同型复用，避免每次 rebuild 重新洗牌）。
  WeatherKind? _kind;
  List<GardenWeatherFxParticle> _particles = const <GardenWeatherFxParticle>[];

  @override
  void initState() {
    super.initState();
    _syncParticles();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant GardenWeatherFx oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _syncParticles();
    if (oldWidget.animate != widget.animate ||
        oldWidget.kind != widget.kind) {
      _syncController();
    }
  }

  /// 日型变化 ⇒ 重建粒子表（同型不动）。
  void _syncParticles() {
    final WeatherKind? kind = widget.kind;
    if (kind == _kind) return;
    _kind = kind;
    _particles = kind == null
        ? const <GardenWeatherFxParticle>[]
        : buildGardenWeatherFxParticles(kind);
  }

  /// 依据 `animate` / `kind` 创建或销毁循环控制器。
  ///
  /// 🔴 与 `garden_sign_hotspot.dart` 的 `_syncController` 同一条做法：
  ///    关停 = 把 controller **置 null 并 dispose**，`build` 里按 null 走静态分支。
  void _syncController() {
    final bool need = widget.animate && widget.kind != null;
    if (need) {
      _controller ??= AnimationController(
        vsync: this,
        // 🔴 第十三批：周期必须是「参考周期 × 整数」的**长**周期，否则
        //    `frac(phase + speed·t)` 在 t=1→0 处断裂（云影 36pt / 雪花 487pt 瞬移）。
        duration: kGardenWeatherFxLoopPeriod,
      )..repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    // 安全：animate == false 时为 null，`?.` 保证不崩。
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WeatherKind? kind = widget.kind;
    // 🔴 日型为 null ⇒ 整层不在场（不是「透明但仍占层」）：测试 / 降级态同口径。
    if (kind == null) return const SizedBox.shrink();

    return IgnorePointer(
      key: kGardenWeatherFxKey,
      // 恒 true：本层是背景氛围，**绝不**吃点击（下方花盆 / 木牌 / FAB 照常响应）。
      ignoring: true,
      child: RepaintBoundary(
        child: CustomPaint(
          // 单 controller 直连 painter 的 `repaint` ⇒ 每帧只 paint，不 rebuild 树。
          painter: GardenWeatherFxPainter(
            kind: kind,
            particles: _particles,
            animation: _controller,
            groundY: widget.groundY,
          ),
          // 外层 `Positioned.fill` 给的是紧约束 ⇒ 这里填满即可。
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 天气动效的**绘制器**（纯绘制，零 IO）。
///
/// 进度来源：`animation?.value`（0..1 循环）；`animation == null` ⇒ 静态
/// [kGardenWeatherFxStaticProgress]。所有坐标先按 `size` 归一化反算，窗口尺寸变化
/// 自动跟随（不需要重建 State）。
class GardenWeatherFxPainter extends CustomPainter {
  /// 构造。
  GardenWeatherFxPainter({
    required this.kind,
    required this.particles,
    this.animation,
    this.groundY,
  }) : super(repaint: animation);

  /// 日型（决定形状、配色与全局氛围）。
  final WeatherKind kind;

  /// 粒子表（来自 [buildGardenWeatherFxParticles]，固定种子）。
  final List<GardenWeatherFxParticle> particles;

  /// 循环进度源；`null` = 静态图（`animate == false`）。
  final Animation<double>? animation;

  /// 雨滴「地面线」在本层坐标里的 y；`null` ⇒ 层底缘。
  final double? groundY;

  /// 共享画笔（每帧只改字段、不 new —— 见类注释的性能口径）。
  final Paint _stroke = Paint()..strokeCap = StrokeCap.round;

  /// 纯色填充画笔（叶片 / 暖尘 / 雪花 / 水花共用，逐次改 color）。
  final Paint _fill = Paint();

  /// 云影画笔（带常量模糊，模糊参数不必每帧重设）。
  final Paint _cloudPaint = Paint()..maskFilter = _cloudBlur;

  /// 光斑径向渐变缓存：key = 半径桶 * 100000 + α 桶（稳态零分配）。
  final Map<int, Paint> _orbPaints = <int, Paint>{};

  /// 热浪气流线的渐变描边缓存（key = 线长桶 / α / 线宽桶）。
  final Map<int, Paint> _wavePaints = <int, Paint>{};

  /// 气流线路径（复用同一实例，每帧 `reset` ⇒ 零分配）。
  final Path _wavePath = Path();

  /// 光束 / 暗角 / 雨雾缓存（按画布尺寸）。
  Paint? _beamPaint;
  Size _beamSize = Size.zero;
  Paint? _vignettePaint;
  Size _vignetteSize = Size.zero;
  Paint? _mistPaint;
  Size _mistSize = Size.zero;

  /// 云影模糊（常量，不每帧 new）。
  static const MaskFilter _cloudBlur = MaskFilter.blur(BlurStyle.normal, 10);

  /// 当前绘制进度（0..1）——测试可读，生产只经 `paint` 使用。
  @visibleForTesting
  double get progress => animation?.value ?? kGardenWeatherFxStaticProgress;

  /// 粒子数（测试断言「不超过 `kGardenWeatherFxParticleCap`」）。
  @visibleForTesting
  int get particleCount => particles.length;

  /// 本日型**同屏水花上限**（测试断言「水花不生成长驻对象」+ 总量红线）。
  @visibleForTesting
  int get splashCap => _configOf(kind).splashCap;

  /// 单帧**绘制对象上限**（粒子 + 水花 + 光束 + 雨雾 + 暗角）——测试断言 ≤ 220。
  @visibleForTesting
  int get drawableUpperBound {
    final _FxConfig c = _configOf(kind);
    return particles.length +
        c.splashCap +
        (c.sunBeam ? 1 : 0) +
        (c.mist ? 1 : 0) +
        (c.vignette ? 1 : 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final _FxConfig config = _configOf(kind);
    final double t = progress;
    final Rect visible = Offset.zero & size;
    final double ground = groundY ?? size.height;

    canvas.save();
    // 元素起止点都在可见区外（见 GardenWeatherFxGeometry），裁到本层范围 ——
    // 雨雪不会画到别的层，回绕也发生在裁剪之外。
    canvas.clipRect(visible);

    // 光束在粒子**之下**（阳光是背景氛围，不该盖住雨雪/叶片）。
    // 光束仍是「12s 扫一遍」（观感不变）：它自己的相位 = 主循环进度 × 60。
    if (config.sunBeam) {
      _drawSunBeam(
        canvas,
        size,
        (t * kGardenWeatherFxLoopFactor) % 1.0,
      );
    }
    // 雨雾同样在粒子之下（先铺「白茫茫」的底，再落雨丝）。
    if (config.mist) _drawMist(canvas, size);

    int splashes = 0;
    for (final GardenWeatherFxParticle p in particles) {
      // 🔴 相位来自**整数圈数**（第十三批根因 A）：controller 由 1 回 0 时逐位闭合。
      final double cycle = GardenWeatherFxGeometry.cycleOf(p, t);
      final GardenWeatherFxSample s = GardenWeatherFxGeometry.sample(
        p,
        layer: size,
        cycle: cycle,
        visible: visible,
      );
      // 完全在视野外（透明度斜坡已归零）⇒ 不画：回绕/入场都发生在看不见的地方。
      if (!s.isVisible) continue;
      if (p.shape == GardenWeatherFxShape.rain) {
        // 水花按「先到先得」计数：达到上限后剩下的雨丝照样画、只是不长水花
        // ⇒ 同屏水花数量**恒 ≤ splashCap**（确定性，且不新增任何常驻对象）。
        final bool spawned = _drawRainDrop(
          canvas,
          size,
          p,
          s,
          cycle,
          groundY: ground,
          allowSplash: splashes < config.splashCap,
        );
        if (spawned) splashes++;
      } else {
        _drawParticle(canvas, size, p, s, cycle);
      }
    }

    // 暗角在**最上层**（暴雨压边、收拢视线）。
    if (config.vignette) _drawVignette(canvas, size);

    canvas.restore();
  }

  /// 光斑渐变（按半径 / α 量化缓存，稳态每帧 0 分配）。
  Paint _orbPaint(Color base, double radius, double alpha) {
    final int key = (radius * 4).round() * 100000 + (alpha * 100).round();
    final Paint? cached = _orbPaints[key];
    if (cached != null) return cached;
    final Color c = base.withValues(alpha: alpha);
    // 渐变定义在**原点**、半径 = radius，绘制时 translate 到粒子中心。
    final Paint p = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        radius,
        <Color>[c, base.withValues(alpha: 0)],
      );
    _orbPaints[key] = p;
    return p;
  }

  /// 热浪气流线的**竖直线性渐变描边**（两端 α→0，中段最亮）。
  Paint _wavePaintFor(Color base, double len, double alpha, double stroke) {
    final int key = (len * 4).round() * 1000000 +
        (alpha * 100).round() * 10000 +
        (stroke * 10).round() * 10 +
        (base.hashCode & 0x7);
    final Paint? cached = _wavePaints[key];
    if (cached != null) return cached;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, len),
        <Color>[
          base.withValues(alpha: 0),
          base.withValues(alpha: alpha),
          base.withValues(alpha: alpha * 0.72),
          base.withValues(alpha: 0),
        ],
        <double>[0.0, 0.32, 0.74, 1.0],
      );
    _wavePaints[key] = p;
    return p;
  }

  /// 画一颗粒子（按形状分支；越界由外层 clip 处理）。
  ///
  /// 坐标一律来自 [sample]（与探针同源），本函数据此只做「画」这件事。
  void _drawParticle(
    Canvas canvas,
    Size size,
    GardenWeatherFxParticle p,
    GardenWeatherFxSample s,
    double cycle,
  ) {
    final Color color = p.color.withValues(alpha: p.alpha * s.opacity);
    final Offset center = s.center;

    switch (p.shape) {
      case GardenWeatherFxShape.orb:
        // 光斑：缓慢漂移 + 呼吸（半径 0.85~1.0 倍）；正弦位移**周期闭合**，无跳变。
        final double angle = cycle * 2 * math.pi;
        final double radius = p.size / 2 * (0.85 + 0.15 * math.sin(angle));
        if (radius <= 0) return;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.drawCircle(
          Offset.zero,
          radius,
          _orbPaint(p.color, radius, p.alpha * s.opacity),
        );
        canvas.restore();

      case GardenWeatherFxShape.leaf:
        // 叶片：从屏左外飘到屏右外（两端都在屏外）+ 上下起伏 + 翻转角度。
        final double ang = cycle * 2 * math.pi;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.sin(ang) * 0.6);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.55,
          ),
          _fill..color = color,
        );
        canvas.restore();

      case GardenWeatherFxShape.cloud:
        // 云影：从「含 3σ 光晕整朵在屏外」走到「整朵在屏外」——行程含模糊扩张，
        // 不再为省时间缩短（缩短就会在两头看见回绕）。
        final double w = p.size * size.width;
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w, height: w * 0.34),
          _cloudPaint..color = color,
        );

      case GardenWeatherFxShape.rain:
        _drawRainDrop(
          canvas,
          size,
          p,
          s,
          cycle,
          groundY: groundY ?? size.height,
          allowSplash: true,
        );

      case GardenWeatherFxShape.heat:
        // 暖尘：自下而上缓慢上浮（两端都在屏外）+ 横向摆动 + 轻微脉动。
        final double sway = math.sin(cycle * 2 * math.pi);
        final double r = p.size * (0.85 + 0.15 * sway);
        canvas.drawCircle(center, r, _fill..color = color);

      case GardenWeatherFxShape.heatWave:
        _drawHeatWave(canvas, size, p, s, cycle);

      case GardenWeatherFxShape.windLine:
        // 风线：较快横向掠过，从屏左外到屏右外（完全水平，读作「风」）。
        _stroke
          ..color = color
          ..strokeWidth = p.stroke;
        canvas.drawLine(
          Offset(center.dx - p.size * 0.5, center.dy),
          Offset(center.dx + p.size * 0.5, center.dy),
          _stroke,
        );

      case GardenWeatherFxShape.snow:
        // 雪花：从屏顶外入场、落到底缘以下离场（不会在屏内淡出再跳顶）。
        // 横向摆动用**整数个**正弦周期（2 圈）⇒ cycle 0/1 处位置连续。
        final Paint fill = _fill..color = color;
        canvas.drawCircle(center, p.size * 0.28, fill);
        final double spin = cycle * 2 * math.pi;
        _stroke
          ..color = color
          ..strokeWidth = p.size >= 14 ? 1.3 : 1.0;
        for (int i = 0; i < 3; i++) {
          final double a = i * math.pi / 3 + spin;
          final Offset d = Offset(math.cos(a), math.sin(a)) * (p.size * 0.5);
          canvas.drawLine(center - d, center + d, _stroke);
        }
    }
  }

  /// 干旱的**热气气流线**（第十二批：玄参「看不出热浪」——抽象颗粒改成可辨识的
  /// 向上飘正弦曲线）。
  ///
  /// 三条观感要素：
  ///  · **波形**：`x = 振幅 · sin(2π·y/波长 + 滚动相位)`，振幅 6~14pt、波长 40~70pt；
  ///  · **在动**：滚动相位 = `cycle · 4π`（每周期滚 2 个波峰）⇒ 波峰上移，不是整体平移；
  ///  · **出入场**：整条线从底缘以下升起、顶缘以上离开，两端都在屏外。
  void _drawHeatWave(
    Canvas canvas,
    Size size,
    GardenWeatherFxParticle p,
    GardenWeatherFxSample s,
    double cycle,
  ) {
    final Rect visible = Offset.zero & size;
    final double len = GardenWeatherFxGeometry.heatWaveLength(visible);
    if (len <= 0) return;
    final double bottom = s.center.dy + len * 0.5;
    final double top = bottom - len;
    final double amp = p.amplitude;
    final double waveLen = p.size <= 0 ? 50 : p.size;
    final double roll = cycle * 4 * math.pi;

    // 分段采样：局部坐标 y ∈ [0, len]，顶部为 0。
    // 🔴 每段必须远小于波长（这里取波长的 1/10，至少 16 段）——否则正弦会被折成
    //    「锯齿」而不是「波纹」（第十二批首版 18 段固定采样就是这个毛病）。
    final int steps = (len / waveLen * 10).round().clamp(16, 160);
    final Path path = _wavePath..reset();
    for (int i = 0; i <= steps; i++) {
      final double y = len * i / steps;
      final double x = amp * math.sin(2 * math.pi * y / waveLen + roll);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.save();
    canvas.translate(s.center.dx, top);
    canvas.drawPath(
      path,
      _wavePaintFor(p.color, len, p.alpha * s.opacity, p.stroke),
    );
    canvas.restore();
  }

  /// 雨丝 + **触底水花**（玄参第十一批：小米/华为天气最抓眼的就是「雨落地」）。
  ///
  /// [groundY] = 「地面线」（背景菜地上沿，页面传入）：雨丝下端穿过这里时溅水花。
  /// [allowSplash] 为 false ⇒ 只画雨丝、不长水花（同屏水花已达上限时的降级）。
  /// 返回 true ⇒ 本帧该粒子**正在生成水花**（计入同屏水花上限）。
  bool _drawRainDrop(
    Canvas canvas,
    Size size,
    GardenWeatherFxParticle p,
    GardenWeatherFxSample s,
    double cycle, {
    required double groundY,
    required bool allowSplash,
  }) {
    final double len = p.size;
    final double dx = math.sin(p.slant) * len;
    final double dy = math.cos(p.slant) * len;
    final Offset start = s.center - Offset(dx * 0.5, dy * 0.5);
    final Offset end = start + Offset(dx, dy);

    _stroke
      ..color = p.color.withValues(alpha: p.alpha * s.opacity)
      ..strokeWidth = p.stroke;
    canvas.drawLine(start, end, _stroke);

    if (!allowSplash) return false;

    // 水花：雨丝下端刚触「地面线」时开始（相位按真实几何反算，不是硬编码 0.90），
    // 存活约 0.8s（按**整数圈数**换算成相位宽度）。
    final double splashStart = GardenWeatherFxGeometry.rainGroundCycle(
      p,
      Offset.zero & size,
      groundY,
    );
    if (cycle < splashStart) return false;
    final double life =
        (0.8 * p.cycles / kGardenWeatherFxLoopPeriod.inSeconds)
            .clamp(0.001, 0.14);
    final double k = (cycle - splashStart) / life;
    if (k >= 1.0) return false;

    // 🔴 衰减必须是**线性**（首版用 (1-k)²：开窗 3.5% 宽，采样到的大多是尾巴，
    //    实测整帧几乎看不到 —— 像素统计里只剩雨丝）。线性 + 抬亮一档才「看得见」。
    final double fade = (1.0 - k) * 0.95;
    final Offset center = Offset(
      start.dx + dx * 0.92,
      groundY.clamp(0.0, size.height) - 4,
    );
    // 尺寸随线宽放大：暴雨（3.2）≈ spread 16 / r 7.4，小雨（2.6）≈ spread 13 / r 6。
    final double scale = (p.stroke / 2.6).clamp(0.85, 1.25);
    final double spread = (3.0 + 10.0 * k) * scale;
    final double r = (2.0 + 4.0 * k) * scale;
    final Paint splash = _fill
      ..color = p.color.withValues(alpha: (p.alpha * fade).clamp(0.0, 0.80));
    canvas.drawCircle(Offset(center.dx - spread, center.dy), r, splash);
    canvas.drawCircle(
      Offset(center.dx + spread, center.dy),
      r * 0.78,
      splash,
    );
    return true;
  }

  /// 晴天那道**缓慢斜扫的光束**（12s 内从左扫到右一次，α ≤ 0.16）。
  void _drawSunBeam(Canvas canvas, Size size, double t) {
    final Paint paint = _beamPaintFor(size);
    final double w = size.width * 0.16;
    canvas.save();
    // -0.7w .. 1.7w：留出斜角溢出，扫过时不会突然出现 / 消失。
    canvas.translate(-0.7 * size.width + t * 2.4 * size.width, 0);
    canvas.rotate(0.35); // ≈20° 斜
    canvas.drawRect(
      Rect.fromLTWH(0, -size.height, w, size.height * 2.4),
      paint,
    );
    canvas.restore();
  }

  /// 光束画笔（按画布尺寸缓存 —— 稳态每帧 0 分配）。
  Paint _beamPaintFor(Size size) {
    final Paint? cached = _beamPaint;
    if (cached != null && _beamSize == size) return cached;
    final double w = size.width * 0.16;
    final Paint p = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(w, 0),
        <Color>[
          const Color(0xFFFFF3C4).withValues(alpha: 0),
          const Color(0xFFFFF3C4).withValues(alpha: 0.16),
          const Color(0xFFFFF3C4).withValues(alpha: 0),
        ],
        <double>[0.0, 0.45, 1.0],
      );
    _beamPaint = p;
    _beamSize = size;
    return p;
  }

  /// 暴雨的**雨雾底层**（整屏极淡灰白垂直渐变，α ≤ 0.10）——
  /// 「白茫茫」是暴雨区别于小雨最直观的一层，比单纯加雨丝有效。
  void _drawMist(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _mistPaintFor(size));
  }

  /// 雨雾画笔（按画布尺寸缓存；α 峰值 0.10，绝不压住植物）。
  Paint _mistPaintFor(Size size) {
    final Paint? cached = _mistPaint;
    if (cached != null && _mistSize == size) return cached;
    final Paint p = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        <Color>[
          const Color(0xFFDCE6EC).withValues(alpha: 0.04),
          const Color(0xFFDCE6EC).withValues(alpha: 0.10),
          const Color(0xFFDCE6EC).withValues(alpha: 0.06),
        ],
        <double>[0.0, 0.55, 1.0],
      );
    _mistPaint = p;
    _mistSize = size;
    return p;
  }

  /// 暴雨轻微暗角（径向，边角 α ≤ 0.12）。
  void _drawVignette(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _vignettePaintFor(size));
  }

  /// 暗角画笔（按画布尺寸缓存）。
  Paint _vignettePaintFor(Size size) {
    final Paint? cached = _vignettePaint;
    if (cached != null && _vignetteSize == size) return cached;
    final Paint p = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.45),
        size.longestSide * 0.72,
        <Color>[
          const Color(0xFF0E1620).withValues(alpha: 0),
          const Color(0xFF0E1620).withValues(alpha: 0.12),
        ],
        <double>[0.55, 1.0],
      );
    _vignettePaint = p;
    _vignetteSize = size;
    return p;
  }

  @override
  bool shouldRepaint(covariant GardenWeatherFxPainter oldDelegate) {
    // 进度由 `repaint`（controller）推动，这里只需管「换了日型 / 换了动画源」。
    return oldDelegate.kind != kind ||
        oldDelegate.animation != animation ||
        oldDelegate.groundY != groundY ||
        oldDelegate.particles != particles;
  }
}
