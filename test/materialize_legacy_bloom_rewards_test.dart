/// 任务 A 回归测试：盛开植物头顶「掉落即定奖」前登记的**零值哨兵**旧 pending 行，
/// 在花园页 `_reload` 调 `materializeLegacyBloomRewards` 后被当场 roll 出真实奖励内容
/// 写回，使头顶图标显示明细（阳光 / 碎片 / 种子）而非礼物盒。
///
/// 根因（玄参 2026-09-28 复验）：iOS 模拟器复用 v12 之前的旧库，旧 pending 行三列全零
/// （`0/0/null`），`rewardIconSpecsFor` 据此渲染礼物盒；本测试验证 `materializeLegacyBloomRewards`：
///  ① 仍可收集（植物仍盛开）的哨兵行 → 回写为真实奖励内容（不再礼物盒）；
///  ② 已定奖行 → 幂等跳过、不被覆盖；
///  ③ 不可收集（植物未盛开 / 已消失）的哨兵行 → 不动，留给 `tickAll` 兜底自动结算。
///
/// 纯 Dart 仓储以内存 Fake 实现；不依赖 Flutter / Drift。
library materialize_legacy_bloom_rewards_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kBloomInstantSunlight,
        kBloomRewardKindNormal,
        kBloomRewardPhaseInstant;
import 'package:sunflower_time/data/local/plant_seed.dart' show kSeedPlantSpecies;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart'
    show AgeTier, PlantMood, PlantStage, PlantStatus;
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

class _MemPlantRepo implements PlantRepository {
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
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
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
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

/// 账本 Fake：materialize 不扣费，余额恒 0、append 无副作用即可。
class _MemLedger implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 0.0;
  @override
  Future<double> balance() async => 0.0;
  @override
  Future<List<SunlightEntry>> all() async => const <SunlightEntry>[];
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
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
}

class _MemSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 12,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _Ctx {
  _Ctx(this.svc, this.plants, this.bloomRewards);
  final PlantGrowthService svc;
  final _MemPlantRepo plants;
  final InMemoryBloomRewardRepository bloomRewards;
}

/// 组装被测服务（[plants] 已含 [bloomed] 等植物）。
_Ctx _make(List<Plant> plants) {
  final _MemPlantRepo repo = _MemPlantRepo()..store.addAll(plants);
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  final PlantGrowthService svc = PlantGrowthService(
    plants: repo,
    focus: _NoFocusRepo(),
    ledger: _MemLedger(),
    settings: _MemSettingsRepo(),
    bloomRewards: bloomRewards,
  );
  return _Ctx(svc, repo, bloomRewards);
}

/// 一株已盛开植物（头顶有可收集奖励）。
Plant _bloomedPlant(String id, String speciesId, DateTime now) => Plant(
      id: id,
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now.subtract(const Duration(days: 10)),
      growthProgress: 1.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.bloomed,
      plantedAt: now.subtract(const Duration(days: 10)),
      lastWaterAt: now.subtract(const Duration(days: 1)),
      wiltedAt: null,
      deadAt: null,
      bloomedAt: now.subtract(const Duration(days: 2)),
      bloomCount: 1,
      mood: PlantMood.calm,
    );

/// 一株成长中（未盛开）植物。
Plant _growingPlant(String id, String speciesId, DateTime now) => Plant(
      id: id,
      speciesId: speciesId,
      potIndex: 1,
      stage: PlantStage.adult,
      stageStartedAt: now.subtract(const Duration(days: 5)),
      growthProgress: 0.9,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(days: 5)),
      lastWaterAt: now.subtract(const Duration(days: 1)),
      wiltedAt: null,
      deadAt: null,
      bloomedAt: null,
      bloomCount: 0,
      mood: PlantMood.calm,
    );

/// 构造一条**零值哨兵** pending 行（v12 之前登记：三列全零 = 未预先定奖）。
PendingBloomReward _sentinel(String id, String plantId, String rewardKind,
        DateTime dueAt) =>
    PendingBloomReward(
      id: id,
      plantId: plantId,
      dueAt: dueAt,
      rewardKind: rewardKind,
    );

void main() {
  final DateTime now = DateTime(2026, 9, 28, 12);

  group('materializeLegacyBloomRewards（任务 A 修复）', () {
    test('① 仍可收集的哨兵行 → 回写为真实奖励内容（不再礼物盒）', () async {
      final _Ctx ctx = _make(<Plant>[_bloomedPlant('p1', 'species_tomato', now)]);

      // 旧库遗留：开花瞬间 + 第二段 两条哨兵行（三列全零）。
      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('r1', 'p1', kBloomRewardPhaseInstant,
            now.subtract(const Duration(hours: 1))),
      );
      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('r2', 'p1', kBloomRewardKindNormal,
            now.subtract(const Duration(hours: 1))),
      );

      await ctx.svc.materializeLegacyBloomRewards(now);

      final List<PendingBloomReward> due =
          await ctx.bloomRewards.pendingBloomRewardsDue(now);
      final PendingBloomReward r1 =
          due.firstWhere((PendingBloomReward r) => r.id == 'r1');
      final PendingBloomReward r2 =
          due.firstWhere((PendingBloomReward r) => r.id == 'r2');

      // 哨兵已消除 → 头顶图标显示明细。
      expect(r1.hasPreAssignedReward, isTrue,
          reason: '开花瞬间哨兵 → 已定奖（保底基础阳光恒 ≥ base）');
      expect(r1.rewardSunlight, greaterThanOrEqualTo(kBloomInstantSunlight),
          reason: '开花瞬间保底基础阳光恒 ≥ base（普通 6）');
      expect(r2.hasPreAssignedReward, isTrue,
          reason: '第二段哨兵 → 已定奖（碎片 / 种子 / 阳光至少其一）');
    });

    test('② 幂等：已定奖行不被覆盖', () async {
      final _Ctx ctx = _make(<Plant>[_bloomedPlant('p1', 'species_tomato', now)]);

      // 已定奖（非哨兵）行：阳光 50、碎片 3。
      await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
        id: 'r3',
        plantId: 'p1',
        dueAt: now.subtract(const Duration(hours: 1)),
        rewardKind: kBloomRewardPhaseInstant,
        rewardSunlight: 50,
        rewardFragments: 3,
      ));

      await ctx.svc.materializeLegacyBloomRewards(now);

      final List<PendingBloomReward> due =
          await ctx.bloomRewards.pendingBloomRewardsDue(now);
      final PendingBloomReward r3 =
          due.firstWhere((PendingBloomReward r) => r.id == 'r3');
      expect(r3.rewardSunlight, 50, reason: '已定奖行不被重 roll 覆盖');
      expect(r3.rewardFragments, 3, reason: '已定奖行不被重 roll 覆盖');
      expect(r3.hasPreAssignedReward, isTrue);
    });

    test('③ 不可收集哨兵行（植物未盛开 / 已消失）不 materialize，留给 tickAll 兜底',
        () async {
      final _Ctx ctx = _make(<Plant>[
        _growingPlant('pGrow', 'species_tomato', now), // 成长中、未盛开
      ]);

      // 哨兵行挂在「不存在的植物」与「未盛开植物」上。
      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('rMissing', 'pGhost', kBloomRewardPhaseInstant,
            now.subtract(const Duration(hours: 1))),
      );
      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('rGrow', 'pGrow', kBloomRewardPhaseInstant,
            now.subtract(const Duration(hours: 1))),
      );

      await ctx.svc.materializeLegacyBloomRewards(now);

      final List<PendingBloomReward> due =
          await ctx.bloomRewards.pendingBloomRewardsDue(now);
      final PendingBloomReward rMissing =
          due.firstWhere((PendingBloomReward r) => r.id == 'rMissing');
      final PendingBloomReward rGrow =
          due.firstWhere((PendingBloomReward r) => r.id == 'rGrow');

      // 仍为零值哨兵（未被回写），继续由 tickAll 兜底自动结算负责。
      expect(rMissing.hasPreAssignedReward, isFalse, reason: '植物已消失 → 跳过');
      expect(rGrow.hasPreAssignedReward, isFalse, reason: '植物未盛开 → 跳过');
    });

    test('④ 精英物种的哨兵行同样被 materialize（按精英档 roll）', () async {
      final _Ctx ctx =
          _make(<Plant>[_bloomedPlant('pE', 'species_moon_orchid', now)]);

      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('rE1', 'pE', kBloomRewardPhaseInstant,
            now.subtract(const Duration(hours: 1))),
      );
      await ctx.bloomRewards.insertPendingBloomReward(
        _sentinel('rE2', 'pE', 'premium',
            now.subtract(const Duration(hours: 1))),
      );

      await ctx.svc.materializeLegacyBloomRewards(now);

      final List<PendingBloomReward> due =
          await ctx.bloomRewards.pendingBloomRewardsDue(now);
      final PendingBloomReward rE1 =
          due.firstWhere((PendingBloomReward r) => r.id == 'rE1');
      final PendingBloomReward rE2 =
          due.firstWhere((PendingBloomReward r) => r.id == 'rE2');
      expect(rE1.hasPreAssignedReward, isTrue);
      expect(rE2.hasPreAssignedReward, isTrue);
    });
  });
}
