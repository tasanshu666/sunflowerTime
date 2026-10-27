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

  /// C90 期 2：[childId] 可选过滤（null = 不过滤，仅迁移/老调用点用；
  /// 仓储层一律传当前孩子，漏传即数据串孩子 —— 全部口径见下）。

  /// 追加一条账本记录（append-only，§3.2）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> append(SunlightLedgersCompanion row, {String? childId}) {
    final SunlightLedgersCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(sunlightLedgers).insert(full);
  }

  /// 全部账本记录（阳光来源记录页用，按时间倒序）。
  Future<List<SunlightLedger>> allDesc({String? childId}) async {
    final query = select(sunlightLedgers);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    final List<SunlightLedger> rows = await query.get();
    rows.sort((SunlightLedger a, SunlightLedger b) => b.ts.compareTo(a.ts));
    return rows;
  }

  /// 当前余额（sum(net)）。
  Future<double> balance({String? childId}) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日净产出（软顶校验用，§3.2）。
  ///
  /// 注意：本方法按**全部类型**（earn / redeem / plant / queueRelease）求和，
  /// 用于「当天净余额」口径；**不可**用于任务打卡的软顶差额核算（会污染核算，
  /// 打卡核算请用 [sumEarnGrossOnDay] / [sumEarnNetOnDay]）。
  Future<double> dayNet(String dayKey, {String? childId}) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.dayKey.equals(dayKey))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日 **earn 类型** 的 gross（毛产出）合计（任务打卡软顶核算用，§4.5）。
  ///
  /// 只统计 `type == earn`，避免 redeem / plant / queueRelease 污染软顶核算。
  Future<double> sumEarnGrossOnDay(String dayKey, {String? childId}) async {
    final Expression<double> sum = sunlightLedgers.gross.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.type.equals(SunlightType.earn.index))
      ..where(sunlightLedgers.dayKey.equals(dayKey))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日 **earn 类型** 的 net（实际发放）合计（任务打卡软顶核算用，§4.5）。
  ///
  /// 只统计 `type == earn`，即「当日已发阳光」的软顶基数。
  Future<double> sumEarnNetOnDay(String dayKey, {String? childId}) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.type.equals(SunlightType.earn.index))
      ..where(sunlightLedgers.dayKey.equals(dayKey))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 已核销总额对账（§3.2）。
  Future<double> verifiedRedeemTotal({String? childId}) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.type.equals(SunlightType.redeem.index))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    final value = row.read(sum);
    return (value ?? 0.0).abs();
  }

  /// 指定 refType 在某日的净阳光合计（家长赠予上限核算用，§4.5）。
  Future<double> sumNetByRefTypeDay(
    String refType,
    String dayKey, {
    String? childId,
  }) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..where(sunlightLedgers.dayKey.equals(dayKey))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
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
    String dayKey, {
    String? childId,
  }) async {
    final Expression<int> countExp = sunlightLedgers.id.count();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..where(sunlightLedgers.refId.equals(refId))
      ..where(sunlightLedgers.dayKey.equals(dayKey))
      ..addColumns([countExp]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 指定 refType + refId 自 [since]（含）以来的**记账条数**（枯萎后养护恢复次数核算，2026-09-23）。
  ///
  /// 与 [countByRefTypeAndRefIdOnDay] 同源：每次浇水 / 施肥都写一条 `refType='plant_water' /
  /// 'plant_fertilize'`、`refId=<植物 id>` 的记录。恢复判定「wilting 后累计浇几次 / 施几次」
  /// 用本方法（以 `wiltedAt` 为 [since]），天然可对账、不引入新计数列。
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since, {
    String? childId,
  }) async {
    final Expression<int> countExp = sunlightLedgers.id.count();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..where(sunlightLedgers.refId.equals(refId))
      ..where(sunlightLedgers.ts.isBiggerOrEqualValue(since))
      ..addColumns([countExp]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 指定 refType 的**全部记账条数**（孩子端「我的」累计护眼次数，2026-10-09）。
  ///
  /// 与 [countByRefTypeAndRefIdOnDay] 的区别：不按日、不按 refId，全表累计 ——
  /// 「累计护眼」以账本 `refType='eye_care_break'` 为权威口径（含上线以来全部历史）。
  Future<int> countByRefType(String refType, {String? childId}) async {
    final Expression<int> countExp = sunlightLedgers.id.count();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..addColumns([countExp]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 指定 refType 的**最近一条**记账（家长赠予到账提醒用，F150）。
  ///
  /// 用账本时间排序取首行；`id` 全局唯一（uuid）作已读判据比 ts 稳（同秒多笔）。
  Future<SunlightLedger?> latestByRefType(
    String refType, {
    String? childId,
  }) {
    final query = select(sunlightLedgers)
      ..where((t) => t.refType.equals(refType))
      ..orderBy([(t) => OrderingTerm.desc(t.ts)])
      ..limit(1);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.getSingleOrNull();
  }

  /// 指定 refType + refId 的**最近一次记账时间**（浇水最小间隔核算，M3 修订）。
  ///
  /// 用账本时间而非 `Plants.lastWaterAt`：后者在施肥 / 救回时也会被刷新，
  /// 会让「浇完水 → 施肥 → 立刻又能浇水」绕过 30 分钟间隔。
  Future<DateTime?> lastTsByRefTypeAndRefId(
    String refType,
    String refId, {
    String? childId,
  }) async {
    final Expression<DateTime> maxExp = sunlightLedgers.ts.max();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..where(sunlightLedgers.refId.equals(refId))
      ..addColumns([maxExp]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(maxExp);
  }

  /// 指定 refType 在某月的净阳光合计（按 dayKey 前缀匹配 monthKey）。
  Future<double> sumNetByRefTypeMonth(
    String refType,
    String monthKey, {
    String? childId,
  }) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final query = selectOnly(sunlightLedgers)
      ..where(sunlightLedgers.refType.equals(refType))
      ..where(sunlightLedgers.dayKey.like('$monthKey%'))
      ..addColumns([sum]);
    if (childId != null) {
      query.where(sunlightLedgers.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0.0;
  }
}

/// 植物 DAO（§3.1 plant，M3 新增）。
///
/// C90 期 2：查询 / 写入方法带可选 [childId]（null = 不过滤 / 不补写，仅迁移与
/// 老调用点用；仓储层一律传当前孩子，漏传即数据串孩子）。
@DriftAccessor(tables: [Plants])
class PlantDao extends DatabaseAccessor<AppDatabase> with _$PlantDaoMixin {
  PlantDao(super.db);

  /// 全部植物。
  Future<List<Plant>> all({String? childId}) {
    final query = select(plants);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.get();
  }

  /// 按主键（id）读取单株，不存在返回 null。
  Future<Plant?> byId(String id, {String? childId}) {
    final query = select(plants)..where((t) => t.id.equals(id));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.getSingleOrNull();
  }

  /// 插入或更新（按主键冲突合并）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> upsert(PlantsCompanion row, {String? childId}) {
    final PlantsCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(plants).insertOnConflictUpdate(full);
  }

  /// 硬删除单株（按主键 id）。
  Future<int> deleteById(String id, {String? childId}) {
    final query = delete(plants)..where((t) => t.id.equals(id));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.go();
  }

  /// 清空全部植物（数据管理 / 删除全部本地数据用）。
  Future<int> deleteAll() => delete(plants).go();
}

/// 空花盆干扰物 DAO（F155-B，玄参 2026-10-27 拍板）。
///
/// 口径（详见 `tables.dart` 的 `EmptyPotDisturbances` 注释）：空盆每天独立 roll
/// 杂草 / 害虫（频率为植物一半），清理奖励与植物一致。单键 = (childId, potIndex)。
///
/// C90 期 2 口径同其它 DAO：方法带可选 [childId]（null = 不过滤 / 不补写，仅迁移与
/// 老调用点用；仓储层一律传当前孩子，漏传即数据串孩子）。
@DriftAccessor(tables: [EmptyPotDisturbances])
class EmptyPotDisturbanceDao extends DatabaseAccessor<AppDatabase>
    with _$EmptyPotDisturbanceDaoMixin {
  EmptyPotDisturbanceDao(super.db);

  /// 当前孩子的全部空盆干扰物记录。
  Future<List<EmptyPotDisturbanceRow>> all({String? childId}) {
    final query = select(emptyPotDisturbances);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.get();
  }

  /// 按 (childId, potIndex) 读取单条，不存在返回 null。
  Future<EmptyPotDisturbanceRow?> byPot(int potIndex, {String? childId}) {
    final query = select(emptyPotDisturbances)
      ..where((t) => t.potIndex.equals(potIndex));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.getSingleOrNull();
  }

  /// 插入或更新（按复合主键 (childId, potIndex) 冲突合并）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> upsert(EmptyPotDisturbancesCompanion row, {String? childId}) {
    final EmptyPotDisturbancesCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(emptyPotDisturbances).insertOnConflictUpdate(full);
  }

  /// 删除某盆记录（种下植物时调用；删 0 行不报错 = 幂等）。
  Future<int> deleteByPot(int potIndex, {String? childId}) {
    final query = delete(emptyPotDisturbances)
      ..where((t) => t.potIndex.equals(potIndex));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.go();
  }

  /// 清空当前孩子的全部记录（数据管理 / 删除全部本地数据用）。
  Future<int> deleteAll({String? childId}) {
    final query = delete(emptyPotDisturbances);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.go();
  }
}

/// 成株后循环玩法 Batch 1 DAO（§3.1）：精品碎片余额 / 第二段待收集奖励 / 已解锁物种。
///
/// C90 期 2 第二批：premium_fragments / unlocked_species 已按孩子隔离
///（schemaVersion 28 表重建，复合主键并入 child_id）—— 查询 / 写入方法带可选
/// [childId]（null = 不过滤 / 不补写，仅迁移与老调用点用；仓储层一律传当前孩子，
/// 漏传即数据串孩子）。pending_bloom_rewards 本批不动（花开队列暂不按孩子分）。
@DriftAccessor(tables: [PremiumFragments, PendingBloomRewards, UnlockedSpecies])
class BloomRewardDao extends DatabaseAccessor<AppDatabase>
    with _$BloomRewardDaoMixin {
  BloomRewardDao(super.db);

  /// 精品碎片余额（单例行 per 孩子：id 恒 = 1 + childId；无记录视为 0）。
  Future<int> fragmentBalance({String? childId}) async {
    final query = select(premiumFragments)..where((t) => t.id.equals(1));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    final PremiumFragmentRow? row = await query.getSingleOrNull();
    return row?.balance ?? 0;
  }

  /// 覆盖式写入精品碎片余额（upsert，复合主键 (id=1, childId) 冲突合并）。
  ///
  /// [childId] 为 null 时不显式带 childId（新行落列默认 kChildIdDefault，
  /// 与「null = 老调用点」口径一致）。
  Future<void> setFragmentBalance(int balance, {String? childId}) =>
      into(premiumFragments).insertOnConflictUpdate(
        PremiumFragmentsCompanion(
          id: const Value(1),
          balance: Value(balance),
          childId: childId == null ? const Value.absent() : Value(childId),
        ),
      );

  /// 已解锁物种 id 列表（语义：当前孩子持有的免费种植券）。
  Future<List<String>> unlockedSpeciesIds({String? childId}) async {
    final query = select(unlockedSpecies);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    final List<UnlockedSpeciesRow> rows = await query.get();
    return rows.map((UnlockedSpeciesRow r) => r.speciesId).toList();
  }

  /// 写入一张免费种植券（幂等，按复合主键 (speciesId, childId) 冲突合并）。
  Future<void> unlockSpecies(String speciesId, {String? childId}) =>
      into(unlockedSpecies).insertOnConflictUpdate(
        UnlockedSpeciesCompanion(
          speciesId: Value(speciesId),
          childId: childId == null ? const Value.absent() : Value(childId),
        ),
      );

  /// 消耗一张免费种植券（删除当前孩子的该 speciesId 行）。
  ///
  /// 删除 0 行不报错（幂等）：调用方可能对「无券」的物种重复调用，视为无副作用。
  /// ⚠️ 按孩子过滤：消耗动作**绝不动**另一孩子的券。
  Future<void> consumeUnlock(String speciesId, {String? childId}) {
    final query = delete(unlockedSpecies)..where((t) => t.speciesId.equals(speciesId));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.go();
  }

  /// 写入一条待收集奖励（花开瞬间 / 花开 48h 后掉落）。
  ///
  /// ⚠️ 用 `insertOnConflictUpdate`（**幂等 upsert**，按主键 id 冲突合并），与内存实现
  /// `InMemoryBloomRewardRepository.insertPendingBloomReward` 的语义**保持一致**。
  /// 历史缺陷（2026-09-26）：此处曾是裸 `insert`，而内存实现是 upsert —— 二者语义不一致，
  /// 导致「对同一条记录按 id 覆盖写」（如调试面板改 `due_at`、或将来重写同 id 记录）在真实
  /// SQLite 上抛 `UNIQUE constraint failed: pending_bloom_rewards.id`（SQLITE_CONSTRAINT 1555）。
  /// 改用 upsert 后，同 id 覆盖写安全幂等，测试 Fake 与真实库行为对齐。
  Future<void> insertPending(PendingBloomRewardsCompanion row) =>
      into(pendingBloomRewards).insertOnConflictUpdate(row);

  /// 已到期且未发放的待发奖励。
  Future<List<PendingBloomRewardRow>> pendingDue(DateTime now) =>
      (select(pendingBloomRewards)
            ..where((t) =>
                t.claimed.equals(false) & t.dueAt.isSmallerOrEqualValue(now)))
          .get();

  /// 按主键读取单条待发奖励（**不限 claimed / 到期**；对账 / 迁移断言用）。
  Future<PendingBloomRewardRow> byId(String id) =>
      (select(pendingBloomRewards)..where((t) => t.id.equals(id))).getSingle();

  /// 标记某条待发奖励为已发放（幂等：已发放再写无副作用）。
  Future<void> markClaimed(String id) =>
      (update(pendingBloomRewards)..where((t) => t.id.equals(id)))
          .write(const PendingBloomRewardsCompanion(claimed: Value(true)));

  /// 物理删除一条待发奖励（C45 历史重复行去重；幂等，删不存在 id 无副作用）。
  Future<void> deletePendingById(String id) =>
      (delete(pendingBloomRewards)..where((t) => t.id.equals(id))).go();

  /// 回写某条待发奖励的「奖励内容」（v12 掉落即定奖）。
  ///
  /// 用途：历史行（三列零值哨兵 `0/0/null` = 未预先定奖）在**首次结算**时退回「现场 roll」，
  /// 把 roll 结果顺手回填本行（不改 claimed——由 [markClaimed] 负责）。
  Future<void> updatePendingContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  }) =>
      (update(pendingBloomRewards)..where((t) => t.id.equals(id))).write(
        PendingBloomRewardsCompanion(
          rewardSunlight: Value(rewardSunlight),
          rewardFragments: Value(rewardFragments),
          rewardSpeciesId: Value(rewardSpeciesId),
        ),
      );

  /// 清空本 DAO 三张表（数据管理 / 删除全部本地数据用）。
  Future<void> deleteAllFragments() => delete(premiumFragments).go();
  Future<void> deleteAllPending() => delete(pendingBloomRewards).go();
  Future<void> deleteAllUnlocked() => delete(unlockedSpecies).go();
}

/// 任务 / 打卡 DAO（§3.1 task / check_in，M3 真实化）。
///
/// C90 期 2：查询 / 写入方法带可选 [childId]（null = 不过滤 / 不补写，仅迁移与
/// 老调用点用；仓储层一律传当前孩子，漏传即数据串孩子）。
@DriftAccessor(tables: [Tasks, CheckIns])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  /// 全部任务模板。
  Future<List<Task>> allTasks({String? childId}) {
    final query = select(tasks);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.get();
  }

  /// 插入或更新任务（按主键冲突合并）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> upsertTask(TasksCompanion row, {String? childId}) {
    final TasksCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(tasks).insertOnConflictUpdate(full);
  }

  /// 硬删除任务（按主键 id）。
  Future<int> deleteTaskById(String id, {String? childId}) {
    final query = delete(tasks)..where((t) => t.id.equals(id));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.go();
  }

  /// 插入一条打卡记录。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> insertCheckIn(CheckInsCompanion row, {String? childId}) {
    final CheckInsCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(checkIns).insert(full);
  }

  /// 某日打卡记录（date 落在 [dayStart, dayStart+1d) 区间）。
  Future<List<CheckIn>> checkInsOfDay(String dayKey, {String? childId}) {
    final DateTime dayStart = _parseDay(dayKey);
    final DateTime dayEnd = dayStart.add(const Duration(days: 1));
    final query = select(checkIns)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(dayStart) &
          t.date.isSmallerThanValue(dayEnd));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.get();
  }

  /// 清空全部任务与打卡（数据管理用）。
  Future<int> deleteAllTasks() => delete(tasks).go();
  Future<int> deleteAllCheckIns() => delete(checkIns).go();

  /// 全部打卡记录条数（跨任务、跨日期累计；M4 打卡领域层聚合用）。
  Future<int> countCheckIns({String? childId}) async {
    final Expression<int> countExp = checkIns.id.count();
    final query = selectOnly(checkIns)..addColumns([countExp]);
    if (childId != null) {
      query.where(checkIns.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 按主键读取单条打卡；不存在返回 null（家长端核销用，M4）。
  Future<CheckIn?> checkInById(String id, {String? childId}) {
    final query = select(checkIns)..where((t) => t.id.equals(id));
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.getSingleOrNull();
  }

  /// 指定核销状态的打卡，按 completedAt 升序（家长端待核销列表用，M4）。
  Future<List<CheckIn>> checkInsByStatus(int status, {String? childId}) {
    final query = select(checkIns)
      ..where((t) => t.status.equals(status))
      ..orderBy([(t) => OrderingTerm(expression: t.completedAt)]);
    if (childId != null) {
      query.where((t) => t.childId.equals(childId));
    }
    return query.get();
  }

  /// 更新打卡记录（按主键冲突合并；家长核销 / 驳回写回用，M4）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子，
  /// 防 upsert 更新路径把归属改写回默认孩子）。
  Future<void> updateCheckIn(CheckInsCompanion row, {String? childId}) {
    final CheckInsCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(checkIns).insertOnConflictUpdate(full);
  }

  /// 指定核销状态的打卡条数（M4 统计口径：只数已核销）。
  ///
  /// 状态以 int 传参（数据层不依赖领域枚举，避免跨层依赖）。
  Future<int> countCheckInsByStatus(int status, {String? childId}) async {
    final Expression<int> countExp = checkIns.id.count();
    final query = selectOnly(checkIns)
      ..addColumns([countExp])
      ..where(checkIns.status.equals(status));
    if (childId != null) {
      query.where(checkIns.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 「仅当仍为 [fromStatus]」时写回核销结果（CAS）；返回受影响行数（0 = 已被处理过）。
  ///
  /// 并发双核销防护：家长连点两次时，第二次 `where` 命中 0 行 → 返回 0，
  /// 调用方据此放弃入账（否则余额翻倍）。状态以 int 传参（数据层不依赖领域枚举）。
  /// [childId] 双保险：id 唯一之外再按孩子过滤（C90 期 2）。
  Future<int> resolveCheckInIfStatus({
    required String id,
    required int fromStatus,
    required int toStatus,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
    String? childId,
  }) {
    return (update(checkIns)
          ..where((t) {
            Expression<bool> cond =
                t.id.equals(id) & t.status.equals(fromStatus);
            if (childId != null) {
              cond = cond & t.childId.equals(childId);
            }
            return cond;
          }))
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
///
/// 🔴 **C91 / F123（玄参平板真机反馈：兑换申请按孩子串显）**：读路径全部支持
/// 可选 [childId] 过滤（null = 不过滤，仅迁移/老调用点用；仓储层一律传当前孩子，
/// 漏传即数据串孩子）。写路径（insert / updateRow）按行上 childId 落库不变。
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

  /// 待核销 + 排队中的申请（可选按孩子过滤）。
  Future<List<RedemptionRequest>> pendingAndQueued({String? childId}) {
    final query = select(redemptionRequests)
      ..where((r) => r.status.isIn(
          [RequestStatus.pending.index, RequestStatus.queued.index]));
    if (childId != null) {
      query.where((r) => r.childId.equals(childId));
    }
    return query.get();
  }

  /// 已核销的申请（status==verified）；排序交给仓储层，避免 drift orderBy 抖动。
  Future<List<RedemptionRequest>> verified({String? childId}) {
    final query = select(redemptionRequests)
      ..where((r) => r.status.equals(RequestStatus.verified.index));
    if (childId != null) {
      query.where((r) => r.childId.equals(childId));
    }
    return query.get();
  }

  /// 已拒绝的申请（status==rejected），供孩子端「拒绝对称通知」使用（B4）。
  Future<List<RedemptionRequest>> rejected({String? childId}) {
    final query = select(redemptionRequests)
      ..where((r) => r.status.equals(RequestStatus.rejected.index));
    if (childId != null) {
      query.where((r) => r.childId.equals(childId));
    }
    return query.get();
  }

  /// 某周排队中的申请（status==queued 且 requestedAt >= 当周周一）。
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey,
      {String? childId}) {
    final query = select(redemptionRequests)
      ..where((r) =>
          r.status.equals(RequestStatus.queued.index) &
          r.requestedAt.isBiggerOrEqualValue(DateTime.parse(weekKey)));
    if (childId != null) {
      query.where((r) => r.childId.equals(childId));
    }
    return query.get();
  }
}

/// 月度池 DAO（§3.2）。
///
/// C90 期 2 第二批：monthly_pools 已按孩子隔离（schemaVersion 28 表重建，
/// 复合主键 (month_key, child_id)）—— 方法带可选 [childId]（null = 不过滤 /
/// 不补写，仅迁移与老调用点用；仓储层一律传当前孩子）。
@DriftAccessor(tables: [MonthlyPools])
class MonthlyPoolDao extends DatabaseAccessor<AppDatabase>
    with _$MonthlyPoolDaoMixin {
  MonthlyPoolDao(super.db);

  /// 按复合主键 (monthKey, childId) 读取单条，不存在返回 null。
  Future<MonthlyPool?> of(String monthKey, {String? childId}) {
    final query = select(monthlyPools)..where((p) => p.monthKey.equals(monthKey));
    if (childId != null) {
      query.where((p) => p.childId.equals(childId));
    }
    return query.getSingleOrNull();
  }

  /// 插入或更新（按复合主键 (monthKey, childId) 冲突合并）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> upsert(MonthlyPoolsCompanion row, {String? childId}) {
    final MonthlyPoolsCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(monthlyPools).insertOnConflictUpdate(full);
  }
}

/// 冷却计数 DAO（§3.2）。
///
/// C90 期 2 第二批：cooldown_counters 已按孩子隔离（schemaVersion 28 表重建，
/// 复合主键 (template_id, period, child_id)）—— 方法带可选 [childId]
///（null = 不过滤 / 不补写，仅迁移与老调用点用；仓储层一律传当前孩子）。
@DriftAccessor(tables: [CooldownCounters])
class CooldownCounterDao extends DatabaseAccessor<AppDatabase>
    with _$CooldownCounterDaoMixin {
  CooldownCounterDao(super.db);

  /// 先确保行存在，再 used_count + 1。
  Future<void> bump(String templateId, CooldownPeriod period,
      {String? childId}) async {
    final int existing = await count(templateId, period, childId: childId);
    if (existing == 0) {
      await into(cooldownCounters).insert(
        CooldownCountersCompanion(
          templateId: Value(templateId),
          period: Value(period.index),
          childId: childId == null ? const Value.absent() : Value(childId),
        ),
      );
    }
    // 复合主键含 child_id：UPDATE 同键定位（与 resolveCheckInIfStatus 同款
    // 「null = 不加过滤」约定，仅老调用点走该分支）。
    if (childId == null) {
      await customStatement(
        'UPDATE cooldown_counters SET used_count = used_count + 1 '
        'WHERE template_id = ? AND period = ?',
        [templateId, period.index],
      );
    } else {
      await customStatement(
        'UPDATE cooldown_counters SET used_count = used_count + 1 '
        'WHERE template_id = ? AND period = ? AND child_id = ?',
        [templateId, period.index, childId],
      );
    }
  }

  /// 返回该 (templateId, period, childId) 行的 used_count（无记录视为 0）。
  /// (templateId, period, childId) 为复合主键，每个孩子至多一行。
  Future<int> count(String templateId, CooldownPeriod period,
      {String? childId}) async {
    final query = select(cooldownCounters)
      ..where((c) =>
          c.templateId.equals(templateId) & c.period.equals(period.index));
    if (childId != null) {
      query.where((c) => c.childId.equals(childId));
    }
    final CooldownCounter? row = await query.getSingleOrNull();
    return row?.usedCount ?? 0;
  }

  /// 冲减 used_count（下限 0），用于拒绝/撤销兑换时回退「已领次数」。
  ///
  /// 行不存在时静默跳过（createRequest 一定先 bump 确保行存在，正常不会触发，
  /// 但拒绝路径独立调用以防边界情况下出现负计数）。
  /// ⚠️ 按孩子过滤：冲减**绝不动**另一孩子的计数。
  Future<void> decrement(String templateId, CooldownPeriod period,
      {String? childId}) async {
    final int existing = await count(templateId, period, childId: childId);
    if (existing <= 0) return; // 无记录即 0，无需操作
    if (childId == null) {
      await customStatement(
        'UPDATE cooldown_counters SET used_count = MAX(0, used_count - 1) '
        'WHERE template_id = ? AND period = ?',
        [templateId, period.index],
      );
    } else {
      await customStatement(
        'UPDATE cooldown_counters SET used_count = MAX(0, used_count - 1) '
        'WHERE template_id = ? AND period = ? AND child_id = ?',
        [templateId, period.index, childId],
      );
    }
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

/// 少儿护眼记录 DAO（玄参 2026-10-09：家长报告护眼统计）。
///
/// 只追加 + 聚合，不修改不删除；聚合口径见 [EyeCareLogRepository]。
/// C90 期 2：方法带可选 [childId]（null = 不过滤 / 不补写，仅迁移与老调用点用；
/// 仓储层一律传当前孩子，漏传即数据串孩子）。
@DriftAccessor(tables: [EyeCareLogs])
class EyeCareLogDao extends DatabaseAccessor<AppDatabase>
    with _$EyeCareLogDaoMixin {
  EyeCareLogDao(super.db);

  /// 追加一条护眼记录（id 冲突时忽略 —— Uuid 碰撞即数据缺陷，不覆盖旧事实）。
  ///
  /// [childId] 非空且 row 未显式带 childId 时补写（C90 期 2：落当前孩子）。
  Future<void> appendRow(EyeCareLogsCompanion row, {String? childId}) {
    final EyeCareLogsCompanion full =
        (childId == null || row.childId.present)
            ? row
            : row.copyWith(childId: Value(childId));
    return into(eyeCareLogs).insert(full, mode: InsertMode.insertOrIgnore);
  }

  /// 指定 result 的累计条数（result = EyeCareResultType.name）。
  Future<int> countByResult(String result, {String? childId}) async {
    final Expression<int> cnt = eyeCareLogs.id.count();
    final query = selectOnly(eyeCareLogs)
      ..addColumns([cnt])
      ..where(eyeCareLogs.result.equals(result));
    if (childId != null) {
      query.where(eyeCareLogs.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(cnt) ?? 0;
  }

  /// 指定 result 的观看秒数合计（skipped 的部分观看时长；completed 恒为全片长，
  /// 报告侧用「账本完成次数 × kEyeCareDurationSeconds」口径更准、防双重计数）。
  Future<int> sumWatchedSecondsByResult(String result,
      {String? childId}) async {
    final Expression<int> sum = eyeCareLogs.watchedSeconds.sum();
    final query = selectOnly(eyeCareLogs)
      ..addColumns([sum])
      ..where(eyeCareLogs.result.equals(result));
    if (childId != null) {
      query.where(eyeCareLogs.childId.equals(childId));
    }
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }
}

/// 孩子档案 DAO（C90 期 1，玄参 2026-10-17 拍板）。
///
/// 全部经 [ChildProfileLocalRepository] 供 [AccountService] 消费；口径
///（切换入口只在家长天地、期 2 数据隔离、只拦新增不删档案）见 tables.dart
/// `ChildProfiles` 注释。
@DriftAccessor(tables: [ChildProfiles])
class ChildProfileDao extends DatabaseAccessor<AppDatabase>
    with _$ChildProfileDaoMixin {
  ChildProfileDao(super.db);

  /// 全部档案（按创建时间升序 —— 「第一个孩子」= 最早建的默认孩子）。
  Future<List<ChildProfileRow>> all() =>
      (select(childProfiles)
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  /// 按主键（id）读取单个档案，不存在返回 null。
  Future<ChildProfileRow?> byId(String id) =>
      (select(childProfiles)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// 插入或更新（按主键冲突合并）。
  Future<void> upsert(ChildProfilesCompanion row) =>
      into(childProfiles).insertOnConflictUpdate(row);

  /// 档案总数（门控配额核算用，只读计数）。
  Future<int> count() async {
    final Expression<int> cnt = childProfiles.id.count();
    final row =
        await (selectOnly(childProfiles)..addColumns([cnt])).getSingle();
    return row.read(cnt) ?? 0;
  }

  /// 更新档案（改名 / 调年龄段；id 与 createdAt 不变，C90 期 1 追加）。
  ///
  /// C90-C：可选 [avatar]（null = 不改；[kChildAvatarSun] = 阳光，否则物种 id）。
  Future<void> updateProfile(
    String id, {
    required String name,
    required int ageTier,
    String? avatar,
  }) =>
      (update(childProfiles)..where((t) => t.id.equals(id))).write(
        ChildProfilesCompanion(
          name: Value(name),
          ageTier: Value(ageTier),
          avatar: avatar == null ? const Value.absent() : Value(avatar),
        ),
      );

  /// 按 id 删除档案（家长 PIN 复核由调用方负责，C90 期 1 追加）。
  Future<void> deleteById(String id) =>
      (delete(childProfiles)..where((t) => t.id.equals(id))).go();
}
