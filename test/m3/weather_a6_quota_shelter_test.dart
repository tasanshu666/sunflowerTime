/// 天气系统 A6 期 · **额度混合态 + 道具跨零点失效 + 余额边界** 守卫。
///
/// ## 为什么需要这份文件（A6 盘点结论）
/// A6 盘点发现三个「看起来被测过、其实没有」的空白：
///
/// ### ① `oneClickPlan` 的**混合额度**（`plant_growth_service.dart:1719`）
/// 既有 `weather_a4_quota_test.dart` 的 V7 只测了「**plan 为空**」时那句原因文案
/// （`batchNoneWaterMessage`），那是**纯字符串**用例，一次都没调过 `oneClickPlan`。
/// 于是「部分可做」这条最常走的路（花园里 4 盆，2 盆刚浇过、1 盆额度满了）**零覆盖**。
/// 后果：计划把不可做的株也算进 `totalCost` ⇒ 确认卡写「×3 / 15☀」，扣了钱只浇上 1 株。
///
/// ### ② 道具**跨零点失效**
/// `weather_a2_test.dart` T02 的 ③ 只钉了「**当日**重复购 → alreadyBought」。
/// 全文件搜不到「次日 / 跨日 / 第二天」。而 `buyShelter` 的幂等闸门是按 **`dayKey(now)`**
/// 查的（`:1992-1996`）—— 若有人图省事改成「查最近一次购买」不按日，
/// 孩子买一次就**永久免疫**，25 天里天天白拿减免，且现有用例全绿。
///
/// ### ③ 余额**恰等于**价格
/// ③ 用余额 97、④ 用余额 9（= 10 − 1）。两端都在，但**恰好的那一点**没人站。
/// `balance < cost` 一旦写成 `balance <= cost`，两端用例照样绿，
/// 而「刚好攒够 10☀」的孩子买不了棚。
///
/// ## 期望值来源（铁律：不引用被测常量自证）
///  · 1pp = 0.01 是**方案 §5.1 的惩罚口径**（每个未做动作各罚 1pp），写死；
///  · 单价 10☀ / 浇水 5☀ 是**玩法常量**（PRD §3），写死，不从 `kXxx` 取；
///  · 计划集合靠 `plantIds` 逐元素比对，不复算。
library weather_a6_quota_shelter_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
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
import 'package:sunflower_time/domain/services/weather_system.dart';

import '../helpers/no_hit_random.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 内存桩（与 `weather_a4_quota_test` 同源；本文件额外需要 `countCalls` 不加，
// 因为我们不测 IO 次数，只测业务结论）
// ─────────────────────────────────────────────────────────────────────────────

class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  _MemoryLedger({this.initialBalance = 1000});

  double initialBalance;

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
              e.refType == refType && e.dayKey.startsWith(monthKey))
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

  /// 全量（跨日）计数。
  ///
  /// 🔴 **必须真实实现，不能 `=> 0`**：本仓多份天气用例的 `_MemoryLedger` 把它写成
  /// `async => 0`，于是若 `buyShelter` 的幂等闸门被改成「查全量买过没」
  /// （`countByRefTypeAndRefIdOnDay` → `countByRefType`），**桩会替实现撒谎**、
  /// 变异悄无声息地活下来。本文件按真语义计数，让那条变异能被 Q2 抓到。
  @override
  Future<int> countByRefType(String refType) async =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

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
        .where((SunlightEntry e) =>
            e.refType == refType && e.refId == refId)
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

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  /// 当日某 refType + refId 的行数（用例里直接查，不经被判对象）。
  int countOn(String refType, String refId, String dayKey) => entries
      .where((SunlightEntry e) =>
          e.refType == refType && e.refId == refId && e.dayKey == dayKey)
      .length;
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
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemorySettingsRepo implements SettingsRepository {
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

({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants}) _make({
  double balance = 1000,
}) {
  final _MemoryLedger ledger = _MemoryLedger(initialBalance: balance);
  final _MemoryPlantRepo plants = _MemoryPlantRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: ledger,
    settings: _MemorySettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    weedRandom: NoHitRandom(),
  );
  return (svc: svc, ledger: ledger, plants: plants);
}

PlantSpecies get _sunflower =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == 'species_sunflower');

// ─────────────────────────────────────────────────────────────────────────────
// 日历辅助（日型一律从 `WeatherSystem` 取，不写死日期）
// ─────────────────────────────────────────────────────────────────────────────

/// 在 2026 年里找出**第一个**满足 [where] 的自然日。
DateTime _firstDayWhere(bool Function(WeatherDay d) where) {
  DateTime d = DateTime(2026, 1, 1, 12);
  for (int i = 0; i < 366; i++) {
    if (where(WeatherSystem.ofDay(d))) return d;
    d = DateTime(d.year, d.month, d.day + 1, 12);
  }
  fail('2026 年内找不到满足条件的自然日 —— 日历前提不成立');
}

/// 一盆「活着、成长中、当日还没浇过」的植物。
Plant _alivePlant(String id, DateTime day) => Plant(
      id: id,
      speciesId: _sunflower.id,
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: day,
      growthProgress: 0.5,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: day,
    );

/// 一条「浇水花了 5☀」的账本行（seeds 用，**不经过 service**）。
///
/// 🔴 必须手工造：走 `svc.water` 会被 30 分钟间隔 / 额度拦住，正是本用例要测的东西。
SunlightEntry _waterRow({
  required String plantId,
  required DateTime at,
}) =>
    SunlightEntry(
      id: 'seed-$plantId-${at.microsecondsSinceEpoch}',
      ts: at,
      type: SunlightType.plant,
      gross: -5,
      net: -5,
      balanceAfter: 995,
      refType: 'plant_water',
      refId: plantId,
      dayKey: dayKey(at),
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Q1 · oneClickPlan 的混合额度：只把「今日真能浇」的株放进计划
  // ───────────────────────────────────────────────────────────────────────────
  group('Q1 · oneClickPlan 混合额度（集合与合计价）', () {
    test('3 株混合态 ⇒ plan 只含可浇的 1 株、合计价 5☀；且另两株的排除理由是真的', () async {
      // 额度满额（3 次）的普通日：小雨 1 / 暴雨 0 都不适合本用例。
      final DateTime day = _firstDayWhere((WeatherDay d) => d.waterQuota == 3);
      final WeatherDay wd = WeatherSystem.ofDay(day);
      expect(wd.waterQuota, 3, reason: '日历前提：这一天必须是满额额度日');
      final DateTime now = DateTime(day.year, day.month, day.day, 12);

      final ({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants})
          h = _make();

      // A：今日一次都没浇 ⇒ 可浇。
      final Plant a = _alivePlant('plant-a', day);
      // B：10 分钟前浇过 ⇒ 间隔（30 分钟）未到。
      final Plant b = _alivePlant('plant-b', day);
      // C：今日已浇 3 次 ⇒ 当日额度用尽。
      final Plant c = _alivePlant('plant-c', day);
      await h.plants.savePlant(a);
      await h.plants.savePlant(b);
      await h.plants.savePlant(c);
      await h.ledger.append(
          _waterRow(plantId: b.id, at: now.subtract(const Duration(minutes: 10))));
      for (final int minutesAgo in <int>[180, 120, 60]) {
        await h.ledger.append(_waterRow(
            plantId: c.id, at: now.subtract(Duration(minutes: minutesAgo))));
      }

      final OneClickPlan plan =
          await h.svc.oneClickPlan(PlantOneClickKind.water, now);

      expect(
        plan.plantIds,
        <String>[a.id],
        reason: '计划只许含「今日可浇」的株：A 可浇 / B 间隔未到 / C 额度用尽。'
            '若 `oneClickPlan` 的 `if (ok)` 过滤被去掉（M-A6-4），这里会变成 3 株',
      );
      expect(
        plan.totalCost,
        5,
        reason: '合计价 = 1 株 × 5☀。若把不可做的株也算进来，孩子会看到「×3 / 15☀」'
            '但只浇上 1 株（确认卡与实际执行对不上）',
      );
      expect(plan.actionCount, 1, reason: '动作次数必须 == 株数');

      // 排除理由必须**真实存在**（不是靠计划少列来糊过去的）：
      // 对 B / C 直接下单必须被各自的闸门拦住。
      await expectLater(
        h.svc.water(b.id, now),
        throwsA(isA<PlantOperationException>().having((PlantOperationException e) =>
            e.code, 'code', PlantOperationError.waterInterval)),
        reason: 'B 的排除理由必须真是「间隔未到」',
      );
      await expectLater(
        h.svc.water(c.id, now),
        throwsA(isA<PlantOperationException>().having((PlantOperationException e) =>
            e.code, 'code', PlantOperationError.waterDailyLimit)),
        reason: 'C 的排除理由必须真是「当日额度用尽」',
      );

      // 执行计划：只有 A 落账。
      for (final String id in plan.plantIds) {
        await h.svc.water(id, now);
      }
      expect(h.ledger.countOn('plant_water', a.id, dayKey(now)), 1,
          reason: 'A 必须新增 1 行浇水账（计划里就它一个）');
      expect(h.ledger.countOn('plant_water', b.id, dayKey(now)), 1,
          reason: 'B 的账本行数不许变（原 1 行）');
      expect(h.ledger.countOn('plant_water', c.id, dayKey(now)), 3,
          reason: 'C 的账本行数不许变（原 3 行）');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Q2 · 道具跨零点失效（当日有效、次日需重买、且不回溯救昨天）
  // ───────────────────────────────────────────────────────────────────────────
  group('Q2 · 道具跨零点失效', () {
    test('D 日买棚只保 D 日；D+1 要重买；重买不回溯改 D 日已结的账', () async {
      // 干旱日：惩罚 = 未浇水 −1pp + 未搭遮阳棚 −1pp（方案 §5.1 规则表）。
      final DateTime droughtDay = _firstDayWhere(
          (WeatherDay d) => d.kind == WeatherKind.drought);
      expect(WeatherSystem.ofDay(droughtDay).kind, WeatherKind.drought,
          reason: '日历前提：这天必须是干旱日');
      final DateTime noon = DateTime(
          droughtDay.year, droughtDay.month, droughtDay.day, 12);
      // 只结算到「D 日已关门」后的 1 秒 ⇒ 只有 D 日进惩罚判据。
      final DateTime justAfterMidnight = DateTime(
              droughtDay.year, droughtDay.month, droughtDay.day)
          .add(const Duration(days: 1, seconds: 1));

      // ── 对照组：不买棚 ──────────────────────────────────────────────────
      final ({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants})
          noShelter = _make();
      final Plant p0 = _alivePlant('plant-noshelter', noon);
      await noShelter.plants.savePlant(p0);
      await noShelter.svc.tickAll(justAfterMidnight);
      final double withoutShelter =
          (await noShelter.plants.plant(p0.id))!.growthProgress;

      // ── 实验组：D 日中午买遮阳棚 ────────────────────────────────────────
      final ({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants})
          withShelter = _make();
      final Plant p1 = _alivePlant('plant-shelter', noon);
      await withShelter.plants.savePlant(p1);

      final ShelterBuyResult bought = await withShelter.svc.buyShelter(
        noon,
        shelterRefType: kWeatherShelterRefTypeShade,
      );
      expect(bought.status, ShelterBuyStatus.bought,
          reason: 'D 日首次购买必须成功');
      await withShelter.svc.tickAll(justAfterMidnight);
      final double withShelterOnDay =
          (await withShelter.plants.plant(p1.id))!.growthProgress;

      // 差**恰好 1pp**（= 方案 §5.1「每个未做动作各罚 1pp」里的「缺棚」那一项）。
      expect(
        withShelterOnDay - withoutShelter,
        closeTo(0.01, 1e-9),
        reason: 'D 日买了棚 ⇒ 只少挨「缺棚」这 1pp。实测差 '
            '${(withShelterOnDay - withoutShelter)}（应为 0.01）',
      );

      // ── 跨零点：D+1 必须**重新**买 ──────────────────────────────────────
      final DateTime nextNoon = noon.add(const Duration(days: 1));
      final ShelterBuyResult again = await withShelter.svc.buyShelter(
        nextNoon,
        shelterRefType: kWeatherShelterRefTypeShade,
      );
      expect(
        again.status,
        ShelterBuyStatus.bought,
        reason: '棚「只管今天」：D+1 必须能重买。若幂等闸门的 dayKey 被换成常量 / '
            '或改成「查最近一次购买」不按日（M-A6-5），这里会返回 alreadyBought ⇒ '
            '孩子买一次永久免疫，25 天全免',
      );

      final List<SunlightEntry> shelterRows = withShelter.ledger.entries
          .where((SunlightEntry e) =>
              e.refType == kWeatherShelterRefTypeShade &&
              e.refId == kWeatherShelterRefId)
          .toList();
      expect(shelterRows.length, 2, reason: '两天各一行，共 2 行道具账');
      expect(
        shelterRows.map((SunlightEntry e) => e.dayKey).toSet(),
        <String>{dayKey(noon), dayKey(nextNoon)},
        reason: '两行的 dayKey 必须是两个不同的自然日（这正是「当日有效」的物理凭据）',
      );
      expect(await withShelter.ledger.balance(), 1000 - 20,
          reason: '买两次共扣 20☀（10 × 2）');

      // ── 不回溯：重买之后再把同一时刻 tick 一遍，D 日已结的账不许变 ──────
      await withShelter.svc.tickAll(justAfterMidnight);
      final double afterRepurchase =
          (await withShelter.plants.plant(p1.id))!.growthProgress;
      expect(
        afterRepurchase,
        closeTo(withShelterOnDay, 1e-12),
        reason: 'D+1 买棚**不得回溯**抹掉 D 日已结算的惩罚（进度必须逐位不变）',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Q3 · 余额恰等于单价（`<` vs `<=` 的 off-by-one）
  // ───────────────────────────────────────────────────────────────────────────
  group('Q3 · 余额边界', () {
    test('余额恰 10☀（正好够）⇒ 必须买到，余额归 0', () async {
      final DateTime day = _firstDayWhere(
          (WeatherDay d) => d.kind == WeatherKind.drought);
      final DateTime noon = DateTime(day.year, day.month, day.day, 12);

      final ({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants})
          h = _make(balance: 10);

      final ShelterBuyResult r = await h.svc.buyShelter(
        noon,
        shelterRefType: kWeatherShelterRefTypeShade,
      );

      expect(
        r.status,
        ShelterBuyStatus.bought,
        reason: '单价 10☀（PRD §3），余额正好 10☀ ⇒ 必须买得起。'
            '若 `balance < cost` 被写成 `balance <= cost`（M-A6-6），'
            '「刚好攒够」的孩子会买不了，而余额 9 / 97 两端的既有用例都照样绿',
      );
      expect(await h.ledger.balance(), 0, reason: '扣完必须恰好归 0（不是负数、不是留着 10）');
      expect(h.ledger.entries.length, 1, reason: '只许写一行账');
      expect(h.ledger.entries.single.net, -10, reason: '净额必须是 −10☀');
    });
  });
}
