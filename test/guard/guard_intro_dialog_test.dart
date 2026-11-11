/// 守卫战玩法说明弹窗（B13.2 冒烟）。
///
/// 🔴 背景：首版弹窗的图鉴 Row 用 `CrossAxisAlignment.stretch`，在
/// SingleChildScrollView 的**无界高度**里硬崩 —— 真机表现为「遮罩变暗、
/// 内容不渲染、无法交互只能杀进程」，而 widget 测试从未覆盖（本文件就是
/// 那次的补课）：只要 `guardIntroDialog` Key 上屏且 `takeException` 为空，
/// 旧实现必红。
library guard_intro_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleMonsterKind;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_intro_dialog.dart';

Future<SharedPreferences> _pump(WidgetTester tester,
    {Map<String, Object> prefs = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences sp = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
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
              onPressed: () =>
                  showGuardIntroDialog(ctx, AppLocalizations.of(ctx)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return sp;
}

Future<void> _openAndSettle(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('弹窗能完整渲染（🔴 旧版 stretch 在无界高度下必红）',
      (WidgetTester tester) async {
    await _pump(tester);
    await _openAndSettle(tester);

    expect(tester.takeException(), isNull,
        reason: '🔴 弹窗内容崩 = 真机「变暗且无法操作」的直接根因');
    expect(find.byKey(const Key('guardIntroDialog')), findsOneWidget);
    expect(find.byKey(const Key('guardIntroOk')), findsOneWidget);
  });

  testWidgets('B13.3 新增两节上屏：能量点是什么 / 今天不打会怎样',
      (WidgetTester tester) async {
    await _pump(tester);
    await _openAndSettle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('能量点是什么'), findsOneWidget);
    expect(
        find.textContaining('专注赢来的免费出战次数'), findsOneWidget);
    expect(find.textContaining('没有能量点也能守卫'), findsOneWidget);
    expect(find.text('今天不打会怎样'), findsOneWidget);
    expect(find.textContaining('第二天打开花园时就会真的扣掉'), findsOneWidget);
  });

  testWidgets('空 prefs = 三只全锁定（锁图标 + 未遇到文案）',
      (WidgetTester tester) async {
    await _pump(tester);
    await _openAndSettle(tester);

    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(3));
    expect(find.text('还没遇到过'), findsNWidgets(3));
  });

  testWidgets('prefs 已解锁 m1/m2 ⇒ 两张亮卡、只有 m3 带锁',
      (WidgetTester tester) async {
    await _pump(tester, prefs: <String, Object>{
      kGuardMetMonstersPrefKey: <String>['m1', 'm2'],
    });
    await _openAndSettle(tester);

    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('还没遇到过'), findsOneWidget);
    expect(find.text('馋光鼠'), findsOneWidget);
    expect(find.text('食叶虫'), findsOneWidget);
  });

  testWidgets('点「知道了」⇒ 弹窗关闭', (WidgetTester tester) async {
    await _pump(tester);
    await _openAndSettle(tester);

    // 🔴 B13.3：弹窗加了「能量点 / 今天不打」两节后内容变高，默认 800×600
    // 测试视口里按钮可能滚出屏外 —— 先确保可见再点（真机上本来就是滚动的）。
    await tester.ensureVisible(find.byKey(const Key('guardIntroOk')));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('guardIntroOk')));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('guardIntroDialog')), findsNothing);
  });

  test('recordMetMonsterKinds：合并去重 + 排序落盘', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kGuardMetMonstersPrefKey: <String>['m2'],
    });
    final SharedPreferences sp = await SharedPreferences.getInstance();

    await recordMetMonsterKinds(
        <GuardBattleMonsterKind>[
          GuardBattleMonsterKind.m3,
          GuardBattleMonsterKind.m2,
        ],
        sp);

    expect(sp.getStringList(kGuardMetMonstersPrefKey), <String>['m2', 'm3']);
  });
}
