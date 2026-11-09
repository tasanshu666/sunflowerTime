/// 花园守卫「当日状态」的 SharedPreferences 实现（`data/local`，插件收敛层）。
///
/// ## 为什么插件只在这一层
/// `shared_preferences` 是 Flutter 插件：`domain` 一旦 import 就破了「纯 Dart →
/// 可被 `package:test` 直接单测」的底线，故由本类实现 `GuardStateStore` 抽象
/// （同 `focus_level_prefs_store.dart` / `settings_store.dart` 既有先例）。
///
/// ## 🔴 键名必须带 childId 后缀
/// 实际键 = `kGuardDayStatePrefPrefix + childId`。`SharedPreferences` 是设备级，
/// 而守卫数据是 childId 级 —— 不带后缀会让「A 的小偷出现在 B 的今日页、A 的
/// 浇水券被 B 用掉」。键名拼装**只**在 [keyOf] 一处。
///
/// ## 一天一条，不按天累积
/// 本键只存**当前**那一条状态（`dayKey` 写在 JSON 里）。跨天后旧存档保留到
/// `GuardService.expire()` 结算完再 [clear] —— 所以本类**不**自动删、也**不**自动
/// 重置过期存档（见 `guard_state_store.dart` 文件头「read 的口径」）。
library guard_state_prefs_store;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';

class GuardStatePrefsStore implements GuardStateStore {
  GuardStatePrefsStore(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;

  /// 时钟（测试可注入固定时间；生产默认 `DateTime.now`）。
  ///
  /// 只在「没有存档 ⇒ 用今天当 `dayKey` 兜底」这一处用到：本类从不判断、
  /// 也从不改写归档所属的那一天。
  final DateTime Function() _clock;

  /// [childId] 对应的 prefs 键（🔴 键名拼装的唯一一处）。
  static String keyOf(String childId) => '$kGuardDayStatePrefPrefix$childId';

  @override
  Future<GuardDayState> read(String childId) async {
    final String today = dayKey(_clock());
    final String? raw = _prefs.getString(keyOf(childId));
    if (raw == null || raw.isEmpty) return GuardDayState.empty(today);
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return GuardDayState.empty(today);
      return GuardDayState.fromJson(
        Map<String, Object?>.from(decoded),
        fallbackDayKey: today,
      );
    } catch (_) {
      // 存档被写坏（手工改过 / 半截写入）→ 当作「没有存档」：
      // 最坏结果是今天没有小偷，绝不能让孩子打不开今日页。
      return GuardDayState.empty(today);
    }
  }

  @override
  Future<void> write(String childId, GuardDayState state) async {
    await _prefs.setString(keyOf(childId), jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear(String childId) async {
    await _prefs.remove(keyOf(childId));
  }
}
