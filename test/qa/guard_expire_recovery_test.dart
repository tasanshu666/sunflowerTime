/// 花园守卫独立验收 · **V2 跨天与强杀恢复**
///
/// 全部探针走生产链路：真实 `GuardStatePrefsStore`（mock prefs）+ 真实 drift
/// 内存账本 + 真实 `PlantGrowthService.raidGrowth`。**不 import `test/guard/`
/// 的任何 helper**，也不读 `lib/` 的常量来反推期望值 —— 期望值全部写字面量。
///
/// 覆盖：
///  · `expire()` 四条互斥分支各一条（`pending` / `fighting` / `claimed` / `short`）；
///  · 三条空操作（同一天 / 时钟回拨 / 无存档）；
///  · 开花株免疫 + 阶段不回退 + `stageStartedAt` 不被改写；
///  · 顺序铁律「先 expire 再 resolve」：正向探针 + 反向探针（证明反了会丢数据）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';

import 'guard_probe_support.dart';

DateTime _today() => DateTime(2026, 11, 9, 10, 30);
DateTime _yesterday() => DateTime(2026, 11, 8, 10, 30);

const String _todayKey = '2026-11-09';
const String _yesterdayKey = '2026-11-08';

/// 构造一条「昨天留下的」存档（绕过确定性派生，直接钉死每个字段）。
GuardDayState _yesterdayState({
  required GuardDayStatus status,
  GuardThiefKind thief = GuardThiefKind.sneakThief,
  int winSun = 2,
  int sunStolen = 0,
  Map<String, double> growthStolen = const <String, double>{},
  int paidSun = 0,
}) {
  return GuardDayState(
    dayKey: _yesterdayKey,
    status: status,
    thiefKind: thief,
    paidSun: paidSun,
    winSun: winSun,
    dropKind: GuardDropKind.none,
    sunStolen: sunStolen,
    growthStolen: growthStolen,
  );
}

/// 只看守卫自己写的行（排除夹具的 `qa_seed` 垫资行）。
Future<List<SunlightEntry>> _guardRows(GuardProbeEnv env) async {
  final List<SunlightEntry> all = await env.ledgerRows();
  return all
      .where((SunlightEntry e) => (e.refType ?? '').startsWith('guard_'))
      .toList();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // V2-0 三条空操作
  // ══════════════════════════════════════════════════════════════════════
  group('V2-0 expire 三条空操作', () {
    test('同一天 ⇒ settled=false、账本 0 行、存档原样', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);

      const GuardDayState todayState = GuardDayState(
        dayKey: _todayKey,
        status: GuardDayStatus.pending,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        sunStolen: 3,
      );
      await env.store.write(env.childId, todayState);

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isFalse);
      expect(out.expiredDayKey, isNull);
      expect(await _guardRows(env), isEmpty);
      expect((await env.store.read(env.childId)).dayKey, _todayKey);
      expect((await env.store.read(env.childId)).sunStolen, 3);
    });

    test('时钟回拨（今天 < 存档日）⇒ 空操作，且**绝不**清档', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);

      // 存档写「明天」，然后把时钟拨回「今天」。
      await env.store.write(
        env.childId,
        const GuardDayState(
          dayKey: '2026-11-10',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          sunStolen: 4,
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isFalse);
      expect(await _guardRows(env), isEmpty);
      final GuardDayState after = await env.store.read(env.childId);
      expect(after.dayKey, '2026-11-10',
          reason: '🔴 回拨一下就把未来存档删了 = 丢一天对账依据');
      expect(after.sunStolen, 4);
    });

    test('从未 resolve（无存档）⇒ 只清不结算，0 行账本', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isFalse);
      expect(await _guardRows(env), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-1 pending：扣阳光 + 扣成长
  // ══════════════════════════════════════════════════════════════════════
  group('V2-1 pending 分支：扣阳光（钳到 0）+ 扣成长', () {
    test('sunStolen=3 ⇒ 扣 3、账本 1 行、dayKey 是**昨天**、存档被清', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 3, winSun: 2),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isTrue);
      expect(out.expiredDayKey, _yesterdayKey);
      expect(out.stolenSun, 3);
      expect(out.grantedWinSun, 0, reason: 'pending 没进战斗 ⇒ 不补发 win');
      expect(out.growthTargets, 0);
      expect(await env.ledger.balance(), 97.0);

      final List<SunlightEntry> rows = await _guardRows(env);
      expect(rows.length, 1, reason: '🔴 只有一行 guard_stolen');
      expect(rows.single.refType, 'guard_stolen');
      expect(rows.single.refId, 'garden');
      expect(rows.single.net, -3.0);
      expect(rows.single.gross, -3.0);
      expect(rows.single.dayKey, _yesterdayKey,
          reason: '🔴 损失归入**发生日**，不是结算日');
      expect(rows.single.balanceAfter, 97.0);

      // 存档已清：再读是今天的空白态。
      final GuardDayState after = await env.store.read(env.childId);
      expect(after.dayKey, _todayKey);
      expect(after.hasThief, isFalse);
    });

    test('余额 2 < sunStolen 5 ⇒ 钳到 2，绝不产生负余额', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(2);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 5, winSun: 1),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.stolenSun, 2, reason: 'wanted=5 但余额只有 2 ⇒ 实扣 2');
      expect(await env.ledger.balance(), 0.0);
      final List<SunlightEntry> rows = await env.rowsOf('guard_stolen');
      expect(rows.length, 1);
      expect(rows.single.net, -2.0);
      expect(rows.single.balanceAfter, 0.0);
    });

    test('余额 0 ⇒ 不写账本行（不产生 0 元行）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 5, winSun: 1),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.stolenSun, 0);
      expect(await _guardRows(env), isEmpty);
    });

    test('成长扣减：progress 0.50 → 0.45；阶段与 stageStartedAt 逐字节不变', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      final Plant before = await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'p1': 0.05},
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.growthTargets, 1);
      final Plant after = (await env.plants.plant('p1'))!;
      expect(after.growthProgress, closeTo(0.45, 1e-9));
      expect(after.stage, before.stage, reason: '🔴 阶段绝不回退');
      expect(after.stageStartedAt, before.stageStartedAt,
          reason: '🔴 动了 stageStartedAt 会导致回血/跳变');
      expect(after.status, before.status);
    });

    test('开花株免疫：growthStolen 里带上开花株 ⇒ 它 1.0 不变', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      final Plant bloomBefore = await env.seedPlant(
        'b1',
        status: PlantStatus.bloomed,
        progress: 1.0,
      );
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'p1': 0.05, 'b1': 0.05},
        ),
      );

      await env.guard.expire();

      final Plant bloomAfter = (await env.plants.plant('b1'))!;
      expect(bloomAfter.growthProgress, 1.0,
          reason: '🔴 开花株被打到 0.95 会在花期硬设 0.5，孩子看到 −45pp');
      expect(bloomAfter.status, bloomBefore.status);
      expect((await env.plants.plant('p1'))!.growthProgress, closeTo(0.45, 1e-9));
    });

    test('growthTargets 计数 = 实际被扣株数，不含开花株（1 而不是 2）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedPlant('b1', status: PlantStatus.bloomed, progress: 1.0);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          growthStolen: <String, double>{'p1': 0.05, 'b1': 0.05},
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.growthTargets, 1, reason: 'F5：只统计实际被扣到的株数');
      expect((await env.plants.plant('p1'))!.growthProgress, closeTo(0.45, 1e-9));
      expect((await env.plants.plant('b1'))!.growthProgress, 1.0);
      // 实际被扣只有 1 株 ⇒ 对外计数必须与事实相等（仅日志/埋点字段）。
      expect(out.growthTargets, 1);
    });

    test('死株免疫：dead 株 progress 不变', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('d1', status: PlantStatus.dead, progress: 0.8);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'d1': 0.05},
        ),
      );

      await env.guard.expire();

      expect((await env.plants.plant('d1'))!.growthProgress, 0.8);
    });

    test('单株单日封顶 5%：塞 50% 只扣 5pp', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.6);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'p1': 0.50},
        ),
      );

      await env.guard.expire();

      expect((await env.plants.plant('p1'))!.growthProgress, closeTo(0.55, 1e-9),
          reason: '封顶 kGuardGrowthStealPerPlantDailyCap = 5%');
    });

    test('progress 0.02 − 0.05 ⇒ 钳到 0（不为负）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.02);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 0,
          growthStolen: <String, double>{'p1': 0.05},
        ),
      );

      await env.guard.expire();

      expect((await env.plants.plant('p1'))!.growthProgress, 0.0);
    });

    test('plantId 指向已不存在的株 ⇒ 跳过，不抛', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 1,
          growthStolen: <String, double>{'ghost': 0.05},
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.stolenSun, 1);
      expect(out.growthTargets, 0, reason: 'F5：ghost 不存在，实际扣到 0 株');
      expect(await env.ledger.balance(), 99.0);
    });

    test('幂等：连调 2 次 ⇒ 第二次 settled=false、账本仍 1 行', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 3),
      );

      await env.guard.expire();
      final GuardExpireOutcome second = await env.guard.expire();

      expect(second.settled, isFalse);
      expect(second.expiredDayKey, isNull);
      expect(await env.rowsOf('guard_stolen'), hasLength(1));
      expect(await env.ledger.balance(), 97.0);
    });

    test('账本层幂等：同一天已有 guard_stolen 行 ⇒ 不再扣（即使存档还在）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      // 先手动塞一行昨天的 guard_stolen（模拟「结算过但存档没清」的中断）。
      await env.ledger.append(SunlightEntry(
        id: 'guard_stolen_${env.childId}_$_yesterdayKey',
        ts: _yesterday(),
        type: SunlightType.plant,
        gross: -3,
        net: -3,
        balanceAfter: 97,
        refType: 'guard_stolen',
        refId: 'garden',
        dayKey: _yesterdayKey,
      ));
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 3),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isTrue, reason: '存档仍被清掉');
      expect(out.stolenSun, 0, reason: '🔴 账本已有该日扣款 ⇒ 绝不二次扣');
      expect((await env.rowsOf('guard_stolen')).length, 1);
      expect(await env.ledger.balance(), 97.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-2 fighting：不扣损失 + 补发 win（只补一次）
  // ══════════════════════════════════════════════════════════════════════
  group('V2-2 fighting 分支：不结算损失、补发必得阳光', () {
    test('补发 winSun=3、0 行 guard_stolen、成长不动、balance 103', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.fighting,
          winSun: 3,
          sunStolen: 4,
          growthStolen: <String, double>{'p1': 0.05},
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isTrue);
      expect(out.grantedWinSun, 3);
      expect(out.stolenSun, 0, reason: '🔴 进了战斗但没点收下 ⇒ 不扣损失');
      expect(out.growthTargets, 0);
      expect(await env.ledger.balance(), 103.0);
      expect(await env.rowsOf('guard_stolen'), isEmpty);
      expect((await env.plants.plant('p1'))!.growthProgress, 0.5);

      final List<SunlightEntry> wins = await env.rowsOf('guard_win');
      expect(wins, hasLength(1));
      expect(wins.single.net, 3.0);
      expect(wins.single.dayKey, _yesterdayKey);
      expect(wins.single.balanceAfter, 103.0);
    });

    test('补发只补一次：第二次 expire ⇒ grantedWinSun=0，仍 1 行', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.fighting, winSun: 3),
      );

      await env.guard.expire();
      final GuardExpireOutcome second = await env.guard.expire();

      expect(second.settled, isFalse);
      expect(second.grantedWinSun, 0);
      expect(await env.rowsOf('guard_win'), hasLength(1));
      expect(await env.ledger.balance(), 103.0);
    });

    test('winSun=0 的存档 ⇒ 补发 kGuardWinSunNoItem（3）而不是 0', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.fighting, winSun: 0),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.grantedWinSun, 3);
      expect(await env.ledger.balance(), 103.0);
    });

    test('不发 buff：fighting 过期后存档清空，券已过期', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.fighting,
          winSun: 2,
        ).copyWith(
          dropKind: GuardDropKind.waterVoucher,
        ),
      );

      await env.guard.expire();

      expect((await env.store.read(env.childId)).buff, isNull,
          reason: '🔴 昨天的券不能带到今天');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-3 claimed：无损失
  // ══════════════════════════════════════════════════════════════════════
  group('V2-3 claimed 分支：无损失、零账本', () {
    test('已领取的存档过期 ⇒ 0 行、余额不动、成长不动', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.claimed,
          winSun: 2,
          sunStolen: 5,
          growthStolen: <String, double>{'p1': 0.05},
          paidSun: 5,
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isTrue, reason: '存档被清 ⇒ settled 标记为 true');
      expect(out.stolenSun, 0);
      expect(out.grantedWinSun, 0, reason: '🔴 已领取 ⇒ 不重复补发');
      expect(out.growthTargets, 0);
      expect(await _guardRows(env), isEmpty);
      expect(await env.ledger.balance(), 100.0);
      expect((await env.plants.plant('p1'))!.growthProgress, 0.5);
      expect((await env.store.read(env.childId)).hasThief, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-4 short（免罚档）：无损失（fail-safe）
  // ══════════════════════════════════════════════════════════════════════
  group('V2-4 short（免罚档）分支：即使存档写了损失也不扣', () {
    test('sunStolen=5 / growth 5% 也一律不扣（fail-safe 偏向孩子）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.short,
          winSun: 2,
          sunStolen: 5,
          growthStolen: <String, double>{'p1': 0.05},
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isTrue);
      expect(out.stolenSun, 0);
      expect(out.growthTargets, 0);
      expect(out.grantedWinSun, 0);
      expect(await _guardRows(env), isEmpty);
      expect(await env.ledger.balance(), 100.0);
      expect((await env.plants.plant('p1'))!.growthProgress, 0.5);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-5 顺序铁律：先 expire 再 resolve
  // ══════════════════════════════════════════════════════════════════════
  group('V2-5 顺序铁律「先 expire 再 resolve」', () {
    test('正向：expire → resolve ⇒ 昨天的损失保住、今天正常结算', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 3,
          growthStolen: <String, double>{'p1': 0.04},
        ),
      );

      final GuardExpireOutcome expired = await env.guard.expire();
      final GuardResolveResult resolved = await env.guard.resolve();

      expect(expired.settled, isTrue);
      expect(expired.stolenSun, 3);
      expect(await env.rowsOf('guard_stolen'), hasLength(1));
      expect((await env.plants.plant('p1'))!.growthProgress, closeTo(0.46, 1e-9));

      expect(resolved.needsExpire, isFalse);
      expect(resolved.dayKey, _todayKey);
      expect((await env.store.read(env.childId)).dayKey, _todayKey);
      // 今天的状态是**新**的（不是昨天那条的原样回放）。
      expect(resolved.state.sunStolen, isNot(3));
    });

    test('🔴 反向探针：先 resolve ⇒ 被 needsExpire 闸门挡住，存档原样不动', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 3,
          growthStolen: <String, double>{'p1': 0.04},
        ),
      );

      final GuardResolveResult resolved = await env.guard.resolve();

      expect(resolved.needsExpire, isTrue,
          reason: '🔴 resolve 必须拒绝覆盖未结算的昨天');
      expect(resolved.roll, isNull);
      expect(resolved.state.dayKey, _yesterdayKey);
      expect(resolved.state.sunStolen, 3);

      // 存档未被覆盖 ⇒ 随后补调 expire 仍能结出这 3 ☀。
      final GuardDayState stillYesterday = await env.store.read(env.childId);
      expect(stillYesterday.dayKey, _yesterdayKey);
      expect(stillYesterday.growthStolen['p1'], 0.04);

      final GuardExpireOutcome expired = await env.guard.expire();
      expect(expired.stolenSun, 3);
      expect(await env.ledger.balance(), 97.0);
    });

    test('🔴 反向探针（模拟闸门被绕过）：直接写今天的状态覆盖昨天 ⇒ 损失永久丢失', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(
          status: GuardDayStatus.pending,
          sunStolen: 3,
          growthStolen: <String, double>{'p1': 0.04},
        ),
      );

      // 模拟「无闸门的 resolve」：不经 resolve()，直接用今天的状态盖掉存档。
      await env.store.write(
        env.childId,
        const GuardDayState(
          dayKey: _todayKey,
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          sunStolen: 1,
        ),
      );

      final GuardExpireOutcome out = await env.guard.expire();

      expect(out.settled, isFalse, reason: '存档已是今天 ⇒ expire 只当同一天空操作');
      expect(out.stolenSun, 0);
      expect(await env.rowsOf('guard_stolen'), isEmpty,
          reason: '🔴 昨天那 3 ☀ 再也不会被扣 = 永久对账缺口');
      expect(await env.ledger.balance(), 100.0);
      expect((await env.plants.plant('p1'))!.growthProgress, 0.5,
          reason: '🔴 昨天那 4% 成长也永久免了');
    });

    test('昨天是 claimed ⇒ resolve **不需要**先 expire（无待结算损失）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.claimed, sunStolen: 5),
      );

      final GuardResolveResult resolved = await env.guard.resolve();

      expect(resolved.needsExpire, isFalse);
      expect(resolved.dayKey, _todayKey);
      expect((await env.store.read(env.childId)).dayKey, _todayKey,
          reason: 'claimed 无损失 ⇒ 覆盖存档是安全的');
    });

    test('昨天是 short ⇒ resolve 也不需要先 expire', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.short, sunStolen: 5),
      );

      final GuardResolveResult resolved = await env.guard.resolve();

      expect(resolved.needsExpire, isFalse);
      expect(resolved.dayKey, _todayKey);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V2-6 跨天读不到旧存档（store 层兜底）
  // ══════════════════════════════════════════════════════════════════════
  group('V2-6 存档边界', () {
    test('存档 dayKey 是今天但 status=none 且无贼 ⇒ 视为今天已结算，不重掷', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      // 先正常 resolve 一次，拿到真实派生结果。
      final GuardResolveResult first = await env.guard.resolve();
      // 再 resolve 一次，必须原样回放。
      final GuardResolveResult second = await env.guard.resolve();

      expect(second.thief, first.thief);
      expect(second.state.winSun, first.state.winSun);
      expect(second.state.dropKind, first.state.dropKind);
      expect(second.state.sunStolen, first.state.sunStolen);
    });

    test('存档被清后 prefs 键真的不存在（不是写空串占位）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _today);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _yesterdayState(status: GuardDayStatus.pending, sunStolen: 1),
      );

      await env.guard.expire();

      final SharedPreferences sp = env.sp;
      expect(sp.containsKey('guard_day_state_v2_${env.childId}'), isFalse,
          reason: '键名口径：kGuardDayStatePrefPrefix + childId');
    });
  });
}
