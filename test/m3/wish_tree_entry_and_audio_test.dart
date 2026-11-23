/// v0.2.0 新入口命中 + 许愿树场景闸门停 / 复播回归（R-P0-04/05 / R-P1-01）。
///
/// 音频判据观测点 = [AudioService] 的测试可见计数器（`gardenAmbientPlayCalls` /
/// `ambientGeneration` / `ambientShouldPlay`）——它们不受 just_audio 后端与
/// 设置开关影响，正是「页面是否还在补播」的最直接证据。
///
/// 🔴 本文件**不复制**花园页判据自证：闸门相关用例一律挂载**真实 `GardenPage`**
/// 与**真实 `WishTreePage`**（真实 DI / 内存库 / 真实 GoRouter push-pop），
/// 避免 WISH-V02-BUG-01 那种「源码字符串守卫 + 自造 harness」式假绿。
/// ⚠️ 花园页有无限动画，本文件全程有界 `pump`，禁止 `pumpAndSettle` 在花园页上跑。
library wish_tree_entry_and_audio_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/state/wish_tree_scene_state.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';

/// 离线 IAP：把插件通道挡在测试外。
class _OfflineIap implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();

  @override
  Future<bool> isStoreAvailable() async => false;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> ids) async =>
      <IapProduct>[];

  @override
  Future<void> startLifetimePurchase(String id) async {}

  @override
  Future<void> startRestore() async {}
}

/// `bgmOn/soundOn` 关：把 just_audio / path_provider 挡在测试外；
/// 起播请求计数与 `ambientShouldPlay` 仍在入口处同步递增，判据照常可用。
class _QuietSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        soundOn: false,
        bgmOn: false,
      );

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 真实 DI 宿主：内存库 + 真实 `AccountService` + 真实服务图。
class _Host {
  _Host(this.tester, this.container);

  final WidgetTester tester;
  final ProviderContainer container;

  static Future<_Host> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
        settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    return _Host(tester, container);
  }

  /// 有界帧推进（花园页无限动画 ⇒ 禁用 `pumpAndSettle`）。
  Future<void> frames({int n = 12, int stepMs = 80}) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(Duration(milliseconds: stepMs));
    }
  }

  bool get gate => container.read(wishTreeSceneActiveProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AudioService audio = AudioService.instance;

  setUp(() => audio.resetForTest());

  group('R-P0-05 天气下方新入口', () {
    testWidgets('热区 ≥ 48×48，点击上抛一次', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: WishTreeWeatherEntry(
              label: '我的许愿树',
              onTap: () => taps++,
            ),
          ),
        ),
      ));
      final Size size = tester.getSize(find.byKey(kWishTreeWeatherEntryKey));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(kWishTreeWeatherEntryKey));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击入口路由到 /wish-tree（旧两处入口不删）',
        (WidgetTester tester) async {
      final GoRouter router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Center(
                child: WishTreeWeatherEntry(
                  label: '我的许愿树',
                  onTap: () => context.push('/wish-tree'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/wish-tree',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Center(child: Text('TREE_PAGE'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.byKey(kWishTreeWeatherEntryKey));
      await tester.pumpAndSettle();

      expect(find.text('TREE_PAGE'), findsOneWidget);
      expect(router.state.uri.path, '/wish-tree');
    });

    test('花园页布局：入口收进右上角单簇、调试入口随簇顺延（源码守卫）', () {
      final String src = File(
        'lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      // v0.3.0（R3-P0-11）：堆叠折叠进单个 Column —— 不再有「各自算 top」的并列 Positioned。
      expect(src.contains('WishTopEntryCluster('), isTrue,
          reason: '右上角改由复用簇渲染「图标 + 下方文字」');
      expect('WishTopEntryCluster('.allMatches(src).length, 2,
          reason: '簇只有两个：天气 + 许愿树');
      expect(src.contains('kWishTreeTopClusterKey'), isTrue,
          reason: '整簇稳定 Key');
      expect(src.contains('kGardenTopEntryGap'), isTrue,
          reason: '两簇之间的间距走 prd_params 单点常量');
      // 图标↔文字的 4dp 间隙归簇组件定义（不在页面里散写数字）。
      final String cluster = File(
        'lib/presentation/child/widgets/wish_top_entry_cluster.dart',
      ).readAsStringSync();
      expect(cluster.contains('kGardenTopLabelGap'), isTrue,
          reason: '图标↔文字间距走 prd_params 单点常量');
      expect(src.contains('gardenDebugEntryTop('), isFalse,
          reason: '旧「手工 top 偏移」已废：调试入口作为簇的下一个子项自然顺延');
      expect(src.contains('WishTreeHotspot('), isFalse,
          reason: 'v0.3 减法：左下角旧热点已整体删除（Key 常量保留）');
    });
  });

  group('R-P0-04 场景闸门停 / 复播', () {
    test('闸门 provider 默认值 false，可翻转（纯状态）', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(wishTreeSceneActiveProvider), isFalse);
      container.read(wishTreeSceneActiveProvider.notifier).state = true;
      expect(container.read(wishTreeSceneActiveProvider), isTrue);
      container.read(wishTreeSceneActiveProvider.notifier).state = false;
      expect(container.read(wishTreeSceneActiveProvider), isFalse);
    });

    // ── 真实 GardenPage：闸门 true ⇒ cancel 定时器 + 停播，60s 零补播；false ⇒ 复播 ──
    testWidgets('真实 GardenPage：闸门置 true ⇒ 停播并 cancel 定时器；60s 无复发；置 false ⇒ 复播',
        (WidgetTester tester) async {
      final _Host h = await _Host.boot(tester);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        // embedded:false ⇒ 整屏花园，无外壳也恒可见（与直接 push /garden 同形态）。
        child: const MaterialApp(home: GardenPage()),
      ));
      await h.frames();

      final int initialPlays = audio.gardenAmbientPlayCalls;
      expect(initialPlays, greaterThanOrEqualTo(1),
          reason: '闸门未开时花园立即起播一次');
      expect(audio.ambientShouldPlay, isTrue);

      // 定时器确实在跑：一个周期补播一次（这是「可循环听见」的机制本体）。
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await h.frames(n: 2);
      expect(audio.gardenAmbientPlayCalls, greaterThanOrEqualTo(initialPlays + 1),
          reason: '30s 周期补播必须工作（修复不能顺手删掉）');

      // 进入许愿树：置 true → 真实花园页 cancel 定时器 + stop。
      final int generationBefore = audio.ambientGeneration;
      h.container.read(wishTreeSceneActiveProvider.notifier).state = true;
      await h.frames();
      expect(audio.ambientGeneration, generationBefore + 1,
          reason: 'stopGardenAmbient 被真实花园页调用');
      expect(audio.ambientShouldPlay, isFalse);

      final int playsAtGate = audio.gardenAmbientPlayCalls;
      // 停留 60s（覆盖 2 个 30s 周期）：定时器已 cancel，零复发。
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
      await h.frames(n: 2);
      expect(audio.gardenAmbientPlayCalls, playsAtGate,
          reason: 'Timer.periodic 已 cancel，60s 内不得有任何 play 调用');

      // 返回花园：置 false → 立即复播并重建定时器。
      h.container.read(wishTreeSceneActiveProvider.notifier).state = false;
      await h.frames();
      expect(audio.gardenAmbientPlayCalls, playsAtGate + 1,
          reason: '返回花园立即复播一次');
      expect(audio.ambientShouldPlay, isTrue);
      expect(tester.takeException(), isNull);

      // 收尾：卸载花园页，成对 cancel 定时器（否则测试结束仍有 pending timer）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    // ── 真实 WishTreePage：挂载置 true / 卸载置 false，全程不得抛异常 ──
    testWidgets('真实 WishTreePage：挂载不抛异常 + 挂载后闸门 true + 卸载后闸门 false',
        (WidgetTester tester) async {
      final _Host h = await _Host.boot(tester);
      expect(h.gate, isFalse, reason: '初始无树页 ⇒ 闸门关');

      // 先挂一个「已存在的常驻 ProviderScope 根」，模拟真实导航时 scope 非本帧新建。
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ));
      await h.frames(n: 4);
      expect(tester.takeException(), isNull, reason: '前置：scope 常驻挂载无异常');

      // 挂载真实树页（= 任意入口 push 进 /wish-tree）。
      final int wishPlayCallsBefore = audio.wishTreeAmbientPlayCalls;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: WishTreePage()),
      ));
      await h.frames(n: 10);
      final Object? mountEx = tester.takeException();
      expect(find.byType(WishTreePage), findsOneWidget,
          reason: '真实树页已上树');
      expect(h.gate, isTrue, reason: '真实树页挂载即占台前 ⇒ 闸门开');
      // C137：进入许愿树页必须请求起播**本页专属**背景音（观测点 = 起播请求计数，
      // 不受 bgmOn=false / just_audio 后端影响 —— 与花园 `gardenAmbientPlayCalls` 同口径）。
      expect(audio.wishTreeAmbientPlayCalls, wishPlayCallsBefore + 1,
          reason: '真实树页 initState 帧后必须调 AudioService.startWishTreeAmbient()');
      expect(audio.wishTreeAmbientShouldPlay, isTrue,
          reason: '页内「应播」意图已记录（bgmOn=false 时同样记，等设置迟到补播）');

      // 卸载真实树页（= pop 回花园）：闸门必须解除 + 专属背景音必须停。
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ));
      await h.frames(n: 4);
      final Object? unmountEx = tester.takeException();
      expect(find.byType(WishTreePage), findsNothing);
      expect(h.gate, isFalse,
          reason: '真实树页 dispose 必须解除闸门（否则返回花园音乐不恢复）');
      expect(audio.wishTreeAmbientShouldPlay, isFalse,
          reason: 'C137：离开许愿树页必须停播专属背景音（其他界面不播放）');
      expect(audio.wishTreeAmbientLooping, isFalse,
          reason: 'C137：离开许愿树页循环必须收尾');
      expect(mountEx, isNull,
          reason: '真实树页 initState / 首帧不得抛「Tried to modify a provider while '
              'the widget tree was building」: $mountEx');
      expect(unmountEx, isNull, reason: '真实树页 dispose 不得抛 provider 断言: $unmountEx');
    });

    // ── 真实 GoRouter push/pop：闸门随页面进出翻转 ──
    testWidgets('真实 GoRouter push/pop：闸门进出翻转且无生命周期异常',
        (WidgetTester tester) async {
      final _Host h = await _Host.boot(tester);
      final GoRouter router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('go_tree'),
                  onPressed: () => context.push('/wish-tree'),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/wish-tree',
            builder: (_, __) => const WishTreePage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await h.frames(n: 6);
      expect(h.gate, isFalse, reason: '首屏非树页 ⇒ 闸门关');

      await tester.tap(find.byKey(const Key('go_tree')));
      await h.frames(n: 12);
      final Object? pushEx = tester.takeException();
      expect(router.state.uri.path, '/wish-tree');
      expect(h.gate, isTrue, reason: 'push 进树页 ⇒ 闸门开');

      router.pop();
      await h.frames(n: 8);
      final Object? popEx = tester.takeException();
      expect(router.state.uri.path, '/');
      expect(h.gate, isFalse, reason: 'pop 回花园 ⇒ 闸门必须解除，否则音乐不恢复');
      expect(pushEx, isNull,
          reason: '真实 push 不得抛「Tried to modify a provider while the widget '
              'tree was building」: $pushEx');
      expect(popEx, isNull, reason: 'pop 不得抛生命周期异常: $popEx');
    });

    test('花园页折入门闸且复用既有成对启停；树页有且仅有自己的专属背景音（源码守卫）', () {
      final String garden = File(
        'lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      expect(
        garden.contains('gardenVisible && !ref.watch(wishTreeSceneActiveProvider)'),
        isTrue,
        reason: '环境音局部判据必须折入场景闸门',
      );
      expect(garden.contains('_syncAmbientTimer();'), isTrue,
          reason: '复用既有成对启停（cancel timer + stop player）');
      expect(garden.contains('bool get _gardenVisible =>'), isTrue,
          reason: '共享 _gardenVisible getter 不动');

      // 树页闸门**行为**已由上两条真实挂载用例覆盖；此处守「音频调用纪律」。
      // （不再断言 `.notifier).state = true` 文本 —— 那正是被修掉的 build 期写入写法。）
      final String tree = File(
        'lib/presentation/child/pages/wish_tree_page.dart',
      ).readAsStringSync();
      final String treeCode = tree
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('///'))
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      // C137（玄参 2026-11-22）：树页现在**必须**驱动自己的专属背景音，
      // 「零 AudioService 代码」的旧纪律就此作废；改为守「只碰这两个成对 API」：
      // 既不许它去动花园的氛围音（playGardenAmbient / stopGardenAmbient），
      // 也不许它在 initState / dispose 里同步置播（会撞 WISH-V02-BUG-01 的生命周期坑）。
      expect(treeCode.contains('startWishTreeAmbient()'), isTrue,
          reason: 'C137：进入树页必须起播专属背景音');
      expect(treeCode.contains('stopWishTreeAmbient('), isTrue,
          reason: 'C137：离开树页必须停专属背景音');
      expect(treeCode.contains('playGardenAmbient'), isFalse,
          reason: '树页不得插手花园氛围音（两套音各自成对启停）');
      expect(treeCode.contains('stopGardenAmbient'), isFalse,
          reason: '树页不得插手花园氛围音（花园音由花园页自己停）');
      // 反向守卫：只允许通过 initState 捕获的 controller 写闸门，
      // 禁止 `ref.read(...notifier).state =` 这种 build/initState 期直接写（WISH-V02-BUG-01）。
      expect(
        treeCode.contains('ref.read(wishTreeSceneActiveProvider.notifier).state'),
        isFalse,
        reason: '必须在 initState 捕获 controller 并延后写入，不得直接 ref.read(...).state =',
      );
      expect(treeCode.contains('late final StateController<bool> _sceneGateCtrl'),
          isTrue,
          reason: 'initState 捕获 notifier 字段引用（照 ChildShellPage 先例）');
      expect(treeCode.contains('addPostFrameCallback'), isTrue,
          reason: '置 true 必须延后到帧后，避开 build 期 markNeedsBuild 断言');
    });
  });
}
