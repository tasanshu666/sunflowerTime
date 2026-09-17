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
import 'package:sunflower_time/domain/entities/settings.dart';

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
  double dailyFocusRemaining(AppSettings s, double todayFocusMin) =>
      max(0.0, s.dailyFocusCap - todayFocusMin);

  /// 是否到了需要休息的节奏：每完成 [AppSettings.restAfterSessions] 场后需要休息
  /// （即 2/4/6… 场后触发，1/3/5… 场不触发）。
  bool restRequired(AppSettings s, int todayValidSessions) =>
      todayValidSessions > 0 && todayValidSessions % s.restAfterSessions == 0;

  /// 综合评估本次「开始专注」的拦截决策。
  ///
  /// 优先级（高 → 低）：夜间锁定 > 每日上限 > 休息要求 > 允许。
  AntiAddictionDecision evaluate({
    required AppSettings s,
    required DateTime now,
    required double todayFocusMin,
    required int todayValidSessions,
    bool restSatisfied = false,
    double appUsageMinutes = 0.0,
  }) {
    // TODO(M2/埋点): 接入 App 使用时长埋点后，appUsageMinutes >= s.dailyAppCapMinutes 时应返回 appCapReached
    if (isNightLocked(s, now)) return AntiAddictionDecision.nightLocked;
    if (todayFocusMin >= s.dailyFocusCap) return AntiAddictionDecision.dailyCapReached;
    if (restRequired(s, todayValidSessions) && !restSatisfied) {
      return AntiAddictionDecision.restRequired;
    }
    return AntiAddictionDecision.allowed;
  }
}
