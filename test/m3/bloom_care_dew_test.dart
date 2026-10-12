/// F111（玄参 2026-10-12 拍板）：**盛开植物养护 + 晨露「保花」折损**回归。
///
/// 背景（真机反馈）：已开花植物显示「有点口渴，该浇水啦」，但浇水 / 施肥按钮是灰的
/// （`仅成长中/枯萎植物可养护`）—— 更严重的是枯萎状态机对 bloomed 一视同仁，
/// 3 天不浇水照样枯萎，而玩家被禁止浇水救援 = 玩法死锁。
///
/// 拍板口径：
///  ① 盛开态**可**浇水 / 施肥（不加成长进度：进度已 1.0）→ 修死锁 + 口径自洽；
///  ② **不延长花期**（延长 = 多给奖励，花园定位是消耗阳光）；
///  ③ 养护的意义 = 保住**第二天**晨露阳光满额；忘养护 → 阳光 ×
///     [kBloomDewNeglectFactor]（向上取整）、由 [kBloomDewMinSunlight] 保底
///     ——「变少而不是没有」。
library bloom_care_dew_test;

import 'package:flutter_test/flutter_test.dart';

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

// ── 内存桩（账本真实计数：countByRefTypeAndRefIdOnDay / Since 按条目实算）────────

class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double initialBalance = 1000000.0;

  /// 指定 refType 的条数（断言「到底扣了几次 / 入了几次账」）。
  int countRef(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.from(entries);

  @override
  Future<double> dayNet(String key) async => entries
      .where((SunlightEntry e) => e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> earnGrossOnDay(String key) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String key) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => entries
      .where((SunlightEntry e) => e.refType == refType && e.dayKey == key)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey.startsWith(monthKey))
          .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

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
              e.refType == refType &&
              e.refId == refId &&
              !e.ts.isBefore(since))
          .length;

  @override
  Future<int> countByRefType(String refType) async =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
    String refType,
    String refId,
  ) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }
}

class _MemoryPlantRepo implements PlantRepository {
  final Map<String, Plant> store = <String, Plant>{};

  @override
  Future<List<Plant>> plants() async => store.values.toList();

  @override
  Future<Plant?> plant(String id) async => store[id];

  @override
  Future<void> savePlant(Plant p) async => store[p.id] = p;

  @override
  Future<void> deletePlant(String id) async => store.remove(id);

  @override
  Future<List<PlantSpecies>> species() async => const <PlantSpecies>[];
}

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemorySettingsRepo implements SettingsRepository {
  AppSettings value = AppSettings(
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

/// 组装被测服务 + 桩（余额给足，隔离经济）。
({
  PlantGrowthService svc,
  _MemoryLedger ledger,
  _MemoryPlantRepo plants,
  InMemoryBloomRewardRepository bloomRewards,
}) _make() {
  final _MemoryLedger ledger = _MemoryLedger();
  final _MemoryPlantRepo plants = _MemoryPlantRepo();
  final InMemoryBloomRewardRepository bloomRewards =
      InMemoryBloomRewardRepository();
  return (
    svc: PlantGrowthService(
      plants: plants,
      focus: _NoFocusRepo(),
      ledger: ledger,
      settings: _MemorySettingsRepo(),
      bloomRewards: bloomRewards,
    ),
    ledger: ledger,
    plants: plants,
    bloomRewards: bloomRewards,
  );
}

/// 一株**盛开**植物（adult / bloomed / 进度 1.0 / 3 天前浇过水）。
Plant _bloomed(String id, DateTime now) => Plant(
      id: id,
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.adult,
      status: PlantStatus.bloomed,
      growthProgress: 1.0,
      growthFactor: 1.0,
      plantedAt: now.subtract(const Duration(days: 30)),
      stageStartedAt: now.subtract(const Duration(days: 3)),
      bloomedAt: now.subtract(const Duration(days: 1)),
      lastWaterAt: now.subtract(const Duration(days: 3)),
    );

void main() {
  // 晨露掉落时刻 = 10-13 08:00；判定看的是**前一天**（10-12）是否养护。
  final DateTime t0 = DateTime(2026, 10, 12, 10, 0);
  final DateTime dewDue = DateTime(2026, 10, 13, 8, 0);

  group('F111① 盛开植物可养护（修「口渴却不能浇」死锁）', () {
    test('careQuota：bloomed 未触上限/间隔 → 可浇水可施肥', () async {
      final ctx = _make();
      final PlantCareQuota q = await ctx.svc.careQuota(_bloomed('p1', t0), t0);
      expect(q.canWater, isTrue,
          reason: '盛开态必须可浇水——枯萎状态机对 bloomed 一视同仁，禁养 = 死锁');
      expect(q.canFertilize, isTrue);
      expect(q.waterBlockReason, isNull);
      expect(q.fertilizeBlockReason, isNull);
    });

    test('careQuota：dead 仍不可养护（对照组）', () async {
      final ctx = _make();
      final Plant dead = _bloomed('p1', t0).copyWith(status: PlantStatus.dead);
      final PlantCareQuota q = await ctx.svc.careQuota(dead, t0);
      expect(q.canWater, isFalse);
      expect(q.canFertilize, isFalse);
    });

    test('浇水盛开植物：不加成长进度（恒 1.0）+ 刷新 lastWaterAt', () async {
      final ctx = _make();
      await ctx.plants.savePlant(_bloomed('p1', t0));

      await ctx.svc.water('p1', t0);

      final Plant after = (await ctx.plants.plant('p1'))!;
      expect(after.growthProgress, 1.0,
          reason: '盛开期浇水不加进度（玄参口径：只是不长培养进度）');
      expect(after.lastWaterAt, t0, reason: '必须刷新浇水时间 → 重置枯萎计时');
      expect(after.status, PlantStatus.bloomed);
      expect(ctx.ledger.countRef('plant_water'), 1);
    });
  });

  group('F111③ 晨露保花折损（只减不加，忘养护不归零）', () {
    test('纯函数 bloomDewSunlight：达标满额 / 未达标减半 / 保底 1', () {
      expect(PlantGrowthService.bloomDewSunlight(8, true), 8);
      expect(PlantGrowthService.bloomDewSunlight(8, false), 4);
      expect(PlantGrowthService.bloomDewSunlight(1, false),
          kBloomDewMinSunlight,
          reason: '折损后仍保底 1 —— 玄参口径「不能一点阳光都没有」');
      expect(PlantGrowthService.bloomDewSunlight(0, false), 0,
          reason: '本就没有阳光的档位（纯碎片 / 种子）不凭空变出阳光');
    });

    test('bloomDewCaredBefore：看的是 dueAt 前一天', () async {
      final ctx = _make();
      await ctx.plants.savePlant(_bloomed('p1', t0));

      expect(await ctx.svc.bloomDewCaredBefore('p1', dewDue), isFalse);

      // 前一天（10-12）浇一次 → 达标。
      await ctx.svc.water('p1', t0);
      expect(await ctx.svc.bloomDewCaredBefore('p1', dewDue), isTrue,
          reason: '昨天养护 → 今天 08:00 的晨露满额');
      expect(ctx.ledger.countRef('plant_water'), 1);
    });

    test('发放：前一天养护 → 满额；未养护 → 减半（账本如实入账）', () async {
      /// 返回实发阳光；实发与账本入账不一致则返回 -1（直接判红）。
      /// ⚠️ 每个用例独立上下文：共享账本会让「养护过」的浇水记录串味到未养护用例。
      Future<int> collectOnce({required bool care}) async {
        final ctx = _make();
        await ctx.plants.savePlant(_bloomed('p1', t0));
        const String rid = 'r1';
        await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
          id: rid,
          plantId: 'p1',
          dueAt: dewDue,
          rewardKind: kBloomRewardKindNormal,
          rewardSunlight: 8,
        ));
        if (care) {
          await ctx.svc.water('p1', t0); // 前一天养护
        }
        final double before = await ctx.ledger.balance();
        final BloomRewardOutcome outcome = await ctx.svc.collectBloomReward(
          rid,
          dewDue.add(const Duration(hours: 1)),
        );
        final double gained = (await ctx.ledger.balance()) - before;
        return outcome.sunlight == gained.round()
            ? outcome.sunlight
            : -1; // 实发 ≠ 入账 → 判红
      }

      expect(await collectOnce(care: true), 8, reason: '养护达标 = 满额');
      expect(await collectOnce(care: false), 4, reason: '未养护 = 减半，不为零');
    });

    test('开花瞬间奖励**不折损**（只折每日晨露）', () async {
      final ctx = _make();
      await ctx.plants.savePlant(_bloomed('p1', t0));
      await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
        id: 'r_instant',
        plantId: 'p1',
        dueAt: t0,
        rewardKind: kBloomRewardPhaseInstant,
        rewardSunlight: 6,
      ));

      final BloomRewardOutcome outcome =
          await ctx.svc.collectBloomReward('r_instant', t0);
      expect(outcome.sunlight, 6, reason: '开花瞬间奖励与养护无关，不打折');
      expect(ctx.ledger.countRef('plant_water'), 0);
    });

    test('展示与发放同源：头顶图标数字 = 实际到手', () async {
      final ctx = _make();
      await ctx.plants.savePlant(_bloomed('p1', t0));
      await ctx.bloomRewards.insertPendingBloomReward(PendingBloomReward(
        id: 'r_show',
        plantId: 'p1',
        dueAt: dewDue,
        rewardKind: kBloomRewardKindNormal,
        rewardSunlight: 8,
      ));

      final Map<String, List<PendingBloomReward>> shown =
          await ctx.svc.withBloomDewDiscount(
        await ctx.svc.collectibleBloomRewards(
          dewDue.add(const Duration(hours: 1)),
        ),
      );
      expect(shown['p1']!.single.rewardSunlight, 4,
          reason: '未养护时图标就必须显示折损后的数字，否则孩子会以为被扣了');

      final BloomRewardOutcome outcome = await ctx.svc.collectBloomReward(
        'r_show',
        dewDue.add(const Duration(hours: 1)),
      );
      expect(outcome.sunlight, 4);
    });
  });
}
