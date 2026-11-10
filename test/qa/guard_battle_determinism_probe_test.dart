/// 守卫战 v2 独立验收 · **W2 确定性与强杀恢复探针**。
///
/// 真源：增量设计 §4.1（确定性模型）/ §2.3-a（中途离开 = 撤退重打）/ §8.2。
///
/// | # | 探针 | 判据 |
/// |---|---|---|
/// | 1 | 重放：同 (dayKey, childId) 两次完整战斗（同 fire timeline）⇒ 账本奖励侧逐位相同（winSun / 券 / guard_win 金额）、被偷额逐位相同 | 纯 sim + 双环境真库 |
/// | 2 | 跨日不同：今天 vs 昨天的 seed ⇒ 剧本至少一处不同（200 seed ≥190 不同） | |
/// | 3 | 强杀：2s / 15s / 29s 三处重挂 ⇒ 账本零新增、可重打、重打从头（非续打）；次日 expire 走 fighting 分支 | |
/// | 4 | 切 tab 作废：同 3 的领域语义（sim 不落盘）| 与 3 同组探 |
library;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';

import 'guard_probe_support.dart';

/// 「450ms 步进连射」时间线（自瞄 + 冷却 400ms ⇒ 全部受理）。
List<int> _greedyTimeline() => <int>[
      for (int t = 450; t <= 30000; t += 450) t,
    ];

/// 用 [timeline] 完整重放一场（100ms 分段喂入），回终局快照。
GuardBattleSnapshot _runFull(String dayKey, String childId, List<int> timeline) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim =
      GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
  int fireIdx = 0;
  for (int t = 100; t <= 31000 && !sim.isOver; t += 100) {
    final List<int> chunk = <int>[];
    while (fireIdx < timeline.length && timeline[fireIdx] <= t) {
      chunk.add(timeline[fireIdx++]);
    }
    sim.step(t, chunk);
  }
  return sim.snapshot();
}

void main() {
  group('W2-1 重放：同 seed + 同 fire timeline', () {
    test('纯 sim：两次完整战斗终局快照逐位相同（JSON 逐字符）', () {
      const String dayKey = '2026-11-09';
      for (int i = 0; i < 20; i++) {
        final String childId = 'qa-replay-$i';
        final List<int> timeline = _greedyTimeline();
        final GuardBattleSnapshot a = _runFull(dayKey, childId, timeline);
        final GuardBattleSnapshot b = _runFull(dayKey, childId, timeline);
        expect(a.toJsonString(), b.toJsonString(), reason: 'seed $childId');
      }
    });

    test('真库双环境：同 dayKey + 同 childId ⇒ winSun / 券 / guard_win 金额、被偷额逐位相同',
        () async {
      // 两个环境共用 AccountService 的默认娃（childId 稳定）+ 固定 dayKey
      // ⇒ 两次的 (dayKey, childId) 相同 = 同 seed。
      final List<(int winSun, String drop, int pay, int win, int stolen)> runs =
          <(int, String, int, int, int)>[];
      for (int run = 0; run < 2; run++) {
        final GuardProbeEnv env = await GuardProbeEnv.create();
        addTearDown(env.close);
        final DateTime day = DateTime(2026, 11, 9, 10, 30);
        final GuardService guard = env.guardAt(() => day);
        await env.seedBalance(20, at: day);
        await env.seedPlant('p_det', now: day);
        await env.focus.saveSession(FocusSession(
          id: 'f_det',
          start: day.subtract(const Duration(minutes: 20)),
          end: day,
          plannedMin: 0,
          actualFocusMin: 20,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: day,
        ));
        final GuardResolveResult resolved = await guard.resolve(now: day);
        await guard.markFighting(now: day);
        final int stolen =
            _runFull(resolved.dayKey, env.childId, _greedyTimeline()).stolenSun;
        await guard.recordBattleTheft(stolenSun: stolen, now: day);
        final GuardClaimOutcome outcome = await guard.claim(now: day);
        final double winNet =
            await env.ledger.netByRefTypeOnDay(kGuardWinRefType, dayKey(day));
        runs.add((
          outcome.winSun,
          outcome.drop.name,
          outcome.paidSun,
          winNet.round(),
          stolen,
        ));
      }
      expect(runs[0], runs[1],
          reason: '🔴 重放口径：(winSun, 券, paid, guard_win 净额, 被偷) 逐位相同；'
              '两次 childId=${runs[0]} vs ${runs[1]}');
    });
  });

  group('W2-2 跨日不同', () {
    test('200 个 seed：今天 vs 昨天剧本 ≥190 个不同', () {
      int same = 0;
      for (int i = 0; i < 200; i++) {
        final String childId = 'qa-crossday-$i';
        final GuardBattleScript today =
            deriveGuardBattleScript(dayKey: '2026-11-09', childId: childId);
        final GuardBattleScript yesterday =
            deriveGuardBattleScript(dayKey: '2026-11-08', childId: childId);
        if (today == yesterday) same++;
      }
      // ignore: avoid_print
      print('QA/W2-2 200 seed：今天 == 昨天的剧本数 = $same');
      expect(200 - same, greaterThanOrEqualTo(190),
          reason: '跨日 seed 必须几乎全体不同');
    });
  });

  group('W2-3 强杀（2s / 15s / 29s 三处重挂）+ W2-4 切 tab 作废', () {
    for (final int killAtMs in <int>[2000, 15000, 29000]) {
      test('强杀 @${killAtMs}ms：账本零新增、重打从头（非续打）、次日 expire 走 fighting',
          () async {
        final GuardProbeEnv env = await GuardProbeEnv.create();
        addTearDown(env.close);
        final DateTime day = DateTime(2026, 11, 9, 10, 30);
        final GuardService guard = env.guardAt(() => day);
        await env.seedBalance(20, at: day);
        await env.seedPlant('p_kill', now: day);
        await env.focus.saveSession(FocusSession(
          id: 'f_kill',
          start: day.subtract(const Duration(minutes: 20)),
          end: day,
          plannedMin: 0,
          actualFocusMin: 20,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: day,
        ));
        final GuardResolveResult resolved = await guard.resolve(now: day);
        await guard.markFighting(now: day);

        // 「强杀」= 打到 killAtMs 后 sim 对象连同内存被偷额一起丢弃（零落账）。
        final GuardBattleScript script = deriveGuardBattleScript(
            dayKey: resolved.dayKey, childId: env.childId);
        final GuardBattleSim killed = GuardBattleSim(
            script: script, dayKey: resolved.dayKey, childId: env.childId);
        killed.step(killAtMs, const <int>[]);
        final int killedStolen = killed.stolenSun; // 内存值，随对象一起消失
        expect(await env.rowsOf(kGuardStolenRefType), isEmpty,
            reason: '🔴 强杀瞬间：战斗态零落账（内存被偷 $killedStolen ☀ 一并作废）');
        expect(await env.rowsOf(kGuardWinRefType), isEmpty);
        expect(await env.rowsOf(kGuardPayRefType), isEmpty);

        // 重打：同 seed 新 sim 从 0s 起跑（非续打）——重打战局与「没杀过」
        // 的完整战局在终局逐位一致。
        final GuardBattleSnapshot asIfNeverKilled =
            _runFull(resolved.dayKey, env.childId, const <int>[]);
        final GuardBattleSim retry = GuardBattleSim(
            script: script, dayKey: resolved.dayKey, childId: env.childId);
        expect(retry.elapsedMs, 0, reason: '重打必须从头（elapsed 归零）');
        for (int t = 500; t <= 31000 && !retry.isOver; t += 500) {
          retry.step(t, const <int>[]);
        }
        expect(retry.snapshot().toJsonString(),
            asIfNeverKilled.toJsonString(),
            reason: '🔴 重打 = 从 0s 重跑同一份剧本，而非从强杀点续打');

        // 重打打完后落被偷账（本探针不点收下 ⇒ 存档停在 fighting）。
        await guard.recordBattleTheft(
            stolenSun: retry.snapshot().stolenSun, now: day);
        expect(await env.rowsOf(kGuardStolenRefType), hasLength(1),
            reason: '重打后只落一次被偷行');

        // 次日 expire：fighting 分支（打了没收下的强杀语义）。
        final DateTime nextDay = day.add(const Duration(days: 1));
        final GuardExpireOutcome expired =
            await env.guardAt(() => nextDay).expire(now: nextDay);
        expect(expired.settled, isTrue);
        expect(expired.grantedWinSun, resolved.winSun,
            reason: '🔴 fighting 语义：补发必得阳光');
        expect(expired.stolenSun, 0, reason: '🔴 fighting 语义：不结算损失');
      });
    }

    test('切 tab 作废（领域语义）：中途弃 sim ⇒ 内存被偷作废，重进同剧本重跑',
        () async {
      const String dayKey = '2026-11-09';
      const String childId = 'qa-tab';
      final GuardBattleScript script =
          deriveGuardBattleScript(dayKey: dayKey, childId: childId);
      // 第一段：打到 8s（3 次开火）弃掉。
      final GuardBattleSim abandoned =
          GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
      abandoned.step(8000, const <int>[1000, 2000, 3000]);
      final int abandonedStolen = abandoned.stolenSun;
      // 「重进」：全新 sim（页面重建 ⇒ L4 重新 initState ⇒ sim 从 0 起跑）。
      final GuardBattleSim resumed =
          GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
      expect(resumed.elapsedMs, 0);
      expect(resumed.stolenSun, 0, reason: '内存被偷 $abandonedStolen ☀ 作废');
      // 同「完整 timeline」重放到底 ⇒ 与「没弃过」的战局逐位一致（无持久化残留）。
      final GuardBattleSim clean =
          GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
      for (int t = 500; t <= 31000 && !clean.isOver; t += 500) {
        clean.step(t, const <int>[]);
      }
      for (int t = 500; t <= 31000 && !resumed.isOver; t += 500) {
        resumed.step(t, const <int>[]);
      }
      expect(resumed.snapshot().toJsonString(), clean.snapshot().toJsonString(),
          reason: '🔴 中途弃局不影响最终战局（sim 不落盘语义）');
    });
  });
}
