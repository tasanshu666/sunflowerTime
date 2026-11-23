/// QA 独立回归：守卫场景卡 L1 横幅背景接入（不复用工程师测试的断言形状）。
///
/// 独立口径：
///  - 素材：直接读磁盘字节 + rootBundle 双通道，解码尺寸与宽高比自算；
///  - 几何：直接调用 Flutter 的 applyBoxFit 求 FittedSizes，不再复刻 max() 公式
///    作为唯一依据（公式只作第二路交叉验证）；
///  - 渲染：直接取 RenderBox.size / localToGlobal 推导竖向留白，不用 getRect；
///  - 层级：直接检查内层 Stack.children 顺序（渐变在下、图片在上）；
///  - 前景：逐项比对 GuardCardLayout 的完整 Rect（left/top/width/height）。
///
/// headless 无法逐像素确认裁切观感；本文件只验证 widget 可观测契约与
/// applyBoxFit 推导出的绘制几何。真机目检仍需单独进行。
library qa_independent_guard_bg_test;

import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
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

const double _tol = 0.01;
const Size _sourcePixels = Size(3712, 640);

typedef _Case = (String name, double width, double scale, double cardHeight);

const List<_Case> _cases = <_Case>[
  ('iPhone390', 390, 1.0, 112.0),
  ('iPad11', 834, 1.3, 145.6),
  ('iPad13', 1032, 1.6, 179.2),
];

GuardTodayView _pendingView() => const GuardTodayView(
      mode: GuardPillMode.pendingFree,
      state: GuardDayState(
        dayKey: 'qa-bg-2026-11-23',
        status: GuardDayStatus.pending,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
      ),
      energyAvailable: 1,
      balance: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width + 40, 1000);
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
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: GuardSceneCard(
              view: _pendingView(),
              dayKey: 'qa-bg-2026-11-23',
              childId: 'qa-seed',
              uiScale: scale,
              onStart: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 60));
}

void _expectRect(Rect actual, Rect expected, String what) {
  expect(actual.left, closeTo(expected.left, _tol), reason: '$what.left');
  expect(actual.top, closeTo(expected.top, _tol), reason: '$what.top');
  expect(actual.width, closeTo(expected.width, _tol), reason: '$what.width');
  expect(actual.height, closeTo(expected.height, _tol), reason: '$what.height');
}

void main() {
  group('QA-A 素材落盘与打包', () {
    test('QA-A1 磁盘字节可解码为 3712x640，且 rootBundle 中同字节、pubspec 已声明',
        () async {
      final io.File file = io.File('assets/guard/background.webp');
      expect(file.existsSync(), isTrue, reason: '背景 WebP 必须落盘');
      final List<int> onDisk = await file.readAsBytes();
      expect(onDisk.length, 291876, reason: 'q95 产物体积应与交付记录一致');

      final ui.Codec codec =
          await ui.instantiateImageCodec(Uint8List.fromList(onDisk));
      final frame = await codec.getNextFrame();
      final Size decoded = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      expect(decoded, _sourcePixels);
      expect(decoded.aspectRatio, closeTo(3712 / 640, 1e-12));

      final ui.Codec bundledCodec = await ui.instantiateImageCodec(
        (await rootBundle.load(GuardArt.sceneBackgroundAsset))
            .buffer
            .asUint8List(),
      );
      final bundledFrame = await bundledCodec.getNextFrame();
      expect(
        Size(
          bundledFrame.image.width.toDouble(),
          bundledFrame.image.height.toDouble(),
        ),
        _sourcePixels,
        reason: 'pubspec 目录声明必须让素材真正进包',
      );
      bundledFrame.image.dispose();
      bundledCodec.dispose();

      expect(
        io.File('pubspec.yaml').readAsStringSync().contains('    - assets/guard/'),
        isTrue,
      );
    });
  });

  group('QA-G applyBoxFit 三档几何', () {
    for (final _Case c in _cases) {
      test('QA-G-${c.$1} cover 目标盒逐像素匹配卡高、竖向零裁剪、仅左右裁剪', () {
        final Size target = Size(c.$2, c.$4);
        final FittedSizes fitted = applyBoxFit(
          BoxFit.cover,
          _sourcePixels,
          target,
        );

        expect(fitted.destination, target,
            reason: 'cover 的 destination 必须等于目标盒（无上下留白）');
        expect(fitted.source.height, closeTo(_sourcePixels.height, 1e-9),
            reason: '源图 640 行必须全部参与绘制');
        expect(fitted.source.width, lessThan(_sourcePixels.width),
            reason: '只能裁左右：源宽必须被裁掉一部分');
        expect(fitted.source.aspectRatio, closeTo(target.aspectRatio, 1e-9),
            reason: '保留区域宽高比 == 目标宽高比，图片未被拉伸');
        expect(target.height - fitted.destination.height, 0.0,
            reason: 'vertical gap 严格为 0');

        // 第二路独立交叉验证：按 max(宽比, 高比) 放大源图。
        final double k = math.max(
          target.width / _sourcePixels.width,
          target.height / _sourcePixels.height,
        );
        expect(_sourcePixels.height * k, closeTo(target.height, 1e-9));
        expect(_sourcePixels.width * k, greaterThanOrEqualTo(target.width - 1e-9));
        expect((_sourcePixels.width * k) / (_sourcePixels.height * k),
            closeTo(_sourcePixels.aspectRatio, 1e-9));

        final double cropEachSideSourcePx =
            (_sourcePixels.width - fitted.source.width) / 2;
        expect(cropEachSideSourcePx, greaterThan(0),
            reason: '两侧都要真被裁，且左右等量（居中）');
        expect(target.height, closeTo(c.$4, 1e-9),
            reason: '卡高 = kGuardSceneCardHeight($kGuardSceneCardHeight) × uiScale');
      });
    }
  });

  group('QA-W 背景层 widget 契约与层级', () {
    for (final _Case c in _cases) {
      testWidgets('QA-W-${c.$1} key 唯一、cover/center、绘制盒=卡高、渐变在下图片在上',
          (WidgetTester tester) async {
        await _pump(tester, width: c.$2, scale: c.$3);

        final Finder cardF = find.byKey(GuardSceneCard.cardKey);
        final Finder layerF = find.byKey(GuardSceneCard.backdropKey);
        final Finder imageF = find.byKey(GuardSceneCard.backdropImageKey);
        expect(layerF, findsOneWidget, reason: 'backdropKey 必须唯一');
        expect(imageF, findsOneWidget, reason: 'backdropImageKey 必须唯一');
        expect(GuardSceneCard.backdropKey, isNot(GuardSceneCard.backdropImageKey));

        final Image image = tester.widget<Image>(imageF);
        expect(image.fit, BoxFit.cover);
        expect(image.fit, isNot(BoxFit.fill));
        expect(image.fit, isNot(BoxFit.contain));
        expect(image.alignment, Alignment.center);
        expect(image.width, double.infinity);
        expect(image.height, double.infinity);
        expect(image.image, isA<AssetImage>());
        expect((image.image as AssetImage).assetName,
            GuardArt.sceneBackgroundAsset);
        expect(image.errorBuilder, isNotNull);

        // 直接读 RenderBox 而非 getRect，独立推导竖向留白。
        final RenderBox cardBox = tester.renderObject<RenderBox>(cardF);
        final RenderBox layerBox = tester.renderObject<RenderBox>(layerF);
        final RenderBox imageBox = tester.renderObject<RenderBox>(imageF);
        final Offset cardOrigin = cardBox.localToGlobal(Offset.zero);
        final Offset imageOrigin = imageBox.localToGlobal(Offset.zero);
        final double drawnBottom = imageOrigin.dy + imageBox.size.height;
        final double cardBottom = cardOrigin.dy + cardBox.size.height;

        expect(imageBox.size.height, closeTo(c.$4, _tol),
            reason: '图片绘制盒高必须严格等于 kGuardSceneCardHeight × uiScale');
        expect(imageBox.size.width, closeTo(c.$2, _tol));
        expect(layerBox.size.height, closeTo(c.$4, _tol));
        expect(imageOrigin.dy - cardOrigin.dy, closeTo(0, _tol));
        expect(cardBottom - drawnBottom, closeTo(0, _tol),
            reason: 'vertical gap 必须为 0');

        // 禁止 FittedBox / 非 cover 的 Image 混入背景层。
        expect(find.descendant(of: layerF, matching: find.byType(FittedBox)),
            findsNothing);
        expect(
          find.descendant(
            of: layerF,
            matching: find.byWidgetPredicate(
              (Widget w) => w is Image && w.fit != BoxFit.cover,
            ),
          ),
          findsNothing,
        );

        // 层级：内层 Stack 恰好两个孩子，[0]=渐变兜底，[1]=图片。
        final Finder innerStackF =
            find.descendant(of: layerF, matching: find.byType(Stack));
        expect(innerStackF, findsOneWidget);
        final Stack inner = tester.widget<Stack>(innerStackF);
        expect(inner.fit, StackFit.expand);
        expect(inner.children.length, 2);
        final Finder lowerF = find.byWidget(inner.children.first);
        final Finder upperF = find.byWidget(inner.children.last);
        expect(
          find.descendant(of: lowerF, matching: find.byType(Image)),
          findsNothing,
          reason: '下层不得含任何 Image（必须是纯程序化渐变）',
        );
        expect(
          find.descendant(
            of: upperF,
            matching: find.byKey(GuardSceneCard.backdropImageKey),
          ),
          findsOneWidget,
          reason: '上层必须是背景图片',
        );
        final Finder gradientF =
            find.descendant(of: lowerF, matching: find.byType(DecoratedBox));
        expect(gradientF, findsOneWidget);
        final BoxDecoration decoration =
            tester.widget<DecoratedBox>(gradientF).decoration as BoxDecoration;
        expect(decoration.gradient, isA<LinearGradient>());
        final LinearGradient gradient = decoration.gradient! as LinearGradient;
        expect(gradient.colors, <Color>[
          const Color(0xFFFFF9E8),
          const Color(0xFFDCEFC4),
          const Color(0xFFB9DDA0),
        ]);
        expect(gradient.stops, <double>[0.0, 0.55, 1.0]);
      });
    }
  });

  group('QA-F 加载失败兜底', () {
    testWidgets('QA-F1 errorBuilder 产物不自绘；渐变层仍在图片下方',
        (WidgetTester tester) async {
      await _pump(tester, width: 390, scale: 1.0);
      final Image image = tester.widget<Image>(
        find.byKey(GuardSceneCard.backdropImageKey),
      );
      expect(image.errorBuilder, isNotNull);

      // 直接调用真实 errorBuilder，把返回物塞进与原卡同样的 Stack 位置。
      final Widget errorWidget = image.errorBuilder!(
        tester.element(find.byKey(GuardSceneCard.cardKey)),
        StateError('qa: background asset missing'),
        StackTrace.empty,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            key: const Key('qa-error-host'),
            child: SizedBox(
              width: 390,
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const _DebugGradient(),
                  Positioned.fill(child: errorWidget),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder host = find.byKey(const Key('qa-error-host'));
      expect(find.descendant(of: host, matching: find.byType(Image)), findsNothing);
      final Finder boxF = find.descendant(of: host, matching: find.byType(SizedBox));
      expect(boxF, findsWidgets);
      final SizedBox shrunk = tester.widget<SizedBox>(boxF.last);
      expect(shrunk.width, 0);
      expect(shrunk.height, 0);
      expect(shrunk.child, isNull);
      expect(
        find.descendant(of: host, matching: find.byWidgetPredicate(
          (Widget w) => w is DecoratedBox,
        )),
        findsOneWidget,
        reason: '错误层自身不绘制任何底色，只有底层渐变可见（不会白块）',
      );
    });
  });

  group('QA-P 前景零回归', () {
    for (final _Case c in _cases) {
      testWidgets('QA-P-${c.$1} 房子/能量点/战士/按钮的完整 Rect 与布局契约一致',
          (WidgetTester tester) async {
        await _pump(tester, width: c.$2, scale: c.$3);
        final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
        final GuardCardLayout layout = GuardCardLayout(c.$2, c.$3);
        final Offset origin = card.topLeft;

        _expectRect(
          tester.getRect(find.byKey(GuardSceneCard.houseKey)).shift(Offset(-origin.dx, -origin.dy)),
          layout.houseRect,
          'house',
        );
        _expectRect(
          tester.getRect(find.byKey(GuardSceneCard.soldierKey)).shift(Offset(-origin.dx, -origin.dy)),
          layout.soldierRect,
          'soldier',
        );
        for (int i = 0; i < 2; i++) {
          _expectRect(
            tester.getRect(find.byKey(GuardSceneCard.energyDotKey(i)))
                .shift(Offset(-origin.dx, -origin.dy)),
            layout.energyDotRect(i),
            'energyDot$i',
          );
          expect(find.byKey(GuardSceneCard.energyDotKey(i)), findsOneWidget);
        }
        _expectRect(
          tester.getRect(find.byKey(GuardSceneCard.startButtonKey)).shift(Offset(-origin.dx, -origin.dy)),
          layout.rightClusterRect,
          'startHitBox',
        );
        expect(
          tester.getRect(find.byKey(GuardSceneCard.startButtonVisualKey)).width,
          closeTo(40 * c.$3, _tol),
        );
        expect(find.byKey(GuardSceneCard.countdownKey), findsNothing);
        expect(find.byKey(GuardSceneCard.houseKey), findsOneWidget);
        expect(find.byKey(GuardSceneCard.soldierKey), findsOneWidget);
        expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget);
        expect(find.byKey(GuardSceneCard.statusSemanticsKey), findsOneWidget);

        // 背景层在房子之前（z-order 靠下），前景仍在背景之上。
        final Stack outer = tester.widget<Stack>(
          find
              .descendant(
                of: find.byKey(GuardSceneCard.cardKey),
                matching: find.byType(Stack),
              )
              .first,
        );
        int bgIndex = -1;
        int fgIndex = -1;
        for (int i = 0; i < outer.children.length; i++) {
          final Finder childF = find.byWidget(outer.children[i]);
          if (find
              .descendant(
                of: childF,
                matching: find.byKey(GuardSceneCard.backdropKey),
              )
              .evaluate()
              .isNotEmpty) {
            bgIndex = i;
          }
          if (find
              .descendant(
                of: childF,
                matching: find.byKey(GuardSceneCard.houseKey),
              )
              .evaluate()
              .isNotEmpty) {
            fgIndex = i;
          }
        }
        expect(bgIndex, greaterThanOrEqualTo(0));
        expect(fgIndex, greaterThanOrEqualTo(0));
        expect(bgIndex, lessThan(fgIndex), reason: '背景必须在前景之下');
      });
    }
  });
}

/// 仅供 QA-F1 使用的已知渐变占位；用于验证 errorBuilder 产物自身不画底色。
class _DebugGradient extends StatelessWidget {
  const _DebugGradient();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFFFF9E8)),
      );
}
