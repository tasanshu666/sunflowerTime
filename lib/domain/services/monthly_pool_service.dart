/// 月度池服务（§2.4 / §3.2 / §4.1）。
///
/// 职责：取/建/重置当月奖励预算池（每月 1 日 0 点），以及 C5 免确认上限计算。
/// 不落任何阳光账本（账本归 [SunlightRepository]），只维护 `monthly_pool` 的独立对账。
///
/// 设计纪律（§7.4）：queued 状态**绝不**由本服务扣账本/扣池；扣减只发生在
/// [RedemptionOrchestrationService] 的 verify / releaseQueue 路径。
library monthly_pool_service;

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/age_tier_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/monthly_pool.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/monthly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';

/// 月度奖励预算池服务。
///
/// 构造注入三个仓储：月度池仓储、设置仓储（取默认预算与档位）、埋点仓储
/// （跨月重置时落 `monthly_pool_reset` 事件）。
class MonthlyPoolService {
  final MonthlyPoolRepository _repo;
  final SettingsRepository _settings;
  final TrackingRepository _tracking;
  final Uuid _uuid = Uuid();

  MonthlyPoolService(this._repo, this._settings, this._tracking);

  /// 取/建当月池：若已存在直接返回；否则按当前设置预算新建并落重置埋点。
  Future<MonthlyPool> ensureAndReset(DateTime now) async {
    final String key = monthKey(now);
    final MonthlyPool? existing = await _repo.get(key);
    if (existing != null) return existing;

    final int budget = (await _settings.getSettings()).monthlyPoolBudget;
    final MonthlyPool pool = MonthlyPool(
      monthKey: key,
      budget: budget,
      used: 0,
      autoReleased: 0,
      resetAt: now,
    );
    await _repo.upsert(pool);
    await _tracking.track(TrackingEvent(
      id: _uuid.v4(),
      name: TrackingEventNames.monthlyPoolReset,
      type: TrackingType.metric,
      ts: now,
      payload: {
        'pool_size': budget,
        'tier': (await _settings.getSettings()).ageTier.name,
      },
    ));
    return pool;
  }

  /// 按 monthKey 取池（不存在则返回一个以默认预算填充、零消耗的占位池，不落库）。
  Future<MonthlyPool> pool(String monthKey) async {
    final MonthlyPool? existing = await _repo.get(monthKey);
    if (existing != null) return existing;
    return MonthlyPool(
      monthKey: monthKey,
      budget: (await _settings.getSettings()).monthlyPoolBudget,
    );
  }

  /// C5② 月度自动放行上限（§3.2 capFor 的薄封装）。
  int autoApproveCap(MonthlyPool pool, AgeTier tier) => capFor(tier, pool.budget);

  /// 应用一笔兑换对池的扣减（[auto]=true 累 autoReleased，否则累 used）。
  ///
  /// `MonthlyPool` 字段为 final，故构造副本后 upsert（替换式写入）。
  Future<void> applyRedemption(MonthlyPool pool, int cost, {required bool auto}) async {
    final MonthlyPool copy = auto
        ? MonthlyPool(
            monthKey: pool.monthKey,
            budget: pool.budget,
            used: pool.used,
            autoReleased: pool.autoReleased + cost,
            resetAt: pool.resetAt,
          )
        : MonthlyPool(
            monthKey: pool.monthKey,
            budget: pool.budget,
            used: pool.used + cost,
            autoReleased: pool.autoReleased,
            resetAt: pool.resetAt,
          );
    await _repo.upsert(copy);
  }
}
