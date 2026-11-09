/// 花园守卫独立验收 · **V7 i18n 剩余项**
///
/// ① `test/i18n/no_han_in_domain_test.dart` 已单独跑（7 例全绿），本文件不重复；
/// ② 中英 ARB **键集合完全一致**：不用 Python，直接在本测试里读两份 ARB 逐键比对
///    （含「守卫相关键在英文里不得出现汉字」）；
/// ③ 战斗浮层 en + 1.3 倍字号不 overflow（结算卡见 V5-2）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_overlay.dart';

Map<String, Object?> _readArb(String path) {
  final String raw = File(path).readAsStringSync();
  return Map<String, Object?>.from(jsonDecode(raw) as Map);
}

/// ARB 里 `@key` 是元数据，不算文案键。
Set<String> _messageKeys(Map<String, Object?> arb) => arb.keys
    .where((String k) => !k.startsWith('@'))
    .toSet();

final RegExp _han = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]');

void main() {
  group('V7-1 中英 ARB 键集合一致', () {
    final Map<String, Object?> zh = _readArb('lib/l10n/app_zh.arb');
    final Map<String, Object?> en = _readArb('lib/l10n/app_en.arb');

    test('键集合差集为空（两个方向都查）', () {
      final Set<String> zhKeys = _messageKeys(zh);
      final Set<String> enKeys = _messageKeys(en);
      expect(zhKeys.length, greaterThan(900), reason: '键数异常 ⇒ 读错文件');
      expect(zhKeys.difference(enKeys), isEmpty, reason: '🔴 中文有、英文缺');
      expect(enKeys.difference(zhKeys), isEmpty, reason: '🔴 英文有、中文缺');
      expect(zhKeys.length, enKeys.length);
    });

    test('守卫相关键在英文里不得含汉字', () {
      final List<String> guardKeys = _messageKeys(en)
          .where((String k) =>
              k.startsWith('guard_') ||
              k.startsWith('garden_guard_') ||
              k == 'child_hist_ref_guard_pay' ||
              k == 'child_hist_ref_guard_win' ||
              k == 'child_hist_ref_guard_stolen')
          .toList();
      expect(guardKeys.length, greaterThan(25), reason: '守卫键数异常');
      for (final String k in guardKeys) {
        final Object? v = en[k];
        if (v is String) {
          expect(_han.hasMatch(v), isFalse, reason: '🔴 $k = "$v" 含汉字');
        }
      }
    });

    test('守卫键在中文里必须是中文（防「英文占位没翻译」）', () {
      for (final String k in <String>[
        'guard_pill_pending_free',
        'guard_pill_fighting',
        'guard_result_collect',
        'garden_guard_buff_water',
        'child_hist_ref_guard_pay',
      ]) {
        final Object? v = zh[k];
        expect(v, isA<String>(), reason: '缺键：$k');
        expect(_han.hasMatch(v! as String), isTrue, reason: '🔴 $k = "$v" 未翻译');
      }
    });
  });

  group('V7-3 战斗浮层 en + 1.3×', () {
    testWidgets('320 宽槽位不 overflow', (WidgetTester tester) async {
      final AppLocalizations en = await AppLocalizations.delegate.load(
        const Locale('en'),
      );

      for (final GuardThiefKind thief in GuardThiefKind.values) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Localizations(
              locale: const Locale('en'),
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
                    body: SizedBox(
                      width: 320,
                      height: 568,
                      child: GuardBattleOverlay(thief: thief, l10n: en),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // 推过 600ms：跳过按钮出现后仍不溢出。
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull, reason: '${thief.id} 战斗浮层溢出');
      }
    });
  });
}
