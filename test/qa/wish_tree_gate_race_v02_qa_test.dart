/// QA Round 2 对抗性复验 · 闸门修复「不是绕过断言」。
///
/// 工程师把 `WishTreePage` 的闸门写入改为：initState 抓 notifier 引用 +
/// `addPostFrameCallback` 置 true（带 `!mounted` 守卫）、dispose 里
/// `scheduleMicrotask` 置 false（带 `try/catch`）。本文件专打这些新写法
/// 可能引入的**新假绿**：
///  A. `scheduleMicrotask` 是否**真的执行并写入** —— 不信 gate==false 本身，
///     而是断言 **pop 后下一帧真实花园页读到 false 并真的重新 playGardenAmbient**；
///  B. push 首帧未到即 pop 的竞态窗口（`!mounted` 守卫）不残留 true、不抛异常；
///  C. 连续 push/pop 两次每次都复播、闸门不累积；
///  D. App 退出 / 容器销毁：`catch(_)` 不把异常逃逸成崩溃；且**新容器闸门恒 false**
///     （StateProvider 不持久化 ⇒ 不可能「永久卡 true 影响下次启动」）。
library wish_tree_gate_race_v02_qa_test;

import 'dart:async';

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

  Future<void> frames({int n = 12, int stepMs = 80}) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(Duration(milliseconds: stepMs));
    }
  }

  bool get gate => container.read(wishTreeSceneActiveProvider);
}

/// 真实 GardenPage（`/garden` 底路由）+ 真实 WishTreePage（`/wish-tree` push 路由）。
/// 花园页作为被覆盖的下层路由仍在树上（maintainState），闸门翻转时它会重建，
/// 从而我们可以观测「pop 后真实复播」。
GoRouter _gardenThenTree() => GoRouter(
      initialLocation: '/garden',
      routes: <RouteBase>[
        GoRoute(
          path: '/garden',
          builder: (_, __) => const GardenPage(),
        ),
        GoRoute(
          path: '/wish-tree',
          builder: (_, __) => const WishTreePage(),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AudioService audio = AudioService.instance;

  setUp(() => audio.resetForTest());

  testWidgets('A · pop 后微任务真写入：下一帧花园页真的重新 playGardenAmbient（非只 gate==false）',
      (WidgetTester tester) async {
    final _Host h = await _Host.boot(tester);
    final GoRouter router = _gardenThenTree();
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await h.frames(n: 10);

    expect(h.gate, isFalse);
    expect(audio.ambientShouldPlay, isTrue, reason: '花园页在播');
    final int afterMount = audio.gardenAmbientPlayCalls;
    expect(afterMount, greaterThanOrEqualTo(1));

    // 进树页
    router.push('/wish-tree');
    await h.frames(n: 10);
    expect(router.state.uri.path, '/wish-tree');
    expect(h.gate, isTrue);
    expect(audio.ambientShouldPlay, isFalse, reason: '进树页停播');
    final int frozen = audio.gardenAmbientPlayCalls;
    await tester.pump(const Duration(seconds: kGardenAmbientIntervalSeconds));
    await h.frames(n: 2);
    expect(audio.gardenAmbientPlayCalls, frozen, reason: '树页期间零补播');

    // 出树页：关键断言 —— 不只是 gate==false，而是花园页**真的**复播。
    router.pop();
    await h.frames(n: 10);
    expect(router.state.uri.path, '/garden');
    expect(h.gate, isFalse, reason: 'scheduleMicrotask 必须真的执行并写入 false');
    expect(audio.ambientShouldPlay, isTrue, reason: '花园页读到 false 后恢复意图');
    expect(audio.gardenAmbientPlayCalls, greaterThan(frozen),
        reason: 'pop 后下一帧花园页必须真的重新调用 playGardenAmbient（微任务真生效，非静默吞掉）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B · push 后首帧未到即 pop（!mounted 竞态窗口）：闸门不残留 true、无异常',
      (WidgetTester tester) async {
    final _Host h = await _Host.boot(tester);
    // 裸 Navigator：push/pop 同步改路由栈（不像 GoRouter 走异步 delegate），
    // 可以在**首帧构建树页之前**就把它 pop 掉 —— 精确命中 !mounted 竞态窗口。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: GardenPage()),
    ));
    await h.frames(n: 10);
    expect(h.gate, isFalse);
    final int before = audio.gardenAmbientPlayCalls;

    final NavigatorState nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const WishTreePage()));
    nav.pop(); // 同一同步块，首帧尚未走到 build/post-frame
    await h.frames(n: 12);

    expect(h.gate, isFalse,
        reason: '首帧未到即 pop：树页要么根本没 build、要么 post-frame 的 !mounted 守卫生效 ⇒ 绝不残留 true');
    expect(audio.ambientShouldPlay, isTrue, reason: '花园页保持播放，不得被卡死');
    expect(audio.gardenAmbientPlayCalls, greaterThanOrEqualTo(before),
        reason: '花园页不得因这次瞬时 push/pop 停摆');
    expect(tester.takeException(), isNull);
  });

  testWidgets('C · 连续 push/pop 两次：每次都复播、闸门不累积、无残留异常',
      (WidgetTester tester) async {
    final _Host h = await _Host.boot(tester);
    final GoRouter router = _gardenThenTree();
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await h.frames(n: 10);

    for (int i = 0; i < 2; i++) {
      final int before = audio.gardenAmbientPlayCalls;
      router.push('/wish-tree');
      await h.frames(n: 8);
      expect(h.gate, isTrue, reason: '第 ${i + 1} 次进树页闸门 true');
      expect(audio.ambientShouldPlay, isFalse);

      router.pop();
      await h.frames(n: 8);
      expect(h.gate, isFalse, reason: '第 ${i + 1} 次出树页闸门 false');
      expect(audio.ambientShouldPlay, isTrue);
      expect(audio.gardenAmbientPlayCalls, greaterThan(before),
          reason: '第 ${i + 1} 次返回花园必须复播');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('D1 · 树页在台时销毁 ProviderScope：catch 兜底不把异常逃逸成崩溃',
      (WidgetTester tester) async {
    // 注意：本用例不走 _Host.boot 的 addTearDown 容器，手动管理以精确控制销毁时序。
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
    final _Host h = _Host(tester, container);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WishTreePage()),
    ));
    await h.frames(n: 8);
    expect(h.gate, isTrue);

    // 模拟 App 退出：先销毁整棵 widget 树（触发 dispose 的 scheduleMicrotask），
    // 再销毁容器（微任务此时可能落在已 disposed 的 notifier 上 ⇒ 必须被 catch 兜住）。
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    // 再 pump 两帧：让挂起的 scheduleMicrotask 落地（写入已销毁容器 → 被 catch）。
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: '容器销毁期间 dispose 的 try/catch 必须兜住，不得逃逸成崩溃');
    await database.close();
  });

  test('D2 · 新容器闸门恒 false（StateProvider 不持久化 ⇒ 不可能永久卡 true 影响下次启动）',
      () {
    final ProviderContainer fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(wishTreeSceneActiveProvider), isFalse,
        reason: '闸门是纯内存 StateProvider，默认值 false；下次启动 = 新容器 = 干净 false');
  });
}
