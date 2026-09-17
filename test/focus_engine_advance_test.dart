// QA Round-2 复验：针对 P1 修复引入的共享推进内核 `_advance` 的边界用例。
//
// 目的：证明「离席窗口即便一个 tick 都没有」与「期间有 tick」两条路径归属一致，
// 且新内核未引入崩溃 / 负时长 / 幂等性回归。仅依赖 `package:test`。
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';

void main() {
  late DateTime now;

  FocusEngine makeEngine({int plannedMin = 20}) => FocusEngine(
        planned: Duration(minutes: plannedMin),
        clock: () => now,
      );

  void advance(Duration d) => now = now.add(d);

  int countLevel(FocusEngine e, FeedbackLevel lvl) =>
      e.eventHistory.where((ev) => ev.level == lvl).length;

  List<FocusEvent> wakes(FocusEngine e) =>
      e.eventHistory.where((ev) => ev.level == FeedbackLevel.lvl4).toList();

  setUp(() => now = DateTime(2026, 9, 15, 9, 0, 0));

  group('L _advance 内核：离席窗口路径一致性', () {
    test('L1 离席 60s「完全无 tick」与「每 10s tick」结果必须一致', () {
      // 路径 A：离席期间一个 tick 都没有。
      final a = makeEngine();
      a.start(now);
      advance(const Duration(seconds: 60));
      a.tick(now); // 在场 60s
      a.onAbsent(now);
      advance(const Duration(seconds: 60)); // 离席 60s，无 tick
      a.onPresent(now);
      advance(const Duration(seconds: 60));
      a.tick(now);
      a.stop();

      // 路径 B：离席期间每 10s 有一次 tick。
      final b = makeEngine();
      b.start(now = DateTime(2026, 9, 15, 9, 0, 0));
      advance(const Duration(seconds: 60));
      b.tick(now);
      b.onAbsent(now);
      for (var i = 0; i < 6; i++) {
        advance(const Duration(seconds: 10));
        b.tick(now);
      } // 离席 60s，被 6 次 tick 覆盖
      b.onPresent(now);
      advance(const Duration(seconds: 60));
      b.tick(now);
      b.stop();

      expect(a.actualFocusMin, closeTo(b.actualFocusMin, 1e-9),
          reason: '实际专注分钟不应因是否有 tick 而变化');
      expect(a.sunlight, closeTo(b.sunlight, 1e-9));
      expect(a.elapsed, b.elapsed);
      expect(countLevel(a, FeedbackLevel.lvl3), countLevel(b, FeedbackLevel.lvl3));
      expect(wakes(a).length, wakes(b).length);
      // 数值锚：在场 60s + 回满后满速 60s；回满窗口 ∫=55s → 55/60
      expect(a.actualFocusMin, closeTo(2.0, 1e-9));
      expect(a.sunlight, closeTo(1.0 + 55 / 60, 1e-9));
    });

    test('L2 离席 90s 无 tick 后恢复 → 补发「轻声」唤醒（lvl4 gentle）', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onAbsent(now);
      advance(const Duration(seconds: 90)); // 离席 90s，无 tick
      e.onPresent(now); // 恢复时才补结算

      final gentle =
          wakes(e).where((ev) => ev.wakeIntensity == WakeIntensity.gentle);
      expect(gentle.length, 1, reason: '超 90s 阈值就该唤醒，不该因无 tick 漏掉');
      // 时序语义：该事件在**恢复调用 onPresent 时**（catch-up）补发，非真值 90s 时刻。
      expect(e.state, FocusEngineState.running);
      expect(countLevel(e, FeedbackLevel.lvl3), 1);
    });

    test('L3 离席 300s 无 tick 后恢复 → 已打断结束（isFinished / interrupted）', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onAbsent(now);
      advance(const Duration(
          seconds: kL3ThresholdSeconds + kInterruptSeconds)); // 300s，无 tick
      e.onPresent(now); // 应在 _advance 内完成打断

      expect(e.isFinished, isTrue);
      expect(e.outcome!.endReason, FocusEndReason.interrupted);
      expect(e.state, FocusEngineState.finished);
      // onPresent 在打断后必须提前返回，不得把 state 翻回 running / 误发 lvl3
      expect(countLevel(e, FeedbackLevel.lvl3), 0);
    });

    test('L4 离席 300s 有 tick 与 无 tick → 均打断且实际专注一致', () {
      final a = makeEngine(plannedMin: 30);
      a.start(now);
      advance(const Duration(seconds: 60));
      a.tick(now);
      a.onAbsent(now);
      advance(const Duration(seconds: 300));
      a.onPresent(now); // 无 tick

      final b = makeEngine(plannedMin: 30);
      b.start(now = DateTime(2026, 9, 15, 9, 0, 0));
      advance(const Duration(seconds: 60));
      b.tick(now);
      b.onAbsent(now);
      for (var i = 0; i < 10; i++) {
        advance(const Duration(seconds: 30));
        b.tick(now);
      } // 每 30s 一次
      b.onPresent(now);

      expect(a.isFinished, isTrue);
      expect(b.isFinished, isTrue);
      expect(a.actualFocusMin, closeTo(b.actualFocusMin, 1e-9));
      expect(a.outcome!.endReason, FocusEndReason.interrupted);
      expect(b.outcome!.endReason, FocusEndReason.interrupted);
    });
  });

  group('M _advance 内核：鲁棒性 / 幂等', () {
    test('M1 onAbsent 传入早于 _lastTick 的时间（倒退）→ 不崩、不负时长', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      final sunBefore = e.sunlight;

      e.onAbsent(now.subtract(const Duration(seconds: 30))); // 倒退
      expect(e.sunlight, greaterThanOrEqualTo(sunBefore - 1e-9));
      expect(e.elapsed.isNegative, isFalse);
      expect(e.actualFocusMin, greaterThanOrEqualTo(0));
      expect(e.state, FocusEngineState.absent);
    });

    test('M2 未 start 直接 onAbsent / onPresent → 幂等不崩、状态不变', () {
      final e = makeEngine();
      expect(() => e.onAbsent(now), returnsNormally);
      expect(() => e.onPresent(now), returnsNormally);
      expect(e.state, FocusEngineState.idle);
      expect(e.isFinished, isFalse);
    });

    test('M3 重复 onAbsent → 幂等；重复 onPresent → 只发一次 lvl3', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 10));
      e.tick(now);
      e.onAbsent(now);
      e.onAbsent(now.add(const Duration(seconds: 5))); // 重复
      expect(e.state, FocusEngineState.absent);

      e.onPresent(now);
      e.onPresent(now.add(const Duration(seconds: 1))); // 重复（已 running）
      expect(e.state, FocusEngineState.running);
      expect(countLevel(e, FeedbackLevel.lvl3), 1);
    });

    test('M4 finished 后再 onAbsent / onPresent → 不崩、outcome 不变', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 300));
      e.tick(now);
      e.stop();
      final o = e.outcome;
      expect(() => e.onAbsent(now), returnsNormally);
      expect(() => e.onPresent(now), returnsNormally);
      expect(identical(e.outcome, o), isTrue);
      expect(e.state, FocusEngineState.finished);
    });

    test('M5 onAbsent/onPresent 缺参走 _clock() 与显式传参结果一致', () {
      final a = makeEngine(); // 走 _clock()
      a.start(now);
      advance(const Duration(seconds: 60));
      a.tick(now);
      a.onAbsent();
      advance(const Duration(seconds: 45));
      a.onPresent();

      final b = makeEngine(); // 显式传参
      b.start(now = DateTime(2026, 9, 15, 9, 0, 0));
      advance(const Duration(seconds: 60));
      b.tick(now);
      b.onAbsent(now);
      advance(const Duration(seconds: 45));
      b.onPresent(now);

      expect(a.actualFocusMin, closeTo(b.actualFocusMin, 1e-9));
      expect(a.sunlight, closeTo(b.sunlight, 1e-9));
      expect(a.elapsed, b.elapsed);
      expect(a.state, b.state);
    });
  });
}
