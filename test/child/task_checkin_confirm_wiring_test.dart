/// 「我做到了」**误触保护**接线测试（玄参 2026-11-06：与联动项 F177 同款口径）。
///
/// 现象：成长页非联动项任务卡的「我做到了」方盒，一点就直接落**待家长确认**
/// （`TaskCheckInService.checkIn`），没有二次确认，孩子易误碰、误提交。
///
/// 修复口径：把「直达打卡」改成「先弹 [showChildConfirmCard] → 确认后才调
/// [_checkIn]；取消（`ok != true`）不落任何记录、流不断」。文案为温柔提示
/// 「确认做完了就提交给爸爸妈妈吧」（`task_checkin_confirm_*` 三键）。
///
/// 三条断言（与 `task_focus_confirm_wiring_test.dart` 同一骨架）：
///  ① 点「我做到了」方盒 → 确认卡**出现**（标题「提交打卡？」/ 提交 / 取消三件套）；
///  ② 「提交」路径 → 真的执行打卡（任务项翻成「等家长确认」只读态 + 反馈条出现）；
///  ③ 「取消」路径 → **不**落任何记录（页面仍是「我做到了」、无 pending 反馈）。
///
/// ⚠️ 期望值**独立于实现**：断言只认「真实入口 + 真值文案 + 页面真实状态翻转」，
/// 不引用 `_confirmCheckIn` 内部任何常量。
library task_checkin_confirm_wiring_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// 非联动任务（`requiresFocus == false` → 渲染「我做到了」方盒）。
Task _plainTask(String id) => Task(
      id: id,
      name: '整理书桌',
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 0,
      sunlightReward: 8,
      isCustom: true,
    );

/// 挂载最小可用的 Riverpod 容器（与 `task_focus_confirm_wiring_test` 同款 3 覆盖）。
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

/// 种子一个非联动任务并挂载成长页（等 board 异步加载完）。
Future<void> _pumpTaskPage(
  WidgetTester tester, {
  required ProviderContainer container,
  required db.AppDatabase database,
  required Task task,
}) async {
  final TaskLocalRepository repo = TaskLocalRepository(
    database,
    account: container.read(accountServiceProvider),
  );
  await repo.saveTask(task);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: ChildTaskPage()),
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

  testWidgets('① 点「我做到了」方盒 → 确认卡出现（标题 + 提交 + 取消三件套）',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(
      tester,
      container: container,
      database: database,
      task: _plainTask('t_plain'),
    );

    // 前置：成长页确实渲染出了「我做到了」方盒（真实入口存在；两行文案「我做/到了」）。
    expect(find.text('我做'), findsWidgets,
        reason: '非联动项任务卡必须渲染「我做到了」方盒');

    // 点击真实入口。
    await tester.tap(find.text('我做'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ① 确认卡出现：标题 + 确认按钮（提交）+ 取消按钮都在。
    expect(find.text('提交打卡？'), findsOneWidget,
        reason: '点「我做到了」必须先弹确认卡（误触保护）');
    expect(find.text('提交'), findsOneWidget, reason: '确认卡必须有「提交」确认键');
    expect(find.text('取消'), findsOneWidget,
        reason: '确认卡必须有「取消」键（C105 显式 cancelLabel）');
    // 卡里提到「爸爸妈妈」—— 温柔提示不是空壳。
    expect(find.textContaining('爸爸妈妈'), findsWidgets,
        reason: '确认卡须呈现「提交给爸爸妈妈」的温柔提示');

    // 关掉卡（点取消即可，不落记录）。
    await tester.tap(find.text('取消'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('提交打卡？'), findsNothing, reason: '取消后确认卡应收起');
  });

  testWidgets('② 「提交」路径 → 真的打卡落待家长确认（页面状态翻转）',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(
      tester,
      container: container,
      database: database,
      task: _plainTask('t_plain'),
    );

    await tester.tap(find.text('我做'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('提交打卡？'), findsOneWidget, reason: '确认卡已出现');

    // 确认 = 提交 → TaskCheckInService.checkIn 落 pending。
    await tester.tap(find.text('提交'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 单任务打卡即 allTasksDone → 完美日庆祝卡会弹出并 **await 等待交互**，
    // 挡在 _feedback 内部（不点掉它，后面的 _reload / 状态刷新不会执行）。
    if (find.textContaining('今日成长项全部完成').evaluate().isNotEmpty) {
      await tester.tap(find.text('太棒啦'));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // ② 打卡真的执行：任务项翻成「等家长确认」只读态。
    expect(find.text('等家长确认'), findsWidgets,
        reason: '确认后必须真正落待家长确认（页面状态翻转）');
    // 反馈条告知孩子「等家长确认就会发阳光」（pending 不当期发阳光）。
    expect(find.textContaining('已经告诉爸爸妈妈'), findsWidgets,
        reason: '打卡后须出现 pending 反馈');
  });

  testWidgets('③ 「取消」路径 → 不落任何记录，成长页流不断',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _container(database);

    await _pumpTaskPage(
      tester,
      container: container,
      database: database,
      task: _plainTask('t_plain'),
    );

    await tester.tap(find.text('我做'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('提交打卡？'), findsOneWidget, reason: '确认卡已出现');

    // 取消 = 分毫不落。
    await tester.tap(find.text('取消'));
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ③ 没打卡：任务项仍是「我做到了」可点态，无 pending 反馈。
    expect(find.text('我做'), findsWidgets,
        reason: '取消后任务项仍是「我做到了」，可再次点击');
    expect(find.text('等家长确认'), findsNothing,
        reason: '取消后绝不得落待家长确认');
    expect(find.textContaining('已经告诉爸爸妈妈'), findsNothing,
        reason: '取消后不得出现打卡反馈');
  });
}
