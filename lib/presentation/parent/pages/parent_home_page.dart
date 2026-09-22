/// 家长端首页（M3 导航重构）：底部导航壳，承载「今日 / 奖励 / 任务 / 夸夸台 / 设置」五页。
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
/// 用 [IndexedStack] 保活各页（夸夸台等页有输入/滚动状态，切走不应丢）。
library parent_home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_praise_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 家长端首页：底部导航壳（5 tab：今日 / 奖励 / 任务 / 夸夸台 / 设置）。
class ParentHomePage extends StatefulWidget {
  const ParentHomePage({super.key});

  @override
  State<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends State<ParentHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // 家长端首页是路由栈底（登录用 go 替换了栈），Android 系统返回键在此会直接
    // 退出 App；拦下并回到孩子端，与 AppBar 返回箭头行为一致。
    //
    // 主题：读外层亮度（app.dart 已按 settings.themeDark 设好 themeMode），
    // 再套家长端皮肤，保证深色开关在家长端同样生效。
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
            title: const Text('家长天地'),
            // 显式返回孩子端：PIN 登录成功用的是 `go`（替换路由栈），栈内没有
            // 上级页面，AppBar 不会自动渲染返回箭头 → 会「进得去出不来」（B19）。
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回孩子端',
              onPressed: () => context.go('/'),
            ),
          ),
          body: IndexedStack(
            index: _index,
            children: const <Widget>[
              ParentTodayPage(),
              ParentRewardPage(),
              // 任务 tab 复用任务配置页的 embedded 形态（不叠加第二层 AppBar；
              // 返回栈仍由本页 AppBar / 系统返回键统一处理）。
              ParentTaskConfigPage(embedded: true),
              ParentPraisePage(),
              ParentSettingsPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (int i) => setState(() => _index = i),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: '今日',
              ),
              NavigationDestination(
                icon: Icon(Icons.card_giftcard_outlined),
                selectedIcon: Icon(Icons.card_giftcard),
                label: '奖励',
              ),
              NavigationDestination(
                icon: Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist),
                label: '成长',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_outline),
                selectedIcon: Icon(Icons.favorite),
                label: '夸夸台',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
