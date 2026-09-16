/// 休息页（T11，§6.3 休息节奏）。
///
/// 每完成 [AppSettings.restAfterSessions] 场专注后需休息 [AppSettings.restMinutes] 分钟。
/// 倒计时归零前「我休息好了」按钮禁用；归零后点击即标记 restSatisfied 并回入口页。
library rest_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';

class RestPage extends ConsumerStatefulWidget {
  const RestPage({super.key});

  @override
  ConsumerState<RestPage> createState() => _RestPageState();
}

class _RestPageState extends ConsumerState<RestPage> {
  late final int _totalSeconds;
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 休息时长来自 Settings 单例（§6.3）；未就绪时回退常量默认 10 分钟。
    final int restMinutes =
        ref.read(settingsProvider).value?.restMinutes ?? kRestMinutes;
    _totalSeconds = restMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );
  }

  void _tick() {
    if (_remainingSeconds <= 0) {
      _timer?.cancel();
      return;
    }
    setState(() => _remainingSeconds -= 1);
    if (_remainingSeconds <= 0) _timer?.cancel();
  }

  void _finish() {
    // 标记已休息满足，供入口页 evaluate 判定放行。
    ref.read(restSatisfiedProvider.notifier).state = true;
    context.go('/entry');
  }

  @override
  void dispose() {
    // 防泄漏：退出页面必须 cancel Timer（B31 教训）。
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool done = _remainingSeconds <= 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('休息一下'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => context.go('/entry'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '休息一下，喝口水～ 还剩 $_remainingSeconds 秒',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  // 倒计时未到时禁用（B31 防误触）。
                  onPressed: done ? _finish : null,
                  child: const Text('我休息好了'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
