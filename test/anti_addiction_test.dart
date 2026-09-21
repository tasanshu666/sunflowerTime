/// 防沉迷服务单测（T11，§6.1 / §6.3）。
///
/// 覆盖：夜间边界、每日上限、综合决策优先级、休息节奏。
library anti_addiction_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
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
}
