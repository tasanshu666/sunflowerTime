/// App 使用时长纯函数单测（P0 · A，§6 测试要点）。
///
/// 锁 4 件事（对齐 MEMORY「时间推进类逻辑」硬规则）：
///  ① **幂等**：同一 now 调两次 → 第二次增量 0（不得翻倍）；now 递增 → 增量 = 真实时间差；
///  ② **跨天归零**：只计「now 所在自然日 0 点以后」的部分；
///  ③ **时钟回拨**：增量记 0，但仍推进基准（不卡死、不负增长）；
///  ④ [AppUsageService.isCapReached] 边界守卫用 `>=`。
///
/// 纯 Dart（`package:test`），不依赖 Flutter 引擎。
library;

import 'package:sunflower_time/domain/services/app_usage_service.dart';
import 'package:test/test.dart';

void main() {
  group('AppUsageService.advance · 幂等 / 跨天 / 时钟回拨', () {
    test('同一 now 调两次 → 第二次增量 0（不得翻倍）', () {
      final DateTime now = DateTime(2026, 9, 23, 10, 0, 0);
      final AppUsageTick t1 = AppUsageService.advance(
        storedDate: '2026-09-23',
        storedSeconds: 100,
        baseAt: now.subtract(const Duration(minutes: 5)),
        now: now,
      );
      expect(t1.seconds, 100 + 300); // 累加 5 分钟
      expect(t1.baseAt, now);
      expect(t1.date, '2026-09-23');

      final AppUsageTick t2 = AppUsageService.advance(
        storedDate: t1.date,
        storedSeconds: t1.seconds,
        baseAt: t1.baseAt,
        now: now, // 同一个 now
      );
      expect(t2.seconds, t1.seconds); // 增量 0，绝不翻倍
      expect(t2.baseAt, now);
    });

    test('now 递增 → 第二次增量 = 两次 now 的真实时间差（不得翻倍）', () {
      final DateTime now1 = DateTime(2026, 9, 23, 10, 0, 0);
      final DateTime now2 = now1.add(const Duration(seconds: 5));

      final AppUsageTick t1 = AppUsageService.advance(
        storedDate: '2026-09-23',
        storedSeconds: 0,
        baseAt: now1,
        now: now1,
      );
      expect(t1.seconds, 0);

      final AppUsageTick t2 = AppUsageService.advance(
        storedDate: t1.date,
        storedSeconds: t1.seconds,
        baseAt: t1.baseAt,
        now: now2,
      );
      expect(t2.seconds, 5); // 恰好 5 秒，不是 10
      expect(t2.baseAt, now2);
    });

    test('跨天归零：只计「today 0 点以后」的部分（丢弃昨日残段）', () {
      final DateTime baseAt = DateTime(2026, 9, 22, 23, 59, 0);
      final DateTime now = DateTime(2026, 9, 23, 0, 5, 0);
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-22',
        storedSeconds: 9999, // 昨日累计应被丢弃
        baseAt: baseAt,
        now: now,
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 300); // 只计 00:00 → 00:05
      expect(t.baseAt, now);
    });

    test('跨天且基准也落在今日 → 计 now - baseAt', () {
      final DateTime baseAt = DateTime(2026, 9, 23, 0, 2, 0);
      final DateTime now = DateTime(2026, 9, 23, 0, 7, 0);
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-22',
        storedSeconds: 500,
        baseAt: baseAt,
        now: now,
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 300); // now - baseAt = 5 分钟
      expect(t.baseAt, now);
    });

    test('时钟回拨（now < baseAt）→ 增量 0，但仍把基准推进到 now', () {
      final DateTime baseAt = DateTime(2026, 9, 23, 10, 5, 0);
      final DateTime now = DateTime(2026, 9, 23, 10, 0, 0);
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-23',
        storedSeconds: 100,
        baseAt: baseAt,
        now: now,
      );
      expect(t.seconds, 100); // 不减少、不负增长
      expect(t.baseAt, now); // 基准仍推进（避免卡死在同一 now）
    });

    test('storedSeconds 为负 → StateError（参数校验，release 不会剥离）', () {
      expect(
        () => AppUsageService.advance(
          storedDate: '2026-09-23',
          storedSeconds: -1,
          baseAt: DateTime(2026, 9, 23, 9),
          now: DateTime(2026, 9, 23, 10),
        ),
        throwsStateError,
      );
    });
  });

  group('AppUsageService.isCapReached · 边界（守卫 >=）', () {
    test('cap=30：1799→false / 1800→true / 1801→true', () {
      expect(
        AppUsageService.isCapReached(capMinutes: 30, secondsToday: 1799),
        isFalse,
      );
      expect(
        AppUsageService.isCapReached(capMinutes: 30, secondsToday: 1800),
        isTrue,
      );
      expect(
        AppUsageService.isCapReached(capMinutes: 30, secondsToday: 1801),
        isTrue,
      );
    });

    test('cap=20：1199→false / 1200→true', () {
      expect(
        AppUsageService.isCapReached(capMinutes: 20, secondsToday: 1199),
        isFalse,
      );
      expect(
        AppUsageService.isCapReached(capMinutes: 20, secondsToday: 1200),
        isTrue,
      );
    });

    test('cap=45（家长档位上界）：2699→false / 2700→true', () {
      expect(
        AppUsageService.isCapReached(capMinutes: 45, secondsToday: 2699),
        isFalse,
      );
      expect(
        AppUsageService.isCapReached(capMinutes: 45, secondsToday: 2700),
        isTrue,
      );
    });
  });

  // ── QA 独立补强：跨天 / 时钟回拨 / 末日残段 的边界正确性 ──────────────
  group('AppUsageService.advance · 边界补强（QA 独立设计）', () {
    test('跨天且 baseAt 早于「今日 0 点」（前天）→ from 取今日 0 点，只计今日', () {
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-21',
        storedSeconds: 500,
        baseAt: DateTime(2026, 9, 20, 8, 0, 0), // 早于今日（09-23）
        now: DateTime(2026, 9, 23, 0, 10, 0),
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 600); // 只计 00:00 → 00:10
      expect(t.baseAt, DateTime(2026, 9, 23, 0, 10, 0));
    });

    test('跨天 + 时钟回拨（baseAt 落在今日未来）→ 增量 0，绝不出现负数', () {
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-22',
        storedSeconds: 100,
        baseAt: DateTime(2026, 9, 23, 10, 0, 0), // 今日未来
        now: DateTime(2026, 9, 23, 9, 0, 0),
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 0);
      expect(t.baseAt, DateTime(2026, 9, 23, 9, 0, 0));
    });

    test('now 恰为今日 00:00:00（baseAt 昨日 23:00）→ 今日秒数 0，不超额', () {
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-22',
        storedSeconds: 800,
        baseAt: DateTime(2026, 9, 22, 23, 0, 0),
        now: DateTime(2026, 9, 23, 0, 0, 0),
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 0);
    });

    test('昨日已近上限 + 跨过午夜 30 秒 → 今日只记 30 秒（绝不带残段）', () {
      final AppUsageTick t = AppUsageService.advance(
        storedDate: '2026-09-22',
        storedSeconds: 1799, // 昨日累计（昨日口径，与今日无关）
        baseAt: DateTime(2026, 9, 22, 23, 59, 30),
        now: DateTime(2026, 9, 23, 0, 0, 30),
      );
      expect(t.date, '2026-09-23');
      expect(t.seconds, 30); // 只计今日 30 秒，而非 1799 + 30
    });
  });
}
