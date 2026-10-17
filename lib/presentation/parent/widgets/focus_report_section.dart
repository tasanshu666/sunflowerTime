/// 家长端「记录」页 · **专注报告** 段（专注报告改造 v2 · C76 / T03）。
///
/// 取代 `parent_history_page.dart` 里原先的「段 0 临时占位」，与「任务与奖励」段
/// （`history_activity_section.dart`）并列承载在记录页分段里。
/// 旧的独立报告页 `parent_report_page.dart` **有意保留为孤儿页**（零改动，不路由到）。
///
/// ## 信息架构（自上而下）
///  1. **周期切换器** `ReportPeriodBar`：日 / 周 / 月 / 年（默认**周**）；
///  2. **期间导航** `◀ 标题 ▶`（标题口径与记录页一致；**不翻未来**）；
///  3. **Hero 卡**：本期间累计专注分钟 + 有效专注日 / 平均每日；
///  4. **趋势卡**：日 → 近 7 日；周 → 本周 7 根日柱；月 → 按周；年 → 按月；
///  5. **稳定性卡**（🔒 付费）：近 4 周有效专注日柱 + 稳定性读数；
///  6. **热力图**（🔒 付费）：近 1 年日历格；
///  7. **护眼统计**（**免费可见**）：完成 / 跳过 / 累计时长 / 跳过率。
///
/// ## C85 变更（免费档引导不再「两张广告牌」）
///  · 稳定性区块未解锁 → 渲染**一条** `ReportUpsellBar` 横条（原 `PremiumUpsellCard`
///    大卡已不再实例化）；
///  · 热力图区块未解锁 → **整块不渲染**（连标题一起），避免「空标题 + 第二条重复引导」。
///  · 结论：免费档全段**恰有 1 条**深度报告引导，热力图组件与任何热力格零渲染。
///
/// ## 门控口径（玄参 2026-10-17 拍板 · C76 裁定 #1）
/// **免费 = 只能看近 7 天**：日 / 周完整可见；月报 / 年报 / 近 4 周稳定性 / 热力图
/// 四处**全部归 `deepReport`（付费）**；护眼统计保持免费。
///
/// 🔴 **判定单点**：`featureAllowedFor(FeatureKey.deepReport, tier)` 全仓**只在本文件**
/// 出现一次（见 [_isUnlocked]）。其余五个组件（palette / period bar / heatmap /
/// stability / eye care）一律只吃 `bool unlocked` 与 `Widget lockedPlaceholder`，
/// 文件内**零权益标识符**（`test/qa/entitlement_gate_guard_test.dart` 白名单只加本文件）。
///
/// 🔴 **C62：「不可点」≠ 静默**：月 / 年**不置空回调**，而是「视觉置灰 + 🔒 + 点击给因」
/// —— 点月 / 年 → **不切换周期** + `showPremiumUpsell` 弹「升级解锁」对话框。
///
/// ## 取数纪律（免费档不做无用功）
/// 免费档**不查** 365 天热力图、**不跑** `buildReport` 的 35 次日查询；只有买断档才付
/// 这两笔代价（见 [_load]）。切换周期 / 翻页一律 `setState` 重载，**不在 build 里发查询**。
library focus_report_section;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/report_period.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_eye_care_card.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_heatmap.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_palette.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_period_bar.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_stability_card.dart';
import 'package:sunflower_time/presentation/parent/widgets/report_upsell_bar.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

/// 记录页「专注报告」段。
class FocusReportSection extends ConsumerStatefulWidget {
  const FocusReportSection({super.key, this.now});

  /// 注入「当前时刻」（仅测试用；生产为 null → 取系统时间）。
  final DateTime? now;

  @override
  ConsumerState<FocusReportSection> createState() => _FocusReportSectionState();
}

class _FocusReportSectionState extends ConsumerState<FocusReportSection> {
  /// 趋势柱最大高度（pt，与老页 `_WeekChartCard` 一致）。
  static const double _kBarMaxHeight = 112;

  /// 周内短标签（索引 = `DateTime.weekday - 1`）。
  static const List<String> _kWeekdayShort = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// 当前周期（**默认周**——玄参要的是「这周怎么样」，日太碎、月年需付费）。
  ReportPeriod _period = ReportPeriod.week;

  /// 期间锚点（其所在周期即当前查看区间）。
  late DateTime _anchor;

  /// 当前取数任务（切换周期 / 翻页 / 下拉刷新都会换一个新的）。
  late Future<_ReportData> _future;

  /// 护眼统计**独立**取数（见 [_loadEyeCare] 的为什么独立）。
  late Future<_EyeCareStats> _eyeCare;

  DateTime get _now => widget.now ?? DateTime.now();

  /// 🔴 门控判定**单点**（C76 裁定 #1）。
  ///
  /// 全仓仅此一处调用 `featureAllowedFor(FeatureKey.deepReport, ...)`：
  ///  · [build] 用 `ref.watch` 的档位调用它 → 档位变化自动重建（购买后立刻放行）；
  ///  · [initState] / [didUpdateWidget] 用 `ref.read` 的档位调用它 → 决定**要不要取**
  ///    365 天热力图与 35 次按日查询（免费档省掉）。
  bool _isUnlocked(EntitlementTier tier) =>
      featureAllowedFor(FeatureKey.deepReport, tier);

  @override
  void initState() {
    super.initState();
    _anchor = _now;
    _future = _load(_isUnlocked(ref.read(entitlementProvider).tier));
    _eyeCare = _loadEyeCare();
  }

  @override
  void didUpdateWidget(FocusReportSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 测试注入的 `now` 变了 → 锚点必须跟着重置并重载（否则期间标题仍是旧「今天」）。
    if (oldWidget.now != widget.now) {
      _anchor = _now;
      _future = _load(_isUnlocked(ref.read(entitlementProvider).tier));
      _eyeCare = _loadEyeCare();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 取数
  // ─────────────────────────────────────────────────────────────────────────

  /// 取当前周期需要的一切（一次 Future 打包，UI 只有一份加载态）。
  ///
  /// 🔴 免费档（`unlocked == false`）**不查**热力图、**不跑** `buildReport` ——
  /// 省掉 365 天 + 35 次按日查询，避免免费用户为一个看不见的区块付出卡顿代价。
  Future<_ReportData> _load(bool unlocked) async {
    final FocusReportService service = ref.read(focusReportServiceProvider);

    // 先把「这次要查什么」定住：await 之后字段可能已被用户改掉。
    final DateTime now = _now;
    final ReportPeriod period = _period;
    final DateTime anchor = _anchor;

    final PeriodReport report = await service.buildPeriodReport(
      period: period,
      anchor: anchor,
      now: now,
    );
    final List<DailyFocusPoint>? heat = unlocked
        ? await service.heatmapDays(today: startOfDay(now), days: 365)
        : null;
    // 日档的趋势图用「近 7 日」（该档 `buckets` 为空列表，见 FocusReportService）。
    final List<DailyFocusPoint> trend = period == ReportPeriod.day
        ? await service.trailingDays(lastDay: anchor, count: 7)
        : const <DailyFocusPoint>[];
    final FocusReport? stability = unlocked
        ? await service.buildReport(now)
        : null;

    return _ReportData(
      report: report,
      heat: heat,
      trend: trend,
      stability: stability,
    );
  }

  /// 护眼统计取数（**独立**于报告主链）。
  ///
  /// 为什么独立而不是塞进 [_load]：护眼三项走 `sunlight_ledger` / `eye_care_logs`
  /// 两张表（各自的仓储可能慢，甚至在某些环境下打不开库）。若并进主链，主链会被
  /// 它拖住 —— 卡住的仓储会让**整段报告**停在 loading 转圈（真机上还可能一直转）。
  /// 拆开后：报告段先出（只依赖专注库），护眼卡自渲染、失败/超时静默降级为 0 次 / `'—'`。
  Future<_EyeCareStats> _loadEyeCare() async {
    try {
      final int completed = await ref
          .read(sunlightRepositoryProvider)
          .countByRefType(kEyeCareRefType);
      final int skipped = await ref
          .read(eyeCareLogRepositoryProvider)
          .countByResult(EyeCareResultType.skipped);
      final int watchedSeconds = await ref
          .read(eyeCareLogRepositoryProvider)
          .watchedSecondsByResult(EyeCareResultType.skipped);
      return _EyeCareStats(
        completed: completed,
        skipped: skipped,
        skippedWatchedSeconds: watchedSeconds,
      );
    } catch (_) {
      // 静默降级：护眼卡显示 0 次 / '—'，不拖垮整个报告段。
      return const _EyeCareStats(
        completed: 0,
        skipped: 0,
        skippedWatchedSeconds: 0,
      );
    }
  }

  /// 下拉刷新 / 错误态重试：换新 Future 并等它落地（错误由 FutureBuilder 展示）。
  Future<void> _reload(bool unlocked) async {
    final Future<_ReportData> next = _load(unlocked);
    setState(() {
      _future = next;
      _eyeCare = _loadEyeCare();
    });
    try {
      await next;
    } catch (_) {
      // 错误态由 FutureBuilder 渲染，这里只负责把刷新动画收尾。
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 交互
  // ─────────────────────────────────────────────────────────────────────────

  /// 切换周期。
  ///
  /// 🔴 C62：付费档位下点月 / 年 **不切换周期**，但**必须给因**（弹「升级解锁」），
  /// 且**不阻塞**其它交互（对话框可「稍后」关掉）。
  void _onPeriodTap(ReportPeriod period, bool unlocked) {
    final bool needsPremium =
        period == ReportPeriod.month || period == ReportPeriod.year;
    if (needsPremium && !unlocked) {
      showPremiumUpsell(context, FeatureKey.deepReport);
      return;
    }
    if (period == _period) return;
    setState(() {
      _period = period;
      _future = _load(unlocked);
    });
  }

  /// 前后翻一个周期（`delta > 0` 往后）。**未来不可翻**由 [_canNext] 兜住。
  void _shift(int delta, bool unlocked) {
    final DateTime start = _period.startOf(_anchor);
    final DateTime nextAnchor = delta > 0
        ? _period.endOf(_anchor)
        // 往前：退到上一周期的最后一天（用日期构造归一化，避开夏令时 23h 天）。
        : DateTime(start.year, start.month, start.day - 1);
    setState(() {
      _anchor = nextAnchor;
      _future = _load(unlocked);
    });
  }

  /// 是否还能往后翻：下一期间起点必须 **≤ 今天 00:00**（否则就翻进未来了）。
  ///
  /// ⚠️ 与任务书伪码 `canNext = !endOf(anchor).isAfter(今天00:00 + 1天)` 的差异说明：
  /// 那个写法在**日档锚定今天**时 `endOf = 明天 00:00`，`+1天` 后比较结果为
  /// 「不晚于」→ `canNext = true`，▶ 会把用户翻到**明天**（未来），与「不翻未来」
  /// 及本文件测试用例「日档 ▶ 恒 disabled」直接冲突。故取右边界的真实语义：
  /// **下一期间起点 ≤ 今天 00:00**。
  bool _canNext(DateTime now) {
    final DateTime today = startOfDay(now);
    return !_period.endOf(_anchor).isAfter(today);
  }

  /// 期间标题（口径与记录页 `history_activity_section` 的 `_Period.label` 一致）。
  String _label(DateTime now) {
    final DateTime start = _period.startOf(_anchor);
    final DateTime end = _period.endOf(_anchor);
    final DateTime today = startOfDay(now);
    final DateTime yesterday = DateTime(today.year, today.month, today.day - 1);
    final DateFormat monthDay = DateFormat('M月d日');
    switch (_period) {
      case ReportPeriod.day:
        if (start == today) return '今天 · ${monthDay.format(start)}';
        if (start == yesterday) return '昨天 · ${monthDay.format(start)}';
        return DateFormat('yyyy年M月d日').format(start);
      case ReportPeriod.week:
        final DateTime lastDay =
            DateTime(end.year, end.month, end.day - 1);
        return '${DateFormat('yyyy年M月d日').format(start)} ～ '
            '${monthDay.format(lastDay)}';
      case ReportPeriod.month:
        return '${start.year} 年 ${start.month} 月';
      case ReportPeriod.year:
        return '${start.year} 年';
    }
  }

  /// 趋势卡标题（四档各异，直说「看的是哪个范围」）。
  String _trendTitle() {
    switch (_period) {
      case ReportPeriod.day:
        return '近 7 日专注分布';
      case ReportPeriod.week:
        return '本周专注分布';
      case ReportPeriod.month:
        return '本月专注分布（按周）';
      case ReportPeriod.year:
        return '本年专注分布（按月）';
    }
  }

  /// 趋势柱数据：日档吃「近 7 日」；其余三档吃服务端算好的 [PeriodBucket]。
  List<_TrendBar> _trendBarsOf(_ReportData data) {
    if (_period == ReportPeriod.day) {
      return <_TrendBar>[
        for (final DailyFocusPoint p in data.trend)
          _TrendBar(
            label: _kWeekdayShort[p.date.weekday - 1],
            minutes: p.focusMinutes,
            valid: p.isWfd,
          ),
      ];
    }
    // 月 / 年桶没有「有效专注日」概念（一个桶含多天），故「有专注即亮」。
    return <_TrendBar>[
      for (final PeriodBucket b in data.report.buckets)
        _TrendBar(
          label: b.label,
          minutes: b.focusMinutes,
          valid: b.focusMinutes > 0,
        ),
    ];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 构建
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 🔴 判定单点：读档位 → 交给 [_isUnlocked]（购买后 StateProvider 变更即重建）。
    final EntitlementTier tier = ref.watch(entitlementProvider).tier;
    final bool unlocked = _isUnlocked(tier);
    final ReportPalette palette = ReportPalette.of(context);
    // C85：锁定时展示的引导**横条**（只在本文件构造，子组件零权益 token）。
    // 买断档不需要引导 → 传 `SizedBox.shrink()`，保证「引导条零渲染」可被测试取证。
    final Widget lockedBar = unlocked
        ? const SizedBox.shrink()
        : ReportUpsellBar(
            onTap: () => showPremiumUpsell(context, FeatureKey.deepReport),
          );

    return FutureBuilder<_ReportData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_ReportData> snapshot) {
        // 刷新时 FutureBuilder 会带着旧数据进入 waiting，故先看 hasData（列表不闪空）。
        if (snapshot.hasData) {
          return RefreshIndicator(
            onRefresh: () => _reload(unlocked),
            child: _buildList(
              data: snapshot.data!,
              unlocked: unlocked,
              lockedBar: lockedBar,
              palette: palette,
            ),
          );
        }
        if (snapshot.hasError) {
          return _buildError(unlocked, palette);
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  /// 错误态：一句人话 + 重试按钮（不把异常堆栈丢给家长看）。
  Widget _buildError(bool unlocked, ReportPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 36, color: palette.warn),
            const SizedBox(height: 12),
            Text(
              '报告生成失败，请下拉重试',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: palette.ink),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _reload(unlocked),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 主列表（内容顺序即信息架构顺序）。
  Widget _buildList({
    required _ReportData data,
    required bool unlocked,
    required Widget lockedBar,
    required ReportPalette palette,
  }) {
    final DateTime now = _now;
    final bool canNext = _canNext(now);
    final List<_TrendBar> bars = _trendBarsOf(data);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        // 1. 周期切换器（四档都可点；月 / 年免费档带 🔒 视觉）。
        ReportPeriodBar(
          period: _period,
          unlocked: unlocked,
          onTap: (ReportPeriod p) => _onPeriodTap(p, unlocked),
        ),
        const SizedBox(height: 6),
        // 2. 期间导航（◀ 标题 ▶；到顶 ▶ 置空 → disabled）。
        _PeriodNav(
          label: _label(now),
          onPrev: () => _shift(-1, unlocked),
          onNext: canNext ? () => _shift(1, unlocked) : null,
        ),
        const SizedBox(height: 6),
        // 3. Hero 卡。
        _HeroCard(report: data.report, palette: palette),
        const SizedBox(height: 20),
        // 4. 趋势卡。
        _SectionTitle(text: _trendTitle(), palette: palette),
        _TrendCard(bars: bars, palette: palette),
        const SizedBox(height: 20),
        // 5. 稳定性卡（🔒 付费）。
        //    C85：未解锁时渲染**一条引导横条**（替代原先的大引导卡），全段仅此一处。
        _SectionTitle(text: '专注稳定性 · 近 4 周', palette: palette),
        if (data.stability == null)
          lockedBar
        else
          ReportStabilityCard(
            unlocked: unlocked,
            lockedPlaceholder: lockedBar,
            report: data.stability!,
          ),
        // 6. 热力图（🔒 付费）。
        //    C85：未解锁时**整块不渲染**（连「专注热力图 · 近 1 年」标题一起省略），
        //    否则会留下一个空标题 + 第二条重复引导，正是本次要消灭的观感问题。
        //    解锁档 `data.heat` 非空 → 标题 + 热力图照旧。
        if (data.heat != null) ...<Widget>[
          const SizedBox(height: 20),
          _SectionTitle(text: '专注热力图 · 近 1 年', palette: palette),
          ReportHeatmap(
            unlocked: unlocked,
            lockedPlaceholder: lockedBar,
            days: data.heat!,
          ),
        ],
        const SizedBox(height: 20),
        // 7. 护眼统计（**免费可见**，不吃 unlocked；独立 FutureBuilder，永不拖住主链）。
        _SectionTitle(text: '护眼统计', palette: palette),
        FutureBuilder<_EyeCareStats>(
          future: _eyeCare,
          builder: (BuildContext context, AsyncSnapshot<_EyeCareStats> snap) {
            if (!snap.hasData) {
              // ⚠️ 待取数时用**静态**占位（不能用 `CircularProgressIndicator`：
              // 常驻动画会让 `pumpAndSettle` 永不收敛，也会让家长觉得「一直在转」）。
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: palette.softBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '护眼统计读取中…',
                  style: TextStyle(fontSize: 12.5, color: palette.inkAt(0.7)),
                ),
              );
            }
            final _EyeCareStats stats = snap.data!;
            return ReportEyeCareCard(
              completed: stats.completed,
              skipped: stats.skipped,
              skippedWatchedSeconds: stats.skippedWatchedSeconds,
            );
          },
        ),
      ],
    );
  }
}

/// 段内取数结果（一次 Future 打包 UI 需要的三份专注数据）。
class _ReportData {
  const _ReportData({
    required this.report,
    required this.heat,
    required this.trend,
    required this.stability,
  });

  /// 当前周期报告（恒有）。
  final PeriodReport report;

  /// 近 1 年热力图（`null` = 免费档，未取数）。
  final List<DailyFocusPoint>? heat;

  /// 日档用的近 7 日序列（其余档为空列表）。
  final List<DailyFocusPoint> trend;

  /// 近 4 周稳定性报告（`null` = 免费档，未取数）。
  final FocusReport? stability;
}

/// 护眼统计三项（独立取数，失败降级为全 0）。
class _EyeCareStats {
  const _EyeCareStats({
    required this.completed,
    required this.skipped,
    required this.skippedWatchedSeconds,
  });

  /// 完成护眼次数。
  final int completed;

  /// 跳过护眼次数。
  final int skipped;

  /// 跳过那几次的实际观看秒数。
  final int skippedWatchedSeconds;
}

/// 趋势图单柱数据（日档来自 `trailingDays`，其余档来自 `buckets`）。
class _TrendBar {
  const _TrendBar({
    required this.label,
    required this.minutes,
    required this.valid,
  });

  /// 柱下方标签（`周一` / `第2周` / `10月` / `一`…`日`）。
  final String label;

  /// 该柱专注分钟。
  final double minutes;

  /// 是否用「达标色」（`palette.valid`）而非「灰柱色」（`palette.idle`）。
  final bool valid;
}

/// 期间导航：`◀ 标题 ▶`（未来不可翻）。
class _PeriodNav extends StatelessWidget {
  const _PeriodNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;

  /// `null` = 已到顶（▶ 置灰不可点）。
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一期间',
          onPressed: onPrev,
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一期间',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// 顶部主卡：本期间累计专注分钟（主指标）+ 有效专注日 / 平均每日（副指标）。
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.report, required this.palette});

  final PeriodReport report;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final int minutes = report.totalFocusMinutes.round();
    final int avgMinutes = report.avgFocusMinutesPerDay.round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.heroGradient,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.heroBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 阳光美术图（缺失 / 失败回退内置图标，与老页一致）。
              Image.asset(
                'assets/rewards/sunlight.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Icon(
                  Icons.wb_sunny_rounded,
                  size: 18,
                  color: Color(0xFFD9A21A),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '本期间专注',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.inkAt(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 大字：'N 分钟'（空数据自然落到 '0 分钟'，不显示占位符）。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$minutes 分钟',
              style: TextStyle(
                fontSize: 40,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: palette.inkAt(0.15)),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '有效专注日 ${report.validFocusDays} 天',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.inkAt(0.85),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '平均每日 $avgMinutes 分钟',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.inkAt(0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 趋势卡：柱状图（柱高 = `minutes / 峰值 × 112`，峰值为 0 时全 0 高）。
///
/// 布局纪律（照搬老页 `_WeekChartCard` 的教训）：**不设外层固定高度** ——
/// 柱高由数据决定、标签在柱下，物理上不可能 `RenderFlex overflow`。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.bars, required this.palette});

  final List<_TrendBar> bars;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final double peak = bars.fold<double>(
      0,
      (double a, _TrendBar b) => b.minutes > a ? b.minutes : a,
    );
    final bool allEmpty = peak <= 0;

    return Container(
      decoration: creamCardDecoration(),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final _TrendBar bar in bars)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          height: 16,
                          child: bar.minutes > 0
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${bar.minutes.round()}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: bar.valid
                                          ? palette.valid
                                          : palette.inkAt(0.65),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        // 固定 112pt 的「绘图区」，柱子底部对齐 → 各柱基线一致。
                        SizedBox(
                          height: _FocusReportSectionState._kBarMaxHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              height: allEmpty
                                  ? 0
                                  : bar.minutes /
                                      peak *
                                      _FocusReportSectionState._kBarMaxHeight,
                              decoration: BoxDecoration(
                                color: bar.valid ? palette.valid : palette.idle,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Container(height: 1.5, color: palette.inkAt(0.15)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final _TrendBar bar in bars)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bar.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: bar.valid ? palette.ink : palette.inkAt(0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (allEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.softBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '本期间还没有专注记录。陪孩子完成一次 15 分钟专注，这里就会亮起来。',
                style: TextStyle(fontSize: 12.5, color: palette.inkAt(0.85)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 分组标题（左侧色条 + 文字，与老页 `_SectionTitle` 同视觉）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.palette});

  final String text;
  final ReportPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
