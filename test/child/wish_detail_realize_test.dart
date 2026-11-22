/// 玄参 iPad13 真机拍板 + R6-P0-02 成长任务闭环：
/// 详情「实现了」唯一入口 + 二次确认 + 无目标放行 + 有任务改「我做到了」。
///
/// 覆盖：
///  ① 无任务愿望：树上详情有且只有一枚「实现了」，确认才落库并关详情；
///  ② 有手动任务：愿望主按钮消失，任务卡给「我做到了」→ checkIn 落 pending，
///     确认卡改「提交后等爸爸妈妈确认…」，确认后不关详情；
///  ③ 提交后任务卡显示「等家长确认」只读胶囊，达成入口消失；
///  ④ 纯专注任务愿望不再给「直接进池」按钮；多任务各自可提交。
library wish_detail_realize_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';

final AppLocalizations _t = AppLocalizationsZh();
final DateTime _now = DateTime(2026, 11, 10, 9);

Wish _wish({
  String id = 'w1',
  int targetValue = 0,
  WishStatus status = WishStatus.pending,
  DateTime? releasedAt,
}) =>
    Wish(
      id: id,
      childId: 'c1',
      text: '🌟小汽车 认识各种车辆',
      status: status,
      createdAt: DateTime(2026, 11, 1),
      treeSlot: 0,
      targetValue: targetValue,
      releasedAt: releasedAt,
    );

Task _task({
  required String id,
  required bool focus,
}) =>
    Task(
      id: id,
      name: '认识各种车辆',
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: 20,
      sunlightReward: 12,
      isCustom: true,
      wishId: 'w1',
    );

CheckIn _checkIn({
  required String taskId,
  CheckInStatus status = CheckInStatus.pending,
}) =>
    CheckIn(
      id: 'c_$taskId',
      taskId: taskId,
      date: _now,
      completedAt: _now,
      isPerfectDay: false,
      status: status,
    );

Widget _host({
  required Wish wish,
  required List<Task> tasks,
  List<CheckIn> checkIns = const <CheckIn>[],
  required Future<void> Function() onSelfFulfill,
  required Future<void> Function(Task task) onDidIt,
  required VoidCallback onRealized,
  Future<void> Function()? onPutInPool,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: <Override>[
            wishTasksFamilyProvider.overrideWith(
              (Ref ref, String wishId) async => tasks,
            ),
            wishTaskCheckInsFamilyProvider.overrideWith(
              (Ref ref, String wishId) async => checkIns,
            ),
          ],
          child: WishDetailBody(
            wish: wish,
            t: _t,
            now: _now,
            onCollect: () {},
            onChange: () {},
            onSelfFulfill: onSelfFulfill,
            onDidIt: onDidIt,
            onRealized: onRealized,
            onPutInPool: onPutInPool,
          ),
        ),
      ),
    );

const Key _mainButton = Key('wish_detail_self_fulfill');
const Key _wayButton = Key('wish_task_did_it');
const Key _poolButton = Key('wish_detail_put_in_pool');
const Key _changeButton = Key('wish_detail_change');
const Key _collectButton = Key('wish_detail_collect');

/// 统计当前画面上的达成入口数（愿望主按钮 + 任务卡方盒）。
int _realizeButtonCount(WidgetTester tester) =>
    tester.widgetList<Widget>(find.byKey(_mainButton)).length +
    tester.widgetList<Widget>(find.byKey(_wayButton)).length;

Future<void> _confirm(WidgetTester tester, {required bool yes, required String label}) async {
  final Finder surface = find.byKey(ChildConfirmCard.surfaceKey);
  expect(surface, findsOneWidget, reason: '必须弹二次确认卡');
  final Finder button = find.descendant(
    of: surface,
    matching: find.text(yes ? label : _t.shared_cancel),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('唯一入口判据（纯函数）', () {
    test('树上无办法 ⇒ 愿望主按钮；有手动办法 ⇒ 办法卡；收藏箱/终态 ⇒ 无', () {
      final Task manual = _task(id: 'm', focus: false);
      expect(
        wishRealizeEntryOf(onTree: true, tasks: const <Task>[]),
        WishRealizeEntry.wishCard,
      );
      expect(
        wishRealizeEntryOf(onTree: true, tasks: <Task>[manual]),
        WishRealizeEntry.firstManualTask,
      );
      expect(
        wishRealizeEntryOf(onTree: false, tasks: <Task>[manual]),
        WishRealizeEntry.none,
      );
    });

    test('R6-P0-02⑤ 有任务（哪怕全是专注任务）⇒ 无「直接进池」按钮', () {
      final Task focus = _task(id: 'f', focus: true);
      expect(
        wishRealizeEntryOf(onTree: true, tasks: <Task>[focus]),
        WishRealizeEntry.none,
        reason: '专注型愿望任务走专注结算闭环，不给 selfFulfill 主按钮',
      );
      expect(
        wishRealizeEntryOf(
          onTree: true,
          tasks: <Task>[focus, _task(id: 'm', focus: false)],
        ),
        WishRealizeEntry.firstManualTask,
      );
    });
  });

  group('① 无任务愿望（targetValue=0）自助实现逐字节不变', () {
    testWidgets('无办法：唯一主按钮文案「实现了」；取消不落库、确认才落库并关详情',
        (WidgetTester tester) async {
      int fulfilledCalls = 0;
      int closedCalls = 0;
      int didItCalls = 0;
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: const <Task>[],
        onSelfFulfill: () async {
          fulfilledCalls++;
        },
        onDidIt: (Task _) async {
          didItCalls++;
        },
        onRealized: () => closedCalls++,
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_mainButton), findsOneWidget);
      expect(find.text(_t.wishDetailRealized), findsOneWidget);

      await tester.tap(find.byKey(_mainButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: false, label: _t.wishDetailRealized);
      expect(fulfilledCalls, 0, reason: '取消绝不落库');
      expect(closedCalls, 0, reason: '取消后详情也不关闭');
      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing,
          reason: '取消后不得再弹第二次确认');

      await tester.tap(find.byKey(_mainButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: true, label: _t.wishDetailRealized);
      expect(fulfilledCalls, 1, reason: '确认才落库');
      expect(closedCalls, 1, reason: '落库后关闭详情，看到愿望进愿望池');
      expect(didItCalls, 0);
    });
  });

  group('② R6-P0-02 有任务愿望：「我做到了」走打卡提交链', () {
    testWidgets('手动办法：任务卡按钮「我做到了」，取消不落库、确认只打卡不关详情',
        (WidgetTester tester) async {
      int fulfilledCalls = 0;
      int closedCalls = 0;
      final List<String> didItTaskIds = <String>[];
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        onSelfFulfill: () async {
          fulfilledCalls++;
        },
        onDidIt: (Task task) async {
          didItTaskIds.add(task.id);
        },
        onRealized: () => closedCalls++,
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_wayButton), findsOneWidget);
      expect(find.byKey(_mainButton), findsNothing,
          reason: '有任务的愿望不再给直接进池按钮');
      expect(find.text(_t.wishTaskDidIt), findsOneWidget);
      expect(find.text(_t.wishDetailRealized), findsNothing);

      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: false, label: _t.wishTaskDidIt);
      expect(didItTaskIds, isEmpty, reason: '取消不落任何记录');
      expect(closedCalls, 0);

      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: true, label: _t.wishTaskDidIt);
      expect(didItTaskIds, <String>['m1'], reason: '确认 ⇒ checkIn 提交该任务');
      expect(fulfilledCalls, 0, reason: '不再走 selfFulfill 即时进池');
      expect(closedCalls, 0, reason: '提交后仍留详情，等待家长确认');
    });

    testWidgets('确认卡正文为「提交后等爸爸妈妈确认…」，不预告愿望实现',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();

      final Finder surface = find.byKey(ChildConfirmCard.surfaceKey);
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishTaskSubmitConfirm),
        ),
        findsOneWidget,
        reason: '新文案必须来自 ARB `wishTaskSubmitConfirm`',
      );
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishRealizedCongrats),
        ),
        findsNothing,
        reason: '尚未经家长确认，不能提前祝贺愿望实现',
      );
      await _confirm(tester, yes: false, label: _t.wishTaskDidIt);
    });

    testWidgets('已提交待确认 ⇒ 只读胶囊「等家长确认」，达成入口消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        checkIns: <CheckIn>[_checkIn(taskId: 'm1')],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(find.text('⏳ ${_t.wishTaskPending}'), findsOneWidget);
      expect(find.byKey(_wayButton), findsNothing,
          reason: 'pending 期间不得再次提交');
      expect(_realizeButtonCount(tester), 0);
    });

    testWidgets('已核销 ⇒ 只读胶囊「已完成」', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        checkIns: <CheckIn>[
          _checkIn(taskId: 'm1', status: CheckInStatus.verified),
        ],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(find.text('✓ ${_t.wishTaskDone}'), findsOneWidget);
      expect(find.byKey(_wayButton), findsNothing);
    });
  });

  group('R7-P0-01①②⑥ 显式进池按钮两态互斥 + 二次确认', () {
    testWidgets('手动任务全 verified ⇒ 单「放进愿望池」按钮，两次级按钮与任务提交入口同时消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        checkIns: <CheckIn>[
          _checkIn(taskId: 'm1', status: CheckInStatus.verified),
        ],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
        onPutInPool: () async {},
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(_poolButton), findsOneWidget,
          reason: '全完成后唯一进池按钮');
      expect(find.text(_t.wishDetailPutInPool), findsOneWidget);
      expect(find.byKey(_changeButton), findsNothing,
          reason: '「换个愿望」隐藏');
      expect(find.byKey(_collectButton), findsNothing,
          reason: '「放进收藏箱」隐藏');
      expect(find.byKey(_mainButton), findsNothing,
          reason: '「实现了」主按钮隐藏');
      expect(find.byKey(_wayButton), findsNothing,
          reason: '任务提交入口隐藏');
    });

    testWidgets('有未完成任务 ⇒ 无进池按钮，维持两次级按钮 + 任务提交入口',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        checkIns: const <CheckIn>[],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
        onPutInPool: () async {},
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(_poolButton), findsNothing);
      expect(find.byKey(_changeButton), findsOneWidget);
      expect(find.byKey(_collectButton), findsOneWidget);
      expect(find.byKey(_wayButton), findsOneWidget);
    });

    testWidgets('Q2 纯专注型（无手动任务）⇒ 不显进池按钮',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'f1', focus: true)],
        checkIns: <CheckIn>[
          _checkIn(taskId: 'f1', status: CheckInStatus.verified),
        ],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
        onPutInPool: () async {},
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(_poolButton), findsNothing, reason: 'Q2 纯专注型不显');
      expect(find.byKey(_changeButton), findsOneWidget);
    });

    testWidgets('Q3 无任务愿望 ⇒ 不显进池按钮，仍显「实现了」自助',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: const <Task>[],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
        onPutInPool: () async {},
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(_poolButton), findsNothing, reason: 'Q3 无任务愿望不显');
      expect(find.byKey(_mainButton), findsOneWidget,
          reason: '无任务愿望仍显「实现了」自助');
    });

    testWidgets('进池按钮：取消不落库不关详情，确认才落库并关详情；标题复用 wishRealizedCongrats',
        (WidgetTester tester) async {
      int poolCalls = 0;
      int closedCalls = 0;
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        checkIns: <CheckIn>[
          _checkIn(taskId: 'm1', status: CheckInStatus.verified),
        ],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () => closedCalls++,
        onPutInPool: () async {
          poolCalls++;
        },
      ));
      await tester.pumpAndSettle();

      // 取消
      await tester.tap(find.byKey(_poolButton));
      await tester.pumpAndSettle();
      final Finder surface = find.byKey(ChildConfirmCard.surfaceKey);
      expect(surface, findsOneWidget, reason: '必须弹二次确认');
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishRealizedCongrats),
        ),
        findsOneWidget,
        reason: '确认标题复用 wishRealizedCongrats（无新增 i18n key）',
      );
      await _confirm(tester, yes: false, label: _t.wishDetailPutInPool);
      expect(poolCalls, 0, reason: '取消不落库');
      expect(closedCalls, 0, reason: '取消不关详情');

      // 确认
      await tester.tap(find.byKey(_poolButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: true, label: _t.wishDetailPutInPool);
      expect(poolCalls, 1, reason: '确认才落库');
      expect(closedCalls, 1, reason: '落库后关详情');
    });
  });

  group('③ 树上愿望的按钮归属', () {
    testWidgets('两条手动办法：每条都有提交入口（门控要求全部任务 verified）',
        (WidgetTester tester) async {
      final List<String> didItTaskIds = <String>[];
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 30),
        tasks: <Task>[
          _task(id: 'm1', focus: false),
          _task(id: 'm2', focus: false),
        ],
        onSelfFulfill: () async {},
        onDidIt: (Task task) async {
          didItTaskIds.add(task.id);
        },
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(_wayButton), findsNWidgets(2));
      expect(find.byKey(_mainButton), findsNothing);
      expect(find.text(_t.wishTaskDidIt), findsNWidgets(2));
    });

    testWidgets('只有专注型办法：没有任何达成入口（专注结算自行闭环）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 30),
        tasks: <Task>[_task(id: 'f', focus: true)],
        onSelfFulfill: () async {},
        onDidIt: (Task _) async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 0);
      expect(find.byKey(_mainButton), findsNothing);
      expect(find.byKey(_wayButton), findsNothing);
      expect(find.byKey(const Key('wish_task_go_focus')), findsOneWidget);
    });

    testWidgets('收藏箱 / 终态愿望：没有达成入口',
        (WidgetTester tester) async {
      for (final Wish wish in <Wish>[
        _wish(releasedAt: _now),
        _wish(status: WishStatus.fulfilled),
      ]) {
        await tester.pumpWidget(_host(
          wish: wish,
          tasks: <Task>[_task(id: 'm', focus: false)],
          onSelfFulfill: () async {},
          onDidIt: (Task _) async {},
          onRealized: () {},
        ));
        await tester.pumpAndSettle();
        expect(_realizeButtonCount(tester), 0);
      }
    });
  });
}
