/// B35 回归 · 晨露奖励「同株 + 同一 8 点槽位」登记去重（真机实证 2026-10-08）。
///
/// 用户口径（玄参真机小米 14）：「第一个向日葵的产物，一下子产生了很多的产物，这次是
/// 他早上 8 点自己刷新的产物」。真机库实锤：调试催熟 33 次开花 → `_enqueueBloomRewards`
/// 每次都把「未来 3 个 8 点槽位」重复登记一遍 → 每槽位 33 条未领取 → 今早 8 点同时到期，
/// 头顶一次性堆 33 个产物图标。
///
/// 修复（B35）：登记前按「同株 + 同 dueAt + 同 kind」槽位指纹判重，已登记的槽位跳过。
/// 本测试模拟真机场景：同一晚连续催熟两次开花 → 晨露槽位不得翻倍。
library bloom_reward_slot_dedupe_test;

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

PlantGrowthService _make(
  _MemPlantRepo plants,
  InMemoryBloomRewardRepository bloomRewards,
) =>
    PlantGrowthService(
      plants: plants,
      focus: _NoFocusRepo(),
      ledger: _MemLedger(),
      settings: _MemSettingsRepo(),
      bloomRewards: bloomRewards,
      random: _SeqRandom(),
      weedRandom: NoHitRandom(),
    );

/// 模拟调试面板 `_forceAdult`：写回 growing + 进度满 → tickAll 触发开花登记。
Future<void> _forceBloom(
  PlantGrowthService svc,
  _MemPlantRepo plants,
  DateTime t,
) async {
  final Plant cur = (await plants.plant(_kPlantId))!;
  await plants.savePlant(cur.copyWith(
    status: PlantStatus.growing,
    growthProgress: 1.0,
    stage: PlantStage.adult,
    stageStartedAt: t,
    lastWaterAt: t,
  ));
  await svc.tickAll(t);
}

void main() {
  group('B35 · 晨露奖励同槽位去重（同株 + 同 dueAt + 同 kind 只登记一次）', () {
    test('同一晚连续两次催熟开花 → 8 点晨露槽位不翻倍（真机 33 条堆图标场景）', () async {
      final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
      final InMemoryBloomRewardRepository bloomRewards =
          InMemoryBloomRewardRepository();
      final PlantGrowthService svc = _make(plants, bloomRewards);

      // 第一次开花：登记 instant + 未来 3 个 8 点槽位（10/8、10/9、10/10）。
      final DateTime t1 = DateTime(2026, 10, 7, 19, 0);
      await plants.savePlant(Plant(
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
      await svc.tickAll(t1);

      // 远未来 = 未领取全量（bloom_debug_panel 同款用法）。
      Future<List<PendingBloomReward>> unclaimed() =>
          bloomRewards.pendingBloomRewardsDue(DateTime(9999));
      int normalCount(List<PendingBloomReward> all) => all
          .where((PendingBloomReward r) =>
              r.plantId == _kPlantId &&
              r.rewardKind == kBloomRewardKindNormal)
          .length;
      expect(normalCount(await unclaimed()), 3, reason: '首次开花登记 3 个晨露槽位');

      // 第二次催熟开花（同晚、不同 bloomedAt）：8 点槽位完全相同 → 不得重复登记。
      final DateTime t2 = t1.add(const Duration(hours: 1));
      await _forceBloom(svc, plants, t2);
      expect(normalCount(await unclaimed()), 3,
          reason: '同槽位去重：晨露条数保持 3，不翻倍（真机上曾翻 33 倍）');

      // 第三次催熟（同一晚）→ 仍然 3 条。
      final DateTime t3 = t2.add(const Duration(hours: 1));
      await _forceBloom(svc, plants, t3);
      expect(normalCount(await unclaimed()), 3);
    });

    test('次日再开花（槽位错开）→ 新槽位正常登记，去重不误伤新花期', () async {
      final _MemPlantRepo plants = _MemPlantRepo(_kSpecies);
      final InMemoryBloomRewardRepository bloomRewards =
          InMemoryBloomRewardRepository();
      final PlantGrowthService svc = _make(plants, bloomRewards);

      final DateTime t1 = DateTime(2026, 10, 7, 19, 0);
      await plants.savePlant(Plant(
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
      await svc.tickAll(t1);
      expect(
        (await bloomRewards.pendingBloomRewardsDue(DateTime(9999)))
            .where((PendingBloomReward r) =>
                r.rewardKind == kBloomRewardKindNormal)
            .length,
        3,
      );

      // 数日后复开花：槽位整体后移 → 新槽位必须照常登记。
      final DateTime t2 = DateTime(2026, 10, 12, 20, 0);
      await _forceBloom(svc, plants, t2);
      final List<PendingBloomReward> normals = (await bloomRewards
              .pendingBloomRewardsDue(DateTime(9999)))
          .where((PendingBloomReward r) =>
              r.rewardKind == kBloomRewardKindNormal)
          .toList();
      // 旧轮 3 条（10/8、10/9、10/10，旧轮行将在后续 tick 被兜底结算或已结算）
      // + 新轮 10/13、10/14、10/15 槽位。此处只断言「新槽位存在」即去重没误伤。
      final Set<String> dueDays = normals
          .map((PendingBloomReward r) => DateTime(
                  r.dueAt.year, r.dueAt.month, r.dueAt.day)
              .toIso8601String()
              .substring(0, 10)) // 取 'YYYY-MM-DD'
          .toSet();
      expect(dueDays.contains('2026-10-13'), isTrue,
          reason: '新花期槽位必须照常登记（去重不误伤）');
      expect(dueDays.contains('2026-10-14'), isTrue);
      expect(dueDays.contains('2026-10-15'), isTrue);
    });
  });
}
