// QA Round-2 复验：P2-1（结算改用 outcome.rawSunlight，不再从 actualFocusMin 反推）
// 与 P2-3（软顶改用常量引用后数值不得漂移）的端到端验证。
//
// 用内存假仓储替代 Drift，仅验证领域逻辑；不触碰真实数据库。仅依赖 `package:test`。
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/utils/math_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';

class _FakeLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async =>
      entries.fold<double>(0.0, (s, e) => s + e.net);

  @override
  Future<double> dayNet(String dayKey) async => entries
      .where((e) => e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0.0, (s, e) => s + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0.0;
}

class _FakeFocus implements FocusRepository {
  final List<FocusSession> sessions = <FocusSession>[];

  @override
  Future<void> saveSession(FocusSession session) async => sessions.add(session);

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async => const [];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
}

void main() {
  group('N P2-1：结算 S 与引擎 rawSunlight 一致（不再多算 5/60）', () {
    test('N1 离席→恢复→结束：账本 gross/净产出 = outcome.rawSunlight', () async {
      var now = DateTime(2026, 9, 15, 9, 0, 0);
      final start = now;
      final e = FocusEngine(
        planned: const Duration(minutes: 20),
        clock: () => now,
      );
      e.start(now);
      now = now.add(const Duration(minutes: 5));
      e.tick(now); // 在场 5 分钟
      e.onAbsent(now);
      now = now.add(const Duration(seconds: 60)); // 离席 60s
      e.onPresent(now); // 恢复，起 10s 斜坡
      now = now.add(const Duration(seconds: 10));
      e.tick(now); // 回满窗口
      now = now.add(const Duration(seconds: 60));
      e.tick(now); // 满速 1 分钟
      e.stop();

      final outcome = e.outcome!;
      // 引擎口径：5 + 5/60(回满) + 1 = 6 + 5/60
      expect(outcome.rawSunlight, closeTo(6.0 + 5 / 60, 1e-9));
      // 实际专注分钟含回满窗口全速：5 + 10/60 + 1
      expect(outcome.actualFocusMin, closeTo(6.0 + 10 / 60, 1e-9));
      // 两者相差 5/60 —— 修复前的 settle 会误用后者
      expect(outcome.actualFocusMin - outcome.rawSunlight, closeTo(5 / 60, 1e-9));

      final ledger = _FakeLedger();
      final focus = _FakeFocus();
      final svc = SunlightService(ledger: ledger, focus: focus);
      final settlement = await svc.settle(
        outcome: outcome,
        start: start,
        end: now,
        plannedMin: 20,
      );

      expect(settlement.rawS, closeTo(outcome.rawSunlight, 1e-9),
          reason: 'rawS 必须等于引擎 rawSunlight，不再从 actualFocusMin 反推');
      expect(settlement.rawS,
          lessThan(outcome.actualFocusMin * kSunlightPerFocusMinute - 1e-6),
          reason: '修复后 rawS 应小于旧的 actualFocusMin×rate 口径');
      expect(ledger.entries.length, 1);
      expect(ledger.entries.single.gross, closeTo(outcome.rawSunlight, 1e-9));
      expect(ledger.entries.single.net,
          closeTo(computeSoftCap(outcome.rawSunlight), 1e-9));
      expect(focus.sessions.length, 1);
      expect(focus.sessions.single.sunlightEarned, settlement.net);
    });

    test('N2 短于 5 分钟：无账本记录、S=0，但仍保存会话', () async {
      var now = DateTime(2026, 9, 15, 9, 0, 0);
      final e = FocusEngine(
        planned: const Duration(minutes: 20),
        clock: () => now,
      );
      e.start(now);
      now = now.add(const Duration(seconds: 180));
      e.tick(now);
      e.stop();
      expect(e.outcome!.status, FocusStatus.shortAborted);

      final ledger = _FakeLedger();
      final focus = _FakeFocus();
      final svc = SunlightService(ledger: ledger, focus: focus);
      final s = await svc.settle(
        outcome: e.outcome!,
        start: DateTime(2026, 9, 15, 9, 0, 0),
        end: now,
        plannedMin: 20,
      );
      expect(s.rawS, 0.0);
      expect(s.net, 0.0);
      expect(ledger.entries, isEmpty);
      expect(focus.sessions.length, 1);
      expect(focus.sessions.single.status, FocusStatus.shortAborted);
    });
  });

  group('O P2-3：软顶数值未因改用常量引用而漂移', () {
    test('O1 PRD §4.5 校验值', () {
      expect(computeSoftCap(162), closeTo(79.0, 1e-9)); // 硬顶
      expect(computeSoftCap(91.8), closeTo(75.36, 1e-9)); // 第三段
      expect(computeSoftCap(47.6), closeTo(47.6, 1e-9)); // 第一段
    });

    test('O2 分段边界值', () {
      expect(computeSoftCap(0), 0);
      expect(computeSoftCap(60), 60); // 段1 末
      expect(computeSoftCap(60.0001), closeTo(60.00005, 1e-9));
      expect(computeSoftCap(90), closeTo(75.0, 1e-9)); // 段2 末
      expect(computeSoftCap(110), closeTo(79.0, 1e-9)); // 段3 末
      expect(computeSoftCap(110.0001), closeTo(79.0, 1e-9)); // 硬顶
      expect(computeSoftCap(1000), closeTo(79.0, 1e-9));
    });

    test('O3 autoApproveMonthlyCap 默认参数改可空后无语义漂移', () {
      // 旧行为：ceiling=min(100,40)=40；返回 min(pool*0.25, 40)
      expect(autoApproveMonthlyCap(400), closeTo(40.0, 1e-9));
      expect(autoApproveMonthlyCap(100), closeTo(25.0, 1e-9));
      expect(autoApproveMonthlyCap(0), closeTo(0.0, 1e-9));
      // 显式传参路径仍可用
      expect(autoApproveMonthlyCap(400, ceilingHigh: 100, ceilingLow: 40),
          closeTo(40.0, 1e-9));
      expect(autoApproveMonthlyCap(1000, ceilingHigh: 500, ceilingLow: 300),
          closeTo(250.0, 1e-9));
    });
  });
}
