/// 守卫战 v2 的**战斗纯模拟器**（零 Flutter 依赖、零 IO、🔴 零 `Random`，
/// 可 `dart test` 直跑重放）。
///
/// 真源：`docs/花园守卫_守卫战玩法_增量设计_v1.md` §4（战斗引擎设计）/ §5（领域接缝）。
///
/// ## 确定性模型：剧本（seed 派生）+ 步进（输入重放）
///
/// **核心原则：把「随机」全部前移到剧本派生，运行时零随机。**
///
/// ```text
/// 剧本 Script = f(dayKey, childId, kGuardBattleSalt)   ← 纯函数，同日同孩逐位相同
/// 战局 State  = g(Script, fireTimeline, elapsedMs)      ← 纯步进，同输入逐位相同
/// ```
///
/// * [fireTimeline]（开火时间线）= 孩子每次点开火钮的时刻（受 [kGuardFireCooldownMs]
///   冷却闸门）；**闪避判定也走确定性哈希**：第 `i` 只怪面对第 `j` 发锁定弹是否闪避 =
///   `deterministicUniform(dayKey, childId, salt: kGuardBattleSalt, channel: 'dodge_i_j')`
///   < 闪避概率 ⇒ 闪避（弹道偏移 + 怪物侧移跳，演出层职责，不改战局）。**不存在运行时掷骰**，
///   所以「同一 seed + 同一开火时间线」重放**逐位一致**（金测的根据，§8.1）。
/// * 弹道为**发射瞬间锁定当前最前（最靠右）存活怪**的自瞄直线 —— 孩子只负责「按」，
///   不负责「瞄」。命中判定 = 弹到达时与目标距离 ≤ [kGuardBulletHitRadius] **且**未触发闪避。
/// * 怪物轨迹 = 基准直线向右 + 由 `wobble_*` 通道派生的纵向摆动（振幅/频率/相位逐怪确定）；
///   闪避跳是叠加在其上的**演出层**侧移，不进入本模拟器的轨迹。
/// * 步长用调用方给的**真实毫秒差**而非帧数 —— 掉帧/高刷屏都不会让战局漂移；
///   确定性定义在「输入时间线」上，与帧率无关。
///
/// ## 🔴 冻结通道表（设计文档 §9.2-3：上线即冻结，B1 合入时登记于此）
///
/// | channel | 派生量 |
/// |---|---|
/// | `count` | 怪数 ∈ [kGuardMonsterCountMin, kGuardMonsterCountMax] |
/// | `kind_<i>` | 第 i 怪种类 ∈ {m1, m2, m3}（等概率三桶） |
/// | `offset_<i>` | 第 i 怪的纵向入场通道 ∈ [0,1) → 行走基准线 laneY |
/// | `wobble_amp_<i>` | 纵向摆动振幅（pt） |
/// | `wobble_freq_<i>` | 纵向摆动频率（Hz） |
/// | `wobble_phase_<i>` | 纵向摆动初相位 ∈ [0, 2π) |
/// | `steal_<i>` | 第 i 怪偷取值 ∈ [kGuardStealMin, kGuardStealMax] |
/// | `dodge_<i>_<j>` | 第 i 怪面对第 j 发锁定弹（j 从 0 计，按该怪被锁定次数）的闪避 u
///   （🔴 B8：本通道**额外过一步 MurmurHash3 终混**，见 [_dodgeUniform] ——
///   裸 FNV-1a 对「末字节只差 1」的连号输入会连闪十几发） |
/// | `lane_shift_n_<i>` | 第 i 怪换道次数 ∈ [kGuardLaneShiftCountMin, kGuardLaneShiftCountMax] |
/// | `lane_shift_t_<i>_<k>` | 第 i 怪第 k 次换道的起始进度 u（映射到 [0.25,0.45] / [0.55,0.80]） |
/// | `lane_shift_y_<i>_<k>` | 第 i 怪第 k 次换道的目标车道 y ∈ [laneTop, laneBottom] |
///
/// 🔴 `lane_shift_*` 是 **B8 追加**（玄参「怪要会换方位」）：只追加、不改旧通道，
/// 故 `count/kind/offset/wobble/steal/dodge` 的历史取值逐位不变。
///
/// 改任何一个通道名 = 让历史战局全部重掷；新增通道只能**追加**。
///
/// ## 状态机（§4.3）
/// * Fighting → **Victory**：**剧本里全部怪都已出场且全部被击灭**（B8 修正 ——
///   B7 及之前的口径是「已出场怪全灭」，导致杀 1 只就赢，玄参判为产品错误）；
/// * Fighting → **Retreat**：[kGuardBattleWindowMs] 到点，剩余怪撤退；
///   已执行的偷窃不回滚（待确认⑤：因为被偷额只在本模拟器内存累计，根本没有
///   中间落账可回滚）；
/// * **Abandoned** 不在本模拟器内：进程被杀 = 本对象随内存消失，零写库、零落账。
///   落账只发生在战斗打完（Victory/Retreat）后由表现层调
///   `GuardService.recordBattleTheft`（结束时一次写，§5.3 裁决 B）。
library guard_battle_sim;

import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';

// ── 冻结通道名（🔴 一经写入即冻结，见文件头通道表）─────────────────────────

/// 通道：怪物数量。
const String kGuardBattleChannelCount = 'count';

/// 通道前缀：第 i 怪种类（实际通道 = `kind_<i>`）。
const String kGuardBattleChannelKind = 'kind';

/// 通道前缀：第 i 怪纵向入场通道（实际通道 = `offset_<i>`）。
const String kGuardBattleChannelOffset = 'offset';

/// 通道前缀：第 i 怪摆动振幅（实际通道 = `wobble_amp_<i>`）。
const String kGuardBattleChannelWobbleAmp = 'wobble_amp';

/// 通道前缀：第 i 怪摆动频率（实际通道 = `wobble_freq_<i>`）。
const String kGuardBattleChannelWobbleFreq = 'wobble_freq';

/// 通道前缀：第 i 怪摆动相位（实际通道 = `wobble_phase_<i>`）。
const String kGuardBattleChannelWobblePhase = 'wobble_phase';

/// 通道前缀：第 i 怪偷取值（实际通道 = `steal_<i>`）。
const String kGuardBattleChannelSteal = 'steal';

/// 通道前缀：第 i 怪对第 j 发锁定弹的闪避判定（实际通道 = `dodge_<i>_<j>`）。
const String kGuardBattleChannelDodge = 'dodge';

/// 通道前缀：第 i 怪换道次数（实际通道 = `lane_shift_n_<i>`，B8 追加）。
const String kGuardBattleChannelLaneShiftCount = 'lane_shift_n';

/// 通道前缀：第 i 怪第 k 次换道的起始进度（实际通道 = `lane_shift_t_<i>_<k>`）。
const String kGuardBattleChannelLaneShiftFrac = 'lane_shift_t';

/// 通道前缀：第 i 怪第 k 次换道的目标车道（实际通道 = `lane_shift_y_<i>_<k>`）。
const String kGuardBattleChannelLaneShiftY = 'lane_shift_y';

// ── 战场几何（🔴 B2 裁定值，见交付报告；表现层只读不改，改动需过设计）──────
//
// B2 裁定（替代 B1 的临时值）：PRD §8 素材清单——「门口/战士位居右侧 1/4」，
// 怪物从左缘入场向右走，战士守在门口。故：
//  · 子弹从**枪口**（战士位左侧 20pt）出发，按目标在枪口的左侧 / 右侧
//    自动向左 / 向右直飞（自瞄，孩子只负责「按」）；
//  · 不再与怪入场点 x=0 重合 —— B1 报告 ⑦-2 指出的「怪刚入场即可被秒」由此消除
//    （子弹到左缘怪要走 ~0.87s，孩子有反应窗口）。

/// 怪物行程：从左缘入场点到门口。单位：pt（设计 §4.2「卡内可行程 ~330pt」，
/// 由它推出 13~17pt/s ⇒ 走完全程 19~25s）。
const double kGuardBattleFieldTravelPt = 330;

/// 战士位 x。单位：pt（≈ 行程的 85%，与素材「战士位居右侧 1/4」对齐）。
const double kGuardBattleSoldierXPt = 280;

/// 子弹出发点 x（枪口 = 战士位左侧 20pt）。单位：pt。
const double kGuardBattleBulletSpawnXPt = 260;

/// 怪物纵向入场通道范围下缘。单位：pt（卡内坐标系，表现层渲染用）。
const double kGuardBattleLaneTopPt = 10;

/// 怪物纵向入场通道范围上缘。单位：pt。
const double kGuardBattleLaneBottomPt = 80;

/// 纵向摆动振幅下限。单位：pt（摆动是演出丰富度，幅度压在命中容错圈内，
/// 保证「自瞄 + 容错圈」不吃技术）。
const double kGuardBattleWobbleAmpMinPt = 2;

/// 纵向摆动振幅上限。单位：pt。
const double kGuardBattleWobbleAmpMaxPt = 6;

/// 纵向摆动频率下限。单位：Hz。
const double kGuardBattleWobbleFreqMinHz = 0.2;

/// 纵向摆动频率上限。单位：Hz。
const double kGuardBattleWobbleFreqMaxHz = 0.5;

// ── 枚举 ─────────────────────────────────────────────────────────────────

/// 战局阶段（§4.3 状态机的模拟器内部分；Abandoned = 本对象被丢弃，无枚举值）。
enum GuardBattlePhase {
  /// 战斗中。
  fighting,

  /// 全灭（提前结束，剩余窗口不补怪）。
  victory,

  /// 到点撤退（已偷不回滚）。
  retreat;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardBattlePhase.fighting:
        return 'fighting';
      case GuardBattlePhase.victory:
        return 'victory';
      case GuardBattlePhase.retreat:
        return 'retreat';
    }
  }
}

/// 战局结束原因（快照 / 步进报告里区分「全灭」与「到点」）。
enum GuardBattleEndReason {
  /// 尚未结束。
  none,

  /// 全部已出场怪被击灭（提前结束）。
  allDead,

  /// [kGuardBattleWindowMs] 到点。
  windowExpired;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardBattleEndReason.none:
        return 'none';
      case GuardBattleEndReason.allDead:
        return 'all_dead';
      case GuardBattleEndReason.windowExpired:
        return 'window_expired';
    }
  }
}

/// 单只怪在快照里的相位。
enum GuardBattleMonsterPhase {
  /// 未出场（出怪时刻未到）。
  waiting,

  /// 行走中（从左缘向门口移动）。
  walking,

  /// 被击灭。
  dead,

  /// 到门口得手后退场（[GuardBattleMonsterSnapshot.stolen] 可为 0：
  /// 超出封顶额度的怪只演出退场、偷 0）。
  fled,

  /// 到点撤退（30s 窗口结束时的剩余怪）。
  retreated;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardBattleMonsterPhase.waiting:
        return 'waiting';
      case GuardBattleMonsterPhase.walking:
        return 'walking';
      case GuardBattleMonsterPhase.dead:
        return 'dead';
      case GuardBattleMonsterPhase.fled:
        return 'fled';
      case GuardBattleMonsterPhase.retreated:
        return 'retreated';
    }
  }
}

/// 怪物种类（m1 棕 / m2 绿 / m3 灰紫；线名冻结）。
enum GuardBattleMonsterKind {
  m1,
  m2,
  m3;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardBattleMonsterKind.m1:
        return 'm1';
      case GuardBattleMonsterKind.m2:
        return 'm2';
      case GuardBattleMonsterKind.m3:
        return 'm3';
    }
  }

  /// 行走速度（pt/s）。
  double get speedPtPerSec {
    switch (this) {
      case GuardBattleMonsterKind.m1:
        return kGuardMonsterSpeedM1;
      case GuardBattleMonsterKind.m2:
        return kGuardMonsterSpeedM2;
      case GuardBattleMonsterKind.m3:
        return kGuardMonsterSpeedM3;
    }
  }

  /// 闪避概率。
  double get dodgeProb {
    switch (this) {
      case GuardBattleMonsterKind.m1:
        return kGuardDodgeProbM1;
      case GuardBattleMonsterKind.m2:
        return kGuardDodgeProbM2;
      case GuardBattleMonsterKind.m3:
        return kGuardDodgeProbM3;
    }
  }

  /// 击杀所需命中数（无血条：累计命中即灭）。
  int get hitsToKill {
    switch (this) {
      case GuardBattleMonsterKind.m1:
        return kGuardMonsterHitsM1;
      case GuardBattleMonsterKind.m2:
        return kGuardMonsterHitsM2;
      case GuardBattleMonsterKind.m3:
        return kGuardMonsterHitsM3;
    }
  }
}

// ── 剧本（不可变，seed 派生，可 == 比较 / 可 JSON 序列化做金测）─────────────

/// 一次换道（B8：玄参「怪要会换方位」）。
///
/// 由 `lane_shift_t_<i>_<k>` / `lane_shift_y_<i>_<k>` 两条通道在**剧本派生时**
/// 一次性算成「绝对时刻 + 目标车道」，运行时零随机、零额外状态：
/// `_monsterYAt(spec, t)` 仍是 `t` 的纯函数。
class GuardLaneShift {
  const GuardLaneShift({
    required this.startMs,
    required this.targetLaneYPt,
  });

  /// 换道起始时刻（ms，战局时间轴；= 出场时刻 + 行程进度 × 行程时长）。
  final int startMs;

  /// 目标车道 y（pt；插值在 [kGuardLaneShiftMs] 内完成）。
  final double targetLaneYPt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardLaneShift &&
          other.startMs == startMs &&
          other.targetLaneYPt == targetLaneYPt;

  @override
  int get hashCode => Object.hash(startMs, targetLaneYPt);

  /// 序列化（金测 / 调试面板用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'startMs': startMs,
        'laneY': targetLaneYPt,
      };
}

/// 一只怪在剧本里的全部确定性参数（§4.4）。
class GuardBattleMonsterSpec {
  const GuardBattleMonsterSpec({
    required this.index,
    required this.kind,
    required this.spawnMs,
    required this.speedPtPerSec,
    required this.dodgeProb,
    required this.hitsToKill,
    required this.steal,
    required this.laneYPt,
    required this.wobbleAmpPt,
    required this.wobbleFreqHz,
    required this.wobblePhaseRad,
    this.laneShifts = const <GuardLaneShift>[],
  });

  /// 怪的序号 i（0-based；闪避通道 `dodge_<i>_<j>` 的 i）。
  final int index;

  /// 种类。
  final GuardBattleMonsterKind kind;

  /// 出场时刻（ms；来自 [kGuardSpawnOffsetsMs] 前 N 项）。
  final int spawnMs;

  /// 行走速度（pt/s）。
  final double speedPtPerSec;

  /// 闪避概率。
  final double dodgeProb;

  /// 击杀所需命中数。
  final int hitsToKill;

  /// 偷取值（☀；封顶在模拟器内裁：`min(steal, 剩余额度)`）。
  final int steal;

  /// 行走基准线 y（pt）。
  final double laneYPt;

  /// 纵向摆动振幅（pt）。
  final double wobbleAmpPt;

  /// 纵向摆动频率（Hz）。
  final double wobbleFreqHz;

  /// 纵向摆动初相位（rad）。
  final double wobblePhaseRad;

  /// 换道计划（B8；空 = 不换道，向后兼容旧剧本构造）。
  ///
  /// 🔴 只影响 `_monsterYAt` 的**车道基准**，摆动（wobble）照旧叠在上面；
  /// 换道不是闪避，**不影响命中判定**（自瞄按 y 现算，跟着怪走）。
  final List<GuardLaneShift> laneShifts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardBattleMonsterSpec &&
          other.index == index &&
          other.kind == kind &&
          other.spawnMs == spawnMs &&
          other.speedPtPerSec == speedPtPerSec &&
          other.dodgeProb == dodgeProb &&
          other.hitsToKill == hitsToKill &&
          other.steal == steal &&
          other.laneYPt == laneYPt &&
          other.wobbleAmpPt == wobbleAmpPt &&
          other.wobbleFreqHz == wobbleFreqHz &&
          other.wobblePhaseRad == wobblePhaseRad &&
          _laneShiftsEqual(other.laneShifts, laneShifts);

  @override
  int get hashCode => Object.hash(
      index,
      kind,
      spawnMs,
      speedPtPerSec,
      dodgeProb,
      hitsToKill,
      steal,
      laneYPt,
      wobbleAmpPt,
      wobbleFreqHz,
      wobblePhaseRad,
      Object.hashAll(laneShifts));

  /// 序列化（金测 / 调试面板用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'kind': kind.id,
        'spawnMs': spawnMs,
        'speed': speedPtPerSec,
        'dodgeProb': dodgeProb,
        'hits': hitsToKill,
        'steal': steal,
        'laneY': laneYPt,
        'wobbleAmp': wobbleAmpPt,
        'wobbleFreq': wobbleFreqHz,
        'wobblePhase': wobblePhaseRad,
        'laneShifts': <Object?>[
          for (final GuardLaneShift s in laneShifts) s.toJson(),
        ],
      };
}

/// 剧本（不可变，seed 派生；§4.4）。
class GuardBattleScript {
  const GuardBattleScript({
    required this.monsters,
    required this.windowMs,
  });

  /// 怪物阵容（数量 3~5：kind/出场 t/速度/闪避 p/hits/steal/轨迹通道）。
  final List<GuardBattleMonsterSpec> monsters;

  /// 战斗窗口（= [kGuardBattleWindowMs]）。
  final int windowMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardBattleScript &&
          other.windowMs == windowMs &&
          _listEquals(other.monsters, monsters);

  @override
  int get hashCode => Object.hash(windowMs, Object.hashAll(monsters));

  /// 序列化（金测 / 调试面板用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'monsters': <Object?>[for (final GuardBattleMonsterSpec m in monsters) m.toJson()],
        'windowMs': windowMs,
      };
}

/// 【纯函数】确定性派生战斗剧本（§4.1：`Script = f(dayKey, childId, salt)`）。
///
/// 同一 `dayKey + childId` 恒得同一份剧本（怪数 / 种类 / 出场表 / 速度 / 闪避 /
/// HP / 偷取值 / 轨迹通道）—— 「继续守卫」同 seed 重跑同一份剧本的前提。
/// **绝无 `Random`**、不读时钟、不读余额。
GuardBattleScript deriveGuardBattleScript({
  required String dayKey,
  required String childId,
}) {
  // 怪数：通道 count 落桶到 [min, max] 的闭区间整数。
  final double uCount =
      _uniform(dayKey: dayKey, childId: childId, channel: kGuardBattleChannelCount);
  final int count = _intInRange(
    uCount,
    kGuardMonsterCountMin,
    kGuardMonsterCountMax,
  );

  final List<GuardBattleMonsterSpec> monsters = <GuardBattleMonsterSpec>[];
  for (int i = 0; i < count; i++) {
    final double uKind = _uniform(
        dayKey: dayKey, childId: childId, channel: '${kGuardBattleChannelKind}_$i');
    final GuardBattleMonsterKind kind = _kindOf(uKind);
    // 出场时刻：出怪时刻表取前 N 项（防御分支：表短于 N 时按 6s 间隔顺延）。
    final int spawnMs = i < kGuardSpawnOffsetsMs.length
        ? kGuardSpawnOffsetsMs[i]
        : kGuardSpawnOffsetsMs.last + 6000 * (i - kGuardSpawnOffsetsMs.length + 1);
    final double uOffset = _uniform(
        dayKey: dayKey, childId: childId, channel: '${kGuardBattleChannelOffset}_$i');
    final double uAmp = _uniform(
        dayKey: dayKey,
        childId: childId,
        channel: '${kGuardBattleChannelWobbleAmp}_$i');
    final double uFreq = _uniform(
        dayKey: dayKey,
        childId: childId,
        channel: '${kGuardBattleChannelWobbleFreq}_$i');
    final double uPhase = _uniform(
        dayKey: dayKey,
        childId: childId,
        channel: '${kGuardBattleChannelWobblePhase}_$i');
    final double uSteal = _uniform(
        dayKey: dayKey, childId: childId, channel: '${kGuardBattleChannelSteal}_$i');
    final double speed = kind.speedPtPerSec;
    final List<GuardLaneShift> laneShifts = _deriveLaneShifts(
      dayKey: dayKey,
      childId: childId,
      index: i,
      spawnMs: spawnMs,
      speedPtPerSec: speed,
    );
    monsters.add(GuardBattleMonsterSpec(
      index: i,
      kind: kind,
      spawnMs: spawnMs,
      speedPtPerSec: speed,
      dodgeProb: kind.dodgeProb,
      hitsToKill: kind.hitsToKill,
      steal: _intInRange(uSteal, kGuardStealMin, kGuardStealMax),
      laneYPt: kGuardBattleLaneTopPt +
          (kGuardBattleLaneBottomPt - kGuardBattleLaneTopPt) * uOffset,
      wobbleAmpPt: kGuardBattleWobbleAmpMinPt +
          (kGuardBattleWobbleAmpMaxPt - kGuardBattleWobbleAmpMinPt) * uAmp,
      wobbleFreqHz: kGuardBattleWobbleFreqMinHz +
          (kGuardBattleWobbleFreqMaxHz - kGuardBattleWobbleFreqMinHz) * uFreq,
      wobblePhaseRad: 2 * math.pi * uPhase,
      laneShifts: laneShifts,
    ));
  }
  return GuardBattleScript(monsters: monsters, windowMs: kGuardBattleWindowMs);
}

/// 【纯函数】派生第 [index] 只怪的换道计划（B8）。
///
/// 通道（见文件头通道表）：
/// * `lane_shift_n_<i>` ⇒ 换道次数 1~2；
/// * `lane_shift_t_<i>_<k>` ⇒ 第 k 次换道发生在行程的哪个进度（第 1 次
///   [kGuardLaneShiftFirstFracMin, kGuardLaneShiftFirstFracMax]，第 2 次
///   [kGuardLaneShiftSecondFracMin, kGuardLaneShiftSecondFracMax]，两段**不重叠**
///   ⇒ 两次 400ms 插值永不互相踩）；
/// * `lane_shift_y_<i>_<k>` ⇒ 目标车道 y（落在
///   [kGuardBattleLaneTopPt, kGuardBattleLaneBottomPt] 内 ⇒ 换道后仍在同一条
///   「水平带」里，不会走到房顶或被倒计时细线裁掉）。
///
/// 换道时刻 = `spawnMs + frac × (门口时刻 − spawnMs)`，即按**行程比例**而不是
/// 绝对秒数 —— 走得快的怪换道也早，节奏一致。
List<GuardLaneShift> _deriveLaneShifts({
  required String dayKey,
  required String childId,
  required int index,
  required int spawnMs,
  required double speedPtPerSec,
}) {
  final double uCount = _uniform(
    dayKey: dayKey,
    childId: childId,
    channel: '${kGuardBattleChannelLaneShiftCount}_$index',
  );
  final int n = _intInRange(
    uCount,
    kGuardLaneShiftCountMin,
    kGuardLaneShiftCountMax,
  );
  if (n <= 0) return const <GuardLaneShift>[];
  final double travelMs = kGuardBattleFieldTravelPt / speedPtPerSec * 1000.0;
  final List<GuardLaneShift> shifts = <GuardLaneShift>[];
  for (int k = 0; k < n; k++) {
    final double uFrac = _uniform(
      dayKey: dayKey,
      childId: childId,
      channel: '${kGuardBattleChannelLaneShiftFrac}_${index}_$k',
    );
    final double uY = _uniform(
      dayKey: dayKey,
      childId: childId,
      channel: '${kGuardBattleChannelLaneShiftY}_${index}_$k',
    );
    final double frac = k == 0
        ? kGuardLaneShiftFirstFracMin +
            (kGuardLaneShiftFirstFracMax - kGuardLaneShiftFirstFracMin) * uFrac
        : kGuardLaneShiftSecondFracMin +
            (kGuardLaneShiftSecondFracMax - kGuardLaneShiftSecondFracMin) *
                uFrac;
    shifts.add(GuardLaneShift(
      startMs: spawnMs + (travelMs * frac).round(),
      targetLaneYPt: kGuardBattleLaneTopPt +
          (kGuardBattleLaneBottomPt - kGuardBattleLaneTopPt) * uY,
    ));
  }
  return List<GuardLaneShift>.unmodifiable(shifts);
}

// ── 演出事件与步进报告 ───────────────────────────────────────────────────

/// 演出事件类型（模拟器 → 表现层的回调素材；§4.4「供 widget 播粒子/闪白」）。
enum GuardBattleEventType {
  /// 怪物入场。
  spawn,

  /// 开火被受理（已过冷却闸门；`targetIndex` = -1 表示当时场上无怪，子弹不发）。
  fireGranted,

  /// 开火被冷却闸门拦下（表现层可给「还没充好」抖动反馈）。
  fireDropped,

  /// 命中（未击灭；表现层播受击闪白）。
  hit,

  /// 闪避（白打一发；表现层播怪物侧移跳）。
  dodge,

  /// 击灭。
  kill,

  /// 到门口退场（`amount` = 实际偷走 ☀，可为 0：封顶额度用尽的怪只演出退场）。
  theft,

  /// 到点撤退。
  retreat,

  /// 子弹落空（目标已退场 / 偏离容错圈）。
  fizzle,
}

/// 一条演出事件（不可变）。
class GuardBattleEvent {
  const GuardBattleEvent({
    required this.type,
    required this.tMs,
    this.monsterIndex = -1,
    this.bulletIndex = -1,
    this.amount = 0,
  });

  /// 事件类型。
  final GuardBattleEventType type;

  /// 事件发生时刻（ms，战局时间轴）。
  final int tMs;

  /// 相关怪物序号（无关 = -1）。
  final int monsterIndex;

  /// 相关子弹序号（无关 = -1）。
  final int bulletIndex;

  /// 数额（theft = 偷走 ☀；其它事件 = 0）。
  final int amount;

  @override
  String toString() =>
      'GuardBattleEvent(${type.name}, t=$tMs, monster=$monsterIndex, '
      'bullet=$bulletIndex, amount=$amount)';
}

/// [GuardBattleSim.step] 的返回值：本步产生的演出事件 + 结束原因。
class GuardBattleStepReport {
  const GuardBattleStepReport({
    required this.events,
    required this.endReason,
  });

  /// 本步产生的演出事件（时间升序）。
  final List<GuardBattleEvent> events;

  /// 本步是否打完了战斗（victory / retreat）；`none` = 还没打完。
  final GuardBattleEndReason endReason;

  /// 是否在本步结束。
  bool get ended => endReason != GuardBattleEndReason.none;
}

// ── 快照（表现层只读渲染；JSON 序列化 = 金测素材）───────────────────────────

/// 快照里一只怪的渲染状态。
class GuardBattleMonsterSnapshot {
  const GuardBattleMonsterSnapshot({
    required this.index,
    required this.kindId,
    required this.spawnMs,
    required this.x,
    required this.y,
    required this.phaseId,
    required this.hitsTaken,
    required this.stolen,
  });

  /// 怪的序号。
  final int index;

  /// 种类线名（m1/m2/m3）。
  final String kindId;

  /// 出场时刻（ms；全灭提前结束时用它判定「被取消出场」的怪）。
  final int spawnMs;

  /// 当前 x（pt）。
  final double x;

  /// 当前 y（pt）。
  final double y;

  /// 相位线名。
  final String phaseId;

  /// 已被命中次数。
  final int hitsTaken;

  /// 实际偷走的 ☀（退场后才有意义）。
  final int stolen;

  /// 序列化（位置取 2 位小数 —— 金测的「逐字符相同」口径）。
  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'kind': kindId,
        'spawnMs': spawnMs,
        'x': _round2(x),
        'y': _round2(y),
        'phase': phaseId,
        'hits': hitsTaken,
        'stolen': stolen,
      };
}

/// 快照里一发在飞子弹的渲染状态。
class GuardBattleBulletSnapshot {
  const GuardBattleBulletSnapshot({
    required this.index,
    required this.targetIndex,
    required this.x,
    required this.y,
  });

  /// 子弹序号（全局递增）。
  final int index;

  /// 锁定的目标怪序号。
  final int targetIndex;

  /// 当前 x（pt）。
  final double x;

  /// 当前 y（pt）。
  final double y;

  /// 序列化（位置取 2 位小数）。
  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'target': targetIndex,
        'x': _round2(x),
        'y': _round2(y),
      };
}

/// 战局快照（§4.4：各怪 (x,y,状态) / 子弹列表 / 累计被偷 / 剩余时间）。
class GuardBattleSnapshot {
  const GuardBattleSnapshot({
    required this.elapsedMs,
    required this.phaseId,
    required this.endReasonId,
    required this.stolenSun,
    required this.stealCapLeft,
    required this.remainingWindowMs,
    required this.monsters,
    required this.bullets,
  });

  /// 战局时间（ms）。
  final int elapsedMs;

  /// 阶段线名（fighting / victory / retreat）。
  final String phaseId;

  /// 结束原因线名（none / all_dead / window_expired）。
  final String endReasonId;

  /// 累计被偷（实际落账口径，已按封顶裁过）。
  final int stolenSun;

  /// 剩余偷窃封顶额度。
  final int stealCapLeft;

  /// 剩余窗口（ms；负值钳到 0）。
  final int remainingWindowMs;

  /// 各怪状态。
  final List<GuardBattleMonsterSnapshot> monsters;

  /// 在飞子弹。
  final List<GuardBattleBulletSnapshot> bullets;

  /// 序列化（金测：同一 seed + 同一开火时间线 ⇒ 逐字符相同）。
  Map<String, Object?> toJson() => <String, Object?>{
        'elapsedMs': elapsedMs,
        'phase': phaseId,
        'endReason': endReasonId,
        'stolenSun': stolenSun,
        'stealCapLeft': stealCapLeft,
        'remainingWindowMs': remainingWindowMs,
        'monsters': <Object?>[for (final GuardBattleMonsterSnapshot m in monsters) m.toJson()],
        'bullets': <Object?>[for (final GuardBattleBulletSnapshot b in bullets) b.toJson()],
      };

  /// JSON 字符串（金测断言「逐字符相等」的素材）。
  String toJsonString() => jsonEncode(toJson());
}

// ── 模拟器本体 ───────────────────────────────────────────────────────────

/// 纯模拟器：UI 层只喂时间与开火事件，读回快照渲染（§4.4）。
///
/// 同一 `script + dayKey + childId + 开火时间线` ⇒ 每一步的快照**逐位一致**。
/// 实例本身**可变**（承载战局），但全部状态只由 `step()` 的入参决定 ——
/// 重放 = 新建实例 + 重喂同一份时间线。
class GuardBattleSim {
  /// [script] 由 [deriveGuardBattleScript] 派生；[dayKey] / [childId] 只用于
  /// 闪避通道（`dodge_<i>_<j>`）的确定性哈希。
  GuardBattleSim({
    required this.script,
    required this.dayKey,
    required this.childId,
  })  : _monsters = <_MonsterRt>[
          for (final GuardBattleMonsterSpec spec in script.monsters)
            _MonsterRt(spec),
        ],
        _stealCapLeft = kGuardStealDailyCap;

  /// 本场剧本（不可变）。
  final GuardBattleScript script;

  /// 战局归属的自然日（闪避通道派生入参）。
  final String dayKey;

  /// 战局归属的孩子（闪避通道派生入参）。
  final String childId;

  final List<_MonsterRt> _monsters;
  final List<_BulletRt> _bullets = <_BulletRt>[];

  int _elapsedMs = 0;
  GuardBattlePhase _phase = GuardBattlePhase.fighting;
  GuardBattleEndReason _endReason = GuardBattleEndReason.none;
  int _frozenMs = -1; // 战局结束时刻（之后 step 一律冻结在它，快照逐位不变）
  int _stolenSun = 0;
  int _stealCapLeft;
  int? _lastFireMs; // null = 从没开过火（首发起火恒过闸门；不用哨兵 int 防 64 位溢出）
  int _bulletSeq = 0;

  /// 当前阶段。
  GuardBattlePhase get phase => _phase;

  /// 结束原因。
  GuardBattleEndReason get endReason => _endReason;

  /// 战局时间（ms）。
  int get elapsedMs => _elapsedMs;

  /// 累计被偷（实际落账口径，已按封顶裁过）。
  int get stolenSun => _stolenSun;

  /// 是否打完（victory / retreat）。Abandoned 不经过本方法 —— 进程被杀时
  /// 本对象直接被丢弃（零写库由「根本没有持久化」保证）。
  bool get isOver => _phase != GuardBattlePhase.fighting;

  /// 推进到 [elapsedMs]，处理其间 [newFireEventsMs] 的开火（含冷却闸门）。
  ///
  /// * [newFireEventsMs] = **自上一次 step 以来新发生的**开火请求时刻（ms，
  ///   战局时间轴；调用方保证每个时刻只提交一次；乱序入参会被升序整理）。
  /// * 事件按时间升序与**固定优先级**处理（spawn < fire < 弹达 < 到门口），
  ///   同毫秒并列时低优先级先处理 —— 这是确定性的组成部分，不许改。
  /// * 返回本步产生的演出事件；[elapsedMs] < 当前战局时间时按当前时间钳制
  ///   （防御分支，防表现层喂负增量）。
  GuardBattleStepReport step(int elapsedMs, List<int> newFireEventsMs) {
    final List<GuardBattleEvent> events = <GuardBattleEvent>[];
    if (elapsedMs < _elapsedMs) elapsedMs = _elapsedMs;
    // 处理视界：战局已收场 ⇒ 只受理时间轴不晚于收场时刻的**迟到开火**（金测
    // 分段无关性的关键：同一份 fireTimeline 无论按什么粒度分批提交，事件都按
    // 绝对时刻进同一根时间排序队列；收场之后的开火一律视作「对空放枪」被视界
    // 挡在战局之外）。迟到的开火只会落到「场上无怪」→ 受理但不发弹，战局不变。
    final List<int> fires = List<int>.of(newFireEventsMs)..sort();
    int fireIdx = 0;
    while (true) {
      final int horizon =
          _phase == GuardBattlePhase.fighting ? elapsedMs : _frozenMs;
      final _NextEvent? next = _nextEvent(fires, fireIdx, horizon);
      if (next == null) break;
      switch (next.kind) {
        case 0:
          _processSpawn(next.index, events);
          break;
        case 1:
          _processFire(fires[fireIdx], events);
          fireIdx++;
          break;
        case 2:
          _processBulletArrival(next.index, events);
          break;
        default:
          _processDoor(next.index, events);
          break;
      }
    }
    if (_phase == GuardBattlePhase.fighting) {
      _elapsedMs = elapsedMs;
      _refreshPositions(elapsedMs);
      if (_elapsedMs >= script.windowMs) {
        _retreatAll(events);
      }
    } else {
      // 战局已收场（本步内打完，或之前已打完只补处理了迟到开火）：
      // 战局时间冻结在结束时刻，快照逐位不变（「已偷不回滚」的快照面体现）。
      _elapsedMs = _frozenMs;
      _refreshPositions(_frozenMs);
    }
    return GuardBattleStepReport(
      events: List<GuardBattleEvent>.unmodifiable(events),
      endReason: _endReason,
    );
  }

  /// 当前快照。
  GuardBattleSnapshot snapshot() {
    _refreshPositions(_elapsedMs);
    final int remaining = script.windowMs - _elapsedMs;
    return GuardBattleSnapshot(
      elapsedMs: _elapsedMs,
      phaseId: _phase.id,
      endReasonId: _endReason.id,
      stolenSun: _stolenSun,
      stealCapLeft: _stealCapLeft,
      remainingWindowMs: remaining > 0 ? remaining : 0,
      monsters: <GuardBattleMonsterSnapshot>[
        for (final _MonsterRt m in _monsters)
          GuardBattleMonsterSnapshot(
            index: m.spec.index,
            kindId: m.spec.kind.id,
            spawnMs: m.spec.spawnMs,
            x: m.x,
            y: m.y,
            phaseId: m.phase.id,
            hitsTaken: m.hitsTaken,
            stolen: m.stolen,
          ),
      ],
      bullets: <GuardBattleBulletSnapshot>[
        for (final _BulletRt b in _bullets)
          if (!b.resolved)
            GuardBattleBulletSnapshot(
              index: b.index,
              targetIndex: b.targetIndex,
              x: b.x,
              y: b.aimY,
            ),
      ],
    );
  }

  // ── 内部：事件调度 ─────────────────────────────────────────────────────

  /// 找下一个 ≤ [elapsedMs] 的事件。kind：0 = 出场 / 1 = 开火 / 2 = 弹达 /
  /// 3 = 到门口。同毫秒并列按 kind 升序（文件头「固定优先级」）。
  _NextEvent? _nextEvent(List<int> fires, int fireIdx, int elapsedMs) {
    double bestT = double.infinity;
    int bestKind = -1;
    int bestIdx = -1;
    void consider(double t, int kind, int idx) {
      if (t > elapsedMs) return;
      if (t < bestT || (t == bestT && kind < bestKind)) {
        bestT = t;
        bestKind = kind;
        bestIdx = idx;
      }
    }

    for (int i = 0; i < _monsters.length; i++) {
      final _MonsterRt m = _monsters[i];
      switch (m.phase) {
        case GuardBattleMonsterPhase.waiting:
          consider(m.spec.spawnMs.toDouble(), 0, i);
          break;
        case GuardBattleMonsterPhase.walking:
          consider(_doorMsOf(m.spec), 3, i);
          break;
        case GuardBattleMonsterPhase.dead:
        case GuardBattleMonsterPhase.fled:
        case GuardBattleMonsterPhase.retreated:
          break;
      }
    }
    if (fireIdx < fires.length) consider(fires[fireIdx].toDouble(), 1, fireIdx);
    for (int b = 0; b < _bullets.length; b++) {
      if (!_bullets[b].resolved) consider(_bullets[b].arrivalMs, 2, b);
    }
    if (bestKind < 0) return null;
    return _NextEvent(bestT, bestKind, bestIdx);
  }

  void _processSpawn(int index, List<GuardBattleEvent> events) {
    final _MonsterRt m = _monsters[index];
    m.phase = GuardBattleMonsterPhase.walking;
    m.x = 0;
    m.y = m.spec.laneYPt;
    events.add(GuardBattleEvent(
      type: GuardBattleEventType.spawn,
      tMs: m.spec.spawnMs,
      monsterIndex: index,
    ));
  }

  void _processFire(int tMs, List<GuardBattleEvent> events) {
    final int? last = _lastFireMs;
    if (last != null && tMs - last < kGuardFireCooldownMs) {
      // 冷却闸门：拦下（表现层可给「还没充好」反馈）。闸门时刻**不**前移 ——
      // 拦下的连点不应重置冷却窗口。
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.fireDropped,
        tMs: tMs,
      ));
      return;
    }
    _lastFireMs = tMs;
    // 自瞄：锁定当前最前（最靠右）**行走中**怪；并列取序号小者（确定性）。
    int target = -1;
    double targetX = -1;
    for (int i = 0; i < _monsters.length; i++) {
      if (_monsters[i].phase != GuardBattleMonsterPhase.walking) continue;
      final double x = _monsterXAt(_monsters[i].spec, tMs.toDouble());
      if (x > targetX) {
        targetX = x;
        target = i;
      }
    }
    if (target < 0) {
      // 场上无怪：受理开火但不发弹（空放也吃冷却 —— 口径简单且防刷）。
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.fireGranted,
        tMs: tMs,
        monsterIndex: -1,
      ));
      return;
    }
    final _MonsterRt m = _monsters[target];
    final double aimX = targetX;
    final double aimY = _monsterYAt(m.spec, tMs.toDouble());
    // B2 裁定：枪口在 260，目标可在枪口左侧（多数时刻）或右侧（将到门口）——
    // 自瞄直线按目标方位自动定向，弹达时刻 = 发射时刻 + 距离 / 弹速（ms）。
    final double dir = aimX >= kGuardBattleBulletSpawnXPt ? 1.0 : -1.0;
    final double arrivalMs = tMs +
        (aimX - kGuardBattleBulletSpawnXPt).abs() / kGuardBulletSpeed * 1000.0;
    final int j = m.lockedCount;
    m.lockedCount++;
    _bullets.add(_BulletRt(
      index: _bulletSeq++,
      targetIndex: target,
      fireMs: tMs,
      arrivalMs: arrivalMs,
      aimX: aimX,
      aimY: aimY,
      dodgeSeq: j,
      dir: dir,
    ));
    events.add(GuardBattleEvent(
      type: GuardBattleEventType.fireGranted,
      tMs: tMs,
      monsterIndex: target,
      bulletIndex: _bulletSeq - 1,
    ));
  }

  void _processBulletArrival(int bulletIndex, List<GuardBattleEvent> events) {
    final _BulletRt b = _bullets[bulletIndex];
    b.resolved = true;
    final _MonsterRt m = _monsters[b.targetIndex];
    if (m.phase != GuardBattleMonsterPhase.walking) {
      // 目标已退场 / 已灭 / 已撤退：落空。
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.fizzle,
        tMs: b.arrivalMs.round(),
        monsterIndex: b.targetIndex,
        bulletIndex: b.index,
      ));
      return;
    }
    final double tArr = b.arrivalMs;
    // 命中判定：弹到达时与目标距离 ≤ 容错圈（自瞄前提下这是容错，不是难度）。
    final double dx = _monsterXAt(m.spec, tArr) - b.aimX;
    final double dy = _monsterYAt(m.spec, tArr) - b.aimY;
    final double dist = math.sqrt(dx * dx + dy * dy);
    if (dist > kGuardBulletHitRadius) {
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.fizzle,
        tMs: tArr.round(),
        monsterIndex: b.targetIndex,
        bulletIndex: b.index,
      ));
      return;
    }
    // 闪避判定（确定性哈希通道 dodge_<i>_<j>，见文件头通道表）。
    //
    // 🔴 B8 修正（**不是调参，是修 bug**）：这里必须用 [_dodgeUniform] 而不是
    // 裸 [_uniform]。原因见 [_mix32] 的注释 —— FNV-1a 对「末字节只差 1」的输入
    // （`dodge_1_3` → `dodge_1_4`）雪崩不足，连号 u 只相差 ≈0.39% ⇒ 一旦跌到
    // 阈值以下就会**连续十几发全部闪避**（实测 seed-3：m1 连闪 40 发 ≈ 12s）。
    // 那种连闪在真机上就是「怪打不死」，20 个 seed 里 4~5 局打不完 30s。
    final double u = _dodgeUniform(
      dayKey: dayKey,
      childId: childId,
      monsterIndex: m.spec.index,
      dodgeSeq: b.dodgeSeq,
    );
    if (u < m.spec.dodgeProb) {
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.dodge,
        tMs: tArr.round(),
        monsterIndex: b.targetIndex,
        bulletIndex: b.index,
      ));
      return;
    }
    // 命中：累计命中数即灭（无血条，待确认④）。
    m.hitsTaken++;
    if (m.hitsTaken >= m.spec.hitsToKill) {
      m.phase = GuardBattleMonsterPhase.dead;
      // 冻结在被击灭时刻的位置（纯函数）：死亡怪不再跟随刷新节奏变化，
      // 否则「快照里尸体的位置」会取决于表现层的刷新调度（确定性破口）。
      m.x = _monsterXAt(m.spec, tArr);
      m.y = _monsterYAt(m.spec, tArr);
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.kill,
        tMs: tArr.round(),
        monsterIndex: b.targetIndex,
        bulletIndex: b.index,
      ));
      _checkVictory(tArr.round());
    } else {
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.hit,
        tMs: tArr.round(),
        monsterIndex: b.targetIndex,
        bulletIndex: b.index,
      ));
    }
  }

  void _processDoor(int index, List<GuardBattleEvent> events) {
    final _MonsterRt m = _monsters[index];
    m.phase = GuardBattleMonsterPhase.fled;
    // 冻结在门口（表现层播退场动画的锚点；不冻结会停留在最后一次刷新位）。
    final double doorMs = _doorMsOf(m.spec);
    m.x = _monsterXAt(m.spec, doorMs);
    m.y = _monsterYAt(m.spec, doorMs);
    // 封顶：逐怪取 min(seed 值, 剩余额度)，超出额度的怪到门口只演出退场、偷 0。
    final int actual = m.spec.steal < _stealCapLeft ? m.spec.steal : _stealCapLeft;
    if (actual > 0) {
      _stealCapLeft -= actual;
      _stolenSun += actual;
      m.stolen = actual;
    }
    events.add(GuardBattleEvent(
      type: GuardBattleEventType.theft,
      tMs: _doorMsOf(m.spec).round(),
      monsterIndex: index,
      amount: actual,
    ));
  }

  /// 全灭判定：**剧本里全部怪都已出场且全部被击灭** ⇒ 提前结束。
  ///
  /// 🔴 口径修正（B8，玄参真机判定「杀 1 只就赢」是产品错误）：
  /// 旧口径是「**已出场**怪全灭即提前收场（待出场怪取消出场）」—— 结果是打死
  /// 第 1 只时后面的怪还没出场，`waiting` 被 `continue` 跳过 ⇒ 立刻判胜。
  /// 新口径要求 `waiting` 也算「没死」⇒ 必须等最后一只按
  /// [kGuardSpawnOffsetsMs] 出场、并被击灭，才可能 Victory。
  /// 到 [kGuardBattleWindowMs] 仍未清完 ⇒ [GuardBattleEndReason.windowExpired]
  /// 走 Retreat（语义不变）。
  ///
  /// 本函数是**单点**：剧本派生与轨迹不受影响。
  void _checkVictory(int atMs) {
    for (final _MonsterRt m in _monsters) {
      // waiting（还没出场）/ walking / fled / retreated 一律「没死」⇒ 不算全灭。
      if (m.phase != GuardBattleMonsterPhase.dead) return;
    }
    _phase = GuardBattlePhase.victory;
    _endReason = GuardBattleEndReason.allDead;
    _frozenMs = atMs;
    _clearBullets();
  }

  void _retreatAll(List<GuardBattleEvent> events) {
    for (final _MonsterRt m in _monsters) {
      if (m.phase != GuardBattleMonsterPhase.walking) continue;
      m.phase = GuardBattleMonsterPhase.retreated;
      // 冻结在窗口到点时刻的位置（纯函数，理由同死亡冻结）。
      m.x = _monsterXAt(m.spec, script.windowMs.toDouble());
      m.y = _monsterYAt(m.spec, script.windowMs.toDouble());
      events.add(GuardBattleEvent(
        type: GuardBattleEventType.retreat,
        tMs: script.windowMs,
        monsterIndex: m.spec.index,
      ));
    }
    _phase = GuardBattlePhase.retreat;
    _endReason = GuardBattleEndReason.windowExpired;
    _frozenMs = script.windowMs;
    _clearBullets();
  }

  // ── 内部：轨迹（位置是时间的纯函数 —— 确定性的根）───────────────────────

  /// 怪在 [tMs] 的 x（直线向右，钳到门口）。
  double _monsterXAt(GuardBattleMonsterSpec spec, double tMs) {
    final double raw = spec.speedPtPerSec * (tMs - spec.spawnMs) / 1000.0;
    if (raw < 0) return 0;
    return raw > kGuardBattleFieldTravelPt ? kGuardBattleFieldTravelPt : raw;
  }

  /// 怪在 [tMs] 的 y（基准车道 + 确定性纵向摆动）。
  ///
  /// B8：基准车道不再是常量 —— 依次套用 [GuardBattleMonsterSpec.laneShifts]
  /// （每次在 [kGuardLaneShiftMs] 内用 smoothstep 从当前车道滑到目标车道）。
  /// 全部输入来自剧本 ⇒ 仍是 `t` 的纯函数，重放逐位一致。
  double _monsterYAt(GuardBattleMonsterSpec spec, double tMs) {
    final double tSec = (tMs - spec.spawnMs) / 1000.0;
    return _laneYAt(spec, tMs) +
        spec.wobbleAmpPt *
            math.sin(2 * math.pi * spec.wobbleFreqHz * tSec + spec.wobblePhaseRad);
  }

  /// 怪在 [tMs] 的车道基准 y（含换道插值）。
  ///
  /// 逐次套用换道计划：
  /// * 还没开始（`d ≤ 0`）⇒ 停在上一条车道上，后面的换道也不再生效；
  /// * 已结束（`d ≥ 1`）⇒ 车道直接置为目标值，继续看下一次；
  /// * 正在换道 ⇒ smoothstep `e = d²(3−2d)` 插值后**立即返回**（一次只插一段，
  ///   两次换道的进度区间不重叠 ⇒ 不会两次插值叠加）。
  double _laneYAt(GuardBattleMonsterSpec spec, double tMs) {
    double lane = spec.laneYPt;
    for (final GuardLaneShift s in spec.laneShifts) {
      final double d = (tMs - s.startMs) / kGuardLaneShiftMs;
      if (d <= 0) break;
      if (d >= 1) {
        lane = s.targetLaneYPt;
        continue;
      }
      final double e = d * d * (3 - 2 * d);
      return lane + (s.targetLaneYPt - lane) * e;
    }
    return lane;
  }

  /// 怪走到门口的时刻（ms）。
  double _doorMsOf(GuardBattleMonsterSpec spec) =>
      spec.spawnMs + kGuardBattleFieldTravelPt / spec.speedPtPerSec * 1000.0;

  /// 把显示位置刷新到 [tMs]（只影响快照渲染；事件逻辑一律用 `_xAt/_yAt` 现算）。
  void _refreshPositions(int tMs) {
    final double t = tMs.toDouble();
    for (final _MonsterRt m in _monsters) {
      switch (m.phase) {
        case GuardBattleMonsterPhase.waiting:
          m.x = 0;
          m.y = m.spec.laneYPt;
          break;
        case GuardBattleMonsterPhase.walking:
          m.x = _monsterXAt(m.spec, t);
          m.y = _monsterYAt(m.spec, t);
          break;
        case GuardBattleMonsterPhase.dead:
        case GuardBattleMonsterPhase.fled:
        case GuardBattleMonsterPhase.retreated:
          break; // 退场 / 被灭：冻结在最后已知位置（演出层负责退场动画）
      }
    }
    for (final _BulletRt b in _bullets) {
      if (b.resolved) continue;
      final double raw = kGuardBattleBulletSpawnXPt +
          b.dir * kGuardBulletSpeed * (t - b.fireMs) / 1000.0;
      // 不许飞过瞄准点（双向钳制：dir>0 不许超过 aimX，dir<0 不许低于 aimX）。
      final bool passed =
          b.dir > 0 ? raw > b.aimX : raw < b.aimX;
      b.x = passed ? b.aimX : raw;
    }
  }

  void _clearBullets() {
    for (final _BulletRt b in _bullets) {
      b.resolved = true;
    }
  }
}

// ── 私有承载类 ───────────────────────────────────────────────────────────

class _NextEvent {
  const _NextEvent(this.t, this.kind, this.index);
  final double t;
  final int kind;
  final int index;
}

/// 一只怪的运行时状态（私有可变承载；对外只暴露快照）。
class _MonsterRt {
  _MonsterRt(this.spec);
  final GuardBattleMonsterSpec spec;
  GuardBattleMonsterPhase phase = GuardBattleMonsterPhase.waiting;
  double x = 0;
  double y = 0;
  int hitsTaken = 0;
  int stolen = 0;

  /// 该怪被子弹锁定的累计次数（= 闪避通道 j 的分配器）。
  int lockedCount = 0;
}

/// 一发在飞（或已结算）的子弹。
class _BulletRt {
  _BulletRt({
    required this.index,
    required this.targetIndex,
    required this.fireMs,
    required this.arrivalMs,
    required this.aimX,
    required this.aimY,
    required this.dodgeSeq,
    required this.dir,
  });
  final int index;
  final int targetIndex;
  final int fireMs;
  final double arrivalMs;
  final double aimX;
  final double aimY;

  /// 闪避通道 j（该怪第几发锁定弹，0-based）。
  final int dodgeSeq;

  /// 飞行方向（+1 = 向右 / −1 = 向左；B2 裁定：枪口 260，双向自瞄）。
  final double dir;
  double x = 0;
  bool resolved = false;
}

// ── 文件级工具 ───────────────────────────────────────────────────────────

/// 取某通道的 `[0,1)` 确定性均匀值（战斗盐 [kGuardBattleSalt]，通道表见文件头）。
double _uniform({
  required String dayKey,
  required String childId,
  required String channel,
}) {
  return deterministicUniform(
    dayKey: dayKey,
    childId: childId,
    salt: kGuardBattleSalt,
    channel: channel,
  );
}

/// 闪避通道的均匀值：`mix32(FNV-1a(seed)) / 2^32`。
///
/// ## 🔴 为什么闪避必须**额外终混**（B8 修的 bug，不是调参）
/// 闪避通道名形如 `dodge_<i>_<j>`，`j` 每锁一发就 +1 ⇒ 相邻两次派生的输入
/// 串**只差最后一个字符**。FNV-1a 的收尾是 `(h ^ 末字节) * FNV_PRIME`：
/// 末字节差 1 ⇒ 输出只差 `FNV_PRIME = 0x01000193 ≈ 1.67e7`，折算成
/// `u = h / 2^32` 只有 **0.39%** 的位移。于是 `u(j)` 在阈值附近几乎是
/// **单调爬行**的：只要 `u(0) < 闪避概率`，后面十几发都会 < 闪避概率
/// ⇒ 出现「连闪」。
///
/// 实测（B8 修之前，5×m3 / HP5 / 闪避 35%）：
/// * `seed-0`：第 0 只怪连闪 **18 发**（867ms → 6244ms）才吃到第一发命中；
/// * `seed-3`：第 1 只怪连闪 **40 发**（8565ms → 17055ms）；
/// * 20 个 seed 里 **4~5 局**在 30s 到点走 Retreat（打不完）。
/// 连闪 18 发的概率在独立同分布下是 `0.35^18 ≈ 1e-8` —— 不是运气差，是哈希坏了。
///
/// 修法：加一步 [\_mix32]（MurmurHash3 32bit finalizer，纯整数运算、无状态、
/// 无 `Random`）⇒ 输入差 1 个字节也会雪崩到完全不同的 32bit，`u(j)` 恢复
/// 独立同分布。**只作用于闪避通道**：经济/偷取/掉落/剧本派生通道一个字节都没动
/// （那些通道每次只取一个值，不存在「连号」问题，历史结果必须保留）。
double _dodgeUniform({
  required String dayKey,
  required String childId,
  required int monsterIndex,
  required int dodgeSeq,
}) {
  final String seed = deterministicSeed(
    dayKey: dayKey,
    childId: childId,
    salt: kGuardBattleSalt,
    channel: '${kGuardBattleChannelDodge}_${monsterIndex}_$dodgeSeq',
  );
  final int mixed = _mix32(fnv1a32(seed));
  return mixed / 4294967296.0;
}

/// MurmurHash3 32bit finalizer：把 32bit 值雪崩打散（纯函数、确定性）。
///
/// 三步「移位异或 + 大质数乘法」是 MurmurHash3 的收尾式（公共算法）：
/// `h ^= h>>16; h *= 0x85EBCA6B; h ^= h>>13; h *= 0xC2B2AE35; h ^= h>>16`。
/// 乘数 × 32bit 输入的积最大 < 2^64 ⇒ Dart 64 位整数按模 2^64 回绕，
/// 再 `& 0xFFFFFFFF` 取低 32bit，跨平台（VM/AOT）逐位一致。
int _mix32(int h) {
  int x = h & 0xFFFFFFFF;
  x ^= x >> 16;
  x = (x * 0x85EBCA6B) & 0xFFFFFFFF;
  x ^= x >> 13;
  x = (x * 0xC2B2AE35) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x & 0xFFFFFFFF;
}

/// 把 `u ∈ [0,1)` 映射到闭区间整数 `[min, max]`（与 `guard_math.dart` 同口径）。
int _intInRange(double u, int min, int max) {
  if (max <= min) return min;
  final int span = max - min + 1;
  final int offset = (u * span).floor();
  final int value = min + offset;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// 把 `u ∈ [0,1)` 等概率落桶到三档怪。
GuardBattleMonsterKind _kindOf(double u) {
  if (u < 1.0 / 3.0) return GuardBattleMonsterKind.m1;
  if (u < 2.0 / 3.0) return GuardBattleMonsterKind.m2;
  return GuardBattleMonsterKind.m3;
}

/// 快照数值口径：位置取 2 位小数（金测「逐字符相同」的确定性格式）。
double _round2(double v) => (v * 100).roundToDouble() / 100;

bool _listEquals(List<GuardBattleMonsterSpec> a, List<GuardBattleMonsterSpec> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 换道计划逐项比较（`GuardBattleMonsterSpec.==` 用）。
bool _laneShiftsEqual(List<GuardLaneShift> a, List<GuardLaneShift> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
