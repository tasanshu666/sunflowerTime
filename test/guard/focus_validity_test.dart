/// 「有效专注」单一真源的验收测试（决策 D5）。
///
/// ## 为什么这些断言必须写死数字
/// 🔴 期望值一律写成**字面量**（15 / 0.90），**不许**从实现里引 `kValidFocusMinutes`
/// 反推。若测试跟着实现引用同一个常量，那么「有人把 15 改成 10」时测试也一起变绿 ——
/// 这条测试就等于没写。
library focus_validity_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/services/focus_validity.dart';

/// 造一个会话（`status` 只影响展示，判定只看时长与完成率）。
FocusSession _session({
  required int plannedMin,
  required double actualFocusMin,
  FocusStatus status = FocusStatus.completed,
}) {
  return FocusSession(
    id: 's-$plannedMin-$actualFocusMin',
    start: DateTime(2026, 11, 8, 9, 0),
    end: DateTime(2026, 11, 8, 9, 30),
    plannedMin: plannedMin,
    actualFocusMin: actualFocusMin,
    status: status,
    sunlightEarned: 0,
    createdAt: DateTime(2026, 11, 8, 9, 0),
  );
}

void main() {
  group('D5 自由专注（plannedMin == 0）只看时长', () {
    test('实际 14 分钟 → 无效（差 1 分钟）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 0, actualFocusMin: 14)),
        isFalse,
      );
    });

    test('实际 15 分钟 → 有效（恰好门槛，含等号）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 0, actualFocusMin: 15)),
        isTrue,
      );
    });

    test('实际 90 分钟 → 有效（自由专注没有「完成率」概念）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 0, actualFocusMin: 90)),
        isTrue,
      );
    });
  });

  group('有计划时长：时长 + 完成率双门槛', () {
    test('25 分钟计划 · 实际 23 分钟（92%）→ 有效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 25, actualFocusMin: 23)),
        isTrue,
      );
    });

    test('25 分钟计划 · 实际 20 分钟（80%）→ 无效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 25, actualFocusMin: 20)),
        isFalse,
      );
    });

    test('25 分钟计划 · 实际 25 分钟（100%）→ 有效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 25, actualFocusMin: 25)),
        isTrue,
      );
    });

    test('25 分钟计划 · 实际 14 分钟（56%）→ 无效（时长先挡）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 25, actualFocusMin: 14)),
        isFalse,
      );
    });

    test(
        '时长够但完成率不够 → 无效（15 分钟计划 · 实际 20 分钟不可能更差，'
        '故用 60 分钟计划 · 实际 40 分钟 = 66.7%）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 60, actualFocusMin: 40)),
        isFalse,
      );
    });
  });

  group('边界：恰好 15 分钟 / 恰好 90%', () {
    test('恰好 15 分钟（计划 15）→ 有效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 15, actualFocusMin: 15)),
        isTrue,
      );
    });

    test('恰好 15 分钟（计划 16，完成率 93.75%）→ 有效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 16, actualFocusMin: 15)),
        isTrue,
      );
    });

    test('14.9 分钟 → 无效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 0, actualFocusMin: 14.9)),
        isFalse,
      );
    });

    test('恰好 90%（计划 20 · 实际 18）→ 有效（含等号）', () {
      expect(
        isValidFocusSession(_session(plannedMin: 20, actualFocusMin: 18)),
        isTrue,
      );
    });

    test('89%（计划 100 · 实际 89）→ 无效', () {
      expect(
        isValidFocusSession(_session(plannedMin: 100, actualFocusMin: 89)),
        isFalse,
      );
    });
  });

  group('shortAborted 不靠枚举挡，靠时长挡', () {
    test('3 分钟就放弃 → 无效', () {
      expect(
        isValidFocusSession(
          _session(
            plannedMin: 25,
            actualFocusMin: 3,
            status: FocusStatus.shortAborted,
          ),
        ),
        isFalse,
      );
    });
  });

  group('validFocusSessionsOf：能量口径的原料', () {
    test('5 次 3 分钟放弃 × 5 → 有效 0 次（防刷能量）', () {
      final List<FocusSession> sessions = <FocusSession>[
        for (int i = 0; i < 5; i++)
          _session(
            plannedMin: 25,
            actualFocusMin: 3,
            status: FocusStatus.shortAborted,
          ),
      ];
      expect(validFocusSessionsOf(sessions), isEmpty);
    });

    test('15 分钟 / 完成率 95% 的会话 × 1 → 有效 1 次', () {
      expect(
        validFocusSessionsOf(<FocusSession>[
          _session(plannedMin: 20, actualFocusMin: 19),
        ]),
        hasLength(1),
      );
    });

    test('混合 3 条 → 只保留有效的 2 条，顺序不变', () {
      final FocusSession a = _session(plannedMin: 25, actualFocusMin: 25);
      final FocusSession b = _session(plannedMin: 25, actualFocusMin: 5);
      final FocusSession c = _session(plannedMin: 0, actualFocusMin: 40);
      final List<FocusSession> kept =
          validFocusSessionsOf(<FocusSession>[a, b, c]);
      expect(kept, hasLength(2));
      expect(kept[0].id, a.id);
      expect(kept[1].id, c.id);
    });
  });
}
