/// 探针：礼物盒根因验证（general-purpose-1 / 任务 #？）。
///
/// 目的：用**真实 Drift 内存库**（非 InMemoryBloomRewardRepository）验证「奖励头顶图标显示
/// 礼物盒」bug 的根因——到底是「v12 之前旧数据零值哨兵」还是「v12 新开花没把三列落库」。
///
/// 两条断言：
///  (a) 全新 v12 库：插入一株 common 物种植物并 tick 到开花（触发 `_enqueueBloomRewards`），
///      从**真实库**读回 pending 行，断言 `rewardSunlight >= 1`（instant 保底 ≥1）且
///      `rewardFragments`/`rewardSpeciesId` 至少其一非空；再对读回的 `PendingBloomReward`
///      调 `rewardIconSpecsFor`，断言**不含** `gift`（显示阳光/碎片/种子明细）。
///  (b) 旧数据哨兵：往真实库手写一条 `0/0/null` 的 pending 行（模拟 v12 之前登记的旧行），
///      断言 `rewardIconSpecsFor` 返回单个 `gift`（哨兵）。
///
/// 结论判据：
///  · 若 (a) 通过 → 新开花已正确落库三列，用户看到的礼物盒**只可能来自旧数据哨兵**；
///  · 若 (a) 失败（读回三列全零）→ 真实写入链路有 bug（丢列）。
library giftbox_probe_test;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
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
  double nextDouble() =>
      doubles.isEmpty ? 0.99 : doubles[_di++ % doubles.length];
  @override
  int nextInt(int max) => ints.isEmpty ? 0 : ints[_ii++ % ints.length] % max;
  @override
  bool nextBool() => false;
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
    weedRandom: NoHitRandom(),
  );
  return _Ctx(database, svc, plants, ledger);
}

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

/// 真实库读回的 [db.PendingBloomRewardRow] → 领域 [PendingBloomReward]（与真实仓储映射一致）。
PendingBloomReward _toReward(db.PendingBloomRewardRow row) =>
    PendingBloomReward(
      id: row.id,
      plantId: row.plantId,
      dueAt: row.dueAt,
      rewardKind: row.rewardKind,
      claimed: row.claimed,
      rewardSunlight: row.rewardSunlight,
      rewardFragments: row.rewardFragments,
      rewardSpeciesId: row.rewardSpeciesId,
    );

void main() {
  // 本探针会建多个内存库；关闭 drift 的多库告警噪音。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final DateTime bloomAt = DateTime(2026, 9, 25, 8, 0);
  final DateTime farFuture = DateTime(2030);

  // ══════════════════════════════════════════════════════════════════════
  // (a) 全新 v12 库：开花写入三列 → 头顶图标显示明细（无礼物盒）
  // ══════════════════════════════════════════════════════════════════════
  group('(a) 全新 v12 库开花 → 真实库读回三列非空 → 头顶图标无礼物盒', () {
    test('确定性单株：instant 保底阳光≥1 且至少一列非空，rewardIconSpecsFor 不含 gift', () async {
      // instant r=0.10 < 15% → 掉 1 片（+ 保底阳光）；second r=0.99 → 基础阳光。
      final _Ctx ctx = await _make(
          random: _SeqRandom(doubles: <double>[0.10, 0.99], ints: <int>[0]));
      await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));
      await ctx.svc.tickAll(bloomAt);

      // 从真实库读回（real Drift read path），不限 due（farFuture）。
      final List<db.PendingBloomRewardRow> rows =
          await ctx.database.bloomRewardDao.pendingDue(farFuture);
      expect(rows, hasLength(3), reason: '应登记瞬间 + 花期两轮晨露（2026-10-07 每日 8 点口径）');

      final db.PendingBloomRewardRow instantRow = rows.firstWhere(
          (db.PendingBloomRewardRow r) =>
              r.rewardKind == kBloomRewardPhaseInstant);
      final PendingBloomReward instant = _toReward(instantRow);

      // 断言：instant 保底阳光 ≥1。
      expect(instant.rewardSunlight, greaterThanOrEqualTo(1),
          reason: 'instant 保底阳光恒 ≥1');
      // 断言：rewardFragments / rewardSpeciesId 至少其一非空。
      expect(instant.rewardFragments != 0 || instant.rewardSpeciesId != null,
          isTrue,
          reason: '至少一列非空（此处为碎片）');
      // 不变式：非哨兵。
      expect(instant.hasPreAssignedReward, isTrue, reason: '新开花非哨兵');

      // 断言：rewardIconSpecsFor 不含礼物盒。
      final List<RewardIconSpec> icons = rewardIconSpecsFor(instant);
      final bool hasGift =
          icons.any((RewardIconSpec s) => s.kind == RewardIconKind.gift);
      expect(hasGift, isFalse, reason: '新开花不显示礼物盒，应显示阳光/碎片明细');
      print('(a) 确定性 instant 行实际值：'
          'sunlight=${instant.rewardSunlight}, fragments=${instant.rewardFragments}, '
          'speciesId=${instant.rewardSpeciesId} → icons=${icons.map((s) => s.kind.name)}');
    });

    test('多随机种子（1..20）加强：每条 instant 均 rewardSunlight≥1 且不含 gift', () async {
      int giftSeen = 0;
      for (int seed = 1; seed <= 20; seed++) {
        final _Ctx ctx = await _make(random: Random(seed));
        await ctx.plants.savePlant(_readyToBloom('species_sunflower', bloomAt));
        await ctx.svc.tickAll(bloomAt);

        final List<db.PendingBloomRewardRow> rows =
            await ctx.database.bloomRewardDao.pendingDue(farFuture);
        expect(rows, hasLength(3), reason: 'seed=$seed 应登记瞬间 + 两轮晨露（2026-10-07）');

        final db.PendingBloomRewardRow instantRow = rows.firstWhere(
            (db.PendingBloomRewardRow r) =>
                r.rewardKind == kBloomRewardPhaseInstant);
        final PendingBloomReward instant = _toReward(instantRow);

        expect(instant.rewardSunlight, greaterThanOrEqualTo(1),
            reason: 'seed=$seed instant 保底阳光≥1');
        expect(instant.hasPreAssignedReward, isTrue, reason: 'seed=$seed 非哨兵');
        final bool hasGift = rewardIconSpecsFor(instant)
            .any((RewardIconSpec s) => s.kind == RewardIconKind.gift);
        if (hasGift) giftSeen++;
      }
      expect(giftSeen, 0, reason: '20 个种子中无一显示礼物盒 → 新开花三列均正确落库');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // (b) 旧数据哨兵 0/0/null → 头顶图标显示礼物盒
  // ══════════════════════════════════════════════════════════════════════
  group('(b) 旧数据零值哨兵 0/0/null → 头顶图标显示礼物盒', () {
    test('手写插入 0/0/null 的 pending 行 → rewardIconSpecsFor 返回单个 gift', () async {
      final _Ctx ctx = await _make(); // 全新 v12 库
      // 手写插入一条哨兵 pending 行（模拟 v12 之前登记的旧行；三列默认零值哨兵）。
      // 走真实写入链路（PlantLocalRepository.insertPendingBloomReward → bloomRewardDao.insertPending）。
      await ctx.plants.insertPendingBloomReward(PendingBloomReward(
        id: 'legacy_gift',
        plantId: 'ghost',
        dueAt: bloomAt,
        rewardKind: kBloomRewardKindNormal,
        // rewardSunlight / rewardFragments / rewardSpeciesId 全部默认（0/0/null）
      ));

      // 从真实库读回该哨兵行。
      final db.PendingBloomRewardRow row =
          await ctx.database.bloomRewardDao.byId('legacy_gift');
      expect(row.rewardSunlight, 0, reason: '零值哨兵');
      expect(row.rewardFragments, 0, reason: '零值哨兵');
      expect(row.rewardSpeciesId, isNull, reason: '零值哨兵');

      final PendingBloomReward reward = _toReward(row);
      final List<RewardIconSpec> icons = rewardIconSpecsFor(reward);
      expect(icons, hasLength(1), reason: '哨兵行只产生一个图标');
      expect(icons.single.kind, RewardIconKind.gift, reason: '旧哨兵行显示礼物盒');
      print('(b) 哨兵行实际值：'
          'sunlight=${reward.rewardSunlight}, fragments=${reward.rewardFragments}, '
          'speciesId=${reward.rewardSpeciesId} → icons=${icons.map((s) => s.kind.name)}');
    });
  });
}
