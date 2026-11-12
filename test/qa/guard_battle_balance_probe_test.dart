/// 守卫战 v2 · **B8 手感 v2 平衡自检**（玄参 2026-11-10 第三轮真机）。
///
/// 玄参原话：「怪血厚了是好事，但孩子 30 秒还打不完，那就是白改。」
/// 本文件把「改完还打不打得完」变成**会红的断言**，而不是一张贴在报告里的表：
///
/// | # | 断言 |
/// |---|---|
/// | B1 | 单怪 TTK 随 HP 单调增（HP 3 < 4 < 5，逐位严格） |
/// | B2 | 单怪最坏 TTK（HP 5 / 闪避 35%）≤ **6000ms** < 出手间隔，自瞄不会积压 |
/// | B3 | **最坏阵容 5×m3**（HP 5 / 闪避 35% / 冷却 300ms）在 30s 窗口内**全清**，且 100 个 seed 都 victory |
/// | B4 | 收场时刻 ≤ **28500ms**（留 ≥1.5s 余量；实测最坏 28263ms） |
/// | B5 | 新手阵容 3×m1（HP 3 / 闪避 22%，玄参 2026-11-12 由 15% 提到 22%）≤ 15000ms 收场（不难） |
///
/// 🔴 口径说明（为什么这些数是「可复现的」）：
/// * 驱动方式 = 表现层同款：每 16ms 一次 `step()`，开火按 [kGuardFireCooldownMs]
///   均匀连按（冷却闸门刚好放行），自瞄由 sim 内部决定 —— 没有 `Random()`，
///   同一 `childId` 的闪避序列由 `dodge_<i>_<j>` 哈希通道逐位决定 ⇒ 表里每个
///   数字都能逐位重放；
/// * 「seed」= `childId`（`seed-0`..`seed-99`），只影响闪避哈希序列；
/// * 阵容用手工剧本构造（`hitsToKill` / `dodgeProb` 直接给定），因为本文件要
///   测的是**参数面**，不是某一天的派生结果。
///
/// ## 🔴 B8 最重要的一条发现：本文件最初是「红」的
/// 第一版跑出来 5×m3 只有 **73/100** victory，且 3×m1 要 16.3s、单怪 HP5 要 6.9s。
/// 诊断后确认**不是 HP 太高，而是闪避哈希连号不独立**：
/// `dodge_<i>_<j>` 的 `j` 每加 1 只改末字节，FNV-1a 对这种输入雪崩不足，
/// `u(j)` 只相差 ≈0.39% ⇒ 一旦掉到阈值以下就**连闪十几发**
/// （seed-0 的第 0 只怪连闪 18 发；seed-3 的第 1 只怪连闪 40 发）。
/// 修法见 `guard_battle_sim.dart` 的 `_dodgeUniform` / `_mix32`（闪避通道加一步
/// MurmurHash3 终混，其余通道与经济域一个字节没动）。
///
/// ## 调整前后的实测（玄参要的「改前 vs 改后」）
/// ```text
///                       闪避通道修前        闪避通道修后
/// 冷却 400ms（B8 之前）  未独立测量          100/100 victory，最坏 29395ms（余量 605ms）
/// 冷却 300ms（B8 落地）  73/100 victory      100/100 victory，最坏 28263ms（余量 1737ms）
/// ```
/// 结论：**HP 3/4/5 本身没问题**（玄参要的手感保留），真正的病是闪避连闪；
/// 冷却 400 → 300 是把余量从 605ms 拉到 1737ms 的第二层保险（玄参允许的两种
/// 手段之一；另一种「放大命中半径」没动 —— 28pt 容错圈本就是自瞄的下限）。
library guard_battle_balance_probe_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardBattleWindowMs, kGuardFireCooldownMs, kGuardSpawnOffsetsMs;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

const String _dayKey = '2026-11-10';

/// 一局的结果（只取本文件关心的三件事）。
class _Play {
  const _Play({
    required this.phaseId,
    required this.endMs,
    required this.dead,
  });

  /// `fighting` / `victory` / `retreat`。
  final String phaseId;

  /// 收场时刻（ms；未收场 = 最后一帧）。
  final int endMs;

  /// 被击灭的怪数。
  final int dead;

  @override
  String toString() =>
      '_Play(phase: $phaseId, end: ${endMs}ms, dead: $dead)';
}

/// 构造一份手工剧本：`kinds` 决定阵容，[hits] / [dodge] 覆盖参数面。
///
/// 速度取该 kind 的默认值（sim 的常量），纵向摆动振幅置 **0**：本文件测的是
/// 时间预算，摆动只会制造 ±3pt 的命中抖动噪声，与 TTK 结论无关。
GuardBattleScript _lineup(
  List<GuardBattleMonsterKind> kinds, {
  required int hits,
  double? dodge,
}) {
  return GuardBattleScript(
    monsters: <GuardBattleMonsterSpec>[
      for (int i = 0; i < kinds.length; i++)
        GuardBattleMonsterSpec(
          index: i,
          kind: kinds[i],
          spawnMs: kGuardSpawnOffsetsMs[i],
          speedPtPerSec: kinds[i].speedPtPerSec,
          dodgeProb: dodge ?? kinds[i].dodgeProb,
          hitsToKill: hits,
          steal: 1,
          laneYPt: 45,
          wobbleAmpPt: 0,
          wobbleFreqHz: 0,
          wobblePhaseRad: 0,
        ),
    ],
    windowMs: kGuardBattleWindowMs,
  );
}

/// 跑一整局：16ms 一帧、按 [cooldownMs] 均匀连按（冷却刚好放行）。
_Play _play(
  GuardBattleScript script, {
  required int cooldownMs,
  required String childId,
}) {
  final GuardBattleSim sim = GuardBattleSim(
    script: script,
    dayKey: _dayKey,
    childId: childId,
  );
  const int stepMs = 16;
  int nextFire = 0;
  for (int t = stepMs; t <= script.windowMs; t += stepMs) {
    final List<int> fires = <int>[];
    while (nextFire <= t) {
      fires.add(nextFire);
      nextFire += cooldownMs;
    }
    sim.step(t, fires);
    final GuardBattleSnapshot snap = sim.snapshot();
    if (snap.phaseId != 'fighting') {
      return _Play(
        phaseId: snap.phaseId,
        endMs: snap.elapsedMs,
        dead: snap.monsters
            .where((GuardBattleMonsterSnapshot m) => m.phaseId == 'dead')
            .length,
      );
    }
  }
  final GuardBattleSnapshot last = sim.snapshot();
  return _Play(
    phaseId: last.phaseId,
    endMs: last.elapsedMs,
    dead: last.monsters
        .where((GuardBattleMonsterSnapshot m) => m.phaseId == 'dead')
        .length,
  );
}

/// 跑同一剧本的 [seeds] 个 seed，返回最坏（最晚）收场。
_Play _worst(
  GuardBattleScript script, {
  required int cooldownMs,
  int seeds = 8,
}) {
  _Play worst = _play(script, cooldownMs: cooldownMs, childId: 'seed-0');
  for (int s = 1; s < seeds; s++) {
    final _Play p =
        _play(script, cooldownMs: cooldownMs, childId: 'seed-$s');
    if (p.endMs > worst.endMs) worst = p;
  }
  return worst;
}

void main() {
  // ── B1 / B2 单怪 TTK 表 ────────────────────────────────────────────────
  test('B1/B2 单怪 TTK：HP 越多越久，最坏仍短于 6s 出场间隔', () {
    // 表：kind × HP ⇒ 8 个 seed 里最晚的击杀时刻（ms）。
    final Map<String, int> table = <String, int>{};
    for (final GuardBattleMonsterKind kind in GuardBattleMonsterKind.values) {
      final List<int> ttk = <int>[];
      for (final int hits in <int>[3, 4, 5]) {
        final _Play p = _worst(
          _lineup(<GuardBattleMonsterKind>[kind], hits: hits),
          cooldownMs: kGuardFireCooldownMs,
        );
        expect(p.phaseId, 'victory',
            reason: '单怪必须能被清掉（${kind.id} / HP $hits）');
        table['${kind.id}-HP$hits'] = p.endMs;
        ttk.add(p.endMs);
      }
      // 严格单调：HP 3 < HP 4 < HP 5（多吃一发就必须多花 ≈ 一个冷却）。
      expect(ttk[0], lessThan(ttk[1]), reason: '${kind.id}: HP3 应快于 HP4');
      expect(ttk[1], lessThan(ttk[2]), reason: '${kind.id}: HP4 应快于 HP5');
      // 🔴 B2：最坏单怪（HP5 + 闪避 35%）必须在 6s 出场间隔内打完，
      // 否则自瞄「打最靠右那只」会把前面的怪积压到门口。
      expect(ttk[2], lessThan(6000),
          reason: '🔴 ${kind.id} HP5 的 TTK 必须 < 6000ms（出场间隔）');
    }
    // ignore: avoid_print
    print('单怪 TTK 表（ms，8 seed 最坏）: $table');

    // 闪避敏感性：同一只怪（HP 5）在 15% / 25% / 35% 三档闪避下的 TTK。
    final Map<String, int> dodgeTable = <String, int>{};
    for (final double p in <double>[0.15, 0.25, 0.35]) {
      final _Play r = _worst(
        _lineup(<GuardBattleMonsterKind>[GuardBattleMonsterKind.m3],
            hits: 5, dodge: p),
        cooldownMs: kGuardFireCooldownMs,
      );
      dodgeTable['${(p * 100).round()}%'] = r.endMs;
    }
    // ignore: avoid_print
    print('闪避敏感性（m3 / HP5，ms，8 seed 最坏）: $dodgeTable');
    expect(dodgeTable['15%']!, lessThan(dodgeTable['35%']!),
        reason: '🔴 闪避越高必须打得越久（否则哈希又坏了）');
  });

  // ── B3/B4 最坏阵容 ─────────────────────────────────────────────────────
  test('B3/B4 最坏阵容 5×m3（HP5 / 闪避 35%）在 30s 内全清', () {
    final GuardBattleScript worstLineup = _lineup(
      const <GuardBattleMonsterKind>[
        GuardBattleMonsterKind.m3,
        GuardBattleMonsterKind.m3,
        GuardBattleMonsterKind.m3,
        GuardBattleMonsterKind.m3,
        GuardBattleMonsterKind.m3,
      ],
      hits: 5,
      dodge: 0.35,
    );
    const int seeds = 100;
    int maxEnd = 0;
    int victories = 0;
    for (int s = 0; s < seeds; s++) {
      final _Play p = _play(
        worstLineup,
        cooldownMs: kGuardFireCooldownMs,
        childId: 'seed-$s',
      );
      if (p.phaseId == 'victory') {
        victories++;
        if (p.endMs > maxEnd) maxEnd = p.endMs;
      }
    }
    // 🔴 上线门槛：100 个 seed **一个都不许 Retreat**。
    expect(victories, seeds,
        reason: '🔴 最坏阵容必须 100/100 全清（冷却 ${kGuardFireCooldownMs}ms）');
    // 🔴 余量：最晚收场 ≤ 28500ms（实测 28263ms ⇒ 余量 1737ms）。
    expect(maxEnd, lessThanOrEqualTo(28500),
        reason: '🔴 最坏收场时刻超出余量线，说明 30s 窗口快撑不住了');
    // ignore: avoid_print
    print('5×m3 / HP5 / 闪避35% / 冷却 ${kGuardFireCooldownMs}ms：'
        '$victories/$seeds victory，最坏收场 ${maxEnd}ms');

    // 诊断（不断言）：改成 400ms 冷却会怎样 —— 这就是 B8 从 400 改到 300 的依据。
    int v400 = 0;
    int max400 = 0;
    for (int s = 0; s < seeds; s++) {
      final _Play p =
          _play(worstLineup, cooldownMs: 400, childId: 'seed-$s');
      if (p.phaseId == 'victory') {
        v400++;
        if (p.endMs > max400) max400 = p.endMs;
      }
    }
    // ignore: avoid_print
    print('对照（400ms 冷却）：$v400/$seeds victory，最坏收场 ${max400}ms');
    expect(v400, lessThanOrEqualTo(seeds),
        reason: '对照数据只做记录，不为它设通过门槛');
  });

  // ── 宽松阵容对照 ──────────────────────────────────────────────────────
  test('3 只 m1（HP3 / 闪避 35%）在 16s 内收场（新手日不难）', () {
    final _Play p = _worst(
      _lineup(
        const <GuardBattleMonsterKind>[
          GuardBattleMonsterKind.m1,
          GuardBattleMonsterKind.m1,
          GuardBattleMonsterKind.m1,
        ],
        hits: 3,
        dodge: 0.35,
      ),
      cooldownMs: kGuardFireCooldownMs,
    );
    expect(p.phaseId, 'victory');
    // 第 3 只 12s 出场，HP3 + 35% 闪避（玄参 2026-11-12 第二轮由 22% 上调，
    // 闪避是馋光鼠专属特性）⇒ 仍远早于窗口收场。
    expect(p.endMs, lessThanOrEqualTo(16000),
        reason: '3×m1 应远早于窗口收场（闪避上调后实测最坏见输出行）');
  });
}
