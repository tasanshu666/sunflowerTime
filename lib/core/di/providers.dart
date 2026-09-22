/// 全局装配（§2.1）。领域服务只依赖 Repository 接口；此处注入本地实现，
/// G2+ 切换云同步时仅需在此替换实现，领域层零改动。
library providers;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/weekly_pool_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/secure_store.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/domain/services/data_management_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
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
  (ref) => TaskLocalRepository(ref.watch(appDatabaseProvider)),
);
final plantRepositoryProvider = Provider<PlantRepository>(
  (ref) => PlantLocalRepository(ref.watch(appDatabaseProvider)),
);
final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) => RewardLocalRepository(ref.watch(appDatabaseProvider)),
);
final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingLocalRepository(ref.watch(appDatabaseProvider)),
);
final weeklyPoolRepositoryProvider = Provider<WeeklyPoolRepository>(
  (ref) => WeeklyPoolLocalRepository(ref.watch(appDatabaseProvider)),
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

/// 单例音频服务（M2 音频模块，§1.1）。跨 focus/settle 页面复用，避免重复 new 播放器。
final audioServiceProvider = Provider<AudioService>((ref) => AudioService.instance);

// ── M2 经济与商店核销：服务装配（T-C 独占本段）────────────────────────────

/// 账号服务（Plan B 单机版留桩，§3.2 / §7.6）。
final accountServiceProvider = Provider<AccountService>((ref) => AccountService());

/// 周阳光池服务（§3.2 / §4.1）：取/建/重置周池 + C5 上限计算。
final weeklyPoolServiceProvider = Provider<WeeklyPoolService>((ref) =>
    WeeklyPoolService(ref.watch(weeklyPoolRepositoryProvider),
        ref.watch(settingsRepositoryProvider), ref.watch(trackingRepositoryProvider)));

/// 经济数据修订号（M2 家长-孩子同步）。
///
/// 任何会改变孩子端经济展示的操作成功后自增：孩子端兑换、家长端核销、家长端拒绝。
/// 孩子端商店页的缓存 `FutureProvider`（storeLoad / storeBalance）`watch` 本值，
/// 修订号一变即重算 —— 否则家长端处理完返回孩子端，商店仍显示旧缓存
/// （待核销总额不变、卡片仍停在「待家长核销」禁用态），即真机 BUG「拒绝后不同步」。
final economyRevisionProvider = StateProvider<int>((ref) => 0);

/// 兑换编排服务（§3.2 / §4.1–4.3）：submit / verify / releaseQueue / pendingList。
final redemptionOrchestrationServiceProvider =
    Provider<RedemptionOrchestrationService>((ref) =>
        RedemptionOrchestrationService(
          reward: ref.watch(rewardRepositoryProvider),
          pools: ref.watch(weeklyPoolServiceProvider),
          ledger: ref.watch(sunlightRepositoryProvider),
          tracking: ref.watch(trackingRepositoryProvider),
          account: ref.watch(accountServiceProvider),
          settings: ref.watch(settingsRepositoryProvider),
        ));

/// 植物养成服务（M3 T02）：种植 / 浇水 / 施肥 / 救回 / 扩容 / 计时成长。
///
/// 与经济账本同源（[SunlightRepository.append]），植物消耗 / 退款可追溯对账。
final plantGrowthServiceProvider = Provider<PlantGrowthService>(
  (ref) => PlantGrowthService(
    plants: ref.watch(plantRepositoryProvider),
    focus: ref.watch(focusRepositoryProvider),
    ledger: ref.watch(sunlightRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// 专注报告服务（M3 T04）：周/日专注分布、有效专注日、稳定性趋势（本地聚合）。
final focusReportServiceProvider = Provider<FocusReportService>(
  (ref) => FocusReportService(focus: ref.watch(focusRepositoryProvider)),
);

/// 本地数据清除服务（M3 T03，§10.4 C5 合规删除入口）。
///
/// 一键删除全部本地数据：Drift 全表 + 系统安全区 PIN + SharedPreferences。
final dataManagementServiceProvider = Provider<DataManagementService>(
  (ref) => DataManagementService(
    db: ref.watch(appDatabaseProvider),
    secure: ref.watch(secureStoreProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  ),
);

/// 任务打卡服务（M4，§4.4 / §4.5）：打卡即刻发阳光，按当日累计过软顶只补差额。
final taskCheckInServiceProvider = Provider<TaskCheckInService>(
  (ref) => TaskCheckInService(
    tasks: ref.watch(taskRepositoryProvider),
    ledger: ref.watch(sunlightRepositoryProvider),
    focus: ref.watch(focusRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);
