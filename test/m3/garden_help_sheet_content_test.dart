// 守卫：花园「玩法说明」弹窗内容与当前口径同步（2026-10-22 内容同步批次）。
//
// 背景：玩法说明自 2026-09-23 扩充后长期未跟批更新，种子/碎片/晨露/杂草害虫/
// 枯萎救回/护眼奖励等已上线玩法缺失（玄参 2026-10-22 反馈「内容还比较旧」）。
// 本文件把**当前口径的关键数字**钉死在断言里：日后任何 PRD 调参若使文案失真，
// 这里先红，提示同步玩法说明（数字真源仍是 prd_params 常量，弹窗只是消费方）。
//
// 🔴 数字派生纪律：GardenHelpSheet 内**禁止裸字面量**——所有数字经 ARB 占位符
// 由 prd_params 常量注入；本测试断言的期望值**独立写死**（不引用被测常量），
// 常量改动 → 弹窗变 → 与此处钉死的旧口径不符 → 红，双向可证伪。
//
// ⚠️ 视口：10 行内容较长，用 360×2000 高视口保证 SingleChildScrollView 全量
// build（懒视口下屏外文本 find 不到，属假红）。
library garden_help_sheet_content_test;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';

Widget _host(AppLocalizations l10n) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: l10n.localeName == 'en' ? const Locale('en') : const Locale('zh'),
      home: Builder(
        builder: (BuildContext context) => const Scaffold(
          body: GardenHelpSheet(capacity: 4, expandCost: 160),
        ),
      ),
    );

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360 * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pump();
}

void main() {
  testWidgets('zh：10 行主题齐全，关键数字与当前口径一致', (WidgetTester tester) async {
    await _pumpTall(tester, _host(AppLocalizationsZh()));

    // 行标题（10 行 = 7 旧 + 3 新）。
    expect(find.text('玩法说明'), findsOneWidget);
    for (final String title in <String>[
      '怎么挣阳光',
      '阳光能干什么',
      '植物怎么长大',
      '别让植物枯萎',
      '任务打卡与家长核销',
      '开花的小惊喜',
      '杂草和害虫',
      '种子和碎片',
      '花园容量',
      '扩容',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺行：$title');
    }

    // 关键数字钉死当前口径（改 prd_params 必须同步玩法说明，这里先红）。
    expect(find.textContaining('每分钟 +1 ☀'), findsOneWidget,
        reason: 'kSunlightPerFocusMinute = 1');
    // 玄参 2026-10-23 反馈：任务打卡奖励按专注时长比例结算（F143），非固定值。
    expect(find.textContaining('还能获得额外的阳光（按专注时长算）'), findsOneWidget,
        reason: '任务奖励必须定性化，禁止出现「每项还 +N ☀」固定数口径');
    expect(find.textContaining('每项还 +'), findsNothing,
        reason: '旧固定值文案不得回潮');
    expect(find.textContaining('+2 ☀。'), findsOneWidget,
        reason: '护眼奖励 kEyeCareRewardSunlight = 2');
    expect(find.textContaining('花 300 ☀ 或 10 片碎片'), findsOneWidget,
        reason: '普通档 kSpeciesSunlightCostCommon=300 / kSpeciesFragmentCostCommon=10');
    expect(find.textContaining('浇水 5 ☀/次起、施肥 10 ☀/次起'), findsOneWidget);
    expect(find.textContaining('拿回一半阳光'), findsOneWidget,
        reason: '铲除返还 50% 口径');
    expect(find.textContaining('3 天没浇水就会枯萎'), findsOneWidget,
        reason: 'kPlantWiltDays = 3');
    expect(find.textContaining('7 天就会枯死'), findsOneWidget,
        reason: 'kPlantDeathDays = 7');
    expect(find.textContaining('3 天内浇浇水就能救回来'), findsOneWidget,
        reason: 'kPlantWiltRecoverHardDays = 3');
    expect(find.textContaining('拖久了要多浇 3 次'), findsOneWidget,
        reason: 'kPlantWiltRecoverHardWater = 3');
    expect(find.textContaining('再施 1 次肥'), findsOneWidget,
        reason: 'kPlantWiltRecoverHardFertilize = 1');
    expect(find.textContaining('按实际专注的时间发一部分阳光'), findsOneWidget,
        reason: 'F143 联动任务比例结算口径');
    expect(find.textContaining('至少 +6 ☀'), findsOneWidget,
        reason: '开花保底阳光 kBloomInstantSunlight = 6（普通档）');
    expect(find.textContaining('每天早上都会掉一份晨露奖励'), findsOneWidget,
        reason: '晨露每日口径（8 点内联实现，文案不写死钟点）');
    expect(find.textContaining('除草 +1 ☀、除虫 +2 ☀'), findsOneWidget,
        reason: 'kGardenWeedReward=1 / kGardenPestReward=2');
    // F155-B（玄参 2026-10-27 拍板）：空花盆也会长草长虫 —— 必须在玩法说明里明说，
    // 否则孩子看到空盆上的浮标无法自解释（只加这一句断言，其余 18 处数字口径不动）。
    expect(find.textContaining('空花盆也会长草长虫'), findsOneWidget,
        reason: 'F155-B 空盆干扰物口径必须写进玩法说明（zh）');
    expect(find.textContaining('当「钱」用'), findsOneWidget,
        reason: '种子第三支付方式（C31）');
    expect(find.textContaining('自动变成碎片'), findsOneWidget,
        reason: '重复种子自动分解');
    expect(find.textContaining('攒 20 片碎片'), findsOneWidget,
        reason: '精英档 kSpeciesFragmentCostPremium = 20');
    expect(find.textContaining('4 / 12 盆'), findsOneWidget,
        reason: '容量默认 4 / 上限 12');

    // 反向：已删除的旧口径不得回潮。
    expect(find.textContaining('10 天'), findsNothing,
        reason: '缺陷 5 回归守卫：精品植物不成立「每阶段约 10 天」');
  });

  testWidgets('en：新三行齐全 + 关键数字一致（i18n 双语同步）', (WidgetTester tester) async {
    // L10nScope 经 AppLocaleController.current 取 locale（静态单点）；
    // 用例结束回 zh，不污染同文件后续用例。
    AppLocaleController.current = const Locale('en');
    addTearDown(() => AppLocaleController.current = const Locale('zh'));
    await _pumpTall(tester, _host(AppLocalizationsEn()));

    for (final String title in <String>[
      'Blooming surprises',
      'Weeds & pests',
      'Seeds & fragments',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺行：$title');
    }
    expect(find.textContaining('at least +6 ☀'), findsOneWidget);
    expect(find.textContaining('+1 ☀ for a weed, +2 ☀ for a pest'),
        findsOneWidget);
    // F155-B 英文同步（en 走自然口语，不是逐字直译）。
    expect(find.textContaining('even empty pots can grow them'), findsOneWidget,
        reason: 'F155-B 空盆干扰物口径必须写进玩法说明（en）');
    expect(find.textContaining('20 fragments'), findsOneWidget);
    expect(find.textContaining('300 ☀ or 10 fragments'), findsOneWidget);
  });
}
