/// 天气系统 A5-a 期 · **§10 感知链路口径重做 + F182 死亡态** 验收守卫（V1~V9）。
///
/// ## 这份文件守的是什么
/// A5-a ① 把卡片那句「每天按时养护，还需约 N 天长成」从**一条错算式**
/// （`remaining / (24/T + 满额养护)`，不看天气、不看额度、不含代劳、复花用首花速率）
/// 换成 `WeatherGrowthMath` 里的两个纯函数。它的风险形态与 A4 同源：
/// **改错了也不抛异常**——
///  · 复花分支漏掉（`bloomCount >= 1` 仍走 `24/T`）⇒ 真值 7~12 天被报成 4 天，
///    数字看着挺合理，没有任何东西会红（这是**线上当前就有的错**，A5 §4.3.1）；
///  · 漏乘 `day.growthFactor` ⇒ 晴天和干旱天报同一个数，孩子看不出天气有用；
///  · 额度不截断 ⇒ 小雨日报「3 次水」、暴雨日仍报 3 次水（A4 刚踩过的同类坑）；
///  · `careQuota` 忘了填 `weather`/`observedAt` ⇒ 卡片永远走 `null` 回退只报百分比，
///    **全部测试绿、线上悄悄降级**（故有 V9）。
///
/// ## 期望值来源（🔴 一律独立于被测物）
/// 本文件**不调用** `WeatherGrowthMath.naturalDailyProgress` /
/// `dailyEstimateProgress` 来当预言机（那是拿被测物自证），而是：
///  · V1/V2：方案 §5.4 的**外部锚** `15.1412` / `6.7741` pp/天（+ `E[rainBonus]=0.04`）；
///  · V3~V5：`prd_params.dart` 的单点常量直接复算；
///  · V6：**真 service 跑一个自然日的 tick**（行为本身当预言机），36 组；
///  · V7/V8/V9：卡片渲染出的**字符串**与快照字段。
///
/// ## 与设计 §9 / §11 的对应
/// | 用例 | 设计项 | 抓的变异 |
/// |---|---|---|
/// | V1 | 加权对账（首花满养护） | M-A5-1 / M-A5-2 / M-A5-4 |
/// | V2 | 加权对账（复花满养护） | M-A5-3 |
/// | V3 | 复花速率线鉴别力 | M-A5-3 |
/// | V4 | 额度截断 | M-A5-2 / M-A5-8 |
/// | V5 | 雨水代劳 | M-A5-1 |
/// | V6 | 行为对账（36 组） | 全部（公式与实现分叉必红） |
/// | V7 | 卡片边界 6 情形 + 单调性 | M-A5-5 / M-A5-6 |
/// | ① | 复花 4 天谬误（team-lead 指定必含） | M-A5-3 |
/// | ② | 首花同 50% 仍是真值（区分度守卫） | M-A5-3 的反向守卫 |
/// | ③ | 干旱 vs 晴同条件天数不同 | M-A5-4 |
/// | ④ | `dead` 态零天数文案 + 进度区折叠（F182） | M-A5-6 |
/// | V9 | 生产路径快照非 null | M-A5-7 |
///
/// ⚠️ 本文件**不含** `pumpAndSettle`：卡片外层若落在花园页上下文里会有无限呼吸动画，
/// 全程有界 `pump`。
library weather_a5_eta_test;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
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
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

import '../helpers/no_hit_random.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 内存桩（与 `weather_a4_quota_test` 同源；只保留本文件用得到的成员）
// ─────────────────────────────────────────────────────────────────────────────

/// 内存阳光账本：append-only。
///
/// V6 的「行为对账」要用到 `countByRefTypeAndRefIdOnDay`（日结批的
/// `wateredOn` / `fertilizedOn` 判据就是这么查的，见 `_WeatherBatch`），
/// 所以这里必须按 `refType / refId / dayKey` **三键过滤**，不能糊成常量 0。
class _MemoryLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double initialBalance = 100000;

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> dayNet(String dayKeyValue) async => entries
      .where((SunlightEntry e) => e.dayKey == dayKeyValue)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKeyValue) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey == dayKeyValue)
          .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey.startsWith(monthKey))
          .fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKeyValue) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == dayKeyValue)
          .length;

  @override
  Future<int> countByRefType(String refType) async => entries
      .where((SunlightEntry e) => e.refType == refType)
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
        .where((SunlightEntry e) =>
            e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }

  @override
  Future<double> earnGrossOnDay(String dayKeyValue) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == dayKeyValue)
      .fold<double>(0.0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String dayKeyValue) async => entries
      .where((SunlightEntry e) =>
          e.type == SunlightType.earn && e.dayKey == dayKeyValue)
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

/// 空专注库：`wfdDays` 恒为空 ⇒ 日结里的 `factor` 恒 1.0。
///
/// V6 是「一天的增量 == 一天的算式」——有效专注日的 1.3 倍会把不确定量引进来，
/// 而 ETA 的展示口径本来也**不含**专注加成（A5 §4.2 没这一项），故这里钉成常量。
class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKeyValue) async =>
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
/// （否则某天恰好 roll 到杂草，成长当天暂停，V6 的算式对账就红）。
({PlantGrowthService svc, _MemoryLedger ledger, _MemoryPlantRepo plants})
    _make() {
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

// ─────────────────────────────────────────────────────────────────────────────
// 物种（`growthHoursPerStage` 一律从种子表读，**不在测试里写死 240 / 480**）
// ─────────────────────────────────────────────────────────────────────────────

/// 普通档：向日葵。
final PlantSpecies _common =
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == 'species_sunflower');

/// 精英档：月光兰（`Rarity.rare` ⇒ `isPremium == true`）。
final PlantSpecies _premium = kSeedPlantSpecies
    .firstWhere((PlantSpecies s) => s.id == 'species_moon_orchid');

/// 就地断言两条前提：档位判定靠 `isPremium`，时长必须**不相同**，
/// 否则「精品 ÷1.5」那条支路在本文件里等于没测。
void _assertSpeciesPremise() {
  expect(_common.isPremium, isFalse);
  expect(_premium.isPremium, isTrue);
  expect(
    _premium.growthHoursPerStage,
    greaterThan(_common.growthHoursPerStage),
    reason: '精英档阶段时长必须更长，否则 V6 的精品支路与普通档无法区分',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 独立复算（预言机）——**绝不调用 `WeatherGrowthMath` 的两个新函数**
// ─────────────────────────────────────────────────────────────────────────────

/// 一天的「满载额度」速率，按 `prd_params.dart` 的常量逐项手算。
///
/// 公式（A5 §4.2）：
/// `daily = natural × g + min(3, quota水) × 水基础 × w + min(1, quota肥) × 肥基础 × f + rainBonus`
///
/// 两个**刻意的取舍**（team-lead §3 铁律「单一事实源」的算式侧）：
///  · 次数取「当日**额度**」而不是「今日**已做**次数」——否则早上 0 次时 N 会虚高数倍；
///  · 只用**今天**的天气（`WeatherSystem.ofDay`），不做未来预报。
class _Oracle {
  _Oracle({
    required this.day,
    required this.growthHoursPerStage,
    required this.bloomCount,
    required this.isPremium,
  });

  final WeatherDay day;
  final double growthHoursPerStage;
  final int bloomCount;
  final bool isPremium;

  /// 精品复花周期的整体放缓倍数（首花不吃）。
  double get premiumDiv => isPremium ? kRebloomPremiumCycleMultiplier : 1.0;

  /// 无天气的自然日速率（progress/天）。
  double get naturalPerDay => bloomCount >= 1
      // 复花：固定 pp/天，与 `growthHoursPerStage` 无关（这是本仓唯一的鉴别点）。
      ? kRebloomAutoProgressPerDay / premiumDiv
      // 首花：24h ÷ 阶段时长 × 自动成长缩放。
      : 24.0 / growthHoursPerStage * kPlantAutoGrowthScale;

  /// 单次浇水的进度增量（复花用复花常量，精品再 ÷ 倍数；首花不吃倍数）。
  double get waterGainPerUse => bloomCount >= 1
      ? kRebloomWaterProgressGain / premiumDiv
      : kPlantWaterProgressGain;

  /// 单次施肥的进度增量（口径同浇水）。
  double get fertilizeGainPerUse => bloomCount >= 1
      ? kRebloomFertilizeProgressGain / premiumDiv
      : kPlantFertilizeProgressGain;

  /// 当日实际可用浇水次数 = `min(满额, 当日额度)`。
  int get waterUses => math.min(kPlantWaterMaxPerDay, day.waterQuota);

  /// 当日实际可用施肥次数 = `min(满额, 当日额度)`。
  int get fertilizeUses => math.min(kPlantFertilizeMaxPerDay, day.fertilizeQuota);

  /// 养护项合计（含天气乘数 `w` / `f`）。
  double get carePerDay =>
      waterUses * waterGainPerUse * day.waterFactor +
      fertilizeUses * fertilizeGainPerUse * day.fertilizeFactor;

  /// 展示口径的一天推进量（**不含**极端日缺失道具的惩罚，那是日结侧的事）。
  double get daily =>
      naturalPerDay * day.growthFactor + carePerDay + day.rainWaterBonusPp;

  /// 极端日「缺一个道具」的惩罚（桩账本查不到道具 ⇒ 本文件恒为 −1pp）。
  ///
  /// 干燥 / 暴雨 / 大风 / 极寒 四类各有一项「强制动作 + 棚」；本文件的 V6 一律
  /// 把浇水 / 施肥**做满**，所以只剩「没买棚」这一项会被罚。温和 5 种不罚。
  double get shelterPenalty =>
      day.kind.isMild ? 0.0 : -kWeatherPenaltyPerMissingItem;

  /// 「还要约几天」：向上取整，最少 1 天、最多 999 天。
  int daysFor(double remaining) => (remaining / daily).ceil().clamp(1, 999);
}

/// 在 [year] 年内找出**每种日型的第一个自然日**（期望值不写死日期）。
///
/// 9 种日型权重最小 3%（暴雨）⇒ 一年内必然全部出现；末尾的完整性断言把这条前提钉住。
Map<WeatherKind, DateTime> _firstDayOfEachKind(int year) {
  final Map<WeatherKind, DateTime> found = <WeatherKind, DateTime>{};
  DateTime d = DateTime(year, 1, 1);
  while (d.year == year) {
    found.putIfAbsent(WeatherSystem.ofDay(d).kind, () => d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return found;
}

// ─────────────────────────────────────────────────────────────────────────────
// 卡片夹具
// ─────────────────────────────────────────────────────────────────────────────

/// 成长中的植物（卡片只读展示，不参与 tick）。
Plant _growingPlant({
  required String id,
  required String speciesId,
  required double progress,
  required PlantStage stage,
  int bloomCount = 0,
  PlantStatus status = PlantStatus.growing,
  DateTime? deadAt,
  DateTime? bloomedAt,
}) {
  final DateTime t = DateTime(2026, 11, 4, 9);
  return Plant(
    id: id,
    speciesId: speciesId,
    potIndex: 0,
    stage: stage,
    stageStartedAt: t,
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: t,
    deadAt: deadAt,
    bloomedAt: bloomedAt,
    bloomCount: bloomCount,
  );
}

/// 把「当日天气快照」原样塞进额度对象（生产路径由 `careQuota` 填，见 V9）。
PlantCareQuota _quotaWith(
  WeatherDay day, {
  DateTime? observedAt,
  int waterUsedToday = 0,
}) =>
    PlantCareQuota(
      waterUsedToday: waterUsedToday,
      fertilizeUsedToday: 0,
      minutesUntilNextWater: 0,
      waterBlockReason: null,
      fertilizeBlockReason: null,
      waterQuota: math.min(kPlantWaterMaxPerDay, day.waterQuota),
      weather: day,
      observedAt: observedAt ?? DateTime(2026, 11, 4, 9),
    );

/// 从渲染结果里**读回**「还需约 N 天」的 N（不靠内部字段，靠孩子看见的那句话）。
int _renderedDays(WidgetTester tester) {
  final RegExp re = RegExp(r'还需约\s*(\d+)\s*天');
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    final String? data = t.data;
    if (data == null) continue;
    final RegExpMatch? m = re.firstMatch(data);
    if (m != null) return int.parse(m.group(1)!);
  }
  fail('卡片上没有「还需约 N 天长成」这行字（可能退化成了只报百分比）');
}

/// 卡片渲染出的**全部**文案（用于「某类文案一个字都不该有」的断言）。
List<String> _allTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .toList(growable: false);

void main() {
  final AppLocalizations zh = AppLocalizationsZh();

  final Map<WeatherKind, DateTime> kindDays = _firstDayOfEachKind(2026);

  // 夹具前提必须是**真的测试**：`expect` 不能在 `main()` 顶层裸调
  // （会抛 `OutsideTestException`，整个文件连加载都失败）。
  test('夹具前提 · 两个物种档位与时长真的不同（否则精品支路等于没测）',
      _assertSpeciesPremise);

  /// 每种日型的 `WeatherDay`（纯表，与日历无关；V1/V2/V4/V5 用它）。
  WeatherDay dayOf(WeatherKind kind) => WeatherSystem.ofKind(kind);

  // ───────────────────────────────────────────────────────────────────────────
  // V1 · 加权对账（普通首花满养护）：外部锚 = 方案 §5.4 的 15.1412 + 0.04
  // ───────────────────────────────────────────────────────────────────────────
  test('V1 · Σ P(d)×estimate(d) == §5.4 的 15.1412 + E[rainBonus]=0.04', () {
    final _Oracle oracle = _Oracle(
      day: dayOf(WeatherKind.sunny), // 占位；V1 逐日替换
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 0,
      isPremium: false,
    );

    double weighted = 0.0;
    for (final WeatherKind kind in WeatherKind.values) {
      final WeatherDay d = dayOf(kind);
      final double p = WeatherSystem.weightOf(kind) / 100.0;
      final double estimate = WeatherGrowthMath.dailyEstimateProgress(
        day: d,
        // 🔴 自然项取**生产装配值**（卡片就是这么传的），而不是测试自己算的：
        // 否则 `naturalDailyProgress` 分岔了 V1 也不会红（V3 已实测到这一点）。
        naturalGainPerDay: WeatherGrowthMath.naturalDailyProgress(
          growthHoursPerStage: _common.growthHoursPerStage,
          bloomCount: 0,
          isPremium: false,
        ),
        waterGainPerUse: oracle.waterGainPerUse,
        fertilizeGainPerUse: oracle.fertilizeGainPerUse,
      );
      weighted += p * estimate;
    }

    expect(
      weighted * 100.0,
      closeTo(15.1812, 1e-3),
      reason: '方案 §5.4 首花满养护 15.1412pp/天 + E[rainBonus]=0.04 ⇒ 15.1812。'
          '（逐月权重表上线后：15.1262 → 15.1412，暴雨 3% → 4% 让 bonus 0.03 → 0.04。）'
          'M-A5-1（删 bonus）/ M-A5-2（额度不截断）/ M-A5-4（漏乘 g）都会把它拉走',
    );
    // 顺带把「权重合计 100」这条前提显式钉一次，否则上面的加权值只是巧合。
    int totalWeight = 0;
    for (final WeatherKind kind in WeatherKind.values) {
      totalWeight += WeatherSystem.weightOf(kind);
    }
    expect(totalWeight, 100);
    // 双保险：生产装配的自然项必须等于手算的 `24/T`（首花）。
    expect(
      WeatherGrowthMath.naturalDailyProgress(
        growthHoursPerStage: _common.growthHoursPerStage,
        bloomCount: 0,
        isPremium: false,
      ),
      closeTo(oracle.naturalPerDay, 1e-12),
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V2 · 加权对账（普通复花满养护）：6.7741 + 0.04
  // ───────────────────────────────────────────────────────────────────────────
  test('V2 · 复花 Σ P(d)×estimate(d) == 6.7741 + 0.04（与首花完全不同的量级）', () {
    final _Oracle oracle = _Oracle(
      day: dayOf(WeatherKind.sunny),
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 1,
      isPremium: false,
    );

    double weighted = 0.0;
    for (final WeatherKind kind in WeatherKind.values) {
      final WeatherDay d = dayOf(kind);
      weighted += WeatherSystem.weightOf(kind) /
          100.0 *
          WeatherGrowthMath.dailyEstimateProgress(
            day: d,
            // 同 V1：自然项取生产装配值，让「复花支路漏掉」在这里也有第二次命中。
            naturalGainPerDay: WeatherGrowthMath.naturalDailyProgress(
              growthHoursPerStage: _common.growthHoursPerStage,
              bloomCount: 1,
              isPremium: false,
            ),
            waterGainPerUse: oracle.waterGainPerUse,
            fertilizeGainPerUse: oracle.fertilizeGainPerUse,
          );
    }

    expect(
      weighted * 100.0,
      closeTo(6.8141, 1e-3),
      reason: '复花满养护 6.7741pp/天 + 0.04 ⇒ 6.8141。'
          '（逐月权重表上线后由 6.8623 派生：auto 3.6×E[g] 0.9280→0.9565、'
          '养护项随 E[w]/E[f] 变化；doc §5.4 的复花子表尚未同步，见交付报告。）'
          'M-A5-3（复花误用 24/T）会让它跳到 15.1812',
    );
    expect(oracle.naturalPerDay, kRebloomAutoProgressPerDay);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V3 · 复花速率线鉴别力（D5 复发的唯一护栏）
  // ───────────────────────────────────────────────────────────────────────────
  group('V3 · naturalDailyProgress 的复花支路', () {
    test('复花 = 0.036/天（普通），且 ≠ 首花的 24/T', () {
      final double first = WeatherGrowthMath.naturalDailyProgress(
        growthHoursPerStage: _common.growthHoursPerStage,
        bloomCount: 0,
        isPremium: false,
      );
      final double rebloom = WeatherGrowthMath.naturalDailyProgress(
        growthHoursPerStage: _common.growthHoursPerStage,
        bloomCount: 1,
        isPremium: false,
      );

      expect(rebloom, kRebloomAutoProgressPerDay,
          reason: '普通复花必须逐位等于常量 0.036');
      expect(first, closeTo(24.0 / _common.growthHoursPerStage, 1e-12));
      expect(rebloom, isNot(closeTo(first, 1e-6)),
          reason: 'M-A5-3：复花误用 24/T 时这两个数会相等');
      expect(first / rebloom, closeTo(2.78, 0.01),
          reason: '量级差 2.78 倍（方案 :263 记的「差近 1 倍」说的是养护项，'
              '自然项差 2.78 倍）');
    });

    test('精品复花 = 0.036 ÷ 1.5；首花不吃这个倍数', () {
      final double rebloomPremium = WeatherGrowthMath.naturalDailyProgress(
        growthHoursPerStage: _premium.growthHoursPerStage,
        bloomCount: 3,
        isPremium: true,
      );
      expect(
        rebloomPremium,
        closeTo(kRebloomAutoProgressPerDay / kRebloomPremiumCycleMultiplier, 1e-12),
      );
      // 首花精品只慢在 `growthHoursPerStage`（480h），**不再**额外 ÷1.5。
      final double firstPremium = WeatherGrowthMath.naturalDailyProgress(
        growthHoursPerStage: _premium.growthHoursPerStage,
        bloomCount: 0,
        isPremium: true,
      );
      expect(
        firstPremium,
        closeTo(24.0 / _premium.growthHoursPerStage, 1e-12),
        reason: '首花若被误 ÷1.5 ⇒ 精品首花会慢到 0.0333/天（实际 0.05）',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V4 · 额度截断（小雨 1 / 暴雨 0）+ `isWater` 未接反
  // ───────────────────────────────────────────────────────────────────────────
  group('V4 · dailyEstimateProgress 的额度截断', () {
    /// 只留浇水项的估计值（自然项与施肥项喂 0）——这样差值就是「浇水项」。
    double waterTerm(WeatherDay d, double gainPerUse) =>
        WeatherGrowthMath.dailyEstimateProgress(
          day: d,
          naturalGainPerDay: 0.0,
          waterGainPerUse: gainPerUse,
          fertilizeGainPerUse: 0.0,
        );

    test('小雨：浇水项 == 1 次 × (0.01 × w)（不是 3 次）', () {
      final WeatherDay d = dayOf(WeatherKind.lightRain);
      expect(d.waterQuota, kWeatherLightRainWaterQuota);
      final double term =
          waterTerm(d, kPlantWaterProgressGain) - waterTerm(d, 0.0);
      expect(
        term,
        closeTo(1 * kPlantWaterProgressGain * d.waterFactor, 1e-12),
        reason: 'M-A5-2：不截断会算成 3 次 ⇒ 小雨日 ETA 虚快 3 倍',
      );
      expect(term, isNot(closeTo(3 * kPlantWaterProgressGain * d.waterFactor, 1e-12)));
    });

    test('暴雨：浇水项 == 0（额度 0 + bonus 不被差值吃掉）', () {
      final WeatherDay d = dayOf(WeatherKind.rainstorm);
      expect(d.waterQuota, kWeatherRainstormWaterQuota);
      final double term =
          waterTerm(d, kPlantWaterProgressGain) - waterTerm(d, 0.0);
      expect(term, closeTo(0.0, 1e-12),
          reason: 'M-A5-2：暴雨日浇水项必须为 0；差值能正常算出 0 也证明 '
              'rainBonus 在两次调用里被同减掉了');
    });

    test('`isWater` 没有接反：浇水吃 w、施肥吃 f', () {
      // 极寒：w=1.10 / f=1.50（两者差得最开，接反立刻露）。
      final WeatherDay d = dayOf(WeatherKind.cold);
      final int waterUses = math.min(kPlantWaterMaxPerDay, d.waterQuota);
      final int fertUses = math.min(kPlantFertilizeMaxPerDay, d.fertilizeQuota);
      final double waterOnly = WeatherGrowthMath.dailyEstimateProgress(
        day: d,
        naturalGainPerDay: 0.0,
        waterGainPerUse: 0.01,
        fertilizeGainPerUse: 0.0,
      );
      final double fertOnly = WeatherGrowthMath.dailyEstimateProgress(
        day: d,
        naturalGainPerDay: 0.0,
        waterGainPerUse: 0.0,
        fertilizeGainPerUse: 0.01,
      );
      // ⚠️ 次数是 `min(满额, 当日额度)`（极寒额度是默认值 3 水 1 肥），
      //    这里不写死 1 —— 本用例测的是「乘数接没接反」，不是次数。
      expect(waterOnly, closeTo(waterUses * 0.01 * d.waterFactor, 1e-12));
      expect(fertOnly, closeTo(fertUses * 0.01 * d.fertilizeFactor, 1e-12));
      expect(d.fertilizeFactor, greaterThan(d.waterFactor),
          reason: '极寒的 f > w 是本用例的鉴别力前提');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V5 · 雨水代劳（+1pp，只在暴雨）
  // ───────────────────────────────────────────────────────────────────────────
  test('V5 · estimate(暴雨) − estimate(暴雨去 bonus) == 0.01', () {
    final WeatherDay withBonus = dayOf(WeatherKind.rainstorm);
    final WeatherDay noBonus = WeatherDay(
      kind: withBonus.kind,
      growthFactor: withBonus.growthFactor,
      waterFactor: withBonus.waterFactor,
      fertilizeFactor: withBonus.fertilizeFactor,
      waterQuota: withBonus.waterQuota,
      fertilizeQuota: withBonus.fertilizeQuota,
      rainWaterBonusPp: 0.0,
    );
    expect(withBonus.rainWaterBonusPp, kWeatherRainstormWaterBonusPp);

    double est(WeatherDay d) => WeatherGrowthMath.dailyEstimateProgress(
          day: d,
          naturalGainPerDay: 0.1,
          waterGainPerUse: kPlantWaterProgressGain,
          fertilizeGainPerUse: kPlantFertilizeProgressGain,
        );

    expect(
      est(withBonus) - est(noBonus),
      closeTo(kWeatherRainstormWaterBonusPp, 1e-12),
      reason: 'M-A5-1：删掉 bonus ⇒ 差值为 0',
    );

    // 温和日不得凭空带 bonus（表格不变量）。
    for (final WeatherKind kind in WeatherKind.values) {
      final double expected =
          kind == WeatherKind.rainstorm ? kWeatherRainstormWaterBonusPp : 0.0;
      expect(dayOf(kind).rainWaterBonusPp, expected, reason: kind.name);
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V6 · 行为对账：真 service 跑一个自然日的 tick（36 组）
  // ───────────────────────────────────────────────────────────────────────────
  //
  // 这是最强的一条：**不比较公式，比较行为**。
  // 夹具要点（四个都已在本文件里被别处钉住）：
  //  ① 起点 = 自然日零点、终点 = 次日零点 ⇒ `segHours` 恰好 24.0、`!dayEnd.isAfter(now)`
  //     恰好成立一次（惩罚与 rainBonus 都只结算一次）；
  //  ② 无有效专注日 ⇒ `factor` = 1.0；
  //  ③ `weedRandom` 永不命中 ⇒ 不会因为杂草暂停成长；
  //  ④ 浇水 / 施肥都在**同一个自然日内**完成（间隔 31 分钟绕开 30 分钟浇水冷却）。
  group('V6 · 一天的实测增量 == 一天的算式（9 日型 × 普通/精品 × 首花/复花）', () {
    Future<double> oneDayDelta({
      required DateTime dayStart,
      required PlantSpecies sp,
      required bool rebloom,
    }) async {
      final ctx = _make();
      final Plant seed = Plant(
        id: 'plant-v6',
        speciesId: sp.id,
        potIndex: 0,
        stage: rebloom ? PlantStage.adult : PlantStage.sprout,
        stageStartedAt: dayStart,
        // 首花取 0.4（与 A4 的夹具同源，离上下边界都够远）；
        // 复花取 0.5 = `_applyBloomCycle` 花谢后回落的**真值**（不是随手编的数）。
        growthProgress: rebloom ? kBloomWiltProgressFloor : 0.4,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: dayStart,
        bloomCount: rebloom ? 1 : 0,
      );
      await ctx.plants.savePlant(seed);

      final WeatherDay wd = WeatherSystem.ofDay(dayStart);
      final int waterUses = math.min(kPlantWaterMaxPerDay, wd.waterQuota);
      for (int i = 0; i < waterUses; i++) {
        await ctx.svc.water(
          seed.id,
          dayStart.add(Duration(minutes: 5 + 31 * i)),
        );
      }
      final int fertUses = math.min(kPlantFertilizeMaxPerDay, wd.fertilizeQuota);
      for (int i = 0; i < fertUses; i++) {
        await ctx.svc.fertilize(
          seed.id,
          dayStart.add(Duration(minutes: 5 + 31 * waterUses + 1 + 31 * i)),
        );
      }

      await ctx.svc.tickAll(dayStart.add(const Duration(days: 1)));
      final Plant after = (await ctx.plants.plant(seed.id))!;
      expect(after.stage, seed.stage, reason: '一天不可能跨阶段（首花一阶段要 240h）');
      expect(after.growthProgress, lessThan(1.0),
          reason: '夹具前提：一天的增量不得把进度推满，否则 clamp 会吃掉差值');
      return after.growthProgress - seed.growthProgress;
    }

    for (final WeatherKind kind in WeatherKind.values) {
      for (final bool premium in <bool>[false, true]) {
        for (final bool rebloom in <bool>[false, true]) {
          final PlantSpecies sp = premium ? _premium : _common;
          test(
            'V6 · ${kind.name} / ${premium ? '精品' : '普通'} / '
            '${rebloom ? '复花' : '首花'}',
            () async {
              final DateTime dayStart = kindDays[kind]!;
              final WeatherDay wd = WeatherSystem.ofDay(dayStart);
              expect(wd.kind, kind, reason: '日历前提：这天确实是 ${kind.name}');

              final _Oracle oracle = _Oracle(
                day: wd,
                growthHoursPerStage: sp.growthHoursPerStage,
                bloomCount: rebloom ? 1 : 0,
                isPremium: premium,
              );
              final double actual =
                  await oneDayDelta(dayStart: dayStart, sp: sp, rebloom: rebloom);
              final double expected = oracle.daily + oracle.shelterPenalty;

              expect(
                actual,
                closeTo(expected, 1e-6),
                reason: '实测 ${actual.toStringAsFixed(6)} vs 算式 '
                    '${expected.toStringAsFixed(6)}（展示口径 '
                    '${oracle.daily.toStringAsFixed(6)} + 缺棚惩罚 '
                    '${oracle.shelterPenalty}）—— 任何「公式与实现分叉」在这条必红',
              );
            },
          );
        }
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V7 · 卡片边界（① 已长满容差 ② N==1 ③ dead 见 ④ ④ 单调性）
  // ───────────────────────────────────────────────────────────────────────────
  group('V7 · 卡片渲染', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required Plant plant,
      required PlantSpecies species,
      PlantCareQuota? quota,
    }) async {
      tester.view.physicalSize = const Size(392 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      AppLocaleController.init(AppLanguage.zh);
      addTearDown(tester.view.reset);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));
      await tester.pumpWidget(
        MaterialApp(
          home: L10nScope(
            child: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 320,
                    child: PlantCard(
                      plant: plant,
                      species: species,
                      quota: quota,
                      onWater: () {},
                      onFertilize: () {},
                      onClear: () {},
                      onShovel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 有界 pump（不含 pumpAndSettle）。
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('V7① · remaining ≤ 1e-3 ⇒ 「即将进入下一阶段」，且容差就是 1e-3',
        (WidgetTester tester) async {
      // 0.9999 ⇒ remaining = 1e-4：1e-3 口径下命中，1e-9 口径下不命中。
      await pumpCard(
        tester,
        plant: _growingPlant(
          id: 'p-v7a',
          speciesId: _common.id,
          progress: 0.9999,
          stage: PlantStage.sprout,
        ),
        species: _common,
        quota: _quotaWith(dayOf(WeatherKind.sunny)),
      );
      expect(find.text(zh.card_hint_next_soon), findsOneWidget);

      // 0.998 ⇒ remaining = 2e-3 > 1e-3：必须仍然报天数（不能并进「即将…」）。
      await pumpCard(
        tester,
        plant: _growingPlant(
          id: 'p-v7b',
          speciesId: _common.id,
          progress: 0.998,
          stage: PlantStage.sprout,
        ),
        species: _common,
        quota: _quotaWith(dayOf(WeatherKind.sunny)),
      );
      expect(find.text(zh.card_hint_next_soon), findsNothing);
      expect(_renderedDays(tester), 1);
    });

    testWidgets('V7② · N == 1 时文案里就是 1（不会出现 0 天）',
        (WidgetTester tester) async {
      final WeatherDay d = dayOf(WeatherKind.sunny);
      final _Oracle oracle = _Oracle(
        day: d,
        growthHoursPerStage: _common.growthHoursPerStage,
        bloomCount: 0,
        isPremium: false,
      );
      // 让 remaining/daily ∈ (0, 1] ⇒ 向上取整得 1。
      final double progress = 1.0 - oracle.daily * 0.8;
      await pumpCard(
        tester,
        plant: _growingPlant(
          id: 'p-v7c',
          speciesId: _common.id,
          progress: progress,
          stage: PlantStage.sprout,
        ),
        species: _common,
        quota: _quotaWith(d),
      );
      expect(_renderedDays(tester), 1);
      expect(find.text(zh.card_hint_grow_days(1)), findsOneWidget);
    });

    testWidgets('V7④ · 同一天内 progress 递增 ⇒ N 不增（用「额度」而非「已做次数」的护栏）',
        (WidgetTester tester) async {
      final WeatherDay d = dayOf(WeatherKind.drought);
      final _Oracle oracle = _Oracle(
        day: d,
        growthHoursPerStage: _common.growthHoursPerStage,
        bloomCount: 0,
        isPremium: false,
      );
      int previous = 1 << 30;
      for (int i = 1; i <= 20; i++) {
        final double progress = 0.05 * i; // 0.05 .. 1.00
        if (progress >= 1.0 - 0.001) break;
        await pumpCard(
          tester,
          plant: _growingPlant(
            id: 'p-v7d$i',
            speciesId: _common.id,
            progress: progress,
            stage: PlantStage.sprout,
          ),
          species: _common,
          quota: _quotaWith(d),
        );
        final int days = _renderedDays(tester);
        expect(days, oracle.daysFor(1.0 - progress),
            reason: 'progress=$progress 时 N 必须是算式值（M-A5-5：'
                '若改成「已做次数」，早晨 0 次会让 N 暴涨且随时刻漂移）');
        expect(days, lessThanOrEqualTo(previous),
            reason: 'progress=$progress 时 N=$days 比上一档 $previous 还大 ⇒ 非单调');
        previous = days;
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // ① 复花 4 天谬误（team-lead 指定必含）
  // ───────────────────────────────────────────────────────────────────────────
  //
  // 🔴 复花开的**唯一**鉴别器是 `bloomCount`：花谢后进度恰好回到 0.5，
  //    所以「按数字反查」一定误命中首花（A5 §4.3.1）。本用例与 ② 用**同一天气、
  //    同一进度**，只差 `bloomCount`，把这条鉴别力钉死。
  testWidgets('① · 复花开 50% 时不再是 4 天（真值 7 天）', (WidgetTester tester) async {
    // 微风：首花 4 天、复花 7 天 —— 同一天气下 4 vs 7，区分度最大。
    final WeatherDay d = dayOf(WeatherKind.breeze);
    final _Oracle oracle = _Oracle(
      day: d,
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 1,
      isPremium: false,
    );
    const double startProgress = kBloomWiltProgressFloor; // = 0.5
    expect(startProgress, 0.5, reason: '花谢回落点就是 0.5（`_applyBloomCycle`）');
    expect(oracle.daysFor(1.0 - startProgress), 7,
        reason: '手表算：微风复花 0.07272/天 ⇒ 0.5/0.07272 = 6.88 ⇒ 7 天');

    tester.view.physicalSize = const Size(392 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    AppLocaleController.init(AppLanguage.zh);
    addTearDown(tester.view.reset);
    addTearDown(() => AppLocaleController.init(AppLanguage.system));
    await tester.pumpWidget(
      MaterialApp(
        home: L10nScope(
          child: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: PlantCard(
                    plant: _growingPlant(
                      id: 'p-rebloom',
                      speciesId: _common.id,
                      progress: startProgress,
                      stage: PlantStage.adult,
                      bloomCount: 1, // ← 唯一鉴别器
                    ),
                    species: _common,
                    quota: _quotaWith(d),
                    onWater: () {},
                    onFertilize: () {},
                    onClear: () {},
                    onShovel: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(_renderedDays(tester), 7,
        reason: 'M-A5-3：复花误用 24/T 时这里会变成 4（线上当前就是这个错）');
    expect(find.text(zh.card_hint_grow_days(4)), findsNothing,
        reason: '4 天正是「按首花速率算复花」的错值，卡片上不许出现');
    expect(find.text(zh.card_hint_grow_days(7)), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // ② 首花同 50%（区分度守卫：② 必须仍然算得对，不能靠「把 4 改大」过关）
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('② · 首花同天气同 50% 仍是 4 天', (WidgetTester tester) async {
    final WeatherDay d = dayOf(WeatherKind.breeze);
    final _Oracle oracle = _Oracle(
      day: d,
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 0,
      isPremium: false,
    );
    expect(oracle.daysFor(0.5), 4,
        reason: '手表算：微风首花 0.162/天 ⇒ 0.5/0.162 = 3.09 ⇒ 4 天');

    tester.view.physicalSize = const Size(392 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    AppLocaleController.init(AppLanguage.zh);
    addTearDown(tester.view.reset);
    addTearDown(() => AppLocaleController.init(AppLanguage.system));
    await tester.pumpWidget(
      MaterialApp(
        home: L10nScope(
          child: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: PlantCard(
                    plant: _growingPlant(
                      id: 'p-first',
                      speciesId: _common.id,
                      progress: 0.5,
                      stage: PlantStage.sprout,
                      bloomCount: 0, // ← 首花
                    ),
                    species: _common,
                    quota: _quotaWith(d),
                    onWater: () {},
                    onFertilize: () {},
                    onClear: () {},
                    onShovel: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(_renderedDays(tester), 4,
        reason: '首花 50% 就该是 4 天 —— 若这条也变了，说明改动把两档一起改错了');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // ③ 天气真的进了算式：干旱 vs 晴
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('③ · 干旱日与晴日同条件天数不同（天气进了算式）', (WidgetTester tester) async {
    /// 只渲染一张卡并把 N 读回来。
    Future<int> daysOn(WeatherKind kind) async {
      final WeatherDay d = dayOf(kind);
      tester.view.physicalSize = const Size(392 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      AppLocaleController.init(AppLanguage.zh);
      await tester.pumpWidget(
        MaterialApp(
          home: L10nScope(
            child: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 320,
                    child: PlantCard(
                      plant: _growingPlant(
                        id: 'p-${kind.name}',
                        speciesId: _common.id,
                        progress: 0.5,
                        // 🔴 必须用**首花**：复花下干旱与晴恰好都算 7 天
                        //    （干旱靠 w=3.00 追回自然项的亏空），用复花会假通过。
                        stage: PlantStage.sprout,
                        bloomCount: 0,
                      ),
                      species: _common,
                      quota: _quotaWith(d),
                      onWater: () {},
                      onFertilize: () {},
                      onClear: () {},
                      onShovel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return _renderedDays(tester);
    }

    addTearDown(tester.view.reset);
    addTearDown(() => AppLocaleController.init(AppLanguage.system));

    final int sunny = await daysOn(WeatherKind.sunny);
    final int drought = await daysOn(WeatherKind.drought);

    final int expectedSunny = _Oracle(
      day: dayOf(WeatherKind.sunny),
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 0,
      isPremium: false,
    ).daysFor(0.5);
    final int expectedDrought = _Oracle(
      day: dayOf(WeatherKind.drought),
      growthHoursPerStage: _common.growthHoursPerStage,
      bloomCount: 0,
      isPremium: false,
    ).daysFor(0.5);

    expect(sunny, expectedSunny, reason: '晴日手表算 $expectedSunny 天');
    expect(drought, expectedDrought, reason: '干旱日手表算 $expectedDrought 天');
    expect(sunny, isNot(drought),
        reason: 'M-A5-4：漏乘 g（或根本不看天气）时两天的 N 会相等');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // ④ dead 态：零天数文案 + 进度区整块折叠（F182）
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('④ · dead 态没有任何天数文案，且进度条整块被折叠（F182）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(392 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    AppLocaleController.init(AppLanguage.zh);
    addTearDown(tester.view.reset);
    addTearDown(() => AppLocaleController.init(AppLanguage.system));

    final DateTime t = DateTime(2026, 11, 4, 9);
    await tester.pumpWidget(
      MaterialApp(
        home: L10nScope(
          child: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: PlantCard(
                    plant: _growingPlant(
                      id: 'p-dead',
                      speciesId: _common.id,
                      progress: 0.42,
                      stage: PlantStage.adult,
                      status: PlantStatus.dead,
                      deadAt: t,
                    ),
                    species: _common,
                    // 天气照给：证明「不显示天数」是 `dead` 分支干的事，
                    // 不是因为缺快照才退化。
                    quota: _quotaWith(dayOf(WeatherKind.sunny)),
                    onWater: () {},
                    onFertilize: () {},
                    onClear: () {},
                    onShovel: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final List<String> texts = _allTexts(tester);

    // ① 三种「进度承诺」类文案一个字都不许有（F182 的正面要求）。
    expect(texts.any((String s) => s.contains('还需约')), isFalse,
        reason: 'M-A5-6：删掉 dead 分支时这里会渲染「还需约 N 天长成」');
    expect(texts.any((String s) => s.contains('天长成')), isFalse);
    expect(texts.any((String s) => s.contains('本阶段成长')), isFalse,
        reason: '百分比兜底同样不该出现');
    expect(texts.any((String s) => s.contains('即将进入下一阶段')), isFalse);
    expect(find.text(zh.card_hint_next_soon), findsNothing);

    // ② 进度条整块折叠（team-lead 追加裁定：进度条是「还会继续长」的暗示）。
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'F182：死亡态必须把进度区整块拿掉，只留徽章 + 清除按钮');

    // ③ 该留的还在：状态徽章（成株 · 已死亡）+ 清除按钮。
    expect(find.text('${zh.card_stage_adult} · ${zh.card_status_dead}'),
        findsOneWidget);
    expect(find.text(zh.card_action_clear), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // V9 · 生产路径：careQuota 必须真的把天气快照塞进来（M-A5-7）
  // ───────────────────────────────────────────────────────────────────────────
  group('V9 · careQuota 的天气快照', () {
    test('weather / observedAt 均非 null，且 weather 就是那一刻的 ofDay', () async {
      final ctx = _make();
      final DateTime plantedAt = DateTime(2026, 3, 10, 9);
      final Plant p = await ctx.svc.plant(_common.id, 0, plantedAt);
      final DateTime now = DateTime(2026, 3, 10, 9, 30);
      final PlantCareQuota q = await ctx.svc.careQuota(p, now);

      expect(q.weather, isNotNull,
          reason: 'M-A5-7：不传 weather ⇒ 卡片永远走 null 回退只报百分比，'
              '全部测试绿但线上用旧口径');
      expect(q.observedAt, now,
          reason: '两个 hint 共用同一瞬间的时钟基准（不再各自 DateTime.now()）');
      expect(q.weather!.kind, WeatherSystem.ofDay(now).kind);
      expect(q.weather!.growthFactor, WeatherSystem.ofDay(now).growthFactor);
      expect(q.waterQuota, math.min(kPlantWaterMaxPerDay, q.weather!.waterQuota),
          reason: '额度与天气必须来自**同一次** ofDay（跨零点错位的防线）');
    });

    testWidgets('快照缺失 ⇒ 退化为「只报百分比」，绝不编造天数', (WidgetTester tester) async {
      // 老库 / 手工构造的额度对象（weather 为 null）——正是 A4 期 7 处构造点的形态，
      // 也是 A5 把两个新字段做成**可选**的理由（零侵入既有构造点）。
      const PlantCareQuota noWeather = PlantCareQuota(
        waterUsedToday: 0,
        fertilizeUsedToday: 0,
        minutesUntilNextWater: 0,
        waterBlockReason: null,
        fertilizeBlockReason: null,
        waterQuota: kPlantWaterMaxPerDay,
      );
      expect(noWeather.weather, isNull);
      expect(noWeather.observedAt, isNull);

      tester.view.physicalSize = const Size(392 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      AppLocaleController.init(AppLanguage.zh);
      addTearDown(tester.view.reset);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));
      await tester.pumpWidget(
        MaterialApp(
          home: L10nScope(
            child: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 320,
                    child: PlantCard(
                      plant: _growingPlant(
                        id: 'p-fallback',
                        speciesId: _common.id,
                        progress: 0.42,
                        stage: PlantStage.sprout,
                      ),
                      species: _common,
                      quota: noWeather,
                      onWater: () {},
                      onFertilize: () {},
                      onClear: () {},
                      onShovel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final List<String> texts = _allTexts(tester);
      expect(texts.any((String s) => s.contains('天长成')), isFalse,
          reason: '没有天气快照时不许报天数（宁可只说百分比）');
      expect(find.text(zh.card_hint_progress(42)), findsOneWidget);
      // 进度条仍在（只有 dead 才折叠，见 ④）。
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
