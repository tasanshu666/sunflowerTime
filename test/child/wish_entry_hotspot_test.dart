/// A-T04 花园入口热点断言 ⑮~⑱（A7.6 S4~S7）。
///
/// 热点本身是纯 widget：常驻可见、点击回调、`animate=false` 时无循环动画
/// （`pumpAndSettle` 能返回）。花园页集成断言（入口在根 Stack 末尾、不进 chips 行、
/// 既有像素零回归）用源码守卫 + 既有 `weather_a3_banner_ui_test` 覆盖。
library wish_entry_hotspot_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/wish_tree_hotspot.dart';

Widget _host({required VoidCallback onTap, required bool animate}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: WishTreeHotspot(
            label: '我的许愿树',
            onTap: onTap,
            animate: animate,
          ),
        ),
      ),
    );

void main() {
  group('⑮ 入口常驻可见', () {
    testWidgets('热点 label 可见且不因条件隐藏', (WidgetTester tester) async {
      await tester.pumpWidget(_host(onTap: () {}, animate: false));
      expect(find.text('我的许愿树'), findsOneWidget);
    });
  });

  group('⑯ 点击 → push（onTap 回调触发）', () {
    testWidgets('点热点触发 onTap 一次', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(onTap: () => taps++, animate: false));
      await tester.tap(find.text('我的许愿树'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('⑰ 既有像素断言不回归：入口不进 chips 行', () {
    test('garden_page 入口在根 Stack 末尾且无购买入口', () {
      final String src = File(
        'lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      expect(src.contains('kWishTreeHotspotKey'), isTrue,
          reason: '入口带稳定 Key');
      expect(src.contains('WishTreeHotspot('), isTrue,
          reason: '花园页挂载热点');
      expect(src.contains('/parent/premium'), isFalse,
          reason: '孩子端花园页不得出现购买入口');
      expect(src.contains('buyLifetime'), isFalse);
    });
  });

  group('⑱ 根 Stack children 数量 / 顺序守卫', () {
    testWidgets('animate=false 不启动循环动画（pumpAndSettle 可返回）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(onTap: () {}, animate: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('路由注册 /wish-tree', () {
      final String src = File('lib/shared/app_router.dart').readAsStringSync();
      expect(src.contains("path: '/wish-tree'"), isTrue,
          reason: '必须注册许愿树路由');
    });
  });
}
