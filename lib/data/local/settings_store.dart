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
}
