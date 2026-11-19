/// In-memory [GuardEnergyStore] for widget tests that override the guard
/// service dependencies but do not want to boot SharedPreferences.
library in_memory_guard_energy_store;

import 'package:sunflower_time/domain/entities/guard_energy.dart';
import 'package:sunflower_time/domain/repositories/guard_energy_store.dart';

class InMemoryGuardEnergyStore implements GuardEnergyStore {
  final Map<String, GuardEnergy> byChild = <String, GuardEnergy>{};

  @override
  Future<GuardEnergy> read(String childId) async =>
      byChild[childId] ?? GuardEnergy.empty;

  @override
  Future<void> write(String childId, GuardEnergy energy) async {
    byChild[childId] = energy;
  }
}
