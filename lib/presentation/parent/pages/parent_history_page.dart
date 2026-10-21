/// 家长端「记录」页（C54 建页 · C55 加「按天 / 按周 / 按月」统计 ·
/// C76 专注报告 v2 信息架构：**分段承载**「专注报告」+「任务与奖励」）。
///
/// 信息架构（v2）：
///  · 顶部**常驻**分段控件 `SegmentedButton`：`专注报告` / `任务与奖励`（不随内容滚动）；
///  · 段 0 = 专注报告（日 / 周 / 月 / 年周期报告，见
///    `widgets/focus_report_section.dart`；月 / 年 / 稳定性 / 热力图归付费 `deepReport`）；
///  · 段 1 = 任务与奖励（成长任务完成记录 + 奖励兑换记录，见
///    `widgets/history_activity_section.dart`）。
///
/// 段状态自持纪律：切段**不得**重建 / 重置另一段的期间状态 —— 两段用
/// `Visibility(maintainState: true)`（即 `Offstage`）同时挂载，只显示其中一段。
/// 理由详见 [build] 处注释（为何不用 `IndexedStack` / `TabBar`）。
///
/// 排版纪律：本页作为「记录」tab 内嵌渲染，**不自带 Scaffold / AppBar**（外层
/// `ParentHomePage` 已提供顶部栏），与「今日 / 奖励 / 设置」三页保持一致。
library parent_history_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/widgets/focus_report_section.dart';
import 'package:sunflower_time/presentation/parent/widgets/history_activity_section.dart';

/// 家长端「记录」页：分段承载「专注报告」与「任务与奖励」。
class ParentHistoryPage extends ConsumerStatefulWidget {
  const ParentHistoryPage({super.key, this.now, this.initialSegment = 0});

  /// 注入「当前时刻」（仅测试用；生产为 null → 取系统时间）。
  final DateTime? now;

  /// 初始段：`0` = 专注报告（默认），`1` = 任务与奖励（越界值夹到这两档）。
  final int initialSegment;

  @override
  ConsumerState<ParentHistoryPage> createState() => _ParentHistoryPageState();
}

class _ParentHistoryPageState extends ConsumerState<ParentHistoryPage> {
  /// 段索引：专注报告段。
  static const int _kReportSegment = 0;

  /// 段索引：任务与奖励段。
  static const int _kActivitySegment = 1;

  /// 当前段（默认专注报告）。
  late int _segment;

  @override
  void initState() {
    super.initState();
    _segment = _clampSegment(widget.initialSegment);
  }

  @override
  void didUpdateWidget(ParentHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 入口带参跳转（设置页「专注报告」卡 / 旧深链 `/parent/report`）在极少数
    // 情况下会是「同页复用 State、仅 props 变化」，这里同步一次，保证跳转生效。
    if (oldWidget.initialSegment != widget.initialSegment) {
      _segment = _clampSegment(widget.initialSegment);
    }
  }

  /// 越界值收敛到 `{0, 1}`：负数 → 专注报告，≥1 → 任务与奖励。
  static int _clampSegment(int value) {
    if (value <= _kReportSegment) return _kReportSegment;
    return _kActivitySegment;
  }

  /// 分段控件：常驻顶部，不随内容滚动。
  ///
  /// ⚠️ 刻意**不用** `TabBar`（nav 结构测试断言 `find.byType(TabBar) findsNothing`，
  /// 且本页不是路由层级的 tab，只是页内分段）。
  Widget _buildSegmentBar(BuildContext context) {
    // i18n B2：分段文案经 [l10nOf]（页级 scope 内取；裸宿主回退 zh）。
    final AppLocalizations t = l10nOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 宽屏铺满；窄屏 / iPad 1.3× 文字缩放下超宽则横向滚动，避免挤压换行。
          final double minWidth =
              constraints.hasBoundedWidth ? constraints.maxWidth : 0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: _kReportSegment,
                    label: Text(t.parent_history_seg_report),
                  ),
                  ButtonSegment<int>(
                    value: _kActivitySegment,
                    label: Text(t.parent_history_seg_activity),
                  ),
                ],
                selected: <int>{_segment},
                onSelectionChanged: (Set<int> selection) {
                  if (selection.isEmpty) return;
                  setState(() => _segment = selection.first);
                },
                showSelectedIcon: false,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 两段同时挂载、只显示其一：
    //  · `Visibility(maintainState: true)` 在不可见时走 `Offstage` —— 子树 Element /
    //    State 全保留（期间锚点、粒度、已拉取数据不丢），但**不绘制、不参与布局
    //    命中、不被 `find.*`（默认 skipOffstage）与无障碍焦点看到**；
    //  · 不用 `IndexedStack`：它会用 `Visibility(maintainSize: true)` 包裹子项（绘制
    //    尺寸保留、靠 Opacity 隐藏），隐藏段仍「在台上」，语义树里会出现两套内容，
    //    与「默认段不是记录段」的断言目标冲突。
    return Column(
      children: <Widget>[
        _buildSegmentBar(context),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Visibility(
                visible: _segment == _kReportSegment,
                maintainState: true,
                child: FocusReportSection(now: widget.now),
              ),
              Visibility(
                visible: _segment == _kActivitySegment,
                maintainState: true,
                child: HistoryActivitySection(now: widget.now),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
