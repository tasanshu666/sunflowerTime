/// M0 阶段未实现的本地仓储桩（Task / Plant / Reward / Tracking）。
///
/// 仅返回空/默认值以保证 DI 可装配、App 可启动；真实实现随 M2/M3 接入
/// Drift DAO 后替换（§2.1 抽象不变，实现替换即可，领域服务零改动）。
///
/// 注：Focus 仓储已在 M1 落地为真实实现 `FocusLocalRepository`（T10），
/// 其桩 `FocusLocalRepositoryStub` 已移除。
library local_stub_repositories;

import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';

class TaskLocalRepositoryStub implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => const [];
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => const [];
}

class PlantLocalRepositoryStub implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => const [];
  @override
  Future<List<PlantSpecies>> species() async => const [];
  @override
  Future<void> savePlant(Plant plant) async {}
}

class RewardLocalRepositoryStub implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => const [];
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> createRequest(RedemptionRequest request) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async => const [];
  @override
  Future<void> updateRequest(RedemptionRequest request) async {}
}

class TrackingLocalRepositoryStub implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent event) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async => const [];
}
