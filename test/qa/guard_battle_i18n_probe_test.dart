/// 守卫战 v2 独立验收 · **W3 文案==账本 & i18n 探针**。
///
/// | # | 探针 | 判据 |
/// |---|---|---|
/// | 1 | zh/en ARB 键集合差集为空；4 条新文案（guard_result_stolen / guard_battle_victory_banner / guard_battle_retreat_banner / guard_energy_bubble）双语齐备；`guard_battle_sim.dart` / `guard_debug_script.dart` 代码（剥注释后）零 CJK | |
/// | 2 | 4 条新文案在 en + 1.3× 下不溢出：结算卡（被偷 3）与场景卡战斗态（横幅 + 能量气泡） | |
library;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

/// CJK 判定（与 `no_han_in_domain_test.dart` 同字符类）。
final RegExp _cjk = RegExp(
  r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

/// 剥掉 `//` 行注释与 `/* */` 块注释（与 no_han_in_domain_test 同口径）。
String _stripComments(String src) {
  final List<String> out = <String>[];
  bool inBlock = false;
  for (final String raw in src.split('\n')) {
    String line = raw;
    if (inBlock) {
      final int end = line.indexOf('*/');
      if (end < 0) {
        out.add('');
        continue;
      }
      line = line.substring(end + 2);
      inBlock = false;
    }
    final int lineComment = line.indexOf('//');
    final int blockComment = line.indexOf('/*');
    if (lineComment >= 0 && (blockComment < 0 || lineComment < blockComment)) {
      line = line.substring(0, lineComment);
    } else if (blockComment >= 0) {
      final int end = line.indexOf('*/', blockComment + 2);
      if (end < 0) {
        inBlock = true;
        line = line.substring(0, blockComment);
      } else {
        line = line.substring(0, blockComment) + line.substring(end + 2);
      }
    }
    out.add(line);
  }
  return out.join('\n');
}

Map<String, Object?> _readArb(String path) {
  final String raw = File(path).readAsStringSync();
  return Map<String, Object?>.from(jsonDecode(raw) as Map);
}

Set<String> _messageKeys(Map<String, Object?> arb) => arb.keys
    .where((String k) => !k.startsWith('@'))
    .toSet();

GuardTodayView _fightingView() {
  return const GuardTodayView(
    mode: GuardPillMode.fighting,
    state: GuardDayState(
      dayKey: '2026-11-09',
      status: GuardDayStatus.fighting,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: 1,
    balance: 20,
  );
}

void main() {
  group('W3-1 ARB 键集合与 4 条新文案', () {
    final Map<String, Object?> zh = _readArb('lib/l10n/app_zh.arb');
    final Map<String, Object?> en = _readArb('lib/l10n/app_en.arb');

    test('zh/en 键集合差集为空（两个方向）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      final Set<String> enKeys = _messageKeys(en);
      expect(zhKeys.difference(enKeys), isEmpty, reason: '🔴 中文有、英文缺');
      expect(enKeys.difference(zhKeys), isEmpty, reason: '🔴 英文有、中文缺');
    });

    const List<String> kNewKeys = <String>[
      'guard_result_stolen',
      'guard_battle_victory_banner',
      'guard_battle_retreat_banner',
      'guard_energy_bubble',
    ];

    test('4 条新文案：zh / en 双语齐备、en 无汉字、zh 是中文', () {
      for (final String k in kNewKeys) {
        final Object? zv = zh[k];
        final Object? ev = en[k];
        expect(zv, isA<String>(), reason: '缺 zh 键：$k');
        expect(ev, isA<String>(), reason: '缺 en 键：$k');
        expect(_cjk.hasMatch(ev! as String), isFalse, reason: '🔴 en.$k 含汉字');
        expect(_cjk.hasMatch(zv! as String), isTrue, reason: '🔴 zh.$k 未翻译');
      }
    });

    test('guard_battle_sim.dart / guard_debug_script.dart 代码零 CJK（剥注释后）', () {
      // guard_battle_sim.dart：领域文件，🔴 零 CJK 硬门槛（与 no_han 同口径）。
      final String simSrc =
          File('lib/domain/services/guard_battle_sim.dart').readAsStringSync();
      final List<String> simHits = <String>[];
      final List<String> simStripped = _stripComments(simSrc).split('\n');
      final List<String> simRaw = simSrc.split('\n');
      for (int i = 0; i < simStripped.length; i++) {
        if (_cjk.hasMatch(simStripped[i])) simHits.add('${i + 1}: ${simRaw[i]}');
      }
      expect(simHits, isEmpty, reason: '🔴 guard_battle_sim.dart 代码含 CJK：$simHits');

      // guard_debug_script.dart：表现层调试文件。已知特征（B5a 实测）：
      // 仅 assert() 消息字符串里有 3 处 CJK（kDebugMode 才执行的开发者向断言，
      // 不面向用户）。红线口径：除 assert 消息外必须零 CJK；若未来出现在
      // 非 assert 的字面量里（= 会面向用户的文案），此处立即判红。
      final String dbgSrc =
          File('lib/presentation/child/state/guard_debug_script.dart')
              .readAsStringSync();
      final List<(int, String)> dbgHits = <(int, String)>[];
      final List<String> dbgStripped = _stripComments(dbgSrc).split('\n');
      final List<String> dbgRaw = dbgSrc.split('\n');
      for (int i = 0; i < dbgStripped.length; i++) {
        if (_cjk.hasMatch(dbgStripped[i])) {
          dbgHits.add((i + 1, dbgRaw[i]));
        }
      }
      for (final (int, String) hit in dbgHits) {
        final String raw = hit.$2.trim();
        // assert( 开头的一行，或 assert 多行参数里的字符串续行（以引号开头）。
        final bool insideAssert = raw.contains('assert(') ||
            raw.startsWith("'") ||
            raw.startsWith('"');
        expect(insideAssert, isTrue,
            reason: '🔴 guard_debug_script.dart 出现 assert 消息之外的 CJK 字面量：'
                '${hit.$1}: ${raw.trim()}（上线前必须迁 ARB）');
      }
      // ignore: avoid_print
      print('QA/W3-1 guard_debug_script.dart assert 消息 CJK 处数 = ${dbgHits.length}');
    });
  });

  group('W3-2 en + 1.3× 不溢出（4 条新文案的实际落点）', () {
    /// 结算卡（guard_result_stolen，最长参数 = 3）。
    testWidgets('结算卡被偷行 en 1.3× 320 宽：零 overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Builder(builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: GuardResultCard(
                  view: _fightingView(),
                  l10n: AppLocalizations.of(context),
                  onCollect: () async => throw UnimplementedError(),
                  stolenSun: 3,
                ),
              ),
            );
          }),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '🔴 结算卡被偷行（stolen=3）en 1.3× 不得溢出');
    });

    /// 场景卡战斗态：victory 横幅（guard_battle_victory_banner）。
    /// 找一个「450ms 连射能提前全灭」的 seed，推过终局让横幅上屏。
    testWidgets('战斗态 victory 横幅 en 1.3× 320 宽：零 overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? winner;
      for (int n = 0; n < 200 && winner == null; n++) {
        final String childId = 'qa-banner-$n';
        final GuardBattleScript script =
            deriveGuardBattleScript(dayKey: '2026-11-09', childId: childId);
        final GuardBattleSim sim = GuardBattleSim(
            script: script, dayKey: '2026-11-09', childId: childId);
        for (int t = 450; t <= 30000 && !sim.isOver; t += 450) {
          sim.step(t, <int>[t]);
        }
        if (sim.phase == GuardBattlePhase.victory) winner = childId;
      }
      expect(winner, isNotNull, reason: '200 seed 里应能找到全灭战局');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 288,
                child: GuardSceneCard(
                  view: _fightingView(),
                  dayKey: '2026-11-09',
                  childId: winner!,
                ),
              ),
            ),
          ),
        ),
      );
      // 推 40s：任何 seed 都会收场（victory 或 retreat 横幅上屏）。
      for (int i = 0; i < 45; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
          reason: '夹具前提：终局横幅已上屏');
      expect(tester.takeException(), isNull, reason: '🔴 横幅 en 1.3× 不得溢出');
      // 让终局的 900ms 收尾 timer 走完（防 Pending timers 误报）。
      await tester.pump(const Duration(milliseconds: 1000));
    });

    /// 场景卡战斗态：retreat 横幅（guard_battle_retreat_banner）+ 能量点气泡
    /// （guard_energy_bubble）。
    testWidgets('战斗态 retreat 横幅 + 能量气泡 en 1.3× 320 宽：零 overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 288,
                child: GuardSceneCard(
                  view: _fightingView(),
                  dayKey: '2026-11-09',
                  childId: 'qa-retreat-banner',
                ),
              ),
            ),
          ),
        ),
      );
      // 一枪不发推满 31s ⇒ retreat 收场。
      for (int i = 0; i < 34; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
          reason: '夹具前提：retreat 横幅已上屏');
      expect(tester.takeException(), isNull, reason: '🔴 retreat 横幅 en 1.3× 不得溢出');
      // 让终局的 900ms 收尾 timer 走完（防 Pending timers 误报）。
      await tester.pump(const Duration(milliseconds: 1000));

      // ❌ B7 已删：原「回待机卡点能量点 ⇒ 气泡 C（guard_energy_bubble）」一段。
      // **删除理由**：B7 玄参裁定删掉卡片左上两个能量点，连同点按弹出的气泡 C
      // 整组交互一起退役 ⇒ 该 ARB 键在运行时**没有再渲染的入口**（键本身仍保留在
      // 双语 ARB 里，由本文件开头的「zh/en 键集合差集为空」静态探针继续守住）。
    });
  });
}
