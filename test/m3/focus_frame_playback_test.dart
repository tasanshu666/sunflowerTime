/// 专注页向日葵序列帧播放测试（玄参 2026-09-29 素材落地）。
///
/// 覆盖新引入的 [FrameSequencePlayer.loop] 循环模式（不渐隐、不回调、可反复播放）
/// 与 [FocusSunflowerStage] 的相位切换（idle 循环 → collect/return 一次性 → 回 idle）。
///
/// 注：循环模式**不能**用 `pumpAndSettle`（永不结束）；一律用固定步长 `pump`，
/// 并在结束前卸载组件以释放 Ticker（否则 flutter_test 报 Ticker still active）。
library focus_frame_playback_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/focus_sunflower_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

void main() {
  group('FrameSequencePlayer · loop 模式', () {
    testWidgets('loop=true：整圈后不回调 onComplete（可反复播放）', (tester) async {
      int done = 0;
      await tester.pumpWidget(MaterialApp(
        home: FrameSequencePlayer(
          // 空帧：只验控制器行为，不触发图片解码。
          frames: const <String>[],
          durationMs: 200,
          loop: true,
          onComplete: () => done++,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600)); // 已过 3 圈
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(done, 0, reason: '循环模式永不回调 onComplete');
      await tester.pumpWidget(const SizedBox()); // 卸载以释放 Ticker
    });

    testWidgets('loop=false：播完 + 渐隐后回调 onComplete 恰一次', (tester) async {
      int done = 0;
      await tester.pumpWidget(MaterialApp(
        home: FrameSequencePlayer(
          frames: const <String>[],
          durationMs: 200,
          fadeOutMs: 100,
          onComplete: () => done++,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(done, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(done, 1, reason: '一次性播放不得重复回调');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('holdLastFrame=true：播完（无渐隐段）回调恰一次并定格，不循环不消失',
        (tester) async {
      int done = 0;
      await tester.pumpWidget(MaterialApp(
        home: FrameSequencePlayer(
          frames: const <String>[],
          durationMs: 200,
          holdLastFrame: true,
          onComplete: () => done++,
        ),
      ));
      // 控制器时长 = durationMs（无渐隐段）→ 200ms 后 completed。
      await tester.pump(const Duration(milliseconds: 260));
      expect(done, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(done, 1, reason: '定格模式播完常驻，不得重复回调');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('FocusSunflowerStage · 相位切换', () {
    testWidgets('idle 仅常驻 idle 层；collect 上升沿叠一层 transient 做交叉淡入',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FocusSunflowerStage(collectSignal: false, returnSignal: false),
      ));
      // 空闲态：只有常驻 idle 一层。
      expect(find.byType(FrameSequencePlayer), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));

      // collect 上升沿（false→true）→ 在原 idle 之上叠一层一次性 collect（交叉淡入）。
      await tester.pumpWidget(const MaterialApp(
        home: FocusSunflowerStage(collectSignal: true, returnSignal: false),
      ));
      await tester.pump();
      // 此刻为「idle 底层 + collect 叠加层」两层并存（交叉淡入过渡中）。
      expect(find.byType(FrameSequencePlayer), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox()); // 卸载以释放 Ticker
    });
  });
}
