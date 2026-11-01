/// 阳光胶囊点击「爆发」特效（玄参 2026-11-01 需求）。
///
/// 需求原话：「孩子端今日页 … 漂浮的阳光胶囊，我想做一个特效，就是点击一下这个
/// 胶囊的话会往四处发散阳光，四处发散的阳光用阳光 UI 来做 … 点一下这个胶囊，
/// 嘣就往外四散一下阳光，又慢慢消失的那种感觉。」
///
/// ## 纯视觉，绝不影响数值
/// 粒子只是 [assets/rewards/sunlight.png] 的图片，**不加阳光、不写账本、不发奖励**——
/// 否则孩子会发现「狂点胶囊能刷阳光」。本组件对外只暴露一个 `onComplete` 回调，
/// 没有任何经济侧接口，从类型上就杜绝了误用。
///
/// ## 确定性轨迹（不用 `Random`）
/// 10 颗粒子的角度抖动 / 距离倍率 / 启动延迟全部是**写死的常量表**：
///  · 每次点都一样 —— 视觉上仍是「四处乱飞」（角度不均匀、距离不均等、有先后），
///  · 但测试可以断言像素、可以重放，不会出现「这次绿下次红」的抖动用例。
///
/// ## 帧纪律
/// 单次播放 [kSunBurstDurationMs]（约 0.6s）后自清；调用方（今日页）负责插入/移除
/// 根 Overlay 浮层，并在 `dispose` 时兜底移除。**连点由调用方闸门控制**（见
/// `_ChildTodayPageState._fireSunBurst`：先撤旧的再插新的，绝不叠加两层）。
library sun_burst;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/shared/responsive.dart';

/// 一次爆发的总时长（毫秒）。
const int kSunBurstDurationMs = 620;

/// 默认粒子数。
const int kSunBurstParticleCount = 10;

/// 粒子飞行距离基准（pt，手机基准；平板乘 `uiScaleOf`）。
///
/// 🔴 2026-11-01 玄参验收调整：72 → 100（原值「发散有点偏小」，飞散半径扩 39%）。
const double kSunBurstDistance = 100;

/// 粒子初始视觉直径（pt，手机基准；平板乘 `uiScaleOf`）。
///
/// 🔴 2026-11-01 玄参验收调整：20 → 30（粒子本体放大 50%，末态由 6.8pt → 10.2pt）。
const double kSunBurstParticleSize = 30;

/// 粒子飞到终点时相对初始尺寸的保留比例（0.34 ≈ 缩到三分之一）。
const double kSunBurstEndScale = 0.34;

/// 粒子素材（与胶囊里的阳光图标同一张，视觉同源）。
const String kSunBurstAsset = 'assets/rewards/sunlight.png';

/// 角度抖动（弧度）：让 10 个方向不呈现「均匀钟面」的机械感。
const List<double> _kAngleJitter = <double>[
  0.00, 0.19, -0.14, 0.27, -0.21, 0.10, -0.25, 0.16, -0.07, 0.23,
];

/// 距离倍率：飞散半径不相同，「嘣」开的边界才自然。
const List<double> _kDistanceFactor = <double>[
  1.00, 0.86, 1.14, 0.92, 1.06, 0.80, 1.18, 0.95, 1.09, 0.88,
];

/// 启动延迟（占总时长比例 0~1）：先后错开 0~70ms，形成迸发感而非「整圈同缩」。
const List<double> _kDelay = <double>[
  0.00, 0.055, 0.020, 0.090, 0.035, 0.070, 0.000, 0.110, 0.045, 0.075,
];

/// 阳光爆发浮层本体。
///
/// 使用方：把本组件当成 **满屏** 的浮层内容（外层套 `Positioned.fill`），
/// [origin] 用**全局坐标**（胶囊中心）。
class SunBurst extends StatefulWidget {
  const SunBurst({
    super.key,
    required this.origin,
    required this.onComplete,
    this.particleCount = kSunBurstParticleCount,
  });

  /// 爆发圆心（全局坐标 = 胶囊中心）。
  final Offset origin;

  /// 动画走完回调（调用方据此移除 OverlayEntry）。
  final VoidCallback onComplete;

  /// 粒子数（≤ 10；超过则按 10 循环复用常量表）。
  final int particleCount;

  @override
  State<SunBurst> createState() => _SunBurstState();
}

class _SunBurstState extends State<SunBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kSunBurstDurationMs),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onComplete();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = uiScaleOf(context);
    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, Widget? _) {
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (int i = 0; i < widget.particleCount; i++)
                  _particle(i, _ctrl.value, scale),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _particle(int index, double t, double uiScale) {
    final int i = index % _kAngleJitter.length;
    final double delay = _kDelay[i];
    // 本地进度：延迟期间恒为 0（粒子尚未出发，停在圆心）。
    final double local =
        delay >= 1 ? 1.0 : ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    final double eased = Curves.easeOutCubic.transform(local);
    final double angle =
        2 * math.pi * (i / _kAngleJitter.length) + _kAngleJitter[i];
    final double distance =
        kSunBurstDistance * uiScale * _kDistanceFactor[i] * eased;

    final double size = kSunBurstParticleSize *
        uiScale *
        (1 - (1 - kSunBurstEndScale) * eased);
    // 透明度：出发即满，末段加速淡出（pow 1.7 → 前段稳、后段化开）。
    final double opacity =
        local <= 0 ? 0.0 : (1 - math.pow(local, 1.7)).toDouble().clamp(0.0, 1.0);

    return Positioned(
      left: widget.origin.dx + math.cos(angle) * distance - size / 2,
      top: widget.origin.dy + math.sin(angle) * distance - size / 2,
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          kSunBurstAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          // 素材缺失（测试环境等）回退内置太阳，保证「点了一定有反馈」。
          errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
              Icon(Icons.wb_sunny, size: size, color: const Color(0xFFE8A600)),
        ),
      ),
    );
  }
}
