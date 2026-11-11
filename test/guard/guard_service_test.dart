/// 花园守卫 · 编排服务（`GuardService`）单测。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.2 / §3.3 / §3.6 / §7。
///
/// ## 本文件钉死的 10 条红线（每条都能真红：改坏实现即失败）
/// | # | 红线 | 断言口径 |
/// |---|---|---|
/// | A1 | 先能量后阳光 | 有 1 点能量 ⇒ `paidSun == 0`、账本只有 1 行 `guard_win`；能量 0 才扣 5 |
/// | A2 | 余额不足不许扣钱 | 余额 3 + 无能量 ⇒ 失败、账本 0 行、余额仍 3 |
/// | A3 | 余额钳制 | 余额 2 被偷 3 ⇒ 余额 **0**（不是 −1） |
/// | A4 | 幂等 | 连调两次 `claim()` ⇒ 只扣一次钱、只发一次奖励 |
/// | A5 | 免费券不整批 | 见 `guard_voucher_test.dart`（本文件另测「券只经服务产出」） |
/// | A6 | 浇水券封顶 | 见 `guard_voucher_test.dart` |
/// | A7 | 同一天 `expire()` 空操作 | 不写账本、不清档 |
/// | A8 | 时钟回拨 `expire()` 空操作 | `today < state.dayKey` ⇒ 不结算、不清档 |
/// | A9 | 开花株不被扣 | `raidGrowth` 对 `bloomed` 无效（`growthProgress` 仍 1.0） |
/// | A10 | `resolve()` 不写账本 | `append` 调用次数 = 0 |
///
/// 🔴 期望值一律写死常量（5 / 2 / 3 / 0.05），**不从实现里引用同一常量反推**
/// —— 否则常量被改错时测试会跟着一起错。
library guard_service_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardWinSunNoItem;
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
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
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

const String _childId = 'c1';
const String _today = '2026-11-09';
const String _yesterday = '2026-11-08';
const String _tomorrow = '2026-11-10';

DateTime _now() => DateTime(2026, 11, 9, 10, 30);
DateTime _nowNextDay() => DateTime(2026, 11, 10, 0, 5);

// ────────────────────────────── 内存 Fake 仓储 ──────────────────────────────

/// 守卫状态存储（一天一条，`read` 原样返回旧存档 —— 与 prefs 实现同口径）。
class _FakeStore implements GuardStateStore {
  final Map<String, GuardDayState> byChild = <String, GuardDayState>{};
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<GuardDayState> read(String childId) async =>
      byChild[childId] ?? GuardDayState.empty(_today);

  @override
  Future<void> write(String childId, GuardDayState state) async {
    byChild[childId] = state;
    writeCount++;
  }

  @override
  Future<void> clear(String childId) async {
    byChild.remove(childId);
    clearCount++;
  }
}

/// 阳光账本（真实现：累计 net；🔴 重复主键抛异常，模拟 DAO 的 `insert`）。
class _MemLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  final Set<String> _ids = <String>{};

  /// 期初余额（测试种子）。
  double initial = 0;

  /// 当前余额。
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
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => entries
      .where((SunlightEntry e) => e.refType == refType && e.dayKey == dayKey)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && (e.dayKey.startsWith(monthKey)))
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

  /// 账本里某 refType 的行数（断言用）。
  int countOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).length;
}

/// 专注仓储（按 dayKey 提供会话；写入不关心）。
class _FakeFocus implements FocusRepository {
  final Map<String, List<FocusSession>> byDay = <String, List<FocusSession>>{};

  /// 造 [count] 条「有效专注」（25 分钟 / 计划 25 分钟 ⇒ 完成率 100%）。
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

  /// 造 [count] 条「无效专注」（3 分钟就放弃）。
  void seedAborted(String dayKey, int count) {
    byDay[dayKey] = <FocusSession>[
      for (int i = 0; i < count; i++)
        FocusSession(
          id: '$dayKey-a$i',
          start: DateTime(2026, 11, 9, 9, i),
          plannedMin: 25,
          actualFocusMin: 3,
          status: FocusStatus.shortAborted,
          sunlightEarned: 0,
          createdAt: DateTime(2026, 11, 9, 9, i),
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

/// 植物仓储（内存；`plants()` 返回副本，避免调用方改到内部列表）。
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

// ───────────────────────────────── 装配 ─────────────────────────────────

class _Ctx {
  _Ctx({
    required this.store,
    required this.ledger,
    required this.focus,
    required this.plants,
    required this.growth,
    required this.guard,
  });

  final _FakeStore store;
  final _MemLedger ledger;
  final _FakeFocus focus;
  final _MemPlants plants;
  final PlantGrowthService growth;
  final GuardService guard;

  /// 便捷读存档。
  GuardDayState get state => store.byChild[_childId]!;

  double get balance => ledger.balanceValue;
}

_Ctx _make({
  double balance = 100,
  List<Plant> plants = const <Plant>[],
  int validSessionsToday = 0,
  int validSessionsYesterday = 0,
  int abortedSessionsToday = 0,
  // 🔴 B13.8 能量档位制：免费 cap 1 / 付费 cap 2（缺省免费，旧用例零改动）。
  bool isPremium = false,
}) {
  final _FakeStore store = _FakeStore();
  final _MemLedger ledger = _MemLedger()..initial = balance;
  final _FakeFocus focus = _FakeFocus();
  if (validSessionsToday > 0) focus.seedValid(_today, validSessionsToday);
  if (validSessionsYesterday > 0) {
    focus.seedValid(_yesterday, validSessionsYesterday);
  }
  if (abortedSessionsToday > 0) focus.seedAborted(_today, abortedSessionsToday);
  final _MemPlants plantsRepo = _MemPlants()..store.addAll(plants);
  final PlantGrowthService growth = PlantGrowthService(
    plants: plantsRepo,
    focus: focus,
    ledger: ledger,
    settings: _MemSettings(),
    bloomRewards: InMemoryBloomRewardRepository(),
  );
  final GuardService guard = GuardService(
    store: store,
    ledger: ledger,
    focus: focus,
    plants: plantsRepo,
    growth: growth,
    childId: () => _childId,
    clock: _now,
    isPremium: () => isPremium,
  );
  return _Ctx(
    store: store,
    ledger: ledger,
    focus: focus,
    plants: plantsRepo,
    growth: growth,
    guard: guard,
  );
}

/// 用同一套仓储、**换一个时钟**新建一个 `GuardService`。
///
/// 模拟「孩子看完动画后强杀进程 / 手机没电 / 闪退，次日重新进 App」：
/// 内存里的对象全没了，能看到的只有存储里的那条存档。
GuardService _guardAt(_Ctx ctx, DateTime Function() clock) => GuardService(
      store: ctx.store,
      ledger: ctx.ledger,
      focus: ctx.focus,
      plants: ctx.plants,
      growth: ctx.growth,
      childId: () => _childId,
      clock: clock,
    );

/// 一株植物（默认：抽芽期、进度 50%）。
Plant _plant(
  String id, {
  PlantStatus status = PlantStatus.growing,
  double progress = 0.5,
  int potIndex = 0,
}) =>
    Plant(
      id: id,
      speciesId: 'sunflower',
      potIndex: potIndex,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 11, 1),
      growthProgress: progress,
      growthFactor: 1.0,
      status: status,
      plantedAt: DateTime(2026, 11, 1),
      lastWaterAt: DateTime(2026, 11, 8),
      bloomedAt: status == PlantStatus.bloomed ? DateTime(2026, 11, 8) : null,
      bloomCount: status == PlantStatus.bloomed ? 1 : 0,
    );

/// 一条「今天已 resolve、待处理」的存档。
GuardDayState _pendingState({
  String dayKey = _today,
  GuardDayStatus status = GuardDayStatus.pending,
  GuardThiefKind thief = GuardThiefKind.sunRat,
  GuardDropKind drop = GuardDropKind.none,
  int winSun = 2,
  int sunStolen = 0,
  Map<String, double> growthStolen = const <String, double>{},
  int energyUsed = 0,
  int paidSun = 0,
  GuardBuffState? buff,
}) =>
    GuardDayState(
      dayKey: dayKey,
      status: status,
      thiefKind: thief,
      energyUsed: energyUsed,
      paidSun: paidSun,
      winSun: winSun,
      dropKind: drop,
      sunStolen: sunStolen,
      growthStolen: growthStolen,
      buff: buff,
    );

void main() {
  // ───────────────────────── A1：先能量后阳光 ─────────────────────────
  group('A1 成本顺序：先能量，能量为 0 才扣阳光', () {
    test('有 1 点能量：claim 不扣阳光，只发必得阳光', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      await ctx.store.write(
        _childId,
        _pendingState(winSun: 2, drop: GuardDropKind.none),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      expect(out.usedEnergy, isTrue);
      expect(out.paidSun, 0, reason: '🔴 有能量时必须不花阳光');
      expect(out.winSun, 2);
      expect(ctx.ledger.entries.length, 1, reason: '免费路径不写扣费行，只有 1 行 earn');
      expect(ctx.ledger.countOf('guard_pay'), 0);
      expect(ctx.ledger.countOf('guard_win'), 1);
      expect(ctx.balance, 102, reason: '100 + 2');
      expect(ctx.state.energyUsed, 1);
      expect(ctx.state.isClaimed, isTrue);
      expect(out.energyAvailable, 0, reason: '1 点能量已用完');
    });

    test('能量为 0 时才扣 5 ☀（100 − 5 + 2 = 97）', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        abortedSessionsToday: 3, // 3 分钟就放弃的会话不算有效专注
      );
      await ctx.store.write(
        _childId,
        _pendingState(winSun: 2, drop: GuardDropKind.none),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      expect(out.usedEnergy, isFalse);
      expect(out.paidSun, 5, reason: '🔴 无能量 → 5 ☀');
      expect(ctx.ledger.countOf('guard_pay'), 1);
      expect(ctx.ledger.countOf('guard_win'), 1);
      expect(ctx.balance, 97);
      expect(ctx.state.energyUsed, 0, reason: '付费路径不消耗能量点');
      expect(ctx.state.paidSun, 5);
    });

    test('能量足够但 useEnergy=false ⇒ 强制付费 5 ☀', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 2,
        // 🔴 B13.8：能量够 2 点是**会员档**口径（免费档 cap 1，见下方能量派生组）。
        isPremium: true,
      );
      await ctx.store.write(_childId, _pendingState(winSun: 1));

      final GuardClaimOutcome out = await ctx.guard.claim(useEnergy: false);

      expect(out.usedEnergy, isFalse);
      expect(out.paidSun, 5);
      expect(out.energyAvailable, 2, reason: '能量一点没动');
    });
  });

  // ───────────────────────── A2：余额不足 ─────────────────────────
  group('A2 余额不足：返回明确失败原因，不扣钱、不发放', () {
    test('余额 3 + 无能量 ⇒ 失败、账本 0 行、余额仍 3', () async {
      final _Ctx ctx = _make(balance: 3, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState(winSun: 2));

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isFalse);
      expect(out.failure, GuardClaimFailure.insufficientBalance);
      expect(out.paidSun, 0);
      expect(out.winSun, 0);
      expect(out.buff, isNull);
      expect(ctx.ledger.entries, isEmpty, reason: '🔴 分毫不扣、什么都不发');
      expect(ctx.balance, 3);
      expect(ctx.state.isClaimed, isFalse, reason: '失败不改写状态');
    });

    test('恰好 5 ☀：可以付（边界，扣到 0）', () async {
      final _Ctx ctx = _make(balance: 5, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState(winSun: 2));

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      expect(out.paidSun, 5);
      expect(ctx.balance, 2, reason: '5 − 5 + 2');
    });

    test('还没 resolve（空存档）⇒ notResolved，不扣钱', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isFalse);
      expect(out.failure, GuardClaimFailure.notResolved);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.balance, 100);
    });

    test('全园无存活株 ⇒ resolve 不生成小偷，claim 返回 noThief', () async {
      final _Ctx ctx = _make(balance: 100);
      final GuardResolveResult resolved = await ctx.guard.resolve();
      expect(resolved.hasThief, isFalse);
      expect(resolved.thief, isNull);

      final GuardClaimOutcome out = await ctx.guard.claim();
      expect(out.ok, isFalse);
      expect(out.failure, GuardClaimFailure.noThief);
      expect(ctx.ledger.entries, isEmpty);
    });
  });

  // ───────────────────────── A3：余额钳制 ─────────────────────────
  group('A3 被偷阳光：扣到 0 为止，绝不出现负余额', () {
    test('余额 2、被偷 3 ⇒ 余额 0（不是 −1）', () async {
      final _Ctx ctx = _make(balance: 2);
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          sunStolen: 3,
          thief: GuardThiefKind.sunRat,
        ),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.settled, isTrue);
      expect(out.expiredDayKey, _yesterday);
      expect(out.stolenSun, 2, reason: '🔴 钳制到余额 2');
      expect(ctx.balance, 0, reason: '🔴 绝不出现 −1');
      expect(ctx.ledger.countOf('guard_stolen'), 1);
      expect(ctx.ledger.entries.single.net, -2);
      expect(ctx.ledger.entries.single.dayKey, _yesterday,
          reason: '账本行落在被偷的那一天（对账口径）');
    });

    test('余额 0、被偷 3 ⇒ 不写 0 元账本行', () async {
      final _Ctx ctx = _make(balance: 0);
      await ctx.store.write(
        _childId,
        _pendingState(dayKey: _yesterday, sunStolen: 3),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.stolenSun, 0);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.balance, 0);
    });

    test('余额 100、被偷 3 ⇒ 全额扣 3', () async {
      final _Ctx ctx = _make(balance: 100);
      await ctx.store.write(
        _childId,
        _pendingState(dayKey: _yesterday, sunStolen: 3),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.stolenSun, 3);
      expect(ctx.balance, 97);
      expect(ctx.ledger.entries.single.net, -3);
    });
  });

  // ───────────────────────── A4：幂等 ─────────────────────────
  group('A4 幂等：重复点击只扣一次钱、只发一次奖励', () {
    test('同一天连调 claim 两次 ⇒ 账本恒为 2 行、余额恒为 97', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState(winSun: 2));

      final GuardClaimOutcome first = await ctx.guard.claim();
      expect(first.alreadyClaimed, isFalse);
      expect(first.paidSun, 5);
      expect(ctx.ledger.entries.length, 2, reason: '1 行 guard_pay + 1 行 guard_win');
      expect(ctx.balance, 97);

      final GuardClaimOutcome second = await ctx.guard.claim();

      expect(second.ok, isTrue);
      expect(second.alreadyClaimed, isTrue);
      expect(ctx.ledger.entries.length, 2, reason: '🔴 第二次一个字都不写');
      expect(ctx.ledger.countOf('guard_pay'), 1);
      expect(ctx.ledger.countOf('guard_win'), 1);
      expect(ctx.balance, 97);
    });

    test('状态被清回 pending（模拟 prefs 写失败）⇒ 账本读判定仍然幂等', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState(winSun: 2));
      await ctx.guard.claim();
      expect(ctx.ledger.entries.length, 2);

      // 覆盖回 pending：账本里已经有今天的 guard_win ⇒ 必须视为已领取。
      await ctx.store.write(_childId, _pendingState(winSun: 2));
      final GuardClaimOutcome again = await ctx.guard.claim();

      expect(again.alreadyClaimed, isTrue);
      expect(ctx.ledger.entries.length, 2, reason: '🔴 绝不重复发');
      expect(ctx.balance, 97);
    });

    test('确定性 id：guard_pay / guard_win 的 id 带 childId + dayKey', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState(winSun: 2));
      await ctx.guard.claim();

      final Set<String> ids =
          ctx.ledger.entries.map((SunlightEntry e) => e.id).toSet();
      expect(ids, <String>{
        'guard_pay_${_childId}_$_today',
        'guard_win_${_childId}_$_today',
      });
    });
  });

  // ───────────────── A7 / A8：跨天与时钟回拨 ─────────────────
  group('A7 同一天 expire 空操作 / A8 时钟回拨空操作', () {
    test('state.dayKey == 今天 ⇒ 什么都不做（不写账本、不清档）', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(
        _childId,
        _pendingState(sunStolen: 3, growthStolen: <String, double>{'p1': 0.03}),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.settled, isFalse);
      expect(out.expiredDayKey, isNull);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.store.clearCount, 0);
      expect(ctx.state.dayKey, _today);
      expect(ctx.plants.store.single.growthProgress, 0.5, reason: '成长一分没扣');
    });

    test('时钟回拨（今天早于存档日）⇒ 空操作，且不删档', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(
        _childId,
        _pendingState(dayKey: _tomorrow, sunStolen: 3),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.settled, isFalse);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.store.byChild.containsKey(_childId), isTrue,
          reason: '🔴 回拨一下不能把存档删了');
      expect(ctx.store.clearCount, 0);
    });

    test('跨天结算幂等：第二次 expire 不再扣钱（存档已清）', () async {
      final _Ctx ctx = _make(balance: 100);
      await ctx.store.write(
        _childId,
        _pendingState(dayKey: _yesterday, sunStolen: 3),
      );
      await ctx.guard.expire();
      expect(ctx.ledger.entries.length, 1);

      final GuardExpireOutcome second = await ctx.guard.expire(
        now: _nowNextDay(),
      );
      expect(second.settled, isFalse);
      expect(ctx.ledger.entries.length, 1);
      expect(ctx.balance, 97);
    });

    test('免罚档（余额 < 5 且无能量）⇒ 当天不结算损失', () async {
      final _Ctx ctx = _make(balance: 3, plants: <Plant>[_plant('p1')]);

      final GuardResolveResult resolved = await ctx.guard.resolve();
      expect(resolved.cost, GuardCostMode.freeRide);
      expect(ctx.state.status, GuardDayStatus.short);
      expect(ctx.state.sunStolen, 0, reason: '免罚档落盘时就把损失写成 0');
      expect(ctx.state.growthStolen, isEmpty);

      final GuardExpireOutcome out = await ctx.guard.expire(now: _nowNextDay());
      expect(out.settled, isTrue);
      expect(out.stolenSun, 0);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.balance, 3);
      expect(ctx.plants.store.single.growthProgress, 0.5);
    });

    test('已领取的存档跨天 ⇒ 无损失', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          status: GuardDayStatus.claimed,
          sunStolen: 3,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.settled, isTrue);
      expect(out.stolenSun, 0);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.plants.store.single.growthProgress, 0.5);
    });

    test('进了战斗但没点「收下」⇒ 补发必得阳光、不结算损失', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          status: GuardDayStatus.fighting,
          winSun: 3,
          sunStolen: 2,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.grantedWinSun, 3);
      expect(out.stolenSun, 0);
      expect(ctx.ledger.countOf('guard_win'), 1);
      expect(ctx.ledger.countOf('guard_stolen'), 0);
      expect(ctx.balance, 103);
      expect(ctx.plants.store.single.growthProgress, 0.5, reason: '不结算成长损失');
    });
  });

  // ───────────── A8′：markFighting（进战斗落盘，强杀重启不再照罚）─────────────
  group('A8′ markFighting：把「已动手」落盘，次日 expire 不照罚', () {
    test('标记后换新 service 实例（模拟强杀重启）⇒ 次日不扣损失 + 补发必得阳光', () async {
      // ── 对照组：**不标记** ⇒ 次日按「没处理」照罚（这个洞是真的）──
      final _Ctx control =
          _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await control.store.write(
        _childId,
        _pendingState(
          dayKey: _today,
          status: GuardDayStatus.pending,
          winSun: 3,
          sunStolen: 2,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      );

      final GuardExpireOutcome punished =
          await _guardAt(control, _nowNextDay).expire();

      expect(punished.stolenSun, 2, reason: '不标记 ⇒ 阳光照扣');
      expect(control.plants.store.single.growthProgress, closeTo(0.47, 1e-12),
          reason: '不标记 ⇒ 成长照扣');
      expect(control.ledger.countOf('guard_stolen'), 1);
      expect(control.ledger.countOf('guard_win'), 0);

      // ── 实验组：**标记过** ⇒ 次日走 fighting 分支 ──
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _today,
          status: GuardDayStatus.pending,
          winSun: 3,
          sunStolen: 2,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      );

      await ctx.guard.markFighting();
      expect(ctx.state.status, GuardDayStatus.fighting,
          reason: 'markFighting 必须把 pending 写成 fighting');

      // 🔴 全新实例 = 内存里的 UI 状态全丢，只剩存储里那条存档。
      final GuardExpireOutcome out = await _guardAt(ctx, _nowNextDay).expire();

      expect(out.settled, isTrue);
      expect(out.expiredDayKey, _today);
      expect(out.stolenSun, 0, reason: '🔴 已进战斗 ⇒ 不结算损失');
      expect(out.grantedWinSun, 3, reason: '🔴 已进战斗 ⇒ 补发必得阳光');
      expect(out.growthTargets, 0);
      expect(ctx.ledger.countOf('guard_stolen'), 0, reason: '不得写 stolen 行');
      expect(ctx.ledger.countOf('guard_win'), 1, reason: '补发恰好一次');
      expect(ctx.balance, 103, reason: '100 + 3（没扣钱）');
      expect(ctx.plants.store.single.growthProgress, 0.5,
          reason: '🔴 成长分毫未动');
      expect(ctx.store.byChild[_childId], isNull, reason: '结算后清档');
    });

    test('非 pending / 非今日 一律空操作（存档对象 == 原状态，且不写库）', () async {
      // ① 已领取 / ② 免罚 / ③ 已在战斗中 / ④ 无贼 / ⑤ 昨天的 pending。
      final List<GuardDayState> cases = <GuardDayState>[
        _pendingState(status: GuardDayStatus.claimed, sunStolen: 2),
        _pendingState(status: GuardDayStatus.short),
        _pendingState(status: GuardDayStatus.fighting),
        _pendingState(thief: GuardThiefKind.sunRat)
            .copyWith(clearThief: true, status: GuardDayStatus.none),
        _pendingState(
          dayKey: _yesterday,
          status: GuardDayStatus.pending,
          sunStolen: 2,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      ];

      for (final GuardDayState original in cases) {
        final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
        await ctx.store.write(_childId, original);
        final int writesBefore = ctx.store.writeCount;

        await ctx.guard.markFighting();

        expect(ctx.store.writeCount, writesBefore,
            reason: '🔴 ${original.status.id}/${original.dayKey} 必须一个字节都不写'
                '（昨天的 pending 若被改成 fighting，昨天的损失就永远收不回来了）');
        expect(ctx.state, original, reason: '存档对象必须 == 原状态');
      }

      // ⑥ 从未 resolve 过（连存档都没有）→ 也是空操作。
      final _Ctx empty = _make(balance: 100);
      await empty.guard.markFighting();
      expect(empty.store.writeCount, 0);
      expect(empty.store.byChild[_childId], isNull);
    });
  });

  // ───────────────────────── A9：开花株免疫 ─────────────────────────
  group('A9 raidGrowth：开花株不被扣、其余株照扣', () {
    test('开花株（progress = 1.0）传进 raidGrowth 后仍是 1.0', () async {
      final _Ctx ctx = _make(
        plants: <Plant>[
          _plant('p1', status: PlantStatus.bloomed, progress: 1.0),
        ],
      );

      await ctx.growth.raidGrowth(
        lossByPlantId: <String, double>{'p1': 0.05},
      );

      final Plant after = ctx.plants.store.single;
      expect(after.growthProgress, 1.0, reason: '🔴 开花株免疫（阶段绝不回退）');
      expect(after.status, PlantStatus.bloomed);
      expect(after.stageStartedAt, DateTime(2026, 11, 1), reason: '不动 stageStartedAt');
      expect(after.stage, PlantStage.sprout, reason: '不动 stage');
    });

    test('普通株照扣，且封顶 0.05（与纯函数同口径）', () async {
      final _Ctx ctx = _make(
        plants: <Plant>[
          _plant('p1', progress: 0.5),
          _plant('p2', progress: 0.5),
        ],
      );

      await ctx.growth.raidGrowth(
        lossByPlantId: <String, double>{'p1': 0.03, 'p2': 0.20},
      );

      expect(ctx.plants.store.firstWhere((Plant p) => p.id == 'p1').growthProgress,
          closeTo(0.47, 1e-12));
      expect(ctx.plants.store.firstWhere((Plant p) => p.id == 'p2').growthProgress,
          closeTo(0.45, 1e-12),
          reason: '🔴 单株单日封顶 5pp（不是 20pp）');
    });

    test('不存在的株 / 死株：跳过不抛异常', () async {
      final _Ctx ctx = _make(
        plants: <Plant>[_plant('dead-1', status: PlantStatus.dead, progress: 0.4)],
      );

      await ctx.growth.raidGrowth(
        lossByPlantId: <String, double>{'ghost': 0.05, 'dead-1': 0.05},
      );

      expect(ctx.plants.store.single.growthProgress, 0.4);
    });

    test('expire 会把 growthStolen 真的落到 plants 表（逐个重读最新行）', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[
          _plant('p1', progress: 0.5),
          _plant('p2', status: PlantStatus.bloomed, progress: 1.0),
        ],
      );
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'p1': 0.03, 'p2': 0.03},
        ),
      );

      final GuardExpireOutcome out = await ctx.guard.expire();

      expect(out.growthTargets, 1,
          reason: '实际只扣到 p1 一株（p2 开花免疫，不计数）');
      expect(ctx.plants.store.firstWhere((Plant p) => p.id == 'p1').growthProgress,
          closeTo(0.47, 1e-12));
      expect(ctx.plants.store.firstWhere((Plant p) => p.id == 'p2').growthProgress,
          1.0, reason: '🔴 开花株免疫');
    });
  });

  // ───────────────────────── A10：resolve 不写账本 ─────────────────────────
  group('A10 resolve 只算不记账（与 claim 必须分离）', () {
    test('resolve 后账本 append 次数 = 0', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );

      final GuardResolveResult out = await ctx.guard.resolve();

      expect(ctx.ledger.entries, isEmpty, reason: '🔴 resolve 绝对不写账本');
      expect(out.hasThief, isTrue);
      expect(out.cost, GuardCostMode.free);
      expect(out.thief, deriveGuardRoll(dayKey: _today, childId: _childId).thief);
      expect(ctx.state.hasThief, isTrue, reason: '只落盘 prefs');
      expect(ctx.state.dayKey, _today);
    });

    test('同一天重复 resolve 不重掷（同一只贼、同一份奖励）', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );

      final GuardResolveResult first = await ctx.guard.resolve();
      final GuardDayState afterFirst = ctx.state;
      final GuardResolveResult second = await ctx.guard.resolve();

      expect(second.thief, first.thief);
      expect(second.winSun, first.winSun);
      expect(second.drop, first.drop);
      expect(ctx.state, afterFirst, reason: '状态逐字段不变');
      expect(ctx.ledger.entries, isEmpty);
    });

    test('付费档：resolve 标 pending + 记录将被偷的金额，但不扣', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);

      final GuardResolveResult out = await ctx.guard.resolve();

      expect(out.cost, GuardCostMode.paid);
      expect(ctx.ledger.entries, isEmpty);
      expect(ctx.balance, 100, reason: 'resolve 分毫不扣');
      expect(ctx.state.status, GuardDayStatus.pending);
    });

    test('🔴 昨天未结算 ⇒ resolve 拒绝覆盖（needsExpire），先 expire 再 resolve', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          sunStolen: 3,
          growthStolen: <String, double>{'p1': 0.03},
        ),
      );

      final GuardResolveResult blocked = await ctx.guard.resolve();

      expect(blocked.needsExpire, isTrue, reason: '🔴 必须先结算昨天');
      expect(ctx.state.dayKey, _yesterday, reason: '昨天的存档一个字都没被改');
      expect(ctx.state.sunStolen, 3);
      expect(ctx.state.growthStolen, <String, double>{'p1': 0.03});
      expect(ctx.ledger.entries, isEmpty, reason: 'resolve 仍不写账本');

      // 正确时序：expire() 结算昨天 → resolve() 生成今天。
      final GuardExpireOutcome expired = await ctx.guard.expire();
      expect(expired.stolenSun, 3);
      final GuardResolveResult today = await ctx.guard.resolve();
      expect(today.needsExpire, isFalse);
      expect(ctx.state.dayKey, _today);
      expect(ctx.state.hasThief, isTrue);
    });

    test('成长损失按「贼的命中范围」落盘：贪婪鼬全株 / 食叶虫只 1 株', () async {      // 覆盖全部存活株：用「每株都真的出现在 growthStolen 里」的方式验证，
      // 不依赖今天恰好掷到哪只贼（确定性派生对固定 dayKey 是常数）。
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[
          _plant('p1', potIndex: 0),
          _plant('p2', potIndex: 1),
          _plant('p3', potIndex: 2),
          _plant('p4', status: PlantStatus.bloomed, progress: 1.0, potIndex: 3),
        ],
      );

      await ctx.guard.resolve();
      final GuardThiefKind thief = ctx.state.thiefKind!;
      final Map<String, double> loss = ctx.state.growthStolen;

      if (!thief.stealsGrowth) {
        expect(loss, isEmpty, reason: '馋光鼠不偷成长');
      } else if (thief.spec.hitsEveryPlant) {
        expect(loss.length, 4, reason: '贪婪鼬：全部存活株各一份');
        expect(loss.containsKey('p4'), isTrue,
            reason: '开花株也在列表里（免疫由纯函数负责，不在服务层复判）');
      } else {
        expect(loss.length, 1, reason: '食叶虫：只挑 1 株');
        expect(loss.containsKey('p4'), isFalse, reason: '开花株免疫，不会被挑中');
      }
    });
  });

  // ───────────────────────── 能量派生（B13.8 档位制）─────────────────────────
  group('能量派生：clamp(今日有效专注次数, 0, 档位上限) − 已消耗（免费 1 / 付费 2）', () {
    test('免费档：1 次有效专注 = 1 点；5 次也只给 1 点（cap 1）', () async {
      final _Ctx ctx1 = _make(validSessionsToday: 1);
      expect(await ctx1.guard.energyAvailable(), 1);

      final _Ctx ctx5 = _make(validSessionsToday: 5);
      expect(await ctx5.guard.energyAvailable(), 1,
          reason: '🔴 B13.8：免费档日上限 = kGuardEnergyDailyMaxFree(1)');
    });

    test('会员档：5 次有效专注给 2 点（cap 2）', () async {
      final _Ctx ctx2 = _make(validSessionsToday: 2, isPremium: true);
      expect(await ctx2.guard.energyAvailable(), 2);

      final _Ctx ctx5 = _make(validSessionsToday: 5, isPremium: true);
      expect(await ctx5.guard.energyAvailable(), 2,
          reason: '🔴 会员档日上限 = kGuardEnergyDailyMaxPremium(2)');
    });

    test('3 分钟就放弃的会话不算能量（不许用 sessions.length）', () async {
      final _Ctx ctx = _make(abortedSessionsToday: 4);
      expect(await ctx.guard.energyAvailable(), 0);
    });

    test('已消耗会扣减；全部用完 = 0（免费档口径）', () async {
      final _Ctx ctx = _make(validSessionsToday: 1);
      await ctx.store.write(_childId, _pendingState(energyUsed: 1));
      expect(await ctx.guard.energyAvailable(), 0);

      await ctx.store.write(_childId, _pendingState(energyUsed: 2));
      expect(await ctx.guard.energyAvailable(), 0);
    });

    test('昨天的 energyUsed 不影响今天（会员档口径）', () async {
      final _Ctx ctx = _make(validSessionsToday: 2, isPremium: true);
      await ctx.store.write(
        _childId,
        _pendingState(dayKey: _yesterday, energyUsed: 2),
      );
      expect(await ctx.guard.energyAvailable(), 2);
    });
  });

  // ───────────────────────── 今日视图（跨天归一） ─────────────────────────
  group('todayState：跨天后昨天的贼 / 券一个都不许出现', () {
    test('存档是昨天的 ⇒ 返回空白当日状态', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _yesterday,
          drop: GuardDropKind.waterVoucher,
          buff: guardBuffFor(GuardDropKind.waterVoucher),
        ),
      );

      final GuardDayState today = await ctx.guard.todayState();

      expect(today.dayKey, _today);
      expect(today.hasThief, isFalse);
      expect(today.buff, isNull);
      expect(today, GuardDayState.empty(_today));
    });

    test('存档是今天的 ⇒ 原样返回', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(_childId, _pendingState(winSun: 3));
      final GuardDayState today = await ctx.guard.todayState();
      expect(today.winSun, 3);
    });
  });

  // ───────────────────────── claim 发券 / 落 buff ─────────────────────────
  group('claim 发放掉落：buff 额度与掉落档同源', () {
    test('掉浇水券 ⇒ buff（quota 6）；无道具档 ⇒ 没有 buff', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      await ctx.store.write(
        _childId,
        _pendingState(winSun: 2, drop: GuardDropKind.waterVoucher),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.drop, GuardDropKind.waterVoucher);
      expect(out.buff, isNotNull);
      expect(out.buff!.kind, GuardDropKind.waterVoucher);
      expect(out.buff!.quota, 6);
      expect(out.buff!.used, 0);
      expect(ctx.state.buff!.quota, 6, reason: 'buff 落盘');
    });

    test('🔴 B13.5 双券：第二张掉落 ⇒ claim 同步发 bonusBuff 落盘', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      // pending 存档由 resolve 写入：主券 water + 第二张 labor（模拟
      // deriveGuardRoll(isPremium) 的双券输出）。
      await ctx.store.write(
        _childId,
        _pendingState(winSun: 2, drop: GuardDropKind.waterVoucher).copyWith(
          bonusDropKind: GuardDropKind.laborVoucher,
        ),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.drop, GuardDropKind.waterVoucher);
      expect(out.bonusDrop, GuardDropKind.laborVoucher);
      expect(out.bonusBuff, isNotNull);
      expect(out.bonusBuff!.kind, GuardDropKind.laborVoucher);
      expect(ctx.state.bonusBuff, isNotNull, reason: '第二张 buff 落盘');
      expect(ctx.state.bonusBuff!.kind, GuardDropKind.laborVoucher);
      expect(ctx.state.buff!.kind, GuardDropKind.waterVoucher,
          reason: '主券槽位不受双券影响');
    });

    test('🔴 B13.5：主券档无第二张（bonusDropKind=none）⇒ 不发 bonusBuff', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      await ctx.store.write(
        _childId,
        _pendingState(winSun: 2, drop: GuardDropKind.waterVoucher),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.bonusDrop, GuardDropKind.none);
      expect(out.bonusBuff, isNull);
      expect(ctx.state.bonusBuff, isNull);
    });

    test('无道具档 ⇒ winSun 取保底（= kGuardWinSunNoItem；B5b 起区间上限 5）', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      // winSun 缺省 0（模拟脏存档）→ claim 兜底发 NoItem（D2：取区间上限），
      // 绝不发 0。🔴 B5b：win 区间 1~3 → 3~5 ⇒ 保底 3 → 5（区间上限同源）。
      await ctx.store.write(_childId, _pendingState(winSun: 0));

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.winSun, kGuardWinSunNoItem);
      expect(ctx.balance, 100.0 + kGuardWinSunNoItem);
      expect(out.buff, isNull);
    });
  });

  // ─────────────────── D：调试接缝（第四批 B，仅 kDebugMode）───────────────────
  //
  // 四个 `*ForDebug` 方法都是 add-only 的调试口：只写今日状态，不写账本。
  // 断言一律写**字面量**（1 / 3 / 0），不引用实现里的常量反推。
  group('D 调试接缝：forceThief / exhaustEnergy / grantVoucher / reset', () {
    test('D1 forceThiefForDebug 覆盖今日存档：status=pending，贼 / 掉落 / 必得阳光逐位相等',
        () async {
      final _Ctx ctx = _make(plants: <Plant>[_plant('p1')]);
      // 先写一条「昨天」的存档：本方法**不走** resolve 的「昨天未结算就拒写」闸门。
      await ctx.store.write(_childId, _pendingState(dayKey: _yesterday));

      await ctx.guard.forceThiefForDebug(
        thief: GuardThiefKind.sneakThief,
        drop: GuardDropKind.freeWater,
        winSun: 3,
      );

      final GuardDayState s = await ctx.guard.todayState();
      expect(s.dayKey, _today);
      expect(s.status, GuardDayStatus.pending);
      expect(s.thiefKind, GuardThiefKind.sneakThief);
      expect(s.dropKind, GuardDropKind.freeWater);
      expect(s.winSun, 3);
      expect(ctx.ledger.entries, isEmpty, reason: '调试接缝绝不写账本');
    });

    test("D1′ forceThiefForDebug 缺省 drop：保留今天的掉落档，不再擦成 none（B12）",
        () async {
      final _Ctx ctx = _make(plants: <Plant>[_plant('p1')]);
      // 今天的存档带自然摇到的券档（模拟 resolve 写入的 dropKind）。
      await ctx.store.write(
        _childId,
        _pendingState(
          dayKey: _today,
          drop: GuardDropKind.waterVoucher,
          buff: guardBuffFor(GuardDropKind.waterVoucher),
        ),
      );

      // 调试重置不带 drop —— 旧口径会覆盖成 none（玄参「每场都没掉落」的根因）。
      await ctx.guard.forceThiefForDebug(thief: GuardThiefKind.sneakThief);

      final GuardDayState s = await ctx.guard.todayState();
      expect(s.dropKind, GuardDropKind.waterVoucher,
          reason: '调试重置只重摆怪，不许擦掉今天自然摇到的券');
      expect(s.buff, isNotNull, reason: '券档在，buff 必须同步在（不然券用不了）');
      expect(s.thiefKind, GuardThiefKind.sneakThief);
    });

    test("D1″ forceThiefForDebug 当天无存档：drop 走 GuardDropKind.roll（与 resolve 同源）",
        () async {
      final _Ctx ctx = _make(plants: <Plant>[_plant('p1')]);

      await ctx.guard.forceThiefForDebug(thief: GuardThiefKind.sneakThief);

      final GuardDayState s = await ctx.guard.todayState();
      expect(
        s.dropKind,
        GuardDropKind.roll(dayKey: _today, childId: _childId),
        reason: '无存档时的缺省档必须与 resolve 同一确定性通道，不许写死 none',
      );
    });

    test('D2 exhaustEnergyForDebug：有 1 次有效专注时能量从 1 归 0', () async {
      final _Ctx ctx = _make(
        plants: <Plant>[_plant('p1')],
        validSessionsToday: 1,
      );
      expect(await ctx.guard.energyAvailable(), 1, reason: '1 次有效专注 = 1 点能量');

      await ctx.guard.exhaustEnergyForDebug();

      expect(await ctx.guard.energyAvailable(), 0);
      expect(ctx.state.energyUsed, 1, reason: '已用能量 = 赚到的总量');
    });

    test('D3 grantVoucherForDebug：免费浇水券 remaining=1；无道具档空操作', () async {
      final _Ctx ctx = _make(plants: <Plant>[_plant('p1')]);
      final GuardVoucherService vouchers = GuardVoucherService(
        store: ctx.store,
        childId: () => _childId,
        clock: _now,
      );

      await ctx.guard.grantVoucherForDebug(GuardDropKind.freeWater);

      final GuardBuffState? buff = await vouchers.currentBuff();
      expect(buff, isNotNull);
      expect(buff!.kind, GuardDropKind.freeWater);
      expect(buff.remaining, 1);

      // 无道具档：guardBuffFor 返回 null ⇒ 不写、不改（存档对象逐位相同）。
      final GuardDayState before = ctx.state;
      final int writes = ctx.store.writeCount;
      await ctx.guard.grantVoucherForDebug(GuardDropKind.none);
      expect(ctx.state, before);
      expect(ctx.store.writeCount, writes);
    });

    test('D4 resetForDebug：todayState 回到空白（无贼）', () async {
      final _Ctx ctx = _make(plants: <Plant>[_plant('p1')]);
      await ctx.store.write(_childId, _pendingState());

      await ctx.guard.resetForDebug();

      final GuardDayState s = await ctx.guard.todayState();
      expect(s.hasThief, isFalse);
      expect(s.status, GuardDayStatus.none);
      expect(s.dropKind, GuardDropKind.none);
      expect(ctx.store.clearCount, 1);
    });
  });

  // ────────────────── B1：recordBattleTheft（守卫战 v2 唯一新增落账口）──────────────────
  //
  // 真源：`docs/花园守卫_守卫战玩法_增量设计_v1.md` §5.2 / §5.3 / §8.4。
  // 期望值全部字面量：封顶 3、id = 'guard_stolen_c1_2026-11-09'。
  group('B1 recordBattleTheft：结束时一次写 / 封顶 / 互斥 / 零成长扣减', () {
    test('E1 封顶：被偷合计 7 → 落账恰 3、恰 1 行、id 冻结格式', () async {
      final _Ctx ctx = _make(balance: 100);

      final int charged = await ctx.guard.recordBattleTheft(stolenSun: 7);

      expect(charged, 3, reason: 'min(7, kGuardStealDailyCap=3, 余额 100) = 3');
      expect(ctx.ledger.countOf('guard_stolen'), 1);
      final SunlightEntry entry = ctx.ledger.entries.single;
      expect(entry.id, 'guard_stolen_c1_2026-11-09');
      expect(entry.refType, 'guard_stolen');
      expect(entry.refId, 'garden');
      expect(entry.dayKey, '2026-11-09');
      expect(entry.net, -3.0);
      expect(ctx.balance, 97.0);
    });

    test('E2 幂等：重复调用第二次返回 0、仍只 1 行、余额不变', () async {
      final _Ctx ctx = _make(balance: 100);
      expect(await ctx.guard.recordBattleTheft(stolenSun: 2), 2);

      expect(await ctx.guard.recordBattleTheft(stolenSun: 2), 0);
      expect(await ctx.guard.recordBattleTheft(stolenSun: 3), 0);

      expect(ctx.ledger.countOf('guard_stolen'), 1);
      expect(ctx.balance, 98.0);
    });

    test('E3 互斥去重（核心探针）：同日已有 guard_stolen 行 → 空操作不双扣', () async {
      final _Ctx ctx = _make(balance: 100);
      // 模拟「当日已有 guard_stolen 行」：expire 半截时序 / 战斗已写过。
      // 直接种一行同 id 账本记录（主键 + 读判定双通道都会命中）。
      await ctx.ledger.append(SunlightEntry(
        id: 'guard_stolen_c1_2026-11-09',
        ts: _now(),
        type: SunlightType.plant,
        gross: -2,
        net: -2,
        balanceAfter: 98,
        refType: 'guard_stolen',
        refId: 'garden',
        dayKey: '2026-11-09',
      ));

      final int charged = await ctx.guard.recordBattleTheft(stolenSun: 3);

      expect(charged, 0, reason: '账本读判定命中 ⇒ 空操作');
      expect(ctx.ledger.countOf('guard_stolen'), 1, reason: '仍是最初那一行');
      expect(ctx.balance, 98.0);
    });

    test('E4 反向互斥：今天战斗偷过 → 明天 expire 的 pending 结算不再扣阳光', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1')],
      );
      await ctx.store.write(
        _childId,
        _pendingState(sunStolen: 2, growthStolen: <String, double>{'p1': 0.02}),
      );
      expect(await ctx.guard.recordBattleTheft(stolenSun: 3), 3);

      // 次日 expire：fighting 分支不触发（存档是 pending）→ 走扣阳光 + 扣成长；
      // 但 _settleSunLoss 的同名读判定命中今日战斗偷窃行 ⇒ 阳光零扣。
      final GuardService guardNextDay = _guardAt(ctx, _nowNextDay);
      final GuardExpireOutcome outcome = await guardNextDay.expire();

      expect(outcome.settled, isTrue);
      expect(outcome.stolenSun, 0, reason: '同 id 互斥：战斗偷过，expire 绝不双扣');
      expect(outcome.growthTargets, 1, reason: '互斥只管阳光；成长照常结算');
      expect(ctx.ledger.countOf('guard_stolen'), 1);
    });

    test('E5 余额钳制：余额 2 被偷 3 → 扣 2，不产生负余额（D6）', () async {
      final _Ctx ctx = _make(balance: 2);

      final int charged = await ctx.guard.recordBattleTheft(stolenSun: 3);

      expect(charged, 2);
      expect(ctx.balance, 0.0);
      expect(ctx.ledger.entries.single.net, -2.0);
    });

    test('E6 脏入参：stolenSun ≤ 0 → 空操作返回 0、零写库', () async {
      final _Ctx ctx = _make(balance: 100);

      expect(await ctx.guard.recordBattleTheft(stolenSun: 0), 0);
      expect(await ctx.guard.recordBattleTheft(stolenSun: -3), 0);

      expect(ctx.ledger.countOf('guard_stolen'), 0);
    });

    test('E7 零成长扣减：recordBattleTheft 后植物成长值逐位不变', () async {
      final _Ctx ctx = _make(
        balance: 100,
        plants: <Plant>[_plant('p1', progress: 0.5), _plant('p2', progress: 0.7)],
      );

      await ctx.guard.recordBattleTheft(stolenSun: 3);

      // 玄参裁定：怪物到门口只偷阳光。两株的成长进度必须逐位不变。
      expect((await ctx.plants.plant('p1'))!.growthProgress, 0.5);
      expect((await ctx.plants.plant('p2'))!.growthProgress, 0.7);
    });

    test('E8 Abandoned 零写库：进战斗后进程被杀（无任何收尾调用）→ 账本零行', () async {
      final _Ctx ctx = _make(balance: 100, plants: <Plant>[_plant('p1')]);
      await ctx.guard.resolve();
      await ctx.guard.markFighting();
      expect(ctx.state.status, GuardDayStatus.fighting);

      // 模拟杀进程：到此为止，没有任何 recordBattleTheft / claim 调用。
      // 战斗态只在内存（模拟器对象被丢弃），落账口根本没被触发。
      expect(ctx.ledger.countOf('guard_stolen'), 0);
      expect(ctx.ledger.countOf('guard_win'), 0);
      expect(ctx.ledger.countOf('guard_pay'), 0);
      expect(ctx.ledger.entries, isEmpty);
    });
  });
}
