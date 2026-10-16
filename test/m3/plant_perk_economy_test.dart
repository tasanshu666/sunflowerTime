/// C77 · **T04 装配与集成**：`currentPlantPerkProvider` 端到端 + **TC-40 经济上限回归**。
///
/// 两件事：
///  ① **装配端到端**（设计 §5.0 / §3.4）：`currentPlantPerkProvider` =
///     `perkOfLevel(levelOfMinutes(totalFocusMinutes))`，随 [economyRevisionProvider] 重算；
///     且经 provider 装配的 [PlantGrowthService] 走**内部 `currentPerk()`** 自算时，
///     扣费与 provider 同源（水 −4 / 施 −9，Lv.40）；
///  ② **TC-40 经济上限回归**（PRD §1.4 标尺），全部**由既有常量推导**、不写第二份魔数：
///     · 消耗减免 12 盆最坏 = `kGardenPotCapacityMax × (kPlantWaterMaxPerDay×减免 + kPlantFertilizeMaxPerDay×减免)` = **48 ☀/天**；
///     · 一次性扩容最坏 = `(kGardenPotCapacityMax − kGardenPotCapacityDefault) × kPerkExpandDiscount` = **160 ☀**；
///     · 护眼日上限 = `kDailyFocusCapLow ÷ kEyeCareIntervalMinDefault` = 3（⑦ 单次 +1）；
///     · 微收入 12 盆最坏 ≈ **33.8 ☀/天**（PRD §1.4 (b)）⇒ 最坏总影响 ≈ 48 + 33.8 = **≈82 ☀/天**。
///
/// ⚠️ 「护眼 3 次/天」是**低龄日专注上限 60 分钟 ÷ 20 分钟一次**的硬推导（K（a））；
/// weed / pest 上限 = 每盆每日 1 次 × 12 盆；bloom / dew 为**频率上限**（随花期模型），
/// 以 PRD §1.4 标尺钉住，并断言「单次一律 ±1」的增量约束。
library plant_perk_economy_test;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
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
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

// ── 内存 Fake 仓储（端到端装配用）────────────────────────────────────────────

class _FocusRepo implements FocusRepository {
  _FocusRepo(this.minutes);
  double minutes;
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => FocusStats(
        totalFocusMinutes: minutes,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _Ledger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);
  @override
  Future<double> balance() async => 1000000.0;
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
  Future<int> countByRefTypeAndRefIdOnDay(String r, String id, String k) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(String r, String id, DateTime s) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

class _PlantRepo implements PlantRepository {
  _PlantRepo(this._plants);
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
        PlantSpecies(
          id: 'sp_common',
          name: '普通草',
          rarity: Rarity.common,
          baseCostHigh: 0,
          baseCostLow: 0,
          growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
        ),
      ];
}

/// 内存假权益仓储（端到端装配用：注入买断票据，使域层 `currentPerk()` 走 premium）。
class _EntitlementRepo implements EntitlementRepository {
  _EntitlementRepo(this._stored);
  Entitlement _stored;
  @override
  Future<Entitlement> read() async => _stored;
  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;
  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

class _SettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

Plant _plant0({DateTime? lastWaterAt}) => Plant(
      id: 'p1',
      speciesId: 'sp_common',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 10, 15, 7),
      growthProgress: 0.2,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 10, 15, 7),
      lastWaterAt: lastWaterAt,
      shovelRefund: 150,
    );

double _minutesOfLevel(int level) =>
    level <= 0 ? 0.0 : kFocusLevelThresholdMinutes[level - 1].toDouble();

void main() {
  // ── ① 装配端到端：provider 与域层同源 ──────────────────────────────────────
  group('T04 · currentPlantPerkProvider 装配（端到端）', () {
    // 🔴 C80 门控反转：provider 读写继承自 entitlementProvider —— free 档短路回
    // [PlantPerk.none]，**premium 档**才按等级累积取属性。本组验证的是「装配与
    // 域层同源」，故统一注入买断档（`Entitlement.lifetime()`）走 premium 分支。
    Future<PlantPerk> perkAt(double minutes) async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider.overrideWithValue(_FocusRepo(minutes)),
          entitlementProvider
              .overrideWith((Ref ref) => Entitlement.lifetime()),
        ],
      );
      addTearDown(c.dispose);
      return c.read(currentPlantPerkProvider.future);
    }

    test('provider == perkOfLevel(levelOfMinutes(minutes))（含 0 / 中段 / 满级）', () async {
      expect(await perkAt(0), perkOfLevel(0),
          reason: '未解锁（<60 分钟）→ none');
      expect(await perkAt(_minutesOfLevel(7)), perkOfLevel(7),
          reason: 'Lv.7 → 累积到 Lv.5 节点');
      expect(await perkAt(_minutesOfLevel(40)), perkOfLevel(40),
          reason: 'Lv.40 → 9 条全生效');
      expect(await perkAt(_minutesOfLevel(40)), perkOfLevel(40));
    });

    test('随 economyRevisionProvider 重算（跨页刷新总线）', () async {
      final _FocusRepo focus = _FocusRepo(_minutesOfLevel(5));
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider.overrideWithValue(focus),
          entitlementProvider
              .overrideWith((Ref ref) => Entitlement.lifetime()),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(currentPlantPerkProvider.future), perkOfLevel(5));

      // 升到 Lv.20 后 bump 修订号 → 重算拿到新属性。
      focus.minutes = _minutesOfLevel(20);
      c.read(economyRevisionProvider.notifier).state++;
      expect(await c.read(currentPlantPerkProvider.future), perkOfLevel(20));
    });

    test('provider 装配的 PlantGrowthService 走内部 currentPerk()（Lv.40 → 水 −4 / 施 −9）',
        () async {
      final _Ledger ledger = _Ledger();
      // C80：域层防线读**注入的** entitlementServiceProvider —— 预置买断票据并 load，
      // 使 `PlantGrowthService.currentPerk()` 走 premium（free 档会回 none → 浇水 5）。
      final MatrixEntitlementService gate = MatrixEntitlementService(
        repository: _EntitlementRepo(Entitlement.lifetime()),
      );
      await gate.load();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider
              .overrideWithValue(_FocusRepo(_minutesOfLevel(40))),
          plantRepositoryProvider.overrideWithValue(_PlantRepo(<Plant>[_plant0()])),
          sunlightRepositoryProvider.overrideWithValue(ledger),
          settingsRepositoryProvider.overrideWithValue(_SettingsRepo()),
          // C80：provider 侧读 entitlementProvider；域侧读 entitlementServiceProvider。
          entitlementProvider
              .overrideWith((Ref ref) => Entitlement.lifetime()),
          entitlementServiceProvider.overrideWithValue(gate),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
        ],
      );
      addTearDown(c.dispose);

      final DateTime now = DateTime(2026, 10, 15, 9);
      await c.read(plantGrowthServiceProvider).water('p1', now); // 缺省 perk → 自算
      expect(
        ledger.entries.where((SunlightEntry e) => e.refType == 'plant_water')
            .fold<double>(0, (double s, SunlightEntry e) => s + e.net),
        -4,
        reason: 'e2e：provider 装配的服务自算 currentPerk → Lv.40 浇水 4 ☀',
      );
    });
  });

  // ── ② TC-40 经济上限回归（PRD §1.4 标尺，全部由常量推导）────────────────────
  group('TC-40 经济上限回归（PRD §1.4 标尺）', () {
    test('消耗减免：12 盆满养护一日最坏 = 48 ☀/天（PRD §1.4 (a)）', () {
      // 单盆每日减免 = 浇水日上限×单次减免 + 施肥日上限×单次减免。
      const int perPotPerDay = kPlantWaterMaxPerDay * kPerkWaterDiscount +
          kPlantFertilizeMaxPerDay * kPerkFertilizeDiscount;
      expect(perPotPerDay, 4, reason: '3 次×1 + 1 次×1 = 4 ☀/盆/天');

      const int worst12 = kGardenPotCapacityMax * perPotPerDay;
      expect(worst12, 48,
          reason: '12 盆 × 4 = 48 ☀/天（减弱 sink，不注入阳光）');
    });

    test('一次性扩容：全生命周期最坏 = 160 ☀（4→12 = 8 次 × −20，PRD §1.4 (c)）', () {
      const int expansions = kGardenPotCapacityMax - kGardenPotCapacityDefault;
      expect(expansions, 8);
      expect(expansions * kPerkExpandDiscount, 160);
    });

    test('护眼日上限 = 3（低龄日专注 60 ÷ 20 分钟一次）；⑦ 单次 +1', () {
      expect(kDailyFocusCapLow ~/ kEyeCareIntervalMinDefault, 3);
      expect(perkOfLevel(30).eyeCareBonus, 1);
    });

    test('微收入 12 盆最坏 ≈ 33.8 ☀/天；单次一律 ±1（PRD §1.4 (b)）', () {
      // 事件类上限（12 盆）：
      final double weedCap = kGardenPotCapacityMax.toDouble(); // 12 盆 × 1/株/天
      final double pestCap = kGardenPotCapacityMax.toDouble(); // 12 盆 × 1/株/天
      final double eyeCap =
          (kDailyFocusCapLow ~/ kEyeCareIntervalMinDefault).toDouble(); // 3
      // 频率类上限（随花期 / 复开花模型，取 PRD §1.4 (b) 标尺）：
      const double bloomCap = 1.71; // 12 盆 ÷ 7 天/复开花
      const double dewCap = 5.1; // 12 盆 × 3 天花期 ÷ 7 天

      final double income = weedCap + pestCap + bloomCap + dewCap + eyeCap;
      expect(income, closeTo(33.8, 0.05), reason: 'PRD §1.4 (b) 12 盆最坏 ≈ 33.8');

      // 「单次一律 ±1」的增量约束（P1）：五条微收入单次加成**恒为 1**（不得调大）。
      final PlantPerk full = perkOfLevel(40);
      expect(full.weedBonus, 1);
      expect(full.pestBonus, 1);
      expect(full.bloomInstantBonus, 1);
      expect(full.dewBonus, 1);
      expect(full.eyeCareBonus, 1);
    });

    test('最坏总影响 ≈ 82 ☀/天（减免 48 + 收入 33.8，PRD §1.4 (d)）', () {
      const int reduction = kGardenPotCapacityMax *
          (kPlantWaterMaxPerDay * kPerkWaterDiscount +
              kPlantFertilizeMaxPerDay * kPerkFertilizeDiscount);
      const double income = 33.8;
      expect(reduction + income, closeTo(82, 0.5),
          reason: 'PRD §1.4 (d)：日频最坏 48 + 33.8 = 81.8 ≈ 82 ☀/天（标尺取整）');
    });
  });
}
