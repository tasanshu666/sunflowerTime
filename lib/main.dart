/// 应用入口（§5 T01 工程脚手架）：初始化 SharedPreferences → bootstrap → ProviderScope(App)。
///
/// 替换 spike 阶段的最小入口；S1/S3 的 demo 仍保留为路由入口（`/s1-demo`、`/focus`）。
library main;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/app.dart';
import 'package:sunflower_time/bootstrap.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/repositories/reward_seed.dart';
import 'package:sunflower_time/data/local/task_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await bootstrap();

  // M2（T-D）：用同一个容器预跑奖励种子（首次启动若无模板则写入），
  // 并复用该容器给 App，保证种子与运行期共享同一个 AppDatabase 实例。
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // M2（T-D）：首次启动播种奖励模板。此处原版用 unawaited 把异常静默吞掉，
  // 导致玄参大人真机的「奖励模板缺失」故障极难发现。改为至少把异常打到日志，
  // 不改启动时序、不阻塞启动、不改变 UX。
  unawaited(
    ensureRewardSeed(container.read(rewardRepositoryProvider)).catchError(
      (Object e, StackTrace st) {
        debugPrint('[seed] 奖励模板播种失败：$e\n$st');
      },
    ),
  );

  // M3（T05）：首次启动播种任务模板（若无模板则写入 3 条内置，幂等）。
  unawaited(
    ensureTaskSeed(container.read(taskRepositoryProvider)).catchError(
      (Object e, StackTrace st) {
        debugPrint('[seed] 任务模板播种失败：$e\n$st');
      },
    ),
  );

  // M2（A1）：跨周排队释放 —— 启动即尝试释放「上周排队」（次周周一自动放行，§4.2）。
  // queued 状态从不扣账本/扣池，释放时才扣减；幂等（已释放的不再处于 queued）。
  unawaited(
    container
        .read(redemptionOrchestrationServiceProvider)
        .releaseQueue(previousWeekKey(DateTime.now()), DateTime.now())
        .then((_) {})
        .catchError((Object e, StackTrace st) {
      debugPrint('[releaseQueue] 跨周排队释放失败：$e\n$st');
    }),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const App(),
    ),
  );
}
