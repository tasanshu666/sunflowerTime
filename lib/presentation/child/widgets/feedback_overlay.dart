import 'package:flutter/material.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

/// 四档反馈呈现（S1）。画布负责花与光，这里负责气泡/文案层。
///
/// 台词三原则（PRD §4.1.3）：① 随光只报信不夸奖；② 夸奖只留结算动画与
/// 家长转述；③ 任何一档不得比结算动画更诱人。
class FeedbackOverlay extends StatelessWidget {
  final FeedbackLevel level;

  const FeedbackOverlay({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final bubble = _bubbleText(level);
    if (bubble == null) return const SizedBox.shrink(); // 一档/三档无声无气泡
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 28),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Text(
          bubble,
          style: const TextStyle(fontSize: 18, color: Color(0xFF5D4037)),
        ),
      ),
    );
  }

  /// 仅二档（随光报信，不夸奖）与四档（唤醒提醒，语音占位文案）出气泡。
  String? _bubbleText(FeedbackLevel level) {
    switch (level) {
      case FeedbackLevel.lvl1:
        return null; // 常态产光：无声
      case FeedbackLevel.lvl2:
        return '我去把它放好。'; // 随光只报信，不回头看反应
      case FeedbackLevel.lvl3:
        return null; // 欢迎回来：纯视觉光晕，无声
      case FeedbackLevel.lvl4:
        return '向日葵想你了，回来看看吧～'; // 唤醒提醒（语音占位文案）
    }
  }
}
