/// 物种表改版（玄参 2026-09-27 拍板）单测：**按物种计价** + 免费券 + 死亡后再种重扣。
///
/// C29 修订（玄参 2026-10-05 拍板）：**植物可重复种植**（废除「每物种仅一株」）；
/// 向日葵**无存活株时首株免费**、第 2 株起按 [kSpeciesSunlightCostCommon]（300）收阳光；
/// 普通档阳光价 400 → **300**。
///
/// 覆盖：
///  ① [PlantGrowthService.plantCost] 具体值（默认项）：向日葵免费 / 月光兰（精英）10 碎片 / 普通 300 阳光 / 精英 10 碎片；
///  ② 向日葵免费种植：不扣阳光、不扣碎片、不写账本；
///  ③ 普通档扣 300 阳光进账本（`refType='plant_plant'`）；
///  ④ 精英 / 普通碎片物种扣对应碎片；
///  ⑤ 碎片余额不足 → 拒绝且余额不变（**绝不为负**）；
///  ⑥ 免费券（`UnlockedSpecies` 语义）：有券时种植不扣碎片 / 阳光，且券被消耗；
///  ⑦ **C29 可重复种植**：同物种可多株并存；向日葵第 2 株起扣 300 阳光；
///  ⑧ 死亡后再种 → 允许且**重新扣费**（一次兑换买一株）；
///  ⑨ 花园页「选择要种的植物」弹窗：稀有度两档（普通 / 精英）与价格文案渲染；
///  ⑩ 种子券入口（玄参 2026-09-29；2026-10-03 徽章图片化）：持券物种徽章（分档种子图/🌰 回退 + 「种子」文字）+ 「用种子种（免费）」按钮置顶。
///  ⑪ **C29 铲除返还**：付费/券种株按档位 50% 返还（普通 150 / 精英 250）、免费首株与死亡株返 0、账本 refType 冻结值。
///  ⑫ **C29 一键操作计划**：跳过不可浇 / 不可施株、合计扣费、护理目标含草+虫双条。
///
/// 纯 Dart 仓储以内存 Fake 实现；弹窗用例为真实 `GardenPage` 组件测试。
library plant_species_pricing_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as t;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

class _MemPlantRepo implements PlantRepository {
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
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
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
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 账本 Fake：初始余额可配置，记录全部 append 条目。
class _MemLedger implements SunlightRepository {
  _MemLedger({this.initialBalance = 1000000});
  double initialBalance;
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
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == key)
          .length;
  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }
}

class _MemSettingsRepo implements SettingsRepository {
  /// 花盆容量（本用例统一 12）。
  static const int capacity = 12;
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: capacity,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger, this.bloomRewards);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
  final InMemoryBloomRewardRepository bloomRewards;
}

_Ctx _make({double balance = 1000000}) {
  final _MemPlantRepo plants = _MemPlantRepo();
  final _MemLedger ledger = _MemLedger(initialBalance: balance);
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: bloomRewards,
  );
  return _Ctx(svc, plants, ledger, bloomRewards);
}

PlantSpecies _sp(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

/// 复制一株植物并改状态（供「死亡后再种」用例）。
Plant _withStatus(Plant p, PlantStatus status) => p.copyWith(status: status);

void main() {
  // ── ① plantCost 具体值 ────────────────────────────────────────────────────
  t.group('① plantCost 具体值（按物种计价）', () {
    final _Ctx ctx = _make();

    t.test('向日葵（初始物种）→ 免费', () async {
      final PlantCost c =
          await ctx.svc.plantCost(_sp(kStarterSpeciesId), AgeTier.low);
      t.expect(c.kind, PlantCostKind.free);
      t.expect(c.amount, 0);
    });

    t.test('月光兰（精英）→ 10 碎片（低 / 高年段同值）', () async {
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low)).kind,
        PlantCostKind.fragments,
      );
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low)).amount,
        kSpeciesFragmentCostPremium,
      );
      t.expect(
        (await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.high))
            .amount,
        kSpeciesFragmentCostPremium,
      );
    });

    t.test('普通档（番茄 / 草莓）→ 300 阳光（默认取阳光，二选一之一；C29 修订 400→300）', () async {
      for (final String id in <String>['species_tomato', 'species_strawberry']) {
        final PlantCost c = await ctx.svc.plantCost(_sp(id), AgeTier.low);
        t.expect(c.kind, PlantCostKind.sunlight);
        t.expect(c.amount, kSpeciesSunlightCostCommon);
        t.expect(c.amount, 300);
      }
    });

    t.test('精英档（4 种）→ 10 碎片', () async {
      for (final String id in <String>[
        'species_star_flower',
        'species_rainbow_fern',
        'species_coral_orchid',
        'species_jade_hydrangea',
      ]) {
        final PlantCost c = await ctx.svc.plantCost(_sp(id), AgeTier.low);
        t.expect(c.kind, PlantCostKind.fragments);
        t.expect(c.amount, kSpeciesFragmentCostPremium);
        t.expect(c.amount, 10);
      }
    });

    t.test('fragmentCostOf：初始物种为 0，其余按档位派生', () {
      t.expect(ctx.svc.fragmentCostOf(_sp(kStarterSpeciesId)), 0);
      t.expect(ctx.svc.fragmentCostOf(_sp('species_tomato')), 6);
      t.expect(ctx.svc.fragmentCostOf(_sp('species_moon_orchid')), 10,
          reason: '月光兰为 rare（精英档），碎片价按档位派生为 10');
    });

    t.test('物种表：恰 8 种、顺序 = 展示顺序、移除 daisy/cactus', () {
      t.expect(kSeedPlantSpecies.length, 8);
      t.expect(
        kSeedPlantSpecies.map((PlantSpecies s) => s.id).toList(),
        <String>[
          'species_sunflower',
          'species_moon_orchid',
          'species_tomato',
          'species_strawberry',
          'species_star_flower',
          'species_rainbow_fern',
          'species_coral_orchid',
          'species_jade_hydrangea',
        ],
      );
      final Set<String> ids =
          kSeedPlantSpecies.map((PlantSpecies s) => s.id).toSet();
      t.expect(ids.contains('species_daisy'), t.isFalse);
      t.expect(ids.contains('species_cactus'), t.isFalse);
    });
  });

  // ── ②③④⑤ 种植收费 ────────────────────────────────────────────────────────
  t.group('②③④⑤ 种植收费（阳光 / 碎片）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('向日葵免费：不扣阳光、不扣碎片、不写账本', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
      t.expect((await ctx.plants.plants()), t.hasLength(1));
    });

    t.test('月光兰（精英）扣 10 碎片（不扣阳光，账本无 plant_plant）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_moon_orchid', 0, now);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 10);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty,
          reason: '精英碎片物种不扣阳光');
    });

    t.test('精英物种扣 10 碎片', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_star_flower', 0, now);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 10);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty,
          reason: '碎片物种不扣阳光');
    });

    t.test('普通物种扣 6 碎片', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_tomato', 0, now,
          payWith: PlantCostKind.fragments);
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 14);
    });

    t.test('碎片不足 → 拒绝且余额不变（不得为负）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(5);
      await t.expectLater(
        () => ctx.svc.plant('species_tomato', 0, now,
            payWith: PlantCostKind.fragments),
        t.throwsA(t.isA<PlantOperationException>()),
      );
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 5);
      t.expect(await ctx.plants.plants(), t.isEmpty, reason: '失败不应落植物');
    });

    t.test('碎片不足（月光兰）→ 拒绝且不扣', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(5);
      await t.expectLater(
        () => ctx.svc.plant('species_moon_orchid', 0, now),
        t.throwsA(t.isA<PlantOperationException>()),
      );
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 5);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty);
      t.expect(await ctx.plants.plants(), t.isEmpty);
    });
  });

  // ── ⑥ 种子券（2026-10-07 新口径：按档位判券 + 第三支付方式）────────────────
  // 旧行为废除（2026-10-07 玄参拍板）：① 券不再「种下时自动优先消耗」——种子是
  // 独立第三支付方式，用户点「种子」按钮才消耗；② 判券从「持有该物种的券」改为
  // 「持有同档位任意物种的券」（与花园左上角普通/精英种子计数同源）。
  t.group('⑥ 种子券（按档位判券 + 第三支付方式，2026-10-07）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('点「种子」支付：不扣碎片 / 阳光、同档位一张券被消耗、返还 = 档位 50%', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(0);
      await ctx.bloomRewards.unlockSpecies('species_strawberry'); // 普通档草莓券

      final Plant p = await ctx.svc
          .plant('species_tomato', 0, now, payWith: PlantCostKind.seed);

      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 0,
          reason: '种子支付 → 不扣碎片');
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.isEmpty,
          reason: '种子支付 → 不扣阳光');
      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(), t.isEmpty,
          reason: '同档位一张券被消耗（草莓券可种番茄：按档位判券）');
      t.expect(await ctx.plants.plants(), t.hasLength(1));
      t.expect(p.shovelRefund, kShovelRefundCommon,
          reason: '券种株铲除仍按档位 50% 返还（C29 口径不变）');
    });

    t.test('无显式 payWith 时不自动耗券：默认按阳光收费（旧「券优先」废除）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_strawberry'); // 普通券

      await ctx.svc.plant('species_tomato', 0, now); // 不点种子按钮

      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(),
          <String>['species_strawberry'],
          reason: '种子不再被自动消耗（2026-10-07 第三支付方式口径）');
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.hasLength(1),
          reason: '默认走阳光收费');
    });

    t.test('精英券不能种普通植物：判券按档位隔离', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_moon_orchid'); // 精英券

      await t.expectLater(
        ctx.svc.plant('species_tomato', 0, now, payWith: PlantCostKind.seed),
        t.throwsA(t.isA<PlantOperationException>()),
        reason: '只有精英券时普通植物无种子可付 → 抛错分因提示',
      );
      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(),
          <String>['species_moon_orchid'], reason: '精英券未被误耗');
    });

    t.test('可用支付方式：种子排最后 = 第三支付方式（阳光 / 碎片 / 种子）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_tomato');

      final List<PlantPaymentOption> opts =
          await ctx.svc.plantPaymentOptions(_sp('species_tomato'));
      t.expect(opts, t.hasLength(3), reason: '300 阳光 + 6 碎片 + 种子');
      t.expect(opts[0].kind, PlantCostKind.sunlight);
      t.expect(opts[1].kind, PlantCostKind.fragments);
      t.expect(opts[2].kind, PlantCostKind.seed,
          reason: '种子第三支付方式（玄参 2026-10-07）');

      // 券消耗后回到两档付费（无种子项）。
      await ctx.bloomRewards.consumeUnlock('species_tomato');
      final List<PlantPaymentOption> after =
          await ctx.svc.plantPaymentOptions(_sp('species_tomato'));
      t.expect(after, t.hasLength(2));
      t.expect(after.last.kind, PlantCostKind.fragments);
    });

    t.test('精英：碎片 + 种子两项；向日葵首株恒单一免费项不受券影响', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_star_flower'); // 精英券
      final List<PlantPaymentOption> elite =
          await ctx.svc.plantPaymentOptions(_sp('species_star_flower'));
      t.expect(elite, t.hasLength(2), reason: '10 碎片 + 种子');
      t.expect(elite[0].kind, PlantCostKind.fragments);
      t.expect(elite[1].kind, PlantCostKind.seed);

      final List<PlantPaymentOption> starter =
          await ctx.svc.plantPaymentOptions(_sp(kStarterSpeciesId));
      t.expect(starter, t.hasLength(1));
      t.expect(starter.first.kind, PlantCostKind.free);
    });

    t.test('向日葵第 2 株：阳光 + 种子（普通券可用）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_tomato'); // 普通券
      await ctx.svc.plant(kStarterSpeciesId, 0, now); // 首株免费
      final List<PlantPaymentOption> opts =
          await ctx.svc.plantPaymentOptions(_sp(kStarterSpeciesId));
      t.expect(opts, t.hasLength(2), reason: '300 阳光 + 种子');
      t.expect(opts[0].kind, PlantCostKind.sunlight);
      t.expect(opts[1].kind, PlantCostKind.seed);
      final Plant p2 = await ctx.svc
          .plant(kStarterSpeciesId, 1, now, payWith: PlantCostKind.seed);
      t.expect(await ctx.bloomRewards.unlockedSpeciesIds(), t.isEmpty,
          reason: '第 2 株可用普通券支付');
      t.expect(p2.shovelRefund, kShovelRefundCommon);
    });
  });

  // ── ⑦⑧ 可重复种植（C29）+ 死亡后再种重扣 ─────────────────────────────────
  t.group('⑦⑧ 可重复种植（C29）/ 死亡后再种重扣', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('同物种可重复种植（C29）：向日葵第 2 株起扣 300 阳光', () async {
      final _Ctx ctx = _make();
      final Plant p1 = await ctx.svc.plant(kStarterSpeciesId, 0, now); // 首株免费
      final Plant p2 = await ctx.svc.plant(kStarterSpeciesId, 1, now); // 第 2 株 -300
      t.expect(p1.id, t.isNot(p2.id));
      t.expect(await ctx.plants.plants(), t.hasLength(2),
          reason: 'C29：同物种可多株并存（娃想种多株向日葵）');
      final List<SunlightEntry> spends = ctx.ledger.entriesOf('plant_plant');
      t.expect(spends, t.hasLength(1), reason: '首株免费不写账本，第 2 株写一条');
      t.expect(spends.single.net, -kSpeciesSunlightCostCommon);
      t.expect(spends.single.refId, kStarterSpeciesId);
      // 第 2 株的铲除返还 = 普通 150（付费途径）。
      t.expect(p2.shovelRefund, kShovelRefundCommon);
      t.expect(p1.shovelRefund, 0, reason: '免费首株铲除不返还（防循环刷阳光）');
    });

    t.test('向日葵铲掉唯一一株后再种 → 恢复免费（无存活向日葵即首株）', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.svc.plant(kStarterSpeciesId, 1, now); // -300
      // 铲掉两株（首株返 0、第 2 株返 150）。
      final List<Plant> alive = await ctx.plants.plants();
      int refunded = 0;
      for (final Plant p in alive) {
        refunded += await ctx.svc.shovel(p.id, now);
      }
      t.expect(refunded, kShovelRefundCommon, reason: '仅付费株返还 150');
      final Plant p3 = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      t.expect(p3.shovelRefund, 0, reason: '无存活向日葵 → 再种又是免费首株');
      final List<SunlightEntry> spends = ctx.ledger.entriesOf('plant_plant');
      t.expect(spends, t.hasLength(1), reason: '全程仅第 2 株付费');
    });

    t.test('不同物种可各种一株', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(40);
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.svc.plant('species_tomato', 1, now);
      await ctx.svc.plant('species_star_flower', 2, now);
      t.expect(await ctx.plants.plants(), t.hasLength(3));
    });

    t.test('死亡后同物种可再种：重种重新扣 10 碎片（一次兑换买一株，死亡全损不退款）',
        () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(40);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      // 置为死亡（全损：不退款）。
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.dead));

      final Plant p1 = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      t.expect(p1.id, t.isNot(p0.id));

      final List<SunlightEntry> spends = ctx.ledger.entriesOf('plant_plant');
      t.expect(spends, t.isEmpty, reason: '精英碎片物种不扣阳光');
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 20,
          reason: '死亡全损不退款，重种重新扣 10 碎片（40→30→20）');
      t.expect(await ctx.plants.plants(), t.hasLength(1),
          reason: '同花盆死亡残留已清理，仅剩新株');
    });

    t.test('枯萎中（wilting）仍算存活 → 再种第 2 株按付费口径（C29）', () async {
      final _Ctx ctx = _make();
      final Plant p0 = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.wilting));
      // 枯萎不算「无存活」→ 第 2 株收费 300。
      final Plant p2 = await ctx.svc.plant(kStarterSpeciesId, 1, now);
      t.expect(p2.shovelRefund, kShovelRefundCommon);
      t.expect(ctx.ledger.entriesOf('plant_plant'), t.hasLength(1));
    });
  });

  // ── ⑪ 铲除返还（C29）────────────────────────────────────────────────────
  t.group('⑪ 铲除返还（C29）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('阳光付费种下的普通株 → 铲除返还 150（档位价 300×50%）', () async {
      final _Ctx ctx = _make();
      final Plant p = await ctx.svc.plant('species_tomato', 0, now); // -300
      t.expect(p.shovelRefund, kShovelRefundCommon);
      final double before = await ctx.ledger.balance();
      final int refund = await ctx.svc.shovel(p.id, now);
      t.expect(refund, 150);
      t.expect(await ctx.ledger.balance(), before + 150);
      // 账本入账：refType 冻结值 + refId = 物种 id。
      final List<SunlightEntry> earns =
          ctx.ledger.entriesOf(kPlantShovelRefundRefType);
      t.expect(earns, t.hasLength(1));
      t.expect(earns.single.gross, 150);
      t.expect(earns.single.refId, 'species_tomato');
      t.expect(await ctx.plants.plants(), t.isEmpty, reason: '铲除后植株消失');
    });

    t.test('碎片种下的精英株 → 铲除返还 250（精英 500×50%，统一口径）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      final Plant p = await ctx.svc.plant('species_moon_orchid', 0, now);
      t.expect(p.shovelRefund, kShovelRefundPremium);
      final int refund = await ctx.svc.shovel(p.id, now);
      t.expect(refund, 250, reason: '精英按阳光等价价 500×50%，与支付通道无关');
      t.expect(await ctx.bloomRewards.premiumFragmentBalance(), 10,
          reason: '碎片不返还（只返阳光）');
    });

    t.test('券种株 → 铲除按档位 50% 返还（玄参「统一」口径；2026-10-07 显式种子支付）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.unlockSpecies('species_star_flower');
      final Plant p = await ctx.svc
          .plant('species_star_flower', 0, now, payWith: PlantCostKind.seed);
      t.expect(p.shovelRefund, kShovelRefundPremium, reason: '精英券种株同样 250');
      t.expect(await ctx.svc.shovel(p.id, now), 250);
    });

    t.test('向日葵免费首株 → 铲除返还 0（防「免费种→铲→循环刷阳光」）', () async {
      final _Ctx ctx = _make();
      final Plant p = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      final double before = await ctx.ledger.balance();
      t.expect(await ctx.svc.shovel(p.id, now), 0);
      t.expect(await ctx.ledger.balance(), before,
          reason: '返 0 不写账本行');
      t.expect(ctx.ledger.entriesOf(kPlantShovelRefundRefType), t.isEmpty);
    });

    t.test('死亡株 → 铲除返还 0（死亡全损口径延续）', () async {
      final _Ctx ctx = _make();
      final Plant p0 = await ctx.svc.plant('species_tomato', 0, now); // -300
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.dead));
      final double before = await ctx.ledger.balance();
      t.expect(await ctx.svc.shovel(p0.id, now), 0,
          reason: '死亡全损：即使付费种下也返还 0');
      t.expect(await ctx.ledger.balance(), before);
    });

    t.test('培养消耗（浇水/施肥）不参与铲除返还', () async {
      final _Ctx ctx = _make();
      final Plant p = await ctx.svc.plant('species_tomato', 0, now);
      await ctx.svc.water(p.id, now); // -5（培养消耗）
      final double before = await ctx.ledger.balance();
      t.expect(await ctx.svc.shovel(p.id, now), 150,
          reason: '只返种植价 50%，浇水消耗不返');
      t.expect(await ctx.ledger.balance(), before + 150);
    });
  });

  // ── ⑫ 一键操作计划（C29）────────────────────────────────────────────────
  t.group('⑫ 一键操作计划（C29）', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    t.test('一键浇水计划：跳过枯萎态外死亡株 / 今日已浇满株，合计 = N×5', () async {
      final _Ctx ctx = _make();
      final Plant a = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      final Plant b = await ctx.svc.plant(kStarterSpeciesId, 1, now); // -300
      final Plant c = await ctx.svc.plant('species_tomato', 2, now); // -300
      // b 今日浇满 3 次 → 跳过；c 置死亡 → 跳过。
      for (int i = 0; i < kPlantWaterMaxPerDay; i++) {
        await ctx.svc.water(b.id, now.add(Duration(minutes: 31 * i)));
      }
      await ctx.plants.savePlant(_withStatus(c, PlantStatus.dead));

      final OneClickPlan plan =
          await ctx.svc.oneClickPlan(PlantOneClickKind.water, now);
      t.expect(plan.plantIds, <String>[a.id],
          reason: '仅剩 a 可浇（b 今日已浇满 3 次达上限、c 死亡跳过）');
      t.expect(plan.totalCost, kPlantWaterCost);
    });

    t.test('一键浇水计划为空 → isEmpty（UI 提示「今天没有可浇水的植物」）', () async {
      final _Ctx ctx = _make();
      final Plant a = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      for (int i = 0; i < kPlantWaterMaxPerDay; i++) {
        await ctx.svc.water(a.id, now.add(Duration(minutes: 31 * i)));
      }
      final OneClickPlan plan =
          await ctx.svc.oneClickPlan(PlantOneClickKind.water, now);
      t.expect(plan.isEmpty, t.isTrue);
    });

    t.test('一键施肥计划：合计 = N×10（每株每日 1 次）', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      await ctx.svc.plant(kStarterSpeciesId, 1, now);
      final OneClickPlan plan =
          await ctx.svc.oneClickPlan(PlantOneClickKind.fertilize, now);
      t.expect(plan.plantIds, t.hasLength(2));
      t.expect(plan.totalCost, 2 * kPlantFertilizeCost);
      // 施 1 株后其跳出计划。
      await ctx.svc.fertilize(plan.plantIds.first, now);
      final OneClickPlan after =
          await ctx.svc.oneClickPlan(PlantOneClickKind.fertilize, now);
      t.expect(after.plantIds, t.hasLength(1));
    });

    t.test('一键护理计划：草 + 虫各一条（同株可双目标），死亡株不算', () async {
      final _Ctx ctx = _make();
      final Plant a = await ctx.svc.plant(kStarterSpeciesId, 0, now);
      final Plant b = await ctx.svc.plant(kStarterSpeciesId, 1, now);
      await ctx.plants.savePlant(a.copyWith(
        weedAt: DateTime(now.year, now.month, now.day),
        pestAt: DateTime(now.year, now.month, now.day),
      ));
      await ctx.plants.savePlant(b.copyWith(
        weedAt: DateTime(now.year, now.month, now.day),
      ));
      final Plant c = await ctx.svc.plant('species_tomato', 2, now);
      await ctx.plants.savePlant(_withStatus(c, PlantStatus.dead));

      final OneClickPlan plan =
          await ctx.svc.oneClickPlan(PlantOneClickKind.care, now);
      t.expect(plan.careTargets, t.hasLength(3),
          reason: 'a 有草+虫 → 2 条；b 只有草 → 1 条；c 死亡跳过');
      t.expect(plan.totalCost, 0, reason: '护理不扣费，奖励照常发放');
      t.expect(plan.actionCount, 3);
      // 真执行：奖励逐株入账（weed +1 / pest +2）。
      for (final ({String plantId, bool weed}) t2 in plan.careTargets) {
        t2.weed
            ? await ctx.svc.clearWeed(t2.plantId, now)
            : await ctx.svc.clearPest(t2.plantId, now);
      }
      t.expect(ctx.ledger.entriesOf('plant_weed'), t.hasLength(2));
      t.expect(ctx.ledger.entriesOf('plant_pest'), t.hasLength(1));
    });

    t.test('铲除返还常量自洽：普通 150 = 300×50%、精英 250 = 500×50%', () {
      t.expect(kShovelRefundCommon, kSpeciesSunlightCostCommon * 0.5);
      t.expect(kShovelRefundPremium, kSpeciesSunlightValuePremium * 0.5);
    });
  });

  // ── ⑨ 花园页「选择要种的植物」弹窗：稀有度两档 + 价格文案 ───────────────────
  t.group('⑨ 花园页选种弹窗（稀有度两档 + 价格文案）', () {
    testWidgets('点空花盆 → 弹窗展示稀有度两档（普通 / 精英）+ 价格按钮（免费 / 300 阳光 / 6 植物碎片 / 10 植物碎片）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
          plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ));

      // 等空花盆建好（木牌是无限呼吸动画 → 只能有界 pump）。
      final bool ready = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      t.expect(ready, t.isTrue);

      await tester.tap(find.byType(EmptyPot).first);
      // _openPlantSheet 现为异步预取计价（依赖账本）→ 有界 pump 直到弹窗标题出现。
      final bool sheetShown = await _pumpUntil(
        tester,
        () => find.text('选择要种的植物').evaluate().isNotEmpty,
      );
      t.expect(sheetShown, t.isTrue, reason: '异步预取后应弹出「选择要种的植物」弹窗');
      // 弹窗入场动画（有限时长）走完。
      await tester.pump(const Duration(milliseconds: 400));

      // 稀有度两档（普通 / 精英）+ 价格文案（每物种一张卡片，标签出现多次）。
      t.expect(find.text('普通'), findsWidgets,
          reason: '普通档（番茄 / 草莓）卡片显示「普通」标签');
      t.expect(find.text('精英'), findsWidgets,
          reason: '精英档（月光兰等 5 种）卡片显示「精英」标签');
      t.expect(find.text('免费'), findsOneWidget, reason: '向日葵 = 免费');
      // 2026-10-05 玄参美化口径：价格=「素材图标 + 数字」，不再写「N 阳光」文字。
      t.expect(find.text('300'), findsWidgets,
          reason: '普通档二选一：阳光 300（C29 修订 400→300）');
      t.expect(find.text('6'), findsWidgets,
          reason: '普通档二选一：碎片 6');
      t.expect(find.text('10'), findsWidgets, reason: '精英档：碎片 10');
      // 稀有度只显示两档：不应再出现旧的「优良 / 稀有」。
      t.expect(find.textContaining('优良'), findsNothing);
      t.expect(find.textContaining('稀有'), findsNothing);
    });
  });

  // ── ⑩ 选种弹窗种子券入口（玄参 2026-09-29）：徽章 + 「用种子种（免费）」按钮 ──
  t.group('⑩ 选种弹窗种子券入口（徽章 + 免费按钮置顶）', () {
    testWidgets('持有番茄券 → 番茄卡片显示「🌰 种子」徽章 + 「用种子种（免费）」按钮',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_tomato'); // 预发一张番茄免费种植券

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
          plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
          bloomRewardRepositoryProvider.overrideWithValue(bloom),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ));

      final bool ready = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      t.expect(ready, t.isTrue);

      await tester.tap(find.byType(EmptyPot).first);
      final bool sheetShown = await _pumpUntil(
        tester,
        () => find.text('选择要种的植物').evaluate().isNotEmpty,
      );
      t.expect(sheetShown, t.isTrue);
      await tester.pump(const Duration(milliseconds: 400));

      // 种子徽章：仅番茄卡片有（其余 7 种无券）。2026-10-05 三修为**纯种子图标**
      // （玄参「掉落了种子，也需要显示一个种子图标」；去掉了「种子」文字）。
      // 2026-10-07 新口径：种子 = 第三支付方式且按档位判券 → **每个普通档物种卡**
      // 都有「种子」按钮（内芯各 1 张普通种子图）+ 番茄卡徽章 1 + 计数 chip 1 → ≥4 处。
      t.expect(
        find.byWidgetPredicate((Widget w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/rewards/seed_common.png'),
        findsWidgets,
        reason: '番茄卡徽章 + 各普通卡种子按钮内芯 + 花园普通种子计数 chip',
      );
      // 支付按钮（2026-10-07 新口径）：向日葵「免费」一 + 各普通物种「种子」按钮。
      t.expect(find.text('免费'), findsOneWidget, reason: '向日葵 = 免费');
      t.expect(find.text('种子'), findsWidgets,
          reason: '各普通物种卡均有种子按钮（第三支付方式，文案精简）');
      // 付费按钮保留在后（阳光 / 碎片）。
      t.expect(find.text('300'), findsWidgets, reason: '阳光价=图标+数字');
      t.expect(find.text('6'), findsWidgets, reason: '碎片价=图标+数字');
    });
  });

  // ── ⑪ 种植二次确认（玄参 2026-10-05「点阳光 / 植物碎片 / 种子都需二次确认，
  //    防止误操作」）：选种弹窗点支付按钮 → 确认卡 → 确认才种植 / 取消分毫不扣 ──
  t.group('⑪ 种植二次确认弹窗（确认才种植 / 取消分毫不扣）', () {
    Future<({_SpyPlantRepo spy, bool ready})> _openSheetWithCoupon(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _SpyPlantRepo spy = _SpyPlantRepo();
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_tomato'); // 预发一张番茄免费种植券

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
          plantRepositoryProvider.overrideWithValue(spy),
          bloomRewardRepositoryProvider.overrideWithValue(bloom),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ));

      final bool ready = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      t.expect(ready, t.isTrue);
      await tester.tap(find.byType(EmptyPot).first);
      final bool sheetShown = await _pumpUntil(
        tester,
        () => find.text('选择要种的植物').evaluate().isNotEmpty,
      );
      t.expect(sheetShown, t.isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      return (spy: spy, ready: ready);
    }

    testWidgets('点「种子」→ 弹二次确认卡；点「取消」→ 不种植', (WidgetTester tester) async {
      await _openSheetWithCoupon(tester);

      await tester.tap(find.text('种子').first);
      final bool confirmShown = await _pumpUntil(
        tester,
        () => find.text('要种下番茄吗？').evaluate().isNotEmpty,
      );
      t.expect(confirmShown, t.isTrue, reason: '支付按钮点击后必须弹二次确认卡');
      t.expect(find.textContaining('普通种子'), findsOneWidget,
          reason: '确认卡明示本次消耗（2026-10-07 精简文案：不再点明物种名）');

      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));
      t.expect(find.text('要种下番茄吗？'), findsNothing,
          reason: '取消后确认卡关闭');
      t.expect(find.byType(EmptyPot), findsWidgets,
          reason: '取消 → 分毫不扣、种子券不消耗，花盆仍为空');
    });

    testWidgets('确认卡点「确定种植」→ 才真正调 plant() 落库', (WidgetTester tester) async {
      final ({_SpyPlantRepo spy, bool ready}) ctx =
          await _openSheetWithCoupon(tester);

      await tester.tap(find.text('种子').first);
      final bool confirmShown = await _pumpUntil(
        tester,
        () => find.text('要种下番茄吗？').evaluate().isNotEmpty,
      );
      t.expect(confirmShown, t.isTrue);
      t.expect(ctx.spy.saved, t.isEmpty, reason: '确认前绝不落库');

      await tester.tap(find.text('确定种植'));
      final bool planted = await _pumpUntil(
        tester,
        () => ctx.spy.saved.isNotEmpty,
      );
      t.expect(planted, t.isTrue, reason: '确认后才真正种植');
      t.expect(ctx.spy.saved.single.speciesId, 'species_tomato');
    });
  });
}

// ── 弹窗用例的假仓储（返回真实 8 物种种子表）─────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepo implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _FakeFocusRepo implements FocusRepository {
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

class _FakePlantRepo implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

/// 记录 `savePlant` 调用的 Spy（⑪ 二次确认用例：断言「确认后才真正种植」）。
class _SpyPlantRepo extends _FakePlantRepo {
  final List<Plant> saved = <Plant>[];
  @override
  Future<void> savePlant(Plant plant) async => saved.add(plant);
}

/// 有界帧推进（木牌无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
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
