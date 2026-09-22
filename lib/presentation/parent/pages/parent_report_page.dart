/// 家长端·专注报告页（M3 T04，§8.3 北极星 / §3.3 有效专注日）。
///
/// 本地聚合展示：近 7 日专注分布（含有效专注日标记）、近 7 日累计专注分钟、
/// 有效专注日数、近 4 周稳定性趋势（有效专注日占比）。纯本地计算，无云端依赖。
///
/// M3 修订（玄参大人真机反馈）：
///  · **溢出根因**：原 `_DayBar` 用固定 `SizedBox(height: 130)` 包住「11px 数值 +
///    最高 120px 柱」= 135 > 130，Android 上直接抛 RenderFlex overflow（黄黑条纹）。
///    修法：**去掉固定高度**，让柱状图按内容自适应（Row + CrossAxisAlignment.end），
///    数值标签放在柱上方、星期与有效专注日标记放在基线下方，物理上不可能再溢出。
///  · **无返回键**：原先本页没有 Scaffold/AppBar（`/parent/report` 是 push 进来的），
///    进得来出不去 —— 一并补上。
///  · **深色模式看不清**（第二轮真机反馈）：配色原先是写死的浅色系（深墨字 + 浅底渐
///    变），深色主题下变成「深字压深卡」，图例/星期/柱值几乎不可辨。现改为
///    **随主题亮度取色**（[_ReportPalette.of]），浅色/深色各一套，两套都保证对比度。
library parent_report_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 报告页配色（随主题亮度切换，深浅两套都保持可读对比度）。
class _ReportPalette {
  /// 主要文字 / 轴标签。
  final Color ink;

  /// 家长端主色（当前周、标题色条）。
  final Color accent;

  /// 有效专注日（达标）。
  final Color valid;

  /// 未构成有效专注日（灰柱）。
  final Color idle;

  /// 结论语按稳定性分档取色。
  final Color warn;
  final Color good;

  /// 顶部主卡渐变 + 描边。
  final List<Color> heroGradient;
  final Color heroBorder;

  /// 中性浅底块（空数据提示等）。
  final Color softBg;

  const _ReportPalette({
    required this.ink,
    required this.accent,
    required this.valid,
    required this.idle,
    required this.warn,
    required this.good,
    required this.heroGradient,
    required this.heroBorder,
    required this.softBg,
  });

  static const _ReportPalette _light = _ReportPalette(
    ink: Color(0xFF27454F),
    accent: Color(0xFF3F7F99),
    valid: Color(0xFF4A9A6B),
    idle: Color(0xFFC3D4DB),
    warn: Color(0xFFC77B2B),
    good: Color(0xFF3E8259),
    heroGradient: <Color>[Color(0xFFF6E7B4), Color(0xFFEAF2F5)],
    heroBorder: Color(0xFFE2D6A8),
    softBg: Color(0xFFF1F6F8),
  );

  /// 深色一套：文字提亮、柱体降饱和，避免深字压深卡的「糊成一团」。
  static const _ReportPalette _dark = _ReportPalette(
    ink: Color(0xFFDCE9EE),
    accent: Color(0xFF7CBCD4),
    valid: Color(0xFF6FCB96),
    idle: Color(0xFF4E626C),
    warn: Color(0xFFE0A85C),
    good: Color(0xFF6FCB96),
    heroGradient: <Color>[Color(0xFF3B3524), Color(0xFF22313A)],
    heroBorder: Color(0xFF4C4530),
    softBg: Color(0xFF1E2A31),
  );

  static _ReportPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// 带透明度派生（统一入口，避免各处各写一个 opacity）。
  Color inkAt(double opacity) => ink.withOpacity(opacity);
}

/// 专注报告页：聚合展示孩子的专注健康度。
class ParentReportPage extends ConsumerStatefulWidget {
  const ParentReportPage({super.key});

  @override
  ConsumerState<ParentReportPage> createState() => _ParentReportPageState();
}

class _ParentReportPageState extends ConsumerState<ParentReportPage> {
  FocusReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _report = await ref
          .read(focusReportServiceProvider)
          .buildReport(DateTime.now());
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: parentThemeFor(Theme.of(context).brightness),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('专注报告'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新生成',
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final _ReportPalette p = _ReportPalette.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('报告生成失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final FocusReport r = _report!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _HeroCard(report: r, palette: p),
        const SizedBox(height: 20),
        _SectionTitle('近 7 日专注分布', palette: p),
        _WeekChartCard(report: r, palette: p),
        const SizedBox(height: 20),
        _SectionTitle('专注稳定性 · 近 4 周', palette: p),
        _StabilityCard(report: r, palette: p),
      ],
    );
  }
}

/// 顶部主卡：本周专注分钟（主指标）+ 有效专注日 / 稳定性（副指标）。
class _HeroCard extends StatelessWidget {
  final FocusReport report;
  final _ReportPalette palette;
  const _HeroCard({required this.report, required this.palette});

  @override
  Widget build(BuildContext context) {
    final _ReportPalette p = palette;
    final int minutes = report.weeklyFocusMinutes.round();
    final int validDays = report.validFocusDaysLast7;
    final int stability = (report.stabilityScore * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.heroGradient,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.heroBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.wb_sunny_rounded,
                  size: 18, color: Color(0xFFD9A21A)),
              const SizedBox(width: 6),
              Text('本周专注',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.inkAt(0.8))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$minutes',
                style: TextStyle(
                  fontSize: 46,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('分钟',
                    style: TextStyle(fontSize: 14, color: p.inkAt(0.85))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: p.inkAt(0.15)),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniMetric(
                  label: '有效专注日',
                  value: '$validDays',
                  unit: '/ 7 天',
                  palette: p,
                ),
              ),
              Container(width: 1, height: 30, color: p.inkAt(0.15)),
              Expanded(
                child: _MiniMetric(
                  label: '稳定性',
                  value: '$stability',
                  unit: '%',
                  palette: p,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final _ReportPalette palette;
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: palette.ink),
                ),
                TextSpan(
                  text: ' $unit',
                  style:
                      TextStyle(fontSize: 12, color: palette.inkAt(0.65)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 12, color: palette.inkAt(0.75))),
        ],
      );
}

/// 7 日专注柱状图卡（有效专注日高亮）。
///
/// 布局纪律：**不设固定高度**。柱高按峰值等比缩放（上限 [_barMaxHeight]），
/// 数值标签在柱上、星期与有效标记在基线下方，各行都是自适应高度 → 永不溢出。
class _WeekChartCard extends StatelessWidget {
  final FocusReport report;
  final _ReportPalette palette;
  const _WeekChartCard({required this.report, required this.palette});

  static const double _barMaxHeight = 112;

  @override
  Widget build(BuildContext context) {
    final _ReportPalette p = palette;
    final List<DailyFocusPoint> days = report.last7Days;
    final double peak = days
        .map((DailyFocusPoint x) => x.focusMinutes)
        .fold(0.0, (double a, double b) => a > b ? a : b);
    final double scale = peak <= 0 ? 1.0 : peak;
    final bool allEmpty = peak <= 0;
    const List<String> weekdayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _LegendDot(color: p.valid),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('有效专注日（≥15 分钟且完成率 ≥90%）',
                      style: TextStyle(fontSize: 11.5, color: p.inkAt(0.75))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 柱体 + 数值（基线之上）
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final DailyFocusPoint x in days)
                  Expanded(
                    child: _DayBar(
                      minutes: x.focusMinutes.round(),
                      height: allEmpty
                          ? 6
                          : (x.focusMinutes / scale * _barMaxHeight)
                              .clamp(6.0, _barMaxHeight),
                      isWfd: x.isWfd,
                      palette: p,
                    ),
                  ),
              ],
            ),
            // 基线
            Container(height: 1.5, color: p.inkAt(0.15)),
            const SizedBox(height: 8),
            // 星期 + 有效专注日标记（基线之下）
            Row(
              children: <Widget>[
                for (int i = 0; i < days.length; i++)
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(
                          weekdayLabels[days[i].date.weekday - 1],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: days[i].isWfd
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: days[i].isWfd ? p.ink : p.inkAt(0.55),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: days[i].isWfd ? p.valid : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (allEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.softBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '近 7 日还没有专注记录。陪孩子完成一次 15 分钟专注，这里就会亮起来。',
                  style: TextStyle(fontSize: 12.5, color: p.inkAt(0.85)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单日柱（数值在上 + 柱体在下，自适应高度，不设外层固定高度）。
class _DayBar extends StatelessWidget {
  final int minutes;
  final double height;
  final bool isWfd;
  final _ReportPalette palette;
  const _DayBar({
    required this.minutes,
    required this.height,
    required this.isWfd,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final _ReportPalette p = palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 16,
          child: minutes > 0
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$minutes',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isWfd ? p.valid : p.inkAt(0.65),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 4),
        Container(
          width: 20,
          height: height,
          decoration: BoxDecoration(
            color: isWfd ? p.valid : p.idle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
      ],
    );
  }
}

/// 稳定性趋势卡：近 4 周有效专注日柱状 + 结论语。
class _StabilityCard extends StatelessWidget {
  final FocusReport report;
  final _ReportPalette palette;
  const _StabilityCard({required this.report, required this.palette});

  static const double _barMaxHeight = 72;

  String get _assessment {
    final double s = report.stabilityScore;
    if (s >= 0.75) return '非常稳定，专注习惯已经养成 🌻';
    if (s >= 0.5) return '比较稳定，继续保持就好';
    if (s >= 0.25) return '略有波动，可以多鼓励规律专注';
    return '波动较大，建议一起定一个每日专注小目标';
  }

  Color get _assessmentColor {
    final double s = report.stabilityScore;
    return s >= 0.5 ? palette.good : palette.warn;
  }

  @override
  Widget build(BuildContext context) {
    final _ReportPalette p = palette;
    final List<int> trend = report.weeklyValidDayTrend;
    // 近 4 周按「越近越大」标注：最后一项 = 本周。
    final int thisWeek = trend.isEmpty ? 0 : trend.last;
    final int lastWeek = trend.length < 2 ? 0 : trend[trend.length - 2];
    final int delta = thisWeek - lastWeek;
    final Color tone = _assessmentColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                for (int i = 0; i < trend.length; i++)
                  Expanded(
                    child: _WeekBar(
                      days: trend[i],
                      isCurrent: i == trend.length - 1,
                      maxHeight: _barMaxHeight,
                      palette: p,
                    ),
                  ),
              ],
            ),
            Container(height: 1.5, color: p.inkAt(0.15)),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                for (int i = 0; i < trend.length; i++)
                  Expanded(
                    child: Text(
                      i == trend.length - 1
                          ? '本周'
                          : '${trend.length - i - 1} 周前',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == trend.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i == trend.length - 1 ? p.ink : p.inkAt(0.55),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tone.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tone.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.insights, size: 18, color: tone),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(_assessment,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: tone)),
                        const SizedBox(height: 4),
                        Text(
                          '本周有效专注 $thisWeek 天，上周 $lastWeek 天'
                          '（${delta >= 0 ? '+' : ''}$delta）'
                          ' · 近 4 周平均 ${(report.stabilityScore * 7).toStringAsFixed(1)} 天/周',
                          style:
                              TextStyle(fontSize: 12, color: p.inkAt(0.8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单周柱（数值在上 + 柱体在下，自适应高度）。
class _WeekBar extends StatelessWidget {
  final int days;
  final bool isCurrent;
  final double maxHeight;
  final _ReportPalette palette;
  const _WeekBar({
    required this.days,
    required this.isCurrent,
    required this.maxHeight,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    // 有效专注日上限为 7 天，按 7 归一 → 各周柱高可直接横向比较。
    final double h = (days / 7 * maxHeight).clamp(6.0, maxHeight);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 16,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$days',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isCurrent ? palette.accent : palette.inkAt(0.65),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 26,
          height: h,
          decoration: BoxDecoration(
            color: isCurrent ? palette.accent : palette.idle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// 分组标题（左侧色条 + 文字）。
class _SectionTitle extends StatelessWidget {
  final String text;
  final _ReportPalette palette;
  const _SectionTitle(this.text, {required this.palette});

  @override
  Widget build(BuildContext context) => Padding(
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
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            ),
          ],
        ),
      );
}
