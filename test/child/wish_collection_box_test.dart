/// A-T04 收藏箱段断言（Q35-A / A24.7）：排序 + 日期显示 + 取回回调。
///
/// 判据：仓储 `boxed()` 已按 `createdAt` 倒序返回，本 widget **只读展示不再重排**；
/// 每条必须显示「许愿日期」（写死期望日期，不引用实现格式化常量）。
library wish_collection_box_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_collection_box.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';

Wish _wish(String id, DateTime createdAt) => Wish(
      id: id,
      childId: 'c1',
      text: '愿望$id',
      createdAt: createdAt,
      releasedAt: createdAt.add(const Duration(days: 1)),
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final AppLocalizations t = AppLocalizationsZh();

  test('收藏箱卡片显示许愿日期（yyyy-MM-dd，写死期望值）', () {
    final DateTime d = DateTime(2025, 3, 7, 10, 30);
    expect(wishDisplayDate(d), '2025-03-07');
  });

  testWidgets('按入参顺序（createdAt 倒序）渲染，不重排',
      (WidgetTester tester) async {
    // 入参已是倒序：w-new(2025-06) 在前，w-old(2025-01) 在后。
    final List<Wish> wishes = <Wish>[
      _wish('w-new', DateTime(2025, 6, 1)),
      _wish('w-old', DateTime(2025, 1, 1)),
    ];
    await tester.pumpWidget(_host(WishCollectionBox(wishes: wishes, t: t)));

    final Finder newTile = find.byKey(const Key('wish_collection_tile_w-new'));
    final Finder oldTile = find.byKey(const Key('wish_collection_tile_w-old'));
    expect(newTile, findsOneWidget);
    expect(oldTile, findsOneWidget);
    // 位置断言：new 的 top 小于 old（即 new 在上 = 倒序）。
    expect(tester.getTopLeft(newTile).dy < tester.getTopLeft(oldTile).dy,
        isTrue);
  });

  testWidgets('每条显示许愿日期文案', (WidgetTester tester) async {
    final List<Wish> wishes = <Wish>[
      _wish('w-new', DateTime(2025, 6, 1)),
    ];
    await tester.pumpWidget(_host(WishCollectionBox(wishes: wishes, t: t)));
    expect(find.byKey(const Key('wish_collection_date_w-new')), findsOneWidget);
    expect(find.textContaining('2025-06-01'), findsOneWidget);
  });

  testWidgets('取回按钮存在且可点（额度由页面判，本 widget 只回调）',
      (WidgetTester tester) async {
    int restored = 0;
    final List<Wish> wishes = <Wish>[
      _wish('w-new', DateTime(2025, 6, 1)),
    ];
    await tester.pumpWidget(_host(WishCollectionBox(
      wishes: wishes,
      t: t,
      onRestore: (_) => restored++,
    )));
    await tester.tap(find.byKey(const Key('wish_collection_restore_w-new')));
    await tester.pump();
    expect(restored, 1);
  });

  testWidgets('空收藏箱显示空态文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(WishCollectionBox(wishes: const <Wish>[], t: t)),
    );
    expect(find.byKey(const Key('wish_collection_empty')), findsOneWidget);
    expect(find.text(t.wishTreeEmptyBox), findsOneWidget);
  });
}
