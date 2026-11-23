/// QA 独立差分复验 · 音频闸门（**真实 GardenPage**，非复制 harness）。
///
/// 工程师 `test/m3/wish_tree_entry_and_audio_test.dart` 用 `_AmbientHarness`
/// **照抄**了花园页判据再自证 —— 即使花园页接线错了，该用例照样绿（假绿）。
/// 本文件把**真实 `GardenPage`** 挂在真实 DI（内存库）上，进步长到 2 个
/// 30s 周期，断言期间 `gardenAmbientPlayCalls` 一格不动 / `ambientShouldPlay`
/// 恒 false；再用**真实 `WishTreePage`** 的挂载/卸载证明闸门由页面生命周期
/// 驱动（与入口无关，故今日页旧入口 push 同样生效）；最后用真实渲染几何
/// 证明新入口在天气徽标正下方且不与调试入口重叠。
///
/// ⚠️ 花园页有无限动画 → 全程有界 pump，禁止 `pumpAndSettle`。
library wish_tree_audio_v02_qa_test;

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
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_top_entry_cluster.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';

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

/// bgmOn/soundOn 关：把 just_audio / path_provider 挡在测试外；
/// 起播请求计数与 ambientShouldPlay 仍照常工作（AudioService 入口处同步递增）。
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

  Future<void> mountGarden() async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      // embedded:false ⇒ 整屏花园，无外壳也恒可见（与直接 push /garden 同形态）。
      child: const MaterialApp(home: GardenPage()),
    ));
    await frames();
  }

  Future<void> frames({int n = 12, int stepMs = 80}) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(Duration(milliseconds: stepMs));
    }
  }

  void setGate(bool value) =>
      container.read(wishTreeSceneActiveProvider.notifier).state = value;
  bool get gate => container.read(wishTreeSceneActiveProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AudioService audio = AudioService.instance;

  setUp(() => audio.resetForTest());

  testWidgets('真实 GardenPage：闸门 true ⇒ 取消定时器 + 停播，60s 零补播；false ⇒ 复播',
      (WidgetTester tester) async {
    final _Host h = await _Host.boot(tester);
    await h.mountGarden();

    expect(audio.gardenAmbientPlayCalls, greaterThanOrEqualTo(1),
        reason: '花园一上屏立即播一次');
    expect(audio.ambientShouldPlay, isTrue);

    // 定时器真实在跑：一个 30s 周期确实补播一次（这是「可循环听见」的机制本体）。
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await h.frames(n: 2);
    final int beforeGate = audio.gardenAmbientPlayCalls;
    expect(beforeGate, greaterThanOrEqualTo(2),
        reason: '闸门未开时 30s 定时补播必须工作（修复不能顺手删掉）');

    // ── 进入许愿树：树页 initState 置 true（这里直接翻 provider = 同一真源）──
    h.setGate(true);
    await h.frames();
    expect(audio.ambientShouldPlay, isFalse,
        reason: '真实花园页必须因闸门翻 false 而停播');
    expect(audio.ambientPlaying, isFalse);
    final int frozen = audio.gardenAmbientPlayCalls;

    // 停留超过 2 个 30s 周期：定时器已 cancel，绝不允许任何 playGardenAmbient()。
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await h.frames(n: 2);
    expect(audio.gardenAmbientPlayCalls, frozen,
        reason: '真实花园页的 Timer.periodic 必须已被 cancel（只 stop 播放器会被复发）');
    expect(audio.ambientShouldPlay, isFalse, reason: 'isPlaying 语义恒 false');
    expect(audio.ambientPlaying, isFalse);

    // ── 返回花园：闸门 false ⇒ 立即复播 + 重建定时器 ──
    h.setGate(false);
    await h.frames();
    expect(audio.gardenAmbientPlayCalls, frozen + 1,
        reason: '返回花园立即复播一次');
    expect(audio.ambientShouldPlay, isTrue);
    // 复播后定时器重建：再过一个周期又补播一次。
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await h.frames(n: 2);
    expect(audio.gardenAmbientPlayCalls, frozen + 2,
        reason: '返回花园后定时器必须重建（成对启停）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实 WishTreePage：initState 置闸门 true、dispose 置 false（入口无关）',
      (WidgetTester tester) async {
    final _Host h = await _Host.boot(tester);
    expect(h.gate, isFalse, reason: '初始无树页 ⇒ 闸门关');

    // 先挂载一个「已存在的 ProviderScope 根」（模拟 app.dart 里常驻的
    // ProviderScope → MaterialApp，真实导航时 scope 不是本帧新建的）。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: SizedBox.shrink()),
    ));
    await h.frames(n: 4);
    expect(tester.takeException(), isNull, reason: '前置：scope 常驻挂载无异常');

    // 导航进入真实树页（scope 保持常驻，只有子树切换）。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: WishTreePage()),
    ));
    await h.frames(n: 10);
    final Object? initEx = tester.takeException();
    expect(h.gate, isTrue, reason: '真实树页挂载即占台前');

    // 卸载树页（等价于任意入口 push 后 pop）：闸门必须解除。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: SizedBox.shrink()),
    ));
    await h.frames(n: 4);
    final Object? disposeEx = tester.takeException();
    expect(h.gate, isFalse, reason: '树页 dispose 必须解除闸门（否则返回花园音乐不恢复）');
    // 汇总两处生命周期异常，一次报全（initState / dispose 均不得在 build 期改 provider）。
    expect(initEx, isNull,
        reason: '真实树页 initState 不得抛「Tried to modify a provider while the widget tree was building」: $initEx');
    expect(disposeEx, isNull,
        reason: '真实树页 dispose 不得抛 provider 修改断言 / Bad state: $disposeEx');
  });

  testWidgets('真实 GoRouter push/pop 路径：闸门进出翻转且无生命周期异常',
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
        reason: '真实 push 不得抛「Tried to modify a provider while the widget tree was building」: $pushEx');
    expect(popEx, isNull, reason: 'pop 不得抛生命周期异常: $popEx');
  });

  testWidgets('真实渲染几何：新入口在天气徽标正下方、视觉 44.8（手机档）、整簇热区 ≥48、与调试入口不重叠',
      (WidgetTester tester) async {
    // 手机视口：garden scale s==1，徽标恰为 56 高，top 12 ⇒ 底 68，新入口 top 80。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final _Host h = await _Host.boot(tester);
    await h.mountGarden();

    final Finder badge = find.byKey(kGardenWeatherBadgeIconKey);
    final Finder entry = find.byKey(kWishTreeWeatherEntryKey);
    final Finder debug = find.byType(BloomDebugEntry);
    expect(badge, findsOneWidget, reason: '天气徽标在真实花园页');
    expect(entry, findsOneWidget, reason: '新入口在真实花园页');
    expect(debug, findsOneWidget, reason: '调试入口仍在（debug 构建）');

    final Rect badgeRect = tester.getRect(badge);
    final Rect entryRect = tester.getRect(entry);
    final Rect debugRect = tester.getRect(debug);

    // R7-P0-03：手机侧图标本体视觉缩到 56×0.8=44.8（架构 §6.2 预期值），
    // 无障碍热区由外层簇的 ConstrainedBox(min 48) 兜底 —— 断言热区而非视觉本体。
    expect(entryRect.width, closeTo(56 * kPhoneEntryScale, 0.5),
        reason: '手机入口视觉 44.8（iPhone 单侧缩放）');
    expect(entryRect.height, closeTo(56 * kPhoneEntryScale, 0.5),
        reason: '手机入口视觉 44.8（iPhone 单侧缩放）');
    for (final Element e in find.byType(WishTopEntryCluster).evaluate()) {
      final Rect hit = tester.getRect(find.byWidget(e.widget));
      expect(hit.width, greaterThanOrEqualTo(48),
          reason: '整簇点击热区宽 ≥48（无障碍底线）');
      expect(hit.height, greaterThanOrEqualTo(48),
          reason: '整簇点击热区高 ≥48（无障碍底线）');
    }

    // v0.3.0（R3-P0-11）：图标下方多了**单行可见文字**，两段间距各走一个常量：
    //   徽标底 → 天气名   = kGardenTopLabelGap
    //   天气名底 → 许愿树图标 = kGardenTopEntryGap
    // 这样「天气块整体高度」由布局算出来，不再由未缩放常量猜（旧 bug 根因）。
    final Rect weatherLabel =
        tester.getRect(find.byKey(kGardenWeatherLabelKey));
    expect(weatherLabel.top - badgeRect.bottom, closeTo(kGardenTopLabelGap, 2.0),
        reason: '徽标与其下方天气名的间距 = kGardenTopLabelGap');
    expect(entryRect.top - weatherLabel.bottom, closeTo(kGardenTopEntryGap, 2.0),
        reason: '许愿树入口在天气块正下方，间距 = kGardenTopEntryGap');
    expect((entryRect.right - badgeRect.right).abs(), lessThan(2.0),
        reason: '新入口与徽标同 right 锚定（簇内右对齐，无额外水平内边距）');
    // 调试入口已顺延到许愿树入口的文字之下，不重叠、不拦截点击。
    final Rect entryLabel =
        tester.getRect(find.byKey(kWishTreeWeatherEntryLabelKey));
    expect(entryLabel.top - entryRect.bottom, closeTo(kGardenTopLabelGap, 2.0),
        reason: '许愿树图标与其名下文字间距 = kGardenTopLabelGap');
    expect(debugRect.top, greaterThanOrEqualTo(entryLabel.bottom),
        reason: 'BloomDebugEntry 必须在许愿树入口文字之下，不重叠');
    expect(tester.takeException(), isNull);
  });

  test('旧入口已删 / 今日页入口保留 + 路由可达（源码守卫补充）', () {
    final String garden = File(
      'lib/presentation/child/pages/garden_page.dart',
    ).readAsStringSync();
    final String today = File(
      'lib/presentation/child/pages/child_today_page.dart',
    ).readAsStringSync();
    final String router = File('lib/shared/app_router.dart').readAsStringSync();
    // v0.3.0：花园页只剩右上角簇内那 1 个 push（左下角旧热点已删，R3-P0-01）。
    expect(
      '${garden.split("context.push('/wish-tree')").length - 1}',
      '1',
      reason: '花园页唯一入口 = 右上角簇',
    );
    expect(today.contains("context.push('/wish-tree')"), isFalse,
        reason: '今日页底部速览卡已按玄参 v0.3 反馈 6 删除');
    expect(router.contains("path: '/wish-tree'"), isTrue);
  });
}
