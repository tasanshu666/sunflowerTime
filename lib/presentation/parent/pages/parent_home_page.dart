/// 家长端首页（M2 · T-F）：改为 TabBar 壳，承载「今日 / 奖励 / 夸夸台」三页。
///
/// 纪律（§7.8 / 任务约束）：**原样保留** B19/B20 返回栈行为——
///  · Scaffold + AppBar(title '家长天地')；
///  · PopScope(canPop:false) 拦截系统返回键 → 回到孩子端（`context.go('/')`）；
///  · AppBar.leading 显式「返回孩子端」按钮，行为同 PopScope。
///
/// 视觉：整页套 [parentTheme]（青蓝主色 + 冷调浅底），与孩子端阳光黄明显区分。
library parent_home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_praise_page.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 家长端首页：TabBar 壳。
class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 家长端首页是路由栈底（登录用 go 替换了栈），Android 系统返回键在此会直接
    // 退出 App；拦下并回到孩子端，与 AppBar 返回箭头行为一致。
    return Theme(
      data: parentTheme,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          context.go('/');
        },
        child: DefaultTabController(
          length: 3,
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
              bottom: const TabBar(
                tabs: <Widget>[
                  Tab(text: '今日', icon: Icon(Icons.today)),
                  Tab(text: '奖励', icon: Icon(Icons.card_giftcard)),
                  Tab(text: '夸夸台', icon: Icon(Icons.favorite)),
                ],
              ),
            ),
            body: const TabBarView(
              children: <Widget>[
                ParentTodayPage(),
                ParentRewardPage(),
                ParentPraisePage(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
