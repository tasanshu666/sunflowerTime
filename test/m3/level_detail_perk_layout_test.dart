/// C77 · **称号详情卡属性徽章布局** widget 测试（设计 §7 / §12.3 TC-30..TC-34）。
///
/// 钉住五件事（**全部 RenderBox 真实度量**，不靠肉眼）：
///  · TC-30：9 行每行右侧**各含 1 枚**属性徽章（emoji + 属性名 + 数值，取自
///    `plant_perk.dart` 纯函数）——「💧 浇水 −1」…「⛏️ 铲除 +20」（C81 纯数值带符号）；
///  · TC-31：**C80/C81 改版**：底部图例区已删（`kLevelPerkLegendText` 常量已随删）——
///    断言图例文案**零残留**，且 **9 行统一**带阳光图标（C81 ②：不再按达等级条件渲染）；
///  · TC-32：**平板 `uiScaleOf=1.3` + `textScaler=1.6` 零溢出**（`takeException()==null`），
///    且内容框宽 ≤ [kLevelDetailCardMaxWidth] × `uiScaleOf`（C81 ⑥ 平板加宽）；
///  · TC-33：**无双重缩放** —— 卡内 `TextStyle.fontSize` 全是**字面量常量**（不 × `uiScaleOf`）；
///    阳光图标尺寸**乘** [uiScaleOf]（C61 图形纪律，反例对照）；
///  · TC-34：**手机档零回归**（`textScaler=1.0` / `uiScaleOf=1.0`）：行宽 == 卡内容宽、
///    无溢出，并**实测最宽属性徽章 < 行宽一半**（C78/C80 同排布局护栏）。
///
/// ⚠️ 屏幕尺寸一律经 `tester.view.physicalSize × devicePixelRatio` 设定（同
/// `tablet_adaptation_test.dart`）；平板文字经**唯一注入点** `applyTabletTextScaling`
/// 语义（本文件直接注入 `textScaler` 以精确取到红线值 1.6）。
/// C80：详情卡为 ConsumerWidget，夹具包 [ProviderScope]（默认 free 档）。
library level_detail_perk_layout_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    ProviderScope(
      child: MaterialApp(
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

      // emoji / 属性名 / 数值**全部**来自 plant_perk.dart 纯函数（页面不得自己拼）。
      final String emoji = perkEmojiOfTitleNode(node);
      final String name = perkNameOfTitleNode(node);
      final String shortText = perkShortTextOf(perkOfTitleNode(node));
      expect(emoji, isNotEmpty);
      expect(name, isNotEmpty);
      expect(shortText, isNotEmpty);
      expect(
        find.descendant(of: badge, matching: find.text(emoji)),
        findsOneWidget,
        reason: 'Lv.$node 属性徽章 emoji = $emoji',
      );
      expect(
        find.descendant(of: badge, matching: find.text(name)),
        findsOneWidget,
        reason: 'Lv.$node 属性徽章名称 = $name（C81 ④）',
      );
      expect(
        find.descendant(of: badge, matching: find.text(shortText)),
        findsOneWidget,
        reason: 'Lv.$node 属性徽章数值 = $shortText',
      );
    }
  });

  testWidgets('TC-31 C80/C81 图例区已删：图例文案零残留 + 9 行统一带阳光图标',
      (WidgetTester tester) async {
    await _openDetail(
      tester,
      totalMinutes: 900,
      logicalSize: const Size(390, 844),
    );
    // 图例零残留（P0-1；常量已删，文案不可能再出现）。新格式：属性名/数值**分列**。
    expect(find.textContaining('浇水−1'), findsNothing,
        reason: '图例已删（新格式：属性名与数值分列，无「浇水−1」合并串）');
    expect(find.textContaining('返还+20'), findsNothing,
        reason: '图例/C80 描述短语已删（C81 ③ 纯数值，无「返还+20」）');
    expect(find.textContaining('额外'), findsNothing, reason: 'C81 ③：描述词「额外」已删');
    expect(find.textContaining('消耗'), findsNothing, reason: 'C81 ③：描述词「消耗」已删');
    expect(find.textContaining('返还'), findsNothing, reason: 'C81 ③：描述词「返还」已删');
    // C81 ②：9 行**统一**带阳光图标（不再按达等级条件渲染）。
    for (final int node in kFocusLevelTitleLevels) {
      expect(
        find.descendant(
          of: find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node)),
          matching: find.byType(Image),
        ),
        findsOneWidget,
        reason: 'Lv.$node 统一带阳光图标（C81 ②）',
      );
    }
  });

  testWidgets('TC-32 平板 uiScaleOf=1.3 + textScaler=1.6：**零溢出** + 卡宽 ×1.3（C81 ⑥）',
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

    // C81 ⑥：内容框宽 = 手机基准 × uiScaleOf(1.3) = 403（加宽以容纳「时光大贤者」+属性名）。
    final double cardW =
        tester.getSize(find.byKey(FocusLevelDetailDialog.cardKey)).width;
    expect(cardW, closeTo(kLevelDetailCardMaxWidth * kTabletUiScale, 1.0),
        reason: '平板卡宽 = kLevelDetailCardMaxWidth × uiScaleOf(1.3)（C81 ⑥ 加宽）');
    expect(cardW, greaterThan(kLevelDetailCardMaxWidth),
        reason: '平板卡必须比手机基准宽（否则 Lv.40「时光大贤者」被 ellipsis 截断）');
    expect(cardW, lessThanOrEqualTo(834), reason: '卡宽不得超出屏宽');
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

    // C61 反例对照：阳光图标（图形素材）**必须**乘 uiScaleOf（12 × 1.3 = 15.6）。
    final Image sun = tester.widget<Image>(find
        .descendant(
          of: find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(1)),
          matching: find.byType(Image),
        )
        .first);
    expect(sun.width, closeTo(kLevelDetailPerkSunIconSize * kTabletUiScale, 0.01),
        reason: '阳光图标尺寸乘 uiScaleOf（C61：图形不吃 textScaler、吃 uiScale）');
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

    // C-3（C78 修订）：量最宽行内容（属性徽章），确认与称号同排后行内不换行溢出——
    // 旧「右列上限 96」常量已随阳光奖励列删除（C78）。
    double widest = 0;
    for (final int node in kFocusLevelTitleLevels) {
      final double w = tester
          .getSize(find.byKey(FocusLevelDetailDialog.titleRowPerkKeyOf(node)))
          .width;
      if (w > widest) widest = w;
    }
    // 实测最宽属性徽章（「−20」/「+20」+ emoji）应明显小于称号行可用宽的一半
    // （留给 5 字称号，防同排挤压触发 ellipsis）。
    expect(widest, lessThan(expectedRowW / 2),
        reason: '实测最宽属性徽章 ${widest.toStringAsFixed(1)} 应 < 行宽一半'
            '（C78 同排布局护栏；若超标则需缩小徽章字号）');
  });
}
