/// 「掉落即定奖」领域单测（玄参 2026-09-27，任务 #6 / v12）。
///
/// 覆盖 5 类：
///  ① **登记时定奖**：`tickAll` 新盛开登记两条 pending 时**当场 roll** 并写库（三列非零值哨兵）；
///  ② **按存定奖、不二次 roll**：结算照单发放，即使随机源「再 roll 会给出不同结果」也不改发放；
///  ③ **历史行哨兵兜底不丢且回写**：`0/0/null` 行结算时现场 roll + `updatePendingRewardContent` 回写；
///  ④ **`tickAll` 可选出参 `autoSettled`**：花谢兜底自动到账逐条 append（`autoSettled: true`），
///     不改返回类型（仍 `List<Plant>`）；
///  ⑤ **重复种子**：允许掉已持券物种的种子（登记仍定种子、不再兜底阳光）；
///     结算时自动分解为植物碎片（普通 3 / 精英 5），券不重复写（玄参 2026-09-29）。
///
/// 纯 Dart：仓储以内存 Fake 实现，随机源以可编排的 [_SeqRandom] 注入（确定性、不 flaky）。
library bloom_reward_preassign_test;

import 'dart:math';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
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
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
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

/// 记录 `updatePendingRewardContent` 调用的内存仓储（验证「哨兵回写」）。
class _RecordingBloomRepo extends InMemoryBloomRewardRepository {
  ({String id, int sunlight, int fragments, String? speciesId})? lastWrite;

  @override
  Future<void> updatePendingRewardContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  }) async {
    lastWrite = (
      id: id,
      sunlight: rewardSunlight,
      fragments: rewardFragments,
      speciesId: rewardSpeciesId,
    );
    await super.updatePendingRewardContent(
      id: id,
      rewardSunlight: rewardSunlight,
      rewardFragments: rewardFragments,
      rewardSpeciesId: rewardSpeciesId,
    );
  }
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
    if (doubles.isEmpty) throw StateError('_SeqRandom.nextDouble 无可用序列');
    return doubles[_di++ % doubles.length];
  }

  @override
  int nextInt(int max) {
    if (ints.isEmpty) throw StateError('_SeqRandom.nextInt 无可用序列');
    return ints[_ii++ % ints.length] % max;
  }

  @override
  bool nextBool() => false;
}

// ── 组装辅助 ────────────────────────────────────────────────────────────────

const String _kPlantId = 'p1';

/// 物种表：2 个普通（common）+ 1 个精品（legendary）。
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

class _Ctx {
  _Ctx(this.svc, this.plants, this.ledger, this.bloom);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final _MemLedger ledger;
  final InMemoryBloomRewardRepository bloom;
}

_Ctx _make({Random? random, List<PlantSpecies>? species}) {
  final _MemPlantRepo plants = _MemPlantRepo(species ?? _kSpecies);
  final _MemLedger ledger = _MemLedger();
  final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: bloom,
    random: random,
    weedRandom: NoHitRandom(),
  );
  return _Ctx(svc, plants, ledger, bloom);
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

/// 一株「正在盛开」的成株（bloomedAt 指定）。
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

List<SunlightEntry> _earns(_MemLedger ledger, String refType) =>
    ledger.entries.where((SunlightEntry e) => e.refType == refType).toList();

PendingBloomReward _instantOf(List<PendingBloomReward> list) => list.firstWhere(
      (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant,
    );

void main() {
  final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
  final DateTime due48h =
      bloomAt.add(const Duration(hours: kBloomRewardDelayHours));

  // ── ① 登记时定奖 ─────────────────────────────────────────────────────────
  group('① 登记时定奖（掉落即定奖）', () {
    test('新盛开 → 登记即定奖落库（非零值哨兵）：instant + 花期两轮晨露（2026-10-07）', () async {
      // instant r=0.99 → 无额外（保底 6）；晨露每轮 r=0.99 → 基础阳光 3–6（nextInt=0 → 3）。
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final List<PendingBloomReward> due =
          await ctx.bloom.pendingBloomRewardsDue(due48h);
      // 开花 08:00 → 晨露首轮 = 次日 08:00；花期 3 天（至 09-28 08:00）→
      // 09-26 / 09-27 两轮晨露（09-28 08:00 == 花谢时刻不计）+ instant = 3 条。
      expect(due, hasLength(3), reason: '瞬间 + 两轮晨露');

      final PendingBloomReward instant = _instantOf(due);
      expect(instant.hasPreAssignedReward, isTrue, reason: '登记时已 roll → 非零值哨兵');
      expect(instant.rewardSunlight, kBloomInstantSunlight,
          reason: 'r=0.99 → 无额外，仅保底 +6');
      expect(instant.rewardFragments, 0);
      expect(instant.rewardSpeciesId, isNull);

      final List<PendingBloomReward> mornings = due
          .where((PendingBloomReward r) => r.rewardKind != kBloomRewardPhaseInstant)
          .toList();
      expect(mornings, hasLength(2));
      for (final PendingBloomReward r in mornings) {
        expect(r.hasPreAssignedReward, isTrue);
        expect(r.rewardSunlight, kBloomSecondPhaseBaseSunlightMin + 0,
            reason: '晨露 r=0.99 → 基础阳光 3–6，nextInt=0 → 3');
        expect(r.dueAt.hour, 8, reason: '晨露固定 08:00 到期');
      }
    });

    test('开花瞬间掉碎片 → 登记即写入 rewardFragments（+ 保底阳光）', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.10], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final PendingBloomReward instant =
          _instantOf(await ctx.bloom.pendingBloomRewardsDue(due48h));
      expect(instant.rewardFragments, 1, reason: 'r=0.10 < 15% → 掉 1 片');
      expect(instant.rewardSunlight, kBloomInstantSunlight,
          reason: '碎片档仍含保底阳光');
    });
  });

  // ── ② 按存定奖、不二次 roll ──────────────────────────────────────────────
  group('② 按存定奖（结算不二次 roll）', () {
    test('登记后收集 → 发放 == 登记时定的内容（随机源「再 roll 会不同」也不改）', () async {
      // 登记：instant(r=0.99 → 无额外 → 6)；第二段(r=0.99 → 基础 3)。
      // 若收集时**再 roll**，会读到第 3 个 double = 0.10 → 掉 1 片（与期望不符）。
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99, 0.99, 0.10], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final PendingBloomReward instant =
          _instantOf(await ctx.bloom.pendingBloomRewardsDue(due48h));
      final BloomRewardOutcome s =
          await ctx.svc.collectBloomReward(instant.id, due48h);
      expect(s.sunlight, kBloomInstantSunlight, reason: '照单发放登记时定的 +6');
      expect(s.fragments, 0, reason: '不得二次 roll 掉碎片');
      expect(await ctx.bloom.premiumFragmentBalance(), 0);
      expect(_earns(ctx.ledger, kBloomRewardRefType), hasLength(1));
      expect(_earns(ctx.ledger, kBloomRewardRefType).first.net,
          kBloomInstantSunlight);

      // 已领取 → 再收集抛错、不重复发放。
      await expectLater(
        () => ctx.svc.collectBloomReward(instant.id, due48h),
        throwsA(isA<PlantOperationException>()),
      );
      expect(_earns(ctx.ledger, kBloomRewardRefType), hasLength(1));
    });
  });

  // ── ③ 历史行哨兵兜底不丢且回写 ───────────────────────────────────────────
  group('③ 历史行（零值哨兵 0/0/null）兜底 + 回写', () {
    test('哨兵行结算 → 现场 roll 发放 + updatePendingRewardContent 回写该行', () async {
      final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
      final _MemLedger ledger = _MemLedger();
      final _RecordingBloomRepo bloom = _RecordingBloomRepo();
      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: _MemSettingsRepo(),
        bloomRewards: bloom,
        random: _SeqRandom(doubles: <double>[0.14], ints: <int>[0]),
        weedRandom: NoHitRandom(),
      );
      // 历史行：三列默认零值哨兵。
      await bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_1',
        plantId: _kPlantId,
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
      ));

      final BloomRewardOutcome s =
          await svc.collectBloomReward('legacy_1', due48h);
      expect(s.fragments, 1, reason: 'r=0.14 < 15% → 掉 1 片（现场 roll）');
      expect(await bloom.premiumFragmentBalance(), 1);

      expect(bloom.lastWrite, isNotNull, reason: '哨兵行必须回写');
      expect(bloom.lastWrite!.id, 'legacy_1');
      expect(bloom.lastWrite!.fragments, 1, reason: '回写内容 == 实际发放');
    });

    test('哨兵行回写后不重发：二次收集抛错（已 claimed）', () async {
      final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
      final _MemLedger ledger = _MemLedger();
      final _RecordingBloomRepo bloom = _RecordingBloomRepo();
      final PlantGrowthService svc = PlantGrowthService(
        plants: plants,
        focus: _NoFocusRepo(),
        ledger: ledger,
        settings: _MemSettingsRepo(),
        bloomRewards: bloom,
        random: _SeqRandom(doubles: <double>[0.21], ints: <int>[0]),
        weedRandom: NoHitRandom(),
      );
      await bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_2',
        plantId: _kPlantId,
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
      ));

      await svc.collectBloomReward('legacy_2', due48h);
      // r=0.21 → 大额阳光 10–20（nextInt=0 → 10）。
      expect(_earns(ledger, kBloomSecondPhaseRefType), hasLength(1));
      expect(_earns(ledger, kBloomSecondPhaseRefType).first.net,
          kBloomBonusSunlightMin + 0);

      await expectLater(
        () => svc.collectBloomReward('legacy_2', due48h),
        throwsA(isA<PlantOperationException>()),
      );
      expect(_earns(ledger, kBloomSecondPhaseRefType), hasLength(1),
          reason: '每行仅发一次');
    });
  });

  // ── ④ tickAll 可选出参 autoSettled ───────────────────────────────────────
  group('④ tickAll 可选出参 autoSettled（花谢自动到账）', () {
    test('花谢未收集 → tickAll(autoSettled) 逐条 append（autoSettled=true）', () async {
      final _Ctx ctx = _make(
        random: _SeqRandom(doubles: <double>[0.99, 0.99], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_bloomed('sp_common_a', bloomAt));
      // 手动登记两条（模拟已在库中）；此处只关心「是否自动到账被记入出参」。
      await ctx.bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_instant',
        plantId: _kPlantId,
        dueAt: bloomAt,
        rewardKind: kBloomRewardPhaseInstant,
      ));
      await ctx.bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_second',
        plantId: _kPlantId,
        dueAt: due48h,
        rewardKind: kBloomRewardKindNormal,
      ));

      // 4 天后：花期已过 + 3 天未浇水 → 不再盛开 → 两条都兜底自动结算。
      final DateTime wellAfter = bloomAt.add(const Duration(days: 4));
      final List<BloomRewardOutcome> auto = <BloomRewardOutcome>[];
      final List<Plant> plants =
          await ctx.svc.tickAll(wellAfter, autoSettled: auto);

      expect(plants, isNotEmpty, reason: '返回类型仍为 List<Plant>（向后兼容）');
      expect(auto, hasLength(2), reason: '两条均花谢兜底 → 逐条 append');
      expect(auto.every((BloomRewardOutcome o) => o.autoSettled), isTrue,
          reason: '出参 outcome 标记 autoSettled=true');
      expect(await ctx.svc.collectibleBloomRewards(wellAfter), isEmpty);
    });

    test('无花谢兜底 → 不传出参亦不报错（向后兼容）', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      final List<Plant> plants = await ctx.svc.tickAll(bloomAt);
      expect(plants, hasLength(1));
    });
  });

  // ── ⑤ 重复种子：允许掉落 + 结算自动分解 ──────────────────────────────────
  group('⑤ 重复种子：允许掉落，结算时自动分解为碎片（2026-09-29）', () {
    test('普通档物种全部已持券 + seed 分支 → 登记仍定种子（允许重复，不再兜底阳光）', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.17], ints: <int>[0]));
      // 两个 common 均持券。
      await ctx.bloom.unlockSpecies('sp_common_a');
      await ctx.bloom.unlockSpecies('sp_common_b');
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final PendingBloomReward instant =
          _instantOf(await ctx.bloom.pendingBloomRewardsDue(due48h));
      // r=0.17 ∈ [15%,20%) → seed 分支；候选 = 全部普通物种（不再排除已持券）
      // → nextInt=0 → sp_common_a（重复种子，允许掉落）。
      expect(instant.rewardSpeciesId, 'sp_common_a',
          reason: '2026-09-29 起：已持券物种仍可被 roll 中（重复掉落）');
      expect(instant.rewardSunlight, kBloomInstantSunlight,
          reason: '种子分支不再叠加兜底大额阳光，仅保底 6');
      expect(instant.hasPreAssignedReward, isTrue);
    });

    test('收集重复种子（普通档）→ 自动分解为 3 植物碎片，券不重复写', () async {
      final _Ctx ctx =
          _make(random: _SeqRandom(doubles: <double>[0.17], ints: <int>[0]));
      await ctx.bloom.unlockSpecies('sp_common_a');
      await ctx.bloom.unlockSpecies('sp_common_b');
      await ctx.plants.savePlant(_readyToBloom('sp_common_a', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final PendingBloomReward instant =
          _instantOf(await ctx.bloom.pendingBloomRewardsDue(due48h));
      await ctx.svc.collectBloomReward(instant.id, due48h);

      final Set<String> coupons = await ctx.bloom.unlockedSpeciesIds();
      expect(coupons, <String>{'sp_common_a', 'sp_common_b'},
          reason: '券不重复写、也不被结算误消耗（仍恰两张）');
      expect(await ctx.bloom.premiumFragmentBalance(),
          kDuplicateSeedDecomposeFragmentsCommon,
          reason: '重复种子自动分解为 3 片（普通档）');
    });

    test('收集重复种子（精英档，预置定奖行）→ 自动分解为 5 植物碎片', () async {
      final _Ctx ctx = _make();
      await ctx.bloom.unlockSpecies('sp_premium');
      await ctx.plants.savePlant(_bloomed('sp_premium', bloomAt));
      await ctx.bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_dup_premium',
        plantId: _kPlantId,
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindPremium,
        rewardSpeciesId: 'sp_premium',
      ));

      final BloomRewardOutcome o = await ctx.svc.collectBloomReward(
          'pr_dup_premium', bloomAt.add(const Duration(hours: 1)));

      expect(o.decomposedSeedSpeciesId, 'sp_premium',
          reason: '结果标记「由重复种子分解而来」，供 UI 文案');
      expect(o.seedSpeciesId, isNull, reason: '分解后不再以种子形态发放');
      expect(o.fragments, kDuplicateSeedDecomposeFragmentsPremium,
          reason: '重复种子自动分解为 5 片（精英档）');
      expect(await ctx.bloom.unlockedSpeciesIds(), <String>{'sp_premium'},
          reason: '券不重复写');
      expect(await ctx.bloom.premiumFragmentBalance(),
          kDuplicateSeedDecomposeFragmentsPremium);
    });

    test('未持券物种的种子照常发券（分解规则不误伤）', () async {
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_bloomed('sp_common_a', bloomAt));
      await ctx.bloom.insertPendingBloomReward(PendingBloomReward(
        id: 'pr_new_seed',
        plantId: _kPlantId,
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
        rewardSpeciesId: 'sp_common_b',
      ));

      final BloomRewardOutcome o = await ctx.svc.collectBloomReward(
          'pr_new_seed', bloomAt.add(const Duration(hours: 1)));

      expect(o.seedSpeciesId, 'sp_common_b', reason: '未持券 → 照常发券');
      expect(o.decomposedSeedSpeciesId, isNull);
      expect(await ctx.bloom.unlockedSpeciesIds(), <String>{'sp_common_b'});
    });
  });
}
