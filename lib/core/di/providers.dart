/// 全局装配（§2.1）。领域服务只依赖 Repository 接口；此处注入本地实现，
/// G2+ 切换云同步时仅需在此替换实现，领域层零改动。
library providers;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
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
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';
import 'package:sunflower_time/domain/entities/settings.dart';

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
  (ref) => FocusLocalRepository(ref.watch(appDatabaseProvider)),
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

/// 阳光记账与软顶服务（T10，§4.5 / §3.2）。专注页结算时读取。
///
/// 注：专注引擎 [FocusEngine] 与在场检测 [PresenceDetector] 为**单场生命周期对象**，
/// 由专注页在 `initState` 中按本次 planned 时长创建、`dispose` 时释放，故不在此装配。
final sunlightServiceProvider = Provider<SunlightService>(
  (ref) => SunlightService(
    ledger: ref.watch(sunlightRepositoryProvider),
    focus: ref.watch(focusRepositoryProvider),
  ),
);

/// 家长 PIN 是否已设置（供路由守卫 / 家长端入口读取）。
final pinSetupProvider = FutureProvider<bool>(
  (ref) => ref.watch(secureStoreProvider).hasPin(),
);

/// 全局设置（FutureProvider 包装 [SettingsRepository]，供 UI 异步读取）。
///
/// 防沉迷页/入口页读取休息时长等字段时复用，避免各自直接拿 Repository。
final settingsProvider = FutureProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).getSettings(),
);

/// 防沉迷服务（T11，§6.1 / §6.3）。
///
/// 领域服务零依赖，此处装配为单例 Provider，便于替换与单测。
final antiAddictionServiceProvider = Provider<AntiAddictionService>(
  (ref) => AntiAddictionService(),
);

/// 本次「已休息满足」标记（T11，§6.3）。
///
/// 休息页倒计时归零后置 true；入口页 evaluate 命中 restRequired 后放行，
/// 并在启动专注时清零（用完即焚）。
final restSatisfiedProvider = StateProvider<bool>((ref) => false);
