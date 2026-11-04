/// 天气系统 A6 期 · **日结浮点容差 `kGrowthEpsilon`（1e-9）边界守卫**。
///
/// ## 为什么需要这份文件（A6 盘点结论）
/// `kGrowthEpsilon` 在 `lib/` 里被 **2 处**使用：
///  · `plant_growth_service.dart:1322` 阶段推进（seed→sprout→adult）；
///  · `plant_growth_service.dart:1351` 成株终点（adult 满进度 → `bloomed`）。
/// 而 A6 盘点时它在 `test/` 下**零引用** —— 也就是说这两条阈值**一条护栏都没有**。
///
/// 回归后果（A6 派工书裁定的「显性回归」）：
///  · 删掉容差、改回严格的 `progress >= 1.0` ⇒ `24h/240h` 累加 10 次得到的是
///    `0.9999999999999999`（**小于** 1.0），于是「正好 10 天一阶段」被推成 11 天，
///    **每一级白多花 1 天**；成株那一格同理 ⇒ 花**永远开不了**，成株循环玩法全挂。
///  · 两个后果都**不抛异常**、`flutter analyze` 不响、旧 3622 例全绿。
///
/// ## 为什么用「1 微秒 tick」而不是「10 天累加」
/// 复现「10 天累加出 0.9999999999999999」需要 10 个连续 `g == 1.0` 的自然日，
/// 而真实日历给不出这种连续段（9 种日型按权重混排）⇒ 那样写出来的用例只能靠
/// 撞运气，且**夹具本身不可读**。
///
/// 本文件改用**边界探针**：把 `growthProgress` 直接摆到容差两侧，再 tick **1 微秒**。
///  · 1 µs 的增量 = `1e-6 / 3.6e9 / 240 × g` ≈ **1.2e-18** —— 比 1.0 的浮点间距
///    （2.2e-16）还小，**物理上加不动进度**，于是「推进 / 不推进」完全由容差决定；
///  · 代码里本来就用微秒算时长（`inMicroseconds / 3600000000.0`，`:1238`），
///    所以 1 µs 不是伪造输入，是这条判据的合法定义域端点。
///
/// ## 期望值来源（铁律：不引用被测常量自证）
///  · 断言写的是**行为**（「进了 adult」/「还是 sprout」），不是常量比对；
///  · 两侧夹逼值 `5e-10` / `5e-9` 是**独立写死的审计口径**：若实现把容差改到
///    这个区间之外（删掉 / 放大到 1e-3 / 1e-2），必有一条红。这比
///    `expect(kGrowthEpsilon, 1e-9)` 强 —— 后者只钉常量、不钉常量被用在哪。
///
/// ## 与设计文档的对应
/// | 用例 | 钉的阈值 | 抓的变异 |
/// |---|---|---|
/// | E1 | `:1322` 阶段推进 · 容差内必须推进 | M-A6-1（`>= 1.0`）/ 容差 < 5e-10 |
/// | E2 | `:1322` 阶段推进 · 容差外不得推进 | M-A6-2（容差放大到 1e-3 / 1e-2） |
/// | E3 | `:1351` 成株终点 · 容差内必须开花 | M-A6-3（只改 `:1351` 一处） |
library weather_a6_growth_epsilon_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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

import '../helpers/no_hit_random.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 内存桩（与 `weather_a4_quota_test` / `plant_care_quota_test` 同源口径）
// ─────────────────────────────────────────────────────────────────────────────

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

/// 空专注库 ⇒ `factor` 恒 1.0（本文件与专注无关，把这条支路钉成常量）。
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

({PlantGrowthService svc, _MemoryPlantRepo plants}) _make() {
  final _MemoryPlantRepo plants = _MemoryPlantRepo();
  final PlantGrowthService svc = PlantGrowthService(
    plants: plants,
    focus: _NoFocusRepo(),
    ledger: _MemoryLedger(),
    settings: _MemorySettingsRepo(),
    bloomRewards: InMemoryBloomRewardRepository(),
    // 干扰物固定「永不命中」：否则某天恰好 roll 到杂草 ⇒ 当天成长暂停 ⇒ 边界量测不到。
    weedRandom: NoHitRandom(),
  );
  return (svc: svc, plants: plants);
}

PlantSpecies get _sunflower =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == 'species_sunflower');

/// 探针基准时刻：随手取一个工作日上午（本文件全部用例都只 tick **1 微秒**，
/// 且同一天不会「关门」⇒ 天气项 / 惩罚项 / 雨水代劳**一项都不参与**，
/// 所以这个日期落在哪种日型上都不影响结论）。
final DateTime _t0 = DateTime(2026, 5, 12, 10);

/// 探针 tick 宽度：**1 微秒**。
///
/// 增量 ≈ `1e-6 / 3.6e9 / 240 × g` ≈ 1.2e-18，小于 1.0 的浮点间距（2.2e-16）
/// ⇒ 进度在数值上「纹丝不动」，「推进与否」只由容差判据决定。
const Duration _kProbeTick = Duration(microseconds: 1);

Plant _probePlant({
  required PlantStage stage,
  required double progress,
  PlantStatus status = PlantStatus.growing,
  int bloomCount = 0,
}) {
  return Plant(
    id: 'plant-epsilon',
    speciesId: _sunflower.id,
    potIndex: 0,
    stage: stage,
    stageStartedAt: _t0,
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: _t0,
    bloomCount: bloomCount,
  );
}

void main() {
  group('E1/E2 · 阶段推进阈值（plant_growth_service.dart:1322）', () {
    test('E1 · 差 5e-10 长满（容差内）⇒ 必须推进到下一阶段', () async {
      // 5e-10 < 1e-9 ⇒ 属「浮点噪声」，按契约视为长满。
      final Plant seed = _probePlant(
        stage: PlantStage.sprout,
        progress: 1.0 - 5e-10,
      );
      expect(seed.stage, PlantStage.sprout, reason: '前置：起点必须是幼苗阶段');
      expect(1.0 - seed.growthProgress, lessThan(1e-9),
          reason: '前置：差值 5e-10 必须落在 1e-9 容差之内');

      final ({PlantGrowthService svc, _MemoryPlantRepo plants}) h = _make();
      await h.plants.savePlant(seed);
      await h.svc.tickAll(_t0.add(_kProbeTick));
      final Plant after = (await h.plants.plant(seed.id))!;

      expect(
        after.stage,
        PlantStage.adult,
        reason: '容差内必须推进：`progress >= 1.0 - kGrowthEpsilon` 若被改成严格的 '
            '`>= 1.0`，0.9999999995 永远进不了 adult ⇒ 每级白多 1 天（M-A6-1）',
      );
      // 残留只能是这 1 微秒的增量（≈1e-18），绝不可能是「一整级没消费掉」。
      expect(after.growthProgress, lessThan(0.01),
          reason: '推进后残留必须是本段增量（≈1e-18），实测 ${after.growthProgress}');
    });

    test('E2 · 差 5e-9 长满（容差外）⇒ 不得推进（防「把容差放大」的过修）', () async {
      // 5e-9 > 1e-9 ⇒ 是真的「还没长满」，不是浮点噪声。
      final Plant seed = _probePlant(
        stage: PlantStage.sprout,
        progress: 1.0 - 5e-9,
      );
      expect(1.0 - seed.growthProgress, greaterThan(1e-9),
          reason: '前置：差值 5e-9 必须落在 1e-9 容差之外');

      final ({PlantGrowthService svc, _MemoryPlantRepo plants}) h = _make();
      await h.plants.savePlant(seed);
      await h.svc.tickAll(_t0.add(_kProbeTick));
      final Plant after = (await h.plants.plant(seed.id))!;

      expect(
        after.stage,
        PlantStage.sprout,
        reason: '容差外不得推进。容差若被放大到 1e-3 / 1e-2（例如为了让别的用例变绿），'
            '0.999999995 会被判成「长满」⇒ 白丢 0.999999995 的阶段进度（M-A6-2）',
      );
      expect(after.growthProgress, greaterThan(0.99),
          reason: '不推进时进度必须原样保留，实测 ${after.growthProgress}');
    });
  });

  group('E3 · 成株终点阈值（plant_growth_service.dart:1351）', () {
    test('E3 · 成株差 5e-10 长满（容差内）⇒ 必须盛开并累加 bloomCount', () async {
      final Plant adult = _probePlant(
        stage: PlantStage.adult,
        progress: 1.0 - 5e-10,
        bloomCount: 0,
      );
      expect(adult.bloomCount, 0, reason: '前置：首花前 bloomCount 必须是 0');
      expect(adult.bloomedAt, isNull, reason: '前置：未盛开时 bloomedAt 必须为 null');

      final ({PlantGrowthService svc, _MemoryPlantRepo plants}) h = _make();
      await h.plants.savePlant(adult);
      await h.svc.tickAll(_t0.add(_kProbeTick));
      final Plant after = (await h.plants.plant(adult.id))!;

      // 🔴 这是**:1351 那条独立阈值**：它和 :1322 是两处 `kGrowthEpsilon`。
      //    只改其中一处（M-A6-3）时，E1 绿而本条红 —— 两条必须各测一处。
      expect(
        after.status,
        PlantStatus.bloomed,
        reason: '成株满进度必须转 bloomed。若 :1351 的容差被删，'
            '0.9999999995 永远到不了 1.0 ⇒ 花永远开不了，成株循环玩法全挂（M-A6-3）',
      );
      expect(after.growthProgress, 1.0,
          reason: '盛开时进度必须被钉成 1.0（不是 0.9999999995）');
      expect(after.bloomCount, 1,
          reason: '首花盛开 bloomCount 必须 0→1（复花节奏的判据）');
      expect(after.bloomedAt, isNotNull,
          reason: 'bloomedAt 必须落值，否则「花期剩余」与花谢循环都没有计时起点');
    });
  });
}
