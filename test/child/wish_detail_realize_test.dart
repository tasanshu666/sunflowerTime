/// 玄参 iPad13 真机拍板：详情「实现了」唯一入口 + 二次确认 + 无目标放行。
///
/// 覆盖三条可验证行为：
///  ① 树上愿望（含 targetValue=0）详情有且只有一枚「实现了」；
///  ② 点击先弹确认，取消不落库、确认才落库并关闭详情；
///  ③ 有手动办法时用办法卡方盒，否则用愿望主按钮，二者永不并存。
library wish_detail_realize_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget _host({
  required Wish wish,
  required List<Task> tasks,
  required Future<void> Function() onSelfFulfill,
  required VoidCallback onRealized,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: <Override>[
            wishTasksFamilyProvider.overrideWith(
              (Ref ref, String wishId) async => tasks,
            ),
          ],
          child: WishDetailBody(
            wish: wish,
            t: _t,
            now: _now,
            onCollect: () {},
            onChange: () {},
            onSelfFulfill: onSelfFulfill,
            onRealized: onRealized,
          ),
        ),
      ),
    );

const Key _mainButton = Key('wish_detail_self_fulfill');
const Key _wayButton = Key('wish_task_did_it');

/// 统计当前画面上的「实现了」达成入口数（愿望主按钮 + 办法卡方盒）。
int _realizeButtonCount(WidgetTester tester) =>
    tester.widgetList<Widget>(find.byKey(_mainButton)).length +
    tester.widgetList<Widget>(find.byKey(_wayButton)).length;

Future<void> _confirm(WidgetTester tester, {required bool yes}) async {
  final Finder surface = find.byKey(ChildConfirmCard.surfaceKey);
  expect(surface, findsOneWidget, reason: '必须弹二次确认卡');
  final Finder button = find.descendant(
    of: surface,
    matching: find.text(yes ? _t.wishDetailRealized : _t.shared_cancel),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('唯一入口判据（纯函数）', () {
    test('树上无办法 ⇒ 愿望主按钮；有手动办法 ⇒ 办法卡；收藏箱/终态 ⇒ 无', () {
      final Task manual = _task(id: 'm', focus: false);
      final Task focus = _task(id: 'f', focus: true);
      expect(
        wishRealizeEntryOf(onTree: true, tasks: const <Task>[]),
        WishRealizeEntry.wishCard,
      );
      expect(
        wishRealizeEntryOf(onTree: true, tasks: <Task>[focus]),
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
  });

  group('① 无目标愿望（targetValue=0）', () {
    testWidgets('无办法：唯一主按钮文案「实现了」；取消不落库、确认才落库并关详情',
        (WidgetTester tester) async {
      int fulfilledCalls = 0;
      int closedCalls = 0;
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: const <Task>[],
        onSelfFulfill: () async {
          fulfilledCalls++;
        },
        onRealized: () => closedCalls++,
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_mainButton), findsOneWidget);
      expect(find.text(_t.wishDetailRealized), findsOneWidget);

      await tester.tap(find.byKey(_mainButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: false);
      expect(fulfilledCalls, 0, reason: '取消绝不落库');
      expect(closedCalls, 0, reason: '取消后详情也不关闭');
      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing,
          reason: '取消后不得再弹第二次确认');

      await tester.tap(find.byKey(_mainButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: true);
      expect(fulfilledCalls, 1, reason: '确认才落库');
      expect(closedCalls, 1, reason: '落库后关闭详情，看到愿望进愿望池');
    });

    testWidgets('有手动办法：办法卡方盒是唯一入口，主按钮消失',
        (WidgetTester tester) async {
      int fulfilledCalls = 0;
      int closedCalls = 0;
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 0),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        onSelfFulfill: () async {
          fulfilledCalls++;
        },
        onRealized: () => closedCalls++,
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_wayButton), findsOneWidget);
      expect(find.byKey(_mainButton), findsNothing);
      expect(find.text(_t.wishDetailRealized), findsOneWidget);

      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: false);
      expect(fulfilledCalls, 0, reason: '取消绝不落库');
      expect(closedCalls, 0);

      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();
      await _confirm(tester, yes: true);
      expect(fulfilledCalls, 1, reason: '确认才落库');
      expect(closedCalls, 1);
    });
  });

  group('② 二次确认单句文案（玄参 2026-11-20 iPad13 拍板）', () {
    /// 在真实弹出的 ChildConfirmCard 里核对：只有一句祝贺，旧问句两处皆无。
    Future<void> assertSingleLineConfirm(WidgetTester tester) async {
      final Finder surface = find.byKey(ChildConfirmCard.surfaceKey);
      expect(surface, findsOneWidget, reason: '必须弹二次确认卡');
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishRealizedCongrats),
        ),
        findsOneWidget,
        reason: '确认卡只应有一句「${_t.wishRealizedCongrats}」',
      );
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishSelfFulfillConfirm),
        ),
        findsNothing,
        reason: '重复的小字正文必须消失',
      );
      expect(
        find.descendant(
          of: surface,
          matching: find.text(_t.wishTreeSelfFulfillConfirm),
        ),
        findsNothing,
      );
      expect(find.text('确定是你自己做到的吗？'), findsNothing);

      final int congratsTextCount = tester
          .widgetList<Text>(
            find.descendant(of: surface, matching: find.byType(Text)),
          )
          .where((Text w) => w.data == _t.wishRealizedCongrats)
          .length;
      expect(congratsTextCount, 1, reason: '同一句话不许既做标题又做正文出现两次');
    }

    testWidgets('愿望主按钮：确认卡只有一句祝贺，旧两行问句消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(),
        tasks: const <Task>[],
        onSelfFulfill: () async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_mainButton));
      await tester.pumpAndSettle();
      await assertSingleLineConfirm(tester);

      await _confirm(tester, yes: false);
      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing);
    });

    testWidgets('办法卡方盒：确认卡同样只有一句祝贺，旧两行问句消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(),
        tasks: <Task>[_task(id: 'm1', focus: false)],
        onSelfFulfill: () async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_wayButton));
      await tester.pumpAndSettle();
      await assertSingleLineConfirm(tester);

      await _confirm(tester, yes: false);
      expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing);
    });
  });

  group('③ 树上愿望有且只有一枚达成按钮', () {
    testWidgets('两条手动办法：只有第一条渲染方盒', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 30),
        tasks: <Task>[
          _task(id: 'm1', focus: false),
          _task(id: 'm2', focus: false),
        ],
        onSelfFulfill: () async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_wayButton), findsOneWidget);
      expect(find.byKey(_mainButton), findsNothing);
      expect(find.text(_t.wishDetailRealized), findsOneWidget);
    });

    testWidgets('只有专注型办法：主按钮唯一，办法卡不给达成入口',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        wish: _wish(targetValue: 30),
        tasks: <Task>[_task(id: 'f', focus: true)],
        onSelfFulfill: () async {},
        onRealized: () {},
      ));
      await tester.pumpAndSettle();

      expect(_realizeButtonCount(tester), 1);
      expect(find.byKey(_mainButton), findsOneWidget);
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
          onRealized: () {},
        ));
        await tester.pumpAndSettle();
        expect(_realizeButtonCount(tester), 0);
      }
    });
  });
}
