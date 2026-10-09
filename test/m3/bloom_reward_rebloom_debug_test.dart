/// P0 回归 · 「催熟到成株」后头顶奖励图标不显示（F78 修订回归）。
///
/// 用户口径（2026-10-07 真机）：「催熟植物，催熟后，植物产生的产物不在植物前面显示了，
/// 看不到奖励的东西了」。
///
/// 复现路径（debug 面板 `_forceAdult`）：
///   目标株写为 `stage=adult / status=growing / progress=1.0 / lastWaterAt=now`
///   → `tickAll(now2)`：本 tick 由 growing → bloomed，登记「开花瞬间」pending
///   → 断言 `collectibleBloomRewards(now3)` 必须返回该株的 instant 奖励（头顶图标数据源）。
///
/// 同时覆盖：
///   · 正常开花（非催熟）路径同样可收集；
///   · 二次催熟（复开花）后**本轮**新奖励仍可收集，旧轮 pending 被兜底结算（不累积滞留）。
library bloom_reward_rebloom_debug_test;

import 'dart:math';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import '../helpers/no_hit_random.dart';

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
  Future<List<PlantSpecies>> species() async =>
      List<PlantSpecies>.of(speciesList);
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
      totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

class _MemLedger implements SunlightRepository {
  double initialBalance = 1000000;
  final List<SunlightEntry> entries = <SunlightEntry>[];
  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance;
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
          String refType, String refId, String key) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
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

/// 确定性随机：`nextDouble` 恒返回 0.99（= 无额外奖励，仅保底阳光）。
class _SeqRandom implements Random {
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

const String _kPlantId = 'p1';

const List<PlantSpecies> _kSpecies = <PlantSpecies>[
  PlantSpecies(
    id: 'sp_common_a',
    name: '普通草A',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
  ),
];

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger, this.bloomRewards);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
  final InMemoryBloomRewardRepository bloomRewards;
}

_Ctx _make() {
  final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
  final _MemLedger ledger = _MemLedger();
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: bloomRewards,
    random: _SeqRandom(),
    weedRandom: NoHitRandom(),
  );
  return _Ctx(svc, plants, ledger, bloomRewards);
}

void main() {
  group('P0 · 催熟到成株后头顶奖励可收集（复现 F78 回归）', () {
    test('催熟路径（adult/growing/1.0）→ 开花 → instant 奖励必须可收集', () async {
      final _Ctx ctx = _make();
      final DateTime write = DateTime(2026, 10, 7, 10, 0, 0);
      // 模拟调试面板 `_forceAdult` 写入：成株 + growing + 进度满。
      await ctx.plants.savePlant(Plant(
        id: _kPlantId,
        speciesId: 'sp_common_a',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: write,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: write,
        lastWaterAt: write,
        mood: PlantMood.calm,
      ));

      // 调试面板随后用**另一次** DateTime.now() 调 tickAll（真实实现即如此）。
      final DateTime tick = write.add(const Duration(milliseconds: 5));
      await ctx.svc.tickAll(tick);

      final Plant after = (await ctx.plants.plant(_kPlantId))!;
      expect(after.status, PlantStatus.bloomed, reason: '本 tick 应开花');
      expect(after.bloomedAt, isNotNull);

      // 花园页刷新时刻（又一次 now）。
      final DateTime refresh = tick.add(const Duration(milliseconds: 5));
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(refresh);
      expect(
        collectible[_kPlantId],
        isNotNull,
        reason: '催熟开花后头顶必须有可收集奖励（用户口径：看不到奖励 = 回归）',
      );
      expect(collectible[_kPlantId]!.first.rewardKind, kBloomRewardPhaseInstant);
    });

    test('正常开花路径 → instant 奖励同样可收集（覆盖非催熟）', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 10, 7, 9, 0);
      await ctx.plants.savePlant(Plant(
        id: _kPlantId,
        speciesId: 'sp_common_a',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: now,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now,
        lastWaterAt: now,
        mood: PlantMood.calm,
      ));
      await ctx.svc.tickAll(now);
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(now);
      expect(collectible[_kPlantId], isNotNull);
      expect(collectible[_kPlantId]!.first.rewardKind, kBloomRewardPhaseInstant);
    });

    test('二次催熟（复开花）→ 本轮新 instant 可收集，且旧轮 pending 不滞留', () async {
      final _Ctx ctx = _make();
      final DateTime t1 = DateTime(2026, 10, 7, 8, 0);
      await ctx.plants.savePlant(Plant(
        id: _kPlantId,
        speciesId: 'sp_common_a',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: t1,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: t1,
        lastWaterAt: t1,
        mood: PlantMood.calm,
      ));
      await ctx.svc.tickAll(t1); // 第一次开花
      // 不收集第一条 instant，直接再催熟（复写 growing + 进度满）。
      final DateTime t2 = t1.add(const Duration(minutes: 10));
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      await ctx.plants.savePlant(cur.copyWith(
        status: PlantStatus.growing,
        growthProgress: 1.0,
        stage: PlantStage.adult,
        stageStartedAt: t2,
        lastWaterAt: t2,
      ));
      await ctx.svc.tickAll(t2); // 第二次开花

      final DateTime refresh = t2.add(const Duration(seconds: 1));
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(refresh);
      expect(collectible[_kPlantId], isNotNull,
          reason: '复开花后本轮 instant 仍应可收集');
      // 本轮只应看到「第二次开花」的 instant（旧轮已被兜底结算，不累积）。
      expect(collectible[_kPlantId]!.length, 1,
          reason: '旧轮 pending 必须兜底结算，不得滞留（F78 原始 bug 不回归）');
      expect(collectible[_kPlantId]!.first.dueAt, t2);
    });
  });

  // ── P0 · 同轮时钟容差（F78 修订兜底防线）────────────────────────────────
  group('P0 · 同轮判定的时钟容差（kBloomSameRoundToleranceSeconds）', () {
    /// 一株「正盛开」的植物（bloomedAt 指定）。
    Plant bloomedAt(DateTime at) => Plant(
          id: _kPlantId,
          speciesId: 'sp_common_a',
          potIndex: 0,
          stage: PlantStage.adult,
          stageStartedAt: at,
          growthProgress: 1.0,
          growthFactor: 1.0,
          status: PlantStatus.bloomed,
          plantedAt: at,
          lastWaterAt: at,
          bloomedAt: at,
          bloomCount: 1,
          mood: PlantMood.calm,
        );

    Future<Map<String, List<PendingBloomReward>>> collectibleWith({
      required DateTime bloomedAtTime,
      required DateTime dueAt,
    }) async {
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(bloomedAt(bloomedAtTime));
      await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_same',
        plantId: _kPlantId,
        dueAt: dueAt,
        rewardKind: kBloomRewardPhaseInstant,
        rewardSunlight: 6,
      ));
      final DateTime now =
          bloomedAtTime.isAfter(dueAt) ? bloomedAtTime : dueAt;
      return ctx.svc.collectibleBloomRewards(now.add(const Duration(seconds: 2)));
    }

    test('dueAt 比 bloomedAt 早 < 容差（同 tick 抖动）→ 仍可收集', () async {
      final DateTime bloom = DateTime(2026, 10, 7, 10, 0, 0);
      final Map<String, List<PendingBloomReward>> r = await collectibleWith(
        bloomedAtTime: bloom,
        dueAt: bloom.subtract(const Duration(milliseconds: 300)),
      );
      expect(r[_kPlantId], isNotNull,
          reason: '同 tick 抖动（早 300ms < 1s）应仍视为本轮、头顶显示奖励');
    });

    test('dueAt 明显早于 bloomedAt（旧轮，早 > 容差）→ 不可收集（不回归 F78）', () async {
      final DateTime bloom = DateTime(2026, 10, 7, 10, 0, 0);
      final Map<String, List<PendingBloomReward>> r = await collectibleWith(
        bloomedAtTime: bloom,
        dueAt: bloom.subtract(const Duration(days: 1)),
      );
      expect(r[_kPlantId], isNull,
          reason: '旧轮 pending（早 1 天）不可收集，由 tickAll 兜底结算，不累积滞留');
    });
  });
}
