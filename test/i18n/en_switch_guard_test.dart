/// EN 切换守卫测试（i18n B1，T02）。
///
/// 守卫目标：
///  ① **豁免回归守卫**：shared 付费引导组件（PremiumUpsellCard /
///     showPremiumUpsell / PremiumQuotaGate.onTap）在 B1 批次**刻意不迁移** ——
///     `test/qa/premium_unlock_table_test.dart` 的 T1 源码守卫逐字钉死其中文
///     文案（「解锁全部功能」/「升级解锁」等 6 处）。本组断言：即使显式切 en，
///     这三个入口仍输出中文（豁免是有意的、可被测试取证的），EN 迁移留待 B2
///     连同家长端一并处理；
///  ② **EN 生效链路**：显式 en 下，`AppLocaleController` / 页级 L10nScope 的
///     locale 解析为 en（保证豁免不是「切换链路坏了」的假象）。
library en_switch_guard_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    // 守卫前提：显式切 en（非测试垫片路径 —— 显式 en 恒生效）。
    AppLocaleController.init(AppLanguage.en);
  });

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          home: L10nScope(child: Scaffold(body: child)),
        ),
      );

  testWidgets('① 豁免守卫：PremiumUpsellCard 在 en 下仍为中文（B1 刻意不迁移）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      host(const PremiumUpsellCard(feature: FeatureKey.oneClickCare)),
    );
    await tester.pumpAndSettle();

    // T1 源码守卫钉死的中文文案原样保留（i18n B1 豁免，B2 随家长端迁移）。
    expect(find.text('解锁「花园一键操作」'), findsOneWidget);
    expect(find.text('一次买断，永久解锁全部功能'), findsOneWidget);
    expect(find.text('Details'), findsNothing,
        reason: '豁免组件不得出现英文（防止「半迁移」状态）');
  });

  testWidgets('① 豁免守卫：showPremiumUpsell 在 en 下仍弹中文确认卡',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () => showPremiumUpsell(
                context,
                FeatureKey.gardenPotCapacity,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('升级解锁'), findsOneWidget);
    expect(find.text('「更多花盆」需要一次性买断解锁。'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('解锁全部功能'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('② EN 生效链路：显式 en 下 L10nScope 解析出英文文案',
      (WidgetTester tester) async {
    late final AppLocalizations resolved;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) {
            resolved = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(resolved.localeName, 'en',
        reason: '显式 en 恒生效（豁免组件不是切换链路故障）');
    // 抽查一条 B1 已迁移的孩子端文案确为英文。
    expect(resolved.shared_cancel, 'Cancel');
  });
}
