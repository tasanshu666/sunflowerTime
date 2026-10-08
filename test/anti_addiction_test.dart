/// 防沉迷服务单测（T11，§6.1 / §6.3）。
///
/// 覆盖：夜间边界、每日上限、综合决策优先级、休息节奏。
library anti_addiction_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';

/// 高年段默认设置（cap=60，边界 21:00，休息每 2 场）。
AppSettings _highSettings() => const AppSettings(
      ageTier: AgeTier.high,
      dailyFocusCap: 60,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 400,
    );

/// 低年段设置（cap=90，边界 21:00，休息每 2 场）。
AppSettings _lowSettings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
    );

void main() {
  group('isNightLocked', () {
    final s = _highSettings();

    test('默认边界 21:00：20:00 为 false', () {
      expect(
        AntiAddictionService().isNightLocked(s, DateTime(2026, 9, 15, 20, 0)),
        isFalse,
      );
    });
    test('默认边界 21:00：21:00 为 true', () {
      expect(
        AntiAddictionService().isNightLocked(s, DateTime(2026, 9, 15, 21, 0)),
        isTrue,
      );
    });
    test('默认边界 21:00：23:30 为 true', () {
      expect(
        AntiAddictionService().isNightLocked(s, DateTime(2026, 9, 15, 23, 30)),
        isTrue,
      );
    });

    test('自定义边界 22:00：21:30 为 false', () {
      const s2 = AppSettings(
        ageTier: AgeTier.high,
        nightBoundaryHour: 22,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 400,
      );
      expect(
        AntiAddictionService().isNightLocked(s2, DateTime(2026, 9, 15, 21, 30)),
        isFalse,
      );
    });
    test('自定义边界 22:00：22:00 为 true', () {
      const s2 = AppSettings(
        ageTier: AgeTier.high,
        nightBoundaryHour: 22,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 400,
      );
      expect(
        AntiAddictionService().isNightLocked(s2, DateTime(2026, 9, 15, 22, 0)),
        isTrue,
      );
    });
  });

  group('dailyFocusRemaining', () {
    final high = _highSettings();
    final low = _lowSettings();

    test('高年段 cap=60：used=0 → 60', () {
      expect(AntiAddictionService().dailyFocusRemaining(high, 0), 60);
    });
    test('高年段 cap=60：used=59 → 1', () {
      expect(AntiAddictionService().dailyFocusRemaining(high, 59), 1);
    });
    test('高年段 cap=60：used=60 → 0', () {
      expect(AntiAddictionService().dailyFocusRemaining(high, 60), 0);
    });
    test('高年段 cap=60：used=90 → 0（封底）', () {
      expect(AntiAddictionService().dailyFocusRemaining(high, 90), 0);
    });
    test('低年段 cap=90：used=0 → 90', () {
      expect(AntiAddictionService().dailyFocusRemaining(low, 0), 90);
    });
    test('低年段 cap=90：used=89 → 1', () {
      expect(AntiAddictionService().dailyFocusRemaining(low, 89), 1);
    });
    test('低年段 cap=90：used=90 → 0', () {
      expect(AntiAddictionService().dailyFocusRemaining(low, 90), 0);
    });
    test('低年段 cap=90：used=120 → 0（封底）', () {
      expect(AntiAddictionService().dailyFocusRemaining(low, 120), 0);
    });
  });

  group('evaluate 优先级', () {
    final s = _highSettings();

    test('nightLocked 优先于其它（21:00 即便未达上限也 nightLocked）', () {
      final d = AntiAddictionService().evaluate(
        s: s,
        now: DateTime(2026, 9, 15, 21, 0),
        todayFocusMin: 0,
        todayValidSessions: 0,
      );
      expect(d, AntiAddictionDecision.nightLocked);
    });

    test('todayFocusMin >= cap → dailyCapReached', () {
      final d = AntiAddictionService().evaluate(
        s: s,
        now: DateTime(2026, 9, 15, 20, 0),
        todayFocusMin: 60,
        todayValidSessions: 0,
      );
      expect(d, AntiAddictionDecision.dailyCapReached);
    });

    test('todayValidSessions=2 且 !restSatisfied → restRequired', () {
      final d = AntiAddictionService().evaluate(
        s: s,
        now: DateTime(2026, 9, 15, 20, 0),
        todayFocusMin: 0,
        todayValidSessions: 2,
        restSatisfied: false,
      );
      expect(d, AntiAddictionDecision.restRequired);
    });

    test('restSatisfied=true → allowed（即便 sessions=2）', () {
      final d = AntiAddictionService().evaluate(
        s: s,
        now: DateTime(2026, 9, 15, 20, 0),
        todayFocusMin: 0,
        todayValidSessions: 2,
        restSatisfied: true,
      );
      expect(d, AntiAddictionDecision.allowed);
    });

    test('正常（白天、未达上限、sessions=1）→ allowed', () {
      final d = AntiAddictionService().evaluate(
        s: s,
        now: DateTime(2026, 9, 15, 20, 0),
        todayFocusMin: 0,
        todayValidSessions: 1,
      );
      expect(d, AntiAddictionDecision.allowed);
    });
  });

  group('restRequired 节奏', () {
    final s = _highSettings();
    final service = AntiAddictionService();

    test('sessions=1 → false', () => expect(service.restRequired(s, 1), isFalse));
    test('sessions=2 → true', () => expect(service.restRequired(s, 2), isTrue));
    test('sessions=3 → false', () => expect(service.restRequired(s, 3), isFalse));
    test('sessions=4 → true', () => expect(service.restRequired(s, 4), isTrue));
  });

  // F66（2026-10-03 真机反馈）：休息义务按墙上时钟推导——锁屏/离开 App 也算休息。
  group('F66 休息义务墙上时钟推导', () {
    final s = _highSettings(); // restMinutes = 10
    final service = AntiAddictionService();

    FocusSession completedAt(DateTime end) => FocusSession(
          id: 's1',
          start: end.subtract(const Duration(minutes: 20)),
          end: end,
          plannedMin: 20,
          actualFocusMin: 20,
          status: FocusStatus.completed,
          sunlightEarned: 20,
          createdAt: end,
        );

    test('lastCompletedSessionEnd：取完成会话的最晚 end（忽略未完成/无 end）', () {
      final DateTime t1 = DateTime(2026, 10, 3, 10, 0);
      final DateTime t2 = DateTime(2026, 10, 3, 11, 0);
      final sessions = <FocusSession>[
        completedAt(t1),
        completedAt(t2),
        FocusSession(
          id: 's3',
          start: t2.add(const Duration(minutes: 30)),
          plannedMin: 15,
          actualFocusMin: 0,
          status: FocusStatus.shortAborted,
          sunlightEarned: 0,
          createdAt: t2.add(const Duration(minutes: 30)),
        ),
      ];
      expect(service.lastCompletedSessionEnd(sessions), t2);
    });

    test('lastCompletedSessionEnd：空列表 → null', () {
      expect(service.lastCompletedSessionEnd(const <FocusSession>[]), isNull);
    });

    test('restNaturallySatisfied：结束至今恰好 10 分钟 → true', () {
      final DateTime end = DateTime(2026, 10, 3, 10, 0);
      expect(
        service.restNaturallySatisfied(
          restMinutes: s.restMinutes,
          now: end.add(const Duration(minutes: 10)),
          lastSessionEnd: end,
        ),
        isTrue,
      );
    });

    test('restNaturallySatisfied：结束至今 9 分 59 秒 → false', () {
      final DateTime end = DateTime(2026, 10, 3, 10, 0);
      expect(
        service.restNaturallySatisfied(
          restMinutes: s.restMinutes,
          now: end.add(
            const Duration(minutes: 9, seconds: 59),
          ),
          lastSessionEnd: end,
        ),
        isFalse,
      );
    });

    test('restNaturallySatisfied：基准为 null → false（不放行）', () {
      expect(
        service.restNaturallySatisfied(
          restMinutes: s.restMinutes,
          now: DateTime(2026, 10, 3, 12, 0),
          lastSessionEnd: null,
        ),
        isFalse,
      );
    });

    test('restRemaining：结束至今 20 分钟 → 零（免重新计满）', () {
      final DateTime end = DateTime(2026, 10, 3, 10, 0);
      expect(
        service.restRemaining(
          restMinutes: s.restMinutes,
          now: end.add(const Duration(minutes: 20)),
          lastSessionEnd: end,
        ),
        Duration.zero,
      );
    });

    test('restRemaining：结束至今 4 分钟 → 还剩 6 分钟', () {
      final DateTime end = DateTime(2026, 10, 3, 10, 0);
      expect(
        service.restRemaining(
          restMinutes: s.restMinutes,
          now: end.add(const Duration(minutes: 4)),
          lastSessionEnd: end,
        ),
        const Duration(minutes: 6),
      );
    });

    test('restRemaining：基准为 null → 完整 restMinutes（安全侧回退）', () {
      expect(
        service.restRemaining(
          restMinutes: s.restMinutes,
          now: DateTime(2026, 10, 3, 12, 0),
          lastSessionEnd: null,
        ),
        const Duration(minutes: 10),
      );
    });
  });

  // 2026-10-08 修订（玄参真机实证：早上 08:34 与中午 12:44 各一场，间隔 4h，
  // 旧口径按当日累计 2 场立刻触发休息）。休息节奏的计数改为「连续场数」：
  // 两场之间自然间隔 ≥ restMinutes 即断连重置。
  group('consecutiveValidSessions 连续场数（2026-10-08 修订）', () {
    final service = AntiAddictionService();
    const int restMinutes = 10;

    FocusSession session(DateTime start, {DateTime? end, FocusStatus status = FocusStatus.completed}) =>
        FocusSession(
          id: 's-${start.millisecondsSinceEpoch}',
          start: start,
          end: end ?? start.add(const Duration(minutes: 20)),
          plannedMin: 20,
          actualFocusMin: 20,
          status: status,
          sunlightEarned: 20,
          createdAt: start,
        );

    test('空列表 → 0', () {
      expect(service.consecutiveValidSessions(const <FocusSession>[], restMinutes), 0);
    });

    test('仅 1 场 → 1', () {
      final sessions = <FocusSession>[session(DateTime(2026, 10, 8, 12, 24))];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 1);
    });

    test('两场间隔 4h（≥ restMinutes）→ 只算最近 1 场（真机场景回归）', () {
      final sessions = <FocusSession>[
        session(DateTime(2026, 10, 8, 8, 14)), // 08:14–08:34（今早测试场）
        session(DateTime(2026, 10, 8, 12, 24)), // 12:24–12:44（间隔 ~4h）
      ];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 1);
    });

    test('两场背靠背（间隔 < restMinutes）→ 2（连续）', () {
      final sessions = <FocusSession>[
        session(DateTime(2026, 10, 8, 12, 0)), // 12:00–12:20
        session(DateTime(2026, 10, 8, 12, 25)), // 12:25–12:45（间隔 5min）
      ];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 2);
    });

    test('恰好间隔 restMinutes → 断连（≥ 边界归休息）', () {
      final sessions = <FocusSession>[
        session(DateTime(2026, 10, 8, 12, 0)), // 12:00–12:20
        session(DateTime(2026, 10, 8, 12, 30)), // 12:30 起（间隔恰好 10min）
      ];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 1);
    });

    test('三场连续 → 3；未完成会话不计数', () {
      final sessions = <FocusSession>[
        session(DateTime(2026, 10, 8, 11, 0)), // 11:00–11:20
        session(DateTime(2026, 10, 8, 11, 25)), // 11:25–11:45
        session(DateTime(2026, 10, 8, 11, 50)), // 11:50–12:10
        session( // 未完成（进行中）→ 不计入
          DateTime(2026, 10, 8, 12, 15),
          status: FocusStatus.active,
        ),
      ];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 3);
    });

    test('传入乱序列表 → 内部按 start 排序后计数（防御）', () {
      final sessions = <FocusSession>[
        session(DateTime(2026, 10, 8, 12, 25)),
        session(DateTime(2026, 10, 8, 12, 0)),
      ];
      expect(service.consecutiveValidSessions(sessions, restMinutes), 2);
    });
  });
}
