/// F154 语言即时切换 + 种子单位「粒」回归测试（2026-10-26 玄参实测反馈）。
///
/// 两个锚点：
///  ① **语言切换必须同帧生效**：已挂载的 L10nScope 页面在切换语言后立即
///     显示新语言文案，不得要求「退出重进」才切（家长端设置页实测 bug）。
///     机制：`AppLocaleController.revision` 变更通知 → L10nScope 重建 →
///     `Localizations` 新 locale → 标准依赖通知刷新全部文案。
///  ② **种子单位 = 粒**：种植确认卡「{count} 粒 / 种下后剩余 {count} 粒」，
///     zh ARB 钉死不得回退成量词「张」（种子按粒计，截图反馈 2026-10-26）。
library l10n_scope_live_switch_test;

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

void main() {
  // 测试垫片：AppLocaleController.current 默认 zh（FLUTTER_TEST 环境）。
  // 本文件会真实切换语言，结束前必须还原，避免静态态泄漏到后续用例。

  testWidgets('F154-① 切换语言后已挂载页面同帧换文案（无需重建页面）',
      (WidgetTester tester) async {
    AppLocaleController.current = const Locale('zh');

    await tester.pumpWidget(
      MaterialApp(
        // 故意不挂 delegates：文案必须经页级 L10nScope 解析（与现网页面同构）。
        home: L10nScope(
          child: Builder(
            builder: (BuildContext context) {
              final AppLocalizations t = AppLocalizations.of(context);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(t.garden_row_use_seed('精英')),
                  Text(t.garden_seed_count(1)),
                  Text(t.garden_seed_remaining(0)),
                ],
              );
            },
          ),
        ),
      ),
    );

    // 初始 zh：种子单位「粒」。
    expect(find.text('使用精英种子'), findsOneWidget);
    expect(find.text('1 粒'), findsOneWidget);
    expect(find.text('种下后剩余 0 粒'), findsOneWidget);

    // 切英文（测试环境：不落盘、无 provider 回调）→ 同帧生效。
    await AppLocaleController.set(AppLanguage.en);
    await tester.pump();

    expect(find.text('Use 精英 seed'), findsOneWidget);
    // F154：en 量词补单位（复数 1 seed / N seeds，不再是裸数字）。
    expect(find.text('1 seed'), findsOneWidget);
    expect(find.text('0 seeds left after planting'), findsOneWidget);
    expect(find.text('1 粒'), findsNothing,
        reason: '旧语言文案必须消失（不得出现中英混排）');

    // 还原静态态。
    await AppLocaleController.set(AppLanguage.zh);
    await tester.pump();
    expect(find.text('1 粒'), findsOneWidget);
  });

  test('F154-② zh ARB 种子单位钉死为「粒」（防回退「张」）', () {
    final String arb = File('lib/l10n/app_zh.arb').readAsStringSync();
    expect(arb.contains('"garden_seed_count": "{count} 粒"'), isTrue,
        reason: '种植确认卡数量行：种子按粒计，不是「张」');
    expect(arb.contains('"garden_seed_remaining": "种下后剩余 {count} 粒"'),
        isTrue, reason: '种植确认卡小结行：种子按粒计，不是「张」');
    expect(arb.contains('{count} 张'), isFalse,
        reason: '全 ARB 不得再用「张」作种子量词（卡片/碎片是「片」、护眼另有键）');
  });
}
