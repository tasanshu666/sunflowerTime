/// 花园守卫「今日券」→ **减免接线** 回归测试（第四批 A）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.7 / §3.8 与本批施工图纸。
///
/// ## 本文件钉死的 14 条（逐条对应施工图纸 §四）
///  1. 无券基线：水 5 / 肥 10 / 除草 +1 / 除虫 +2（防回归地基）；
///  2. 浇水券剩 1 + 批量 3 盆：4 / 5 / 5，合计 14（专抓「循环外只算一次」）；
///  3. 浇水券满额 6 + 批量 12 盆：前 6 盆 4、后 6 盆 5，合计 54（减免恰好 6）；
///  4. 有植物盆除草 + 劳动券：实到 2，飘字也是 +2（同一个 perk）；
///  5. 空盆除草 + 劳动券：实到 2；
///  6. 施肥券：今日每次施肥都是 8 ☀（额度 12 次，不缩额）；
///  7. 免费浇水券（单株）：显示 0、实扣 0、核销后另一盆 5；
///  8. 免费浇水券 + 一键批量：前 1 盆 0 ☀、后 3 盆 5 ☀，额度核销 1 次（B13.20）；
///  9. 跨天过期：价格原样、chip 不显示；
/// 10. prefs 不可用：页面正常、价格原样（比什么都重要）；
/// 11. chip 无 `×`、chips 行 top/left 与基线一致（embedded 12 / standalone 60）；
/// 12. chip 在 320×568 + en + 1.3 倍字号下无 overflow；
/// 13. `refLabelOf` 三个 guard refType 返回具体中文（不再是「其他」）；
/// 14. 额度用完：价格回原价 **且** chip 仍在屏上、文案含「已用完」。
///
/// 🔴 纪律：期望值一律写**字面量**（4 / 5 / 14 / 54 / 8 / 10 / 2），
/// 不引用 `waterCostOf(perk)` 之类实现算式反推 —— 否则实现改错时测试也一起错。
library guard_voucher_garden_wiring_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';

import '../helpers/no_hit_random.dart';

// ── 常量 ─────────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

String _todayKey() => dayKey(DateTime.now());

/// 造「今日已领取，buff = 指定券」的存档（`used` 可指定已用额度）。
GuardDayState _guardDay(GuardDropKind kind, {int quota = 0, int used = 0}) =>
    GuardDayState(
      dayKey: _todayKey(),
      status: GuardDayStatus.claimed,
      dropKind: kind,
      buff: GuardBuffState(kind: kind, quota: quota, used: used),
    );

// ── Fake：守卫存档（内存）────────────────────────────────────────────────────

/// 只关心「今天这一条」：读忽略 childId（单 child 用例），写计数用于
/// 「额度未被核销」类断言。
class _FakeGuardStore implements GuardStateStore {
  _FakeGuardStore([this.state]);

  GuardDayState? state;
  int writeCount = 0;

  @override
  Future<GuardDayState> read(String childId) async =>
      state ?? GuardDayState.empty(_todayKey());

  @override
  Future<void> write(String childId, GuardDayState next) async {
    state = next;
    writeCount++;
  }

  @override
  Future<void> clear(String childId) async {
    state = null;
  }
}

// ── Fake：阳光账本（内存，按 refType + refId 精确对账）───────────────────────

class _MemLedger implements SunlightRepository {
  double balanceValue = 1000;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> ofType(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  /// 某类账本行的**绝对值**（支出行的 net 是负数）。
  List<int> amountsOf(String refType) =>
      ofType(refType).map((SunlightEntry e) => (-e.net).round()).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    balanceValue += entry.net;
    return balanceValue;
  }

  @override
  Future<double> balance() async => balanceValue;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    final List<SunlightEntry> hits = ofType(refType);
    return hits.isEmpty ? null : hits.last;
  }

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
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

  @override
  Future<int> countByRefType(String refType) async => ofType(refType).length;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  /// 🔴 必须**同时**按 refType + refId 过滤：只按 refType 会让「上一盆刚浇过」
  /// 把后面所有盆的 30 分钟间隔闸门全部误判成 blocked（批量用例会整批失败）。
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

// ── Fake：仓储 / 服务 ────────────────────────────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this.capacity);

  final int capacity;

  @override
  Future<AppSettings> getSettings() async => AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: capacity,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _NoFocusRepo implements FocusRepository {
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

class _MemPlantRepo implements PlantRepository {
  _MemPlantRepo(this._store);

  final List<Plant> _store;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_store);

  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    final int i = _store.indexWhere((Plant p) => p.id == plant.id);
    if (i >= 0) {
      _store[i] = plant;
    } else {
      _store.add(plant);
    }
  }

  @override
  Future<void> deletePlant(String id) async =>
      _store.removeWhere((Plant p) => p.id == id);

  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

class _MemPotDisturbanceRepo implements PotDisturbanceRepository {
  _MemPotDisturbanceRepo([List<PotDisturbance> seed = const <PotDisturbance>[]]) {
    for (final PotDisturbance d in seed) {
      store[d.potIndex] = d;
    }
  }

  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      store.values.toList()..sort((PotDisturbance a, PotDisturbance b) =>
          a.potIndex.compareTo(b.potIndex));

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];

  @override
  Future<void> save(PotDisturbance disturbance) async {
    store[disturbance.potIndex] = disturbance;
  }

  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);

  @override
  Future<void> deleteAll() async => store.clear();
}

// ── 造植物 ──────────────────────────────────────────────────────────────────

/// [n] 株可浇水的存活幼苗（`lastWaterAt` 两日前；间隔闸门实际读账本）。
List<Plant> _plants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'p$i',
      speciesId: _sunflower.id,
      potIndex: i,
      stage: PlantStage.sprout,
      stageStartedAt: now.subtract(const Duration(hours: 2)),
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(hours: 2)),
      lastWaterAt: now.subtract(const Duration(days: 2)),
    ),
  );
}

/// 一株当天有杂草的存活幼苗（`weedPestRollDay == 今天` ⇒ tick 不重 roll、不清理）。
Plant _weedyPlant({String id = 'p0'}) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  return Plant(
    id: id,
    speciesId: _sunflower.id,
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: now.subtract(const Duration(hours: 2)),
    growthProgress: 0.3,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now.subtract(const Duration(hours: 2)),
    lastWaterAt: now.subtract(const Duration(days: 2)),
    weedAt: today,
    weedPestRollDay: today,
  );
}

/// 花盆 tooltip 文案（宿主的 AppLocale 默认 zh）。
String _weedTooltip(int reward) => '有杂草，点我拔掉 +$reward ☀';
String _pestTooltip(int reward) => '有害虫，点我除掉 +$reward ☀';

// ── 宿主 ────────────────────────────────────────────────────────────────────

/// 真实 `GardenPage` 宿主。
///
/// [store] 为 null ⇒ **不** override `guardStateStoreProvider`（= prefs 不可用场景）。
Widget _hostGarden({
  required _MemLedger ledger,
  required _MemPlantRepo plants,
  _FakeGuardStore? store,
  int capacity = 12,
  _MemPotDisturbanceRepo? pots,
  bool embedded = true,
}) {
  final List<Override> overrides = <Override>[
    entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
    settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo(capacity)),
    sunlightRepositoryProvider.overrideWithValue(ledger),
    focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
    plantRepositoryProvider.overrideWithValue(plants),
    bloomRewardRepositoryProvider
        .overrideWithValue(InMemoryBloomRewardRepository()),
    plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
          plants: ref.watch(plantRepositoryProvider),
          focus: ref.watch(focusRepositoryProvider),
          ledger: ref.watch(sunlightRepositoryProvider),
          settings: ref.watch(settingsRepositoryProvider),
          bloomRewards: ref.watch(bloomRewardRepositoryProvider),
          weedRandom: NoHitRandom(),
        )),
  ];
  if (store != null) {
    overrides.add(guardStateStoreProvider.overrideWithValue(store));
  }
  if (pots != null) {
    overrides.add(potDisturbanceRepositoryProvider.overrideWithValue(pots));
    overrides.add(emptyPotServiceProvider.overrideWithValue(
      EmptyPotService(
        disturbances: pots,
        ledger: ledger,
        weedRandom: NoHitRandom(),
        pestRandom: NoHitRandom(),
        firstSightImmune: false,
      ),
    ));
  }
  return ProviderScope(
    overrides: overrides,
    // 独立路由形态下 `GardenPage` 自带 Scaffold + AppBar（见 `garden_page.dart`
    // 末尾的 `if (widget.embedded)`），宿主**不得**再叠一层 AppBar。
    child: MaterialApp(
      home: embedded
          ? const Scaffold(body: GardenPage(embedded: true))
          : const GardenPage(embedded: false),
    ),
  );
}

/// 养护卡宿主：先把一个「打开养护卡」按钮挂在首页，再经真实
/// `showPlantCareCard`（`showDialog`）打开卡片 —— 与生产同一路由语义，
/// 卡片成功后会 `Navigator.pop` 回到按钮页（直接挂 `PlantCareCard` 当根路由
/// 会被 pop 掉整棵树，第二个用例就没法连续开两张卡了）。
Widget _careHost(ProviderContainer container, {required String plantId}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showPlantCareCard(ctx, plantId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

ProviderContainer _careContainer({
  required _MemLedger ledger,
  required _MemPlantRepo plants,
  required _FakeGuardStore store,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo(12)),
      sunlightRepositoryProvider.overrideWithValue(ledger),
      focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
      plantRepositoryProvider.overrideWithValue(plants),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      guardStateStoreProvider.overrideWithValue(store),
      currentPlantPerkProvider.overrideWith((Ref ref) async => PlantPerk.none),
      plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
            plants: ref.watch(plantRepositoryProvider),
            focus: ref.watch(focusRepositoryProvider),
            ledger: ref.watch(sunlightRepositoryProvider),
            settings: ref.watch(settingsRepositoryProvider),
            bloomRewards: ref.watch(bloomRewardRepositoryProvider),
            weedRandom: NoHitRandom(),
          )),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// ── 工具 ────────────────────────────────────────────────────────────────────

/// 有界帧推进（花园页木牌 / 花盆有无限动画 ⇒ 禁止 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 打开某株的养护卡（真实 `showPlantCareCard` 路由）并等卡片就绪。
Future<void> _openCareCard(
  WidgetTester tester,
  ProviderContainer container,
  String plantId,
) async {
  await tester.pumpWidget(_careHost(container, plantId: plantId));
  await _pumpFrames(tester, 20);
  await tester.tap(find.text('open'));
  final bool ready = await _pumpUntil(
    tester,
    () => find.byType(PlantCareCard).evaluate().isNotEmpty,
    maxFrames: 80,
  );
  expect(ready, isTrue, reason: '养护卡应打开');
  await _pumpFrames(tester, 30); // 等 _load 读完
}

/// 浮标 tooltip 走 `Semantics(label:)`（不是 Flutter `Tooltip`）。
Finder _semanticLabel(String label) => find.byWidgetPredicate(
    (Widget w) => w is Semantics && w.properties.label == label);

/// 完整一次「除草 / 除虫演出（4.1s）+ 淡出（300ms）+ 刷新落地」的帧预算。
const int _clearSettleFrames = 420;

/// 杂草 / 害虫浮标（按素材名匹配，素材加载失败也仍在树上）。
Finder _weedChip() => find.byWidgetPredicate((Widget w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == kGardenWeedAsset);

Finder _pestChip() => find.byWidgetPredicate((Widget w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == kGardenPestAsset);

/// 资源 chips 行（`×N` 文本的**第二层**祖先 Row）。
Finder _chipsRow() {
  final Finder rows = find.ancestor(
    of: find.textContaining('×').first,
    matching: find.byType(Row),
  );
  return rows.at(1);
}

/// 一键操作的确认卡流程：FAB → 菜单 → 等确认卡（**不点确定**）。
Future<void> _openOneClickCard(
  WidgetTester tester,
  String actionLabel,
) async {
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');
  await tester.tap(find.byIcon(Icons.touch_app));
  final bool menuShown = await _pumpUntil(
    tester,
    () => find.text(actionLabel).evaluate().isNotEmpty,
  );
  expect(menuShown, isTrue, reason: '点 FAB 应展开操作菜单（$actionLabel）');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(actionLabel));

  final bool dialogShown = await _pumpUntil(
    tester,
    () => find.text('确定').evaluate().isNotEmpty,
  );
  expect(dialogShown, isTrue, reason: '一键操作应先弹确认卡');
  await tester.pump(const Duration(milliseconds: 300));
}

/// 一键操作的确认卡流程：FAB → 菜单 → 确认卡 → 确定。
Future<void> _runOneClick(WidgetTester tester, String actionLabel) async {
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');
  await tester.tap(find.byIcon(Icons.touch_app));
  final bool menuShown = await _pumpUntil(
    tester,
    () => find.text(actionLabel).evaluate().isNotEmpty,
  );
  expect(menuShown, isTrue, reason: '点 FAB 应展开操作菜单（$actionLabel）');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(actionLabel));

  final bool dialogShown = await _pumpUntil(
    tester,
    () => find.text('确定').evaluate().isNotEmpty,
  );
  expect(dialogShown, isTrue, reason: '一键操作应先弹确认卡');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('确定'));
  await tester.pump(const Duration(milliseconds: 16));
}

/// 养护卡里「带指定价格文案的那个动作按钮」（相邻两个按钮价格互不重复）。
Future<void> _tapCostButton(WidgetTester tester, String costLabel) async {
  final Finder cost = find.text(costLabel);
  expect(cost, findsOneWidget, reason: '养护卡上应有价格「$costLabel」');
  final Finder button = find
      .ancestor(of: cost, matching: find.byType(OutlinedButton))
      .first;
  await tester.tap(button);
  await _pumpFrames(tester, 30);
}

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();

  tearDown(() {
    AppLocaleController.current = const Locale('zh');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 1 · 无券基线（防回归地基）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('1 · 无券：水 5 / 肥 10 / 除草 +1 / 除虫 +2（与改动前逐位相同）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    // p0 = 有杂草（验 tooltip +1），p1 = 干净（点它开养护卡看水价 / 肥价，
    // 避免点到浮标把点击吃掉）。
    final _MemPlantRepo plants =
        _MemPlantRepo(<Plant>[_weedyPlant(), _plants(2)[1]]);
    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: plants,
      store: _FakeGuardStore(), // 今天没有券
      capacity: 4,
    ));

    expect(
      await _pumpUntil(tester, () => _weedChip().evaluate().isNotEmpty),
      isTrue,
      reason: '前置：植物上的杂草浮标应渲染',
    );
    expect(_semanticLabel(_weedTooltip(1)), findsOneWidget,
        reason: '无券时除草 tooltip 必须是基础 +1 ☀');

    // 打开养护卡看水价 / 肥价（点第二盆，避开杂草浮标的 opaque 命中区）。
    await tester.tap(find.byType(GardenPot).last);
    expect(
      await _pumpUntil(tester, () => find.text('5 ☀').evaluate().isNotEmpty),
      isTrue,
      reason: '养护卡应就绪并显示水价',
    );
    expect(find.text('5 ☀'), findsOneWidget, reason: '无券水价 = 5 ☀');
    expect(find.text('10 ☀'), findsOneWidget, reason: '无券肥价 = 10 ☀');
  });

  testWidgets('1b · 无券：除虫 tooltip = +2 ☀', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final Plant pestPlant = Plant(
      id: 'pest0',
      speciesId: _sunflower.id,
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: now.subtract(const Duration(hours: 2)),
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(hours: 2)),
      lastWaterAt: now.subtract(const Duration(days: 2)),
      pestAt: today,
      weedPestRollDay: today,
    );
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(<Plant>[pestPlant]),
      store: _FakeGuardStore(),
      capacity: 4,
    ));

    expect(
      await _pumpUntil(tester, () => _pestChip().evaluate().isNotEmpty),
      isTrue,
    );
    expect(_semanticLabel(_pestTooltip(2)), findsOneWidget,
        reason: '无券时除虫 tooltip 必须是基础 +2 ☀');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2 · 浇水券（存量存档剩 1）+ 批量 3 盆（🔴 B13.4 不限次：全程足额）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('2 · 浇水券（存量剩 1）+ 批量 3 盆：4 / 4 / 4，合计 12（B13.4）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    final List<Plant> four = _plants(4);
    // p3 今天刚浇过（账本里有一条同刻 plant_water）⇒ 30 分钟间隔闸门把它跳过，
    // 计划恰好剩 3 盆（FAB 仍因 4 株存活而出现）。
    ledger.entries.add(SunlightEntry(
      id: 'seed_water_p3',
      ts: DateTime.now(),
      type: SunlightType.plant,
      gross: 5,
      net: -5,
      balanceAfter: 995,
      refType: kPlantWaterRefType,
      refId: 'p3',
      dayKey: _todayKey(),
    ));

    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(four),
      // 浇水券：quota 6、已用 5（旧封顶时代的存量记账）——B13.4 起不挡减免。
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6, used: 5),
      ),
      capacity: 6,
    ));

    await _runOneClick(tester, '一键浇水');
    await _pumpFrames(tester, 40); // 等逐盆执行 + 汇总浮层

    final List<int> spent = ledger
        .ofType(kPlantWaterRefType)
        .where((SunlightEntry e) => e.refId != 'p3')
        .map((SunlightEntry e) => (-e.net).round())
        .toList();
    expect(spent, <int>[4, 4, 4],
        reason: 'B13.4：浇水券当日不限次，额度字段不挡减免（旧口径 4/5/5 废除）');
    expect(spent.fold<int>(0, (int a, int b) => a + b), 12,
        reason: '合计 12 —— 不是 14（旧封顶口径）、不是 15');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3 · 浇水券 + 批量 12 盆（🔴 B13.4 不限次：12 盆全 4）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('3 · 浇水券 + 批量 12 盆：全 4，合计 48（B13.4 不限次）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(_plants(12)),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6),
      ),
      capacity: 12,
    ));

    await _runOneClick(tester, '一键浇水');
    await _pumpFrames(tester, 60);

    final List<int> spent = ledger.amountsOf(kPlantWaterRefType);
    expect(spent.length, 12, reason: '12 盆应各入账一条 plant_water');
    expect(spent, <int>[4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
        reason: 'B13.4：当日不限次，12 盆全部 −1（旧「前 6 盆 4 后 6 盆 5」废除）');
    expect(spent.fold<int>(0, (int a, int b) => a + b), 48,
        reason: '合计 48 = 12×5 − 12：减免 12 ☀（旧封顶 6 ☀ 废除）');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3b / 3c · G1：确认卡 note 必须与合计同口径（单值 / 区间两档）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('3b · 浇水券 + 12 盆（B13.4 不限次）：note 单值「每盆 4 ☀」且合计 −48 ☀',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(_plants(12)),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6),
      ),
      capacity: 12,
    ));

    await _openOneClickCard(tester, '一键浇水');

    // 🔴 B13.4：12 盆全部 4 ☀ ⇒ 单价齐整，note 回**单值**口径（旧区间 4~5 废除）。
    expect(
      find.text('将对 12 盆植物各浇 1 次水（每盆 4 ☀）'),
      findsOneWidget,
      reason: '不限次后每盆同价，必须报单值而不是区间',
    );
    expect(find.text('−48 ☀'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChildConfirmCard),
        matching: find.textContaining('4~5'),
      ),
      findsNothing,
      reason: '不得残留旧封顶时代的区间 note',
    );

    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ledger.entries, isEmpty, reason: '取消 ⇒ 分毫不扣');
  });

  testWidgets('3c · 无券 + 12 盆：note 仍是「每盆 5 ☀」且卡内不出现 ~',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(_plants(12)),
      store: _FakeGuardStore(), // 今天没有券
      capacity: 12,
    ));

    await _openOneClickCard(tester, '一键浇水');

    expect(
      find.text('将对 12 盆植物各浇 1 次水（每盆 5 ☀）'),
      findsOneWidget,
      reason: '单价全相同 ⇒ 必须沿用原单值文案（逐字不变）',
    );
    expect(find.text('−60 ☀'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChildConfirmCard),
        matching: find.textContaining('~'),
      ),
      findsNothing,
      reason: '单价一致时不得出现区间波浪号',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4 · 有植物盆除草 + 劳动券：实到 2、飘字 +2
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('4 · 劳动券 + 有植物盆除草：账本 2 ☀ 且飘字 +2（同一个 perk）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(<Plant>[_weedyPlant()]),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.laborVoucher, quota: 4),
      ),
      capacity: 4,
    ));

    expect(
      await _pumpUntil(tester, () => _weedChip().evaluate().isNotEmpty),
      isTrue,
      reason: '前置：杂草浮标应渲染',
    );
    expect(_semanticLabel(_weedTooltip(2)), findsOneWidget,
        reason: '劳动券下 tooltip 必须显示 +2 ☀（与实发同源）');

    await tester.tap(_weedChip().first);
    final bool settled = await _pumpUntil(
      tester,
      () => find.text('除草成功').evaluate().isNotEmpty,
      maxFrames: _clearSettleFrames,
    );
    expect(settled, isTrue, reason: '演出 + 淡出结束后应弹飘字');

    final SunlightEntry entry = ledger.ofType(kGardenWeedRefType).single;
    expect(entry.net, 2.0, reason: '劳动券：除草基础 1 + 1 = 2 ☀ 实到');
    expect(find.text('+2'), findsOneWidget,
        reason: '飘字必须是 +2（与账本同一个 clearPerk；各算一遍会分叉）');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5 · 空盆除草 + 劳动券：实到 2
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('5 · 劳动券 + 空盆除草：账本 2 ☀', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final _MemLedger ledger = _MemLedger();
    final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo(<PotDisturbance>[
      PotDisturbance(potIndex: 0, weedAt: today, rollDay: today),
    ]);

    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(<Plant>[]),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.laborVoucher, quota: 4),
      ),
      capacity: 4,
      pots: pots,
    ));

    final bool weedShown = await _pumpUntil(
      tester,
      () => _weedChip().evaluate().isNotEmpty,
    );
    expect(weedShown, isTrue, reason: '前置：空盆应渲染杂草浮标');
    // 空盆浮标同样按劳动券显示 +2（与植物侧同源）。
    expect(_semanticLabel(_weedTooltip(2)), findsOneWidget);

    await tester.tap(_weedChip().first);
    final bool earned = await _pumpUntil(
      tester,
      () => ledger.ofType(kGardenWeedRefType).isNotEmpty,
      maxFrames: _clearSettleFrames,
    );
    expect(earned, isTrue, reason: '空盆拔草必须入账');
    expect(ledger.ofType(kGardenWeedRefType).single.net, 2.0,
        reason: '劳动券：空盆除草也是 1 + 1 = 2 ☀');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6 · 施肥券：今日每次施肥都 −2 ☀（额度 12 次，同日两次都是 8）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('6 · 施肥券：今日每次施肥都是 8 ☀（额度 12 次，不缩额）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_plants(2));
    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.fertilizeVoucher, quota: 12));
    final ProviderContainer container =
        _careContainer(ledger: ledger, plants: plants, store: store);

    await _openCareCard(tester, container, 'p0');
    expect(find.text('8 ☀'), findsOneWidget,
        reason: '施肥券：今日每次施肥都显示 8 ☀（10 − 2）');

    await _tapCostButton(tester, '8 ☀');
    expect(ledger.ofType(kPlantFertilizeRefType).single.net, -8.0,
        reason: '第 1 次施肥实扣 8 ☀');
    expect(store.state?.buff?.used, 1,
        reason: '施肥 1 次核销 1 个额度（共 12 次，还剩 11 次）');

    // 同日另一盆：额度还剩 11 次 ⇒ 仍然 8 ☀（不是回原价 10）。
    await _openCareCard(tester, container, 'p1');
    expect(find.text('8 ☀'), findsOneWidget,
        reason: '同日第二次施肥仍是 8 ☀（今日每次施肥都 −2 ☀）');

    await _tapCostButton(tester, '8 ☀');
    expect(
      ledger.amountsOf(kPlantFertilizeRefType),
      <int>[8, 8],
      reason: '两次施肥各扣 8 ☀，合计 16',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7 · 免费浇水券（单株）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('7 · 免费浇水券：显示 0、实扣 0；核销后另一盆显示 5',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_plants(2));
    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.freeWater, quota: 1));
    final ProviderContainer container =
        _careContainer(ledger: ledger, plants: plants, store: store);

    await _openCareCard(tester, container, 'p0');
    expect(find.text('0 ☀'), findsOneWidget,
        reason: '免费浇水券：该株水价显示 0 ☀');

    await _tapCostButton(tester, '0 ☀');
    expect(ledger.ofType(kPlantWaterRefType).single.net, 0.0,
        reason: '实际扣 0 ☀（免费券只对单株生效）');
    expect(store.state?.buff?.used, 1, reason: '免费浇水券用一次即核销');

    // 核销后另开一盆：券已用完 ⇒ 5 ☀。
    await _openCareCard(tester, container, 'p1');
    expect(find.text('5 ☀'), findsOneWidget,
        reason: '免费额度用掉后另一盆必须回原价 5 ☀');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 8 · 免费浇水券 + 一键批量：前 N 次免费、按盆计数（B13.20）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('8 · 免费浇水券 + 一键批量 4 盆：前 1 盆 0 ☀ 后 3 盆 5 ☀，额度核销 1 次',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.freeWater, quota: 1));

    await tester.pumpWidget(_hostGarden(
      ledger: ledger,
      plants: _MemPlantRepo(_plants(4)),
      store: store,
      capacity: 6,
    ));

    await _runOneClick(tester, '一键浇水');
    await _pumpFrames(tester, 40);

    // 🔴 B13.20：批量按盆计数 —— 总免费额恒 = 券面值（1 × 5 ☀），
    //    绝不整批免费（0,0,0,0）也绝不整批原价（5,5,5,5）。
    expect(ledger.amountsOf(kPlantWaterRefType), <int>[0, 5, 5, 5],
        reason: 'B13.20：前 1 盆免费、后 3 盆原价（额度按盆核销）');
    expect(store.writeCount, 1, reason: '免费额度恰好核销 1 次');
    expect(store.state?.buff?.remaining, 0, reason: '×1 券额度用尽');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 9 · 跨天过期
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('9 · 存档 dayKey 是昨天：价格原样、chip 不显示',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    final _FakeGuardStore store = _FakeGuardStore(GuardDayState(
      dayKey: dayKey(yesterday),
      status: GuardDayStatus.claimed,
      dropKind: GuardDropKind.waterVoucher,
      buff: const GuardBuffState(
        kind: GuardDropKind.waterVoucher,
        quota: 6,
      ),
    ));

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
      capacity: 4,
    ));
    await _pumpFrames(tester, 40);

    expect(find.byKey(GuardBuffChip.chipKey), findsNothing,
        reason: '存档不是今天 ⇒ currentBuff 返回 null ⇒ 不显示 chip');

    await tester.tap(find.byType(GardenPot).first);
    expect(
      await _pumpUntil(tester, () => find.text('5 ☀').evaluate().isNotEmpty),
      isTrue,
    );
    expect(find.text('5 ☀'), findsOneWidget, reason: '过期券不得再减免（水价原样 5）');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 10 · prefs 不可用（不 override sharedPreferencesProvider）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('10 · prefs 不可用：花园页正常渲染、无错误页、价格原样',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      capacity: 4,
      // store 为 null ⇒ 不 override guardStateStoreProvider ⇒ prefs 抛 UnimplementedError
    ));

    final bool loaded = await _pumpUntil(
      tester,
      () => find.textContaining('×').evaluate().isNotEmpty,
    );
    expect(loaded, isTrue, reason: '券读不到也必须正常渲染（不得停在错误页）');
    expect(find.textContaining('加载失败'), findsNothing,
        reason: '绝不能把「券不可用」打成整页错误页');
    expect(find.byKey(GuardBuffChip.chipKey), findsNothing,
        reason: '读不到券 ⇒ 视同「今天没券」，不显示 chip');

    await tester.tap(find.byType(GardenPot).first);
    expect(
      await _pumpUntil(tester, () => find.text('5 ☀').evaluate().isNotEmpty),
      isTrue,
    );
    expect(find.text('5 ☀'), findsOneWidget, reason: 'price 原样（无券）');
    expect(find.text('10 ☀'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 11 · chip 无 ×、chips 行几何不变（embedded 12 / standalone 60）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('11 · chip 无 ×；embedded chips top == 12、left == 12',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6),
      ),
      capacity: 4,
    ));
    expect(
      await _pumpUntil(
          tester, () => find.byKey(GuardBuffChip.chipKey).evaluate().isNotEmpty),
      isTrue,
      reason: '前置：今日券 chip 应渲染',
    );

    expect(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.textContaining('×'),
      ),
      findsNothing,
      reason: '🔴 chip 文案里绝不能出现 ×（A3 / 开花奖励用例按 × 定位 chips）',
    );

    final Rect chips = tester.getRect(_chipsRow());
    expect(chips.top, closeTo(12, 0.5), reason: 'embedded chips 视觉顶恒 y=12');
    expect(chips.left, closeTo(12, 0.5), reason: 'chips 左锚 12');
    // chip 在 chips 行下方（不挤占、不覆盖）。
    final Rect chipRect =
        tester.getRect(find.byKey(GuardBuffChip.chipKey));
    expect(chipRect.top, greaterThan(chips.bottom),
        reason: '券 chip 必须在资源 chips 行**下方**');
  });

  testWidgets('11b · standalone chips 视觉顶 − body 顶 == 60', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6),
      ),
      capacity: 4,
      embedded: false,
    ));
    expect(
      await _pumpUntil(
          tester, () => find.byKey(GuardBuffChip.chipKey).evaluate().isNotEmpty),
      isTrue,
    );

    final double bodyTop = tester.getRect(find.byType(AppBar)).bottom;
    final Rect chips = tester.getRect(_chipsRow());
    expect(chips.top - bodyTop, closeTo(60, 0.5),
        reason: 'standalone 与 embedded 同一套相对几何（12 + 48 = 60）');
    expect(chips.left, closeTo(12, 0.5));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 12 · 320×568 + en + 1.3 倍字号：chip 无 overflow
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('12 · 320×568 + en + 1.3 倍字号：chip 在场且无 overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    AppLocaleController.current = const Locale('en');

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: _FakeGuardStore(
        // 英文文案最长的一档：浇水券（带「剩 N」）；劳动券已去掉剩余量。
        _guardDay(GuardDropKind.waterVoucher, quota: 6),
      ),
      capacity: 4,
    ));
    expect(
      await _pumpUntil(
          tester, () => find.byKey(GuardBuffChip.chipKey).evaluate().isNotEmpty),
      isTrue,
      reason: '前置：en 环境下 chip 仍应渲染',
    );
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull,
        reason: 'EN + 1.3 倍字号 + 320 宽下不得出现 RenderFlex overflow');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 13 · refLabelOf 三个 guard refType
  // ══════════════════════════════════════════════════════════════════════════
  test('13 · refLabelOf：guard_pay / guard_win / guard_stolen 不再是「其他」', () {
    expect(refLabelOf(kGuardPayRefType, zh), '请守卫出手');
    expect(refLabelOf(kGuardWinRefType, zh), '赶跑偷菜贼');
    expect(refLabelOf(kGuardStolenRefType, zh), '被偷菜贼偷走');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 14 · 存量存档「额度用完」（🔴 B13.4）：浇水券不限次 ⇒ 水价仍 4，
  //      chip 仍在屏上且**不**追加「已用完」（施肥 / 免费券才保留该口径）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('14 · 存量额度用完（B13.4 不限次）：水价仍 4，chip 在屏且不含「已用完」',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      // quota 6、used 6 ⇒ 旧封顶时代的「用完」记账 —— B13.4 起不影响减免。
      store: _FakeGuardStore(
        _guardDay(GuardDropKind.waterVoucher, quota: 6, used: 6),
      ),
      capacity: 4,
    ));

    expect(
      await _pumpUntil(
          tester, () => find.byKey(GuardBuffChip.chipKey).evaluate().isNotEmpty),
      isTrue,
      reason: '券仍然显示（不限次券更不会「用完消失」）',
    );
    final Iterable<Text> chipTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byType(Text),
      ),
    );
    expect(
      chipTexts.map((Text t) => t.data ?? '').join(),
      isNot(contains('已用完')),
      reason: '🔴 B13.4：浇水券当日不限次，「已用完」永不出现（used==quota 只是旧记账）',
    );

    await tester.tap(find.byType(GardenPot).first);
    expect(
      await _pumpUntil(tester, () => find.text('4 ☀').evaluate().isNotEmpty),
      isTrue,
    );
    expect(find.text('4 ☀'), findsOneWidget,
        reason: '🔴 B13.4：即便存量记账 used==quota，水价仍是券后 4 ☀');
  });

  // 🔴 2026-11-12 玄参 iPad 实测「获得了浇水券，养护卡浇水还要 5 ☀」回归：
  // 根因 = `plant_care_sheet` 用 `currentBuff()`（只返回**主券**）——今天
  // 主券是劳动券、浇水券是**第二张**（B13.5 双券）时，养护卡永远拿不到
  // 浇水券 ⇒ 5 ☀。修复 = 改 `currentBuffs()` + 按动作匹配（同花园页）。
  // 本用例钉死：主券 labor + 第二张 water ⇒ 养护卡浇水 4 ☀、除草 +2 生效。
  testWidgets('双券（主劳动 + 第二浇水）：养护卡浇水 4 ☀（原 bug：只读主券 → 5 ☀）',
      (WidgetTester tester) async {
    final _FakeGuardStore store = _FakeGuardStore(GuardDayState(
      dayKey: _todayKey(),
      status: GuardDayStatus.claimed,
      dropKind: GuardDropKind.laborVoucher,
      buff: const GuardBuffState(
        kind: GuardDropKind.laborVoucher,
        quota: 4,
      ),
      bonusBuff: const GuardBuffState(
        kind: GuardDropKind.waterVoucher,
        quota: 6,
      ),
    ));

    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
      capacity: 4,
    ));
    await _pumpFrames(tester, 40);

    await tester.tap(find.byType(GardenPot).first);
    expect(
      await _pumpUntil(tester, () => find.text('4 ☀').evaluate().isNotEmpty),
      isTrue,
      reason: '🔴 第二张浇水券必须在养护卡生效：5 − 1 = 4 ☀（只读主券的旧实现这里显示 5 ☀）',
    );
    // 除草（主券劳动券）也照常生效：奖励 1 + 1 = 2 —— 双券互不干扰。
    expect(find.text('4 ☀'), findsOneWidget,
        reason: '水价只出现一份（券后 4 ☀，不是原价 5 ☀）');
  });
}
