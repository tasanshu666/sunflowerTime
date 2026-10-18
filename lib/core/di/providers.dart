/// 全局装配（§2.1）。领域服务只依赖 Repository 接口；此处注入本地实现，
/// G2+ 切换云同步时仅需在此替换实现，领域层零改动。
library providers;

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/focus_level_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/weekly_pool_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/eye_care_log_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/entitlement_local_repository.dart';
import 'package:sunflower_time/data/local/secure_entitlement_store.dart';
import 'package:sunflower_time/data/local/secure_store.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/eye_care_log_repository.dart';
import 'package:sunflower_time/domain/repositories/child_profile_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/weekly_pool_service.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/domain/services/data_management_service.dart';
import 'package:sunflower_time/domain/services/memoir_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/presentation/child/state/app_usage_controller.dart';

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
// C90 期 2：六张隔离表（plants / focus_sessions / sunlight_ledgers / tasks /
// check_ins / eye_care_logs）的仓储实现统一注入 accountService —— 写入落当前
// 孩子、读取按当前孩子过滤；🔴 仓储接口签名一律不变。⚠️ 装配顺序无环：
// accountService → childProfileRepository / settingsRepository / prefs，
// 不回指下列任何仓储。
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsLocalRepository(ref.watch(appDatabaseProvider)),
);
final sunlightRepositoryProvider = Provider<SunlightRepository>(
  (ref) => SunlightLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);
final focusRepositoryProvider = Provider<FocusRepository>(
  (ref) => FocusLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);

/// 护眼记录仓储（玄参 2026-10-09：家长报告护眼统计）。
final eyeCareLogRepositoryProvider = Provider<EyeCareLogRepository>(
  (ref) => EyeCareLogLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);
/// 本地植物仓储单例（同时实现 [PlantRepository] 与 [BloomRewardRepository]，
/// 共用同一 [AppDatabase]）；两个接口各暴露一个 Provider 供不同消费方注入。
final plantLocalRepositoryProvider = Provider<PlantLocalRepository>(
  (ref) => PlantLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);
final plantRepositoryProvider = Provider<PlantRepository>(
  (ref) => ref.watch(plantLocalRepositoryProvider),
);
final bloomRewardRepositoryProvider = Provider<BloomRewardRepository>(
  (ref) => ref.watch(plantLocalRepositoryProvider),
);
final rewardRepositoryProvider = Provider<RewardRepository>(
  (ref) => RewardLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
);
final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingLocalRepository(ref.watch(appDatabaseProvider)),
);
final weeklyPoolRepositoryProvider = Provider<WeeklyPoolRepository>(
  (ref) => WeeklyPoolLocalRepository(ref.watch(appDatabaseProvider),
      account: ref.watch(accountServiceProvider)),
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

/// 孩子档案仓储（C90 期 1，Drift `child_profiles` 表实现）。
final childProfileRepositoryProvider = Provider<ChildProfileRepository>(
  (ref) => ChildProfileLocalRepository(ref.watch(appDatabaseProvider)),
);

/// 账号服务（C90 期 1 真实现：本地多档案 + 家长天地切换；云同步仍留桩，C1）。
///
/// 全量依赖注入后具备多档案能力；冷启动由 main 调 `initialize()`
///（空表补建默认孩子 + 从 SP 恢复活跃孩子）。
///
/// C90 期 2 第二批：更多消费方（reward / weeklyPool 仓储、childAgeTierProvider、
/// PlantGrowthService）watch 本 Provider —— 装配改为**容错**：任一依赖不可用
///（如测试环境未 override `sharedPreferencesProvider` / `appDatabaseProvider`）时
/// 回退**无参旧桩**（childId 恒 kChildIdDefault、currentProfile 恒 null，不触库），
/// 与「无参 = 旧行为」口径一致；生产 main 全量 override，永远走全量依赖分支。
final accountServiceProvider = Provider<AccountService>((ref) {
  try {
    return AccountService(
      children: ref.watch(childProfileRepositoryProvider),
      settings: ref.watch(settingsRepositoryProvider),
      prefs: ref.watch(sharedPreferencesProvider),
    );
  } catch (_) {
    return AccountService();
  }
});

/// 档案修订号（C90 期 1，仿 [economyRevisionProvider] 模式）。
///
/// 家长天地新建 / 切换孩子成功后自增；档案相关 UI（`ChildProfileBar` 等）
/// watch 本值即自动刷新，无需回调。期 2 数据隔离落地后，孩子端经济展示
/// 也应挂本修订号。
final childProfileRevisionProvider = StateProvider<int>((ref) => 0);

/// 当前孩子的年龄段（C90 期 2 第二批：**年龄段跟孩子走**，玄参拍板）。
///
/// 孩子端档位读取**单点**（专注页 / 花园页 / 商店页）：有当前孩子档案 → 档案
/// `ageTier`；无档案（AccountService 桩 / 未初始化）→ 回退全局 settings 单行
///（= 隔离前行为，测试 fake settings 照常生效）。家长端全局口径仍读
/// [settingsProvider]。watch [childProfileRevisionProvider] —— 家长改档 / 切孩子
/// 后自动重算。
final childAgeTierProvider = FutureProvider.autoDispose<AgeTier>((ref) async {
  ref.watch(childProfileRevisionProvider);
  final AccountService account = ref.watch(accountServiceProvider);
  try {
    // 🔴 有界等待（Q-E 先例）：档案源不可用 → 超时回退 null 落全局 settings 兜底。
    final ChildProfile? profile = await account
        .currentProfile()
        .timeout(kChildProfileReadTimeout);
    if (profile != null) return profile.ageTier;
  } catch (_) {
    // 档案源不可用 → 落下方全局 settings 兜底。
  }
  return (await ref.watch(settingsRepositoryProvider).getSettings()).ageTier;
});

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

/// 阳光余额（随 [economyRevisionProvider] 自动重算；花园页左上角胶囊展示用）。
///
/// 余额任何变化（养护扣费、家长赠予、兑换核销）都会自增经济修订号，本 Provider 随之
/// 重算，胶囊即时刷新，无需页面各自拉取。autoDispose：无胶囊展示时自动释放。
final sunlightBalanceProvider = FutureProvider.autoDispose<double>((ref) async {
  ref.watch(economyRevisionProvider);
  return ref.read(sunlightRepositoryProvider).balance();
});

/// C77 · 当前称号专属属性（花园 / 护眼 / 详情卡 / 演出 / 结算共用，单实例）。
///
/// = `perkOfLevel(levelOfMinutes(totalFocusMinutes))` —— **唯一来源**（设计 §3.4）；
/// 输入是**原始等级**（不是已结算等级 / SP 锚点）。
///
/// C80 · **门控反转（废止 C77 P4「免费 / 买断一致」）**：`watch` [entitlementProvider]，
/// free 档**短路**回 [PlantPerk.none]（不查库），premium 档才按等级累积取属性。
/// 购买成功写 [entitlementProvider]（StateProvider），本 Provider 已 watch 之 → 自动重算，
/// 详情卡 / 花园等消费方零回调代码即刷新。随 [economyRevisionProvider]
/// （跨页刷新总线）重算：专注结算 / 升级后回到花园即拿到新属性。
///
/// ⚠️ 性能（Q-J）：`totalStats()` 全量取行内存求和；花园单株动作各读一次可接受，
/// 批量路径（一键）由页面**只读一次**后经 `PlantGrowthService` 参数下发（§5.2）。
final currentPlantPerkProvider = FutureProvider<PlantPerk>((ref) async {
  ref.watch(economyRevisionProvider);
  // C80 门控：免费档安全默认 = 无属性（异常回退 none ≡ 免费语义，双重一致）。
  if (!featureAllowedFor(
      FeatureKey.titlePerks, ref.watch(entitlementProvider).tier)) {
    return PlantPerk.none;
  }
  // 🔴 有界等待（Q-E）：仓储不可用 / 极慢 → 超时回退 [PlantPerk.none]，
  // 绝不把「读属性」变成会挂住 UI 流程（护眼奖励 / 结算展示）的 await。
  try {
    final stats = await ref
        .read(focusRepositoryProvider)
        .totalStats()
        .timeout(kPlantPerkProviderTimeout);
    return perkOfLevel(levelOfMinutes(stats.totalFocusMinutes));
  } catch (_) {
    return PlantPerk.none;
  }
});

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
///
/// 成株后循环玩法 Batch 1：额外注入 [BloomRewardRepository]（开花奖励 × 碎片解锁 ×
/// 第二段待收集队列）；`onEconomyChanged` 在发放开花 / 第二段奖励后自增 `economyRevisionProvider`
/// 刷新孩子端经济展示（域层不直接依赖 Riverpod）。
final plantGrowthServiceProvider = Provider<PlantGrowthService>(
  (ref) => PlantGrowthService(
    plants: ref.watch(plantRepositoryProvider),
    focus: ref.watch(focusRepositoryProvider),
    ledger: ref.watch(sunlightRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    bloomRewards: ref.watch(bloomRewardRepositoryProvider),
    // C90 期 2：扩容档位判定（年龄段）跟当前孩子走（可选注入，域单测零改动）。
    account: ref.watch(accountServiceProvider),
    // 阶段 4 域层防线：花盆扩容按档位上限（免费 4 / 买断 12），防绕过 UI 顶满。
    entitlement: ref.watch(entitlementServiceProvider),
    onEconomyChanged: () =>
        ref.read(economyRevisionProvider.notifier).state++,
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

// ── P0 · A App 总时长防沉迷（§6.1）──────────────────────────────────

/// App 总使用时长控制器（娱乐 tab 前台计时 + 到顶判定；见 [AppUsageController]）。
final appUsageControllerProvider =
    NotifierProvider<AppUsageController, AppUsageState>(AppUsageController.new);

/// 纪念册服务（P0 · B）：花园周快照 / 里程碑 / 夸夸语录送达埋点（零接口变更）。
final memoirServiceProvider = Provider<MemoirService>(
  (ref) => MemoirService(
    ref.watch(trackingRepositoryProvider),
    ref.watch(plantRepositoryProvider),
  ),
);

/// 奖励物美术资源清单（玄参 2026-09-27「奖励物图标化」）。
///
/// 用 `AssetManifest.loadFromAssetBundle` + `listAssets()` 判定资源是否存在
/// （**不要用 `AssetManifest.json`**——Flutter 3.7+ 不再生成该文件）。返回的字符串集合
/// 供 [`resolveRewardAsset`] 判断「`assets/rewards/*.png` 是否可用」；不可用时 UI 一律
/// 回退内置 `Icons`（阳光 / 碎片 / 种子 / 礼包）。加载失败（如测试无资源）返回空集，不抛。
final rewardAssetsProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().toSet();
  } catch (_) {
    return <String>{};
  }
});

// ── C74 · 专注等级（§5.24）：已结算等级存储 + 结算服务 ──────────────────────
//
// 🔴 两条 lazy 铁律（付费墙阶段既有的 Provider 纪律，本功能沿用）：
//   1. Provider 函数体只在**首次 read** 时执行，此处仅「登记如何构造」；
//   2. 不在 build 路径同步构造对象（尤其不碰 SharedPreferences 的异步读取）。

/// 「已结算到的最高等级」存储（SharedPreferences 实现，同 C14 防沉迷先例）。
///
/// ⚠️ 惰性：`sharedPreferencesProvider` 必须在 main 中 override，若不惰性会在
/// 未初始化的 ProviderScope 里提前读。
final focusLevelStoreProvider = Provider<FocusLevelSettledStore>(
  (ref) => FocusLevelPrefsStore(ref.watch(sharedPreferencesProvider)),
);

/// 专注等级结算服务（纯 Dart 编排：SP + 阳光账本）。
///
/// 依赖向上指着 [focusLevelStoreProvider] / [sunlightRepositoryProvider]，
/// **不反向依赖**任何 presentation；id 生成注入 `Uuid().v4()`（domain 不引入插件）。
final focusLevelServiceProvider = Provider<FocusLevelService>(
  (ref) => FocusLevelService(
    ledger: ref.watch(sunlightRepositoryProvider),
    store: ref.watch(focusLevelStoreProvider),
    idFactory: () => const Uuid().v4(),
  ),
);

// ── 付费墙权益（2026 付费墙 · 阶段 1 技术底座）─────────────────────────────
//
// 🔴 三条铁律（否则会让现有 widget 测试集体抛异常 / 免费功能退化）：
//   1. 新增 Provider **必须惰性**：Riverpod Provider 的函数体在**首次 read 时**才执行，
//      此处只是「登记如何构造」，**绝不在 build 路径同步构造对象**。
//   2. `entitlementProvider` **默认值必须是 free**，且 IAP 完全不可用时**不得抛异常**。
//   3. 阶段 1 **不接线任何门控点**：门控矩阵全放开，故即便有人 watch 本 Provider，
//      行为也与今天一致。

/// 权益票据仓储（惰性：首次 read 才构造本地实现 + 安全区存储）。
final entitlementRepositoryProvider = Provider<EntitlementRepository>(
  (ref) => EntitlementLocalRepository(SecureEntitlementStore()),
);

/// 内购平台服务（惰性：`IapService.instance` 构造**不解析插件**，构造安全；
/// 首次 `loadProducts` / `buyLifetime` / `restore` 才惰性接入 StoreKit / Play Billing）。
final iapServiceProvider = Provider<IapService>(
  (ref) => IapService.instance,
);

/// 权益服务（惰性：判定实现纯逻辑，构造不触平台）。
///
/// 内存态默认 [Entitlement.free]；首次 [`EntitlementService.load`] 才读安全区票据。
/// 阶段 1 门控矩阵全放开，[`EntitlementService.can`] 对 free 亦返回 true。
/// 阶段 2 起注入 [`IapService`]（真实购买 / 恢复链路；失败仍安全退回 free）。
final entitlementServiceProvider = Provider<EntitlementService>(
  (ref) => MatrixEntitlementService(
    repository: ref.watch(entitlementRepositoryProvider),
    iap: ref.watch(iapServiceProvider),
  ),
);

/// 当前权益（UI 门控读取的唯一来源）。
///
/// **默认 [Entitlement.free]，构造即安全**——StateProvider 的初始函数只在首次
/// read 时求值，返回常量 free，不触任何平台 API、不会抛。购买 / 恢复成功后由
/// 上层置为 premium（阶段 2 接线；阶段 1 恒为 free）。
final entitlementProvider = StateProvider<Entitlement>(
  (ref) => Entitlement.free,
);

/// 🐞 **仅 Debug 调试用**：模拟「已解锁」开关（release 不显示、不参与任何业务判定）。
///
/// 用途仅为真机预览付费内容（月 / 年报告、热力图、深度报告），**不落库、不写票据**，
/// 重启 App 即失效；`main.dart` 冷启动 `hydrateEntitlement` 会按真实票据覆盖。
///
/// 为什么单独一个 Provider 而不直接改 [entitlementProvider]：调试开关需要自带
/// **可回读的布尔值**给 UI 开关控件（`SwitchListTile.value`），而
/// [entitlementProvider] 存的是实体快照；两者同源同向（见 [debugSetPremiumUnlock]），
/// 但语义分离后可避免「调试态」污染购买链路的票据来源判断。
final StateProvider<bool> debugPremiumUnlockProvider =
    StateProvider<bool>((ref) => false);

/// 🐞 **仅 Debug**：切换模拟解锁（写内存态 [entitlementProvider]，不落库）。
///
/// [enabled] 为 `true` → 记一个 `productId: 'debug.simulated.unlock'` 的假票据
/// （`productId` 一眼可辨，便于真机上排查「为什么我解锁了」）；为 `false` → 回
/// [Entitlement.free]。
///
/// 🔴 本函数是「调试态 → 权益态」的**唯一转换点**：UI 侧（`DebugUnlockSwitch`）
/// 只碰 [debugPremiumUnlockProvider] 与本函数，故调试控件文件内零权益标识符
/// （`test/qa/entitlement_gate_guard_test.dart` 守卫仍紧）。
void debugSetPremiumUnlock(WidgetRef ref, bool enabled) {
  ref.read(debugPremiumUnlockProvider.notifier).state = enabled;
  ref.read(entitlementProvider.notifier).state = enabled
      ? Entitlement.lifetime(
          acquiredAt: DateTime.now(),
          productId: 'debug.simulated.unlock',
        )
      : Entitlement.free;
}
