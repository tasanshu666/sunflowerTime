/// 守卫战 v2 独立验收 · **W1 经济红线探针**（QA 自造，不依赖工程师测试）。
///
/// 与 `test/guard/` 工程师测试刻意不共享 helper：账本 / 存档 / 植物 / 专注 /
/// 成长全部走**真实生产链路**（内存 drift + mock prefs），夹具见
/// `guard_probe_support.dart`（v1 验收遗留，本批原样复用）。
///
/// ## 覆盖（对应主理人验收单 W1-1~6）
/// | # | 探针 | 判据 |
/// |---|---|---|
/// | 1 | 守恒：任意战局结算后 余额变化 == winSun − 实扣被偷 | 12 个 DB seed 逐分对账；200 个纯 sim seed 抽 win − stolen 分布 |
/// | 2 | 封顶：名义被偷 > 3 ⇒ 账本净额恰 −3.0、恰 1 行 | sim 级构造（公开构造器拼剧本）+ debug 高偷窃战局 + 服务级直灌 7 |
/// | 3 | 互斥：战斗先落账 ⇒ 次日 expire 零扣；expire 先落账 ⇒ recordBattleTheft 空操作 | 两个方向都探（含 markFighting 失败的最坏时序） |
/// | 4 | 幂等：recordBattleTheft ×3 只 1 行；claim 在战斗路径下 guard_win 恰 1 行（付费路径 guard_pay 恰 1 行） | |
/// | 5 | 零成长扣减：战斗路径前后全部 plant.growthProgress 逐位一致 | 3 个成长型贼 seed × 3 株 |
/// | 6 | 卡面==账本：结算卡「偷走 N」N == guard_stolen 行；stolenSun=0 整行不渲染 | widget 级（zh/en） |
library;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart' show dayKey;
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';

import 'guard_probe_support.dart';

/// 「一枪不发」纯 sim 整场重放（500ms 步进推满 30s 窗口），回终局快照。
GuardBattleSnapshot _replayNoFire(String dayKey, String childId) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim =
      GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
  for (int t = 500; t <= script.windowMs; t += 500) {
    sim.step(t, const <int>[]);
  }
  return sim.snapshot();
}

void main() {
  group('W1-1 经济守恒', () {
    test('200 个 seed：winSun − sim被偷 的分布（≤ 0 的 seed 全部点名）', () {
      // winSun 与 sim 被偷都是 (dayKey, childId) 的纯函数，无需 DB。
      int negative = 0;
      final List<String> bad = <String>[];
      for (int i = 0; i < 200; i++) {
        final String childId = 'qa-econ-$i';
        const String dayKey = '2026-11-09';
        final int winSun =
            deriveGuardRoll(dayKey: dayKey, childId: childId).winSun;
        final int stolen = _replayNoFire(dayKey, childId).stolenSun;
        if (winSun - stolen < 0) {
          negative++;
          bad.add('$childId: win=$winSun stolen=$stolen net=${winSun - stolen}');
        }
      }
      // ignore: avoid_print
      print('QA/W1-1 200 seed 抽样：win − stolen < 0 的 seed 数 = $negative');
      for (final String b in bad.take(10)) {
        // ignore: avoid_print
        print('QA/W1-1 反例：$b');
      }
      // 判定不在本行：反例清单进报告，由主理人裁决「口径」还是「bug」。
      expect(bad.length, negative);
    });

    testWidgets('12 个 DB seed 全链路逐分对账：Δ余额 == +winSun − 实扣被偷',
        (WidgetTester tester) async {
      for (int i = 0; i < 12; i++) {
        final GuardProbeEnv env = await GuardProbeEnv.create();
        addTearDown(env.close);
        final DateTime day = DateTime(2026, 11, 9, 10, 30)
            .subtract(Duration(days: i)); // 换日换 seed
        final GuardService guard = env.guardAt(() => day);
        const double seeded = 20;
        await env.seedBalance(seeded, at: day);
        await env.focus.saveSession(FocusSession(
          id: 'f_$i',
          start: day.subtract(const Duration(minutes: 20)),
          end: day,
          plannedMin: 0,
          actualFocusMin: 20,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: day,
        ));
        await env.seedPlant('p_$i', now: day);

        final double before = await env.ledger.balance();
        final GuardResolveResult resolved = await guard.resolve(now: day);
        expect(resolved.cost, GuardCostMode.free, reason: 'seed $i 应走能量路径');
        final int winSun = resolved.winSun;
        await guard.markFighting(now: day);

        // 同一 (dayKey, childId) 的纯 sim 战局：一枪不发，取被偷合计。
        final int stolen =
            _replayNoFire(resolved.dayKey, env.childId).stolenSun;
        final int charged =
            await guard.recordBattleTheft(stolenSun: stolen, now: day);
        expect(charged, stolen, reason: 'seed $i：余额充足 ⇒ 实扣 == sim 被偷');

        final GuardClaimOutcome outcome = await guard.claim(now: day);
        expect(outcome.ok, isTrue, reason: 'seed $i');
        final double after = await env.ledger.balance();

        // 🔴 逐分对账：Δ余额 == +winSun − 实扣被偷（能量路径无 guard_pay）。
        expect(after - before, (winSun - charged).toDouble(),
            reason: 'seed $i：before=$before after=$after win=$winSun '
                'stolen=$charged');
        final double stolenNet =
            await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, dayKey(day));
        expect(stolenNet, -charged.toDouble(), reason: 'seed $i：卡面==账本');
      }
    });
  });

  group('W1-2 封顶 3 ☀', () {
    test('sim 级：公开构造器拼「名义被偷 4 > 封顶 3」的战局 ⇒ sim 内钳到 3', () {
      // m3@0（19.4s 到门，steal 2）+ m2@6s（28s 到门，steal 2）+ m1@12s（37.4s
      // 才到门 ⇒ 撤退）：名义被偷 = 2+2 = 4 > 3。
      const GuardBattleScript script = GuardBattleScript(
        monsters: <GuardBattleMonsterSpec>[
          GuardBattleMonsterSpec(
              index: 0,
              kind: GuardBattleMonsterKind.m3,
              spawnMs: 0,
              speedPtPerSec: 17,
              dodgeProb: 0.35,
              hitsToKill: 3,
              steal: 2,
              laneYPt: 20,
              wobbleAmpPt: 4,
              wobbleFreqHz: 0.3,
              wobblePhaseRad: 0),
          GuardBattleMonsterSpec(
              index: 1,
              kind: GuardBattleMonsterKind.m2,
              spawnMs: 6000,
              speedPtPerSec: 15,
              dodgeProb: 0.25,
              hitsToKill: 2,
              steal: 2,
              laneYPt: 45,
              wobbleAmpPt: 4,
              wobbleFreqHz: 0.3,
              wobblePhaseRad: 0),
          GuardBattleMonsterSpec(
              index: 2,
              kind: GuardBattleMonsterKind.m1,
              spawnMs: 12000,
              speedPtPerSec: 13,
              dodgeProb: 0.15,
              hitsToKill: 1,
              steal: 3,
              laneYPt: 70,
              wobbleAmpPt: 4,
              wobbleFreqHz: 0.3,
              wobblePhaseRad: 0),
        ],
        windowMs: 30000,
      );
      final GuardBattleSim sim =
          GuardBattleSim(script: script, dayKey: '2026-11-09', childId: 'qa-cap');
      for (int t = 500; t <= 30000; t += 500) {
        sim.step(t, const <int>[]);
      }
      final GuardBattleSnapshot snap = sim.snapshot();
      final int nominal = snap.monsters
          .where((GuardBattleMonsterSnapshot m) => m.phaseId == 'fled')
          .fold(0, (int sum, GuardBattleMonsterSnapshot m) => sum + m.stolen);
      // 名义口径：fled 怪的剧本 steal 合计（含被钳成 0 的那只）。
      int nominalSeed = 0;
      for (final GuardBattleMonsterSnapshot m in snap.monsters) {
        if (m.phaseId == 'fled') nominalSeed += script.monsters[m.index].steal;
      }
      expect(nominalSeed, 4, reason: '夹具前提：到门口怪的名义 steal 合计 > 3');
      expect(snap.stolenSun, 3, reason: '🔴 sim 内钳到封顶 3');
      expect(snap.stealCapLeft, 0);
      expect(nominal, 3, reason: '逐怪实偷合计 == 3');
    });

    test('debug 高偷窃战局（5×m1）+ 服务落账：净额恰 −3.0、恰 1 行', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedBalance(20);
      // buildGuardBattleScriptForDebug(highTheft: true)：5 只全 m1、steal 全 3。
      final GuardBattleScript script =
          buildGuardBattleScriptForDebug(monsterCount: 5, highTheft: true);
      final GuardBattleSim sim = GuardBattleSim(
        script: script,
        dayKey: env.today,
        childId: env.childId,
      );
      for (int t = 500; t <= 30000; t += 500) {
        sim.step(t, const <int>[]);
      }
      // 注意：m1 全场 25.4s 行程 ⇒ 30s 窗口内只有 spawn=0 那只能到门口，
      // 名义到门被偷 = 3（不是 15）；sim 被偷合计 = 3 = 封顶。
      final GuardBattleSnapshot snap = sim.snapshot();
      expect(snap.stolenSun, 3);
      final int charged = await env.guard
          .recordBattleTheft(stolenSun: snap.stolenSun, now: env.clock());
      expect(charged, 3);
      final double net =
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today);
      expect(net, -3.0, reason: '🔴 账本被偷净额恰好 −3.0');
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1));
    });

    test('服务级双保险：recordBattleTheft(stolenSun: 7) ⇒ 实落 3、恰 1 行', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedBalance(20);
      expect(await env.guard.recordBattleTheft(stolenSun: 7), 3,
          reason: '名义 7 ⇒ 钳到封顶 3');
      final double net =
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today);
      expect(net, -3.0);
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1));
    });
  });

  group('W1-3 互斥（两个方向）', () {
    test('方向 A：战斗先落 guard_stolen ⇒ 次日 expire 阳光零扣（fighting 补发分支）',
        () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedBalance(20);
      await env.seedPlant('p_a');
      await env.focus.saveSession(FocusSession(
        id: 'f_a',
        start: env.clock().subtract(const Duration(minutes: 20)),
        end: env.clock(),
        plannedMin: 0,
        actualFocusMin: 20,
        status: FocusStatus.completed,
        sunlightEarned: 0,
        createdAt: env.clock(),
      ));
      final GuardService guard = env.guard;
      final GuardResolveResult resolved = await guard.resolve();
      await guard.markFighting();
      expect(await guard.recordBattleTheft(stolenSun: 2), 2);
      final double afterTheft = await env.ledger.balance();

      final DateTime nextDay = env.clock().add(const Duration(days: 1));
      final GuardExpireOutcome expired =
          await env.guardAt(() => nextDay).expire(now: nextDay);
      expect(expired.settled, isTrue);
      expect(expired.stolenSun, 0, reason: '🔴 fighting 分支：阳光零扣');
      expect(expired.grantedWinSun, resolved.winSun, reason: '补发必得阳光');
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1),
          reason: '不产生第二行 guard_stolen');
      expect(
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today),
          -2.0);
      expect(await env.ledger.balance(),
          closeTo(afterTheft + resolved.winSun, 1e-9));
    });

    test('方向 A′（最坏时序）：markFighting 失败存档仍 pending + 战斗已落账 '
        '⇒ 次日 expire 的 pending 分支被同 id 读判定挡住、零双扣', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedBalance(20);
      await env.seedPlant('p_a2');
      // 无能量、余额 ≥ 5 ⇒ 付费 pending 档（sunStolen = roll.sunLoss ≥ 0）。
      final GuardService guard = env.guard;
      final GuardResolveResult resolved = await guard.resolve();
      expect(resolved.cost, GuardCostMode.paid);
      // 模拟「markFighting 写失败但战斗照打且被偷已落账」：不调 markFighting。
      expect(await guard.recordBattleTheft(stolenSun: 3), 3);
      final double afterTheft = await env.ledger.balance();

      final DateTime nextDay = env.clock().add(const Duration(days: 1));
      final GuardExpireOutcome expired =
          await env.guardAt(() => nextDay).expire(now: nextDay);
      expect(expired.stolenSun, 0,
          reason: '🔴 同 id 幂等：当日已有 guard_stolen 行 ⇒ _settleSunLoss 返回 0');
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1));
      expect(
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today),
          -3.0);
      expect(await env.ledger.balance(), closeTo(afterTheft, 1e-9),
          reason: 'expire 不再扣第二笔');
      // 付费成本仍会在次日补扣吗？不会——本战局孩子没点收下，pending 分支只结算
      // 损失；guard_pay 只在 claim 里写。这里断言无 guard_pay 行。
      expect(await env.rowsOf(kGuardPayRefType), isEmpty);
      expect(resolved.sunLoss, greaterThanOrEqualTo(0));
    });

    test('方向 B：expire 先落 guard_stolen ⇒ 当日 recordBattleTheft 空操作',
        () async {
      // 找一个「今天贼会偷阳光（sunLoss ≥ 1）」的日子（有的贼只偷成长）。
      GuardProbeEnv? found;
      GuardResolveResult? resolvedFound;
      for (int i = 0; i < 20 && found == null; i++) {
        final DateTime day = DateTime(2026, 11, 9, 10, 30)
            .subtract(Duration(days: i));
        final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
        await env.seedBalance(20, at: day);
        await env.seedPlant('p_b_$i', now: day);
        final GuardResolveResult r = await env.guard.resolve(now: day);
        if (r.cost == GuardCostMode.paid && r.sunLoss >= 1) {
          found = env;
          resolvedFound = r;
        } else {
          await env.close();
        }
      }
      expect(found, isNotNull, reason: '20 天里应能找到 sunLoss ≥ 1 的付费档日');
      final GuardProbeEnv env = found!;
      addTearDown(env.close);
      final GuardResolveResult resolved = resolvedFound!;
      expect(resolved.sunLoss, greaterThanOrEqualTo(1));
      final GuardService guard = env.guardAt(() => env.clock());
      final DateTime nextDay = env.clock().add(const Duration(days: 1));
      final GuardExpireOutcome expired =
          await env.guardAt(() => nextDay).expire(now: nextDay);
      expect(expired.settled, isTrue);
      expect(expired.stolenSun, resolved.sunLoss,
          reason: '夹具前提：expire 已按 pending 结算被偷');
      final double expireNet =
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today);
      expect(expireNet, lessThanOrEqualTo(-1.0),
          reason: '夹具前提：expire 已落被偷行');

      // 当日（旧时钟）战斗层再调 recordBattleTheft ⇒ 空操作。
      expect(await guard.recordBattleTheft(stolenSun: 3), 0,
          reason: '🔴 同日已有 guard_stolen 行 ⇒ 返回 0');
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1));
      expect(
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, env.today),
          expireNet);
    });
  });

  group('W1-4 幂等', () {
    test('recordBattleTheft 连调 3 次只 1 行；claim 恰 1 行 guard_win；付费路径恰 1 行 guard_pay',
        () async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);
      await env.seedBalance(20);
      await env.seedPlant('p_i');
      final GuardService guard = env.guard;
      // 先 resolve 出当日存档（claim 的前提），再验 recordBattleTheft 幂等。
      await env.focus.saveSession(FocusSession(
        id: 'f_i',
        start: env.clock().subtract(const Duration(minutes: 20)),
        end: env.clock(),
        plannedMin: 0,
        actualFocusMin: 20,
        status: FocusStatus.completed,
        sunlightEarned: 0,
        createdAt: env.clock(),
      ));
      final GuardResolveResult resolved = await guard.resolve();
      expect(resolved.cost, GuardCostMode.free);
      expect(await guard.recordBattleTheft(stolenSun: 2), 2);
      expect(await guard.recordBattleTheft(stolenSun: 2), 0,
          reason: '第 2 次幂等空操作');
      expect(await guard.recordBattleTheft(stolenSun: 1), 0,
          reason: '第 3 次幂等空操作');
      expect(await env.rowsOf(kGuardStolenRefType), hasLength(1));

      await guard.markFighting();
      final GuardClaimOutcome o1 = await guard.claim();
      expect(o1.ok, isTrue);
      final GuardClaimOutcome o2 = await guard.claim();
      expect(o2.alreadyClaimed, isTrue, reason: '第 2 次 claim 幂等回放');
      expect(await env.rowsOf(kGuardWinRefType), hasLength(1),
          reason: '🔴 战斗路径下 claim 仍只 1 行 guard_win');
      expect(await env.rowsOf(kGuardPayRefType), isEmpty,
          reason: '能量路径无 guard_pay');

      // 付费路径：新环境，无能量、余额充足。
      final GuardProbeEnv env2 = await GuardProbeEnv.create();
      addTearDown(env2.close);
      await env2.seedBalance(20);
      await env2.seedPlant('p_i2');
      final GuardService guard2 = env2.guard;
      final GuardResolveResult r2 = await guard2.resolve();
      expect(r2.cost, GuardCostMode.paid);
      await guard2.markFighting();
      final GuardClaimOutcome o3 = await guard2.claim();
      expect(o3.ok, isTrue);
      expect(o3.paidSun, kGuardPayCost);
      expect(await env2.rowsOf(kGuardPayRefType), hasLength(1),
          reason: '🔴 付费路径 guard_pay 恰 1 行');
      expect(await env2.rowsOf(kGuardWinRefType), hasLength(1));
    });
  });

  group('W1-5 零成长扣减', () {
    test('3 个成长型贼 seed：战斗全链路前后所有株 growthProgress 逐位一致',
        () async {
      // 找 3 个「今天会偷成长」的 day（食叶虫 / 贪婪鼬；馋光鼠不偷成长）。
      final List<String> growthDays = <String>[];
      for (int i = 0; i < 60 && growthDays.length < 3; i++) {
        final String gDay =
            dayKey(DateTime(2026, 11, 9).subtract(Duration(days: i)));
        final GuardRoll roll =
            deriveGuardRoll(dayKey: gDay, childId: 'qa-growth');
        if (roll.stealsGrowth) growthDays.add(gDay);
      }
      expect(growthDays.length, 3, reason: '60 天里应能找到 3 个成长型贼日');
      for (int s = 0; s < growthDays.length; s++) {
        final String gDay = growthDays[s];
        final List<int> parts =
            gDay.split('-').map(int.parse).toList(growable: false);
        final DateTime day = DateTime(parts[0], parts[1], parts[2], 10, 30);
        final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
        addTearDown(env.close);
        await env.seedBalance(20, at: day);
        await env.seedPlant('sp_a', now: day, progress: 0.3);
        await env.seedPlant('sp_b', now: day, progress: 0.6, potIndex: 1);
        await env.seedPlant('sp_c',
            now: day, progress: 0.9, potIndex: 2, status: PlantStatus.bloomed);

        final GuardService guard = env.guardAt(() => day);
        final List<double> before = <double>[
          for (final Plant p in await env.plants.plants()) p.growthProgress,
        ]..sort();
        await guard.resolve(now: day);
        await guard.markFighting(now: day);
        await guard.recordBattleTheft(stolenSun: 2, now: day);
        await guard.claim(now: day);

        final List<Plant> afterPlants = await env.plants.plants();
        final List<double> after = <double>[
          for (final Plant p in afterPlants) p.growthProgress,
        ]..sort();
        expect(after.length, before.length, reason: 'day $dayKey');
        for (int i = 0; i < before.length; i++) {
          expect(identical(before[i], after[i]) || before[i] == after[i], isTrue,
              reason: '🔴 day $dayKey 株 #$i 成长被改动：'
                  '${before[i]} → ${after[i]}');
        }
      }
    });
  });

  group('W1-6 卡面==账本（结算卡被偷行）', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required int stolenSun,
      required Locale locale,
    }) async {
      const GuardDayState state = GuardDayState(
        dayKey: '2026-11-09',
        status: GuardDayStatus.fighting,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
      );
      const GuardTodayView view = GuardTodayView(
        mode: GuardPillMode.fighting,
        state: state,
        energyAvailable: 1,
        balance: 20,
      );
      late final AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Builder(builder: (BuildContext context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Center(
                child: GuardResultCard(
                  view: view,
                  l10n: l10n,
                  onCollect: () async => throw UnimplementedError(),
                  stolenSun: stolenSun,
                ),
              ),
            );
          }),
        ),
      );
      await tester.pump();
    }

    testWidgets('zh：stolenSun=2 ⇒ 「被偷菜贼偷走 2 阳光」且为红色行',
        (WidgetTester tester) async {
      await pumpCard(tester, stolenSun: 2, locale: const Locale('zh'));
      expect(find.text('被偷菜贼偷走 2 阳光'), findsOneWidget);
      // 红色行：被偷行图标颜色 = 0xFFB3261E（图标与文案同在一个 Row）。
      final Icon icon = tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(
            of: find.text('被偷菜贼偷走 2 阳光'),
            matching: find.byType(Row),
          ).first,
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, const Color(0xFFB3261E), reason: '被偷行必须是红色');
    });

    testWidgets('zh：stolenSun=0 ⇒ 整行不渲染（「偷走」句式绝不出现）',
        (WidgetTester tester) async {
      await pumpCard(tester, stolenSun: 0, locale: const Locale('zh'));
      expect(find.textContaining('偷走'), findsNothing,
          reason: '🔴 不许出现「偷走 0 阳光」');
    });

    testWidgets('en：stolenSun=3 ⇒ 账本口径文案渲染且不溢出',
        (WidgetTester tester) async {
      await pumpCard(tester, stolenSun: 3, locale: const Locale('en'));
      expect(find.textContaining('3'), findsWidgets,
          reason: 'en 文案同样携带账本实扣额 3');
      expect(tester.takeException(), isNull);
    });
  });
}
