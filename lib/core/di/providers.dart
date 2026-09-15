/// 全局装配（§2.1）。领域服务只依赖 Repository 接口；此处注入本地实现，
/// G2+ 切换云同步时仅需在此替换实现，领域层零改动。
library providers;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/local_stub_repositories.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/secure_store.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';

/// SharedPreferences 实例（main 初始化后 override 注入，见 main.dart）。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider 必须在 main 中 override'),
);

/// 系统安全区（家长 PIN 哈希 + salt）。
final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

/// 加密本地库（Drift + SQLCipher，Lazy 打开）。
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

/// 首启同意标记存储（shared_preferences 封装）。
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

// ── Repository 装配 ───────────────────────────────────────────────
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsLocalRepository(ref.watch(appDatabaseProvider)),
);
final sunlightRepositoryProvider = Provider<SunlightRepository>(
  (ref) => SunlightLocalRepository(ref.watch(appDatabaseProvider)),
);
final focusRepositoryProvider = Provider<FocusRepository>(
  (ref) => FocusLocalRepositoryStub(),
);
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskLocalRepositoryStub(),
);
final plantRepositoryProvider = Provider<PlantRepository>(
  (ref) => PlantLocalRepositoryStub(),
);
final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) => RewardLocalRepositoryStub(),
);
final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingLocalRepositoryStub(),
);

/// 家长 PIN 是否已设置（供路由守卫 / 家长端入口读取）。
final pinSetupProvider = FutureProvider<bool>(
  (ref) => ref.watch(secureStoreProvider).hasPin(),
);
