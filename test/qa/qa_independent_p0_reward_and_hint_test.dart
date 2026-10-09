/// 独立复验（QA/Edward）· P0-① 头顶奖励图标「催熟后看不到奖励」反证批（领域层 + 真实库）。
///
/// 与工程用例 `bloom_reward_rebloom_debug_test.dart` **不同**：本文件刻意走团队负责人点名的
/// **额外场景**，独立构造，不复跑工程用例：
///  · A1 多株场景：只催熟其中一株 → 仅该株头顶有奖励，其余不受影响；
///  · A2 有干扰物（杂草）的「已盛开」株 → 奖励仍可见；
///  · A2b 有干扰物的「未盛开」株 →（C26）当天成长暂停 → 不盛开 → 无奖励（如实验证）；
///  · A3 枯萎（wilting）株经催熟面板写回 growing → 开花且奖励可见；A3b 不催熟 → 无奖励；
///  · A4 复开花多轮：旧轮 pending 不累积（F78 不回归，头顶始终 ≤1 条）。
///  · E1/E2 P1-⑤ 重试不得复活已 stop 的氛围音（`startAmbientWithRetries` 行为级）；
///  · E3/E4 P1-⑥ `grantSeedForDebug` 不刷券（同档位全持券返回 null）。
///  · F1 真实 Drift 库链路：催熟 → 落库 → 重读 → 可收集 → 收集入账恰一次。
library qa_independent_p0_reward_and_hint_test;

import 'dart:math';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
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
import 'package:sunflower_time/platform/audio_service.dart';

import '../helpers/no_hit_random.dart';

// ── 依赖替身 ────────────────────────────────────────────────────────────────

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
    gardenPotCapacity: 6,
  );
  @override
  Future<AppSettings> getSettings() async => value;
  @override
  Future<void> saveSettings(AppSettings settings) async => value = settings;
}

/// 确定性随机：`nextDouble` 恒 0.99（无额外奖励，仅保底阳光）/ `nextInt` 恒 0。
class _SeqRandom implements Random {
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

// ── 物种表 ──────────────────────────────────────────────────────────────────

const List<PlantSpecies> _kSpecies = <PlantSpecies>[
  PlantSpecies(
    id: 'species_sunflower',
    name: '向日葵',
    rarity: Rarity.common,
    baseCostHigh: 40,
    baseCostLow: 20,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
  ),
  PlantSpecies(
    id: 'sp_common_b',
    name: '普通草B',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
  ),
  PlantSpecies(
    id: 'sp_premium',
    name: '精英花',
    rarity: Rarity.rare,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
  ),
];

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
}

_Ctx _make() {
  final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
  final _MemLedger ledger = _MemLedger();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    random: _SeqRandom(),
    weedRandom: NoHitRandom(),
  );
  return _Ctx(svc, plants, ledger);
}

/// 一株「成株 / 进度满」的植物（tick 即可能开花）。
Plant _readyToBloom(
  String id,
  String speciesId,
  int pot,
  DateTime now, {
  PlantStatus status = PlantStatus.growing,
  DateTime? weedAt,
  DateTime? weedPestRollDay,
  DateTime? lastWaterAt,
}) =>
    Plant(
      id: id,
      speciesId: speciesId,
      potIndex: pot,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: status,
      plantedAt: now,
      lastWaterAt: lastWaterAt ?? now,
      weedAt: weedAt,
      weedPestRollDay: weedPestRollDay,
      mood: PlantMood.calm,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // A · P0-① 领域层反证（内存）
  // ═══════════════════════════════════════════════════════════════════════
  group('A · P0-① 催熟后头顶奖励（额外场景反证）', () {
    test('A1 多株场景：只催熟其中一株 → 仅该株头顶有奖励，其余不受影响', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      await ctx.plants.savePlant(Plant(
        id: 'p_sun',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.seed,
        stageStartedAt: now,
        growthProgress: 0.1,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now,
        lastWaterAt: now,
        mood: PlantMood.calm,
      ));
      await ctx.plants.savePlant(_readyToBloom('p_forced', 'sp_common_b', 1, now));
      await ctx.plants.savePlant(Plant(
        id: 'p_c',
        speciesId: 'sp_common_b',
        potIndex: 2,
        stage: PlantStage.sprout,
        stageStartedAt: now,
        growthProgress: 0.2,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now,
        lastWaterAt: now,
        mood: PlantMood.calm,
      ));
      await ctx.plants.savePlant(Plant(
        id: 'p_d',
        speciesId: 'sp_premium',
        potIndex: 3,
        stage: PlantStage.sprout,
        stageStartedAt: now,
        growthProgress: 0.2,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now,
        lastWaterAt: now,
        mood: PlantMood.calm,
      ));

      await ctx.svc.tickAll(now);
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));

      expect(collectible.containsKey('p_forced'), isTrue,
          reason: '被催熟那株头顶必须有奖励');
      expect(collectible.keys.toSet(), <String>{'p_forced'},
          reason: '其余 3 株不得受牵连（多株隔离）');
      expect(collectible['p_forced']!.first.rewardKind, kBloomRewardPhaseInstant);
    });

    test('A2 有干扰物的「已盛开」株：奖励仍可见（干扰物不隐藏头顶奖励）', () async {
      final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
      final _MemLedger ledger = _MemLedger();
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      final DateTime today = DateTime(now.year, now.month, now.day);
      await plants.savePlant(Plant(
        id: 'p1',
        speciesId: 'sp_common_b',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: now,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.bloomed,
        plantedAt: now,
        lastWaterAt: now,
        bloomedAt: now,
        bloomCount: 1,
        weedAt: today,
        weedPestRollDay: today,
        mood: PlantMood.calm,
      ));
      await bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'pr1',
        plantId: 'p1',
        dueAt: now,
        rewardKind: kBloomRewardPhaseInstant,
        rewardSunlight: kBloomInstantSunlight,
      ));
      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: _MemSettingsRepo(),
        bloomRewards: bloom,
        random: _SeqRandom(),
        weedRandom: NoHitRandom(),
      );
      final Map<String, List<PendingBloomReward>> collectible =
          await svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));
      expect(collectible['p1'], isNotNull,
          reason: '已盛开株即使当天长草，头顶奖励也必须仍可见');
    });

    test('A2b 有干扰物的「未盛开」株：C26 当天成长暂停 → 催熟不开花 → 无奖励（如实验证）',
        () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      final DateTime today = DateTime(now.year, now.month, now.day);
      await ctx.plants.savePlant(_readyToBloom('p1', 'sp_common_b', 0, now,
          weedAt: today, weedPestRollDay: today));
      await ctx.svc.tickAll(now);
      final Plant after = (await ctx.plants.plant('p1'))!;
      expect(after.status, PlantStatus.growing,
          reason: 'C26：当天有杂草 → 成长暂停 → 不盛开');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));
      expect(collectible.containsKey('p1'), isFalse,
          reason: '未盛开 → 无头顶奖励（与「催熟看不到奖励」同表象，但属 C26 预期行为）');
    });

    test('A3 枯萎（wilting）株经催熟面板（写回 growing+满进度）→ 开花且奖励可见', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      await ctx.plants.savePlant(_readyToBloom('p1', 'sp_common_b', 0, now,
          status: PlantStatus.wilting, lastWaterAt: now));
      final Plant cur = (await ctx.plants.plant('p1'))!;
      await ctx.plants.savePlant(cur.copyWith(status: PlantStatus.growing));
      await ctx.svc.tickAll(now);
      final Plant after = (await ctx.plants.plant('p1'))!;
      expect(after.status, PlantStatus.bloomed, reason: '催熟后应盛开');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));
      expect(collectible['p1'], isNotNull, reason: '枯萎株催熟开花后头顶奖励必须可见');
    });

    test('A3b 枯萎株「不催熟」直接 tick → 不盛开 → 无奖励', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      await ctx.plants.savePlant(Plant(
        id: 'p1',
        speciesId: 'sp_common_b',
        potIndex: 0,
        stage: PlantStage.adult,
        stageStartedAt: now,
        growthProgress: 1.0,
        growthFactor: 1.0,
        status: PlantStatus.wilting,
        plantedAt: now.subtract(const Duration(days: 2)),
        lastWaterAt: now.subtract(const Duration(days: 2)),
        wiltedAt: now.subtract(const Duration(hours: 2)),
        mood: PlantMood.thirsty,
      ));
      await ctx.svc.tickAll(now);
      final Plant after = (await ctx.plants.plant('p1'))!;
      expect(after.status, PlantStatus.wilting, reason: '枯萎态不因 tick 变盛开');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));
      expect(collectible.containsKey('p1'), isFalse);
    });

    test('A4 复开花多轮：旧轮 pending 不累积（F78 不回归，头顶始终 ≤1 条）', () async {
      final _Ctx ctx = _make();
      final DateTime t1 = DateTime(2026, 10, 8, 8, 0); // 08:00 → 晨露首轮次日
      await ctx.plants.savePlant(_readyToBloom('p1', 'sp_common_b', 0, t1));
      await ctx.svc.tickAll(t1); // 第 1 轮开花

      for (int round = 2; round <= 5; round++) {
        final DateTime tn = t1.add(Duration(minutes: 10 * (round - 1)));
        final Plant cur = (await ctx.plants.plant('p1'))!;
        await ctx.plants.savePlant(cur.copyWith(
          status: PlantStatus.growing,
          growthProgress: 1.0,
          stage: PlantStage.adult,
          stageStartedAt: tn,
          lastWaterAt: tn,
        ));
        await ctx.svc.tickAll(tn);

        final Map<String, List<PendingBloomReward>> collectible =
            await ctx.svc.collectibleBloomRewards(tn.add(const Duration(seconds: 1)));
        final List<PendingBloomReward> instants =
            (collectible['p1'] ?? const <PendingBloomReward>[])
                .where((PendingBloomReward r) =>
                    r.rewardKind == kBloomRewardPhaseInstant)
                .toList();
        expect(instants.length, 1,
            reason: '第 $round 轮：头顶只能有 1 条 instant（旧轮必须兜底结算，不得累积成一大排）');
        expect(instants.first.dueAt, tn,
            reason: '第 $round 轮：可见的 instant 必须是本轮（due=本轮 bloomedAt）');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // E · P1-⑤ / P1-⑥ 纯静态行为
  // ═══════════════════════════════════════════════════════════════════════
  group('E · P1-⑤ 重试不得复活已 stop 的氛围音', () {
    test('E1 首次失败后、重试前命中 stop（shouldAbort）→ 不再尝试、停播、返回 false', () async {
      int attempts = 0;
      bool aborted = false;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async {
          attempts++;
          throw StateError('首次 setAsset 失败');
        },
        isPlaying: () => false,
        // 第一次（进入循环）false；重试前的再校验 true = 这中间用户切走 tab / 退后台。
        shouldAbort: () => attempts >= 1,
        onAbort: () async => aborted = true,
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );
      expect(ok, isFalse, reason: '被 stop 拦下 → 不得置「已启动」');
      expect(attempts, 1, reason: '命中 shouldAbort 后不得再发起第 2 次启动（不复活）');
      expect(aborted, isTrue, reason: '必须停播');
    });

    test('E2 每次尝试前都重新校验 shouldAbort（含重试间隔后）→ 命中即停、尝试次数冻结', () async {
      int checks = 0;
      int attempts = 0;
      bool aborted = false;
      final bool ok = await AudioService.startAmbientWithRetries(
        start: () async {
          attempts++;
          // 第 1 次尝试「返回但未真正在播」→ 进入下一轮；下一轮开头 shouldAbort 命中。
          return;
        },
        isPlaying: () => false, // 始终未在播
        shouldAbort: () {
          checks++;
          return checks >= 2; // 第 2 次校验（= 第 2 次尝试前）起命中
        },
        onAbort: () async => aborted = true,
        maxAttempts: 5,
        retryDelay: Duration.zero,
      );
      expect(ok, isFalse);
      expect(attempts, 1, reason: '命中 shouldAbort 后不再发起新尝试');
      expect(aborted, isTrue, reason: '命中闸门必须停播');
    });
  });

  group('E · P1-⑥ grantSeedForDebug 不刷券', () {
    test('E3 普通档全持券 → 返回 null（不无限发券）', () async {
      final _Ctx ctx = _make();
      final String? first = await ctx.svc.grantSeedForDebug(premium: false);
      final String? second = await ctx.svc.grantSeedForDebug(premium: false);
      final String? third = await ctx.svc.grantSeedForDebug(premium: false);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(third, isNull, reason: '普通档 2 个物种全持券 → 第 3 次返回 null（不刷券）');
      expect(first == second, isFalse, reason: '两次发给不同物种（券按 speciesId 去重）');
    });

    test('E4 精英档发券 → 落到 rare 物种；再发 → null', () async {
      final _Ctx ctx = _make();
      final String? p1 = await ctx.svc.grantSeedForDebug(premium: true);
      final String? p2 = await ctx.svc.grantSeedForDebug(premium: true);
      expect(p1, 'sp_premium', reason: '精英券应发给精英档物种');
      expect(p2, isNull, reason: '精英档仅 1 个物种，再发 → null');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // F · 真实 Drift 库链路
  // ═══════════════════════════════════════════════════════════════════════
  group('F · 真实 Drift 库：催熟 → 落库 → 重读 → 可收集 → 收集入账一次', () {
    test('F1 完整链路（真实库时间戳精度）', () async {
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
        gardenPotCapacity: 6,
      ));
      await ledger.append(SunlightEntry(
        id: 'seed_balance',
        ts: DateTime(2026, 1, 1),
        type: SunlightType.earn,
        gross: 1000,
        net: 1000,
        balanceAfter: 1000,
        refType: 'seed',
        dayKey: '2026-01-01',
      ));

      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: settings,
        bloomRewards: plants,
        random: _SeqRandom(),
        weedRandom: NoHitRandom(),
      );

      final DateTime now = DateTime(2026, 10, 7, 10, 0);
      await plants.savePlant(_readyToBloom('p1', 'species_sunflower', 0, now));
      await svc.tickAll(now.add(const Duration(milliseconds: 5)));

      final Map<String, List<PendingBloomReward>> collectible =
          await svc.collectibleBloomRewards(now.add(const Duration(seconds: 1)));
      expect(collectible['p1'], isNotNull,
          reason: '真实库时间戳精度下，催熟后仍必须可收集（工程师自认唯一未覆盖的变量）');

      final PendingBloomReward instant = collectible['p1']!
          .firstWhere((PendingBloomReward r) =>
              r.rewardKind == kBloomRewardPhaseInstant);
      final double before = await ledger.balance();
      await svc.collectBloomReward(instant.id, now.add(const Duration(seconds: 2)));
      final double after = await ledger.balance();
      expect(after - before, instant.rewardSunlight.toDouble(),
          reason: '手动收集恰入账一次（照单发放）');

      await expectLater(
        svc.collectBloomReward(instant.id, now.add(const Duration(seconds: 3))),
        throwsA(isA<PlantOperationException>()),
      );
    });
  });
}
