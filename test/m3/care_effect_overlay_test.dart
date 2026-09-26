/// 养护动效叠加层（[CareEffectOverlay]）widget 测试。
///
/// 覆盖要求：
///  1. 浇水 / 施肥两类 overlay 均**有限时长**——`pumpAndSettle()` 能正常返回
///     （无无限循环动画，否则会超时失败）；
///  2. 两类 overlay 渲染无异常（包含代码粒子层 / 含植物副本时均正常）；
///  3. 序列帧预留接口：传入 `frames` 也能有限渲染（资源缺失走 errorBuilder 兜底，不崩）。
///
/// 不依赖真实 DB / Riverpod，直接渲染组件本身。
library care_effect_overlay_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/care_effect_overlay.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

Plant _seed() => Plant(
      id: 'p1',
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: DateTime(2026, 9, 24, 8),
      growthProgress: 0.1,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: DateTime(2026, 9, 24, 8),
    );

/// 把 [CareEffectOverlay] 装进固定尺寸的盒子渲染并 pumpAndSettle。
///
/// 返回（不返回，仅驱动）——pumpAndSettle 成功返回即证明动画有限、可结束。
Future<void> _pumpOverlay(
  WidgetTester tester,
  CareEffectType type, {
  Plant? plant,
  List<String>? frames,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 100,
            height: 140,
            child: CareEffectOverlay(
              type: type,
              plant: plant,
              species: plant == null ? null : _sunflower,
              frames: frames,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('浇水 overlay：有限时长、粒子层渲染无异常',
      (WidgetTester tester) async {
    await _pumpOverlay(tester, CareEffectType.water);
    // 代码粒子层用 CustomPaint 绘制；存在即说明渲染正常。
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('施肥 overlay：有限时长、粒子层渲染无异常',
      (WidgetTester tester) async {
    await _pumpOverlay(tester, CareEffectType.fertilize);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('overlay 含植物副本（带 plant）时正常渲染无异常',
      (WidgetTester tester) async {
    await _pumpOverlay(tester, CareEffectType.fertilize, plant: _seed());
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('序列帧预留接口：传入 frames 也能有限渲染（资源缺失走 errorBuilder）',
      (WidgetTester tester) async {
    // 本轮不新增 png 资产，传入的帧路径不存在 → errorBuilder 兜底空，不抛异常，
    // 且动画仍有限（pumpAndSettle 正常返回）。
    await _pumpOverlay(
      tester,
      CareEffectType.water,
      frames: const <String>['assets/plants/fx_water_01.png'],
    );
  });
}
