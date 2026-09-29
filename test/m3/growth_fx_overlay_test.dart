/// 成长演出卡（[GrowthFxOverlay]）widget 测试。
///
/// 覆盖要求：
///  1. **有限时长**：弹入 + 播放 + 淡出三段动画都能被 `pumpAndSettle()` 结束
///     （二期若误加无限循环动画会超时失败）；播完回吐 [onComplete] 恰好一次；
///  2. 渲染无异常（序列帧资源在测试环境缺失，走 errorBuilder 兜底，不崩）；
///  3. **视觉护栏**（玄参 2026-09-29 反馈「纯白底很难看」）：
///     · 卡片背景必须是**渐变**而非纯白 /
///     · 传入 title 时必须渲染出标题文案。
///
/// 不依赖真实 DB / Riverpod，直接渲染组件本身。
library growth_fx_overlay_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';

/// 测试用帧列表（测试环境无真实资源，走 errorBuilder 兜底）。
const List<String> _frames = <String>[
  'assets/fx/grow/sunflower/seed_to_sprout/frame001.png',
  'assets/fx/grow/sunflower/seed_to_sprout/frame002.png',
];

Future<void> _pump(
  WidgetTester tester, {
  String? title,
  required VoidCallback onComplete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GrowthFxOverlay(
          frames: _frames,
          durationMs: 300,
          title: title,
          onComplete: onComplete,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('演出全程有限时长，pumpAndSettle 能结束并回吐一次完成',
      (WidgetTester tester) async {
    int calls = 0;
    await _pump(tester, onComplete: () => calls++);
    await tester.pumpAndSettle();
    expect(calls, 1, reason: 'onComplete 应恰好回吐一次（播放结束 + 淡出结束）');
  });

  testWidgets('传入 title 时渲染标题文案', (WidgetTester tester) async {
    await _pump(tester, title: '开花啦！🌻', onComplete: () {});
    await tester.pump();
    expect(find.text('开花啦！🌻'), findsOneWidget);
  });

  testWidgets('卡片背景是渐变而非纯白（奶油阳光风护栏）',
      (WidgetTester tester) async {
    await _pump(tester, title: '长大啦！🌿', onComplete: () {});
    await tester.pump();

    final Iterable<DecoratedBox> boxes =
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final Iterable<BoxDecoration> decorations = boxes
        .map((DecoratedBox b) => b.decoration)
        .whereType<BoxDecoration>();

    // ① 外层卡片：必须是 LinearGradient（纯白 sin(渐变) 会在此失败）。
    final Iterable<BoxDecoration> gradientCards = decorations
        .where((BoxDecoration d) => d.gradient is LinearGradient);
    expect(gradientCards, isNotEmpty,
        reason: '成长演出卡必须是渐变奶油底，不能回退成纯白');
    for (final BoxDecoration d in gradientCards) {
      expect(d.color, isNull, reason: '渐变与 color 不可同时存在');
    }

    // ② 卡内播放区：必须有径向柔光，避免透明底植株贴在白纸上。
    final Iterable<BoxDecoration> glow = decorations
        .where((BoxDecoration d) => d.gradient is RadialGradient);
    expect(glow, isNotEmpty, reason: '卡内播放区应有金色径向柔光');
  });
}
