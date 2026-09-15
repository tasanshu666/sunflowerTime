/// 家长端首页（M0 占位）。M2 将接入核销卡 / 夸夸台 / 奖励配置（§5）。
library parent_home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 家长端首页是路由栈底（登录用 go 替换了栈），Android 系统返回键在此会直接
    // 退出 App；拦下并回到孩子端，与 AppBar 返回箭头行为一致。
    return PopScope(
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
        body: const Center(
          child: Text('家长端首页\nM0 骨架占位 · M2 接入核销/夸夸台/奖励配置'),
        ),
      ),
    );
  }
}
