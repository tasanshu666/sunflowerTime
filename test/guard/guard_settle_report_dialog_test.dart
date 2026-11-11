/// 次日结算报告弹窗（B13.4）单测。
///
/// 🔴 覆盖三件事：
/// 1. `guardSettleHasNews` 纯函数：none / 零损失 ⇒ 不弹；有损失 / 有补发 ⇒ 弹；
/// 2. 弹窗内容随结算结果逐行变化（阳光 / 成长 / 补发三行可叠加）；
/// 3. 「知道了」关闭。
library guard_settle_report_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_settle_report_dialog.dart';

GuardExpireOutcome _outcome({
  bool settled = true,
  int sun = 0,
  int growth = 0,
  int win = 0,
}) {
  return GuardExpireOutcome(
    today: '2026-11-11',
    expiredDayKey: '2026-11-10',
    settled: settled,
    stolenSun: sun,
    growthTargets: growth,
    grantedWinSun: win,
  );
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showGuardSettleReport(
              ctx,
              AppLocalizations.of(ctx),
              _outcome(sun: 3, growth: 2),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('guardSettleHasNews：none / 全零 ⇒ false；有损失 / 补发 ⇒ true', () {
    expect(guardSettleHasNews(const GuardExpireOutcome.none('2026-11-11')),
        isFalse);
    expect(guardSettleHasNews(_outcome(settled: false, sun: 3)), isFalse,
        reason: 'settled == false（同日空操作）绝不弹');
    expect(guardSettleHasNews(_outcome()), isFalse,
        reason: '结算了但零损失零补发（claimed / short 过期）⇒ 没什么可说，不弹');
    expect(guardSettleHasNews(_outcome(sun: 3)), isTrue);
    expect(guardSettleHasNews(_outcome(growth: 2)), isTrue);
    expect(guardSettleHasNews(_outcome(win: 2)), isTrue,
        reason: 'fighting 补发也是「新闻」（好消息也要说）');
  });

  testWidgets('损失场景：标题 + 阳光行 + 成长行 + 引导语逐行上屏',
      (WidgetTester tester) async {
    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('guardSettleReport')), findsOneWidget);
    expect(find.text('昨晚小怪来过了'), findsOneWidget);
    expect(find.text('小怪偷走了 3 阳光。'), findsOneWidget);
    expect(find.text('2 棵植物的成长被偷吃了一些。'), findsOneWidget);
    expect(find.textContaining('收进账'), findsNothing,
        reason: '没有补发就不该出现补发行');
    expect(find.text('今天记得回来守卫菜园哦！'), findsOneWidget);
  });

  testWidgets('补发场景（昨天打了没收奖励）：只出补发行', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showGuardSettleReport(
                ctx,
                AppLocalizations.of(ctx),
                _outcome(win: 2),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.textContaining('已经帮你把 2 阳光奖励收进账'), findsOneWidget);
    expect(find.textContaining('偷走'), findsNothing);
  });

  testWidgets('无新闻调用 showGuardSettleReport ⇒ 不弹任何东西',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showGuardSettleReport(
                ctx,
                AppLocalizations.of(ctx),
                _outcome(), // settled 但全零
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('guardSettleReport')), findsNothing);
  });

  testWidgets('点「知道了」⇒ 弹窗关闭', (WidgetTester tester) async {
    await _pumpHost(tester);
    await tester.tap(find.text('open'));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('guardSettleOk')));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('guardSettleReport')), findsNothing);
  });
}
