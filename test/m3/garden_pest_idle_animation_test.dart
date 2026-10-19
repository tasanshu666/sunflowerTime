/// 蝗虫（害虫浮标）**待机微动动画**单测（玄参 2026-10-19：
/// 「你说的给蝗虫做一个动画，你做一下，我看看效果」）。
///
/// 覆盖 3 件事：
///  ① **真的在动**：`pump(0)` 与 `pump(700ms)`（半个周期）下，动画根 `Transform`
///     的矩阵**不相同**（去掉 `repeat` 本断言必红）；
///  ② **隐藏页不耗电**：外层 `TickerMode(enabled: false)` 时，`pump(700ms)` 后矩阵
///     与 `pump(0)` **完全相同** —— 外壳 `IndexedStack` 保活的花园 tab 切走后
///     必须零帧回调（`SingleTickerProviderStateMixin` 的 Ticker 自动 mute）；
///  ③ **只有害虫动**：同一株只长杂草时不挂动画（草丛动了反而像渲染 bug）。
///
/// ⚠️ 全文件用**有界 `pump`**，不用 `pumpAndSettle`：本动画是无限往复
/// （`repeat(reverse: true)`），`pumpAndSettle` 会一直等到超时。花园页里本来就有
/// 「木牌呼吸」等无限动画（见 `one_click_batch_hint_center_test` 头注释），
/// 既有花园用例早已全部改成有界推进，本文件沿用同一纪律。
library garden_pest_idle_animation_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

Plant _plant({required bool weed, required bool pest}) {
  final DateTime t = DateTime(2026, 10, 19, 8);
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

/// 单盆宿主（240 宽的格子，与 `garden_interference_anchor_test` 同尺寸口径）。
///
/// [tickerEnabled] = false 时用 `TickerMode` 模拟「花园 tab 被切走」
/// （外壳对隐藏 tab 正是这么包的）。
Widget _harness(Plant plant, {bool tickerEnabled = true}) {
  return MaterialApp(
    home: Scaffold(
      body: TickerMode(
        enabled: tickerEnabled,
        child: Center(
          child: SizedBox(
            width: 240,
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
    ),
  );
}

/// 动画根 `Transform` 的矩阵指纹（字符串化便于 `equals` 断言）。
String _matrixOf(WidgetTester tester) {
  final Transform transform =
      tester.widget<Transform>(find.byKey(kPestIdleAnimKey));
  return transform.transform.storage
      .map((double v) => v.toStringAsFixed(6))
      .join(',');
}

/// 动画根 `Transform` 的纵向位移（浮动幅度，px）。
double _offsetY(WidgetTester tester) {
  final Transform transform =
      tester.widget<Transform>(find.byKey(kPestIdleAnimKey));
  return transform.transform.getTranslation().y;
}

void main() {
  testWidgets('① 有害虫 → 700ms 后动画矩阵与初始不同（真的在动）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_harness(_plant(weed: false, pest: true)));
    await tester.pump(); // 建立第一帧（controller value = 0）

    expect(find.byKey(kPestIdleAnimKey), findsOneWidget,
        reason: '有害虫必须挂着待机动画根节点');
    final String atZero = _matrixOf(tester);
    final double yAtZero = _offsetY(tester);

    // 700ms = 周期 1400ms 的一半：平移从 +2.5% 走到 0、旋转从 −4° 走到 0。
    await tester.pump(const Duration(milliseconds: 700));
    final String atHalf = _matrixOf(tester);

    expect(atHalf, isNot(equals(atZero)),
        reason: '🔴 半周期后矩阵必须变化（去掉 repeat / 只 setState 一次本断言必红）');
    expect(yAtZero, isNot(0.0), reason: '浮动必须静态也可测（首帧就带偏移）');
    expect(_offsetY(tester).abs(), lessThan(yAtZero.abs()),
        reason: '半周期时应回到居中位置（位移绝对值变小）');

    // 再推到第 2 个周期末（2800ms）→ 回到起点，证明是「循环」而非「跑一次就停」。
    await tester.pump(const Duration(milliseconds: 2100));
    expect(_offsetY(tester), closeTo(yAtZero, 0.2),
        reason: '两个完整周期后应回到起点（repeat(reverse: true) 的往复）');
  });

  testWidgets('② TickerMode(enabled: false) → 700ms 后矩阵与初始完全相同（隐藏页零耗电）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _harness(_plant(weed: false, pest: true), tickerEnabled: false),
    );
    await tester.pump();
    final String atZero = _matrixOf(tester);

    await tester.pump(const Duration(milliseconds: 700));
    expect(_matrixOf(tester), equals(atZero),
        reason: 'TickerMode 关闭时 Ticker 被 mute，动画帧推进不得改变视觉');

    await tester.pump(const Duration(milliseconds: 1400));
    expect(_matrixOf(tester), equals(atZero),
        reason: '更长时间也不得推进（否则切走的 tab 仍在耗电）');
  });

  testWidgets('③ 只有杂草 → 不挂待机动画（草丛保持静止）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_harness(_plant(weed: true, pest: false)));
    await tester.pump();

    expect(find.byKey(kPestIdleAnimKey), findsNothing,
        reason: '杂草是「植物的一部分」，动起来像渲染抖动');
  });
}
