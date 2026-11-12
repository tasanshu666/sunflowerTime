/// 花园页**天气对话框**（[showGardenWeatherDialog]）· 组件级测试。
///
/// ## 覆盖口径（玄参 2026-11-07 第三批）
///  · **温和日**：大图标淡色托 + 名字 + 孩子视角引导详情 + 关闭键；**无**买棚按钮；
///  · **极端日 todo**：买棚按钮在场（`kShelterButtonHitKey`，T-7 恢复的入口），
///    命中盒**真实 ≥44**，点击 = 先关本框 → 触发 `onBuy`（页面 `_onShelterTap`）；
///  · **极端日 done**：**无**买棚按钮 + **无**红色警示徽章；盾牌行已迁往天气
///    badge 左侧（第七批 2026-11-07），框内不再有盾牌 /「已获保护」；
///  · **done 态额外动作提醒**（`kGardenWeatherDialogExtraHintKey`，第九批
///    2026-11-07）：干旱=当日浇水 = 0 在场 / 浇水 ≥1 消失；暴雨=施肥同构；
///    大风 / 极寒买棚即全部完成，无此行；
///  · **明日预告行**（`kGardenWeatherDialogTomorrowKey`，第五批：ticker 撤除后
///    「明天 · …」由对话框承接）三种态都在场；
///  · **成长影响行**（`kGardenWeatherDialogGrowthKey`，第十批 2026-11-08）：正文
///    之后、明日预告之前一行定性说明（`garden_weather_growth_*`），方向与
///    `prd_params.dart` 的 g / w / f 乘数一致；
///  · **弹出方式**：`showDialog` 默认遮罩可点关（barrierDismissible）。
///
/// ## 口径纪律
/// 全部文案由测试在页面语境解析好装进 [GardenWeatherDialogSpec]（弹窗铁律同构：
/// 组件不做 l10n 解析）；期望值写死，不引用实现常量自证。
library garden_weather_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart'
    show kShelterButtonHitKey;
void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();

  setUp(() {
    AppLocaleController.current = const Locale('zh');
  });
  tearDown(() {
    AppLocaleController.current = const Locale('zh');
  });

  /// 与页面 `_showWeatherDialog` 同构的 spec 装配（文案在「页面语境」解析好）。
  ///
  /// 明日预告钉死「明天 · 微风」（breeze）：与今日 kind 无关，断言写死不引用实现。
  /// [wateredToday] / [fertilizedToday] = 账本重算的「当日浇水 / 施肥 ≥1 次」
  /// 事实（页面由 `_anyWateredToday` / `_anyFertilizedToday` 传入）；extraActionHint
  /// 的派生逻辑与页面同构：仅 done 态 + 对应动作未完成时传串，否则 null。
  GardenWeatherDialogSpec specOf(
    WeatherKind kind,
    WeatherBannerMood mood, {
    bool wateredToday = false,
    bool fertilizedToday = false,
  }) {
    final String? refType = kind.shelterRefType;
    final bool done = mood == WeatherBannerMood.done;
    final String name = switch (kind) {
      WeatherKind.drought => zh.weather_drought,
      WeatherKind.rainstorm => zh.weather_rainstorm,
      WeatherKind.wind => zh.weather_wind,
      WeatherKind.cold => zh.weather_cold,
      _ => zh.weather_sunny,
    };
    final String detail = switch (kind) {
      WeatherKind.drought => zh.garden_weather_guide_drought,
      WeatherKind.rainstorm => zh.garden_weather_guide_rainstorm,
      WeatherKind.wind => zh.garden_weather_guide_wind,
      WeatherKind.cold => zh.garden_weather_guide_cold,
      _ => zh.garden_weather_guide_sunny,
    };
    // 「今天天气对成长的影响」一行（第十批）：与页面 `_weatherGrowthHintOf` 同构。
    final String growthHint = switch (kind) {
      WeatherKind.drought => zh.garden_weather_growth_drought,
      WeatherKind.rainstorm => zh.garden_weather_growth_rainstorm,
      WeatherKind.wind => zh.garden_weather_growth_wind,
      WeatherKind.cold => zh.garden_weather_growth_cold,
      _ => zh.garden_weather_growth_sunny,
    };
    // done 态额外动作提醒（第九批）：干旱=未浇水 / 暴雨=未施肥时给串，否则 null。
    String? extraActionHint;
    if (done) {
      switch (kind) {
        case WeatherKind.drought:
          if (!wateredToday) extraActionHint = zh.garden_weather_action_drought;
        case WeatherKind.rainstorm:
          if (!fertilizedToday) {
            extraActionHint = zh.garden_weather_action_rainstorm;
          }
        default:
          break;
      }
    }
    // 🔴 B13.18：买棚收益行已删（收益并入正文合并句），不再传 shelterEffect。
    return GardenWeatherDialogSpec(
      kind: kind,
      name: name,
      detail: detail,
      growthHint: growthHint,
      tomorrowLabel: zh.garden_weather_dialog_tomorrow(zh.weather_breeze),
      // B13.16：明日预告胶囊里的图标（与页面同构：build 顶层算好的明日日型）。
      tomorrowKind: WeatherKind.breeze,
      shelterRefType: refType,
      buyLabel: refType == null
          ? null
          : '${zh.garden_shelter_shade} · $kWeatherShelterPrice ☀',
      done: done,
      extraActionHint: extraActionHint,
      closeLabel: zh.garden_weather_dialog_close,
    );
  }

  /// 宿主：一个按钮触发 showGardenWeatherDialog（真实 route 链路）。
  Widget host(
    WeatherKind kind,
    WeatherBannerMood mood,
    VoidCallback onBuy, {
    bool wateredToday = false,
    bool fertilizedToday = false,
  }) {
    return MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: Center(
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showGardenWeatherDialog(
                    context: context,
                    spec: specOf(
                      kind,
                      mood,
                      wateredToday: wateredToday,
                      fertilizedToday: fertilizedToday,
                    ),
                    onBuy: onBuy,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('温和日：大图标 + 名字 + hint 详情 + 关闭键；无买棚按钮',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(WeatherKind.sunny, WeatherBannerMood.none, () {}));
    await open(tester);

    expect(find.byKey(kGardenWeatherDialogKey), findsOneWidget,
        reason: '对话框在页面中部弹出（showDialog 默认居中）');
    expect(find.byKey(kGardenWeatherDialogArtTrayKey), findsOneWidget,
        reason: '大图标淡色圆角托在场（第六批卡片美化）');
    expect(find.text(zh.weather_sunny), findsOneWidget, reason: '日型名在场');
    expect(find.text(zh.garden_weather_guide_sunny), findsOneWidget,
        reason: '温和日详情 = 孩子视角引导文案（garden_weather_guide_*，第六批）');
    // 第十批（玄参「每天浇水但进度不一样，孩子会迷茫」）：正文之后、明日预告之前
    // 一行「今天天气对成长的影响」。
    expect(find.byKey(kGardenWeatherDialogGrowthKey), findsOneWidget,
        reason: '成长影响行在场（garden_weather_growth_*）');
    expect(find.text(zh.garden_weather_growth_sunny), findsOneWidget,
        reason: '晴 =「长得更快一点，浇水也更管用」（g=1.05 / w=1.10 方向）');
    final Rect detailRect = tester.getRect(find.text(zh.garden_weather_guide_sunny));
    final Rect growthRect =
        tester.getRect(find.byKey(kGardenWeatherDialogGrowthKey));
    final Rect tomorrowRect =
        tester.getRect(find.byKey(kGardenWeatherDialogTomorrowKey));
    expect(growthRect.top, greaterThanOrEqualTo(detailRect.bottom),
        reason: '成长行在正文（指引）之后');
    expect(growthRect.bottom, lessThanOrEqualTo(tomorrowRect.top),
        reason: '成长行在明日预告之前（玄参指定位置）');
    expect(find.byKey(kGardenWeatherDialogAlertMarkKey), findsNothing,
        reason: '温和日无红色警示徽章');
    // 明日预告行（第五批：ticker 撤除后由对话框承接「明天 · …」）。
    expect(find.byKey(kGardenWeatherDialogTomorrowKey), findsOneWidget,
        reason: '明日预告行在场');
    expect(find.text(zh.garden_weather_dialog_tomorrow(zh.weather_breeze)),
        findsOneWidget,
        reason: '明日预告 =「明天 · {明日日型名}」（页面拼好传入）');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: '温和日没有买棚按钮（refType == null）');
    expect(find.text(zh.garden_weather_dialog_close), findsOneWidget,
        reason: '关闭键在场');

    // 关闭键可关。
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await tester.pumpAndSettle();
    expect(find.byKey(kGardenWeatherDialogKey), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('极端日 todo：买棚按钮在场（真实 ≥44 命中）、点击 = 关本框 + 触发 onBuy',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    int buys = 0;
    await tester.pumpWidget(
        host(WeatherKind.drought, WeatherBannerMood.todo, () => buys++));
    await open(tester);

    expect(find.text(zh.garden_weather_guide_drought), findsOneWidget,
        reason: '极端日详情 = 孩子视角引导文案（garden_weather_guide_*，第六批）');
    // 第十批：极端日同样有成长影响行，且**方向与常量一致**（干旱 g=0.20 几乎停长、
    // w=3.00 浇水最管用 —— 不许写成「长得快」）。
    expect(find.text(zh.garden_weather_growth_drought), findsOneWidget,
        reason: '干旱成长行 =「几乎不长个儿 + 浇水最管用」（g=0.20 / w=3.00 方向）');
    // 极端日同样有明日预告行（顺序：图标 + 今日名 + 详情 + 明日 + 买棚按钮）。
    expect(find.byKey(kGardenWeatherDialogTomorrowKey), findsOneWidget,
        reason: '极端日明日预告行也在场（顺序在买棚按钮之前）');
    // 极端 todo：标题旁红色警示小徽章在场（第六批美化，视觉层级不变）。
    expect(find.byKey(kGardenWeatherDialogAlertMarkKey), findsOneWidget,
        reason: '极端 todo 态标题旁红色警示小徽章在场');
    final Finder buy = find.byKey(kShelterButtonHitKey);
    expect(buy, findsOneWidget, reason: '极端日买棚按钮在对话框里（T-7 入口）');

    // 命中盒真实 ≥44（含上下透明 padding 的总命中高）。
    expect(tester.getSize(buy).height, greaterThanOrEqualTo(44),
        reason: '买棚按钮命中盒 ≥44（A2-10 纪律）');

    // 点击：先关本框（不叠两层弹窗），再触发 onBuy（页面 _onShelterTap 含二次确认）。
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(find.byKey(kGardenWeatherDialogKey), findsNothing,
        reason: '点买棚先关天气对话框');
    expect(buys, 1, reason: 'onBuy（页面买棚链路）被触发');

    expect(tester.takeException(), isNull);
  });

  testWidgets('极端日 done：无买棚按钮、无警示徽章；盾牌行已迁出（第七批）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        host(WeatherKind.drought, WeatherBannerMood.done, () {}));
    await open(tester);

    // 第七批：盾牌从对话框迁往天气 badge 左侧 —— 框内不再有「已获保护」。
    expect(find.text(zh.garden_weather_protected), findsNothing,
        reason: 'done 态对话框不再渲染盾牌 /「已获保护」行（已迁往 badge 左侧）');
    expect(find.byKey(kGardenWeatherDialogAlertMarkKey), findsNothing,
        reason: 'done 态不显示红色警示徽章（已保护不再吓人）');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: 'done 态不显示买棚按钮（退场逻辑保留）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('done 干旱未浇水：额外动作提醒小字条在场（第九批玄参原话）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      WeatherKind.drought,
      WeatherBannerMood.done,
      () {},
      wateredToday: false,
    ));
    await open(tester);

    expect(find.byKey(kGardenWeatherDialogExtraHintKey), findsOneWidget,
        reason: 'done + 干旱 + 当日浇水 = 0 ⇒ 额外动作提醒小字条在场');
    expect(find.text(zh.garden_weather_action_drought), findsOneWidget,
        reason: '提醒文案 =「植物极度口渴，记得多浇水哦」（玄参原话，页面拼好传入）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('done 干旱已浇水：额外动作提醒小字条退场（当日浇水 ≥1 即消失）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      WeatherKind.drought,
      WeatherBannerMood.done,
      () {},
      wateredToday: true,
    ));
    await open(tester);

    expect(find.byKey(kGardenWeatherDialogExtraHintKey), findsNothing,
        reason: 'done + 干旱 + 当日浇水 ≥1 ⇒ 提醒消失（动作已做，不重复催）');
    expect(find.text(zh.garden_weather_action_drought), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('done 暴雨：未施肥在场、已施肥退场（与干旱同构）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 未施肥：提醒在场。
    await tester.pumpWidget(host(
      WeatherKind.rainstorm,
      WeatherBannerMood.done,
      () {},
      fertilizedToday: false,
    ));
    await open(tester);
    expect(find.byKey(kGardenWeatherDialogExtraHintKey), findsOneWidget,
        reason: 'done + 暴雨 + 当日施肥 = 0 ⇒ 额外动作提醒小字条在场');
    expect(find.text(zh.garden_weather_action_rainstorm), findsOneWidget,
        reason: '提醒文案 =「雨水替你浇花啦，记得施一次肥哦」（依此类推：暴雨额外动作=施肥）');

    // 关掉再开已施肥态。
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(
      WeatherKind.rainstorm,
      WeatherBannerMood.done,
      () {},
      fertilizedToday: true,
    ));
    await open(tester);
    expect(find.byKey(kGardenWeatherDialogExtraHintKey), findsNothing,
        reason: 'done + 暴雨 + 当日施肥 ≥1 ⇒ 提醒消失');
    expect(find.text(zh.garden_weather_action_rainstorm), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('done 大风 / 极寒：无额外动作提醒行（买棚即全部完成）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.wind,
      WeatherKind.cold,
    ]) {
      await tester.pumpWidget(host(kind, WeatherBannerMood.done, () {}));
      await open(tester);
      expect(find.byKey(kGardenWeatherDialogExtraHintKey), findsNothing,
          reason: '$kind done 态买棚即全部完成，无额外动作 ⇒ 无提醒行');
      await tester.tap(find.text(zh.garden_weather_dialog_close));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  // ── B13.18（2026-11-12 玄参）：收益行退场，收益并入正文合并句 ────────────

  testWidgets('B13.18 极端日 todo：正文 = 合并句（极寒逐字）+ 无收益行 + 明日胶囊带图标',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(WeatherKind.cold, WeatherBannerMood.todo, () {}));
    await open(tester);

    // 合并句逐字（玄参原话）：正文同时含「搭棚」动作与「受保护」收益，
    // 与常量方向一致（期望独立于实现）。
    expect(find.text(zh.garden_weather_guide_cold), findsOneWidget,
        reason: '极寒正文 = 合并句「要上冻啦，搭上保温棚，植物成长进度会受到保护」');
    // 明日预告胶囊（B13.17 重排）：图标槽位有东西（Image 或回退 Icon）。
    final Finder pillIcon = find.descendant(
      of: find.byKey(kGardenWeatherDialogTomorrowKey),
      matching: find.byWidgetPredicate((Widget w) => w is Image || w is Icon),
    );
    expect(pillIcon, findsOneWidget,
        reason: '明日胶囊必须带明日日型图标（素材缺失回退 Icon，不许空槽）');
    // 明日预告在买棚按钮之前（排版顺序钉住）。
    final Rect tomorrowRect =
        tester.getRect(find.byKey(kGardenWeatherDialogTomorrowKey));
    final Rect buyRect = tester.getRect(find.byKey(kShelterButtonHitKey));
    expect(tomorrowRect.bottom, lessThanOrEqualTo(buyRect.top),
        reason: '明日预告在买棚按钮之前');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B13.18 温和日 / 极端日 done：无收益行（合并后恒不存在）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 温和日：shelterEffect = null ⇒ 不渲染。
    await tester.pumpWidget(host(WeatherKind.sunny, WeatherBannerMood.none, () {}));
    await open(tester);
    expect(find.text('garden_weather_dialog_shelter_effect'), findsNothing,
        reason: 'B13.18 起收益行 Key 已从组件删除，恒不渲染');
    await tester.tap(find.text(zh.garden_weather_dialog_close));
    await tester.pumpAndSettle();

    // 极端日 done：收益已兑现 ⇒ 不渲染（不对已保护用户再打广告）。
    await tester.pumpWidget(host(WeatherKind.cold, WeatherBannerMood.done, () {}));
    await open(tester);
    expect(find.text('garden_weather_dialog_shelter_effect'), findsNothing,
        reason: 'done 态收益行恒不渲染（B13.18 起 Key 已删）');
    expect(tester.takeException(), isNull);
  });
}
