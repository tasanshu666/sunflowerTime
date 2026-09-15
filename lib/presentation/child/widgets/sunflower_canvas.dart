import 'dart:math';
import 'package:flutter/material.dart';

/// 四档反馈档位（PRD §4.1.3）。前两档「陪」，后两档「看」。
enum FeedbackLevel {
  lvl1, // 一档 · 常态产光：全程默认态，无声
  lvl2, // 二档 · 随光报信：每完成 1/3 进度，送一粒光 + 气泡（不夸奖）
  lvl3, // 三档 · 欢迎回来：离席后恢复在场，纯视觉光晕 / 半秒眨眼
  lvl4, // 四档 · 唤醒提醒：离席持续超阈值，睁眼说软话（语音占位）
}

/// 各档对外标签（演示用，非上屏产品文案）。
const Map<FeedbackLevel, String> kFeedbackLevelLabel = {
  FeedbackLevel.lvl1: '一档 · 常态产光',
  FeedbackLevel.lvl2: '二档 · 随光报信',
  FeedbackLevel.lvl3: '三档 · 欢迎回来',
  FeedbackLevel.lvl4: '四档 · 唤醒提醒',
};

/// 向日葵画布（S1）：CustomPainter 绘制 + 呼吸式明暗/极慢姿态动画。
///
/// 这是「打盹屏」中央那朵在做自己事的花（PRD §4.1.1）：慢而不突，零突事件。
class SunflowerCanvas extends StatefulWidget {
  final FeedbackLevel level;
  final bool emitParticle; // 二档：往外送出一粒光

  const SunflowerCanvas({
    super.key,
    this.level = FeedbackLevel.lvl1,
    this.emitParticle = false,
  });

  @override
  State<SunflowerCanvas> createState() => _SunflowerCanvasState();
}

class _SunflowerCanvasState extends State<SunflowerCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    // 呼吸周期 4s，往复；低亮慢频，不抢注意力
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final t = _breath.value; // 0..1 呼吸相位
        final scale = 0.96 + 0.06 * t;
        final opacity = 0.82 + 0.18 * t;
        return CustomPaint(
          painter: _SunflowerPainter(
            breath: t,
            scale: scale,
            opacity: opacity,
            level: widget.level,
            emitParticle: widget.emitParticle,
          ),
          size: const Size(300, 300),
        );
      },
    );
  }
}

class _SunflowerPainter extends CustomPainter {
  final double breath;
  final double scale;
  final double opacity;
  final FeedbackLevel level;
  final bool emitParticle;

  _SunflowerPainter({
    required this.breath,
    required this.scale,
    required this.opacity,
    required this.level,
    required this.emitParticle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    // 三档：欢迎回来光晕（纯视觉，无声）
    if (level == FeedbackLevel.lvl3) {
      final glow = Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha:0.35 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 135 + 6 * breath, glow);
    }

    // 花瓣（12 片，随呼吸极慢微旋）
    final petalPaint = Paint()
      ..color = const Color(0xFFFFC107).withValues(alpha:opacity)
      ..style = PaintingStyle.fill;
    const petalCount = 12;
    for (int i = 0; i < petalCount; i++) {
      final angle = (i / petalCount) * 2 * pi;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + 0.04 * (breath - 0.5)); // 极慢姿态变化
      final petal = Path()..addOval(const Rect.fromLTWH(-14, -120, 28, 70));
      canvas.drawPath(petal, petalPaint);
      canvas.restore();
    }

    // 花心
    final corePaint = Paint()
      ..color = const Color(0xFF6D4C41).withValues(alpha:opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 42, corePaint);

    // 花心种子纹理（三层）
    final seedPaint = Paint()
      ..color = const Color(0xFF3E2723).withValues(alpha:opacity)
      ..style = PaintingStyle.fill;
    for (int r = 1; r <= 3; r++) {
      final count = r * 6;
      for (int a = 0; a < count; a++) {
        final ang = (a / count) * 2 * pi;
        final rad = r * 11.0;
        canvas.drawCircle(
          Offset(center.dx + rad * cos(ang), center.dy + rad * sin(ang)),
          2.2,
          seedPaint,
        );
      }
    }

    // 四档：睁眼（觉醒，开口说软话前的那一眼）
    if (level == FeedbackLevel.lvl4) {
      final eyeWhite = Paint()..color = Colors.white.withValues(alpha:opacity);
      final pupil = Paint()..color = Colors.black87.withValues(alpha:opacity);
      for (final dx in [-14.0, 14.0]) {
        canvas.drawCircle(Offset(center.dx + dx, center.dy - 6), 7, eyeWhite);
        canvas.drawCircle(Offset(center.dx + dx, center.dy - 6), 3.2, pupil);
      }
    }

    // 二档：往外送出一粒光（朝屏外走）
    if (emitParticle) {
      final dist = 60 + 70 * breath;
      final pAngle = -pi / 2; // 向上送出
      final px = center.dx + dist * cos(pAngle);
      final py = center.dy + dist * sin(pAngle);
      final particle = Paint()
        ..color = const Color(0xFFFFF59D).withValues(alpha:0.9 * (1 - breath))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 6, particle);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SunflowerPainter old) =>
      old.breath != breath ||
      old.level != level ||
      old.emitParticle != emitParticle ||
      old.opacity != opacity ||
      old.scale != scale;
}
