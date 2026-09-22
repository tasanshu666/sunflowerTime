import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 植物仓储抽象（§2.1 / §3.1 / §4.6 软绑定）。
abstract class PlantRepository {
  /// 全部植物（含枯萎 / 死亡记录，调用方按需按 potIndex/status 过滤）。
  Future<List<Plant>> plants();

  /// 按主键（id）读取单株，不存在返回 null。
  Future<Plant?> plant(String id);

  /// 插入或更新单株。
  Future<void> savePlant(Plant plant);

  /// 删除单株（按 id）。
  Future<void> deletePlant(String id);

  /// 全部植物物种（M3 静态种子，见 [kSeedPlantSpecies]）。
  Future<List<PlantSpecies>> species();
}
