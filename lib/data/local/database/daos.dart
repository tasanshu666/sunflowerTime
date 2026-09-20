/// DAO：聚合 / 时间序列查询（§3.2 对账 SQL）。
library daos;

import 'package:drift/drift.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

import 'app_database.dart';
import 'tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// 读取设置单行（单例行，id = 1）。
  Future<Setting?> getRow() => select(settings).getSingleOrNull();

  /// 插入或更新（按主键 id 冲突合并）。
  Future<void> upsert(SettingsCompanion row) =>
      into(settings).insertOnConflictUpdate(row);
}

@DriftAccessor(tables: [SunlightLedgers])
class SunlightLedgerDao extends DatabaseAccessor<AppDatabase>
    with _$SunlightLedgerDaoMixin {
  SunlightLedgerDao(super.db);

  /// 追加一条账本记录（append-only，§3.2）。
  Future<void> append(SunlightLedgersCompanion row) =>
      into(sunlightLedgers).insert(row);

  /// 当前余额（sum(net)）。
  Future<double> balance() async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日净产出（软顶校验用，§3.2）。
  Future<double> dayNet(String dayKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 已核销总额对账（§3.2）。
  Future<double> verifiedRedeemTotal() async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.type.equals(SunlightType.redeem.index))
          ..addColumns([sum]))
        .getSingle();
    final value = row.read(sum);
    return (value ?? 0.0).abs();
  }
}

/// 奖励模板 DAO（§3.2）。
@DriftAccessor(tables: [RewardTemplates])
class RewardTemplateDao extends DatabaseAccessor<AppDatabase>
    with _$RewardTemplateDaoMixin {
  RewardTemplateDao(super.db);

  /// 全部奖励模板。
  Future<List<RewardTemplate>> all() => select(rewardTemplates).get();

  /// 仅启用中的模板。
  Future<List<RewardTemplate>> watchEnabled() =>
      (select(rewardTemplates)..where((t) => t.enabled.equals(true))).get();

  /// 插入或更新（按主键冲突合并）。
  Future<void> upsert(RewardTemplatesCompanion row) =>
      into(rewardTemplates).insertOnConflictUpdate(row);
}

/// 兑换申请 DAO（§3.2）。
@DriftAccessor(tables: [RedemptionRequests])
class RedemptionRequestDao extends DatabaseAccessor<AppDatabase>
    with _$RedemptionRequestDaoMixin {
  RedemptionRequestDao(super.db);

  /// 插入一条兑换申请。
  Future<void> insert(RedemptionRequestsCompanion row) =>
      into(redemptionRequests).insert(row);

  /// 按主键冲突更新。
  Future<void> updateRow(RedemptionRequestsCompanion row) =>
      into(redemptionRequests).insertOnConflictUpdate(row);

  /// 待核销 + 排队中的申请。
  Future<List<RedemptionRequest>> pendingAndQueued() =>
      (select(redemptionRequests)
            ..where((r) => r.status.isIn(
                [RequestStatus.pending.index, RequestStatus.queued.index])))
          .get();

  /// 已核销的申请（status==verified）；排序交给仓储层，避免 drift orderBy 抖动。
  Future<List<RedemptionRequest>> verified() =>
      (select(redemptionRequests)
            ..where((r) => r.status.equals(RequestStatus.verified.index)))
          .get();

  /// 某月排队中的申请（status==queued 且 requestedAt >= 当月首日）。
  Future<List<RedemptionRequest>> queuedOfMonth(String monthKey) =>
      (select(redemptionRequests)
            ..where((r) =>
                r.status.equals(RequestStatus.queued.index) &
                r.requestedAt
                    .isBiggerOrEqualValue(DateTime.parse('$monthKey-01'))))
          .get();
}

/// 月度池 DAO（§3.2）。
@DriftAccessor(tables: [MonthlyPools])
class MonthlyPoolDao extends DatabaseAccessor<AppDatabase>
    with _$MonthlyPoolDaoMixin {
  MonthlyPoolDao(super.db);

  /// 按主键（monthKey）读取单条，不存在返回 null。
  Future<MonthlyPool?> of(String monthKey) =>
      (select(monthlyPools)..where((p) => p.monthKey.equals(monthKey)))
          .getSingleOrNull();

  /// 插入或更新（按主键冲突合并）。
  Future<void> upsert(MonthlyPoolsCompanion row) =>
      into(monthlyPools).insertOnConflictUpdate(row);
}

/// 冷却计数 DAO（§3.2）。
@DriftAccessor(tables: [CooldownCounters])
class CooldownCounterDao extends DatabaseAccessor<AppDatabase>
    with _$CooldownCounterDaoMixin {
  CooldownCounterDao(super.db);

  /// 先确保行存在，再 used_count + 1。
  Future<void> bump(String templateId, CooldownPeriod period) async {
    final int existing = await count(templateId, period);
    if (existing == 0) {
      await into(cooldownCounters).insert(
        CooldownCountersCompanion(
          templateId: Value(templateId),
          period: Value(period.index),
        ),
      );
    }
    await customStatement(
      'UPDATE cooldown_counters SET used_count = used_count + 1 '
      'WHERE template_id = ? AND period = ?',
      [templateId, period.index],
    );
  }

  /// 返回该 (templateId, period) 行的 used_count（无记录视为 0）。
  /// (templateId, period) 为月度池主键，至多一行。
  Future<int> count(String templateId, CooldownPeriod period) async {
    final CooldownCounter? row = await (select(cooldownCounters)
          ..where((c) =>
              c.templateId.equals(templateId) & c.period.equals(period.index)))
        .getSingleOrNull();
    return row?.usedCount ?? 0;
  }
}

/// 埋点 DAO（§3.2 / §6）。
@DriftAccessor(tables: [TrackingEvents])
class TrackingEventDao extends DatabaseAccessor<AppDatabase>
    with _$TrackingEventDaoMixin {
  TrackingEventDao(super.db);

  /// 插入一条埋点。
  Future<void> insert(TrackingEventsCompanion row) =>
      into(trackingEvents).insert(row);

  /// 按 type 返回。
  Future<List<TrackingEvent>> ofType(int type) =>
      (select(trackingEvents)..where((e) => e.type.equals(type))).get();

  /// ts 落在 [from, to] 区间（含端点）。
  Future<List<TrackingEvent>> inRange(DateTime from, DateTime to) =>
      (select(trackingEvents)
            ..where((e) => e.ts.isBetweenValues(from, to)))
          .get();
}
