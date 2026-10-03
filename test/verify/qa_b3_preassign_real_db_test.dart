/// 独立复验探针 #6（qa-verify3）：**奖励物图标化 + 掉落即定奖**（v12）。
///
/// 与工程用例 `test/m3/bloom_reward_preassign_test.dart` **不同**：本探针一律跑在
/// **真实 Drift 内存库 + 真实仓储**（`PlantLocalRepository` / `SunlightLocalRepository`
/// / `SettingsLocalRepository`），且用**自建探针**证明核心不变式，不复跑工程用例。
///
/// 覆盖（对应任务 #31 第 1/2/3/4/7 条）：
///  ① 掉落即定奖：登记时写入 pending 三列；随后结算**照单发放**——「登记值」与
///     「结算返回的 outcome」及「账本/碎片/券的实际增量」三者严格相等；多种随机种子各跑一遍。
///  ② 绝不二次 roll：用**计数随机源**证明「登记后 → 结算」随机数消耗计数**冻结**（结算零 roll）。
///  ③ 哨兵兜底：手工造历史行三列 `0/0/null` → 结算退回现场 roll，**阳光 > 0 确实入账**、
///     行被回写为定奖结果、重复收集不重复入账。
///  ④ 花谢兜底出参：`tickAll(now, autoSettled: out)` 恰收对应条目、`autoSettled == true`、
///     金额与账本/碎片/券的实际增量一致；未发生兜底时 `out` 为空。
///  ⑦ 抽查：死亡全损（阳光/碎片均不退、无 `plant_death_refund` 行）、月光兰首购优惠。
library qa_b3_preassign_real_db_test;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:test/test.dart';

import '../helpers/no_hit_random.dart';

// ── 依赖替身（仅「无关」依赖用内存；被验对象一律真实库）────────────────────────

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

/// 可编排随机源（确定性）：`nextDouble` 依次取 [doubles]（循环）；`nextInt` 取 [ints]。
class _SeqRandom implements Random {
  _SeqRandom({this.doubles = const <double>[], this.ints = const <int>[]});
  final List<double> doubles;
  final List<int> ints;
  int _di = 0;
  int _ii = 0;
  @override
  double nextDouble() => doubles[_di++ % doubles.length];
  @override
  int nextInt(int max) => ints[_ii++ % ints.length] % max;
  @override
  bool nextBool() => false;
}

/// **计数随机源**：包一层固定种子 `Random`，记录 `nextDouble` / `nextInt` 调用总次数。
///
/// 用途：证明「登记时 roll 一次（计数 N）→ 结算零消耗（计数仍 N）」——即结算**不二次 roll**。
/// 这是本探针的核心仪器；下面用「哨兵行结算会消耗随机数」来**校准**仪器（证明计数有效）。
class _CountingRandom implements Random {
  _CountingRandom(int seed) : _inner = Random(seed);
  final Random _inner;
  int nextDoubleCalls = 0;
  int nextIntCalls = 0;
  int get totalCalls => nextDoubleCalls + nextIntCalls;
  @override
  double nextDouble() {
    nextDoubleCalls++;
    return _inner.nextDouble();
  }

  @override
  int nextInt(int max) {
    nextIntCalls++;
    return _inner.nextInt(max);
  }

  @override
  bool nextBool() => _inner.nextBool();
}

/// 真实库上下文。
class _Ctx {
  _Ctx(this.database, this.svc, this.plants, this.ledger);
  final db.AppDatabase database;
  final PlantGrowthService svc;
  final PlantLocalRepository
      plants; // 同时是 PlantRepository 与 BloomRewardRepository
  final SunlightLocalRepository ledger;
}

/// 建一个真实内存库 + 真实仓储 + 真实服务的上下文。
Future<_Ctx> _make({double initialBalance = 1000000, Random? random}) async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  await database.customSelect('SELECT 1').get(); // 建表（onCreate → createAll）
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
    random: random,
    // 本文件只验「掉落即定奖」，与 C26 干扰物无关：注入永不命中的桩，
    // 防止随机 roll 出杂草/虫 → 当天成长暂停 → 盛开分支被跳过（seed=2 实证）。
    weedRandom: NoHitRandom(),
  );
  return _Ctx(database, svc, plants, ledger);
}

// ── 真实 SQL 计数辅助 ────────────────────────────────────────────────────────

Future<int> _countByRefType(db.AppDatabase database, String refType) async {
  final QueryRow row = await database.customSelect(
    'SELECT COUNT(*) AS c FROM sunlight_ledgers WHERE ref_type = ?;',
    variables: <Variable>[Variable.withString(refType)],
  ).getSingle();
  return row.read<int>('c');
}

Future<int> _countByRefTypeAndRefId(
    db.AppDatabase database, String refType, String refId) async {
  final QueryRow row = await database.customSelect(
    'SELECT COUNT(*) AS c FROM sunlight_ledgers WHERE ref_type = ? AND ref_id = ?;',
    variables: <Variable>[
      Variable.withString(refType),
      Variable.withString(refId),
    ],
  ).getSingle();
  return row.read<int>('c');
}

// ── 植物构造辅助 ─────────────────────────────────────────────────────────────

const String _pid = 'p1';

/// 一株「立刻可盛开」的成株（adult + growing + progress 1.0 → tick 即 bloomed）。
Plant _readyToBloom(String speciesId, DateTime now) => Plant(
      id: _pid,
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

PendingBloomReward _instantOf(List<PendingBloomReward> list) => list.firstWhere(
      (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant,
    );

PendingBloomReward _secondOf(List<PendingBloomReward> list) => list.firstWhere(
      (PendingBloomReward r) => r.rewardKind != kBloomRewardPhaseInstant,
    );

/// 结算一条 pending，断言「登记值 == 结算返回 == 账本/碎片/券实际增量」三者一致。
Future<BloomRewardOutcome> _settleAndAssert(
  _Ctx ctx,
  PendingBloomReward row,
  DateTime at,
) async {
  final double balBefore = await ctx.ledger.balance();
  final int fragBefore = await ctx.plants.premiumFragmentBalance();
  final Set<String> unlockedBefore = await ctx.plants.unlockedSpeciesIds();

  final BloomRewardOutcome o = await ctx.svc.collectBloomReward(row.id, at);

  final double balAfter = await ctx.ledger.balance();
  final int fragAfter = await ctx.plants.premiumFragmentBalance();
  final Set<String> unlockedAfter = await ctx.plants.unlockedSpeciesIds();

  // 「结算返回的 outcome」== 「登记时写库的三列」。
  expect(o.sunlight, row.rewardSunlight, reason: '照单发放阳光（不二次 roll）');
  expect(o.fragments, row.rewardFragments, reason: '照单发放碎片（不二次 roll）');
  expect(o.seedSpeciesId, row.rewardSpeciesId, reason: '照单发放种子（不二次 roll）');

  // 「账本/碎片/券的实际增量」== 「登记时写库的三列」。
  expect(balAfter - balBefore, o.sunlight.toDouble(),
      reason: '账本实际入账阳光 == 登记值（row=${row.rewardSunlight}）');
  expect(fragAfter - fragBefore, o.fragments,
      reason: '碎片余额实际增量 == 登记值（row=${row.rewardFragments}）');
  final Set<String> seedDelta = unlockedAfter.difference(unlockedBefore);
  if (o.seedSpeciesId == null) {
    expect(seedDelta, isEmpty, reason: '无种子 → 券不增');
  } else {
    expect(seedDelta, <String>{o.seedSpeciesId!}, reason: '种子 → 恰写入该物种一张券');
  }
  return o;
}

void main() {
  // 本探针会在一处用例内建多个内存库（多种种子各一库）；关闭 drift 的多库告警噪音。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
  final DateTime due48h =
      bloomAt.add(const Duration(hours: kBloomRewardDelayHours));

  // ══════════════════════════════════════════════════════════════════════
  // ① 掉落即定奖：登记值 == 结算发放值（真实库；多种种子）
  // ══════════════════════════════════════════════════════════════════════
  group('① 掉落即定奖（真实库）', () {
    test('登记三列已写入，且与结算入账完全一致（15 个随机种子各跑一遍）', () async {
      final Set<String> branches = <String>{};
      for (int seed = 1; seed <= 15; seed++) {
        final _Ctx ctx = await _make(random: Random(seed));
        await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));
        await ctx.svc.tickAll(bloomAt);

        final List<PendingBloomReward> due =
            await ctx.plants.pendingBloomRewardsDue(due48h);
        expect(due, hasLength(2), reason: 'seed=$seed 应登记瞬间 + 第二段两条');
        final PendingBloomReward inst = _instantOf(due);
        final PendingBloomReward sec = _secondOf(due);

        // 登记时已定奖（非零值哨兵）。
        expect(inst.hasPreAssignedReward, isTrue,
            reason: 'seed=$seed instant 非哨兵');
        expect(sec.hasPreAssignedReward, isTrue,
            reason: 'seed=$seed second 非哨兵');
        expect(inst.rewardSunlight, greaterThan(0), reason: 'instant 保底阳光恒 ≥1');

        branches.add(
            'I:${inst.rewardSunlight}/${inst.rewardFragments}/${inst.rewardSpeciesId}');

        // 结算 instant：登记值 == 返回 == 账本增量。
        await _settleAndAssert(ctx, inst, bloomAt);
        // 结算第二段：登记值 == 返回 == 账本/碎片/券增量。
        await _settleAndAssert(ctx, sec, due48h);

        // 两条各恰入账一次；账本条数与档位 refType 对齐。
        final int instRows =
            await _countByRefType(ctx.database, kBloomRewardRefType);
        final int secRows =
            await _countByRefType(ctx.database, kBloomSecondPhaseRefType);
        // instant 至少一笔（保底），大额阳光档为两笔；第二段最多一笔。
        expect(instRows, greaterThanOrEqualTo(1));
        expect(secRows, lessThanOrEqualTo(1));
      }
      print('[①] 观察到的 instant 分支样本（阳光/碎片/种子）：$branches');
      expect(branches, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ② 绝不二次 roll：结算零随机消耗
  // ══════════════════════════════════════════════════════════════════════
  group('② 绝不二次 roll（计数随机源）', () {
    test('登记消耗随机数；结算 instant / 第二段均**零消耗**', () async {
      final _CountingRandom rng = _CountingRandom(7);
      final _Ctx ctx = await _make(random: rng);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      final int callsAfterRegister = rng.totalCalls;
      expect(callsAfterRegister, greaterThan(0),
          reason: '登记时确实 roll 了（否则本仪器无意义）');

      final List<PendingBloomReward> due =
          await ctx.plants.pendingBloomRewardsDue(due48h);
      final PendingBloomReward inst = _instantOf(due);
      final PendingBloomReward sec = _secondOf(due);

      await _settleAndAssert(ctx, inst, bloomAt);
      expect(rng.totalCalls, callsAfterRegister,
          reason: '结算 instant 不得消耗任何随机数（不二次 roll）');

      await _settleAndAssert(ctx, sec, due48h);
      expect(rng.totalCalls, callsAfterRegister,
          reason: '结算第二段不得消耗任何随机数（不二次 roll）');
    });

    test('仪器校准：哨兵行结算**会**消耗随机数（证明计数有效）', () async {
      final _CountingRandom rng = _CountingRandom(11);
      final _Ctx ctx = await _make(random: rng);
      // 手工造历史行（三列零值哨兵）。
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_probe',
        plantId: 'ghost',
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
      ));
      final int before = rng.totalCalls;
      await ctx.svc.collectBloomReward('legacy_probe', due48h);
      expect(rng.totalCalls, greaterThan(before),
          reason: '哨兵行必须现场 roll → 计数应增长（否则计数仪器失效）');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ③ 哨兵兜底：老 pending 奖励不丢
  // ══════════════════════════════════════════════════════════════════════
  group('③ 历史行哨兵 0/0/null 兜底（真实库）', () {
    test('哨兵行（第二段）结算 → 阳光 > 0 确实入账 + 行被回写为定奖结果 + 不重复', () async {
      // 第二段普通：r=0.99 ≥ 0.40 → 基础阳光 3–6，nextInt=0 → 3。
      final _Ctx ctx = await _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_second',
        plantId: 'ghost',
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
      ));

      // 结算前：确为哨兵。
      final db.PendingBloomRewardRow before =
          await ctx.database.bloomRewardDao.byId('legacy_second');
      expect(before.rewardSunlight, 0);
      expect(before.rewardFragments, 0);
      expect(before.rewardSpeciesId, isNull);
      expect(before.claimed, isFalse);

      final double balBefore = await ctx.ledger.balance();
      final BloomRewardOutcome o =
          await ctx.svc.collectBloomReward('legacy_second', due48h);

      expect(o.sunlight, greaterThan(0), reason: '哨兵兜底必须发出阳光（≥1）');
      expect(await ctx.ledger.balance() - balBefore, o.sunlight.toDouble(),
          reason: '哨兵兜底阳光确实入账');
      expect(await _countByRefType(ctx.database, kBloomSecondPhaseRefType), 1);

      // 行被回写为定奖结果（不再是哨兵），且 claimed。
      final db.PendingBloomRewardRow after =
          await ctx.database.bloomRewardDao.byId('legacy_second');
      expect(
          after.rewardSunlight != 0 ||
              after.rewardFragments != 0 ||
              after.rewardSpeciesId != null,
          isTrue,
          reason: '结算后应回写奖励内容（脱离零值哨兵）');
      expect(after.rewardSunlight, o.sunlight);
      expect(after.rewardFragments, o.fragments);
      expect(after.claimed, isTrue);

      // 重复收集：抛错、不重复入账、余额不变。
      final double balAfterFirst = await ctx.ledger.balance();
      await expectLater(
        () => ctx.svc.collectBloomReward('legacy_second', due48h),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await ctx.ledger.balance(), balAfterFirst, reason: '重复收集不重复入账');
      expect(await _countByRefType(ctx.database, kBloomSecondPhaseRefType), 1);
    });

    test('哨兵行（第二段）掉碎片 → 碎片入账 + 回写 rewardFragments', () async {
      // r=0.10 < 0.15 → 掉 1 片（普通档单倍）。
      final _Ctx ctx = await _make(
        random: _SeqRandom(doubles: <double>[0.10], ints: <int>[0]),
      );
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_frag',
        plantId: 'ghost',
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
      ));

      final int fragBefore = await ctx.plants.premiumFragmentBalance();
      final BloomRewardOutcome o =
          await ctx.svc.collectBloomReward('legacy_frag', due48h);
      expect(o.fragments, 1);
      expect(await ctx.plants.premiumFragmentBalance() - fragBefore, 1);

      final db.PendingBloomRewardRow after =
          await ctx.database.bloomRewardDao.byId('legacy_frag');
      expect(after.rewardFragments, 1, reason: '回写碎片数');
      expect(after.rewardSunlight, 0);
      expect(after.claimed, isTrue);
    });

    test('哨兵行（开花瞬间）结算 → 保底阳光入账 + 回写', () async {
      final _Ctx ctx = await _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_instant',
        plantId: 'ghost',
        dueAt: bloomAt,
        rewardKind: kBloomRewardPhaseInstant,
      ));

      final double balBefore = await ctx.ledger.balance();
      final BloomRewardOutcome o =
          await ctx.svc.collectBloomReward('legacy_instant', due48h);
      expect(o.sunlight, kBloomInstantSunlight, reason: '瞬间保底 +6（无额外）');
      expect(await ctx.ledger.balance() - balBefore, kBloomInstantSunlight);

      final db.PendingBloomRewardRow after =
          await ctx.database.bloomRewardDao.byId('legacy_instant');
      expect(after.rewardSunlight, kBloomInstantSunlight);
      expect(after.claimed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ④ 花谢兜底出参 autoSettled
  // ══════════════════════════════════════════════════════════════════════
  group('④ tickAll(autoSettled) 花谢自动到账出参（真实库）', () {
    test('恰收对应条目、autoSettled==true、金额 == 实际入账', () async {
      final _Ctx ctx = await _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));

      // 登记 tick：不产生兜底（花仍盛开、可收集）。
      final List<BloomRewardOutcome> none = <BloomRewardOutcome>[];
      await ctx.svc.tickAll(bloomAt, autoSettled: none);
      expect(none, isEmpty, reason: '登记 tick 不应兜底');

      final List<PendingBloomReward> due =
          await ctx.plants.pendingBloomRewardsDue(due48h);
      final PendingBloomReward inst = _instantOf(due);
      final PendingBloomReward sec = _secondOf(due);

      final double balBefore = await ctx.ledger.balance();
      final int fragBefore = await ctx.plants.premiumFragmentBalance();
      final Set<String> unlockedBefore = await ctx.plants.unlockedSpeciesIds();

      // 4 天后：花期（3 天）已过 + 3 天未浇水 → 不再盛开 → 兜底自动结算两条。
      final DateTime fade = bloomAt.add(const Duration(days: 4));
      final List<BloomRewardOutcome> auto = <BloomRewardOutcome>[];
      final List<Plant> plants = await ctx.svc.tickAll(fade, autoSettled: auto);

      expect(plants, isNotEmpty, reason: '返回类型仍为 List<Plant>（向后兼容）');
      expect(auto, hasLength(2), reason: '两条均花谢兜底 → 逐条 append');
      expect(auto.every((BloomRewardOutcome o) => o.autoSettled), isTrue,
          reason: '出参 outcome 标记 autoSettled=true');

      // 金额与账本/碎片/券的实际增量一致。
      final double balAfter = await ctx.ledger.balance();
      final int fragAfter = await ctx.plants.premiumFragmentBalance();
      final Set<String> unlockedAfter = await ctx.plants.unlockedSpeciesIds();
      final int outSun =
          auto.fold<int>(0, (int s, BloomRewardOutcome o) => s + o.sunlight);
      final int outFrag =
          auto.fold<int>(0, (int s, BloomRewardOutcome o) => s + o.fragments);
      expect(balAfter - balBefore, outSun.toDouble(),
          reason: '出参阳光合计 == 账本实际入账');
      expect(fragAfter - fragBefore, outFrag, reason: '出参碎片合计 == 碎片实际增量');
      final Set<String> seedsOut = <String>{
        for (final BloomRewardOutcome o in auto)
          if (o.seedSpeciesId != null) o.seedSpeciesId!,
      };
      expect(unlockedAfter.difference(unlockedBefore), seedsOut,
          reason: '出参种子集合 == 券实际增量');

      // 出参内容 == 登记时定的内容（只是标记为 autoSettled）。
      final Set<String> outContent = auto
          .map((BloomRewardOutcome o) =>
              '${o.sunlight}/${o.fragments}/${o.seedSpeciesId}')
          .toSet();
      final Set<String> registered = <String>{
        '${inst.rewardSunlight}/${inst.rewardFragments}/${inst.rewardSpeciesId}',
        '${sec.rewardSunlight}/${sec.rewardFragments}/${sec.rewardSpeciesId}',
      };
      expect(outContent, registered, reason: '兜底发放内容 == 登记时定奖内容');

      expect(await ctx.svc.collectibleBloomRewards(fade), isEmpty,
          reason: '两条均已结算，无残留可收集');
    });

    test('未发生兜底（花仍盛开）→ out 为空，奖励仍可收集', () async {
      final _Ctx ctx = await _make(
        random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]),
      );
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      // 48h 后花仍在花期（3 天）内 → 两条到期但可收集 → 不兜底。
      final List<BloomRewardOutcome> out = <BloomRewardOutcome>[];
      await ctx.svc.tickAll(due48h, autoSettled: out);
      expect(out, isEmpty, reason: '可收集的到期奖励不自动发放');
      final Map<String, List<PendingBloomReward>> collectible =
          await ctx.svc.collectibleBloomRewards(due48h);
      expect(collectible[_pid], hasLength(2), reason: '两条仍可收集');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ⑦ 抽查：死亡全损 + 月光兰（精英）仅碎片计价
  // ══════════════════════════════════════════════════════════════════════
  group('⑦ 抽查 · 死亡全损 / 月光兰（精英）仅碎片（真实库）', () {
    test('死亡全损：月光兰（精英）死亡后阳光与碎片余额均不变、无 plant_death_refund 行', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(20);
      final DateTime t0 = DateTime(2026, 9, 27, 8);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, t0);
      final double afterPlant = await ctx.ledger.balance();
      expect(afterPlant, 1000000, reason: '精英碎片物种不扣阳光');
      expect(await ctx.plants.premiumFragmentBalance(), 10,
          reason: '精英扣 10 碎片');
      expect(
          await _countByRefTypeAndRefId(
              ctx.database, 'plant_plant', 'species_moon_orchid'),
          0,
          reason: '精英不写阳光账本');

      // 强制枯萎 → 死亡：4 天前未浇水。
      await ctx.plants.savePlant(
          p0.copyWith(lastWaterAt: t0.subtract(const Duration(days: 4))));
      await ctx.svc.tickAll(t0); // → wilting
      expect((await ctx.plants.plant(p0.id))!.status, PlantStatus.wilting);
      await ctx.svc.tickAll(t0.add(const Duration(days: 7))); // → dead
      expect((await ctx.plants.plant(p0.id))!.status, PlantStatus.dead);

      expect(await ctx.ledger.balance(), afterPlant,
          reason: '死亡全损 → 阳光不退（旧 30% 退款已废止）');
      expect(await ctx.plants.premiumFragmentBalance(), 10,
          reason: '死亡全损 → 碎片不退');
      expect(await _countByRefType(ctx.database, 'plant_death_refund'), 0,
          reason: '死亡全损 → 不得产生 plant_death_refund 行');
      print('[⑦] 月光兰死亡：余额=${await ctx.ledger.balance()}（种植后未变）、'
          '退款行=0');
    });

    test('月光兰（精英）：首次扣 10 碎片；死后重种再扣 10 碎片、不扣阳光', () async {
      final _Ctx ctx = await _make();
      await ctx.plants.setPremiumFragmentBalance(40);
      final DateTime t0 = DateTime(2026, 9, 27, 8);
      final Plant p0 = await ctx.svc.plant('species_moon_orchid', 0, t0);
      expect(await ctx.ledger.balance(), 1000000, reason: '精英不扣阳光');
      expect(await ctx.plants.premiumFragmentBalance(), 30,
          reason: '首种扣 10 碎片');
      expect(
          await _countByRefTypeAndRefId(
              ctx.database, 'plant_plant', 'species_moon_orchid'),
          0);

      await ctx.plants.savePlant(p0.copyWith(status: PlantStatus.dead));
      final int fragBeforeReplant = await ctx.plants.premiumFragmentBalance();
      final Plant p1 = await ctx.svc
          .plant('species_moon_orchid', 0, t0.add(const Duration(days: 1)));
      expect(p1.id, isNot(p0.id));
      expect(await ctx.ledger.balance(), 1000000, reason: '重种不扣阳光');
      expect(await ctx.plants.premiumFragmentBalance(), fragBeforeReplant - 10,
          reason: '死亡全损不退款，重种重新扣 10 碎片');
      expect(
          await _countByRefTypeAndRefId(
              ctx.database, 'plant_plant', 'species_moon_orchid'),
          0,
          reason: '精英始终不写阳光账本');
      print('[⑦] 月光兰（精英）两次均扣碎片：余额=${await ctx.ledger.balance()}、'
          '碎片=${await ctx.plants.premiumFragmentBalance()}');
    });
  });
}
