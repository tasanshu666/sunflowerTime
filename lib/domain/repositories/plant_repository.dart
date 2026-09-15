import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 植物仓储抽象（§2.1 / §3.1 / §4.6 软绑定）。
abstract class PlantRepository {
  Future<List<Plant>> plants();
  Future<List<PlantSpecies>> species();
  Future<void> savePlant(Plant plant);
}
