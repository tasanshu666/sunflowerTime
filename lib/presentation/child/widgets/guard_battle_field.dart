/// 守卫战 v2 · **L4 战斗层**（设计文档 §6.1 第四层 / §7-B3：卡内最小可玩闭环）。
///
/// ## 它是什么
/// `GuardSceneCard` 在 `fighting` 态挂进 Stack 的第四层：`Ticker` 把帧间毫秒差
/// 喂给 [GuardBattleSim] 的 `step()` —— **绝不给 sim 任何 wall-clock**
/// （`DateTime.now()` 只用于派生 seed 的 dayKey，由页面传入，不进时间轴）。
/// 《怪物 / 子弹》经 `guard_art.dart` 渲染（B2 占位色块，B5 换图零改动）。
///
/// 🔴 **B7 变更**：战士不再属于本层 —— 它是卡内 L3 的**常驻角色**（玄参：
/// 「战士从战斗层提到场景卡常驻」）。本层只负责怪 / 子弹 / 终局横幅，并在
/// 开火被受理时回调 [GuardBattleField.onFireAccepted] 让卡切攻击帧。
///
/// ## 确定性（测试依据）
/// * sim 时间轴 = 各帧 `Ticker.elapsed` 的**累计毫秒**（测试环境下由
///   `tester.pump(Duration)` 精确推进）⇒ 「同 seed + 同开火时间线」重放，
///   锚点时刻的快照**逐位相等**（与 B1 金测同一口径）。
/// * 开火：页面右上阳光胶囊（或测试自持手柄）→ [GuardBattleHandle.fire] →
///   本层在**当前 sim 时刻**入队，下一帧随 `step()` 交给 sim（冷却闸门 /
///   自瞄 / 闪避全部由 sim 判，本层不做任何战局判断）。
///
/// 🔴 **B9/D1 变更**：怪被击灭后不再「原地冻结尸体」，而是**转身逃跑 + 淡出**：
/// 收到 `kill` 记 `deathT = e.tMs`，800ms 内水平翻转、向右平移 60pt/700ms、
/// 200ms 起 opacity 1→0，到点从树上摘掉（常量见 `kGuardDeath*`）。
/// 纯渲染层 —— sim 的 `dead` 相位与冻结坐标**一个字节未动**（确定性零破口）。
///
/// ## 终局接线（§7-B3 裁定）
/// Victory / Retreat 后：横幅上屏 + 停一会儿让孩子看清 → [GuardBattleHandle]
/// 置结束、`onFinished(stolenSun)` 回调页面 → 页面先 `recordBattleTheft` 落账
/// （B4），再走**既有** `showGuardResultCard` 流（claim 语义 / 幂等 / 账本口径
/// 一行不动）。本层零写库。
///
/// 🔴 **B10/D1**：终局若由「打死最后一只怪」触发，`onFinished` 延迟
/// [kGuardDeathFleeMs]（800ms）—— 逃跑演出**播完**才切结算卡；这段补时期内
/// ticker 继续跑（否则演出冻在第 0 帧，B9 已知边界）。到点撤退 / 中止没有死亡
/// 演出 ⇒ 延迟 0（仍是 [kGuardEndBannerDwellMs] 900ms 横幅停留）。
///
/// ## i18n
/// 本层**在页级 L10nScope 之内**（卡内 in-tree，不是 dialog），文案走
/// `l10nOf(context)`（裸测试宿主自动回落 zh，与场景卡同口径）。
library guard_battle_field;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardAttackVolume,
        kGuardDeathFadeStartMs,
        kGuardDeathFleeMs,
        kGuardDeathFleePt,
        kGuardDeathFleeRunMs,
        kGuardEndBannerDwellMs,
        kGuardMissFxMs,
        kGuardSunDropFxMs,
        kGuardSunRiseFadeStart,
        kGuardSunRiseFadeStartOpacity,
        kGuardSunRisePt;
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';

/// 开火手柄：**页面**持有（阳光胶囊在卡外），经 [GuardSceneCard] 传给本层；
/// 点击经它把「按」递进 sim。
///
/// 为什么经手柄而不让卡直接摸 sim：sim 是 field 的私有状态，卡的职责只有
/// 「转发点击」与「按快照渲染倒计时 / 派生战士姿态」—— 手柄把这条缝做成单向、
/// 可测（测试直接 new 一个手柄喂 field / 卡）。
class GuardBattleHandle {
  VoidCallback? _fire;

  /// 战局已收场（field 在 onFinished 时置位）：之后的开火请求一律 no-op ——
  /// B1 R3 的 UI 面体现：结束后提交的开火在 sim 里会被静默丢弃，
  /// 这里从源头就不递。
  bool _over = false;

  /// 请求开火（战局结束后 no-op；未接线时 no-op）。
  void fire() {
    if (_over) return;
    _fire?.call();
  }
}

/// L4 战斗层（占满 [GuardSceneCard] 的 L1 底图之上的整张卡面）。
class GuardBattleField extends StatefulWidget {
  /// 战斗层根 Key（页面级测试断言「战斗已上屏」）。
  static const Key fieldKey = Key('guardBattleField');

  /// 终局横幅 Key（Victory / Retreat 共用容器；文案见各自断言）。
  static const Key bannerKey = Key('guardBattleBanner');

  /// 第 [index] 只怪的 Key（③ 三种怪占位色可区分）。
  static Key monsterKey(int index) => Key('guardBattleMonster$index');

  /// 第 [index] 发在飞子弹的 Key。
  static Key bulletKey(int index) => Key('guardBattleBullet$index');

  /// 第 [monsterIndex] 只怪身上的「MISS」打击反馈 Key（B8）。
  static Key missKey(int monsterIndex) => Key('guardBattleMiss$monsterIndex');

  /// 第 [monsterIndex] 只怪**死亡淡出层**的 Key（B9/D1）。
  ///
  /// 测试读法：`tester.widget<Opacity>(find.byKey(deathFadeKey(i))).opacity`
  /// ⇒ 断言「死亡后 200ms 起 opacity 单调不增、800ms 时 ≈0 且节点消失」。
  static Key deathFadeKey(int monsterIndex) =>
      Key('guardBattleDeathFade$monsterIndex');

  /// 第 [monsterIndex] 只怪击杀掉落的**阳光精灵** Key（B13.8）。
  ///
  /// 测试读法：kill 后它应在树（[kGuardSunDropFxMs] 内），之后摘除：
  /// `find.byKey(GuardBattleField.sunDropKey(i))` 先 findsOneWidget 再 findsNothing。
  static Key sunDropKey(int monsterIndex) =>
      Key('guardBattleSunDrop$monsterIndex');

  /// 阳光精灵的不透明度曲线（纯函数，可单测）。
  ///
  /// 前 [kGuardSunRiseFadeStart]（60%）线性 1 → [kGuardSunRiseFadeStartOpacity]
  /// （0.35），之后线性收到 0；`t` 越界自动钳在 [0,1]。
  ///
  /// 🔴 曲线挂在**公开 Widget 类**上（而不是 `_State`）的唯一原因：这是「演出
  /// 规格」而不是「渲染细节」，页面级 / 单元测试要能直接钉住它，无需把整层战斗
  /// 挂起来（见 `test/guard/guard_sun_drop_fx_test.dart` 的方向 + 淡出曲线用例）。
  static double sunRiseOpacityAt(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    if (clamped <= kGuardSunRiseFadeStart) {
      final double p = clamped / kGuardSunRiseFadeStart;
      return 1 - (1 - kGuardSunRiseFadeStartOpacity) * p;
    }
    final double p =
        (clamped - kGuardSunRiseFadeStart) / (1 - kGuardSunRiseFadeStart);
    return kGuardSunRiseFadeStartOpacity * (1 - p);
  }

  /// 战局归属的自然日（sim seed 入参；页面传当日 `dayKey`）。
  final String dayKey;

  /// 战局归属的孩子（sim seed 入参；页面传当前 childId）。
  final String childId;

  /// 开火手柄（卡持有，本层在 initState 注册实现）。
  final GuardBattleHandle handle;

  /// 每帧快照回调（卡据此绑倒计时细线 / 派生战士姿态）。
  final ValueChanged<GuardBattleSnapshot>? onSnapshot;

  /// 开火**被受理**回调（B7：卡内开火钮已删，开火改由页面右上阳光胶囊经
  /// [GuardBattleHandle] 触发；卡需要知道「刚刚真的打了一枪」才能把常驻战士
  /// 切到攻击帧 [kGuardSoldierAttackFlashMs] 毫秒）。
  ///
  /// 🔴 只在 [GuardBattleHandle.fire] 真正落到本层、且战局未收场时回调一次
  /// （= 旧实现在 `_fireNow` 里刷 `_attackFlashUntilMs` 的同一时刻），
  /// 逐位保持「点击 → 攻击帧」的语义；被冷却闸门拦下的枪**不会**触发。
  final VoidCallback? onFireAccepted;

  /// 终局回调（Victory / Retreat 收场 + 横幅展示约 900ms 后触发一次）。
  ///
  /// B4 起携带**本场实际被偷合计**（sim 终局 `stolenSun`，含 30s 到点时刻的
  /// 钳制值 —— 战局冻结后快照逐位不变，见 guard_battle_sim 文件头）。
  /// 取数链路（§5.3 裁决 B）：sim 报告 → 页面（`recordBattleTheft` 落账）
  /// → 结算卡。本层只报数，**零写库**。
  final ValueChanged<int>? onFinished;

  /// 调试剧本覆盖（B5a，**仅 kDebugMode 有非空值**；null = 走真实 seed 派生）。
  ///
  /// 注入链：调试面板「强制剧本」→ `debugGuardBattleScriptOverrideProvider` →
  /// `ChildTodayPage` → [GuardSceneCard] → 本参数。release 无写入方 ⇒ 恒为
  /// null ⇒ 生产路径零感知；**冻结的 `deriveGuardBattleScript` 一行未动**。
  final GuardBattleScript? debugScriptOverride;

  /// **平板 UI 放大倍率**（来自 `uiScaleOf`，手机 = 1.0）。
  ///
  /// 🔴 战斗层与场景卡共用同一把几何尺（`GuardCardLayout`），本值透传给它的
  /// 几何计算（怪/子弹/通道/卡高全部等比放大）；怪/子弹之外的演出固定尺寸
  /// （MISS / 阳光精灵 / 逃跑位移）也按本倍率放大，保持与卡同比例。默认 1.0
  /// ⇒ 手机与既有测试逐位零回归。
  final double uiScale;

  const GuardBattleField({
    super.key,
    required this.dayKey,
    required this.childId,
    required this.handle,
    this.onSnapshot,
    this.onFireAccepted,
    this.onFinished,
    this.debugScriptOverride,
    this.uiScale = 1.0,
  });

  @override
  State<GuardBattleField> createState() => _GuardBattleFieldState();
}

class _GuardBattleFieldState extends State<GuardBattleField>
    with SingleTickerProviderStateMixin {
  /// 纯模拟器（本批唯一战局事实源）。
  ///
  /// 非 final（E2）：调试剧本覆盖变化时 [`_restartBattle`] 会整体重建
  /// （IndexedStack 保活下本 State 不重建，不重开就是「点了没响应」）。
  late GuardBattleSim _sim;

  /// 战局代际号：每次重开 +1；终局 900ms 延迟回调据此作废旧战局的交回
  /// （重开发生在横幅窗口内时，旧战局的结果不再打扰新战局）。
  int _battleGen = 0;

  /// 最近一次 `_onTick` 的**原始** ticker 累计毫秒（E2：重开战局的锚点用）。
  int _rawMs = 0;

  /// sim 时间零点在原始 ticker 时间轴上的锚点。initState 时 ticker 与 sim
  /// 同步起跑 ⇒ 0；重开战局时 ticker 不重建（累计 elapsed 已很大）⇒ 把锚点
  /// 拨到当前原始值，`sim 时刻 = 原始值 − 锚点`，避免新 sim 被单大步喂穿。
  int _simZeroMs = 0;

  late final Ticker _ticker;

  /// 自上一次 step 以来新入队的开火时刻（sim 战局时间轴）。
  final List<int> _pendingFires = <int>[];

  /// 最近一份快照（渲染源；终局后冻结）。initState 首帧即赋值。
  late GuardBattleSnapshot _snap;

  /// 终局只处理一次的闸门。
  bool _endHandled = false;

  /// 正在播放的「MISS」反馈（B8：玄参「闪避没表现」）。
  ///
  /// 由 [GuardBattleStepReport] 的 `dodge` 事件驱动 —— **不改 sim 的闪避判定**，
  /// 只把「这一发白打了」演出来：在该怪身边冒一个 MISS，[kGuardMissFxMs] 内
  /// 上浮 + 淡出。同一只怪连续闪避 ⇒ 同一 index 的记录被**刷新**（重新计时），
  /// 不会堆成一列字。
  final List<_MissFx> _misses = <_MissFx>[];

  /// 已击灭的怪（B9/D1 死亡逃跑演出）：`怪序号 → 死亡时刻（战局时间轴 ms）`。
  ///
  /// 🔴 **纯渲染层账本**：sim 的 `dead` 相位与冻结坐标一个字节不动，这里只记
  /// 「什么时候看到 kill 事件」，动画全部由 `deathT` 推出来 ⇒ 同一个 `deathT`
  /// 必然推出同一段轨迹（同 seed 两遍逐位一致，确定性零破口）。
  /// 不清理（一场最多 5 只）；重开战局时随 [_restartBattle] 清空。
  final Map<int, int> _deaths = <int, int>{};

  /// 击杀掉落的「阳光精灵」列表（B13.8：kill 事件 → 怪位置冒一颗阳光，
  /// [kGuardSunDropFxMs] 内**上飞** + 漂移 + 淡出后摘除）。
  ///
  /// 🔴 **纯渲染层**，与 [_deaths] 同一纪律：sim / 结算 / 确定性**零感知**。
  /// 🔴 随机漂移量的 `math.Random()` 只允许活在本 Fx 层 —— 绝不进 sim / 领域层。
  final List<_SunDropFx> _sunDrops = <_SunDropFx>[];

  /// 阳光精灵漂移量的随机源（仅 Fx 层消费；影响演出轨迹，不影响战局）。
  final math.Random _fxRandom = math.Random();

  /// 终局后「死亡演出补时」的起点（原始 ticker ms；null = 不在补时期）。
  ///
  /// ## 🔴 B10/D1：为什么终局后 ticker 还得活着
  /// 旧实现在 `sim.isOver` 的那一帧就 `_ticker.stop()`，而死亡演出是**按
  /// `_snap.elapsedMs` 推**的（sim 冻结 ⇒ 快照时刻冻住）⇒ 最后一只怪一旦
  /// 同时打死并结束战局，逃跑动画就永远停在第 0 帧（B9 已知边界）。
  /// B10 改为：终局那一刻若还有死亡演出没播完，**ticker 继续跑**
  /// [补时时长]（= `kGuardDeathFleeMs − 已播时长`），期间只推进渲染时钟
  /// [fxClockMs]（不再喂 sim），到点才 stop 并把结果交回页面。
  int? _postEndFxStartRawMs;

  /// 补时期间累计推进的毫秒（加在冻结的 `_snap.elapsedMs` 上 = [fxClockMs]）。
  int _postEndFxElapsedMs = 0;

  /// 补时结束的原始 ticker 时刻（null = 无补时）。
  int? _postEndFxEndRawMs;

  @override
  void initState() {
    super.initState();
    _sim = _buildSim();
    _snap = _sim.snapshot();
    widget.handle._fire = _fireNow;
    // 🔴 B10/B3：**每次挂载都要把「战局已收场」的闸门放开**。
    // 手柄是页面级长生命周期对象（`_guardBattleHandle`），上一场在终局时把它
    // 置了 `_over = true`；本 State 重新挂载（换卡 / 调试重置后重开）时若不
    // 复位，`handle.fire()` 会在源头直接 return ⇒ 玄参报的「点了胶囊不发射」。
    widget.handle._over = false;
    _ticker = createTicker(_onTick);
    _ticker.start();
    // 🔴 B13.6（玄参交付「进攻音效」，B13.7 重制）：战斗开始 → 播放战斗
    // 背景音（**只播一遍**，不循环）。独立战斗通道（与花园氛围音 / SFX 互
    // 不打断）；headless 测试无声频后端 ⇒ AudioService 静默降级，零感知。
    // 战斗结束 / dispose 由本层负责停。
    unawaited(AudioService.instance.startGuardBattleBgm());
  }

  /// 按当前 widget 配置构造 sim（initState 与 [`_restartBattle`] 共用）。
  GuardBattleSim _buildSim() {
    return GuardBattleSim(
      // B5a：调试剧本覆盖（仅 debug 面板写入；null = 走真实 seed 派生，
      // 派生函数原样 —— 冻结三件套零 diff）。
      script: widget.debugScriptOverride ??
          deriveGuardBattleScript(
            dayKey: widget.dayKey,
            childId: widget.childId,
          ),
      dayKey: widget.dayKey,
      childId: widget.childId,
    );
  }

  @override
  void didUpdateWidget(covariant GuardBattleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🔴 E2（玄参真机报「点恢复随机剧本没响应」）：调试剧本覆盖变化 ⇒
    // **立即以新剧本重开战局**。IndexedStack 保活下本 State 不重建
    // （initState 只跑一次），旧实现里 override 永远进不了正在跑的战局。
    // `GuardBattleScript` 的 `==` 已冻结（逐位比较），null == null 恒成立。
    if (widget.debugScriptOverride != oldWidget.debugScriptOverride) {
      _restartBattle();
    }
  }

  /// 以当前配置重开战局（B5a/E2 调试链路专用）。
  ///
  /// 生产零感知：release 覆盖恒为 null ⇒ `null != null` 为 false ⇒ 本方法
  /// 永不被调用；重开只影响演出与 sim 状态，**零写库**（落账仍由页面在
  /// `onFinished` 里做，被作废的旧战局不落账 = 调试行为，可接受）。
  ///
  /// ⚠️ 不在这里调 `onSnapshot`：didUpdateWidget 处于 build 期，父卡
  /// `setState` 会炸「markNeedsBuild during build」；下一帧 ticker 自然把
  /// 新快照送出去。
  ///
  /// ## 🔴 B10/B3（玄参第五轮「调试重置后点胶囊不发射」）
  /// 旧实现只在 `!_ticker.isActive` 分支里 `start()`，且**没有重绑
  /// `handle._fire` / 没有复位 `handle._over`**；而终局时本层已经
  /// `_ticker.stop()` + `_over = true` —— 一旦这一帧没走到「ticker 停摆」分支
  /// （或手柄被上一场置了 `_over`），新战局就再也收不到开火。
  /// 现在固定走「**stop → 重建 sim → 归零时间锚 → 重绑开火 → start**」，
  /// 四条一起做，任何一条漏掉都会让第二场打进空气。
  void _restartBattle() {
    _battleGen++;
    // ① 先停表：下面要靠「停表后 start 会把 elapsed 归零」这条性质。
    if (_ticker.isActive) _ticker.stop();
    // ② 重建 sim（新剧本 / 新 seed）。
    _sim = _buildSim();
    _snap = _sim.snapshot();
    _pendingFires.clear();
    _misses.clear();
    _deaths.clear();
    _sunDrops.clear();
    _endHandled = false;
    // ③ 时间锚点归零（stop→start 后 ticker 从 0 起算，见 Ticker.start）。
    _simZeroMs = 0;
    _rawMs = 0;
    // ④ 补时状态（D1）一并清掉。
    _postEndFxStartRawMs = null;
    _postEndFxElapsedMs = 0;
    _postEndFxEndRawMs = null;
    // ⑤ 手柄重绑：`_fire` 可能被上一场的 dispose 置 null；`_over` 必须是 false。
    widget.handle._fire = _fireNow;
    widget.handle._over = false;
    // ⑥ 重新起表。
    _ticker.start();
    setState(() {});
  }

  @override
  void dispose() {
    // 🔴 B7：开火入口已搬到卡外的阳光胶囊 —— 战斗层卸载后（如切到 claimed）
    // 手柄必须**断开**，否则一次误触会让已 dispose 的 State 收到 fire。
    widget.handle._fire = null;
    // 🔴 B13.6：战斗层卸载（战局结束交回 / 换卡）→ 战斗背景音必须停，
    // 否则底噪会漏到结算卡甚至花园页（BGM 泄漏 = 玄参抓过的同类问题）。
    unawaited(AudioService.instance.stopGuardBattleBgm());
    _ticker.dispose();
    super.dispose();
  }

  /// 阳光胶囊 / 卡内入口 → 手柄 → 这里：在**当前 sim 时刻**入队，下一帧交给 sim。
  /// （时刻取 `_sim.elapsedMs` 而非墙钟 —— 最多滞后一帧（≈16ms），
  ///   对 400ms 冷却闸门与确定性都无影响：测试里 pump 与 tap 交替，
  ///   时刻仍然逐位可复现。）
  void _fireNow() {
    // B7 防御：开火源在卡外，可能在战斗层已卸载后仍被点到。
    if (!mounted) return;
    if (_sim.isOver) return;
    _pendingFires.add(_sim.elapsedMs);
    // 🔴 2026-11-12 玄参：开火**被受理**（子弹入队）那一刻播攻击音效
    // （MISS 不回退——打没打中都算「攻击了」）。fire-and-forget（playSfx
    // 本身就是 void 非阻塞口径），失败静默降级，绝不影响战局确定性。
    AudioService.instance.playSfx(AudioCue.guardAttack, volume: kGuardAttackVolume);
    // 战士攻击帧（300ms）由**卡**渲染（战士是卡内常驻 L3 元素），本层只报事件。
    widget.onFireAccepted?.call();
  }

  /// 渲染时钟：死亡演出 / MISS 的「现在」。单位：ms（战局时间轴）。
  ///
  /// 平时 = `_snap.elapsedMs`；终局补时（[`_postEndFxStartRawMs`] 非空）期间
  /// 在冻结的 sim 时刻上继续累加 —→ 逃跑动画能真的播完（B10/D1）。
  int get fxClockMs => _snap.elapsedMs + _postEndFxElapsedMs;

  /// Ticker 回调：`elapsed` = 动画时钟累计值（不给 sim 任何 wall-clock）。
  void _onTick(Duration elapsed) {
    _rawMs = elapsed.inMilliseconds;
    // ── 终局补时（B10/D1）：只推进渲染时钟，不再喂 sim ──────────────────
    if (_endHandled) {
      final int? startRaw = _postEndFxStartRawMs;
      final int? endRaw = _postEndFxEndRawMs;
      if (startRaw == null || endRaw == null) {
        // 无补时（到点撤退 / 中止）：ticker 早已停在终局那一帧。
        _ticker.stop();
        return;
      }
      _postEndFxElapsedMs = _rawMs - startRaw;
      if (_rawMs >= endRaw) {
        _postEndFxElapsedMs = endRaw - startRaw;
        _ticker.stop();
      }
      _pruneSunDrops();
      if (mounted) setState(() {});
      return;
    }
    final int ms = _rawMs - _simZeroMs;
    if (ms <= _sim.elapsedMs && _pendingFires.isEmpty) return;
    final List<int> fires = List<int>.of(_pendingFires);
    _pendingFires.clear();
    final GuardBattleStepReport report = _sim.step(ms, fires);
    _snap = _sim.snapshot();
    _collectMissFx(report);
    _collectDeathFx(report);
    _collectSunDropFx(report);
    _playHitSfx(report);
    _pruneSunDrops();
    widget.onSnapshot?.call(_snap);
    if (_sim.isOver && !_endHandled) {
      _endHandled = true;
      widget.handle._over = true;
      // 🔴 B13.6：战局收场 → 战斗背景音即刻停（横幅/补时期间不再有底噪）。
      unawaited(AudioService.instance.stopGuardBattleBgm());
      // 被偷合计在**调度时**定格（战局已冻结，之后 step 也逐位不变；
      // 显式取值避免延迟回调里再读可变字段）。
      final int stolenSun = _sim.stolenSun;
      // 🔴 B10/D1：终局由「打死最后一只怪」触发 ⇒ 逃跑演出还没播完 ⇒
      // ticker 多活 `补时 = 800 − 已播`，播完（800ms）才交回页面；
      // 到点撤退 / 中止没有死亡演出 ⇒ 补时 0，照旧 900ms 横幅停留。
      final int fxRemainMs = _deathFxRemainMs();
      final int delayMs =
          fxRemainMs > 0 ? fxRemainMs : kGuardEndBannerDwellMs;
      if (fxRemainMs > 0) {
        _postEndFxStartRawMs = _rawMs;
        _postEndFxEndRawMs = _rawMs + fxRemainMs;
        _postEndFxElapsedMs = 0;
      } else {
        _ticker.stop();
      }
      // 代际号闸门（E2）：窗口期内若调试覆盖触发重开，旧战局的结果作废。
      final int gen = _battleGen;
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (mounted && gen == _battleGen) widget.onFinished?.call(stolenSun);
      });
    }
    setState(() {});
  }

  /// 死亡演出还需播放多久（0 = 没有未播完的死亡演出）。单位：ms。
  ///
  /// 取**最年轻**的那只死怪（`deathT` 最大）算剩余时长：`800 − 已播`，
  /// 钳到 `[0, kGuardDeathFleeMs]`。到点撤退 / 中止 / 没有击杀 ⇒ 0。
  int _deathFxRemainMs() {
    if (_deaths.isEmpty) return 0;
    final int now = _snap.elapsedMs;
    int maxDeathT = -1;
    for (final int deathT in _deaths.values) {
      if (deathT > maxDeathT) maxDeathT = deathT;
    }
    if (maxDeathT < 0) return 0;
    final int remain = kGuardDeathFleeMs - (now - maxDeathT);
    if (remain <= 0) return 0;
    return remain > kGuardDeathFleeMs ? kGuardDeathFleeMs : remain;
  }

  /// 把本步的 `dodge` 事件翻译成演出：在该怪当前位置冒一个 MISS。
  ///
  /// 位置取**当前快照**里该怪的 (x, y)（闪避发生时它一定在行走 ⇒ 位置有效），
  /// 而不是事件里带的（事件只带 index，不带坐标 —— sim 不关心渲染）。
  void _collectMissFx(GuardBattleStepReport report) {
    // 先清过期的。
    _misses.removeWhere(
        (_MissFx m) => _snap.elapsedMs - m.startMs >= kGuardMissFxMs);
    for (final GuardBattleEvent e in report.events) {
      if (e.type != GuardBattleEventType.dodge) continue;
      GuardBattleMonsterSnapshot? target;
      for (final GuardBattleMonsterSnapshot m in _snap.monsters) {
        if (m.index == e.monsterIndex) {
          target = m;
          break;
        }
      }
      if (target == null) continue;
      // 同一只怪连续闪避：刷新计时（而不是叠两条）。
      _misses.removeWhere((_MissFx m) => m.monsterIndex == e.monsterIndex);
      _misses.add(_MissFx(
        monsterIndex: e.monsterIndex,
        startMs: _snap.elapsedMs,
        x: target.x,
        y: target.y,
      ));
    }
  }

  /// 把本步的 `hit` / `kill` 事件翻译成**击中音效**（B13.6 玄参交付口径：
  /// 「击中音效只有在真正打中小怪的时候响应，miss 的时候不播放」）。
  ///
  /// · `hit`（命中未击灭）与 `kill`（击灭）都算「真打中」⇒ 播；
  /// · `dodge`（闪避 = MISS）**绝不播**；
  /// · 同一步多只怪同时被命中 ⇒ 只播一次（共享 SFX 播放器，多播也只是互掐）；
  /// · 音频失败静默降级（AudioService 既有口径），绝不影响战局确定性 ——
  ///   本方法**只读事件**，不碰 sim 状态。
  void _playHitSfx(GuardBattleStepReport report) {
    for (final GuardBattleEvent e in report.events) {
      if (e.type == GuardBattleEventType.hit ||
          e.type == GuardBattleEventType.kill) {
        // B13.7：音量 0.25（玄参「声音有点大，稍微有个声音能听见就行」）。
        AudioService.instance.playSfx(AudioCue.guardHit, volume: 0.25);
        return;
      }
    }
  }

  /// 把本步的 `kill` 事件记成死亡时刻（B9/D1 逃跑演出的**唯一输入**）。
  ///
  /// 用事件自带的 `tMs`（sim 时间轴，精确到毫秒）而不是「当前快照时刻」：
  /// 与帧率无关 ⇒ 同 seed 两遍的死亡时刻逐位相同，演出轨迹也逐位相同。
  /// `putIfAbsent`：同一只怪不会被重复记账（重复 kill 不改首帧时刻）。
  void _collectDeathFx(GuardBattleStepReport report) {
    for (final GuardBattleEvent e in report.events) {
      if (e.type != GuardBattleEventType.kill) continue;
      if (e.monsterIndex < 0) continue;
      _deaths.putIfAbsent(e.monsterIndex, () => e.tMs);
    }
  }

  /// 把本步的 `kill` 事件翻译成**阳光掉落 VFX**（B13.8，玄参提案拍板）。
  ///
  /// 与 [_collectDeathFx] 读同一批 kill 事件，但只追加渲染记录：在怪的
  /// **当前位置**（事件只带 index 不带坐标，同 MISS 的做法取快照）冒一颗
  /// 阳光精灵，[kGuardSunDropFxMs] 内**上飞** + 随机漂移 + 淡出后摘除。
  ///
  /// 🔴 **零确定性破口**：sim 事件流 / 结算 / seed 一个字节不动；随机量
  /// （漂移方向）只影响演出，`math.Random()` 只活在本 Fx 层。
  /// `putIfAbsent` 语义：同一只怪只掉一颗（重复 kill 不重复生成）。
  void _collectSunDropFx(GuardBattleStepReport report) {
    for (final GuardBattleEvent e in report.events) {
      if (e.type != GuardBattleEventType.kill) continue;
      if (e.monsterIndex < 0) continue;
      final bool already = _sunDrops.any(
        (_SunDropFx s) => s.monsterIndex == e.monsterIndex,
      );
      if (already) continue;
      GuardBattleMonsterSnapshot? target;
      for (final GuardBattleMonsterSnapshot m in _snap.monsters) {
        if (m.index == e.monsterIndex) {
          target = m;
          break;
        }
      }
      if (target == null) continue;
      _sunDrops.add(_SunDropFx(
        monsterIndex: e.monsterIndex,
        startMs: e.tMs,
        x: target.x,
        y: target.y,
        // 随机漂移：±12pt（仅演出；Random 只在 Fx 层，不进 sim/领域层）。
        driftDx: _fxRandom.nextDouble() * 24 - 12,
      ));
    }
  }

  /// 清掉已播完（过期）的阳光精灵（与 [_misses] 同一清理口径）。
  void _pruneSunDrops() {
    _sunDrops.removeWhere(
        (_SunDropFx s) => fxClockMs - s.startMs >= kGuardSunDropFxMs);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final bool victory = _sim.phase == GuardBattlePhase.victory;

    // 卡宽由外层卡撑满 ⇒ 用 LayoutBuilder 拿真实宽度，几何全部来自
    // `guard_card_layout`（与卡同一把尺子，绝不各自算）。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final GuardCardLayout layout = GuardCardLayout(constraints.maxWidth, widget.uiScale);

        return Stack(
          key: GuardBattleField.fieldKey,
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            // ── 怪物（walking = 行走；dead = 转身逃跑 → 淡出 → 摘除）────────
            // 🔴 B6 镜像：怪从**右**端入场、向**左**走向战士（`mapMonsterX`）。
            // 🔴 B7：战士已提到卡内 L3 常驻（本层不再画战士）—— 怪与战士的
            //    纵向关系由 `GuardCardLayout.mapMonsterY` 的「同一条水平带」保证。
            // 🔴 B9/D1：死亡演出在 [_monsterSlot] 里（纯渲染，sim 零字段）。
            for (final GuardBattleMonsterSnapshot m in _snap.monsters)
              if (m.phaseId == GuardBattleMonsterPhase.walking.id ||
                  m.phaseId == GuardBattleMonsterPhase.dead.id)
                _monsterSlot(layout, m),

            // ── 「MISS」打击反馈（B8：闪避要有表现）────────────────────────
            for (final _MissFx miss in _misses) _missFx(layout, miss),

            // ── 击杀掉落的阳光精灵（B13.8：下落 + 漂移 + 淡出，纯演出）──────
            for (final _SunDropFx s in _sunDrops) _sunDropFx(layout, s),

            // ── 在飞子弹（同一把尺子 ⇒ 方向自动镜像：怪在右就往右飞）──────
            for (final GuardBattleBulletSnapshot b in _snap.bullets)
              Positioned(
                key: GuardBattleField.bulletKey(b.index),
                left: layout.mapBulletX(b.x) - layout.bulletExtent / 2,
                top: layout.mapBulletY(b.y) - layout.bulletExtent / 2,
                width: layout.bulletExtent,
                height: layout.bulletExtent,
                child: GuardArt.bullet(),
              ),

            // ── 终局横幅（Victory / Retreat；约 900ms 后 onFinished 交回页面）──
            // 🔴 B13.15（玄参：文字把向日葵战士盖住了）：从居中改贴**卡顶**，
            //    只压场景上空，不再压战士/怪物的水平带（y 72±8）。
            if (_sim.isOver)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                    key: GuardBattleField.bannerKey,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xCCFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      victory
                          ? t.guard_battle_victory_banner
                          : t.guard_battle_retreat_banner,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B5A3E),
                      ),
                    ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── 战士素材（B7：已搬到卡内 L3 常驻位，见 `guard_scene_card.dart`）──────

  // ── 怪物的三种渲染态（B9/D1）────────────────────────────────────────────

  /// 单只怪的渲染：`walking` 正常行走 / `dead` 逃跑演出 / 到点摘除。
  ///
  /// ## D1 演出（玄参第四轮：「打死的怪没有消失」）
  /// 收到 `kill` 的那一刻记下 `deathT`（[`_deaths`]），随后 800ms 内：
  /// * **水平翻转**（`Transform.flip(flipX: true)`）⇒ 从「朝左走向战士」变成
  ///   「朝右逃跑」；
  /// * x 以 `kGuardDeathFleePt(60) / kGuardDeathFleeRunMs(700)` **线性向右**平移；
  /// * `opacity` 在 `kGuardDeathFadeStartMs(200)` 之后从 1 线性降到 0；
  /// * `kGuardDeathFleeMs(800)` 到点 ⇒ 返回零尺寸占位（节点从树上消失）。
  ///
  /// 🔴 全部由 `deathT` 推导 ⇒ 同一 `deathT` 必然同一段轨迹（确定性零破口）；
  /// sim 的 `dead` 相位与冻结坐标**一个字节未动**。
  /// 兜底：`dead` 但没记到 `kill`（理论上不会发生）⇒ 沿用 B6 的冻结尸体。
  Widget _monsterSlot(GuardCardLayout layout, GuardBattleMonsterSnapshot m) {
    final bool dead = m.phaseId == GuardBattleMonsterPhase.dead.id;
    final int? deathT = _deaths[m.index];
    // 🔴 B10/C3：每只怪按**自己的**等面积宽高占位（m1 49.42×39.19 /
    // m2 44×44 / m3 60.93×31.77），中心锚在 (mapMonsterX, mapMonsterY)。
    final double w = layout.monsterWidthOf(m.kindId);
    final double h = layout.monsterHeightOf(m.kindId);
    final double baseLeft = layout.mapMonsterX(m.x) - w / 2;
    final double top = layout.mapMonsterY(m.y) - h / 2;

    if (!dead || deathT == null) {
      return Positioned(
        key: GuardBattleField.monsterKey(m.index),
        left: baseLeft,
        top: top,
        width: w,
        height: h,
        child: _monsterArt(m),
      );
    }

    // 🔴 B10/D1：演出时钟用 [fxClockMs]（终局补时期间仍在走），
    // 否则最后一只怪的逃跑会冻在第 0 帧。
    final int deathAgeMs = fxClockMs - deathT;
    if (deathAgeMs >= kGuardDeathFleeMs) {
      // 800ms 到点：**彻底摘掉**（玄参「打死要消失」）。
      return const SizedBox.shrink();
    }
    // 向右逃：60pt / 700ms 线性；700ms 后位移停在 60（末段原地淡出）。
    final double runFrac =
        (deathAgeMs / kGuardDeathFleeRunMs).clamp(0.0, 1.0).toDouble();
    // 淡出：死亡后 200ms 起 1 → 0（800ms 时正好 0）。
    final double fadeFrac = ((deathAgeMs - kGuardDeathFadeStartMs) /
            (kGuardDeathFleeMs - kGuardDeathFadeStartMs))
        .clamp(0.0, 1.0)
        .toDouble();

    return Positioned(
      key: GuardBattleField.monsterKey(m.index),
      left: baseLeft + kGuardDeathFleePt * runFrac * layout.uiScale,
      top: top,
      width: w,
      height: h,
      child: Opacity(
        key: GuardBattleField.deathFadeKey(m.index),
        opacity: 1.0 - fadeFrac,
        // 水平翻转：转身朝右（逃跑方向）跑。
        child: Transform.flip(
          flipX: true,
          child: _monsterArt(m),
        ),
      ),
    );
  }

  /// 一只怪的**素材本体**（B10/C3：等面积宽高，横向溢出方框不裁）。
  ///
  /// 尺寸由 `monsterWidthOf` / `monsterHeightOf` 反解（`w × h ≡ 1936pt²`、
  /// 比例 = 素材比例）⇒ 三种怪的**视觉体量一致**，各自的长宽比保留。
  /// 素材用 `BoxFit.fitHeight` 画满这个框（`_GuardSequence` 的 `fit`），
  /// 绝不 contain（contain 会把 m3 按宽压到 22.9pt 高）。
  ///
  /// 🔴 只影响绘制：`mapMonsterX` 的 simX 映射、`channelLeft` 的
  /// `monsterExtent × 0.5`（= 22pt）**一个字节没动**。
  Widget _monsterArt(GuardBattleMonsterSnapshot m) {
    return GuardArt.monsterWalk(
      _kindOf(m.kindId),
      (m.x / 10).floor() % 2, // 行走帧占位（真帧序列自带时间轴）
    );
  }

  /// 单个 MISS 反馈的渲染（在怪身边上浮 + 淡出，[kGuardMissFxMs] 内）。
  ///
  /// 🔴 文案 `MISS` 是**游戏拟声词**、不是本地化文案：中英通吃，故不进 ARB
  /// （避免 i18n 面扩张）。宽度固定 52pt + `FittedBox` ⇒ 系统字号 1.3× 也
  /// 不会撑破卡（这是卡内唯一允许出现 `Text` 的地方，见 `missKey`）。
  Widget _missFx(GuardCardLayout layout, _MissFx miss) {
    final double t =
        ((fxClockMs - miss.startMs) / kGuardMissFxMs).clamp(0.0, 1.0);
    return Positioned(
      key: GuardBattleField.missKey(miss.monsterIndex),
      left: layout.mapMonsterX(miss.x) - 26 * layout.uiScale,
      top: layout.mapMonsterY(miss.y) -
          layout.monsterExtent / 2 -
          6 * layout.uiScale -
          18 * layout.uiScale * t,
      width: 52 * layout.uiScale,
      height: 18 * layout.uiScale,
      child: IgnorePointer(
        child: Opacity(
          opacity: (1.0 - t).clamp(0.0, 1.0),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'MISS',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: Color(0xFFE04A2F),
                  shadows: <Shadow>[
                    Shadow(color: Color(0xCCFFFFFF), blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 单个**阳光精灵** VFX 的渲染（Guard-B13.11：**上飞** + 随机漂移 + 淡出）。
  ///
  /// 轨迹全部由 `fxClockMs − startMs` 推导（与死亡演出同一口径，确定性友好）：
  /// * y 随 `t` 线性**上飞** [kGuardSunRisePt]（26pt，钳在场景卡内的安全高度）；
  /// * x 随 `t` 线性漂移（±12pt，生成时由 [_fxRandom] 抽定）；
  /// * opacity：前 [kGuardSunRiseFadeStart]（60%）从 1 淡到
  ///   [kGuardSunRiseFadeStartOpacity]（0.35），后 40% 加速淡出到 0 ——
  ///   「先看到它飞起来，再淡掉」（原实现一冒头就消失，等于没演出）；
  /// * [kGuardSunDropFxMs](700ms) 到点返回零尺寸占位
  ///   （由 [_pruneSunDrops] 在 tick 里摘除记录）。
  ///
  /// 🔴 为什么上飞只有 26pt：卡高 112pt、怪的水平带被 `mapMonsterY` 钳在卡底
  /// 倒计时细线之上 —— 再高就会盖住卡顶的计时条 / 能量点（玄参红线）。
  ///
  /// 素材复用既有 `assets/rewards/sunlight.png`；缺失回退零尺寸，不 crash。
  Widget _sunDropFx(GuardCardLayout layout, _SunDropFx s) {
    final int ageMs = fxClockMs - s.startMs;
    if (ageMs < 0 || ageMs >= kGuardSunDropFxMs) {
      return const SizedBox.shrink();
    }
    final double t =
        (ageMs / kGuardSunDropFxMs).clamp(0.0, 1.0).toDouble();
    final double size = 18 * layout.uiScale;
    return Positioned(
      key: GuardBattleField.sunDropKey(s.monsterIndex),
      left: layout.mapMonsterX(s.x) - size / 2 + s.driftDx * t,
      // 🔴 负号 = 向上（原实现是 `+ 26 * t`，即下落）。
      top: layout.mapMonsterY(s.y) - kGuardSunRisePt * layout.uiScale * t,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: GuardBattleField.sunRiseOpacityAt(t),
          child: Image.asset(
            'assets/rewards/sunlight.png',
            fit: BoxFit.contain,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// 阳光精灵的不透明度曲线（纯函数）—— 实现见
  /// [GuardBattleField.sunRiseOpacityAt]（挂在公开类上以便单测直接钉住）。

  static GuardBattleMonsterKind _kindOf(String kindId) {
    return GuardBattleMonsterKind.values.firstWhere(
      (GuardBattleMonsterKind k) => k.id == kindId,
    );
  }}

/// 一条正在播放的「MISS」反馈（[kGuardMissFxMs] 后出场）。
///
/// 只存**呈现所需**的三件事：哪只怪、什么时候开始、当时它站在哪。
/// 位置在闪避发生那一刻定格 —— 演出不该跟着后续帧抖动。
class _MissFx {
  _MissFx({
    required this.monsterIndex,
    required this.startMs,
    required this.x,
    required this.y,
  });

  /// 怪序号（同一只怪连续闪避 ⇒ 复用同一条记录，只刷新 [startMs]）。
  final int monsterIndex;

  /// 开始时刻（战局时间轴 ms）。
  final int startMs;

  /// 闪避发生时的 sim x（pt）。
  final double x;

  /// 闪避发生时的 sim y（pt）。
  final double y;
}

/// 一颗正在播放的**击杀掉落阳光**精灵（[kGuardSunDropFxMs] 后摘除）。
///
/// 只存呈现所需的五件事：哪只怪、什么时候开始、当时它站在哪、漂移方向。
/// 位置在 kill 发生那一刻定格 —— 演出不跟着后续帧抖动（与 [_MissFx] 同因）。
class _SunDropFx {
  _SunDropFx({
    required this.monsterIndex,
    required this.startMs,
    required this.x,
    required this.y,
    required this.driftDx,
  });

  /// 怪序号（同一只怪只掉一颗；重开战局随列表清空）。
  final int monsterIndex;

  /// 开始时刻 = kill 事件的 `tMs`（战局时间轴 ms，逐位可复现）。
  final int startMs;

  /// 击杀发生时的怪 sim x（pt）。
  final double x;

  /// 击杀发生时的怪 sim y（pt）。
  final double y;

  /// 横向漂移总量（pt；生成时由 Fx 层 `math.Random()` 抽定的 ±12）。
  final double driftDx;
}
