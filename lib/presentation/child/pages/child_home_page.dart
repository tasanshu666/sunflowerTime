/// 孩子端首页（M0 占位，竖屏）。M1 将替换为「今日状态卡 + 底部导航」（§5）。
library child_home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChildHomePage extends StatelessWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('向日葵专注')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('孩子端首页', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            const Text('M0 骨架占位 · M1 接入今日状态卡与底部导航'),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => context.go('/focus'),
              child: const Text('进入打盹屏（S3）'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/s1-demo'),
              child: const Text('四档反馈预览（S1）'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/parent'),
              child: const Text('家长天地 →'),
            ),
          ],
        ),
      ),
    );
  }
}
