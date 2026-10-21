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
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
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
              return _buildLayout(box: c.biggest);
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
  Widget _buildLayout({required Size box}) {
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
            SizedBox(height: sceneGap),
            // 中间：状态卡 + 引导文案，唯一可滚动区域。
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: <Widget>[
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
class _FloatingSunBubble extends StatelessWidget {
  final double balance;
  final Animation<double> drift;

  /// 胶囊容器的 Key（度量护栏用，由页面传入 [ChildTodayPage.sunBubbleKey]）。
  final Key? capsuleKey;

  const _FloatingSunBubble({
    required this.balance,
    required this.drift,
    this.capsuleKey,
  });

  @override
  Widget build(BuildContext context) {
    // C65：气泡内素材图**不随 textScaler 缩放**（图片不吃 textScaler），
    // 故与旁边已放大的数字相比会显小 —— 显式乘 uiScaleOf 补平（手机 = 1.0，零回归）。
    final double s = uiScaleOf(context);
    return AnimatedBuilder(
      animation: drift,
      builder: (BuildContext context, Widget? child) {
        final double t = drift.value * 2 * math.pi;
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
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: Container(
        key: capsuleKey,
        // C67：胶囊整体放大（见类文档的尺寸表）。
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x33E8A600)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4)),
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
            Text(
              '${sunlightDisplayInt(balance)}',
              // C67：18 → 19（数字只微幅跟进，把放大余量让给图标）。
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            // C44g（玄参 2026-10-09）：删掉尾部小太阳「☀」——阳光素材图标已
            // 表意，双太阳重复（用户截图实证）。仅保留素材图标 + 数字。
          ],
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
