/// 独立边界验证测试（QA 回归，2026-09-23 玄参大人拍板口径）。
///
/// 目标：证明 9/23 的植物养成状态规则改动「真的按设计工作」，而非仅跑通。
/// 用 Fake 账本把「自枯萎以来的浇水/施肥次数」作为事实源计数（区别于工程师
/// 桩文件里 `countByRefTypeAndRefIdSince` 恒返 0 的占位实现，本文件用真实计数）。
///
/// 逐项对应主理人边界清单：
///   A. kPlantWiltDays=3：3 天未浇 → wilting；2 天未浇仍 growing（不因旧值 7 误判）。
///   B. 轻度恢复：wilting 且 wiltedAt<3 天，浇水 1 次即恢复。
///   C. 重度门槛（关键）：wilting 且 wiltedAt≥3 天，必须「3 浇 + 1 施」缺任一都不恢复。
///   D. dead 不可养护：careQuota 对 dead 返回阻塞原因、canWater/canFertilize=false。
///   E. wilting 可养护：careQuota 对 wilting（未触每日上限/间隔）canWater/canFertilize=true。
///   F. 死亡触发：wilting 且 wiltedAt≥7 天 → tickAll → dead；账本应有 plant_death_refund（30% 成本）。
///   G. grep revive/onRevive/kPlantReviveCost（见测试报告；本文件不引用）。
library plant_wilt_recover_boundary_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

// ── 内存桩（真实计数版：countByRefTypeAndRefIdSince 真正按 ts>=since 计数）────

class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double initialBalance = 1000000.0;

  /// 账本中指定 refType（任意 refId）的条数，用于断言「到底扣了几次」。
  int countRef(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  /// 指定 refType 的条目列表。
  List<SunlightEntry> entriesOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> dayNet(String key) async => entries
      .where((SunlightEntry e) => e.dayKey == key)
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

  /// 真实计数：自 [since]（含）起、指定 refType+refId 的记账条数。
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }

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
  Future<List<SunlightEntry>> all() async =>
      List<SunlightEntry>.from(entries);
}

class _MemoryPlantRepo implements PlantRepository {
  final Map<String, Plant> store = <String, Plant>{};

  @override
  Future<List<Plant>> plants() async => store.values.toList();

  @override
  Future<Plant?> plant(String id) async => store[id];

  @override
  Future<void> savePlant(Plant plant) async => store[plant.id] = plant;

  @override
  Future<void> deletePlant(String id) async => store.remove(id);

  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
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

/// 组装被测服务 + 桩（余额默认给足，隔离经济）。
({
  PlantGrowthService svc,
  _MemoryLedger ledger,
  _MemoryPlantRepo plants,
}) _make() {
  final _MemoryLedger ledger = _MemoryLedger();
  final _MemoryPlantRepo plants = _MemoryPlantRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemorySettingsRepo(),
  );
  return (svc: svc, ledger: ledger, plants: plants);
}

/// 种一株指定物种的植物，返回其 id（成本无关，余额充足）。
Future<String> _seed(PlantGrowthService svc, String speciesId, DateTime now) async {
  final Plant p = await svc.plant(speciesId, 0, now);
  return p.id;
}

/// 构造一株 wilting 植物（供 careQuota / 恢复相关断言）。
///
/// 默认物种为向日葵（成本 0），死亡返还场景需显式传 [speciesId] 为小雏菊
/// （低年段成本 72）以产生可见的 30% 返还额。
Plant _wiltingPlant(
  String id,
  DateTime now, {
  required DateTime wiltedAt,
  String speciesId = 'species_sunflower',
  PlantStage stage = PlantStage.seed,
  double growthProgress = 0.0,
}) =>
    Plant(
      id: id,
      speciesId: speciesId,
      potIndex: 0,
      stage: stage,
      stageStartedAt: now.subtract(const Duration(days: 30)),
      growthProgress: growthProgress,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.wilting,
      plantedAt: now.subtract(const Duration(days: 30)),
      lastWaterAt: wiltedAt,
      wiltedAt: wiltedAt,
      deadAt: null,
      mood: PlantMood.thirsty,
    );

void main() {
  final DateTime t0 = DateTime(2026, 9, 21, 9, 0);

  group('A. kPlantWiltDays=3：3 天未浇→wilting，2 天仍 growing（不因旧值 7 误判）', () {
    test('lastWaterAt = now-3天 → tickAll 后 status==wilting', () async {
      final ctx = _make();
      final Plant p = Plant(
        id: 'pA1',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.seed,
        stageStartedAt: t0.subtract(const Duration(days: 10)),
        growthProgress: 0.0,
        growthFactor: 1.0,
        waterUsed: false,
        fertilizerUsed: false,
        status: PlantStatus.growing,
        plantedAt: t0.subtract(const Duration(days: 10)),
        lastWaterAt: t0.subtract(Duration(days: kPlantWiltDays)), // 恰好 3 天
        wiltedAt: null,
        deadAt: null,
        mood: PlantMood.calm,
      );
      await ctx.plants.savePlant(p);

      await ctx.svc.tickAll(t0);
      final Plant after = (await ctx.plants.plant('pA1'))!;
      expect(after.status, PlantStatus.wilting,
          reason: '3 天未浇应进入 wilting（证明用的是新值 3，不是旧值 7）');
      expect(after.wiltedAt, isNotNull);
      // 枯萎计时基准不应被 tick 改动。
      expect(after.lastWaterAt, t0.subtract(Duration(days: kPlantWiltDays)));
    });

    test('lastWaterAt = now-2天 → tickAll 后仍为 growing（阈值严格 >2）', () async {
      final ctx = _make();
      final Plant p = Plant(
        id: 'pA2',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.seed,
        stageStartedAt: t0.subtract(const Duration(days: 10)),
        growthProgress: 0.0,
        growthFactor: 1.0,
        waterUsed: false,
        fertilizerUsed: false,
        status: PlantStatus.growing,
        plantedAt: t0.subtract(const Duration(days: 10)),
        lastWaterAt: t0.subtract(const Duration(days: 2)), // 2 天 < 3
        wiltedAt: null,
        deadAt: null,
        mood: PlantMood.calm,
      );
      await ctx.plants.savePlant(p);

      await ctx.svc.tickAll(t0);
      final Plant after = (await ctx.plants.plant('pA2'))!;
      expect(after.status, PlantStatus.growing,
          reason: '仅 2 天未浇不应枯萎（阈值为 3 而非 7）');
    });

    test('lastWaterAt = now-4天 → tickAll 后 status==wilting（与 3 天同向，确认是 3 不是 7）',
        () async {
      final ctx = _make();
      final Plant p = Plant(
        id: 'pA3',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.seed,
        stageStartedAt: t0.subtract(const Duration(days: 10)),
        growthProgress: 0.0,
        growthFactor: 1.0,
        waterUsed: false,
        fertilizerUsed: false,
        status: PlantStatus.growing,
        plantedAt: t0.subtract(const Duration(days: 10)),
        lastWaterAt: t0.subtract(const Duration(days: 4)), // 4 天 > 3
        wiltedAt: null,
        deadAt: null,
        mood: PlantMood.calm,
      );
      await ctx.plants.savePlant(p);

      await ctx.svc.tickAll(t0);
      expect((await ctx.plants.plant('pA3'))!.status, PlantStatus.wilting);
    });
  });

  group('B. 轻度恢复：wilting 且 wiltedAt<kPlantWiltRecoverHardDays，浇水 1 次即恢复', () {
    test('wiltedAt = now-1天，water() 1 次 → status==growing 且 wiltedAt==null',
        () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(
        _wiltingPlant(id, t0, wiltedAt: t0.subtract(const Duration(days: 1))),
      );

      await ctx.svc.water(id, t0);
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.growing,
          reason: '未满恢复阈值，浇水 1 次应直接恢复');
      expect(after.wiltedAt, isNull, reason: '恢复必须清空 wiltedAt');
      expect(after.lastWaterAt, t0);
    });
  });

  group('C. 重度门槛（关键）：wilting 且 wiltedAt≥kPlantWiltRecoverHardDays，必须 3 浇 + 1 施', () {
    test('C1：浇 3 次 + 施 1 次 → 恢复（growing）', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        wiltedAt: t0.subtract(Duration(days: kPlantWiltRecoverHardDays + 1)),
      ));

      // 3 次浇水（间隔 >30 分钟，满足每日 3 次上限与 30 分钟间隔）。
      await ctx.svc.water(id, t0);
      await ctx.svc.water(id, t0.add(const Duration(minutes: 31)));
      await ctx.svc.water(id, t0.add(const Duration(minutes: 62)));
      // 此时仍应 wilting（只浇了 3 次、没施肥）。
      expect((await ctx.plants.plant(id))!.status, PlantStatus.wilting,
          reason: '3 浇但 0 施 → 尚未满足，必须仍为 wilting');
      // 第 1 次施肥 → 满足「3 浇 + 1 施」→ 恢复。
      await ctx.svc.fertilize(id, t0.add(const Duration(minutes: 93)));
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.growing,
          reason: '3 浇 + 1 施 应恢复为 growing');
      expect(after.wiltedAt, isNull);
    });

    test('C2：只浇 2 次（差 1 次）→ 仍 wilting，不恢复', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        wiltedAt: t0.subtract(Duration(days: kPlantWiltRecoverHardDays + 1)),
      ));

      await ctx.svc.water(id, t0);
      await ctx.svc.water(id, t0.add(const Duration(minutes: 31)));
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.wilting,
          reason: '仅 2 浇（差 1 次）不应恢复');
      expect(after.wiltedAt, isNotNull);
    });

    test('C3（最易错）：浇 3 次但 0 次施肥 → 仍 wilting，不恢复', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        wiltedAt: t0.subtract(Duration(days: kPlantWiltRecoverHardDays + 1)),
      ));

      // 浇满 3 次（已达每日上限），全程不施肥。
      await ctx.svc.water(id, t0);
      await ctx.svc.water(id, t0.add(const Duration(minutes: 31)));
      await ctx.svc.water(id, t0.add(const Duration(minutes: 62)));
      // 再尝试第 4 次浇水会被每日上限拦下（验证确实浇了 3 次而非更多）。
      expect(
        () => ctx.svc.water(id, t0.add(const Duration(minutes: 93))),
        throwsA(isA<PlantOperationException>()),
      );
      await Future<void>.delayed(Duration.zero);

      final Plant after = (await ctx.plants.plant(id))!;
      expect(ctx.ledger.countRef('plant_water'), 3,
          reason: '账本应恰好记 3 次浇水');
      expect(ctx.ledger.countRef('plant_fertilize'), 0,
          reason: '全程未施肥');
      expect(after.status, PlantStatus.wilting,
          reason: '浇满 3 次但 0 施肥 → 重度门槛不满足，必须仍为 wilting');
      expect(after.wiltedAt, isNotNull,
          reason: '未恢复则 wiltedAt 不应被清空');
    });

    test('C4：施 1 次 + 浇 2 次（差 1 浇）→ 仍 wilting，不恢复', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        wiltedAt: t0.subtract(Duration(days: kPlantWiltRecoverHardDays + 1)),
      ));

      await ctx.svc.fertilize(id, t0);
      await ctx.svc.water(id, t0.add(const Duration(minutes: 31)));
      await ctx.svc.water(id, t0.add(const Duration(minutes: 62)));
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.wilting,
          reason: '施 1 + 浇 2（差 1 浇）→ 不应恢复');
    });
  });

  group('D. dead 不可养护：careQuota 对 dead 返回阻塞原因', () {
    test('dead 植物 careQuota：waterBlockReason/fertilizeBlockReason 非 null，canWater/canFertilize=false',
        () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant((await ctx.plants.plant(id))!.copyWith(
        status: PlantStatus.dead,
        wiltedAt: t0.subtract(const Duration(days: 10)),
        deadAt: t0,
      ));

      final Plant dead = (await ctx.plants.plant(id))!;
      final PlantCareQuota q = await ctx.svc.careQuota(dead, t0);
      expect(q.waterBlockReason, isNotNull,
          reason: 'dead 应禁止浇水');
      expect(q.fertilizeBlockReason, isNotNull,
          reason: 'dead 应禁止施肥');
      expect(q.canWater, isFalse);
      expect(q.canFertilize, isFalse);
    });

    test('dead 植物调用 water/fertilize 应抛异常（不可养护）', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant((await ctx.plants.plant(id))!.copyWith(
        status: PlantStatus.dead,
        wiltedAt: t0.subtract(const Duration(days: 10)),
        deadAt: t0,
      ));
      expect(
        () => ctx.svc.water(id, t0),
        throwsA(isA<PlantOperationException>()),
      );
      expect(
        () => ctx.svc.fertilize(id, t0),
        throwsA(isA<PlantOperationException>()),
      );
    });
  });

  group('E. wilting 可养护：careQuota 对 wilting（未触上限/间隔）canWater/canFertilize=true', () {
    test('wilting 植物（无当日养护）careQuota：可浇水可施肥，无阻塞原因', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_sunflower', t0);
      await ctx.plants.savePlant(_wiltingPlant(id, t0,
          wiltedAt: t0.subtract(const Duration(days: 1))));

      final Plant wilting = (await ctx.plants.plant(id))!;
      final PlantCareQuota q = await ctx.svc.careQuota(wilting, t0);
      expect(q.canWater, isTrue, reason: 'wilting 应允许浇水（用于恢复）');
      expect(q.canFertilize, isTrue, reason: 'wilting 应允许施肥（用于恢复）');
      expect(q.waterBlockReason, isNull);
      expect(q.fertilizeBlockReason, isNull);
      expect(q.waterRemaining, kPlantWaterMaxPerDay);
      expect(q.fertilizeRemaining, kPlantFertilizeMaxPerDay);
    });
  });

  group('F. 死亡触发：wilting 且 wiltedAt≥kPlantDeathDays → tickAll → dead + 30% 返还', () {
    test('wiltedAt = now-7天 → tickAll 后 status==dead，且账本有 plant_death_refund（30% 成本）',
        () async {
      final ctx = _make();
      // 用小雏菊（低年段成本 72）以产生可见返还额。
      final String id = await _seed(ctx.svc, 'species_daisy', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        speciesId: 'species_daisy',
        wiltedAt: t0.subtract(Duration(days: kPlantDeathDays)),
      ));

      await ctx.svc.tickAll(t0);
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.dead,
          reason: '枯萎满 7 天应死亡');
      expect(after.deadAt, isNotNull);

      // 死亡返还 = 种植成本 × 30%（低年段 daisy 成本 = baseCostLow）。
      final PlantSpecies sp = kSeedPlantSpecies.firstWhere(
        (PlantSpecies s) => s.id == 'species_daisy',
      );
      final int cost = sp.baseCostLow; // ageTier=low
      final int expectedRefund = (cost * kPlantDeathRefundRate).round();
      final List<SunlightEntry> refunds =
          ctx.ledger.entriesOf('plant_death_refund');
      expect(refunds, hasLength(1),
          reason: '死亡应恰好写一笔 plant_death_refund');
      expect(refunds.first.net, expectedRefund.toDouble(),
          reason: '返还额应为成本的 30%');
      expect(refunds.first.refId, id);
    });

    test('死亡返还幂等：二次 tickAll 不再产生第二笔 plant_death_refund', () async {
      final ctx = _make();
      final String id = await _seed(ctx.svc, 'species_daisy', t0);
      await ctx.plants.savePlant(_wiltingPlant(
        id,
        t0,
        speciesId: 'species_daisy',
        wiltedAt: t0.subtract(Duration(days: kPlantDeathDays)),
      ));

      await ctx.svc.tickAll(t0);
      await ctx.svc.tickAll(t0.add(const Duration(hours: 1)));
      final List<SunlightEntry> refunds =
          ctx.ledger.entriesOf('plant_death_refund');
      expect(refunds, hasLength(1),
          reason: '已死亡植物重复 tick 不应重复返还');
      expect((await ctx.plants.plant(id))!.status, PlantStatus.dead);
    });
  });
}
