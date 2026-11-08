/// 花园一键 FAB 的**权益响应性**回归守卫（玄参 2026-11-07 第四批 · 真 bug 修复）。
///
/// ## 修复前的真 Bug（iPad 13 实测）
/// 会员调试开关打开后，花园右下角（现 ticker 右上方）一键 FAB 不出现
/// （开关已开、存活株 ≥3）。
///
/// 根因：外壳 [IndexedStack] 保活 5 个 tab（切 tab 只切 index，不重建），
/// 花园页 `_entTier` 用 `ref.read(entitlementProvider).tier` **不订阅** ——
/// 「孩子回到花园 tab 即重读」的前提在保活下不成立 ⇒ `entitlementProvider`
/// 变化（`debugSetPremiumUnlock` 写入）后花园页不重建，`_showOneClickFab`
/// 不重算。修复：`read` → `watch`。
///
/// ## 本文件锁三件事
///  ① free 档 + 存活株 ≥ [kOneClickMinPlants] ⇒ FAB **不在**（门控本体）；
///  ② 挂载**之后** `debugSetPremiumUnlockIn(container, true)` ⇒ 有限帧内
///     FAB **出现**（修复点：watch 订阅让页面随权益变化重建；修复前此处
///     永远假绿不出来）；
///  ③ 开关关回 ⇒ FAB **再次消失**（订阅是双向的，不是单向 latch）。
///
/// ⚠️ 全程禁用 `pumpAndSettle`：花园页木牌呼吸 / 氛围音是无限动画。
library garden_fab_entitlement_reactive_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/di/today_weather.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';

// ── 内存 Fake 仓储（口径与 weather_a2_test 的真页面宿主一致）─────────────────

const PlantSpecies _fabSunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

class _FakeSettings implements SettingsRepository {
  AppSettings value = const AppSettings(
    ageTier: AgeTier.low,
    dailyFocusCap: kDailyFocusCapLow,
    dailyAppCapMinutes: 30,
    restAfterSessions: 2,
    restMinutes: 10,
    taskSunlight: 12,
    poolBudget: kPoolBudgetDefaultLow,
  );

  @override
  Future<AppSettings> getSettings() async => value;

  @override
  Future<void> saveSettings(AppSettings settings) async => value = settings;
}

class _FakePlants implements PlantRepository {
  _FakePlants(this._plants);

  final List<Plant> _plants;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);

  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _plants) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    _plants.removeWhere((Plant p) => p.id == plant.id);
    _plants.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      _plants.removeWhere((Plant p) => p.id == id);

  @override
  Future<List<PlantSpecies>> species() async => const <PlantSpecies>[
        _fabSunflower,
      ];
}

class _FakeFocus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _FakeLedger implements SunlightRepository {
  _FakeLedger();

  final double initial = 100;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async =>
      initial + entries.fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  @override
  Future<double> dayNet(String key) async => 0;

  @override
  Future<double> earnGrossOnDay(String key) async => 0;

  @override
  Future<double> earnNetOnDay(String key) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String key,
  ) async =>
      0;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
    String refType,
    String refId,
  ) async =>
      null;
}

/// 票据仓储假件（避免真实装配触平台安全区存储）。
class _FakeEntitlementRepo implements EntitlementRepository {
  Entitlement stored = Entitlement.free;

  @override
  Future<Entitlement> read() async => stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      stored = entitlement;

  @override
  Future<void> clear() async => stored = Entitlement.free;
}

// ── 日期挑选（绝不手写日型，一律走真源 `WeatherSystem.ofDay`）────────────────

DateTime _findDay(bool Function(WeatherKind) match) {
  final DateTime base = DateTime(2026, 11, 3);
  for (int i = 0; i < 800; i++) {
    final DateTime day = DateTime(base.year, base.month, base.day + i, 9);
    if (match(WeatherSystem.ofDay(day).kind)) return day;
  }
  throw StateError('no matching day found within 800 days');
}

/// 钉死的**温和日**快照（A3 测试接缝 §13.6：天气经 `todayWeatherProvider` 钉死）。
TodayWeather _pinnedMildToday() {
  final DateTime day = _findDay((WeatherKind k) => k.isMild);
  return TodayWeather(
    day: WeatherSystem.ofDay(day),
    dayKey: WeatherSystem.dayKey(day),
    observedAt: day,
  );
}

/// 造 [n] 株**存活**向日葵（`plantedAt` / `stageStartedAt` 取当下，防 tick 结死）。
List<Plant> _alivePlants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'fab_reactive_p$i',
      speciesId: _fabSunflower.id,
      potIndex: i,
      stage: PlantStage.sprout,
      stageStartedAt: now,
      growthProgress: 0.4,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
    ),
  );
}

void main() {
  testWidgets(
      'free 档挂载（存活 5 株）FAB 不在 → debugSetPremiumUnlockIn(true) → '
      'FAB 出现 → 关回 → FAB 再消失（watch 订阅双向）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        sunlightRepositoryProvider.overrideWithValue(_FakeLedger()),
        focusRepositoryProvider.overrideWithValue(_FakeFocus()),
        plantRepositoryProvider.overrideWithValue(_FakePlants(_alivePlants(5))),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        entitlementRepositoryProvider
            .overrideWithValue(_FakeEntitlementRepo()),
        todayWeatherProvider.overrideWithValue(_pinnedMildToday()),
        // 🔴 权益**不 override**：用 entitlementProvider 的真实默认值 free ——
        // 本用例的语义就是「free 挂载 → 运行期写 premium」，初始态必须走生产链。
      ],
    );
    addTearDown(container.dispose);
    // 模拟「外壳停在花园 tab 且在前台」（花园页可见性判据）。
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGarden;
    container.read(childShellOnStageProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ),
    );
    // 等数据就绪（badge 渲染 = build 完成、非 loading）。
    bool badgeReady() =>
        find.byKey(kGardenWeatherBadgeKey).evaluate().isNotEmpty;
    for (int i = 0; i < 60 && !badgeReady(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(badgeReady(), isTrue,
        reason: '真实 GardenPage 应在有限帧内加载完成（badge 在场 = 非loading）');
    await tester.pump();

    // ① free 档 + 存活 5 株（≥ kOneClickMinPlants）⇒ FAB 必须不在（D3 门控）。
    expect(find.byKey(kOneClickCapsuleKey), findsNothing,
        reason: 'free 档隐藏一键 FAB（oneClickCare.freeEnabled = false）');

    // ② 运行期开调试开关（等价 IndexedStack 保活下家长端切完开关回花园）。
    debugSetPremiumUnlockIn(container, true);
    expect(container.read(entitlementProvider).isPremium, isTrue,
        reason: '前置：调试开关必须真的写入 entitlementProvider');

    // 修复点：watch 订阅 ⇒ 权益变化即重建，有限帧内 FAB 出现。
    bool fabVisible() =>
        find.byKey(kOneClickCapsuleKey).evaluate().isNotEmpty;
    bool appeared = false;
    for (int i = 0; i < 60; i++) {
      if (fabVisible()) {
        appeared = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(appeared, isTrue,
        reason: 'entitlementProvider 变化后花园页必须**响应式**重算 _showOneClickFab'
            '（修复前 read 不订阅 + IndexedStack 保活 ⇒ FAB 永远不出现）');
    await tester.pump();

    // ③ 开关关回 ⇒ FAB 再次消失（订阅双向，非单向 latch）。
    debugSetPremiumUnlockIn(container, false);
    bool disappeared = false;
    for (int i = 0; i < 60; i++) {
      if (!fabVisible()) {
        disappeared = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(disappeared, isTrue, reason: '关回 free 后 FAB 必须随重建消失');

    expect(tester.takeException(), isNull);
  });
}
