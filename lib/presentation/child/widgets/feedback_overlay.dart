import 'package:flutter/material.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';

/// 四档反馈呈现（T08）。画布负责花与光，这里负责「向日葵说话气泡」层。
///
/// 台词三原则（PRD §4.1.3）：① 随光只报信不夸奖；② 夸奖只留结算动画与
/// 家长转述；③ 任何一档不得比结算动画更诱人。
///
/// 声量账（PRD §4.1.4）：lvl2 走画面气泡（不占声量上限）；lvl3 出「欢迎回来」
/// 气泡（玄参 2026-09-30 拍板，取代原顶部金色大字，避免压住向日葵）；
/// lvl4 唤醒分「轻声 / 加重」两档台词（语音占位）。
///
/// 视觉改版（玄参 2026-09-30）：旧版为屏幕底部横向白色圆角条，1/3 收集阳光
/// 时会盖住向日葵；现改为「说话气泡」——暖黄底 + 左下小尾巴指向向日葵。
/// 组件本体只渲染气泡（无定位）；**位置由调用方决定**（focus_page 用
/// `Positioned` 锚在向日葵头右上旁，太远会不像向日葵说的话）。
class FeedbackOverlay extends StatelessWidget {
  final FeedbackLevel level;

  /// lvl4 唤醒强度（仅 lvl4 有意义，默认轻声）。
  final WakeIntensity wakeIntensity;

  const FeedbackOverlay({
    super.key,
    required this.level,
    this.wakeIntensity = WakeIntensity.none,
  });

  @override
  Widget build(BuildContext context) {
    final String? bubble = _bubbleText(level);
    if (bubble == null) return const SizedBox.shrink(); // 一档/三档无声无气泡
    // 气泡本体（无定位包裹）：暖黄奶油底 + 左下尾巴指向向日葵。
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE9B8), // 暖黄奶油底（向日葵同色系）
            borderRadius: BorderRadius.circular(14),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Colors.black26, blurRadius: 6),
            ],
          ),
          child: Text(
            bubble,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF5D4037),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 左下小尾巴：斜指向向日葵，营造「向日葵在说话」。
        Positioned(
          left: 14,
          bottom: -6,
          child: CustomPaint(
            size: const Size(12, 8),
            painter: _BubbleTailPainter(),
          ),
        ),
      ],
    );
  }

  /// 仅二档（随光报信，不夸奖）与四档（唤醒提醒）出气泡。
  ///
  /// 台词（PRD §4.1.3 / §4.1.4 写死）：
  /// - lvl2：「太好了，又收集到阳光了。」
  /// - lvl3：「欢迎回来」（说话气泡，玄参 2026-09-30 拍板）
  /// - lvl4 轻声：「向日葵想你了，回来看看吧」
  /// - lvl4 加重：「休息一下就回来哦」
  String? _bubbleText(FeedbackLevel level) {
    switch (level) {
      case FeedbackLevel.lvl1:
        return null; // 常态产光：无声
      case FeedbackLevel.lvl2:
        return '太好了，又收集到阳光了。';
      case FeedbackLevel.lvl3:
        return '欢迎回来'; // 玄参 2026-09-30：改说话气泡，不压向日葵
      case FeedbackLevel.lvl4:
        return wakeIntensity == WakeIntensity.strong
            ? '休息一下就回来哦'
            : '向日葵想你了，回来看看吧';
    }
  }
}

/// 气泡左下尾巴（斜向下的三角，颜色与气泡底一致）。
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = const Color(0xFFFFE9B8);
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.2, size.height)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
