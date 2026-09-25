/// shared_preferences 封装（§1.1 简单 KV 设置）。
/// 当前仅承载「首次启动同意」标记；其余设置走 Drift settings 表。
library settings_store;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';

class SettingsStore {
  final SharedPreferences _sp;

  SettingsStore(this._sp);

  Future<bool> isFirstLaunchConsented() async =>
      _sp.getBool(kPrefFirstLaunchConsented) ?? false;

  Future<void> setFirstLaunchConsented(bool value) async =>
      _sp.setBool(kPrefFirstLaunchConsented, value);

  /// 孩子端已展示过的「家长核销成功」申请 id（默认空）。
  Future<List<String>> acknowledgedVerifyIds() async =>
      _sp.getStringList(kPrefAckedVerifyIds) ?? <String>[];

  /// 覆写「家长核销成功」已读 id 列表。
  Future<void> setAcknowledgedVerifyIds(List<String> ids) async =>
      _sp.setStringList(kPrefAckedVerifyIds, ids);

  /// 孩子端已展示过的「家长拒绝」申请 id（默认空，B4 对称通知去重）。
  Future<List<String>> acknowledgedRejectIds() async =>
      _sp.getStringList(kPrefAckedRejectIds) ?? <String>[];

  /// 覆写「家长拒绝」已读 id 列表。
  Future<void> setAcknowledgedRejectIds(List<String> ids) async =>
      _sp.setStringList(kPrefAckedRejectIds, ids);

  // ── P0 · A App 总使用时长（§6.1）：日键 + 当日累计秒 ──────────────────

  /// App 当日累计时长所属自然日 key（yyyy-MM-dd；无记录返回 null）。
  Future<String?> appUsageDate() async => _sp.getString(kPrefAppUsageDate);

  /// App 当日累计秒数（无记录默认 0）。
  Future<int> appUsageSeconds() async => _sp.getInt(kPrefAppUsageSeconds) ?? 0;

  /// 覆写 App 当日累计时长（日期 + 秒数）。
  Future<void> saveAppUsage({
    required String date,
    required int seconds,
  }) async {
    await _sp.setString(kPrefAppUsageDate, date);
    await _sp.setInt(kPrefAppUsageSeconds, seconds);
  }
}
