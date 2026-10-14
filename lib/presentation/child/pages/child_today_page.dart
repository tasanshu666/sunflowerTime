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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/shared/responsive.dart';
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

/// 孩子端「今日」状态卡。
class ChildTodayPage extends ConsumerStatefulWidget {
  const ChildTodayPage({super.key});

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
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _todayEarn = todayEarn;
        _focusMinutes = focusMinutes;
        _focusCount = sessions.length;
        _taskDone = board.doneCount;
        _taskTotal = board.total;
        _loading = false;
      });
    } catch (_) {
      // 今日卡属概览，任一查询失败不阻塞（保留上次值）。
      if (mounted) setState(() => _loading = false);
    }
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
        : _buildLayout();

    // C44：整页背景（上半场景 + 下半留白，白卡浮在留白区上）。
    return TabBackground(
      asset: kTodayBgAsset,
      // C67：底图锚点**冻结**在 [kTodayBgPanelTargetRatio]（=0.37），**不跟**卡片下移
      // —— 玄参明确「背景图片的位置已经比较合适了」（互相关实证背景像素零变化）。
      panelTargetRatio: kTodayBgPanelTargetRatio,
      fallbackColor: const Color(0xFFFBF4E4),
      child: body,
    );
  }

  /// 布局：`Stack[ 场景留白 + 卡片滚动区 + 钉底按钮 , 悬浮阳光气泡 ]`。
  Widget _buildLayout() {
    final double screenH = MediaQuery.sizeOf(context).height;
    final double screenW = MediaQuery.sizeOf(context).width;
    // 第一张卡起点 = [kTodayCardTopRatio] × 屏高（C67 = **0.40**）：上半向日葵 +
    // 积木插画完整露出，下方再留 3% 屏高的奶油呼吸带。直接用屏高比例定位（实测模拟器 padding.top ≈118pt
    // 双倍计入，减 topInset 反而会把卡片顶回 20%，故与 topInset 解耦）。
    final double sceneGap = screenH * kTodayCardTopRatio;

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
                    label: '今日获取阳光',
                    // F105 口径：展示一律 sunlightDisplayInt（向下取整）。
                    value: '+${sunlightDisplayInt(_todayEarn)}',
                    unit: '☀',
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.timer,
                    assetIcon: 'assets/ui/growth/focus.webp',
                    color: Colors.teal,
                    label: '今日专注',
                    value: '${_focusMinutes.round()} 分钟',
                    unit: '· $_focusCount 次',
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.checklist,
                    assetIcon: 'assets/ui/growth/habit.webp',
                    color: Colors.indigo,
                    // 口径与「任务」tab 一致：仅「今日必做（isDaily）」。
                    // doneCount/total 由 [TodayTaskBoard] 保证只统计 isDaily 项。
                    label: '今日成长',
                    value: '$_taskDone / $_taskTotal',
                    unit: _taskTotal > 0 && _taskDone >= _taskTotal
                        ? '全部完成 🌻'
                        : '',
                  ),
                  const SizedBox(height: 14),
                  // 引导：只有从「成长」tab 的具体成长项进入专注，达标后才会自动
                  // 结算该项阳光（本页的「开始专注」是自由专注入口，不联动结算）。
                  const Text(
                    '想赚成长阳光？从「成长」里点具体项目开始专注 🌻',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF8A7A66)),
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
                  label: const Text('开始专注'),
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
        Positioned(
          left: screenW * 0.65,
          top: screenH * 0.25,
          child: _FloatingSunBubble(
            balance: _balance,
            drift: _drift,
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

  const _FloatingSunBubble({required this.balance, required this.drift});

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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          value,
                          style: const TextStyle(
                              fontSize: 23, fontWeight: FontWeight.bold),
                        ),
                        if (unit.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(unit,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF8A7A66))),
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
