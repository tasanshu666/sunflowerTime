/// 孩子端「今日」tab（M3 导航重构 / §5 信息架构：今日状态卡）。
///
/// 内容（§5）：阳光气泡（悬浮）+ 今日获取阳光 / 今日专注 / 今日必做进度
/// （仅 isDaily）+「开始专注」主按钮（钉底）。
/// 数据随 [economyRevisionProvider] 变化重新拉取 —— 孩子打卡或家长核销后回到
/// 「今日」能看到最新进度（否则 IndexedStack 保活导致数值不刷新）。
///
/// C44e 版式（玄参 2026-10-09 期望图 + 二轮反馈）：
///  · 上半场景为背景插画（**底图锚点**见 [kTodayBgPanelTargetRatio]，当前 37%），
///    标题浮在场景上（shell 透明 AppBar）；三张卡自 **[kTodayCardTopRatio]**（当前 40%，
///    C67）起 —— 二者之间是有意留出的奶油「呼吸带」；
///  · 「我的阳光」做成**悬浮气泡**，在向日葵右半侧无规律小范围飘动；
///  · 中间三张状态卡可滚动，「开始专注」按钮钉在底部。
///
/// 纪律：不自行实现任何阳光 / 软顶 / 打卡业务逻辑，任务进度取自
/// [TaskCheckInService.board]（与「任务」tab 同源），今日获取取自
/// [SunlightRepository.earnNetOnDay]（当日实际发放合计，§4.5 口径）。
library child_today_page;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart'
    show debugGuardBattleScriptOverrideProvider;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleScript, GuardBattleMonsterSpec, deriveGuardBattleScript;
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
// B3（守卫战 v2）：战斗浮层（guard_battle_overlay.dart）已退役 —— 战斗本体
// 在场景卡 L4（guard_battle_field.dart）跑；v1 胶囊（guard_pill.dart）同批删除，
// 模式判定函数本就驻在 guard_today_state.dart（落点未变）。
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart'
    show GuardBattleHandle;
import 'package:sunflower_time/presentation/child/widgets/guard_intro_dialog.dart'
    show recordMetMonsterKinds;
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_settle_report_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/sun_burst.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

/// 本页卡片（状态卡）起点占**屏高**的比例。
///
/// 沿革：C44e 实测标定 0.42 → C65（2026-10-13 玄参 iPad 实测）下调到 0.37 →
/// **C67（2026-10-13 晚 玄参 iPad 实测）上调到 0.40**。
///
/// ## C67 依据（玄参交付「现状 vs 期望」两张同屏截图）
/// 两张图做垂直互相关：**底图像素完全一致**（最佳偏移处 MEA = 0.17，即背景没动），
/// 而三张卡的图标圆心一律下移 **39px**。按本机标定（截图 907px 宽 ↔ iPad 834pt 宽，
/// 1.088 px/pt）换算 ≈ **36pt ≈ 屏高 3%** → 0.37 + 0.03 = **0.40**。
/// 视觉效果 = 底图场景与第一张卡之间留出一条奶油色「呼吸带」（玄参期望图形态）。
///
/// ## ⚠️ 与底图锚点**解耦**（C67 关键）
/// C64 起底图分界线锚在「卡片起点」；但本次玄参要求**卡片下移、底图不动**
/// （原话：「背景图片的位置已经比较合适了」）→ 底图锚点改用独立的
/// [kTodayBgPanelTargetRatio]（冻结在 0.37）。**改本常量不再牵动底图**。
///
/// ⚠️ 本值下边界：底图里向日葵花头顶距分界线仅 0.2115 图高 → 花头顶屏幕位置
/// `= r × 屏高 − 0.2115 × 绘制高`（iPad 11″ ≈ 1210r − 392）：
///   r=0.42 → 116pt、r=0.40 → 92pt、r=0.37 → 56pt、r=0.35 → 32pt、r≤0.324 → 花头被切掉。
/// 本值**不可低于 ~0.35**，否则向日葵会被裁。
///
/// 手机端底图恒 `topCenter`（不跟随任何比例）→ 本值只影响卡片位置：0.40 时
/// 分界线（0.399×893.3 = 356.4pt）与卡片起点（0.40×874 = 349.6pt）仅差 ≈7pt
/// （0.37 时差 ≈33pt）→ 手机端同样受益，无回归。
const double kTodayCardTopRatio = 0.40;

/// 「今日」底图「场景 ↔ 留白」分界线要对齐到的**屏高比例**（仅平板生效）。
///
/// 恒 = 0.37 —— C65 玄参 iPad 实测认可的位置。C67 把卡片下移到 [kTodayCardTopRatio]
/// 时玄参明确「背景图片的位置已经比较合适了」→ **底图保持不动**，故此处独立成常量。
/// ⚠️ 只有「今日」页有这个双常量结构（成长/商店两页的底图锚点仍 = 卡片起点）。
const double kTodayBgPanelTargetRatio = 0.37;

/// 底图分界线 ↔ 第一张卡之间那条奶油「呼吸带」占**屏高**的比例（C67 = 3%）。
///
/// ## 为什么必须显式成常量（2026-10-14 玄参 iOS 手机模拟器实测回归）
/// C67 把卡片定在 [kTodayCardTopRatio] = 0.40、底图锚点定在 0.37，二者之差 **3%
/// 就是呼吸带** —— 但这个减法只在**平板**成立：平板上底图会按 [kTodayBgPanelTargetRatio]
/// 主动对齐，分界线**真的**落在 `0.37 × 屏高`。
/// **手机端底图恒 `topCenter`（C64 手机零像素回归）** → 分界线落在 `cover` 几何处
/// （今日图 = `0.399 × 3200 × 屏宽 / 1440` ≈ `0.887 × 屏宽`），与 `0.37 × 屏高`
/// **无关**；而卡片仍按 `0.40 × 屏高` 摆 → 手机上卡片反而在分界线**之上**约 7pt
/// （实测 iPhone 390×844：卡顶 337.6 / 分界线 345.8），也就是玄参截图里「卡片骑在
/// 面板圆角上、呼吸带没了」。
///
/// ## 修法
/// 卡片起点改为 `max(0.40 × 屏高, 实测分界线 + 本常量 × 屏高)`：
///  · **平板**：分界线 = 0.37 × 屏高 ⇒ 第二项 = 0.40 × 屏高 ⇒ `max` 取到**冻结值本身**
///    （iPad 零像素变化，C67 标定 36pt 呼吸带原样保留）；
///  · **手机**：分界线被 cover 抬高 ⇒ 第二项更大 ⇒ 卡片随之下移到分界线下方，
///    呼吸带 = 3% 屏高（iPhone 844 ≈ 25pt），与平板**同口径**。
///
/// ⚠️ 两个 C67 冻结常量（0.40 / 0.37）**均未改动**；底图仍恒 topCenter，**零像素变化**。
const double kTodayBreathingBandRatio = 0.03;

/// 孩子端「今日」状态卡。
class ChildTodayPage extends ConsumerStatefulWidget {
  const ChildTodayPage({super.key});

  /// 悬浮阳光胶囊的 Key（度量护栏用：读它的 RenderBox 得到真实胶囊矩形，
  /// 与生产同源 —— `today_badge_bounds_test.dart` 平板「徽章 ∩ 阳光胶囊 = ∅」）。
  static const Key sunBubbleKey = Key('todayFloatingSunBubble');

  @override
  ConsumerState<ChildTodayPage> createState() => _ChildTodayPageState();
}

class _ChildTodayPageState extends ConsumerState<ChildTodayPage>
    with SingleTickerProviderStateMixin, ChildTabAutoRefresh<ChildTodayPage> {
  double _balance = 0;
  double _todayEarn = 0;
  double _focusMinutes = 0;
  int _focusCount = 0;
  int _taskDone = 0;
  int _taskTotal = 0;
  bool _loading = true;

  /// 累计有效专注分钟（C74 驱动量；`FocusRepository.totalStats()` 派生）。
  double _totalFocusMinutes = 0;

  /// 升级演出（**只在称号节点**播）在飞闸门（F114 教训：单 bool 抑制不可靠 →
  /// 只在演出 `onComplete` 与兜底定时器里解除，绝不被 `_reload` 重入提前清）。
  bool _levelUpFxInFlight = false;

  /// 升级演出的根 Overlay 浮层（页面卸载时必须显式移除）。
  OverlayEntry? _levelUpFxEntry;

  /// 演出兜底定时器（onComplete 因任何原因没触发也保证浮层被清走）。
  Timer? _levelUpFxTimer;

  /// 阳光爆发浮层（F170，玄参 2026-11-01）。
  ///
  /// 用**根 Overlay**：粒子要飞出胶囊边界（胶囊在场景区 Stack 的 `Positioned` 内，
  /// 有裁剪风险），根 Overlay 不被任何局部 Stack 裁剪，且坐标系恒等于屏幕。
  OverlayEntry? _sunBurstEntry;

  /// 爆发兜底定时器（`onComplete` 未触发也要清走，防浮层滞留挡视线）。
  Timer? _sunBurstTimer;

  /// 守卫链路的**重入令牌**：`_reload` 会被多个入口触发（initState / 切 tab /
  /// 经济修订号变化 / 战斗收尾），叠加时只允许**最后发出**的那次结果落库，
  /// 否则「旧快照后到」会把刚领完的 `claimed` 覆回 `pending`。
  int _guardRefreshToken = 0;

  /// 守卫交互在飞闸门（防「连点胶囊」叠出两个战斗浮层）。
  bool _guardBusy = false;

  /// 进入战斗前的守卫快照（结算卡入参；`_onGuardCardTap` 存、
  /// `_onBattleFinished` 用完即清 —— v1 用局部变量承载，B3 战斗改在卡内跑，
  /// 终局跨方法回调，故升为字段）。
  GuardTodayView? _battleView;

  /// 开火手柄（B7）：**页面**持有 —— 开火入口是页面右上的阳光胶囊，
  /// 它在场景卡之外，经 `GuardSceneCard(battleHandle: …)` 下发到 L4 战斗层。
  /// 战斗层未挂载 / 已收场时 `fire()` 是 no-op（手柄自带闸门）。
  final GuardBattleHandle _guardBattleHandle = GuardBattleHandle();

  /// 教学浮层是否**已经看过**（B7：prefs 永久一次，不再按天重置）。
  ///
  /// 🔴 读失败（prefs 宿主不可用 / 未 override）⇒ 当作**没看过**：
  /// 宁可多讲一遍，也不能因为存储异常让孩子看不到规则；且绝不阻断开战。
  bool _tutorialSeenInPrefs() {
    try {
      return ref.read(sharedPreferencesProvider)
              .getBool(kGuardTutorialSeenPrefKey) ??
          false;
    } catch (e) {
      debugPrint('[Guard] 读「教学已看」失败（按未看过处理）：$e');
      return false;
    }
  }

  /// 标记教学已看（失败一律吞掉：最坏下次再讲一遍，绝不阻断开战）。
  Future<void> _markTutorialSeenInPrefs() async {
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setBool(kGuardTutorialSeenPrefKey, true);
    } catch (e) {
      debugPrint('[Guard] 标记「教学已看」失败（不阻断）：$e');
    }
  }

  /// 点阳光胶囊 → 播一次「阳光四散」。
  ///
  /// **连点策略：先撤旧的、再插新的**（绝不叠两层）。相反做法（忽略新点击）
  /// 会让孩子以为「点了没反应」；撤旧再插的观感更接近「重新炸一次」。
  ///
  /// 🔴 纯视觉：**不加阳光、不写账本、不发奖励**。孩子的阳光余额只由真实
  /// 专注 / 打卡 / 养护产生 —— 这是防「狂点刷阳光」的产品红线。
  void _fireSunBurst(Offset center) {
    if (!mounted) return;
    _removeSunBurst();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned.fill(
        child: SunBurst(origin: center, onComplete: _removeSunBurst),
      ),
    );
    _sunBurstEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _sunBurstTimer = Timer(
      const Duration(milliseconds: kSunBurstDurationMs + 200),
      _removeSunBurst,
    );
  }

  /// 移除爆发浮层（幂等）。
  void _removeSunBurst() {
    _sunBurstTimer?.cancel();
    _sunBurstTimer = null;
    _sunBurstEntry?.remove();
    _sunBurstEntry = null;
  }

  /// 悬浮气泡的漂动时钟（C44i：玄参反馈太陕太窄 → 12s 一圈、振幅放大 ~70%；
  /// Lissajous 轨迹，整数倍谐波 → 无规律小范围飘动感且循环无跳变）。
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..repeat();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _cancelLevelUpFx(); // 根 Overlay 浮层不随本页卸载，必须显式移除。
    _removeSunBurst(); // 同上：爆发浮层也要显式摘掉。
    _drift.dispose();
    super.dispose();
  }

  // ── C68：自动刷新接线（切回本 tab / 回前台 / 跨 08:00 或跨天）───────────────
  @override
  int? get refreshTabIndex => kChildTabIndexOfToday;

  @override
  Future<void> onTabRefreshRequested() => _reload(silent: true);

  /// [silent] = true 时不整页转圈（C68 自动刷新用）——切 tab / 回前台是高频动作，
  /// 闪一下加载圈会让孩子以为「页面重载了」。
  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final DateTime now = DateTime.now();
      final String today = dayKey(now);
      final SunlightRepository sunlight =
          ref.read(sunlightRepositoryProvider);
      final double balance = await sunlight.balance();
      // 「今日获取」= 当日 earn 类型实际发放（net）合计——与孩子端打卡/专注
      // 结算的到账口径一致（§4.5），不含家长赠予/redeem。
      final double todayEarn = await sunlight.earnNetOnDay(today);
      final List<FocusSession> sessions =
          await ref.read(focusRepositoryProvider).sessionsOfDay(today);
      final double focusMinutes = sessions.fold(
          0.0, (double a, FocusSession s) => a + s.actualFocusMin);
      final TodayTaskBoard board =
          await ref.read(taskCheckInServiceProvider).board(now);
      // C74 驱动量：累计有效专注分钟（来自 App 首用至今的全部会话）。
      // ⚠️ 技术债（Q-J）：`totalStats()` 是全量取行后内存求和，当前量级无碍，
      //    超过 ~5 万行再评估改 SQL 聚合 —— v1 不改。
      final double totalFocusMinutes =
          (await ref.read(focusRepositoryProvider).totalStats())
              .totalFocusMinutes;
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _todayEarn = todayEarn;
        _focusMinutes = focusMinutes;
        _focusCount = sessions.length;
        _taskDone = board.doneCount;
        _taskTotal = board.total;
        _totalFocusMinutes = totalFocusMinutes;
        _loading = false;
      });
      // C74 结算必须在 setState 之后：徽章先亮出来，再看是否要播演出。
      await _settleFocusLevel(totalFocusMinutes);
    } catch (_) {
      // 今日卡属概览，任一查询失败不阻塞（保留上次值）。
      if (mounted) setState(() => _loading = false);
    }
    // ── 花园守卫（第三批）────────────────────────────────────────────────
    // 🔴 刻意放在主查询**之后**：胶囊是「附加信息」，主数据先上屏；链路失败 /
    //    超时 ⇒ 视同没有守卫（零占位），绝不让它把今日页变成转圈。
    if (mounted) await _refreshGuard();
  }

  // ── 花园守卫 · 向日葵守卫者（第三批）────────────────────────────────────

  /// 刷新今日守卫视图（`expire() → resolve() → energyAvailable()`）。
  ///
  /// 🔴 **顺序不可换**：`resolve()` 有一道闸门 —— 昨天还有未结算存档时它会
  /// **拒绝覆盖**并返回 `needsExpire == true`。若先 `resolve` 后 `expire`，
  /// 昨天的 `sunStolen` / `growthStolen` 会被今天的状态永久盖掉（对账缺口，
  /// 被偷了却没扣）。故本方法**永远**先 `expire()`。
  ///
  /// 🔴 **整条链有界超时**（[kGuardTodayReadTimeout]）：纯 widget 宿主里某些
  /// 查询会 `await` 永不返回（不是抛错），一旦卡住 `_loading` 就永远为 true、
  /// 今日页只剩转圈。超时 / 异常 ⇒ [GuardTodayView.absent]。
  Future<void> _refreshGuard() async {
    final int token = ++_guardRefreshToken;
    GuardTodayView view;
    // 🔴 B13.4：expire() 的结算结果带出来 —— 昨天没打（pending）⇒ 静默扣账后
    // 要弹「昨晚小怪来过了」报告（玄参拍板：做弹窗、不做自动扣能量豆代打）。
    GuardExpireOutcome? settleOutcome;
    try {
      view = await _loadGuardView(
        onExpired: (GuardExpireOutcome outcome) => settleOutcome = outcome,
      ).timeout(kGuardTodayReadTimeout);
    } catch (e) {
      // 守卫数据不可用是**正常降级**（旧库、权限、超时、首装竞态），
      // 记一行日志即可，绝不冒泡到今日页。
      debugPrint('[Guard] 今日守卫链路不可用，按「没有守卫」处理：$e');
      view = const GuardTodayView.absent();
    }
    if (!mounted) return;
    if (token == _guardRefreshToken) {
      ref.read(guardTodayProvider.notifier).state = view;
    }
    // 次日结算报告（🔴 在 token 检查**之外**：结算只发生这一次，若本次刷新的
    // token 已被更新的刷新顶掉、而新刷新的 expire() 只会拿到同日 none ——
    // 错过就再也不弹。expire 幂等 ⇒ 一天最多弹一次）。
    final GuardExpireOutcome? outcome = settleOutcome;
    if (outcome != null && guardSettleHasNews(outcome)) {
      // 等首帧落完：[_l10n] 在 build 里赋值，首刷可能早于它。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final AppLocalizations? t = _l10n;
      if (t != null) {
        unawaited(showGuardSettleReport(context, t, outcome));
      }
    }
  }

  /// 真正的守卫读链路（无自捕获：超时/异常由 [_refreshGuard] 统一兜住）。
  Future<GuardTodayView> _loadGuardView({
    void Function(GuardExpireOutcome outcome)? onExpired,
  }) async {
    // service 在第一个 await 之前取好 —— 之后不再碰 `ref`（页面已卸载也安全）。
    final GuardService service = ref.read(guardServiceProvider);
    final GuardExpireOutcome expired = await service.expire();
    onExpired?.call(expired);
    final GuardResolveResult resolved = await service.resolve();
    // ③ 剩余能量：成本模式（免费 / 付费 / 免罚）的输入。`resolve()` 内部也读过
    //    一次，这里按接线契约**显式**再读，使「expire → resolve → energyAvailable」
    //    三连在源码上可逐行审计（也保证胶囊用的是**最新**能量）。
    final int energy = await service.energyAvailable();

    // F4：结算卡「券还能省 N」要按**实际称号单价**算（免费券随称号减免变小）。
    // 🔴 独立 try/catch 降级为 [PlantPerk.none]：读称号失败 **不能** 连累胶囊消失
    //    （本方法外层的 catch 会把整条链路判成 absent）。
    PlantPerk perk = PlantPerk.none;
    try {
      perk = await ref.read(currentPlantPerkProvider.future);
    } catch (e) {
      debugPrint('[Guard] 读称号属性失败，券节省按无称号算：$e');
    }

    // `fromResolve` 已处理两条降级：needsExpire（昨天欠结算）/ 今天无贼 ⇒ absent。
    final GuardTodayView base =
        GuardTodayView.fromResolve(resolved, perk: perk);
    if (!base.isVisible) return base;
    return base.copyWith(
      mode: guardPillModeOf(base.state, energy, base.balance),
      energyAvailable: energy,
    );
  }

  /// 点场景卡「开始守卫」：教学闸门（首次）→ 确认卡（付费）→ 落盘「已进战斗」
  /// → 场景卡切入战斗态。战斗本体在**卡内 L4**跑（`GuardBattleField`，ticker
  /// 喂 sim）；终局（Victory / Retreat）由 [GuardSceneCard.onBattleFinished]
  /// 回调 [_onBattleFinished] 接结算卡 —— v1 的战斗浮层（dialog）已随 B3 退役。
  Future<void> _onGuardCardTap() async {
    if (_guardBusy || !mounted) return;
    final GuardTodayView view = ref.read(guardTodayProvider);
    final GuardThiefKind? thief = view.thief;
    final AppLocalizations? t = _l10n;
    if (!view.isActionable || thief == null || t == null) return;

    _guardBusy = true;
    try {
      // ⓪ 教学浮层（B2 新增，PRD §6「A 为主」）：**一辈子只讲一次**。
      //
      // 🔴 B7 修复（玄参真机：「每天都要再看一遍」）：判据从当日存档的
      //    `GuardDayState.tutorialSeen`（跨天被新存档重置）改为**设备级 prefs**
      //    [kGuardTutorialSeenPrefKey]。浮层只做展示；prefs 读不到 ⇒ 当作没看过
      //    （宁可多讲一遍也不让孩子看不到规则），写失败吞掉 ⇒ 绝不阻断开战。
      if (!_tutorialSeenInPrefs()) {
        await showGuardTutorialSheet(context: context, l10n: t);
        if (!mounted) return;
        await _markTutorialSeenInPrefs();
        if (!mounted) return;
        // 兼容保留：当日存档里的 `tutorialSeen` 照旧打上（老存档 / 老逻辑的
        // 向后兼容），但它**已不驱动弹层**。写失败同样不阻断。
        try {
          await ref.read(guardServiceProvider).markTutorialSeen();
        } catch (e) {
          debugPrint('[Guard] 标记「教学已看」（存档）失败（不阻断）：$e');
        }
        if (!mounted) return;
      }

      // ① **两条路径都先弹确认卡**（B13.7 玄参：「在有能量的情况下，点击开始
      //    战斗按钮，也需要弹出确认卡片，防止误操作」）：
      //    · 付费路径：标题带花费（原口径）；
      //    · 能量路径：不提阳光（不花钱），只问「要派出战士吗」。
      if (view.needsPayConfirm) {
        final bool? confirmed = await showChildConfirmCard(
          context: context,
          title: t.guard_confirm_pay_title(kGuardPayCost),
          confirmLabel: t.shared_ok,
          // 🔴 必须显式传：弹窗上下文在页级 L10nScope 之外，靠默认值会回落中文。
          cancelLabel: t.guard_confirm_pay_later,
        );
        if (confirmed != true || !mounted) return;
      } else {
        final bool? confirmed = await showChildConfirmCard(
          context: context,
          title: t.guard_confirm_free_title,
          confirmLabel: t.shared_ok,
          cancelLabel: t.guard_confirm_pay_later,
        );
        if (confirmed != true || !mounted) return;
      }

      // ② 落盘「已进战斗」：孩子看完战斗后强杀进程 / 闪退 / 没电，次日
      //    `expire()` 会走 `fighting` 分支（**补发**必得阳光、**不结算**损失），
      //    而不是把他当「压根没管」照罚。必须发生在**开战之前**（B3 复核：
      //    仍在 provider 切 fighting（= 卡挂 L4 战斗层）之前一步，语义保位），
      //    否则杀进程的窗口期就落回 `pending`。
      //    🔴 只经领域服务写存储（`GuardStateStore` 文档：页面不得直接写）。
      //    写失败不阻断战斗 —— 最坏退回 `pending`（= 不标记的既有行为）。
      try {
        await ref.read(guardServiceProvider).markFighting();
      } catch (e) {
        debugPrint('[Guard] 标记「战斗中」失败（不阻断战斗）：$e');
      }
      if (!mounted) return;
      // 🔴 B13 图鉴解锁：这场战斗里出现的怪种记入「已遇到」（开战即解锁）。
      // 与 L4 上屏战局**同一份剧本**（调试覆盖优先，覆盖 null = 真实 seed 派生）；
      // 失败吞掉（图鉴少一格，绝不阻断开战）。
      try {
        final SharedPreferences sp = ref.read(sharedPreferencesProvider);
        final GuardBattleScript battleScript =
            ref.read(debugGuardBattleScriptOverrideProvider) ??
                deriveGuardBattleScript(
                  dayKey: dayKey(DateTime.now()),
                  childId: ref.read(accountServiceProvider).childId,
                );
        await recordMetMonsterKinds(
          battleScript.monsters
              .map((GuardBattleMonsterSpec m) => m.kind),
          sp,
        );
      } catch (e) {
        debugPrint('[Guard] 记录图鉴解锁失败（不阻断）：$e');
      }
      if (!mounted) return;
      // 结算卡用**进入战斗前的快照**：`claim()` 的奖品由 `resolve()` 定死，
      // 与战局输赢无关（v1 ④ 同口径，搬到终局回调里用）。
      _battleView = view;
      // 切 fighting ⇒ 卡挂 L4 战斗层（sim 零落盘：战局进度只活在 widget 树里，
      // 强杀 / 重挂 = 战局重开，账本零新增行；落账只发生在打完之后的 claim）。
      ref.read(guardTodayProvider.notifier).state =
          view.copyWith(mode: GuardPillMode.fighting);
      debugPrint('[Guard] 战斗开始（卡内 L4）：seed=$thief '
          'day=${view.state.dayKey}');
    } catch (e) {
      // 确认 / 标记异常不弹错误框：最坏结果是「明天再来」。
      debugPrint('[Guard] 进入战斗失败：$e');
      _battleView = null;
    } finally {
      _guardBusy = false;
    }
  }

  /// L4 战斗层终局回调（Victory / Retreat 各一次）：先落账「被偷」（B4 新增），
  /// 再接**既有**结算卡流 —— v1 `_onGuardCardTap` 的 ④ 段原样保留，claim 语义 /
  /// 幂等 / 账本口径一行不动。
  ///
  /// [battleStolenSun] = sim 终局报告的实际被偷合计（含 30s 到点时刻的钳制值；
  /// 取数链路：sim 报告 → 本方法 → 结算卡）。
  Future<void> _onBattleFinished(int battleStolenSun) async {
    if (_guardBusy || !mounted) return;
    final GuardTodayView? view = _battleView;
    final AppLocalizations? t = _l10n;
    if (view == null || t == null) return; // 防御：无快照（理论不可达）
    _guardBusy = true;
    try {
      // ③½ 落账「被偷」（B4，§5.3 裁决 B「结束时一次写」）：战斗态零落盘，
      //    被偷额只活在 sim 内存里，打完这一场才由本处**一次**写入 —— 同日
      //    至多 1 行 `guard_stolen`（领域层自带读判定互斥，防与 expire 半截
      //    时序双扣）。
      //    🔴 失败不阻断结算卡：存储异常吞掉 + `[Guard]` 日志（与守卫链的
      //    独立 try/catch 同范式）—— 绝不让「被偷没记上」导致孩子多看一张卡
      //    或多扣一次。落账失败 ⇒ 实扣 0 ⇒ 结算卡**不渲染**被偷行（卡面 N
      //    恒 == 账本行，见 [showGuardResultCard] 的 stolenSun 契约）。
      int stolenCharged = 0;
      try {
        stolenCharged = await ref
            .read(guardServiceProvider)
            .recordBattleTheft(stolenSun: battleStolenSun);
        debugPrint('[Guard] 战斗被偷落账: sim=$battleStolenSun → '
            '实扣=$stolenCharged');
      } catch (e) {
        debugPrint('[Guard] 落账「被偷」失败（不阻断结算卡）：$e');
      }
      if (!mounted) return;
      // ④ 结算卡：「收下」才 `claim()`（唯一记账入口，领域层自带三层幂等）。
      //    stolenSun 传**账本实扣额**（recordBattleTheft 返回值），不传 sim
      //    原始值 —— 余额不足 / 已写过时实扣 < sim 值，卡面必须与账本一致。
      final GuardClaimOutcome? outcome = await showGuardResultCard(
        context,
        view: view,
        l10n: t,
        stolenSun: stolenCharged,
        onCollect: () => ref.read(guardServiceProvider).claim(),
      );
      if (outcome == null) return;
      ref.read(guardTodayProvider.notifier).state =
          GuardTodayView.fromClaim(outcome, perk: view.perk);
      if (outcome.ok) {
        // 既有跨页刷新总线（花园页 / 我的页 / 今日阳光卡都在听）。
        ref.read(economyRevisionProvider.notifier).state++;
        // 🆕 claim() 同时改写了守卫存档（落当日 buff 券）⇒ 通知花园页重读
        // 券快照，让左上角胶囊与「今天便宜一点」的价格同步（玄参真机 ③）。
        ref.read(guardBuffRevisionProvider.notifier).state++;
        // 诊断日志（玄参 2026-11-09 晚：真机「收下后回花园无券」仍复现一次，
        // 全链路测试均绿 ⇒ 需真机日志分辨「bump 是否到达」）：
        debugPrint('[Guard] claim ok: drop=${outcome.drop.name} '
            'buff=${outcome.buff?.kind.name ?? 'null'} → bump economy+guardBuff');
      } else {
        debugPrint('[Guard] claim 失败: ${outcome.failure}（不 bump）');
      }
    } catch (e) {
      // 领取异常不弹错误框：孩子已经看完战斗，最坏结果是「明天再来」。
      debugPrint('[Guard] 结算或领取失败：$e');
    } finally {
      _guardBusy = false;
      _battleView = null;
      // 无论成功、失败还是中途退出，都以存储为事实源校正一次卡态。
      if (mounted) await _refreshGuard();
    }
  }

  // ── C74 · 专注等级结算 + 升级演出（只在今日页；§5.24.3 / §5.24.6）────────

  /// 结算本轮等级（**C78：零阳光、零账本写入**），再按结果决定是否播演出。
  ///
  /// 🔑 只有**跨过称号节点**时 `granted` 非空 → 自增经济修订号 + 播 1 场演出；
  /// 普通升级（40 级里的另外 31 次）零演出，只更新徽章进度。
  /// 失败一律记日志后吞掉（S10：`catch(_)` 静默吞 = 泄漏），**不阻塞今日页渲染**。
  Future<void> _settleFocusLevel(double totalFocusMinutes) async {
    try {
      final FocusLevelSettleResult result =
          await ref.read(focusLevelServiceProvider).settle(totalFocusMinutes);
      if (!mounted) return;
      // 🔑 C74 §6 **修订二** + C78：每次升级都播演出，称号节点不再发阳光。
      //  `levelUpFxKindOf` 返回 null = 没升级 / 老用户首用静默 ⇒ 什么都不做。
      final LevelUpFxKind? kind = levelUpFxKindOf(result);
      if (kind == null) return;
      if (kind == LevelUpFxKind.titleNode) {
        // 属性已随等级纯派生生效 → 同步孩子端经济展示（今日阳光 / 我的页 / 花园胶囊）。
        ref.read(economyRevisionProvider.notifier).state++;
      }
      // 演出只在**今日页可见**时上屏（§5.24.4：不可见 ⇒ 只结算不播；
      // 演出属庆祝不补播）。
      // F138：可见性 = 外壳在台前 **且** 当前 tab 是今日（只看索引会把「外壳已销毁、
      // 记忆仍停在今日」误判成可见 —— 与花园氛围音同源的口径缺陷）。
      final bool visible = ref.read(childShellOnStageProvider) &&
          ref.read(childShellTabIndexProvider) == kChildTabIndexOfToday;
      if (visible) await _showLevelUpFx(result, kind);
    } catch (e) {
      // 结算失败不影响今日页任何既有功能（等级是纯荣誉）。
      debugPrint('[FocusLevel] 结算失败：$e');
    }
  }

  /// 播一场升级演出（根 Overlay + in-flight 闸门，保证一次进页至多一场）。
  ///
  /// ⚠️ 普通升级的演出频次是称号节点的数倍（40 级全升完播 39 场）→ 闸门必须只
  /// 放行一场；跨多级一次结算也**只播一场**（用最高节点对应的素材）。
  /// [frames] 先解析好再建浮层（解析是 async，不能在 OverlayEntry.builder 里做）。
  Future<void> _showLevelUpFx(
    FocusLevelSettleResult result,
    LevelUpFxKind kind,
  ) async {
    if (!mounted || _levelUpFxInFlight) return;
    _levelUpFxInFlight = true;
    final LevelUpFxSpec spec = levelUpFxSpecOf(kind);
    final List<String> frames = await resolveFxFrames(
      spec.dir,
      ext: spec.frameExt,
      fallbackCount: spec.fallbackFrameCount,
    );
    if (!mounted) {
      _levelUpFxInFlight = false; // 解析期间已卸载：直接解除闸门
      return;
    }
    final OverlayEntry entry = levelUpFxOverlayEntry(
      result: result,
      frames: frames,
      onComplete: _removeLevelUpFx,
    );
    _levelUpFxEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    // 兜底：演出 onComplete 因任何原因未触发也保证浮层被清走 + 解除闸门。
    _levelUpFxTimer = Timer(
      Duration(milliseconds: spec.totalMs + 300),
      _removeLevelUpFx,
    );
  }

  /// 移除演出浮层（幂等；唯一的闸门解锁口）。
  void _removeLevelUpFx() {
    _levelUpFxTimer?.cancel();
    _levelUpFxTimer = null;
    _levelUpFxEntry?.remove();
    _levelUpFxEntry = null;
    _levelUpFxInFlight = false;
  }

  /// 页面卸载：停定时器并摘浮层（不触碰 ref —— Riverpod 纪律）。
  void _cancelLevelUpFx() {
    _levelUpFxTimer?.cancel();
    _levelUpFxTimer = null;
    _levelUpFxEntry?.remove();
    _levelUpFxEntry = null;
    _levelUpFxInFlight = false;
  }

  @override
  Widget build(BuildContext context) {
    // 经济修订号变化（打卡 / 核销 / 兑换）→ 重新拉取，保证数字同步。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload();
    });

    // 🔴 守卫当日状态**必须 watch**（不是 read）：`_entTier` 用 read 导致
    // 「买了会员界面不刷新」的教训。胶囊 / 第四批的 buff chip / 调试面板
    // 全部 watch 这同一个实例，任一处写完另一处自动刷新。
    final GuardTodayView guardView = ref.watch(guardTodayProvider);

    // 🔴 E2（玄参真机报「调试面板点强制剧本没响应」的另一半）：调试「强制
    // 剧本」按钮在**花园页**面板里，而本页在 IndexedStack 后台保活 —— 面板
    // 写的是 store，本页的 [guardTodayProvider] 快照只有 `_refreshGuard` 才
    // 会更新 ⇒ 不 listen 就永远不重读，卡片停在旧态（待机时甚至不出卡）。
    // 覆盖变化 ⇒ 立即重读守卫状态。release 该 provider 恒 null、永不变化
    // ⇒ 本 listen 零生产影响。
    ref.listen<GuardBattleScript?>(
      debugGuardBattleScriptOverrideProvider,
      (_, GuardBattleScript? __) => _refreshGuard(),
    );

    // C44 验收反馈（玄参 2026-10-09，参照期望图重排）：
    // ①上半场景（向日葵+积木插画）完整露出，卡片从 [kTodayCardTopRatio] 屏高开始
    //   （0.42 → C65 0.37 → C67 **0.40**）；
    // ②「我的阳光」改悬浮气泡飘在向日葵右半侧；
    // ③「开始专注」按钮钉在底部；④只有中间状态卡可滚动。
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        // LayoutBuilder 量到的就是 [TabBackground] 的真实盒子（DecoratedBox 原样
        // 透传约束）→ 卡片起点才能与底图分界线**同源反算**（见 [_buildLayout]）。
        : LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              // i18n（B1）：LayoutBuilder 上下文在 L10nScope 之内 → 此处取文案
              // 存入 [_l10n]，供下方 [_buildLayout]（State 方法，用的 State 上下文
              // 在 scope 之外）取用。
              _l10n = AppLocalizations.of(context);
              return _buildLayout(box: c.biggest, guard: guardView);
            },
          );

    // C44：整页背景（上半场景 + 下半留白，白卡浮在留白区上）。
    //
    // F142（玄参 2026-10-20 拍板）：**平板**下底图整体再下移
    // [tabletContentDownshiftOf]（随屏宽等效 pt）—— 换算成比例后传给
    // [TabBackground]，手机仍原样传 [kTodayBgPanelTargetRatio]（0.37）。
    // ⚠️ 只改**传进去的**比例，不改 C67 冻结常量本身（见 `test/qa/focus_level_guard_test.dart`）。
    // i18n（B1）：页级 L10n 范围 —— 裸 MaterialApp 测试宿主（无 delegates）也能取文案。
    return L10nScope(
      child: TabBackground(
      asset: kTodayBgAsset,
      // C67：底图锚点**冻结**在 [kTodayBgPanelTargetRatio]（=0.37），**不跟**卡片下移
      // —— 玄参明确「背景图片的位置已经比较合适了」（互相关实证背景像素零变化）。
      // F142 平板例外：玄参新反馈「背景图也偏上」→ 平板下随屏宽等效下移。
      panelTargetRatio: _panelTargetRatio,
      fallbackColor: const Color(0xFFFBF4E4),
      child: body,
      ),
    );
  }

  /// 平板「漂浮阳光」气泡的**半高**（F142 四轮）：气泡总高 ~34pt（白底胶囊，
  /// 见 `_FloatingSunBubble`），「与花头齐平」= 气泡中心 ≈ 花脸中心 →
  /// `top = 花脸中心屏上 y − 本值`。
  /// i18n（B1）：页内文案（LayoutBuilder scope 内上下文解析，见 build）。
  AppLocalizations? _l10n;

  static const double _kSunBubbleHalfHeight = 17.0;

  /// 平板内容下移量（**随屏宽线性放大**，F142 三轮）；手机恒 `0`（逐像素零回归）。
  ///
  /// 一轮 40 / 二轮 100（玄参实测「感知不到」后加码）→ 三轮按屏宽比例化：
  /// 底图 cover 缩放 ∝ 屏宽，同量下移在 iPad 13″ 被「图放得更大」稀释
  /// （头顶比 11″ 反而高 ≈16pt，玄参截图实证「胶囊和向日葵头顶还是那么近」）。
  /// 见 `responsive.tabletContentDownshiftOf` / `kTabletDownshiftReferenceWidth`：
  /// iPad 11″ = 100（基准不变）/ iPad 13″ ≈ 123.7 / 手机 = 0（零回归）。
  double get _contentDownshift => tabletContentDownshiftOf(context);

  /// 底图锚点比例：平板按下移量**等效换算**（比例 = pt / 屏高）。
  ///
  /// 手机（`_contentDownshift == 0`）→ **逐位等于** [kTodayBgPanelTargetRatio]（0.37）。
  /// 平板 iPad 11″（1210）→ 0.37 + 100/1210 ≈ 0.4527；iPad 13″（1376）→ 0.37 + 123.7/1376 ≈ 0.4599。
  ///
  /// 🔴 [build] 与 [_buildLayout] **必须**共用本 getter：前者决定底图怎么画，
  /// 后者用它反算分界线；两处不同源会让「卡片呼吸带」与真实分界线错位。
  double get _panelTargetRatio {
    final double h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return kTodayBgPanelTargetRatio;
    return kTodayBgPanelTargetRatio + _contentDownshift / h;
  }

  /// 布局：`Stack[ 场景留白 + 卡片滚动区 + 钉底按钮 , 悬浮阳光气泡 ]`。
  ///
  /// [guard] = 今日守卫快照（第三批）。`GuardPillMode.absent` 时**零占位**：
  /// 连空 `SizedBox` 都不插，`ListView` 的子项与无守卫时逐项相同。
  ///
  /// ⚠️ **已知且接受的代价**：胶囊占了 `kGuardPillHeight + kGuardPillGap` = 54pt，
  /// 小屏 / 大字号下三张统计卡需要向下滚一点才能全部看见。实测（RenderBox）：
  ///  · 390×844 外壳宿主：列表内容高度 +54pt ⇒ `maxScrollExtent` 由 **0 → 30.1pt**；
  ///  · 320×554 + 1.3 倍字号：`maxScrollExtent` **268.4pt**，第三张卡需滚 208.3pt。
  /// 故本页**不**承诺「今日页零滚动」；「胶囊存在时三张卡仍可通过滚动触达」由
  /// `test/child/shell_narrow_large_text_test.dart` 与
  /// `test/guard/guard_pill_test.dart` 两处护栏覆盖。
  Widget _buildLayout({required Size box, required GuardTodayView guard}) {
    final double screenH = MediaQuery.sizeOf(context).height;
    final double screenW = MediaQuery.sizeOf(context).width;
    // F142：平板内容整体下移（随屏宽，手机恒 0，见 [tabletContentDownshiftOf]）。
    final double downshift = _contentDownshift;
    // 底图分界线（**实测反算**，与 TabBackground 同源；未登记几何 ⇒ -inf）。
    // ⚠️ 必须传 [_panelTargetRatio]（含平板下移等效比例）而不是裸常量，
    //    否则平板下「量到的分界线」与「画出来的分界线」会错开一个下移量。
    final double panelLineY = TabBackground.panelLineY(
      context: context,
      box: box,
      asset: kTodayBgAsset,
      targetRatio: _panelTargetRatio,
    );
    // 第一张卡起点：C67 冻结值 `0.40 × 屏高` **与**「实测分界线 + 3% 呼吸带」取大。
    // 平板上两者相等（⇒ iPad 零变化）；手机上分界线被 cover 抬高，取大即把卡片
    // 压回分界线下方，恢复呼吸带（见 [kTodayBreathingBandRatio] 的推导）。
    // 直接用屏高比例定位（实测模拟器 padding.top ≈118pt
    // 双倍计入，减 topInset 反而会把卡片顶回 20%，故与 topInset 解耦）。
    //
    // F142：下移量只加在**第一条**（冻结基线）上，而不是加在 `max()` 之后 ——
    // 第二条已经因底图锚点同步下移而自动含了这个下移量，两者在平板上恰好相等
    // （0.40H + downshift），加在 max 之后会变成 +2×downshift（卡片压掉半张统计卡）。
    final double sceneGap = math.max(
      screenH * kTodayCardTopRatio + downshift,
      panelLineY + screenH * kTodayBreathingBandRatio,
    );

    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            // 场景区：只占位不渲染内容，露出背景插画。
            //
            // 🔴 B10/B1：场景卡「整体上移」不再用 `Transform`，而是把**滚动区
            // 整体上移** [kGuardCardLift]（16pt）。原因：`Transform` 不消耗布局
            // 空间 ⇒ 卡的绘制矩形被顶到 ListView 视口之外，被 `ClipRect` 直接
            // 裁掉 —— 玄参第五轮报的「房子被削顶」就是这个。缩留白之后
            // 视口顶边随之上移 16pt，卡仍在视口内 y=0 ⇒ **卡顶 == 视口顶边**，
            // 整张卡合法可见（`guard_scene_card_visible_test` 硬断言）。
            // 钳 ≥ 0：极矮屏 / 平板下移叠加时不允许出现负高度。
            SizedBox(
              height: math.max(
                sceneGap - (guard.isVisible ? kGuardCardLift : 0),
                0,
              ),
            ),
            // 中间：状态卡 + 引导文案，唯一可滚动区域。
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: <Widget>[
                  // ── 花园守卫场景卡（守卫战 v2 · B2）──────────────────────
                  // 第 0 项：三张统计卡之前。`absent` ⇒ 一项都不插（零占位）。
                  // 高度恒 kGuardSceneCardHeight（B10 布局 v6 = **112**，
                  // = padTop 14 + 房子 88 + padBottom 10；不随字号缩放，
                  // F127 抗溢出口径）。宽度见下方 OverflowBox（满宽贴边）。
                  if (guard.isVisible) ...<Widget>[
                    // 🔴 B8/A4：场景卡**满宽贴边** —— ListView 有 16pt 横向
                    // 内边距，但玄参要「草地条横向铺到屏幕边」（去框之后卡不再
                    // 有圆角容器，边到边才不显得被切）。做法：给卡套一层
                    // OverflowBox，把宽度撑到 screenW、左右各溢出 16pt ——
                    // 溢出量仍在视口内，ListView 的裁剪不会真的切掉内容。
                    // ⚠️ 高度必须是**紧约束**（ListView 子项高度无界，
                    // OverflowBox 自己按 incoming constraints 定尺寸）。
                    // 🔴 B10/B1：**不再包 Transform**（B9 的上移改成缩上面的
                    // `sceneGap`，见那里的注释）—— 卡在视口内从 y=0 开始画，
                    // 顶边不会被 ListView 裁掉。
                    SizedBox(
                      height: kGuardSceneCardHeight,
                      child: OverflowBox(
                        minWidth: screenW,
                        maxWidth: screenW,
                        child: GuardSceneCard(
                          view: guard,
                          // sim seed 入参：战局剧本 = f(dayKey, childId)，
                          // 与守卫存档 / 奖励口径同源（同日同孩逐位相同）。
                          dayKey: dayKey(DateTime.now()),
                          childId: ref.read(accountServiceProvider).childId,
                          onStart: _onGuardCardTap,
                          onBattleFinished: _onBattleFinished,
                          // B7：开火手柄由页面持有（阳光胶囊在卡外，见 build 的
                          // `_FloatingSunBubble` 挂载点）。
                          battleHandle: _guardBattleHandle,
                          // B5a 调试剧本覆盖：仅 kDebugMode 的调试面板会写入该
                          // provider（release 恒 null ⇒ 走真实 seed 派生，零感知）。
                          debugScriptOverride:
                              ref.watch(debugGuardBattleScriptOverrideProvider),
                        ),
                      ),
                    ),
                    // 卡后间距：**保持 kGuardPillGap(10)**。上移 16 已经落在
                    // 上方 sceneGap 里了，这里再扣就会把统计卡多顶上去 10pt。
                    const SizedBox(height: kGuardPillGap),
                  ],
                  _StatCard(
                    icon: Icons.trending_up,
                    // C48：玄参 2026-10-10 —— 三卡图标用 UI 素材。
                    assetIcon: 'assets/rewards/sunlight.png',
                    color: const Color(0xFFE8890C),
                    label: _l10n!.child_today_sunlight_title,
                    // F105 口径：展示一律 sunlightDisplayInt（向下取整）。
                    value: '+${sunlightDisplayInt(_todayEarn)}',
                    unit: '☀',
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.timer,
                    assetIcon: 'assets/ui/growth/focus.webp',
                    color: Colors.teal,
                    label: _l10n!.child_today_focus_label,
                    value: _l10n!.child_today_minutes(_focusMinutes.round()),
                    unit: _l10n!.child_today_focus_count(_focusCount),
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.checklist,
                    assetIcon: 'assets/ui/growth/habit.webp',
                    color: Colors.indigo,
                    // 口径与「任务」tab 一致：仅「今日必做（isDaily）」。
                    // doneCount/total 由 [TodayTaskBoard] 保证只统计 isDaily 项。
                    label: _l10n!.child_today_growth_label,
                    value: '$_taskDone / $_taskTotal',
                    unit: _taskTotal > 0 && _taskDone >= _taskTotal
                        ? _l10n!.child_today_all_done
                        : '',
                  ),
                  const SizedBox(height: 14),
                  // 引导：只有从「成长」tab 的具体成长项进入专注，达标后才会自动
                  // 结算该项阳光（本页的「开始专注」是自由专注入口，不联动结算）。
                  Text(
                    _l10n!.child_today_growth_hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
                  ),
                ],
              ),
            ),
            // 钉底主按钮：不随卡片滚动，常驻导航栏上方（玄参 2026-10-09）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/entry'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_l10n!.shared_start_focus),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
        // 悬浮阳光气泡：飘在向日葵右侧书架前空地（玄参 2026-10-09 三轮反馈
        // 蓝框标注，cv2 模板匹配实测屏幕区域 x 65.5-89.5% / y 23.9-29.8%，
        // 匹配置信度 0.92）。锚点=蓝框中心回推气泡左上角（气泡 ~98×34pt）。
        // F142 二/三轮：平板与卡片/底图同向下移（随屏宽，手机 +0）。
        // F142 四轮（玄参拍板「平板的漂浮阳光往上移到与向日葵头部齐平」）：
        // 平板改为**气泡中心 ≈ 花脸中心 y**——经分界线实测值反算（cover 几何，
        // 下移/切 tab 自动同步，见 [bgScreenYFromPanelLine]）；手机保持 cv2
        // 蓝框定稿 0.25H（花头右侧偏下的书架空地）**零回归**。
        Positioned(
          left: screenW * 0.65,
          top: isTabletOf(context)
              ? bgScreenYFromPanelLine(
                  panelLineScreenY: panelLineY,
                  box: box,
                  src: kTodayBgSrcSize,
                  panelTopFraction: kTodayBgPanelTopFraction,
                  fraction: kTodayBgSunflowerHeadCenterYFraction,
                ) -
                  _kSunBubbleHalfHeight
              : screenH * 0.25 + downshift,
          child: _FloatingSunBubble(
            capsuleKey: ChildTodayPage.sunBubbleKey,
            balance: _balance,
            drift: _drift,
            // 🔴 B7（玄参裁定）：守卫战进行中 ⇒ 胶囊**停止漂浮**（位置钉死），
            // 并临时变成「开火按钮」：点它 = 让小小葵打一枪（走页面持有的
            // GuardBattleHandle，400ms 冷却 / 终局禁用语义全部不变）。
            // 非战斗态 ⇒ 恢复原漂浮轨迹 + 「阳光四散」纯视觉特效（F170）。
            firing: guard.mode == GuardPillMode.fighting,
            onFire: () => _guardBattleHandle.fire(),
            // F170：点击 → 阳光四散（纯视觉，见 [_fireSunBurst]）。
            onBurst: _fireSunBurst,
          ),
        ),
        // C74 · 专注等级徽章。
        // 🔴 不改本页任何冻结常量：卡片起点 [kTodayCardTopRatio] 与底图锚点
        // [kTodayBgPanelTargetRatio] 均未改动，徽章只是场景区上方的**新增元素**。
        //
        // · 手机：左上角（[kTodayBadgeLeftRatio] / [kTodayBadgeTopRatio]）—— 零回归。
        //   手机上徽章底边 ≈ 花头顶（0.11H + 徽章高 ≈ 花头 cover 顶 134pt）。
        // · 平板（F142 四轮，玄参拍板「按 iPhone 的布局放回左上角」）：**弃用 v4
        //   右对齐锚点**，同款左上比例；top 锚「花头立绘顶 − [kTodayBadgeHeadGap]」
        //   再用 `FractionalTranslation(0,-1)` 整体上移自身高度 = **贴在花头上方**。
        //   为什么不直接用 0.11H+downshift：cover 放大把「0.11H vs 花头 0.18 图内」
        //   的手机相对关系拉散（平板 0.11H+100 ≈ 219 会压进花脸 140~505），
        //   故平板必须跟花头**几何**走；挂到分界线实测值上，下移/切 tab 自动同步。
        //   （v4 右对齐的根因「花头抬到 y≈44 墙区被占」已被 F142 平板整体下移
        //   缓解——花头顶回到 ≈140，pill 与花头之间放得下徽章。）
        Positioned(
          left: screenW * kTodayBadgeLeftRatio,
          top: isTabletOf(context)
              ? bgScreenYFromPanelLine(
                  panelLineScreenY: panelLineY,
                  box: box,
                  src: kTodayBgSrcSize,
                  panelTopFraction: kTodayBgPanelTopFraction,
                  fraction: kTodayBgSunflowerNormalizedRect.top,
                ) -
                  kTodayBadgeHeadGap
              : screenH * kTodayBadgeTopRatio + downshift,
          child: isTabletOf(context)
              ? FractionalTranslation(
                  translation: const Offset(0, -1),
                  child: FocusLevelBadge(
                    progress: progressOf(_totalFocusMinutes),
                    totalMinutes: _totalFocusMinutes,
                  ),
                )
              : FocusLevelBadge(
                  progress: progressOf(_totalFocusMinutes),
                  totalMinutes: _totalFocusMinutes,
                ),
        ),
      ],
    );
  }
}

/// 「我的阳光」悬浮气泡：白底圆角胶囊 + 阳光余额，沿 Lissajous 轨迹
/// 无规律小范围飘动（x 振幅 ~11pt / y ~10pt，7s 一圈，玄参 2026-10-09）。
/// C44g 三轮反馈：锚点移到向日葵右侧书架前空地（蓝框标注实测 x65%/y25%），
/// 删尾部「☀」双太阳重复。
///
/// **C67（2026-10-13 晚 玄参 iPad 实测）——整体放大**：玄参「飘动的阳光胶囊
/// 可以适当放大一些，把里面的阳光图标变大一些」。胶囊 12/6 → **13/7** 内边距、
/// 圆角 24 → **26**、图标 22 → **30**（+36%，主导放大）、文字 18 → **19**、
/// 图标与数字间距 6 → **7**。胶囊高 36.3 → **44pt**（+21%）。
/// ⚠️ 手机端（402pt 宽）右侧边界复核：锚点左缘 0.65×402 = 261.3pt，胶囊宽
/// ≈ 13+30+7+42+13 = 105pt，加最大水平漂移 31.9pt → 右缘 ≈ **398pt < 402pt**（不越屏）。
///
/// 🔴 **F170（玄参 2026-11-01）——可点击 + 阳光四散**：胶囊从纯展示变成**可点**。
/// 点击 → ① 数字轻弹一下（220ms，1.0→1.16→1.0，即时触觉反馈）；
/// ② 上报**爆发圆心（全局坐标）**给页面，由页面插根 Overlay 播 [SunBurst]。
/// 组件自身**不碰经济**（无奖励、无账本），只负责「点我 → 给坐标」。
///
/// 🔴 **B7（玄参 2026-11-10）——守卫战期间变身开火键**：守卫战进行中
/// （[firing] = true）胶囊 ①**停止漂浮**（位置钉死：开火要瞄一个不动的目标）；
/// ②点击改为**开火**（`onFire` → `GuardBattleHandle.fire()`，400ms 冷却 /
/// 终局禁用语义全在领域层，胶囊只递「按」）；③不再播四散（战斗信号优先）。
/// 战斗结束后自动恢复原漂浮轨迹 + 四散特效 —— 两条路径互斥、零状态残留。
class _FloatingSunBubble extends StatefulWidget {
  final double balance;
  final Animation<double> drift;

  /// 胶囊容器的 Key（度量护栏用，由页面传入 [ChildTodayPage.sunBubbleKey]）。
  final Key? capsuleKey;

  /// 点击胶囊 → 回调**爆发圆心全局坐标**（页面据此插根 Overlay）。
  /// 为 null 时该形态不可点（保留旧的纯展示语义，供只做度量的测试使用）。
  final ValueChanged<Offset>? onBurst;

  /// 🔴 B7：守卫战进行中 = true ——
  ///  · **停止漂浮**（`Transform.translate` 归零，位置钉死，连测逐位相同）；
  ///  · 点击改为**开火**（走 [onFire]，不再播「阳光四散」—— 战斗中的每一次
  ///    点击都该有战局意义，四散特效会盖住信号弹）。
  final bool firing;

  /// 战斗态点击 → 开火（页面传 `() => handle.fire()`）。
  final VoidCallback? onFire;

  const _FloatingSunBubble({
    required this.balance,
    required this.drift,
    this.capsuleKey,
    this.onBurst,
    this.firing = false,
    this.onFire,
  });

  @override
  State<_FloatingSunBubble> createState() => _FloatingSunBubbleState();
}

class _FloatingSunBubbleState extends State<_FloatingSunBubble>
    with SingleTickerProviderStateMixin {
  /// 点击后的数字轻弹（有限时长，绝不无限循环 → 不干扰 `pumpAndSettle` 纪律）。
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _popScale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 38,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.16, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 62,
      ),
    ],
  ).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    // 数字轻弹：连点直接从头重播（`forward(from:0)` 幂等，不叠加控制器）。
    // 战斗中同样轻弹 —— 这是「点到了」的即时反馈（开火是否被冷却拦下由 sim
    // 决定，反馈不带战局含义）。
    _pop.forward(from: 0);
    // 🔴 B7：战斗中点击 = 开火（不播四散，站位也不动）。
    if (widget.firing) {
      widget.onFire?.call();
      return;
    }
    final ValueChanged<Offset>? onBurst = widget.onBurst;
    if (onBurst == null) return;
    // 用**自身 RenderObject** 的全局矩形换算圆心：外层 `Transform.translate`
    // 的漂移已在 `localToGlobal` 里被祖先变换计入 → 圆心永远跟着胶囊走。
    final RenderBox? rb = context.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached || !rb.hasSize) return;
    onBurst(rb.localToGlobal(rb.size.center(Offset.zero)));
  }

  /// 胶囊是否可点（两种形态各有入口；都为 null ⇒ 纯展示，供度量测试用）。
  bool get _tappable =>
      widget.firing ? widget.onFire != null : widget.onBurst != null;

  @override
  Widget build(BuildContext context) {
    // C65：气泡内素材图**不随 textScaler 缩放**（图片不吃 textScaler），
    // 故与旁边已放大的数字相比会显小 —— 显式乘 uiScaleOf 补平（手机 = 1.0，零回归）。
    final double s = uiScaleOf(context);
    return AnimatedBuilder(
      animation: widget.drift,
      builder: (BuildContext context, Widget? child) {
        final double t = widget.drift.value * 2 * math.pi;
        // C44h（玄参 2026-10-09）：频率必须是基频**整数倍**（1/2/3/4/5/6 次谐波）——
        // 旧版用 2.7/1.3/0.7 非整倍频，t=2π 归零瞬间各分量不回原点（dy 跳 ~12pt），
        // 观感「飘着飘着突然跳变」。整数谐波下 sin(2π·k)=0、cos(2π·k)=1，轨迹
        // 首尾无缝闭合，循环永无跳变；三组谐波叠加仍保持「无规律」漂动感。
        // C44i：振幅实测 dx ±20 / dy ±16（系数经数值反推，谐波间会互相抵消，
        // 名义系数需大于目标振幅）；整数谐波保证 t=2π 首尾闭合无跳变（C44h）。
        // 屏幕边界已验证：气泡活动区 x 241-379pt（右缘 < 402、左缘 60% 屏宽
        // 不碰花头）、y 203-268pt（场景带 0-367 内）。
        final double dx = math.sin(t) * 20.7 +
            math.sin(3 * t) * 8 +
            math.sin(5 * t) * 3.2;
        final double dy = math.cos(2 * t) * 12.2 +
            math.sin(4 * t) * 4.9 +
            math.cos(6 * t) * 2.4;
        // 🔴 B7：战斗中（[firing]）**钉死位置** —— 开火要打的是「那个不动的
        // 目标」，飘着点会让孩子瞄错、也让「连测 3 帧矩形逐位相同」不成立。
        final Offset offset = widget.firing ? Offset.zero : Offset(dx, dy);
        return Transform.translate(offset: offset, child: child);
      },
      // GestureDetector 包在胶囊**外层**：命中区 = 胶囊矩形本身（不透明白底），
      // 不需要额外放大 —— 胶囊已有 44pt 高，满足触控下限（C67 放大后 46pt）。
      child: GestureDetector(
        // `opaque`：让空白内边距也算命中，避免「点在胶囊里却没反应」。
        behavior: HitTestBehavior.opaque,
        onTap: _tappable ? _handleTap : null,
        child: Container(
          key: widget.capsuleKey,
          // C67：胶囊整体放大（见类文档的尺寸表）。
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(26),
            // 🔴 B7：战斗态把描边提成实金 + 加一圈金色柔光 —— 这是「现在点它
            // 有用」的唯一视觉提示（不新增文案、不改尺寸：描边宽度恒 1，
            // 故胶囊矩形逐位不变）。
            border: Border.all(
              color: widget.firing
                  ? const Color(0xFFE8A600)
                  : const Color(0x33E8A600),
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 4)),
              if (widget.firing)
                const BoxShadow(
                    color: Color(0x66E8A600),
                    blurRadius: 14,
                    spreadRadius: 1),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 阳光素材（2026-10-06 玄参交付），缺失回退内置图标。
              // C65：随平板 UI 倍率放大（见 build 内 s 的说明）。
              // C67：22 → **30**（玄参要求「把里面的阳光图标变大一些」，主导放大）。
              Image.asset(
                'assets/rewards/sunlight.png',
                width: 30 * s,
                height: 30 * s,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.wb_sunny,
                    color: const Color(0xFFE8A600), size: 30 * s),
              ),
              const SizedBox(width: 7), // C67：6 → 7
              // 数字：点击时 `_popScale` 轻弹（1.0 → 1.16 → 1.0）。
              // `transformHitTests: false` —— 缩放只影响绘制，不能把命中区一起放大，
              // 否则连点边界会随动画抖动（`ScaleTransition` 无此开关，故手写）。
              AnimatedBuilder(
                animation: _popScale,
                builder: (BuildContext _, Widget? child) => Transform.scale(
                  scale: _popScale.value,
                  transformHitTests: false,
                  child: child,
                ),
                child: Text(
                  '${sunlightDisplayInt(widget.balance)}',
                  // C67：18 → 19（数字只微幅跟进，把放大余量让给图标）。
                  style:
                      const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              // C44g（玄参 2026-10-09）：删掉尾部小太阳「☀」——阳光素材图标已
              // 表意，双太阳重复（用户截图实证）。仅保留素材图标 + 数字。
            ],
          ),
        ),
      ),
    );
  }
}

/// 单张状态卡（图标 + 标签 + 主数值 + 次要单位）。
///
/// C44e 二轮反馈（玄参 2026-10-09）：纯白太呆 → 暖色渐变底 + 淡金描边 +
/// 柔和投影；整体收窄（纵向 padding 18→11，label/value 字号微降）。
/// C48（玄参 2026-10-10）：图标改用 UI 素材（阳光/专注闹钟/习惯），
/// 加载失败回退原内置图标。
class _StatCard extends StatelessWidget {
  final IconData icon;

  /// UI 素材路径（非 null 时优先显示素材图，失败回退 [icon]）。
  final String? assetIcon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _StatCard({
    required this.icon,
    this.assetIcon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          // 暖白渐变（左上白 → 右下奶油），与背景「上半场景+下半留白」呼应。
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Colors.white, Color(0xFFFDF3DD)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x26E8A600)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x1F8A5A00),
                blurRadius: 10,
                offset: Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: <Widget>[
              // C65：图标底圆与素材同步乘 UI 倍率 —— 否则数字放大 1.3× 后
              // 圆头像（42/21）相对变小，卡片左右重心失衡（手机 = 1.0，零回归）。
              CircleAvatar(
                radius: 21 * uiScaleOf(context),
                backgroundColor: color.withValues(alpha: 0.15),
                // C48：优先 UI 素材图（方形图直接铺满圆形底内），失败回退内置图标。
                child: assetIcon == null
                    ? Icon(icon, color: color, size: 24 * uiScaleOf(context))
                    : ClipRRect(
                        borderRadius:
                            BorderRadius.circular(21 * uiScaleOf(context)),
                        child: Image.asset(
                          assetIcon!,
                          width: 42 * uiScaleOf(context),
                          height: 42 * uiScaleOf(context),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(icon,
                              color: color, size: 24 * uiScaleOf(context)),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF8A7A66))),
                    const SizedBox(height: 2),
                    // 🔴 F127（2026-10-20）：本行**必须**保持可收缩 —— 此前两个
                    // `Text` 都是「不可压缩」子项，父级 `Row` 在
                    // 320×568 + `textScaler: 1.3` 下装不下就整体溢出
                    // （`A RenderFlex overflowed by 14 pixels on the right.`：
                    //  `今日专注` 卡的值 119.6 + 间距 6 + 单位 84.5 = 210.1 > 可用 198）。
                    // 修法：两个 `Text` 各自套 `Flexible`（默认 flex 1 / loose）+
                    // 单行省略 —— 空间不够时**收缩**，而不是撑破父级。
                    // ⚠️ 刻意**不**用 `FittedBox` / `AutoSizeText` / 压 `fontSize`：
                    // 大字号是用户的**无障碍设置**，压字等于对抗用户选择；这里只做
                    // 结构性收敛。等分（1:1）而非按比例倾斜，是为了让「宽屏 / 常规字号」
                    // 下两者都拿得到自然宽度（`Flexible` 是 loose：装得下就用自然宽度），
                    // 零像素回归。
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 23, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (unit.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              unit,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF8A7A66)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
