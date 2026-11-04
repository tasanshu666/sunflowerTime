/// 天气系统 A4 期 · **额度 + 雨水代劳 + 禁用态** 验收守卫（V1~V7）。
///
/// ## 这份文件守的是什么
/// A4 三件（`docs/天气系统_A4_增量设计.md` §5.1 / §5.2 / §5.3）全部是「把已有数据
/// 接进已有管线」——**没有新分层、没有新玩法常量**，所以它最大的风险不是编译不过，
/// 而是**接错位置且不报错**：
///  · 雨水代劳若照 TODO 字面放在 `!dayEnd.isAfter(now)` 守卫**外** → 同一天多 tick
///    一次就重复 +1pp，暴雨日被浇成 +2pp / +3pp，**不抛异常、旧测试全绿**；
///  · 额度若漏 `min(3, waterQuota)` → 普通日毫无变化（3 = 3），小雨日却不会禁用；
///  · 判据若把「额度用尽」排在「暴雨」之前 → 暴雨日有效上限是 0，`0 >= 0` 立刻成立，
///    孩子看到「今天浇够了」而不是「雨水帮你浇好啦」。
/// 故本文件的断言一律**从算式 / 纯函数出期望值**，不写死「某天 = 某数」。
///
/// ## 与设计 §6 的对应
/// | 用例 | 设计项 | 抓的变异 |
/// |---|---|---|
/// | V1 | rainBonus 生效 | M-A4-1（错乘 100） |
/// | V2 | rainBonus 不重复累加 | M-A4-2（放守卫外） |
/// | V3 | 额度截断优先级 | M-A4-3 / M-A4-4 |
/// | V4 | `waterRemaining` 用有效上限 | M-A4-3 |
/// | V5 | 施肥不受天气影响 | M-A4-5 |
/// | V6 | 禁用态渲染 + 不扣费 | M-A4-6 / M-A4-7 |
/// | V7 | 一键雨天原因（§12.1-Q2） | — |
///
/// V8（`error_l10n` 19 码穷举）在 `test/i18n/error_l10n_test.dart`。
///
/// ⚠️ 本文件**不含** `pumpAndSettle`：花园页木牌是无限呼吸动画，全程有界 `pump`。
library weather_a4_quota_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/error_l10n.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
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
import 'package:sunflower_time/domain/services/weather_growth_math.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

import '../helpers/no_hit_random.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 内存桩（与 `plant_care_quota_test` 同源，只保留本文件用得到的成员）
// ─────────────────────────────────────────────────────────────────────────────

/// 内存阳光账本：append-only。
class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double initialBalance = 1000;

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

  @override
  Future<int> countByRefType(String refType) async => 0;

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

/// 空专注库：`wfdDays` 恒为空 ⇒ `_advanceGrowth` 的 `factor` 恒 1.0。
///
/// 这是 V1 能写「算式期望值」的前提：有效专注日的 1.3 倍是把不确定量引进来，
/// 而 A4 与专注无关，本文件刻意把这条支路钉成常量。
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

/// 组装被测服务 + 桩。`weedRandom` 固定「永不命中」，把 C26 干扰物隔离掉
/// （否则某天恰好 roll 到杂草，成长当天暂停，V1 的算式期望值就对不上）。
({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants}) _make() {
  final _MemoryLedger ledger = _MemoryLedger();
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

/// 向日葵物种（`growthHoursPerStage` 从种子表读，**不在测试里写死 240**）。
PlantSpecies get _sunflower =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == 'species_sunflower');

// ─────────────────────────────────────────────────────────────────────────────
// 日历辅助（期望值一律来自 `WeatherSystem`，不写死日期）
// ─────────────────────────────────────────────────────────────────────────────

/// 在 [year] 年内找出**每种日型的第一个自然日**。
///
/// 用途：把纯判据搬回**真实日历**上验一遍（`careQuota` 自己读 `WeatherSystem.ofDay`，
/// 注入不了假天气）。9 种日型权重最小 3%（暴雨）⇒ 一年内必然全部出现，
/// 本函数末尾的完整性断言会把这条前提钉住。
Map<WeatherKind, DateTime> _firstDayOfEachKind(int year) {
  final Map<WeatherKind, DateTime> found = <WeatherKind, DateTime>{};
  DateTime d = DateTime(year, 1, 1);
  while (d.year == year) {
    found.putIfAbsent(WeatherSystem.ofDay(d).kind, () => d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return found;
}

/// 当天中午 12:00（避开零点边界，让 `dayKey` 与「已关门」判据都无歧义）。
DateTime _noon(DateTime day) => DateTime(day.year, day.month, day.day, 12);

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  // 全量重跑用的日型日历（2026 年，与设计文档的取值年一致）。
  final Map<WeatherKind, DateTime> kindDays = _firstDayOfEachKind(2026);

  // ───────────────────────────────────────────────────────────────────────────
  // V1 · 雨水代劳生效：暴雨日增量 − 同条件（不含 bonus）增量 == rainWaterBonusPp
  // ───────────────────────────────────────────────────────────────────────────
  group('V1 · 雨水代劳（rainWaterBonusPp）生效', () {
    /// 种在 [day] 00:00、tick 到次日 00:00 —— **恰好一个完整自然日、且已关门**。
    ///
    /// 「已关门」是 A4 的关键：`!dayEnd.isAfter(now)` 成立时那一刻，`segHours` 恰好
    /// 是 24.0，于是整天的增量可以用 `WeatherGrowthMath` 的两个纯函数原样写出来。
    Future<double> progressOfOneClosedDay(DateTime day) async {
      final ctx = _make();
      final Plant p = await ctx.svc.plant('species_sunflower', 0, day);
      await ctx.svc.tickAll(day.add(const Duration(days: 1)));
      final Plant after = (await ctx.plants.plant(p.id))!;
      // 只走了一个自然日，不可能跨阶段（首花一个阶段要 240h）。
      expect(after.stage, PlantStage.seed, reason: '一天不可能跨阶段');
      return after.growthProgress;
    }

    /// 不含 bonus 的「同条件」期望增量（算式来源，非实测值）。
    double expectedWithoutBonus(WeatherDay wd) =>
        WeatherGrowthMath.segmentProgress(
              segHours: 24.0,
              day: wd,
              growthHoursPerStage: _sunflower.growthHoursPerStage,
            ) *
            1.0 /* factor：无有效专注日 */ *
            kPlantAutoGrowthScale +
        WeatherGrowthMath.penaltyOf(
          day: wd,
          hasShelter: false, // 桩账本查不到道具 ⇒ 无棚
          watered: false, // 没浇过水
          fertilized: false, // 没施过肥
        );

    test('暴雨日：实测 = 算式期望 + 0.01（且常量就是 0.01 = 1pp）', () async {
      final DateTime rainstormDay = kindDays[WeatherKind.rainstorm]!;
      final WeatherDay wd = WeatherSystem.ofDay(rainstormDay);
      expect(wd.kind, WeatherKind.rainstorm, reason: '日历前提：这天是暴雨日');
      expect(kWeatherRainstormWaterBonusPp, 0.01,
          reason: '§3：雨水代劳 = 1pp（进度是 0..1 尺度）');
      expect(wd.rainWaterBonusPp, kWeatherRainstormWaterBonusPp);

      final double actual = await progressOfOneClosedDay(rainstormDay);
      expect(
        actual,
        closeTo(expectedWithoutBonus(wd) + kWeatherRainstormWaterBonusPp, 1e-9),
        reason: '暴雨日必须「关掉的那一天」多 +1pp —— 少加（未接线）/ 多加都红',
      );
    });

    test('非暴雨日：实测 = 算式期望（bonus 恒 0，不得凭空发力）', () async {
      // 取「小雨」作对照：它同样有水相关变化（额度 1），但**没有** bonus，
      // 能顺带证明「额度 ≠ 代劳」两件事没被搅在一起。
      final DateTime lightRainDay = kindDays[WeatherKind.lightRain]!;
      final WeatherDay wd = WeatherSystem.ofDay(lightRainDay);
      expect(wd.rainWaterBonusPp, 0.0);

      final double actual = await progressOfOneClosedDay(lightRainDay);
      expect(
        actual,
        closeTo(expectedWithoutBonus(wd), 1e-9),
        reason: '非暴雨日不得有任何 rainBonus',
      );
    });

    test('9 种日型里只有暴雨带 bonus（表格本身的不变量）', () {
      for (final WeatherKind kind in WeatherKind.values) {
        final WeatherDay wd = WeatherSystem.ofKind(kind);
        final double expected =
            kind == WeatherKind.rainstorm ? 0.01 : 0.0;
        expect(wd.rainWaterBonusPp, expected,
            reason: '${kind.name} 的 rainWaterBonusPp 应为 $expected');
        // 额度侧同样只有小雨 / 暴雨偏离满额。
        final int quota = kind == WeatherKind.rainstorm
            ? kWeatherRainstormWaterQuota
            : kind == WeatherKind.lightRain
                ? kWeatherLightRainWaterQuota
                : kWeatherDefaultWaterQuota;
        expect(wd.waterQuota, quota, reason: '${kind.name} 的 waterQuota');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V2 · 不重复累加：同一天多次 tick 与一次 tick 到同一点，进度必须相同
  //
  // 🔴 **V1 与 V2 必须成对存在，删一条另一条就残**（A6 期的登记结论）：
  //   · V1（`暴雨日 waterBonus 恰好 +1pp`）断的是**绝对值** —— 只有它能抓
  //     「bonus 整条被删掉 / 数值被改」；
  //   · V2（本条）断的是 **A 与 B 的相对相等** —— 只有它能抓「同一天重复结算」。
  //   但 V2 是**纯相对**断言：把 `rainBonus` 整条删掉，A 和 B 依然相等 ⇒ **V2 照样绿**。
  //   反过来，V1 抓不到「幂等性」（它只 tick 一次）。
  //   ⇒ 后来者若觉得「V2 和 V1 讲的是同一件事，删一条」：删 V1 会丢掉全部绝对
  //     数值守卫，删 V2 会丢掉全部幂等守卫。**两条都要留着。**
  // ───────────────────────────────────────────────────────────────────────────
  group('V2 · rainBonus 同一天**只结算一次**（抓「放守卫外」）', () {
    test('暴雨日内先 tick 4 次再跨日，与一口气跨日的进度逐位相等', () async {
      final DateTime rainstormDay = kindDays[WeatherKind.rainstorm]!;
      expect(WeatherSystem.ofDay(rainstormDay).kind, WeatherKind.rainstorm);
      // 起点刻意取 00:30 而非零点：真机上 `stageStartedAt` 永远不等于零点
      // （每次 tick 末尾都被推到 now），零点起点是不现实的乐观假设。
      final DateTime start =
          rainstormDay.add(const Duration(minutes: 30));
      final DateTime end = start.add(const Duration(days: 1));

      // A：一口气 tick 到 end（只跨一次日）。
      final ctxA = _make();
      final Plant a = await ctxA.svc.plant('species_sunflower', 0, start);
      await ctxA.svc.tickAll(end);
      final double progressA = (await ctxA.plants.plant(a.id))!.growthProgress;

      // B：先在同一个暴雨日里 tick 4 次，再 tick 到同一个 end。
      final ctxB = _make();
      final Plant b = await ctxB.svc.plant('species_sunflower', 0, start);
      for (final int addHours in <int>[5, 11, 17, 22]) {
        await ctxB.svc.tickAll(start.add(Duration(hours: addHours)));
      }
      await ctxB.svc.tickAll(end);
      final double progressB = (await ctxB.plants.plant(b.id))!.growthProgress;

      expect(
        progressB,
        closeTo(progressA, 1e-12),
        reason: '同一天多次 tick 不得把 +1pp 重复累加（M-A4-2：放守卫外时 '
            'B 会多出 4×0.01）',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V3 · 额度截断与优先级（纯判据，零 widget / 零 DB）
  // ───────────────────────────────────────────────────────────────────────────
  group('V3 · resolveWaterGate 优先级（暴雨先于额度用尽）', () {
    const PlantBlockReason rainstormBlock =
        PlantBlockReason(PlantOperationError.waterRainstorm);
    const PlantBlockReason lightRainBlock =
        PlantBlockReason(PlantOperationError.waterLightRain);

    test('暴雨（quota 0）：即便 used=0 也禁用，且原因是「雨水代劳」', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.rainstorm);
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 0,
          minutesUntilNextWater: 0,
        ),
        rainstormBlock,
        reason: 'M-A4-4：若「额度用尽」先判，0 >= 0 会命中 waterDailyLimit',
      );
    });

    test('暴雨压过「间隔未到」与超高 used（优先级 ② > ④ > ⑤）', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.rainstorm);
      for (final int used in <int>[0, 1, 3, 9]) {
        expect(
          resolveWaterGate(
            status: PlantStatus.growing,
            day: day,
            waterUsedToday: used,
            minutesUntilNextWater: 25,
          ),
          rainstormBlock,
          reason: 'used=$used 也必须是「雨水代劳」，不能退化成额度/间隔',
        );
      }
    });

    test('小雨（quota 1）：未浇可浇；浇过 1 次 → waterLightRain', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.lightRain);
      expect(day.waterQuota, 1);
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 0,
          minutesUntilNextWater: 0,
        ),
        isNull,
        reason: '小雨未浇 → 允许浇一次',
      );
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 1,
          minutesUntilNextWater: 0,
        ),
        lightRainBlock,
        reason: 'M-A4-3：漏判「小雨已用」会退化成 waterDailyLimit / 或一路放行',
      );
      // 小雨已用 + 间隔未到 ⇒ 仍报「小雨」而非「间隔」（优先级 ③ > ⑤）。
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 1,
          minutesUntilNextWater: 12,
        ),
        lightRainBlock,
      );
    });

    test('普通日（quota 3）：used<3 且间隔到 → 可浇；used>=3 → quota 用尽', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.sunny);
      expect(day.waterQuota, 3);
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 0,
          minutesUntilNextWater: 0,
        ),
        isNull,
      );
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: day,
          waterUsedToday: 2,
          minutesUntilNextWater: 0,
        ),
        isNull,
      );
      final PlantBlockReason? full = resolveWaterGate(
        status: PlantStatus.growing,
        day: day,
        waterUsedToday: 3,
        minutesUntilNextWater: 0,
      );
      expect(full?.code, PlantOperationError.waterDailyLimit);
      expect(full?.a, 3, reason: '载荷 a = 有效上限');
    });

    test('有效上限是 min(3, quota)：quota 虚高时仍按 3 截断', () {
      // 真实日历里没有 quota=5 的日型，但判据必须对「未来新增日型」安全。
      const WeatherDay weird = WeatherDay(
        kind: WeatherKind.sunny,
        growthFactor: 1.0,
        waterQuota: 5,
      );
      expect(
        resolveWaterGate(
          status: PlantStatus.growing,
          day: weird,
          waterUsedToday: 3,
          minutesUntilNextWater: 0,
        )?.code,
        PlantOperationError.waterDailyLimit,
        reason: 'M-A4-3：直接拿 quota 当上限 ⇒ used=3 会被放行（超浇 2 次）',
      );
    });

    test('间隔未到（额度还有）→ waterInterval，载荷 = 常量 + 剩余分钟', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.sunny);
      final PlantBlockReason? r = resolveWaterGate(
        status: PlantStatus.growing,
        day: day,
        waterUsedToday: 1,
        minutesUntilNextWater: 12,
      );
      expect(r?.code, PlantOperationError.waterInterval);
      expect(r?.a, kPlantWaterIntervalMinutes);
      expect(r?.b, 12);
    });

    test('死亡株永远先报 careStateInvalid（优先级 ① 最高）', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.rainstorm);
      expect(
        resolveWaterGate(
          status: PlantStatus.dead,
          day: day,
          waterUsedToday: 0,
          minutesUntilNextWater: 0,
        )?.code,
        PlantOperationError.careStateInvalid,
      );
    });

    test('枯萎 / 盛开仍可养护（与 isPlantCareActionable 同源）', () {
      final WeatherDay day = WeatherSystem.ofKind(WeatherKind.sunny);
      for (final PlantStatus s in <PlantStatus>[
        PlantStatus.growing,
        PlantStatus.wilting,
        PlantStatus.bloomed,
      ]) {
        expect(isPlantCareActionable(s), isTrue, reason: '${s.name} 应可养护');
        expect(
          resolveWaterGate(
            status: s,
            day: day,
            waterUsedToday: 0,
            minutesUntilNextWater: 0,
          ),
          isNull,
        );
      }
      expect(isPlantCareActionable(PlantStatus.dead), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V4 · waterRemaining 用**有效上限**（快照字段，不再自己查天气）
  // ───────────────────────────────────────────────────────────────────────────
  group('V4 · PlantCareQuota.waterRemaining 按有效上限算', () {
    PlantCareQuota quotaOf({required int used, required int max}) =>
        PlantCareQuota(
          waterUsedToday: used,
          fertilizeUsedToday: 0,
          minutesUntilNextWater: 0,
          waterBlockReason: null,
          fertilizeBlockReason: null,
          waterQuota: max,
        );

    test('暴雨 0 / 小雨 1 / 普通 3 的剩余次数', () {
      expect(quotaOf(used: 0, max: 0).waterRemaining, 0);
      expect(quotaOf(used: 0, max: 1).waterRemaining, 1);
      expect(quotaOf(used: 1, max: 1).waterRemaining, 0);
      expect(quotaOf(used: 0, max: 3).waterRemaining, 3);
      expect(quotaOf(used: 2, max: 3).waterRemaining, 1);
      expect(quotaOf(used: 3, max: 3).waterRemaining, 0);
    });

    test('clamp 下界：used 超上限（账本脏数据）不得显示负数', () {
      expect(quotaOf(used: 7, max: 3).waterRemaining, 0);
      expect(quotaOf(used: 2, max: 0).waterRemaining, 0);
    });

    test('真实日历：careQuota 的 waterQuota / waterRemaining 随日型变', () async {
      final ctx = _make();
      // 一株「成长中」的向日葵，起点取普通日正午（与后续查询日无关）。
      final Plant p = await ctx.svc.plant(
        'species_sunflower',
          0,
          _noon(kindDays[WeatherKind.sunny]!),
      );

      for (final WeatherKind kind in WeatherKind.values) {
        final DateTime day = _noon(kindDays[kind]!);
        final PlantCareQuota q = await ctx.svc.careQuota(p, day);
        final int expectedMax = WeatherSystem.ofKind(kind).waterQuota;
        expect(q.waterQuota, expectedMax, reason: '${kind.name} 的有效上限');
        expect(q.waterRemaining, expectedMax,
            reason: '${kind.name} 未浇过 ⇒ 剩余 == 有效上限');
        expect(q.waterRemaining, lessThanOrEqualTo(kPlantWaterMaxPerDay));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V5 · 施肥额度与天气无关（9 种日型恒 1，暴雨日仍可施肥）
  // ───────────────────────────────────────────────────────────────────────────
  group('V5 · 施肥不受天气影响（§12.1-Q1：不接 min）', () {
    test('9 种日型的 fertilizeQuota 恒 1 == kPlantFertilizeMaxPerDay', () {
      expect(kPlantFertilizeMaxPerDay, 1);
      for (final WeatherKind kind in WeatherKind.values) {
        expect(WeatherSystem.ofKind(kind).fertilizeQuota, 1,
            reason: '${kind.name} 的施肥额度必须是 1 —— 若将来改，§12.1-Q1 要求'
                '回来接 min，本断言会先红');
      }
    });

    test('resolveFertilizeGate：used=0 恒放行；used>=1 → quota 用尽', () {
      for (final WeatherKind kind in WeatherKind.values) {
        // 施肥判据**没有** day 入参 —— 天气物理上进不来（结构性保证）。
        expect(
          resolveFertilizeGate(
            status: PlantStatus.growing,
            fertilizeUsedToday: 0,
          ),
          isNull,
          reason: '${kind.name}：used=0 必须可施肥',
        );
      }
      final PlantBlockReason? full = resolveFertilizeGate(
        status: PlantStatus.growing,
        fertilizeUsedToday: 1,
      );
      expect(full?.code, PlantOperationError.fertilizeDailyLimit);
      expect(full?.a, kPlantFertilizeMaxPerDay);
      expect(
        resolveFertilizeGate(
          status: PlantStatus.dead,
          fertilizeUsedToday: 0,
        )?.code,
        PlantOperationError.careStateInvalid,
      );
    });

    test('真实日历：暴雨日 canFertilize == true 且 canWater == false', () async {
      final ctx = _make();
      final Plant p = await ctx.svc.plant(
        'species_sunflower',
          0,
          _noon(kindDays[WeatherKind.sunny]!),
      );
      for (final WeatherKind kind in WeatherKind.values) {
        final PlantCareQuota q =
            await ctx.svc.careQuota(p, _noon(kindDays[kind]!));
        expect(q.canFertilize, isTrue,
            reason: 'M-A4-5：${kind.name} 日 used=0 必须可施肥（雨天不禁施肥）');
      }
      final PlantCareQuota rain =
          await ctx.svc.careQuota(p, _noon(kindDays[WeatherKind.rainstorm]!));
      expect(rain.canWater, isFalse, reason: '暴雨日禁浇水');
      expect(rain.waterBlockReason?.code, PlantOperationError.waterRainstorm);
      expect(rain.canFertilize, isTrue, reason: '暴雨日仍要施肥（§9 强制动作）');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V6 · 禁用态渲染：常驻原因 + 灰按钮 + 点了不扣费
  // ───────────────────────────────────────────────────────────────────────────
  group('V6 · 卡片禁用态（常驻原因 + 按钮不可点）', () {
    /// 成长中的向日葵（卡片只读展示，不参与 tick）。
    Plant growingSunflower() {
      final DateTime t = DateTime(2026, 11, 4, 9);
      return Plant(
        id: 'plant-a4',
        speciesId: 'species_sunflower',
        potIndex: 0,
        stage: PlantStage.sprout,
        stageStartedAt: t,
        growthProgress: 0.4,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: t,
      );
    }

    Widget host(PlantCareQuota quota, {VoidCallback? onWater}) => MaterialApp(
          home: L10nScope(
            child: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 320,
                    child: PlantCard(
                      plant: growingSunflower(),
                      species: _sunflower,
                      quota: quota,
                      onWater: onWater,
                      onFertilize: () {}, // 施肥恒可点，隔离出「只有浇水灰」的场景
                      onClear: () {},
                      onShovel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    Future<void> pumpCard(
      WidgetTester tester,
      PlantCareQuota quota, {
      VoidCallback? onWater,
    }) async {
      tester.view.physicalSize = const Size(392 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      AppLocaleController.init(AppLanguage.zh);
      addTearDown(tester.view.reset);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));
      await tester.pumpWidget(host(quota, onWater: onWater));
      await tester.pump(const Duration(milliseconds: 50));
    }

    const PlantCareQuota rainstormQuota = PlantCareQuota(
      waterUsedToday: 0,
      fertilizeUsedToday: 0,
      minutesUntilNextWater: 0,
      waterBlockReason:
          PlantBlockReason(PlantOperationError.waterRainstorm),
      fertilizeBlockReason: null,
      waterQuota: 0,
    );

    testWidgets('暴雨：原因是「雨水代劳」原话，额度显示 0/0，按钮 onPressed 为 null',
        (WidgetTester tester) async {
      await pumpCard(tester, rainstormQuota);

      // ① 原因**常驻可见**（§6.2 / §12.1-Q3：不靠点击触发）。
      expect(
        find.text(zh.garden_care_water_disabled_rainstorm),
        findsOneWidget,
        reason: '卡片必须常驻一句「雨水帮你浇好啦」',
      );
      // ② 额度行按**有效上限**显示（M-A4-3：漏改 waterMax 会显示 0/3）。
      expect(
        find.text(zh.card_quota_left(0, 0, 1, kPlantFertilizeMaxPerDay)),
        findsOneWidget,
        reason: '暴雨日应显示「剩余 0/0」，不是「0/3」',
      );
      expect(
        find.text(zh.card_quota_left(0, kPlantWaterMaxPerDay, 1,
            kPlantFertilizeMaxPerDay)),
        findsNothing,
      );
      // ③ 「灰」的判据是回调被拿掉（不是靠颜色）。
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton).first).onPressed,
        isNull,
        reason: '浇水按钮必须真的不可点（M-A4-6）',
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton).at(1)).onPressed,
        isNotNull,
        reason: '施肥按钮应仍可点（雨天不禁施肥）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点禁用按钮：零回调、零确认卡、零异常（M-A4-6）',
        (WidgetTester tester) async {
      int waterCalls = 0;
      await pumpCard(tester, rainstormQuota, onWater: () => waterCalls++);

      final Finder waterBtn = find.byType(OutlinedButton).first;
      await tester.tap(waterBtn, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));

      expect(waterCalls, 0, reason: '禁用态点下去不得触发浇水（更不得扣费）');
      expect(find.byType(AlertDialog), findsNothing,
          reason: '§12.1-Q3：不得弹确认卡');
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('小雨已浇 1 次：原因是「小雨只浇一次」，额度 0/1',
        (WidgetTester tester) async {
      await pumpCard(
        tester,
        const PlantCareQuota(
          waterUsedToday: 1,
          fertilizeUsedToday: 0,
          minutesUntilNextWater: 0,
          waterBlockReason:
              PlantBlockReason(PlantOperationError.waterLightRain),
          fertilizeBlockReason: null,
          waterQuota: 1,
        ),
      );
      expect(find.text(zh.garden_care_water_disabled_light_rain), findsOneWidget);
      expect(
        find.text(zh.card_quota_left(0, 1, 1, kPlantFertilizeMaxPerDay)),
        findsOneWidget,
      );
    });

    testWidgets('普通日额度用尽：说孩子话术（不是「已达 N 次上限」）',
        (WidgetTester tester) async {
      await pumpCard(
        tester,
        const PlantCareQuota(
          waterUsedToday: 3,
          fertilizeUsedToday: 0,
          minutesUntilNextWater: 0,
          waterBlockReason: PlantBlockReason(
            PlantOperationError.waterDailyLimit,
            a: kPlantWaterMaxPerDay,
          ),
          fertilizeBlockReason: null,
          waterQuota: 3,
        ),
      );
      expect(find.text(zh.garden_care_water_disabled_quota), findsOneWidget);
      // A4 口径分层：卡片上**不得**出现异常路径的账本口吻。
      expect(
        find.text(zh.shared_plant_err_water_daily_limit(kPlantWaterMaxPerDay)),
        findsNothing,
        reason: '卡片常驻原因必须说孩子话术（§6.2），账本口吻只留给异常兜底',
      );
      expect(find.text(zh.card_quota_left(0, 3, 1, kPlantFertilizeMaxPerDay)),
          findsOneWidget);
    });

    testWidgets('施肥额度用尽：原因是「今天已经施过肥啦」', (WidgetTester tester) async {
      await pumpCard(
        tester,
        const PlantCareQuota(
          waterUsedToday: 0,
          fertilizeUsedToday: 1,
          minutesUntilNextWater: 0,
          waterBlockReason: null,
          fertilizeBlockReason: PlantBlockReason(
            PlantOperationError.fertilizeDailyLimit,
            a: kPlantFertilizeMaxPerDay,
          ),
          waterQuota: 3,
        ),
        // 浇水回调必须给：卡片把「回调缺失」也当禁用，不给就测不出
        // 「浇水不受施肥额度影响」这条（会假红）。
        onWater: () {},
      );
      expect(find.text(zh.garden_care_fertilize_disabled_quota), findsOneWidget);
      // 浇水不受影响：仍可点。
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton).first).onPressed,
        isNotNull,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V7 · 一键「无盆可浇」的雨天原因（§12.1-Q2）
  // ───────────────────────────────────────────────────────────────────────────
  group('V7 · 一键浇水 plan 空时的原因（9 种日型穷举）', () {
    test('只有暴雨改说雨天专属原因，其余沿用通用文案', () {
      for (final WeatherKind kind in WeatherKind.values) {
        final String text =
            batchNoneWaterMessage(day: WeatherSystem.ofKind(kind), t: zh);
        final String expected = kind == WeatherKind.rainstorm
            ? zh.garden_batch_none_water_rainstorm
            : zh.garden_batch_none_water;
        expect(text, expected, reason: '${kind.name} 的一键空态文案');
      }
    });

    test('en 侧同样只有暴雨换句（且无 CJK）', () {
      final RegExp cjk = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');
      for (final WeatherKind kind in WeatherKind.values) {
        final String text =
            batchNoneWaterMessage(day: WeatherSystem.ofKind(kind), t: en);
        expect(text, isNotEmpty);
        expect(cjk.hasMatch(text), isFalse, reason: '${kind.name} 的 en 漏翻');
        expect(
          text,
          kind == WeatherKind.rainstorm
              ? en.garden_batch_none_water_rainstorm
              : en.garden_batch_none_water,
        );
      }
    });

    test('Q2 硬约束：一键文案不得与卡片文案逐字重复（同屏两处一样的话）', () {
      expect(
        zh.garden_batch_none_water_rainstorm,
        isNot(zh.garden_care_water_disabled_rainstorm),
        reason: '§12.1-Q2：卡片讲「雨水帮你浇好啦」，一键讲「今天不用一键浇水」',
      );
      expect(
        en.garden_batch_none_water_rainstorm,
        isNot(en.garden_care_water_disabled_rainstorm),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 日历前提（前置于所有依赖 kindDays 的用例）
  // ───────────────────────────────────────────────────────────────────────────
  test('日历前提：2026 年内 9 种日型各至少出现一次（V3/V4/V5 的数据源）', () {
    expect(
      kindDays.keys.toSet(),
      WeatherKind.values.toSet(),
      reason: '9 种日型都必须在 2026 年内出现过，否则上面按日型取代表日的用例会空跑',
    );
    // 顺带把「同一天算两次结论相同」这条纯函数不变量钉住（缓存不得改变结论）。
    for (final WeatherKind kind in WeatherKind.values) {
      final DateTime day = kindDays[kind]!;
      expect(WeatherSystem.ofDay(day).kind, WeatherSystem.ofDay(day).kind);
      expect(dayKey(day), dayKey(DateTime(day.year, day.month, day.day)));
    }
  });
}
