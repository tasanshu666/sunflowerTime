import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sunflower_time/presentation/child/widgets/feedback_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

/// S1 演示页：一屏 demo，四档反馈可切换预览。
///
/// 验收（真机）：四档切换无卡顿；向日葵绘制帧率达标。本页仅用于 spike 预览，
/// 非产品最终页（产品页为打盹屏 + 四档由专注引擎按触发自动呈现，见 S3 / 架构 §4.1）。
class S1DemoPage extends StatefulWidget {
  const S1DemoPage({super.key});

  @override
  State<S1DemoPage> createState() => _S1DemoPageState();
}

class _S1DemoPageState extends State<S1DemoPage> {
  FeedbackLevel _level = FeedbackLevel.lvl1;
  bool _emit = false;

  void _pick(FeedbackLevel lvl) {
    setState(() {
      _level = lvl;
      _emit = lvl == FeedbackLevel.lvl2; // 二档触发送光
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('S1 · 四档反馈 + 向日葵画布'),
        // 本页经 go('/s1-demo') 进入 = 路由栈底，AppBar 不会自动出现返回箭头（B19 同类问题）
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回孩子端',
          onPressed: () => context.go('/'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SunflowerCanvas(level: _level, emitParticle: _emit),
                FeedbackOverlay(level: _level),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: FeedbackLevel.values.map((lvl) {
                final selected = lvl == _level;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selected ? Colors.amber : null,
                    foregroundColor: selected ? Colors.black87 : null,
                  ),
                  onPressed: () => _pick(lvl),
                  child: Text(kFeedbackLevelLabel[lvl]!),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
