/// 玄参 2026-11-20 真机验收 · **点击战士分态** + **cast/fx 两段分离** widget 护栏。
///
/// 独立期望：待机态弹居中说明卡（不是轻提示 / 不是买断引导）；战斗态 0 格
/// 弹 1s 淡出轻提示；cast 帧只挂战士本体 Key，fx 段不含任何战士形象。
library guard_ultimate_interaction_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart'
    show entitlementProvider;
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart'
    show GuardSceneCard;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show GuardUltimateFx;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_help_dialog.dart'
    show guardUltimateHelpConfirmKey, guardUltimateHelpKey;
import 'package:sunflower_time/presentation/shared/brief_notice.dart'
    show hideBriefNotice;
import 'package:sunflower_time/presentation/shared/premium_gate.dart'
    show onGuardUltimateTap;

GuardTodayView _view(GuardPillMode mode) {
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-01-01',
      status: switch (mode) {
        GuardPillMode.fighting => GuardDayStatus.fighting,
        _ => GuardDayStatus.pending,
      },
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
      tutorialSeen: true,
    ),
    energyAvailable: 1,
    balance: 10,
    isPremium: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bug3 · 点击向日葵战士分态', () {
    testWidgets('待机态：弹屏幕居中用法说明卡 + 知道了（不是轻提示/买断引导）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Localizations(
            locale: const Locale('zh'),
            delegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 390,
                      child: GuardSceneCard(
                        view: _view(GuardPillMode.pendingPaid),
                        dayKey: '2026-01-01',
                        childId: 'seed-0',
                        onStart: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 待机战士帧序列是 loop 播放器 ⇒ 绝不能 pumpAndSettle（永不 settle）。
      await tester.tap(find.byKey(GuardSceneCard.soldierKey),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(guardUltimateHelpKey), findsOneWidget,
          reason: '待机态点战士 = 居中说明卡，不是轻提示');
      expect(
        find.text(AppLocalizationsZh().guard_ultimate_help_title),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizationsZh().guard_ultimate_help_confirm),
        findsOneWidget,
        reason: '必须有「知道了」按钮',
      );

      await tester.tap(find.byKey(guardUltimateHelpConfirmKey));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(guardUltimateHelpKey), findsNothing);
    });

    testWidgets('战斗态 0 格（买断）：弹「请专注去获得能量吧」1s 后淡出消失',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: _GateHost())),
          ),
        ),
      );
      final BuildContext ctx = tester.element(find.byType(_GateHost));

      int allowedCalls = 0;
      onGuardUltimateTap(ctx, hasEnergy: false, onAllowed: () => allowedCalls++);
      await tester.pump(const Duration(milliseconds: 200));

      expect(allowedCalls, 0, reason: '0 格绝不释放');
      expect(
        find.text(AppLocalizationsZh().guard_ultimate_empty_hint_light),
        findsOneWidget,
        reason: '文案精确为「请专注去获得能量吧」',
      );
      // 保持 1s + 淡出 180ms：到 1.5s 时浮层必须已自清（不常驻）。
      await tester.pump(const Duration(milliseconds: 1400));
      expect(
        find.text(AppLocalizationsZh().guard_ultimate_empty_hint_light),
        findsNothing,
        reason: '1 秒后淡出消失，绝不回退 F165 常驻黑条',
      );
      hideBriefNotice(); // 兜底清理，避免污染后续用例
    });
  });

  group('bug5 · cast 帧只在战士本体 / fx 段无战士形象', () {
    testWidgets('cast 播放器带战士本体 Key（由场景卡原位挂载）',
        (WidgetTester tester) async {
      // 直接构造 cast widget：断言它渲染的是带专用 Key 的 27 帧播放器，
      // 而不是另起一个 GuardArt.soldier（那会在战场多出一个战士）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              height: 60,
              child: GuardArt.soldierUltimateCast(
                playToken: 0,
                onComplete: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(GuardArt.ultimateCastKey), findsOneWidget);
    });

    testWidgets('fx 段只含特效 Key，绝无 cast 战士 Key', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GuardUltimateFx(
              anchor: Offset(240, 70),
              uiScale: 1.0,
            ),
          ),
        ),
      );
      expect(find.byKey(GuardUltimateFx.fxKey), findsOneWidget);
      expect(find.byKey(GuardArt.ultimateCastKey), findsNothing,
          reason: 'fx 段（1470×630）是纯特效，不得混入战士释放帧');
    });
  });
}

/// ProviderScope / MaterialApp 之内的最小宿主（门控 helper 需要真实容器）。
class _GateHost extends StatelessWidget {
  const _GateHost();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
