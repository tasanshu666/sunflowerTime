/// 玄参 v0.3 验收反馈 5(c)：家长端关联愿望任务 → 孩子端「许愿」栏真可见。
///
/// 真链路：真 TaskEditorDialog 选愿望并保存 → 真 TaskLocalRepository 落库 →
/// 真 TaskCheckInService.board()（走 WishTaskReadBridge）→ 真 ChildTaskPage 渲染。
/// 另造一条存量 `category=other` 但 `wishId!=null` 的任务，确认旧数据也进栏。
library wish_task_child_board_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';

Future<ProviderContainer> _boot(db.AppDatabase database) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('家长选愿望保存 → 孩子端「许愿」栏显示；存量 other+wishId 也进栏',
      (WidgetTester tester) async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer container = await _boot(database);
    addTearDown(container.dispose);

    final Wish wish = Wish(
      id: 'w-1',
      childId: container.read(accountServiceProvider).childId,
      text: '想要一只小乌龟',
      createdAt: DateTime(2026, 11, 1),
    );

    // ① 真编辑器：填名字 → 选愿望 → 科目区隐藏 → 保存落真仓储。
    Task? saved;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: ElevatedButton(
                key: const Key('open_editor'),
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (BuildContext _) => TaskEditorDialog(
                    wishes: <Wish>[wish],
                    onSave: (Task task) async {
                      saved = task;
                      await container.read(taskRepositoryProvider).saveTask(task);
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open_editor')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '给乌龟喂食');
    await tester.pump();
    await tester.tap(find.byKey(const Key('task_editor_wish_link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(wish.text).last);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<TaskSubject>), findsNothing,
        reason: '关联愿望后科目必填项必须隐藏');
    await tester.tap(
        find.text(AppLocalizations.of(tester.element(find.byType(Scaffold)))
            .parent_task_edit_btn_save));
    await tester.pumpAndSettle();

    expect(saved, isNotNull, reason: '未填科目也应能保存');
    final Task persisted = saved!;
    expect(persisted.wishId, 'w-1');
    expect(persisted.category, TaskCategory.wish,
        reason: '关联愿望自动归类为许愿');

    // ② 真孩子端成长页：board 走桥接拿到愿望任务。
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: ChildTaskPage()),
      ),
    ));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('许愿'), findsOneWidget, reason: '孩子端出现「许愿」分区');
    expect(find.text(wishTaskShortTitle('给乌龟喂食')), findsOneWidget,
        reason: '愿望任务真的出现在孩子端');
    expect(find.byType(WishTaskBadge), findsWidgets,
        reason: '愿望任务带徽标');

    // ③ 存量愿望任务：category=other 但 wishId!=null，也必须进同一栏。
    await container.read(taskRepositoryProvider).saveTask(Task(
          id: 'legacy_wish',
          name: '给乌龟换水',
          subject: TaskSubject.general,
          category: TaskCategory.other,
          requiresFocus: false,
          minFocusMin: 0,
          sunlightReward: 0,
          repeatRule: 'none',
          isCustom: true,
          wishId: wish.id,
        ));
    // ChildTaskPage 的 board 在 initState 读一次，重新挂载模拟切 tab 回来刷新。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: ChildTaskPage(key: Key('child_task_reload'))),
      ),
    ));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(wishTaskShortTitle('给乌龟换水')), findsOneWidget,
        reason: '存量 category=other 的愿望任务也要进栏');
  });
}
