/// 独立复验探针 B（qa-verify2）：奖励「零丢失、零重复」+ 反向质疑 upsert 是否掩盖重复登记
/// + 死亡退款与新计价口径的张力。
///
/// **全部跑在真实 Drift 库 + 真实仓储**（`PlantLocalRepository` / `SunlightLocalRepository`
/// / `SettingsLocalRepository`），不依赖工程内存 Fake —— 独立证据，非复跑工程用例。
///
/// 覆盖：
///  A 反向质疑：upsert 会不会掩盖「同株重复登记 → 奖励翻倍 / due 被反复重置」？
///    · 同一株一次盛开 → 真实表里**恰好 2 条**；连续多次 tickAll **不新增**；
///      已领取的两条不会因后续 tick 被重新写回。
///  B 零丢失零重复：点击收集一次 / 兜底一次 / 竞态（先点后兜底）/ 枯萎 / 删除 各恰一次；
///    账本按 refType（`bloom_reward` / `bloom_reward_24h`，值冻结）**数条数**核对。
///  C 死亡退款张力：月光兰（baseCost=400）死亡实退；碎片物种（baseCost=0）死亡实退。
library qa_b2_service_real_db_test;

import 'dart:math';

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
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:test/test.dart';

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
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 可编排随机源（确定性）。
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

/// 真实库上下文。
class _Ctx {
  _Ctx(this.database, this.svc, this.plants, this.ledger);
  final db.AppDatabase database;
  final PlantGrowthService svc;
  final PlantLocalRepository plants; // 同时是 PlantRepository 与 BloomRewardRepository
  final SunlightLocalRepository ledger;
}

/// 建一个真实内存库 + 真实仓储 + 真实服务的上下文。
Future<_Ctx> _make({double initialBalance = 1000000, Random? random}) async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  await database.customSelect('SELECT 1').get(); // 建表
  addTearDown(() => database.close());

  final PlantLocalRepository plants = PlantLocalRepository(database);
  final SunlightLocalRepository ledger = SunlightLocalRepository(database);
  final SettingsLocalRepository settings = SettingsLocalRepository(database);

  // 低年段 + 12 花盆（避免容量挡住用例）。
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
  );
  return _Ctx(database, svc, plants, ledger);
}

// ── 真实 SQL 计数辅助 ────────────────────────────────────────────────────────

Future<int> _pendingCount(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect('SELECT COUNT(*) AS c FROM pending_bloom_rewards;')
      .getSingle();
  return row.read<int>('c');
}

Future<int> _pendingUnclaimedCount(db.AppDatabase database) async {
  final QueryRow row = await database
      .customSelect(
          'SELECT COUNT(*) AS c FROM pending_bloom_rewards WHERE claimed = 0;')
      .getSingle();
  return row.read<int>('c');
}

/// 账本中 refType=[refType] 的**记账条数**（数条数，非求和）。
Future<int> _ledgerCount(db.AppDatabase database, String refType) async {
  final QueryRow row = await database.customSelect(
    'SELECT COUNT(*) AS c FROM sunlight_ledgers WHERE ref_type = ?;',
    variables: <Variable>[Variable.withString(refType)],
  ).getSingle();
  return row.read<int>('c');
}

/// 账本中 refType=[refType] 的净额合计。
Future<double> _ledgerNetSum(db.AppDatabase database, String refType) async {
  final QueryRow row = await database.customSelect(
    'SELECT COALESCE(SUM(net), 0) AS s FROM sunlight_ledgers WHERE ref_type = ?;',
    variables: <Variable>[Variable.withString(refType)],
  ).getSingle();
  return row.read<double>('s');
}

// ── 植物构造辅助 ─────────────────────────────────────────────────────────────

const String _pid = 'p1';

/// 一株「立刻可盛开」的成株（adult + growing + progress 1.0）。
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

/// 一株「正在盛开」的成株（bloomedAt 指定）。
Plant _bloomed(String speciesId, DateTime bloomedAt) => Plant(
      id: _pid,
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

/// 一株「成株成长中、未开花」的植株（进度可指定；供死亡退款用例）。
Plant _adultGrowing(String speciesId, DateTime now, {double progress = 0.5, DateTime? lastWaterAt}) =>
    Plant(
      id: 'p_$speciesId',
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: progress,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: lastWaterAt ?? now,
      mood: PlantMood.calm,
    );

PlantSpecies _sp(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

/// 取可收集列表中第一条「开花瞬间」奖励并收集。
Future<void> _collectInstant(_Ctx ctx, DateTime now) async {
  final Map<String, List<PendingBloomReward>> map =
      await ctx.svc.collectibleBloomRewards(now);
  final PendingBloomReward inst = map[_pid]!.firstWhere(
    (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant,
  );
  await ctx.svc.collectBloomReward(inst.id, now);
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // A · 反向质疑：upsert 是否掩盖「同株重复登记 → 奖励翻倍 / due 反复重置」
  // ══════════════════════════════════════════════════════════════════════
  group('A · 反向质疑 upsert 掩盖重复登记', () {
    test('同一株一次盛开 → 真实表里恰 3 条 pending（instant + 花期两轮晨露，2026-10-07）', () async {
      final _Ctx ctx = await _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', now));

      await ctx.svc.tickAll(now);

      // 花期 3 天（09-27 08:00 → 09-30 08:00），开花恰在 08:00 → 晨露 09-28 / 09-29
      // 两天（09-30 08:00 == 花谢时刻不计）+ instant = 3 条。
      expect(await _pendingCount(ctx.database), 3,
          reason: '一次盛开登记 instant + 每日 8 点晨露（花期两轮）');

      final List<PendingBloomReward> due =
          await ctx.plants.pendingBloomRewardsDue(now.add(const Duration(hours: kBloomRewardDelayHours)));
      expect(
        due.map((PendingBloomReward r) => r.rewardKind).toSet(),
        <String>{kBloomRewardPhaseInstant, kBloomRewardKindNormal},
      );
      final PendingBloomReward inst = due.firstWhere(
          (PendingBloomReward r) => r.rewardKind == kBloomRewardPhaseInstant);
      expect(inst.dueAt, now, reason: 'instant due = bloomedAt');
      final List<PendingBloomReward> mornings = due
          .where((PendingBloomReward r) => r.rewardKind != kBloomRewardPhaseInstant)
          .toList();
      expect(mornings.map((PendingBloomReward r) => r.dueAt).toSet(),
          <DateTime>{
            DateTime(2026, 9, 28, 8),
            DateTime(2026, 9, 29, 8),
          },
          reason: '晨露 = 花期内每天 08:00（玄参 2026-10-07 口径）');
    });

    test('连续多次 tickAll（花一直盛开）→ pending 条数恒为 3，不重复登记', () async {
      final _Ctx ctx = await _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', now));

      await ctx.svc.tickAll(now);
      for (int i = 0; i < 8; i++) {
        await ctx.svc.tickAll(now.add(Duration(minutes: i)));
      }
      expect(await _pendingCount(ctx.database), 3,
          reason: '重复 tick 不得新增 pending（否则奖励翻倍）');
    });

    test('已收集的全部三条，后续 tick 不会被 upsert 重新写回（不复活已领奖励）', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', now));
      await ctx.svc.tickAll(now);

      // 收集 instant（花仍盛开）。
      await _collectInstant(ctx, now);
      // 到 +48h 逐条收集两条晨露。
      final DateTime due48 = now.add(const Duration(hours: kBloomRewardDelayHours));
      final Map<String, List<PendingBloomReward>> at48 =
          await ctx.svc.collectibleBloomRewards(due48);
      for (final PendingBloomReward r in at48[_pid]!) {
        await ctx.svc.collectBloomReward(r.id, due48);
      }

      expect(await _pendingUnclaimedCount(ctx.database), 0, reason: '三条都已领');
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1);
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 2,
          reason: '两轮晨露各入账一次');

      // 再 tick 多次（花仍盛开）：不得把已领记录改回未领 / 不新增。
      for (int i = 0; i < 5; i++) {
        await ctx.svc.tickAll(due48.add(Duration(minutes: i)));
      }
      expect(await _pendingCount(ctx.database), 3, reason: '条数不变');
      expect(await _pendingUnclaimedCount(ctx.database), 0, reason: '不被写回应领');
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1);
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 2);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B · 零丢失零重复（点击 / 兜底 / 竞态 / 枯萎 / 删除）
  // ══════════════════════════════════════════════════════════════════════
  group('B · 奖励零丢失零重复', () {
    test('B1 点击收集 instant → 恰入账一次；重复点击不再入账', () async {
      final _Ctx ctx = await _make(random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime now = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', now));
      await ctx.svc.tickAll(now);

      final PendingBloomReward inst =
          (await ctx.svc.collectibleBloomRewards(now))[_pid]!.first;
      await ctx.svc.collectBloomReward(inst.id, now);
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1);
      expect(await _ledgerNetSum(ctx.database, kBloomRewardRefType),
          kBloomInstantSunlight.toDouble());

      // 重复点击同一 id → 必须抛「已领取」，账本条数不变。
      await expectLater(
        () => ctx.svc.collectBloomReward(inst.id, now),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1,
          reason: '同一 id 只发一次');
    });

    test('B2 点击收集第二段 → 恰入账一次；重复点击不再入账', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime boom = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_bloomed('species_sunflower', boom));
      final DateTime due = boom.add(const Duration(hours: kBloomRewardDelayHours));
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
          id: 'rp', plantId: _pid, dueAt: due, rewardKind: kBloomRewardKindNormal));

      final Map<String, List<PendingBloomReward>> at =
          await ctx.svc.collectibleBloomRewards(due);
      await ctx.svc.collectBloomReward(at[_pid]!.first.id, due);
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1);

      await expectLater(
        () => ctx.svc.collectBloomReward(at[_pid]!.first.id, due),
        throwsA(isA<PlantOperationException>()),
      );
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1);
    });

    test('B3 instant 未点击 → 花谢后兜底自动到账恰一次（多次 tick 不翻倍）', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime boom = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', boom));
      await ctx.svc.tickAll(boom);
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 0,
          reason: '未点击前不入账');

      // 4 天后：花期（3 天）已过 + 3 天未浇水 → 不再盛开 → 兜底。
      final DateTime fade = boom.add(const Duration(days: 4));
      await ctx.svc.tickAll(fade);
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1,
          reason: 'instant 兜底恰一次');
      // instant + 两轮晨露此刻都已到期且不再盛开 → 都兜底。
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 2,
          reason: '花期两轮晨露各兜底一次');

      // 再 tick：不得翻倍。
      await ctx.svc.tickAll(fade.add(const Duration(days: 1)));
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1);
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 2);
    });

    test('B4 竞态：先点击 instant 收集，紧接着花谢兜底 → 不二次入账', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime boom = DateTime(2026, 9, 27, 8);
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', boom));
      await ctx.svc.tickAll(boom);

      // 立即点击 instant（此时花还盛开）。
      await _collectInstant(ctx, boom);
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1);

      // 紧接着触发花谢兜底（4 天后 tick）。
      final DateTime fade = boom.add(const Duration(days: 4));
      await ctx.svc.tickAll(fade);
      expect(await _ledgerCount(ctx.database, kBloomRewardRefType), 1,
          reason: '竞态下 instant 仍只发一次（同一 id 去重）');
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 2,
          reason: '两轮晨露在此之前未领 → 兜底各恰一次');
    });

    test('B5 枯萎路径：第二段到期前枯萎 → 兜底恰一次', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime boom = DateTime(2026, 9, 27, 8);
      // 盛开但 3 天前就没浇水 → 一 tick 即枯萎。
      final Plant w = _bloomed('species_sunflower', boom).copyWith(
        lastWaterAt: boom.subtract(const Duration(days: 4)),
      );
      await ctx.plants.savePlant(w);
      final DateTime due = boom.add(const Duration(hours: kBloomRewardDelayHours));
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
          id: 'rp', plantId: _pid, dueAt: due, rewardKind: kBloomRewardKindNormal));

      final DateTime when = boom.add(const Duration(days: 5));
      await ctx.svc.tickAll(when); // 枯萎 → 不再盛开 → 兜底
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1);
      await ctx.svc.tickAll(when.add(const Duration(days: 1)));
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1,
          reason: '枯萎兜底不得重复');
    });

    test('B6 植物被删除路径：到期后 tickAll → 兜底恰一次', () async {
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.99], ints: <int>[0]));
      final DateTime boom = DateTime(2026, 9, 27, 8);
      final DateTime due = boom.add(const Duration(hours: kBloomRewardDelayHours));
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
          id: 'rp', plantId: 'ghost', dueAt: due, rewardKind: kBloomRewardKindNormal));

      await ctx.svc.tickAll(due); // 无此植物 → 不可收集 → 兜底
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1);
      await ctx.svc.tickAll(due.add(const Duration(days: 2)));
      expect(await _ledgerCount(ctx.database, kBloomSecondPhaseRefType), 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C · 死亡全损 × 新计价口径（玄参 2026-09-27 拍板：死亡不退任何资源）
  // ══════════════════════════════════════════════════════════════════════
  group('C · 死亡全损 × 新计价口径', () {
    test('C1 月光兰死亡：死亡全损 → 实退 0（不写 plant_death_refund 行）', () async {
      final _Ctx ctx = await _make();
      final DateTime t0 = DateTime(2026, 9, 27, 8);
      final Plant p = _adultGrowing('species_moon_orchid', t0,
          progress: 0.5, lastWaterAt: t0.subtract(const Duration(days: 4)));
      await ctx.plants.savePlant(p);

      await ctx.svc.tickAll(t0); // → wilting
      expect((await ctx.plants.plant(p.id))!.status, PlantStatus.wilting);
      final DateTime deadAt = t0.add(const Duration(days: 7));
      await ctx.svc.tickAll(deadAt); // → dead
      expect((await ctx.plants.plant(p.id))!.status, PlantStatus.dead);

      // 死亡全损（玄参 2026-09-27）→ 不产生任何 plant_death_refund 行、余额不退。
      final double refund = await _ledgerNetSum(ctx.database, 'plant_death_refund');
      expect(refund, 0, reason: '死亡全损 → 实退 0（旧口径 (400×30%)=120 已废止）');
      print('[C1] 月光兰 死亡全损 → 死亡退款=$refund ☀（旧口径 120 已废止）');
    });

    test('C2 碎片物种（精英/普通）死亡：baseCost=0 → 实退 0 阳光（无账本行）', () async {
      for (final String id in <String>['species_jade_hydrangea', 'species_tomato']) {
        final _Ctx ctx = await _make();
        final DateTime t0 = DateTime(2026, 9, 27, 8);
        final PlantSpecies sp = _sp(id);
        final Plant p = _adultGrowing(id, t0,
            progress: 0.5,
            lastWaterAt: t0.subtract(const Duration(days: 4)));
        await ctx.plants.savePlant(p);

        await ctx.svc.tickAll(t0);
        await ctx.svc.tickAll(t0.add(const Duration(days: 7)));
        expect((await ctx.plants.plant(p.id))!.status, PlantStatus.dead);

        final double refund =
            await _ledgerNetSum(ctx.database, 'plant_death_refund');
        expect(refund, 0, reason: '${sp.name} baseCost=0 → 死亡退款 0');
        print('[C2] ${sp.name} baseCost=${sp.baseCostLow} 死亡退款=$refund ☀');
      }
    });
  });
}
