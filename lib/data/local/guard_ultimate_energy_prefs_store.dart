/// 大招能量持久化（SharedPreferences，data 层唯一实现）。
///
/// 独立于旧 `guard_energy_v1_*`：
/// * 状态 key = `guard_ultimate_v1_<childId>`（[keyOf]）；
/// * 去重集合 key = `guard_ultimate_v1_credited_<childId>`（[creditedKeyOf]）。
///
/// 与旧能量同为「设备级 prefs + childId 后缀」策略（PRD §10-B5），
/// 但 key 前缀物理隔离 —— schemaVersion 恒 32，零表/列变更（架构 §8-S1）。
library guard_ultimate_energy_prefs_store;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';
import 'package:sunflower_time/domain/repositories/guard_ultimate_energy_store.dart';

class GuardUltimateEnergyPrefsStore implements GuardUltimateEnergyStore {
  GuardUltimateEnergyPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  /// 状态 key 的唯一装配处。
  static String keyOf(String childId) => '$kGuardUltimatePrefPrefix$childId';

  /// 去重集合 key 的唯一装配处。
  static String creditedKeyOf(String childId) =>
      '${kGuardUltimatePrefPrefix}credited_$childId';

  @override
  Future<UltimateEnergy> read(String childId) async {
    final String? raw = _prefs.getString(keyOf(childId));
    if (raw == null || raw.isEmpty) return UltimateEnergy.empty;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return UltimateEnergy.empty;
      return UltimateEnergy.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return UltimateEnergy.empty;
    }
  }

  @override
  Future<void> write(String childId, UltimateEnergy energy) async {
    await _prefs.setString(keyOf(childId), jsonEncode(energy.toJson()));
  }

  @override
  Future<Set<String>> readCreditedSessionIds(String childId) async {
    final String? raw = _prefs.getString(creditedKeyOf(childId));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return <String>{
        for (final Object? id in decoded)
          if (id is String && id.isNotEmpty) id,
      };
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<void> writeCreditedSessionIds(String childId, Set<String> ids) async {
    final List<String> sorted = ids.toList()..sort();
    await _prefs.setString(creditedKeyOf(childId), jsonEncode(sorted));
  }
}
