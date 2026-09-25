/// App 总使用时长计时纯函数（P0 · A，§6.1）。
///
/// 设计纪律（与 `FocusEngine` / `PresenceDetector` 一致）：
/// - **纯 Dart，零 Flutter 依赖** —— 仅 import `dart:core` 与本项目的纯 dart 工具
///   （[datetime_ext]），可被 `package:test` 直接单测；
/// - **无状态、无单例**：所有状态由调用方传入并回传，是「记录基准 + 差值」的幂等纯函数。
library app_usage_service;

import 'package:sunflower_time/core/utils/datetime_ext.dart';

/// 一次结算的返回。
///
/// 不变量：[baseAt] **恒等于**本次调用传入的 `now`（每次结算**无条件**推进基准）——
/// 这是「刷新越多次涨越快」这类重复累加缺陷的根本对策
/// （见 MEMORY「时间推进类逻辑」硬规则与 `_advanceGrowth` 事故）。
class AppUsageTick {
  /// 累计所属自然日 key（yyyy-MM-dd）。
  final String date;

  /// 该日累计秒（封底 0）。
  final int seconds;

  /// 已推进到 `now` 的结算基准时刻。
  final DateTime baseAt;

  const AppUsageTick({
    required this.date,
    required this.seconds,
    required this.baseAt,
  });
}

/// App 使用时长计时（纯函数式，flutter-free）。
class AppUsageService {
  /// 纯静态命名空间，禁止实例化。
  AppUsageService._();

  /// 把 `[baseAt, now]` 区间内**属于「now 所在自然日」**的秒数累加到 [storedSeconds]。
  ///
  /// 幂等性（核心保证）：
  /// - 返回值 [AppUsageTick.baseAt] **恒等于 [now]**（每次结算无条件推进基准）；
  /// - 同一 [now] 调两次 → 第二次增量 = 0（**不得翻倍**）；
  /// - [now] 递增 → 增量 = 两次 [now] 的真实时间差。
  ///
  /// 跨天：`dayKey(now) != storedDate` → **归零重算**，只计 `[max(baseAt, 当日0点), now]`
  /// 的秒数（丢弃午夜前的残段，**绝不超额**）。
  ///
  /// 时钟回拨（`now < baseAt`）→ 增量记 0，**仍把基准推进到 [now]**（避免负增长或卡死）。
  ///
  /// 参数校验：累计秒数不允许为负，否则抛 [StateError]（release 会剥离 assert，
  /// 故用 [StateError] 而非 assert 做防御）。
  static AppUsageTick advance({
    required String storedDate,
    required int storedSeconds,
    required DateTime baseAt,
    required DateTime now,
  }) {
    if (storedSeconds < 0) {
      throw StateError('AppUsageService.advance: storedSeconds 不允许为负（$storedSeconds）');
    }

    final String todayKey = dayKey(now);

    if (storedDate != todayKey) {
      // 跨天：归零重算，只计「now 所在自然日的 0 点以后」的部分。
      final DateTime dayStart = DateTime(now.year, now.month, now.day);
      final DateTime from = baseAt.isAfter(dayStart) ? baseAt : dayStart;
      final int seconds = now.difference(from).inSeconds;
      return AppUsageTick(
        date: todayKey,
        seconds: seconds > 0 ? seconds : 0,
        baseAt: now,
      );
    }

    // 同日：累加 [baseAt, now]；时钟回拨（now < baseAt）→ 增量 0，但仍推进基准。
    final int delta = now.difference(baseAt).inSeconds;
    final int total = storedSeconds + (delta > 0 ? delta : 0);
    return AppUsageTick(
      date: todayKey,
      seconds: total > 0 ? total : 0,
      baseAt: now,
    );
  }

  /// App 时长是否已达当日上限（§6.1）——**唯一判定入口**，禁止在他处另写比较。
  ///
  /// ⚠️ 全仓 `seconds >= capMinutes * 60` 的比较**只允许存在这一处**：
  ///   · `AppUsageController` 的 hydrate / settle 均调用本方法判定 `reached`；
  ///   · `AntiAddictionService.isAppCapReached` 仅作**一行委托**（防沉迷语义门面）。
  /// 纯判定，**不参与**「开始专注」。
  ///
  /// 边界（守卫用 `>=`）：`capMinutes = 30` 时 `1799 秒 → false`、`1800 秒 → true`。
  static bool isCapReached({
    required int capMinutes,
    required int secondsToday,
  }) =>
      secondsToday >= capMinutes * 60;
}
