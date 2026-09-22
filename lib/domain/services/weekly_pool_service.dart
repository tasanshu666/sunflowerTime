/// 周阳光池服务（§2.4 / §3.2 / §4.1）。
///
/// 职责：取/建/重置当周奖励预算池（每周一 0 点），以及 C5 免确认上限计算。
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

/// 周奖励预算池服务。
///
/// 构造注入三个仓储：周池仓储、设置仓储（取默认预算与档位）、埋点仓储
/// （跨周重置时落 `weekly_pool_reset` 事件）。
class WeeklyPoolService {
  final WeeklyPoolRepository _repo;
  final SettingsRepository _settings;
  final TrackingRepository _tracking;
  final Uuid _uuid = Uuid();

  WeeklyPoolService(this._repo, this._settings, this._tracking);

  /// 取/建当周池：若已存在直接返回；否则按当前设置预算新建并落重置埋点。
  Future<WeeklyPool> ensureAndReset(DateTime now) async {
    final String key = weekKey(now);
    final WeeklyPool? existing = await _repo.get(key);
    if (existing != null) return existing;

    final int budget = (await _settings.getSettings()).poolBudget;
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

  /// 按 weekKey 取池（不存在则返回一个以默认预算填充、零消耗的占位池，不落库）。
  Future<WeeklyPool> pool(String weekKey) async {
    final WeeklyPool? existing = await _repo.get(weekKey);
    if (existing != null) return existing;
    return WeeklyPool(
      weekKey: weekKey,
      budget: (await _settings.getSettings()).poolBudget,
    );
  }

  /// 家长改动周预算：同步改写当周池的 budget，保留 used / autoReleased / resetAt。
  ///
  /// 避免「保存预算后展示卡不刷新」（原 [pool] 对已存在的行直接返回，budget 永远停在
  /// 建池时的旧值）。不存在则按给定 budget 新建一行（零消耗）。返回更新后的池。
  Future<WeeklyPool> updateBudget(DateTime now, int budget) async {
    final String key = weekKey(now);
    final WeeklyPool? existing = await _repo.get(key);
    if (existing == null) {
      final WeeklyPool created = WeeklyPool(
        weekKey: key,
        budget: budget,
        used: 0,
        autoReleased: 0,
        resetAt: now,
      );
      await _repo.upsert(created);
      return created;
    }
    // 仅替换 budget，其余字段（used / autoReleased / resetAt）原样保留。
    final WeeklyPool updated = WeeklyPool(
      weekKey: existing.weekKey,
      budget: budget,
      used: existing.used,
      autoReleased: existing.autoReleased,
      resetAt: existing.resetAt,
    );
    await _repo.upsert(updated);
    return updated;
  }

  /// C5② 周自动放行上限（§3.2 capFor 的薄封装）。
  int autoApproveCap(WeeklyPool pool, AgeTier tier) => capFor(tier, pool.budget);

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
