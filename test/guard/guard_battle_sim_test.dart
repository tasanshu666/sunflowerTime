/// 守卫战 v2 · 战斗纯模拟器（`guard_battle_sim.dart`）验收测试。
///
/// 真源：`docs/花园守卫_守卫战玩法_增量设计_v1.md` §8.1（确定性重放金测）。
///
/// ## 本文件钉死的红线（期望值全部字面量，不从实现反推）
/// | # | 红线 | 断言口径 |
/// |---|---|---|
/// | G1 | 金测：同 seed + 同 fireTimeline 逐位一致 | 10s/20s/29999ms 快照 JSON 逐字符相同；不同 seed 不同 |
/// | G2 | 剧本派生确定性 + 区间 | 同日同孩两次派生 `==`；怪数 3~5、steal 1~3、dodge 0.15~0.35、speed 13~17 |
/// | G3 | 怪数 3 与 5 都在 seed 空间可达 | 60 个 childId 里 3 与 5 都出现 |
/// | G4 | 冷却闸门 | 400ms 内的第二发被拦下 |
/// | G5 | 全灭提前结束 | 密集开火 → victory 且早于 30s；待出场怪取消、已出场怪全灭 |
/// | G6 | 到点撤退 + 已偷保留 + 封顶 | 空 fireTimeline → retreat；被偷 = 逐怪合计 ≤ 3；之后快照冻结 |
/// | G7 | 分段无关性 | 同一时间线按不同步长切分 → 最终快照逐位相同 |
/// | G8 | 反 Random 哨兵 | 源文件不出现 `Random(` |
///
/// 🔴 期望值一律写死常量（30000 / 3~5 / 0.15~0.35 / 13~17），**不从实现里引用
/// 同一常量反推** —— 否则常量被改错时测试会跟着一起错。
library guard_battle_sim_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardBattleWindowMs, kGuardMonsterSpeedM1;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

const String _dayKey = '2026-11-08';
const String _childId = 'c1';

/// 金测开火时间线 A：800ms 起每 450ms 一发（间隔 > 400ms 冷却，全部受理），
/// 直至 75 发 —— 密集开火，事件最重（提前全灭收场）。
List<int> _goldTimeline() => <int>[
      for (int i = 0; i < 75; i++) 800 + 450 * i,
    ];

/// 金测开火时间线 B：只在 7s（m1 刚入场、走到枪口左侧深处）开一炮 ——
/// 7000ms 标记点有一发在飞的弹（B2 裁定：枪口 260，飞到左缘 ~0.87s），
/// 其后三个标记点战局都活着（怪在走、摆动在变）。
List<int> _goldLateTimeline() => <int>[7000];

/// 跑一整局：按 [stepMarks] 切分时间线喂 `step()`，在每个标记点取快照。
///
/// 每个开火时刻只提交一次（≤ 当前标记），与表现层 Ticker 的喂法一致。
List<GuardBattleSnapshot> _runBattle(
  String dayKey,
  String childId,
  List<int> fireTimeline,
  List<int> stepMarks,
) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim = GuardBattleSim(
    script: script,
    dayKey: dayKey,
    childId: childId,
  );
  final List<GuardBattleSnapshot> snapshots = <GuardBattleSnapshot>[];
  int fireIdx = 0;
  for (final int mark in stepMarks) {
    final List<int> chunk = <int>[];
    while (fireIdx < fireTimeline.length && fireTimeline[fireIdx] <= mark) {
      chunk.add(fireTimeline[fireIdx]);
      fireIdx++;
    }
    sim.step(mark, chunk);
    snapshots.add(sim.snapshot());
  }
  return snapshots;
}

/// 每秒细分的跑法（用不同的分段喂同一时间线，验证分段无关性）。
List<GuardBattleSnapshot> _runBattleFine(
  String dayKey,
  String childId,
  List<int> fireTimeline,
  List<int> stepMarks,
) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim = GuardBattleSim(
    script: script,
    dayKey: dayKey,
    childId: childId,
  );
  final List<GuardBattleSnapshot> snapshots = <GuardBattleSnapshot>[];
  int fireIdx = 0;
  int prev = 0;
  for (final int mark in stepMarks) {
    int t = prev;
    while (t < mark) {
      final int next = (t + 1000) > mark ? mark : (t + 1000);
      final List<int> chunk = <int>[];
      while (fireIdx < fireTimeline.length && fireTimeline[fireIdx] <= next) {
        chunk.add(fireTimeline[fireIdx]);
        fireIdx++;
      }
      sim.step(next, chunk);
      t = next;
    }
    prev = mark;
    snapshots.add(sim.snapshot());
  }
  return snapshots;
}

void main() {
  group('G1 确定性重放（金测）', () {
    test('同 seed + 同 fireTimeline：10s/20s/29999ms 快照 JSON 逐字符相同（密集开火）', () {
      final List<GuardBattleSnapshot> run1 = _runBattle(
          _dayKey, _childId, _goldTimeline(), <int>[10000, 20000, 29999]);
      final List<GuardBattleSnapshot> run2 = _runBattle(
          _dayKey, _childId, _goldTimeline(), <int>[10000, 20000, 29999]);
      expect(run1[0].toJsonString(), run2[0].toJsonString());
      expect(run1[1].toJsonString(), run2[1].toJsonString());
      expect(run1[2].toJsonString(), run2[2].toJsonString());
    });

    test('同 seed + 同 fireTimeline：快照 JSON 逐字符相同（战局活着）', () {
      // 7s 开一炮：7000ms 标记点有在飞的弹，10s/20s/29999ms 三个标记点都有
      // 活怪（位置/摆动随时间变化）—— 「逐位一致」在动态战局上同样成立。
      final List<GuardBattleSnapshot> run1 = _runBattle(_dayKey, _childId,
          _goldLateTimeline(), <int>[7000, 10000, 20000, 29999]);
      final List<GuardBattleSnapshot> run2 = _runBattle(_dayKey, _childId,
          _goldLateTimeline(), <int>[7000, 20000, 29999, 29999 + 1]);
      // 注意：第二个 run 的标记点切分不同（步进分段无关性由 G7 单独钉），
      // 但时间线相同 ⇒ 各标记点逐位一致。
      expect(run1[0].toJsonString(), run2[0].toJsonString());
      expect(run1[2].toJsonString(), run2[1].toJsonString());
      expect(run1[3].toJsonString(), run2[2].toJsonString());
      // 7000ms：弹在飞（枪口 260 → 目标在左缘附近，飞行 ~0.87s）。
      expect(run1[0].bullets, isNotEmpty,
          reason: '7s 开火后弹要飞 ~0.87s，此刻必然在飞');
      // 四个标记点的战局必须真的在变（不是全冻结的平凡相等）。
      expect(run1[0].toJsonString() != run1[1].toJsonString(), isTrue);
      expect(run1[1].toJsonString() != run1[2].toJsonString(), isTrue);
      expect(run1[2].toJsonString() != run1[3].toJsonString(), isTrue);
    });

    test('不同 seed（不同 childId）：战局不同', () {
      final List<GuardBattleSnapshot> runA = _runBattle(
          _dayKey, _childId, _goldLateTimeline(), <int>[10000, 20000, 29999]);
      final List<GuardBattleSnapshot> runB = _runBattle(
          _dayKey, 'c2', _goldLateTimeline(), <int>[10000, 20000, 29999]);
      // 剧本不同（怪数 / 种类 / 轨迹通道至少一处不同）。
      final GuardBattleScript scriptA =
          deriveGuardBattleScript(dayKey: _dayKey, childId: _childId);
      final GuardBattleScript scriptB =
          deriveGuardBattleScript(dayKey: _dayKey, childId: 'c2');
      expect(scriptA == scriptB, isFalse, reason: '不同 seed 必须派生出不同剧本');
      expect(runA[2].toJsonString(), isNot(runB[2].toJsonString()));
    });

    test('同一 seed 两次派生剧本逐位相同（== 且 JSON 相同）', () {
      final GuardBattleScript s1 =
          deriveGuardBattleScript(dayKey: _dayKey, childId: _childId);
      final GuardBattleScript s2 =
          deriveGuardBattleScript(dayKey: _dayKey, childId: _childId);
      expect(s1, equals(s2));
      expect(s1.hashCode, s2.hashCode);
      expect(jsonEncode(s1.toJson()), jsonEncode(s2.toJson()));
    });
  });

  group('G2 剧本区间（字面量）', () {
    test('怪数 3~5、出场表、steal 1~3、dodge 0.15~0.35、speed 13~17、HP 3~5、窗口 30000', () {
      final GuardBattleScript script =
          deriveGuardBattleScript(dayKey: _dayKey, childId: _childId);
      expect(script.windowMs, 30000);
      expect(script.monsters.length, greaterThanOrEqualTo(3));
      expect(script.monsters.length, lessThanOrEqualTo(5));
      for (int i = 0; i < script.monsters.length; i++) {
        final GuardBattleMonsterSpec m = script.monsters[i];
        expect(m.index, i);
        expect(m.spawnMs, <int>[0, 6000, 12000, 18000, 24000][i],
            reason: '出场时刻必须来自出怪时刻表前 N 项');
        expect(m.steal, greaterThanOrEqualTo(1));
        expect(m.steal, lessThanOrEqualTo(3));
        expect(m.dodgeProb, greaterThanOrEqualTo(0.15));
        expect(m.dodgeProb, lessThanOrEqualTo(0.35));
        expect(m.speedPtPerSec, greaterThanOrEqualTo(13.0));
        expect(m.speedPtPerSec, lessThanOrEqualTo(17.0));
        // B8：HP 1/2/3 → 3/4/5（玄参「一下死太无聊」）。
        expect(m.hitsToKill, greaterThanOrEqualTo(3));
        expect(m.hitsToKill, lessThanOrEqualTo(5));
      }
    });
  });

  group('G3 怪数 3 与 5 都在 seed 空间可达', () {
    test('扫 60 个 childId：3 和 5 都出现', () {
      final Set<int> counts = <int>{};
      for (int i = 0; i < 60; i++) {
        final GuardBattleScript script = deriveGuardBattleScript(
          dayKey: _dayKey,
          childId: 'seed-$i',
        );
        counts.add(script.monsters.length);
      }
      expect(counts.contains(3), isTrue, reason: '实际分布：$counts');
      expect(counts.contains(5), isTrue, reason: '实际分布：$counts');
    });
  });

  group('G4 开火冷却闸门', () {
    test('300ms 内的第二发被拦下（fireDropped），间隔足够的受理', () {
      // childId 'seed-0'：第 0 只怪不是一炮秒（B8 起 m1/m2/m3 = 3/4/5 发），
      // 首炮命中不会立刻收场，闸门行为可以被单独观察。
      const String childId = 'seed-0';
      final GuardBattleScript script =
          deriveGuardBattleScript(dayKey: _dayKey, childId: childId);
      expect(script.monsters.first.hitsToKill, greaterThan(1),
          reason: '夹具前提：首怪不是一炮秒，否则观察不到闸门');
      final GuardBattleSim sim = GuardBattleSim(
        script: script,
        dayKey: _dayKey,
        childId: childId,
      );
      // B8：冷却 400 → 300 ⇒ 1150 落在窗内（150 < 300）被拦，1400 受理
      // （1400 − 1000 = 400 ≥ 300）。
      final GuardBattleStepReport report = sim.step(2600, <int>[1000, 1150, 1400]);
      final int granted = report.events
          .where((GuardBattleEvent e) =>
              e.type == GuardBattleEventType.fireGranted)
          .length;
      final int dropped = report.events
          .where((GuardBattleEvent e) =>
              e.type == GuardBattleEventType.fireDropped)
          .length;
      expect(granted, 2, reason: '1000 与 1400 受理（间隔 400 ≥ 300）');
      expect(dropped, 1, reason: '1150 落在冷却窗内（150 < 300）被拦下');
      // 两发都命中了首怪（B2 几何下弹从枪口 260 飞向左缘怪 ~0.8s，
      // 2600ms 前两发都已到达）。
      expect(sim.snapshot().monsters.first.hitsTaken, 2);
      // 🔴 B8：首怪 HP ≥ 3 ⇒ 两发还打不死它，战局继续（旧口径 HP=1/2 时会
      // 在这里就全灭收场）。
      expect(sim.phase, GuardBattlePhase.fighting,
          reason: '首怪未死 ⇒ 仍在战斗');
    });
  });

  group('G5 全灭提前结束', () {
    test('密集开火 → victory 且早于 30s；**全部**怪（含最后出场的那只）都被击灭', () {
      // 每 401ms 一发（恒过 300ms 冷却闸门）直至 75 发。
      final List<int> dense = <int>[
        for (int i = 0; i < 75; i++) 300 + 401 * i,
      ];
      final List<int> marks = <int>[
        for (int t = 1000; t <= 30000; t += 1000) t,
      ];
      final List<GuardBattleSnapshot> snaps =
          _runBattle(_dayKey, _childId, dense, marks);
      // 找到打完的时刻。
      int overAt = -1;
      String phaseAtOver = '';
      for (final GuardBattleSnapshot s in snaps) {
        if (s.phaseId != 'fighting') {
          overAt = s.elapsedMs;
          phaseAtOver = s.phaseId;
          break;
        }
      }
      expect(phaseAtOver, 'victory', reason: '密集开火应当全灭（而非到点撤退）');
      expect(overAt, lessThan(30000), reason: '全灭 = 提前结束，实际在 ${overAt}ms');
      final GuardBattleSnapshot last = snaps.last;
      expect(last.phaseId, 'victory');
      expect(last.endReasonId, 'all_dead');
      // 🔴 B8 口径：胜利 = **剧本全部怪都已出场且被击灭**（旧口径「已出场怪
      // 全灭」会让「打死第 1 只」直接判胜，玄参判为产品错误）。因此：
      //  · 收场时刻必须晚于最后一只的出场时刻；
      //  · 收场时**不允许**存在 waiting / fled / retreated 的怪。
      int lastSpawnMs = 0;
      for (final GuardBattleMonsterSnapshot m in last.monsters) {
        if (m.spawnMs > lastSpawnMs) lastSpawnMs = m.spawnMs;
      }
      expect(overAt, greaterThan(lastSpawnMs),
          reason: '🔴 必须先等最后一只出场（${lastSpawnMs}ms）才可能收场');
      for (final GuardBattleMonsterSnapshot m in last.monsters) {
        expect(m.phaseId, 'dead',
            reason: '全灭 = 每一只都被击灭（含 spawn=${m.spawnMs} 的最后一只）');
      }
    });

    test('🔴 只打死第 1 只 ⇒ 不判胜、状态仍 fighting、第 2/3 只照常出场', () {
      // 手工剧本：3 只 m1、HP 3、闪避 0、spawn 0/6000/12000（确定性强于 seed）。
      final GuardBattleScript script = GuardBattleScript(
        monsters: <GuardBattleMonsterSpec>[
          for (int i = 0; i < 3; i++)
            GuardBattleMonsterSpec(
              index: i,
              kind: GuardBattleMonsterKind.m1,
              spawnMs: <int>[0, 6000, 12000][i],
              speedPtPerSec: kGuardMonsterSpeedM1,
              dodgeProb: 0,
              hitsToKill: 3,
              steal: 2,
              laneYPt: 45,
              wobbleAmpPt: 0,
              wobbleFreqHz: 0.3,
              wobblePhaseRad: 0,
            ),
        ],
        windowMs: kGuardBattleWindowMs,
      );
      final GuardBattleSim sim = GuardBattleSim(
        script: script,
        dayKey: _dayKey,
        childId: 'b8-victory-probe',
      );
      // 3 发打死第 1 只（首怪在打，自瞄恒锁它）。
      sim.step(2000, <int>[200, 600, 1000]);
      sim.step(2000, <int>[]);
      sim.step(2100, <int>[]);
      final GuardBattleSnapshot afterFirst = sim.snapshot();
      expect(afterFirst.monsters.first.phaseId, 'dead',
          reason: '🔴 前置：第 1 只必须真的死了');
      expect(afterFirst.phaseId, 'fighting',
          reason: '🔴 只杀 1 只不算赢（这是玄参点名的产品错误）');
      expect(afterFirst.endReasonId, 'none');
      expect(sim.isOver, isFalse);

      // 第 2 只照常出场（旧口径下它会被「取消出场」）。
      sim.step(6200, <int>[]);
      final GuardBattleSnapshot afterSpawn2 = sim.snapshot();
      expect(afterSpawn2.monsters[1].phaseId, 'walking',
          reason: '🔴 第 2 只必须照常出场（不许被取消）');
      expect(afterSpawn2.phaseId, 'fighting');

      // 全部清完才 Victory。
      sim.step(13000, <int>[6300, 7000, 7400]);
      sim.step(14000, <int>[]);
      sim.step(16000, <int>[13000, 13400, 13800, 14200, 14600, 15000]);
      sim.step(17000, <int>[]);
      final GuardBattleSnapshot fin = sim.snapshot();
      for (final GuardBattleMonsterSnapshot m in fin.monsters) {
        expect(m.phaseId, 'dead', reason: '三只都该死');
      }
      expect(fin.phaseId, 'victory', reason: '🔴 全灭才判胜');
      expect(fin.endReasonId, 'all_dead');
    });
  });

  group('G6 到点撤退 + 已偷保留 + 封顶', () {
    test('空 fireTimeline：30s 到点 retreat、被偷恰 2（c1 seed 钉死的字面量）、之后快照冻结', () {
      final List<GuardBattleSnapshot> snaps = _runBattle(
          _dayKey, _childId, <int>[], <int>[10000, 20000, 29999, 30000, 30001]);
      final GuardBattleSnapshot atEnd = snaps[3];
      expect(atEnd.phaseId, 'retreat');
      expect(atEnd.endReasonId, 'window_expired');
      // c1 的剧本 = 4 只 m1（13pt/s）：第 0 只 spawn 0、25.4s 到门口得手
      // （偷 2，封顶额度 3 用剩 1）；其余三只 spawn 6/12/18s、31.4s+ 才到门口
      // ⇒ 30s 到点撤退、偷 0。被偷合计钉死 = 2。
      expect(atEnd.stolenSun, 2);
      expect(atEnd.stealCapLeft, 1);
      int sumStolen = 0;
      for (final GuardBattleMonsterSnapshot m in atEnd.monsters) {
        sumStolen += m.stolen;
        expect(m.phaseId, anyOf('fled', 'retreated', 'waiting'),
            reason: '空时间线：得手退场 / 到点撤退 / 没走到门口被撤退');
      }
      expect(sumStolen, atEnd.stolenSun,
          reason: '逐怪偷取合计 = 快照累计（封顶口径一致）');
      // 已偷不回滚：结束后再喂时间，快照冻结。
      expect(snaps[4].toJsonString(), atEnd.toJsonString());
    });
  });

  group('G7 分段无关性', () {
    test('同一时间线按不同步长切分 → 各标记点快照逐位相同（两条时间线）', () {
      final List<int> marks = <int>[10000, 20000, 29999];
      for (final List<int> timeline in <List<int>>[_goldTimeline(), _goldLateTimeline()]) {
        final List<GuardBattleSnapshot> coarse =
            _runBattle(_dayKey, _childId, timeline, marks);
        final List<GuardBattleSnapshot> fine =
            _runBattleFine(_dayKey, _childId, timeline, marks);
        for (int i = 0; i < marks.length; i++) {
          expect(coarse[i].toJsonString(), fine[i].toJsonString(),
              reason: 't=${marks[i]}：确定性定义在输入时间线上，与步进分段无关');
        }
      }
    });
  });

  group('G8 反 Random 哨兵', () {
    test('guard_battle_sim.dart 源文件不出现 Random(', () {
      final String src =
          File('lib/domain/services/guard_battle_sim.dart').readAsStringSync();
      expect(src.contains('Random('), isFalse,
          reason: '全域禁用 Random；战斗「随机」只能走 stable_hash 确定性哈希');
    });
  });
}
