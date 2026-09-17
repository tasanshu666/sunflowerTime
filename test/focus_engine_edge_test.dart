// QA 独立边界用例（M1 批次一 T06–T10）。
//
// 作者：QA 严过关。目的：**证明**专注引擎在 PRD §4.1.3–§4.1.6 / §4.3 / §6.2
// 口径下的边界行为，而不是复述工程师自检。仅依赖 `package:test`（本机 flutter_tester
// 不可用），因此只测纯 Dart 的 FocusEngine（零 Flutter 依赖）。
//
// 结论中标注了若干「口径待确认」项，见每个 review 注释。
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
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

  // ─────────────────────────────────────────────────────────────
  group('A 产出速率（PRD §4.1.5）', () {
    test('A1 连续在场 60s → 恰好 1.0 阳光', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.sunlight, closeTo(1.0, 1e-9));
      expect(e.actualFocusMin, closeTo(1.0, 1e-9));
    });

    test('A2 连续在场 20 分钟到底 → 20.0 阳光', () {
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      advance(const Duration(minutes: 20));
      e.tick(now);
      expect(e.outcome!.rawSunlight, closeTo(20.0, 1e-9));
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('B 离席停产出、不扣减（PRD §4.1.5 / §6.2「灭屏=离席」）', () {
    test('B1 离席期间产出不变，且已得阳光不减少', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 30));
      e.tick(now);
      expect(e.sunlight, closeTo(0.5, 1e-9));

      e.onAbsent(); // 灭屏 → 离席
      advance(const Duration(seconds: 60));
      e.tick(now);
      // 离席 60s：产出停止、不扣减
      expect(e.sunlight, closeTo(0.5, 1e-9));
      // 离席窗口不计入实际专注
      expect(e.actualFocusMin, closeTo(0.5, 1e-9));
      expect(e.state, FocusEngineState.absent);
      expect(e.isAbsent, isTrue);
    });

    test('B2 离席不冻结会话倒计时（elapsed 仍前进）', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 30));
      e.tick(now);
      expect(e.elapsed, const Duration(seconds: 30));

      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);
      // 口径待确认：离席不进产出，但**会话倒计时照走**（与顶部 mm:ss 一致）
      expect(e.elapsed, const Duration(seconds: 90));
    });

    test('B3 离席跨越 1/3 边界仍会送光（随光报信按会话进度触发）', () {
      // 口径待确认：lvl2 边界按「会话进度」判定，离席期间跨越边界也会触发。
      final e = makeEngine(plannedMin: 20); // 1/3 = 400s
      e.start(now);
      advance(const Duration(seconds: 100));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 0);

      e.onAbsent();
      advance(const Duration(seconds: 400)); // 会话进度 500s ≥ 400s
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 1,
          reason: '会话进度越过 1/3 → 即便此刻离席也发 lvl2');
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('C 10 秒线性回满（PRD §4.1.5）', () {
    test('C1 恢复回满窗口产出恒为 5/60 阳光（解析积分）', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      final s0 = e.sunlight;

      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onPresent(now); // 亮屏 → 恢复在场
      advance(const Duration(seconds: 10));
      e.tick(now);

      // ∫0..10 (t/10) dt = 5（秒·满速）→ 5/60 阳光
      expect(e.sunlight - s0, closeTo(5 / 60, 1e-9));
      // lvl3 欢迎回来必发一次
      expect(countLevel(e, FeedbackLevel.lvl3), 1);
    });

    test('C2 回满后转满速：再过 60s 恰好 +1.0', () {
      final e = makeEngine();
      e.start(now);
      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onPresent(now);
      advance(const Duration(seconds: 10));
      e.tick(now);
      final s1 = e.sunlight; // 5/60
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.sunlight - s1, closeTo(1.0, 1e-9));
    });

    test('C3 逐秒 tick 累加回满同样得 5/60（积分对分步鲁棒）', () {
      final e = makeEngine();
      e.start(now);
      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onPresent(now);
      final s0 = e.sunlight;
      for (var i = 0; i < 10; i++) {
        advance(const Duration(seconds: 1));
        e.tick(now);
      }
      expect(e.sunlight - s0, closeTo(5 / 60, 1e-9));
    });

    test('C4 口径不一致证据：rawSunlight 与 actualFocusMin×rate 相差 5/60', () {
      // 引擎按 §4.1.5 斜坡积分；但 SunlightService.settle() 用 actualFocusMin 计 S，
      // 两者在有一次恢复后不等 —— 差额恰为回满窗口少算的 5/60（见报告 P2）。
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      advance(const Duration(minutes: 5));
      e.tick(now);
      e.onAbsent();
      advance(const Duration(seconds: 60));
      e.tick(now);
      e.onPresent(now);
      advance(const Duration(seconds: 10));
      e.tick(now);
      advance(const Duration(minutes: 1));
      e.tick(now);
      e.stop();

      final o = e.outcome!;
      expect(o.rawSunlight, closeTo(6.0 + 5 / 60, 1e-9)); // 引擎口径
      expect(o.actualFocusMin, closeTo(6.0 + 10 / 60, 1e-9)); // 含回满窗口全速
      expect(
        o.actualFocusMin * kSunlightPerFocusMinute - o.rawSunlight,
        closeTo(5 / 60, 1e-9),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('D 随光报信 1/3、2/3（PRD §4.1.3）', () {
    test('D1 恰好各一次，共 2 次', () {
      final e = makeEngine(plannedMin: 20); // 1200s：1/3=400，2/3=800
      e.start(now);
      advance(const Duration(seconds: 400));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 1);
      advance(const Duration(seconds: 400));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 2);
      advance(const Duration(seconds: 399));
      e.tick(now);
      expect(countLevel(e, FeedbackLevel.lvl2), 2, reason: '天然 2 次，不追加');
    });

    test('D2 边界前 1 微秒不触发，恰好到点才触发', () {
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      e.tick(now.add(const Duration(seconds: 400)));
      expect(countLevel(e, FeedbackLevel.lvl2), 1);
      final e2 = makeEngine(plannedMin: 20);
      e2.start(now);
      e2.tick(now.add(const Duration(milliseconds: 399999)));
      expect(countLevel(e2, FeedbackLevel.lvl2), 0);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('E 唤醒时间轴 90/180/300s（PRD §4.1.4）', () {
    test('E1 90s 轻声 → 180s 加重 → 300s 打断结束', () {
      final e = makeEngine(plannedMin: 30); // 避免到时
      e.start(now);
      e.onAbsent();

      advance(const Duration(seconds: kL2ThresholdSeconds));
      e.tick(now);
      expect(
        wakes(e).any((ev) => ev.wakeIntensity == WakeIntensity.gentle),
        isTrue,
      );

      advance(const Duration(seconds: kL3ThresholdSeconds - kL2ThresholdSeconds));
      e.tick(now);
      expect(
        wakes(e).any((ev) => ev.wakeIntensity == WakeIntensity.strong),
        isTrue,
      );

      advance(const Duration(seconds: kInterruptSeconds));
      e.tick(now);
      expect(e.isFinished, isTrue);
      expect(e.outcome!.endReason, FocusEndReason.interrupted);
    });

    test('E2 边界：89s 不唤醒，第 90s 才轻声', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      e.onAbsent();
      advance(const Duration(seconds: kL2ThresholdSeconds - 1));
      e.tick(now);
      expect(wakes(e), isEmpty, reason: '89s 不应唤醒');
      advance(const Duration(seconds: 1));
      e.tick(now);
      expect(wakes(e).length, 1, reason: '第 90s 才轻声');
    });

    test('E3 恢复在场重置离席窗口：两段 89s 均不唤醒', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      e.onAbsent();
      advance(const Duration(seconds: 89));
      e.tick(now);
      e.onPresent(now); // 回到座位 → 窗口重置
      e.onAbsent();
      advance(const Duration(seconds: 89));
      e.tick(now);
      expect(wakes(e), isEmpty, reason: '「离席持续」= 连续，恢复即重置');
      expect(countLevel(e, FeedbackLevel.lvl3), 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('F 声量账（PRD §4.1.4）', () {
    test('F1 lvl4 每场 ≤ 3 次', () {
      final e = makeEngine(plannedMin: 60);
      e.start(now);
      for (var seg = 0; seg < 5; seg++) {
        e.onAbsent();
        advance(const Duration(seconds: kL2ThresholdSeconds));
        e.tick(now);
        e.onPresent(now);
      }
      expect(wakes(e).length, lessThanOrEqualTo(kWakeMaxPerSession));
      expect(wakes(e).length, kWakeMaxPerSession); // 恰好 3 次
    });

    test('F2 加重 ≤ 1 次', () {
      final e = makeEngine(plannedMin: 60);
      e.start(now);
      for (var seg = 0; seg < 3; seg++) {
        e.onAbsent();
        advance(const Duration(seconds: kL3ThresholdSeconds)); // 到 180s
        e.tick(now);
        e.onPresent(now);
      }
      final strong =
          wakes(e).where((ev) => ev.wakeIntensity == WakeIntensity.strong);
      expect(strong.length, lessThanOrEqualTo(kWakeStrongMaxPerSession));
      expect(strong.length, kWakeStrongMaxPerSession);
    });

    test('F3 声量用尽后，300s 仍会打断（抑制只作用于语音，不改时间轴）', () {
      final e = makeEngine(plannedMin: 60);
      e.start(now);
      // 用尽 3 次轻声额度
      for (var seg = 0; seg < 3; seg++) {
        e.onAbsent();
        advance(const Duration(seconds: kL2ThresholdSeconds));
        e.tick(now);
        e.onPresent(now);
      }
      expect(wakes(e).length, kWakeMaxPerSession);

      // 再离席 300s：语音被抑制，但打断照常
      e.onAbsent();
      advance(const Duration(
          seconds: kL3ThresholdSeconds + kInterruptSeconds)); // 300s
      e.tick(now);
      expect(wakes(e).length, kWakeMaxPerSession, reason: '不再新增语音');
      expect(e.isFinished, isTrue, reason: '用尽后仍按 300s 打断');
      expect(e.outcome!.endReason, FocusEndReason.interrupted);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('G 最短结算时长 5 分钟（PRD §6.2）', () {
    test('G1 4 分 59 秒 → shortAborted，阳光 0', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 299));
      e.tick(now);
      e.stop();
      expect(e.outcome!.status, FocusStatus.shortAborted);
      expect(e.outcome!.rawSunlight, 0.0);
      expect(e.outcome!.actualFocusMin, lessThan(kMinFocusMinutes.toDouble()));
    });

    test('G2 恰好 5 分 00 秒 → completed，有产出', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 300));
      e.tick(now);
      e.stop();
      expect(e.outcome!.status, FocusStatus.completed);
      expect(e.outcome!.rawSunlight, closeTo(5.0, 1e-9));
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('H 打断也要求实际专注 ≥5 分钟（PRD §6.2 明写）', () {
    test('H1 在场仅 4 分钟后被打断 → 无产出', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      advance(const Duration(minutes: 4));
      e.tick(now);
      e.onAbsent();
      advance(const Duration(
          seconds: kL3ThresholdSeconds + kInterruptSeconds)); // 300s
      e.tick(now);

      expect(e.outcome!.endReason, FocusEndReason.interrupted);
      expect(e.outcome!.status, FocusStatus.shortAborted,
          reason: '打断实际专注 <5 分钟，同样作废');
      expect(e.outcome!.rawSunlight, 0.0);
    });

    test('H2 在场满 5 分钟后被打断 → 全额保留', () {
      final e = makeEngine(plannedMin: 30);
      e.start(now);
      advance(const Duration(minutes: 5));
      e.tick(now);
      e.onAbsent();
      advance(const Duration(
          seconds: kL3ThresholdSeconds + kInterruptSeconds));
      e.tick(now);

      expect(e.outcome!.endReason, FocusEndReason.interrupted);
      expect(e.outcome!.status, FocusStatus.completed);
      expect(e.outcome!.rawSunlight, closeTo(5.0, 1e-9));
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('I 到时正常结束（PRD §4.1.2）', () {
    test('I1 planned 到点 → timedOut / completed / 产出正确', () {
      final e = makeEngine(plannedMin: 20);
      e.start(now);
      for (var i = 0; i < 20; i++) {
        advance(const Duration(minutes: 1));
        e.tick(now);
      }
      expect(e.isFinished, isTrue);
      expect(e.outcome!.endReason, FocusEndReason.timedOut);
      expect(e.outcome!.status, FocusStatus.completed);
      expect(e.outcome!.rawSunlight, closeTo(20.0, 1e-9));
      expect(e.remaining, Duration.zero);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('J 暂停冻结（PRD §4.1.6 退出确认）', () {
    test('J1 paused 冻结会话倒计时与产出', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.elapsed, const Duration(seconds: 60));
      expect(e.sunlight, closeTo(1.0, 1e-9));

      e.pause();
      advance(const Duration(seconds: 300)); // 确认框停留 5 分钟
      e.tick(now);
      expect(e.elapsed, const Duration(seconds: 60), reason: '暂停冻结倒计时');
      expect(e.sunlight, closeTo(1.0, 1e-9), reason: '暂停冻结产出');

      e.resume(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.elapsed, const Duration(seconds: 120));
      expect(e.sunlight, closeTo(2.0, 1e-9));
    });

    test('J2 paused 与 absent 的区别：absent 走时钟、paused 不走', () {
      final absent = makeEngine();
      absent.start(now);
      absent.onAbsent();
      advance(const Duration(seconds: 120));
      absent.tick(now);

      final paused = makeEngine();
      paused.start(now);
      paused.pause();
      advance(const Duration(seconds: 120));
      paused.tick(now);

      expect(absent.elapsed, const Duration(seconds: 120));
      expect(paused.elapsed, Duration.zero);
      expect(paused.state, FocusEngineState.paused);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('K 鲁棒性（不得崩溃 / 不得负阳光）', () {
    test('K1 tick 传入倒退时间：不崩溃、不产生负阳光', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 60));
      e.tick(now);
      expect(e.sunlight, closeTo(1.0, 1e-9));

      e.tick(now.subtract(const Duration(seconds: 30))); // 倒退
      expect(e.sunlight, closeTo(1.0, 1e-9));
      expect(e.sunlight, greaterThanOrEqualTo(0));
    });

    test('K2 重复 finish() 幂等，outcome 不被覆盖', () {
      final e = makeEngine();
      e.start(now);
      advance(const Duration(seconds: 300));
      e.tick(now);
      e.stop(); // manual
      final first = e.outcome;
      e.finish(FocusEndReason.timedOut); // 再次结束
      expect(identical(e.outcome, first), isTrue);
      expect(e.outcome!.endReason, FocusEndReason.manual);
    });

    test('K3 planned = 0：立即结束且无产出、不崩溃', () {
      final e = FocusEngine(planned: Duration.zero, clock: () => now);
      e.start(now);
      e.tick(now);
      expect(e.isFinished, isTrue);
      expect(e.outcome!.status, FocusStatus.shortAborted);
      expect(e.outcome!.rawSunlight, 0.0);
    });

    test('K4 planned 为负：不崩溃、不产生负阳光', () {
      final e = FocusEngine(planned: const Duration(minutes: -5), clock: () => now);
      e.start(now);
      advance(const Duration(seconds: 10));
      e.tick(now);
      expect(e.sunlight, greaterThanOrEqualTo(0));
      expect(e.remaining, Duration.zero);
    });

    test('K5 未 start 直接 tick/finish 不崩溃', () {
      final e = makeEngine();
      expect(() => e.tick(now), returnsNormally); // idle 直接返回
      e.stop();
      expect(e.isFinished, isTrue);
    });
  });
}
