/// 花园花盆网格的**布局度量测试**（2026-09-23 花园显示改造）。
///
/// ## 为什么需要这份测试
/// 花园从「纵向卡片列表」改成「草地 + 3 列花盆网格」后，最大风险是**格子装不下内容**
/// （植物 + 花盆 + 进度条 + 标签），在窄屏上会报 RenderFlex overflow ——
/// 这类问题是编译与逻辑单测**都抓不到**的（编译完全合法），且我无法截图自查。
///
/// 因此这里直接渲染生产组件 [GardenGrid]（不在测试里复刻布局参数），度量真实坐标：
///  1. 三种窄/常用屏宽下都不抛异常（overflow 会以异常形式冒出来）；
///  2. 3 列网格第一行确实 3 格、横坐标递增、纵坐标一致；
///  3. 每格内容都在格子范围内（底部标签不越界）；
///  4. 「加盆」格的三态文案正确（够钱带价 / 不够钱写还差多少）。
///
/// ## 二次改造（2026-09-23）后的新口径
/// 美术图统一为 1200×2000 画布且**植物图自带花盆** → 代码只渲染一张图、不再叠花盆。
/// 布局度量据此改为：空盆与有植物盆的**图片框尺寸一致、底部对齐、不被改小**；
/// 有植物格内**只有一个 Image**（不再叠第二个盆）。
///
/// 纯 widget 测试，不依赖数据库与 Riverpod（花盆组件本身无业务依赖）。
library garden_pot_layout_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

/// 造一株测试用植物（字段取最小必需集）。
Plant _plant({
  String id = 'p1',
  int potIndex = 0,
  PlantStage stage = PlantStage.sprout,
  PlantStatus status = PlantStatus.growing,
  double progress = 0.4,
}) {
  final DateTime t = DateTime(2026, 9, 23, 8);
  return Plant(
    id: id,
    speciesId: 'species_sunflower',
    potIndex: potIndex,
    stage: stage,
    stageStartedAt: t,
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: t,
  );
}

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 宿主：给定逻辑屏宽，渲染 [GardenGrid]。
///
/// 尺寸刻意与花园页一致：页 ListView padding 12 + 草地 padding 左右各 10 → 网格可用宽 = 屏宽 - 44。
Widget _harness({required double screenWidth, required List<Widget> cells}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: screenWidth - 44,
          child: GardenGrid(cells: cells),
        ),
      ),
    ),
  );
}

/// 模拟手机屏（逻辑像素）。
void _setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('花盆网格 · 不溢出（多屏宽）', () {
    // 320 = 最窄常见屏；360 = 主流 Android；390 = iPhone 常规宽
    for (final double w in <double>[320, 360, 390]) {
      testWidgets('屏宽 ${w.toInt()}：3 列 + 多个花盆不抛异常', (WidgetTester tester) async {
        _setScreen(tester, w, 780);
        await tester.pumpWidget(_harness(
          screenWidth: w,
          cells: <Widget>[
            GardenPot(
              plant: _plant(potIndex: 0),
              species: _sunflower,
              onTap: () {},
            ),
            EmptyPot(potIndex: 1, onTap: () {}),
            GardenPot(
              plant: _plant(
                id: 'p3',
                potIndex: 2,
                status: PlantStatus.wilting,
                progress: 0.93,
              ),
              species: _sunflower,
              onTap: () {},
            ),
            ExpandPotSlot(
              cost: 400,
              shortfall: -100,
              busy: false,
              onTap: () {},
            ),
          ],
        ));
        await tester.pump();

        // overflow / unbounded 之类会以异常形式出现；为 null 才算布局成立。
        expect(tester.takeException(), isNull);
        expect(find.byType(GardenPot), findsNWidgets(2));
        expect(find.byType(EmptyPot), findsOneWidget);
        expect(find.byType(ExpandPotSlot), findsOneWidget);
        // 加盆格**只显示加号**：格内不得再出现第二个花盆（Image）。
        expect(
          find.descendant(
            of: find.byType(ExpandPotSlot),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
      });
    }
  });

  group('花盆网格 · 空盆与有植物盆等大 + 底部对齐（本次改造的主要目标）', () {
    testWidgets('空盆与有植物盆的图片框尺寸一致、底部对齐、且足够大',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          GardenPot(plant: _plant(potIndex: 0), species: _sunflower, onTap: () {}),
          EmptyPot(potIndex: 1, onTap: () {}),
        ],
      ));
      // 植物美术图经 FutureBuilder 解析资产清单后才出现（需等一帧以后）。
      await tester.pumpAndSettle();

      // growthScale=0 → 盆不随进度缩放，图片框内不再内缩：
      // 有植物格内唯一的 Image 外框即「图片框」，可与空盆的 pot.png 图片框**直接对量**。
      final Finder filledImg = find.descendant(
        of: find.byType(GardenPot),
        matching: find.byType(Image),
      );
      final Finder emptyImg = find.descendant(
        of: find.byType(EmptyPot),
        matching: find.byType(Image),
      );
      expect(filledImg, findsOneWidget);
      expect(emptyImg, findsOneWidget);

      // 以格子外框为基准（而非写死数值），避免十字间距微调就误红。
      final Rect cell = tester.getRect(find.byType(GardenPot));
      final Rect filled = tester.getRect(filledImg);
      final Rect empty = tester.getRect(emptyImg);

      // ① 图片框尺寸完全一致（三类格子可用宽相同 + 同一组 _artWidthRatio/_artAspectRatio）。
      expect(empty.width, closeTo(filled.width, 0.01));
      expect(empty.height, closeTo(filled.height, 0.01));
      // ② 底部对齐：同一行 → 同顶同高 → 两图片框底边相同，且都在格内。
      expect(empty.bottom, closeTo(filled.bottom, 0.5));
      expect(filled.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
      expect(empty.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
      // ③ 盆真的够大：图片框宽 ≥ 格宽 × 0.8（锁住「不许再被改小」）。
      expect(filled.width, greaterThanOrEqualTo(cell.width * 0.8));
      expect(empty.width, greaterThanOrEqualTo(cell.width * 0.8));
      // ④ 图片框宽 = 格内宽 × 0.86（格内宽 = 格宽 - 2 × 横向内边距 2）。
      expect(filled.width, closeTo((cell.width - 4) * 0.86, 0.5));
      // ⑤ 画布宽高比锁死 1200:2000 = 5/3（美术图统一画布）。
      expect(filled.height / filled.width, closeTo(5 / 3, 0.002));
    });

    testWidgets('有植物格内只有 1 个 Image（不再叠第二个花盆）',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          GardenPot(plant: _plant(potIndex: 0), species: _sunflower, onTap: () {}),
        ],
      ));
      await tester.pumpAndSettle();

      // 一格一图：植物图自带花盆，代码不再叠 pot.png。
      expect(
        find.descendant(
          of: find.byType(GardenPot),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });
  });

  group('花盆网格 · 真实坐标', () {
    testWidgets('第一行 3 格：横坐标递增、纵坐标一致', (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          GardenPot(plant: _plant(potIndex: 0), species: _sunflower, onTap: () {}),
          GardenPot(
            plant: _plant(id: 'p2', potIndex: 1),
            species: _sunflower,
            onTap: () {},
          ),
          GardenPot(
            plant: _plant(id: 'p3', potIndex: 2),
            species: _sunflower,
            onTap: () {},
          ),
        ],
      ));
      await tester.pump();

      final List<Rect> rects = <Rect>[
        for (int i = 0; i < 3; i++)
          tester.getRect(find.byType(GardenPot).at(i)),
      ];
      // 同一行 → 顶边一致
      expect(rects[0].top, rects[1].top);
      expect(rects[1].top, rects[2].top);
      // 从左到右 → 左边界递增且互不重叠
      expect(rects[0].left, lessThan(rects[1].left));
      expect(rects[1].left, lessThan(rects[2].left));
      expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
      expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
      // 3 格都在屏内
      expect(rects[2].right, lessThanOrEqualTo(360.0));
    });

    testWidgets('第 4 格换行到第二行', (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          for (int i = 0; i < 4; i++)
            GardenPot(
              plant: _plant(id: 'p$i', potIndex: i),
              species: _sunflower,
              onTap: () {},
            ),
        ],
      ));
      await tester.pump();

      final Rect first = tester.getRect(find.byType(GardenPot).at(0));
      final Rect fourth = tester.getRect(find.byType(GardenPot).at(3));
      // 第 4 格回到最左列，且在第一行下方
      expect(fourth.left, first.left);
      expect(fourth.top, greaterThan(first.top));
    });

    testWidgets('格内内容不越界：底部标签在格子下沿之内', (WidgetTester tester) async {
      _setScreen(tester, 320, 780); // 最窄屏，最容易挤爆
      await tester.pumpWidget(_harness(
        screenWidth: 320,
        cells: <Widget>[
          GardenPot(
            plant: _plant(status: PlantStatus.bloomed, progress: 1.0),
            species: _sunflower,
            onTap: () {},
          ),
        ],
      ));
      await tester.pump();

      final Rect cell = tester.getRect(find.byType(GardenPot));
      final Rect label = tester.getRect(find.text('向日葵 · 开花'));
      expect(label.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
      expect(label.left, greaterThanOrEqualTo(cell.left - 0.5));
      expect(label.right, lessThanOrEqualTo(cell.right + 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('进度条位于格内下半部（在花盆图下方）', (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          GardenPot(
            plant: _plant(progress: 0.5),
            species: _sunflower,
            onTap: () {},
          ),
        ],
      ));
      await tester.pump();

      final Rect cell = tester.getRect(find.byType(GardenPot));
      // 进度条位于格内下半部（盆图下方），保证「盆 + 条」的层级不颠倒
      final Rect bar = tester.getRect(find.byType(LinearProgressIndicator));
      expect(bar.top, greaterThan(cell.top + cell.height * 0.5));
      expect(bar.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
    });
  });

  group('加盆格的三态文案', () {
    testWidgets('阳光够 → 带价格、可点', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          ExpandPotSlot(
            cost: 400,
            shortfall: -100,
            busy: false,
            onTap: () => tapped = true,
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('加盆 · 400☀'), findsOneWidget);
      await tester.tap(find.byType(ExpandPotSlot));
      expect(tapped, isTrue);
    });

    testWidgets('阳光不足 → 写还差多少；**点击仍回调**（分因提示由页面层兜底，不静默）',
        (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          ExpandPotSlot(
            cost: 400,
            shortfall: 173,
            busy: false,
            onTap: () => tapped = true,
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('还差 173☀'), findsOneWidget);
      // ⚠️ 2026-09-24 修订（玄参真机反馈「点了没反应」）：阳光不足**不再拦点击**，
      // 回调照常触发；「阳光不足，还差 N ☀」的分因提示由 GardenPage._confirmAndExpand
      // 兜底弹出。旧口径 onTap: null 会让点击静默失败，等于 UI 层把失败藏起来。
      await tester.tap(find.byType(ExpandPotSlot));
      expect(tapped, isTrue);
    });

    testWidgets('busy 期间即使够钱也不可点（防连点绕过扣费）', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(_harness(
        screenWidth: 360,
        cells: <Widget>[
          ExpandPotSlot(
            cost: 400,
            shortfall: -100,
            busy: true,
            onTap: () => tapped = true,
          ),
        ],
      ));
      await tester.pump();
      await tester.tap(find.byType(ExpandPotSlot));
      expect(tapped, isFalse);
    });
  });

  group('状态色与标签（一眼看出哪盆要救）', () {
    testWidgets('枯萎写「快救回」、死亡写「已枯萎」、开花写「开花」', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(
        screenWidth: 390,
        cells: <Widget>[
          GardenPot(
            plant: _plant(id: 'a', potIndex: 0, status: PlantStatus.wilting),
            species: _sunflower,
            onTap: () {},
          ),
          GardenPot(
            plant: _plant(id: 'b', potIndex: 1, status: PlantStatus.dead),
            species: _sunflower,
            onTap: () {},
          ),
          GardenPot(
            plant: _plant(id: 'c', potIndex: 2, status: PlantStatus.bloomed),
            species: _sunflower,
            onTap: () {},
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('向日葵 · 快救回'), findsOneWidget);
      expect(find.text('向日葵 · 已枯萎'), findsOneWidget);
      expect(find.text('向日葵 · 开花'), findsOneWidget);
    });
  });
}
