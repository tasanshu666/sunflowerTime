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

  /// 是否到了需要休息的节奏：每完成 [AppSettings.restSessions] 场后需要休息
  /// （即 2/4/6… 场后触发，1/3/5… 场不触发）。
  bool restRequired(AppSettings s, int todayValidSessions) =>
      todayValidSessions > 0 && todayValidSessions % s.restAfterSessions == 0;

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
