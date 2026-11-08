/// 左下角天气**图标状态灯**（[GardenWeatherBadge]）· 组件级接线测试。
///
/// ## 第三轮改名与简化后的口径（玄参 2026-11-07 拍板：「白色长条删除」）
/// 旧 `GardenWeatherDock`（72 白条 + 一键右区 + 200 命中扩展盒）整体退役，
/// 组件退化为独立图标状态灯 `GardenWeatherBadge`（Dock → Badge 改名留痕见组件
/// 文件头）。本文件由 `garden_weather_dock_test.dart` 改名重写：
///  · **① 温和日（none）**：状态灯在场（56×56）+ **绿底**（0xFFC0DD97）
///    + **无**角标 + **无**任何文字 + 点击回调触发；
///  · **② 极端日 todo**：状态灯**雾霾青蓝底**（0xFF6FA3A0，第八批：纯白雪花在
///    第七批淡青底上仍看不清 → 底色加深一档）+ **1.5 红描边**（0xFFE24B4A）
///    + **红底白「!」角标在场**；
///  · **③ 极端日 done**：状态灯**绿底** + **绿底白对勾角标在场**（「叹号换成
///    对勾」玄参原话）；
///  · **④ 几何 / 命中**：真实 56×56 命中块（`getSize` == 56×56，无假命中把戏）；
///  · **⑤ 白条退役**：组件树里不得再出现旧停靠条 Key（`garden_weather_dock`）
///    / 72 高白条 / 一键占位；
///  · **⑥ 左侧盾牌（第七批 / 第八批 / 第十批）**：已购棚（shelterBought）⇒
///    盾牌在状态灯**左侧**（间距 7、垂直居中）；第十批 2026-11-08 玄参「还是小」⇒
///    盒 56 → **72**，且位图按内容 bbox 裁掉透明边距撑到 64（视觉主体与 56 天气框
///    相当）；**盾牌盒不参与行高**（状态灯 top 恒 12，买棚时不下跳）；未购 ⇒ 不在场。
///
/// ## 口径纪律
///  · 期望值**写死**（56 / 12 / `0xFFC0DD97` / `0xFF6FA3A0` / `0xFFE24B4A`），
///    不引用实现常量自证；
///  · `WeatherBannerState` 用**真实构造**（与 `weather_a3_banner_logic_test` 同法）；
///  · 组件内零动画 ⇒ 普通 `pump` 即可，不涉及 `pumpAndSettle` 陷阱。
library garden_weather_badge_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_badge.dart';
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

  /// 组件宿主：与页面真实用法同构 —— `Positioned(right:12, top:12)` 挂进
  /// 390×844 的 Stack（2026-11-07 第四批：状态灯移右上角，与左上 chips 对称）。
  Widget host({
    required WeatherBannerState banner,
    WeatherKind kind = WeatherKind.sunny,
    bool shelterBought = false,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: 12,
                  top: 12,
                  child: GardenWeatherBadge(
                    kind: kind,
                    banner: banner,
                    shelterBought: shelterBought,
                    onTap: onTap ?? () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// 读图标状态灯容器的底色（BoxDecoration.color，写死断言用）。
  Color iconBg(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
              .decoration! as BoxDecoration)
          .color!;

  /// 读状态角标容器的底色（todo 红 / done 绿）。
  Color markBg(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(kGardenWeatherBadgeMarkKey))
              .decoration! as BoxDecoration)
          .color!;

  testWidgets('① 温和日（none）：绿底状态灯（56×56）+ 无角标 + 无文字 + 点击回调触发',
      (WidgetTester tester) async {
    phoneViewport(tester);
    int taps = 0;
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.none,
        kind: WeatherKind.sunny,
        shelterRefType: null,
      ),
      kind: WeatherKind.sunny,
      onTap: () => taps++,
    ));
    await tester.pump();

    // 状态灯：56×56（写死规格，不引用实现常量自证）+ 绿底（正常态）。
    final Size icon = tester.getSize(find.byKey(kGardenWeatherBadgeIconKey));
    expect(icon.width, closeTo(56, 0.5), reason: '天气图标容器宽 56（醒目放大）');
    expect(icon.height, closeTo(56, 0.5), reason: '天气图标容器高 56');
    expect(iconBg(tester), const Color(0xFFC0DD97),
        reason: '温和日状态灯 = 浅绿底（正常）');

    // 无角标、无买棚按钮、无任何天气描述文字。
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsNothing,
        reason: '温和日无状态角标');
    expect(find.byKey(kShelterButtonHitKey), findsNothing,
        reason: '买棚按钮已迁入对话框，状态灯上永不存在');
    expect(find.textContaining(zh.weather_sunny), findsNothing,
        reason: '状态灯不渲染任何描述性文字（玄参：「只保留 56×56 的圆角块就好了」）');

    // 点击回调触发（可点击 → 打开对话框的入口）。
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await tester.pump();
    expect(taps, 1, reason: '点状态灯必须触发 onTap（宿主弹出天气对话框）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('② 极端日 todo：雾霾青蓝底 + 1.5 红描边状态灯 + 红底白「!」角标在场',
      (WidgetTester tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.todo,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
    ));
    await tester.pump();

    // 状态灯底色（第八批：淡青底加深为雾霾青蓝，纯白雪花对比 ≥2.5 要清晰）。
    expect(iconBg(tester), const Color(0xFF6FA3A0),
        reason: '极端 todo 态状态灯 = 雾霾青蓝底（白 vs 底对比度 ≈2.8，雪花清晰）');

    // 红描边 1.5（警示语义由描边 + 角标承担）。
    final BoxDecoration deco =
        tester.widget<Container>(find.byKey(kGardenWeatherBadgeIconKey))
            .decoration! as BoxDecoration;
    final Border border = deco.border! as Border;
    expect(border.top.color, const Color(0xFFE24B4A),
        reason: 'todo 态描边 = 红（写死色值，与角标同族）');
    expect(border.top.width, 1.5, reason: 'todo 态描边宽 1.5');

    // 叹号角标在场（红底白「!」）。
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: 'todo 态必须有叹号角标（「背景红色加叹号，表示需要处理」）');
    expect(markBg(tester), const Color(0xFFE24B4A),
        reason: '叹号角标 = 红底（写死色值）');
    expect(find.text('!'), findsOneWidget, reason: '角标内容 = 白色「!」');

    expect(tester.takeException(), isNull);
  });

  testWidgets('③ 极端日 done：绿底状态灯 + 绿底白对勾角标（「叹号换成绿对勾」）',
      (WidgetTester tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.done,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
    ));
    await tester.pump();

    // done 态状态灯回到浅绿底（完成 = 正常色）。
    expect(iconBg(tester), const Color(0xFFC0DD97),
        reason: 'done 态状态灯 = 浅绿底（完成 = 正常）');

    // 对勾角标在场：绿底 + Icons.check（白对勾），不是叹号。
    expect(find.byKey(kGardenWeatherBadgeMarkKey), findsOneWidget,
        reason: 'done 态角标在场（玄参：「叹号换成绿对勾」）');
    expect(markBg(tester), const Color(0xFF2E7D32),
        reason: 'done 角标 = 绿底（与「已获保护」同族色）');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: 'done 角标内容 = 白对勾');
    expect(find.text('!'), findsNothing, reason: 'done 态不再是叹号');

    expect(tester.takeException(), isNull);
  });

  testWidgets('④ 几何 / 命中：真实 56×56 块贴右上（right 12 / top 12），'
      '角标 20×20 压右上', (WidgetTester tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.todo,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
    ));
    await tester.pump();

    // 根命中块：56×56（`GestureDetector` 视觉同尺寸 —— 无「声明 44」假命中）。
    final Rect badgeRect = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
    expect(badgeRect.width, closeTo(56, 0.5), reason: '命中块宽 56（真实尺寸命中）');
    expect(badgeRect.height, closeTo(56, 0.5), reason: '命中块高 56');
    expect(badgeRect.right, closeTo(390 - 12, 0.5), reason: '右锚 12');
    expect(badgeRect.top, closeTo(12, 0.5), reason: '贴顶 12');

    // 点击中心必须命中（真实点击探针在 ①）。
    // 角标（外扩 4 压角）：20×20。
    final Size mark = tester.getSize(find.byKey(kGardenWeatherBadgeMarkKey));
    expect(mark.width, closeTo(20, 0.5), reason: '角标边长 20');
    expect(mark.height, closeTo(20, 0.5), reason: '角标边长 20');

    expect(tester.takeException(), isNull);
  });

  testWidgets('⑤ 白条退役：组件树里不存在旧停靠条结构（72 高白条 / 全宽宿主）',
      (WidgetTester tester) async {
    phoneViewport(tester);
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.none,
        kind: WeatherKind.sunny,
        shelterRefType: null,
      ),
      kind: WeatherKind.sunny,
    ));
    await tester.pump();

    // 状态灯不再坐在 72 高的白条里：根命中块之上没有 Material 白条
    //（旧 dock 的视觉条是 `Material(color: white .92, elevation: 2)`，
    //  高 72；现在组件内部只有角标 Container 与位图，无 72 高盒子）。
    expect(tester.getSize(find.byKey(kGardenWeatherBadgeKey)).height,
        closeTo(56, 0.5),
        reason: '组件总高 == 56（旧 72 白条已删，玄参 2026-11-07 拍板）');
    // 旧 dock 的全宽宿主断言口径（width == 页宽 − 24）随之退役：现在宽 56。
    expect(tester.getSize(find.byKey(kGardenWeatherBadgeKey)).width,
        closeTo(56, 0.5), reason: '组件总宽 == 56（不再全宽）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('⑥ 已购棚（第七批 / 第八批 / 第十批）：盾牌在状态灯左侧（72×72 盒、'
      '间距 7、垂直居中、顶锚不变）；未购 ⇒ 不在场', (WidgetTester tester) async {
    phoneViewport(tester);

    // ① 未购：盾牌不在场，状态灯右锚位置不受影响。
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.todo,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
    ));
    await tester.pump();
    expect(find.byKey(kGardenWeatherBadgeShelterKey), findsNothing,
        reason: '未购棚 ⇒ 状态灯左侧无盾牌');
    final Rect badgeRectBare = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
    expect(badgeRectBare.right, closeTo(390 - 12, 0.5),
        reason: '未购态状态灯右锚 12（基线不变）');

    // ② 已购：盾牌在状态灯左侧 —— 72×72（第十批放大：「要跟右边天气框差不多大」）、
    //    间距 7、垂直居中。
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.todo,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
      shelterBought: true,
    ));
    await tester.pump();

    final Finder shelter = find.byKey(kGardenWeatherBadgeShelterKey);
    expect(shelter, findsOneWidget, reason: '已购棚 ⇒ 盾牌位图在场（badge 左侧）');
    final Rect shelterRect = tester.getRect(shelter);
    final Rect badgeRect = tester.getRect(find.byKey(kGardenWeatherBadgeKey));
    expect(shelterRect.width, closeTo(72, 0.5),
        reason: '盾牌盒边长 72（第十批：第八批 56 玄参仍觉得小）');
    expect(shelterRect.height, closeTo(72, 0.5), reason: '盾牌盒子 72×72');
    expect(shelterRect.right, closeTo(badgeRect.left - 7, 0.5),
        reason: '盾牌与状态灯间距 7（玄参口径 6~8pt）');
    expect(shelterRect.center.dy, closeTo(badgeRect.center.dy, 0.5),
        reason: '盾牌与状态灯垂直居中对齐');
    // 🔴 第十批新增守卫：盾牌盒 72 但**不参与行高**（OverflowBox 溢出），
    //    否则买棚瞬间状态灯会被挤下 8pt（top 12 → 20），那是新缺陷。
    expect(badgeRect.top, closeTo(12, 0.5),
        reason: '有盾牌时状态灯仍贴顶 12（盾牌盒向上溢出，不撑高整行）');
    // 状态灯本体几何逐位不变（Row(min) 向左生长，右缘锚不受影响）。
    expect(badgeRect.right, closeTo(390 - 12, 0.5),
        reason: '有盾牌时状态灯右锚仍 12（整排向左生长）');
    expect(badgeRect.width, closeTo(56, 0.5), reason: '状态灯本体仍 56 宽');
    // 盾牌本体是位图（Image），素材缺失时回退 Material 盾牌图标 —— 两者都合法。
    expect(
      find.descendant(of: shelter,
          matching: find.byWidgetPredicate((Widget w) =>
              w is Image || (w is Icon && w.icon == Icons.shield_outlined))),
      findsOneWidget,
      reason: '盾牌 = shelterArtOf 位图（或素材缺失时的 Material 盾牌回退）',
    );
    // 点击仍落在状态灯上（盾牌是纯展示件，不挡 badge 命中区）。
    int taps = 0;
    await tester.pumpWidget(host(
      banner: const WeatherBannerState(
        mood: WeatherBannerMood.todo,
        kind: WeatherKind.drought,
        shelterRefType: kWeatherShelterRefTypeShade,
      ),
      kind: WeatherKind.drought,
      shelterBought: true,
      onTap: () => taps++,
    ));
    await tester.pump();
    await tester.tap(find.byKey(kGardenWeatherBadgeKey));
    await tester.pump();
    expect(taps, 1, reason: '有盾牌时点状态灯仍触发 onTap');

    expect(tester.takeException(), isNull);
  });
}
