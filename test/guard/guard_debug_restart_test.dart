/// 守卫战 v2 · **B10/B3 重开战局护栏**（玄参 2026-11-10 第五轮）。
///
/// ## 玄参原话
/// 「在调试面板里重置之后，点胶囊**不发射**了」—— 同一场次连打两次，
/// 第二次开战后的子弹永远不出现（等于点了没反应）。
///
/// ## 病理（三处，全部在 `_GuardBattleFieldState` 的生命周期上）
/// 1. `GuardBattleHandle._over` 是**页面级长生命周期对象**上的字段：终局时置
///    `true`，只有 `_restartBattle()` 会复位。State 重新挂载（换卡 / 调试重置
///    后重开）走的却是 `initState` —— 旧实现没在那里复位 ⇒ `handle.fire()`
///    在**源头**直接 return（`.fire()` 内的 `if (_over) return;`）。
/// 2. 终局时 `_ticker.stop()`；旧 `_restartBattle` 只在「ticker 已停摆」的分支里
///    `start()`，且没有把 `_simZeroMs` / `_rawMs` 归零 ⇒ 新 sim 可能被单大步
///    喂穿（一步跨完 30s 窗口）。
/// 3. `handle._fire` 可能被上一场的 `dispose` 置 `null`（切到结算卡 / 换卡），
///    重开后不重绑就再也没人接开火。
///
/// ## 修法（B10）
/// `initState` 复位 `handle._over`；`_restartBattle` 固定走
/// 「stop → 重建 sim → 归零时间锚 → 重绑 `_fire` / 复位 `_over` → start」六步。
///
/// 🔴 本文件第 ① 条的**第一条断言**就是「第二次战局 1s 内存在 bullet」——
/// 旧实现下它必红（`_over` 卡在 true ⇒ 一发都没有）。
///
/// ## 夹具约定（为什么每一场都用「短窗口 + 到点撤退」）
/// 用 `hitsToKill: 99` 的慢速怪 ⇒ 窗口内打不死、也走不到门，战局必然在
/// `windowMs` 那一刻**到点撤退**收场（`_ticker.stop()` + `handle._over = true`
/// —— 正是 B3 的致病状态）。窗口取 300~500ms，一条用例几十帧就能走完两场。
///
/// ⚠️ 收场后会挂一个 `Future.delayed(kGuardEndBannerDwellMs)`（横幅停留 900ms
/// 再 `onFinished`）；用例收尾必须 pump 掉它，否则 `testWidgets` 会报
/// 「A Timer is still pending even after the widget tree was disposed」。
library guard_debug_restart_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

/// 1 只「打不死、走得慢」的怪 + 指定窗口（窗口短 ⇒ 到点撤退，战局快速收场）。
GuardBattleScript _script({required int windowMs}) {
  return GuardBattleScript(
    windowMs: windowMs,
    monsters: <GuardBattleMonsterSpec>[
      const GuardBattleMonsterSpec(
        index: 0,
        kind: GuardBattleMonsterKind.m1,
        spawnMs: 0,
        speedPtPerSec: 4, // 330pt 要 82s ⇒ 窗口内绝不会到门
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

Future<void> _pumpField(
  WidgetTester tester, {
  required GuardBattleHandle handle,
  required GuardBattleScript script,
  required List<GuardBattleSnapshot> snaps,
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
            height: kGuardSceneCardHeight,
            child: GuardBattleField(
              dayKey: '2026-11-10',
              childId: 'restart-0',
              handle: handle,
              debugScriptOverride: script,
              onSnapshot: snaps.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// 把「收场后 900ms 的横幅停留回调」走完（否则测试收尾报 pending Timer）。
///
/// ⚠️ 必须 **pump 两次**：最后一场在收尾时可能**仍在跑**——
/// * 第一段 1000ms 把它推到窗口外 ⇒ 收场，并**此刻**才挂上 900ms 停留回调；
/// * 第二段 1000ms 才是把那条回调走完。
/// 只 pump 一次的话，「收场」与「走完停留」会被压在同一段里 ⇒ 差几百毫秒 ⇒ 报
/// `A Timer is still pending`。
Future<void> _drainEndDwell(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pump(const Duration(milliseconds: 1000));
}

/// 从当前帧起最多 [maxFrames] 帧内等一颗在飞的子弹（返回是否等到）。
///
/// 一帧 16ms ⇒ 默认 60 帧 ≈ 960ms，足够覆盖「开火冷却 + 一两帧入队延迟」。
Future<bool> _awaitBullet(WidgetTester tester, {int maxFrames = 60}) async {
  for (int i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byKey(GuardBattleField.bulletKey(0)).evaluate().isNotEmpty) {
      return true;
    }
  }
  return false;
}

void main() {
  testWidgets('① 同一场次连打两次：第二次开局 1s 内必须有飞行的子弹',
      (WidgetTester tester) async {
    final GuardBattleHandle handle = GuardBattleHandle();
    final List<GuardBattleSnapshot> snaps = <GuardBattleSnapshot>[];

    // ── 第一场：窗口 300ms ⇒ 到点撤退收场（ticker stop / handle._over = true）──
    await _pumpField(
      tester,
      handle: handle,
      script: _script(windowMs: 300),
      snaps: snaps,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
        reason: '第一场必须真的收场（横幅上屏 ⇒ ticker 已停、`_over` 已置位）');
    final int snapsAfterFirst = snaps.length;

    // 收场后开火是 no-op（B1 R3 口径，这里顺带钉住）。
    handle.fire();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(GuardBattleField.bulletKey(0)), findsNothing,
        reason: '已收场的战局不接受开火（旧的「结束后静默丢弃」口径不变）');

    // ── 重开：换剧本 ⇒ didUpdateWidget ⇒ _restartBattle（State 不复建）──
    await _pumpField(
      tester,
      handle: handle,
      script: _script(windowMs: kGuardBattleWindowMs),
      snaps: snaps,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(GuardBattleField.bannerKey), findsNothing,
        reason: '重开后横幅必须消失（新战局从 0 开始）');

    // 🔴 第一条断言（旧实现必红）：1s 内必须有子弹在飞。
    handle.fire();
    final bool bullet = await _awaitBullet(tester);
    expect(bullet, isTrue,
        reason: '🔴 B3：第二次战局开火必须有子弹（旧实现 `handle._over` 卡在 true ⇒ '
            '`fire()` 在源头 return，一颗都没有）');

    // ② ticker 真的重启了：新快照的时刻必须从 0 重新往上走。
    expect(snaps.length, greaterThan(snapsAfterFirst),
        reason: '重开后 ticker 必须在跑（否则再也不会有新快照）');
    expect(snaps.last.elapsedMs, lessThan(kGuardBattleWindowMs),
        reason: '新战局的时间轴从 0 起（不是被上一场的累计值喂穿）');

    // ③ 第二次战局的怪还在场（画面上真的重开了一局）。
    expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget,
        reason: '重开后必须重新出现怪（新 sim 的 0 号怪）');

    // 收尾：第一场收场时挂的 900ms 横幅停留回调，别留给 teardown。
    await _drainEndDwell(tester);
  });

  testWidgets('② 重开两次都能开火（不是只对「第二次」有效）',
      (WidgetTester tester) async {
    final GuardBattleHandle handle = GuardBattleHandle();
    final List<GuardBattleSnapshot> snaps = <GuardBattleSnapshot>[];

    // 每一轮：先用短窗口把**当前**战局收场（造出 B3 的致病状态：ticker 停 +
    // `_over = true`），再换一个**不同窗口**的剧本重开（`==` 逐位比较 ⇒ 变了
    // 才会走 `didUpdateWidget → _restartBattle`），最后验证开火有子弹。
    int windowMs = 300;
    await _pumpField(
      tester,
      handle: handle,
      script: _script(windowMs: windowMs),
      snaps: snaps,
    );

    for (int round = 1; round <= 2; round++) {
      // ① 收场
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
          reason: '第 $round 场必须收场');

      // ② 重开（窗口 +100ms ⇒ 剧本对象内容不同 ⇒ 真重开）
      windowMs += 100;
      await _pumpField(
        tester,
        handle: handle,
        script: _script(windowMs: windowMs),
        snaps: snaps,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(GuardBattleField.bannerKey), findsNothing,
          reason: '第 $round 次重开后必须是一局新战局（横幅已撤）');

      // ③ 开火必须有子弹（B3 的核心回归点，第二轮同样要绿）
      handle.fire();
      final bool bullet = await _awaitBullet(tester);
      expect(bullet, isTrue, reason: '第 $round 次重开后开火必须有子弹');
    }

    // 收尾：最后一场的「横幅停留」延迟回调（kGuardEndBannerDwellMs）走完。
    await _drainEndDwell(tester);
  });
}
