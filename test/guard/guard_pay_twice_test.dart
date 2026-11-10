/// 守卫战 v2 · **B10/B4 同日第二场必须真扣钱**（玄参第五轮）。
///
/// ## 玄参原话
/// 「在调试面板里重置之后再打一场，**第二次花 5 阳光不扣**」—— 胶囊照常弹出
/// 「−5 ☀」提示，可账本一行没多、余额一分没少。
///
/// ## 病理
/// `claim()` 的账本层幂等（第二层）用**当天**的 `guard_win` 行数做判据：
/// `countByRefTypeAndRefIdOnDay('guard_win', 'garden', today) > 0` ⇒ 视为「今天
/// 已经领过」，直接回放。而账本 id 也是**一天一条**（`guard_pay_<child>_<day>`）
/// —— 第二场即便绕过状态层闸门，`insert` 也会被主键撞掉。
/// 结果：同日第二场「看起来付了钱，实际一分没扣」，孩子白拿一份奖励。
///
/// ## B10 修法（`GuardService`）
/// 1. 账本 id 追加**当日场次后缀**：第 1 场无后缀（与历史 id 逐位相同），
///    第 N 场（N ≥ 2）追加 `_a<序号>`；
/// 2. 场次序号 `= 当日已完成场次 = 当日 guard_win 行数`，在 `resolve()` /
///    `forceThiefForDebug()` 生成状态时定死进 `GuardDayState.battleAttempt`；
/// 3. 账本层判据从「当日行数 > 0」收窄为「当日行数 > **本场序号**」。
///
/// ## 🔴 幂等一格没松
/// 生产路径一天一场 ⇒ `battleAttempt == 0` ⇒ 判据退化为 `行数 > 0`、id 无后缀，
/// 与旧实现**逐位等价**。本文件第 ②③ 条就是守这一格的（重复 claim / 账本半截
/// 状态都只扣一次）。
library guard_pay_twice_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardPayCost, kGuardPayRefType, kGuardWinRefType, kGuardRefId;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

const String _childId = 'c1';
const String _today = '2026-11-09';

DateTime _now() => DateTime(2026, 11, 9, 10, 30);

/// 一条「今天已 resolve、待处理」的存档（账本半截状态用例手工造场景用）。
GuardDayState _pending({
  required int battleAttempt,
  int winSun = 2,
}) {
  return GuardDayState(
    dayKey: _today,
    status: GuardDayStatus.pending,
    thiefKind: GuardThiefKind.sunRat,
    winSun: winSun,
    battleAttempt: battleAttempt,
  );
}

// ────────────────────────────── 内存 Fake 仓储 ──────────────────────────────

/// 守卫状态存储（一天一条，`read` 原样返回旧存档 —— 与 prefs 实现同口径）。
class _FakeStore implements GuardStateStore {
  final Map<String, GuardDayState> byChild = <String, GuardDayState>{};

  @override
  Future<GuardDayState> read(String childId) async =>
      byChild[childId] ?? GuardDayState.empty(_today);

  @override
  Future<void> write(String childId, GuardDayState state) async {
    byChild[childId] = state;
  }

  @override
  Future<void> clear(String childId) async => byChild.remove(childId);
}

/// 阳光账本：累计 `net`，**重复主键抛异常**（模拟 DAO 的 `InsertMode.insert`）。
///
/// 这一条是 B4 的**病灶放大器**：只要 id 撞了，第二次写就会抛 ⇒ `_appendLedger`
/// 吞掉 ⇒ 不扣钱也不报错 —— 正是玄参在真机上看到的「静默不扣」。
class _MemLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  final Set<String> _ids = <String>{};

  /// 期初余额（测试种子）。
  double initial = 0;

  double get balanceValue => initial +
      entries.fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  /// 某 refType 的行（断言用）。
  List<SunlightEntry> rowsOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  /// 某 refType 的 net 合计（断言用）。
  double netOf(String refType) =>
      rowsOf(refType).fold<double>(0, (double a, SunlightEntry e) => a + e.net);

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
      .where(
          (SunlightEntry e) => e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.gross);

  @override
  Future<double> earnNetOnDay(String dayKey) async => entries
      .where(
          (SunlightEntry e) => e.dayKey == dayKey && e.type == SunlightType.earn)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async =>
      entries
          .where(
              (SunlightEntry e) => e.refType == refType && e.dayKey == dayKey)
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
              e.refType == refType && e.refId == refId && !e.ts.isBefore(since))
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

/// 专注仓储：本用例**不种任何会话** ⇒ 今日能量 = 0 ⇒ 必然走「花 5 阳光」路径。
class _FakeFocus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
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

/// 植物仓储（内存；有 1 株存活株 ⇒ `resolve()` 才会生出贼）。
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

/// 一株抽芽期植物（存活 ⇒ 今天有贼）。
Plant _plant(String id) => Plant(
      id: id,
      speciesId: 'sunflower',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 11, 1),
      growthProgress: 0.5,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 11, 1),
      lastWaterAt: DateTime(2026, 11, 8),
      bloomedAt: null,
      bloomCount: 0,
    );

// ───────────────────────────────── 装配 ─────────────────────────────────

class _Ctx {
  _Ctx({
    required this.store,
    required this.ledger,
    required this.guard,
  });

  final _FakeStore store;
  final _MemLedger ledger;
  final GuardService guard;

  GuardDayState get state => store.byChild[_childId]!;

  double get balance => ledger.balanceValue;
}

_Ctx _make({double balance = 20}) {
  final _FakeStore store = _FakeStore();
  final _MemLedger ledger = _MemLedger()..initial = balance;
  final _FakeFocus focus = _FakeFocus();
  final _MemPlants plants = _MemPlants()..store.add(_plant('p1'));
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
    childId: () => _childId,
    clock: _now,
  );
  return _Ctx(store: store, ledger: ledger, guard: guard);
}

void main() {
  group('① B10/B4 同日第二场：账本多一条 −5、余额确实少 5', () {
    test('第一场与第二场各扣一次 5 ☀，id 逐位可区分', () async {
      final _Ctx ctx = _make(balance: 20);

      // ── 第一场（生产路径：一日一场）──────────────────────────────────
      await ctx.guard.resolve(now: _now());
      expect(ctx.state.battleAttempt, 0,
          reason: '第一场序号必须是 0（当日还没有 guard_win 行）');
      final GuardClaimOutcome first = await ctx.guard.claim(now: _now());
      expect(first.ok, isTrue, reason: '第一场必须领取成功');
      expect(first.paidSun, kGuardPayCost,
          reason: '无能量 + 余额充足 ⇒ 必须走付费路径扣 5 ☀');
      final double balanceAfterFirst = ctx.balance;

      // 第一场的 id 必须与历史**逐位相同**（零后缀，老账本零影响）。
      final List<SunlightEntry> pay1 = ctx.ledger.rowsOf(kGuardPayRefType);
      expect(pay1.length, 1);
      expect(pay1.single.id, 'guard_pay_${_childId}_$_today',
          reason: '第 1 场 id 不许带后缀（生产 id 与 B9 之前逐位相同）');
      expect(ctx.ledger.rowsOf(kGuardWinRefType).single.id,
          'guard_win_${_childId}_$_today');

      // ── 第二场（调试重置后再打：玄参报的就是这一场不扣钱）────────────
      await ctx.guard.forceThiefForDebug(now: _now());
      expect(ctx.state.battleAttempt, 1,
          reason: '重置后造出的是**新的一场**：序号 = 当日已完成的 guard_win 行数 = 1');
      expect(ctx.state.status, GuardDayStatus.pending,
          reason: '调试造的贼必须是「待处理」，否则胶囊点不开');

      final GuardClaimOutcome second = await ctx.guard.claim(now: _now());
      expect(second.ok, isTrue, reason: '第二场同样领取成功');
      expect(second.alreadyClaimed, isFalse,
          reason: '🔴 第二场绝不能被当成「今天已经领过」回放 —— 那就是玄参看到的 bug');
      expect(second.paidSun, kGuardPayCost,
          reason: '🔴 B4 核心：第二场必须真的扣 5 ☀');

      // 账本：多一条 −5，且两条合计 −10。
      final List<SunlightEntry> pay2 = ctx.ledger.rowsOf(kGuardPayRefType);
      expect(pay2.length, 2, reason: '🔴 第二场必须在账本多落一条 guard_pay');
      expect(pay2.first.net, -5.0, reason: '第一场：−5 ☀（写死数字，不从实现常量反推）');
      expect(pay2.last.net, -5.0, reason: '第二场：−5 ☀');
      expect(ctx.ledger.netOf(kGuardPayRefType), -10.0,
          reason: '两场合计必须 −10 ☀');
      expect(pay2.last.id, 'guard_pay_${_childId}_${_today}_a1',
          reason: '第二场 id 带场次后缀 `_a1` ⇒ 不会再被主键去重静默丢弃');

      // 奖励同样多一条（否则「扣钱不发奖」会把第二场的券吃掉）。
      expect(ctx.ledger.rowsOf(kGuardWinRefType).length, 2,
          reason: '第二场也要落一条 guard_win（_a1）');
      expect(ctx.ledger.rowsOf(kGuardWinRefType).last.id,
          'guard_win_${_childId}_${_today}_a1');

      // 余额：第二场的扣费行上 balanceAfter 严格比第一场结束时少 5。
      expect(pay2.last.balanceAfter, balanceAfterFirst - 5,
          reason: '🔴 「余额少 5」的直接证据：第二行账本的 balanceAfter = 第一场余额 − 5');
      expect(ctx.balance,
          balanceAfterFirst - 5 + second.winSun.toDouble(),
          reason: '期末余额 = 第一场余额 − 5 + 第二场必得阳光');
    });

    test('第三场继续加后缀（不是「只对第二次特殊处理」）', () async {
      final _Ctx ctx = _make(balance: 20);

      await ctx.guard.resolve(now: _now());
      await ctx.guard.claim(now: _now());

      for (int round = 1; round <= 2; round++) {
        await ctx.guard.forceThiefForDebug(now: _now());
        expect(ctx.state.battleAttempt, round,
            reason: '第 ${round + 1} 场的序号必须等于当日已完成的 guard_win 行数');
        final GuardClaimOutcome out = await ctx.guard.claim(now: _now());
        expect(out.paidSun, kGuardPayCost,
            reason: '第 ${round + 1} 场同样要真扣 5 ☀');
      }

      final List<String> ids = <String>[
        for (final SunlightEntry e in ctx.ledger.rowsOf(kGuardPayRefType)) e.id,
      ];
      expect(ids, <String>[
        'guard_pay_${_childId}_$_today',
        'guard_pay_${_childId}_${_today}_a1',
        'guard_pay_${_childId}_${_today}_a2',
      ], reason: '三场三行，后缀按场次序号递增');
      expect(ctx.ledger.netOf(kGuardPayRefType), -15.0);
    });
  });

  group('② 生产幂等一格没松（一天一场只扣一次）', () {
    test('同一场连调三次 claim：只有一条 guard_pay', () async {
      final _Ctx ctx = _make(balance: 20);
      await ctx.guard.resolve(now: _now());

      final GuardClaimOutcome first = await ctx.guard.claim(now: _now());
      expect(first.ok, isTrue);
      final double afterFirst = ctx.balance;

      final GuardClaimOutcome again = await ctx.guard.claim(now: _now());
      final GuardClaimOutcome third = await ctx.guard.claim(now: _now());
      expect(again.alreadyClaimed, isTrue, reason: '状态层幂等：已领取 ⇒ 回放');
      expect(third.alreadyClaimed, isTrue);
      expect(ctx.ledger.rowsOf(kGuardPayRefType).length, 1,
          reason: '🔴 重复点击绝不许再落一条 guard_pay');
      expect(ctx.balance, afterFirst, reason: '🔴 重复点击绝不许再动余额');
    });

    test('账本半截状态（prefs 没落上）：账本层判据挡住第二次扣费', () async {
      final _Ctx ctx = _make(balance: 20);
      // 手工造场景：账本里已经有本场的 guard_win（写成功了），
      // 但存档仍是 pending / 序号 0（prefs 写失败）。
      await ctx.ledger.append(SunlightEntry(
        id: 'guard_win_${_childId}_$_today',
        ts: _now(),
        type: SunlightType.earn,
        gross: 2,
        net: 2,
        balanceAfter: 22,
        refType: kGuardWinRefType,
        refId: kGuardRefId,
        dayKey: _today,
      ));
      ctx.store.byChild[_childId] = _pending(battleAttempt: 0);
      final double before = ctx.balance;

      final GuardClaimOutcome out = await ctx.guard.claim(now: _now());
      expect(out.alreadyClaimed, isTrue,
          reason: '本场已有 guard_win 行 ⇒ 视为已领取（宁可少发一次，绝不重复发）');
      expect(ctx.ledger.rowsOf(kGuardPayRefType), isEmpty,
          reason: '🔴 半截状态绝不许补扣一次 5 ☀');
      expect(ctx.balance, before, reason: '余额一分不动');
      expect(ctx.state.status, GuardDayStatus.claimed,
          reason: '顺带把状态修复成 claimed，下次不再走这条分支');
    });
  });
}
