/// C77 · **称号详情卡属性徽章布局** widget 测试（设计 §7 / §12.3 TC-30..TC-34）。
///
/// 钉住五件事（**全部 RenderBox 真实度量**，不靠肉眼）：
///  · TC-30：9 行每行右侧**各含 1 枚**属性徽章（emoji + 增减量，取自 `plant_perk.dart`
///    纯函数）——「💧 −1」…「⛏️ +20」；
///  · TC-31：卡底 **9 条 emoji 图例**存在（单点常量 [kLevelPerkLegendText]）；
///  · TC-32：**平板 `uiScaleOf=1.3` + `textScaler=1.6` 零溢出**（`takeException()==null`），
///    且内容框宽 ≤ [kLevelDetailCardMaxWidth]（310）；
///  · TC-33：**无双重缩放** —— 卡内 `TextStyle.fontSize` 全是**字面量常量**（不 × `uiScaleOf`）；
///  · TC-34：**手机档零回归**（`textScaler=1.0` / `uiScaleOf=1.0`）：行宽 == 卡内容宽、
///    无溢出，并**实测最宽属性徽章**回填 [kLevelDetailPerkRightColMaxWidth]（设计 §7.4 C-3）。
///
/// ⚠️ 屏幕尺寸一律经 `tester.view.physicalSize × devicePixelRatio` 设定（同
/// `tablet_adaptation_test.dart`）；平板文字经**唯一注入点** `applyTabletTextScaling`
/// 语义（本文件直接注入 `textScaler` 以精确取到红线值 1.6）。
library level_detail_perk_layout_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 设定逻辑屏幕尺寸（物理像素 = 逻辑 × 3，与既有护栏一致）。
void _setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 立泵徽章并点开详情卡；[textScale] 经 `MaterialApp.builder` 注入到**整棵子树**
/// （含 `showDialog` 弹出的路由 —— 路由挂在 Navigator 之下，能继承本 MediaQuery）。
///
/// [seenScale] 回吐该子树实际生效的 `uiScaleOf`（证明平板/手机档判定）。
Future<void> _openDetail(
  WidgetTester tester, {
  required double totalMinutes,
  required Size logicalSize,
  double textScale = 1.0,
  void Function(double uiScale)? seenScale,
}) async {
  _setScreen(tester, logicalSize.width, logicalSize.height);
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) {
        final Widget content = child ?? const SizedBox.shrink();
        seenScale?.call(uiScaleOf(context));
        final MediaQueryData mq =
            MediaQuery.maybeOf(context) ?? const MediaQueryData();
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
          child: content,
        );
      },
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FocusLevelBadge(
            progress: progressOf(totalMinutes),
            totalMinutes: totalMinutes,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TC-30 详情卡 9 行**各含 1 枚**属性徽章（emoji + 增减量，单点函数）',
      (WidgetTester tester) async {
    // Lv.7：已解锁 Lv.1 / Lv.5 两节点，其余 7 行未解锁（徽章灰显但仍存在）。
    await _openDetail(
      tester,
      totalMinutes: 900,
      logicalSize: const Size(390, 844),
    );

    expect(kFocusLevelTitleLevels.length, 9);
    for (final int node in kFocusLevelTitleLevels) {
      final Finder badge =
          find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node));
      expect(badge, findsOneWidget, reason: 'Lv.$node 行必须有属性徽章');

      // emoji 与增减量**全部**来自 plant_perk.dart 纯函数（页面不得自己拼）。
      final String emoji = perkEmojiOfTitleNode(node);
      final String shortText = perkShortTextOf(perkOfTitleNode(node));
      expect(emoji, isNotEmpty);
      expect(shortText, isNotEmpty);
      expect(
        find.descendant(of: badge, matching: find.text(emoji)),
        findsOneWidget,
        reason: 'Lv.$node 属性徽章 emoji = $emoji',
      );
      expect(
        find.descendant(of: badge, matching: find.text(shortText)),
        findsOneWidget,
        reason: 'Lv.$node 属性徽章增减量 = $shortText',
      );
    }
  });

  testWidgets('TC-31 卡底 9 条 emoji 图例存在（单点常量 kLevelPerkLegendText）',
      (WidgetTester tester) async {
    await _openDetail(
      tester,
      totalMinutes: 900,
      logicalSize: const Size(390, 844),
    );
    expect(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.dialogKey),
        matching: find.text(kLevelPerkLegendText),
      ),
      findsOneWidget,
      reason: '图例走单点常量渲染，页面不拼接',
    );
  });

  testWidgets('TC-32 平板 uiScaleOf=1.3 + textScaler=1.6：**零溢出** + 内容框宽 ≤ 310',
      (WidgetTester tester) async {
    double seenScale = -1;
    await _openDetail(
      tester,
      // 834×1112 → shortestSide 834 ≥ 600 → 平板。
      totalMinutes: 900,
      logicalSize: const Size(834, 1112),
      textScale: 1.6,
      seenScale: (double s) => seenScale = s,
    );

    expect(seenScale, kTabletUiScale, reason: '本档确为平板（uiScaleOf=1.3）');

    // 🔴 零溢出（C-4）：行用 minHeight:44，1.6× 撑高时行随内容增高，不 RenderFlex overflow。
    expect(tester.takeException(), isNull,
        reason: 'textScaler=1.6 + uiScaleOf=1.3 下不得有任何 overflow');

    // C-2：内容框宽 ≤ 310（Dialog 外层铺满屏，量内容框才有意义）。
    final double cardW =
        tester.getSize(find.byKey(FocusLevelDetailDialog.cardKey)).width;
    expect(cardW, lessThanOrEqualTo(kLevelDetailCardMaxWidth + 0.01),
        reason: '卡内容框宽必须 ≤ kLevelDetailCardMaxWidth(310)');
    expect(cardW, lessThanOrEqualTo(834),
        reason: '卡宽不得超出屏宽');

    // 图例在 1.6× 下必然换行，但仍在卡内（不溢出）。
    expect(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.dialogKey),
        matching: find.text(kLevelPerkLegendText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TC-33 无双重缩放：卡内字号为**字面量常量**（不 × uiScaleOf）',
      (WidgetTester tester) async {
    await _openDetail(
      tester,
      totalMinutes: 900,
      logicalSize: const Size(834, 1112),
      textScale: 1.6,
    );

    // 称号行：fontSize 必须 == kLevelDetailRowFontSize（若误乘 1.3 → 16.9）。
    final Text rowText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowKeyOf(1)),
        matching: find.text(titleOfLevel(1)),
      ),
    );
    expect(rowText.style?.fontSize, kLevelDetailRowFontSize,
        reason: '称号行字号为字面量（不乘 uiScaleOf，C65 教训）');

    // 属性徽章增减量字号 == kLevelDetailPerkFontSize。
    final Text perkText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)),
        matching: find.text(perkShortTextOf(perkOfTitleNode(1))),
      ),
    );
    expect(perkText.style?.fontSize, kLevelDetailPerkFontSize,
        reason: '属性徽章字号为字面量（不乘 uiScaleOf）');

    // 底部图例字号 == kLevelDetailLegendFontSize。
    final Text legend = tester.widget<Text>(find.text(kLevelPerkLegendText));
    expect(legend.style?.fontSize, kLevelDetailLegendFontSize,
        reason: '图例字号为字面量（不乘 uiScaleOf）');
  });

  testWidgets('TC-34 手机档零回归：uiScaleOf=1.0、行宽 == 卡内容宽、实测最宽属性徽章',
      (WidgetTester tester) async {
    double seenScale = -1;
    await _openDetail(
      tester,
      totalMinutes: 900,
      logicalSize: const Size(390, 844),
      textScale: 1.0,
      seenScale: (double s) => seenScale = s,
    );

    expect(seenScale, 1.0, reason: '手机档 uiScaleOf 必须 == 1.0（零回归前提）');
    expect(tester.takeException(), isNull);

    // 「行宽不变」：行宽 == 卡内容宽（310 − 2×pad 20 = 270）。
    const double expectedRowW = kLevelDetailCardMaxWidth - kLevelDetailCardPad * 2;
    for (final int node in kFocusLevelTitleLevels) {
      final double w =
          tester.getSize(find.byKey(FocusLevelDetailDialog.titleRowKeyOf(node)))
              .width;
      expect(w, closeTo(expectedRowW, 0.01),
          reason: 'Lv.$node 行宽应为卡内容宽 $expectedRowW（手机档不变）');
    }

    // C-3：逐行量属性徽章宽，`kLevelPerkRightColMaxWidth` 必须**足够**（不触发钳制）。
    double widest = 0;
    for (final int node in kFocusLevelTitleLevels) {
      final double w = tester
          .getSize(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node)))
          .width;
      if (w > widest) widest = w;
    }
    // Q-G 实测回填（设计 §7.4）：手机档最坏行（3 字符「+20」+ emoji）实测 ≈ 47.25
    // < 96 ⇒ `kLevelDetailPerkRightColMaxWidth = 96` 足够，无需下调（保留 provisional 96）。
    expect(widest, lessThan(kLevelDetailPerkRightColMaxWidth),
        reason: '实测最宽属性徽章 $widest < 上限 $kLevelDetailPerkRightColMaxWidth'
            '（回填依据；若接近上限则需按设计 §7.4 调小图例字号）');
  });
}
