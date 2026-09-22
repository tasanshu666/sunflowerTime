/// M0 阶段未实现的本地仓储桩（Task / Plant）。
///
/// 仅返回空/默认值以保证 DI 可装配、App 可启动；真实实现随 M3 接入。
///
/// 注：Focus 仓储已在 M1 落地为真实实现 `FocusLocalRepository`（T10），
/// 其桩 `FocusLocalRepositoryStub` 已移除。
/// Reward / Tracking 仓储已在 M2 T-A 落地为真实实现并移除其桩。
library local_stub_repositories;

import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';

class TaskLocalRepositoryStub implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => const [];
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => const [];
  @override
  Future<int> totalCheckInCount() async => 0;
}

class PlantLocalRepositoryStub implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => const [];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<List<PlantSpecies>> species() async => const [];
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
}
