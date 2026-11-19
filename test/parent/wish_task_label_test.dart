/// 家长端「愿望任务」形态（v0.3.0 / R3-P0-09、R3-P1-05、R3-P0-10）。
///
/// ## 三条硬断言
///  ① `wishId != null` 的任务在家长端列表显示「愿望任务 · {愿望标题}」标签
///     （**挂真实 `ParentTaskConfigPage`** 断言，不接受「塞一段 ARB 文本进裸 Text」）；
///  ② **写 1 条愿望任务后，「今日必做 x/y」计数不变**（`allTasks()` 默认
///     `includeWishTasks=false` 不动 —— 这是玄参上一版最容易再反馈的点）；
///     且愿望任务**不占**免费 5 条成长项配额（展示口径 ≠ 配额口径）；
///  ③ 任务编辑器「关联愿望」下拉：默认「不关联」= null，选中写 `wish_id`，
///     且**不影响**既有必填校验。
library wish_task_label_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';

/// 普通成长任务（`wish_id == null`）。
Task _ordinary(String id, String name) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 0,
      sunlightReward: 5,
      repeatRule: 'none',
      isCustom: true,
    );

/// 现实类「小办法」= 关联愿望的任务（`wish_id != null`）。
Task _realityWay(String id, String name, String wishId) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 0,
      sunlightReward: 5,
      repeatRule: 'none',
      isCustom: true,
      wishId: wishId,
    );

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

Future<ProviderContainer> _boot() async {
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
  return container;
}

void main() {
  final AppLocalizations t = AppLocalizationsZh();

  group('R3-P0-09② 今日必做计数不含愿望任务（成长链路零影响）', () {
    test('写 1 条 wishId != null 的任务后，今日必做计数不变', () async {
      final ProviderContainer c = await _boot();

      // 「今日必做」读侧 = `TaskRepository.tasks()`（内部走
      // `allTasks(includeWishTasks: false)`）—— 正是成长链路的真实口径。
      Future<int> todayCount() async {
        final List<Task> list = await c.read(taskRepositoryProvider).tasks();
        return list.length;
      }

      final int before = await todayCount();

      // 先造一个树上愿望（真实落库）。
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime(2026, 11, 19, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );

      // 再写一条**关联该愿望**的任务。
      await c.read(taskRepositoryProvider).saveTask(Task(
            id: 'wish-task-1',
            name: '帮妈妈洗碗',
            subject: TaskSubject.general,
            requiresFocus: false,
            minFocusMin: 0,
            sunlightReward: 5,
            repeatRule: 'none',
            isCustom: true,
            wishId: wish.id,
          ));

      final int after = await todayCount();
      expect(after, before,
          reason: '`allTasks()` 默认 includeWishTasks=false ⇒ 愿望任务不计入今日必做');
      // 但「含愿望任务」的读法能看到它（证明数据真的写进去了，不是没落库）。
      // 「含愿望任务」的读法挂在 [WishTaskReadBridge] 上（与 TODO 无关：
      // 家长端待核销需要看全量，而今日板按 includeWishTasks=false 隔离）。
      final WishTaskReadBridge bridge =
          c.read(taskRepositoryProvider) as WishTaskReadBridge;
      final List<Task> withWish = await bridge.allTasksIncludingWish();
      expect(withWish.where((Task x) => x.wishId == wish.id).length, 1,
          reason: '愿望任务必须真实落库（否则上面的「计数不变」是假绿）');
    });
  });

  group('R3-P0-09③ 家长端任务列表「愿望任务 · {标题}」标签', () {
    // 🔴 教训（WISH-V03-BUG-01）：本组原先只把 ARB 文案塞进裸 `Text` 就断言「标签
    // 存在」——**从来没有挂载真实 `ParentTaskConfigPage`**，于是源码里
    // `if (t.wishId != null)` 那段徽标是死代码也照样全绿（假绿）。现在一律挂真页面。
    Future<void> pumpPage(WidgetTester tester, ProviderContainer c) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ParentTaskConfigPage()),
      ));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('真实页面：愿望任务带标签、普通任务不带、列表条目数 = 全量',
        (WidgetTester tester) async {
      final ProviderContainer c = await _boot();
      await c.read(taskRepositoryProvider).saveTask(_ordinary('t1', '练字 15 分钟'));
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime(2026, 11, 19, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await c
          .read(taskRepositoryProvider)
          .saveTask(_realityWay('w1', '帮妈妈洗碗', wish.id));

      await pumpPage(tester, c);

      // 前置自证：页面起来了、普通任务在列（否则「找不到标签」可能只是没渲染）。
      expect(find.byType(ParentTaskConfigPage), findsOneWidget);
      expect(find.text('练字 15 分钟'), findsOneWidget,
          reason: '前置：普通成长任务必须已渲染');
      // ① 核心断言：愿望任务标签真的出现在列表里（WISH-V03-BUG-01 的回归点）。
      expect(find.byKey(const Key('parent_task_wish_badge_w1')), findsOneWidget,
          reason: 'wishId != null ⇒ 必须渲染「愿望任务 · {标题}」徽标；'
              '渲染不出来说明列表读的是 includeWishTasks=false 的口径');
      expect(find.text(t.wishTaskBadgeOfWish('想要一只小乌龟')), findsOneWidget,
          reason: '标签文案 = 「愿望任务 · {愿望标题}」');
      // ② 普通任务不得带标签（否则标签无信息量）。
      expect(find.byKey(const Key('parent_task_wish_badge_t1')), findsNothing,
          reason: '普通成长任务不得显示愿望任务标签');
      // ③ 列表条目数是「展示口径」：1 普通 + 1 愿望 = 2 项。
      expect(find.text(t.parent_today_count(2)), findsOneWidget,
          reason: '列表计数必须数"列表里有几项"（含愿望任务），不是配额');
      expect(tester.takeException(), isNull);
    });

    testWidgets('配额与展示分离：愿望任务撑大列表但**不占**免费 5 条配额',
        (WidgetTester tester) async {
      final ProviderContainer c = await _boot();
      // 4 条普通 + 2 条愿望 = 列表 6 项。免费上限 5 条只数普通任务 ⇒ 仍可新增。
      // 🔴 若有人图省事把配额也换成展示口径（6 > 5），本用例立刻红。
      for (int i = 0; i < 4; i++) {
        await c.read(taskRepositoryProvider).saveTask(_ordinary('t$i', '普通 $i'));
      }
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一次露营',
                category: WishCategory.other,
                now: DateTime(2026, 11, 19, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await c
          .read(taskRepositoryProvider)
          .saveTask(_realityWay('w1', '一起搭帐篷', wish.id));
      await c
          .read(taskRepositoryProvider)
          .saveTask(_realityWay('w2', '一起做饼干', wish.id));

      await pumpPage(tester, c);

      expect(find.text(t.parent_today_count(6)), findsOneWidget,
          reason: '展示口径：列表 6 项（4 普通 + 2 愿望）');
      expect(find.byKey(const Key('parent_task_wish_badge_w2')), findsOneWidget);

      // 点「新增成长项」：配额只数 4 条普通任务 ⇒ 允许 ⇒ 编辑器必须打开。
      await tester.tap(
        find.widgetWithText(OutlinedButton, t.parent_task_edit_title_new),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditorDialog), findsOneWidget,
          reason: '免费配额只数普通成长任务（4 < 5）⇒ 必须放行；'
              '被挡住说明愿望任务虚占了配额（R3-P0-09④）');
      expect(tester.takeException(), isNull);
    });

    test('标签文案 = 「愿望任务 · {标题}」且 zh/en 均有', () {
      expect(t.wishTaskBadgeOfWish('小乌龟'), contains('愿望任务'));
      expect(t.wishTaskBadgeOfWish('小乌龟'), contains('小乌龟'));
      expect(t.wishTaskBadgeLabel, isNotEmpty);
    });
  });

  group('R3-P1-05 成长任务编辑器「关联愿望」下拉', () {
    Future<Task?> pumpEditor(
      WidgetTester tester, {
      required List<Wish> wishes,
      Task? initial,
      String name = '新任务',
      bool selectWish = false,
    }) async {
      Task? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: ElevatedButton(
                key: const Key('open_editor'),
                onPressed: () => showDialog<bool>(
                  context: ctx,
                  builder: (BuildContext _) => TaskEditorDialog(
                    initial: initial,
                    wishes: wishes,
                    onSave: (Task x) async => saved = x,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open_editor')));
      await tester.pumpAndSettle();

      // 填名称（必填）。
      await tester.enterText(
        find.byType(TextField).first,
        name,
      );
      await tester.pump();

      if (selectWish) {
        await tester.tap(find.byKey(const Key('task_editor_wish_link')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(wishes.first.text).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(t.parent_task_edit_btn_save));
      await tester.pumpAndSettle();
      return saved;
    }

    final Wish wish = Wish(
      id: 'w-1',
      childId: 'c1',
      text: '想要一只小乌龟',
      createdAt: DateTime(2026, 11, 1),
    );

    testWidgets('无愿望时**不渲染**下拉（行为与改造前一致）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskEditorDialog(
            wishes: const <Wish>[],
            onSave: (Task _) async {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('task_editor_wish_link')), findsNothing);
    });

    testWidgets('默认「不关联」⇒ 保存写 wishId = null', (WidgetTester tester) async {
      final Task? saved = await pumpEditor(tester, wishes: <Wish>[wish]);
      expect(saved, isNotNull, reason: '必填校验必须照常通过（关联字段不影响校验）');
      expect(saved!.wishId, isNull, reason: '未选愿望 ⇒ wish_id = null');
    });

    testWidgets('选中愿望 ⇒ 保存写 wishId == wish.id', (WidgetTester tester) async {
      final Task? saved = await pumpEditor(
        tester,
        wishes: <Wish>[wish],
        selectWish: true,
      );
      expect(saved, isNotNull);
      expect(saved!.wishId, wish.id);
    });
  });
}
