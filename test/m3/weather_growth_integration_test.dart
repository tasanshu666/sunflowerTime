/// 天气 × 成长**接线**集成测试（T02 阶段二；方案 §11.2 / §11.3 / §11.4）。
///
/// ## 本文件验的是「接线」，不是「数学」
/// 纯计算口径（`segmentProgress` / `careProgress` / `penaltyOf` 的公式本身）已由
/// `test/m3/weather_growth_math_test.dart` 钉死；日型生成由
/// `test/m3/weather_system_test.dart` 钉死。这里只回答一个问题：
/// **这三条纯函数真的被 `PlantGrowthService` 的真实生长流程调用了吗？**
///
/// ## 逐条对应验收要求
/// 1. `g` 真的进日结：晴天 24h 与干旱日 24h 的自然生长比 ≈ `g(干旱)/g(晴天)`；
/// 2. 惩罚只算「已关门」的日子：今天（`now` 所在日）永不罚（方案 P2）；
/// 3. `w` / `f` 真的乘在即时侧：浇水增量 = `kPlantWaterProgressGain × w(当天)`；
/// 4. 上限不回退：进度到 1.0 后浇水不超过 1.0；干旱日 `clamp(0,1)` 不为负；
/// 5. 零 IO 回归：账本查询次数 = 「预取窗口内的极端日数 + 需动作的日数」，
///    日结循环里不再现查（用 fake 仓储的调用计数断言）；
/// 6. V10 显式声明：有虫草时早退、惩罚不结算 —— **有意为之**，并断言进度完全不动。
///
/// 另附两组对账：方案 §15 的聚合口径（`E[g]` / `E[w]` / `E[f]`）与 §5.4 的
/// 复开花实测天数。
///
/// 纯 Dart：仓储全部内存 Fake，不依赖 Drift / Flutter。
library weather_growth_integration_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
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

// ── 内存 Fake 仓储 ──────────────────────────────────────────────────────────

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

/// 无任何专注会话：成长系数恒 1.0，隔离「有效专注日 ×1.3」这条干扰因素。
class _MemFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

/// 账本 Fake：余额恒充足（本文件只测成长口径，不看经济），
/// 但**按日计数是真的**（预取与惩罚判定都靠它），且统计
/// [countByRefTypeAndRefIdOnDay] 的调用次数，用来断言「零 IO 回归」。
class _CountingLedgerRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  /// [countByRefTypeAndRefIdOnDay] 被调用的总次数（跨全部 refType）。
  int countQueries = 0;

  /// 直接往账本里塞一行（模拟「昨天买过棚 / 浇过水」的历史事实）。
  void seed({
    required String refType,
    required String refId,
    required DateTime ts,
  }) {
    entries.add(SunlightEntry(
      id: 'seed-${entries.length}',
      ts: ts,
      type: SunlightType.plant,
      gross: 0,
      net: 0,
      balanceAfter: 0,
      refType: refType,
      refId: refId,
      dayKey: dayKey(ts),
    ));
  }

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  @override
  Future<double> balance() async => 1000000.0;

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
  ) async {
    countQueries++;
    return entries
        .where((SunlightEntry e) =>
            e.refType == refType && e.refId == refId && e.dayKey == key)
        .length;
  }

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
  Future<DateTime?> lastTsByRefTypeAndRefId(
      String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType != refType || e.refId != refId) continue;
      if (last == null || e.ts.isAfter(last)) last = e.ts;
    }
    return last;
  }
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

// ── 组装辅助 ────────────────────────────────────────────────────────────────

const String _kPlantId = 'p1';

typedef _Ctx = ({
  PlantGrowthService svc,
  _MemPlantRepo plants,
  _CountingLedgerRepo ledger,
});

_Ctx _make({double hoursPerStage = kPlantGrowthHoursPerStageDefault}) {
  final _MemPlantRepo plants = _MemPlantRepo(<PlantSpecies>[
    PlantSpecies(
      id: 'sp_test',
      name: 'test-grass',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: hoursPerStage,
      subscriptionOnly: false,
    ),
  ]);
  final _CountingLedgerRepo ledger = _CountingLedgerRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _MemFocusRepo(),
    ledger: ledger,
    settings: _MemSettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    weedRandom: NoHitRandom(),
  );
  return (svc: svc, plants: plants, ledger: ledger);
}

/// 种子期植物。`lastWaterAt = null` → 不触发枯萎 / 死亡，隔离「纯成长速率」。
Plant _seedPlant(
  DateTime stageStartedAt, {
  double progress = 0.0,
}) =>
    Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: stageStartedAt,
      growthProgress: progress,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: stageStartedAt,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      mood: PlantMood.calm,
    );

/// 成株复开花植物（`bloomCount >= 1`，进度回落到 [kBloomWiltProgressFloor]）。
Plant _rebloomPlant(DateTime stageStartedAt) => Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: stageStartedAt,
      growthProgress: kBloomWiltProgressFloor,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: stageStartedAt,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      bloomCount: 1,
      mood: PlantMood.calm,
    );

Future<Plant> _load(_MemPlantRepo plants) async =>
    (await plants.plant(_kPlantId))!;

/// 找第一个日型为 [kind] 的自然日（从 [from] 起逐日扫描）。
///
/// 用「扫」而不是硬编码日期：日型由 `WeatherSystem` 的哈希 + 软约束决定，
/// 硬编码某个日期会在日型表一变就静默失效；扫出来的日期则永远自洽。
DateTime _dayOfKind(WeatherKind kind, {DateTime? from}) {
  DateTime cursor = from ?? DateTime(2026, 1, 1);
  for (int i = 0; i < 800; i++) {
    if (WeatherSystem.ofDay(cursor).kind == kind) return cursor;
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  fail('no day of kind ${kind.name} within 800 days from $from');
}

/// 某日 0 点。
DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// `d` 之后第 [n] 天的 0 点。
DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// 让某日的极端日强制项「全部完成」：买棚 + 浇一次水（走原始账本行，
/// 不经过 `water()`，以免 `w × 1pp` 的即时加值污染「只看 `g`」的测量）。
void _fulfillDrought(_CountingLedgerRepo ledger, DateTime day) {
  ledger.seed(
    refType: kWeatherShelterRefTypeShade,
    refId: kWeatherShelterRefId,
    ts: day,
  );
  ledger.seed(refType: kPlantWaterRefType, refId: _kPlantId, ts: day);
}

/// 把 `from..to`（含端点）之间**所有**极端日的强制动作都补成「已完成」：
/// 该日型需要的棚 + 干旱的浇水 / 暴雨的施肥。
///
/// 用途：长跨度用例里若留着大量未完成的极端日，P1 的逐日 `clamp(0,1)` 会把进度
/// 反复削回 0，**被测的那 2pp 差异会被抹平**（进度都贴在 0 上，差恒为 0）。
/// 先补齐「与结论无关的日子」，差异才留得下来。
///
/// [skip] 指定的那一天**不补**（制造对照组的唯一差异）。
void _fulfillAllExtremeDays(
  _CountingLedgerRepo ledger,
  DateTime from,
  DateTime to, {
  DateTime? skip,
}) {
  final DateTime skipDay = skip == null ? DateTime(0) : _dayStart(skip);
  for (DateTime d = _dayStart(from);
      !d.isAfter(_dayStart(to));
      d = _plusDays(d, 1)) {
    if (d == skipDay) continue;
    final WeatherKind kind = WeatherSystem.ofDay(d).kind;
    final String? shelterRefType = kind.shelterRefType;
    if (shelterRefType == null) continue; // 温和日：无强制项、无惩罚
    ledger.seed(refType: shelterRefType, refId: kWeatherShelterRefId, ts: d);
    if (kind == WeatherKind.drought) {
      ledger.seed(refType: kPlantWaterRefType, refId: _kPlantId, ts: d);
    } else if (kind == WeatherKind.rainstorm) {
      ledger.seed(refType: kPlantFertilizeRefType, refId: _kPlantId, ts: d);
    }
  }
}

/// 预取窗口（与服务内 `_weatherWindowDays` 同口径）内**应该**发生的账本查询次数。
///
/// = 极端日数（每天一次道具查询，温和日不查）+ 需动作日数
///   （干旱查 `plant_water`、暴雨查 `plant_fertilize`，各一次）。
int _expectedPrefetchQueries({
  required DateTime plantedDay,
  required DateTime now,
  bool withActions = true,
}) {
  final DateTime today = _dayStart(now);
  DateTime start = _plusDays(today, -kWeatherGrowthLookbackDays);
  final DateTime planted = _dayStart(plantedDay);
  if (planted.isBefore(start)) start = planted;

  int count = 0;
  for (DateTime d = start; !d.isAfter(today); d = _plusDays(d, 1)) {
    final WeatherKind kind = WeatherSystem.ofDay(d).kind;
    if (kind.shelterRefType != null) count++; // 道具查询
    if (withActions &&
        (kind == WeatherKind.drought || kind == WeatherKind.rainstorm)) {
      count++; // 动作查询
    }
  }
  return count;
}

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // 1. `g` 真的进日结（方案 §11.3 改法 2）
  // ════════════════════════════════════════════════════════════════════════
  group('改法 2：g 真的进日结循环', () {
    test('晴天 24h vs 干旱日 24h：自然生长比 ≈ g(干旱) / g(晴天)', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final DateTime drought = _dayOfKind(WeatherKind.drought);

      // 晴天：温和日无惩罚，24h 段进度 = 24 × g / growthHoursPerStage。
      final _Ctx sunnyCtx = _make();
      await sunnyCtx.plants.savePlant(_seedPlant(_dayStart(sunny)));
      await sunnyCtx.svc.tickAll(_plusDays(sunny, 1));
      final double onSunny = (await _load(sunnyCtx.plants)).growthProgress;

      // 干旱日：先把强制项做完（棚 + 浇水）⇒ 惩罚归零，只剩下 g 的作用。
      final _Ctx droughtCtx = _make();
      await droughtCtx.plants.savePlant(_seedPlant(_dayStart(drought)));
      _fulfillDrought(droughtCtx.ledger, _dayStart(drought));
      await droughtCtx.svc.tickAll(_plusDays(drought, 1));
      final double onDrought = (await _load(droughtCtx.plants)).growthProgress;

      const double hoursPerStage = kPlantGrowthHoursPerStageDefault;
      const double expectSunny =
          24.0 * kWeatherSunnyGrowthFactor / hoursPerStage;
      const double expectDrought =
          24.0 * kWeatherDroughtGrowthFactor / hoursPerStage;

      print('[接线/g] 晴天 24h = $onSunny（期望 $expectSunny）');
      print('[接线/g] 干旱 24h = $onDrought（期望 $expectDrought）');

      expect(onSunny, closeTo(expectSunny, 1e-12));
      expect(onDrought, closeTo(expectDrought, 1e-12));
      // 比值必须等于两个乘数之比（用常量算，不写死浮点）。
      expect(
        onDrought / onSunny,
        closeTo(kWeatherDroughtGrowthFactor / kWeatherSunnyGrowthFactor, 1e-12),
      );
      // 干旱日显著更慢：这是孩子能感知到的方向，别把符号写反。
      expect(onDrought, lessThan(onSunny));
    });

    test('复开花（bloomCount ≥ 1）同样乘 g：不能只影响首花', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final DateTime drought = _dayOfKind(WeatherKind.drought);

      final _Ctx sunnyCtx = _make();
      await sunnyCtx.plants.savePlant(_rebloomPlant(_dayStart(sunny)));
      await sunnyCtx.svc.tickAll(_plusDays(sunny, 1));
      final double onSunny = (await _load(sunnyCtx.plants)).growthProgress;

      final _Ctx droughtCtx = _make();
      await droughtCtx.plants.savePlant(_rebloomPlant(_dayStart(drought)));
      _fulfillDrought(droughtCtx.ledger, _dayStart(drought));
      await droughtCtx.svc.tickAll(_plusDays(drought, 1));
      final double onDrought = (await _load(droughtCtx.plants)).growthProgress;

      // 复开花的自动速率是固定 pp/天（没有 growthHoursPerStage），故 24h 增量
      // = kRebloomAutoProgressPerDay × g（非精品无 premiumDiv）。
      const double expectSunny =
          kBloomWiltProgressFloor +
              kRebloomAutoProgressPerDay * kWeatherSunnyGrowthFactor;
      const double expectDrought =
          kBloomWiltProgressFloor +
              kRebloomAutoProgressPerDay * kWeatherDroughtGrowthFactor;

      print('[接线/g] 复开花 晴天 24h = $onSunny（期望 $expectSunny）');
      print('[接线/g] 复开花 干旱 24h = $onDrought（期望 $expectDrought）');

      expect(onSunny, closeTo(expectSunny, 1e-12));
      expect(onDrought, closeTo(expectDrought, 1e-12));
      expect(onDrought, lessThan(onSunny));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 2. 惩罚只结算「已关门」的日子（方案 P2）
  // ════════════════════════════════════════════════════════════════════════
  group('改法 2：惩罚只算已关门的日子（P2：今天永不罚）', () {
    test('同一天：23:00 不罚，过了零点才罚（缺浇水那一项）', () async {
      final DateTime drought = _dayOfKind(WeatherKind.drought);

      // 只买棚、不浇水 ⇒ 干旱日强制项「浇水 ≥ 1」未完成 ⇒ 关门后罚 1pp。
      final _Ctx openCtx = _make();
      await openCtx.plants.savePlant(_seedPlant(_dayStart(drought)));
      openCtx.ledger.seed(
        refType: kWeatherShelterRefTypeShade,
        refId: kWeatherShelterRefId,
        ts: _dayStart(drought),
      );
      // 今天还没关门（23:00）⇒ 只吃 g，不罚。
      await openCtx.svc.tickAll(_dayStart(drought).add(const Duration(hours: 23)));
      final double whileOpen = (await _load(openCtx.plants)).growthProgress;

      // 关门后（次日 00:00）⇒ 同样一天先吃 g 再吃 -1pp 惩罚。
      final _Ctx closedCtx = _make();
      await closedCtx.plants.savePlant(_seedPlant(_dayStart(drought)));
      closedCtx.ledger.seed(
        refType: kWeatherShelterRefTypeShade,
        refId: kWeatherShelterRefId,
        ts: _dayStart(drought),
      );
      await closedCtx.svc.tickAll(_plusDays(drought, 1));
      final double afterClosed = (await _load(closedCtx.plants)).growthProgress;

      const double gPart23h =
          23.0 * kWeatherDroughtGrowthFactor / kPlantGrowthHoursPerStageDefault;
      const double gPart24h =
          24.0 * kWeatherDroughtGrowthFactor / kPlantGrowthHoursPerStageDefault;

      print('[接线/惩罚] 23:00（未关门）= $whileOpen（期望 $gPart23h，无惩罚项）');
      print('[接线/惩罚] 次日 00:00（已关门）= $afterClosed（期望 ${gPart24h - kWeatherPenaltyPerMissingItem}）');

      // 🔴 P2 的核心断言：今天即使极端日且未浇水，也不得出现惩罚项。
      expect(whileOpen, closeTo(gPart23h, 1e-12));
      // 关门后必须罚（且只罚缺的那一项：棚已买）。
      expect(
        afterClosed,
        closeTo(gPart24h - kWeatherPenaltyPerMissingItem, 1e-12),
      );
      expect(afterClosed, lessThan(whileOpen));
    });

    test('干旱日两项都缺 → 罚 2pp（B 口径：每个未做动作各罚 1pp）', () async {
      final DateTime drought = _dayOfKind(WeatherKind.drought);

      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_dayStart(drought)));
      await ctx.svc.tickAll(_plusDays(drought, 1));
      final double progress = (await _load(ctx.plants)).growthProgress;

      const double expected =
          24.0 * kWeatherDroughtGrowthFactor / kPlantGrowthHoursPerStageDefault -
              2 * kWeatherPenaltyPerMissingItem;
      print('[接线/惩罚] 两项全缺 = $progress（期望 $expected）');
      expect(progress, closeTo(expected, 1e-12));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 3. `w` / `f` 乘在即时加值侧（方案 §11.2 改法 1）
  // ════════════════════════════════════════════════════════════════════════
  group('改法 1：w / f 乘在浇水 / 施肥的即时增量上', () {
    test('浇水增量 = kPlantWaterProgressGain × w(当天)，不是裸基数', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_dayStart(sunny)));

      await ctx.svc.water(_kPlantId, _dayStart(sunny).add(const Duration(hours: 12)));
      final double after = (await _load(ctx.plants)).growthProgress;

      print('[接线/w] 浇水后 = $after（裸基数 $kPlantWaterProgressGain）');
      expect(after, closeTo(kPlantWaterProgressGain * kWeatherSunnyWaterFactor, 1e-12));
      // 反向断言：绝不能还是「裸基数」——那说明 w 没接线。
      expect(after, isNot(closeTo(kPlantWaterProgressGain, 1e-9)));
    });

    test('施肥增量 = kPlantFertilizeProgressGain × f(当天)，不是裸基数', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_dayStart(sunny)));

      await ctx.svc.fertilize(
          _kPlantId, _dayStart(sunny).add(const Duration(hours: 12)));
      final double after = (await _load(ctx.plants)).growthProgress;

      print('[接线/f] 施肥后 = $after（裸基数 $kPlantFertilizeProgressGain）');
      expect(
        after,
        closeTo(kPlantFertilizeProgressGain * kWeatherSunnyFertilizeFactor, 1e-12),
      );
      expect(after, isNot(closeTo(kPlantFertilizeProgressGain, 1e-9)));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 4. 上限与钳制（方案 P1）
  // ════════════════════════════════════════════════════════════════════════
  group('上限不回退 / 钳制不为负（P1）', () {
    test('进度已在 0.999：浇水后封顶 1.0，不会超过', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_dayStart(sunny), progress: 0.999));

      await ctx.svc.water(
          _kPlantId, _dayStart(sunny).add(const Duration(hours: 12)));
      final double after = (await _load(ctx.plants)).growthProgress;

      print('[接线/上限] 0.999 浇水后 = $after');
      expect(after, closeTo(1.0, 1e-12));
      expect(after, lessThanOrEqualTo(1.0));
    });

    test('干旱日 g ×0.20 叠 2pp 惩罚：进度被钳在 0，不变负', () async {
      final DateTime drought = _dayOfKind(WeatherKind.drought);
      // 精品 480h/阶段：24h 的自然增量只有 0.20 × 24/480 = 0.01，比 2pp 惩罚还小。
      final _Ctx ctx = _make(hoursPerStage: kPlantGrowthHoursPerStagePremium);
      await ctx.plants.savePlant(_seedPlant(_dayStart(drought), progress: 0.001));

      await ctx.svc.tickAll(_plusDays(drought, 1));
      final double after = (await _load(ctx.plants)).growthProgress;

      print('[接线/钳制] 0.001 + 0.01 - 0.02 → 实测 $after');
      expect(after, greaterThanOrEqualTo(0.0));
      expect(after, closeTo(0.0, 1e-12));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 5. 零 IO 回归（R6 / R7：日结循环内不现查账本）
  // ════════════════════════════════════════════════════════════════════════
  group('零 IO 回归：账本只在 tickAll 预取，日结循环内零查询', () {
    test('账本查询次数 = 窗口内极端日数 + 需动作日数（无重复、无逐株放大）', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final DateTime planted = _dayStart(sunny);
      final DateTime now = _plusDays(sunny, 2);

      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(planted));
      await ctx.svc.tickAll(now);

      final int expected =
          _expectedPrefetchQueries(plantedDay: planted, now: now);
      print('[接线/IO] countByRefTypeAndRefIdOnDay 调用次数 = '
          '${ctx.ledger.countQueries}（期望 $expected）');
      expect(ctx.ledger.countQueries, expected);
      // 窗口有界：绝不允许「逐日 × 逐株」无上限地扫。
      expect(
        ctx.ledger.countQueries,
        lessThanOrEqualTo(2 * (kWeatherGrowthLookbackDays + 3)),
      );
    });

    test('同参重复 tickAll：进度逐次完全一致（不重复累加）', () async {
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_dayStart(sunny)));
      final DateTime now = _plusDays(sunny, 3);

      await ctx.svc.tickAll(now);
      final double first = (await _load(ctx.plants)).growthProgress;
      for (int i = 0; i < 3; i++) {
        await ctx.svc.tickAll(now);
      }
      final double repeated = (await _load(ctx.plants)).growthProgress;

      print('[接线/IO] 首次 = $first，重复 3 次后 = $repeated');
      expect(repeated, closeTo(first, 1e-12));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 6. V10：有虫草时早退、惩罚也不结算 —— **有意为之**
  // ════════════════════════════════════════════════════════════════════════
  group('F174：有虫草时只暂停「今天」（原 V10 整段早退已按玄参 2026-11-04 拍板修正）', () {
    test('害虫在今日：出现前那几天照常结算，今天暂停，基准推到 now', () async {
      // 🔴 F174（玄参 2026-11-04 拍板「顺序修正」）：旧 V10 行为是「有虫草 → 整段
      // [stageStartedAt, now] 早退丢弃」。App 多天没开时，这会把「离开那几天」本该
      // 长的进度全吞掉（孩子什么都没做错就白长了）。现改为**只暂停今天**：出现前
      // 那段（stageStartedAt → 今天零点）照常结算，只暂停今天零点 → now。
      final DateTime drought = _dayOfKind(WeatherKind.drought);
      final DateTime today = _dayStart(drought);

      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_seedPlant(_plusDays(today, -3), progress: 0.4)
          .copyWith(pestAt: today, weedPestRollDay: today));
      final DateTime now = today.add(const Duration(hours: 12));

      await ctx.svc.tickAll(now);
      final Plant after = await _load(ctx.plants);

      print('[接线/F174] 有虫时进度 = ${after.growthProgress}（原 0.4），'
          'stageStartedAt = ${after.stageStartedAt}');
      // 出现前那 3 天必须照常结算 → 进度严格大于起点 0.4（旧行为是恒等 0.4）。
      expect(after.growthProgress, greaterThan(0.4),
          reason: 'F174：出现前那几天照常生长，不得被今日害虫回溯归零');
      // 幂等基准照常前移到 now（今天这段暂停、永不倒补）。
      expect(after.stageStartedAt, now);
      expect(after.status, PlantStatus.growing);
      expect(after.hasPest, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 对账基线（方案 §15，可直接抄成断言）
  // ════════════════════════════════════════════════════════════════════════
  group('对账基线（方案 §15）', () {
    test('权重合计 100、温和 80 / 极端 20', () {
      int mild = 0;
      int extreme = 0;
      for (final WeatherKind k in WeatherKind.values) {
        final int w = WeatherSystem.weightOf(k);
        expect(w, greaterThan(0));
        if (k.isMild) {
          mild += w;
        } else {
          extreme += w;
        }
      }
      print('[对账] 权重合计 = ${mild + extreme}，温和 $mild / 极端 $extreme');
      expect(mild + extreme, 100);
      expect(mild, 80);
      expect(extreme, 20);
    });

    test('温和加权 g = 1.0000 / 极端加权 g = 0.6400 / E[g] = 0.9280', () {
      double mildWeighted = 0;
      double extremeWeighted = 0;
      for (final WeatherKind k in WeatherKind.values) {
        final double contribution =
            WeatherSystem.weightOf(k) * WeatherSystem.ofKind(k).growthFactor;
        if (k.isMild) {
          mildWeighted += contribution;
        } else {
          extremeWeighted += contribution;
        }
      }
      final double mildG = mildWeighted / 80.0;
      final double extremeG = extremeWeighted / 20.0;
      final double expectedG = 0.8 * mildG + 0.2 * extremeG;

      print('[对账] 温和加权 g = $mildG，极端加权 g = $extremeG，E[g] = $expectedG');
      expect(mildG, closeTo(1.0, 5e-5));
      expect(extremeG, closeTo(0.64, 5e-5));
      expect(expectedG, closeTo(0.9280, 5e-5));
    });

    test('E[w] = 1.0700 / E[f] = 0.9514（按权重加权，不含额度截断）', () {
      double expectedW = 0;
      double expectedF = 0;
      for (final WeatherKind k in WeatherKind.values) {
        final WeatherDay day = WeatherSystem.ofKind(k);
        final double weight = WeatherSystem.weightOf(k) / 100.0;
        expectedW += weight * day.waterFactor;
        expectedF += weight * day.fertilizeFactor;
      }
      print('[对账] E[w] = $expectedW，E[f] = $expectedF');
      expect(expectedW, closeTo(1.0700, 5e-5));
      expect(expectedF, closeTo(0.9514, 5e-5));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 复开花乘 g 的实测（对照方案 §5.4）
  // ════════════════════════════════════════════════════════════════════════
  group('复开花乘 g 的实测天数（方案 §5.4：零养护 14.97）', () {
    test('零养护：实测天数与 §5.4 的 14.97 同量级', () async {
      final DateTime start = _dayStart(_dayOfKind(WeatherKind.sunny));
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_rebloomPlant(start));

      int? days;
      DateTime now = start;
      for (int day = 0; day < 120; day++) {
        await ctx.svc.tickAll(now);
        final Plant cur = await _load(ctx.plants);
        if (cur.status == PlantStatus.bloomed) {
          days = day;
          break;
        }
        now = _plusDays(now, 1);
      }

      print('[§5.4] 复开花零养护实测 = $days 天（设计值 基准 14.97 / B 16.44）');
      expect(days, isNotNull);
      // §5.4.1 实测（730 个起点）单起点整数天范围 **14 ~ 21**（中位 17），
      // 本起点落 16。区间取实测包络，满足 §5.4.1「复开花单起点整数天 ≥ ±2 天」。
      expect(days, inInclusiveRange(14, 21));
    });

    test('每天 3 水 1 肥：实测天数与 §5.4 的 7.29 / 7.62 同量级', () async {
      final DateTime start = _dayStart(_dayOfKind(WeatherKind.sunny));
      final _Ctx ctx = _make();
      await ctx.plants.savePlant(_rebloomPlant(start));

      int? days;
      DateTime now = start;
      for (int day = 0; day < 120; day++) {
        await ctx.svc.tickAll(now);
        final Plant cur = await _load(ctx.plants);
        if (cur.status == PlantStatus.bloomed) {
          days = day;
          break;
        }
        // 3 次浇水（间隔 > 30 分钟）+ 1 次施肥。
        await ctx.svc.water(_kPlantId, now);
        await ctx.svc.water(_kPlantId, now.add(const Duration(minutes: 31)));
        await ctx.svc.water(_kPlantId, now.add(const Duration(minutes: 62)));
        await ctx.svc.fertilize(_kPlantId, now.add(const Duration(minutes: 93)));
        now = _plusDays(now, 1);
      }

      print('[§5.4] 复开花 3 水 1 肥实测 = $days 天（设计值 基准 7.29 / B 7.62）');
      // 口径已由产品经理 2026-11-02 校准（`docs/天气系统_最终方案.md` v6.2 §5.4）：
      //   `日均 = 3.6×E[g] + 0.7×ΣP·min(3,额度)·w + 1.5×E[f]`
      //        = 3.3408 + 0.7×2.9920 + 1.5×0.9514 = **6.8623 pp/天**
      //   ⇒ `50 ÷ 6.8623 = 7.29 天`（基准）/ B 口径 7.62 天。
      // ⚠️ 两个口径陷阱，别写错：
      //  ① **不能省掉额度截断**：不截断是 7.0149 pp/天 → 7.13 天；B 口径 6.7149 → 7.45 天。
      //     A1 期额度**尚未接线**（`TODO(weather-A4)`，`careQuota` 仍只认 3 次），
      //     故本测试实测的是「不截断口径」7.45 天 → 整数 8；与截断口径 7.62 的
      //     **整数天相同**，不影响结论（§5.4.1 末条「一条给 A4 期的提醒」）。
      //  ② **次数与乘数必须按日相关**（`E[次数×w]`），不能拆成 `E[次数]×E[w]`。
      // §5.4.1 规定复开花单起点整数天的区间宽度 ≥ ±2 天，故取 6~10（本起点落 8）。
      expect(days, isNotNull);
      expect(days, inInclusiveRange(6, 10));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 变异守卫（QA 独立验收：M5 窗口边界 / M6 clamp 位置）
  //
  // 这两条不是「验收需求」的复述，而是**给变异测试设的探针**：QA 做源码变异
  // （M1~M6）时，它们必须变红。改动它们前先确认自己不是为了「让它绿」。
  // ════════════════════════════════════════════════════════════════════════
  group('M5 变异守卫：窗口边界必须按「覆盖优先」取 min', () {
    test('窗口边界：窗口外的账本事实必须被读到（min 覆盖优先）', () async {
      // 🔴 本用例是为 **M5 变异**（`_weatherWindowDays` 里
      // `planted.isBefore(start)` → `isAfter`，等价于把 `min` 改成「真截断 90 天」）
      // 设的**行为级守卫**：改成截断后本用例**必须变红**。
      // 它刻意**不断言 IO 次数** —— 「零 IO 回归」那条用例虽然也会因查询次数对不上
      // 而变红，但报错信息指向「性能 / 次数」，会把人往错误方向带；这里直接断言
      // **孩子看得见的进度差**。
      //
      // 危害是**不对称**的：`_advanceGrowth` 里天气有兜底
      // （`batch.byDay[key] ?? WeatherSystem.ofDay(cursor)`）⇒ `g` 永远算对；
      // 但 `hasShelter` / `watered` / `fertilized` 三个布尔**没有任何兜底**，
      // 窗口外一律退化成 `false` ⇒ 老盆的远古极端日被**静默罚满 2pp**：
      // 不抛异常、不打日志，只是花长得莫名慢（最难查的一类错）。
      //
      // 参数按 QA 给的口径，**不要改小**（跨度太小就压不到窗口边界）：
      //  · 盆龄 155 天（> 90 天窗口 ⇒ 干净代码的 `min` 会把窗口放大到 155 天）；
      //  · 干旱日 = 起点后第 60 天 ⇒ 距 `now` **95 天**，必然落在「截断 90 天」之外。
      const int stageAgeDays = 155;
      const int droughtOffsetFromStart = 60;

      final DateTime drought = _dayOfKind(WeatherKind.drought);
      final DateTime start = _plusDays(drought, -droughtOffsetFromStart);
      final DateTime now = _plusDays(drought, stageAgeDays - droughtOffsetFromStart);

      // 阶段时长刻意放大 100 倍：155 天只推进约 0.15 阶段进度，**既不会跨阶段、
      // 也不会开花**，两株的唯一差异就是「那一个干旱日做没做强制动作」。
      // （普通 240h 下 155 天会跨 14 个阶段并开花，进度差会被阶段推进 / 花期重置吃掉。）
      const double longStageHours =
          kPlantGrowthHoursPerStageDefault * 100;

      // A 株：**除目标日以外**的所有极端日都补成「已完成」，目标干旱日也补
      // （走原始账本行，不经过 `water()`，以免 `w × 1pp` 的即时加值污染测量）。
      final _Ctx withFacts = _make(hoursPerStage: longStageHours);
      await withFacts.plants.savePlant(_seedPlant(start));
      _fulfillAllExtremeDays(withFacts.ledger, start, now);

      // B 株：完全相同的对照，只把目标干旱日那两条事实**留空**。
      // 🔴 **不许「简化」回『只给目标日补事实、其余极端日不管』** —— 那样必假绿：
      // 155 天里约 31 个极端日，两株每天 −1~2pp 而增长只有 +0.1pp/天 ⇒ P1 的
      // 逐日 `clamp(0,1)` 会把两株进度反复削回 0（实测两株都停在 0.00509），
      // 2pp 差异被 clamp 完全抹平，差恒为 0.0 ⇒ **用例绿着，但什么都没验**
      // （第一版就是这么写的，2026-11-02 实测踩到）。补满其余极端日后进度才单调
      // 上行（0.1426 vs 0.1226），差才留得住。
      final _Ctx withoutFacts = _make(hoursPerStage: longStageHours);
      await withoutFacts.plants.savePlant(_seedPlant(start));
      _fulfillAllExtremeDays(withoutFacts.ledger, start, now, skip: drought);

      await withFacts.svc.tickAll(now);
      await withoutFacts.svc.tickAll(now);

      final double withP = (await _load(withFacts.plants)).growthProgress;
      final double withoutP = (await _load(withoutFacts.plants)).growthProgress;
      final double diff = withP - withoutP;

      print('[变异/M5] 有事实 = $withP，无事实 = $withoutP，差 = $diff'
          '（期望 ${2 * kWeatherPenaltyPerMissingItem}）');

      // 唯一断言：两条事实都被读到 ⇒ 差恰好 = 2 个「缺项」的惩罚。
      // M5 变异体上那天的事实查不到 ⇒ 两株一模一样 ⇒ 差 = 0.0 ⇒ closeTo 失败。
      expect(diff, closeTo(2 * kWeatherPenaltyPerMissingItem, 1e-12));
      // 反向断言（失败时的可读性）：差必须非 0，否则就是「窗口外事实静默丢失」。
      expect(diff, isNot(closeTo(0.0, 1e-9)),
          reason: '窗口外的账本事实被丢弃了：老盆的远古极端日会被静默罚满 2pp');
    });
  });

  group('M6 变异守卫：clamp 必须在阶段推进之后', () {
    test('跨级残留：0.99 + 一天增量 → 推进后残留 = 增量 − 0.01，不是 0', () async {
      // 🔴 本用例是为 **M6 变异**（把 `progress.clamp(0.0, 1.0)` 从阶段推进的
      // `while` 之后挪回「惩罚结算紧后面」）设的**直接守卫**。
      // 挪早后：`0.99 + 0.105 = 1.095` → clamp 削成 `1.0` → 推进减 1.0 → 残留 **0.0**，
      // 每跨一级白丢最多 0.095 阶段进度（≈ 一整天），等于凭 clamp 人为拖慢成长。
      // 正确位置在推进之后：溢出先被推进消费，clamp 只作用于「剩下的余数」。
      final DateTime sunny = _dayOfKind(WeatherKind.sunny);
      final DateTime dayStart = _dayStart(sunny);

      final _Ctx ctx = _make();
      // 0.99 + 一天的增量必然 > 1.0 ⇒ 本段一定跨一级（seed → sprout）。
      await ctx.plants.savePlant(_seedPlant(dayStart, progress: 0.99));
      await ctx.svc.tickAll(_plusDays(sunny, 1));
      final Plant after = await _load(ctx.plants);

      // 期望值一律由常量 + 当日天气算出（不写死 0.095 之类的观测值）。
      const double oneFullDayHours = 24.0;
      const double progressBefore = 0.99;
      final WeatherDay weather = WeatherSystem.ofDay(dayStart);
      final double oneDayGain =
          oneFullDayHours * weather.growthFactor * kPlantAutoGrowthScale /
              kPlantGrowthHoursPerStageDefault;
      final double expected = progressBefore + oneDayGain - 1.0;

      print('[变异/M6] 实测残留 = ${after.growthProgress}，期望 $expected'
          '（clamp 挪早会变 0.0）');
      print('[变异/M6] 阶段 = ${after.stage.name}');

      // 先钉住「这一段确实跨了级」，否则后面的残留断言不成立（没跨级就没有溢出）。
      expect(after.stage, PlantStage.sprout);
      expect(after.growthProgress, closeTo(expected, 1e-12));
      // 反向断言：clamp 挪早会把残留削成 0，这一条让失败信息一眼可辨。
      expect(after.growthProgress, greaterThan(0.0),
          reason: 'clamp 抢在阶段推进之前执行了：溢出的那一小段被白丢');
    });
  });
}
