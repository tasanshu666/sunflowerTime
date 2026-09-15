import 'package:sunflower_time/domain/entities/settings.dart';

/// 设置仓储抽象（§2.1）。MVP 用 LocalSettingsRepository；G2+ 可换 SyncedSettingsRepository。
abstract class SettingsRepository {
  /// 读取全局设置（夜间边界唯一值来自此处，§6.1）。
  Future<AppSettings> getSettings();

  /// 写入全局设置。
  Future<void> saveSettings(AppSettings settings);
}
