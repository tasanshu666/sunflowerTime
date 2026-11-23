/// 守卫战 v2 · **L1 横幅背景接入护栏**（玄参新交付「背景图片.png」）。
///
/// 覆盖：
/// 1. 资产落盘契约：WebP、3712×640、体积远小于源 PNG；
/// 2. `BoxFit.cover` 几何：三种机型下**绘制高度严格 = 卡高**，仅左右裁切；
/// 3. widget 层：背景层根 key 唯一且尺寸 = 卡尺寸，图片 fit=cover / 路径正确，
///    渐变草地兜底仍在（含 errorBuilder 触发后的表现）；
/// 4. 前景零回归：房子 / 战士 / 开始钮仍按 `GuardCardLayout` 原位渲染。
///
/// 🔴 headless 的边界：Flutter tester 不合成真实 GPU 帧，无法逐像素比对
/// 「哪几列被裁掉」。这里验证的是 **widget 可观测边界**（key、约束尺寸、
/// fit、assetName、源图宽高比）+ 由 `applyBoxFit` 同款公式推导的绘制几何。
/// 真机目检仍需玄参确认左右裁切中心与画面观感。
library guard_scene_background_test;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

const double _kEps = 0.02;

/// 源图实测尺寸（与 tools/convert_guard_background.py 的 EXPECTED_SIZE 同源）。
const Size _kArtworkSize = Size(3712, 640);

GuardTodayView _view() => const GuardTodayView(
      mode: GuardPillMode.pendingFree,
      state: GuardDayState(
        dayKey: '2026-11-23',
        status: GuardDayStatus.pending,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
      ),
      energyAvailable: 1,
      balance: 0,
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  required double uiScale,
}) async {
  tester.view.physicalSize = Size(cardWidth, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cardWidth,
            child: GuardSceneCard(
              view: _view(),
              dayKey: '2026-11-23',
              childId: 'seed-0',
              uiScale: uiScale,
              onStart: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 与 Flutter `applyBoxFit(BoxFit.cover, ...)` 同款的缩放系数。
double _coverScale(Size source, Size target) =>
    math.max(target.width / source.width, target.height / source.height);

void main() {
  group('① 资产落盘契约', () {
    test('背景 WebP 存在、可解码、尺寸 3712×640、体积远小于源 PNG', () async {
      final bytes = await rootBundle.load(GuardArt.sceneBackgroundAsset);
      expect(GuardArt.sceneBackgroundAsset, 'assets/guard/background.webp');
      expect(bytes.lengthInBytes, lessThan(400 * 1024),
          reason: '🔴 WebP q95 应远小于 2.4MB 源 PNG（实测 291,876 B）');

      final ui.Codec codec =
          await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, _kArtworkSize.width.toInt());
      expect(frame.image.height, _kArtworkSize.height.toInt());
      frame.image.dispose();
      codec.dispose();
    });
  });

  group('② BoxFit.cover 几何（三档机型）', () {
    // iPhone 390pt / iPad 11″ 834pt u=1.3 / iPad 13″ 1032pt u=1.6。
    const List<(String, double, double)> cases = <(String, double, double)>[
      ('iPhone 390pt', 390, 1.0),
      ('iPad 11" 834pt', 834, 1.3),
      ('iPad 13" 1032pt', 1032, 1.6),
    ];

    for (final (String name, double cardWidth, double scale) in cases) {
      test('$name：绘制高度 = 卡高 ${(kGuardSceneCardHeight * scale).toStringAsFixed(1)}，'
          '只裁左右、不上下留白', () {
        final Size box = Size(cardWidth, kGuardSceneCardHeight * scale);
        final double s = _coverScale(_kArtworkSize, box);
        final double drawnHeight = _kArtworkSize.height * s;
        final double drawnWidth = _kArtworkSize.width * s;

        expect(drawnHeight, closeTo(box.height, _kEps),
            reason: '🔴 5.8:1 素材宽于任何机型卡 ⇒ cover 必按高度缩放，无上下留白');
        expect(drawnWidth, greaterThanOrEqualTo(box.width - _kEps));
        expect((drawnWidth - box.width) / 2, greaterThan(0),
            reason: '$name 必须左右居中裁切（只多不少）');
        expect(box.aspectRatio, lessThan(_kArtworkSize.aspectRatio),
            reason: '卡比图窄是「高度驱动 cover」的前提');
      });
    }
  });

  group('③ 背景层 widget 契约', () {
    const List<(String, double, double)> cases = <(String, double, double)>[
      ('iPhone 390pt', 390, 1.0),
      ('iPad 11" 834pt', 834, 1.3),
      ('iPad 13" 1032pt', 1032, 1.6),
    ];

    for (final (String name, double cardWidth, double scale) in cases) {
      testWidgets('$name：背景层 = 卡尺寸、key 唯一、cover 图片 + 渐变兜底',
          (WidgetTester tester) async {
        await _pumpCard(tester, cardWidth: cardWidth, uiScale: scale);

        final Finder backdrop = find.byKey(GuardSceneCard.backdropKey);
        expect(backdrop, findsOneWidget,
            reason: '🔴 backdropKey 必须唯一（旧 find.byKey 断言不能歧义）');

        final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
        final Rect layer = tester.getRect(backdrop);
        expect(layer.width, closeTo(card.width, _kEps));
        expect(layer.height, closeTo(card.height, _kEps),
            reason: '🔴 背景层高度严格等于卡高 = '
                '${(kGuardSceneCardHeight * scale).toStringAsFixed(1)}');
        expect(layer.top, closeTo(card.top, _kEps));
        expect(layer.left, closeTo(card.left, _kEps));

        final Finder imageFinder = find.byKey(GuardSceneCard.backdropImageKey);
        expect(imageFinder, findsOneWidget);
        final Image image = tester.widget<Image>(imageFinder);
        expect(image.fit, BoxFit.cover,
            reason: '🔴 必须 cover：fill 变形 / FittedBox 压字号 / contain 留白');
        expect(image.width, double.infinity);
        expect(image.height, double.infinity);
        expect(image.alignment, Alignment.center, reason: '左右居中裁切');
        expect((image.image as AssetImage).assetName, GuardArt.sceneBackgroundAsset);
        expect(image.errorBuilder, isNotNull, reason: '加载失败必须能兜底');

        final Rect imageRect = tester.getRect(imageFinder);
        expect(imageRect.height, closeTo(card.height, _kEps),
            reason: '🔴 图片的绘制盒高度 = 卡高');
        expect(imageRect.width, closeTo(card.width, _kEps));

        expect(
          find.descendant(
            of: backdrop,
            matching: find.byType(DecoratedBox),
          ),
          findsOneWidget,
          reason: '🔴 渐变草地板兜底仍在图片下层',
        );
        expect(
          find.descendant(of: backdrop, matching: find.byType(FittedBox)),
          findsNothing,
          reason: '🔴 禁止 FittedBox（会压字号）',
        );
      });
    }

    testWidgets('前景六件事原位零回归（390pt）', (WidgetTester tester) async {
      const double cardWidth = 390;
      const double scale = 1.0;
      await _pumpCard(tester, cardWidth: cardWidth, uiScale: scale);

      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      const GuardCardLayout l = GuardCardLayout(cardWidth, scale);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect soldier = tester.getRect(find.byKey(GuardSceneCard.soldierKey));
      final Rect start = tester.getRect(find.byKey(GuardSceneCard.startButtonKey));

      expect(house.top - card.top, closeTo(l.houseRect.top, _kEps));
      expect(house.left - card.left, closeTo(l.houseRect.left, _kEps));
      expect(soldier.top - card.top, closeTo(l.soldierRect.top, _kEps));
      expect(soldier.left - card.left, closeTo(l.soldierRect.left, _kEps));
      expect(start.width, closeTo(l.rightClusterRect.width, _kEps));
      expect(find.byKey(GuardSceneCard.countdownKey), findsNothing);
    });
  });

  group('④ 加载失败兜底', () {
    testWidgets('errorBuilder 返回零尺寸盒 ⇒ 底层渐变仍铺满卡，无白块',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390, uiScale: 1.0);
      final Image image = tester.widget<Image>(
        find.byKey(GuardSceneCard.backdropImageKey),
      );
      expect(image.errorBuilder, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: Builder(
              key: const Key('errorFallbackHost'),
              builder: (BuildContext context) =>
                  image.errorBuilder!(context, StateError('asset missing'), StackTrace.empty),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder host = find.byKey(const Key('errorFallbackHost'));
      final SizedBox errorBox = tester.widget<SizedBox>(
        find.descendant(of: host, matching: find.byType(SizedBox)),
      );
      // 注意：父级 Positioned.fill 给的是紧约束，SizedBox.shrink() 的渲染盒
      // 会被父约束撑到卡大小；关键在它**自身不画任何东西**（宽高配置 0、
      // 无 child、无 decoration）⇒ 下层渐变直接透出来，不会出现白块。
      expect(errorBox.width, 0);
      expect(errorBox.height, 0);
      expect(errorBox.child, isNull);
      expect(
        find.descendant(of: host, matching: find.byType(DecoratedBox)),
        findsNothing,
        reason: '错误层自身不绘制任何 DecoratedBox（不会盖住渐变）',
      );
    });

    testWidgets('兜底渐变色阶未改动（上奶油 / 中浅绿 / 下深绿）',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390, uiScale: 1.0);
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(GuardSceneCard.backdropKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final BoxDecoration decoration = box.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
      final LinearGradient gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, const <Color>[
        Color(0xFFFFF9E8),
        Color(0xFFDCEFC4),
        Color(0xFFB9DDA0),
      ]);
      expect(gradient.stops, const <double>[0.0, 0.55, 1.0]);
    });
  });
}
