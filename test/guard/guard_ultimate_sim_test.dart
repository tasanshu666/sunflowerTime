/// 大招清场 `castUltimate` 测试（P0-05 / P0-04② / B3 / A5/A6）。
///
/// 期望值独立写死：5 怪全清、含闪避怪、阳光/宝箱掉落 +0（不发 `kill` 事件）、
/// 战果记 5、非战斗态 no-op、后续波次照常 spawn。
library guard_ultimate_sim_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

const String _dayKey = '2026-11-20';
const String _childId = 'ult-kid';

/// 构造 [count] 只怪的剧本：全部 spawnMs=0（step 后立即 walking），
/// 其中 [dodgeCount] 只带 1.0 闪避概率（必闪）——用于验证大招无视闪避。
GuardBattleScript _script({required int count, required int dodgeCount}) {
  return GuardBattleScript(
    windowMs: 30000,
    monsters: <GuardBattleMonsterSpec>[
      for (int i = 0; i < count; i++)
        GuardBattleMonsterSpec(
          index: i,
          kind: GuardBattleMonsterKind.m1,
          spawnMs: 0,
          speedPtPerSec: 15,
          dodgeProb: i < dodgeCount ? 1.0 : 0.0,
          hitsToKill: 99, // 普通子弹极难打死，确保清场完全归因于大招
          steal: 1,
          laneYPt: 100 + i * 4,
          wobbleAmpPt: 0,
          wobbleFreqHz: 0,
          wobblePhaseRad: 0,
        ),
    ],
  );
}

GuardBattleSim _sim(GuardBattleScript script) => GuardBattleSim(
      script: script,
      dayKey: _dayKey,
      childId: _childId,
    );

void main() {
  group('P0-05 · castUltimate 清场', () {
    test('5 只 walking 怪（含 2 只必闪）全部清除，战果记 5（A5）', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 2));
      sim.step(1000, <int>[]); // 全部入场 walking
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);

      expect(sim.ultimateKillCount, 5);
      final GuardBattleSnapshot snap = sim.snapshot();
      expect(
        snap.monsters.where((GuardBattleMonsterSnapshot m) => m.phaseId == 'dead').length,
        5,
        reason: '5 只全部置 dead（走击杀结算，非撤退）',
      );
      expect(
        snap.monsters.any((GuardBattleMonsterSnapshot m) => m.phaseId == 'retreated'),
        isFalse,
        reason: '不是 _retreatAll 撤退',
      );
    });

    test('事件流：5 条 ultimateKill + 1 条 ultimateCast，零 kill（A5 零掉落）', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 2));
      sim.step(1000, <int>[]);
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);

      expect(
        events.where((GuardBattleEvent e) => e.type == GuardBattleEventType.ultimateKill).length,
        5,
      );
      expect(
        events.where((GuardBattleEvent e) => e.type == GuardBattleEventType.ultimateCast).length,
        1,
      );
      expect(
        events.any((GuardBattleEvent e) => e.type == GuardBattleEventType.kill),
        isFalse,
        reason: '大招绝不发 kill ⇒ 表现层阳光掉落零误触发（口径 8）',
      );
      expect(
        events
            .where((GuardBattleEvent e) => e.type == GuardBattleEventType.ultimateKill)
            .every((GuardBattleEvent e) => e.tMs == 1000),
        isTrue,
        reason: '事件时刻 = atMs',
      );
    });

    test('无视闪避：dodgeProb=1.0 的怪也被清除', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 5));
      sim.step(1000, <int>[]);
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);
      // 全必闪怪仍被清 5 只，且没有 dodge 事件（不走子弹 / 闪避路径）。
      expect(sim.ultimateKillCount, 5);
      expect(
        events.any((GuardBattleEvent e) => e.type == GuardBattleEventType.dodge),
        isFalse,
      );
    });

    test('清掉最后一波 ⇒ 判胜（allDead，可计入通关）', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 1));
      sim.step(1000, <int>[]);
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);
      expect(sim.phase, GuardBattlePhase.victory);
      expect(sim.endReason, GuardBattleEndReason.allDead);
    });

    test('多次释放：第二场重置后仍可用（一场内扣格由服务层管，sim 无状态限制）', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 1));
      sim.step(1000, <int>[]);
      sim.castUltimate(1000, <GuardBattleEvent>[]);
      expect(sim.ultimateKillCount, 5);
      // 重开一局（sim 是单战局对象）：新建即归零，与前一场无关。
      final GuardBattleSim sim2 = _sim(_script(count: 5, dodgeCount: 1));
      expect(sim2.ultimateKillCount, 0);
    });
  });

  group('P0-04② · 非战斗态 no-op', () {
    test('终局后 castUltimate 不产生任何事件、不改战果', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 0));
      sim.step(1000, <int>[]);
      sim.castUltimate(1000, <GuardBattleEvent>[]); // 判胜，phase=victory
      final int before = sim.ultimateKillCount;
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(2000, events); // 非战斗态再放
      expect(events, isEmpty);
      expect(sim.ultimateKillCount, before);
    });
  });

  group('B3 · 不改波次调度', () {
    test('只清当前 walking，waiting 怪照常按 step 出场', () {
      // 6 只怪：前 2 只 spawnMs=0，后 4 只稍后出场。
      final GuardBattleScript script = GuardBattleScript(
        windowMs: 30000,
        monsters: <GuardBattleMonsterSpec>[
          for (int i = 0; i < 6; i++)
            GuardBattleMonsterSpec(
              index: i,
              kind: GuardBattleMonsterKind.m1,
              spawnMs: i < 2 ? 0 : 2000,
              speedPtPerSec: 15,
              dodgeProb: 0,
              hitsToKill: 99,
              steal: 1,
              laneYPt: 100 + i * 4,
              wobbleAmpPt: 0,
              wobbleFreqHz: 0,
              wobblePhaseRad: 0,
            ),
        ],
      );
      final GuardBattleSim sim = _sim(script);
      sim.step(1000, <int>[]); // 2 只 walking，4 只 waiting
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);
      expect(sim.ultimateKillCount, 2, reason: '只清当前 walking 的 2 只');
      expect(sim.phase, GuardBattlePhase.fighting, reason: 'waiting 怪还在，不判胜');

      // 后续波次照常 spawn（B3）。
      sim.step(2500, <int>[]);
      final GuardBattleSnapshot snap = sim.snapshot();
      expect(
        snap.monsters.where((GuardBattleMonsterSnapshot m) => m.phaseId == 'walking').length,
        4,
        reason: '后 4 只按既有 step 节奏入场',
      );
    });
  });

  group('零掉落 · 阳光/宝箱 +0', () {
    test('大招不发 kill ⇒ sim 侧无掉落事件（theft 只在到门口）', () {
      final GuardBattleSim sim = _sim(_script(count: 5, dodgeCount: 2));
      sim.step(1000, <int>[]);
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);
      // 掉落 VFX 由表现层仅消费 kill；sim 侧无 theft（到门口偷阳光）事件。
      expect(events.any((GuardBattleEvent e) => e.type == GuardBattleEventType.theft), isFalse);
      expect(sim.stolenSun, 0, reason: '大招不发 theft、未到门口 ⇒ 被偷 0');
    });
  });
}
