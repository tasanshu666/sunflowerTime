/// 应用入口（§5 T01 工程脚手架）：初始化 SharedPreferences → bootstrap → ProviderScope(App)。
///
/// 替换 spike 阶段的最小入口；专注链路仍保留为路由入口（`/focus`）。
library main;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/app.dart';
import 'package:sunflower_time/bootstrap.dart';
import 'package:sunflower_time/core/constants/build_flags.dart';
import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/repositories/reward_seed.dart';
import 'package:sunflower_time/data/local/task_seed.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await bootstrap();

  // M2（T-D）：用同一个容器预跑奖励种子（首次启动若无模板则写入），
  // 并复用该容器给 App，保证种子与运行期共享同一个 AppDatabase 实例。
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // 付费墙（阶段 4 · P1 修复）：冷启动**先加载权益票据**并写入 `entitlementProvider`
  // 门控单点。抽取为顶层 [hydrateEntitlement]，便于被冷启动回归测试直接单测
  //（`main()` 顶层逻辑无法在测试宿主直接跑）。
  await hydrateEntitlement(container);
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

  // P0 · B（纪念册）：启动惰性补写「本周花园快照」（每周一次、幂等；不补历史周）。
  // 与种子 / releaseQueue 同款 unawaited 模式：不阻塞启动、不改时序。
  unawaited(
    container
        .read(memoirServiceProvider)
        .ensureWeeklySnapshot(DateTime.now())
        .catchError((Object e, StackTrace st) {
      debugPrint('[memoir] 花园周快照写入失败：$e\n$st');
    }),
  );

  // C44（玄参 2026-10-09）：全 App **默认锁竖屏**——除专注链路（专注页/护眼卡
  // 临时切横屏，退场各自恢复竖屏）外，任何页面不随物理旋转。
  // 各页面自己的锁是叠加态：专注页进场改横、退场改回竖；此处只是全局初值。
  try {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {} // 方向锁失败静默：体验优化，不阻塞启动。

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const App(),
    ),
  );
}

/// 冷启动「落票据」：读安全区票据并回填 [entitlementProvider]（门控单点）。
///
/// 付费墙（阶段 4 · P1 修复）：若不落票据，**已购用户冷启动会被误判为 free**
///（直到进过购买页），导致所有门控按 free 生效 —— 买了也不解锁。
///
/// 失败安全：`EntitlementLocalRepository.read` 内部已 catch 回退 free、绝不抛；
/// 此处再兜一层 try/catch，确保任何异常都不阻塞启动（按 free 继续）。
///
/// ⚠️ 抽成**顶层函数**（而非内联在 `main()`）以便被
/// `test/qa/cold_start_entitlement_test.dart` 直接单测；行为与内联版逐字一致。
Future<void> hydrateEntitlement(ProviderContainer container) async {
  // 内部验收包（`--dart-define=FORCE_UNLOCK_ALL=true`）：跳过票据读取，直接注入
  // 永久会员，供自家设备验收付费区。默认构建该常量为 false → 正式包行为逐字不变。
  // 🔴 不写库：是否会员只由「构建时带没带 define」决定，卸载重装不会改变。
  if (kForceUnlockAll) {
    container.read(entitlementProvider.notifier).state = Entitlement.lifetime(
      acquiredAt: DateTime(2026, 10, 17),
      productId: kIapProductIdLifetime,
    );
    debugPrint('[entitlement] FORCE_UNLOCK_ALL 生效：本次启动按永久会员运行');
    return;
  }
  try {
    final Entitlement entitlement =
        await container.read(entitlementServiceProvider).load();
    container.read(entitlementProvider.notifier).state = entitlement;
  } catch (e) {
    debugPrint('[entitlement] 启动加载失败（按 free 继续）：$e');
  }
}
