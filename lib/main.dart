import 'package:flutter/material.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/s1_demo_page.dart';

void main() => runApp(const SunFocusApp());

/// 最小可运行工程入口（spike 阶段）。仅用于本地预览三个 spike，非产品最终壳。
class SunFocusApp extends StatelessWidget {
  const SunFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SunFocus · Spike',
      theme: ThemeData(primarySwatch: Colors.amber),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SunFocus · Spike 演示')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('S1 · 四档反馈 + 向日葵画布'),
            subtitle: const Text('一屏 demo，四档可切换预览'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const S1DemoPage()),
            ),
          ),
          ListTile(
            title: const Text('S3 · 打盹屏专注页'),
            subtitle: const Text('横屏 + 计时 + 常亮 + 方向锁（真机验证常亮/计时）'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FocusPage(plannedMinutes: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
