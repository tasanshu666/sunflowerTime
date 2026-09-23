/// M3 修订：浇水 / 施肥经济规则单测（固定价 + 每日限额 + 30 分钟最小间隔）。
///
/// 为什么必须自动测：口径要求「每天最多浇 3 次、两次间隔 ≥30 分钟」——
/// 手工在真机上验证「3 次上限」至少要等 1 小时以上，且「连点两次」这种
/// 竞态在手上根本复现不出来。故此处用内存账本把规则钉死：
///  ① 浇水固定扣 5 阳光、施肥固定扣 10 阳光（不分年龄档）；
///  ② 同一株每天浇水 ≤3 次、施肥 ≤1 次（按日键重置）；
///  ③ 两次浇水间隔 ≥30 分钟（「不能连续浇水」）；
///  ④ 「今日已用几次」的事实源是账本（refType + refId + dayKey 计数），
///     不是 Plants 表的布尔标记。
library plant_care_quota_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
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

// ── 内存桩 ────────────────────────────────────────────────────────────────

/// 内存阳光账本：append-only，按 (refType, refId, dayKey) 计数 / 取最近时间。
class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double initialBalance = 0;

  /// 账本中指定 refType 的条数（断言「到底扣了几次」）。
  int countRef(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  /// 最后一次记账（种植本身也会写一条 plant_plant，故不能用 single）。
  SunlightEntry get last => entries.last;

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> dayNet(String dayKey) async => entries
      .where((SunlightEntry e) => e.dayKey == dayKey)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey == dayKey)
          .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.dayKey.startsWith(monthKey))
          .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == dayKey)
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }

  @override
  Future<double> earnGrossOnDay(String dayKey) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == dayKey)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String dayKey) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == dayKey)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.from(entries);
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
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
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

/// 组装被测服务 + 桩（余额默认给足）。
({
  PlantGrowthService svc,
  _MemoryLedger ledger,
  _MemoryPlantRepo plants,
}) _make({double balance = 1000}) {
  final _MemoryLedger ledger = _MemoryLedger()..initialBalance = balance;
  final _MemoryPlantRepo plants = _MemoryPlantRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemorySettingsRepo(),
  );
  return (svc: svc, ledger: ledger, plants: plants);
}

/// 种下一株向日葵（成本 0），返回植物 id。
Future<String> _seedSunflower(PlantGrowthService svc, DateTime now) async {
  final Plant p = await svc.plant('species_sunflower', 0, now);
  return p.id;
}

void main() {
  final DateTime day1 = DateTime(2026, 9, 21, 9, 0); // 周一 09:00

  test('浇水固定扣 5 阳光（不分年龄档），账本落 refType=plant_water', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);
    final double before = await ctx.ledger.balance();

    await ctx.svc.water(id, day1);

    expect(await ctx.ledger.balance(), before - 5);
    expect(ctx.ledger.countRef('plant_water'), 1);
    expect(ctx.ledger.last.net, -5);
    expect(ctx.ledger.last.refId, id); // 计数口径依赖 refId
    expect(ctx.ledger.last.dayKey, dayKey(day1));
  });

  test('施肥固定扣 10 阳光，账本落 refType=plant_fertilize', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);
    final double before = await ctx.ledger.balance();

    await ctx.svc.fertilize(id, day1);

    expect(await ctx.ledger.balance(), before - 10);
    expect(ctx.ledger.last.net, -10);
    expect(ctx.ledger.last.refType, 'plant_fertilize');
  });

  test('不能连续浇水：同一时刻第二次被拦下，且不重复扣账', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);

    await ctx.svc.water(id, day1);

    expect(
      () => ctx.svc.water(id, day1),
      throwsA(isA<PlantOperationException>()),
    );
    // 等异步断言收敛后，账本应仍只有 1 条扣减（没被绕过多扣）。
    await Future<void>.delayed(Duration.zero);
    expect(ctx.ledger.countRef('plant_water'), 1);
  });

  test('浇水间隔 30 分钟：29 分钟不行、31 分钟可行', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);
    await ctx.svc.water(id, day1);

    expect(
      () => ctx.svc.water(id, day1.add(const Duration(minutes: 29))),
      throwsA(isA<PlantOperationException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ctx.ledger.countRef('plant_water'), 1);

    await ctx.svc.water(id, day1.add(const Duration(minutes: 31)));
    expect(ctx.ledger.countRef('plant_water'), 2);
  });

  test('每日浇水上限 3 次：第 4 次被拦下', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);

    await ctx.svc.water(id, day1); // 09:00
    await ctx.svc.water(id, day1.add(const Duration(minutes: 31))); // 09:31
    await ctx.svc.water(id, day1.add(const Duration(minutes: 62))); // 10:02
    expect(ctx.ledger.countRef('plant_water'), 3);
    expect(kPlantWaterMaxPerDay, 3);

    expect(
      () => ctx.svc.water(id, day1.add(const Duration(minutes: 93))), // 10:33
      throwsA(isA<PlantOperationException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ctx.ledger.countRef('plant_water'), 3);
  });

  test('每日施肥上限 1 次：同日第二次被拦下', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);

    await ctx.svc.fertilize(id, day1);
    expect(kPlantFertilizeMaxPerDay, 1);

    expect(
      () => ctx.svc.fertilize(id, day1.add(const Duration(hours: 3))),
      throwsA(isA<PlantOperationException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ctx.ledger.countRef('plant_fertilize'), 1);
  });

  test('次日额度重置：第二天可再浇 3 次', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);

    await ctx.svc.water(id, day1);
    await ctx.svc.water(id, day1.add(const Duration(minutes: 31)));
    await ctx.svc.water(id, day1.add(const Duration(minutes: 62)));
    expect(ctx.ledger.countRef('plant_water'), 3);

    // 次日同一时刻：日键变化 → 额度重置，可再浇。
    await ctx.svc.water(id, day1.add(const Duration(days: 1)));
    expect(ctx.ledger.countRef('plant_water'), 4);
  });

  test('阳光不足：余额 < 5 时浇水被拦下，且不写账本', () async {
    final ctx = _make(balance: 4);
    final String id = await _seedSunflower(ctx.svc, day1);

    expect(
      () => ctx.svc.water(id, day1),
      throwsA(isA<PlantOperationException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ctx.ledger.countRef('plant_water'), 0);
  });

  test('额度快照：剩余次数与阻塞原因对外可读（供卡片渲染）', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);
    final Plant p = (await ctx.plants.plant(id))!;

    PlantCareQuota q0 = await ctx.svc.careQuota(p, day1);
    expect(q0.canWater, isTrue);
    expect(q0.waterRemaining, 3);
    expect(q0.fertilizeRemaining, 1);

    await ctx.svc.water(id, day1);
    q0 = await ctx.svc.careQuota(p, day1);
    expect(q0.waterUsedToday, 1);
    expect(q0.waterRemaining, 2);
    expect(q0.canWater, isFalse); // 30 分钟内不可再浇
    expect(q0.minutesUntilNextWater, greaterThan(0));

    await ctx.svc.fertilize(id, day1);
    q0 = await ctx.svc.careQuota(p, day1);
    expect(q0.canFertilize, isFalse);
    expect(q0.fertilizeRemaining, 0);
  });

  test('枯萎植物也可养护（取消付费救回，恢复靠浇水/施肥）', () async {
    final ctx = _make();
    final String id = await _seedSunflower(ctx.svc, day1);
    final Plant p = (await ctx.plants.plant(id))!;
    await ctx.plants.savePlant(p.copyWith(status: PlantStatus.wilting));

    final Plant wilting = (await ctx.plants.plant(id))!;
    final PlantCareQuota q = await ctx.svc.careQuota(wilting, day1);
    // wilting 已放开为可养护（每日次数 / 30 分钟间隔限制仍生效，dead 仍不可养护）。
    expect(q.canWater, isTrue);
    expect(q.canFertilize, isTrue);
    expect(q.waterBlockReason, isNull);
  });

  group('枯萎靠养护恢复（取消付费救回，2026-09-23）', () {
    test('wilting 未满 3 天：浇水 1 次即恢复 growing', () async {
      final ctx = _make();
      final String id = await _seedSunflower(ctx.svc, day1);
      // 制造一株 wilting，wiltedAt 在 2 天前（未满 kPlantWiltRecoverHardDays 阈值）。
      await ctx.plants.savePlant((await ctx.plants.plant(id))!
          .copyWith(
            status: PlantStatus.wilting,
            wiltedAt: day1.subtract(const Duration(days: 2)),
          ));
      await ctx.svc.water(id, day1);
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.growing);
      expect(after.wiltedAt, isNull);
    });

    test('wilting 已满 3 天：需 3 浇 + 1 施才恢复；差一次仍保持 wilting', () async {
      final ctx = _make();
      final String id = await _seedSunflower(ctx.svc, day1);
      await ctx.plants.savePlant((await ctx.plants.plant(id))!
          .copyWith(
            status: PlantStatus.wilting,
            wiltedAt: day1.subtract(const Duration(days: 5)),
          ));
      // 2 浇 + 1 施：尚未满足（需 3 浇）。
      await ctx.svc.water(id, day1);
      await ctx.svc.water(id, day1.add(const Duration(minutes: 31)));
      await ctx.svc.fertilize(id, day1.add(const Duration(minutes: 62)));
      expect((await ctx.plants.plant(id))!.status, PlantStatus.wilting);
      // 第 3 次浇水 → 满足 → 恢复。
      await ctx.svc.water(id, day1.add(const Duration(minutes: 93)));
      final Plant after = (await ctx.plants.plant(id))!;
      expect(after.status, PlantStatus.growing);
      expect(after.wiltedAt, isNull);
    });
  });
}
