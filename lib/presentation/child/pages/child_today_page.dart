/// 孩子端「今日」tab（M3 导航重构 / §5 信息架构：今日状态卡）。
///
/// 内容（§5）：阳光气泡（悬浮）+ 今日获取阳光 / 今日专注 / 今日必做进度
/// （仅 isDaily）+「开始专注」主按钮（钉底）。
/// 数据随 [economyRevisionProvider] 变化重新拉取 —— 孩子打卡或家长核销后回到
/// 「今日」能看到最新进度（否则 IndexedStack 保活导致数值不刷新）。
///
/// C44e 版式（玄参 2026-10-09 期望图 + 二轮反馈）：
///  · 上半 ~42% 屏高是背景插画场景，标题浮在场景上（shell 透明 AppBar）；
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
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';

/// 孩子端「今日」状态卡。
class ChildTodayPage extends ConsumerStatefulWidget {
  const ChildTodayPage({super.key});

  @override
  ConsumerState<ChildTodayPage> createState() => _ChildTodayPageState();
}

class _ChildTodayPageState extends ConsumerState<ChildTodayPage>
    with SingleTickerProviderStateMixin {
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

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
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
    // ①上半场景（向日葵+积木插画）完整露出，卡片从 ~42% 屏高开始；
    // ②「我的阳光」改悬浮气泡飘在向日葵右半侧；
    // ③「开始专注」按钮钉在底部；④只有中间状态卡可滚动。
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _buildLayout();

    // C44：整页背景（上半场景 + 下半留白，白卡浮在留白区上）。
    return TabBackground(
      asset: kTodayBgAsset,
      fallbackColor: const Color(0xFFFBF4E4),
      child: body,
    );
  }

  /// 布局：`Stack[ 场景留白 + 卡片滚动区 + 钉底按钮 , 悬浮阳光气泡 ]`。
  Widget _buildLayout() {
    final double screenH = MediaQuery.sizeOf(context).height;
    final double screenW = MediaQuery.sizeOf(context).width;
    // 第一张卡起点 ≈ 42% 屏高（玄参期望图 2026-10-09 实测 ~43%）：上半向日葵+
    // 积木插画完整露出。直接用屏高比例定位（实测模拟器 padding.top ≈118pt
    // 双倍计入，减 topInset 反而会把卡片顶回 20%，故与 topInset 解耦）。
    final double sceneGap = screenH * 0.42;

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
                    color: const Color(0xFFE8890C),
                    label: '今日获取阳光',
                    value: '+${_todayEarn.round()}',
                    unit: '☀',
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.timer,
                    color: Colors.teal,
                    label: '今日专注',
                    value: '${_focusMinutes.round()} 分钟',
                    unit: '· $_focusCount 次',
                  ),
                  const SizedBox(height: 10),
                  _StatCard(
                    icon: Icons.checklist,
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
class _FloatingSunBubble extends StatelessWidget {
  final double balance;
  final Animation<double> drift;

  const _FloatingSunBubble({required this.balance, required this.drift});

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
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
            Image.asset(
              'assets/rewards/sunlight.png',
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.wb_sunny,
                  color: Color(0xFFE8A600), size: 22),
            ),
            const SizedBox(width: 6),
            Text(
              '${balance.toInt()}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _StatCard({
    required this.icon,
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
              CircleAvatar(
                radius: 21,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 24),
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
