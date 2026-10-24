/// C80 · **T01 门控与数据层**：provider 红线反转 + 域层防线（TC-V3-02..06）。
///
/// 权威设计 = `docs/称号属性_v1_系统设计.md` §0.3-V3-1：
///  · `currentPlantPerkProvider` 改读 [entitlementProvider]：free 短路回
///    [PlantPerk.none]（不查库），premium → `perkOfLevel` 累积（TC-V3-02/03）；
///  · **P1-1 购买即时生效 = 零回调**：provider watch [entitlementProvider]，
///    置 premium 后自动重算（TC-V3-04）；
///  · bounded 2s 回退语义保留：异常 → none（free 与 premium 同路径，TC-V3-05）；
///  · **域层防线**：`PlantGrowthService.currentPerk()` 以注入的
///    `EntitlementService.can(FeatureKey.titlePerks)` 门控——free 假件 → 浇水扣 5
///    （基础值），premium 假件 → 扣 4（C78 减免），`_entitlement == null` 保
///    C77 旧行为（TC-V3-06）。
library plant_perk_gating_test;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
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
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

// ── 内存假件（与 plant_perk_economy_test 同款夹具，独立成套防耦合）──────────

class _FocusRepo implements FocusRepository {
  _FocusRepo(this.minutes, {this.throwOnRead = false});
  double minutes;
  final bool throwOnRead;
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async {
    if (throwOnRead) {
      throw StateError('boom');
    }
    return FocusStats(
      totalFocusMinutes: minutes,
      totalSessions: 0,
      totalValidDays: 0,
    );
  }
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
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
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

/// 档位固定的 [EntitlementService] 假件（TC-V3-06 域防线注入用）。
///
/// 判定委托矩阵单点 [featureAllowedFor]，与生产 `MatrixEntitlementService` 同源无孪生。
class _FixedTierEntitlementService implements EntitlementService {
  _FixedTierEntitlementService(this.tier);
  final EntitlementTier tier;
  @override
  Future<Entitlement> load() async =>
      tier == EntitlementTier.premium ? Entitlement.lifetime() : Entitlement.free;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> purchaseLifetime() async {}
  @override
  Future<RestoreResult> restore() async => RestoreResult.nothingToRestore;
  @override
  bool can(FeatureKey f) => featureAllowedFor(f, tier);
  @override
  int quotaOf(FeatureKey f) => featureQuotaFor(f, tier);
}

Plant _plant0() => Plant(
      id: 'p1',
      speciesId: 'sp_common',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 10, 16, 7),
      growthProgress: 0.2,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 10, 16, 7),
      shovelRefund: 150,
    );

double _minutesOfLevel(int level) =>
    level <= 0 ? 0.0 : kFocusLevelThresholdMinutes[level - 1].toDouble();

/// 组装域服务（[entitlement] 传 null = C77 旧行为路径）。
PlantGrowthService _service({
  required _FocusRepo focus,
  required _Ledger ledger,
  EntitlementService? entitlement,
}) =>
    PlantGrowthService(
      plants: _PlantRepo(<Plant>[_plant0()]),
      focus: focus,
      ledger: ledger,
      settings: _SettingsRepo(),
      bloomRewards: InMemoryBloomRewardRepository(),
      entitlement: entitlement,
    );

void main() {
  // ── TC-V3-02 provider free：老号（level ≥ 1）也恒 none ─────────────────────
  group('C80 · provider 门控（free）', () {
    test('TC-V3-02：level≥1 的老号（totalFocusMinutes 足量）→ 仍 PlantPerk.none',
        () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider
              .overrideWithValue(_FocusRepo(_minutesOfLevel(40))),
          // entitlementProvider 默认 free，无需 override。
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(currentPlantPerkProvider.future), PlantPerk.none,
          reason: 'free 短路：不查库直接 none（9 条属性 premium 专享）');
    });
  });

  // ── TC-V3-03 provider premium：累积口径 ────────────────────────────────────
  group('C80 · provider 门控（premium）', () {
    Future<PlantPerk> perkPremiumAt(double minutes) async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider.overrideWithValue(_FocusRepo(minutes)),
          entitlementProvider
              .overrideWith((ref) => Entitlement.lifetime()),
        ],
      );
      addTearDown(c.dispose);
      return c.read(currentPlantPerkProvider.future);
    }

    test('TC-V3-03a：premium Lv.1 → 仅 eyeCareBonus=1（C78 前置）', () async {
      final PlantPerk perk =
          await perkPremiumAt(_minutesOfLevel(1));
      expect(perk, perkOfLevel(1));
      expect(perk.eyeCareBonus, 1);
      expect(perk.waterDiscount, 0, reason: '浇水节点 Lv.5，Lv.1 不应含');
    });

    test('TC-V3-03b：premium Lv.40 → 逐字段 = C78 映射累积（9 条全生效）', () async {
      final PlantPerk perk =
          await perkPremiumAt(_minutesOfLevel(40));
      expect(perk, perkOfLevel(40));
      expect(perk.eyeCareBonus, 1);
      expect(perk.waterDiscount, 1);
      expect(perk.fertilizeDiscount, 1);
      expect(perk.weedBonus, 1);
      expect(perk.pestBonus, 1);
      // C91（玄参 2026-10-19 拍板）：绽放 / 晨露两条 +1 → +2，其余七条不变。
      expect(perk.bloomInstantBonus, 2);
      expect(perk.dewBonus, 2);
      expect(perk.expandDiscount, 20);
      expect(perk.shovelRefundBonus, 20);
    });
  });

  // ── TC-V3-04 P1-1 购买即时生效（零回调）────────────────────────────────────
  test('TC-V3-04：先 free 读 none → 置 entitlement=lifetime → 自动重算（无 invalidate）',
      () async {
    final _FocusRepo focus = _FocusRepo(_minutesOfLevel(40));
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        focusRepositoryProvider.overrideWithValue(focus),
      ],
    );
    addTearDown(c.dispose);

    expect(await c.read(currentPlantPerkProvider.future), PlantPerk.none,
        reason: '初始 free → none');

    // 模拟购买成功（parent_premium_page 写 StateProvider）。
    c.read(entitlementProvider.notifier).state = Entitlement.lifetime();

    final PlantPerk perk = await c.read(currentPlantPerkProvider.future);
    expect(perk, perkOfLevel(40),
        reason: 'P1-1：watch(entitlementProvider) 驱动重算，无需手动 invalidate');
  });

  // ── TC-V3-05 bounded 回退：异常 → none（free 与 premium 同路径）────────────
  test('TC-V3-05：totalStats() 抛异常 → none（free 与 premium 同路径）', () async {
    for (final bool premium in <bool>[false, true]) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          focusRepositoryProvider
              .overrideWithValue(_FocusRepo(0, throwOnRead: true)),
          if (premium)
            entitlementProvider.overrideWith((ref) => Entitlement.lifetime()),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(currentPlantPerkProvider.future), PlantPerk.none,
          reason: '异常回退 none ≡ 免费语义（kPlantPerkProviderTimeout 同兜底路径）');
    }
  });

  // ── TC-V3-06 域层防线：currentPerk() / water() ─────────────────────────────
  group('C80 · 域层防线（PlantGrowthService.currentPerk）', () {
    test('注入 free 档假件 → 缺省 perk 浇水扣 5（基础值，防线生效）', () async {
      final _Ledger ledger = _Ledger();
      final PlantGrowthService service = _service(
        focus: _FocusRepo(_minutesOfLevel(40)),
        ledger: ledger,
        entitlement: _FixedTierEntitlementService(EntitlementTier.free),
      );
      await service.water('p1', DateTime(2026, 10, 16, 9));
      expect(
        ledger.entries
            .where((SunlightEntry e) => e.refType == 'plant_water')
            .fold<double>(0, (double s, SunlightEntry e) => s + e.net),
        -kPlantWaterCost,
        reason: 'free 域防线：5 − 0 = 5（即便累计专注已达 Lv.40）',
      );
    });

    test('注入 premium 档假件 → 缺省 perk 浇水扣 4（C78 减免生效）', () async {
      final _Ledger ledger = _Ledger();
      final PlantGrowthService service = _service(
        focus: _FocusRepo(_minutesOfLevel(40)),
        ledger: ledger,
        entitlement: _FixedTierEntitlementService(EntitlementTier.premium),
      );
      await service.water('p1', DateTime(2026, 10, 16, 9));
      expect(
        ledger.entries
            .where((SunlightEntry e) => e.refType == 'plant_water')
            .fold<double>(0, (double s, SunlightEntry e) => s + e.net),
        -(kPlantWaterCost - kPerkWaterDiscount),
        reason: 'premium：5 − 1 = 4',
      );
    });

    test('currentPerk() 直调：free → none / premium → perkOfLevel（防线双向）', () async {
      final _FocusRepo focus = _FocusRepo(_minutesOfLevel(5));
      final _Ledger ledger = _Ledger();
      expect(
        await _service(
                focus: focus,
                ledger: ledger,
                entitlement: _FixedTierEntitlementService(EntitlementTier.free))
            .currentPerk(),
        PlantPerk.none,
      );
      expect(
        await _service(
                focus: focus,
                ledger: ledger,
                entitlement:
                    _FixedTierEntitlementService(EntitlementTier.premium))
            .currentPerk(),
        perkOfLevel(5),
      );
    });

    test('_entitlement == null → C77 旧行为（不门控，保既有域单测逐字节不变）', () async {
      final _FocusRepo focus = _FocusRepo(_minutesOfLevel(5));
      final _Ledger ledger = _Ledger();
      expect(
        await _service(focus: focus, ledger: ledger).currentPerk(),
        perkOfLevel(5),
        reason: 'null 缺省 = 旧行为（与 expandPot 防线同款缺省语义）',
      );
    });
  });
}
