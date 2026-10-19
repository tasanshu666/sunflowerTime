/// 周阳光池服务（§2.4 / §3.2 / §4.1）。
///
/// 职责：取/建/重置当周奖励预算池（每周一 0 点）。
/// 🔴 C90-C：原 C5 免确认上限计算（`autoApproveCap` / `capFor`）已随自动放行
/// 功能删除；`budget <= kWeeklyPoolBudgetUnlimited`（0）= 高年级默认不限额，
/// 兑换只受阳光余额约束（判定单点在 `RedemptionService.decide`）。
/// 不落任何阳光账本（账本归 [SunlightRepository]），只维护 `weekly_pool` 的独立对账。
///
/// 设计纪律（§7.4）：queued 状态**绝不**由本服务扣账本/扣池；扣减只发生在
/// [RedemptionOrchestrationService] 的 verify / releaseQueue 路径。
library weekly_pool_service;

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

/// 周奖励预算池服务。
///
/// 构造注入三个仓储 + **可选** [AccountService]（C90-C 同日二次修订接线）：
/// 周池仓储、设置仓储（旧路径档位回退）、埋点仓储（跨周重置时落
/// `weekly_pool_reset` 事件）。与 `RedemptionOrchestrationService` 的 `account`
/// 同款可选注入口径——无参构造 = 旧路径（档位回退全局 settings 单行），存量
/// 调用方 / 测试零改动；DI 注入后预算按**当前孩子年级默认值**派生。
class WeeklyPoolService {
  final WeeklyPoolRepository _repo;
  final SettingsRepository _settings;
  final TrackingRepository _tracking;
  final AccountService? _account;
  final Uuid _uuid = Uuid();

  WeeklyPoolService(
    this._repo,
    this._settings,
    this._tracking, {
    AccountService? account,
  }) : _account = account;

  /// 周池预算**单点判定**（C90-C 同日二次修订接线）。
  ///
  /// 🔴 `settings.poolBudget` 自本修订起**退出消费链**（实体字段 / DB 列保留
  /// 兼容存量库，见 `AppSettings.poolBudget` 废弃注释），实际预算一律由当前
  /// 孩子年级默认值派生：
  ///  · 已注入 [AccountService] → `currentAgeTier()`（年龄段跟孩子走，玄参拍板）；
  ///  · 未注入（旧路径 / 存量测试）→ 回退全局 settings 单行 `ageTier`；
  ///  · 预算 = `kAgeTierParams[tier].poolBudgetDefault`
  ///    （低 300 / 中 600 / 高 [kWeeklyPoolBudgetUnlimited] = 0 不限额哨兵）。
  Future<int> _budgetForCurrentTier() async {
    final AgeTier tier = await _account?.currentAgeTier() ??
        (await _settings.getSettings()).ageTier;
    // Map 查表按静态类型可空（三档枚举全覆盖，`!` 安全）；同文件内多处取
    // poolBudgetDefault 的既有口径（age_tier_params_test 等）一致。
    return kAgeTierParams[tier]!.poolBudgetDefault;
  }

  /// 取/建当周池：若已存在直接返回（**C91：预算即时派生视图**，见下）；否则按
  /// 当前孩子年级默认预算新建并落重置埋点（预算判定单点 [_budgetForCurrentTier]；
  /// `tier` 埋点键维持全局 settings 口径 —— 既有裁定，勿改）。
  ///
  /// 🔴 **C91 修订（玄参平板真机反馈：高年级存量行仍带修复前的预算 400）**：
  /// 预算**彻底即时派生** —— 已存在的池行返回「预算 = [_budgetForCurrentTier()]
  /// 现算值」的视图副本，**不再读池行的 budget 列**（列保留标废弃，无迁移）；
  /// 行只承担 used / autoReleased 记账。效果：高年级立即显示「不限」、低/中立即
  /// 300/600，历史行旧预算自然作废。
  Future<WeeklyPool> ensureAndReset(DateTime now) async {
    final int budget = await _budgetForCurrentTier();
    final String key = weekKey(now);
    final WeeklyPool? existing = await _repo.get(key);
    if (existing != null) {
      return _derivedView(existing, budget);
    }

    final WeeklyPool pool = WeeklyPool(
      weekKey: key,
      budget: budget,
      used: 0,
      autoReleased: 0,
      resetAt: now,
    );
    await _repo.upsert(pool);
    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.weeklyPoolReset,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'pool_size': budget,
        'tier': (await _settings.getSettings()).ageTier.name,
      },
    ));
    return pool;
  }

  /// 按 weekKey 取池：预算一律**即时派生**（C91，同 [ensureAndReset]）——
  /// 存量行返回派生视图副本；不存在则返回一个以派生预算填充、零消耗的占位池
  /// （不落库）。
  Future<WeeklyPool> pool(String weekKey) async {
    final int budget = await _budgetForCurrentTier();
    final WeeklyPool? existing = await _repo.get(weekKey);
    if (existing != null) {
      return _derivedView(existing, budget);
    }
    return WeeklyPool(weekKey: weekKey, budget: budget);
  }

  /// 池行的「预算即时派生」视图副本：budget 用现算值替换，used / autoReleased /
  /// resetAt 原样（行只承担记账 —— C91 纪律）。
  WeeklyPool _derivedView(WeeklyPool row, int derivedBudget) => WeeklyPool(
        weekKey: row.weekKey,
        budget: derivedBudget,
        used: row.used,
        autoReleased: row.autoReleased,
        resetAt: row.resetAt,
      );

  /// 🔴 **已随 C90-C 同日二次修订删除**：原 `updateBudget(now, budget)`（家长改动
  /// 周预算时同步改写当周池）—— 「本周预算调整」输入控件删除后预算完全按年级
  /// 默认值走，不再有编辑路径，本方法成为死代码一并清理；本注释仅为迷路指针。

  /// 🔴 **已随 C90-C 删除**：原 `autoApproveCap(pool, tier)`（C5② 周自动放行上限，
  /// §3.2 capFor 的薄封装）—— 自动放行功能整体移除；本注释仅为迷路指针。

  /// 应用一笔兑换对池的扣减（[auto]=true 累 autoReleased，否则累 used）。
  ///
  /// `WeeklyPool` 字段为 final，故构造副本后 upsert（替换式写入）。
  Future<void> applyRedemption(WeeklyPool pool, int cost, {required bool auto}) async {
    final WeeklyPool copy = auto
        ? WeeklyPool(
            weekKey: pool.weekKey,
            budget: pool.budget,
            used: pool.used,
            autoReleased: pool.autoReleased + cost,
            resetAt: pool.resetAt,
          )
        : WeeklyPool(
            weekKey: pool.weekKey,
            budget: pool.budget,
            used: pool.used + cost,
            autoReleased: pool.autoReleased,
            resetAt: pool.resetAt,
          );
    await _repo.upsert(copy);
  }
}
