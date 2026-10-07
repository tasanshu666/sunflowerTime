/// 死亡全损 + 按物种档位计价 单测（玄参 2026-09-28 计价模型：月光兰改精英 → 仅碎片）。
///
/// 覆盖（逐条对应派工规格）：
///  ① 月光兰（精英）扣 10 碎片（不扣阳光，账本无 `plant_plant`）；
///  ② **死亡全损**：枯萎→死亡不退阳光 / 碎片、无 `plant_death_refund` 行、余额不变；
///  ③ 死亡后再种 → **重扣 10 碎片**（`plant_plant` 无阳光记录，一次兑换买一株）；
///  ④ 免费券优先：有券不扣（阳光 / 碎片均不扣）、券被消耗；死亡后再种按档位碎片价；
///  ⑤ 向日葵仍免费（初始物种，恒不扣）；
///  ⑥ 番茄 / 草莓仍 6 碎片（无券、无首购逻辑）。
///
/// 另附 ⓪ `plantCost` 计价矩阵：月光兰（精英）恒为碎片 10，不存在「首购优惠」切换。
library plant_death_and_firstbuy_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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

/// 账本 Fake：固定初始余额，记录全部 append 条目；实现真实 `lastTsByRefTypeAndRefId`。
class _MemLedger implements SunlightRepository {
  double initialBalance = 1000000;
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
      0;
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

_Ctx _make() {
  final _MemPlantRepo plants = _MemPlantRepo();
  final _MemLedger ledger = _MemLedger();
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

Plant _withStatus(Plant p, PlantStatus status) => p.copyWith(status: status);

void main() {
  final DateTime now = DateTime(2026, 9, 27, 8);

  // ── ⓪ plantCost 计价矩阵 ───────────────────────────────────────────────
  group('⓪ plantCost 计价（按物种档位，无首购切换）', () {
    test('月光兰（精英）：plantCost 恒为碎片 10', () async {
      final _Ctx ctx = _make();
      final PlantCost c =
          await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low);
      expect(c.kind, PlantCostKind.fragments);
      expect(c.amount, kSpeciesFragmentCostPremium);
      // 即使已经种过（曾扣过碎片），价格仍为碎片，不存在「首购优惠」概念。
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_moon_orchid', 0, now);
      final PlantCost after =
          await ctx.svc.plantCost(_sp('species_moon_orchid'), AgeTier.low);
      expect(after.kind, PlantCostKind.fragments);
      expect(after.amount, kSpeciesFragmentCostPremium);
    });

    test('普通（番茄）/ 精英 / 向日葵：plantCost 恒按其档位默认项', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(50);
      // 普通档默认取阳光（plantCost 返回 plantPaymentOptions 的首项）。
      expect((await ctx.svc.plantCost(_sp('species_tomato'), AgeTier.low)).kind,
          PlantCostKind.sunlight,
          reason: '普通默认取阳光');
      expect((await ctx.svc.plantCost(_sp('species_tomato'), AgeTier.low)).amount,
          kSpeciesSunlightCostCommon);
      expect((await ctx.svc.plantCost(_sp(kStarterSpeciesId), AgeTier.low)).kind,
          PlantCostKind.free);
      // 即使已经种过番茄（碎片支付），价格仍为阳光默认项（无首购概念，计价恒定）。
      await ctx.svc.plant('species_tomato', 0, now,
          payWith: PlantCostKind.fragments);
      expect((await ctx.svc.plantCost(_sp('species_tomato'), AgeTier.low)).amount,
          kSpeciesSunlightCostCommon);
    });
  });

  // ── ① 月光兰（精英）扣碎片 ──────────────────────────────────────────────
  group('① 月光兰（精英）扣 10 碎片', () {
    test('碎片余额 -10、账本无 plant_plant；阳光余额不变', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_moon_orchid', 0, now);

      expect(await ctx.bloomRewards.premiumFragmentBalance(), 10);
      expect(ctx.ledger.entriesOf('plant_plant'), isEmpty,
          reason: '精英碎片物种不扣阳光');
      expect(await ctx.ledger.balance(), 1000000);
    });
  });

  // ── ② 死亡全损 ──────────────────────────────────────────────────────────
  group('② 死亡全损（不退任何资源）', () {
    test('月光兰（精英）：枯萎→死亡 → 无 plant_death_refund 行、碎片余额不变', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      final Plant p = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      final int fragBefore = await ctx.bloomRewards.premiumFragmentBalance();
      expect(fragBefore, 10);

      // 构造「已枯萎满死亡阈值」→ tickAll 触发死亡（此前口径会退 120）。
      final Plant wilting = p.copyWith(
        status: PlantStatus.wilting,
        wiltedAt: now.subtract(const Duration(days: kPlantDeathDays)),
      );
      await ctx.plants.savePlant(wilting);

      await ctx.svc.tickAll(now);
      final Plant after = (await ctx.plants.plant(p.id))!;
      expect(after.status, PlantStatus.dead);
      expect(after.deadAt, isNotNull);

      expect(ctx.ledger.entriesOf('plant_death_refund'), isEmpty,
          reason: '死亡全损 → 不产生退款行');
      expect(await ctx.bloomRewards.premiumFragmentBalance(), fragBefore,
          reason: '碎片余额不退');
    });

    test('碎片物种：死亡不退碎片（碎片余额不变、无退款行）', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      final Plant p = await ctx.svc.plant('species_tomato', 0, now,
          payWith: PlantCostKind.fragments); // -6 碎片
      final int fragBefore = await ctx.bloomRewards.premiumFragmentBalance();
      expect(fragBefore, 14);

      final Plant wilting = p.copyWith(
        status: PlantStatus.wilting,
        wiltedAt: now.subtract(const Duration(days: kPlantDeathDays)),
      );
      await ctx.plants.savePlant(wilting);
      await ctx.svc.tickAll(now);

      expect((await ctx.plants.plant(p.id))!.status, PlantStatus.dead);
      expect(ctx.ledger.entriesOf('plant_death_refund'), isEmpty);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), fragBefore,
          reason: '死亡全损 → 碎片不退');
    });
  });

  // ── ③ 死亡后再种重扣 ────────────────────────────────────────────────────
  group('③ 死亡后再种（一次兑换买一株，死亡全损不退款）', () {
    test('月光兰死亡后再种 → 重扣 10 碎片，plant_plant 无阳光记录', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(40);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.dead));

      await ctx.svc.plant('species_moon_orchid', 0, now); // 重种 → -10

      expect(ctx.ledger.entriesOf('plant_plant'), isEmpty,
          reason: '精英碎片物种不扣阳光');
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 20,
          reason: '死亡全损不退款，重种重新扣 10 碎片（40→30→20）');
    });
  });

  // ── ④ 种子券（2026-10-07 新口径：显式种子支付，不再自动优先耗券）───────
  group('④ 种子券（显式支付，2026-10-07）', () {
    test('点种子支付 → 不扣阳光 / 碎片、券消失；死亡后再种按档位碎片价', () async {
      final _Ctx ctx = _make();
      await ctx.bloomRewards.setPremiumFragmentBalance(0);
      await ctx.bloomRewards.unlockSpecies('species_moon_orchid'); // 发精英券

      final Plant p0 = await ctx.svc
          .plant('species_moon_orchid', 0, now, payWith: PlantCostKind.seed);
      expect(ctx.ledger.entriesOf('plant_plant'), isEmpty, reason: '种子支付不扣阳光');
      expect(await ctx.ledger.balance(), 1000000, reason: '种子支付不扣阳光');
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0, reason: '种子支付不扣碎片');
      expect(await ctx.bloomRewards.unlockedSpeciesIds(), isEmpty, reason: '券被消耗');

      // 死亡后再种 → 按档位碎片价（精英 10 碎片，无首购优惠概念）。
      await ctx.bloomRewards.setPremiumFragmentBalance(20);
      await ctx.plants.savePlant(_withStatus(p0, PlantStatus.dead));
      await ctx.svc.plant('species_moon_orchid', 0, now);

      expect(await ctx.bloomRewards.premiumFragmentBalance(), 10,
          reason: '重种按精英碎片价 10');
      expect(ctx.ledger.entriesOf('plant_plant'), isEmpty, reason: '精英不扣阳光');
    });
  });

  // ── ⑤ 向日葵仍免费 ──────────────────────────────────────────────────────
  group('⑤ 向日葵仍免费', () {
    test('不扣阳光、不扣碎片、不写账本', () async {
      final _Ctx ctx = _make();
      await ctx.svc.plant(kStarterSpeciesId, 0, now);
      expect(ctx.ledger.entriesOf('plant_plant'), isEmpty);
      expect(await ctx.ledger.balance(), 1000000);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
    });
  });

  // ── ⑥ 番茄 / 草莓仍 6 碎片 ──────────────────────────────────────────────
  group('⑥ 番茄 / 草莓仍 6 碎片（无券无首购逻辑）', () {
    test('扣 6 碎片、不扣阳光', () async {
      for (final String id in <String>['species_tomato', 'species_strawberry']) {
        final _Ctx ctx = _make();
        await ctx.bloomRewards.setPremiumFragmentBalance(20);
        await ctx.svc.plant(id, 0, now, payWith: PlantCostKind.fragments);
        expect(ctx.ledger.entriesOf('plant_plant'), isEmpty,
            reason: '$id 不扣阳光');
        expect(await ctx.bloomRewards.premiumFragmentBalance(), 14,
            reason: '$id 扣 6 碎片');
      }
    });
  });
}
