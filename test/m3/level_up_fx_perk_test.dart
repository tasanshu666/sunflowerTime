/// C77 · **升级演出「本称号专属」追加行** widget 测试（设计 §8 / §12.3 TC-35..TC-37）。
///
/// 钉住三件事：
///  · TC-35：**称号节点**演出 + `perkOfLevel(shownLevel).isNone == false`
///    → 出现「本称号专属：…」（文案由 [perkSummaryTextOf] + 模板单点装配）；
///  · TC-36：**普通升级**演出 → **不出现**该行（无新称号，即便 `perkOfLevel(4)` 非空）；
///  · TC-37：一次跨级 Lv.19→Lv.25 → 追加行取**最高**称号（Lv.25 守时小星使）的**累积**属性。
///
/// ⚠️ 直接 `pumpWidget(LevelUpFxOverlay(...))` 独立渲染（与 `level_up_fx_overlay_test.dart`
/// 同款）；`frames` 传空 → 走静态徽章兜底，不依赖真机素材。
library level_up_fx_perk_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';

const List<String> _kNoFrames = <String>[];

/// 称号节点 Lv.5（专注小苗苗，+5）。
FocusLevelSettleResult _titleNode5() => const FocusLevelSettleResult(
      currentLevel: 5,
      settledLevel: 5,
      settledBefore: 4,
      granted: <LevelGrant>[LevelGrant(level: 5, amount: 5)],
      totalSunlight: 5,
      firstUseSilent: false,
    );

/// 普通升级 Lv.4（非称号节点）：零阳光、**granted 为空**但 leveledUp。
FocusLevelSettleResult _ordinary() => const FocusLevelSettleResult(
      currentLevel: 4,
      settledLevel: 4,
      settledBefore: 3,
      granted: <LevelGrant>[],
      totalSunlight: 0,
      firstUseSilent: false,
    );

/// 一次跨级：Lv.19 → Lv.25（新解锁节点 20 / 25，最高 = Lv.25）。
FocusLevelSettleResult _cross() => const FocusLevelSettleResult(
      currentLevel: 25,
      settledLevel: 25,
      settledBefore: 19,
      granted: <LevelGrant>[
        LevelGrant(level: 20, amount: 11),
        LevelGrant(level: 25, amount: 13),
      ],
      totalSunlight: 24,
      firstUseSilent: false,
    );

Future<void> _pump(WidgetTester tester, FocusLevelSettleResult result) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LevelUpFxOverlay(
          result: result,
          frames: _kNoFrames,
          onComplete: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('TC-35 称号节点 + perk 非空 → 出现「本称号专属：…」（单点摘要文案）',
      (WidgetTester tester) async {
    await _pump(tester, _titleNode5());

    final PlantPerk perk = perkOfLevel(5);
    expect(perk.isNone, isFalse, reason: 'Lv.5 已含 Lv.1/Lv.5 两节点属性');
    final String expected = kLevelUpFxPerkTemplate.replaceAll(
      '{text}',
      perkSummaryTextOf(perk),
    );
    expect(find.text(expected), findsOneWidget,
        reason: '追加行由 perkSummaryTextOf + 模板单点装配（不页面拼 9 种）');
    // 主文案仍是最高新称号。
    expect(find.text('Lv.5 · ${titleOfLevel(5)}'), findsOneWidget);
  });

  testWidgets('TC-36 普通升级 → **不出现**「本称号专属」行（无新称号，即使 perk 非空）',
      (WidgetTester tester) async {
    await _pump(tester, _ordinary());

    // 前提：Lv.4 的累积属性并非 none（含 Lv.1 浇水 −1），但因为是**普通升级**
    // （isTitleNode=false）该行必须被闸门挡住。
    expect(perkOfLevel(4).isNone, isFalse);
    expect(find.textContaining('本称号专属'), findsNothing,
        reason: '普通升级无新称号，不得冒充称号演出');
    expect(find.text(kLevelUpFxLevelTitle), findsOneWidget);
  });

  testWidgets('TC-37 多级跨档 Lv.19→Lv.25 → 追加行取**最高**称号（守时小星使）累积属性',
      (WidgetTester tester) async {
    await _pump(tester, _cross());

    // 主文案 = 最高新称号节点 Lv.25。
    expect(find.text('Lv.25 · ${titleOfLevel(25)}'), findsOneWidget,
        reason: '演出主文案取本轮最高新称号');
    // 追加行 = perkOfLevel(25)（≤Lv.25 的**全部**已解锁节点属性累积）摘要。
    final String expected = kLevelUpFxPerkTemplate.replaceAll(
      '{text}',
      perkSummaryTextOf(perkOfLevel(25)),
    );
    expect(find.text(expected), findsOneWidget,
        reason: '追加行随 shownLevel=25 取累积属性（与域层同源）');
  });
}
