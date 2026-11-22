/// 循环树换批验收（玄参 2026-11-20 iPad13）：帧索引纯函数 / 10 秒循环 widget /
/// 3:4 树框几何与树根锚定 / 51 帧资产与 pubspec 目录声明。
///
/// 全部用真实 Widget 宿主 + Flutter FakeAsync 驱动，不用字符串 contains 冒充行为。
library wish_tree_scene_animation_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/wish_tree_scene.dart';

const Key _treeKey = Key('wish_scene_tree');

Widget _host(Size size, {double dpr = 1, double actionScale = 1.0}) =>
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: dpr),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: WishTreeScene(
              actionScale: actionScale,
              eggs: <WishEgg>[
                WishEgg(
                  asset: WishTreeArt.eggWish,
                  label: '愿望一',
                  onTap: () {},
                  key: const Key('egg_0'),
                ),
              ],
              onStartWish: () {},
              onOpenBox: () {},
              onOpenPool: () {},
              boxLabel: '收藏箱',
              poolLabel: '愿望池',
              startLabel: '许愿',
            ),
          ),
        ),
      ),
    );

/// 读取当前树帧文件名（[Image] 带 cacheWidth ⇒ provider 包了一层 [ResizeImage]）。
String _treeFrameName(WidgetTester tester) {
  final Image image = tester.widget<Image>(find.byKey(_treeKey));
  Object provider = image.image;
  if (provider is ResizeImage) {
    provider = provider.imageProvider;
  }
  expect(provider, isA<AssetImage>(), reason: '树必须是 Image.asset 帧');
  return (provider as AssetImage).assetName.split('/').last;
}

/// 取最近的 [Positioned] 祖先（本 Flutter 版本没有 `WidgetTester.ancestorOf`）。
Positioned _positionedOf(WidgetTester tester, Key key) =>
    tester.widget<Positioned>(
      find.ancestor(of: find.byKey(key), matching: find.byType(Positioned)).first,
    );

void main() {
  group('① 帧索引纯函数（QA 变异测试入口）', () {
    test('progress=0 → 0；接近 1 → 50；越界与异常值 clamp', () {
      const int count = WishTreeSceneLayout.treeFrameCount;
      expect(count, 51);
      expect(wishTreeFrameIndex(0, count), 0);
      expect(wishTreeFrameIndex(0.5, count), 25);
      expect(wishTreeFrameIndex(1 - 1e-9, count), 50);
      expect(wishTreeFrameIndex(1.0, count), 50, reason: '1.0 按最后一帧 clamp');
      expect(wishTreeFrameIndex(-0.25, count), 0);
      expect(wishTreeFrameIndex(1.7, count), 50);
      expect(wishTreeFrameIndex(double.nan, count), 0);
      expect(wishTreeFrameIndex(double.infinity, count), 50);
      expect(wishTreeFrameIndex(0, 0), 0, reason: '零帧防御');
      expect(wishTreeFrameIndex(0.9, -3), 0, reason: '负帧数防御');
    });

    test('整帧覆盖：51 个文件名连续且资产真实落盘', () {
      for (int i = 0; i < WishTreeSceneLayout.treeFrameCount; i++) {
        final String path = WishTreeArt.treeFrameAsset(i);
        expect(
          path,
          'assets/wish_tree/tree_frames/frame${(i + 1).toString().padLeft(3, '0')}.png',
        );
        expect(File(path).existsSync(), isTrue, reason: '缺帧 $path');
      }
      expect(File(WishTreeArt.tree).existsSync(), isTrue,
          reason: '旧 tree.png 保留不删');
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- assets/wish_tree/tree_frames/'),
        reason: '目录声明不递归，漏这行 51 帧静默不进包',
      );
    });
  });

  group('② 10 秒循环 widget（vsync + dispose）', () {
    testWidgets('首帧 frame001 → 1s 后 frame006 → 10s 周期末回到 frame001',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const Size(800, 600)));
      expect(find.byKey(_treeKey), findsOneWidget);
      expect(_treeFrameName(tester), 'frame001.png');

      await tester.pump(const Duration(seconds: 1));
      expect(_treeFrameName(tester), 'frame006.png',
          reason: '1/10 × 51 = 5.1 ⇒ 第 5 帧（frame006）');

      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_treeFrameName(tester), 'frame001.png',
          reason: '10 秒一轮 repeat()，末帧回到第 0 帧');

      // 反复挂载/卸载不抛 Ticker 未 dispose 异常。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('按显示像素 × dpr 限制解码尺寸（不把 51 张全尺寸塞进缓存）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const Size(800, 600), dpr: 2));
      final Image image = tester.widget<Image>(find.byKey(_treeKey));
      expect(image.width, 324);
      expect(image.height, 432);
      expect(image.image, isA<ResizeImage>());
      final ResizeImage resized = image.image as ResizeImage;
      expect(resized.width, 648, reason: '324 逻辑宽 × dpr2');
      expect(resized.height, 864, reason: '432 逻辑高 × dpr2');
      expect(resized.width, lessThanOrEqualTo(720));
      expect(resized.height, lessThanOrEqualTo(960));
      expect(image.gaplessPlayback, isTrue, reason: '帧间不能有白闪');
    });
  });

  group('③ 3:4 树框几何 + 树根锚定（防改回方图）', () {
    test('树根比例常量来自新帧实测（895/960）', () {
      expect(WishTreeSceneLayout.treeRootFraction, 0.9323);
      expect(WishTreeSceneLayout.treeWidthHeightRatio, 0.75);
      expect(WishTreeSceneLayout.treeRootFraction, isNot(0.852),
          reason: '0.852 是旧 2048² 方图的树根');
    });

    testWidgets('常规屏：树框 324×432 = 高 × 0.75，树根压在小岛场景 y 上',
        (WidgetTester tester) async {
      const Size scene = Size(800, 600);
      await tester.pumpWidget(_host(scene));

      final Positioned treeBox = _positionedOf(tester, _treeKey);
      expect(treeBox.width, closeTo(324, 1e-6));
      expect(treeBox.height, closeTo(432, 1e-6));
      expect(treeBox.width, closeTo(treeBox.height! * 0.75, 1e-9));

      final double islandY = WishTreeSceneLayout.sceneYOfBackgroundFraction(
        scene,
        WishTreeSceneLayout.islandImageFraction,
      );
      expect(
        treeBox.top,
        closeTo(islandY - 0.9323 * 432, 1e-6),
        reason: 'treeTop = islandSceneY − treeRootFraction × treeHeight',
      );

      // 蛋的纵向坐标必须按树**高**算（3:4 后与宽不同）。
      final Positioned eggBox = _positionedOf(tester, const Key('egg_0'));
      const double eggSize = 800 * WishTreeSceneLayout.eggSizeRatio;
      expect(
        eggBox.top,
        closeTo(treeBox.top! + WishTreeScene.eggSpots[0].dy * 432 - eggSize / 2,
            1e-6),
      );
    });

    testWidgets('极窄屏：宽度按场景宽 ×1.48 封顶并反推高度', (WidgetTester tester) async {
      // 场景必须真的有 960 高，否则 Scaffold body 仍按测试默认 800×600 布局。
      await tester.binding.setSurfaceSize(const Size(340, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(const Size(340, 960)));
      final Positioned treeBox = _positionedOf(tester, _treeKey);
      expect(treeBox.width, closeTo(503.2, 1e-6), reason: '340 × 1.48');
      expect(
        treeBox.height,
        closeTo(503.2 / WishTreeSceneLayout.treeWidthHeightRatio, 1e-6),
        reason: '高度由封顶宽度反推',
      );
    });
  });

  group('R7-P0-03 图3 底部三圆形按钮单侧缩放', () {
    /// 读收藏箱圆形按钮 Container 的边长按场景宽 390 计算：
    /// raw = 390×0.22 = 85.8 → clamp(84,92)=85.8 → ×actionScale。
    double boxButtonSize(WidgetTester tester) {
      final Container c = tester.widget<Container>(find
          .descendant(
            of: find.byKey(const Key('wish_scene_box_button')),
            matching: find.byType(Container),
          )
          .first);
      return c.constraints!.maxWidth;
    }

    testWidgets('手机 actionScale=0.8：三按钮按系数缩，85.8×0.8≈68.6dp ≥48',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const Size(390, 844),
        actionScale: 0.8,
      ));
      expect(boxButtonSize(tester), closeTo(85.8 * 0.8, 0.01),
          reason: '先 clamp(84,92)=85.8 再 ×0.8');
      expect(85.8 * 0.8, greaterThanOrEqualTo(48), reason: '热区底线');
    });

    testWidgets('iPad actionScale=1.0：按钮 85.8 逐字节不变（默认参数同）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const Size(390, 844),
        actionScale: 1.0,
      ));
      expect(boxButtonSize(tester), closeTo(85.8, 0.01));
    });
  });
}
