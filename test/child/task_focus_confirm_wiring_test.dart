/// F177（寇豆码 2026-10-30）：孩子端·成长页任务卡**误触保护** —— 组件层接线守卫。
///
/// 现象（iPad 真机）：成长页联动项任务卡的「去专注」方盒，**一点就直接进专注**，
/// 没有二次确认，孩子易误碰。花园页一键操作有确认卡，成长卡原本没有。
///
/// 修复口径（C105）：把「直达专注」改成「先弹 [showChildConfirmCard] → 确认后才
/// `context.go('/focus?...')`；取消（`ok != true`）分毫不扣，绝不进专注」。本文件
/// 是从**真实入口**（任务卡 `_focusBox` 的 onTap）走进去的接线测试，不是把
/// [showChildConfirmCard] 单独挂出来——要验证的是「卡 → 进专注」这条**链路**。
///
/// 三条断言（team-lead 硬性要求）：
///  ① 点「去专注」方盒 → 确认卡**出现**（标题 / 确认 / 取消三件套都在）；
///  ② 「确认」路径 → 真的 `context.go` 进专注，且 query 参数（minutes / dnd / task）正确；
///  ③ 「取消」路径 → **不**进专注，且成长页**流不断**（卡片仍在、路由没切走）。
///
/// ⚠️ 期望值**独立于实现**：断言只认「真实入口 + 真值文案 + 真实路由跳转」，
/// 不引用 `_focusBox` 内部任何常量（否则实现被改两边一起变 → 断言恒绿）。
library task_focus_confirm_wiring_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';

/// 联动专注任务（复刻 `task_verified_notice_test.dart` 的最小任务工厂，但 requiresFocus=true）。
Task _focusTask(String id, {int minFocusMin = 20}) => Task(
      id: id,
      name: '朗读英语',
      subject: TaskSubject.general,
      requiresFocus: true,
      minFocusMin: minFocusMin,
      sunlightReward: 12,
      isCustom: true,
    );

/// 挂载最小可用的 Riverpod 容器（与 `task_verified_notice_test._pumpShell` 同款 3 覆盖）。
Future<ProviderContainer> _container(db.AppDatabase database) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  return ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
    ],
  );
}

/// 把成长页挂到**真实 GoRouter** 下（修复用的 `context.go('/focus?...')` 必须能找到
/// 路由器 —— 没有路由器的 `context.go` 会直接抛「GoRouter not found」）。
///
/// `/focus` 路由用**桩 widget**（捕获实际跳转 URI 即返回哨兵文案），只验证「跳转发生 +
/// 参数正确」，不拉起真实专注页（真实专注页依赖计时引擎，本接线测试不负责）。
String? _lastFocusUri;

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          // ⚠️ 必须包 Scaffold：成长页的「去专注」方盒是 InkWell，调试模式
          // `debugCheckHasMaterial` 要求有 Material 祖先——线上它在 ChildShellPage
          // 的 Scaffold 里，本测试直挂页面也得补一个，否则 InkWell 构建直接抛断言、
          // 「去专注」文字整棵子树不渲染。
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: ChildTaskPage()),
        ),
        GoRoute(
          path: '/focus',
          builder: (BuildContext context, GoRouterState state) {
            _lastFocusUri = state.uri.toString();
            return const Scaffold(body: Center(child: Text('FOCUS_PAGE_REACHED')));
          },
        ),
      ],
    );

/// 种子一个联动专注任务并挂载成长页（等 board 异步加载完）。
Future<void> _pumpTaskPage(
  WidgetTester tester, {
  required ProviderContainer container,
  required db.AppDatabase database,
  required Task task,
}) async {
  final TaskLocalRepository repo = TaskLocalRepository(database, account: container.read(accountServiceProvider));
  await repo.saveTask(task);

  _lastFocusUri = null;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: _router(),
      ),
    ),
  );
  // board() 是异步（读库），等它落定再断言。
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 点「去专注」方盒 → 确认卡出现（标题 + 确认 + 取消三件套）',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(tester, container: container, database: database, task: _focusTask('t_focus'));

    // 前置：成长页确实渲染出了「去专注」方盒（真实入口存在）。
    expect(find.text('去专注'), findsWidgets, reason: '联动项任务卡必须渲染「去专注」方盒');

    // 点击真实入口。
    await tester.tap(find.text('去专注'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ① 确认卡出现：标题 + 确认按钮（开始专注）+ 取消按钮（取消）都在。
    expect(find.text('进入专注？'), findsOneWidget, reason: '点「去专注」必须先弹确认卡（F177 误触保护）');
    expect(find.text('开始专注'), findsOneWidget, reason: '确认卡必须有「开始专注」确认键');
    expect(find.text('取消'), findsOneWidget, reason: '确认卡必须有「取消」键（C105 显式 cancelLabel）');
    // 卡里提到了本次专注分钟数（20 分钟）—— 确认信息不是空壳。
    expect(find.textContaining('20'), findsWidgets, reason: '确认卡须呈现本次专注时长');

    // 关掉卡，避免影响后续（点取消即可，不进专注）。
    await tester.tap(find.text('取消'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('进入专注？'), findsNothing, reason: '取消后确认卡应收起');
  });

  testWidgets('② 「确认」路径 → 真的进专注，且 query 参数正确（minutes / dnd / task）',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(tester, container: container, database: database, task: _focusTask('t_focus', minFocusMin: 20));

    await tester.tap(find.text('去专注'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('进入专注？'), findsOneWidget, reason: '确认卡已出现');

    // 确认 = 开始专注 → 应触发 context.go('/focus?minutes=20&dnd=1&task=t_focus')。
    await tester.tap(find.text('开始专注'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ② 确认后真的进了专注页（桩路由的哨兵文案出现）。
    expect(find.text('FOCUS_PAGE_REACHED'), findsOneWidget, reason: '确认后必须跳转进入专注页');
    // 跳转 URI 的 query 参数与实现约定一致（独立于实现常量）。
    expect(_lastFocusUri, isNotNull, reason: '必须真的发起过 /focus 跳转');
    expect(_lastFocusUri, contains('minutes=20'), reason: '专注分钟数必须等于任务 minFocusMin');
    expect(_lastFocusUri, contains('dnd=1'), reason: '联动专注默认开勿扰');
    expect(_lastFocusUri, contains('task=t_focus'), reason: '必须带上任务 id');
  });

  testWidgets('③ 「取消」路径 → 不进专注，且成长页流不断（卡片仍在、路由没切走）',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(tester, container: container, database: database, task: _focusTask('t_focus'));

    await tester.tap(find.text('去专注'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('进入专注？'), findsOneWidget, reason: '确认卡已出现');

    // 取消 = 分毫不扣，绝不进专注。
    await tester.tap(find.text('取消'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ③ 没进专注：桩路由哨兵**绝不能**出现。
    expect(find.text('FOCUS_PAGE_REACHED'), findsNothing, reason: '取消后绝不得跳转进专注');
    expect(_lastFocusUri, isNull, reason: '取消后不得发起任何 /focus 跳转');
    // 成长页流不断：任务卡「去专注」方盒仍在树上（页面没被卸载 / 没被路由替换）。
    expect(find.text('去专注'), findsWidgets, reason: '取消后成长页仍在，方盒可再次点击');
  });
}
