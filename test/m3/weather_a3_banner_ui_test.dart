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
/// ## 2026-11-07 第三轮改写（玄参拍板「白色长条删除」）
///  · 停靠条（`GardenWeatherDock`，72 白条）**退役**，改名 `GardenWeatherBadge`
///    独立图标状态灯（56×56）—— 本文件的停靠条
///    几何断言（72 高 / 全宽）全部改写为状态灯断言；
///  · 买棚按钮在**天气对话框**里（点状态灯弹出）—— V9 done 态补断言盾牌，
///    T-7 恢复执行（前置「点 badge → 弹对话框」两步）。
///
/// ## 2026-11-07 第四轮改写（玄参第四批排版）
///  · 状态灯移**右上角**（`right:12 / top:12`，与左上 chips 行对称）。
///
/// ## 2026-11-07 第五轮改写（玄参第五批拍板）
///  · 底部天气提示框（`GardenWeatherTicker`）**整体撤除**（「不显示了，就放在
///    天气弹窗里吧」）—— 明日预告由对话框承接；本文件的 ticker 断言删除，
///    并补「ticker 不存在」守卫；
///  · 一键 FAB 回归**右下角原位**（`right:12 / bottom:12`）。
///
/// ## 期望值来源（独立于实现常量）
/// · 状态灯 `right == 390 − 12 / top == 12 / 尺寸 == 56`
///   + 底色（温和/done = `0xFFC0DD97` 绿、极端 todo = `0xFF6FA3A0` 雾霾青蓝 + 红描边，
///   + 叹号角标 / done 对勾角标）= 玄参 2026-11-07 拍板的**写死坐标表**；
/// · `chips 视觉顶 == 12` = A2 封版基线；
/// · `kWeatherRowKey` / `kWeatherBannerKey` 在真页面树里**不存在** = 2026-11-06
///   「天气预告整体撤出顶部」的契约（不是实现细节）。
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
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_dialog.dart';
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

/// 不依赖天气行定位 chips 行（2026-11-06 起顶部天气行/胶囊整体撤除，页面树里
/// **不再存在** `kWeatherRowKey`，旧的结构定位口径随之退役）。
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
  // V6 · 温和日：顶部零天气件（条幅/胶囊均撤除），右上角状态灯渲染
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V6 · 温和日（sunny，动态查找）：条幅/顶部胶囊不存在，'
      '右上角状态灯（绿底 56×56 贴 right12/top12，无白条）在场，'
      '底部提示框不存在（第五批撤除），chips 行顶 == 12',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kMildDay)));

    // 旧顶部件全部退场（2026-11-06 玄参拍板：天气预告整体撤出顶部）。
    expect(find.byKey(kWeatherBannerKey), findsNothing,
        reason: '旧条幅不再渲染（无论温和日 / 极端日）');
    expect(find.byKey(kWeatherRowKey), findsNothing,
        reason: '顶部天气胶囊整体撤除 —— 契约：`kWeatherRowKey` 在真页面树里不存在');
    expect(find.byKey(kWeatherPillKey), findsNothing);

    // 右上角状态灯：温和日 = 图标状态灯（绿底 56×56），无角标 / 无买棚按钮。
    final Finder badge = find.byKey(kGardenWeatherBadgeKey);
    expect(badge, findsOneWidget, reason: '温和日也必须渲染状态灯（点击开对话框）');
    expect(find.byKey(kGardenWeatherBadgeIconKey), findsOneWidget,
        reason: '56×56 图标状态灯在场（玄参：「图标太小了要单独拎出来放大」）');
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFFC0DD97),
      reason: '温和日状态灯 = 浅绿底（正常，写死色值）',
    );
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsNothing,
        reason: '温和日无状态角标');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: '买棚按钮只在天气对话框里，状态灯上永不存在');
    expect(
      find.descendant(
        of: badge,
        matching: find.textContaining(zh.weather_sunny),
      ),
      findsNothing,
      reason: '状态灯不渲染描述文字（玄参第三轮：「只保留 56×56 的圆角块就好了」）',
    );

    // 几何：真实 56×56 块贴右上（right 12 / top 12，与左上 chips 行对称）；
    // 旧 72 白条已删（组件总高 == 56，不是 72）。
    final Rect badgeRect = tester.getRect(badge);
    expect(badgeRect.right, closeTo(390 - 12, 0.5), reason: '状态灯右锚 12');
    expect(badgeRect.top, closeTo(12, 0.5), reason: '状态灯贴顶 12');
    expect(badgeRect.width, closeTo(56, 0.5), reason: '状态灯宽 56（无白条全宽）');
    expect(badgeRect.height, closeTo(56, 0.5), reason: '状态灯高 56（白条已删）');

    // 底部提示框已撤（第五批玄参拍板）：kGardenWeatherTickerKey 在树里不存在
    // ——「今日 / 明日」信息全部收进天气对话框（点状态灯弹出）。
    expect(find.byKey(const ValueKey<String>('garden_weather_ticker')),
        findsNothing,
        reason: '底部天气提示框已整体撤除（第五批），契约：其 Key 不在页面树里');

    // 顶部 chips 行不动：视觉顶仍 y=12（A2 基线）。
    final Rect chips = tester.getRect(_chipsRowFinderNoWeatherRow(tester));
    expect(chips.top, closeTo(12, 0.5), reason: 'chips 行顶必须仍是 12');

    // 一键操作按钮：右下角原位（right:12 / bottom:12；第五批 ticker 撤除后
    // 从「ticker 右上方 bottom:52」的临时摆位回归玄参预期的右下角）。
    final Finder fab = find.byKey(kOneClickCapsuleKey);
    expect(fab, findsOneWidget, reason: '买断档 + 存活 5 株 ⇒ 一键 FAB 在场');
    final Rect fabRect = tester.getRect(fab);
    expect(fabRect.right, closeTo(390 - 12, 0.5), reason: 'FAB 右缘 = 页宽 − 12');
    expect(fabRect.bottom, closeTo(844 - 12, 0.5),
        reason: 'FAB 底缘 = 页高 − 12（右下角原位）');

    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V7 · 极端日几何（**写死坐标**，不引用实现常量）—— 2026-11-07 第四批起
  //      状态灯在右上角（第五批起底部提示框撤除，FAB 回右下角）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V7 · 极端日（drought，动态查找）：状态灯 right==390−12 / top==12 / '
      '56×56 + 红底 + 红色「!」角标（无白条、无买棚按钮）；底部提示框不存在；'
      'chips 行顶==12；kWeatherRowKey 不存在', (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay)));

    final Finder badge = find.byKey(kGardenWeatherBadgeKey);
    expect(badge, findsOneWidget, reason: '极端日必须渲染状态灯');

    // 图标状态灯（todo 态）：雾霾青蓝底 + 1.5 红描边 + 红色「!」角标
    // （写死色值，不引用实现常量；第八批：淡青底加深，纯白雪花要清晰）。
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFF6FA3A0),
      reason: '极端 todo 态状态灯 = 雾霾青蓝底（第八批：白 vs 底对比度 ≥2.5）',
    );
    expect(
      ((tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
                  .decoration! as BoxDecoration)
              .border! as Border)
          .top
          .color,
      const Color(0xFFE24B4A),
      reason: '极端 todo 态状态灯 = 1.5 红描边',
    );
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: 'todo 态必须有叹号角标（「背景红色加叹号，表示需要处理」）');
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeMarkKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFFE24B4A),
      reason: '叹号角标 = 红底（写死色值）',
    );
    expect(find.text('!'), findsOneWidget, reason: '角标内容 = 白色「!」');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: '买棚按钮只在对话框里（点状态灯弹出），页面上无按钮');

    // 几何：真实 56×56 块贴右上（写死坐标，不引用实现常量）。
    final Rect rect = tester.getRect(badge);
    expect(rect.right, closeTo(390 - 12, 0.5), reason: '状态灯右锚 12');
    expect(rect.top, closeTo(12, 0.5), reason: '状态灯贴顶 12');
    expect(rect.width, closeTo(56, 0.5), reason: '状态灯宽 56（无白条全宽）');
    expect(rect.height, closeTo(56, 0.5), reason: '状态灯高 56（白条已删）');

    // 底部提示框已撤（第五批）：极端日也不再有底部警示条目。
    expect(find.byKey(const ValueKey<String>('garden_weather_ticker')),
        findsNothing,
        reason: '极端日底部提示框同样不存在（第五批撤除）');

    // 旧顶部件全部退场（条幅时代的「chips 下移到 68」几何随之退役）。
    expect(find.byKey(kWeatherBannerKey), findsNothing);
    expect(find.byKey(kWeatherRowKey), findsNothing,
        reason: '极端日 `kWeatherRowKey` 在树里**不存在** —— 契约不是实现细节'
            '（变异点 M-A3-6 的抓手）');
    expect(find.byKey(kWeatherPillKey), findsNothing);

    // chips 行顶不变：极端日不再下移（旧的 6 + 56 + 6 = 68 已退役）。
    final Rect chipsRow = tester.getRect(_chipsRowFinderNoWeatherRow(tester));
    expect(chipsRow.top, closeTo(12, 0.5),
        reason: 'chips 行顶 == 12（顶部条幅撤除后极端日不再下移 chips）');
    expect(chipsRow.left, closeTo(12, 0.5), reason: 'chips 仍贴左边距 12');

    expect(tester.takeException(), isNull,
        reason: '极端日真页面不得有 RenderFlex overflow / 负宽断言等异常');
  });

  testWidgets('V7 · 极端日 standalone（embedded: false）：状态灯贴 body 顶'
      '（right:12 / top:12、56×56），chips 视觉顶 − body 顶 == 12',
      (WidgetTester tester) async {
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

    final Rect rect = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
    // standalone 有 AppBar：坐标以 **body** 为基准（AppBar 之下）。
    final double bodyTop = tester.getRect(find.byType(AppBar)).bottom;
    expect(rect.width, closeTo(56, 0.5), reason: '状态灯宽 56');
    expect(rect.height, closeTo(56, 0.5), reason: '状态灯高 56（白条已删）');
    expect(rect.right, closeTo(390 - 12, 0.5), reason: '状态灯右锚 12');
    expect(rect.top - bodyTop, closeTo(12, 0.5),
        reason: 'standalone 状态灯贴 body 顶（top:12）');
    // 相对几何与 embedded 同一套：chips 视觉顶 − body 顶 == 60
    //（standalone 浮层 top = (60 − 6) = 54 + chips 内距 6；A2 温和日基线原值）。
    final Rect chipsRow =
        tester.getRect(_chipsRowFinderNoWeatherRow(tester));
    expect(chipsRow.top - bodyTop, closeTo(60, 0.5),
        reason: 'chips 视觉顶 − body 顶 = 54 + 6 = 60（与 embedded 同一套相对几何：'
            'embedded 为 12，standalone 整体 +48）');
    expect(find.byKey(kWeatherRowKey), findsNothing);
    expect(find.byKey(kWeatherBannerKey), findsNothing);
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
  testWidgets('V9 · 极端日 + 当日「浇过水」+「已买遮阳棚」⇒ 状态灯 done 态'
      '（绿底 + 绿对勾角标；badge 左侧盾牌在场；对话框无盾牌行、买棚按钮退场）',
      (WidgetTester tester) async {
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

    final Finder badge = find.byKey(kGardenWeatherBadgeKey);
    expect(badge, findsOneWidget);

    // done 态 = 绿底状态灯 + 绿底对勾角标（完成 = 正常色；todo 文案 / 买棚按钮
    // 均不在场 —— 买棚入口在对话框里，done 态对话框换盾牌）。
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFFC0DD97),
      reason: 'done 态状态灯 = 浅绿底（完成 = 正常，写死色值）',
    );
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: 'done 态角标在场（玄参：「叹号换成绿对勾」）');
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeMarkKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFF2E7D32),
      reason: 'done 角标 = 绿底（与「已获保护」同族色）',
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: 'done 角标内容 = 白对勾');
    expect(find.text(zh.garden_weather_banner_todo_drought), findsNothing,
        reason: 'done 态不得显示 todo 文案（状态灯本身也不渲染文字）');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: '页面上无买棚按钮（在对话框里）');

    // 第七批：已购棚 ⇒ 状态灯**左侧**盾牌位图在场（盾牌语义从对话框迁出）。
    expect(find.byKey(kGardenWeatherBadgeShelterKey), findsOneWidget,
        reason: '已购棚 ⇒ badge 左侧盾牌位图在场（第七批 2026-11-07）');
    final Rect badgeRectV9 = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
    expect(badgeRectV9.right, closeTo(390 - 12, 0.5),
        reason: '有盾牌时状态灯右锚仍 12（整排向左生长，右缘不变）');

    // 点状态灯 → 天气对话框弹出：买棚按钮退场（done）；盾牌行已迁往 badge 左侧
    //（第七批），框内不再有「已获保护」。
    await tester.tap(badge);
    final bool dialogShown = await _pumpUntilReady(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
      maxFrames: 40,
    );
    expect(dialogShown, isTrue, reason: '点状态灯应弹出天气对话框');
    expect(find.text(zh.garden_weather_protected), findsNothing,
        reason: 'done 态对话框不再渲染盾牌 /「已获保护」行（第七批迁往 badge 左侧）');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: 'done 态无买棚按钮（退场逻辑保留）');
    // 关对话框（不污染后续断言）。
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await _pumpUntilReady(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isEmpty,
      maxFrames: 20,
    );

    // 页面再跑若干帧（经济修订号 / tab 刷新会反复 _reload）也不许回退。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFFC0DD97),
      reason: '重复刷新后仍必须 done（绿底不回退；重算幂等，§3.2）',
    );
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: '重复刷新后仍是对勾角标（重算幂等，§3.2）');
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V10 · 状态灯零动画（badge 子树内没有任何动画件；连续帧几何逐位不变）
  // （ticker 已于第五批撤除，其轮播契约测试 `garden_weather_ticker_test.dart`
  //   一并删除——不再有该组件。）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('V10 · 状态灯零动画：子树内无 AnimatedContainer / AnimatedOpacity / '
      'AnimatedSwitcher / TweenAnimationBuilder，且 30 帧内矩形逐位不变',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay)));

    final Finder badge = find.byKey(kGardenWeatherBadgeKey);
    expect(badge, findsOneWidget);

    // 🔴 只对「进场 / 尺寸」类动画下断言：`Material(elevation: 2)` 内部的
    //    `AnimatedPhysicalModel` 只在 elevation 变化时才跑，本页永不变化，
    //    且它是薄行 / 旧条幅同一个组件既有的实现细节，不算「条加了动画」。
    for (final Finder animated in <Finder>[
      find.descendant(of: badge, matching: find.byType(AnimatedContainer)),
      find.descendant(of: badge, matching: find.byType(AnimatedOpacity)),
      find.descendant(of: badge, matching: find.byType(AnimatedSwitcher)),
      find.descendant(of: badge, matching: find.byType(TweenAnimationBuilder<double>)),
      find.descendant(of: badge, matching: find.byType(ScaleTransition)),
      find.descendant(of: badge, matching: find.byType(FadeTransition)),
    ]) {
      expect(animated, findsNothing, reason: '状态灯内不许有任何入场 / 尺寸动画（§9.8）');
    }

    final Rect first = tester.getRect(badge);
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final Rect now = tester.getRect(badge);
      expect(now, first, reason: '第 $i 帧状态灯矩形发生了变化 ⇒ 存在动画');
    }
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // T-7.3 · 跨零点：确认卡写的道具 == 账本记的道具 == provider 的 dayKey
  //
  // ✅ **恢复执行（2026-11-07，第三批）**：极端日买棚 UI 入口已恢复 —— 从「旧条幅
  // → 停靠条」一路迁到「**天气对话框**」（点右上角状态灯弹出，玄参 2026-11-07
  // 拍板）。入口链登记：**条幅 → 停靠条 → 天气对话框（2026-11-07）**。
  // 前置步骤 = 「点 badge → pump 弹出对话框」两步，测试体其余原样未动；
  //  · 被保护的生产逻辑（`_onShelterTap` / `_buyShelterNow` / 记账链路 / §13.5
  //    同源快照纪律）一直未变；
  //  · 2026-11-06 曾因「停靠条只做状态灯、入口撤除」skip 过一轮，本次随对话框
  //    落地正式摘除 skip。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets(
      'T-7 · 跨零点（钉「动态查找的干旱日 23:59:59」，与真实今天不同日）：'
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

    // 前置（2026-11-07 入口链：状态灯 → 天气对话框）：点状态灯弹出对话框，
    // 买棚按钮（kShelterButtonHitKey）如今住在对话框里。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    final bool dialogShown = await _pumpUntilReady(
      tester,
      () => find.byKey(kGardenWeatherDialogKey).evaluate().isNotEmpty,
      maxFrames: 40,
    );
    expect(dialogShown, isTrue, reason: '点状态灯应弹出天气对话框（买棚入口）');

    // 点对话框里的「遮阳棚 · 10 ☀」→ 关对话框 + 弹确认卡（文案由页面 context
    // 取好，走 zh）。
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
        reason: '账本的 dayKey 必须与 provider 的 dayKey 一致 —— 若任何一步偷偷'
            ' `DateTime.now()`，这里会是真实今天（M-A3-9 / M-A3-10 的抓手）');
    expect(
      ledger.entries.where((SunlightEntry e) => e.refType == kWeatherShelterRefTypeRain),
      isEmpty,
      reason: '不许因跨零点写成次日的「遮雨棚」',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // T-11 · done 判据语义（第八批 ① · 玄参 2026-11-07 拍板：**买棚即 done**）
  //
  // 干旱日 done 判据 = **仅买棚**（第八批语义：干旱「浇水 ≥ 1」门槛已删，旧
  // T-11「只买棚永远 todo」守卫已反转）。只买棚不浇水 ⇒ badge **立即** done
  // （绿底对勾）+ 左侧盾牌在场 —— 买棚成功走 `_buyShelterNow` 的 setState 同帧
  // 切 done（判据已满足时无需等任何刷新，见 `_rememberWeatherBannerDone`）。
  // 本用例把新语义钉死：若有人把旧门槛加回来，这里变红。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets(
      'T-11 · 干旱日只买棚不浇水 ⇒ badge 立即 done（绿底对勾）+ 左侧盾牌在场'
      '（第八批新语义守卫：买棚即 done，浇水门槛已删）',
      (WidgetTester tester) async {
    _phoneViewport(tester);
    final String key = WeatherSystem.dayKey(_kDroughtDay);
    // 只有买棚行，**没有** plant_water 行。
    final _FakeLedger ledger = _FakeLedger()
      ..entries.add(SunlightEntry(
        id: 'a3_shelter_only',
        ts: _kDroughtDay,
        type: SunlightType.plant,
        gross: -10,
        net: -10,
        balanceAfter: 90,
        refType: kWeatherShelterRefTypeShade,
        refId: kWeatherShelterRefId,
        dayKey: key,
      ));

    await _pumpLoaded(tester, _page(today: _todayOf(_kDroughtDay), ledger: ledger));

    // badge = done：绿底白对勾角标在场，叹号退场。
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: '只买棚即 done ⇒ 角标在场（对勾）');
    expect(
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeMarkKey))
              .decoration! as BoxDecoration)
          .color,
      const Color(0xFF2E7D32),
      reason: 'done 角标 = 绿底（不是 todo 红）',
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: '买棚即 done ⇒ 对勾立即出现（无需等浇水）');
    expect(find.text('!'), findsNothing, reason: 'done 态叹号退场');
    // 棚买了 ⇒ badge 左侧盾牌在场（盾牌语义与 done 同帧齐现）。
    expect(find.byKey(kGardenWeatherBadgeShelterKey), findsOneWidget,
        reason: '已购棚 ⇒ badge 左侧盾牌在场');

    // 多跑若干帧（经济修订号触发的静默刷新重算）结论不变（重算幂等）。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: '重算幂等：只买棚的 done 重算多少次都不许闪回 todo');

    expect(tester.takeException(), isNull);
  });
}
