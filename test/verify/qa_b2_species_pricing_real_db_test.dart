/// 独立复验探针 D（qa-verify2）：物种表改版 —— 按物种计价矩阵 / 免费券 / 边界 / 每物种仅一株。
///
/// **全部跑在真实 Drift 库 + 真实仓储**（碎片余额落 `premium_fragments`、免费券落
/// `unlocked_species`、阳光落 `sunlight_ledgers`），与工程内存 Fake 用例相互独立。
library qa_b2_species_pricing_real_db_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:test/test.dart';

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

class _Ctx {
  _Ctx(this.database, this.svc, this.plants, this.ledger);
  final db.AppDatabase database;
  final PlantGrowthService svc;
  final PlantLocalRepository plants;
  final SunlightLocalRepository ledger;
}

Future<_Ctx> _make({double initialBalance = 100000}) async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  await database.customSelect('SELECT 1').get();
  addTearDown(() => database.close());

  final PlantLocalRepository plants = PlantLocalRepository(database);
  final SunlightLocalRepository ledger = SunlightLocalRepository(database);
  final SettingsLocalRepository settings = SettingsLocalRepository(database);
  await settings.saveSettings(const AppSettings(
    ageTier: AgeTier.low,
    dailyFocusCap: kDailyFocusCapLow,
    dailyAppCapMinutes: 30,
    restAfterSessions: 2,
    restMinutes: 10,
    taskSunlight: 12,
    poolBudget: kPoolBudgetDefaultLow,
    gardenPotCapacity: 12,
  ));
  if (initialBalance > 0) {
    await ledger.append(SunlightEntry(
      id: 'seed_balance',
      ts: DateTime(2026, 1, 1),
      type: SunlightType.earn,
      gross: initialBalance,
      net: initialBalance,
      balanceAfter: initialBalance,
      refType: 'seed',
      dayKey: '2026-01-01',
    ));
  }
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: settings,
    bloomRewards: plants,
  );
  return _Ctx(database, svc, plants, ledger);
}

Future<int> _ledgerCountByRef(
    db.AppDatabase database, String refType, String refId) async {
  final QueryRow row = await database.customSelect(
    'SELECT COUNT(*) AS c FROM sunlight_ledgers WHERE ref_type = ? AND ref_id = ?;',
    variables: <Variable>[Variable.withString(refType), Variable.withString(refId)],
  ).getSingle();
  return row.read<int>('c');
}

Future<int> _plantCount(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect('SELECT COUNT(*) AS c FROM plants;')
      .getSingle();
  return row.read<int>('c');
}

PlantSpecies _sp(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

// 8 物种 id（顺序 = 展示顺序）。
const List<String> _kAllIds = <String>[
  'species_sunflower',
  'species_moon_orchid',
  'species_tomato',
  'species_strawberry',
  'species_star_flower',
  'species_rainbow_fern',
  'species_coral_orchid',
  'species_jade_hydrangea',
];

void main() {
  // ── 计价矩阵 ────────────────────────────────────────────────────────────
  group('D1 · plantCost / fragmentCostOf 8 物种矩阵（与口径逐条对齐）', () {
    test('物种表恰 8 种、顺序 = 展示顺序、无 daisy/cactus', () {
      expect(kSeedPlantSpecies.map((PlantSpecies s) => s.id).toList(), _kAllIds);
      final Set<String> ids =
          kSeedPlantSpecies.map((PlantSpecies s) => s.id).toSet();
      expect(ids.contains('species_daisy'), isFalse);
      expect(ids.contains('species_cactus'), isFalse);
    });

    test('plantCost 矩阵（low / high 同值）', () async {
      final _Ctx ctx = await _make();
      // 期望：id → (kind, amount)
      final Map<String, (PlantCostKind, int)> expectLow =
          <String, (PlantCostKind, int)>{
        'species_sunflower': (PlantCostKind.free, 0),
        'species_moon_orchid': (PlantCostKind.fragments, kSpeciesFragmentCostPremium),
        'species_tomato': (PlantCostKind.sunlight, kSpeciesSunlightCostCommon),
        'species_strawberry': (PlantCostKind.sunlight, kSpeciesSunlightCostCommon),
        'species_star_flower': (PlantCostKind.fragments, 10),
        'species_rainbow_fern': (PlantCostKind.fragments, 10),
        'species_coral_orchid': (PlantCostKind.fragments, 10),
        'species_jade_hydrangea': (PlantCostKind.fragments, 10),
      };
      for (final MapEntry<String, (PlantCostKind, int)> e in expectLow.entries) {
        final PlantCost low = await ctx.svc.plantCost(_sp(e.key), AgeTier.low);
        final PlantCost high = await ctx.svc.plantCost(_sp(e.key), AgeTier.high);
        expect(low.kind, e.value.$1, reason: '${e.key} low kind');
        expect(low.amount, e.value.$2, reason: '${e.key} low amount');
        expect(high.kind, e.value.$1, reason: '${e.key} high kind');
        expect(high.amount, e.value.$2, reason: '${e.key} high amount');
      }
    });

    test('fragmentCostOf：初始物种 0，其余按档位（普通 6 / 精英 10）', () async {
      final _Ctx ctx = await _make();
      expect(ctx.svc.fragmentCostOf(_sp('species_sunflower')), 0);
      expect(ctx.svc.fragmentCostOf(_sp('species_tomato')), kSpeciesFragmentCostCommon);
      expect(ctx.svc.fragmentCostOf(_sp('species_strawberry')), 6);
      for (final String id in <String>[
        'species_moon_orchid',
        'species_star_flower',
        'species_rainbow_fern',
        'species_coral_orchid',
        'species_jade_hydrangea',
      ]) {
        expect(ctx.svc.fragmentCostOf(_sp(id)), kSpeciesFragmentCostPremium,
            reason: '$id 为 rare → 档位派生 10');
      }
    });
  });

  // ── 月光兰（精英）扣碎片 + 账本记录 ─────────────────────────────────────
  group('D2 · 月光兰（精英）：扣 10 碎片、账本无 plant_plant 记录', () {
    test('碎片 -10、无 plant_plant 记录、阳光余额不变', () async {
      final _Ctx ctx = await _make();
      final DateTime now = DateTime(2026, 9, 27, 8);
      await ctx.plants.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_moon_orchid', 0, now);

      final List<SunlightEntry> all = await ctx.ledger.all();
      final List<SunlightEntry> spends = all
          .where((SunlightEntry e) => e.refType == 'plant_plant')
          .toList();
      expect(spends, isEmpty, reason: '精英碎片物种不扣阳光');
      expect(await _ledgerCountByRef(ctx.database, 'plant_plant', 'species_moon_orchid'), 0);
      expect(await ctx.plants.premiumFragmentBalance(), 10);
      expect(await ctx.ledger.balance(), 100000);
    });

    test('普通物种用碎片种植不扣阳光（无 plant_plant 记录）', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(20);
      await ctx.svc.plant('species_tomato', 0, DateTime(2026, 9, 27, 8),
          payWith: PlantCostKind.fragments);
      expect(await _ledgerCountByRef(ctx.database, 'plant_plant', 'species_tomato'), 0);
      expect(await ctx.plants.premiumFragmentBalance(), 14);
    });
  });

  // ── 免费券 ──────────────────────────────────────────────────────────────
  group('D3 · 免费种植券（UnlockedSpecies 语义）', () {
    test('持券：不扣碎片 / 不扣阳光、券被消耗（表里该行消失）', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(0);
      await ctx.plants.unlockSpecies('species_star_flower'); // 发券
      expect(await ctx.plants.unlockedSpeciesIds(), contains('species_star_flower'));

      await ctx.svc.plant('species_star_flower', 0, DateTime(2026, 9, 27, 8));

      expect(await ctx.plants.premiumFragmentBalance(), 0, reason: '有券不扣碎片');
      expect(await _ledgerCountByRef(ctx.database, 'plant_plant', 'species_star_flower'), 0,
          reason: '有券不扣阳光');
      expect(await ctx.plants.unlockedSpeciesIds(), isNot(contains('species_star_flower')),
          reason: '券被消耗 → 行消失');
      expect(await _plantCount(ctx.database), 1);
    });

    test('券对月光兰同样生效（不扣阳光）', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.unlockSpecies('species_moon_orchid');
      await ctx.svc.plant('species_moon_orchid', 0, DateTime(2026, 9, 27, 8));
      expect(await _ledgerCountByRef(ctx.database, 'plant_plant', 'species_moon_orchid'), 0);
      expect(await ctx.plants.unlockedSpeciesIds(), isEmpty);
    });

    test('consumeUnlock 对无券物种幂等（删 0 行不报错）', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.consumeUnlock('species_nonexistent'); // 不应抛
      await ctx.plants.consumeUnlock('species_nonexistent');
      expect(await ctx.plants.unlockedSpeciesIds(), isEmpty);
    });
  });

  // ── 碎片不足边界 ────────────────────────────────────────────────────────
  group('D4 · 碎片不足边界：拒绝且余额不变、绝不为负', () {
    test('普通 5/6：余额 5 种番茄被拒，余额仍 5、不落植物', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(5);
      await expectLater(
        () => ctx.svc.plant('species_tomato', 0, DateTime(2026, 9, 27, 8),
            payWith: PlantCostKind.fragments),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.plants.premiumFragmentBalance(), 5);
      expect(await _plantCount(ctx.database), 0);
    });

    test('普通 6/6：余额 6 种番茄成功，余额归 0', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(6);
      await ctx.svc.plant('species_tomato', 0, DateTime(2026, 9, 27, 8),
          payWith: PlantCostKind.fragments);
      expect(await ctx.plants.premiumFragmentBalance(), 0);
    });

    test('精英 9/10：余额 9 种星辰花被拒，余额仍 9', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(9);
      await expectLater(
        () => ctx.svc.plant('species_star_flower', 0, DateTime(2026, 9, 27, 8)),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.plants.premiumFragmentBalance(), 9);
      expect(await _plantCount(ctx.database), 0);
    });

    test('精英 10/10：余额 10 成功，余额归 0', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(10);
      await ctx.svc.plant('species_star_flower', 0, DateTime(2026, 9, 27, 8));
      expect(await ctx.plants.premiumFragmentBalance(), 0);
    });

    test('碎片 0：任何碎片物种被拒，余额仍 0（不为负）', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(0);
      await expectLater(
        () => ctx.svc.plant('species_star_flower', 0, DateTime(2026, 9, 27, 8)),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.plants.premiumFragmentBalance(), 0);
      expect(await _plantCount(ctx.database), 0);
    });
  });

  // ── 月光兰碎片不足边界 ──────────────────────────────────────────────────
  group('D5 · 月光兰碎片不足边界', () {
    test('碎片余额 9 种月光兰被拒：不扣、不落植物', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(9);
      await expectLater(
        () => ctx.svc.plant('species_moon_orchid', 0, DateTime(2026, 9, 27, 8)),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.plants.premiumFragmentBalance(), 9);
      expect(await _plantCount(ctx.database), 0);
    });

    test('碎片余额 10 恰好可种，余额归 0', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(10);
      await ctx.svc.plant('species_moon_orchid', 0, DateTime(2026, 9, 27, 8));
      expect(await ctx.plants.premiumFragmentBalance(), 0);
    });
  });

  // ── 同物种同时仅一株 ────────────────────────────────────────────────────
  group('D6 · 同物种可重复种植（C29 修订）/ 死亡后可重种重扣', () {
    final DateTime now = DateTime(2026, 9, 27, 8);

    test('已存活同物种 → 再种放行，第 2 株扣 300 阳光（C29）', () async {
      final _Ctx ctx = await _make();
      await ctx.svc.plant('species_sunflower', 0, now); // 首株免费
      final Plant p2 = await ctx.svc.plant('species_sunflower', 1, now);
      expect(p2.shovelRefund, 150, reason: '付费株铲除返还 = 普通 300×50%');
      expect(await _plantCount(ctx.database), 2,
          reason: 'C29：同物种可多株并存');
      final QueryRow row = await ctx.database.customSelect(
          'SELECT net FROM sunlight_ledgers WHERE ref_type = \'plant_plant\';')
          .getSingle();
      expect(row.read<double>('net'), -300,
          reason: '向日葵第 2 株起按普通档阳光价收费');
    });

    test('枯萎（wilting）算存活 → 再种仍按付费口径放行（C29）', () async {
      final _Ctx ctx = await _make();
      final Plant p = await ctx.svc.plant('species_sunflower', 0, now);
      await ctx.plants.savePlant(p.copyWith(status: PlantStatus.wilting));
      final Plant p2 = await ctx.svc.plant('species_sunflower', 1, now);
      expect(await _plantCount(ctx.database), 2);
      expect(p2.shovelRefund, 150);
    });

    test('死亡（dead）后可再种：重种重扣 10 碎片（一次兑换买一株，死亡全损不退款）',
        () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(40);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      await ctx.plants.savePlant(p0.copyWith(status: PlantStatus.dead));

      final Plant p1 = await ctx.svc.plant('species_moon_orchid', 0, now); // -10
      expect(p1.id, isNot(p0.id));
      expect(await _ledgerCountByRef(ctx.database, 'plant_plant', 'species_moon_orchid'), 0,
          reason: '精英碎片物种不扣阳光');
      expect(await ctx.plants.premiumFragmentBalance(), 20,
          reason: '死亡全损不退款，重种重新扣 10 碎片（40→30→20）');
      expect(await _plantCount(ctx.database), 1, reason: '死株已释放，仅剩新株');
    });

    test('不同物种可各种一株', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(40);
      await ctx.svc.plant('species_sunflower', 0, now);
      await ctx.svc.plant('species_tomato', 1, now);
      await ctx.svc.plant('species_star_flower', 2, now);
      expect(await _plantCount(ctx.database), 3);
    });
  });
}
