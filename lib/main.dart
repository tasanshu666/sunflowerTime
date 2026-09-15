/// 应用入口（§5 T01 工程脚手架）：初始化 SharedPreferences → bootstrap → ProviderScope(App)。
///
/// 替换 spike 阶段的最小入口；S1/S3 的 demo 仍保留为路由入口（`/s1-demo`、`/focus`）。
library main;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/app.dart';
import 'package:sunflower_time/bootstrap.dart';
import 'package:sunflower_time/core/di/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await bootstrap();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}
