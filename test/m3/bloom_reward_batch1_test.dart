/// 成株后循环玩法 Batch 1 单测（玄参拍板）：复开花节奏 + 花期双阶段奖励 + 精品碎片。
///
/// 覆盖：
///  ① 复开花节奏分档：普通 7（满养护）/ 14（不养护）天；精品 11（满养护）/ 21（不养护）天。
///  ② 开花瞬间奖励（变更 B：改为「掉落 + 手动收集」，不再即时入账）：普通/精品保底基础阳光；
///     四分支（碎片 / 种子 / 大额阳光 / 无额外）逐一钉死；精品「碎片 60% 掉 2 片」的双倍碎片场景；
///     收集前不入账、点击后入账一次。
///  ③ 第二段奖励（花开 48h 后掉落）：**手动收集**（不自动发放）+ 花谢兜底自动结算；
///     普通/精品各分支概率 + pending 领取置 claimed（每株仅发一次）。
///  ④ 精品碎片持有 / 余额（旧「满 8 手动解锁」已于物种表改版移除，用例见
///     `plant_species_pricing_test.dart`）。
///
/// 纯 Dart：仓储以内存 Fake 实现，随机源以可编排的 [_SeqRandom] 注入（确定性、不 flaky）。
library bloom_reward_batch1_test;

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

/// 账本 Fake：余额充足；记录全部 append 条目（供断言阳光发放）。
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
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && !e.ts.isBefore(since))
          .length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
      String refType, String refId) async {
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

/// 可编排随机源（确定性）：`nextDouble` 依次取 [doubles]（循环）；`nextInt` 取 [ints]。
class _SeqRandom implements Random {
  _SeqRandom({this.doubles = const <double>[], this.ints = const <int>[]});

  final List<double> doubles;
  final List<int> ints;
  int _di = 0;
  int _ii = 0;

  @override
  double nextDouble() {
    if (doubles.isEmpty) {
      throw StateError('_SeqRandom.nextDouble 无可用序列');
    }
    return doubles[_di++ % doubles.length];
  }

  @override
  int nextInt(int max) {
    if (ints.isEmpty) {
      throw StateError('_SeqRandom.nextInt 无可用序列');
    }
    return ints[_ii++ % ints.length] % max;
  }

  @override
  bool nextBool() => false;
}

// ── 组装辅助 ────────────────────────────────────────────────────────────────

const String _kPlantId = 'p1';

/// 物种表：2 个普通（common）+ 1 个精品（legendary，cactus 对应）。
const List<PlantSpecies> _kSpecies = <PlantSpecies>[
  PlantSpecies(
    id: 'sp_common_a',
    name: '普通草A',
    rarity: Rarity.common,
    baseCostHigh: 0,
    baseCostLow: 0,
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
    name: '精品花',
    rarity: Rarity.legendary,
    baseCostHigh: 0,
    baseCostLow: 0,
    growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
  ),
];

/// 一个 `rare` 物种（口径：rare 也算精品档，2026-09-26 拍板）。
const PlantSpecies _rareSpecies = PlantSpecies(
  id: 'sp_rare',
  name: '稀有花',
  rarity: Rarity.rare,
  baseCostHigh: 0,
  baseCostLow: 0,
  growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
);

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger, this.bloomRewards);

  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
  final InMemoryBloomRewardRepository bloomRewards;
}

_Ctx _make({Random? random, List<PlantSpecies>? species}) {
  final _MemPlantRepo plants = _MemPlantRepo(species ?? _kSpecies);
  final _MemLedger ledger = _MemLedger();
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: bloomRewards,
    random: random,
    weedRandom: NoHitRandom(),
  );
  return _Ctx(svc, plants, ledger, bloomRewards);
}

/// 一株「立刻可盛开」的成株：adult + growing + progress 1.0（tick 即 bloomed）。
Plant _readyToBloom(String speciesId, DateTime now) => Plant(
      id: _kPlantId,
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: now,
      mood: PlantMood.calm,
    );

/// 一株「复开花」成株：adult + growing + progress 0.5 + bloomCount 1（已开过一次花）。
Plant _rebloomPlant(String speciesId, DateTime now) => Plant(
      id: _kPlantId,
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: kBloomWiltProgressFloor,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: null, // 不触发枯萎，隔离纯成长速率
      bloomCount: 1,
      mood: PlantMood.calm,
    );

/// 一株「正在盛开」的成株（bloomedAt 指定）：供第二段奖励「可收集 / 兜底」测试。
Plant _bloomed(String speciesId, DateTime bloomedAt) => Plant(
      id: _kPlantId,
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: bloomedAt,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: PlantStatus.bloomed,
      plantedAt: bloomedAt,
      lastWaterAt: bloomedAt,
      bloomedAt: bloomedAt,
      bloomCount: 1,
      mood: PlantMood.calm,
    );

/// 一株枯萎中的成株（供回归 DEF-1：枯萎恢复不得清零 bloomCount）。
Plant _wilting(
  String speciesId,
  DateTime now, {
  required int bloomCount,
  required int wiltedDaysAgo,
}) =>
    Plant(
      id: _kPlantId,
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 0.4,
      growthFactor: 1.0,
      status: PlantStatus.wilting,
      plantedAt: now,
      lastWaterAt: now.subtract(Duration(days: wiltedDaysAgo)),
      wiltedAt: now.subtract(Duration(days: wiltedDaysAgo)),
      bloomCount: bloomCount,
      mood: PlantMood.thirsty,
    );

/// 一天满养护：3 次浇水（间隔 >30min）+ 1 次施肥。
Future<void> _dailyCare(
  PlantGrowthService svc,
  String plantId,
  DateTime dayStart,
) async {
  await svc.water(plantId, dayStart);
  await svc.water(plantId, dayStart.add(const Duration(minutes: 31)));
  await svc.water(plantId, dayStart.add(const Duration(minutes: 62)));
  await svc.fertilize(plantId, dayStart.add(const Duration(minutes: 93)));
}

/// 逐日推进直到复开花，返回**天数**（-1 = 上限内未开花）。
///
/// [species] 缺省用内置 [_kSpecies]；传入自定义物种表可覆盖档位（如 `rare` 物种）。
Future<int> _daysToRebloom({
  required String speciesId,
  required bool fullCare,
  List<PlantSpecies>? species,
}) async {
  final _Ctx ctx = _make(species: species);
  final DateTime start = DateTime(2026, 9, 1);
  await ctx.plants.savePlant(_rebloomPlant(speciesId, start));

  DateTime now = start;
  for (int day = 0; day < 60; day++) {
    await ctx.svc.tickAll(now);
    final Plant? cur = await ctx.plants.plant(_kPlantId);
    if (cur == null) break;
    if (cur.status == PlantStatus.bloomed) return day;
    if (fullCare && cur.status == PlantStatus.growing) {
      await _dailyCare(ctx.svc, cur.id, now);
    }
    now = now.add(const Duration(days: 1));
  }
  return -1;
}

/// 账本中 refType 为 [refType] 的条目（用于断言阳光发放）。
List<SunlightEntry> _earns(_Ctx ctx, String refType) => ctx.ledger.entries
    .where((SunlightEntry e) => e.refType == refType)
    .toList();

/// 收集某株的「开花瞬间」奖励（变更 B：开花瞬间奖励也需手动点击收集）。
///
/// 开花 tick 后服务会登记「瞬间（`due = bloomedAt`）+ 第二段（`due = +48h`）」两条；本辅助
/// 从可收集列表中挑出前者并收集（触发真实发放），供各分支断言使用。
Future<void> _collectInstant(
  _Ctx ctx,
  DateTime now, {
  String plantId = _kPlantId,
}) async {
  final Map<String, List<PendingBloomReward>> map =
      await ctx.svc.collectibleBloomRewards(now);
  final List<PendingBloomReward> list =
      map[plantId] ?? const <PendingBloomReward>[];
  final PendingBloomReward instant = list.firstWhere(
    (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant,
    orElse: () => throw StateError('无可收集的开花瞬间奖励'),
  );
  await ctx.svc.collectBloomReward(instant.id, now);
}

void main() {
  // ── ① 复开花节奏分档 ─────────────────────────────────────────────────────
  group('复开花节奏（成株后循环 Batch 1）', () {
    test('普通植物：不养护 ≈ 14 天再盛开', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_common_a',
        fullCare: false,
      );
      print('[复开花] 普通 不养护 = $days 天');
      expect(days, inInclusiveRange(13, 15));
    });

    test('普通植物：满养护（3 浇 +1 肥）≈ 7 天再盛开', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_common_a',
        fullCare: true,
      );
      print('[复开花] 普通 满养护 = $days 天');
      expect(days, inInclusiveRange(6, 8));
    });

    test('精品植物：不养护 ≈ 21 天再盛开（×1.5 更慢）', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_premium',
        fullCare: false,
      );
      print('[复开花] 精品 不养护 = $days 天');
      expect(days, inInclusiveRange(20, 22));
    });

    test('精品植物：满养护 ≈ 11 天再盛开（×1.5 更慢）', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_premium',
        fullCare: true,
      );
      print('[复开花] 精品 满养护 = $days 天');
      expect(days, inInclusiveRange(10, 12));
    });

    test('复开花常量钉死（防回退）', () {
      expect(kRebloomAutoProgressPerDay, 0.036);
      expect(kRebloomWaterProgressGain, 0.008);
      expect(kRebloomFertilizeProgressGain, 0.012);
      expect(kRebloomPremiumCycleMultiplier, 1.5);
      expect(kBloomDurationDaysPremium, 4.5);
      // 普通：0.5 / 0.036 ≈ 14；0.5 / (0.036 + 3×0.008 + 0.012) ≈ 7。
      expect(0.5 / kRebloomAutoProgressPerDay, closeTo(13.89, 0.05));
      expect(
        0.5 /
            (kRebloomAutoProgressPerDay +
                kPlantWaterMaxPerDay * kRebloomWaterProgressGain +
                kRebloomFertilizeProgressGain),
        closeTo(6.94, 0.05),
      );
    });
  });

  // ── ② 开花瞬间奖励（普通档） ─────────────────────────────────────────────
  group('开花瞬间奖励 · 普通植物', () {
    test('保底 +6☀（100%）必给，且 roll 命中「无额外」时不掉碎片/种子', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', now));
      await ctx.svc.tickAll(now);
      // 变更 B：开花不再即时入账，先断言未收集前「零入账」。
      expect(_earns(ctx, kBloomRewardRefType), isEmpty,
          reason: '变更 B：开花瞬间奖励改为手动收集，未点击前不入账');
      await _collectInstant(ctx, now);

      final List<SunlightEntry> earns = _earns(ctx, kBloomRewardRefType);
      expect(earns, hasLength(1), reason: '仅保底一笔');
      expect(earns.first.net, kBloomInstantSunlight);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
      expect(await ctx.bloomRewards.unlockedSpeciesIds(), isEmpty);
    });

    test('roll <15% → 掉 1 片精品碎片', () async {
      final _Ctx ctx = _make(random: _SeqRandom(doubles: <double>[0.10]));
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      expect(await ctx.bloomRewards.premiumFragmentBalance(), 1);
      expect(_earns(ctx, kBloomRewardRefType), hasLength(1), reason: '仅保底');
    });

    test('15% ≤ roll <20% → 掉普通物种种子（写入 unlocked_species）', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.17], ints: <int>[0]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      final Set<String> unlocked = await ctx.bloomRewards.unlockedSpeciesIds();
      expect(unlocked, hasLength(1));
      expect(unlocked.first, startsWith('sp_common'));
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
    });

    test('20% ≤ roll <40% → 掉大额阳光 10–20☀（额外一笔 earn）', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.30], ints: <int>[5]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      final List<SunlightEntry> earns = _earns(ctx, kBloomRewardRefType);
      expect(earns, hasLength(2), reason: '保底 + 大额阳光两笔');
      final double bonus = earns.map((SunlightEntry e) => e.net).reduce(max);
      expect(bonus,
          inInclusiveRange(kBloomBonusSunlightMin, kBloomBonusSunlightMax));
      expect(bonus, kBloomBonusSunlightMin + 5);
    });
  });

  // ── ② 开花瞬间奖励（精品档，含双倍碎片；变更 C 概率：碎片20/种子10/大额25/兜底45） ──
  group('开花瞬间奖励 · 精品植物', () {
    test('保底 +10☀；roll <20% 且 60% 命中 → 掉 2 片精品碎片', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.10, 0.10]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_premium', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      expect(_earns(ctx, kBloomRewardRefType).first.net,
          kBloomInstantSunlightPremium);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 2,
          reason: '精品碎片 60% 概率掉 2 片');
    });

    test('精品 roll <20% 且 40% 未命中 → 掉 1 片精品碎片', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.10, 0.99]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_premium', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      expect(await ctx.bloomRewards.premiumFragmentBalance(), 1);
    });

    test('精品 20% ≤ roll <30% → 掉精品物种种子', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.25], ints: <int>[0]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_premium', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      expect(
          await ctx.bloomRewards.unlockedSpeciesIds(), <String>['sp_premium']);
    });

    test('精品 30% ≤ roll <55% → 掉大额阳光 15–25☀', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.50], ints: <int>[0]),
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_premium', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      final List<SunlightEntry> earns = _earns(ctx, kBloomRewardRefType);
      expect(earns, hasLength(2));
      expect(earns.map((SunlightEntry e) => e.net).reduce(max),
          kBloomBonusSunlightMinPremium);
    });

    test('开花即登记两条待收集奖励：瞬间（即刻可收集，未入账）+ 第二段（due = +48h）', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 25, 8, 0);
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', now));
      await ctx.svc.tickAll(now);

      // 即刻可收集的「开花瞬间」记录（due = bloomedAt），未入账。
      final List<PendingBloomReward> dueNow =
          await ctx.bloomRewards.pendingBloomRewardsDue(now);
      expect(dueNow, hasLength(1));
      expect(dueNow.first.rewardKind, kBloomRewardPhaseInstant);
      expect(_earns(ctx, kBloomRewardRefType), isEmpty,
          reason: '变更 B：未点击收集前不入账');

      // 48h 后：瞬间 + 第二段两条均到期。
      final List<PendingBloomReward> later = await ctx.bloomRewards
          .pendingBloomRewardsDue(
              now.add(const Duration(hours: kBloomRewardDelayHours)));
      expect(later, hasLength(2), reason: '瞬间 + 第二段两条都到期');
      expect(
        later.map((PendingBloomReward r) => r.rewardKind).toSet(),
        <String>{kBloomRewardPhaseInstant, kBloomRewardKindNormal},
      );
    });
  });

  // ── ③ 第二段奖励（花开 48h 后掉落，手动收集）──────────────────────────────
  group('第二段奖励（花开 48h 后手动收集）', () {
    Future<_Ctx> withPending(Random random, {required String kind}) async {
      final _Ctx ctx = _make(random: random);
      final DateTime bloom = DateTime(2026, 9, 25, 8, 0);
      await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_1',
        plantId: 'p1',
        dueAt: bloom.add(const Duration(hours: kBloomRewardDelayHours)),
        rewardKind: kind,
      ));
      return ctx;
    }

    final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
    final DateTime dueTime =
        bloomAt.add(const Duration(hours: kBloomRewardDelayHours));

    test('未到期不可收集（collectBloomReward 抛错）', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.05]),
        kind: kBloomRewardKindNormal,
      );
      await expectLater(
        () => ctx.svc.collectBloomReward('pr_1', bloomAt),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0);
    });

    test('普通：roll <15% → 掉 1 片碎片（r=0.14）；收集后置 claimed（不可重复）', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.14]),
        kind: kBloomRewardKindNormal,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 1);
      expect(await ctx.bloomRewards.pendingBloomRewardsDue(dueTime), isEmpty,
          reason: '已领取（claimed=1）');

      // 再次收集：不得重复发放。
      await expectLater(
        () => ctx.svc.collectBloomReward('pr_1', dueTime),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 1);
    });

    test('普通：15% ≤ roll <20% → 掉本档种子（r=0.16）', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.16], ints: <int>[1]),
        kind: kBloomRewardKindNormal,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      final Set<String> unlocked = await ctx.bloomRewards.unlockedSpeciesIds();
      expect(unlocked, hasLength(1));
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 0,
          reason: '种子档不得掉碎片');
    });

    test('普通：20% ≤ roll <40% → 大额阳光 10–20☀（r=0.21 → 10）', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.21], ints: <int>[0]),
        kind: kBloomRewardKindNormal,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      final List<SunlightEntry> earns = _earns(ctx, kBloomSecondPhaseRefType);
      expect(earns, hasLength(1));
      expect(earns.first.net, kBloomBonusSunlightMin);
    });

    test('普通：roll ≥40% → 基础阳光 3–6☀（r=0.41 → 3）', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.41], ints: <int>[0]),
        kind: kBloomRewardKindNormal,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      final List<SunlightEntry> earns = _earns(ctx, kBloomSecondPhaseRefType);
      expect(earns, hasLength(1));
      expect(earns.first.net, kBloomSecondPhaseBaseSunlightMin + 0);
    });

    test('精品：roll <20% 且 50% 命中 → 掉 2 片碎片', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.10, 0.10]),
        kind: kBloomRewardKindPremium,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      expect(await ctx.bloomRewards.premiumFragmentBalance(), 2);
    });

    test('精品：20% ≤ roll <30% → 掉精品物种种子', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.25], ints: <int>[0]),
        kind: kBloomRewardKindPremium,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      expect(
          await ctx.bloomRewards.unlockedSpeciesIds(), <String>['sp_premium']);
    });

    test('精品：roll ≥55% → 基础阳光 6–10☀', () async {
      final _Ctx ctx = await withPending(
        _SeqRandom(doubles: <double>[0.90], ints: <int>[3]),
        kind: kBloomRewardKindPremium,
      );
      await ctx.svc.collectBloomReward('pr_1', dueTime);
      final List<SunlightEntry> earns = _earns(ctx, kBloomSecondPhaseRefType);
      expect(earns, hasLength(1));
      expect(earns.first.net, kBloomSecondPhaseBaseSunlightMinPremium + 3);
    });
  });

  // ── ③b 第二段奖励 · 花盆旁可收集 / 兜底（变更 A）───────────────────────────
  group('第二段奖励 · 可收集与兜底（变更 A）', () {
    final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
    final DateTime dueTime =
        bloomAt.add(const Duration(hours: kBloomRewardDelayHours));

    Future<void> insertPending(_Ctx ctx) =>
        ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
          id: 'pr_1',
          plantId: _kPlantId,
          dueAt: dueTime,
          rewardKind: kBloomRewardKindNormal,
        ));

    test('到期但花仍盛开 → tickAll 不自动发放，且列入可收集', () async {
      final _Ctx ctx = _make(random: _SeqRandom(doubles: <double>[0.90]));
      await ctx.plants.savePlant(_bloomed('sp_common_a', bloomAt));
      await insertPending(ctx);

      await ctx.svc.tickAll(dueTime);
      expect(_earns(ctx, kBloomSecondPhaseRefType), isEmpty,
          reason: '仍可收集 → 不自动发');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(dueTime);
      expect(collectible.keys, <String>[_kPlantId]);
    });

    test('手动收集 → 发放并置 claimed；收集后不再可收集', () async {
      final _Ctx ctx = _make(random: _SeqRandom(doubles: <double>[0.05]));
      await ctx.plants.savePlant(_bloomed('sp_common_a', bloomAt));
      await insertPending(ctx);

      final Map<String, List<PendingBloomReward>> before =
          await ctx.svc.collectibleBloomRewards(dueTime);
      await ctx.svc.collectBloomReward(before[_kPlantId]!.first.id, dueTime);

      expect(await ctx.bloomRewards.premiumFragmentBalance(), 1);
      expect(await ctx.svc.collectibleBloomRewards(dueTime), isEmpty);
    });

    test('花谢 / 枯萎前未收集 → tickAll 自动兜底发放', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.90], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_bloomed('sp_common_a', bloomAt));
      await insertPending(ctx);

      // 4 天后：花期（3 天）已过且 3 天未浇水 → 不再盛开。
      final DateTime wellAfter = bloomAt.add(const Duration(days: 4));
      await ctx.svc.tickAll(wellAfter);

      expect(_earns(ctx, kBloomSecondPhaseRefType), hasLength(1),
          reason: '兜底自动发放一笔基础阳光');
      expect(await ctx.bloomRewards.pendingBloomRewardsDue(wellAfter), isEmpty,
          reason: '已兜底结算并置 claimed');
      expect(await ctx.svc.collectibleBloomRewards(wellAfter), isEmpty);
    });
  });

  // ── ④ 精品碎片 · 手动解锁：已于「物种表改版」移除 ──────────────────────────
  //
  // 玄参 2026-09-27 物种表改版：旧「满 8 片手动解锁精品物种」（`unlockPremiumSpecies` /
  // `lockedPremiumSpecies` / `kPremiumFragmentUnlockThreshold`）体系被「按物种计价、直接兑换
  // 种下」取代；对应用例已迁至 `test/m3/plant_species_pricing_test.dart`（免费券 / 碎片 / 阳光
  // 计价 + 每物种仅一株 + 死亡后再种重新扣费）。

  // ── ⑤ 回归 DEF-1：枯萎恢复不得清零 bloomCount ─────────────────────────────
  group('回归 DEF-1：枯萎恢复（_maybeRecover 重建 Plant）不得丢 bloomCount', () {
    test('软枯萎（<3 天）浇 1 次恢复 → status=growing 且 bloomCount 保留', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 9, 25, 9, 0);
      await ctx.plants.savePlant(
        _wilting('sp_common_a', now, bloomCount: 3, wiltedDaysAgo: 1),
      );
      await ctx.svc.water(_kPlantId, now);

      final Plant after = (await ctx.plants.plant(_kPlantId))!;
      expect(after.status, PlantStatus.growing);
      expect(after.bloomCount, 3, reason: '枯萎浇活后退回首花速率 = DEF-1 回归');
    });

    test('硬枯萎（≥3 天）3 浇 +1 肥恢复 → bloomCount 保留（fertilize 路径）', () async {
      final _Ctx ctx = _make();
      final DateTime now = DateTime(2026, 9, 25, 9, 0);
      await ctx.plants.savePlant(
        _wilting('sp_common_a', now, bloomCount: 2, wiltedDaysAgo: 4),
      );
      await ctx.svc.water(_kPlantId, now);
      await ctx.svc.water(_kPlantId, now.add(const Duration(minutes: 31)));
      await ctx.svc.water(_kPlantId, now.add(const Duration(minutes: 62)));
      expect((await ctx.plants.plant(_kPlantId))!.status, PlantStatus.wilting,
          reason: '硬枯萎 3 浇后仍缺施肥，未恢复');

      await ctx.svc.fertilize(_kPlantId, now.add(const Duration(minutes: 93)));
      final Plant after = (await ctx.plants.plant(_kPlantId))!;
      expect(after.status, PlantStatus.growing);
      expect(after.bloomCount, 2);
    });
  });

  // ── ⑥ 档位判据：rare 也算精品档（玄参 2026-09-26 拍板）────────────────────
  group('精品档判据：rare 计入精品', () {
    test('isPremium 具体值：common→false，rare→true，legendary→true', () {
      expect(_kSpecies[0].rarity, Rarity.common);
      expect(_kSpecies[0].isPremium, isFalse, reason: 'common = 普通档');
      expect(_rareSpecies.rarity, Rarity.rare);
      expect(_rareSpecies.isPremium, isTrue, reason: 'rare 纳入精品档');
      expect(_kSpecies[2].rarity, Rarity.legendary);
      expect(_kSpecies[2].isPremium, isTrue, reason: 'legendary = 精品档');
    });

    test('rare 物种：复开花节奏按精品档 ×1.5 —— 不养护 ≈ 21 天', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_rare',
        fullCare: false,
        species: <PlantSpecies>[_rareSpecies],
      );
      print('[复开花] rare 不养护 = $days 天');
      expect(days, inInclusiveRange(20, 22));
    });

    test('rare 物种：满养护 ≈ 11 天再盛开（与 legendary 同步）', () async {
      final int days = await _daysToRebloom(
        speciesId: 'sp_rare',
        fullCare: true,
        species: <PlantSpecies>[_rareSpecies],
      );
      print('[复开花] rare 满养护 = $days 天');
      expect(days, inInclusiveRange(10, 12));
    });

    test('rare 物种：开花瞬间保底走精品档（+10☀，非普通 +6☀）', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
        species: <PlantSpecies>[_rareSpecies],
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_rare', now));
      await ctx.svc.tickAll(now);
      await _collectInstant(ctx, now);

      final List<SunlightEntry> earns = _earns(ctx, kBloomRewardRefType);
      expect(earns, hasLength(1), reason: '仅保底一笔');
      expect(earns.first.net, kBloomInstantSunlightPremium,
          reason: 'rare 应走精品保底 +10☀');
    });

    test('rare 物种：第二段待收集奖励登记为精品档（rewardKind=premium）', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
        species: <PlantSpecies>[_rareSpecies],
      );
      final DateTime now = DateTime(2026, 9, 25);
      await ctx.plants.savePlant(_readyToBloom('sp_rare', now));
      await ctx.svc.tickAll(now);

      final Map<String, List<PendingBloomReward>> due = await ctx.svc
          .collectibleBloomRewards(
              now.add(const Duration(hours: kBloomRewardDelayHours)));
      final List<PendingBloomReward> list =
          due[_kPlantId] ?? const <PendingBloomReward>[];
      final PendingBloomReward second = list.firstWhere(
        (PendingBloomReward r) => r.rewardKind != kBloomRewardPhaseInstant,
        orElse: () => throw StateError('缺第二段待收集记录'),
      );
      expect(second.rewardKind, kBloomRewardKindPremium,
          reason: 'rare 第二段奖励应为精品档');
    });
  });

  // ── ⑦ 开花瞬间奖励 · 掉落 + 手动收集（变更 B）──────────────────────────────
  group('开花瞬间奖励 · 掉落 + 手动收集（变更 B）', () {
    final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
    final DateTime due48h =
        bloomAt.add(const Duration(hours: kBloomRewardDelayHours));

    test('开花 → 登记一条可收集的 instant 记录（due = bloomedAt），且未入账', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      expect(_earns(ctx, kBloomRewardRefType), isEmpty,
          reason: '变更 B：未点击收集前不入账');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(bloomAt);
      final List<PendingBloomReward> list =
          collectible[_kPlantId] ?? const <PendingBloomReward>[];
      expect(list, hasLength(1), reason: '开花此刻仅 instant 到期');
      expect(list.first.rewardKind, kBloomRewardPhaseInstant);
      expect(list.first.dueAt, bloomAt, reason: 'instant due = bloomedAt');
    });

    test('点击 instant 气泡 → 入账一次；重复点击不再入账', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final PendingBloomReward inst =
          (await ctx.svc.collectibleBloomRewards(bloomAt))[_kPlantId]!.first;
      await ctx.svc.collectBloomReward(inst.id, bloomAt);
      expect(_earns(ctx, kBloomRewardRefType), hasLength(1),
          reason: '保底一笔（r=0.99 → 无额外）');

      // 回归 A：同一 id 再点不得抛 UNIQUE / 不得重复入账。
      await expectLater(
        () => ctx.svc.collectBloomReward(inst.id, bloomAt),
        throwsA(isA<PlantOperationException>()),
      );
      expect(_earns(ctx, kBloomRewardRefType), hasLength(1));
    });

    test('花谢前未点击 instant → tickAll 自动兜底到账一次', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);
      expect(_earns(ctx, kBloomRewardRefType), isEmpty);

      // 4 天后：花期（3 天）已过 → 不再盛开 → tickAll 兜底（instant + 第二段一并结算）。
      final DateTime later = bloomAt.add(const Duration(days: 4));
      await ctx.svc.tickAll(later);

      expect(_earns(ctx, kBloomRewardRefType), hasLength(1),
          reason: 'instant 未点击 → 自动到账一次（保底）');
      expect(await ctx.svc.collectibleBloomRewards(later), isEmpty,
          reason: '两条均已结算，无可收集残留');
    });

    test('instant 与 48h 记录互不干扰：独立登记、分别收集', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      // 开花此刻：仅 instant 可收集。
      final Map<String, List<PendingBloomReward>> atBloom =
          await ctx.svc.collectibleBloomRewards(bloomAt);
      expect(atBloom[_kPlantId], hasLength(1));
      expect(atBloom[_kPlantId]!.first.rewardKind, kBloomRewardPhaseInstant);

      // 收集 instant → 只发 instant；48h 记录仍在、未受影响。
      await ctx.svc.collectBloomReward(atBloom[_kPlantId]!.first.id, bloomAt);
      expect(_earns(ctx, kBloomRewardRefType), hasLength(1),
          reason: 'instant 入账一次');
      expect(_earns(ctx, kBloomSecondPhaseRefType), isEmpty,
          reason: '48h 记录互不干扰、仍待收集');

      // 到 48h（花仍盛开）：仅剩第二段可收集。
      final Map<String, List<PendingBloomReward>> at48 =
          await ctx.svc.collectibleBloomRewards(due48h);
      final List<PendingBloomReward> rest =
          at48[_kPlantId] ?? const <PendingBloomReward>[];
      expect(rest, hasLength(1), reason: 'instant 已领 → 仅剩第二段');
      expect(rest.first.rewardKind, kBloomRewardKindNormal);

      await ctx.svc.collectBloomReward(rest.first.id, due48h);
      expect(_earns(ctx, kBloomSecondPhaseRefType), hasLength(1),
          reason: '第二段入账一次');
      expect(await ctx.svc.collectibleBloomRewards(due48h), isEmpty);
    });
  });
}
