/// 花园守卫独立验收 · **V7 i18n 剩余项**
///
/// ① `test/i18n/no_han_in_domain_test.dart` 已单独跑（7 例全绿），本文件不重复；
/// ② 中英 ARB **键集合完全一致**：不用 Python，直接在本测试里读两份 ARB 逐键比对
///    （含「守卫相关键在英文里不得出现汉字」）；
/// ③ L4 战斗层 en + 1.3 倍字号不 overflow（结算卡见 V5-2）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

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

  group('V7-3 L4 战斗层 en + 1.3×（B3 迁移：原夹具为 GuardBattleOverlay）', () {
    testWidgets('288×140 卡内槽位不 overflow', (WidgetTester tester) async {
      // 三个固定 seed（代替旧版的 3 种贼循环）：剧本阵容不同 ⇒ 横幅 / 怪物
      // 渲染分支都被走到；seed 不含当日日期 ⇒ 判定逐日稳定。
      const List<String> childIds = <String>['seed-0', 'seed-1', 'seed-2'];
      for (final String childId in childIds) {
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
                    body: Center(
                      child: SizedBox(
                        width: 288,
                        height: 140,
                        child: GuardBattleField(
                          dayKey: '2026-01-01',
                          childId: childId,
                          handle: GuardBattleHandle(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // 推进 2s：首怪已在车道上行走（剧本出怪表首项 = 0ms）。
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: '$childId 战斗层溢出');
      }
    });
  });
}
