/// 高级宝箱**发放链路**的验收测试（`GuardService.claim()` / `expire()`）。
///
/// 真源：`docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §5（奖励发放与幂等），
/// 玄参 2026-11-11 第九轮裁定（种子 5% / 碎片 1~2 片）。
///
/// ## 本文件钉死的 7 条红线（每条都能真红）
/// | # | 红线 | 断言口径 |
/// |---|---|---|
/// | 1 | 高级宝箱阳光**翻倍入账** | 基础 4 ⇒ 账本 `guard_win` gross **= 8**、余额 +8 |
/// | 2 | 高级宝箱发**碎片** | 碎片余额 +1（走 `BloomRewardRepository`，不进阳光账本） |
/// | 3 | 高级宝箱发**种子** | `unlockedSpeciesIds()` 多 1 个物种（重复 ⇒ 折碎片） |
/// | 4 | 重复 `claim()` 不重发 | `guard_win` 行仍 1、碎片余额仍 +1、券仍 1 张 |
/// | 5 | `chestExtrasGranted` 护栏 | 已置位 ⇒ 不再发碎片 / 种子 |
/// | 6 | `expire()` 的 fighting 补发**也翻倍** | 高级宝箱 + 基础 4 + 强杀 ⇒ 补发 **8** |
/// | 7 | 上述补发**补齐 extras**，且**幂等** | 碎片/种子同批补；账本已有行（半截态）⇒ 阳光补 0 但 extras **仍补**；清档成功后重跑不再发；**清档前被杀也不再发**（标记先于清档落盘）；残余窗口（标记落盘前被杀）会多发 1 次 —— 写成断言 |
/// | 8 | `bloomRewards` 漏注入**不得**把「没发」记成「已发」 | 阳光照发 + 碎片 0 + `chestExtrasGranted` 仍 false |
/// | 9 | 旧字段 / `dayKey` 脏类型不抛 `TypeError`（本批 chest* 口径的对称收口） | 见 `guard_day_state_test.dart` |
///
/// 🔴 期望值一律写**字面量**（8 / 4 / 1 / 2 / 3 / 5），不引用 `kGuardChest*`
/// 常量反算 —— 否则常量被改错时测试会跟着一起变绿。
///
/// ## 为什么状态用「直接构造」而不是跑 `resolve()`
/// 本文件验证的是**发放**（claim / expire）而不是**派生**（resolve），派生见
/// `guard_chest_math_test.dart`。直接构造 `GuardDayState` 才能精确控制
/// 「高级宝箱 + 碎片 2 片 + 种子精英档」这类组合（等自然派生要等几百天）。
library guard_chest_grant_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

const String _childId = 'c1';
const String _today = '2026-11-09';
const String _yesterday = '2026-11-08';

DateTime _now() => DateTime(2026, 11, 9, 10, 30);
DateTime _nowNextDay() => DateTime(2026, 11, 10, 0, 5);

// ────────────────────────────── 内存 Fake 仓储 ──────────────────────────────
//
// 只实现 `GuardService` 真正会调用的成员，其余一律经 `noSuchMethod` 炸掉 ——
// 「没人调的方法写错」这类隐患因此不会藏在假替身里（真调到就立刻红）。

/// 守卫状态存储（一天一条；`read` 原样返回旧存档，与 prefs 实现同口径）。
class _FakeStore implements GuardStateStore {
  final Map<String, GuardDayState> byChild = <String, GuardDayState>{};
  int writeCount = 0;

  /// 置真 ⇒ [clear] 抛异常（模拟「进程死在清档之前」这种半截态）。
  ///
  /// 为什么要这个开关：`expire()` 结尾的 `clear` 是崩溃窗口的边界之一，
  /// 只有让 `clear` 真的**失败**，才能造出「extras 已发 + 旧档仍在」的持久状态，
  /// 否则用例只能测「正常清档后重跑」那种无害场景。
  bool failClear = false;

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
    if (failClear) {
      // 🔴 先抛再删：模拟「clear 还没生效就被杀」，旧档必须**留在**存储里。
      throw StateError('clear aborted (simulated crash)');
    }
    byChild.remove(childId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeStore.${invocation.memberName}');
}

/// 阳光账本（真实现口径：累计 net；🔴 重复主键抛异常 = DAO 的 `insert`）。
class _MemLedger implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  final Set<String> _ids = <String>{};

  /// 期初余额（测试种子）。
  double initial = 0;

  double get balanceValue =>
      initial + entries.fold<double>(0, (double a, SunlightEntry e) => a + e.net);

  /// 某 refType 的行数（断言用）。
  int countOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  /// 某 refType 的金额合计（断言「卡面 N == 账本行」用）。
  double grossOf(String refType) => entries
      .where((SunlightEntry e) => e.refType == refType)
      .fold<double>(0, (double a, SunlightEntry e) => a + e.gross);

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_MemLedger.${invocation.memberName}');
}

/// 专注仓储（一律无会话 ⇒ 能量 0 ⇒ 走「扣 5 ☀」路径，断言更直接）。
class _FakeFocus implements FocusRepository {
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      const <FocusSession>[];

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeFocus.${invocation.memberName}');
}

/// 植物仓储（一株存活株 ⇒ `expire()` 不会走「全园无株」分支）。
class _MemPlants implements PlantRepository {
  final List<Plant> store = <Plant>[
    Plant(
      id: 'p1',
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: DateTime(2026, 11, 1),
      growthProgress: 0.5,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 11, 1),
    ),
  ];

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(store);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_MemPlants.${invocation.memberName}');
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_MemSettings.${invocation.memberName}');
}

// ───────────────────────────────── 装配 ─────────────────────────────────

class _Ctx {
  _Ctx({
    required this.store,
    required this.ledger,
    required this.bloom,
    required this.guard,
  });

  final _FakeStore store;
  final _MemLedger ledger;
  final BloomRewardRepository bloom;
  final GuardService guard;

  GuardDayState get state => store.byChild[_childId]!;

  double get balance => ledger.balanceValue;
}

_Ctx _make({
  double balance = 100,
  BloomRewardRepository? bloom,
  bool withBloomPort = true,
}) {
  final _FakeStore store = _FakeStore();
  final _MemLedger ledger = _MemLedger()..initial = balance;
  final _FakeFocus focus = _FakeFocus();
  final _MemPlants plants = _MemPlants();
  final InMemoryBloomRewardRepository bloomRepo =
      InMemoryBloomRewardRepository();
  final BloomRewardRepository bloomPort = bloom ?? bloomRepo;
  final PlantGrowthService growth = PlantGrowthService(
    plants: plants,
    focus: focus,
    ledger: ledger,
    settings: _MemSettings(),
    bloomRewards: bloomRepo,
  );
  final GuardService guard = GuardService(
    store: store,
    ledger: ledger,
    focus: focus,
    plants: plants,
    growth: growth,
    childId: () => _childId,
    clock: _now,
    bloomRewards: withBloomPort ? bloomPort : null,
  );
  return _Ctx(store: store, ledger: ledger, bloom: bloomPort, guard: guard);
}

/// 用同一套仓储、**换一个时钟**新建一个服务（模拟「强杀 App 后次日重进」）。
GuardService _guardAt(_Ctx ctx, DateTime Function() clock) => GuardService(
      store: ctx.store,
      ledger: ctx.ledger,
      focus: _FakeFocus(),
      plants: _MemPlants(),
      growth: PlantGrowthService(
        plants: _MemPlants(),
        focus: _FakeFocus(),
        ledger: ctx.ledger,
        settings: _MemSettings(),
        bloomRewards: ctx.bloom,
      ),
      childId: () => _childId,
      clock: clock,
      bloomRewards: ctx.bloom,
    );

/// 一条「今天已 resolve、待处理」的存档（宝箱字段由调用方指定）。
GuardDayState _pending({
  String dayKey = _today,
  GuardDayStatus status = GuardDayStatus.pending,
  int winSun = 4,
  GuardDropKind drop = GuardDropKind.waterVoucher,
  GuardChestTier tier = GuardChestTier.normal,
  GuardDropKind chestBonus = GuardDropKind.none,
  int fragmentQty = 0,
  GuardSeedKind seedKind = GuardSeedKind.none,
  String? seedSpeciesId,
  bool extrasGranted = false,
}) =>
    GuardDayState(
      dayKey: dayKey,
      status: status,
      thiefKind: GuardThiefKind.sunRat,
      winSun: winSun,
      dropKind: drop,
      chestTier: tier,
      chestBonusDropKind: chestBonus,
      chestFragmentQty: fragmentQty,
      chestSeedKind: seedKind,
      chestSeedSpeciesId: seedSpeciesId,
      chestExtrasGranted: extrasGranted,
    );

void main() {
  // ───────────────── ① claim：翻倍 + 碎片 + 种子 ─────────────────
  group('claim 发放高级宝箱附加奖励', () {
    test('🔴 高级宝箱：阳光翻倍入账（4 ⇒ 8）+ 碎片 +1 + 种子写券', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          chestBonus: GuardDropKind.laborVoucher,
          fragmentQty: 1,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_rose',
        ),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      // 无能量 ⇒ 扣 5 ☀；再入账 8 ☀（高级宝箱翻倍）。
      expect(out.paidSun, 5);
      expect(ctx.ledger.grossOf('guard_win'), 8,
          reason: '🔴 账本 gross 必须 = 翻倍值 8（卡面 N 恒 == 账本行）');
      expect(out.winSun, 8, reason: '结算结果也必须是翻倍值');
      expect(ctx.balance, 103, reason: '100 − 5 + 8');
      // 碎片走账户余额（不进阳光账本）。
      expect(await ctx.bloom.premiumFragmentBalance(), 1);
      // 种子 ⇒ 一张免费种植券。
      expect(await ctx.bloom.unlockedSpeciesIds(), contains('species_rose'));
      // 状态：基础值仍存 4（翻倍只在读取侧派生），幂等标记置位。
      expect(ctx.state.winSun, 4, reason: '🔴 winSun 存基础值，翻倍不写回状态');
      expect(ctx.state.chestExtrasGranted, isTrue);
      expect(ctx.state.isClaimed, isTrue);
      // 第二张券由 chest 层决定。
      expect(out.bonusDrop, GuardDropKind.laborVoucher);
      expect(out.bonusBuff, isNotNull);
      expect(out.bonusBuff!.kind, GuardDropKind.laborVoucher);
      expect(ctx.ledger.countOf('guard_win'), 1, reason: '只写 1 行');
    });

    test('🔴 进度：碎片 2 片 ⇒ 余额 +2（玄参覆写「1~2 片随机」）', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(tier: GuardChestTier.premium, fragmentQty: 2),
      );

      await ctx.guard.claim();

      expect(await ctx.bloom.premiumFragmentBalance(), 2);
    });

    test('普通宝箱：阳光不翻倍、无碎片、无种子（改造前口径零变化）', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(_childId, _pending());

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.winSun, 4, reason: '普通宝箱一分不多给');
      expect(ctx.ledger.grossOf('guard_win'), 4);
      expect(ctx.balance, 99, reason: '100 − 5 + 4');
      expect(await ctx.bloom.premiumFragmentBalance(), 0);
      expect(await ctx.bloom.unlockedSpeciesIds(), isEmpty);
    });

    test('重复种子 ⇒ 自动分解为碎片（普通档 +3）', () async {
      final InMemoryBloomRewardRepository bloom =
          InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_rose');
      final _Ctx ctx = _make(bloom: bloom);
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_rose',
        ),
      );

      await ctx.guard.claim();

      expect(await ctx.bloom.premiumFragmentBalance(), 3,
          reason: '普通档重复种子分解 3 片');
      expect(await ctx.bloom.unlockedSpeciesIds(), contains('species_rose'),
          reason: '不重复写券（集合里仍只有 1 个）');
      expect((await ctx.bloom.unlockedSpeciesIds()).length, 1);
    });

    test('重复种子（精英档）⇒ 分解 5 片；碎片同时发放则累加', () async {
      final InMemoryBloomRewardRepository bloom =
          InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_lotus');
      final _Ctx ctx = _make(bloom: bloom);
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.premium,
          seedSpeciesId: 'species_lotus',
        ),
      );

      await ctx.guard.claim();

      expect(await ctx.bloom.premiumFragmentBalance(), 7,
          reason: '碎片 2 片 + 精英重复种子分解 5 片');
    });

    test('🔴 连调 3 次 claim：guard_win 仍 1 行、碎片只 +1 一次', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          fragmentQty: 1,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_tomato',
        ),
      );

      await ctx.guard.claim();
      final GuardClaimOutcome second = await ctx.guard.claim();
      final GuardClaimOutcome third = await ctx.guard.claim();

      expect(second.alreadyClaimed, isTrue);
      expect(third.alreadyClaimed, isTrue);
      expect(ctx.ledger.countOf('guard_win'), 1, reason: '🔴 只记一次钱');
      expect(ctx.ledger.countOf('guard_pay'), 1, reason: '🔴 只扣一次钱');
      expect(await ctx.bloom.premiumFragmentBalance(), 1, reason: '碎片只发一次');
      expect((await ctx.bloom.unlockedSpeciesIds()).length, 1);
      expect(ctx.balance, 103, reason: '100 − 5 + 8（不重复入账）');
      // 回放的金额也要是翻倍值（否则卡面与账本打架）。
      expect(second.winSun, 8);
      expect(third.winSun, 8);
    });

    test('chestExtrasGranted 护栏：已置位 ⇒ 不再发碎片 / 种子', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_blueberry',
          extrasGranted: true,
        ),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      expect(await ctx.bloom.premiumFragmentBalance(), 0,
          reason: '🔴 标记已置位 ⇒ 一片都不再发');
      expect(await ctx.bloom.unlockedSpeciesIds(), isEmpty);
      expect(ctx.ledger.grossOf('guard_win'), 8, reason: '阳光照发（护栏只管 extras）');
    });

    test('未注入 bloomRewards 端口 ⇒ claim 仍成功（只是不发 extras，不崩）', () async {
      final _Ctx ctx = _make(withBloomPort: false);
      await ctx.store.write(
        _childId,
        _pending(
          tier: GuardChestTier.premium,
          fragmentQty: 1,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_rose',
        ),
      );

      final GuardClaimOutcome out = await ctx.guard.claim();

      expect(out.ok, isTrue);
      expect(ctx.ledger.grossOf('guard_win'), 8, reason: '阳光与端口无关');
      expect(await ctx.bloom.premiumFragmentBalance(), 0);
      // 🔴 P2-②：一片都没发 ⇒ 幂等标记**必须**保持 false。
      //    「发不了」≠「已发完」—— 置成 true 会让事后补好 DI 也永不补发。
      expect(ctx.state.chestExtrasGranted, isFalse,
          reason: '端口未注入不得把「没发」记成「已发」');
    });
  });

  // ─────────── ② expire：fighting 补发（最高风险漏点）───────────
  group('expire 的 fighting 补发：阳光翻倍 + extras 补齐', () {
    test('🔴 高级宝箱 + 基础 4 ⇒ 补发 8（不是 4）+ 碎片 / 种子同批补发', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          dayKey: _yesterday,
          status: GuardDayStatus.fighting,
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.premium,
          seedSpeciesId: 'species_lotus',
        ),
      );

      final GuardExpireOutcome out =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(out.settled, isTrue);
      expect(out.expiredDayKey, _yesterday);
      expect(out.grantedWinSun, 8,
          reason: '🔴 漏改 = 高级宝箱用户强杀 App 后次日只补发一半');
      expect(ctx.ledger.grossOf('guard_win'), 8);
      expect(await ctx.bloom.premiumFragmentBalance(), 2,
          reason: '碎片必须跟着阳光一起补');
      expect(await ctx.bloom.unlockedSpeciesIds(), contains('species_lotus'));
    });

    test('普通宝箱 + 基础 4 ⇒ 补发 4（与旧口径逐位一致）', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(dayKey: _yesterday, status: GuardDayStatus.fighting),
      );

      final GuardExpireOutcome out =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(out.grantedWinSun, 4);
      expect(ctx.ledger.grossOf('guard_win'), 4);
      expect(await ctx.bloom.premiumFragmentBalance(), 0);
      expect(await ctx.bloom.unlockedSpeciesIds(), isEmpty);
    });

    // 🔴 P2-① 回归（与独立 QA 的 `QA-1d` 同口径、同场景，写在**自己的**文件里）：
    //    账本行**已存在**（= 上次 expire 写完 `guard_win` 就被杀）时，
    //    `grantedWinSun == 0`（账本层幂等，正确），但 extras **仍必须补发** ——
    //    因为 extras 的幂等闸门是 `chestExtrasGranted`，不是「本次有没有写账本行」。
    //    旧实现把闸门挂在 `grantedWinSun > 0` 上 ⇒ 碎片/种子永久丢失 ⇒ 本用例红。
    test('🔴 P2-①：账本已有当日 guard_win 行 ⇒ 阳光补 0，但 extras **仍补发**', () async {
      final _Ctx ctx = _make();
      // 手工塞一行「上次 expire 已经写过」的 guard_win（进程随后被杀）。
      await ctx.ledger.append(SunlightEntry(
        id: 'guard_win_${_childId}_$_yesterday',
        ts: DateTime(2026, 11, 8, 23, 50),
        type: SunlightType.earn,
        gross: 8,
        net: 8,
        balanceAfter: 108,
        refType: 'guard_win',
        refId: 'garden',
        dayKey: _yesterday,
      ));
      await ctx.store.write(
        _childId,
        _pending(
          dayKey: _yesterday,
          status: GuardDayStatus.fighting,
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_rose',
        ),
      );

      final GuardExpireOutcome out =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(out.grantedWinSun, 0, reason: '账本层幂等：阳光不再补（一条都不能多）');
      expect(ctx.ledger.countOf('guard_win'), 1);
      expect(await ctx.bloom.premiumFragmentBalance(), 2,
          reason: '🔴 碎片/种子是**永久账户收益**，结算卡已经承诺过；'
              '把 extras 闸门挂在「本次写了账本行」上 ⇒ 半截态永久吞奖励');
      expect(await ctx.bloom.unlockedSpeciesIds(), contains('species_rose'),
          reason: '种子同样按 chestExtrasGranted 判幂等，不按账本行');
      // 存档结算完即清 ⇒ 这条正常路径上不存在「同一份旧档被反复结算」。
      // （真正的重跑风险是「清档之前被杀」，由下面两条用例分别钉死。）
      expect(ctx.store.byChild.containsKey(_childId), isFalse,
          reason: 'expire 结束后必须清档');
    });

    // ══════════════════════════════════════════════════════════════════════
    // 重跑幂等（P2-① 收尾）：**分两条用例，各测各的场景**
    //
    // 为什么要拆：原来只有下面第一条，却起名叫「expire 重跑…不会无限重发」——
    // 它实际跑的是「第一次 expire **正常跑完**（clear 已执行）⇒ 第二次读到无旧档」，
    // 根本没进过危险场景。**测错场景的名字比没有测试更糟**（它会把
    // 「每次崩溃都能多发一次」包装成「不会无限重发」）。
    //
    // 现在两条各钉一件事：
    //  · ①正常路径（clear 成功）：不重复发 —— 无害但必要的基线；
    //  · ②崩溃窗口（extras 已发、clear 前被杀）：重进**不再发** —— 新代码保证的
    //    正是这一条（`expire()` 在 clear 之前先落盘 `chestExtrasGranted`）；
    //  · ③残余窗口（extras 已发、**标记落盘前**被杀）：会再发 1 次 ——
    //    把最坏结果写成**断言**，不写成愿望。
    // ══════════════════════════════════════════════════════════════════════
    test('🔴 P2-① 正常路径：**清档成功之后**重跑不再发 extras（本用例不覆盖崩溃窗口）',
        () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          dayKey: _yesterday,
          status: GuardDayStatus.fighting,
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.none,
        ),
      );

      final GuardExpireOutcome first =
          await _guardAt(ctx, _nowNextDay).expire();
      expect(first.grantedWinSun, 8);
      expect(await ctx.bloom.premiumFragmentBalance(), 2);

      // 第一次 expire 已清档 ⇒ 第二次没什么可结算（走「从未 resolve」分支）。
      // ⚠️ 本用例**只**证明「clear 成功后的重跑无害」；「clear 之前被杀」的场景
      //    由下面两条用例分别钉死（一条证明不再发，一条证明残余窗口会多发 1 次）。
      final GuardExpireOutcome second =
          await _guardAt(ctx, _nowNextDay).expire();
      expect(second.settled, isFalse, reason: '清档后没有旧存档可结算');
      expect(await ctx.bloom.premiumFragmentBalance(), 2,
          reason: '🔴 重跑不得再发一遍');
    });

    // 🔴 P2-① 崩溃窗口（**这条才是原来那条用例名想测的场景**）：
    //    `expire()` 发完 extras、但进程死在 `_store.clear()` 之前 ——
    //    旧档还在（`read` 会原样返回它）。若幂等标记没落盘，重进时
    //    `_grantWinIfAbsent` 因账本行已存在返回 0，而无条件调用的
    //    `_grantChestExtras` 会**再发一遍**。
    //    修法：`expire()` 在 clear **之前**先 `write(... chestExtrasGranted: true)`。
    //    本用例用 `failClear` 造出「标记已落盘、清档未完成」的持久状态。
    test('🔴 P2-① 崩溃窗口：发完 extras、清档前被杀 ⇒ 重进**不再**重发（已闭窗）',
        () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          dayKey: _yesterday,
          status: GuardDayStatus.fighting,
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.none,
        ),
      );

      // 模拟「extras 已发 + 标记已落盘 → 进程死在 clear 之前」。
      ctx.store.failClear = true;
      await expectLater(
        _guardAt(ctx, _nowNextDay).expire(),
        throwsA(isA<StateError>()),
        reason: 'clear 抛异常 = 进程死在清档之前（这是本用例要造的半截态）',
      );
      expect(await ctx.bloom.premiumFragmentBalance(), 2,
          reason: '第一次已经发过 2 片');
      // 🔴 这条断言就是「闭窗」的物理证据：旧档还在，但标记已是 true。
      expect(ctx.store.byChild[_childId], isNotNull, reason: '旧档没清掉');
      expect(ctx.store.byChild[_childId]!.chestExtrasGranted, isTrue,
          reason: '🔴 幂等标记**必须**先于清档落盘，否则下面的重进必再发一遍');

      // 用户重开 App（clear 恢复正常）。
      ctx.store.failClear = false;
      final GuardExpireOutcome second =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(second.settled, isTrue, reason: '这次真的结算掉了那条旧档');
      expect(second.grantedWinSun, 0, reason: '阳光有账本层幂等网，不会多发');
      expect(ctx.ledger.countOf('guard_win'), 1, reason: '🔴 账本仍只有 1 行');
      expect(await ctx.bloom.premiumFragmentBalance(), 2,
          reason: '🔴 窗口已闭：标记落盘之后，反复崩溃/反复重进都**不会**再发');
      expect(ctx.store.byChild.containsKey(_childId), isFalse,
          reason: '第二次清档成功');
    });

    // ⚠️ 残余窗口（已知、已接受 —— 写成断言，不写成愿望）：
    //    「extras 已发 → 标记 write 完成」之间那几毫秒。两个独立存储、无事务 ⇒
    //    无法消除。造法：把「旧档 + 标记未置位」原样写回存储 —— 这正是
    //    「标记还没落盘就被杀」留下的**持久状态**（账本行已存在、flag=false、旧档仍在）。
    test('⚠️ 已知接受：崩溃恰好落在「extras 已发 → 标记落盘」之间 ⇒ 会再发 1 次',
        () async {
      final _Ctx ctx = _make();
      final GuardDayState half =
          _pending(
            dayKey: _yesterday,
            status: GuardDayStatus.fighting,
            tier: GuardChestTier.premium,
            fragmentQty: 2,
            seedKind: GuardSeedKind.none,
          );
      await ctx.store.write(_childId, half);

      await _guardAt(ctx, _nowNextDay).expire();
      expect(await ctx.bloom.premiumFragmentBalance(), 2);

      // 回滚到「标记没落盘」的持久状态（模拟那一刻被杀）。
      expect(half.chestExtrasGranted, isFalse);
      await ctx.store.write(_childId, half);

      final GuardExpireOutcome second =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(second.grantedWinSun, 0, reason: '阳光不会多发（账本层幂等）');
      expect(ctx.ledger.countOf('guard_win'), 1, reason: '🔴 钱一条都不能多');
      // 🔴 最坏结果写成断言：碎片**会**再发一遍（2 ⇒ 4）。
      expect(await ctx.bloom.premiumFragmentBalance(), 4,
          reason: '⚠️ 残余窗口：恰在 extras→标记落盘之间被杀 ⇒ 多发 1 次；'
              '方向偏向孩子，量级 ≈ 1e-6/天/次启动；'
              '一旦走到「标记落盘」就永久闭合（见上一条用例）');
    });

    test('pending（没进战斗）⇒ 照旧扣损失，补发额 0、extras 不发', () async {
      final _Ctx ctx = _make();
      await ctx.store.write(
        _childId,
        _pending(
          dayKey: _yesterday,
          tier: GuardChestTier.premium,
          fragmentQty: 2,
          seedKind: GuardSeedKind.common,
          seedSpeciesId: 'species_rose',
          winSun: 4,
        ),
      );

      final GuardExpireOutcome out =
          await _guardAt(ctx, _nowNextDay).expire();

      expect(out.grantedWinSun, 0);
      expect(ctx.ledger.countOf('guard_win'), 0);
      expect(await ctx.bloom.premiumFragmentBalance(), 0);
    });
  });
}
