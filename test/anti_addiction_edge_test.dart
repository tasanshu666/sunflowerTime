/// 防沉迷边界补充测试（T11 独立 QA 自测，覆盖原 22 例未覆盖的关键边界）。
///
/// 重点：
/// - `evaluate` 每日上限的 `>=` 方向（59 放行 / 60 触顶 / 61 触顶）；
/// - 休息节奏对 `restAfterSessions != 2` 的泛化（改为 3 场时的 3/6/9 触发）；
/// - 休息环路 state 流转：2 场→restRequired→休息放行→下次偶数场再次 restRequired。
library anti_addiction_edge_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';

AppSettings _settings({int restAfterSessions = 2, int dailyFocusCap = 60}) =>
    AppSettings(
      ageTier: AgeTier.high,
      dailyFocusCap: dailyFocusCap,
      dailyAppCapMinutes: 30,
      restAfterSessions: restAfterSessions,
      restMinutes: 10,
      taskSunlight: 12,
      monthlyPoolBudget: 400,
    );

void main() {
  final service = AntiAddictionService();

  group('evaluate 每日上限边界方向（守护 >= 而非 >）', () {
    final s = _settings();

    test('todayFocusMin=59 且 cap=60 → allowed（刚好未触顶）', () {
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 59,
          todayValidSessions: 0,
        ),
        AntiAddictionDecision.allowed,
      );
    });

    test('todayFocusMin=61 且 cap=60 → dailyCapReached（越界）', () {
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 61,
          todayValidSessions: 0,
        ),
        AntiAddictionDecision.dailyCapReached,
      );
    });
  });

  group('restRequired 节奏泛化（restAfterSessions=3）', () {
    final s = _settings(restAfterSessions: 3);

    test('sessions 1,2 → false', () {
      expect(service.restRequired(s, 1), isFalse);
      expect(service.restRequired(s, 2), isFalse);
    });
    test('sessions 3 → true（首次应休息）', () {
      expect(service.restRequired(s, 3), isTrue);
    });
    test('sessions 4,5 → false', () {
      expect(service.restRequired(s, 4), isFalse);
      expect(service.restRequired(s, 5), isFalse);
    });
    test('sessions 6 → true（第二次应休息）', () {
      expect(service.restRequired(s, 6), isTrue);
    });
  });

  group('休息环路 state 流转（证明不会无限跳 /rest）', () {
    final s = _settings(); // restAfterSessions=2

    test('完整环路：2 场触发→休息放行→3 场免休→4 场再触发', () {
      // 第 2 场完成后未休息：restSatisfied=false → 必须休息
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 0,
          todayValidSessions: 2,
          restSatisfied: false,
        ),
        AntiAddictionDecision.restRequired,
      );

      // 用户休息完（restSatisfied=true）→ 放行，且入口页会在启动时清零
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 0,
          todayValidSessions: 2,
          restSatisfied: true,
        ),
        AntiAddictionDecision.allowed,
      );

      // 第 3 场完成（todayValidSessions=3），restSatisfied 已清零=false → 3%2!=0 免休
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 0,
          todayValidSessions: 3,
          restSatisfied: false,
        ),
        AntiAddictionDecision.allowed,
      );

      // 第 4 场完成（todayValidSessions=4），restSatisfied=false → 再次要求休息
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 20, 0),
          todayFocusMin: 0,
          todayValidSessions: 4,
          restSatisfied: false,
        ),
        AntiAddictionDecision.restRequired,
      );
    });

    test('休息后仍被夜间边界压制：restSatisfied=true 但 21:00 → nightLocked', () {
      expect(
        service.evaluate(
          s: s,
          now: DateTime(2026, 9, 15, 21, 0),
          todayFocusMin: 0,
          todayValidSessions: 2,
          restSatisfied: true,
        ),
        AntiAddictionDecision.nightLocked,
      );
    });
  });
}
