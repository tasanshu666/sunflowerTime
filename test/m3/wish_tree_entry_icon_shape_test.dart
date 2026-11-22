/// 许愿树入口换图 / 放大回归（玄参 2026-11-20 两次真机反馈）。
///
/// 钉住四件事：① 中心是 `许愿树1.png`（`AssetImage`）而非系统 `Icon`；
/// ② 容器 / 热区都是 12dp 圆角方形（与天气徽标同常量、**不乘 uiScale**），
///    不是 `side / 2` 的正圆；③ 容器边长对齐天气徽标 56（原 48 小一圈）；
/// ④ 位图显示盒放大到 52（原 26 下树实际仅 ≈18dp，又小又糊）。
library wish_tree_entry_icon_shape_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 只渲染入口本体，避免花园页其它热区干扰 Finder。
Widget _entryHarness() {
  return MaterialApp(
    home: WishTreeWeatherEntry(
      label: '许愿树',
      onTap: () {},
    ),
  );
}

/// 从入口节点向下找唯一的 Material / InkWell（两者就在 Semantics 里层）。
Material _entryMaterial(WidgetTester tester) {
  return tester.widget<Material>(find
      .descendant(
        of: find.byKey(kWishTreeWeatherEntryKey),
        matching: find.byType(Material),
      )
      .first);
}

InkWell _entryInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(find
      .descendant(
        of: find.byKey(kWishTreeWeatherEntryKey),
        matching: find.byType(InkWell),
      )
      .first);
}

/// InkWell 内部那个定尺寸的 SizedBox（Semantics 在 loose 约束下会撑满父节点）。
SizedBox _entryBox(WidgetTester tester) {
  return tester.widget<SizedBox>(find
      .descendant(
        of: find.byType(InkWell),
        matching: find.byType(SizedBox),
      )
      .first);
}

void main() {
  group('尺寸常量单点：与天气徽标等大、树放大', () {
    test('容器 = 天气徽标 56；位图显示盒 = 52（> 旧值 26）', () {
      expect(kGardenWeatherBadgeIconSize, 56.0);
      expect(kWishTreeWeatherEntrySize, 56.0,
          reason: '许愿树容器必须与天气徽标视觉等大（2026-11-20 二次反馈）');
      expect(kWishTreeWeatherEntrySize, kGardenWeatherBadgeIconSize);
      expect(kWishTreeWeatherEntryIconSize, 52.0);
      expect(kWishTreeWeatherEntryIconSize, greaterThan(26.0),
          reason: '旧的 26 盒里树只有 ≈18dp，必须放大');
      expect(kWishTreeWeatherEntryIconSize, lessThan(kWishTreeWeatherEntrySize),
          reason: '透明边距保证不顶边，显示盒仍需小于容器');
    });
  });

  group('许愿树入口图标与形状', () {
    testWidgets('手机：许愿树1.png + 56 容器 + 12dp 圆角方形（非正圆）',
        (WidgetTester tester) async {
      // flutter test 默认 800×600 会被判成平板（shortestSide=600），须显式设手机视口。
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_entryHarness());

      final Finder entry = find.byKey(kWishTreeWeatherEntryKey);
      expect(entry, findsOneWidget);

      final BorderRadius expected =
          BorderRadius.circular(kGardenWeatherBadgeIconContainerRadius);
      expect(_entryMaterial(tester).borderRadius, expected,
          reason: 'Material 圆角须与天气徽标一致 = 12dp');
      expect(_entryInkWell(tester).borderRadius, expected,
          reason: 'InkWell 水波纹圆角须与 Material 一致 = 12dp');
      expect(_entryMaterial(tester).borderRadius,
          isNot(BorderRadius.circular(kWishTreeWeatherEntrySize / 2)),
          reason: '旧的 side/2 = 正圆，必须已改掉');

      expect(find.descendant(of: entry, matching: find.byType(Icon)),
          findsNothing,
          reason: '系统 Icons.park_outlined 已被素材图替换');
      final Finder imageFinder =
          find.descendant(of: entry, matching: find.byType(Image));
      expect(imageFinder, findsOneWidget);
      final Image image = tester.widget<Image>(imageFinder);
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName,
          kWishTreeWeatherEntryIconAsset);
      // 2048 方图必须有显式尺寸盒，loose 约束下不写宽高会撑爆父布局。
      expect(image.width, 52.0);
      expect(image.height, 52.0);
      expect(image.fit, BoxFit.contain);
      final SizedBox box = _entryBox(tester);
      expect(box.width, kGardenWeatherBadgeIconSize);
      expect(box.height, kGardenWeatherBadgeIconSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad 11″：容器与树均按 uiScale 等比放大，圆角仍固定 12dp',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_entryHarness());

      final Finder imageFinder = find.descendant(
        of: find.byKey(kWishTreeWeatherEntryKey),
        matching: find.byType(Image),
      );
      final Image image = tester.widget<Image>(imageFinder);
      expect(image.width, closeTo(52.0 * 1.3, 0.01));
      expect(image.height, closeTo(52.0 * 1.3, 0.01));
      final SizedBox box = _entryBox(tester);
      expect(box.width, closeTo(56.0 * 1.3, 0.01));
      expect(box.height, closeTo(56.0 * 1.3, 0.01));
      final BorderRadius expected =
          BorderRadius.circular(kGardenWeatherBadgeIconContainerRadius);
      expect(_entryMaterial(tester).borderRadius, expected);
      expect(_entryInkWell(tester).borderRadius, expected);
      expect(tester.takeException(), isNull);
    });
  });

  group('R7-P0-03 手机单侧缩放：系数单点 + iPad 逐字节不变', () {
    test('compactScaleFor 真值表：手机 0.8 / iPad 1.0，系数单点常量 = 0.8', () {
      expect(kPhoneEntryScale, 0.8);
      expect(compactScaleFor(isTablet: false), closeTo(0.8, 0.001));
      expect(compactScaleFor(isTablet: true), 1.0,
          reason: 'iPad 恒 1.0，逐字节不变');
    });

    testWidgets('手机传 scale=0.8：容器/位图按系数缩，圆角仍固定 12dp',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: WishTreeWeatherEntry(
          label: '许愿树',
          scale: compactScaleFor(isTablet: false),
          onTap: () {},
        ),
      ));

      final Image image = tester.widget<Image>(find
          .descendant(
            of: find.byKey(kWishTreeWeatherEntryKey),
            matching: find.byType(Image),
          )
          .first);
      expect(image.width, closeTo(52.0 * 0.8, 0.01));
      expect(image.height, closeTo(52.0 * 0.8, 0.01));
      final SizedBox box = _entryBox(tester);
      expect(box.width, closeTo(56.0 * 0.8, 0.01));
      expect(box.height, closeTo(56.0 * 0.8, 0.01));
      // 圆角常量不乘 scale。
      expect(_entryMaterial(tester).borderRadius,
          BorderRadius.circular(kGardenWeatherBadgeIconContainerRadius));
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad 传 scale=1.0：与不传 scale 逐字节一致（56×1.3 / 52×1.3）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: WishTreeWeatherEntry(
          label: '许愿树',
          scale: compactScaleFor(isTablet: true),
          onTap: () {},
        ),
      ));

      final Image image = tester.widget<Image>(find
          .descendant(
            of: find.byKey(kWishTreeWeatherEntryKey),
            matching: find.byType(Image),
          )
          .first);
      expect(image.width, closeTo(52.0 * 1.3, 0.01));
      expect(image.height, closeTo(52.0 * 1.3, 0.01));
      final SizedBox box = _entryBox(tester);
      expect(box.width, closeTo(56.0 * 1.3, 0.01));
      expect(box.height, closeTo(56.0 * 1.3, 0.01));
      expect(tester.takeException(), isNull);
    });
  });

  test('许愿树图标资源落盘且 pubspec 声明了父目录', () {
    final File asset = File(kWishTreeWeatherEntryIconAsset);
    expect(asset.existsSync(), isTrue,
        reason: '资源缺失：$kWishTreeWeatherEntryIconAsset');
    expect(asset.lengthSync(), greaterThan(0), reason: '资源不能是空文件');

    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/wish_tree/'),
        reason: 'Flutter 目录声明不递归，父目录必须单独声明');
  });
}
