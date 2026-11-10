/// 守卫战 v2 · **D1 死亡逃跑演出护栏**（B9；玄参 2026-11-10 第四轮）。
///
/// ## 玄参原话
/// 「打死的怪**没有消失**」—— 现状是 `phase == dead` 后原地冻结不动。
///
/// ## 本批口径（纯渲染层，sim 零字段）
/// `GuardBattleField` 收到 `GuardBattleEventType.kill` 时记下该怪 `deathT`，
/// 随后 `kGuardDeathFleeMs`(800ms) 内继续渲染：
/// * **水平翻转**（`Transform.flip(flipX: true)`）⇒ 转身朝右逃跑；
/// * x 以 `kGuardDeathFleePt(60) / kGuardDeathFleeRunMs(700)` **线性向右**平移；
/// * `opacity` 从 `kGuardDeathFadeStartMs(200)` 起 `1 → 0`；
/// * 800ms 到点 ⇒ **从树上摘掉**。
/// 🔴 sim 里 `dead` 相位与冻结坐标一个字节没动；同一 `deathT` 推同一段轨迹
/// ⇒ 同 seed 两遍逐位一致（本文件 ④ 就是这条）。
///
/// ## 为什么夹具是「2 只怪」
/// 战局**全灭即终局**，终局时 `GuardBattleField` 会 `_ticker.stop()` 冻结画面
/// （横幅 / 倒计时都不许再动）。若只放 1 只怪，打死它的瞬间战局就结束 ⇒
/// 逃跑动画被冻在第 0 帧，测不到轨迹。故用第 2 只（永不被击杀的）怪把战局
/// 撑住 —— 这也正是玄参实机看到 D1 的场景（逐只打）。
///
/// 🔴 全文件有界 `pump`（ticker + 帧序列常驻，绝不 `pumpAndSettle`）。
library guard_battle_death_fx_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
// ═══════════════════════════════════════════════════════════════════════

/// 2 只 m1：0 号一枪即死（hits 1、不闪避）、1 号永远活着（撑住战局）。
///
/// 速度 4pt/s ⇒ 330pt 行程要 82s ≫ 30s 窗口 ⇒ 两只都不会走到门口，
/// 战局不会因「被偷光」提前结束。
GuardBattleScript _script() {
  GuardBattleMonsterSpec spec(int index, int spawnMs, int hits) {
    return GuardBattleMonsterSpec(
      index: index,
      kind: GuardBattleMonsterKind.m1,
      spawnMs: spawnMs,
      speedPtPerSec: 4,
      dodgeProb: 0,
      hitsToKill: hits,
      steal: 1,
      laneYPt: (kGuardBattleLaneTopPt + kGuardBattleLaneBottomPt) / 2,
      wobbleAmpPt: 0,
      wobbleFreqHz: 0,
      wobblePhaseRad: 0,
    );
  }

  return GuardBattleScript(
    windowMs: kGuardBattleWindowMs,
    monsters: <GuardBattleMonsterSpec>[
      spec(0, 0, 1),
      spec(1, 6000, 99),
    ],
  );
}

/// 一次 D1 观测的原始数据（同一 seed 两遍必须逐位相等）。
class _DeathTrace {
  _DeathTrace({
    required this.xAtDeath,
    required this.opacityAtDeath,
    required this.xs,
    required this.opacities,
    required this.removedAfterWindow,
    required this.deathAgeAtRemoval,
  });

  /// 死亡当帧的屏幕 x（怪左上角）。
  final double xAtDeath;

  /// 死亡当帧的 opacity（应为 1.0：前 200ms 不淡出）。
  final double opacityAtDeath;

  /// 800ms 窗口内逐 60ms 采样的屏幕 x（单调不减 = 一直往右逃）。
  final List<double> xs;

  /// 同上的 opacity（单调不增 = 只淡不亮）。
  final List<double> opacities;

  /// 800ms 后节点是否已从树上摘掉。
  final bool removedAfterWindow;

  /// 摘除时刻的「死亡后经过毫秒」。
  final int deathAgeAtRemoval;
}

Future<_DeathTrace> _runDeathTrace(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final GuardBattleHandle handle = GuardBattleHandle();
  final List<GuardBattleSnapshot> snaps = <GuardBattleSnapshot>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            height: 108,
            child: GuardBattleField(
              dayKey: '2026-11-10',
              childId: 'fx-0',
              handle: handle,
              // 🔴 调试剧本覆盖：只改阵容，战局判定 / 经济域一律走真实引擎。
              debugScriptOverride: _script(),
              onSnapshot: (GuardBattleSnapshot s) => snaps.add(s),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));

  // ── 开火：t=1000 一枪（首发恒过 300ms 冷却闸门），之后按 320ms 补射
  //    直到 0 号怪出现 dead 相位（子弹要飞一段，1~2 枪足够）。
  await tester.pump(const Duration(milliseconds: 984)); // 对齐到 t≈1000
  handle.fire();
  bool dead = false;
  for (int i = 0; i < 40 && !dead; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(GuardBattleField.deathFadeKey(0)).evaluate().isNotEmpty) {
      dead = true;
    }
    if (i % 7 == 6 && !dead) handle.fire();
  }
  expect(dead, isTrue,
      reason: '🔴 一枪致命的剧本必须在 2s 内出现「死亡淡出层」（D1 演出入口）');

  final double xAtDeath =
      tester.getTopLeft(find.byKey(GuardBattleField.monsterKey(0))).dx;
  final double opacityAtDeath =
      tester.widget<Opacity>(find.byKey(GuardBattleField.deathFadeKey(0)))
          .opacity;

  // ── 800ms 窗口：逐 60ms 采样（x 与 opacity）。
  final List<double> xs = <double>[];
  final List<double> ops = <double>[];
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    final Finder fade = find.byKey(GuardBattleField.deathFadeKey(0));
    if (fade.evaluate().isEmpty) break;
    xs.add(tester.getTopLeft(find.byKey(GuardBattleField.monsterKey(0))).dx);
    ops.add(tester.widget<Opacity>(fade).opacity);
  }

  // ── 越过 800ms：节点必须已摘除。
  bool removed = find.byKey(GuardBattleField.deathFadeKey(0)).evaluate().isEmpty;
  int age = 0;
  while (!removed && age < 2000) {
    await tester.pump(const Duration(milliseconds: 40));
    age += 40;
    removed =
        find.byKey(GuardBattleField.deathFadeKey(0)).evaluate().isEmpty;
  }

  return _DeathTrace(
    xAtDeath: xAtDeath,
    opacityAtDeath: opacityAtDeath,
    xs: xs,
    opacities: ops,
    removedAfterWindow: removed,
    deathAgeAtRemoval: age,
  );
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  // ── ① 死亡后仍可取到 + 前 200ms 不淡出 ────────────────────────────────
  testWidgets('① 收到 kill ⇒ 该怪在 800ms 窗口内仍渲染，且起始 opacity == 1',
      (WidgetTester tester) async {
    final _DeathTrace tr = await _runDeathTrace(tester);

    expect(tr.opacityAtDeath, 1.0,
        reason: '🔴 死亡后 200ms 内保持不透明（让孩子看清「转身」）');
    expect(tr.xs, isNotEmpty,
        reason: '🔴 死亡后仍在树上（玄参：现在打死了原地不动 = 看起来没死）');
    expect(tr.xs.first, greaterThanOrEqualTo(tr.xAtDeath),
        reason: '🔴 只许往右逃（水平翻转后的逃跑方向）');
  });

  // ── ② x 单调不减（往右逃 60pt / 700ms 线性）──────────────────────────
  testWidgets('② x 单调不减，且窗口内位移落在 0 → kGuardDeathFleePt 之间',
      (WidgetTester tester) async {
    final _DeathTrace tr = await _runDeathTrace(tester);

    for (int i = 1; i < tr.xs.length; i++) {
      expect(tr.xs[i], greaterThanOrEqualTo(tr.xs[i - 1] - 0.01),
          reason: '🔴 x 必须单调不减（往右逃）：${tr.xs}');
    }
    final double travel = tr.xs.last - tr.xAtDeath;
    expect(travel, greaterThan(0),
        reason: '🔴 必须真的在逃（位移 > 0）');
    expect(travel, lessThanOrEqualTo(kGuardDeathFleePt + 0.01),
        reason: '🔴 位移上限 = kGuardDeathFleePt($kGuardDeathFleePt) / '
            'kGuardDeathFleeRunMs 线性（实测量 $travel）');
  });

  // ── ③ opacity 单调不增 + 800ms 后摘除 ─────────────────────────────────
  testWidgets('③ opacity 单调不增（200ms 起淡出）；800ms 后从树上摘掉',
      (WidgetTester tester) async {
    final _DeathTrace tr = await _runDeathTrace(tester);

    for (int i = 1; i < tr.opacities.length; i++) {
      expect(tr.opacities[i], lessThanOrEqualTo(tr.opacities[i - 1] + 1e-9),
          reason: '🔴 opacity 单调不增（只淡不亮）：${tr.opacities}');
    }
    expect(tr.opacities.last, lessThan(tr.opacityAtDeath),
        reason: '🔴 窗口里必须真的在淡出（否则玄参还是「没消失」）');
    expect(tr.removedAfterWindow, isTrue,
        reason: '🔴 kGuardDeathFleeMs(800ms) 到点必须摘掉（实测用到 '
            '${tr.deathAgeAtRemoval}ms 才消失）');
    expect(tr.deathAgeAtRemoval, lessThan(800),
        reason: '🔴 摘除必须发生在 800ms 之后的第一个采样点（不该拖到 1s 外）');
  });

  // ── ④ 同 seed 两遍逐位一致（确定性零破口）─────────────────────────────
  testWidgets('④ 同一剧本跑两遍：死亡时刻的 x / 逐帧 x / 逐帧 opacity 逐位相等',
      (WidgetTester tester) async {
    final _DeathTrace a = await _runDeathTrace(tester);
    // 卸载再挂：State 重建（ticker 归零，锚点回到 0），避免复用上一局的时间轴。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 16));
    final _DeathTrace b = await _runDeathTrace(tester);

    expect(b.xAtDeath, a.xAtDeath,
        reason: '🔴 同一 deathT ⇒ 同一段演出（x 起点逐位相等）');
    expect(b.opacityAtDeath, a.opacityAtDeath);
    expect(b.xs, a.xs, reason: '🔴 逐帧 x 必须逐位相等（确定性零破口）');
    expect(b.opacities, a.opacities, reason: '🔴 逐帧 opacity 必须逐位相等');
    expect(b.removedAfterWindow, a.removedAfterWindow);
    expect(b.deathAgeAtRemoval, a.deathAgeAtRemoval);
  });

  // ── ⑤ 常量口径（改参必须有意识地改这里）───────────────────────────────
  test('⑤ 演出常量：800ms 总时长 / 60pt ÷ 700ms / 200ms 起淡出', () {
    expect(kGuardDeathFleeMs, 800);
    expect(kGuardDeathFleeRunMs, 700);
    expect(kGuardDeathFleePt, 60);
    expect(kGuardDeathFadeStartMs, 200);
    // 位移在 700ms 内跑完、淡出在 800ms 归零（末 100ms 原地淡出）。
    expect(kGuardDeathFleeRunMs, lessThan(kGuardDeathFleeMs));
    expect(kGuardDeathFadeStartMs, lessThan(kGuardDeathFleeMs));
  });

  // ── ⑥ 未死亡 / 已摘除的怪不渲染淡出层 ─────────────────────────────────
  testWidgets('⑥ 存活怪没有淡出层（只有被击杀的怪才有 D1 演出）',
      (WidgetTester tester) async {
    await _runDeathTrace(tester);
    // 1 号怪 6s 才出场：再推 6s 让它上屏（同一段战局，未被击杀）。
    await tester.pump(const Duration(milliseconds: 6000));
    expect(find.byKey(GuardBattleField.monsterKey(1)), findsOneWidget,
        reason: '🔴 存活的怪照旧渲染（战局没结束）');
    expect(find.byKey(GuardBattleField.deathFadeKey(1)), findsNothing,
        reason: '🔴 未死亡的怪不许有淡出层');
    expect(find.byKey(GuardBattleField.deathFadeKey(0)), findsNothing,
        reason: '🔴 0 号怪的演出已收场（800ms 后摘除）');
  });

  // ── ⑦ B10/D1：终局延迟到逃跑演出播完 ──────────────────────────────────
  //
  // 玄参第五轮：「打死的怪要逃跑，但结算卡在动画播完前就弹出来了」。
  // 旧实现在 `sim.isOver` 那一帧 `_ticker.stop()`，而演出按快照时刻推 ⇒
  // 打死的怪会冻在第 0 帧（本文件的 3 只怪夹具掩盖了这个边界，因为第 2 只
  // 怪把战局撑住了）。⑦ 用「**1 只怪**」把边界摆到台面上。
  group('⑦ B10/D1 终局延迟 800ms（1 只怪 = 打死即终局）', () {
    /// 1 只 m1：一枪即死 ⇒ 击杀帧 == 终局帧（最坏边界）。
    GuardBattleScript oneShot() {
      return const GuardBattleScript(
        windowMs: kGuardBattleWindowMs,
        monsters: <GuardBattleMonsterSpec>[
          GuardBattleMonsterSpec(
            index: 0,
            kind: GuardBattleMonsterKind.m1,
            spawnMs: 0,
            speedPtPerSec: 4,
            dodgeProb: 0,
            hitsToKill: 1,
            steal: 1,
            laneYPt: (kGuardBattleLaneTopPt + kGuardBattleLaneBottomPt) / 2,
            wobbleAmpPt: 0,
            wobbleFreqHz: 0,
            wobblePhaseRad: 0,
          ),
        ],
      );
    }

    /// 1 只永不死的怪 + 短窗口 ⇒ 到点撤退（**没有**死亡演出）。
    GuardBattleScript timeoutOnly() {
      return const GuardBattleScript(
        windowMs: 600,
        monsters: <GuardBattleMonsterSpec>[
          GuardBattleMonsterSpec(
            index: 0,
            kind: GuardBattleMonsterKind.m1,
            spawnMs: 0,
            speedPtPerSec: 4,
            dodgeProb: 0,
            hitsToKill: 99,
            steal: 1,
            laneYPt: (kGuardBattleLaneTopPt + kGuardBattleLaneBottomPt) / 2,
            wobbleAmpPt: 0,
            wobbleFreqHz: 0,
            wobblePhaseRad: 0,
          ),
        ],
      );
    }

    Future<void> pumpField(
      WidgetTester tester, {
      required GuardBattleScript script,
      required GuardBattleHandle handle,
      required List<int> finishedAt,
      required int Function() nowMs,
    }) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 108,
                child: GuardBattleField(
                  dayKey: '2026-11-10',
                  childId: 'end-0',
                  handle: handle,
                  debugScriptOverride: script,
                  onFinished: (int _) => finishedAt.add(nowMs()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('击杀最后一只 ⇒ 0..799ms 不结算、逃跑动画在播；800ms 之后才 onFinished',
        (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      final List<int> finishedAt = <int>[];
      int clock = 0; // 自「死亡首帧」起的毫秒数
      await pumpField(
        tester,
        script: oneShot(),
        handle: handle,
        finishedAt: finishedAt,
        nowMs: () => clock,
      );

      // 开火（首发恒过 300ms 冷却闸门）直到出现死亡淡出层。
      await tester.pump(const Duration(milliseconds: 984));
      handle.fire();
      bool dead = false;
      for (int i = 0; i < 40 && !dead; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        dead = find.byKey(GuardBattleField.deathFadeKey(0)).evaluate().isNotEmpty;
        if (i % 7 == 6 && !dead) handle.fire();
      }
      expect(dead, isTrue, reason: '一枪致命的剧本必须出现死亡演出');
      // 🔴 这条同时证明「战局已结束」：1 只怪被打死 ⇒ 全灭 ⇒ victory。
      expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
          reason: '🔴 击杀最后一只 = 终局（横幅已上屏）');

      final double x0 =
          tester.getTopLeft(find.byKey(GuardBattleField.monsterKey(0))).dx;
      final double op0 =
          tester.widget<Opacity>(find.byKey(GuardBattleField.deathFadeKey(0)))
              .opacity;
      expect(op0, 1.0, reason: '死亡首帧不淡出');

      // ── 推到 t=700ms（死亡后）：演出必须还在走、结算卡还不许出现 ──
      for (int i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        clock += 100;
      }
      expect(finishedAt, isEmpty,
          reason: '🔴 700ms 时 onFinished 不许触发（结算卡提前弹出 = 玄参的投诉现场）');
      final Finder fade = find.byKey(GuardBattleField.deathFadeKey(0));
      expect(fade, findsOneWidget,
          reason: '🔴 逃跑动画必须还在树上（ticker 活到 800ms，不再冻在第 0 帧）');
      final double x700 =
          tester.getTopLeft(find.byKey(GuardBattleField.monsterKey(0))).dx;
      final double op700 = tester.widget<Opacity>(fade).opacity;
      expect(x700, greaterThan(x0 + 1),
          reason: '🔴 逃跑位移必须真的在推进（旧实现冻在 $x0）');
      expect(op700, lessThan(op0),
          reason: '🔴 淡出必须真的在推进（旧实现冻在 $op0）');

      // ── t=799ms：仍然不许结算 ──
      await tester.pump(const Duration(milliseconds: 99));
      clock += 99;
      expect(finishedAt, isEmpty, reason: '🔴 799ms 时 onFinished 仍不许触发');

      // ── t=801ms：已交回页面 ──
      await tester.pump(const Duration(milliseconds: 2));
      clock += 2;
      expect(finishedAt, isNotEmpty,
          reason: '🔴 800ms 到点必须 onFinished（D1：演出播完才切结算卡）');
      expect(finishedAt.first, lessThanOrEqualTo(820),
          reason: '🔴 延迟就是 kGuardDeathFleeMs(800)，不是 900 / 1700');
    });

    testWidgets('到点撤退（无死亡演出）⇒ 不延迟：仍按 900ms 横幅停留',
        (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      final List<int> finishedAt = <int>[];
      int clock = 0;
      await pumpField(
        tester,
        script: timeoutOnly(),
        handle: handle,
        finishedAt: finishedAt,
        nowMs: () => clock,
      );

      // 窗口 600ms：推到 650ms（终局已发生、横幅已上屏）。
      for (int i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        clock += 50;
      }
      expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
          reason: '到点撤退 ⇒ 横幅上屏');
      expect(find.byKey(GuardBattleField.deathFadeKey(0)), findsNothing,
          reason: '没有击杀 ⇒ 不该有死亡演出');

      // 850ms（终局后 ≈200ms… 这里按 30s→600ms 窗口直接推到 850ms 总时长）：
      // 终局发生在 ~600ms，850ms 时还没到 900ms 的横幅停留 ⇒ 不许结算。
      while (clock < 850) {
        await tester.pump(const Duration(milliseconds: 50));
        clock += 50;
      }
      expect(clock - 600, lessThan(kGuardEndBannerDwellMs),
          reason: '前提：此刻仍未走完 900ms 横幅停留');
      expect(finishedAt, isEmpty,
          reason: '🔴 撤退路径没有 D1 延迟，但也不许提前于横幅停留结算');

      // 越过「终局 + 900ms 横幅停留」（≈ 1500ms）：必须结算。
      for (int i = 0; i < 30 && finishedAt.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        clock += 50;
      }
      expect(finishedAt, isNotEmpty,
          reason: '🔴 撤退路径 900ms 到点结算（延迟 = 0，不是 800 + 900）');
      final int delay = finishedAt.first - 600;
      expect(delay, greaterThanOrEqualTo(850),
          reason: '🔴 不许早于 900ms 横幅停留（实测 $delay ms）');
      expect(delay, lessThan(1000),
          reason: '🔴 撤退路径不许被 D1 的 800ms 再叠一层（实测 $delay ms）');
    });
  });
}
