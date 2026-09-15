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
}
