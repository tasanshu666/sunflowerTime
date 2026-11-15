/// F204 回归 · 一键护理**必须清掉空盆干扰物**（玄参 2026-11-15 真机裁定）。
///
/// 玄参原话：「我刚才给花园做了一件护理，但是发现空盆的杂草和害虫没有被清理掉，
/// 这应该是个bug」。旧口径（garden_page 334 行注释）认为「一键护理不触碰空盆
/// 干扰物」是刻意设计 —— 本裁定推翻：一键护理目标**扩到空盆干扰物**。
///
/// 用例：
/// * A：植物侧无干扰物、空盆 pot4（草+虫）/ pot5（虫）→ 确认卡「共清理 3 处，
///   奖励合计 +5 ☀」→ 确定 → 仓储草虫位清空 + 账本 3 行（refId='pot:<i>' 与
///   EmptyPotService 单清同源）+ 汇总提示「一键护理成功 ×3」；
/// * B：植物 p0 长草 + 空盆 pot4 长虫 → 两类目标**同批**清掉（账本 2 行）。
///
/// ⚠️ 花园页木牌呼吸 / 害虫待机微动都是无限动画 → 全程有界 `pump`（禁 pumpAndSettle）。
library one_click_care_empty_pot_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 4 株「幼苗 · 成长中 · 无干扰物」的活株（占盆 0~3，容量 6 ⇒ 空盆 4、5）。
List<Plant> _fourCleanSprouts({bool weedOnFirst = false}) {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: 0.3,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now.subtract(const Duration(hours: 2)),
        lastWaterAt: now.subtract(const Duration(days: 2)),
        weedAt: (weedOnFirst && i == 0) ? DateTime(now.year, now.month, now.day) : null,
        // 🔴 预置 weedAt 时必须同步写幂等位：否则 _reload → tickAll 的每日 roll
        //    会用 NoHitRandom 把预置杂草重写成无草（weedAt = kClear）。
        weedPestRollDay:
            (weedOnFirst && i == 0) ? DateTime(now.year, now.month, now.day) : null,
      ),
  ];
}

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 6,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 内存账本（记录全部 append 行，余额按 net 累加）。
class _MemLedger implements SunlightRepository {
  static const double initialBalance = 100.0;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> entriesOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    final List<SunlightEntry> list = entriesOf(refType).toList()
      ..sort((SunlightEntry a, SunlightEntry b) => b.ts.compareTo(a.ts));
    return list.isEmpty ? null : list.first;
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
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String key) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _StoringPlantRepository implements PlantRepository {
  _StoringPlantRepository(this._plants);
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
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

/// 内存版空盆干扰物仓储（与 empty_pot_disturbance_test 同款）。
class _MemPotRepo implements PotDisturbanceRepository {
  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  /// 预置「今天出现」的干扰物（weedAt/pestAt = 今日零点；rollDay = 今日零点
  /// ⇒ 之后任何 tick 不会重掷骰子把预置状态覆盖掉 —— 与
  /// [EmptyPotService.forceDisturbanceForDebug] 同一「与生产同语义」口径）。
  void seed(int potIndex, {bool weed = false, bool pest = false}) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    store[potIndex] = PotDisturbance(
      potIndex: potIndex,
      weedAt: weed ? today : null,
      pestAt: pest ? today : null,
      rollDay: today,
    );
  }

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      List<PotDisturbance>.of(store.values);

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];

  @override
  Future<void> save(PotDisturbance disturbance) async =>
      store[disturbance.potIndex] = disturbance;

  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);

  @override
  Future<void> deleteAll() async => store.clear();
}

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

Widget _host(
  PlantRepository plants,
  PotDisturbanceRepository pots,
  SunlightRepository ledger,
) =>
    ProviderScope(
      overrides: <Override>[
        // free 档隐藏一键 FAB → 按**买断档**运行（与既有 one-click 用例同款）。
        entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(ledger),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
        potDisturbanceRepositoryProvider.overrideWithValue(pots),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        plantGrowthServiceProvider.overrideWith((ref) => PlantGrowthService(
              plants: ref.watch(plantRepositoryProvider),
              focus: ref.watch(focusRepositoryProvider),
              ledger: ref.watch(sunlightRepositoryProvider),
              settings: ref.watch(settingsRepositoryProvider),
              bloomRewards: ref.watch(bloomRewardRepositoryProvider),
              weedRandom: NoHitRandom(),
            )),
      ],
      child:
          const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

/// 预置「今天出现」的空盆干扰物由 [_MemPotRepo.seed] 承担（类方法，直接写 store）。

void main() {
  testWidgets('F204-A：植物侧无干扰物，空盆 pot4（草+虫）/pot5（虫）被一键护理清掉',
      (WidgetTester tester) async {
    final _MemPotRepo pots = _MemPotRepo()
      ..seed(4, weed: true, pest: true)
      ..seed(5, pest: true);
    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(
        _host(_StoringPlantRepository(_fourCleanSprouts()), pots, ledger));

    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

    await tester.tap(find.byIcon(Icons.touch_app));
    final bool menuShown = await _pumpUntil(
      tester,
      () => find.text('一键护理').evaluate().isNotEmpty,
    );
    expect(menuShown, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('一键护理'));

    // 确认卡：3 处（pot4 草+虫、pot5 虫），奖励合计 1+2+2 = 5。
    final bool dialogShown = await _pumpUntil(
      tester,
      () => find.text('要一键护理吗？').evaluate().isNotEmpty,
    );
    expect(dialogShown, isTrue,
        reason: '🔴 F204：植物计划为空但空盆有草虫 ⇒ 必须照常进确认卡（旧口径直接空计划提示）');
    expect(find.text('共清理 3 处，奖励合计 +5 ☀'), findsOneWidget,
        reason: '确认卡处数/奖励必须含空盆干扰物');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定'));

    // 执行 + 刷新（有界 pump 等收尾）。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // ① 仓储：pot4 草虫位清空、pot5 虫位清空（rollDay 保留防同日重 roll）。
    expect(pots.store[4]!.hasWeed, isFalse, reason: 'pot4 杂草应被一键护理清掉');
    expect(pots.store[4]!.hasPest, isFalse, reason: 'pot4 害虫应被一键护理清掉');
    expect(pots.store[5]!.hasPest, isFalse, reason: 'pot5 害虫应被一键护理清掉');
    expect(pots.store[4]!.rollDay, isNotNull, reason: '清除后保留 rollDay（防同日重 roll）');

    // ② 账本：与 EmptyPotService 单清同源（refType 复用植物侧、refId='pot:<i>'）。
    final List<SunlightEntry> weedRows =
        ledger.entriesOf(kGardenWeedRefType).toList();
    final List<SunlightEntry> pestRows =
        ledger.entriesOf(kGardenPestRefType).toList();
    expect(weedRows.length, 1, reason: 'pot4 杂草奖励 1 行');
    expect(weedRows.single.refId, 'pot:4');
    expect(weedRows.single.net, kGardenWeedReward);
    expect(pestRows.length, 2, reason: 'pot4 + pot5 害虫奖励 2 行');
    expect(
      <String>[for (final SunlightEntry e in pestRows) e.refId ?? '']..sort(),
      <String>['pot:4', 'pot:5'],
    );
    for (final SunlightEntry e in pestRows) {
      expect(e.net, kGardenPestReward);
    }

    // ③ 汇总提示：成功 ×3。
    final bool hintShown = await _pumpUntil(
      tester,
      () => find.text('一键护理成功 ×3').evaluate().isNotEmpty,
    );
    expect(hintShown, isTrue, reason: '汇总计数应含空盆目标');
  });

  testWidgets('F204-B：植物 p0 长草 + 空盆 pot4 长虫 → 两类目标同批清掉',
      (WidgetTester tester) async {
    final _MemPotRepo pots = _MemPotRepo()..seed(4, pest: true);
    final _MemLedger ledger = _MemLedger();
    await tester.pumpWidget(_host(
        _StoringPlantRepository(_fourCleanSprouts(weedOnFirst: true)),
        pots,
        ledger));

    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue);

    await tester.tap(find.byIcon(Icons.touch_app));
    final bool menuShown = await _pumpUntil(
      tester,
      () => find.text('一键护理').evaluate().isNotEmpty,
    );
    expect(menuShown, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('一键护理'));

    final bool dialogShown = await _pumpUntil(
      tester,
      () => find.text('要一键护理吗？').evaluate().isNotEmpty,
    );
    expect(dialogShown, isTrue);
    expect(find.text('共清理 2 处，奖励合计 +3 ☀'), findsOneWidget,
        reason: '植物草（+1）+ 空盆虫（+2）= 2 处 +3 ☀');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定'));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(pots.store[4]!.hasPest, isFalse, reason: '空盆 pot4 害虫应被清掉');
    final List<SunlightEntry> weedRows =
        ledger.entriesOf(kGardenWeedRefType).toList();
    final List<SunlightEntry> pestRows =
        ledger.entriesOf(kGardenPestRefType).toList();
    expect(weedRows.length, 1);
    expect(weedRows.single.refId, 'p0', reason: '植物侧 refId = plantId（口径不变）');
    expect(weedRows.single.net, kGardenWeedReward);
    expect(pestRows.length, 1);
    expect(pestRows.single.refId, 'pot:4');
    expect(pestRows.single.net, kGardenPestReward);
  });
}
