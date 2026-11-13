/// 守卫战 v2 · **平板适配（uiScale）护栏**。
///
/// 背景：守卫卡此前未走平板适配（`uiScaleOf`），iPad 上被拉成全宽窄带、房子/战士/
/// 按钮还是手机尺寸。现 `GuardCardLayout` 与 `GuardSceneCard` / `GuardBattleField`
/// 都接入 `uiScale`（手机 = 1.0 ⇒ 逐位零回归；iPad 11″ 1.3 / 13″ 1.6 ⇒ 等比放大）。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | 1 | 手机（u=1.0）：卡高 / 房子 / 战士 / 按钮槽 / 倒计时细线全部 = 旧值（零回归） |
/// | 2 | iPad 11″（834, u=1.3）：上述几何全部 ×1.3（卡高 145.6 等） |
/// | 3 | iPad 13″（1024, u=1.6）：上述几何全部 ×1.6（卡高 179.2 等） |
/// | 4 | 渲染层：GuardSceneCard 在 u=1.3 下真实卡高 = 145.6、开始钮插槽 = 83.2（命中盒，B13.5）、视觉钮 = 52、旗标 = 83.2 |
library guard_scene_card_tablet_scale_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

const double _eps = 0.01;

/// 平板倍率：iPad 11″ = 1.3 / iPad 13″ = 1.6（与 `tabletUiScaleFor` 同源）。
void main() {
  group('① 手机零回归（u=1.0，几何逐位不变）', () {
    const GuardCardLayout l = GuardCardLayout(390, 1.0);
    test('卡高 / 基线 / 房子 / 战士 / 按钮槽 / 倒计时细线 = 旧值', () {
      expect(l.cardHeight, closeTo(112, _eps));
      expect(l.baselineY, closeTo(102, _eps));
      expect(l.houseRect.height, closeTo(88, _eps));
      expect(l.houseRect.top, closeTo(14, _eps));
      expect(l.soldierRect.width, closeTo(60, _eps));
      expect(l.rightClusterRect.width, closeTo(64, _eps));
      expect(l.countdownRect.height, closeTo(4, _eps));
      expect(l.monsterExtent, closeTo(44, _eps));
    });
  });

  group('② iPad 11″（834 宽，u=1.3）等比放大', () {
    const GuardCardLayout l = GuardCardLayout(834, 1.3);
    test('几何全部 ×1.3', () {
      expect(l.cardHeight, closeTo(112 * 1.3, _eps));
      expect(l.baselineY, closeTo(102 * 1.3, _eps));
      expect(l.houseRect.height, closeTo(88 * 1.3, _eps));
      expect(l.houseRect.top, closeTo(14 * 1.3, _eps));
      expect(l.soldierRect.width, closeTo(60 * 1.3, _eps));
      expect(l.rightClusterRect.width, closeTo(64 * 1.3, _eps));
      expect(l.countdownRect.height, closeTo(4 * 1.3, _eps));
      expect(l.monsterExtent, closeTo(44 * 1.3, _eps));
    });
    test('u=1.3 与 u=1.0 必须不同（缩放确实生效）', () {
      const GuardCardLayout base = GuardCardLayout(834, 1.0);
      expect(l.cardHeight, greaterThan(base.cardHeight + 10));
    });
  });

  group('③ iPad 13″（1024 宽，u=1.6）等比放大', () {
    const GuardCardLayout l = GuardCardLayout(1024, 1.6);
    test('几何全部 ×1.6', () {
      expect(l.cardHeight, closeTo(112 * 1.6, _eps));
      expect(l.houseRect.height, closeTo(88 * 1.6, _eps));
      expect(l.soldierRect.width, closeTo(60 * 1.6, _eps));
      expect(l.rightClusterRect.width, closeTo(64 * 1.6, _eps));
      expect(l.countdownRect.height, closeTo(4 * 1.6, _eps));
    });
  });

  group('④ 渲染层：GuardSceneCard 真实卡高 / 按钮 / 旗标随 uiScale', () {
    Widget host(Widget child, Size size) => MaterialApp(
          locale: const Locale('zh'),
          builder: (BuildContext context, Widget? inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: size),
            child: inner!,
          ),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Scaffold(body: child),
        );

    GuardTodayView viewOf(GuardPillMode mode) => GuardTodayView(
          mode: mode,
          state: GuardDayState(
            dayKey: '2026-11-12',
            status: mode == GuardPillMode.fighting
                ? GuardDayStatus.fighting
                : GuardDayStatus.pending,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 2,
          ),
          energyAvailable: 2,
          balance: 20,
        );

    testWidgets('待机态（pendingFree）u=1.3：卡高 = 145.6、开始钮插槽 = 83.2、视觉钮 = 52',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        SizedBox(
          width: 834,
          child: GuardSceneCard(
            view: viewOf(GuardPillMode.pendingFree),
            dayKey: '2026-11-12',
            childId: 'tablet-idle',
            onStart: () {},
            uiScale: 1.3,
          ),
        ),
        const Size(834, 1194),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 卡高随 uiScale 放大（112 → 145.6）。
      expect(
        tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
        closeTo(112 * 1.3, 0.5),
      );
      // 开始钮**插槽**（命中盒，B13.5 口径）= 右簇槽位 64 × 1.3 = 83.2。
      expect(
        tester.getRect(find.byKey(GuardSceneCard.startButtonKey)).width,
        closeTo(64 * 1.3, 0.5),
      );
      // 开始钮**视觉**（内层 SizedBox 40 × 1.3 = 52）。
      expect(
        tester.getRect(find.byKey(GuardSceneCard.startButtonVisualKey)).width,
        closeTo(40 * 1.3, 0.5),
      );
    });

    testWidgets('已完成态（claimed）u=1.3：旗标 = 83.2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        SizedBox(
          width: 834,
          child: GuardSceneCard(
            view: viewOf(GuardPillMode.claimed),
            dayKey: '2026-11-12',
            childId: 'tablet-claimed',
            uiScale: 1.3,
          ),
        ),
        const Size(834, 1194),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(GuardSceneCard.claimedBadgeKey)).width,
        closeTo(64 * 1.3, 0.5),
      );
    });

    testWidgets('免费代劳态（freeRide）u=1.3：归并到胜利旗帜，不再空白',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const SizedBox(
          width: 834,
          child: GuardSceneCard(
            view: GuardTodayView(
              mode: GuardPillMode.freeRide,
              state: GuardDayState(
                dayKey: '2026-11-12',
                status: GuardDayStatus.short,
                thiefKind: GuardThiefKind.sunRat,
              ),
              energyAvailable: 0,
              balance: 0,
            ),
            dayKey: '2026-11-12',
            childId: 'tablet-freeride',
            uiScale: 1.3,
          ),
        ),
        const Size(834, 1194),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 🔴 2026-11-12（玄参「就两种视觉」）：freeRide 原本右簇 shrink 空白，iPad 上
      // 看不出状态；现归并到「胜利旗帜」视觉 ⇒ 旗标必须在树、且不得渲染开始钮。
      expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsOneWidget);
      expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing);
    });
  });
}
