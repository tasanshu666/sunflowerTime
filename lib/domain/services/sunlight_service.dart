/// 阳光记账与软顶 SunlightService（T10）。
///
/// 公式①（PRD §4.5）：`S = 专注分钟 × 1 + 任务数 × 12 × 完美日系数`。
/// 软顶**直接复用** `core/utils/math_ext.dart` 的 [computeSoftCap]（分段，日上限 79），
/// 不在此重复实现。
/// 记账（架构 §3.2 / §4.1 时序）：单一 append-only 账本，结算时
/// `append(gross=S, net=有效)`，`balanceAfter = 当前余额 + net`；同时保存 [FocusSession]。
library sunlight_service;

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/math_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';

/// 一次专注的结算结果（供结算页呈现）。
class FocusSettlement {
  /// 生成的专注会话 id。
  final String sessionId;

  /// 本次实际专注分钟。
  final double actualFocusMin;

  /// 原始产出 S（未过软顶；短期作废时为 0）。
  final double rawS;

  /// 本次实际到手阳光（软顶后；短期作废时为 0）。
  final double net;

  /// 记账后的账本余额。
  final double balanceAfter;

  /// 当日累计净产出（含本次）。
  final double todayNet;

  /// 结算状态。
  final FocusStatus status;

  /// 结束原因。
  final FocusEndReason endReason;

  const FocusSettlement({
    required this.sessionId,
    required this.actualFocusMin,
    required this.rawS,
    required this.net,
    required this.balanceAfter,
    required this.todayNet,
    required this.status,
    required this.endReason,
  });

  /// 本次是否有阳光产出。
  bool get hasOutput => net > 0;
}

/// 阳光记账与软顶领域服务。
class SunlightService {
  SunlightService({
    required SunlightRepository ledger,
    required FocusRepository focus,
    Uuid? idGenerator,
  })  : _ledger = ledger,
        _focus = focus,
        _uuid = idGenerator ?? const Uuid();

  final SunlightRepository _ledger;
  final FocusRepository _focus;
  final Uuid _uuid;

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

  /// 有效阳光（软顶，PRD §4.5 分段公式；复用 [computeSoftCap]）。
  double computeEffective(double rawS) => computeSoftCap(rawS);

  /// 结算一次专注（PRD §4.1.5 / §4.5 / §6.2 / 架构 §4.1 时序）。
  ///
  /// - `actualFocusMin < kMinFocusMinutes` → 记 [FocusStatus.shortAborted]、无产出；
  /// - 否则按软顶记账 `append(gross=rawS, net=有效)` 并更新余额；
  /// - 打断 / 到时 / 手动均**全额保留**已产出（§4.1.4，不砍半）；
  /// - 无论是否有产出，均保存 [FocusSession]（架构 §4.1 else 分支）。
  Future<FocusSettlement> settle({
    required FocusOutcome outcome,
    required DateTime start,
    required DateTime end,
    required int plannedMin,
    int taskCount = 0,
    double perfectDayCoefficient = 1.0,
  }) async {
    final String sessionId = _uuid.v4();
    final bool shortAborted = outcome.status == FocusStatus.shortAborted;

    final double rawS = shortAborted
        ? 0.0
        : computeRawS(
            focusSunlight: outcome.rawSunlight,
            taskCount: taskCount,
            perfectDayCoefficient: perfectDayCoefficient,
          );

    double net = 0.0;
    double balanceAfter = await _ledger.balance();
    if (!shortAborted) {
      net = computeEffective(rawS);
      balanceAfter = balanceAfter + net;
      await _ledger.append(SunlightEntry(
        id: _uuid.v4(),
        ts: end,
        type: SunlightType.earn,
        gross: rawS,
        net: net,
        balanceAfter: balanceAfter,
        refType: 'focus_session',
        refId: sessionId,
        dayKey: dayKey(end),
      ));
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

    final double todayNet = await _ledger.dayNet(dayKey(end));

    return FocusSettlement(
      sessionId: sessionId,
      actualFocusMin: outcome.actualFocusMin,
      rawS: rawS,
      net: net,
      balanceAfter: balanceAfter,
      todayNet: todayNet,
      status: outcome.status,
      endReason: outcome.endReason,
    );
  }

  /// 当日累计净产出（软顶校验用，§3.2）。
  Future<double> todayCumulativeNet(DateTime now) =>
      _ledger.dayNet(dayKey(now));
}
