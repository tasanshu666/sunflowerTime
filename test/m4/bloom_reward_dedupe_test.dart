/// C45 回归测试（玄参 2026-10-09 截图反馈「一株头顶一次性堆 20+ 图标，密密麻麻」）：
/// B35 去重护栏（2026-10-08）只挡**新增**重复登记，护栏上线前调试催熟已写入的
/// 历史重复 pending 行仍在库里且全部「可收集」。`dedupePendingBloomRewards` 按
/// `plantId | dueAt | rewardKind` 分组去重，组内保留一条、其余物理删除。
///
/// 验证：
///  ① 同槽位重复行 → 只留一条（保留先到者），其余删除；
///  ② 不同槽位（不同 dueAt / 不同 kind）→ 不受影响；
///  ③ 已领取（claimed）行不参与去重；
///  ④ 幂等：无重复时零删除；
///  ⑤ 跨株互不干扰。
///
/// 纯 Dart 仓储以内存 Fake 实现；不依赖 Flutter / Drift。
library bloom_reward_dedupe_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kBloomRewardKindNormal, kBloomRewardPhaseInstant;
import 'package:sunflower_time/data/local/plant_seed.dart' show kSeedPlantSpecies;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart'
    show AgeTier;
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

// ── 内存 Fake 仓储（与 materialize_legacy_bloom_rewards_test 同款最小集）──

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
          String refType, String refId, String key) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
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

PendingBloomReward _row(
  String id, {
  required String plantId,
  required DateTime dueAt,
  String kind = kBloomRewardKindNormal,
  bool claimed = false,
  int sunlight = 6,
}) =>
    PendingBloomReward(
      id: id,
      plantId: plantId,
      dueAt: dueAt,
      rewardKind: kind,
      claimed: claimed,
      rewardSunlight: sunlight,
    );

void main() {
  final DateTime now = DateTime(2026, 10, 9, 12);
  final DateTime slot = DateTime(2026, 10, 9, 8); // 晨露 8 点槽位
  final DateTime slot2 = DateTime(2026, 10, 8, 8); // 前一日槽位

  Future<(PlantGrowthService, InMemoryBloomRewardRepository)> make() async {
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    final PlantGrowthService svc = PlantGrowthService(
      plants: _MemPlantRepo(),
      focus: _NoFocusRepo(),
      ledger: _MemLedger(),
      settings: _MemSettingsRepo(),
      bloomRewards: bloom,
    );
    return (svc, bloom);
  }

  group('dedupePendingBloomRewards（C45 历史重复行清理）', () {
    test('① 同槽位 33 条重复（调试催熟实证场景）→ 只留一条，其余删除', () async {
      final (PlantGrowthService svc, InMemoryBloomRewardRepository bloom) =
          await make();
      for (int i = 0; i < 33; i++) {
        await bloom.insertPendingBloomReward(_row('dup$i', plantId: 'p1', dueAt: slot));
      }
      expect(await bloom.pendingBloomRewardsDue(now), hasLength(33));

      final int removed = await svc.dedupePendingBloomRewards();

      expect(removed, 32, reason: '33 条同槽位只留 1 条');
      final List<PendingBloomReward> rest =
          await bloom.pendingBloomRewardsDue(now);
      expect(rest, hasLength(1));
      expect(rest.single.id, 'dup0', reason: '保留先登记者');
    });

    test('② 不同槽位（不同 dueAt / 不同 kind）→ 不受影响', () async {
      final (PlantGrowthService svc, InMemoryBloomRewardRepository bloom) =
          await make();
      await bloom.insertPendingBloomReward(
          _row('a', plantId: 'p1', dueAt: slot));
      await bloom.insertPendingBloomReward(
          _row('b', plantId: 'p1', dueAt: slot2));
      await bloom.insertPendingBloomReward(
          _row('c', plantId: 'p1', dueAt: slot, kind: kBloomRewardPhaseInstant));

      final int removed = await svc.dedupePendingBloomRewards();

      expect(removed, 0, reason: '三个不同槽位，无重复');
      expect(await bloom.pendingBloomRewardsDue(now), hasLength(3));
    });

    test('③ 已领取行不参与去重（未领取的重复行保留）', () async {
      final (PlantGrowthService svc, InMemoryBloomRewardRepository bloom) =
          await make();
      await bloom.insertPendingBloomReward(
          _row('live', plantId: 'p1', dueAt: slot));
      await bloom.insertPendingBloomReward(
          _row('done', plantId: 'p1', dueAt: slot, claimed: true));

      final int removed = await svc.dedupePendingBloomRewards();

      expect(removed, 0, reason: 'pendingBloomRewardsDue 只返回未领取行，claimed 不参与');
      final List<PendingBloomReward> rest =
          await bloom.pendingBloomRewardsDue(now);
      expect(rest, hasLength(1));
      expect(rest.single.id, 'live');
    });

    test('④ 幂等：无重复时零删除；重复跑第二遍零删除', () async {
      final (PlantGrowthService svc, InMemoryBloomRewardRepository bloom) =
          await make();
      await bloom.insertPendingBloomReward(
          _row('x', plantId: 'p1', dueAt: slot));
      await bloom.insertPendingBloomReward(
          _row('y', plantId: 'p1', dueAt: slot));

      expect(await svc.dedupePendingBloomRewards(), 1);
      expect(await svc.dedupePendingBloomRewards(), 0, reason: '第二遍无重复');
      expect(await bloom.pendingBloomRewardsDue(now), hasLength(1));
    });

    test('⑤ 跨株互不干扰：两株各自的同槽位行都保留', () async {
      final (PlantGrowthService svc, InMemoryBloomRewardRepository bloom) =
          await make();
      await bloom.insertPendingBloomReward(
          _row('p1a', plantId: 'p1', dueAt: slot));
      await bloom.insertPendingBloomReward(
          _row('p2a', plantId: 'p2', dueAt: slot));

      expect(await svc.dedupePendingBloomRewards(), 0);
      expect(await bloom.pendingBloomRewardsDue(now), hasLength(2));
    });
  });
}
