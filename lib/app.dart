/// 应用壳：Riverpod ProviderScope + Theme + Router（§5 T01）。
///
/// M3 修订：主题模式由 `settings.themeDark` 驱动（原先只挂了 `theme: lightTheme`，
/// 家长端深色开关写进库却无人消费 → 真机反馈「开关没变化」）。
library app;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/shared/app_router.dart';
import 'package:sunflower_time/shared/theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // 设置尚未读出时回落浅色（默认皮肤），避免首帧闪深色。
    // 家长端设置页保存后 invalidate 本 Provider，切换即时生效。
    final bool dark = ref.watch(settingsProvider).value?.themeDark ?? false;
    return MaterialApp.router(
      title: 'SunFocus 向日葵专注',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
