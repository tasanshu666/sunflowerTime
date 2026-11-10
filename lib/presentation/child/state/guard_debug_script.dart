/// 守卫战 v2 · **调试剧本覆盖**（仅 `kDebugMode` · B5a）。
///
/// ## 解决什么问题
/// 玄参验收守卫战时需要**确定性**的战局：指定怪数（3 / 5）、三怪混编（m1/m2/m3
/// 各一）、高偷窃（必有怪到门口）—— 但 `deriveGuardBattleScript` 的 `kind_<i>`
/// 通道在**同一 seed 内强相关**（B3 实测 200 个 seed 从未出现三怪混编），
/// 「搜 seed」这条路走不通，必须走**显式覆盖**。
///
/// ## 覆盖注入点（生产路径零感知）
/// ```text
/// 调试面板「花园守卫 → 强制剧本」按钮组（仅 kDebugMode 可见）
///   → 写 [debugGuardBattleScriptOverrideProvider]（null = 跟随真实派生）
///   → ChildTodayPage 建卡时读取 → GuardSceneCard 透传
///   → GuardBattleField.initState：sim 用 override ?? deriveGuardBattleScript(...)
/// ```
/// * **冻结三件套零 diff**：`guard_battle_sim.dart` 的派生函数一行未动 ——
///   本文件在**表现层**用公开的 `GuardBattleScript` / `GuardBattleMonsterSpec`
///   构造器显式拼剧本（构造器是 B1 冻结的公开 API，不属于生产语义）。
/// * **release 安全**：写入方只有调试面板（release 整块不出现）⇒ provider
///   恒为 null ⇒ `GuardBattleField` 走原派生分支，生产行为逐位不变。
/// * **确定性**：覆盖剧本零随机（laneY 均布 / wobble 定值 / steal 按序轮转），
///   同参数逐位可复现 —— 行为测试的字面量期望由此而来。
///
/// ## 命名惯例
/// 对齐 v1 的 `*ForDebug` 家族（`forceThiefForDebug` / `grantSeedForDebug`…）：
/// 仅 kDebugMode、不抛异常、不写账本。
library guard_debug_script;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

/// 调试剧本覆盖（null = 跟随真实 seed 派生）。
///
/// 唯一写入方 = 调试面板「强制剧本」按钮组；唯一读取方 = `ChildTodayPage`。
final StateProvider<GuardBattleScript?>
    debugGuardBattleScriptOverrideProvider =
    StateProvider<GuardBattleScript?>((Ref ref) => null);

// ── 按钮 Key（调试面板与行为测试共用同一组常量，防字符串漂移）────────────────

/// 「强制 3 只怪」按钮 Key。
const String kDebugGuardScriptKeyCount3 = 'debug_guard_script_count3';

/// 「强制 5 只怪」按钮 Key。
const String kDebugGuardScriptKeyCount5 = 'debug_guard_script_count5';

/// 「强制三怪混编」按钮 Key。
const String kDebugGuardScriptKeyMixed = 'debug_guard_script_mixed';

/// 「强制高偷窃战局」按钮 Key。
const String kDebugGuardScriptKeyTheft = 'debug_guard_script_theft';

/// 「恢复随机剧本」按钮 Key。
const String kDebugGuardScriptKeyFollow = 'debug_guard_script_follow';

/// 「当前模式」常显行 Key（守卫调试区**顶部**，玄参「点了不知道有没有生效」）。
const String kDebugGuardModeTextKey = 'debug_guard_mode_text';

/// 「上次操作」回执行 Key（守卫调试区按钮**下方**，手指落点旁边）。
const String kDebugGuardFeedbackTextKey = 'debug_guard_feedback_text';

/// 构造一份**显式**的调试战斗剧本（不走 seed 派生）。
///
/// * [monsterCount]：怪数（1..[kGuardSpawnOffsetsMs.length]，出场时刻取前 N 项）。
/// * [kinds]：逐怪种类；null = 全 m1（最慢 13pt/s，全场 ~25.4s，便于稳定观察）。
/// * [highTheft]：true = 全员 `steal = [kGuardStealMax]` 且全 m1 ⇒ 只要孩子不开火，
///   必有怪在 30s 窗口内到门口（封顶钳制 / 被偷行展示的确定性素材）。
///
/// 确定性口径：steal 默认按 `1 + (i % 3)` 轮转（1/2/3/1/2）、laneY 在
/// [kGuardBattleLaneTopPt, kGuardBattleLaneBottomPt] 均布、wobble 定值 ——
/// 同参数重跑逐位一致。
GuardBattleScript buildGuardBattleScriptForDebug({
  required int monsterCount,
  List<GuardBattleMonsterKind>? kinds,
  bool highTheft = false,
}) {
  assert(kDebugMode,
      'debug battle script must be built in debug builds only (no release caller)');
  assert(
    monsterCount >= 1 && monsterCount <= kGuardSpawnOffsetsMs.length,
    'monsterCount must be within the spawn schedule range '
    '(1..${kGuardSpawnOffsetsMs.length})',
  );

  // 种类：显式指定（混编按钮传 [m1, m2, m3]）；缺省全 m1（最慢 = 必有怪到门口）。
  final List<GuardBattleMonsterKind> effectiveKinds = highTheft
      ? List<GuardBattleMonsterKind>.filled(
            monsterCount, GuardBattleMonsterKind.m1,
            growable: false,
          )
      : (kinds ?? List<GuardBattleMonsterKind>.filled(
            monsterCount, GuardBattleMonsterKind.m1,
            growable: false,
          ));
  assert(effectiveKinds.length == monsterCount,
      'kinds length must equal monsterCount');

  final List<GuardBattleMonsterSpec> monsters = <GuardBattleMonsterSpec>[
    for (int i = 0; i < monsterCount; i++)
      _specForDebug(
        index: i,
        kind: effectiveKinds[i],
        total: monsterCount,
        steal: highTheft ? kGuardStealMax : 1 + (i % kGuardStealMax),
      ),
  ];
  return GuardBattleScript(
    monsters: monsters,
    windowMs: kGuardBattleWindowMs,
  );
}

/// 单只怪的确定性参数（均布车道 + 定值摆动；零随机）。
GuardBattleMonsterSpec _specForDebug({
  required int index,
  required GuardBattleMonsterKind kind,
  required int total,
  required int steal,
}) {
  // laneY：在车道范围内均布（1 只 = 居中），保证多怪不叠在同一行。
  final double t = total <= 1 ? 0.5 : index / (total - 1);
  final double laneY = kGuardBattleLaneTopPt +
      (kGuardBattleLaneBottomPt - kGuardBattleLaneTopPt) * t;
  return GuardBattleMonsterSpec(
    index: index,
    kind: kind,
    spawnMs: kGuardSpawnOffsetsMs[index],
    speedPtPerSec: kind.speedPtPerSec,
    dodgeProb: kind.dodgeProb,
    hitsToKill: kind.hitsToKill,
    steal: steal,
    laneYPt: laneY,
    wobbleAmpPt: 4.0,
    wobbleFreqHz: 0.3,
    wobblePhaseRad: 0.0,
  );
}
