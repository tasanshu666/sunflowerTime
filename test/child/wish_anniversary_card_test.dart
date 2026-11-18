/// A-T04「历史上的今天」回顾卡断言 T-V250-01~09（A26.10 / A36.1~A36.3）。
///
/// 判据量写死独立期望值（不引用实现常量）。四态判据 / 命中口径 / 年份文案
/// 均为导出纯函数，直接断言 + 纯 widget pump，不拉起整页 DB。
library wish_anniversary_card_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart'
    show isAnniversaryMatch, shouldCelebrateMilestone;
import 'package:sunflower_time/presentation/child/widgets/wish_anniversary_card.dart';

Wish _wish({
  required String id,
  required DateTime createdAt,
  WishStatus status = WishStatus.pending,
  DateTime? releasedAt,
  DateTime? fulfilledAt,
  String text = '去年想要的恐龙',
}) =>
    Wish(
      id: id,
      childId: 'c1',
      text: text,
      status: status,
      createdAt: createdAt,
      releasedAt: releasedAt,
      fulfilledAt: fulfilledAt,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();
  final DateTime today = DateTime(2026, 3, 7, 9, 0);

  group('T-V250-01/02/06 命中口径（同月同日 + 年早于今年）', () {
    test('往年同月同日命中', () {
      expect(isAnniversaryMatch(_wish(id: 'a', createdAt: DateTime(2025, 3, 7)), today),
          isTrue);
    });

    test('今天刚许的不命中（同年）', () {
      expect(isAnniversaryMatch(_wish(id: 'b', createdAt: DateTime(2026, 3, 7)), today),
          isFalse);
    });

    test('跨多年依然命中（年度回顾语义）', () {
      expect(isAnniversaryMatch(_wish(id: 'c', createdAt: DateTime(2020, 3, 7)), today),
          isTrue);
    });

    test('不同月日不命中', () {
      expect(isAnniversaryMatch(_wish(id: 'd', createdAt: DateTime(2025, 3, 8)), today),
          isFalse);
    });
  });

  group('T-V250-05 四态判据（K26 恰 4 分支，无兜底）', () {
    test('status=fulfilled ⇒ fulfilled', () {
      expect(
        anniversaryStateOf(_wish(
          id: 'f',
          createdAt: DateTime(2025, 3, 7),
          status: WishStatus.fulfilled,
          fulfilledAt: DateTime(2025, 5, 1),
        )),
        WishAnniversaryState.fulfilled,
      );
    });

    test('releasedAt=null 且非 fulfilled ⇒ onTree', () {
      expect(
        anniversaryStateOf(_wish(id: 't', createdAt: DateTime(2025, 3, 7))),
        WishAnniversaryState.onTree,
      );
    });

    test('releasedAt!=null ⇒ boxed', () {
      expect(
        anniversaryStateOf(_wish(
          id: 'x',
          createdAt: DateTime(2025, 3, 7),
          releasedAt: DateTime(2025, 8, 1),
        )),
        WishAnniversaryState.boxed,
      );
    });

    test('status=abandoned ⇒ changed', () {
      expect(
        anniversaryStateOf(_wish(
          id: 'z',
          createdAt: DateTime(2025, 3, 7),
          status: WishStatus.abandoned,
        )),
        WishAnniversaryState.changed,
      );
    });

    test('四态文案无否定评价词（T-V250-05）', () {
      for (final WishAnniversaryState s in WishAnniversaryState.values) {
        final String text = anniversaryStateTextOf(s, zh);
        for (final String bad in <String>['没做到', '失败', '没完成', '快点']) {
          expect(text.contains(bad), isFalse, reason: '$s 不得含「$bad」');
        }
      }
    });
  });

  group('T-V250-09 年份参数化 + 英文无 Chinglish', () {
    test('1 年 → 去年今天；2 年 → 两年前；5 年 → 5 年前', () {
      expect(anniversaryYearLabel(1, zh), '这是你去年今天许的');
      expect(anniversaryYearLabel(2, zh), '这是你2年前的今天许的');
      expect(anniversaryYearLabel(5, zh), '这是你5年前的今天许的');
    });

    test('英文年份文案存在且非中文', () {
      expect(anniversaryYearLabel(1, en), isNotEmpty);
      expect(anniversaryYearLabel(3, en), contains('3'));
      expect(RegExp(r'[\u4E00-\u9FFF]').hasMatch(anniversaryYearLabel(3, en)),
          isFalse);
    });
  });

  group('T-V250-04 折叠计数 + A36.2 就地展开', () {
    testWidgets('extraCount>0 显示「还有 N 条」，点击展开小列表',
        (WidgetTester tester) async {
      final Wish main = _wish(id: 'main', createdAt: DateTime(2025, 3, 7));
      final Wish extra = _wish(
        id: 'extra',
        createdAt: DateTime(2024, 3, 7),
        text: '更早的愿望',
      );
      await tester.pumpWidget(_host(WishAnniversaryCard(
        wish: main,
        years: 1,
        t: zh,
        extraWishes: <Wish>[extra],
        extraCount: 1,
        onLook: () {},
        onDismiss: () {},
      )));

      expect(find.byKey(const Key('wish_anniversary_more')), findsOneWidget);
      expect(find.text('还有 1 条'), findsOneWidget);
      expect(find.byKey(const Key('wish_anniversary_extra_extra')), findsNothing);
      await tester.tap(find.byKey(const Key('wish_anniversary_more')));
      await tester.pump();
      expect(find.byKey(const Key('wish_anniversary_extra_extra')), findsOneWidget);
    });

    testWidgets('extraCount=0 不显示折叠行', (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishAnniversaryCard(
        wish: _wish(id: 'solo', createdAt: DateTime(2025, 3, 7)),
        years: 1,
        t: zh,
        onLook: () {},
        onDismiss: () {},
      )));
      expect(find.byKey(const Key('wish_anniversary_more')), findsNothing);
    });
  });

  group('T-V250-08/06 卡片只读 + 两个动作回调', () {
    testWidgets('看看它 / 收起 分别触发回调', (WidgetTester tester) async {
      int looks = 0;
      int dismisses = 0;
      await tester.pumpWidget(_host(WishAnniversaryCard(
        wish: _wish(id: 'a', createdAt: DateTime(2025, 3, 7)),
        years: 1,
        t: zh,
        onLook: () => looks++,
        onDismiss: () => dismisses++,
      )));
      await tester.tap(find.byKey(const Key('wish_anniversary_look')));
      await tester.tap(find.byKey(const Key('wish_anniversary_dismiss')));
      await tester.pump();
      expect(looks, 1);
      expect(dismisses, 1);
    });
  });

  group('里程碑演出幂等（A-T04 断言 ⑦）', () {
    test('同一 stage 只播一次（current>last 才播）', () {
      expect(shouldCelebrateMilestone(3, 2), isTrue);
      expect(shouldCelebrateMilestone(3, 3), isFalse, reason: '相等不播');
      expect(shouldCelebrateMilestone(2, 3), isFalse, reason: '退档不播');
    });
  });
}
