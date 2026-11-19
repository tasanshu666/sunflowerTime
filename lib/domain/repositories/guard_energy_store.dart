/// Persistent guard-energy storage abstraction (pure Dart, zero plugins).
///
/// This is intentionally **not** part of `GuardStateStore`: that interface owns
/// exactly one day-keyed record and is cleared by `GuardService.expire()`.
/// Energy is a long-lived balance; mixing the two would make a cross-day
/// settlement silently wipe the child's saved points.
library guard_energy_store;

import 'package:sunflower_time/domain/entities/guard_energy.dart';

/// Read/write a child's persistent guard energy.
abstract class GuardEnergyStore {
  /// Returns `GuardEnergy.empty` when no record exists or the record is broken.
  Future<GuardEnergy> read(String childId);

  /// Overwrites the child's energy snapshot (balance + credited session ids).
  Future<void> write(String childId, GuardEnergy energy);
}
