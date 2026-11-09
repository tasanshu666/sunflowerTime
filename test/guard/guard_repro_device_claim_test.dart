/// 「清档 → 今日页守卫 → 跳过 → 收下」真机链路的**领域层等价复现**（玄参 2026-11-09 晚报）。
///
/// 真机现象：调试面板「清空今日守卫存档」→ 今日页点开始守卫 → 跳过 →
/// 结算卡显示「获得 3 ☀ + 浇水券」→ 回花园页，左上角 buff 胶囊不出现。
///
/// 现有红测试（`guard_buff_chip_refresh_test.dart` 场景 6）用的是**内存 fake store**，
/// 全绿 —— 但真机用的是**真实 `GuardStatePrefsStore`（SharedPreferences）**。
/// 本文件把存储层换成真实实现，复刻「清档 → resolve → markFighting → claim →
/// finally 里再 resolve/expire（今日页 `_refreshGuard`）」的完整时序，
/// 逐环断言 buff 是否真的落盘、读得回。
///
/// 🔴 期望值一律写字面量；`deriveGuardRoll` 是确定性派生，本文件按「扫 childId
/// 选一个掉浇水券的组合」造场景，不注入随机数。
library guard_repro_device_claim_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

DateTime _now() => DateTime(2026, 11, 9, 10, 30);
String get _today => dayKey(_now());

// ── Fake 仓储（与 guard_service_test 同口径；唯一真实组件 = prefs store）────

class _MemLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  final Set<String> _ids = <String>{};
  double initial = 0;

  double get balanceValue =>
      initial + entries.fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> append(SunlightEntry entry) async {
    if (_ids.contains(entry.id)) {
      throw StateError('duplicate ledger id: ${entry.id}');
    }
    _ids.add(entry.id);
    entries.add(entry);
    return balanceValue;
  }

  @override
  Future<double> balance() async => balanceValue;

  @override
  Future<List<SunlightEntry>> all() async =>
      entries.reversed.toList(growable: false);

  @override
  Future<double> dayNet(String dayKey) async => entries
      .where((SunlightEntry e) => e.dayKey == dayKey)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> earnGrossOnDay(String dayKey) async => entries
      .where((SunlightEntry e) =>
          e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String dayKey) async => entries
      .where((SunlightEntry e) =>
          e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey == dayKey)
          .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.dayKey.startsWith(monthKey))
          .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async =>
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
  Future<int> countByRefType(String refType) async =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
    String refType,
    String refId,
  ) async {
    DateTime? latest;
    for (final SunlightEntry e in entries) {
      if (e.refType != refType || e.refId != refId) continue;
      if (latest == null || e.ts.isAfter(latest)) latest = e.ts;
    }
    return latest;
  }

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    for (final SunlightEntry e in entries.reversed) {
      if (e.refType == refType) return e;
    }
    return null;
  }
}

class _FakeFocus implements FocusRepository {
  final Map<String, List<FocusSession>> byDay = <String, List<FocusSession>>{};

  void seedValid(String dayKey, int count) {
    byDay[dayKey] = <FocusSession>[
      for (int i = 0; i < count; i++)
        FocusSession(
          id: '$dayKey-v$i',
          start: DateTime(2026, 11, 9, 8, i),
          plannedMin: 25,
          actualFocusMin: 25,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: DateTime(2026, 11, 9, 8, i),
        ),
    ];
  }

  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      byDay[dayKey] ?? const <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemPlants implements PlantRepository {
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
  Future<List<PlantSpecies>> species() async => const <PlantSpecies>[];
}

class _MemSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 12,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

Plant _plant(String id) => Plant(
      id: id,
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 11, 1),
      growthProgress: 0.5,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 11, 1),
      lastWaterAt: DateTime(2026, 11, 8),
    );

// ── 装配 ────────────────────────────────────────────────────────────────────

class _Ctx {
  _Ctx({
    required this.store,
    required this.ledger,
    required this.vouchers,
    required this.guard,
  });

  final GuardStatePrefsStore store;
  final _MemLedger ledger;
  final GuardVoucherService vouchers;
  final GuardService guard;
}

/// 扫 childId 找一个「今天掉浇水券」的确定性组合（禁 Random：结果可复现）。
(String, GuardRoll) _childWithWaterVoucher() {
  for (int i = 0; i < 500; i++) {
    final String childId = 'child_repro_$i';
    final GuardRoll roll =
        deriveGuardRoll(dayKey: _today, childId: childId);
    if (roll.drop == GuardDropKind.waterVoucher) return (childId, roll);
  }
  throw StateError('500 个 childId 里没有掉浇水券的组合？派生分布有问题');
}

Future<_Ctx> _make({required String childId, int validSessionsToday = 0}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final GuardStatePrefsStore store = GuardStatePrefsStore(prefs, clock: _now);
  final _MemLedger ledger = _MemLedger()..initial = 100;
  final _FakeFocus focus = _FakeFocus();
  if (validSessionsToday > 0) focus.seedValid(_today, validSessionsToday);
  final _MemPlants plants = _MemPlants()..store.addAll(<Plant>[_plant('p1')]);
  final PlantGrowthService growth = PlantGrowthService(
    plants: plants,
    focus: focus,
    ledger: ledger,
    settings: _MemSettings(),
    bloomRewards: InMemoryBloomRewardRepository(),
  );
  final GuardService guard = GuardService(
    store: store,
    ledger: ledger,
    focus: focus,
    plants: plants,
    growth: growth,
    childId: () => childId,
    clock: _now,
  );
  final GuardVoucherService vouchers = GuardVoucherService(
    store: store,
    childId: () => childId,
    clock: _now,
  );
  return _Ctx(store: store, ledger: ledger, vouchers: vouchers, guard: guard);
}

void main() {
  test('真实 prefs 链路：清档 → resolve → markFighting → claim → buff 落盘且读得回',
      () async {
    final (String childId, _) = _childWithWaterVoucher();
    final _Ctx ctx = await _make(childId: childId, validSessionsToday: 1);

    // ① 调试面板「清空今日守卫存档」（真机第一步）。
    await ctx.guard.resetForDebug();
    expect(
      (await ctx.store.read(childId)).dayKey,
      _today,
      reason: '清档后 read 应回落到「今天的空档」',
    );

    // ② 今日页刷新：expire → resolve（落盘 pending + 掉落档）。
    await ctx.guard.expire();
    final GuardResolveResult resolved = await ctx.guard.resolve();
    expect(resolved.state.status, GuardDayStatus.pending);
    expect(resolved.state.dropKind, GuardDropKind.waterVoucher);
    expect(resolved.state.buff, isNull, reason: 'resolve 不发 buff，buff 等 claim');

    // ③ 点胶囊 → markFighting → 跳过 → 结算卡「收下」→ claim。
    await ctx.guard.markFighting();
    final GuardClaimOutcome outcome = await ctx.guard.claim();
    expect(outcome.ok, isTrue,
        reason: 'claim 失败 ⇒ 真机上今天根本没有券，见 failure=${outcome.failure}');

    // ④ 🔴 核心：真实 prefs 往返后 buff 必须在。
    final GuardDayState stored = await ctx.store.read(childId);
    expect(stored.status, GuardDayStatus.claimed);
    expect(stored.buff, isNotNull,
        reason: 'claim 落的 buff 在真实 prefs 往返后丢了 ⇒ 这就是真机根因');
    expect(stored.buff!.quota, 6, reason: '浇水券额度 6（字面量）');
    expect(stored.buff!.used, 0);

    // ⑤ 花园页 `_reload` 读的是 `currentBuff()` ⇒ 必须读得回。
    final GuardBuffState? buff = await ctx.vouchers.currentBuff();
    expect(buff, isNotNull, reason: 'currentBuff() 读不到 ⇒ 花园页胶囊不可能出现');
    expect(buff!.remaining, 6);
  });

  test('真机时序补刀：claim 之后今日页 finally 又跑 expire/resolve，buff 不许被抹',
      () async {
    final (String childId, _) = _childWithWaterVoucher();
    final _Ctx ctx = await _make(childId: childId, validSessionsToday: 1);

    await ctx.guard.resetForDebug();
    await ctx.guard.expire();
    await ctx.guard.resolve();
    await ctx.guard.markFighting();
    final GuardClaimOutcome outcome = await ctx.guard.claim();
    expect(outcome.ok, isTrue);

    // 今日页 `_onGuardPillTap` 的 finally：`_refreshGuard()` → expire → resolve。
    await ctx.guard.expire();
    await ctx.guard.resolve();

    final GuardDayState stored = await ctx.store.read(childId);
    expect(stored.buff, isNotNull,
        reason: 'claim 后的 finally 刷新把 buff 抹掉 ⇒ 真机根因');
    final GuardBuffState? buff = await ctx.vouchers.currentBuff();
    expect(buff, isNotNull);
    expect(buff!.remaining, 6);
  });
}
