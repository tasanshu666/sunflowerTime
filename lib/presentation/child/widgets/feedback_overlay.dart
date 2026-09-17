import 'package:flutter/material.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';

/// 四档反馈呈现（T08）。画布负责花与光，这里负责气泡/文案层。
///
/// 台词三原则（PRD §4.1.3）：① 随光只报信不夸奖；② 夸奖只留结算动画与
/// 家长转述；③ 任何一档不得比结算动画更诱人。
///
/// 声量账（PRD §4.1.4）：lvl2 走画面气泡（不占声量上限）；lvl3 纯视觉无气泡；
/// lvl4 唤醒分「轻声 / 加重」两档台词（语音占位）。
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

  /// 仅二档（随光报信，不夸奖）与四档（唤醒提醒）出气泡。
  ///
  /// 台词（PRD §4.1.3 / §4.1.4 写死）：
  /// - lvl2：「我去把它放好。」
  /// - lvl4 轻声：「向日葵想你了，回来看看吧」
  /// - lvl4 加重：「休息一下就回来哦」
  /// - lvl3：纯视觉光晕，无气泡。
  String? _bubbleText(FeedbackLevel level) {
    switch (level) {
      case FeedbackLevel.lvl1:
        return null; // 常态产光：无声
      case FeedbackLevel.lvl2:
        return '我去把它放好。'; // 随光只报信，不回头看反应
      case FeedbackLevel.lvl3:
        return null; // 欢迎回来：纯视觉光晕，无声
      case FeedbackLevel.lvl4:
        return wakeIntensity == WakeIntensity.strong
            ? '休息一下就回来哦'
            : '向日葵想你了，回来看看吧';
    }
  }
}
