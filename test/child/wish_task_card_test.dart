/// A-T04 愿望任务卡断言 ⑲~㉒（A22.3 / A24.6 ①）。
///
/// 期望值写死，不引用实现常量。用真实 GoRouter 捕获 `context.go` 的 URI，
/// 验证「去专注」先弹确认、取消不进专注、确认才带 `?wishTask=<tasks.id>`。
library wish_task_card_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';

Task _task({required bool focus, String id = 'wish-task-1'}) => Task(
      id: id,
      name: '朗读绘本',
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: 20,
      sunlightReward: 12,
      isCustom: true,
      wishId: 'wish-1',
    );

String? _lastUri;

GoRouter _router(Widget child) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext c, GoRouterState s) => Scaffold(body: child),
        ),
        GoRoute(
          path: '/focus',
          builder: (BuildContext c, GoRouterState s) {
            _lastUri = s.uri.toString();
            return const Scaffold(body: Center(key: Key('focus_reached')));
          },
        ),
      ],
    );

Widget _host(Widget child) => MaterialApp.router(
      routerConfig: _router(child),
    );

WishTaskCard _card({
  required Task task,
  VoidCallback? onDidIt,
}) =>
    WishTaskCard(
      task: task,
      wishTitle: '小恐龙',
      focusActionLabel: '去专注',
      didItLabel: '我做到了',
      confirmTitle: '去专注',
      confirmMessage: '开始专注吗',
      startFocusLabel: '开始',
      cancelLabel: '取消',
      doneLabel: '已完成',
      pendingLabel: '等家长确认',
      onDidIt: onDidIt,
    );

void main() {
  setUp(() => _lastUri = null);

  group('⑲ 专注型任务卡有「去专注」', () {
    testWidgets('requiresFocus=true ⇒ wish_task_go_focus 出现，无 did_it',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_card(task: _task(focus: true))));
      expect(find.byKey(const Key('wish_task_go_focus')), findsOneWidget);
      expect(find.byKey(const Key('wish_task_did_it')), findsNothing);
    });
  });

  group('⑳ 手动型有「我做到了」', () {
    testWidgets('requiresFocus=false ⇒ wish_task_did_it 出现，无 go_focus',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_card(task: _task(focus: false))));
      expect(find.byKey(const Key('wish_task_did_it')), findsOneWidget);
      expect(find.byKey(const Key('wish_task_go_focus')), findsNothing);
    });
  });

  group('㉑ 「去专注」先弹确认卡（取消不进专注）', () {
    testWidgets('取消 ⇒ 不跳 /focus', (WidgetTester tester) async {
      await tester.pumpWidget(_host(_card(task: _task(focus: true))));
      await tester.tap(find.byKey(const Key('wish_task_go_focus')));
      await tester.pumpAndSettle();
      // 确认卡出现。
      expect(find.byKey(const Key('child_confirm_card_surface')), findsOneWidget);
      // 点「取消」。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(_lastUri, isNull, reason: '取消绝不进专注');
    });

    testWidgets('确认 ⇒ 跳 /focus 带 minutes/dnd/wishTask',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(_card(task: _task(focus: true, id: 'task-xyz'))),
      );
      await tester.tap(find.byKey(const Key('wish_task_go_focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      expect(_lastUri, isNotNull);
      expect(_lastUri, contains('/focus'));
      expect(_lastUri, contains('minutes=20'));
      expect(_lastUri, contains('dnd=1'));
      expect(_lastUri, contains('wishTask=task-xyz'));
      expect(_lastUri, isNot(contains('?task=')),
          reason: '走 wishTask 分支，不带 ?task=');
    });
  });

  group('㉒ 愿望徽标 + 短名 + 手动确认回调', () {
    testWidgets('wishId != null ⇒ wish_task_badge 出现',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_card(task: _task(focus: true))));
      expect(find.byKey(const Key('wish_task_badge')), findsOneWidget);
      expect(find.textContaining('小恐龙'), findsWidgets);
    });

    test('短名按码点截断：超 8 emoji 以省略号结尾', () {
      final String long = '🌟' * 12;
      final String short = wishTaskShortTitle(long);
      expect(short.runes.length, 9, reason: '8 个 emoji + 1 个省略号');
      expect(short.endsWith('…'), isTrue);
    });

    testWidgets('手动型「我做到了」先确认再回调',
        (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(_host(_card(
        task: _task(focus: false),
        onDidIt: () => calls++,
      )));
      await tester.tap(find.byKey(const Key('wish_task_did_it')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('child_confirm_card_surface')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, 0, reason: '取消不落库');
    });
  });
}
