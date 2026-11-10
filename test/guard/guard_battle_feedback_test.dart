/// 守卫战 v2 · **B8 战斗手感 v2 护栏**（玄参 2026-11-10 第三轮真机）。
///
/// 真源：`guard_battle_sim.dart`（HP 3/4/5 · 换道通道 `lane_shift_*` ·
/// 胜利条件「全部出场且全灭」）+ `guard_battle_field.dart`（MISS 打击反馈）。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | F1 | 闪避 ⇒ 怪身边出现 `MISS`，且 [kGuardMissFxMs] 后消失（600ms） |
/// | F2 | 同一只怪连续闪避 ⇒ 只有一条 MISS（刷新，不堆叠） |
/// | F3 | 换道：同一 seed 的 y 轨迹逐位可重放；**至少变化 1 次**（不是直线） |
/// | F4 | 换道时段：每次换道都落在 [kGuardLaneShiftMs] 的平滑过渡里（无瞬移） |
/// | F5 | HP 字面量：m1/m2/m3 = 3/4/5（打 2 发打不死 m1） |
///
/// 🔴 绝不 `pumpAndSettle`（战斗层 ticker 常驻 + 常驻战士帧序列都在跑）。
library guard_battle_feedback_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
// ═══════════════════════════════════════════════════════════════════════

GuardTodayView _fightingView() => const GuardTodayView(
      mode: GuardPillMode.fighting,
      state: GuardDayState(
        dayKey: '2026-11-10',
        status: GuardDayStatus.fighting,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
      ),
      energyAvailable: 2,
      balance: 0,
    );

/// 单怪剧本（闪避概率可控 ⇒ MISS 断言不需要靠 seed 碰运气）。
GuardBattleScript _oneMonsterScript({
  required double dodgeProb,
  int hitsToKill = 3,
  int speed = 13,
  List<GuardLaneShift> laneShifts = const <GuardLaneShift>[],
  double wobbleAmp = 0,
}) {
  return GuardBattleScript(
    monsters: <GuardBattleMonsterSpec>[
      GuardBattleMonsterSpec(
        index: 0,
        kind: GuardBattleMonsterKind.m1,
        spawnMs: 0,
        speedPtPerSec: speed.toDouble(),
        dodgeProb: dodgeProb,
        hitsToKill: hitsToKill,
        steal: 1,
        laneYPt: 45,
        wobbleAmpPt: wobbleAmp,
        wobbleFreqHz: 0.3,
        wobblePhaseRad: 0,
        laneShifts: laneShifts,
      ),
    ],
    windowMs: kGuardBattleWindowMs,
  );
}

/// 把「战斗态场景卡」挂起来（战斗层 ticker 会跑，绝不用 pumpAndSettle）。
Future<void> _pumpFightingCard(
  WidgetTester tester, {
  required GuardBattleScript script,
  required GuardBattleHandle handle,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: GuardSceneCard(
              view: _fightingView(),
              dayKey: '2026-11-10',
              childId: 'b8-feedback',
              battleHandle: handle,
              debugScriptOverride: script,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // ── F1/F2 MISS 打击反馈 ───────────────────────────────────────────────
  group('F1 MISS 打击反馈（玄参：闪避没表现）', () {
    testWidgets('闪避 ⇒ 怪身边出现 MISS，600ms 内消失', (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      await _pumpFightingCard(
        tester,
        // 闪避概率 1.0 ⇒ 每一发都白打，MISS 必然出现。
        script: _oneMonsterScript(dodgeProb: 1.0),
        handle: handle,
      );
      expect(find.byKey(GuardBattleField.missKey(0)), findsNothing,
          reason: '夹具前提：还没开火 ⇒ 没有 MISS');

      handle.fire();
      // 子弹从枪口 260 飞到左缘怪 ≈ 867ms（300pt/s）⇒ 之后才有 dodge 事件。
      int seenAt = -1;
      for (int i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byKey(GuardBattleField.missKey(0)).evaluate().isNotEmpty) {
          seenAt = i;
          break;
        }
      }
      expect(seenAt, greaterThanOrEqualTo(0),
          reason: '🔴 闪避必须在怪身边弹出 MISS（玄参：闪避没表现）');
      expect(find.text('MISS'), findsOneWidget, reason: '🔴 文案字面量 MISS');

      // 再推 700ms（> kGuardMissFxMs 600）⇒ 必须消失。
      for (int i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(GuardBattleField.missKey(0)), findsNothing,
          reason: '🔴 MISS 只活 600ms（上浮 + 淡出），不许常驻');
    });

    testWidgets('同一只怪连续闪避 ⇒ 只留一条 MISS（刷新不堆叠）',
        (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      await _pumpFightingCard(
        tester,
        script: _oneMonsterScript(dodgeProb: 1.0),
        handle: handle,
      );
      // 连开三枪（间隔 ≥ 300ms 冷却），每枪都会闪避。
      for (int round = 0; round < 3; round++) {
        handle.fire();
        for (int i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.byKey(GuardBattleField.missKey(0)), findsOneWidget,
            reason: '🔴 第 ${round + 1} 枪后仍只有一条 MISS（同 index 刷新）');
        expect(find.text('MISS'), findsOneWidget);
      }
    });
  });

  // ── F3/F4 换道 ────────────────────────────────────────────────────────
  group('F3 小怪换道（玄参：怪要会换方位）', () {
    /// 用纯 sim 采样 y 轨迹（[stepMs] 步进，不开火）。
    List<double> sampleY(GuardBattleScript script, {int stepMs = 50}) {
      final GuardBattleSim sim = GuardBattleSim(
        script: script,
        dayKey: '2026-11-10',
        childId: 'b8-lane',
      );
      final List<double> ys = <double>[];
      for (int t = 0; t <= 20000; t += stepMs) {
        sim.step(t, <int>[]);
        ys.add(sim.snapshot().monsters.first.y);
      }
      return ys;
    }

    test('同一 seed 的 y 轨迹逐位可重放（确定性零破口）', () {
      final GuardBattleScript s1 =
          deriveGuardBattleScript(dayKey: '2026-11-10', childId: 'b8-lane');
      final GuardBattleScript s2 =
          deriveGuardBattleScript(dayKey: '2026-11-10', childId: 'b8-lane');
      expect(s1, equals(s2), reason: '同一 seed 剧本必须逐位相等（含换道计划）');
      expect(sampleY(s1), sampleY(s2), reason: '🔴 y 轨迹逐点相等');
    });

    test('行进中 y 至少变化 1 次（换道真的发生了，不是直线）', () {
      // 关掉摆动（wobbleAmp=0）⇒ y 的任何变化都只能来自换道。
      final GuardBattleScript withShift = _oneMonsterScript(
        dodgeProb: 0,
        laneShifts: const <GuardLaneShift>[
          GuardLaneShift(startMs: 5000, targetLaneYPt: 70),
        ],
      );
      final List<double> ys = sampleY(withShift);
      double minY = ys.first;
      double maxY = ys.first;
      for (final double y in ys) {
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      expect(maxY - minY, closeTo(25, 0.5),
          reason: '🔴 45 → 70 的换道必须真的走完（差值 = 25pt）');

      // 对照组：没有换道计划 ⇒ y 恒定（证明上面测到的变化确实来自换道）。
      final List<double> flat = sampleY(_oneMonsterScript(dodgeProb: 0));
      expect(flat.toSet().length, 1, reason: '无换道 + 无摆动 ⇒ y 恒为 45');
      expect(flat.first, closeTo(45, 0.01));
    });

    test('换道是 [kGuardLaneShiftMs] 的平滑过渡（无瞬移）', () {
      // 10ms 步进看单步最大跳变：smoothstep 在 400ms 内走 25pt ⇒ 每 10ms
      // 最多约 25 × (3 × 0.025) ≈ 1.9pt；瞬移会出现 25pt 的单步跳。
      final GuardBattleScript withShift = _oneMonsterScript(
        dodgeProb: 0,
        laneShifts: const <GuardLaneShift>[
          GuardLaneShift(startMs: 5000, targetLaneYPt: 70),
        ],
      );
      final GuardBattleSim sim = GuardBattleSim(
        script: withShift,
        dayKey: '2026-11-10',
        childId: 'b8-lane',
      );
      double prev = sim.snapshot().monsters.first.y;
      double maxStep = 0;
      for (int t = 10; t <= 20000; t += 10) {
        sim.step(t, <int>[]);
        final double y = sim.snapshot().monsters.first.y;
        final double d = (y - prev).abs();
        if (d > maxStep) maxStep = d;
        prev = y;
      }
      expect(maxStep, lessThan(3.0),
          reason: '🔴 换道必须平滑（单步最大跳变 ${maxStep}pt，瞬移会是 25pt）');
    });

    test('派生剧本里每只怪都有 1~2 次换道计划，且时刻落在行程中段', () {
      final GuardBattleScript script =
          deriveGuardBattleScript(dayKey: '2026-11-10', childId: 'b8-lane');
      for (final GuardBattleMonsterSpec m in script.monsters) {
        expect(m.laneShifts.length, inInclusiveRange(1, 2),
            reason: '🔴 每只怪换道 1~2 次（玄参：行进中做 1~2 次换道）');
        for (final GuardLaneShift s in m.laneShifts) {
          expect(s.startMs, greaterThan(m.spawnMs),
              reason: '换道必须在出场之后');
          expect(s.targetLaneYPt,
              inInclusiveRange(kGuardBattleLaneTopPt, kGuardBattleLaneBottomPt),
              reason: '目标车道必须落在车道带内（否则怪会跑出可视带）');
        }
      }
    });
  });

  // ── F5 HP 字面量 ──────────────────────────────────────────────────────
  group('F5 HP 3/4/5（玄参：一下死太无聊）', () {
    test('打 2 发打不死 m1（HP 3）；第 3 发才灭', () {
      final GuardBattleSim sim = GuardBattleSim(
        script: _oneMonsterScript(dodgeProb: 0, hitsToKill: 3),
        dayKey: '2026-11-10',
        childId: 'b8-hp',
      );
      // 两发（间隔 ≥ 300ms 冷却），各自 ~870ms 后到达。
      sim.step(100, <int>[100]);
      sim.step(500, <int>[500]);
      sim.step(2000, <int>[]);
      expect(sim.snapshot().monsters.first.hitsTaken, 2);
      expect(sim.snapshot().monsters.first.phaseId, 'walking',
          reason: '🔴 2 发打不死（HP 3）');
      expect(sim.isOver, isFalse);

      sim.step(2500, <int>[2200]);
      sim.step(4000, <int>[]);
      expect(sim.snapshot().monsters.first.phaseId, 'dead',
          reason: '🔴 第 3 发才灭');
    });

    test('常量字面量：m1/m2/m3 = 3/4/5', () {
      expect(kGuardMonsterHitsM1, 3);
      expect(kGuardMonsterHitsM2, 4);
      expect(kGuardMonsterHitsM3, 5);
      // 与剧本派生的实际取值一致（防「常量改了但 kind 没接上」）。
      for (final GuardBattleMonsterKind k in GuardBattleMonsterKind.values) {
        final int expected = switch (k) {
          GuardBattleMonsterKind.m1 => 3,
          GuardBattleMonsterKind.m2 => 4,
          GuardBattleMonsterKind.m3 => 5,
        };
        expect(k.hitsToKill, expected);
      }
    });
  });
}
