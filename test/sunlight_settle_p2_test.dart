// QA Round-2 复验：P2-1（结算改用 outcome.rawSunlight，不再从 actualFocusMin 反推）
// 与「专注日上限」口径（2026-09-23 取代分段软顶）的端到端验证。
//
// 用内存假仓储替代 Drift，仅验证领域逻辑；不触碰真实数据库。仅依赖 `package:test`。
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/math_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
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

  /// 聚焦额度核算依赖本方法：必须**真的**按 refType 过滤，否则「额度截断」
  /// 相关断言会因一律返回 0 而失去意义（假仓储也要忠于契约）。
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async =>
      entries
          .where((e) => e.refType == refType && e.dayKey == dayKey)
          .fold<double>(0.0, (s, e) => s + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((e) =>
              e.refType == refType && e.dayKey.startsWith(monthKey))
          .fold<double>(0.0, (s, e) => s + e.net);

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      entries
          .where((e) =>
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == dayKey)
          .length;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => entries
      .where((e) => e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0.0, (s, e) => s + e.gross);

  @override
  Future<double> earnNetOnDay(String dayKey) async => entries
      .where((e) => e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0.0, (s, e) => s + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.from(entries);
}

class _FakeFocus implements FocusRepository {
  final List<FocusSession> sessions = <FocusSession>[];

  @override
  Future<void> saveSession(FocusSession session) async => sessions.add(session);

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async => const [];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 直接构造一个已完成的专注产出（不必驱动引擎，专注阳光 = 传入值）。
FocusOutcome _done(double sunlight, {double? minutes}) => FocusOutcome(
      actualFocusMin: minutes ?? sunlight,
      rawSunlight: sunlight,
      status: FocusStatus.completed,
      endReason: FocusEndReason.timedOut,
      wakeCount: 0,
      strongWakeCount: 0,
    );

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
        dailyFocusCap: kDailyFocusCapHigh,
      );

      expect(settlement.rawS, closeTo(outcome.rawSunlight, 1e-9),
          reason: 'rawS 必须等于引擎 rawSunlight，不再从 actualFocusMin 反推');
      expect(settlement.rawS,
          lessThan(outcome.actualFocusMin * kSunlightPerFocusMinute - 1e-6),
          reason: '修复后 rawS 应小于旧的 actualFocusMin×rate 口径');
      expect(ledger.entries.length, 1);
      expect(ledger.entries.single.gross, closeTo(outcome.rawSunlight, 1e-9));
      // 额度充足（高年段 120）→ 1:1 全额到手，不再分段打薄。
      expect(ledger.entries.single.net, closeTo(outcome.rawSunlight, 1e-9));
      expect(settlement.net, closeTo(outcome.rawSunlight, 1e-9));
      expect(settlement.capped, isFalse, reason: '额度充足不应标记被截断');
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
        dailyFocusCap: kDailyFocusCapHigh,
      );
      expect(s.rawS, 0.0);
      expect(s.net, 0.0);
      expect(s.capped, isFalse);
      expect(ledger.entries, isEmpty);
      expect(focus.sessions.length, 1);
      expect(focus.sessions.single.status, FocusStatus.shortAborted);
    });
  });

  group('O 专注日上限（2026-09-23 口径，取代分段软顶）', () {
    test('O1 effectiveFocusSunlight：min(本场, 剩余额度)，负数一律 0', () {
      expect(
          effectiveFocusSunlight(focusSunlight: 10, remainingAllowance: 5), 5);
      expect(
          effectiveFocusSunlight(focusSunlight: 5, remainingAllowance: 10), 5);
      expect(
          effectiveFocusSunlight(focusSunlight: 10, remainingAllowance: 0), 0);
      expect(
          effectiveFocusSunlight(focusSunlight: 0, remainingAllowance: 10), 0);
      expect(
          effectiveFocusSunlight(focusSunlight: -3, remainingAllowance: 10), 0);
      expect(
          effectiveFocusSunlight(focusSunlight: 10, remainingAllowance: -1), 0);
    });

    test('O2 单场即被年段上限截断（低年段 60：专注 90 分钟只拿 60）', () async {
      final ledger = _FakeLedger();
      final svc =
          SunlightService(ledger: ledger, focus: _FakeFocus());
      final s = await svc.settle(
        outcome: _done(90),
        start: DateTime(2026, 9, 15, 9, 0, 0),
        end: DateTime(2026, 9, 15, 10, 30, 0),
        plannedMin: 90,
        dailyFocusCap: kDailyFocusCapLow, // 60
      );
      expect(s.rawS, 90);
      expect(s.net, closeTo(60, 1e-9),
          reason: '1:1 + 年段硬封顶：90 分钟只到手 60（旧口径会打薄成 75）');
      expect(s.capped, isTrue);
      // 高年段同样一场 90 分钟 → 应全额 90（证明封顶真的跟着年段走）
      final ledger2 = _FakeLedger();
      final svc2 =
          SunlightService(ledger: ledger2, focus: _FakeFocus());
      final s2 = await svc2.settle(
        outcome: _done(90),
        start: DateTime(2026, 9, 15, 9, 0, 0),
        end: DateTime(2026, 9, 15, 10, 30, 0),
        plannedMin: 90,
        dailyFocusCap: kDailyFocusCapHigh, // 120
      );
      expect(s2.net, closeTo(90, 1e-9), reason: '高年段 120 应能拿满 90');
      expect(s2.capped, isFalse);
    });

    test('O3 多场累计不超上限（低年段 60：三场 30 分钟 → 30/30/0）', () async {
      final ledger = _FakeLedger();
      final focus = _FakeFocus();
      final svc = SunlightService(ledger: ledger, focus: focus);
      final day = DateTime(2026, 9, 15);

      Future<FocusSettlement> run(int hour) => svc.settle(
            outcome: _done(30),
            start: DateTime(2026, 9, 15, hour),
            end: DateTime(2026, 9, 15, hour, 30),
            plannedMin: 30,
            dailyFocusCap: kDailyFocusCapLow,
          );

      final a = await run(9);
      final b = await run(11);
      final c = await run(14);

      expect(a.net, closeTo(30, 1e-9));
      expect(b.net, closeTo(30, 1e-9));
      expect(c.net, closeTo(0, 1e-9), reason: '额度已用完 → 第三场不再发阳光');
      expect(c.capped, isTrue);
      expect(await svc.focusEarnedToday(DateTime(2026, 9, 15, 15)),
          closeTo(60, 1e-9));
      expect(await svc.focusRemainingToday(kDailyFocusCapLow, DateTime(2026, 9, 15, 15)),
          closeTo(0, 1e-9));
      // 额度用完后仍留痕（net=0 的账目），便于对账「这场为什么没拿到阳光」。
      expect(ledger.entries.length, 3);
      expect(dayKey(day), isNotEmpty);
    });

    test('O4 成长奖励与家长赠予不占专注额度（不被挤占）', () async {
      final ledger = _FakeLedger();
      final svc = SunlightService(ledger: ledger, focus: _FakeFocus());
      final day = DateTime(2026, 9, 15, 9);

      // 先灌入成长打卡 79 + 家长赠予 100（都是 earn，但 refType 与专注无关）。
      ledger.entries.addAll(<SunlightEntry>[
        SunlightEntry(
          id: 'c1',
          ts: day,
          type: SunlightType.earn,
          gross: kTaskCheckinDailyCap,
          net: kTaskCheckinDailyCap,
          balanceAfter: kTaskCheckinDailyCap,
          refType: 'task_checkin',
          refId: 'k1',
          dayKey: dayKey(day),
        ),
        SunlightEntry(
          id: 'g1',
          ts: day,
          type: SunlightType.earn,
          gross: 100,
          net: 100,
          balanceAfter: 179,
          refType: 'parent_gift',
          refId: null,
          dayKey: dayKey(day),
        ),
      ]);

      // 专注额度应仍是满额 60（上面两笔都不是 focus_session）。
      expect(await svc.focusEarnedToday(day), 0);
      final s = await svc.settle(
        outcome: _done(60),
        start: day,
        end: DateTime(2026, 9, 15, 10),
        plannedMin: 60,
        dailyFocusCap: kDailyFocusCapLow,
      );
      expect(s.net, closeTo(60, 1e-9),
          reason: '成长奖励/家长赠予不占专注额度，专注应照拿 60');
      expect(s.capped, isFalse);
    });

    test('O5 任务奖励单独记账，不污染后续专注额度', () async {
      final ledger = _FakeLedger();
      final svc = SunlightService(ledger: ledger, focus: _FakeFocus());
      final day = DateTime(2026, 9, 15, 9);

      final first = await svc.settle(
        outcome: _done(10),
        start: day,
        end: DateTime(2026, 9, 15, 9, 10),
        plannedMin: 10,
        dailyFocusCap: kDailyFocusCapLow,
        taskCount: 2, // 2 × 12 = 24 任务奖励
      );
      expect(first.net, closeTo(10 + 2 * kTaskSunlightReward, 1e-9));
      // 两条账目：专注一条、任务奖励一条
      expect(ledger.entries.length, 2);
      final focusEntry = ledger.entries
          .firstWhere((e) => e.refType == SunlightService.focusRefType);
      final taskEntry = ledger.entries
          .firstWhere((e) => e.refType == SunlightService.focusTaskRewardRefType);
      expect(focusEntry.net, closeTo(10, 1e-9));
      expect(taskEntry.net, closeTo(2 * kTaskSunlightReward, 1e-9));
      // 关键：任务奖励没被算进「已用专注额度」，第二场仍能用满剩余 50 分钟
      expect(await svc.focusEarnedToday(day), closeTo(10, 1e-9));
      final second = await svc.settle(
        outcome: _done(50),
        start: day,
        end: DateTime(2026, 9, 15, 10, 30),
        plannedMin: 50,
        dailyFocusCap: kDailyFocusCapLow,
      );
      expect(second.net, closeTo(50, 1e-9));
    });

    test('O6 rawS 语义仍为「未受上限约束的原始产出」', () async {
      final svc = SunlightService(ledger: _FakeLedger(), focus: _FakeFocus());
      final s = await svc.settle(
        outcome: _done(45),
        start: DateTime(2026, 9, 15, 9),
        end: DateTime(2026, 9, 15, 9, 45),
        plannedMin: 45,
        dailyFocusCap: kDailyFocusCapLow,
      );
      expect(s.rawS, 45);
      expect(s.net, 45);
      expect(await svc.todayCumulativeNet(DateTime(2026, 9, 15, 10)), 45);
    });
  });

  group('O P2-3：autoApprovePoolCap 默认参数改可空后无语义漂移', () {
    test('O7 周自动放行上限', () {
      // 旧行为：ceiling=min(100,40)=40；返回 min(pool*0.25, 40)
      expect(autoApprovePoolCap(400), closeTo(40.0, 1e-9));
      expect(autoApprovePoolCap(100), closeTo(25.0, 1e-9));
      expect(autoApprovePoolCap(0), closeTo(0.0, 1e-9));
      // 显式传参路径仍可用
      expect(autoApprovePoolCap(400, ceilingHigh: 100, ceilingLow: 40),
          closeTo(40.0, 1e-9));
      expect(autoApprovePoolCap(1000, ceilingHigh: 500, ceilingLow: 300),
          closeTo(250.0, 1e-9));
    });
  });
}
