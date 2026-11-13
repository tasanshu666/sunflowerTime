/// 独立 QA 复核 · 「花园守卫 · 宝箱与结算演出」批次 **领域层** 探针。
///
/// 刻意**不复用** `test/guard/` 的任何 helper，也不把工程师的断言当结论：
///  · 守卫存档走**真实** `GuardStatePrefsStore`（mock prefs，含旧存档 / 脏档原文）；
///  · 阳光账本 / 植物 / 专注走**真实** drift 内存库 + 真实仓储；
///  · 期望值一律写字面量或从**落盘状态**反推（不引实现常量当期望值，否则改错也不红）。
///
/// 覆盖：
///  · QA-1 强杀恢复（`resolve → markFighting → 不 claim → 次日 expire`）；
///  · QA-2 旧存档 / 脏档不抛异常、不白屏；
///  · QA-4 「到账额 == 展示额」（阳光翻倍 / 碎片 / 种子 / 重复分解 / 双券不同种）；
///  · QA-5 `bloomRewards` 漏注入的后果（显式断言：portMissing **不置**幂等标记）。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/guard_chest.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';

import 'guard_probe_support.dart';

// ══════════════════════════════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════════════════════════════

/// 造一个守卫服务（档位 / 时钟 / 发放端口全部显式给，绝不依赖缺省值）。
GuardService _service(
  GuardProbeEnv env, {
  required DateTime Function() now,
  bool isPremium = true,
  BloomRewardRepository? bloomRewards,
  SunlightRepository? ledger,
  String Function()? childId,
}) {
  return GuardService(
    store: env.store,
    ledger: ledger ?? env.ledger,
    focus: env.focus,
    plants: env.plants,
    growth: env.growth,
    childId: childId ?? (() => env.childId),
    clock: now,
    isPremium: () => isPremium,
    bloomRewards: bloomRewards,
  );
}

/// **顺序探针**：把每次 `append` 的 refType 记进共享日志后转给真实仓储。
///
/// 位置参数走**超参数**（`super.database` 只是本地名，按位置转发 —— 不需要
/// 与超类那个私有的 `_db` 同名）；`account` 是命名参数，名字天然对齐。
class _RecordingLedger extends SunlightLocalRepository {
  _RecordingLedger(
    super.database, {
    super.account,
    required this.log,
  });

  final List<String> log;

  @override
  Future<double> append(SunlightEntry entry) {
    log.add('ledger:${entry.refType}');
    return super.append(entry);
  }
}

/// **顺序探针**：碎片余额写入 / 物种解锁时往共享日志里打一个 `extras` 标记。
class _RecordingBloomRewards implements BloomRewardRepository {
  _RecordingBloomRewards(this._inner, this.log);

  final BloomRewardRepository _inner;
  final List<String> log;

  @override
  Future<int> premiumFragmentBalance() => _inner.premiumFragmentBalance();

  @override
  Future<void> setPremiumFragmentBalance(int balance) {
    log.add('extras');
    return _inner.setPremiumFragmentBalance(balance);
  }

  @override
  Future<Set<String>> unlockedSpeciesIds() => _inner.unlockedSpeciesIds();

  @override
  Future<void> unlockSpecies(String speciesId) {
    log.add('extras');
    return _inner.unlockSpecies(speciesId);
  }

  @override
  Future<void> consumeUnlock(String speciesId) =>
      _inner.consumeUnlock(speciesId);

  @override
  Future<void> insertPendingBloomReward(PendingBloomReward reward) =>
      _inner.insertPendingBloomReward(reward);

  @override
  Future<List<PendingBloomReward>> pendingBloomRewardsDue(DateTime now) =>
      _inner.pendingBloomRewardsDue(now);

  @override
  Future<void> markPendingBloomRewardClaimed(String id) =>
      _inner.markPendingBloomRewardClaimed(id);

  @override
  Future<void> deletePendingBloomReward(String id) =>
      _inner.deletePendingBloomReward(id);

  @override
  Future<void> updatePendingRewardContent({
    required String id,
    required int rewardSunlight,
    required int rewardFragments,
    String? rewardSpeciesId,
  }) =>
      _inner.updatePendingRewardContent(
        id: id,
        rewardSunlight: rewardSunlight,
        rewardFragments: rewardFragments,
        rewardSpeciesId: rewardSpeciesId,
      );
}

/// 纯函数定位一个「高级宝箱」的日子（**只用来挑日期**，断言不依赖它）。
///
/// 用 `deriveGuardChest` 找日子是为了避免「跑 2000 次 resolve」把测试拖慢；
/// 但每条用例随后都会用**落盘状态**重新确认 `chestTier`，所以定位失败会红而不是假绿。
String _locateDay({
  required String childId,
  required bool Function(GuardChestRoll roll) want,
  int maxDays = 2000,
}) {
  for (int i = 0; i < maxDays; i++) {
    final String key = dayKey(DateTime(2026, 1, 1).add(Duration(days: i)));
    final GuardChestRoll roll = deriveGuardChest(
      dayKey: key,
      childId: childId,
      isPremium: true,
      drop: GuardDropKind.roll(dayKey: key, childId: childId, isPremium: true),
    );
    if (want(roll)) return key;
  }
  throw StateError('搜遍 $maxDays 天没有满足条件的高级宝箱 —— 派生通道异常');
}

DateTime _at(String day, {int hour = 10}) =>
    DateTime.parse(day).add(Duration(hours: hour));

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // QA-1 🔴 强杀 App 后的补发路径（最高风险）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-1 高级宝箱 + 强杀 ⇒ 次日 expire 补发', () {
    test('QA-1a 补发阳光 = 基础值 × 2（真实 resolve → markFighting → expire）', () async {
      DateTime now = DateTime(2026, 1, 1, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final GuardService guard = _service(env, now: () => now);

      // ── 挑一个「高级宝箱且无任何附加项」的日子（避免 extras 干扰本用例）──
      final String day = _locateDay(
        childId: env.childId,
        want: (GuardChestRoll r) => r.tier.isPremium && !r.hasAnyExtra,
      );

      now = _at(day);
      final GuardResolveResult resolved = await guard.resolve();
      expect(resolved.needsExpire, isFalse);

      final GuardDayState stored = await env.store.read(env.childId);
      expect(stored.chestTier, GuardChestTier.premium,
          reason: '前置条件：这一天必须是高级宝箱（否则本用例什么都没验到）');
      expect(stored.chestExtrasGranted, isFalse);
      final int base = stored.winSun;
      expect(base, inInclusiveRange(3, 5), reason: '落盘的 winSun 是**基础值** 3~5');

      // ── 进战斗（页面开战即落 fighting），然后「强杀」：不 claim ──
      await guard.markFighting();
      expect((await env.store.read(env.childId)).status, GuardDayStatus.fighting);

      now = DateTime.parse(day).add(const Duration(days: 1, hours: 10));
      final double before = await env.ledger.balance();
      final GuardExpireOutcome out = await guard.expire();
      final double after = await env.ledger.balance();

      expect(out.settled, isTrue);
      expect(out.grantedWinSun, base * 2,
          reason: '🔴 高级宝箱的补发必须是基础值 × 2，不是基础值（base=$base）');
      expect(after - before, (base * 2).toDouble());

      final List<SunlightEntry> wins = await env.rowsOf('guard_win');
      expect(wins, hasLength(1));
      expect(wins.single.net, (base * 2).toDouble(),
          reason: '🔴 账本行 == 补发额；少一半就是「结算卡承诺 +${base * 2}、账本只 +$base」');
      expect(wins.single.dayKey, day, reason: '补发归入**发生日**');
      expect(await env.rowsOf('guard_stolen'), isEmpty,
          reason: 'fighting 分支不结算损失');
    });

    test('QA-1b 碎片 / 种子在 expire 里也补发（漏了就是永久吞掉）', () async {
      DateTime now = DateTime(2026, 1, 1, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      final String day = _locateDay(
        childId: env.childId,
        want: (GuardChestRoll r) =>
            r.tier.isPremium && (r.hasFragments || r.hasSeed),
      );

      now = _at(day);
      await guard.resolve();
      final GuardDayState stored = await env.store.read(env.childId);
      expect(stored.chestTier, GuardChestTier.premium);
      expect(stored.chestFragmentQty + (stored.chestSeedKind.hasSeed ? 1 : 0),
          greaterThan(0),
          reason: '前置条件：这一天必须至少有一项附加奖励');

      final int wantFragments = stored.chestFragmentQty;
      final String? wantSpecies =
          stored.chestSeedKind.hasSeed ? stored.chestSeedSpeciesId : null;
      expect(await bloom.premiumFragmentBalance(), 0);
      expect(await bloom.unlockedSpeciesIds(), isEmpty);

      await guard.markFighting();
      now = DateTime.parse(day).add(const Duration(days: 1, hours: 10));
      final GuardExpireOutcome out = await guard.expire();

      expect(out.grantedWinSun, greaterThan(0), reason: '前置：阳光确实补发了');
      expect(await bloom.premiumFragmentBalance(), wantFragments,
          reason: '🔴 expire 必须补发碎片（fragmentQty=$wantFragments）；'
              '漏了 = 孩子永久少 $wantFragments 片且毫无提示');
      if (wantSpecies != null) {
        expect(await bloom.unlockedSpeciesIds(), contains(wantSpecies),
            reason: '🔴 expire 必须补发种子（$wantSpecies）');
      }
    });

    test('QA-1c claim()：extras 发放**先于**写 guard_win 账本（顺序铁律）', () async {
      DateTime now = DateTime(2026, 1, 1, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);

      final List<String> log = <String>[];
      final _RecordingLedger ledger =
          _RecordingLedger(env.database, account: env.account, log: log);
      final _RecordingBloomRewards bloom = _RecordingBloomRewards(
        InMemoryBloomRewardRepository(),
        log,
      );
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom, ledger: ledger);

      // 钉死一条「高级宝箱 + 2 片碎片」的当日状态（不依赖概率命中）。
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          dropKind: GuardDropKind.waterVoucher,
          chestTier: GuardChestTier.premium,
          chestBonusDropKind: GuardDropKind.laborVoucher,
          chestFragmentQty: 2,
          chestSeedKind: GuardSeedKind.none,
        ),
      );

      final GuardClaimOutcome out = await guard.claim();
      expect(out.ok, isTrue);
      expect(out.winSun, 8, reason: '高级宝箱 4 ⇒ 8');

      final int payIdx = log.indexOf('ledger:guard_pay');
      final int extrasIdx = log.indexOf('extras');
      final int winIdx = log.indexOf('ledger:guard_win');
      expect(payIdx, isNonNegative, reason: '本场走了阳光路径（无能量）');
      expect(extrasIdx, isNonNegative, reason: '碎片必须在这条链路上被真的写过');
      expect(winIdx, isNonNegative);
      expect(extrasIdx, lessThan(winIdx),
          reason: '🔴 顺序必须是「⑤′ 发 extras → ⑥ 写 guard_win」。'
              '反了 ⇒ 账本行写成功而碎片发放前崩溃 ⇒ 重进被判「已领取」'
              '⇒ 碎片永久丢失，而结算卡已经承诺「获得碎片」');
      expect(payIdx, lessThan(extrasIdx), reason: '扣费在发奖之前（⑤ → ⑤′）');
    });

    test(
        'QA-1d ✅ 已修：账本已有当日行时 extras **仍会补发**'
        '（expire 的 extras 闸门不再挂在「本次真的写了账本行」上）', () async {
      // 本条原本是「残余窗口」的文档型断言（旧实现里 `expire()` 用
      // `grantedWinSun > 0` 当 extras 的闸门 ⇒ 账本行已存在就整段跳过 extras）。
      // 🔴 修复后：`expire()` **无条件**调用 `_grantChestExtras`（幂等闸门内移到
      // `_grantChestExtras` 自己身上：它本来就查 `chestTier.isPremium` 与
      // `chestExtrasGranted`），并在 `_store.clear()` **之前**把
      // `chestExtrasGranted: true` 落盘 ⇒ 「崩溃重发窗口」从无界收成单次。
      //
      // 因此这里翻的是**期望值本身**：账本已有 `guard_win` 行（阳光不重复发，
      // 这条账本层幂等仍然正确），但碎片/种子必须补发到手。
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      const String yesterday = '2026-11-08';
      await env.store.write(
        env.childId,
        const GuardDayState(
          dayKey: yesterday,
          status: GuardDayStatus.fighting,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestFragmentQty: 2,
          chestExtrasGranted: false,
        ),
      );
      // 模拟「上次 expire 写完 guard_win 行后立刻被杀」：账本行已存在，extras 未发。
      await env.ledger.append(SunlightEntry(
        id: 'guard_win_${env.childId}_$yesterday',
        ts: DateTime(2026, 11, 8, 10),
        type: SunlightType.earn,
        gross: 8,
        net: 8,
        balanceAfter: 108,
        refType: 'guard_win',
        refId: 'garden',
        dayKey: yesterday,
      ));

      final GuardExpireOutcome out = await guard.expire();

      expect(out.grantedWinSun, 0, reason: '账本层幂等：不重复发阳光（正确）');
      expect(await bloom.premiumFragmentBalance(), 2,
          reason: '🔴 已修：expire 的 extras 闸门不再挂在「本次真的写了账本行」上 ⇒ '
              '账本行已存在时碎片（2 片）仍会补发，不会被永久吞掉');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // QA-2 🟠 旧存档不白屏 / 脏档容错
  // ══════════════════════════════════════════════════════════════════════
  group('QA-2 旧存档 / 脏档', () {
    test('没有 chest* 六个键的旧 JSON ⇒ 六个字段兜底，不抛异常', () {
      // 改造前（B13 之前）的真实线名集合，**一个 chest 键都没有**。
      final Map<String, Object?> oldJson = <String, Object?>{
        'dayKey': '2026-11-09',
        'status': 'pending',
        'thiefKind': 'sun_rat',
        'energyUsed': 1,
        'paidSun': 0,
        'winSun': 4,
        'dropKind': 'water_voucher',
        'sunStolen': 3,
        'growthStolen': <String, double>{'p1': 0.05},
        'tutorialSeen': true,
        'battleAttempt': 0,
      };

      final GuardDayState s =
          GuardDayState.fromJson(oldJson, fallbackDayKey: '2026-11-09');

      expect(s.chestTier, GuardChestTier.normal, reason: '缺省 = 普通宝箱（= 改造前全部内容）');
      expect(s.chestBonusDropKind, GuardDropKind.none);
      expect(s.chestFragmentQty, 0);
      expect(s.chestSeedKind, GuardSeedKind.none);
      expect(s.chestSeedSpeciesId, isNull);
      expect(s.chestExtrasGranted, isFalse);
      // 旧字段一字不变
      expect(s.winSun, 4);
      expect(s.dropKind, GuardDropKind.waterVoucher);
      expect(s.sunStolen, 3);
      expect(s.growthStolen['p1'], 0.05);
      // 写回再读一遍：不得因为新键把旧档读坏
      final GuardDayState round =
          GuardDayState.fromJson(s.toJson(), fallbackDayKey: '2026-11-09');
      expect(round, s, reason: 'toJson → fromJson 必须逐字段相等');
    });

    test('旧存档经真实 GuardStatePrefsStore 读取 ⇒ 不抛、不白屏、档位 normal', () async {
      // 直接把手写的「升级前」JSON 塞进 prefs，再走**生产**读取路径。
      SharedPreferences.setMockInitialValues(<String, Object>{
        GuardStatePrefsStore.keyOf('child_default'):
            '{"dayKey":"2026-11-09","status":"claimed",'
                '"thiefKind":"sneak_thief","winSun":5,'
                '"dropKind":"labor_voucher","tutorialSeen":true}',
      });
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final GuardStatePrefsStore store =
          GuardStatePrefsStore(sp, clock: () => DateTime(2026, 11, 9, 10, 30));

      final GuardDayState s = await store.read('child_default');
      expect(s.dayKey, '2026-11-09');
      expect(s.status, GuardDayStatus.claimed);
      expect(s.winSun, 5);
      expect(s.chestTier, GuardChestTier.normal);
      expect(s.chestFragmentQty, 0);
      expect(s.chestSeedKind, GuardSeedKind.none);
      expect(s.chestExtrasGranted, isFalse);
    });

    test('彻底写坏的存档（半截 JSON）⇒ 当作没有存档，绝不抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        GuardStatePrefsStore.keyOf('child_broken'): '{"dayKey":"2026-11-',
      });
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final GuardStatePrefsStore store =
          GuardStatePrefsStore(sp, clock: () => DateTime(2026, 11, 9, 10, 30));

      final GuardDayState s = await store.read('child_broken');
      expect(s.dayKey, '2026-11-09', reason: '兜底成「今天」');
      expect(s.hasThief, isFalse);
      expect(s.chestTier, GuardChestTier.normal);
    });

    test('脏档：chest* 六个键类型全错也不抛，逐字段兜底', () {
      final Map<String, Object?> dirty = <String, Object?>{
        'dayKey': '2026-11-09',
        'chestTier': 123, // 数字 ⇒ normal
        'chestBonusDropKind': 9, // 数字 ⇒ none
        'chestFragmentQty': 'abc', // 不可解析 ⇒ 0
        'chestSeedKind': 'bogus', // 未知线名 ⇒ none
        'chestSeedSpeciesId': 42, // 非字符串 ⇒ null
        'chestExtrasGranted': 'yes', // 非 true ⇒ false
      };

      final GuardDayState s =
          GuardDayState.fromJson(dirty, fallbackDayKey: '2026-01-01');

      expect(s.chestTier, GuardChestTier.normal);
      expect(s.chestBonusDropKind, GuardDropKind.none);
      expect(s.chestFragmentQty, 0);
      expect(s.chestSeedKind, GuardSeedKind.none);
      expect(s.chestSeedSpeciesId, isNull);
      expect(s.chestExtrasGranted, isFalse);
      expect(s.dayKey, '2026-11-09');
    });

    test('✅ 已修 P2：`status` 非字符串的脏档不抛异常，回落到 GuardDayStatus.none', () {
      // 本条原本是「存疑 P2」的文档型断言：chest* 四个键换了 `_stringOf`，但同一
      // 函数里**旧的** status / thiefKind / dropKind / bonusDropKind 仍在用
      // `json['x'] as String?` 硬转 ⇒ `{"status": 42}` 会抛 TypeError。
      // 🔴 修复后：`fromJson` 已**全字段容错**（dayKey / status / thiefKind /
      // dropKind / bonusDropKind / chestSeedKind 全走 `_stringOf`）⇒ 非 String
      // 与空串都读成 `null`，再经 `guardDayStatusFromId(null)` 回落到
      // [GuardDayStatus.none]，与文件头「绝不抛异常 —— 一份坏掉的 prefs 不该让
      // 孩子打不开今日页」的公开契约一致。
      late GuardDayState dirty;
      expect(
        () => dirty = GuardDayState.fromJson(
          <String, Object?>{'dayKey': '2026-11-09', 'status': 42},
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
        reason: '🔴 脏档不得抛 TypeError（fromJson 已全字段容错）',
      );
      expect(dirty.status, GuardDayStatus.none,
          reason: '未知 / 非字符串线名一律兜底 none（不是上一档、也不是 pending）');
      expect(dirty.dayKey, '2026-11-09', reason: '同一份 JSON 里的正常字段照常读出来');
    });

    test('脏档边界：负片数收敛 0；字符串数字可解析；档位 none 时物种强制 null', () {
      final GuardDayState neg = GuardDayState.fromJson(
        <String, Object?>{'chestFragmentQty': -3},
        fallbackDayKey: '2026-11-09',
      );
      expect(neg.chestFragmentQty, 0, reason: '覆盖式写余额 ⇒ 负片数会真的扣账户');

      final GuardDayState strNum = GuardDayState.fromJson(
        <String, Object?>{'chestFragmentQty': '2'},
        fallbackDayKey: '2026-11-09',
      );
      expect(strNum.chestFragmentQty, 2);

      final GuardDayState contradiction = GuardDayState.fromJson(
        <String, Object?>{
          'chestSeedKind': 'none',
          'chestSeedSpeciesId': 'species_tomato',
        },
        fallbackDayKey: '2026-11-09',
      );
      expect(contradiction.chestSeedKind, GuardSeedKind.none);
      expect(contradiction.chestSeedSpeciesId, isNull,
          reason: '🔴 不变量：档位 none ⇒ 物种必须为 null（否则发放层会发一颗不存在的种子）');

      final GuardDayState kindNoSpecies = GuardDayState.fromJson(
        <String, Object?>{'chestSeedKind': 'common', 'chestSeedSpeciesId': 42},
        fallbackDayKey: '2026-11-09',
      );
      expect(kindNoSpecies.chestSeedKind, GuardSeedKind.common);
      expect(kindNoSpecies.chestSeedSpeciesId, isNull);
      expect(kindNoSpecies.chestSeedKind.hasSeed, isTrue);
      // 只有档位没物种 ⇒ 不该发（`_grantChestExtras` 读 species != null）
      expect(
        kindNoSpecies.chestSeedKind != GuardSeedKind.none &&
            kindNoSpecies.chestSeedSpeciesId != null,
        isFalse,
      );
    });

    test('GuardChestRoll.fromJson 脏数据同样兜底', () {
      final GuardChestRoll r = GuardChestRoll.fromJson(<String, Object?>{
        'tier': 5,
        'bonusDrop': <String, Object?>{},
        'fragmentQty': 'x',
        'seedKind': 'nope',
        'seedSpeciesId': 'species_tomato',
      });
      expect(r.tier, GuardChestTier.normal);
      expect(r.bonusDrop, GuardDropKind.none);
      expect(r.fragmentQty, 0);
      expect(r.seedKind, GuardSeedKind.none);
      expect(r.seedSpeciesId, isNull);
      expect(r, GuardChestRoll.empty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // QA-4 🔴 到账额 == 展示额
  // ══════════════════════════════════════════════════════════════════════
  group('QA-4 到账额 == 展示额', () {
    test('免费档 2000 天采样：chestTier 命中 premium 的次数 == 0', () {
      int premiumHits = 0;
      for (int i = 0; i < 2000; i++) {
        final String key = dayKey(DateTime(2024, 1, 1).add(Duration(days: i)));
        for (final GuardDropKind drop in GuardDropKind.values) {
          final GuardChestRoll r = deriveGuardChest(
            dayKey: key,
            childId: 'qa-free-${i % 17}',
            isPremium: false,
            drop: drop,
          );
          if (r.tier.isPremium) premiumHits++;
          // 免费档不得出现任何附加项（连误触的通道都不该被读到）
          expect(r.hasAnyExtra, isFalse);
        }
      }
      expect(premiumHits, 0,
          reason: '🔴 付费墙的唯一判据是 isPremium；免费档漏出一次高级宝箱 = 直接送钱');
    });

    test('付费档 2000 天：高级宝箱 ≈30%（±3pp），且高级档内第二张券恒 ≠ 首张', () async {
      int premium = 0;
      int bonus = 0;
      for (int i = 0; i < 2000; i++) {
        final String key = dayKey(DateTime(2026, 1, 1).add(Duration(days: i)));
        final GuardDropKind drop =
            GuardDropKind.roll(dayKey: key, childId: 'qa-paid', isPremium: true);
        final GuardChestRoll r = deriveGuardChest(
          dayKey: key,
          childId: 'qa-paid',
          isPremium: true,
          drop: drop,
        );
        if (!r.tier.isPremium) {
          // 🔴 B13.20：普通宝箱 = 首张券透传入参 drop + 无任何附加项
          //    （firstDrop 是「主券」本身，不算「多给」）。
          expect(r.firstDrop, drop,
              reason: '普通宝箱首张券必须透传 drop（B13.20 firstDrop 语义）');
          expect(r.hasAnyExtra, isFalse,
              reason: '普通宝箱在主券之外一分不多给');
          expect(r.bonusDrop, GuardDropKind.none);
          expect(r.fragmentQty, 0);
          expect(r.seedKind, GuardSeedKind.none);
          continue;
        }
        premium++;
        expect(r.firstDrop.hasVoucher, isTrue,
            reason: '高级宝箱首券被全池重挑，恒为 9 种券之一（none 不在池内）');
        if (r.hasBonusDrop) {
          bonus++;
          expect(r.bonusDrop, isNot(r.firstDrop),
              reason: '🔴 第二张券不得与首张（重挑后 ${r.firstDrop.id}）同种');
        }
      }
      expect(premium / 2000, closeTo(0.30, 0.03),
          reason: '高级宝箱出现率 30%（玄参 2026-11-12 B13.14 裁定，由 20% 上调）');
      expect(bonus / 2000, closeTo(0.06, 0.02),
          reason: '30% × 20% = 6%/天（B13.14：双券 10%→20%）');
    });

    test('高级宝箱：账本 guard_win == 卡面 winSunToGrant == 基础 × 2', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: InMemoryBloomRewardRepository());

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 5,
          dropKind: GuardDropKind.waterVoucher,
          chestTier: GuardChestTier.premium,
        ),
      );
      final GuardClaimOutcome out = await guard.claim();

      final GuardTodayView view = GuardTodayView.fromClaim(out);
      final List<SunlightEntry> wins = await env.rowsOf('guard_win');

      expect(out.winSun, 10);
      expect(view.winSunToGrant, 10, reason: '卡面读 winSunToGrant');
      expect(view.winSun, 5, reason: 'view.winSun 仍是基础值（别混用）');
      expect(wins.single.net, 10.0,
          reason: '🔴 账本 == 卡面：卡写 +10 账本必须 +10');
    });

    test('普通宝箱不得翻倍（5 ⇒ 5，不是 10）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final GuardService guard = _service(env, now: () => now, isPremium: false);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 5,
          dropKind: GuardDropKind.waterVoucher,
          chestTier: GuardChestTier.normal,
        ),
      );
      final GuardClaimOutcome out = await guard.claim();
      expect(out.winSun, 5, reason: '普通宝箱恒等于改造前口径');
      expect((await env.rowsOf('guard_win')).single.net, 5.0);
      expect(GuardTodayView.fromClaim(out).winSunToGrant, 5);
    });

    test('碎片：卡面片数 == prefs 余额增量（+2 ⇒ 2）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          dropKind: GuardDropKind.waterVoucher,
          chestTier: GuardChestTier.premium,
          chestFragmentQty: 2,
        ),
      );
      final GuardClaimOutcome out = await guard.claim();
      final GuardTodayView view = GuardTodayView.fromClaim(out);

      expect(view.chestFragmentQty, 2, reason: '卡面 +2');
      expect(await bloom.premiumFragmentBalance(), 2,
          reason: '🔴 prefs 余额增量必须等于卡面片数');
      expect(out.state.chestExtrasGranted, isTrue, reason: '幂等标记必须置位');
    });

    test('碎片：既有余额上只做正向加（3 → 3+1 = 4，不是覆盖成 1）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.setPremiumFragmentBalance(3);
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestFragmentQty: 1,
        ),
      );
      await guard.claim();
      expect(await bloom.premiumFragmentBalance(), 4,
          reason: '🔴 setPremiumFragmentBalance 是覆盖式 upsert ⇒ 必须先读再写');
    });

    test('种子：卡面 ×1 的物种 == unlockedSpeciesIds 的实际增量（全新物种）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestSeedKind: GuardSeedKind.common,
          chestSeedSpeciesId: 'species_rose',
        ),
      );
      final GuardClaimOutcome out = await guard.claim();
      final GuardTodayView view = GuardTodayView.fromClaim(out);

      expect(view.chestSeedSpeciesId, 'species_rose');
      expect(view.chestSeedKind, GuardSeedKind.common);
      expect(await bloom.unlockedSpeciesIds(), <String>{'species_rose'});
      expect(await bloom.premiumFragmentBalance(), 0,
          reason: '全新物种不该分解');
    });

    test('重复种子自动分解（普通档）⇒ 3 片，且不重复写券', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_tomato');
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestSeedKind: GuardSeedKind.common,
          chestSeedSpeciesId: 'species_tomato',
        ),
      );
      await guard.claim();

      expect(await bloom.premiumFragmentBalance(), 3,
          reason: '🔴 普通档重复种子 ⇒ 3 片碎片（kDuplicateSeedDecomposeFragmentsCommon）');
      expect((await bloom.unlockedSpeciesIds()).length, 1,
          reason: '已持券的物种不该被重复解锁/重复计数');
    });

    test('重复种子自动分解（精英档）⇒ 5 片', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_lotus');
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestSeedKind: GuardSeedKind.premium,
          chestSeedSpeciesId: 'species_lotus',
        ),
      );
      await guard.claim();

      expect(await bloom.premiumFragmentBalance(), 5,
          reason: '🔴 精英档重复种子 ⇒ 5 片碎片');
    });

    test('碎片 + 重复种子同时命中：片数相加（2 + 3 = 5）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_blueberry');
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: bloom);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestFragmentQty: 2,
          chestSeedKind: GuardSeedKind.common,
          chestSeedSpeciesId: 'species_blueberry',
        ),
      );
      await guard.claim();
      expect(await bloom.premiumFragmentBalance(), 5,
          reason: '2 片掉落 + 3 片分解');
    });

    test('第二张券：卡面读合并口径（chest 优先），且 claim 透传一致', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      final GuardService guard =
          _service(env, now: () => now, bloomRewards: InMemoryBloomRewardRepository());

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          dropKind: GuardDropKind.waterVoucher,
          // 旧字段与宝箱字段同时非空 ⇒ 必须读宝箱那个（chest 优先）
          bonusDropKind: GuardDropKind.fertilizeVoucher,
          chestTier: GuardChestTier.premium,
          chestBonusDropKind: GuardDropKind.freeWater,
        ),
      );
      final GuardClaimOutcome out = await guard.claim();
      final GuardTodayView view = GuardTodayView.fromClaim(out);

      expect(view.bonusDropKind, GuardDropKind.freeWater,
          reason: '🔴 合并口径：chestBonusDropKind 优先（与 claim 逐字同源）');
      expect(out.bonusDrop, GuardDropKind.freeWater);
      expect(out.bonusBuff?.kind, GuardDropKind.freeWater);
      expect(view.dropKind, GuardDropKind.waterVoucher);
      expect(view.bonusDropKind, isNot(view.dropKind),
          reason: '两张卡不得同种（同种 = 结算卡画两张一样的）');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // QA-5 🔴 bloomRewards 漏注入
  // ══════════════════════════════════════════════════════════════════════
  group('QA-5 bloomRewards 端口', () {
    test('生产 DI（guardServiceProvider）确实注入了端口', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(guardServiceProvider).hasBloomRewardPort, isTrue,
          reason: '🔴 漏注入 ⇒ 高级宝箱的碎片/种子静默丢失（可选参数不会报错）');
    });

    test(
        '✅ 已修：未注入端口 ⇒ 碎片静默不发、无异常，且 chestExtrasGranted **不置位**'
        '（portMissing 不写幂等标记 ⇒ 事后补好 DI 仍有补发机会）', () async {
      DateTime now = DateTime(2026, 11, 9, 10, 30);
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => now);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      // 刻意**不**传 bloomRewards（= 漏接线的后果）
      final GuardService guard = _service(env, now: () => now);

      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(now),
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 4,
          chestTier: GuardChestTier.premium,
          chestFragmentQty: 2,
          chestSeedKind: GuardSeedKind.common,
          chestSeedSpeciesId: 'species_rose',
        ),
      );

      final GuardClaimOutcome out = await guard.claim();

      expect(out.ok, isTrue, reason: '漏注入不得让 claim 抛异常 / 失败');
      // 🔴 修复点：`_grantChestExtras` 返回三态（settled / portMissing / failed），
      // `claim()` **只在 settled 时**置 `chestExtrasGranted`。端口未注入 ⇒
      // portMissing ⇒ 「发不了」≠「已发完」，绝不写幂等标记 ——
      // 否则事后补好 DI 也永不补发（静默吞掉孩子的高级宝箱奖励）。
      expect(out.state.chestExtrasGranted, isFalse,
          reason: '🔴 portMissing 不置幂等标记：碎片一片都没发出去，'
              '就不能在存档里记成「已发完」（否则补好 DI 后永久吞掉）');
      expect(out.winSun, 8, reason: '阳光仍按翻倍发（不依赖 bloom 端口）');
      expect((await env.rowsOf('guard_win')).single.net, 8.0);
    });
  });
}

