/// Persistent guard-energy store backed by SharedPreferences (data layer only).
///
/// Key = `kGuardEnergyPrefPrefix + childId`: a device-level store holding
/// child-level state must always carry the child id in its key. This key is
/// separate from `kGuardDayStatePrefPrefix`, so `GuardService.expire()` cannot
/// wipe the balance when it clears yesterday's day-state record.
library guard_energy_prefs_store;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_energy.dart';
import 'package:sunflower_time/domain/repositories/guard_energy_store.dart';

class GuardEnergyPrefsStore implements GuardEnergyStore {
  GuardEnergyPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  /// The only place where the prefs key is assembled.
  static String keyOf(String childId) => '$kGuardEnergyPrefPrefix$childId';

  @override
  Future<GuardEnergy> read(String childId) async {
    final String? raw = _prefs.getString(keyOf(childId));
    if (raw == null || raw.isEmpty) return GuardEnergy.empty;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return GuardEnergy.empty;
      return GuardEnergy.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return GuardEnergy.empty;
    }
  }

  @override
  Future<void> write(String childId, GuardEnergy energy) async {
    await _prefs.setString(keyOf(childId), jsonEncode(energy.toJson()));
  }
}
