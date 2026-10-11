/// 花园干扰物（杂草 / 害虫）浮标的**布局度量回归测试**。
///
/// ## 为什么需要这份测试
/// 2026-10-09 画布 1200→1720 加宽（C40 全局等盆）后，盆在画布内占比从 0.667 降到
/// 0.465，而干扰物浮标还是「画布比例锚点 + 定长尺寸」（left 0.17 / 60px）——
/// 真机实证杂草跑到盆外左上角、且比盆还大（玄参 2026-10-11 反馈）。
/// 修法 = 尺寸与横向锚点全部改**盆身相对**表达（常量收口 `prd_params.dart`；
/// 2026-10-11 画布 1720→1440 收窄后公式自动跟随，盆占比现为 800/1440≈0.556）。
///
/// 本测试锁三条产品行为：
///  1. 浮标尺寸随盆**等比缩放**（格宽翻倍 → 浮标近似翻倍），任何未来的画布/列数
///     调整都不会再让它「固定大小错位」；
///  2. 尺寸公式 = 格内美术宽 × (800/1440) × 比例（杂草 0.83 / 害虫 0.72），
///     与 2026-10-03 定稿的视觉比例一致；
///  3. 横向锚点贴盆缘：杂草左缘 = 盆左缘、害虫右缘越出盆右缘（kPestRightFraction）。
///
/// 纯 widget 测试，不依赖数据库与 Riverpod。
library garden_interference_anchor_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

Plant _plant({required bool weed, required bool pest}) {
  final DateTime t = DateTime(2026, 10, 11, 8);
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: t,
    growthProgress: 0.4,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: t,
    weedAt: weed ? t : null,
    pestAt: pest ? t : null,
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

Widget _harness({required double cellWidth, required Plant plant}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: cellWidth,
          child: GardenPot(
            plant: plant,
            species: _sunflower,
            onTap: () {},
            onClearWeed: () {},
            onClearPest: () {},
          ),
        ),
      ),
    ),
  );
}

Image? _glyphImage(WidgetTester tester, String assetName) {
  final Iterable<Image> images = tester.widgetList<Image>(
    find.byWidgetPredicate(
      (Widget w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == assetName,
    ),
  );
  return images.isEmpty ? null : images.first;
}

/// 捕获浮标 Image 及其所属 Positioned（必须在同一棵树内当场捕获）。
({Image glyph, Positioned pos})? _capture(WidgetTester tester, String assetName) {
  final Image? glyph = _glyphImage(tester, assetName);
  if (glyph == null) return null;
  final Positioned pos = tester.widget<Positioned>(
    find.ancestor(
      of: find.byWidget(glyph),
      matching: find.byType(Positioned),
    ).first,
  );
  return (glyph: glyph, pos: pos);
}

/// 格内美术框宽（GardenPot 内 LayoutBuilder 拿到的宽 − 横向内边距 2×2）。
double _artWidthOf(double cellWidth) => (cellWidth - 4) * kGardenArtWidthRatio;

void main() {
  testWidgets('杂草浮标：尺寸随盆等比 + 左缘贴盆左缘', (WidgetTester tester) async {
    const double narrowCell = 120;
    const double wideCell = 240;

    await tester.pumpWidget(_harness(
      cellWidth: narrowCell,
      plant: _plant(weed: true, pest: false),
    ));
    final ({Image glyph, Positioned pos})? narrow =
        _capture(tester, 'assets/garden/weed.png');
    expect(narrow, isNotNull, reason: '有杂草必须渲染杂草图');

    await tester.pumpWidget(_harness(
      cellWidth: wideCell,
      plant: _plant(weed: true, pest: false),
    ));
    final Image? wideWeed = _glyphImage(tester, 'assets/garden/weed.png');
    expect(wideWeed, isNotNull);

    // ① 等比：格宽翻倍 → 浮标近似翻倍（容差 0.05：格宽含固定 4px 内边距，
    //    (240-4)/(120-4) ≈ 2.034；精确公式由 ② 锁定）
    expect(wideWeed!.width! / narrow!.glyph.width!, closeTo(2.0, 0.05),
        reason: '杂草必须随盆等比缩放，不许再固定 px');

    // ② 公式：宽 = 美术框宽 × (800/1440) × 0.83
    final double expectNarrow =
        _artWidthOf(narrowCell) * kPlantPotWidthFraction * kWeedSizeToPotRatio;
    expect(narrow.glyph.width!, closeTo(expectNarrow, 0.5));

    // ③ 锚点：左缘 = 盆左缘（美术框宽 × (1-800/1440)/2）
    expect(narrow.pos.left,
        closeTo(_artWidthOf(narrowCell) * kWeedLeftFraction, 0.5));
  });

  testWidgets('害虫浮标：尺寸随盆等比 + 高按素材宽高比 30:52', (WidgetTester tester) async {
    const double narrowCell = 120;
    const double wideCell = 240;

    await tester.pumpWidget(_harness(
      cellWidth: narrowCell,
      plant: _plant(weed: false, pest: true),
    ));
    final ({Image glyph, Positioned pos})? narrow =
        _capture(tester, 'assets/garden/pest.png');
    expect(narrow, isNotNull, reason: '有害虫必须渲染害虫图');
    final double narrowW = narrow!.glyph.width!;
    final double narrowH = narrow.glyph.height!;

    await tester.pumpWidget(_harness(
      cellWidth: wideCell,
      plant: _plant(weed: false, pest: true),
    ));
    final Image? widePest = _glyphImage(tester, 'assets/garden/pest.png');
    expect(widePest, isNotNull);
    expect(widePest!.width! / narrowW, closeTo(2.0, 0.05),
        reason: '害虫必须随盆等比缩放');

    // 公式：宽 = 美术框宽 × (800/1440) × 0.72；高 = 宽 × 30/52
    final double expectW =
        _artWidthOf(narrowCell) * kPlantPotWidthFraction * kPestSizeToPotRatio;
    expect(narrowW, closeTo(expectW, 0.5));
    expect(narrowH, closeTo(expectW * 30 / 52, 0.5));

    // 锚点：右缘越出盆右缘（右距 = kPestRightFraction × 美术框宽）
    expect(narrow.pos.right,
        closeTo(_artWidthOf(narrowCell) * kPestRightFraction, 0.5));
  });
}
