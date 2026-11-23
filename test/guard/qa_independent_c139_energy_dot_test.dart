/// QA 独立验证 · C139（玄参测试服反馈）：
/// 守卫模式免费用户第二个能量球，由「锁图标」改成与向日葵战士头顶大招能量条
/// 免费档一致的**灰色虚线空槽**（灰 0xFF9E9E9E / dash 4-3 / 线宽 1.2）。
///
/// ## 与工程师自测的独立性
/// 不复用 `test/guard/guard_scene_card_test.dart` 的用例结构；本文件自建夹具，
/// 并**直接读取 CustomPaint.painter 的公开字段**（color/strokeWidth/dashWidth/
/// dashSpace）做量化断言 —— 这比「只验 painter 类型名」更硬，能挡住「换了 painter
/// 但参数值随手写了 1.0」这类漏网。
///
/// ## 可验边界
/// headless 可证「锁图标缺席 + painter 被创建 + 参数值与头顶能量条免费档一致 +
/// 亮/灭/付费两态与点按提示未变」。像素级观感（虚线是否真圆、灰度是否肉眼一致）
/// 需真机确认，见文件末尾。
library qa_independent_c139_energy_dot_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

const Color _kExpectedDash = Color(0xFF9E9E9E);
const double _kExpectedDashWidth = 4.0;
const double _kExpectedDashSpace = 3.0;
const double _kExpectedStroke = 1.2;

GuardTodayView _view(
  GuardPillMode mode, {
  int energy = 0,
  bool isPremium = false,
}) {
  return GuardTodayView(
    mode: mode,
    state: const GuardDayState(
      dayKey: '2026-01-01',
      status: GuardDayStatus.pending,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
      tutorialSeen: false,
    ),
    energyAvailable: energy,
    balance: 0,
    isPremium: isPremium,
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  GuardTodayView view, {
  double width = 288,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 568),
        textScaler: TextScaler.linear(1.0),
      ),
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
                  width: width,
                  child: GuardSceneCard(
                    view: view,
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
}

/// 取某个能量点槽位下的 CustomPaint（若无则 finder 为 empty）。
Finder _dotPainterFinder(int index) => find.descendant(
      of: find.byKey(GuardSceneCard.energyDotKey(index)),
      matching: find.byType(CustomPaint),
    );

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // L · 锁图标缺席 + 虚线 painter 被创建且参数与头顶能量条免费档一致
  // ══════════════════════════════════════════════════════════════════════════
  group('L · 免费档第二颗 = 灰色虚线空槽', () {
    testWidgets('L1：免费档 energy=1 —— 无锁图标，dot1 画虚线圆且参数量化正确',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 1));

      // 锁图标彻底缺席（C139 核心：不再上锁）。
      expect(find.byIcon(Icons.lock_rounded), findsNothing,
          reason: 'C139：免费档第二颗不得再显示锁标');
      expect(find.text('会员双能量'), findsNothing,
          reason: '卡内零文本纪律不因 C139 破坏');

      // dot1 必须是 CustomPaint（虚线画师），且恰好一个。
      expect(_dotPainterFinder(1), findsOneWidget,
          reason: '第二颗应由 CustomPaint 画虚线空槽');

      final CustomPaint cp = tester.widget<CustomPaint>(_dotPainterFinder(1));
      expect(cp.painter, isNotNull, reason: 'painter 必须真实存在');
      // 直接读公开字段（私有类上的 public getter，dynamic 派发可读）。
      final dynamic p = cp.painter;
      expect(p.runtimeType.toString(), contains('DashedEnergyDotPainter'),
          reason: '必须是虚线点画师而非其它 painter');
      expect(p.color, _kExpectedDash,
          reason: 'C139：灰色必须是 0xFF9E9E9E（与头顶能量条免费档一致）');
      expect(p.dashWidth, _kExpectedDashWidth, reason: 'dash 实线 4pt');
      expect(p.dashSpace, _kExpectedDashSpace, reason: 'dash 空白 3pt');
      expect(p.strokeWidth, _kExpectedStroke, reason: '线宽 1.2pt（uiScale=1.0）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('L2：免费档 energy=0 —— dot1 仍虚线（锁定态与能量数值无关）',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 0));

      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(_dotPainterFinder(1), findsOneWidget,
          reason: '第二颗是「权限锁定」而非「能量不足」，任何 energy 下都应是虚线空槽');
      final dynamic p =
          tester.widget<CustomPaint>(_dotPainterFinder(1)).painter;
      expect(p.color, _kExpectedDash);
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S · 亮/灭两态 + 付费两颗表现零回归
  // ══════════════════════════════════════════════════════════════════════════
  group('S · 其它三态零回归', () {
    testWidgets('S1：免费档 energy=1 —— dot0 金色实心（原样），dot1 才是虚线',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 1));

      final DecoratedBox d0 = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(GuardSceneCard.energyDotKey(0)),
          matching: find.byType(DecoratedBox),
        ),
      );
      final BoxDecoration dec0 = d0.decoration as BoxDecoration;
      expect(dec0.color, const Color(0xFFFFC93C),
          reason: '第 1 颗攒满 = 金色实心，未被 C139 波及');
      expect(_dotPainterFinder(0), findsNothing,
          reason: '第 1 颗不得画虚线');
    });

    testWidgets('S2：免费档 energy=0 —— dot0 空心灰环（原样）',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 0));

      final DecoratedBox d0 = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(GuardSceneCard.energyDotKey(0)),
          matching: find.byType(DecoratedBox),
        ),
      );
      final BoxDecoration dec0 = d0.decoration as BoxDecoration;
      expect(dec0.color, const Color(0x00000000),
          reason: '第 1 颗未攒满 = 透明底 + 灰环，原样');
      expect(_dotPainterFinder(0), findsNothing);
    });

    testWidgets('S3：付费档 energy=2 —— 两颗都金色实心，无虚线、无锁标',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(GuardPillMode.pendingFree, energy: 2, isPremium: true),
      );

      expect(_dotPainterFinder(0), findsNothing,
          reason: '付费第 1 颗不得画虚线');
      expect(_dotPainterFinder(1), findsNothing,
          reason: '🔴 付费第 2 颗照常亮/灭，绝不能被 C139 的虚线分支吃掉');
      expect(find.byIcon(Icons.lock_rounded), findsNothing);

      for (int i = 0; i < 2; i++) {
        final DecoratedBox d = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(GuardSceneCard.energyDotKey(i)),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect((d.decoration as BoxDecoration).color, const Color(0xFFFFC93C),
            reason: '付费 energy=2 ⇒ 两颗都攒满金色');
      }
    });

    testWidgets('S4：付费档 energy=1 —— 第 2 颗空心灰环（灭态原样）',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(GuardPillMode.pendingFree, energy: 1, isPremium: true),
      );

      expect(_dotPainterFinder(1), findsNothing,
          reason: '付费第 2 颗走「灭态灰环」而非虚线锁定态');
      final DecoratedBox d1 = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(GuardSceneCard.energyDotKey(1)),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect((d1.decoration as BoxDecoration).color, const Color(0x00000000),
          reason: '付费第 2 颗未攒满 = 透明底灰环');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // T · 点按提示卡 / 权限与能量累计逻辑未变
  // ══════════════════════════════════════════════════════════════════════════
  group('T · 交互与规则未变', () {
    testWidgets('T1：点免费档第二颗 → 只弹 C81 提示卡，无购买入口、不跳转',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 1));

      await tester.tap(find.byKey(GuardSceneCard.energyDotKey(1)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(GuardSceneCard.energyLockedHintKey), findsOneWidget,
          reason: '虚线空槽仍可点，必须弹 C81 提示卡');
      expect(find.text('完整版每天有 2 颗能量点哦'), findsOneWidget,
          reason: '提示卡正文不变（B13.9 完整版口径）');
      expect(find.byType(GuardSceneCard), findsOneWidget,
          reason: 'C81：无路由跳转，仍在本页');
      expect(tester.takeException(), isNull);
    });

    test('T2：源码守卫 —— 权限 / 能量规则 / 头顶能量条参数未被改动', () {
      const String card =
          'lib/presentation/child/widgets/guard_scene_card.dart';
      const String bar =
          'lib/presentation/child/widgets/guard_ultimate_energy_bar.dart';
      final String cardSrc = File(card).readAsStringSync();
      final String barSrc = File(bar).readAsStringSync();

      // 本轮只允许「显示层」改变：锁定判定 / 能量累计口径必须原样。
      expect(
        cardSrc.contains('locked: !widget.view.isPremium && i == 1'),
        isTrue,
        reason: '免费档锁定判定未变（仍由 isPremium 决定，非能量数值）',
      );
      expect(
        cardSrc.contains('i == 0 && view.energyAvailable >= 1'),
        isTrue,
        reason: '免费档第 1 颗亮 = energy>=1 的能量规则未变',
      );
      expect(cardSrc.contains('_showEnergyLockedHint(t)'), isTrue,
          reason: '点按弹提示卡逻辑仍在');
      expect(cardSrc.contains('Icons.lock_rounded'), isFalse,
          reason: '🔴 锁图标必须从源码消失（变异：换回锁标 ⇒ 必红）');
      expect(cardSrc.contains('CustomPaint('), isTrue,
          reason: '改由 CustomPaint 承载虚线');

      // 虚线参数与头顶能量条免费档逐项一致。
      expect(cardSrc.contains('const Color _kLockedEnergyDashColor = '
          'Color(0xFF9E9E9E);'), isTrue);
      expect(cardSrc.contains('const double _kLockedEnergyDashWidth = 4.0;'),
          isTrue);
      expect(cardSrc.contains('const double _kLockedEnergyDashSpace = 3.0;'),
          isTrue);
      expect(cardSrc.contains('const double _kLockedEnergyDashStroke = 1.2;'),
          isTrue);
      expect(barSrc.contains('static const Color _lockedBorder = '
          'Color(0xFF9E9E9E);'), isTrue,
          reason: '头顶能量条免费档灰度基准未被改');
      expect(barSrc.contains('static const double _dashWidth = 4.0;'), isTrue);
      expect(barSrc.contains('static const double _dashSpace = 3.0;'), isTrue);
      expect(barSrc.contains('static const double _dashStrokeWidth = 1.2;'),
          isTrue);

      // 能量上限常量未被改动（权限档位口径）。
      expect(kGuardEnergyDailyMaxFree > 0, isTrue,
          reason: '免费档能量上限常量仍存在');
    });
  });
}

// ── 需真机确认的观感项 ──────────────────────────────────────────────────────
// 1. 虚线圆与战士头顶大招能量条免费档「肉眼一致」（headless 只证参数相同）。
// 2. 平板 uiScale>1 时 dash 4-3 / 线宽 1.2 按比例放大的实际观感。
