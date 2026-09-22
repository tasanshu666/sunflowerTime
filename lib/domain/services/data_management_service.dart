/// 数据管理服务（M3 T03，§10.4 C5 合规删除入口）。
///
/// 一键删除全部本地数据：清空 Drift 全表（含 settings 单行）+ 系统安全区 PIN +
/// SharedPreferences（夸夸语录 `praise_notes_v1`、核销回执 ack id 等）。
/// 导出成册（§10.4 先导后清）留 V2，本服务只负责「清」。
library data_management_service;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/secure_store.dart';

/// 本地数据清除（合规 §10.4 C5：家长拥有删除权）。
class DataManagementService {
  final AppDatabase _db;
  final SecureStore _secure;
  final SharedPreferences _prefs;

  DataManagementService({
    required AppDatabase db,
    required SecureStore secure,
    required SharedPreferences prefs,
  })  : _db = db,
        _secure = secure,
        _prefs = prefs;

  /// 删除全部本地数据（家长确认后调用）。
  ///
  /// 顺序：① Drift 全表清空（[AppDatabase.deleteEverything]，含 settings 单行）；
  /// ② 系统安全区 PIN 清除；③ SharedPreferences 全部键清除（夸夸语录 / ack 标记等）。
  /// 调用方应在清库后引导重新初始化（如回到同意流 / 登录），由 [SettingsLocalRepository]
  /// 在下次读取时按需重建默认设置。
  Future<void> clearAll() async {
    await _db.deleteEverything();
    await _secure.clear();
    await _prefs.clear();
  }
}
