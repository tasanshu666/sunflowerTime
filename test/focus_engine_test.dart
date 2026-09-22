import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';

/// FocusEngine 单测（T06）。
///
/// 时钟完全由外部注入，时间轴由 `tick` 驱动 —— 所有用例对时间轴可完全控制。
void main() {
  late DateTime now;

  FocusEngine makeEngine({int plannedMin = 20}) => FocusEngine(
        planned: Duration(minutes: plannedMin),
        clock: () => now,
      );

  void advance(Duration d) => now = now.add(d);

  int countLevel(FocusEngine e, FeedbackLevel lvl) =>
      e.eventHistory.where((ev) => ev.level == lvl).length;

  setUp(() => now = DateTime(2026, 9, 15, 9, 0, 0));

  group('产出速率与离席（PRD §4.1.5）', () {
    test('在场产出速率 = 1 阳光/分钟', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(minutes: 1));
      e.tick(now);
      expect(e.sunlight, closeTo(kSunlightPerFocusMinute, 1e-9));
      expect(e.actualFocusMin, closeTo(1.0, 1e-9));
    });

    test('灭屏 = 离席：离席停产出且不扣减已有产出', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      final before = e.sunlight;
      expect(before, closeTo(1.0, 1e-9));

      // 灭屏 → onAbsent（离席）
      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);

      // 产出停止，且不扣减
      expect(e.sunlight, closeTo(before, 1e-9));
      // 离席窗口不补产出：实际专注分钟未增长
      expect(e.actualFocusMin, closeTo(1.0, 1e-9));
      expect(e.state, FocusEngineState.absent);
    });

    test('恢复在场：10 秒线性回满，离席窗口不补产出', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      final s0 = e.sunlight; // 1.0

      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now); // 离席 60s：无产出
      expect(e.sunlight, closeTo(s0, 1e-9));

      // 亮屏 → 恢复在场，自检测时刻起 10s 线性回满
      e.onPresent(now);
      advance(const Duration(seconds: 10));
      e.tick(now);
      // 斜坡 ∫0..10 (t/10)dt = 5（秒·满速），折算 5/60 阳光
      expect(e.sunlight - s0, closeTo(5 / 60, 1e-9));

      // 再过 60s：已回满，恢复满速 → +1.0 阳光
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.sunlight - s0, closeTo(5 / 60 + 1.0, 1e-9));
    });
  });

  group('四档反馈：随光报信（PRD §4.1.3 / §4.1.4）', () {
    test('每完成 1/3 进度各送一次光（1/3 与 2/3 各一次）', () {
      final e = makeEngine(plannedMin: 20); // 1200s；1/3=400s，2/3=800s
      e.start(now);

      advance(const Duration(seconds: 400));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 1);

      advance(const Duration(seconds: 400));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 2);

      // 再推进到结束前不应再触发（天然 2 次）
      advance(const Duration(seconds: 300));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 2);
    });
  });

  group('四档反馈：唤醒与声量账（PRD §4.1.4）', () {
    test('离席 90s 轻声 / 180s 加重 / 300s 打断', () {
      final e = makeEngine(plannedMin: 30); // 1800s，避免到时
      e.start(now);
      e.onAbsent();

      advance(const Duration(seconds: kL2ThresholdSeconds));
      e.tick(now);
      expect(
        e.eventHistory.any((ev) =>
            ev.level == FeedbackLevel.lvl4 &&
            ev.wakeIntensity == WakeIntensity.gentle),
        isTrue,
        reason: '90s 应触发轻声唤醒',
      );

      advance(
          const Duration(seconds: kL3ThresholdSeconds - kL2ThresholdSeconds));
      e.tick(now); // 累计 180s
      expect(
        e.eventHistory.any((ev) =>
            ev.level == FeedbackLevel.lvl4 &&
            ev.wakeIntensity == WakeIntensity.strong),
        isTrue,
        reason: '180s 应触发加重唤醒',
      );

      advance(const Duration(seconds: kInterruptSeconds));
      e.tick(now); // 累计 300s
      expect(e.isFinished, isTrue, reason: '300s 应自然结束（打断）');
      expect(e.outcome!.endReason, FocusEndReason.interrupted);
    });

    test('声量账：lvl4 每场 ≤ 3 次，其中加重 ≤ 1 次', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);

      // 第一段离席：90s 轻声 + 90s 加重
      e.onAbsent();
      advance(const Duration(seconds: 180));
      e.tick(now);
      e.onPresent(now);

      // 第二段离席：轻声（第 3 次），加重已达上限 → 抑制
      e.onAbsent();
      advance(const Duration(seconds: 180));
      e.tick(now);
      e.onPresent(now);

      // 第三段离席：轻声已达上限 → 抑制
      e.onAbsent();
      advance(const Duration(seconds: 90));
      e.tick(now);

      final wakes =
          e.eventHistory.where((ev) => ev.level == FeedbackLevel.lvl4).toList();
      expect(wakes.length, lessThanOrEqualTo(kWakeMaxPerSession));
      expect(wakes.length, kWakeMaxPerSession); // 恰好 3 次
      expect(
        wakes
            .where((ev) => ev.wakeIntensity == WakeIntensity.strong)
            .length,
        lessThanOrEqualTo(kWakeStrongMaxPerSession),
      );
      expect(
        wakes
            .where((ev) => ev.wakeIntensity == WakeIntensity.strong)
            .length,
        kWakeStrongMaxPerSession,
      );
      expect(e.isFinished, isFalse); // 未到打断时间轴
    });
  });

  group('结算（PRD §4.1.4 / §6.2）', () {
    test('短于最短结算时长（<5 分钟）→ 无产出', () {
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      advance(const Duration(seconds: 180)); // 3 分钟
      e.tick(now);
      e.stop();

      expect(e.outcome!.status, FocusStatus.shortAborted);
      expect(e.outcome!.rawSunlight, 0.0);
      expect(e.outcome!.actualFocusMin, lessThan(kMinFocusMinutes.toDouble()));
    });

    test('到时正常结束 → completed，产出全额保留', () {
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      advance(const Duration(minutes: 20));
      e.tick(now);

      expect(e.isFinished, isTrue);
      expect(e.outcome!.endReason, FocusEndReason.timedOut);
      expect(e.outcome!.status, FocusStatus.completed);
      expect(e.outcome!.rawSunlight, closeTo(20.0 * kSunlightPerFocusMinute, 1e-6));
    });

    test('打断（离席超时）全额保留已产出，不砍半', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      advance(const Duration(minutes: 6)); // 在场 6 分钟 → 6 阳光
      e.tick(now);
      final earned = e.sunlight;
      expect(earned, closeTo(6.0, 1e-6));

      e.onAbsent();
      advance(const Duration(
          seconds: kL3ThresholdSeconds + kInterruptSeconds)); // 300s
      e.tick(now);

      expect(e.outcome!.endReason, FocusEndReason.interrupted);
      expect(e.outcome!.status, FocusStatus.completed);
      expect(e.outcome!.rawSunlight, closeTo(earned, 1e-6)); // 全额保留
    });
  });
}
