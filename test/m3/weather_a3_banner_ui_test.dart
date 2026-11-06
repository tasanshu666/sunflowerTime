/// 天气系统 A3 期 · 顶部天气条幅 **验收测试**（V6~V10 + 跨零点接缝）。
///
/// ## 全部走**真页面** + 钉死天气（设计 §13）
/// 每条用例都 `todayWeatherProvider.overrideWithValue(...)` 把日型钉死，日期由
/// `_findDay` **动态查找**（`WeatherSystem.ofDay` 是纯函数，故查找结果是确定值；
/// 但不许手写日期 —— 逐月权重表上线后「哪天是干旱」会随季节口径变化，
/// 写死日期 = 埋一个只在某些月份红的雷）：
///  · `_kMildDay` ⇒ 2026-11-03 起第一个 `sunny`（温和日，胶囊路径）；
///  · `_kDroughtDay` ⇒ 2026-11-03 起第一个 `drought`（极端日，条幅路径）；
///  · `_kCrossMidnightDroughtDay` ⇒ 同上那天的 `23:59:59`（跨零点用例：
///    与「跑测试那天」**不同日**才抓得住重新读钟的实现）。
///
/// 🔴 **禁 `pumpAndSettle`**：花园页有两个无限动画（木牌呼吸 / 氛围音），
///    `pumpAndSettle` 永不返回 ⇒ 本文件一律用有界 `pump`。
///
/// ## 期望值来源（独立于实现常量）
/// · 条幅 `top == 6` / `height == 56` / `left == 12` / `width == 页宽−24`
///   = 设计 §1.4 的**写死坐标表**（不是读实现常量自证）；
/// · `chips 文本顶 == 68` = `6 + 56 + 6`；
/// · 温和日 `y == 12` = A2 封版基线（§1.1 表）；
/// · `kWeatherRowKey` 在极端日**不存在** = 设计 §6 的契约（不是实现细节）。
library weather_a3_banner_ui_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/di/today_weather.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
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
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart'
    show GardenGrid, GardenPot;
import 'package:sunflower_time/presentation/child/widgets/weather_banner.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';

// ── 日期挑选（**绝不手写日型 / 绝不写死日期**，一律走真源 `WeatherSystem.ofDay`）──

/// 从 **2026-11-03** 起逐日往后扫，找到第一个满足 [match] 的自然日（上限 800 天）。
///
/// 与 `weather_a2_test.dart` 里的同名工具同法：800 天覆盖两年多，对 9 种日型
/// （最稀有的干旱在非旱季权重为 0，旱季也有 7~8%）来说必然命中；扫不到就是
/// 权重表被改坏了，`StateError` 让根因直接暴露，而不是退回一个假日期。
DateTime _findDay(bool Function(WeatherKind) match) {
  final DateTime base = DateTime(2026, 11, 3);
  for (int i = 0; i < 800; i++) {
    final DateTime day = DateTime(base.year, base.month, base.day + i, 9);
    if (match(WeatherSystem.ofDay(day).kind)) return day;
  }
  throw StateError('no matching day found within 800 days');
}

/// 温和日（`sunny`）：2026-11-03 起第一个阳光明媚日（动态查找）。
final DateTime _kMildDay = _findDay((WeatherKind k) => k == WeatherKind.sunny);

/// 极端日（`drought`）：2026-11-03 起第一个干旱日（动态查找）。
///
/// 🔴 **不能写死 2026-11-05**：逐月权重表上线后干旱只在 **5-9 月**出现，
/// 而 11 月的干旱权重是 0 ⇒ 那个日期现在是大风/极寒，写死必红。
final DateTime _kDroughtDay = _findDay((WeatherKind k) => k == WeatherKind.drought);

/// 跨零点用例用：**同一个干旱日的 `23:59:59`**（动态查找 + 后移时分秒）。
///
/// 与「跑测试那天」不是同一天（2026-11-03 起扫到的旱季日子距真实今天至少半年），
/// 故任何一处偷偷 `DateTime.now()` 都会写出不同的 `dayKey`，断言当场变红
/// （变异点 M-A3-9）。
final DateTime _kCrossMidnightDroughtDay = DateTime(
  _kDroughtDay.year,
  _kDroughtDay.month,
  _kDroughtDay.day,
  23,
  59,
  59,
);

/// 把某个自然日包成 [TodayWeather]（三字段同源，与生产口径一致）。
TodayWeather _todayOf(DateTime day) => TodayWeather(
      day: WeatherSystem.ofDay(day),
      dayKey: WeatherSystem.dayKey(day),
      observedAt: day,
    );

// ── 假仓储（装配口径与 `weather_a2_test.dart` / `garden_layout_v3_test.dart` 一致）──

const PlantSpecies _kSunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

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
  Future<List<PlantSpecies>> species() async =>
      const <PlantSpecies>[_kSunflower];
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

/// 账本 Fake：余额 = `initial + Σnet`；[entries] 可**预置**（V9 直接喂事实）。
class _FakeLedger implements SunlightRepository {
  _FakeLedger();

  /// 初始余额（本文件恒 100☀：够买棚，且与页面既有宿主同口径）。
  static const double initial = 100;
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
  ) async {
    return entries
        .where((SunlightEntry e) =>
            e.refType == refType && e.refId == refId && e.dayKey == key)
        .length;
  }

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
  ) async {
    for (final SunlightEntry e in entries.reversed) {
      if (e.refType == refType && e.refId == refId) return e.ts;
    }
    return null;
  }
}

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

/// 造 [n] 株**存活**向日葵（`stageStartedAt` = 当下，避免被 tick 成枯死残株）。
List<Plant> _alivePlants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'a3_p$i',
      speciesId: _kSunflower.id,
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

// ── 宿主 ────────────────────────────────────────────────────────────────────

/// 共享内存库（装配链要它；本文件所有仓储都是假的 ⇒ 它从不被业务读写）。
db.AppDatabase? _sharedDb;

db.AppDatabase _sharedDatabase() =>
    _sharedDb ??= db.AppDatabase(NativeDatabase.memory());

/// 真页面宿主（真实 `GardenPage(embedded: true)`）+ 钉死天气。
Widget _page({
  required TodayWeather today,
  _FakeLedger? ledger,
  int plants = 5,
}) {
  return ProviderScope(
    overrides: <Override>[
      entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
      appDatabaseProvider.overrideWithValue(_sharedDatabase()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      sunlightRepositoryProvider.overrideWithValue(ledger ?? _FakeLedger()),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      plantRepositoryProvider.overrideWithValue(_FakePlants(_alivePlants(plants))),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      todayWeatherProvider.overrideWithValue(today),
    ],
    child: const MaterialApp(
      home: Scaffold(body: GardenPage(embedded: true)),
    ),
  );
}

/// 有界帧推进（花园页有无限动画 ⇒ 只能「条件 + 有界帧」）。
Future<bool> _pumpUntilReady(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 80,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 泵到「数据就绪」（chips 出现 = `_loading == false` 且无错误页）。
Future<void> _pumpLoaded(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(page);
  final bool ready =
      await _pumpUntilReady(tester, () => find.textContaining('×').evaluate().isNotEmpty);
  expect(ready, isTrue,
      reason: '真实 GardenPage 应在有限帧内加载完成（chips 出现 = _loading 归零）；'
          '不出现说明宿主没搭起来或 _reload 被卡住');
  await tester.pump();
}

/// 手机视口（390×844 逻辑像素 ⇒ `uiScaleOf == 1.0`）。
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 定位 chips 行（**结构定位** + 「×N」自检，与 A2-8④ 同款）。
Finder _chipsRowFinder(WidgetTester tester, Finder weatherRow) {
  final Finder outerRow =
      find.ancestor(of: weatherRow, matching: find.byType(Row)).first;
  final Finder chipTexts =
      find.descendant(of: outerRow, matching: find.textContaining('×'));
  expect(chipTexts, findsAtLeastNWidgets(1),
      reason: 'chips（碎片 / 普通种子 / 精英种子）必须渲染 —— 否则定位到的不是浮层行');
  return find.descendant(of: outerRow, matching: find.byType(Row)).first;
}

/// 不依赖天气行也能定位 chips 行（极端日天气行**不存在**）。
///
/// `×N` 文本的**最近** Row 祖先是 `_SeedCountChip` 内部的布局 Row（它上面还有
/// `Padding(vertical: 6)`），故取「再上一层」= 三个 chip 所在的行。
/// 自检：定位到的 Row 里必须**含至少两个**「×N」文本（碎片 + 两档种子），
/// 防结构变化后量错对象假绿。
Finder _chipsRowFinderNoWeatherRow(WidgetTester tester) {
  final Finder rows = find.ancestor(
    of: find.textContaining('×').first,
    matching: find.byType(Row),
  );
  expect(rows.evaluate().length, greaterThanOrEqualTo(2),
      reason: 'chips 行与 chip 内部行两层 Row 都必须存在');
  final Finder chipsRow = rows.at(1);
  expect(
    find.descendant(of: chipsRow, matching: find.textContaining('×')),
    findsAtLeastNWidgets(2),
    reason: '自检：定位到的 Row 必须装着「碎片 + 两档种子」的 ×N 文本',
  );
  return chipsRow;
}

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();

  setUp(() {
    AppLocaleController.current = const Locale('zh');
  });
  tearDown(() {
    AppLocaleController.current = const Locale('zh');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V6 · 温和日：**零几何变化**（条幅不渲染，胶囊与 chips 都在 y=12）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V6 · 温和日（sunny，动态查找）：条幅不存在、胶囊存在，'
      '胶囊槽顶/胶囊实体顶/chips 行顶 == 12（与 A2 基线同值）', (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kMildDay)));

    expect(find.byKey(kWeatherBannerKey), findsNothing,
        reason: '温和日**不得**渲染条幅（M-A3-2 的抓手：多渲染一条会顶高 62pt）');
    expect(find.byKey(kWeatherRowKey), findsOneWidget,
        reason: '温和日天气胶囊必须照旧渲染（A2 §6：极端日才由条幅承接）');

    final Rect slot = tester.getRect(find.byKey(kWeatherPillSlotKey));
    final Rect entity = tester.getRect(find.byKey(kWeatherPillKey));
    expect(slot.top, closeTo(12, 0.5), reason: '胶囊槽顶必须仍是 12（A2 基线）');
    expect(entity.top, closeTo(slot.top, 0.5), reason: '实体顶对齐槽顶');
    expect(slot.height, closeTo(32, 0.5), reason: '槽高 32');
    expect(entity.height, closeTo(28, 0.5), reason: '实体 28');
    expect(tester.getRect(find.byKey(kWeatherPillHitKey)).height, closeTo(44, 0.5),
        reason: '命中盒 44（A11y 下限）');

    final Rect chips = tester.getRect(_chipsRowFinder(tester, find.byKey(kWeatherRowKey)));
    expect(chips.top, closeTo(12, 0.5),
        reason: 'chips 行顶必须仍是 12（`Padding(top: 6)` 仍在）');

    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V7 · 极端日几何（**写死坐标**，不引用实现常量）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V7 · 极端日（drought，动态查找）：条幅 top==6 / height==56 / '
      'left==12 / width==366；chips 行顶==68；kWeatherRowKey 不存在',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay)));

    final Finder banner = find.byKey(kWeatherBannerKey);
    expect(banner, findsOneWidget, reason: '极端日必须渲染条幅');

    final Rect rect = tester.getRect(banner);
    expect(rect.top, closeTo(6, 0.5), reason: '条幅顶 = 浮层 top = 6（embedded）');
    expect(rect.height, closeTo(56, 0.5), reason: '条幅固定高 56');
    expect(rect.left, closeTo(12, 0.5), reason: '左边距 12');
    expect(rect.width, closeTo(390 - 24, 0.5), reason: '全宽 = 页宽 − 24');

    // 契约（设计 §6）：极端日天气胶囊**不渲染**。
    expect(find.byKey(kWeatherRowKey), findsNothing,
        reason: '极端日 `kWeatherRowKey` 在树里**不存在** —— 这是契约不是实现细节'
            '（变异点 M-A3-6 的抓手）');
    expect(find.byKey(kWeatherPillKey), findsNothing);

    // chips 行下移到条幅之下：6 + 56 + 6 = 68（chips 的 `Padding(top: 6)` 必须置 0，
    // 否则会是 74 —— 变异点 M-A3-8 的抓手）。
    // 🔴 定位口径：`×N` 文本的**最近** Row 祖先是 `_SeedCountChip` 内部那层
    //    （它上面还有 `Padding(vertical: 6)` ⇒ 比 chips 行顶低 6）⇒ 必须取
    //    「再上一层 Row」= 三个 chip 所在的行（`_chipsRowFinderNoWeatherRow` 内含自检）。
    final Rect chipsRow =
        tester.getRect(_chipsRowFinderNoWeatherRow(tester));
    expect(chipsRow.top, closeTo(68, 0.5),
        reason: 'chips 行顶 = 6 + 56 + 6 = 68');
    expect(chipsRow.left, closeTo(12, 0.5), reason: 'chips 仍贴左边距 12');

    // 条幅文案 = todo_drought（zh），且**没有** ellipsis。
    expect(find.text(zh.garden_weather_banner_todo_drought), findsOneWidget);

    // 道具按钮在条幅内（视觉 32 / 命中 44），且**只有一个**（薄行那条已不渲染）。
    expect(find.byKey(kShelterButtonHitKey), findsOneWidget);
    expect(tester.getRect(find.byKey(kShelterButtonVisualKey)).height,
        closeTo(32, 0.5),
        reason: '条幅内的道具按钮视觉高 32');
    expect(tester.getRect(find.byKey(kShelterButtonHitKey)).height,
        closeTo(44, 0.5),
        reason: '命中盒 44（A11y 下限）');

    expect(tester.takeException(), isNull,
        reason: '极端日真页面不得有 RenderFlex overflow / 负宽断言等异常');
  });

  testWidgets('V7 · 极端日 standalone（embedded: false）几何整体 +48，'
      '条幅 top==54、chips 行顶==116', (WidgetTester tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
          appDatabaseProvider.overrideWithValue(_sharedDatabase()),
          settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
          sunlightRepositoryProvider.overrideWithValue(_FakeLedger()),
          focusRepositoryProvider.overrideWithValue(_FakeFocus()),
          plantRepositoryProvider
              .overrideWithValue(_FakePlants(_alivePlants(5))),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
          todayWeatherProvider.overrideWithValue(_todayOf(_kDroughtDay)),
        ],
        child: const MaterialApp(home: GardenPage()),
      ),
    );
    final bool ready = await _pumpUntilReady(
      tester,
      () => find.textContaining('×').evaluate().isNotEmpty,
    );
    expect(ready, isTrue, reason: 'standalone 花园页也应加载完成');

    final Rect rect = tester.getRect(find.byKey(kWeatherBannerKey));
    // standalone 有 AppBar：坐标以 **body 顶**为基准（AppBar 之下），
    // 故这里用「AppBar 底」换算，而不是写死屏幕坐标。
    final double bodyTop = tester.getRect(find.byType(AppBar)).bottom;
    expect(rect.top - bodyTop, closeTo(54, 0.5),
        reason: 'standalone 浮层 top = (60 − 6) = 54（独立路由有阳光胶囊）');
    expect(rect.height, closeTo(56, 0.5));
    // 相对几何与 embedded 同一套：chips 行顶 − 条幅顶 = 56 + 6 = 62。
    final Rect chipsRow =
        tester.getRect(_chipsRowFinderNoWeatherRow(tester));
    expect(chipsRow.top - rect.top, closeTo(62, 0.5),
        reason: 'chips 行顶 − 条幅顶 = 56 + 6 = 62（与 embedded 同一套相对几何）');
    expect(find.byKey(kWeatherRowKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V8 · 网格零推动（条幅是浮层，不许改 `firstRowTop`）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V8 · 极端日与温和日的花盆网格顶**逐位相同**（条幅是浮层，零推动）',
      (WidgetTester tester) async {
    _phoneViewport(tester);

    await _pumpLoaded(tester, _page(today: _todayOf(_kMildDay)));
    final Rect gridMild = tester.getRect(find.byType(GardenGrid));
    final Rect firstPotMild = tester.getRect(find.byType(GardenPot).first);

    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay)));
    final Rect gridExtreme = tester.getRect(find.byType(GardenGrid));
    final Rect firstPotExtreme = tester.getRect(find.byType(GardenPot).first);

    expect(gridExtreme.top, closeTo(gridMild.top, 0.5),
        reason: '网格顶不许因条幅变化（M-A3-5 的抓手：条幅一旦进 _buildGardenBody，'
            '`firstRowTop` 就变 ⇒ gardenGridVisibleHeight 矮屏断言必红）');
    expect(gridExtreme.height, closeTo(gridMild.height, 0.5));
    expect(firstPotExtreme.top, closeTo(firstPotMild.top, 0.5),
        reason: '第一排花盆格顶必须与温和日同值');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V9 · 完成态：账本重算 ⇒ done（页面重建后不回退）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V9 · 极端日 + 当日「浇过水」+「已买遮阳棚」⇒ 条幅 done 态'
      '（✓ 图标 + done 文案，todo 文案退场）', (WidgetTester tester) async {
    _phoneViewport(tester);
    final String key = WeatherSystem.dayKey(_kDroughtDay);
    final _FakeLedger ledger = _FakeLedger()
      ..entries.addAll(<SunlightEntry>[
        SunlightEntry(
          id: 'a3_water_1',
          ts: _kDroughtDay,
          type: SunlightType.plant,
          gross: -3,
          net: -3,
          balanceAfter: 97,
          refType: 'plant_water',
          refId: 'a3_p0',
          dayKey: key,
        ),
        SunlightEntry(
          id: 'a3_shelter_1',
          ts: _kDroughtDay,
          type: SunlightType.plant,
          gross: -10,
          net: -10,
          balanceAfter: 87,
          refType: kWeatherShelterRefTypeShade,
          refId: kWeatherShelterRefId,
          dayKey: key,
        ),
      ]);

    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay), ledger: ledger));

    expect(find.byKey(kWeatherBannerKey), findsOneWidget);
    expect(find.text(zh.garden_weather_banner_done_drought), findsOneWidget,
        reason: '账本事实齐全 ⇒ 条幅必须直接进 done 态（重建后以账本重算为准，§3.2）');
    expect(find.text(zh.garden_weather_banner_todo_drought), findsNothing,
        reason: 'done 态不得同时显示 todo 文案');

    // 完成态图标：**天气位图换成 ✓**（§9.5 语义优先于美术）。
    expect(
      find.descendant(
        of: find.byKey(kWeatherBannerIconKey),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
      reason: '完成态图标位必须是 ✓（不是天气位图）',
    );

    // 页面再跑若干帧（经济修订号 / tab 刷新会反复 _reload）也不许回退。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text(zh.garden_weather_banner_done_drought), findsOneWidget,
        reason: '重复刷新后仍必须 done（重算幂等，§3.2）');
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V10 · 零动画（条幅子树内没有任何动画件；连续帧几何逐位不变）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V10 · 条幅零动画：子树内无 AnimatedContainer / AnimatedOpacity / '
      'AnimatedSwitcher / TweenAnimationBuilder，且 30 帧内矩形逐位不变',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay)));

    final Finder banner = find.byKey(kWeatherBannerKey);
    expect(banner, findsOneWidget);

    // 🔴 只对「进场 / 尺寸」类动画下断言：`Material(elevation: 2)` 内部的
    //    `AnimatedPhysicalModel` 只在 elevation 变化时才跑，本页永不变化，
    //    且它是薄行同一个组件既有的实现细节，不算「条幅加了动画」。
    for (final Finder animated in <Finder>[
      find.descendant(of: banner, matching: find.byType(AnimatedContainer)),
      find.descendant(of: banner, matching: find.byType(AnimatedOpacity)),
      find.descendant(of: banner, matching: find.byType(AnimatedSwitcher)),
      find.descendant(of: banner, matching: find.byType(TweenAnimationBuilder<double>)),
      find.descendant(of: banner, matching: find.byType(ScaleTransition)),
      find.descendant(of: banner, matching: find.byType(FadeTransition)),
    ]) {
      expect(animated, findsNothing, reason: '条幅内不许有任何入场 / 尺寸动画（§9.8）');
    }

    final Rect first = tester.getRect(banner);
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final Rect now = tester.getRect(banner);
      expect(now, first, reason: '第 $i 帧条幅矩形发生了变化 ⇒ 存在动画');
    }
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // T-7.3 · 跨零点：确认卡写的道具 == 账本记的道具 == provider 的 dayKey
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('T-7 · 跨零点（钉「动态查找的干旱日 23:59:59」，与真实今天不同日）：'
      '确认卡写「遮阳棚」，账本写入 refType==shelter_shade 且 dayKey==钉死日',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    final _FakeLedger ledger = _FakeLedger();
    final TodayWeather pinned = _todayOf(_kCrossMidnightDroughtDay);

    await _pumpLoaded(tester, _page(today: pinned, ledger: ledger));

    // 前置：钉的这一天确实是干旱日、且与真实今天不是同一天（否则本用例没意义）。
    expect(pinned.day.kind, WeatherKind.drought);
    expect(pinned.dayKey, WeatherSystem.dayKey(_kCrossMidnightDroughtDay));
    expect(pinned.dayKey, isNot(WeatherSystem.dayKey(DateTime.now())),
        reason: '钉死的日子必须与「跑测试那天」不同，才能抓住重新读钟的实现');

    // 点条幅里的道具按钮 → 弹确认卡（文案由页面 context 取好，走 zh）。
    await tester.tap(find.byKey(kShelterButtonHitKey));
    final bool cardShown = await _pumpUntilReady(
      tester,
      () => find.text(zh.garden_shelter_confirm_ok).evaluate().isNotEmpty,
      maxFrames: 40,
    );
    expect(cardShown, isTrue, reason: '点「推荐道具」应弹出确认卡');
    expect(find.text(zh.garden_shelter_confirm_title(zh.garden_shelter_shade)),
        findsOneWidget,
        reason: '确认卡必须写「遮阳棚」（= provider 快照的 refType）');

    // 点「搭起来」→ 记账。
    await tester.tap(find.text(zh.garden_shelter_confirm_ok));
    await _pumpUntilReady(
      tester,
      () => ledger.entries.any((SunlightEntry e) => e.refType != null),
      maxFrames: 60,
    );

    final Iterable<SunlightEntry> shelters = ledger.entries.where(
      (SunlightEntry e) => e.refType == kWeatherShelterRefTypeShade,
    );
    expect(shelters, isNotEmpty,
        reason: '账本必须写入 shelter_shade 行（买棚必须真的记账）');
    expect(shelters.single.dayKey, pinned.dayKey,
        reason: '账本的 dayKey 必须与 provider 的 dayKey 一致 —— 若 `:1759` 还在'
            '自己 `DateTime.now()`，这里会是真实今天（M-A3-9 / M-A3-10 的抓手）');
    expect(
      ledger.entries.where((SunlightEntry e) => e.refType == kWeatherShelterRefTypeRain),
      isEmpty,
      reason: '不许因跨零点写成次日的「遮雨棚」',
    );
  });
}
