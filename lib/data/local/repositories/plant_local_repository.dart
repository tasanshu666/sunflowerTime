/// 本地植物仓储（实现 domain 接口，§2.1 / §3.1 / §4.6）。
///
/// 真实 Drift 实现，替换 M0 的 `PlantLocalRepositoryStub`（M3 T01）。
/// 物种为静态种子（[kSeedPlantSpecies]），不落库；植物实例落 `Plants` 表。
library plant_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';

/// 本地植物仓储：实现植物实例读写（[PlantRepository]）与成株后循环玩法 Batch 1 的
/// 奖励账目（[BloomRewardRepository]），二者共用同一 `AppDatabase`。
class PlantLocalRepository implements PlantRepository, BloomRewardRepository {
  final db.AppDatabase _db;

  PlantLocalRepository(this._db);

  @override
  Future<List<Plant>> plants() async =>
      (await _db.plantDao.all()).map(_toPlant).toList();

  @override
  Future<Plant?> plant(String id) async {
    final db.Plant? row = await _db.plantDao.byId(id);
    return row == null ? null : _toPlant(row);
  }

  @override
  Future<void> savePlant(Plant plant) =>
      _db.plantDao.upsert(_toCompanion(plant));

  @override
  Future<void> deletePlant(String id) => _db.plantDao.deleteById(id);

  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;

  // ── BloomRewardRepository ────────────────────────────────────────────────

  @override
  Future<int> premiumFragmentBalance() => _db.bloomRewardDao.fragmentBalance();

  @override
  Future<void> setPremiumFragmentBalance(int balance) =>
      _db.bloomRewardDao.setFragmentBalance(balance);

  @override
  Future<Set<String>> unlockedSpeciesIds() async =>
      (await _db.bloomRewardDao.unlockedSpeciesIds()).toSet();

  @override
  Future<void> unlockSpecies(String speciesId) =>
      _db.bloomRewardDao.unlockSpecies(speciesId);

  @override
  Future<void> consumeUnlock(String speciesId) =>
      _db.bloomRewardDao.consumeUnlock(speciesId);

  @override
  Future<void> insertPendingBloomReward(PendingBloomReward reward) =>
      _db.bloomRewardDao.insertPending(db.PendingBloomRewardsCompanion(
        id: Value(reward.id),
        plantId: Value(reward.plantId),
        dueAt: Value(reward.dueAt),
        rewardKind: Value(reward.rewardKind),
        claimed: Value(reward.claimed),
        rewardSunlight: Value(reward.rewardSunlight),
        rewardFragments: Value(reward.rewardFragments),
        rewardSpeciesId: Value(reward.rewardSpeciesId),
      ));

  @override
  Future<List<PendingBloomReward>> pendingBloomRewardsDue(DateTime now) async {
    final List<db.PendingBloomRewardRow> rows =
        await _db.bloomRewardDao.pendingDue(now);
    return rows
        .map((db.PendingBloomRewardRow r) => PendingBloomReward(
              id: r.id,
              plantId: r.plantId,
              dueAt: r.dueAt,
              rewardKind: r.rewardKind,
              claimed: r.claimed,
              rewardSunlight: r.rewardSunlight,
              rewardFragments: r.rewardFragments,
              rewardSpeciesId: r.rewardSpeciesId,
            ))
        .toList();
  }

  @override
  Future<void> markPendingBloomRewardClaimed(String id) =>
      _db.bloomRewardDao.markClaimed(id);

  @override
  Future<void> updatePendingRewardContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  }) =>
      _db.bloomRewardDao.updatePendingContent(
        id: id,
        rewardSunlight: rewardSunlight,
        rewardFragments: rewardFragments,
        rewardSpeciesId: rewardSpeciesId,
      );
}

/// [db.Plant]（Drift 数据类）→ 领域 [Plant]。
Plant _toPlant(db.Plant r) => Plant(
      id: r.id,
      speciesId: r.speciesId,
      potIndex: r.potIndex,
      stage: PlantStage.values[r.stage],
      stageStartedAt: r.stageStartedAt,
      growthProgress: r.growthProgress,
      growthFactor: r.growthFactor,
      waterUsed: r.waterUsed,
      fertilizerUsed: r.fertilizerUsed,
      status: PlantStatus.values[r.status],
      plantedAt: r.plantedAt,
      lastWaterAt: r.lastWaterAt,
      wiltedAt: r.wiltedAt,
      deadAt: r.deadAt,
      bloomedAt: r.bloomedAt,
      bloomCount: r.bloomCount,
      mood: PlantMood.values[r.mood],
      weedAt: r.weedAt,
      pestAt: r.pestAt,
      weedPestRollDay: r.weedPestRollDay,
    );

/// 领域 [Plant] → [db.PlantsCompanion]（append-only 落库）。
db.PlantsCompanion _toCompanion(Plant p) => db.PlantsCompanion(
      id: Value(p.id),
      speciesId: Value(p.speciesId),
      potIndex: Value(p.potIndex),
      stage: Value(p.stage.index),
      stageStartedAt: Value(p.stageStartedAt),
      growthProgress: Value(p.growthProgress),
      growthFactor: Value(p.growthFactor),
      waterUsed: Value(p.waterUsed),
      fertilizerUsed: Value(p.fertilizerUsed),
      status: Value(p.status.index),
      plantedAt: Value(p.plantedAt),
      lastWaterAt: Value(p.lastWaterAt),
      wiltedAt: Value(p.wiltedAt),
      deadAt: Value(p.deadAt),
      bloomedAt: Value(p.bloomedAt),
      bloomCount: Value(p.bloomCount),
      mood: Value(p.mood.index),
      weedAt: Value(p.weedAt),
      pestAt: Value(p.pestAt),
      weedPestRollDay: Value(p.weedPestRollDay),
    );
