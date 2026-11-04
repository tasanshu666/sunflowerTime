/// 植物成长 V2 回归测试（玄参大人 2026-09-22 拍板口径）。
///
/// 覆盖两件事：
///  ① **幂等**：`_advanceGrowth` 的 `stage_started_at` 必须在每次 tick 后推进到 now，
///     否则每次 `tickAll` 都会把「stage_started_at → now」整段时间**重复累加**
///     （真机：浇水标注 +12%、实际阶段进度跳 21%）。判据是**增量**，不是「跑通了」：
///       · 同一时刻重复 tick → 增量必须为 0（页面刷新多少次都不许涨）；
///       · 相邻两次 tick（间隔 24h）→ 两次增量必须**相等**（0.1），不是 0.1 / 0.2。
///  ② **数值口径**：
///       · 普通植物（240h/阶段）完全不养护 → 正好 30 天长成（bloomed）；
///       · 每天满养护（3 次浇水 +3%、1 次施肥 +3%）→ 约 19 天长成；
///       · 精品植物（480h/阶段）完全不养护 → 60 天长成。
///
/// 纯 Dart：仓储以内存 Fake 实现，不依赖 Drift / Flutter。
library plant_growth_v2_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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

/// 无任何专注会话：成长系数为 1.0（隔离「不养护」场景）。
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

/// 账本 Fake：余额恒充足（测成长不看经济），但养护次数 / 上次时间按真实记录。
class _MemLedgerRepo implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

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
  ) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;

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

({
  PlantGrowthService svc,
  _MemPlantRepo plants,
}) _make({
  double hoursPerStage = kPlantGrowthHoursPerStageDefault,
}) {
  final _MemPlantRepo plants = _MemPlantRepo(<PlantSpecies>[
    PlantSpecies(
      id: 'sp_test',
      name: '测试草',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: hoursPerStage,
      subscriptionOnly: false,
    ),
  ]);
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _MemFocusRepo(),
    ledger: _MemLedgerRepo(),
    settings: _MemSettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    weedRandom: NoHitRandom(),
  );
  return (svc: svc, plants: plants);
}

/// 种子期植物。`lastWaterAt = null` → 不触发枯萎/死亡，隔离「纯成长速率」测量。
Plant _seedPlant(DateTime now) => Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthProgress: 0.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      mood: PlantMood.calm,
    );

/// 成株盛开植物（用于花谢循环测试）。`bloomedAt = null` 模拟老库升级来的已开花植物。
///
/// 🔴 [bloomCount] 默认 **0**（历史夹具语义），意味着「花谢后」的成长会命中
/// `_advanceGrowth` 的 `p.bloomCount == 0` 分支 ⇒ 走**首花速率**
/// （`24h / growthHoursPerStage` ≈ 10pp/天），**不是**复开花速率
/// （`kRebloomAutoProgressPerDay` = 3.6pp/天）。
/// 要覆盖复开花路径的用例**必须显式传 `bloomCount: 1`**，否则名字与路径不符
/// （2026-11-02 由产品经理与 team-lead 共同指出，见 `docs/天气系统_最终方案.md`
/// §5.4.1 的观察项：谁把这里「修正」成 1，那条 `4~6` 的断言会跳到 14~21 变红，
/// 那是**夹具修正的预期结果**，不要去动 `kRebloom*` 常量）。
Plant _adultBloomed(
  DateTime now, {
  DateTime? bloomedAt,
  int bloomCount = 0,
}) =>
    Plant(
      id: _kPlantId,
      speciesId: 'sp_test',
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 1.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.bloomed,
      plantedAt: now,
      lastWaterAt: null,
      wiltedAt: null,
      deadAt: null,
      bloomedAt: bloomedAt,
      bloomCount: bloomCount,
      mood: PlantMood.calm,
    );

Future<double> _progress(_MemPlantRepo plants) async =>
    (await plants.plant(_kPlantId))!.growthProgress;

/// 找一对**连续两天都是温和日**的自然日（返回其中第一天 0 点）。
///
/// 用途：需要断言「两段 24h 增量之比 = 两日 `g` 之比」时，必须排除极端日惩罚的
/// 干扰；温和 5 种无强制动作、惩罚恒 0，故两段增量严格只含 `g`。
///
/// ⚠️ 用「扫」而不是硬编码日期：日型由 `WeatherSystem` 的哈希 + 软约束决定，
/// 硬编码某个日期会在日型表一变时静默失效（天气按天变 → 数字对不上）。
DateTime _twoConsecutiveMildDays() {
  DateTime cursor = DateTime(2026, 1, 1);
  for (int i = 0; i < 800; i++) {
    final DateTime next = DateTime(cursor.year, cursor.month, cursor.day + 1);
    if (WeatherSystem.ofDay(cursor).kind.isMild &&
        WeatherSystem.ofDay(next).kind.isMild) {
      return cursor;
    }
    cursor = next;
  }
  throw StateError('no two consecutive mild days found within 800 days');
}

/// 一天「尽额度养护」：最多 3 次浇水（间隔 >30min）+ 1 次施肥。
///
/// 🔴 **A4 起额度随天气变化**（暴雨 0 / 小雨 1 / 普通 3）：真实孩子在下雨天也
/// 点不了那么多次，故这里逐次问 `careQuota` 的判据（**判据与 UI 同源**），
/// 额度不允许就停手 —— 模拟的是「孩子每天尽可能照顾」而不是「无视规则刷满 3 次」。
/// ⚠️ 施肥不受天气影响（§12.1-Q1 裁定：`fertilizeQuota` 恒 1），但仍走同一判据。
Future<void> _dailyCare(
  PlantGrowthService svc,
  Plant p,
  DateTime dayStart,
) async {
  for (int i = 0; i < kPlantWaterMaxPerDay; i++) {
    final DateTime at = dayStart.add(Duration(minutes: 31 * i));
    final PlantCareQuota q = await svc.careQuota(p, at);
    if (!q.canWater) break;
    await svc.water(p.id, at);
  }
  final DateTime fertAt = dayStart.add(const Duration(minutes: 93));
  final PlantCareQuota qf = await svc.careQuota(p, fertAt);
  if (qf.canFertilize) await svc.fertilize(p.id, fertAt);
}

/// 逐日推进直到 bloomed，返回**天数**（-1 = 上限内未开花）。
Future<int> _daysToBloom({
  required bool fullCare,
  double hoursPerStage = kPlantGrowthHoursPerStageDefault,
}) async {
  final ctx = _make(hoursPerStage: hoursPerStage);
  final DateTime start = DateTime(2026, 9, 1);
  await ctx.plants.savePlant(_seedPlant(start));

  DateTime now = start;
  for (int day = 0; day < 200; day++) {
    await ctx.svc.tickAll(now);
    final Plant? cur = await ctx.plants.plant(_kPlantId);
    if (cur == null) break;
    if (cur.status == PlantStatus.bloomed) return day;
    if (fullCare && cur.status == PlantStatus.growing) {
      await _dailyCare(ctx.svc, cur, now);
    }
    now = now.add(const Duration(days: 1));
  }
  return -1;
}

void main() {
  group('幂等：stage_started_at 必须每次 tick 推进到 now', () {
    test('同一时刻重复 tickAll → 增量为 0（页面刷新多少次都不许涨）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0);
      final double first = await _progress(ctx.plants);

      // 同一时刻再 tick 3 次（模拟花园页反复刷新 / 浇水后 reload）。
      for (int i = 0; i < 3; i++) {
        await ctx.svc.tickAll(t0);
      }
      final double repeated = await _progress(ctx.plants);

      expect(first, closeTo(0.0, 1e-9));
      expect(
        repeated - first,
        closeTo(0.0, 1e-9),
        reason: '重复 tick 仍在累加进度 → 非幂等（旧 bug：每次刷新都涨一段）',
      );
    });

    test('相邻两次 tick（各 +24h）→ 增量之比 = 两日 g 之比，且同 now 重复 tick 增量为 0', () async {
      // 🔴 2026-11-02 天气接线（T02 阶段二）后本条被**重写**：
      // 原断言是「相邻两天增量相等、均为 24h/240h = 0.1」，它的隐含前提是
      // 「今天和明天的成长速度一样」。天气介入后 `g` **按天变化**，这个前提
      // 已经不存在（旧断言实测：第一天 0.096、第二天 0.02−0.02=0.0），
      // 不是「改个数字」能救的，必须改成两条真正成立的性质：
      //   ① 同一个 `now` 重复 tick → 增量为 0（幂等，旧 bug 的原始防线）；
      //   ② 两段 24h 增量之比 = 两日的 `g` 之比（`g` 真的按日生效）。
      // 为保证 ② 是**纯 `g` 之比**（不被极端日惩罚混入），起点选一对
      // **连续两天都是温和日**的自然日：温和日无强制动作、无惩罚。
      final DateTime t0 = _twoConsecutiveMildDays();
      final ctx = _make();
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0);
      final double p0 = await _progress(ctx.plants);

      await ctx.svc.tickAll(t0.add(const Duration(hours: 24)));
      final double p1 = await _progress(ctx.plants);

      await ctx.svc.tickAll(t0.add(const Duration(hours: 48)));
      final double p2 = await _progress(ctx.plants);

      print('[V2 幂等] p0=$p0, p1=$p1, p2=$p2 '
          '→ 第一次增量=${p1 - p0}, 第二次增量=${p2 - p1}');

      const double hoursPerStage = kPlantGrowthHoursPerStageDefault;
      final double g1 = WeatherSystem.ofDay(t0).growthFactor;
      final double g2 = WeatherSystem.ofDay(
        t0.add(const Duration(hours: 24)),
      ).growthFactor;
      final double expectFirst =
          24.0 / hoursPerStage * g1 * kPlantAutoGrowthScale;
      final double expectSecond =
          24.0 / hoursPerStage * g2 * kPlantAutoGrowthScale;

      expect(p0, closeTo(0.0, 1e-9));
      expect(p1 - p0, closeTo(expectFirst, 1e-9));
      expect(
        p2 - p1,
        closeTo(expectSecond, 1e-9),
        reason: '第二次增量应为「一整天 × 当天 g」；若变成 0.2 量级说明整段被重复累加',
      );
      // ② 两段增量之比严格等于两日 `g` 之比（温和日无惩罚，故是纯 g 之比）。
      expect((p2 - p1) / (p1 - p0), closeTo(g2 / g1, 1e-9));

      // ① 同一个 `now` 重复 tick 3 次 → 增量必须为 0（幂等的原始防线）。
      for (int i = 0; i < 3; i++) {
        await ctx.svc.tickAll(t0.add(const Duration(hours: 48)));
      }
      expect(await _progress(ctx.plants), closeTo(p2, 1e-12));
    });

    test('半天 tick：增量减半（2×12h == 1×24h，同一自然日内）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.tickAll(t0.add(const Duration(hours: 12)));
      final double half = await _progress(ctx.plants);
      await ctx.svc.tickAll(t0.add(const Duration(hours: 24)));
      final double full = await _progress(ctx.plants);

      // 两个采样点同属 2026-09-01 ⇒ 同一个 `g`，「减半」这条性质仍严格成立；
      // 期望值由常量 + 当日 `g` 算出（天气接入前 g 恒为 1.0，那时就是 0.05 / 0.1）。
      const double hoursPerStage = kPlantGrowthHoursPerStageDefault;
      final double g = WeatherSystem.ofDay(t0).growthFactor;
      expect(half, closeTo(12.0 / hoursPerStage * g * kPlantAutoGrowthScale, 1e-9));
      expect(full, closeTo(24.0 / hoursPerStage * g * kPlantAutoGrowthScale, 1e-9));
      expect(full, closeTo(half * 2, 1e-9));
    });
  });

  group('V2 成长数值口径（玄参大人 2026-09-22 拍板）', () {
    test('普通植物 240h/阶段：完全不养护 → 33 天量级长成（含天气 g 与 B 口径惩罚）', () async {
      final int days = await _daysToBloom(fullCare: false);
      print('[V2 数值] 不养护长成天数 = $days');
      // 🔴 天气接线后由「正好 30 天」改为区间：`E[g] = 0.9280` 让全园平均慢 7.2%，
      // 叠 B 口径惩罚 0.30pp/天 ⇒ 方案 §5.4「零养护」B 口径设计值 = **33.41 天**。
      // ⚠️ **不能断言精确值**：`docs/天气系统_最终方案.md` §5.4.1 实测（730 个起点）
      // 给出单起点整数天范围 **31 ~ 39**（中位 34，本测试起点落 34）—— 差异来自
      // 「整数量化 +1.6 天」与「确定性哈希的采样方差 ±2 天」，不是代码 bug。
      // §5.4.1 规定单起点整数天的区间宽度 **≥ ±3 天**，故此处取实测包络 31~39。
      expect(days, inInclusiveRange(31, 39));
    });

    test('普通植物 240h/阶段：每天满养护（3 浇 +1 肥）→ 约 20 天长成', () async {
      final int days = await _daysToBloom(fullCare: true);
      // 理论值：3.0 阶段 ÷（自动 10% + 养护 6%）/天 = 18.75 天 → 实测进位 19 天。
      print('[V2 数值] 每天满养护长成天数 = $days（理论 18.75 天）');
      // 🔴 天气接线后由旧窄区间 `19~20` 校准为 `[18, 23]`（产品经理 2026-11-02 穷举
      // 730 个起点复算，见 `docs/天气系统_最终方案.md` §5.4.1「成品区间」表）：
      //  · 不截断 B 口径包络 **19~22**（分布 {19:1, 20:321, 21:391, 22:17}，中位 21）；
      //  · 截断 B 口径（A4 接额度后）包络 **20~22**（中位 21）；
      //  · 本测试起点 `2026-09-01` 两口径都落 **20**。
      // 取「包络上下各 ±1」= `[18, 23]`（不是机械 ±3 到 17~24）：包络是穷举出来的，
      // ±1 只为将来的起点与 A4 口径漂移留余量。
      // ⚠️ 这条是全组**最脆**的一条：旧区间 `19~20` 只有 ±0.5，B 口径下约 **30% 的
      // 起点**会落到 21/22 ⇒ 换起点必红。**别为了让它绿去动任何常量。**
      expect(days, inInclusiveRange(18, 23));
    });

    test('精品植物 480h/阶段：完全不养护 → 70 天量级长成', () async {
      final int days = await _daysToBloom(
        fullCare: false,
        hoursPerStage: kPlantGrowthHoursPerStagePremium,
      );
      print('[V2 数值] 精品植物不养护长成天数 = $days');
      // 🔴 天气接线后由「60 天」改为区间（`E[g] = 0.9280` + B 口径惩罚）。
      // §5.4 设计值：精品零养护 基准 **64.66** / B **69.12**。
      // ⚠️ **不能断言精确值**：§5.4.1 实测（730 个起点）单起点整数天范围
      // **65 ~ 77**（中位 70，本测试起点落 71 —— 730 个起点里有 91 个给出 71），
      // 主因是「整数量化 +1.6 天」与「采样方差 ±5 天」。
      // 🟢 G1d 护栏（52~68）**不放宽**：产品裁定 B 口径与整数天**不进护栏**，
      // 护栏走「100 周期连续均值」口径（基准口径 64.58 实测，sd 仅 0.05），
      // 见 §5.5 / §5.4.1。本条是**实测值**探针、不是护栏断言。
      expect(days, inInclusiveRange(65, 77));
    });

    // ⚠️ 为什么补这条：文档「精品植物满养护约 28 天」是 2026-09-25 施肥 5%→3% 后
    // **按公式推算**出来的（3.0 ÷（自动 5% + 养护 6%）= 27.27 → 进位 28），
    // 当时没有测试背书。推算值必须实测钉死，否则文档里的 28 天永远是「没人验过的数」。
    test('精品植物 480h/阶段：每天满养护（3 浇 +1 肥）→ 29 天量级长成', () async {
      final int days = await _daysToBloom(
        fullCare: true,
        hoursPerStage: kPlantGrowthHoursPerStagePremium,
      );
      // 天气接入前：3.0 阶段 ÷（自动 24h/480h = 5% + 养护 6%）/天 = 27.27 → 进位 28。
      // 天气接入后：精品 3 水 1 肥 B 口径设计值 = **29.45 天**（§5.4）⇒ 实测 30。
      // ⚠️ §5.4.1 规定**精品首花**单起点整数天的区间宽度 ≥ ±5 天（采样方差最大），
      // 故取 25~35；不断言精确值。
      print('[V2 数值] 精品植物每天满养护长成天数 = $days（设计 27.27 → 含天气 29.45）');
      expect(days, inInclusiveRange(25, 35));
    });

    test('常量取值钉死（防回退）', () {
      expect(kPlantGrowthHoursPerStageDefault, 240.0);
      expect(kPlantGrowthHoursPerStagePremium, 480.0);
      expect(kPlantWaterProgressGain, 0.01);
      expect(kPlantFertilizeProgressGain, 0.03);
      expect(kPlantAutoGrowthScale, 1.0);
      // 每天养护上限 6%：3×1% + 1×3%
      expect(
        kPlantWaterMaxPerDay * kPlantWaterProgressGain +
            kPlantFertilizeMaxPerDay * kPlantFertilizeProgressGain,
        closeTo(0.06, 1e-9),
      );
    });
  });

  group('养护增量口径：浇水 +1% / 施肥 +3%（不再跳 21%）', () {
    test('浇水一次 → 进度 +1% × 当日 w（旧口径 +12% 会跳）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.water(_kPlantId, t0);
      final double afterWater = await _progress(ctx.plants);
      print('[V2 养护] 浇水后进度 = $afterWater');

      // 天气接线后（方案 §11.2 改法 1）：`w` 乘在**即时加值侧**，
      // 故期望值 = 裸基数 × 当日 `w`。**不写死观测值**（如 0.0095），
      // 一律由常量 + `WeatherSystem.ofDay` 算出，天气口径一变自动跟随。
      final double w = WeatherSystem.ofDay(t0).waterFactor;
      expect(afterWater, closeTo(kPlantWaterProgressGain * w, 1e-9));
    });

    test('浇水后立刻 tickAll：不会把「已结算过的整段」再累加一遍', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1, 0, 0);
      await ctx.plants.savePlant(_seedPlant(t0));

      await ctx.svc.water(_kPlantId, t0);
      final double before = await _progress(ctx.plants);

      // 浇水后表现层 reload → tickAll（真机正是这条路径把 +1% 变成 +21%）。
      await ctx.svc.tickAll(t0);
      await ctx.svc.tickAll(t0.add(const Duration(minutes: 1)));
      final double after = await _progress(ctx.plants);

      print('[V2 养护] 浇水+reload 后进度 = $after（浇水后 $before）');
      // 只允许 1 分钟的真实时间增量（1/60/240 × 当日 g），绝不允许把整天叠加进来。
      final double g = WeatherSystem.ofDay(t0).growthFactor;
      expect(
        after - before,
        closeTo(
          kPlantAutoGrowthScale / 60.0 / kPlantGrowthHoursPerStageDefault * g,
          1e-9,
        ),
      );
    });
  });

  group('花谢循环（玄参大人 2026-09-23 拍板：盛开不能一直保持）', () {
    test('盛开保持 kBloomDurationDays 天后花谢：status→growing、进度回落 floor', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0, bloomedAt: t0));

      // 花期内（0 .. kBloomDurationDays-1 天）保持盛开。
      for (int d = 0; d < kBloomDurationDays; d++) {
        await ctx.svc.tickAll(t0.add(Duration(days: d)));
        final Plant cur = (await ctx.plants.plant(_kPlantId))!;
        expect(cur.status, PlantStatus.bloomed, reason: '第 $d 天仍在花期');
      }

      // 跨过花期一天 → 花谢。
      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays)));
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.growing);
      expect(cur.growthProgress, closeTo(kBloomWiltProgressFloor, 1e-9));
    });

    test('花谢后不会立即再盛开（进度需由时间/养护重新养满）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0, bloomedAt: t0));

      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays)));
      expect((await ctx.plants.plant(_kPlantId))!.status, PlantStatus.growing);

      // 花谢后仅过 1 天（自动成长「一整天 × 当日 g」，再结算当日惩罚）→ 仍 growing。
      await ctx.svc.tickAll(t0.add(Duration(days: kBloomDurationDays + 1)));
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.growing);
      // 期望值一律由常量 + 当日天气算出（**不写死 0.605 之类的观测值**）。
      final DateTime advancedDay =
          t0.add(const Duration(days: kBloomDurationDays));
      final WeatherDay wd = WeatherSystem.ofDay(advancedDay);
      final double expectedGain =
          24.0 / kPlantGrowthHoursPerStageDefault * wd.growthFactor *
                  kPlantAutoGrowthScale +
              // 该日已过零点（本 tick 落在次日 0 点）⇒ 极端日照样结算惩罚；
              // 无棚、未浇水、未施肥。
              WeatherGrowthMath.penaltyOf(
                day: wd,
                hasShelter: false,
                watered: false,
                fertilized: false,
              );
      expect(
        cur.growthProgress,
        closeTo(kBloomWiltProgressFloor + expectedGain, 1e-9),
      );
    });

    test('花谢后经时间重新养满 → 再度盛开（走复开花速率，循环成立）', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      // 🔴 `bloomCount: 1` **必传**：夹具默认 0 会让这株命中 `p.bloomCount == 0`
      // 分支、走**首花速率**（≈10pp/天），用例名说「复开花」而实际跑的不是 ——
      // 2026-11-02 产品经理 + team-lead 一起指出，本轮修正。
      await ctx.plants.savePlant(
        _adultBloomed(t0, bloomedAt: t0, bloomCount: 1),
      );

      // 让花期结束 → 花谢。
      final DateTime afterWiltDay =
          t0.add(const Duration(days: kBloomDurationDays));
      await ctx.svc.tickAll(afterWiltDay);
      expect((await ctx.plants.plant(_kPlantId))!.status, PlantStatus.growing);

      // ══════════════════════════════════════════════════════════════════
      // 路径证明（本轮新增，**这条比天数区间更值钱**）
      // 只断言天数区间证明不了「真的走了复开花路径」——区间够宽时，错路径也能凑巧
      // 落在里面。这里直接验**速率**：花谢后推进 24h（= 1 天），增量必须等于
      // 复开花速率 × g，且**不等于**首花速率 × g。
      // ══════════════════════════════════════════════════════════════════
      final WeatherDay wd = WeatherSystem.ofDay(afterWiltDay);
      final double penalty = WeatherGrowthMath.penaltyOf(
        day: wd,
        hasShelter: false,
        watered: false,
        fertilized: false,
      );
      final double progressAfterWilt =
          (await ctx.plants.plant(_kPlantId))!.growthProgress;

      await ctx.svc.tickAll(afterWiltDay.add(const Duration(days: 1)));
      final double gain1 =
          (await ctx.plants.plant(_kPlantId))!.growthProgress - progressAfterWilt;

      // 期望值一律由常量 + 当日天气算出（不写死观测值）。
      // 复开花：固定 pp/天 × g（非精品无 premiumDiv）；24h 恰好一整天。
      final double expectRebloom =
          kRebloomAutoProgressPerDay * wd.growthFactor + penalty;
      // 首花：24h / growthHoursPerStage × g × scale（这就是「走错路径」的值）。
      final double expectFirstBloom =
          24.0 / kPlantGrowthHoursPerStageDefault * wd.growthFactor *
                  kPlantAutoGrowthScale +
              penalty;

      print('[V2 循环] 花谢后 24h 增量 = $gain1'
          '（复开花期望 $expectRebloom / 首花速率 $expectFirstBloom）');
      // ① 必须等于复开花速率。
      expect(gain1, closeTo(expectRebloom, 1e-9));
      // ② 🔴 核心反向断言：必须**不是**首花速率 ⇒ 证明名字与路径一致。
      expect(gain1, isNot(closeTo(expectFirstBloom, 1e-9)),
          reason: '这株仍在走首花速率（bloomCount 没生效），用例名与路径不符');

      // ── 循环成立：纯自动成长（不养护）直到再次盛开 ────────────────────
      // 🔴 计数量纲（产品经理 2026-11-02 校准）：`rebloomDay` 用 **`i + 1`**，
      // 因为 `i = 0` 对应花谢后**第 1 天**，而花谢那次 tick 只把进度压回
      // `kBloomWiltProgressFloor`、不叠加当日增量 ⇒ `i = N - 1`（N = 从花谢日
      // 到盛开的整段天数）。§5.4.1 的 `[14,21]` 是 **N 口径**，故必须断 `i + 1`；
      // 照旧写 `i` 会得到 N-1 = 14，**正好贴死在下界**（下界贴边等于没有下界）。
      DateTime now = afterWiltDay.add(const Duration(days: 2));
      int rebloomDays = -1;
      for (int i = 1; i < 60; i++) {
        await ctx.svc.tickAll(now);
        final Plant cur = (await ctx.plants.plant(_kPlantId))!;
        if (cur.status == PlantStatus.bloomed) {
          rebloomDays = i + 1;
          expect(cur.bloomedAt, isNotNull, reason: '再盛开应记录新花期起点');
          expect(cur.bloomCount, 2, reason: '首花 1 次 + 本次 = 2 次');
          break;
        }
        now = now.add(const Duration(days: 1));
      }
      print('[V2 循环] 花谢后再盛开 = $rebloomDays 天（N 口径）');
      // §5.4.1：普通复开花·零养护 N 的 730 起点包络 **14 ~ 21**（中位 17）。
      // 本测试起点（`t0 = 2026-09-01`，花谢日 09-04）实测 N = 15。
      expect(rebloomDays, greaterThanOrEqualTo(0),
          reason: '花谢后应能再次盛开，实测 N=$rebloomDays');
      expect(rebloomDays, inInclusiveRange(14, 21));
    });

    test('老库升级来的已开花植物（bloomedAt=null）首次 tick 不花谢、补计时起点', () async {
      final ctx = _make();
      final DateTime t0 = DateTime(2026, 9, 1);
      await ctx.plants.savePlant(_adultBloomed(t0)); // bloomedAt 为 null

      await ctx.svc.tickAll(t0);
      final Plant cur = (await ctx.plants.plant(_kPlantId))!;
      expect(cur.status, PlantStatus.bloomed, reason: '仍是盛开，不应立即花谢');
      expect(cur.bloomedAt, t0, reason: '应以本次 tick 为计时起点补上');
    });
  });

  // ── F68（玄参 2026-10-04）：养护增量公开单点口径 ──────────────────────
  // 背景：按钮文案曾写死首花「施肥 +3%」，复开花植物实际 +1.2%（59%→60%）被当成
  // bug 上报。修复 = 文案与领域层共用 [PlantGrowthService.careProgressGain]。
  group('careProgressGain 养护增量单点口径', () {
    test('首花（bloomCount==0）：浇水 +1% / 施肥 +3%，不受精品影响', () {
      expect(
        PlantGrowthService.careProgressGain(
          bloomCount: 0,
          isPremium: false,
          firstGain: kPlantWaterProgressGain,
          rebloomGain: kRebloomWaterProgressGain,
        ),
        kPlantWaterProgressGain,
      );
      expect(
        PlantGrowthService.careProgressGain(
          bloomCount: 0,
          isPremium: true,
          firstGain: kPlantFertilizeProgressGain,
          rebloomGain: kRebloomFertilizeProgressGain,
        ),
        kPlantFertilizeProgressGain,
      );
    });

    test('复开花（普通）：浇水 +0.7% / 施肥 +1.5%', () {
      expect(
        PlantGrowthService.careProgressGain(
          bloomCount: 1,
          isPremium: false,
          firstGain: kPlantWaterProgressGain,
          rebloomGain: kRebloomWaterProgressGain,
        ),
        kRebloomWaterProgressGain,
      );
      expect(
        PlantGrowthService.careProgressGain(
          bloomCount: 3,
          isPremium: false,
          firstGain: kPlantFertilizeProgressGain,
          rebloomGain: kRebloomFertilizeProgressGain,
        ),
        closeTo(0.015, 1e-12),
        reason: '2026-11-02 比例修正后为 1.5%；59% 施肥 → 60.5%（截断显示 60%）',
      );
    });

    test('复开花（精品）：增量 ÷ kRebloomPremiumCycleMultiplier', () {
      expect(
        PlantGrowthService.careProgressGain(
          bloomCount: 1,
          isPremium: true,
          firstGain: kPlantFertilizeProgressGain,
          rebloomGain: kRebloomFertilizeProgressGain,
        ),
        closeTo(kRebloomFertilizeProgressGain / kRebloomPremiumCycleMultiplier,
            1e-12),
      );
    });
  });
}
