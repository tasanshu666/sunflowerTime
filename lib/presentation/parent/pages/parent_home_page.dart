/// 家长端首页（M3 导航重构）：底部导航壳，承载「今日 / 奖励 / 成长 / 记录 / 设置」五页。
///
/// 纪律（§7.8 / 任务约束）：**原样保留** B19/B20 返回栈行为——
///  · Scaffold + AppBar(title '家长天地')；
///  · PopScope(canPop:false) 拦截系统返回键 → 回到孩子端（`context.go('/')`）；
///  · AppBar.leading 显式「返回孩子端」按钮，行为同 PopScope。
///
/// 视觉：整页套家长端主题（青蓝主色 + 冷调底），与孩子端阳光黄明显区分；
/// 深色开关打开时自动切到 [parentDarkTheme]（M3 修订）。
///
/// M3 导航重构：tab 由 AppBar 顶部 [TabBar] 挪到屏幕**底部** [NavigationBar]；
/// 用 [IndexedStack] 保活各页（页面有输入/滚动状态，切走不应丢）。
/// C49（玄参 2026-10-10）：夸夸台 tab 裁撤（纯本地备忘壳、孩子端不可见、实用价值低），
/// 5 tab 收敛为 4 tab。
/// C54（玄参 2026-10-10）：新增「记录」tab（成长任务完成 / 奖励兑换历史，按内容统计次数），
/// 4 tab 扩为 5 tab：今日 / 奖励 / 成长 / 记录 / 设置。
library parent_home_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_history_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/child_profile_bar.dart';
import 'package:sunflower_time/shared/adaptive_nav_bar.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 家长端首页：底部导航壳（5 tab：今日 / 奖励 / 成长 / 记录 / 设置）。
///
/// C76（专注报告 v2）：支持带参直达 —— `/parent/home?tab=3&seg=0` 落地到
/// 「记录」tab 的「专注报告」段（设置页「专注报告」入口卡 / 旧深链 `/parent/report`
/// 都经此进入），家长端 ≤1 click 可看报告。
class ParentHomePage extends StatefulWidget {
  const ParentHomePage({super.key, this.initialTab = 0, this.initialSegment = 0});

  /// 初始 tab（0 今日 / 1 奖励 / 2 成长 / 3 记录 / 4 设置；越界自动夹取）。
  final int initialTab;

  /// 「记录」tab 内的初始分段（0 专注报告 / 1 任务与奖励）；其余 tab 忽略此值。
  final int initialSegment;

  @override
  State<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends State<ParentHomePage> {
  /// 底栏 tab 总数（今日 / 奖励 / 成长 / 记录 / 设置）。
  static const int _kTabCount = 5;

  /// 当前 tab（默认「今日」）。
  late int _index;

  @override
  void initState() {
    super.initState();
    // State 字段不能在声明处读 widget，必须在 initState 里初始化。
    _index = widget.initialTab.clamp(0, _kTabCount - 1);
  }

  @override
  void didUpdateWidget(ParentHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 带参直达（`/parent/home?tab=n`）在「同页复用 State、仅 props 变化」时也能生效。
    if (oldWidget.initialTab != widget.initialTab) {
      _index = widget.initialTab.clamp(0, _kTabCount - 1);
    }
  }

  /// 5 tab 保活栈（C90 期 2：按孩子档案修订号整组重挂载）。
  ///
  /// [childProfileRevisionProvider] 变化（家长切换 / 新建 / 编辑 / 删除孩子成功）
  /// → 五个 KeyedSubtree 的 key 全换 → IndexedStack 整组 tab **卸载重建** =
  /// 各页 `initState → _reload()` 全量重读当前孩子的数据（期 2 起数据已按孩子
  /// 隔离，防「切完孩子还是上个孩子的快照」）。
  ///
  /// ⚠️ 取舍（拍板口径）：切孩子是**低频**动作，整组重挂载会丢各 tab 的滚动位 /
  /// 输入态 —— 可接受，换来五个页面数据源一次换净；不做逐页 listenManual 改造
  ///（5 个页面一个都不碰，改动面最小）。日常切 tab（修订号不变）仍是原样保活。
  Widget _buildIndexedStack() {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final int revision = ref.watch(childProfileRevisionProvider);
        // key 带 tab 后缀（同级 children 的 key 必须唯一，防 debug 断言
        // 「Duplicate keys found」）；五个 key 共享同一 revision 段，
        // 修订号一变即整组换 key → 全量重挂载。
        return IndexedStack(
          index: _index,
          children: <Widget>[
            KeyedSubtree(
              key: ValueKey<String>('c90-child-$revision-today'),
              child: const ParentTodayPage(),
            ),
            KeyedSubtree(
              key: ValueKey<String>('c90-child-$revision-reward'),
              child: const ParentRewardPage(),
            ),
            // 任务 tab 复用任务配置页的 embedded 形态（不叠加第二层 AppBar；
            // 返回栈仍由本页 AppBar / 系统返回键统一处理）。
            KeyedSubtree(
              key: ValueKey<String>('c90-child-$revision-task'),
              child: const ParentTaskConfigPage(embedded: true),
            ),
            // C54：记录 tab（C76：分段承载「专注报告」+「任务与奖励」）。
            // 带参直达时把 initialSegment 透传给记录页。
            KeyedSubtree(
              key: ValueKey<String>('c90-child-$revision-history'),
              child: ParentHistoryPage(initialSegment: widget.initialSegment),
            ),
            KeyedSubtree(
              key: ValueKey<String>('c90-child-$revision-settings'),
              child: const ParentSettingsPage(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 家长端首页是路由栈底（登录用 go 替换了栈），Android 系统返回键在此会直接
    // 退出 App；拦下并回到孩子端，与 AppBar 返回箭头行为一致。
    //
    // 主题：读外层亮度（app.dart 已按 settings.themeDark 设好 themeMode），
    // 再套家长端皮肤，保证深色开关在家长端同样生效。
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析；Builder 的
    // context 参数位于 scope 之下，可安全取文案。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return Theme(
            data: parentThemeFor(Theme.of(context).brightness),
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                context.go('/');
              },
              child: Scaffold(
                appBar: AppBar(
                  title: Text(l10n.parent_home_title),
                  // 显式返回孩子端：PIN 登录成功用的是 `go`（替换路由栈），栈内没有
                  // 上级页面，AppBar 不会自动渲染返回箭头 → 会「进得去出不来」（B19）。
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l10n.parent_home_back_tooltip,
                    onPressed: () => context.go('/'),
                  ),
                ),
                // C90 期 1：顶部「当前孩子」胶囊条（切换 / 新建入口只在家长天地），
                // 下方 5 tab IndexedStack 原样保活。
                body: Column(
                  children: <Widget>[
                    const ChildProfileBar(),
                    Expanded(child: _buildIndexedStack()),
                  ],
                ),
                // C61 平板适配：限宽居中（同孩子端）；手机端原样（零变化）。
                bottomNavigationBar: AdaptiveNavBarHost(
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: (int i) =>
                        setState(() => _index = i),
                    destinations: <NavigationDestination>[
                      NavigationDestination(
                        icon: const Icon(Icons.today_outlined),
                        selectedIcon: const Icon(Icons.today),
                        label: l10n.parent_home_tab_today,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.card_giftcard_outlined),
                        selectedIcon: const Icon(Icons.card_giftcard),
                        label: l10n.parent_home_tab_reward,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.checklist_outlined),
                        selectedIcon: const Icon(Icons.checklist),
                        label: l10n.parent_home_tab_growth,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.history_outlined),
                        selectedIcon: const Icon(Icons.history),
                        label: l10n.parent_home_tab_history,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        label: l10n.parent_home_tab_settings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
