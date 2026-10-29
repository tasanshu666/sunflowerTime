/// F163：**花园养护卡「铲除」标签折行 + 「施肥增幅」被省略号吃掉** 守卫。
///
/// ## 背景（玄参 2026-10-29 小米 14 Pro 截图）
/// 养护卡右上角垃圾桶下方的红字 `Remove` 折成两行，**末行只剩一个孤零零的 `e`**
/// （`Remov` / `e`）；下方并排按钮里 `Fertilize +0.8%` 被截成 `Fertilize +...`
/// —— 恰好把「施肥能涨多少」这个孩子最该看到的信息吃掉了。
///
/// ## 根因（与 F161/F162 同一族：容器给了死宽度，文字却不许收）
///  · `Remove`：铲除列是 `SizedBox(width: 44)`（命中区硬要求），11px 文字只有 ~40pt
///    可用 —— 真实字体在系统字号 1.0 下刚好卡线，字号一调大就折行；
///  · `Fertilize +0.8%`：两个按钮各占一半（小米 14 Pro 档 ≈ 139pt），扣掉内边距
///    与图标后文字区只剩 ~101pt，英文标签需要 ~104pt → `maxLines:1 + ellipsis`
///    直接吐省略号。中文「施肥 +3%」只有 7 个字符，所以从没暴露。
///
/// ## 修法
/// 两处都改「单行 + `FittedBox(scaleDown)`」：宁可整词等比缩小，也绝不折行、
/// 绝不吐省略号。中文字号足够，缩放比例 = 1.0，视觉零回归。
///
/// ## 守卫口径
///  · 卡宽不是拍脑袋：`392（小米 14 Pro 逻辑宽）− 24×2（Dialog insetPadding）
///    − 12×2（养护卡容器内边距）` = **320**，与真机截图实测一致；
///  · 断「行数」用 `RenderParagraph.computeLineMetrics()`（**不用像素断行**，
///    测试字体是等宽方块，与真机字宽不同）；
///  · 断「有没有被截」用 `RenderParagraph.didExceedMaxLines`；
///  · 再补一条几何断言：标签的**实际屏幕矩形**必须落在自己那颗按钮之内
///    （`FittedBox` 的缩放会体现在 `getRect` 里，这条能抓到「缩了但缩不够」）。
library f163_plant_card_long_label_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

/// 小米 14 Pro 逻辑宽（1080 / 2.75）。
const double _kPhoneLogicalWidth = 392;

/// 养护卡在手机档的真实卡宽：Dialog 左右各留 24，容器内边距左右各 12。
const double _kPhoneCardWidth = _kPhoneLogicalWidth - 24 * 2 - 12 * 2; // = 320

/// iPad 13" 逻辑宽（1032）。
const double _kIpad13LogicalWidth = 1032;
const double _kIpad13CardWidth = _kIpad13LogicalWidth - 24 * 2 - 12 * 2;

/// 精英物种（走 1.5 倍复开花折减 → 浇水 +0.5% / 施肥 +0.8%，与玄参截图同值）。
const PlantSpecies _coralOrchid = PlantSpecies(
  id: 'species_coral_orchid',
  name: '珊瑚岭兰',
  rarity: Rarity.rare,
  baseCostHigh: 0,
  baseCostLow: 0,
  growthHoursPerStage: kPlantGrowthHoursPerStagePremium,
);

/// 已开过一次花 → 走「复开花」档（截图里正是 +0.5% / +0.8%）。
Plant _rebloomingOrchid() {
  final DateTime t = DateTime(2026, 10, 29, 8);
  return Plant(
    id: 'plant-f163',
    speciesId: 'species_coral_orchid',
    potIndex: 1,
    stage: PlantStage.adult,
    stageStartedAt: t,
    growthProgress: 0.6,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: t,
    bloomCount: 1,
  );
}

/// 今日额度全满（两个按钮都可点 → 才渲染带增幅的完整标签）。
const PlantCareQuota _freshQuota = PlantCareQuota(
  waterUsedToday: 0,
  fertilizeUsedToday: 0,
  minutesUntilNextWater: 0,
  waterBlockReason: null,
  fertilizeBlockReason: null,
);

/// 与 `PlantCard._fmtGain` 同口径（三位小数由 `toStringAsFixed(1)` 收口）。
String _fmtGain(double gain) {
  final double pct = gain * 100;
  final String s = pct.toStringAsFixed(1);
  return s.endsWith('.0') ? pct.round().toString() : s;
}

Widget _host(double cardWidth) => MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: Center(
            // 纵向可滚：本用例只关心横向排版，不许纵向溢出污染断言。
            child: SingleChildScrollView(
              child: SizedBox(
                width: cardWidth,
                child: PlantCard(
                  plant: _rebloomingOrchid(),
                  species: _coralOrchid,
                  quota: _freshQuota,
                  onWater: () {},
                  onFertilize: () {},
                  onClear: () {},
                  onShovel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  required double viewWidth,
  required double cardWidth,
  required double textScale,
  required AppLanguage lang,
}) async {
  tester.view.physicalSize = Size(viewWidth * 3.0, 900 * 3.0);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  AppLocaleController.init(lang);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  await tester.pumpWidget(_host(cardWidth));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 已渲染段落的行数（真实布局结果，不是按字符数估算）。
///
/// `RenderParagraph` 不公开 `computeLineMetrics`，改用「整段选区 → 每行一个
/// TextBox」的公开接口取行数：折了行就必然 > 1 个 box。
int _lineCount(WidgetTester tester, String text) {
  final RenderParagraph p =
      tester.renderObject<RenderParagraph>(find.text(text));
  final String plain = p.text.toPlainText();
  final List<TextBox> boxes = p.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plain.length),
  );
  return boxes.length;
}

/// 是否吐了省略号（`maxLines` 被突破）。
bool _didExceedMaxLines(WidgetTester tester, String text) {
  final RenderParagraph p =
      tester.renderObject<RenderParagraph>(find.text(text));
  return p.didExceedMaxLines;
}

/// 标签的实际屏幕矩形必须在自己那颗按钮内（含 0.5pt 浮点容差）。
void _expectInsideButton(WidgetTester tester, String label, int buttonIndex) {
  final Rect text = tester.getRect(find.text(label));
  final Rect button = tester.getRect(find.byType(OutlinedButton).at(buttonIndex));
  const double eps = 0.5;
  expect(
    text.left >= button.left - eps &&
        text.right <= button.right + eps &&
        text.top >= button.top - eps &&
        text.bottom <= button.bottom + eps,
    isTrue,
    reason: '「$label」矩形 $text 必须落在按钮 $button 之内（缩了但没缩够 / 顶出边界）',
  );
}

void main() {
  final AppLocalizations en = AppLocalizationsEn();
  final AppLocalizations zh = AppLocalizationsZh();

  String shovelLabel(AppLocalizations l) => l.card_action_shovel;
  final String fertEn = en.card_action_fertilize_gain(_fmtGain(
    PlantGrowthService.careProgressGain(
      bloomCount: 1,
      isPremium: true,
      firstGain: kPlantFertilizeProgressGain,
      rebloomGain: kRebloomFertilizeProgressGain,
    ),
  ));
  final String waterEn = en.card_action_water_gain(_fmtGain(
    PlantGrowthService.careProgressGain(
      bloomCount: 1,
      isPremium: true,
      firstGain: kPlantWaterProgressGain,
      rebloomGain: kRebloomWaterProgressGain,
    ),
  ));
  final String fertZh = zh.card_action_fertilize_gain(_fmtGain(
    PlantGrowthService.careProgressGain(
      bloomCount: 1,
      isPremium: true,
      firstGain: kPlantFertilizeProgressGain,
      rebloomGain: kRebloomFertilizeProgressGain,
    ),
  ));

  group('F163 · 手机档（卡宽 320 = 小米 14 Pro 真机宽度）', () {
    testWidgets('en · 字号 1.0：Remove 单行、施肥增幅完整、零溢出',
        (WidgetTester tester) async {
      await _pump(
        tester,
        viewWidth: _kPhoneLogicalWidth,
        cardWidth: _kPhoneCardWidth,
        textScale: 1.0,
        lang: AppLanguage.en,
      );

      // 防假绿：卡片真的渲染出这两个标签（装配失败时下面断言会双双空转）。
      expect(find.text(shovelLabel(en)), findsOneWidget);
      expect(find.text(fertEn), findsOneWidget);
      expect(find.text(waterEn), findsOneWidget);
      expect(fertEn, startsWith('Fertilize +'));

      expect(_lineCount(tester, shovelLabel(en)), 1,
          reason: '「Remove」不得折行（截图症状：末行只剩一个孤字母 e）');
      expect(_didExceedMaxLines(tester, fertEn), isFalse,
          reason: '「$fertEn」不得被省略号截断（施肥增幅必须看得见）');
      expect(_didExceedMaxLines(tester, waterEn), isFalse,
          reason: '「$waterEn」不得被省略号截断');

      _expectInsideButton(tester, fertEn, 1);
      _expectInsideButton(tester, waterEn, 0);

      expect(tester.takeException(), isNull, reason: '手机档不得出现 RenderFlex 溢出');
    });

    testWidgets('en · 字号 1.3（系统大字号）：两条约束依旧成立',
        (WidgetTester tester) async {
      await _pump(
        tester,
        viewWidth: _kPhoneLogicalWidth,
        cardWidth: _kPhoneCardWidth,
        textScale: 1.3,
        lang: AppLanguage.en,
      );

      expect(find.text(shovelLabel(en)), findsOneWidget);
      expect(find.text(fertEn), findsOneWidget);

      expect(_lineCount(tester, shovelLabel(en)), 1,
          reason: '大字号下「Remove」同样不得折行');
      expect(_didExceedMaxLines(tester, fertEn), isFalse,
          reason: '大字号下「$fertEn」同样不得被截断');

      _expectInsideButton(tester, fertEn, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zh · 字号 1.3：中文档零回归（不折行、不截断、零溢出）',
        (WidgetTester tester) async {
      await _pump(
        tester,
        viewWidth: _kPhoneLogicalWidth,
        cardWidth: _kPhoneCardWidth,
        textScale: 1.3,
        lang: AppLanguage.zh,
      );

      expect(find.text(zh.card_action_shovel), findsOneWidget);
      expect(find.text(fertZh), findsOneWidget);

      expect(_lineCount(tester, zh.card_action_shovel), 1,
          reason: '中文「铲除」两字本就放得下，限宽不许把它挤成两行');
      expect(_didExceedMaxLines(tester, fertZh), isFalse,
          reason: '中文「$fertZh」不得被截断');
      expect(tester.takeException(), isNull);
    });
  });

  group('F163 · iPad13 回归：修复不改坏平板档', () {
    testWidgets('en · 字号 1.3：零溢出、不截断', (WidgetTester tester) async {
      await _pump(
        tester,
        viewWidth: _kIpad13LogicalWidth,
        cardWidth: _kIpad13CardWidth,
        textScale: 1.3,
        lang: AppLanguage.en,
      );

      expect(_lineCount(tester, shovelLabel(en)), 1);
      expect(_didExceedMaxLines(tester, fertEn), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
