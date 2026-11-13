/// 阳光记账与日上限 SunlightService（T10）。
///
/// 公式①（PRD §4.5）：`S = 专注分钟 × 1 + 任务数 × 12 × 完美日系数`。
///
/// **日上限口径（玄参 2026-09-23 拍板，取代原「分段软顶」）**：
///   · 专注 1 分钟 = 1 阳光，唯一约束是**年段每日专注上限**
///     （低 60 / 中 90 / 高 120 分钟，设置项 `AppSettings.dailyFocusCap`）；
///   · 有效阳光 = `min(本场专注阳光, 今日剩余额度)`，其中今日剩余额度
///     = `dailyFocusCap − 今日已入账专注阳光`；
///   · **成长奖励（成长项打卡）与家长赠予不占本额度** —— 账本 `refType` 独立
///     （`focus_session` / `task_checkin` / `parent_gift`），故额度只按
///     `focus_session` 聚合，天然互不挤占。
///
/// 为什么取消分段打薄：分段第一段本身就是「60 分钟以内全额」，因此「封顶跟随年段」
/// 与「分段打薄」不能共存；旧口径下高年段孩子专注满 120 分钟只能拿 79 阳光。
/// 详见 [effectiveFocusSunlight]。
///
/// 记账（架构 §3.2 / §4.1 时序）：单一 append-only 账本，结算时
/// `append(gross=原始, net=有效)`，`balanceAfter = 当前余额 + net`；同时保存 [FocusSession]。
///
/// ## 🔴 B13.20 专注加成券（玄参 2026-11-13 拍板）
/// 守卫掉落的两种**被动**券在本服务的结算链路生效（不走养护减免）：
///  · **专注放大券**：本场专注净额（日上限截断后）×[kGuardFocusBoostRate]；
///  · **专注加餐券**：当日累计实际专注 ≥ [kGuardFocusMealThresholdMin] 分钟
///    ⇒ 一次性 +[kGuardFocusMealSun] ☀（达成瞬间自动到账）。
/// 两者都走**独立 refType** [kGuardFocusBonusRefType] ⇒ 不占每日专注额度
/// （额度只按 `focus_session` 聚合；与「成长奖励不算在内」同一条口径）。
library sunlight_service;

import 'dart:math';

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/math_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';

/// 一次专注的结算结果（供结算页呈现）。
class FocusSettlement {
  /// 生成的专注会话 id。
  final String sessionId;

  /// 本次实际专注分钟。
  final double actualFocusMin;

  /// 原始产出 S（未受日上限约束；短期作废时为 0）。
  final double rawS;

  /// 本次实际到手阳光（日上限截断后；短期作废时为 0）。
  final double net;

  /// 记账后的账本余额。
  final double balanceAfter;

  /// 当日累计净产出（含本次）。
  final double todayNet;

  /// 本次计划专注分钟（埋点 valid_focus_day 完成率计算需要，§3.3）。
  final double plannedMin;

  /// 结算状态。
  final FocusStatus status;

  /// 结束原因。
  final FocusEndReason endReason;

  /// 🔴 B13.20：本场**专注放大券**加成（独立账目，不含在 [net] 里；0 = 未持券）。
  final double boostBonus;

  /// 🔴 B13.20：本场触发的**专注加餐券**到账（一次性 +10；0 = 未达成 / 未持券 /
  /// 今日已发过）。
  final double mealBonus;

  const FocusSettlement({
    required this.sessionId,
    required this.actualFocusMin,
    required this.rawS,
    required this.net,
    required this.balanceAfter,
    required this.todayNet,
    required this.plannedMin,
    required this.status,
    required this.endReason,
    this.boostBonus = 0.0,
    this.mealBonus = 0.0,
  });

  /// 本次是否有阳光产出。
  bool get hasOutput => net > 0;

  /// 🔴 B13.20：专注券加成合计（放大 + 加餐；供结算页浮字提示）。
  double get voucherBonusTotal => boostBonus + mealBonus;

  /// 本次是否被**今日专注额度**削过（原始 > 实得）。
  ///
  /// 取代原先「rawS 是否超过软顶第一段」的推断（那个口径随分段打薄一并作废）：
  /// 现在直接比较原始与实得，任何被额度截断的情形都能识别。
  bool get capped => net < rawS - 1e-9;
}

/// 阳光记账与日上限领域服务。
class SunlightService {
  SunlightService({
    required SunlightRepository ledger,
    required FocusRepository focus,
    Uuid? idGenerator,
    // 🔴 B13.20：守卫券服务 + childId 取值器（专注加成券用）。缺省 `null` =
    // 不启用专注券（一切旧构造点 / 老测试零改动、行为逐位不变）；
    // 生产装配（providers.dart）注入后加成自动生效。
    GuardVoucherService? guardVouchers,
    String Function()? childId,
  })  : _ledger = ledger,
        _focus = focus,
        _uuid = idGenerator ?? const Uuid(),
        _guardVouchers = guardVouchers,
        _childId = childId;

  final SunlightRepository _ledger;
  final FocusRepository _focus;
  final Uuid _uuid;

  /// 🔴 B13.20：守卫券服务（`null` = 专注加成券停用）。
  final GuardVoucherService? _guardVouchers;
  final String Function()? _childId;

  /// 专注产出的账本类型（额度只按它聚合）。
  static const String focusRefType = 'focus_session';

  /// 任务奖励的账本类型（**单独记账**，不与专注混记，否则会污染专注额度）。
  static const String focusTaskRewardRefType = 'focus_task_reward';

  /// 公式①（PRD §4.5）：`S = 专注阳光 + 任务数 × kTaskSunlight × 完美日系数`。
  ///
  /// [focusSunlight] 直接取引擎按 §4.1.5（含 10 秒回满斜坡积分）算出的
  /// [FocusOutcome.rawSunlight]，**不再从 actualFocusMin 反推**——否则每次「离席后恢复」
  /// 都会多算回满窗口的 5/60 阳光，引擎里的精确积分等于白做（P2-1 缺陷修复）。
  /// [taskCount] 默认 0 —— 任务模块在 M3，本批参数化传 0，不写死。
  double computeRawS({
    required double focusSunlight,
    int taskCount = 0,
    double perfectDayCoefficient = 1.0,
  }) {
    return focusSunlight +
        taskCount * kTaskSunlightReward * perfectDayCoefficient;
  }

  /// 今日已入账的**专注阳光**（= 今日已用掉的专注额度，分钟与阳光 1:1）。
  ///
  /// 单点真源：额度只看 `refType='focus_session'`。成长奖励 / 家长赠予是独立
  /// refType，**不占专注额度**（玄参 2026-09-23 拍板）。
  Future<double> focusEarnedToday(DateTime now) =>
      _ledger.netByRefTypeOnDay(focusRefType, dayKey(now));

  /// 今日剩余可专注阳光（= 剩余分钟，1:1），封底 0。
  ///
  /// 选时长页据此收口可选档位与自定义上限；结算内部也走同一口径。
  Future<double> focusRemainingToday(int dailyFocusCap, DateTime now) async {
    final double earned = await focusEarnedToday(now);
    return max(0.0, dailyFocusCap - earned);
  }

  /// 结算一次专注（PRD §4.1.5 / §4.5 / §6.2 / 架构 §4.1 时序）。
  ///
  /// - `actualFocusMin < kMinFocusMinutes` → 记 [FocusStatus.shortAborted]、无产出；
  /// - 否则按**今日剩余额度**截断后记账：`net = min(本场专注阳光, 剩余额度) + 任务奖励`；
  /// - 打断 / 到时 / 手动均**全额保留**已产出（§4.1.4，不砍半）；
  /// - 无论是否有产出，均保存 [FocusSession]（架构 §4.1 else 分支）；
  /// - [dailyFocusCap] 由调用方从 `AppSettings.dailyFocusCap` 传入（年段口径的
  ///   **单点收口**在设置项，本服务不另存一份）。
  Future<FocusSettlement> settle({
    required FocusOutcome outcome,
    required DateTime start,
    required DateTime end,
    required int plannedMin,
    required int dailyFocusCap,
    int taskCount = 0,
    double perfectDayCoefficient = 1.0,
  }) async {
    final String sessionId = _uuid.v4();
    final bool shortAborted = outcome.status == FocusStatus.shortAborted;
    final String day = dayKey(end);

    // 本场原始产出：专注部分（引擎按 1 分钟 = 1 阳光积分）+ 任务部分（公式①，默认 0）。
    final double focusPortion = shortAborted ? 0.0 : outcome.rawSunlight;
    final double taskPortion = shortAborted
        ? 0.0
        : taskCount * kTaskSunlightReward * perfectDayCoefficient;
    final double rawS = focusPortion + taskPortion;

    double net = 0.0;
    // 本场**截断后**的专注净额（B13.20：专注放大券的乘算基数；短退 = 0）。
    double focusNet = 0.0;
    double balanceAfter = await _ledger.balance();
    if (!shortAborted) {
      // 剩余额度在**写入本条账目之前**取，否则会把本场算进已用额度。
      final double remaining =
          await focusRemainingToday(dailyFocusCap, end);
      focusNet = effectiveFocusSunlight(
        focusSunlight: focusPortion,
        remainingAllowance: remaining,
      );
      // 任务奖励不参与截断：它是「成长奖励」，按口径不占专注额度。
      net = focusNet + taskPortion;

      if (focusPortion > 0) {
        balanceAfter += focusNet;
        await _ledger.append(SunlightEntry(
          id: _uuid.v4(),
          ts: end,
          type: SunlightType.earn,
          gross: focusPortion,
          net: focusNet, // 额度已用完时为 0，仍留痕便于对账
          balanceAfter: balanceAfter,
          refType: focusRefType,
          refId: sessionId,
          dayKey: day,
        ));
      }
      // 任务奖励**单独一条账目**：若并进上面那条，它的 net 会被算成「已用专注额度」，
      // 让下一场专注少拿阳光 —— 与「成长奖励不算在内」正相反。
      if (taskPortion > 0) {
        balanceAfter += taskPortion;
        await _ledger.append(SunlightEntry(
          id: _uuid.v4(),
          ts: end,
          type: SunlightType.earn,
          gross: taskPortion,
          net: taskPortion,
          balanceAfter: balanceAfter,
          refType: focusTaskRewardRefType,
          refId: sessionId,
          dayKey: day,
        ));
      }
    }

    await _focus.saveSession(FocusSession(
      id: sessionId,
      start: start,
      end: end,
      plannedMin: plannedMin,
      actualFocusMin: outcome.actualFocusMin,
      status: outcome.status,
      sunlightEarned: net,
      createdAt: end,
    ));

    // 🔴 B13.20：专注加成券（放在 saveSession 之后 —— 加餐券的「当日累计分钟」
    // 必须包含刚落库的这一场；放大券按截断后的净额乘算，也要求净额已定）。
    // 两条加成走独立 refType [kGuardFocusBonusRefType] ⇒ 不占每日专注额度。
    double boostBonus = 0.0;
    double mealBonus = 0.0;
    final GuardVoucherService? vouchers = _guardVouchers;
    if (!shortAborted && vouchers != null) {
      try {
        final List<GuardBuffState> buffs = await vouchers.currentBuffs(now: end);
        // ① 专注放大券：本场专注净额（日上限截断后）× 20%。被动券、当日不限场。
        final bool hasBoost = buffs.any((GuardBuffState b) =>
            GuardVoucherKind.of(b.kind) == GuardVoucherKind.focusBoost);
        if (hasBoost) {
          final double amount = focusNet * kGuardFocusBoostRate;
          final double granted = await _appendFocusBonus(
            amount: amount,
            id: 'guard_focus_boost_${_uuid.v4()}',
            day: day,
            at: end,
            refId: sessionId,
          );
          boostBonus = granted;
        }
        // ② 专注加餐券：当日累计实际专注 ≥ 15 分钟 ⇒ 一次性 +10。
        //    幂等网 = 确定性账本 id（同日同 childId 唯一）+ 券额度核销。
        final GuardBuffState? meal = buffs
            .cast<GuardBuffState?>()
            .firstWhere(
              (GuardBuffState? b) =>
                  GuardVoucherKind.of(b!.kind) == GuardVoucherKind.focusMeal,
              orElse: () => null,
            );
        if (meal != null && meal.hasRemaining) {
          final double minutesToday = await _actualFocusMinutesOfDay(day);
          if (minutesToday + 1e-9 >= kGuardFocusMealThresholdMin) {
            final String childId = _childId?.call() ?? 'unknown';
            final double granted = await _appendFocusBonus(
              amount: kGuardFocusMealSun,
              id: 'guard_focus_meal_${childId}_$day',
              day: day,
              at: end,
              refId: sessionId,
            );
            if (granted > 0) {
              // 只有账本真的写进了（含加餐幂等网放行）才核销券额度 —— 反了会
              // 「券没了、阳光没到」。
              await vouchers.recordConsumed(
                kind: GuardVoucherKind.focusMeal,
                plantId: null,
                now: end,
              );
              mealBonus = granted;
            }
          }
        }
      } catch (_) {
        // 券服务抖动：加成是「锦上添花」，专注本身已成功结算 —— 静默跳过，
        // 绝不让守卫券把专注结算打成异常（与 taskOutcome 的降级口径一致）。
      }
    }
    if (boostBonus > 0) balanceAfter += boostBonus;
    if (mealBonus > 0) balanceAfter += mealBonus;

    final double todayNet = await _ledger.dayNet(day);

    return FocusSettlement(
      sessionId: sessionId,
      actualFocusMin: outcome.actualFocusMin,
      rawS: rawS,
      net: net,
      balanceAfter: balanceAfter,
      todayNet: todayNet,
      plannedMin: plannedMin.toDouble(),
      status: outcome.status,
      endReason: outcome.endReason,
      boostBonus: boostBonus,
      mealBonus: mealBonus,
    );
  }

  /// 某自然日的**累计实际专注分钟**（加餐券达成门槛的判据；含刚落库的一场）。
  Future<double> _actualFocusMinutesOfDay(String day) async {
    final List<FocusSession> sessions = await _focus.sessionsOfDay(day);
    double total = 0.0;
    for (final FocusSession s in sessions) {
      final double m = s.actualFocusMin;
      if (m.isFinite && m > 0) total += m;
    }
    return total;
  }

  /// 写一行**专注券加成**账目（独立 refType，不占每日专注额度）。
  ///
  /// 返回实际到账额（0 = 金额非法 / 主键冲突 = 同日已发过 / 账本抖动）。
  /// 加餐券的幂等网就是这里的确定性 id：`guard_focus_meal_<childId>_<day>`
  /// 一天只可能写进一次，重复触发被 DAO 主键冲突挡下并视为「已发过」。
  Future<double> _appendFocusBonus({
    required double amount,
    required String id,
    required String day,
    required DateTime at,
    required String refId,
  }) async {
    if (amount <= 0) return 0.0;
    try {
      final double balance = await _ledger.balance();
      await _ledger.append(SunlightEntry(
        id: id,
        ts: at,
        type: SunlightType.earn,
        gross: amount,
        net: amount,
        balanceAfter: balance + amount,
        refType: kGuardFocusBonusRefType,
        refId: refId,
        dayKey: day,
      ));
      return amount;
    } catch (_) {
      // 主键冲突（加餐券同日重触发）/ 账本抖动 ⇒ 不重复发、不抛异常。
      return 0.0;
    }
  }

  /// 当日累计净产出（含全部类型；仅供展示/对账，**不是**专注额度口径）。
  Future<double> todayCumulativeNet(DateTime now) =>
      _ledger.dayNet(dayKey(now));
}
