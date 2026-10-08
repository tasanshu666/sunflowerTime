/// 防沉迷服务（T11，§6.1 不变式 / §6.3 休息节奏）。
///
/// 设计约束（与 [FocusEngine] 风格一致，架构 §3）：
/// - **纯 Dart，零 Flutter 依赖**——可被 `flutter test` 直接单测；
/// - 全部为纯函数式实例方法，可调数值一律来自 [AppSettings]（单例承载），
///   不在此处写裸字面量；
/// - 夜间边界以 [AppSettings.nightBoundaryHour/Minute] 为唯一值（§6.1 不变式）。
library anti_addiction_service;

import 'dart:math';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/app_usage_service.dart';

/// 防沉迷决策结果。
enum AntiAddictionDecision {
  allowed, // 允许开始专注
  nightLocked, // 夜间边界锁定（§6.1）
  dailyCapReached, // 当日专注已达上限（§6.1）
  restRequired, // 需要休息（§6.3）
}

/// 防沉迷服务（T11）。
///
/// 综合「夜间边界 / 每日专注上限 / 休息节奏 / App 使用时长」给出本次
/// 「开始专注」是否应被拦截以及原因。本批先落地前三者，App 使用时长埋点接入后置灰。
class AntiAddictionService {
  /// 是否处于夜间锁定（读 [AppSettings] 夜间边界唯一值，§6.1 不变式）。
  bool isNightLocked(AppSettings s, DateTime now) =>
      isNight(now, boundaryHour: s.nightBoundaryHour, boundaryMinute: s.nightBoundaryMinute);

  /// 今日剩余可专注分钟（封底 0）。
  ///
  /// **单点真源**：调用方传入的 [todayFocusMin] 必须是**今日已入账的专注阳光**
  /// （`SunlightService.focusEarnedToday`，分钟与阳光 1:1），而不是自行把当日会话
  /// 的 `actualFocusMin` 加起来 —— 后者在「本场被额度截断」时会比真实额度消耗多，
  /// 导致拦截口径与扣减口径不一致（2026-09-23 统一到账本）。
  double dailyFocusRemaining(AppSettings s, double todayFocusMin) =>
      max(0.0, s.dailyFocusCap - todayFocusMin);

  /// 是否到了需要休息的节奏：每**连续**完成 [AppSettings.restAfterSessions] 场后需要
  /// 休息（即连续 2/4/6… 场后触发，1/3/5… 场不触发）。
  ///
  /// [todayValidSessions] 必须传 [consecutiveValidSessions] 的结果（**连续场数**，
  /// 而非当日累计场数）——2026-10-08 真机实证：早上 08:34 与中午 12:44 各一场
  /// （间隔 4h），旧口径按当日累计 2 场立刻触发休息，但间隔早已是充分休息，
  /// 孩子体感是「我只专注了一场就被要求休息」。连续口径下两场间隔 ≥
  /// [AppSettings.restMinutes] 即断连重置。
  bool restRequired(AppSettings s, int todayValidSessions) =>
      todayValidSessions > 0 && todayValidSessions % s.restAfterSessions == 0;

  /// 今日**连续**完成场数（休息节奏的计数口径，2026-10-08 修订）。
  ///
  /// 从最近一场往前数，只要相邻两场之间的自然间隔 ≥ [restMinutes]（两场之间
  /// 已经眼睛离开屏幕休息过了），就停止累计——休息的本质是离开屏幕（F66 同源），
  /// 中间歇够 [restMinutes] 等价于完成了一次休息义务，连续计数清零重新起算。
  ///
  /// [sessions] 为当日会话（调用方已按日过滤），内部再按开始时间排序防御。
  int consecutiveValidSessions(
    Iterable<FocusSession> sessions,
    int restMinutes,
  ) {
    final List<FocusSession> done = sessions
        .where((FocusSession s) => s.status == FocusStatus.completed)
        .toList()
      ..sort((FocusSession a, FocusSession b) => a.start.compareTo(b.start));
    if (done.isEmpty) return 0;
    int count = 1; // 最近一场必计入
    final Duration gapLimit = Duration(minutes: restMinutes);
    for (int i = done.length - 1; i > 0; i--) {
      final DateTime? prevEnd = done[i - 1].end; // 进行中/异常会话无 end → 断连
      if (prevEnd == null) break;
      final DateTime curStart = done[i].start;
      if (curStart.difference(prevEnd) >= gapLimit) break; // 中间歇够了 → 断连
      count++;
    }
    return count;
  }

  /// 今日最后一场完成会话的结束时间（F66：休息义务的起始基准）。
  ///
  /// 「每 2 场休 10 分钟」触发时，义务从**触发场结算完成那一刻**就开始算——
  /// 孩子锁屏离开、去喝水玩耍，全是真实休息。此前只在休息页开着且 App 前台时
  /// 才计时，导致「离开 20 分钟回来仍被要求重新休息 10 分钟」（真机 2026-10-03）。
  DateTime? lastCompletedSessionEnd(Iterable<FocusSession> sessions) {
    DateTime? last;
    for (final FocusSession s in sessions) {
      final DateTime? e = s.end;
      if (s.status == FocusStatus.completed && e != null) {
        if (last == null || e.isAfter(last)) last = e;
      }
    }
    return last;
  }

  /// 休息义务是否已自然满足（F66）：最后一场完成至今已过 [restMinutes]。
  ///
  /// 休息的本质是**眼睛离开屏幕**——待在休息页、锁屏、切走都算。墙上时钟
  /// 推导天然幂等，杀进程也不丢（不再依赖内存 restSatisfied 标记）。
  /// [lastSessionEnd] 为 null（无完成会话/数据异常）时不放行，返回 false。
  bool restNaturallySatisfied({
    required int restMinutes,
    required DateTime now,
    required DateTime? lastSessionEnd,
  }) =>
      lastSessionEnd != null &&
      now.difference(lastSessionEnd) >= Duration(minutes: restMinutes);

  /// 休息页剩余等待时长（F66）。基准 = [lastSessionEnd]；
  /// null（数据异常）时回退完整 [restMinutes]（安全侧，维持旧行为）。
  Duration restRemaining({
    required int restMinutes,
    required DateTime now,
    required DateTime? lastSessionEnd,
  }) {
    if (lastSessionEnd == null) return Duration(minutes: restMinutes);
    final Duration required = Duration(minutes: restMinutes);
    final Duration elapsed = now.difference(lastSessionEnd);
    return elapsed >= required ? Duration.zero : required - elapsed;
  }

  /// App 总使用时长是否达上限（仅用于娱乐页准入；**绝不**参与 evaluate 的专注准入）。
  ///
  /// 语义与 [evaluate] 相反：本方法**放行专注、拦娱乐页**，故刻意做成独立方法，
  /// 不并入 [AntiAddictionDecision] 枚举 —— 若塞进同一枚举，极易被误接进
  /// 「开始专注」链路（`entry_page` 的 evaluate switch）而把专注也挡掉。
  ///
  /// ⚠️ **本方法只是防沉迷语义门面，算法实现在 [AppUsageService.isCapReached]**（唯一判定
  /// 入口）；此处**不得**再写第二份 `appUsageSeconds >= cap*60` 比较（防「判定孪生」）。
  bool isAppCapReached(AppSettings s, int appUsageSeconds) =>
      AppUsageService.isCapReached(
        capMinutes: s.dailyAppCapMinutes,
        secondsToday: appUsageSeconds,
      );

  /// 综合评估本次「开始专注」的拦截决策。
  ///
  /// 优先级（高 → 低）：夜间锁定 > 每日上限 > 休息要求 > 允许。
  ///
  /// ⚠️ 本方法只判「**现在能不能开始**」，**不保证本场不会超出剩余额度**。
  /// 「这一场选了多久、会不会超」由调用方（选时长页）用 [dailyFocusRemaining]
  /// 收口档位，并由 `SunlightService.settle` 在结算时硬截断（2026-09-23 P0 修复：
  /// 此前仅在此处拦「已达上限」，孩子选一场 180 分钟即可一次冲过上限）。
  ///
  /// 注：[appUsageMinutes] 保留供调用方传入，但**本方法不消费它**。App 总使用时长的
  /// 准入判定走**独立方法** [isAppCapReached]（仅拦娱乐页、放行专注）——二者语义
  /// 相反（一个拦专注、一个放专注），刻意不并入本方法的决策枚举。
  AntiAddictionDecision evaluate({
    required AppSettings s,
    required DateTime now,
    required double todayFocusMin,
    required int todayValidSessions,
    bool restSatisfied = false,
    double appUsageMinutes = 0.0,
  }) {
    if (isNightLocked(s, now)) return AntiAddictionDecision.nightLocked;
    if (todayFocusMin >= s.dailyFocusCap) return AntiAddictionDecision.dailyCapReached;
    if (restRequired(s, todayValidSessions) && !restSatisfied) {
      return AntiAddictionDecision.restRequired;
    }
    return AntiAddictionDecision.allowed;
  }
}
