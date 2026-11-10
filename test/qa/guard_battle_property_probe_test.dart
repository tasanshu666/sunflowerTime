/// 守卫战 v2 独立验收 · **W7 属性测试探针（200 seed）**。
///
/// 判据（主理人验收单 W7）：
/// * 怪数 ∈ [3,5]、每怪 steal ∈ [1,3]、dodge ∈ [0.15,0.35]、HP ∈ [3,5]、
///   spawn 时刻 ∈ kGuardSpawnOffsetsMs 表、laneY ∈ [10,80]；
/// * kind 通道相关性作为**已知特征**记录分布（不判红——B3 已实测同 seed 强相关）。
library;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

void main() {
  final Map<GuardBattleMonsterKind, int> kindCount = <GuardBattleMonsterKind, int>{};
  final Map<int, int> countHistogram = <int, int>{};
  final Map<GuardBattleMonsterKind, int> firstKindHistogram =
      <GuardBattleMonsterKind, int>{};

  setUpAll(() {
    for (int i = 0; i < 200; i++) {
      final GuardBattleScript script = deriveGuardBattleScript(
        dayKey: '2026-11-09',
        childId: 'qa-prop-$i',
      );
      countHistogram[script.monsters.length] =
          (countHistogram[script.monsters.length] ?? 0) + 1;
      firstKindHistogram[script.monsters.first.kind] =
          (firstKindHistogram[script.monsters.first.kind] ?? 0) + 1;
      for (final GuardBattleMonsterSpec m in script.monsters) {
        kindCount[m.kind] = (kindCount[m.kind] ?? 0) + 1;
      }
    }
  });

  test('怪数 ∈ [3,5]（200 seed）', () {
    for (int i = 0; i < 200; i++) {
      final GuardBattleScript script = deriveGuardBattleScript(
          dayKey: '2026-11-09', childId: 'qa-prop-$i');
      expect(script.monsters.length, inInclusiveRange(3, 5),
          reason: 'seed qa-prop-$i 怪数 ${script.monsters.length}');
    }
  });

  test('每怪 steal ∈ [1,3]、dodge ∈ [0.15,0.35]、HP ∈ [3,5]（200 seed 全怪）', () {
    for (int i = 0; i < 200; i++) {
      final GuardBattleScript script = deriveGuardBattleScript(
          dayKey: '2026-11-09', childId: 'qa-prop-$i');
      for (final GuardBattleMonsterSpec m in script.monsters) {
        expect(m.steal, inInclusiveRange(kGuardStealMin, kGuardStealMax),
            reason: 'seed qa-prop-$i 怪 #${m.index} steal=${m.steal}');
        expect(m.dodgeProb, inInclusiveRange(0.15, 0.35),
            reason: 'seed qa-prop-$i 怪 #${m.index} dodge=${m.dodgeProb}');
        // B8：HP 1/2/3 → 3/4/5（玄参「一下死太无聊」）。
        expect(m.hitsToKill, inInclusiveRange(3, 5),
            reason: 'seed qa-prop-$i 怪 #${m.index} HP=${m.hitsToKill}');
      }
    }
  });

  test('spawn 时刻 ∈ kGuardSpawnOffsetsMs 前 N 项（200 seed）', () {
    for (int i = 0; i < 200; i++) {
      final GuardBattleScript script = deriveGuardBattleScript(
          dayKey: '2026-11-09', childId: 'qa-prop-$i');
      for (int j = 0; j < script.monsters.length; j++) {
        expect(script.monsters[j].spawnMs, kGuardSpawnOffsetsMs[j],
            reason: 'seed qa-prop-$i 怪 #$j spawn=${script.monsters[j].spawnMs}');
      }
    }
  });

  test('laneY ∈ [10,80]（200 seed 全怪）', () {
    for (int i = 0; i < 200; i++) {
      final GuardBattleScript script = deriveGuardBattleScript(
          dayKey: '2026-11-09', childId: 'qa-prop-$i');
      for (final GuardBattleMonsterSpec m in script.monsters) {
        expect(m.laneYPt, inInclusiveRange(kGuardBattleLaneTopPt,
            kGuardBattleLaneBottomPt),
            reason: 'seed qa-prop-$i 怪 #${m.index} laneY=${m.laneYPt}');
      }
    }
  });

  test('【已知特征·不判红】kind 通道相关性分布记录', () {
    // ignore: avoid_print
    print('QA/W7 kind 分布（全怪计）：$kindCount');
    // ignore: avoid_print
    print('QA/W7 首怪种类直方图（200 seed）：$firstKindHistogram');
    // ignore: avoid_print
    print('QA/W7 怪数直方图（200 seed）：$countHistogram');
    // 已知特征（B3 实测、本次复核）：kind_<i> 通道在同 seed 内强相关——
    // 200 seed 从未出现三怪混编，同 seed 几乎全同种。这是特征不是缺陷：
    // 调试面板因此走显式覆盖（buildGuardBattleScriptForDebug）。
    // 本探针只记录分布，不作红绿判定（W7 口径）。
    expect(kindCount.values.fold(0, (int a, int b) => a + b), greaterThan(0));
  });
}
