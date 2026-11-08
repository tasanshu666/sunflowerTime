/// A2 天气道具「搭棚」验收测试（T02 领域四态 + T03 天气行布局守卫）。
///
/// ## 覆盖什么
/// 领域层（纯 Dart，内存 Fake 仓储，零 Drift / 零 Flutter 依赖）：
///  · [PlantGrowthService.buyShelter] 的**四态**：bought / alreadyBought /
///    insufficientSunlight / notNeeded；
///  · 账本写入正确性（`refType` / `refId='garden'` / `net=-10` / `dayKey`）；
///  · 重复购买拦截（当日已有记录 → 余额与账本零变化）；
///  · 买错棚（干旱日显式传 `shelter_rain`）→ 允许写、照扣；
///  · **温和日 0 次额外 IO**（`countByRefTypeAndRefIdOnDay` 一次都不调）。
///
/// 表现层（裸 `MaterialApp` 宿主，零 Riverpod / 零数据库）：
///  · 天气行**视觉带恒定 32pt**（胶囊**槽** 32 / 按钮**视觉件** 32），温和日与极端日
///    逐位相等（A2-8 ③）；
///  · 胶囊**实体 28**，且**顶对齐 32 槽顶（槽底留 4pt）**（A2-8⑧ · PRD D-11）；
///  · 天气图标实测边长 == 18 × uiScaleOf、内容不溢出实体（A2-8⑨ · R3 不缩水）；
///  · 温和日 / 账本未读完时**不渲染**推荐道具按钮，但胶囊已渲染（A2-2）；
///  · 推荐道具按钮的命中区 ≥ 44×44（A2-10 ①②）；
///  · 320 / 360 / 390 / 414 / 768 五种宽度**零 RenderFlex overflow**（A2-8 ⑤）；
///  · 行内顺序 = `[按钮][胶囊]`（主理人裁定 M1），胶囊贴右；
///  · 中英映射同源（英文环境不出现中文兜底，A2-7）。
///
/// ## 🔴 压缩阶梯断言的口径（PRD v1.8 · A2-11 八条不变式）
///  · **不写「某宽度 = 某档位」**（A2-11⑥）—— 落档取决于 chips 的实际占用（外部量）
///    与字体口径（PRD D-14：`flutter_test` 是**方块字体**，`10 ☀` 量得 48pt、真机约
///    30pt）⇒ 换台机器 / 换个字体就红。全部改写成**不变式**：
///    ① 名字要么完整要么整体退场；② 判「半截」查 `RenderParagraph.didExceedMaxLines`；
///    ③ 价格与两个图标恒在；④ 降级顺序单调；⑤ 五个代表宽度各跑一遍。
///  · **字体口径标注（A2-11⑧）**：本文件所有落档相关结论都在
///    **flutter_test 方块字体**口径下成立；真机字体更窄 ⇒ 落档更宽松。
library weather_a2_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

import '../helpers/no_hit_random.dart';

// ── 图标槽 finder（A5-b 起图标可能是 `Image`，不再是 `Icon`）──────────────────
//
// 🔴 **为什么不能再用 `find.byIcon(weatherIconOf(kind))`**：A5-b 把天气 / 道具图标
//    换成了 288² 的 WebP 位图，`find.byIcon` 只匹配 `Icon` widget ⇒ 恒 0 命中。
//    但这几条断言的本意**不是**「必须用 Icon 画」，而是「**图标槽还在、且没被挤缩**」
//    （R3：图标永不缩水 / 兜底档只缩尺寸不删元素）。故按**契约路径或回退图标**匹配：
//    路径写错、图标被换掉，两条都会红，强度不变。
Finder _glyphOf({required String? assetPath, required IconData iconData}) =>
    find.byWidgetPredicate(
      (Widget w) =>
          (w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == assetPath) ||
          (w is Icon && w.icon == iconData),
      description: '图标槽（${assetPath ?? '(无美术)'} / $iconData）',
    );

/// 天气图标槽：位图（[weatherArtPathOf]）或回退 Material 图标。
Finder weatherGlyphOf(WeatherKind kind) => _glyphOf(
      assetPath: weatherArtPathOf(kind),
      iconData: weatherIconOf(kind),
    );

/// 道具图标槽：位图（[shelterArtPathOf]）或回退 Material 图标。
///
/// ⚠️ **已购态**的 ✓ 仍是 `Icon(Icons.check_circle_rounded)`，不在本 finder 覆盖范围内
/// （那是 §9.5 完成态语义，A2 已封版）——本 finder 只用于**未购态**断言。
Finder shelterGlyphOf(String refType) => _glyphOf(
      assetPath: shelterArtPathOf(refType),
      iconData: shelterIconOf(refType),
    );

// ── 内存 Fake 仓储（只实现本批用得到的成员）──────────────────────────────────

class _FakePlants implements PlantRepository {
  final List<Plant> store = <Plant>[];

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(store);

  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    store.removeWhere((Plant p) => p.id == plant.id);
    store.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      store.removeWhere((Plant p) => p.id == id);

  @override
  Future<List<PlantSpecies>> species() async => const <PlantSpecies>[];
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

/// 账本 Fake：**余额可控**（`initial + Σnet`），并记录查询次数
/// （用于断言「温和日 0 次额外 IO」）。
class _FakeLedger implements SunlightRepository {
  _FakeLedger({this.initial = 100});

  final double initial;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  /// `countByRefTypeAndRefIdOnDay` 的调用次数（温和日必须为 0）。
  int countCalls = 0;

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
    countCalls++;
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
  ) async =>
      null;
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

/// 组装：`buyShelter` 只需要账本 + 一堆不被本方法触碰的依赖。
({PlantGrowthService svc, _FakeLedger ledger}) _makeService({
  double balance = 100,
}) {
  final _FakeLedger ledger = _FakeLedger(initial: balance);
  final PlantGrowthService svc = PlantGrowthService(
    plants: _FakePlants(),
    focus: _FakeFocus(),
    ledger: ledger,
    settings: _FakeSettings(),
    bloomRewards: InMemoryBloomRewardRepository(),
    weedRandom: NoHitRandom(),
  );
  return (svc: svc, ledger: ledger);
}

// ── 日期挑选（**绝不手写日型**，一律走真源 `WeatherSystem.ofDay`）────────────

/// 找到第一个满足 [match] 的自然日（从 2026-11-03 起逐日往后扫）。
DateTime _findDay(bool Function(WeatherKind) match) {
  final DateTime base = DateTime(2026, 11, 3);
  for (int i = 0; i < 800; i++) {
    final DateTime day = DateTime(base.year, base.month, base.day + i, 9);
    if (match(WeatherSystem.ofDay(day).kind)) return day;
  }
  throw StateError('no matching day found within 800 days');
}

DateTime _extremeDay() => _findDay((WeatherKind k) => k.isExtreme);
DateTime _mildDay() => _findDay((WeatherKind k) => k.isMild);
DateTime _droughtDay() => _findDay((WeatherKind k) => k == WeatherKind.drought);

/// `'yyyy-MM-dd'`（与领域层 [_appendSpend] 用的 `datetime_ext.dayKey` 同口径）。
String _dayKeyOf(DateTime day) => WeatherSystem.dayKey(day);

/// 钉死的**温和日**天气快照（A3 测试接缝，设计 §13 / §10 T-6）。
///
/// ## 为什么必须钉
/// A3 起**极端日不再渲染天气胶囊**（`kWeatherRowKey` 在树里不存在），而下面三处
/// 真页面用例（`:1838` / `:2152` / `:2209`，共 **7 次执行**）原先的日型由
/// 「跑测试那天」决定 ⇒ 约 20% 的日历天上会整片变红（今天 2026-11-05 正好是
/// `drought`，改前实测全红）。
///
/// ## 处置口径（🔴 断言一行不改）
/// 把页面用的 `todayWeatherProvider` 钉到 [WeatherSystem.ofDay] 实测出来的
/// **温和日**（`_mildDay()` 从 2026-11-03 起扫描，恒返回温和日；不手写「某月某日
/// 是晴天」——那是猜）。这样 7 次执行从「依赖日历」变成「依赖显式入参」，
/// 语义与原先完全一致。
/// ⚠️ 2026-11-06（玄参拍板）后语义更新：温和日顶部**不再渲染**天气胶囊
/// （`kWeatherRowKey` 在真页面树里不存在——整体迁往底部停靠条）；钉温和日
/// 的价值不变：真页面用例与「跑测试那天是什么天气」彻底解耦。
TodayWeather _pinnedMildToday() {
  final DateTime day = _mildDay();
  return TodayWeather(
    day: WeatherSystem.ofDay(day),
    dayKey: WeatherSystem.dayKey(day),
    observedAt: day,
  );
}

// ── 表现层宿主 ──────────────────────────────────────────────────────────────

/// 按页面真实结构搭壳：`Row(spaceBetween)[chips 占位, Flexible(天气行)]`。
///
/// 这里**刻意复刻页面结构**（含 chips 占位宽度），因为 R2 的两个坑
/// （chips 漏 `MainAxisSize.min` / `_loading` 时缺少零宽占位）都只在这个结构下才暴露。
Widget _host({
  required WeatherKind kind,
  required double pageWidth,
  required double chipsWidth,
  bool showShelterButton = true,
  bool bought = false,
  bool affordable = true,
  bool chipsVisible = true,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          final Widget content = Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: pageWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    if (chipsVisible)
                      SizedBox(width: chipsWidth, child: const Text('🧩 ×3'))
                    else
                      const SizedBox.shrink(),
                    Flexible(
                      child: GardenWeatherRow(
                        key: kWeatherRowKey,
                        kind: kind,
                        shelterRefType: kind.shelterRefType,
                        bought: bought,
                        affordable: affordable,
                        showShelterButton: showShelterButton,
                        onShelterTap: () {},
                        onPillTap: null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          // 🔴 **字号放大器**：用 `MediaQuery.of(context).copyWith` 改文字缩放，
          //    保留原 `size`（`uiScaleOf` 依赖 `MediaQuery.sizeOf`）。
          if (textScale == 1.0) return content;
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: content,
          );
        },
      ),
    ),
  );
}

Future<void> _setPhoneView(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 天气行里三个「名字类」元素**在不在 widget 树里**（干旱日 + 遮阳棚口径）。
///
/// 🔴 判「在不在」必须**查 widget 树**：名字要么完整要么整体退场，
///    退场时那个 `Text` **根本不进树**（不是被 ellipsis 截短）。
({bool hint, bool shelterName, bool weatherName}) presenceOf(
  WidgetTester tester,
) {
  final AppLocalizations zh = AppLocalizationsZh();
  return (
    hint: find
        .textContaining('· ${zh.garden_weather_hint_drought}')
        .evaluate()
        .isNotEmpty,
    shelterName: find.text(zh.garden_shelter_shade).evaluate().isNotEmpty,
    weatherName: find.text(zh.weather_drought).evaluate().isNotEmpty,
  );
}

// ── A2-8④ · 真页面宿主（**真实** GardenPage）──────────────────────────────
//
// 🔴 为什么用「假仓储 + 真实页面」而不是「内存 Drift 库」：
//    页面只经 provider 取数（仓储全部可 override）⇒ 假仓储足够，且**零 IO**、
//    零插件依赖（path_provider / secure_storage / audio 都不会被拉起来）。
//    装配口径与既有用例 `test/m3/garden_layout_v3_test.dart` 的 `_realGardenTier`
//    **完全一致**（同一批 override、同一批假仓储），避免「自己搭一套宿主」。

/// 真页面用的向日葵物种（页面靠物种表把「株」渲染成花盆；缺失时网格会走空态）。
const PlantSpecies _a2Sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 本文件共享的**内存** Drift 库（真页面宿主的装配链需要它）。
///
/// 🔴 为什么共享一个、而不是每个用例各建：
///    ① drift 的「同类 DB 多实例」告警按类型计数（**不随 close 归零**，只有 close
///       本身会 −1）⇒ 每个用例各建一个会在第 2 个用例刷一屏 WARNING 栈（噪音）；
///    ② 本组所有仓储都是假的 ⇒ 这个库**从头到尾不被业务读写**，只被
///       `accountServiceProvider` / `emptyPotServiceProvider` 的装配链引用。
db.AppDatabase? _sharedMemoryDb;

/// 取（并懒建）本文件的共享内存库。
db.AppDatabase _sharedMemoryDatabase() =>
    _sharedMemoryDb ??= db.AppDatabase(NativeDatabase.memory());

/// 真页面宿主的植物仓储：**带物种表** + 植物列表。
///
/// 植物列表决定「存活株数」⇒ 一键 FAB 的出现条件（`kOneClickMinPlants` = 4）。
class _RealPagePlants implements PlantRepository {
  _RealPagePlants(this._plants);

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
      const <PlantSpecies>[_a2Sunflower];
}

/// 造 [n] 株**存活**向日葵（potIndex 0..n-1）。
///
/// 🔴 `stageStartedAt` / `plantedAt` 取**当下**（不是历史日期）—— 否则 `tickAll`
///    会把「久未养护」的株结算成死亡残株，存活株数掉到 0 ⇒ 一键 FAB 不出现。
List<Plant> _alivePlants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'a2_8_4_p$i',
      speciesId: _a2Sunflower.id,
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

/// 真页面宿主：真实 `GardenPage(embedded: true)`。
///
/// 🔴 权益必须给**买断档**：`entitlement_matrix` 里 `oneClickCare.freeEnabled = false`
///    ⇒ 免费档**不渲染**一键 FAB ⇒ 本组就量不到 FAB（用例会假绿）。
///
/// 🔴 A3 测试接缝（§13.6）：天气一律经 [todayWeatherProvider] **钉死**（缺省 = 温和日，
///    见 [_pinnedMildToday]）。三处调用点（`:1838` / `:2152` / `:2209`）因此与
///    「跑测试那天是什么天气」彻底解耦，**断言内容一行不改**（§10 T-6 / V7b）。
///    需要别的日型时显式传 `today:`（本轮无此需求，参数留作接缝）。
Widget _realGardenPage({required List<Plant> plants, TodayWeather? today}) {
  return ProviderScope(
    overrides: <Override>[
      entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
      appDatabaseProvider.overrideWithValue(_sharedMemoryDatabase()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      sunlightRepositoryProvider.overrideWithValue(_FakeLedger(initial: 100)),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      plantRepositoryProvider.overrideWithValue(_RealPagePlants(plants)),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      todayWeatherProvider.overrideWithValue(today ?? _pinnedMildToday()),
    ],
    child: const MaterialApp(
      home: Scaffold(body: GardenPage(embedded: true)),
    ),
  );
}

/// 有界帧推进：等 [ready] 为真即停。
///
/// 🔴 花园页有**无限循环**动画（木牌呼吸光晕）⇒ `pumpAndSettle` 永不返回；
///    固定帧数又会把「异步抖动」悄悄掩盖 ⇒ 用「条件 + 有界帧」，超时即失败。
Future<bool> _pumpUntilReady(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

void main() {
  // 共享内存库在**全部用例结束后**关闭（drift 的多实例计数随 close 归零）。
  tearDownAll(() async {
    await _sharedMemoryDb?.close();
    _sharedMemoryDb = null;
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('T02 · 领域层 buyShelter 四态', () {
    test('① 余额充足且当日无记录 → bought，refType 与天气同源、余额 −10', () async {
      final DateTime now = _extremeDay();
      final String? expected = WeatherSystem.ofDay(now).kind.shelterRefType;
      expect(expected, isNotNull, reason: '选出来的必须是极端日');

      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 97);
      final ShelterBuyResult r = await h.svc.buyShelter(now);

      expect(r.status, ShelterBuyStatus.bought);
      expect(r.isBought, isTrue);
      // 🔴 refType 必须与本日天气推导出来的完全一致（写错则减免永不生效）。
      expect(r.refType, expected);
      expect(r.balanceAfter, 87);
      expect(h.ledger.entries.length, 1);
      expect(await h.ledger.balance(), 87);
    });

    test('② 账本写入正确性：一行、net=-10、refType/refId/dayKey 全对', () async {
      final DateTime now = _droughtDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 100);
      await h.svc.buyShelter(now);

      final SunlightEntry e = h.ledger.entries.single;
      expect(e.net, -kWeatherShelterPrice);
      expect(e.gross, -kWeatherShelterPrice);
      expect(e.refType, kWeatherShelterRefTypeShade);
      // 🔴 「按园买」的唯一凭据：refId 必须是 'garden'，不是植物 id。
      expect(e.refId, kWeatherShelterRefId);
      expect(e.dayKey, _dayKeyOf(now));
      // 账本行自带的 balanceAfter 由仓储侧重算，应与余额一致。
      expect(e.balanceAfter, 90);
    });

    test('③ 当日已购 → alreadyBought，账本行数仍为 1、余额不变（B1 硬闸门）', () async {
      final DateTime now = _extremeDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 97);

      await h.svc.buyShelter(now);
      final double afterFirst = await h.ledger.balance();
      final ShelterBuyResult second = await h.svc.buyShelter(now);

      expect(second.status, ShelterBuyStatus.alreadyBought);
      expect(h.ledger.entries.length, 1, reason: '重复购买不许写第二行');
      expect(await h.ledger.balance(), afterFirst);
    });

    test('④ 余额不足 → insufficientSunlight(missing=1)，未扣费、账本零新增', () async {
      final DateTime now = _extremeDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: kWeatherShelterPrice - 1);

      final ShelterBuyResult r = await h.svc.buyShelter(now);

      expect(r.status, ShelterBuyStatus.insufficientSunlight);
      expect(r.missing, 1);
      expect(h.ledger.entries, isEmpty);
      expect(await h.ledger.balance(), kWeatherShelterPrice - 1);
    });

    test('⑤ 温和日不传 refType → notNeeded，且**一次账本查询都不发**（0 次额外 IO）',
        () async {
      final DateTime now = _mildDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 100);

      final ShelterBuyResult r = await h.svc.buyShelter(now);

      expect(r.status, ShelterBuyStatus.notNeeded);
      expect(r.refType, isNull);
      expect(h.ledger.entries, isEmpty);
      expect(h.ledger.countCalls, 0, reason: '温和日必须短路，不查账本');
    });

    test('⑥ 买错棚（干旱日显式传 shelter_rain）→ 允许写、照扣 10☀（PRD §4.4-2）',
        () async {
      final DateTime now = _droughtDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 100);

      final ShelterBuyResult r = await h.svc.buyShelter(
        now,
        shelterRefType: kWeatherShelterRefTypeRain,
      );

      expect(r.status, ShelterBuyStatus.bought);
      expect(r.refType, kWeatherShelterRefTypeRain);
      expect(h.ledger.entries.single.refType, kWeatherShelterRefTypeRain);
      expect(await h.ledger.balance(), 100 - kWeatherShelterPrice);
    });

    test('⑦ 四种道具各买一次 → 当日道具类账本恰 4 条（B1 后半）', () async {
      // 同一天买 4 件不同道具：显式传 refType 即可（UI 只渲染推荐件）。
      final DateTime now = _droughtDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 100);
      const List<String> all = <String>[
        kWeatherShelterRefTypeShade,
        kWeatherShelterRefTypeRain,
        kWeatherShelterRefTypeWind,
        kWeatherShelterRefTypeWarm,
      ];
      for (final String refType in all) {
        final ShelterBuyResult r =
            await h.svc.buyShelter(now, shelterRefType: refType);
        expect(r.status, ShelterBuyStatus.bought);
      }
      expect(h.ledger.entries.length, all.length);
      expect(h.ledger.entries.map((SunlightEntry e) => e.refType).toSet(),
          all.toSet());
      expect(await h.ledger.balance(), 100 - all.length * kWeatherShelterPrice);
    });

    test('⑧ isRecommended 由领域层算：买推荐件 = true，买别的 = false', () async {
      final DateTime now = _droughtDay();

      // 缺省（= 买今天的推荐件）→ true。
      final ({PlantGrowthService svc, _FakeLedger ledger}) h1 =
          _makeService(balance: 100);
      final ShelterBuyResult recommended = await h1.svc.buyShelter(now);
      expect(recommended.status, ShelterBuyStatus.bought);
      expect(recommended.isRecommended, isTrue);
      expect(recommended.refType, kWeatherShelterRefTypeShade);

      // 显式买另一件 → 允许买、照扣，但 isRecommended = false（**不减免**惩罚）。
      final ({PlantGrowthService svc, _FakeLedger ledger}) h2 =
          _makeService(balance: 100);
      final ShelterBuyResult wrong = await h2.svc.buyShelter(
        now,
        shelterRefType: kWeatherShelterRefTypeWarm,
      );
      expect(wrong.status, ShelterBuyStatus.bought);
      expect(wrong.isRecommended, isFalse);
      expect(wrong.refType, kWeatherShelterRefTypeWarm);
      expect(await h2.ledger.balance(), 100 - kWeatherShelterPrice);
    });

    test('⑨ 未知 refType → 绝不扣费写账（不收无法命名的钱）', () async {
      final DateTime now = _droughtDay();
      final ({PlantGrowthService svc, _FakeLedger ledger}) h =
          _makeService(balance: 100);

      // 契约：debug 构建里 `assert` 先炸（开发期立刻暴露「有人传了未知 refType」）；
      // release 构建里返回 `notNeeded()`。**两条路径都不许扣费、不许写账**。
      try {
        final ShelterBuyResult r =
            await h.svc.buyShelter(now, shelterRefType: 'shelter_mystery');
        expect(r.status, ShelterBuyStatus.notNeeded);
        expect(r.isRecommended, isFalse);
      } on AssertionError {
        // debug 路径：assert 已炸，仍必须零扣费（assert 在任何 IO 之前）。
      }
      expect(h.ledger.entries, isEmpty);
      expect(await h.ledger.balance(), 100);
    });

    test('⑩ 结果对象的相等性包含 isRecommended（不同推荐性不得判等）', () {
      const ShelterBuyResult a =
          ShelterBuyResult.bought('shelter_shade', 90, isRecommended: true);
      const ShelterBuyResult b =
          ShelterBuyResult.bought('shelter_shade', 90, isRecommended: false);
      const ShelterBuyResult c =
          ShelterBuyResult.bought('shelter_shade', 90, isRecommended: true);
      expect(a, c);
      expect(a.hashCode, c.hashCode);
      expect(a, isNot(b));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('T03 · 天气行布局守卫', () {
    test('映射函数：9 种日型的名字 / 图标 / 提示语中英同源（无中文兜底）', () {
      final AppLocalizations zh = AppLocalizationsZh();
      final AppLocalizations en = AppLocalizationsEn();
      for (final WeatherKind kind in WeatherKind.values) {
        // 9 种日型恒有名 + 恒有图标。
        expect(weatherNameOf(kind, zh), isNotEmpty);
        expect(weatherNameOf(kind, en), isNotEmpty);
        expect(weatherIconOf(kind), isNotNull);
        // 英文环境不得回落到中文（逐字符比较即可：两语言文案本就不等）。
        expect(weatherNameOf(kind, en), isNot(weatherNameOf(kind, zh)),
            reason: '${kind.name} 的英文名回落成了中文');
        // 大风 / 极寒**故意**没有提示语（强制动作只有买棚）。
        final String? h = weatherHintOf(kind, zh);
        final String? he = weatherHintOf(kind, en);
        if (kind == WeatherKind.wind || kind == WeatherKind.cold) {
          expect(h, isNull);
          expect(he, isNull);
        } else {
          expect(h, isNotEmpty);
          expect(he, isNotEmpty);
          expect(he, isNot(h));
        }
      }
    });

    test('映射函数：4 件道具的名字 / toast 中英同源，且与阳光明细同词', () {
      final AppLocalizations zh = AppLocalizationsZh();
      final AppLocalizations en = AppLocalizationsEn();
      const List<String> all = <String>[
        kWeatherShelterRefTypeShade,
        kWeatherShelterRefTypeRain,
        kWeatherShelterRefTypeWind,
        kWeatherShelterRefTypeWarm,
      ];
      for (final String refType in all) {
        expect(shelterNameOf(refType, zh), isNotEmpty);
        expect(shelterNameOf(refType, en), isNotEmpty);
        expect(shelterNameOf(refType, en), isNot(shelterNameOf(refType, zh)));
        expect(shelterBoughtToastOf(refType, zh), isNotEmpty);
        expect(shelterBoughtToastOf(refType, en), isNotEmpty);
        expect(shelterIconOf(refType), isNotNull);
      }
      // 与 prd_params 的四个常量逐一对上（防新增 refType 时静默漏配）。
      expect(shelterNameOf(kWeatherShelterRefTypeShade, zh), zh.garden_shelter_shade);
      expect(shelterNameOf(kWeatherShelterRefTypeRain, zh), zh.garden_shelter_rain);
      expect(shelterNameOf(kWeatherShelterRefTypeWind, zh), zh.garden_shelter_wind);
      expect(shelterNameOf(kWeatherShelterRefTypeWarm, zh), zh.garden_shelter_warm);
    });

    testWidgets('极端日与温和日的天气行**视觉带高度逐位相等**且 == 32（A2-8 ③）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);

      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));
      // 🔴 测**视觉件**（32），不是行容器（44 = 命中容器）。
      //    「遮挡了多少」由视觉件决定；容器高只是为了让 44 的命中盒成立。
      //    两者混用 ⇒ 断言会测错盒子（这是本批踩过的坑）。
      // 🔴 **测的是「槽」不是「实体」**（PRD D-11）：`kWeatherPillSlotKey` = 32
      //    （透明度量容器，保证视觉带恒 32）；`kWeatherPillKey` = **实体 28**
      //    （与 chips 同族）。实体高度由 A2-8⑧ 单独断言。
      final double extremeBtnH =
          tester.getSize(find.byKey(kShelterButtonVisualKey)).height;
      final double extremePillH =
          tester.getSize(find.byKey(kWeatherPillSlotKey)).height;

      await tester.pumpWidget(_host(
        kind: WeatherKind.sunny,
        pageWidth: 390,
        chipsWidth: 179,
      ));
      final double mildPillH =
          tester.getSize(find.byKey(kWeatherPillSlotKey)).height;

      // 🔴 **期望值写死 32**（**不引用 kWeatherRowHeight**）——
      //    引用同一常量时，常量本身被改会两边一起变 ⇒ 断言恒绿 ⇒ 抓不到。
      //    32 是 PRD §5.0 高度预算表的**产品口径**，不是「实现当前是多少」。
      expect(extremeBtnH, 32, reason: '按钮视觉件必须恒 32');
      expect(extremePillH, 32, reason: '胶囊**槽**必须恒 32');
      expect(mildPillH, 32, reason: '胶囊**槽**必须恒 32');
      expect(extremePillH, mildPillH,
          reason: '极端日不得比温和日高（顶部不许跳动）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('胶囊**实体 28** 且**顶对齐 32 槽顶（槽底留 4pt）**（A2-8⑧）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));

      // 🔴 **A2-8⑧ 是唯一能测出「实体被改成 32」的断言**（PRD D-11）：
      //    32 实体装进 32 槽时，槽高与按钮高照样是 32、A2-8③ 会全绿放行。
      final Rect slot = tester.getRect(find.byKey(kWeatherPillSlotKey));
      final Rect entity = tester.getRect(find.byKey(kWeatherPillKey));

      // 🔴 **期望值写死 28 / 32**（**不引用 kWeatherPillHeight /
      //    kWeatherPillSlotHeight**）—— 引用同一常量时，常量本身被改会两边
      //    一起变 ⇒ 断言恒绿 ⇒ 抓不到。28 / 32 是 PRD §5.2 的**产品口径**。
      expect(entity.height, closeTo(28, 0.5),
          reason: '胶囊实体必须恒 28（与 chips 同族），不能被槽拉回 32');
      expect(slot.height, closeTo(32, 0.5),
          reason: '胶囊槽必须恒 32（视觉带恒定由它保证）');
      // 🔴 **顶对齐**（T07-②）：实体顶 == 槽顶（与 chips 视觉顶齐边），
      //    多出来的 4pt 全部留在**槽底**（透明）。
      expect(entity.top - slot.top, closeTo(0, 0.5),
          reason: '实体顶必须 == 槽顶（顶对齐，实体顶与 chips 顶齐边）');
      expect(slot.bottom - entity.bottom, closeTo(4, 0.5),
          reason: '槽底必须留 4pt 透明（32 − 28 = 4，全在底部）');
      // 🔴 实体与槽**不得**同高（那正是被撤回的 PRD v1.6 形态）。
      expect(entity.height, lessThan(slot.height),
          reason: '实体 28 必须矮于槽 32 —— 同高即说明实体被拉回去了');
      expect(tester.takeException(), isNull);
    });

    testWidgets('天气图标实测边长 == 18 × uiScaleOf，且内容不溢出实体（A2-8⑨）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));

      // 🔴 **A2-8⑨：图标边长必须被单独实测**（PRD v1.9 §5.2「图标 18 × uiScaleOf」）。
      //    为什么必须实测、不能只信常量：
      //    「图标不缩水」是 R3 硬要求（层级表达：天气 > 资源）⇒ 一旦图标被
      //    `FittedBox` / `Flexible` / 约束挤小，**宽度不会变**、**overflow 也不会报**
      //    ⇒ 只测「实体高 28」「零 overflow」都抓不到图标被缩。
      final double uiScale =
          uiScaleOf(tester.element(find.byKey(kWeatherPillKey)));
      final Size iconSize =
          tester.getSize(weatherGlyphOf(WeatherKind.drought));

      // 🔴 **期望值写死 18**（**不引用 kWeatherPillIconSize**）——
      //    引用同一常量时，常量本身被改（18 → 16）会两边一起变 ⇒ 断言恒绿
      //    ⇒ 抓不到。18 是 PRD §5.2 的**产品口径**（天气 > 资源的层级差）。
      expect(iconSize.width, closeTo(18 * uiScale, 0.5),
          reason: '天气图标宽必须 == 18 × uiScaleOf（图标**不许缩水**）');
      expect(iconSize.height, closeTo(18 * uiScale, 0.5),
          reason: '天气图标高必须 == 18 × uiScaleOf（图标**不许缩水**）');
      expect(iconSize.width, closeTo(iconSize.height, 0.5),
          reason: '天气图标必须是正方形');

      // 实体高 == 28 × uiScaleOf（图标 18 装得下 ⇒ 纵向等效留白 = (28 − 18) / 2 = 5）。
      expect(tester.getSize(find.byKey(kWeatherPillKey)).height,
          closeTo(28 * uiScale, 0.5),
          reason: '胶囊实体高必须 == 28 × uiScaleOf（28 写死，不引用实现常量）');

      // 内容不溢出：图标的矩形必须**完整落在**实体矩形内（纵向等效留白 = 5）。
      final Rect entity = tester.getRect(find.byKey(kWeatherPillKey));
      final Rect icon = tester.getRect(weatherGlyphOf(WeatherKind.drought));
      expect(icon.top, greaterThanOrEqualTo(entity.top - 0.5),
          reason: '天气图标不得顶出实体上沿');
      expect(icon.bottom, lessThanOrEqualTo(entity.bottom + 0.5),
          reason: '天气图标不得底出实体下沿');
      expect(icon.left, greaterThanOrEqualTo(entity.left - 0.5),
          reason: '天气图标不得左出实体');
      expect(icon.right, lessThanOrEqualTo(entity.right + 0.5),
          reason: '天气图标不得右出实体');
      expect(tester.takeException(), isNull,
          reason: '内容不得溢出（RenderFlex overflow / 负约束）');
    });

    testWidgets('极窄屏 + 大字号（1.3×）不得崩：槽宽永远非负，缩放交给 FittedBox 兜底',
        (WidgetTester tester) async {
      // 🔴 **回归守卫**（2026-11-03 实测崩溃）：320×568 + textScaler 1.3 + 3 位数
      //    chips 时，胶囊的「分配额」= 可用宽 − 按钮命中宽 − 间距 − 外扩 会变成
      //    **负数** ⇒ 旧实现 `SizedBox(width: 负数)` ⇒
      //    `BoxConstraints has a negative minimum width` ⇒ **整页崩**。
      //    修法：槽宽 = 胶囊的**自然宽**（预算只决定「丢哪个元素」），
      //    真的放不下时由外层 `FittedBox(scaleDown)` 等比缩整行。
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 320,
        chipsWidth: 240,
        textScale: 1.3,
      ));

      expect(tester.takeException(), isNull,
          reason: '极窄屏 + 大字号不得抛异常（槽宽为负会崩）');
      // 兜底档只是**缩尺寸**，不删元素 ⇒ 价格与两个图标仍在（R3）。
      expect(find.text('10 ☀', skipOffstage: false),
          findsOneWidget,
          reason: '兜底档不许把价格吞掉');
      expect(shelterGlyphOf(kWeatherShelterRefTypeShade),
          findsOneWidget,
          reason: '兜底档不许把道具图标吞掉');
      expect(weatherGlyphOf(WeatherKind.drought), findsOneWidget,
          reason: '兜底档不许把天气图标吞掉');
      // 槽宽必须非负（直接量槽的宽度，负数会立刻炸在 `SizedBox` 上）。
      expect(tester.getSize(find.byKey(kWeatherPillSlotKey)).width,
          greaterThanOrEqualTo(0));
    });

    testWidgets('温和日：按钮整条不渲染、无灰色占位；胶囊已渲染（PRD §4.5）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.sunny,
        pageWidth: 390,
        chipsWidth: 179,
      ));

      expect(find.byKey(kWeatherPillKey), findsOneWidget);
      expect(find.byType(ShelterBuyButton), findsNothing);
      // 「没事可做」本身也是信息：温和日仍要显示天气名。
      expect(find.text(zhSunnyText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('`showShelterButton: false`（账本未读完）：按钮不渲染、胶囊已渲染（A2-2）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        showShelterButton: false,
      ));

      expect(find.byKey(kWeatherPillKey), findsOneWidget);
      expect(find.byType(ShelterBuyButton), findsNothing,
          reason: '加载完成前不许出现「买」字闪一下又变');
      expect(tester.takeException(), isNull);
    });

    testWidgets('行内顺序 = [按钮][胶囊]，胶囊贴右（主理人裁定 M1）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));

      final Rect btn = tester.getRect(find.byKey(kShelterBuyButtonKey));
      final Rect pillHit = tester.getRect(find.byKey(kWeatherPillHitKey));
      // 🔴 贴右对齐的那一层是**槽**（`kWeatherPillSlotKey`）；实体与槽同宽
      //    （实体的宽度被槽的 tight 宽钉死）⇒ 两个 key 的右缘相同。
      final Rect pillSlot = tester.getRect(find.byKey(kWeatherPillSlotKey));
      final Rect pillEntity = tester.getRect(find.byKey(kWeatherPillKey));
      final Rect row = tester.getRect(find.byKey(kWeatherRowKey));
      expect(btn.right, lessThanOrEqualTo(pillHit.left), reason: '按钮必须在胶囊左侧');
      // 胶囊贴右：**命中盒**的右边缘即行右边缘（误差 ≤ 0.5 由对齐取整产生）。
      expect((row.right - pillHit.right).abs(), lessThanOrEqualTo(0.5));
      // 命中盒比视觉件宽 10pt（水平外扩左 4 / 右 6）⇒ 视觉槽比行右边缘内缩 6pt。
      expect((pillHit.right - pillSlot.right), closeTo(kHitPadRight, 0.5),
          reason: '胶囊槽的右边缘必须比命中盒内缩 kHitPadRight（右 6pt）');
      expect((pillSlot.right - pillEntity.right).abs(), lessThanOrEqualTo(0.5),
          reason: '实体与槽同宽（右缘必须重合）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('推荐道具按钮命中区 ≥ 44×44（A2-10 ①②）', (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));
      final Size s = tester.getSize(find.byKey(kShelterBuyButtonKey));
      // 🔴 **期望值写死 44 / 32**（**不引用 kMinTapTarget / kShelterButtonHeight**）——
      //    引用同一常量时，常量本身被改会两边一起变 ⇒ 断言恒绿 ⇒ 抓不到。
      //    44 是 PRD §5.2.1 的**产品口径**（热区 ≥44×44），32 是按钮视觉高。
      expect(s.height, greaterThanOrEqualTo(44));
      expect(s.width, greaterThanOrEqualTo(44));
      // 「热区比看起来大」必须成立：视觉高只有 32。
      expect(s.height, greaterThan(32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('已购 / 灰态同样可点，命中区不缩水（不回退 onTap: null，F166）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      for (final bool bought in <bool>[true, false]) {
        for (final bool affordable in <bool>[true, false]) {
          await tester.pumpWidget(_host(
            kind: WeatherKind.drought,
            pageWidth: 390,
            chipsWidth: 179,
            bought: bought,
            affordable: affordable,
          ));
          final Size s = tester.getSize(find.byKey(kShelterBuyButtonKey));
          expect(s.height, greaterThanOrEqualTo(44),
              reason: 'bought=$bought affordable=$affordable（44 写死，PRD §5.2.1）');
          // 三种状态都必须真的能收到点击。
          final Finder ink = find.descendant(
            of: find.byType(ShelterBuyButton),
            matching: find.byType(InkWell),
          );
          final InkWell well = tester.widget<InkWell>(ink.first);
          expect(well.onTap, isNotNull,
              reason: 'bought=$bought affordable=$affordable 时按钮不得真空禁');
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 / 360 / 390 / 414 / 768 五种宽度零 overflow（A2-8 ⑤）',
        (WidgetTester tester) async {
      // chipsWidth 取 PRD §5.3 的口径：3 位数 ≈ 200，其余 ≈ 179。
      const List<(double, double)> cases = <(double, double)>[
        (320, 200),
        (360, 179),
        (390, 179),
        (414, 179),
        (768, 179),
      ];
      for (final (double pageWidth, double chipsWidth) in cases) {
        for (final bool button in <bool>[true, false]) {
          tester.view.physicalSize = Size(pageWidth * 2, 844 * 2);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(_host(
            kind: WeatherKind.rainstorm,
            pageWidth: pageWidth,
            chipsWidth: chipsWidth,
            showShelterButton: button,
          ));
          expect(tester.takeException(), isNull,
              reason: 'width=$pageWidth chips=$chipsWidth button=$button 发生溢出');
          // 任何宽度下道具图标 + 价格都必须在（R3：永不省略/截断）。
          if (button) {
            expect(find.text('10 ☀', skipOffstage: false),
                findsOneWidget,
                reason: 'width=$pageWidth 时价格被吞掉了');
          }
        }
      }
    });

    testWidgets('账本未读完时右端不跳位（左侧留零宽占位，避免首帧后横移）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        chipsVisible: false,
      ));
      final Rect loadingPill = tester.getRect(find.byKey(kWeatherPillSlotKey));

      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
      ));
      final Rect loadedPill = tester.getRect(find.byKey(kWeatherPillSlotKey));

      // 胶囊右边缘两帧一致（chips 出现不会把胶囊挤走）。
      expect((loadedPill.right - loadingPill.right).abs(),
          lessThanOrEqualTo(0.5));
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('A2-11 · 压缩阶梯（PRD v1.8 八条不变式口径）', () {
    // 🔴 **口径纪律（A2-11⑥ + D-14）**：本组**不写**「某屏宽 = 某档位」这类断言 ——
    //    落档取决于 chips 的实际占用（**外部量**）与字体口径（`flutter_test` 用
    //    **方块字体**：`10 ☀` 量得 48pt、真机约 30pt）⇒ 换台机器 / 换个字体就红。
    //    全部改写成**不变式**（A2-11①~⑤）。
    //
    // 🔴 **判「半截」必须查渲染树**（A2-11② / ⑦）：`TextOverflow.ellipsis` 是
    //    **渲染期**行为，`Text.data` 本身仍是完整字符串 ⇒ 看文本内容会漏判；
    //    唯一可靠的判据是 `RenderParagraph.didExceedMaxLines`。
    //
    // 🔴 **字体口径标注（A2-11⑧）**：本组全部结论都在 **flutter_test 方块字体**
    //    口径下成立；真机字体更窄 ⇒ 落档更宽松（更不容易降级）。

    /// PRD A2-11⑤ 规定的五个代表宽度（pageWidth, chipsWidth）。
    ///
    /// 🔴 chips 宽度按 PRD §5.3 的口径取「3 位数 ≈ 200、其余 ≈ 179」⇒ 可用宽
    ///    （= pageWidth − 24 − chips）依次是 **96 / 157 / 187 / 211 / 565**，
    ///    **单调递增** —— 正好用来断言「变窄 ⇒ 只会更省」。
    const List<(double, double)> widths = <(double, double)>[
      (320, 200), // SE1 + 3 位数 chips：最窄
      (360, 179), // 主流安卓小屏
      (390, 179), // 主力机型
      (414, 179), // 大屏手机
      (768, 179), // 平板竖屏
    ];

    /// 当前宽度下「三个可降级元素各自在不在」的快照。
    /// 切到 [pageWidth] 的视口并搭好宿主（五个宽度共用同一条路径）。
    Future<void> pumpRow(
      WidgetTester tester,
      double pageWidth,
      double chipsWidth, {
      WeatherKind kind = WeatherKind.drought,
    }) async {
      tester.view.physicalSize = Size(pageWidth * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        kind: kind,
        pageWidth: pageWidth,
        chipsWidth: chipsWidth,
      ));
    }

    testWidgets('A2-11③ · 价格「10 ☀」与两个图标**任何宽度都必留**（永不省略 / 截断）',
        (WidgetTester tester) async {
      for (final (double pageWidth, double chipsWidth) in widths) {
        await pumpRow(tester, pageWidth, chipsWidth);

        // ① 价格：完整文本在树里（不是一个被截断的片段）。
        expect(find.text('10 ☀', skipOffstage: false),
            findsOneWidget,
            reason: 'width=$pageWidth：价格被吞掉了');
        // ② 道具图标 + 天气图标：都在。
        expect(shelterGlyphOf(kWeatherShelterRefTypeShade),
            findsOneWidget,
            reason: 'width=$pageWidth：道具图标不见了');
        expect(weatherGlyphOf(WeatherKind.drought), findsOneWidget,
            reason: 'width=$pageWidth：天气图标不见了');
        // ③ 320 + 3 位数 chips（可用 96）走的是**兜底档**（`FittedBox(scaleDown)`
        //    等比缩整行）—— 缩的是尺寸不是内容 ⇒ 这条也必须成立。
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('M-I · 表现层价格字面量守卫：未购态按钮恒显示「10 ☀」且位于按钮视觉件内',
        (WidgetTester tester) async {
      // 🔴 **L2 纪律（期望值独立于实现）**：这里**刻意不引用** `kWeatherShelterPrice`
      //    —— 「10 ☀」是 PRD §5.2 钉死的产品口径。若有人把领域层常量改成 9 / 12，
      //    本断言**不会跟着变绿**，会立刻抓到「表现层渲染值与产品口径不符」。
      //    （领域层 T02 组校验「买断扣 10 颗」逻辑；本组只锁「屏幕上画出来的字」。）
      await _setPhoneView(tester, 390);
      for (final bool bought in <bool>[false, true]) {
        for (final bool affordable in <bool>[true, false]) {
          await tester.pumpWidget(_host(
            kind: WeatherKind.drought,
            pageWidth: 390,
            chipsWidth: 179,
            bought: bought,
            affordable: affordable,
          ));
          if (bought) {
            // 已购态：按钮变「✅ 已搭好」，不再显示购买价格（R3 不约束已购态）。
            expect(find.text('10 ☀', skipOffstage: false), findsNothing,
                reason: 'bought=$bought 已购态不应再显示购买价格');
          } else {
            // 未购态（含灰态 / 买得起态）：价格字面量「10 ☀」必须显示（R3 不省略 / 不截断）。
            final Finder priceText = find.text('10 ☀', skipOffstage: false);
            expect(priceText, findsOneWidget,
                reason: 'bought=$bought affordable=$affordable：'
                    '价格「10 ☀」必须显示');
            // 价格必须落在按钮视觉件（kShelterButtonVisualKey）之内，不是飘在行外。
            expect(
              find.descendant(
                of: find.byKey(kShelterButtonVisualKey),
                matching: priceText,
              ),
              findsOneWidget,
              reason: 'bought=$bought affordable=$affordable：'
                  '价格必须位于按钮视觉件内',
            );
          }
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('A2-11①② · 名字要么完整、要么整体退场（查渲染树，绝不半截）',
        (WidgetTester tester) async {
      final AppLocalizations zh = AppLocalizationsZh();
      for (final (double pageWidth, double chipsWidth) in widths) {
        await pumpRow(tester, pageWidth, chipsWidth);

        // ① 名字只有两种合法状态：**完整在树里**（1 个）或**整体不在树里**（0 个）。
        //    「半截」是第三个状态，不许存在。
        final Map<String, String> names = <String, String>{
          '天气名': zh.weather_drought,
          '道具名': zh.garden_shelter_shade,
        };
        for (final MapEntry<String, String> entry in names.entries) {
          final Finder finder = find.text(entry.value);
          final int count = finder.evaluate().length;
          expect(count, anyOf(0, 1),
              reason: 'width=$pageWidth：${entry.key}出现了 $count 个 —— '
                  '半截名字是第三个状态，不许存在');
          if (count == 1) {
            // ② 在树里 ⇒ 必须**完整**：渲染时不得超行（超行 = 被 ellipsis 截断）。
            final RenderParagraph para =
                tester.renderObject<RenderParagraph>(finder);
            expect(para.didExceedMaxLines, isFalse,
                reason: 'width=$pageWidth：${entry.key}「${entry.value}」被截断了 —— '
                    '名字只允许完整出现或整体消失');
          }
        }

        // 提示语（以 '· ' 开头）是**唯一**允许 ellipsis 的元素 ⇒ 除它之外，
        // 任何 Text 都不得在渲染时被截断（查渲染树，不看文本内容）。
        for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
          final String data = text.data ?? '';
          if (data.startsWith('· ')) continue;
          final RenderParagraph para =
              tester.renderObject<RenderParagraph>(find.byWidget(text));
          expect(para.didExceedMaxLines, isFalse,
              reason: 'width=$pageWidth：「$data」在渲染时被截断了');
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('A2-11④ · 降级顺序单调：提示语 → 道具名 → 天气名（不倒转、不跳档）',
        (WidgetTester tester) async {
      final List<({double width, bool hint, bool shelterName, bool weatherName})>
          snaps =
          <({double width, bool hint, bool shelterName, bool weatherName})>[];

      for (final (double pageWidth, double chipsWidth) in widths) {
        await pumpRow(tester, pageWidth, chipsWidth);
        final ({bool hint, bool shelterName, bool weatherName}) p =
            presenceOf(tester);
        snaps.add((
          width: pageWidth,
          hint: p.hint,
          shelterName: p.shelterName,
          weatherName: p.weatherName,
        ));
      }

      // ① 阶梯顺序（不得跳档、不得倒转）：
      //    · 道具名整体退场 ⇒ 提示语必须**已经**不在（提示语是第一个被牺牲的）；
      //    · 天气名整体退场 ⇒ 道具名必须**已经**不在。
      for (final ({double width, bool hint, bool shelterName, bool weatherName}) s
          in snaps) {
        if (!s.shelterName) {
          expect(s.hint, isFalse,
              reason: 'width=${s.width}：道具名整体退场了，提示语却还在 —— '
                  '降级顺序倒转（提示语必须先于道具名被牺牲）');
        }
        if (!s.weatherName) {
          expect(s.shelterName, isFalse,
              reason: 'width=${s.width}：天气名整体退场了，道具名却还在 —— '
                  '降级顺序倒转（道具名必须先于天气名被牺牲）');
        }
      }

      // ② 变窄 ⇒ 只会更省（单调）：可用宽单调递增，
      //    「宽的那一档已经缺的」绝不允许在「窄的那一档」里重新出现。
      for (int i = 0; i + 1 < snaps.length; i++) {
        final ({double width, bool hint, bool shelterName, bool weatherName})
            narrow = snaps[i];
        final ({double width, bool hint, bool shelterName, bool weatherName})
            wide = snaps[i + 1];
        if (!wide.hint) {
          expect(narrow.hint, isFalse,
              reason: '宽度 ${narrow.width} → ${wide.width}：宽的一档提示语已经没了，'
                  '窄的一档却又出现 —— 降级不是单调的：$snaps');
        }
        if (!wide.shelterName) {
          expect(narrow.shelterName, isFalse,
              reason: '宽度 ${narrow.width} → ${wide.width}：宽的一档道具名已经没了，'
                  '窄的一档却又出现 —— 降级不是单调的：$snaps');
        }
        if (!wide.weatherName) {
          expect(narrow.weatherName, isFalse,
              reason: '宽度 ${narrow.width} → ${wide.width}：宽的一档天气名已经没了，'
                  '窄的一档却又出现 —— 降级不是单调的：$snaps');
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('温和日没有按钮 ⇒ 胶囊独占整行（名字不会被牺牲）',
        (WidgetTester tester) async {
      final AppLocalizations zh = AppLocalizationsZh();
      // 🔴 **余量结论**（不是「某宽度 = 某档位」的档位结论）：
      //    可用宽 = 320 − 24 − 179 = **117**；
      //    胶囊「名 + 命中盒外扩」= 图标 18 + gap 4 + 名 52 + 内距 16 + 外扩 10
      //    = **100** ≤ 117 ⇒ 名字**必然完整**（两种字体口径都成立：CJK 字宽 = 字号）。
      await pumpRow(tester, 320, 179, kind: WeatherKind.sunny);
      expect(find.text(zh.weather_sunny), findsOneWidget,
          reason: '温和日没有按钮，胶囊独占整行 ⇒ 天气名必须完整');
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('T04 · 页面骨架的垂直锚点（A2-8⑥：视觉顶必须落在 y=12）', () {
    /// 复刻 `garden_page.dart` 的浮层结构：根 Stack + `Positioned(top: 12−6)` +
    /// `Row(spaceBetween)[chips(Padding top: 6), 天气行]`。
    ///
    /// 🔴 `crossAxisAlignment: start` 是**必填项**：命中容器 44 高、chips 只有
    ///    28+6 = 34 高，若用默认的 `center` 对齐，chips 会被压低 (44−34)/2 = 5pt
    ///    ⇒ **既有资源 chips 的视觉位置逐位变化**（A1 基线回归）。
    Widget pageSkeleton({required double pageWidth, required double chipsWidth}) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned(
                left: 12,
                right: 12,
                top: 12 - 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        width: chipsWidth,
                        child: const Text('🧩 ×3'),
                      ),
                    ),
                    Flexible(
                      child: GardenWeatherRow(
                        key: kWeatherRowKey,
                        kind: WeatherKind.drought,
                        shelterRefType: WeatherKind.drought.shelterRefType,
                        bought: false,
                        affordable: true,
                        showShelterButton: true,
                        onShelterTap: () {},
                        onPillTap: null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('按钮 / 胶囊 / chips 三者的视觉顶都落在 y=12（A2-8⑥ + A1 基线）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(pageSkeleton(pageWidth: 390, chipsWidth: 179));

      expect(tester.getRect(find.byKey(kShelterButtonVisualKey)).top,
          closeTo(12, 0.5),
          reason: '按钮视觉顶必须落在 y=12（`Positioned.top` 已 −6，命中带再 +6）');
      // 🔴 A2-8⑥ 断言的是「**视觉带顶**」= 胶囊**槽**的顶（32 高，与按钮视觉件
      //    同高同位）；**实体**（28）**顶对齐槽顶**（T07-②）⇒ 实体顶也落在 **12**
      //    —— 与 chips 的视觉顶逐位齐边。
      expect(tester.getRect(find.byKey(kWeatherPillSlotKey)).top,
          closeTo(12, 0.5),
          reason: '胶囊**槽**顶必须落在 y=12（视觉带恒 32）');
      // 实体顶对齐槽顶（= 0 偏移）⇒ 实体顶同样落在 y=12，与 chips 齐边。
      final Rect pillSlot = tester.getRect(find.byKey(kWeatherPillSlotKey));
      final Rect pillEntity = tester.getRect(find.byKey(kWeatherPillKey));
      expect(pillEntity.top - pillSlot.top, closeTo(0, 0.5),
          reason: '实体顶对齐槽顶（顶对齐，不是 2，也不是 6）');
      expect(pillEntity.height, closeTo(28, 0.5),
          reason: '胶囊实体必须恒 28（与 chips 同族；28 写死，不引用实现常量）');
      expect(tester.getRect(find.text('🧩 ×3')).top, closeTo(12, 0.5),
          reason: '既有 chips 的视觉顶必须**逐位不变**（y=12）—— '
              '行容器若用默认的 center 对齐，34 高的 chips 会被 44 高的命中容器压低 5pt');
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('T03 · 压缩阶梯纯函数（PRD §5.3 契约 · 设计文档 §3.2）', () {
    // 🔴 档位决策是**纯函数**（零 widget / 零 context）⇒ 宽度边界可以在纯 Dart
    //    单测里穷举，不必 pump 任何东西 —— 这是 PRD A2-11 的可测性来源。
    //
    // 🔴 **口径纪律（A2-11⑥）**：本组断言的是**函数的显式入参 ⇒ 输出的关系**
    //    （函数契约），**不是**「某屏宽 = 某档位」的环境结论 —— 这里的宽度是
    //    调用方直接传进来的数字，与 chips 的实际占用、字体口径**都无关**
    //    ⇒ 换机器 / 换字体不会红。屏幕级的「宽度 → 落档」结论一律降级为
    //    **不变式**断言（见上面的 A2-11 组）。
    //
    // 🔴 **字体口径标注（A2-11⑧）**：下面的宽度是**合成的自洽数字**，只用来验证
    //    函数契约；真实落档宽度由 `TextPainter` 实测得出，随字体口径变化
    //    （PRD D-14：`flutter_test` 方块字体比真机宽 18pt）。

    /// 一组**自洽**的宽度：阶梯必须单调递减
    /// （full ≥ hintTruncated ≥ noHint ≥ noShelterName ≥ noWeatherName）。
    ///
    /// 🔴 `hintTruncated` 与 `noHint` 是**两个不同的门槛**（架构师 R23）：
    ///    · `widthHintTruncated` = 提示语**被截断**到最小位仍放得下；
    ///    · `widthNoHint` = 提示语**整句消失**、两个名字都完整仍放得下（**不含** 24pt 位）。
    ///    两者的差 = 最小提示语位 ⇒ `noHint` 档的生存区间非空 ⇒ 该档可达。
    const double widthFull = 200;
    const double widthHintTruncated = 160;
    const double widthNoHint = 140;
    const double widthNoShelterName = 120;
    const double widthNoWeatherName = 80;

    /// 纯函数调用（唯一入口：宽度全部由调用方**显式**传入）。
    WeatherRowTier pick(double available) => resolveWeatherRowTier(
          availableWidth: available,
          widthFull: widthFull,
          widthHintTruncated: widthHintTruncated,
          widthNoHint: widthNoHint,
          widthNoShelterName: widthNoShelterName,
          widthNoWeatherName: widthNoWeatherName,
        );

    test('纯函数契约：取「第一个放得下的档」，都放不下就取最省档（兜底）', () {
      expect(pick(widthFull), WeatherRowTier.full,
          reason: '恰好等于完整态需求 ⇒ 完整态');
      expect(pick(widthFull + 0.01), WeatherRowTier.full,
          reason: '比完整态还宽 ⇒ 仍是完整态');
      expect(pick(widthHintTruncated), WeatherRowTier.hintTruncated,
          reason: '恰好等于「提示语截断」档的需求 ⇒ 该档');
      expect(pick(widthHintTruncated - 0.01), WeatherRowTier.noHint,
          reason: '差 0.01 就必须再降一档（提示语整句消失）');
      expect(pick(widthNoHint), WeatherRowTier.noHint,
          reason: '恰好等于「提示语整句消失」档的需求 ⇒ 该档（两个名字都完整）');
      expect(pick(widthNoHint - 0.01), WeatherRowTier.noShelterName,
          reason: '差 0.01 就必须再降一档（道具名让位）');
      expect(pick(widthNoShelterName), WeatherRowTier.noShelterName);
      expect(pick(widthNoShelterName - 0.01), WeatherRowTier.noWeatherName);
      expect(pick(widthNoWeatherName), WeatherRowTier.noWeatherName);
      expect(pick(widthNoWeatherName - 0.01), WeatherRowTier.noWeatherName,
          reason: '连最省形态都放不下 ⇒ 仍是最省档（外层 FittedBox 负责等比收尾）');
      expect(pick(0), WeatherRowTier.noWeatherName);
    });

    test('档位随可用宽**单调降级**（不会出现「降一档又把名字加回来」）', () {
      final List<WeatherRowTier> ladder = <WeatherRowTier>[
        for (final double w in <double>[
          400, 250, 201, 200, 199, 161, 160, 159, 141, 140, 139, 121, 120, 119,
          81, 80, 79, 10,
        ])
          pick(w),
      ];
      for (int i = 1; i < ladder.length; i++) {
        expect(ladder[i].index, greaterThanOrEqualTo(ladder[i - 1].index),
            reason: '宽度变窄时档位只能更省，不能回退：$ladder');
      }
    });

    test('枚举顺序 = 降级顺序（提示语 → 道具名 → 天气名，**不许重排**）', () {
      expect(WeatherRowTier.full.index,
          lessThan(WeatherRowTier.hintTruncated.index),
          reason: '完整态必须排在「提示语截断」之前');
      expect(WeatherRowTier.hintTruncated.index,
          lessThan(WeatherRowTier.noHint.index),
          reason: '「提示语截断」必须排在「提示语整句消失」之前');
      expect(WeatherRowTier.noHint.index,
          lessThan(WeatherRowTier.noShelterName.index),
          reason: '提示语档必须排在「省道具名」之前');
      expect(WeatherRowTier.noShelterName.index,
          lessThan(WeatherRowTier.noWeatherName.index),
          reason: '「省道具名」必须排在「省天气名」之前');
    });

    // ── T07-④ 4a · 死枚举守卫（本批最重要的一条新增契约）────────────────────
    //
    // 🔴 **为什么必须有这条**（架构师 K25/K28 的直接产出）：
    //    「某一档永不返回」**不违反任何不变式** —— 图标恒在、名字整存整取、
    //    零 overflow、视觉带恒 32 **全都照样成立** ⇒
    //    ① 不变式断言**抓不到**它；② 编译器也抓不到（`case noHint` 存在但永不命中）；
    //    ③ QA 的变异测试也抓不到（它只测「不变式被破坏」）。
    //    ⇒ 只能靠「**穷举宽度 → 收集命中的档位集合 → 与枚举全集比对**」这条
    //    **契约测试**抓出来。
    test('纯函数契约：5 档全部可达（每档至少命中一次 —— 防死枚举）', () {
      // 🔴 口径纪律（A2-11⑥）：这里的宽度是**函数的显式入参**，
      //    与 chips 实际占用、字体口径**都无关** ⇒ 换机器 / 换字体不会红。
      //    宽度集合自洽且单调递减，使 5 档的生存区间互不重叠：
      //    full 200 / hintTruncated 160 / noHint 140 / noShelterName 120 /
      //    noWeatherName 80。
      //
      // 🔴 `hintTruncated` 与 `noHint` 的差 = 20（模拟 `kWeatherHintMinWidth` 位）
      //    ⇒ `noHint` 档的生存区间宽度 **20 > 0** ⇒ 该档**可达**。
      //    （架构师 R23 恒等式：两档门槛之差 = 最小提示语位 ⇒ 非空 ⇒ 可达。）
      final Set<WeatherRowTier> hit = <WeatherRowTier>{};
      for (double w = 0; w <= 400; w += 0.5) {
        hit.add(resolveWeatherRowTier(
          availableWidth: w,
          widthFull: 200,
          widthHintTruncated: 160,
          widthNoHint: 140,
          widthNoShelterName: 120,
          widthNoWeatherName: 80,
        ));
      }
      final List<WeatherRowTier> missing = WeatherRowTier.values
          .where((WeatherRowTier t) => !hit.contains(t))
          .toList();
      expect(missing, isEmpty,
          reason: '每个枚举档位都必须有可达判据 —— 死枚举编译器与不变式断言都抓不到。'
              '实际命中的档位：${hit.map((WeatherRowTier t) => t.name).join('、')}；'
              '**不可达的档位：${missing.map((WeatherRowTier t) => t.name).join('、')}**');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('T07 · 铁律 D · 判据量的定义式（架构师 v1.11 §3.2 · D-1 / D-2 + 铁律 B）', () {
    // 🔴 **铁律 D 的由来**（架构师裁定）：「不变式断言只能守住不变量，守不住档位序列」
    //    ⇒ 光有「5 档全部可达」（4a 守卫）**不够**：必须**直接断言判据量的定义式**，
    //    否则下次有人把公式改错（例：把 `widthNoHint` 又写回含 24pt 提示语位）
    //    一样全绿。
    //
    // 🔴 **D-1 的纪律**：判据量必须**由实现直接暴露**（[computeWeatherRowWidths]），
    //    测试**直接调用**它拿真值；**绝对不许在测试里复算公式**
    //    （复算 = 把实现抄一遍 ⇒ 实现改错测试跟着错，等于没测）。
    //    本组所有断言的对象**全部**来自实现返回的真值。
    //
    // 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。

    /// 三个代表性图形倍率：手机 1.0 / 小平板 1.3 / 大平板 1.6。
    ///
    /// 🔴 平板上**文字与图形分别放大**（文字走 `MediaQuery.textScaler`，
    ///    图形走 `uiScaleOf`）⇒ 本组把文字缩放器也设成同一个倍率，
    ///    复现真实平板场景（PRD §5.6 平台倍率清单）。
    const List<double> scales = <double>[1.0, 1.3, 1.6];

    /// 一份**真实**的判据量（实现直接暴露；测试**不复算**任何公式）。
    ({WeatherRowMetrics metrics, WeatherRowWidths widths}) widthsFor({
      required WeatherKind kind,
      required bool hasButton,
      bool bought = false,
      double scale = 1.0,
      TextScaler? scaler,
    }) {
      final AppLocalizations t = AppLocalizationsZh();
      final WeatherRowMetrics metrics = measureWeatherRowMetrics(
        kind: kind,
        shelterRefType: kind.shelterRefType,
        hasButton: hasButton,
        t: t,
        scaler: scaler ?? TextScaler.linear(scale),
        scale: scale,
      );
      return (
        metrics: metrics,
        widths: computeWeatherRowWidths(
          metrics: metrics,
          bought: bought,
          hasButton: hasButton,
        ),
      );
    }

    test('D-2① · widthHintTruncated − widthNoHint == kWeatherHintMinWidth × s', () {
      for (final double scale in scales) {
        for (final WeatherKind kind in WeatherKind.values) {
          for (final bool button in <bool>[true, false]) {
            final ({WeatherRowMetrics metrics, WeatherRowWidths widths}) r =
                widthsFor(kind: kind, hasButton: button, scale: scale);
            final WeatherRowWidths w = r.widths;
            expect(
              w.widthHintTruncated - w.widthNoHint,
              closeTo(kWeatherHintMinWidth * r.metrics.scale, 0.001),
              reason: 'kind=${kind.name} button=$button scale=$scale：'
                  '「提示语被截断」与「提示语整句消失」两个门槛之差必须 == 提示语最小保留位'
                  '（架构师 R23 恒等式）—— 差值不对 ⇒ noHint 档的生存区间宽度就错了',
            );
          }
        }
      }
    });

    test('D-2② · widthNoHint − widthNoShelterName == buttonFullHit − buttonIconPriceHit',
        () {
      for (final double scale in scales) {
        for (final WeatherKind kind in WeatherKind.values) {
          for (final bool button in <bool>[true, false]) {
            final WeatherRowWidths w =
                widthsFor(kind: kind, hasButton: button, scale: scale).widths;
            expect(
              w.widthNoHint - w.widthNoShelterName,
              closeTo(w.buttonFullHit - w.buttonIconPriceHit, 0.001),
              reason: 'kind=${kind.name} button=$button scale=$scale：'
                  '「牺牲道具名」释放出来的宽度必须 == 按钮省掉名字省下的宽度'
                  '（两个门槛只差按钮名那一份）',
            );
          }
        }
      }
    });

    test('D-2③ · 门槛单调不增，严格性按场景写清（不许写死 `>` 让它假红）', () {
      for (final double scale in scales) {
        for (final WeatherKind kind in WeatherKind.values) {
          for (final bool button in <bool>[true, false]) {
            final ({WeatherRowMetrics metrics, WeatherRowWidths widths}) r =
                widthsFor(kind: kind, hasButton: button, scale: scale);
            final WeatherRowWidths w = r.widths;
            final String tag = 'kind=${kind.name} button=$button scale=$scale';

            // ① **不增**（硬断言：任何场景都必须成立）
            expect(w.widthNoWeatherName, lessThanOrEqualTo(w.widthNoShelterName),
                reason: '$tag：noWeatherName 门槛不得高于 noShelterName');
            expect(w.widthNoShelterName, lessThanOrEqualTo(w.widthNoHint),
                reason: '$tag：noShelterName 门槛不得高于 noHint');
            expect(w.widthNoHint, lessThan(w.widthHintTruncated),
                reason: '$tag：noHint 门槛必须**严格**低于 hintTruncated'
                    '（两者之差 = 提示语最小保留位 > 0）');

            // ② **严格性按场景写清**（不许写死 `>`）：
            //    · 按钮名有宽度 ⇒ noShelterName 门槛必须严格更低；
            //    · 按钮名无宽度（无按钮）⇒ 两个门槛相等。
            if (w.buttonFullHit > w.buttonIconPriceHit) {
              expect(w.widthNoShelterName, lessThan(w.widthNoHint),
                  reason: '$tag：道具名有宽度 ⇒ noShelterName 门槛必须严格低于 noHint');
            } else {
              expect(w.widthNoShelterName, w.widthNoHint,
                  reason: '$tag：道具名无宽度 ⇒ 两个门槛必须相等');
            }
            //    · 天气名有宽度 ⇒ noWeatherName 门槛必须严格更低。
            if (w.pillName > w.pillIcon) {
              expect(w.widthNoWeatherName, lessThan(w.widthNoShelterName),
                  reason: '$tag：天气名有宽度 ⇒ noWeatherName 门槛必须严格低于 noShelterName');
            } else {
              expect(w.widthNoWeatherName, w.widthNoShelterName,
                  reason: '$tag：天气名无宽度 ⇒ 两个门槛必须相等');
            }

            //    · 「full ≥ hintTruncated」**依赖提示语的真实宽度**：
            //      提示语存在 ⇒ pillFull − pillName = gap + 提示语宽 ≥ 24 ⇒ 成立；
            //      提示语不存在（wind / cold）⇒ pillFull − pillName = gap = 4 < 24
            //      ⇒ 该两档对**无提示语**的日型不可达（两档渲染完全相同，无可见影响）。
            if (w.pillFull - w.pillName > kWeatherHintMinWidth * r.metrics.scale) {
              expect(w.widthHintTruncated, lessThan(w.widthFull),
                  reason: '$tag：提示语有宽度 ⇒ hintTruncated 门槛必须严格低于 full');
            } else {
              expect(w.widthHintTruncated, greaterThanOrEqualTo(w.widthFull),
                  reason: '$tag：该日型无提示语 ⇒ hintTruncated 门槛不得低于 full'
                      '（无提示语时两档渲染相同 ⇒ hintTruncated 档对该日型不可达）');
            }
          }
        }
      }
    });

    test('D-2④ · 5 个门槛恒 > 0（挡住负分配额进 SizedBox · K24⑤）', () {
      for (final double scale in scales) {
        for (final WeatherKind kind in WeatherKind.values) {
          for (final bool button in <bool>[true, false]) {
            final WeatherRowWidths w =
                widthsFor(kind: kind, hasButton: button, scale: scale).widths;
            final String tag = 'kind=${kind.name} button=$button scale=$scale';
            expect(w.widthFull, greaterThan(0), reason: '$tag：widthFull 必须 > 0');
            expect(w.widthHintTruncated, greaterThan(0),
                reason: '$tag：widthHintTruncated 必须 > 0');
            expect(w.widthNoHint, greaterThan(0),
                reason: '$tag：widthNoHint 必须 > 0');
            expect(w.widthNoShelterName, greaterThan(0),
                reason: '$tag：widthNoShelterName 必须 > 0');
            expect(w.widthNoWeatherName, greaterThan(0),
                reason: '$tag：widthNoWeatherName 必须 > 0');
          }
        }
      }
    });

    test('D-2⑤ · 每档生存区间非空 ⇒ 5 档逐档可达（用**真量**穷举）', () {
      // 🔴 与 4a（**合成**阈值）**互为独立证据**：4a 用合成数字验证函数契约，
      //    本条用**实现算出来的真量**验证真实场景 —— 两边都绿 ⇒ 5 档真可达。
      for (final double scale in scales) {
        final WeatherRowWidths w =
            widthsFor(kind: WeatherKind.drought, hasButton: true, scale: scale)
                .widths;

        final Set<WeatherRowTier> hit = <WeatherRowTier>{};
        for (double a = 0; a <= w.widthFull + 1; a += 0.5) {
          hit.add(resolveWeatherRowTier(
            availableWidth: a,
            widthFull: w.widthFull,
            widthHintTruncated: w.widthHintTruncated,
            widthNoHint: w.widthNoHint,
            widthNoShelterName: w.widthNoShelterName,
            widthNoWeatherName: w.widthNoWeatherName,
          ));
        }
        final List<WeatherRowTier> missing = WeatherRowTier.values
            .where((WeatherRowTier t) => !hit.contains(t))
            .toList();
        expect(missing, isEmpty,
            reason: '极端日（有按钮 + 有提示语）的**真实**判据量下，5 档必须逐档可达'
                '（scale=$scale）。'
                '实际命中：${hit.map((WeatherRowTier t) => t.name).join('、')}；'
                '不可达：${missing.map((WeatherRowTier t) => t.name).join('、')}');
      }

      // 🔴 **无按钮 ⇒ `noShelterName` 档不可达**（没有按钮名可牺牲 ⇒ 两门槛相等）
      //    —— 这是**设计**，不是死枚举。
      final WeatherRowWidths wNo =
          widthsFor(kind: WeatherKind.drought, hasButton: false).widths;
      expect(wNo.widthNoHint, wNo.widthNoShelterName,
          reason: '无按钮时 noHint 与 noShelterName 两个门槛必须相等'
              '（没有按钮名可牺牲 ⇒ 该档不可达，属设计）');
    });

    test('铁律 B · 档位映射：边界闭合 / 差 0.01 落下一档 / 单调只变好', () {
      // 🔴 口径纪律（A2-11⑥）：断言的是**函数的显式入参 ⇒ 输出的关系**，
      //    不是「某屏宽 = 某档位」的环境结论 ⇒ 换机器 / 换字体不会红。
      const double widthFull = 200;
      const double widthHintTruncated = 160;
      const double widthNoHint = 140;
      const double widthNoShelterName = 120;
      const double widthNoWeatherName = 80;

      WeatherRowTier pick(double available) => resolveWeatherRowTier(
            availableWidth: available,
            widthFull: widthFull,
            widthHintTruncated: widthHintTruncated,
            widthNoHint: widthNoHint,
            widthNoShelterName: widthNoShelterName,
            widthNoWeatherName: widthNoWeatherName,
          );

      // ① 边界闭合（`<=` 语义）：available **恰好等于**门槛 ⇒ 恰好落该档
      expect(pick(widthFull), WeatherRowTier.full);
      expect(pick(widthHintTruncated), WeatherRowTier.hintTruncated);
      expect(pick(widthNoHint), WeatherRowTier.noHint);
      expect(pick(widthNoShelterName), WeatherRowTier.noShelterName);
      expect(pick(widthNoWeatherName), WeatherRowTier.noWeatherName);

      // ② 差 0.01 ⇒ 落**下一档**（严格大于边界的正确性）
      expect(pick(widthFull - 0.01), WeatherRowTier.hintTruncated);
      expect(pick(widthHintTruncated - 0.01), WeatherRowTier.noHint);
      expect(pick(widthNoHint - 0.01), WeatherRowTier.noShelterName);
      expect(pick(widthNoShelterName - 0.01), WeatherRowTier.noWeatherName);
      expect(pick(widthNoWeatherName - 0.01), WeatherRowTier.noWeatherName,
          reason: '已是最省档 ⇒ 兜底仍是它（外层 FittedBox 负责等比收尾）');

      // ③ 可用宽增大 ⇒ 档位**只变好**（index 不增）
      WeatherRowTier? prev;
      for (double a = 0; a <= 400; a += 0.5) {
        final WeatherRowTier cur = pick(a);
        if (prev != null) {
          expect(cur.index, lessThanOrEqualTo(prev.index),
              reason: '可用宽 $a 比前一步宽 ⇒ 档位只能更好，不能更省');
        }
        prev = cur;
      }
    });

    testWidgets('D-1 · 判据与渲染共用同一套数字：按真量给出的可用宽逐档验证落档',
        (WidgetTester tester) async {
      // 🔴 这是 D-1 的**集成级**证据：真量来自 [computeWeatherRowWidths]，
      //    而组件落档用的是**同一套**数字 ⇒ 把「真量边界」当可用宽泵进去，
      //    渲染出来的形态必须与该边界对应。
      //    若实现与暴露的真量**分家**（两份数字），本条立刻红。
      //
      // 🔴 倍率与文字缩放器**必须从组件的真实 context 里取**（不许写死 1.0）：
      //    组件用 `uiScaleOf(context)` 与 `MediaQuery.textScalerOf(context)`，
      //    写死会让「真量」与「组件实际用的数字」分家 ⇒ 本条测的就不是同一件事。
      await _setPhoneView(tester, 390);

      Future<void> pumpAt(double available) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            // `UnconstrainedBox`：允许子件宽于视口（真量边界可能 > 视口宽）。
            body: UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: available,
                child: GardenWeatherRow(
                  key: kWeatherRowKey,
                  kind: WeatherKind.drought,
                  shelterRefType: WeatherKind.drought.shelterRefType,
                  bought: false,
                  affordable: true,
                  showShelterButton: true,
                  onShelterTap: () {},
                  onPillTap: null,
                ),
              ),
            ),
          ),
        ));
      }

      // 先泵一次，拿到**组件真实使用**的倍率与文字缩放器（不许写死 1.0）。
      await pumpAt(390);
      final BuildContext ctx = tester.element(find.byKey(kWeatherPillKey));
      final WeatherRowWidths w = widthsFor(
        kind: WeatherKind.drought,
        hasButton: true,
        scale: uiScaleOf(ctx),
        scaler: MediaQuery.textScalerOf(ctx),
      ).widths;

      // available == widthHintTruncated ⇒「提示语被截断」档（提示语**在**树里）
      await pumpAt(w.widthHintTruncated);
      expect(presenceOf(tester).hint, isTrue,
          reason: 'available 恰等于 widthHintTruncated ⇒ 提示语必须还在');

      // available == widthHintTruncated − 0.01 ⇒「提示语整句消失」档
      await pumpAt(w.widthHintTruncated - 0.01);
      ({bool hint, bool shelterName, bool weatherName}) p = presenceOf(tester);
      expect(p.hint, isFalse, reason: '窄 0.01 ⇒ 提示语必须整句消失');
      expect(p.shelterName, isTrue, reason: '窄 0.01 ⇒ 道具名必须还在');
      expect(p.weatherName, isTrue, reason: '窄 0.01 ⇒ 天气名必须还在');

      // available == widthNoHint ⇒ 边界闭合 ⇒ 仍是「提示语整句消失」档
      await pumpAt(w.widthNoHint);
      p = presenceOf(tester);
      expect(p.hint, isFalse);
      expect(p.shelterName, isTrue);
      expect(p.weatherName, isTrue);

      // available == widthNoHint − 0.01 ⇒ 牺牲道具名
      await pumpAt(w.widthNoHint - 0.01);
      p = presenceOf(tester);
      expect(p.hint, isFalse);
      expect(p.shelterName, isFalse, reason: '窄 0.01 ⇒ 道具名必须整体退场');
      expect(p.weatherName, isTrue, reason: '道具名退场时天气名必须还在');

      // available == widthNoShelterName − 0.01 ⇒ 牺牲天气名
      await pumpAt(w.widthNoShelterName - 0.01);
      p = presenceOf(tester);
      expect(p.weatherName, isFalse, reason: '窄 0.01 ⇒ 天气名必须整体退场');

      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // A2-8④ · 真页面级几何：chips 行 / 右上角状态灯 / 一键 FAB / 木牌
  //
  // 🔴 2026-11-06（玄参拍板）：顶部天气行/条幅整体撤除，天气信息迁到**底部**。
  // 🔴 2026-11-07（玄参第三轮拍板）：旧 72 白条（GardenWeatherDock）整体删除，
  //    改名 `GardenWeatherBadge` 独立图标状态灯（56×56）。
  // 🔴 2026-11-07（玄参第四批排版）：状态灯移**右上角**（right:12 / top:12，与
  //    左上 chips 行对称）。
  // 🔴 2026-11-07（玄参第五批拍板）：底部提示框（ticker）整体撤除，「明日预告」
  //    由天气对话框承接；一键 FAB 回归**右下角原位**（right:12 / bottom:12）。
  //    本组断言随之改写。
  // ══════════════════════════════════════════════════════════════════════════
  group('A2-8④ · 真页面几何（真实 GardenPage · 390×844）', () {
    for (final Locale locale in const <Locale>[Locale('zh'), Locale('en')]) {
      testWidgets(
          '${locale.languageCode}：chips 视觉顶 y=12；右上角状态灯齐备（56×56）、'
          '不与木牌相交；一键 FAB 在右下角原位；温和日无买棚按钮',
          (WidgetTester tester) async {
        // 🔴 页面文案语言由 `AppLocaleController.current` 决定（页级 [L10nScope]
        //    读它，**不是** MaterialApp 的 `locale`）⇒ 改静态值 + 用例结束还原。
        //    zh / en 两轮都跑：两边文案长度不同 ⇒ 短语 / FAB 宽度不同 ⇒
        //    两个 locale 合起来覆盖面更大。
        final Locale prevLocale = AppLocaleController.current;
        addTearDown(() => AppLocaleController.current = prevLocale);
        AppLocaleController.current = locale;

        // 手机视口（390×844 逻辑像素）：`uiScaleOf` 按**屏短边**判定 ⇒ 390 < 600
        // ⇒ 倍率恒 1.0（平板档另由 T04 / 铁律 D 的 1.3 / 1.6 覆盖）。
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_realGardenPage(plants: _alivePlants(5)));

        // 一键 FAB 出现 ⇒ 数据已就绪（不是 loading 占位）。
        final bool ready = await _pumpUntilReady(
          tester,
          () => find.byKey(kOneClickCapsuleKey).evaluate().isNotEmpty,
        );
        expect(ready, isTrue,
            reason: '真实 GardenPage 应在有限帧内加载完成并出现一键 FAB'
                '（买断档 + 存活 5 株 ⇒ FAB 必须出现；不出现说明宿主没搭起来）');
        await tester.pump();

        // ── 顶部：天气行退场，chips 顶恒 y=12 ────────────────────────────────
        expect(find.byKey(kWeatherRowKey), findsNothing,
            reason: '顶部天气行已整体撤除（迁往底部停靠条）—— 契约：kWeatherRowKey '
                '在真页面树里不存在');
        expect(find.byKey(kWeatherPillSlotKey), findsNothing);

        // chips 行结构定位（自检：「×N」文本必须落在其中）。
        final Finder rows = find.ancestor(
          of: find.textContaining('×').first,
          matching: find.byType(Row),
        );
        expect(rows.evaluate().length, greaterThanOrEqualTo(2),
            reason: 'chips 行与 chip 内部行两层 Row 都必须存在');
        final Finder chipsRow = rows.at(1);
        final Rect chipsRect = tester.getRect(chipsRow);
        expect(chipsRect.top, closeTo(12, 0.5),
            reason: 'chips 视觉顶必须恒 y=12（A2 基线，顶部条幅撤除后不分态）');
        expect(chipsRect.left, closeTo(12, 0.5), reason: 'chips 贴左边距 12');

        // ── 右上角状态灯：齐备且不与木牌相交 ──────────────────────────────
        final Finder badge = find.byKey(kGardenWeatherBadgeKey);
        expect(badge, findsOneWidget, reason: '天气图标状态灯必须渲染（温和日）');
        final Rect badgeRect = tester.getRect(badge);
        expect(badgeRect.right, closeTo(390 - 12, 0.5),
            reason: '状态灯右锚 12（右上角，与左上 chips 行对称）');
        expect(badgeRect.top, closeTo(12, 0.5), reason: '状态灯贴顶 12');
        expect(badgeRect.width, closeTo(56, 0.5),
            reason: '状态灯宽 56（旧 72 白条已删，玄参 2026-11-07 拍板）');
        expect(badgeRect.height, closeTo(56, 0.5),
            reason: '状态灯高 56（白条已删，不再全宽）');
        expect(find.byKey(kGardenWeatherBadgeIconKey), findsOneWidget,
            reason: '56×56 天气图标状态灯在场');
        // 2026-11-06 第二轮简化：短语文字层整体撤除（玄参：「不需要描述性的文字」）。
        expect(
          find.descendant(
            of: badge,
            matching: find.textContaining(zhSunnyText),
          ),
          findsNothing,
          reason: '温和日短语已撤 —— 状态灯只渲染图标，无描述性文字',
        );
        // 防假绿：图标不得被压成 0 宽。
        expect(tester.getSize(find.byKey(kGardenWeatherBadgeIconKey)).width,
            greaterThan(0));

        final Finder sign = find.byType(GardenSignHotspot);
        expect(sign, findsOneWidget, reason: '木牌热区必须在场');
        final Rect signRect = tester.getRect(sign);

        // ① chips vs 木牌：不得相交（chips 左上 / 木牌左下）。
        expect(chipsRect.overlaps(signRect), isFalse,
            reason: 'chips 行与木牌热区不得相交；chips=$chipsRect sign=$signRect');
        // ② 状态灯 vs 木牌：不得相交（状态灯在右上角、木牌在左下角）。
        expect(badgeRect.overlaps(signRect), isFalse,
            reason: '状态灯与左下木牌热区不得相交；badge=$badgeRect sign=$signRect');

        // ── 一键 FAB：右下角原位（right:12 / bottom:12，第五批 ticker 撤除）──
        final Finder fab = find.byKey(kOneClickCapsuleKey);
        expect(fab, findsOneWidget, reason: '买断档 + 存活 5 株 ⇒ 一键 FAB 必须在场');
        final Rect fabRect = tester.getRect(fab);
        expect(fabRect.right, closeTo(390 - 12, 0.5),
            reason: 'FAB 右缘 = 页宽 − 12；fab=$fabRect');
        expect(fabRect.bottom, closeTo(844 - 12, 0.5),
            reason: 'FAB 底缘 = 页高 − 12（右下角原位，玄参第五批拍板）');

        // ── 温和日没有买棚按钮 ─────────────────────────────────────────────
        expect(find.byKey(kShelterButtonHitKey), findsNothing,
            reason: '温和日（钉死 sunny）页面上不得出现买棚按钮（在对话框里）');

        expect(tester.takeException(), isNull);
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // M-G · 平板档 UI 层守卫（第 4 轮 QA 路由；A3 收口补齐平板档）
  //
  // 生产代码 `weather_status_bar.dart` 的 `uiScaleOf(context)` 是**视口驱动**
  // （= `tabletUiScaleFor(MediaQuery.sizeOf(context).shortestSide)`）：手机（短边
  // <600）恒 1.0；834 → 1.3；1032 → 1.6（钳制）。
  //
  // 🔴 **A3 收口前**：本组只有「手机视口 == 1.0」一条 ⇒ 平板档（1.3 / 1.6×）UI 表现
  //    **无测试覆盖**（＝已登记的「M-G 平板覆盖缺口」）。
  // ✅ **A3 收口后**：缺口已补 —— 见本文件尾部两组：
  //    · `M-G · 平板视口 UI 层（A3 收口）`：834 / 1032 视口下 pump UI 层，断言
  //      视觉带高 / 胶囊槽高 / 胶囊实体高 / 命中容器高 / 实体顶对齐槽顶 / 无溢出，
  //      以及「`resolveWeatherRowTier` 用**实测**可用宽算出的档位 == 组件实际渲染形态」；
  //    · `平板不齐边 6×(s−1)（A3 收口 · 已登记差异）`：把 1.8pt 差异钉成契约。
  //
  // 🔎 1.8pt 的根因（架构师 A3 盘点 · 已实测复现）：chips 的 `Padding(top:6)` 是**固定
  //    字面量**（不乘 s），行内垂直居中偏移 `(44−32)/2 = 6` **乘了 s** ⇒ 差 = `6×(s−1)`。
  //    s=1（手机）两者相等 ⇒ 手机零回归；s=1.3 ⇒ 1.8pt；s=1.6 ⇒ 3.6pt。
  //    **主理人裁定：登记不改（与 K27 / R24 同类处置），但必须补守卫钉住**（防止将来
  //    有人悄悄把 chips 的 top 也乘上倍率或改掉这条公式）。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('M-G · 手机视口（390×844）下组件实际 uiScaleOf == 1.0',
      (WidgetTester tester) async {
    // 手机视口：短边 390 < 600 ⇒ tabletUiScaleFor 恒 1.0。
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      kind: WeatherKind.drought,
      pageWidth: 390,
      chipsWidth: 179,
    ));
    // 直接读组件**实际**使用的 uiScaleOf（不自己复算公式，避免与实现同义反复）。
    final BuildContext ctx = tester.element(find.byKey(kWeatherPillKey));
    final double scale = uiScaleOf(ctx);
    expect(scale, 1.0,
        reason: '手机视口（390×844）下 uiScaleOf 必须 == 1.0'
            '（平板档另由上方缺口登记，本断言只锁手机档不被回归）');
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // FD1 · 满档提示语不得被 ellipsis 吞字（A3 首件）
  //
  // 🔴 **根因**：修复前 `measureTextWidth` 量宽度**不含**环境 `DefaultTextStyle`
  //    （M3 bodyMedium 自带 `letterSpacing: 0.25`）⇒ 量得比实际渲的窄 `0.25 × 字数`
  //    ⇒ 满档提示语预算算「放得下」⇒ 选满档 ⇒ 实际渲更宽 ⇒ Flexible 位不够 ⇒
  //    ellipsis 吞 1 字（「· 浇…」）。修复后测量与渲染**共用同一套样式**
  //    （`kWeatherLetterSpacing`），「量」==「渲」，满档提示语必须完整。
  // 🔴 **守卫口径（实测定宽，非拍脑袋）**：FD1 只在「满档被选、但测量漏算字距」的
  //    **窄窗口**复现——太宽（如 768，scale 1.3 余量太大）永远不截；太窄则已降到
  //    「提示语整句消失」档（那不是 bug）。本仓用 TEMP sweep 实测：修复前
  //    `didExceedMaxLines` **true** 的窗口约 pageWidth ∈ [≈500, 590]（短边 <600 ⇒
  //    scale 1.0），590 之后转 false；修复后**所有宽度**均为 false。**故选 585**
  //    （scale 1.0、满档复现窗口中央）：修复前必红（提示语在树里却被截），修复后必绿
  //    （量==渲，不再残字）—— 这条守卫是真的能抓回归，不是假绿。
  // ══════════════════════════════════════════════════════════════════════════
  group('FD1 · 满档提示语不吞字（A3 首件 · 量==渲同源）', () {
    testWidgets(
        'pageWidth=585（满档复现窗口）：提示语完整渲染、未被 ellipsis 截断（didExceedMaxLines == false）',
        (WidgetTester tester) async {
      // 585×1194 逻辑视口 ⇒ 短边 585 < 600 ⇒ scale 1.0；该宽度下满档（含完整提示语）
      // 被选中，且正好落在 FD1 复现窗口（测量漏算字距 ⇒ 实际渲更宽 ⇒ Flexible 截断）。
      tester.view.physicalSize = const Size(585 * 2, 1194 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 585,
        chipsWidth: 179,
      ));

      final AppLocalizations zh = AppLocalizationsZh();
      final String hintText = '· ${zh.garden_weather_hint_drought}';
      // ① 满档必须把完整提示语放进树里（不是整体退场 ⇒ findsNothing）。
      expect(find.text(hintText), findsOneWidget,
          reason: 'pageWidth=585 应走满档，完整提示语「$hintText」必须在树里');
      // ② 提示语**不得**被 ellipsis 截断（FD1 修复前的残字「· 浇…」正是这里漏的）。
      //    `find.text` 命中的是 `data`（截断不改 data），故必须用渲染期
      //    `didExceedMaxLines` 判「半截」。修复前这条必红。
      final RenderParagraph para =
          tester.renderObject<RenderParagraph>(find.text(hintText));
      expect(para.didExceedMaxLines, isFalse,
          reason: 'FD1：满档提示语「$hintText」不得被 ellipsis 截断（量==渲同源）');
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // M-G · 平板视口 UI 层（A3 收口 · 只动 test，不动 lib）
  //
  // 补齐「M-G 平板覆盖缺口」：A3 之前 UI 层从未在平板视口 pump 过 ⇒ 把平板分支
  // （倍率 1.3 / 1.6）改坏了自动化也不会红。
  //
  // 🔴 口径纪律（A2 期反复踩过的坑，W-1/W-2/D-14 已封版）：
  //    **只断言不变式，不断言「某宽度 = 某档位」** —— 测试字体是方块字体（每字形
  //    advance = 字号），「宽度→档位」的结论在测试环境下不成立。
  // 🔴 倍率**一律从真实 `context` 取 `uiScaleOf`**（不写死 1.3 / 1.6）；
  //    期望值里的 32 / 28 / 44 是**规格常量**（写死，不引用实现同名常量），
  //    从而「期望值」与「实现取值」不同源，不会自证。
  // ══════════════════════════════════════════════════════════════════════════
  group('M-G · 平板视口 UI 层（A3 收口）', () {
    for (final List<double> vp in <List<double>>[
      <double>[834, 1112],
      <double>[1032, 1376],
    ]) {
      testWidgets(
          '行级 ${vp[0].toInt()}×${vp[1].toInt()}：槽 32s / 实体 28s / 命中 44s，'
          '实体顶对齐槽顶，且【判据==渲染】（档位用实测可用宽算）',
          (WidgetTester tester) async {
        tester.view.physicalSize = Size(vp[0] * 3, vp[1] * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        // 极端日 + 有按钮（干旱 = 遮阳棚）：按钮与胶囊都会渲染 ⇒ 覆盖最全。
        const WeatherKind kind = WeatherKind.drought;
        // 可用宽 = 页面宽 − 左右各 12（与真页面同口径），由 SizedBox 钉成 tight。
        final double available = vp[0] - 24;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: available,
                child: GardenWeatherRow(
                  key: kWeatherRowKey,
                  kind: kind,
                  shelterRefType: kind.shelterRefType,
                  bought: false,
                  affordable: true,
                  showShelterButton: true,
                  onShelterTap: () {},
                  onPillTap: null,
                ),
              ),
            ),
          ),
        ));
        await tester.pump();

        final BuildContext ctx = tester.element(find.byKey(kWeatherPillKey));
        final double s = uiScaleOf(ctx);
        expect(s, greaterThan(1.0),
            reason: '前置：${vp[0].toInt()} 档必须真的处于平板倍率（>1.0），'
                '否则本条量的是手机分支');

        final Rect slot = tester.getRect(find.byKey(kWeatherPillSlotKey));
        final Rect entity = tester.getRect(find.byKey(kWeatherPillKey));
        final Rect pillHit = tester.getRect(find.byKey(kWeatherPillHitKey));
        final Rect btnVisual = tester.getRect(find.byKey(kShelterButtonVisualKey));
        final Rect btnHit = tester.getRect(find.byKey(kShelterButtonHitKey));

        // ── 尺寸层：每层各自「规格常量 × 真实倍率」────────────────────────
        expect(slot.height, closeTo(32 * s, 0.5),
            reason: '胶囊槽高必须随倍率（32×s），实测 ${slot.height}');
        expect(entity.height, closeTo(28 * s, 0.5),
            reason: '胶囊实体高必须随倍率（28×s），实测 ${entity.height}');
        expect(pillHit.height, closeTo(44 * s, 0.5),
            reason: '胶囊命中容器高必须随倍率（44×s），实测 ${pillHit.height}');
        expect(btnVisual.height, closeTo(32 * s, 0.5),
            reason: '道具按钮视觉高必须随倍率（32×s），实测 ${btnVisual.height}');
        expect(btnHit.height, closeTo(44 * s, 0.5),
            reason: '道具按钮命中容器高必须随倍率（44×s），实测 ${btnHit.height}');

        // ── 对齐层：实体顶 == 槽顶（顶对齐，不是居中）──────────────────────
        expect(entity.top - slot.top, closeTo(0, 0.5),
            reason: '胶囊实体必须顶对齐槽顶（不是居中）：'
                'entity.top=${entity.top} slot.top=${slot.top}');

        // ── 档位层：用**实测**可用宽 + 真实倍率/字号算档位，再比渲染形态 ────
        // （判据与渲染共用同一套数字 ⇒ 若实现分家，这里必红。）
        final AppLocalizations zh = AppLocalizationsZh();
        final WeatherRowMetrics metrics = measureWeatherRowMetrics(
          kind: kind,
          shelterRefType: kind.shelterRefType,
          hasButton: true,
          t: zh,
          scaler: MediaQuery.textScalerOf(ctx),
          scale: s,
        );
        final WeatherRowWidths w = computeWeatherRowWidths(
          metrics: metrics,
          bought: false,
          hasButton: true,
        );
        final WeatherRowTier tier = resolveWeatherRowTier(
          availableWidth: available,
          widthFull: w.widthFull,
          widthHintTruncated: w.widthHintTruncated,
          widthNoHint: w.widthNoHint,
          widthNoShelterName: w.widthNoShelterName,
          widthNoWeatherName: w.widthNoWeatherName,
        );
        final ({bool hint, bool shelterName, bool weatherName}) p =
            presenceOf(tester);
        final bool expectHint = tier == WeatherRowTier.full ||
            tier == WeatherRowTier.hintTruncated;
        final bool expectShelterName =
            tier != WeatherRowTier.noShelterName &&
                tier != WeatherRowTier.noWeatherName;
        final bool expectWeatherName = tier != WeatherRowTier.noWeatherName;
        expect(p.hint, expectHint,
            reason: '档位 $tier ⇒ 提示语在树里应 == $expectHint（实测 $p）');
        expect(p.shelterName, expectShelterName,
            reason: '档位 $tier ⇒ 道具名在树里应 == $expectShelterName（实测 $p）');
        expect(p.weatherName, expectWeatherName,
            reason: '档位 $tier ⇒ 天气名在树里应 == $expectWeatherName（实测 $p）');

        // 防假绿：行宽不得被压成 0（否则上面的尺寸/对齐断言毫无意义）。
        expect(tester.getRect(find.byKey(kWeatherRowKey)).width, greaterThan(0),
            reason: '天气行宽度必须 > 0');
        expect(tester.takeException(), isNull,
            reason: '${vp[0].toInt()} 平板档 pump 完不得有溢出/异常（$vp）');
      });

      testWidgets(
          '真页面 ${vp[0].toInt()}×${vp[1].toInt()}：状态灯 56×s 随倍率（K27 口径），'
          'chips 视觉顶恒 12，无溢出',
          (WidgetTester tester) async {
        final Locale prevLocale = AppLocaleController.current;
        addTearDown(() => AppLocaleController.current = prevLocale);
        AppLocaleController.current = const Locale('zh');

        tester.view.physicalSize = Size(vp[0] * 3, vp[1] * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_realGardenPage(plants: _alivePlants(5)));
        final bool ready = await _pumpUntilReady(
          tester,
          () => find.byKey(kOneClickCapsuleKey).evaluate().isNotEmpty,
        );
        expect(ready, isTrue,
            reason: '真实 GardenPage 应在有限帧内加载完成并出现一键 FAB');
        await tester.pump();

        // 顶部胶囊撤除（2026-11-06）⇒ 倍率探针改从状态灯图标取。
        expect(find.byKey(kWeatherPillKey), findsNothing,
            reason: '顶部天气胶囊已整体撤除');
        final BuildContext ctx =
            tester.element(find.byKey(kGardenWeatherBadgeIconKey));
        final double s = uiScaleOf(ctx);
        expect(s, greaterThan(1.0),
            reason: '前置：${vp[0].toInt()} 档必须真的处于平板倍率（>1.0）');

        final Rect badge = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
        expect(badge.width, closeTo(56 * s, 0.5),
            reason: '真页面：状态灯宽必须随倍率（56×s，K27 口径），实测 ${badge.width}');
        expect(badge.height, closeTo(56 * s, 0.5),
            reason: '真页面：状态灯高必须随倍率（56×s；旧 72 白条已删）');
        expect(badge.right, closeTo(vp[0] - 12, 0.5),
            reason: '真页面：状态灯右锚 12（右上角）');
        expect(badge.top, closeTo(12, 0.5), reason: '真页面：状态灯贴顶 12');

        // chips 行顶恒 12（内距不乘倍率的契约件，见下方「chips 视觉顶恒 12」组）。
        final Finder rows = find.ancestor(
          of: find.textContaining('×').first,
          matching: find.byType(Row),
        );
        final Rect chipsRect = tester.getRect(rows.at(1));
        expect(chipsRect.top, closeTo(12, 0.5),
            reason: '真页面：chips 视觉顶恒 12');

        expect(tester.takeException(), isNull,
            reason: '${vp[0].toInt()} 平板真页面 pump 完不得有溢出/异常');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // chips 视觉顶恒 12（2026-11-06 迁移后的契约）
  //
  // 🔴 旧契约「胶囊顶 − chips 顶 == 6×(s−1)」随顶部胶囊撤除**退役**（胶囊已不在
  //    页面树里，没有第二个可对的顶）。保留下来的可守不变式是：chips 的
  //    `Padding(top: 6)` 是**固定字面量**（不乘倍率）⇒ chips 视觉顶在任何倍率下
  //    都恒等于 12 —— 若哪天有人把 chips 的 top 也乘上倍率，本用例必红。
  // 🔴 期望值里的 `12` 是**契约本身**（写死不算「对着常量自证」）；`s` 从真实
  //    `context` 取，**绝对不许写死 1.3 / 1.6**。
  // ══════════════════════════════════════════════════════════════════════════
  group('chips 视觉顶恒 12（2026-11-06 迁移后契约）', () {
    for (final List<double> vp in <List<double>>[
      <double>[390, 844],
      <double>[834, 1112],
      <double>[1032, 1376],
    ]) {
      testWidgets('${vp[0].toInt()}×${vp[1].toInt()}：chips 视觉顶 == 12 ± 0.5'
          '（内距不乘倍率），状态灯 56×s 随倍率',
          (WidgetTester tester) async {
        final Locale prevLocale = AppLocaleController.current;
        addTearDown(() => AppLocaleController.current = prevLocale);
        AppLocaleController.current = const Locale('zh');

        tester.view.physicalSize = Size(vp[0] * 3, vp[1] * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_realGardenPage(plants: _alivePlants(5)));
        final bool ready = await _pumpUntilReady(
          tester,
          () => find.byKey(kOneClickCapsuleKey).evaluate().isNotEmpty,
        );
        expect(ready, isTrue, reason: '真实 GardenPage 应在有限帧内加载完成');
        await tester.pump();

        // chips 行定位：与 A2-8④ 同款结构定位（×N 文本 → 最近两层 Row 的外层），
        // 防止定位错对象假绿。
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

        final Rect chipsRect = tester.getRect(chipsRow);
        expect(chipsRect.top, closeTo(12, 0.5),
            reason: 'chips 视觉顶 = 浮层 top(6) + Padding(6) = 12，'
                '任何倍率下恒定（chips 内距不乘倍率）；实测 ${chipsRect.top}');

        // 倍率从真实 context 取（不写死 1.3 / 1.6）。
        final BuildContext ctx =
            tester.element(find.byKey(kGardenWeatherBadgeIconKey));
        final double s = uiScaleOf(ctx);
        final double badgeW =
            tester.getRect(find.byKey(kGardenWeatherBadgeKey)).width;
        expect(badgeW, closeTo(56 * s, 0.5),
            reason: '状态灯随倍率（56×s，K27 口径），实测 $badgeW，s=$s');
        expect(tester.takeException(), isNull);
      });
    }
  });

}

/// 中文「阳光明媚」（直接取 ARB 生成物，避免在测试里手抄文案）。
final String zhSunnyText = AppLocalizationsZh().weather_sunny;
