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

  /// 全部账本记录（阳光来源记录页用，按时间倒序）。
  Future<List<SunlightLedger>> allDesc() async {
    final List<SunlightLedger> rows = await select(sunlightLedgers).get();
    rows.sort((SunlightLedger a, SunlightLedger b) => b.ts.compareTo(a.ts));
    return rows;
  }

  /// 当前余额（sum(net)）。
  Future<double> balance() async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日净产出（软顶校验用，§3.2）。
  ///
  /// 注意：本方法按**全部类型**（earn / redeem / plant / queueRelease）求和，
  /// 用于「当天净余额」口径；**不可**用于任务打卡的软顶差额核算（会污染核算，
  /// 打卡核算请用 [sumEarnGrossOnDay] / [sumEarnNetOnDay]）。
  Future<double> dayNet(String dayKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日 **earn 类型** 的 gross（毛产出）合计（任务打卡软顶核算用，§4.5）。
  ///
  /// 只统计 `type == earn`，避免 redeem / plant / queueRelease 污染软顶核算。
  Future<double> sumEarnGrossOnDay(String dayKey) async {
    final Expression<double> sum = sunlightLedgers.gross.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.type.equals(SunlightType.earn.index))
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日 **earn 类型** 的 net（实际发放）合计（任务打卡软顶核算用，§4.5）。
  ///
  /// 只统计 `type == earn`，即「当日已发阳光」的软顶基数。
  Future<double> sumEarnNetOnDay(String dayKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.type.equals(SunlightType.earn.index))
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

  /// 指定 refType 在某日的净阳光合计（家长赠予上限核算用，§4.5）。
  Future<double> sumNetByRefTypeDay(String refType, String dayKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.refType.equals(refType))
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 指定 refType + refId 在某日的**记账条数**（植物每日养护次数上限核算，M3 修订）。
  ///
  /// 养护次数以账本为唯一事实源：每次浇水 / 施肥都写一条 `refType='plant_water' /
  /// 'plant_fertilize'`、`refId=<植物 id>` 的记录，故「今日已用几次」= 当日条数。
  /// 好处是不给 Plants 表加计数列（免二次 schema 迁移），且天然可对账。
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async {
    final Expression<int> countExp = sunlightLedgers.id.count();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.refType.equals(refType))
          ..where(sunlightLedgers.refId.equals(refId))
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([countExp]))
        .getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 指定 refType + refId 的**最近一次记账时间**（浇水最小间隔核算，M3 修订）。
  ///
  /// 用账本时间而非 `Plants.lastWaterAt`：后者在施肥 / 救回时也会被刷新，
  /// 会让「浇完水 → 施肥 → 立刻又能浇水」绕过 30 分钟间隔。
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final Expression<DateTime> maxExp = sunlightLedgers.ts.max();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.refType.equals(refType))
          ..where(sunlightLedgers.refId.equals(refId))
          ..addColumns([maxExp]))
        .getSingle();
    return row.read(maxExp);
  }

  /// 指定 refType 在某月的净阳光合计（按 dayKey 前缀匹配 monthKey）。
  Future<double> sumNetByRefTypeMonth(String refType, String monthKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.refType.equals(refType))
          ..where(sunlightLedgers.dayKey.like('$monthKey%'))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }
}

/// 植物 DAO（§3.1 plant，M3 新增）。
@DriftAccessor(tables: [Plants])
class PlantDao extends DatabaseAccessor<AppDatabase> with _$PlantDaoMixin {
  PlantDao(super.db);

  /// 全部植物。
  Future<List<Plant>> all() => select(plants).get();

  /// 按主键（id）读取单株，不存在返回 null。
  Future<Plant?> byId(String id) =>
      (select(plants)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 插入或更新（按主键冲突合并）。
  Future<void> upsert(PlantsCompanion row) =>
      into(plants).insertOnConflictUpdate(row);

  /// 硬删除单株（按主键 id）。
  Future<int> deleteById(String id) =>
      (delete(plants)..where((t) => t.id.equals(id))).go();

  /// 清空全部植物（数据管理 / 删除全部本地数据用）。
  Future<int> deleteAll() => delete(plants).go();
}

/// 任务 / 打卡 DAO（§3.1 task / check_in，M3 真实化）。
@DriftAccessor(tables: [Tasks, CheckIns])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  /// 全部任务模板。
  Future<List<Task>> allTasks() => select(tasks).get();

  /// 插入或更新任务（按主键冲突合并）。
  Future<void> upsertTask(TasksCompanion row) =>
      into(tasks).insertOnConflictUpdate(row);

  /// 硬删除任务（按主键 id）。
  Future<int> deleteTaskById(String id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// 插入一条打卡记录。
  Future<void> insertCheckIn(CheckInsCompanion row) =>
      into(checkIns).insert(row);

  /// 某日打卡记录（date 落在 [dayStart, dayStart+1d) 区间）。
  Future<List<CheckIn>> checkInsOfDay(String dayKey) {
    final DateTime dayStart = _parseDay(dayKey);
    final DateTime dayEnd = dayStart.add(const Duration(days: 1));
    return (select(checkIns)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(dayStart) &
              t.date.isSmallerThanValue(dayEnd)))
        .get();
  }

  /// 清空全部任务与打卡（数据管理用）。
  Future<int> deleteAllTasks() => delete(tasks).go();
  Future<int> deleteAllCheckIns() => delete(checkIns).go();

  /// 全部打卡记录条数（跨任务、跨日期累计；M4 打卡领域层聚合用）。
  Future<int> countCheckIns() async {
    final Expression<int> countExp = checkIns.id.count();
    final row =
        await (selectOnly(checkIns)..addColumns([countExp])).getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 按主键读取单条打卡；不存在返回 null（家长端核销用，M4）。
  Future<CheckIn?> checkInById(String id) =>
      (select(checkIns)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 指定核销状态的打卡，按 completedAt 升序（家长端待核销列表用，M4）。
  Future<List<CheckIn>> checkInsByStatus(int status) =>
      (select(checkIns)
            ..where((t) => t.status.equals(status))
            ..orderBy([(t) => OrderingTerm(expression: t.completedAt)]))
          .get();

  /// 更新打卡记录（按主键冲突合并；家长核销 / 驳回写回用，M4）。
  Future<void> updateCheckIn(CheckInsCompanion row) =>
      into(checkIns).insertOnConflictUpdate(row);

  /// 指定核销状态的打卡条数（M4 统计口径：只数已核销）。
  ///
  /// 状态以 int 传参（数据层不依赖领域枚举，避免跨层依赖）。
  Future<int> countCheckInsByStatus(int status) async {
    final Expression<int> countExp = checkIns.id.count();
    final row = await (selectOnly(checkIns)
          ..addColumns([countExp])
          ..where(checkIns.status.equals(status)))
        .getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 「仅当仍为 [fromStatus]」时写回核销结果（CAS）；返回受影响行数（0 = 已被处理过）。
  ///
  /// 并发双核销防护：家长连点两次时，第二次 `where` 命中 0 行 → 返回 0，
  /// 调用方据此放弃入账（否则余额翻倍）。状态以 int 传参（数据层不依赖领域枚举）。
  Future<int> resolveCheckInIfStatus({
    required String id,
    required int fromStatus,
    required int toStatus,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) {
    return (update(checkIns)
          ..where((t) => t.id.equals(id) & t.status.equals(fromStatus)))
        .write(CheckInsCompanion(
          status: Value(toStatus),
          sunlightGranted: Value(sunlightGranted),
          resolvedAt: Value(resolvedAt),
          parentNote: Value(parentNote),
        ));
  }

  /// 解析日键 `yyyy-MM-dd` 为当日 0 点。
  DateTime _parseDay(String key) {
    final List<String> parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
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

  /// 硬删除一个奖励模板（按主键 id）。
  Future<int> deleteById(String id) =>
      (delete(rewardTemplates)..where((t) => t.id.equals(id))).go();
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

  /// 已拒绝的申请（status==rejected），供孩子端「拒绝对称通知」使用（B4）。
  Future<List<RedemptionRequest>> rejected() =>
      (select(redemptionRequests)
            ..where((r) => r.status.equals(RequestStatus.rejected.index)))
          .get();

  /// 某周排队中的申请（status==queued 且 requestedAt >= 当周周一）。
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) {
    final query = select(redemptionRequests)
      ..where((r) =>
          r.status.equals(RequestStatus.queued.index) &
          r.requestedAt.isBiggerOrEqualValue(DateTime.parse(weekKey)));
    return query.get();
  }
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

  /// 冲减 used_count（下限 0），用于拒绝/撤销兑换时回退「已领次数」。
  ///
  /// 行不存在时静默跳过（createRequest 一定先 bump 确保行存在，正常不会触发，
  /// 但拒绝路径独立调用以防边界情况下出现负计数）。
  Future<void> decrement(String templateId, CooldownPeriod period) async {
    final int existing = await count(templateId, period);
    if (existing <= 0) return; // 无记录即 0，无需操作
    await customStatement(
      'UPDATE cooldown_counters SET used_count = MAX(0, used_count - 1) '
      'WHERE template_id = ? AND period = ?',
      [templateId, period.index],
    );
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
