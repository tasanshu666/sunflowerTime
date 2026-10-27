/// 调试面板「空盆干扰」入口回归（F157-FEAT-3）。
///
/// ## 为什么加它（玄参 2026-10-27 原话）
/// 「我没有调试按钮，建了空盆之后，我不能在空盆上让它直接长草或长虫，然后再去
/// 清除草和虫」。
///
/// 现状（改造前）：`bloom_debug_panel.dart` 已有「长出杂草🌿 / 长出害虫🐛」，但走
/// `Plant` 字段（**只对有植物盆生效**）；空盆干扰物（`PotDisturbance`）没有强制
/// 入口 —— 而它每天只有 20% / 15% 概率、还有**首日免疫**，真机上根本等不到，
/// F155/F156 无法验收。
///
/// ## 本文件钉死的行为
///  ① 面板新增「空盆长草 / 空盆长虫 / 空盆草虫全清」，作用于**第一个空盆**
///     （无空盆时按钮禁用 + 提示）；
///  ② 点「空盆长草」→ 该盆 `hasWeed == true`（写 `weedAt = rollDay = 今天零点`，
///     与生产 roll 同语义）→ 关闭面板回花园能看到杂草浮标；
///  ③ 点「空盆草虫全清」→ 状态清空 **且账本新增 2 行**（草 + 虫各一条，走
///     `EmptyPotService.clearWeed/clearPest` 的生产链路，带 `refType` 与 `refId`）。
///
/// ## 位置纪律（本文件依赖它）
/// 「空盆干扰」区块在面板列表**末尾**（不顶掉既有条目 → 存量用例零回归），
/// 因此用例必须**先滚到它**再点。
///
/// ⚠️ 花园页木牌是无限呼吸动画 → 全程有界 `pump`，**禁止 `pumpAndSettle`**。
library empty_pot_debug_panel_test;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';

// ── Fake：空盆干扰物仓储（内存）──────────────────────────────────────────────

class _MemPotDisturbanceRepo implements PotDisturbanceRepository {
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

/// 永不命中的随机源（空盆每日 roll 恒不命中 → 测试状态完全由调试入口决定）。
class _NeverHitRandom implements Random {
  @override
  double nextDouble() => 0.9999999999999999;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

/// 账本 Fake：记录 append 条目 + 维护余额（其余对账口返回 0 / null）。
class _MemLedger implements SunlightRepository {
  double balanceValue = 1000;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> ofType(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

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
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits =
        entries.where((SunlightEntry e) => e.refType == refType).toList();
    return hits.isEmpty ? null : hits.last.ts;
  }
}

class _FakeSettingsRepo implements SettingsRepository {
  /// 4 盆（与 `kGardenPotCapacityDefault` 一致）。
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: 4,
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
  _MemPlantRepo(this.store);
  final List<Plant> store;

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
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

// ── 宿主与工具 ──────────────────────────────────────────────────────────────

/// 杂草浮标判据：`Image.asset(kGardenWeedAsset)`（素材缺失时组件回退 emoji，
/// 但 `Image` 节点仍在 → 加载成败都能定位，与 `empty_pot_ui_test` 同款做法）。
Finder _weedChip() => find.byWidgetPredicate((Widget w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == kGardenWeedAsset);

/// 有界帧推进（花园页木牌无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 240,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 只有 1 株植物（占盆 0）→ 盆 1 / 2 / 3 是空盆，「第一个空盆」= 1。
List<Plant> _onePlant() {
  final DateTime now = DateTime.now();
  return <Plant>[
    Plant(
      id: 'p0',
      speciesId: kSeedPlantSpecies.first.id,
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: now.subtract(const Duration(hours: 2)),
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(hours: 2)),
      lastWaterAt: now,
    ),
  ];
}

/// 真实花园页宿主（调试入口需 `kDebugMode`；测试环境恒 debug）。
Widget _host({
  required _MemPotDisturbanceRepo pots,
  required _MemLedger ledger,
  required _MemPlantRepo plants,
}) {
  final EmptyPotService svc = EmptyPotService(
    disturbances: pots,
    ledger: ledger,
    // 空盆每日 roll 恒不命中：状态只能由调试入口写入（确定性）。
    weedRandom: _NeverHitRandom(),
    pestRandom: _NeverHitRandom(),
    firstSightImmune: false,
  );
  return ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      sunlightRepositoryProvider.overrideWithValue(ledger),
      focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
      plantRepositoryProvider.overrideWithValue(plants),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      potDisturbanceRepositoryProvider.overrideWithValue(pots),
      emptyPotServiceProvider.overrideWithValue(svc),
    ],
    child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
  );
}

/// 打开调试面板并滚到「空盆干扰」区块（该区块在列表末尾，见文件头位置纪律）。
Future<void> _openPanelAndScrollToEmptyPotSection(WidgetTester tester) async {
  final bool entryShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.science).evaluate().isNotEmpty,
  );
  expect(entryShown, isTrue, reason: 'debug 构建应出现「花期调试」入口');

  await tester.tap(find.byIcon(Icons.science));
  final bool panelShown = await _pumpUntil(
    tester,
    () => find.text('花期调试').evaluate().isNotEmpty,
  );
  expect(panelShown, isTrue, reason: '点入口应弹出调试面板');

  // 等 bottom sheet 滑入动画结束（isScrollControlled + 0.85 屏高）。
  await tester.pump(const Duration(milliseconds: 400));

  // 滚到「空盆干扰」区块（列表末尾 → ListView 懒构建，必须先滚出来）。
  final Finder sheetScrollable = find
      .descendant(
        of: find.byType(BloomDebugSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.textContaining('空盆长草'),
    120,
    scrollable: sheetScrollable,
  );
  await tester.pump();
  expect(find.textContaining('空盆长草'), findsOneWidget,
      reason: '面板必须提供「空盆长草」调试按钮');
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 点「空盆长草」→ 该盆 hasWeed，关面板回花园能看到杂草浮标',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);

    final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_onePlant());

    await tester.pumpWidget(_host(pots: pots, ledger: ledger, plants: plants));
    await _openPanelAndScrollToEmptyPotSection(tester);

    // 目标盆回显（第一个空盆 = 盆 1）。
    expect(find.textContaining('目标：盆 #1'), findsOneWidget,
        reason: '默认作用于第一个空盆，并在面板内标注盆号');

    // 点「空盆长草」。
    await tester.tap(find.textContaining('空盆长草'));
    final DateTime today = DateTime.now();
    final DateTime todayZero = DateTime(today.year, today.month, today.day);
    final bool written = await _pumpUntil(
      tester,
      () => pots.store[1]?.hasWeed ?? false,
    );
    expect(written, isTrue, reason: '点「空盆长草」→ 盆 1 必须立即长出杂草');
    expect(
      pots.store[1]?.weedAt,
      equals(todayZero),
      reason: 'weedAt 必须是「今天零点」（与生产 roll 同语义，别写脏数据）',
    );
    expect(
      pots.store[1]?.rollDay,
      equals(todayZero),
      reason: 'rollDay 必须同步对齐今天（否则下次 tick 会把手工状态重掷掉）',
    );

    // 关闭面板 → 回花园看浮标。
    final BuildContext sheetCtx = tester.element(find.textContaining('空盆长草'));
    Navigator.of(sheetCtx).pop();
    final bool weedVisible = await _pumpUntil(
      tester,
      () => _weedChip().evaluate().isNotEmpty,
    );
    expect(weedVisible, isTrue,
        reason: '关面板回花园后，空盆上必须能看到杂草浮标');
  });

  testWidgets('② 点「空盆草虫全清」→ 状态清空 + 账本新增 2 行（草 + 虫）',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);

    final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_onePlant());

    await tester.pumpWidget(_host(pots: pots, ledger: ledger, plants: plants));
    await _openPanelAndScrollToEmptyPotSection(tester);

    // 先让盆 1 同时有草 + 虫（两个按钮各点一次）。
    await tester.tap(find.textContaining('空盆长草'));
    await _pumpUntil(tester, () => pots.store[1]?.hasWeed ?? false);
    await tester.tap(find.textContaining('空盆长虫'));
    final bool bothOn = await _pumpUntil(
      tester,
      () => pots.store[1]?.hasPest ?? false,
    );
    expect(bothOn, isTrue, reason: '「空盆长虫」应写入害虫');
    expect(ledger.entries, isEmpty, reason: '长草 / 长虫只是写状态，不入账');

    // 全清。
    await tester.tap(find.textContaining('空盆草虫全清'));
    final bool cleared = await _pumpUntil(
      tester,
      () =>
          !(pots.store[1]?.hasWeed ?? true) && !(pots.store[1]?.hasPest ?? true),
    );
    expect(cleared, isTrue, reason: '「空盆草虫全清」必须把草和虫都清掉');

    // 账本：草 + 虫各一行（与孩子真机点浮标**同一条链路**：带 refType / refId）。
    expect(ledger.ofType(kGardenWeedRefType).length, 1,
        reason: '拔草必须入账一行（refType = kGardenWeedRefType）');
    expect(ledger.ofType(kGardenPestRefType).length, 1,
        reason: '除虫必须入账一行（refType = kGardenPestRefType）');
    expect(ledger.entries.length, 2, reason: '全清 = 净新增 2 行（草 + 虫）');
    expect(
      ledger.ofType(kGardenWeedRefType).single.refId,
      equals(EmptyPotService.refIdOf(1)),
      reason: '空盆账本 refId 口径 = pot:<potIndex>（与植物侧 plantId 同构）',
    );

    // 面板里的状态回显同步（不再显示「草 / 虫：都有」）。
    expect(find.textContaining('当前状态：草 / 虫：无'), findsOneWidget,
        reason: '清完后面板状态回显必须同步为「草 / 虫：无」');
  });
}
