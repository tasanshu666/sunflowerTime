/// 植物成长 V2 回归测试（玄参大人 2026-09-22 拍板口径）。
///
/// 覆盖两件事：
///  ① **幂等**：`_advanceGrowth` 的 `stage_started_at` 必须在每次 tick 后推进到 now，
///     否则每次 `tickAll` 都会把「stage_started_at → now」整段时间**重复累加**
///     （真机：浇水标注 +12%、实际阶段进度跳 21%）。判据是**增量**，不是「跑通了」：
///       · 同一时刻重复 tick → 增量必须为 0（页面刷新多少次都不许涨）；
///       · 相邻两次 tick（间隔 24h）→ 两次增量必须**相等**（0.1），不是 0.1 / 0.2。
///  ② **数值口径**：
///       · 普通植物（240h/阶段）完全不养护 → 正好 30 天长成（bloomed）；
///       · 每天满养护（3 次浇水 +3%、1 次施肥 +3%）→ 约 19 天长成；
///       · 精品植物（480h/阶段）完全不养护 → 60 天长成。
///
/// 纯 Dart：仓储以内存 Fake 实现，不依赖 Drift / Flutter。
library plant_growth_v2_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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
  _MemPlantRepo(this.speciesList);

  final List<PlantSpecies> speciesList;
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
  Future<List<PlantSpecies>> species() async => List<PlantSpecies>.of(speciesList);
}

/// 无任何专注会话：成长系数为 1.0（隔离「不养护」场景）。
class _MemFocusRepo implements FocusRepository {
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

/// 账本 Fake：余额恒充足（测成长不看经济），但养护次数 / 上次时间按真实记录。
class _MemLedgerRepo implements SunlightRepository {
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
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType != refType || e.refId != refId) continue;
      if (last == null || e.ts.isAfter(last)) last = e.ts;
    }
    return last;
  }
}

class _MemSettingsRepo implements SettingsRepository {
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

// ── 组装辅助 ────────────────────────────────────────────────────────────────

const String _kPlantId = 'p1';

({
  PlantGrowthService svc,
  _MemPlantRepo plants,
}) _make({
  double hoursPerStage = kPlantGrowthHoursPerStageDefault,
}) {
  final _MemPlantRepo plants = _MemPlantRepo(<PlantSpecies>[
    PlantSpecies(
      id: 'sp_test',
      name: '测试草',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: hoursPerStage,
      subscriptionOnly: false,
    ),
  ]);
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _MemFocusRepo(),
    ledger: _MemLedgerRepo(),
    settings: _MemSettingsRepo(),
  );
  return (svc: svc, plants: plants);
}

/// 种子期植物。`lastWaterAt = null` → 不触发枯萎/死亡，隔离「纯成长速率」测量。
Plant _seedPlant(DateTime now) => Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthProgress: 0.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      mood: PlantMood.calm,
    );

/// 成株盛开植物（用于花谢循环测试）。`bloomedAt = null` 模拟老库升级来的已开花植物。
Plant _adultBloomed(DateTime now, {DateTime? bloomedAt}) => Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 1.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.bloomed,
      plantedAt: now,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      bloomedAt: bloomedAt,
      mood: PlantMood.calm,
    );

Future<double> _progress(_MemPlantRepo plants) async =>
    (await plants.plant(_kPlantId))!.growthProgress;

/// 一天满养护：3 次浇水（间隔 >30min）+ 1 次施肥。
Future<void> _dailyCare(
  PlantGrowthService svc,
  Plant p,
  DateTime dayStart,
) async {
  await svc.water(p.id, dayStart);
  await svc.water(p.id, dayStart.add(const Duration(minutes: 31)));
  await svc.water(p.id, dayStart.add(const Duration(minutes: 62)));
  await svc.fertilize(p.id, dayStart.add(const Duration(minutes: 93)));
}

/// 逐日推进直到 bloomed，返回**天数**（-1 = 上限内未开花）。
Future<int> _daysToBloom({
  required bool fullCare,
  double hoursPerStage = kPlantGrowthHoursPerStageDefault,
}) async {
  final ctx = _make(hoursPerStage: hoursPerStage);
  final DateTime start = DateTime(2026, 9, 1);
  await ctx.plants.savePlant(_seedPlant(start));

  DateTime now = start;
  for (int day = 0; day < 200; day++) {
    await ctx.svc.tickAll(now);
    final Plant? cur = await ctx.plants.plant(_kPlantId);
    if (cur == null) break;
    if (cur.status == PlantStatus.bloomed) return day;
    if (fullCare && cur.status == PlantStatus.growing) {
      await _dailyCare(ctx.svc, cur, now);
    }
    now = now.add(const Duration(days: 1));
  }
  return -1;
}

void main() {
  group('幂等：stage_started_at 必须每次 tick 推进到 now', () {
    test('同一时刻重复 tickAll → 增量为 0（页面刷新多少次都不许涨）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0);
      final double first = await _progress(ctx.plants);

      // 同一时刻再 tick 3 次（模拟花园页反复刷新 / 浇水后 reload）。
      for (int i = 0; i < 3; i++) {
        await ctx.svc.tickAll(t0);
      }
      final double repeated = await _progress(ctx.plants);

      expect(first, closeTo(0.0, 1e-9));
      expect(
        repeated - first,
        closeTo(0.0, 1e-9),
        reason: '重复 tick 仍在累加进度 → 非幂等（旧 bug：每次刷新都涨一段）',
      );
    });

    test('相邻两次 tick（各 +24h）→ 两次增量相等，均为 24h/240h = 0.1', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0);
      final double p0 = await _progress(ctx.plants);

      await ctx.svc.tickAll(t0.add(const Duration(hours: 24)));
      final double p1 = await _progress(ctx.plants);

      await ctx.svc.tickAll(t0.add(const Duration(hours: 48)));
      final double p2 = await _progress(ctx.plants);

      print('[V2 幂等] p0=$p0, p1=$p1, p2=$p2 '
          '→ 第一次增量=${p1 - p0}, 第二次增量=${p2 - p1}');

      expect(p0, closeTo(0.0, 1e-9));
      expect(p1 - p0, closeTo(0.1, 1e-9)); // 24h / 240h
      expect(
        p2 - p1,
        closeTo(0.1, 1e-9),
        reason: '第二次增量应与第一次相同；若变成 0.2 说明整段被重复累加',
      );
    });

    test('半天 tick：增量减半（2×12h == 1×24h）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0.add(const Duration(hours: 12)));
      final double half = await _progress(ctx.plants);
      await ctx.svc.tickAll(t0.add(const Duration(hours: 24)));
      final double full = await _progress(ctx.plants);

      expect(half, closeTo(0.05, 1e-9));
      expect(full, closeTo(0.1, 1e-9));
    });
  });

  group('V2 成长数值口径（玄参大人 2026-09-22 拍板）', () {
    test('普通植物 240h/阶段：完全不养护 → 正好 30 天长成', () async {
      final int days = await _daysToBloom(fullCare: false);
      print('[V2 数值] 不养护长成天数 = $days');
      expect(days, 30);
    });

    test('普通植物 240h/阶段：每天满养护（3 浇 +1 肥）→ 约 19 天长成', () async {
      final int days = await _daysToBloom(fullCare: true);
      // 理论值：3.0 阶段 ÷（自动 10% + 养护 6%）/天 = 18.75 天 → 实测进位 19 天。
      print('[V2 数值] 每天满养护长成天数 = $days（理论 18.75 天）');
      expect(days, inInclusiveRange(19, 20));
    });

    test('精品植物 480h/阶段：完全不养护 → 60 天长成', () async {
      final int days = await _daysToBloom(
        fullCare: false,
        hoursPerStage: kPlantGrowthHoursPerStagePremium,
      );
      print('[V2 数值] 精品植物不养护长成天数 = $days');
      expect(days, 60);
    });

    // ⚠️ 为什么补这条：文档「精品植物满养护约 28 天」是 2026-09-25 施肥 5%→3% 后
    // **按公式推算**出来的（3.0 ÷（自动 5% + 养护 6%）= 27.27 → 进位 28），
    // 当时没有测试背书。推算值必须实测钉死，否则文档里的 28 天永远是「没人验过的数」。
    test('精品植物 480h/阶段：每天满养护（3 浇 +1 肥）→ 约 28 天长成', () async {
      final int days = await _daysToBloom(
        fullCare: true,
        hoursPerStage: kPlantGrowthHoursPerStagePremium,
      );
      // 理论值：3.0 阶段 ÷（自动 24h/480h = 5% + 养护 6%）/天 = 27.27 天 → 进位 28 天。
      print('[V2 数值] 精品植物每天满养护长成天数 = $days（理论 27.27 天）');
      expect(days, inInclusiveRange(27, 29));
    });

    test('常量取值钉死（防回退）', () {
      expect(kPlantGrowthHoursPerStageDefault, 240.0);
      expect(kPlantGrowthHoursPerStagePremium, 480.0);
      expect(kPlantWaterProgressGain, 0.01);
      expect(kPlantFertilizeProgressGain, 0.03);
      expect(kPlantAutoGrowthScale, 1.0);
      // 每天养护上限 6%：3×1% + 1×3%
      expect(
        kPlantWaterMaxPerDay * kPlantWaterProgressGain +
            kPlantFertilizeMaxPerDay * kPlantFertilizeProgressGain,
        closeTo(0.06, 1e-9),
      );
    });
  });

  group('养护增量口径：浇水 +1% / 施肥 +3%（不再跳 21%）', () {
    test('浇水一次 → 进度恰好 +1%（旧口径 +12% 会跳）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.water(_kPlantId, t0);
      final double afterWater = await _progress(ctx.plants);
      print('[V2 养护] 浇水后进度 = $afterWater');

      expect(afterWater, closeTo(kPlantWaterProgressGain, 1e-9));
    });

    test('浇水后立刻 tickAll：不会把「已结算过的整段」再累加一遍', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.water(_kPlantId, t0);
      final double before = await _progress(ctx.plants);

      // 浇水后表现层 reload → tickAll（真机正是这条路径把 +1% 变成 +21%）。
      await ctx.svc.tickAll(t0);
      await ctx.svc.tickAll(t0.add(const Duration(minutes: 1)));
      final double after = await _progress(ctx.plants);

      print('[V2 养护] 浇水+reload 后进度 = $after（浇水后 $before）');
      // 只允许 1 分钟的真实时间增量（1/60/240），绝不允许把整天叠加进来。
      expect(after - before, closeTo(1.0 / 60.0 / 240.0, 1e-9));
    });
  });

  group('花谢循环（玄参大人 2026-09-23 拍板：盛开不能一直保持）', () {
    test('盛开保持 kBloomDurationDays 天后花谢：status→growing、进度回落 floor', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0, bloomedAt: t0));

      // 花期内（0 .. kBloomDurationDays-1 天）保持盛开。
      for (int d = 0; d < kBloomDurationDays; d++) {
        await ctx.svc.tickAll(t0.add(Duration(days: d)));
        final Plant cur = (await ctx.plants.plant(_kPlantId))!;
        expect(cur.status, PlantStatus.bloomed, reason: '第 $d 天仍在花期');
      }

      // 跨过花期一天 → 花谢。
      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays)));
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.growing);
      expect(cur.growthProgress, closeTo(kBloomWiltProgressFloor, 1e-9));
    });

    test('花谢后不会立即再盛开（进度需由时间/养护重新养满）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0, bloomedAt: t0));

      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays)));
      expect((await ctx.plants.plant(_kPlantId))!.status, PlantStatus.growing);

      // 花谢后仅过 1 天（自动成长 +10%/天）→ 进度 0.5→0.6，仍 growing。
      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays + 1)));
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.growing);
      expect(cur.growthProgress,
          closeTo(kBloomWiltProgressFloor + 0.10, 1e-9));
    });

    test('花谢后经时间重新养满 → 再度盛开（循环成立）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0, bloomedAt: t0));

      // 让花期结束 → 花谢。
      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays)));
      expect((await ctx.plants.plant(_kPlantId))!.status, PlantStatus.growing);

      // 之后纯自动成长（不养护）每天 +10%，直到再次盛开。
      DateTime now = t0.add(Duration(days: kBloomDurationDays + 1));
      int rebloomDay = -1;
      for (int i = 0; i < 60; i++) {
        await ctx.svc.tickAll(now);
        final Plant cur = (await ctx.plants.plant(_kPlantId))!;
        if (cur.status == PlantStatus.bloomed) {
          rebloomDay = i;
          expect(cur.bloomedAt, isNotNull, reason: '再盛开应记录新花期起点');
          break;
        }
        now = now.add(const Duration(days: 1));
      }
      // 普通植物 (1-0.5)/0.10 = 5 天养满 → 约第 5 天再盛开。
      expect(rebloomDay, greaterThanOrEqualTo(0),
          reason: '花谢后应能再次盛开，实测 rebloomDay=$rebloomDay');
      expect(rebloomDay, inInclusiveRange(4, 6));
    });

    test('老库升级来的已开花植物（bloomedAt=null）首次 tick 不花谢、补计时起点', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0)); // bloomedAt 为 null

      await ctx.svc.tickAll(t0);
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.bloomed, reason: '仍是盛开，不应立即花谢');
      expect(cur.bloomedAt, t0, reason: '应以本次 tick 为计时起点补上');
    });
  });
}
