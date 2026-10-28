/// 欢迎页语言切换链路 widget 测试（i18n B1，T02）。
///
/// 覆盖：
///  1. 默认（SP 无存档）→ 测试垫片 system → zh 文案（zh 断言零改动）；
///  2. 点「English」段选 → 同帧切换英文文案 + `AppLocaleController.current` 更新
///     + SP 落盘 `app_language: 'en'`；
///  3. 切回「跟随系统」→ 回 zh（测试垫片）；
///  4. 语言选择与同意标记互不耦合（选语言不写同意标记，同意按钮仍走主流程）。
library consent_language_flow_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';

Future<SharedPreferences> _mockPrefs({
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // 每条用例复位运行期单点（默认 = 测试垫片 zh），避免用例间泄漏。
    AppLocaleController.init(AppLanguage.system);
  });

  testWidgets('默认 zh：欢迎标题 / 合规文案 / 主按钮全为现网中文',
      (WidgetTester tester) async {
    final SharedPreferences prefs = await _mockPrefs();
    AppLocaleController.init(AppLanguage.system, store: SettingsStore(prefs));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: ConsentPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用小小葵番茄钟'), findsOneWidget);
    expect(
      find.textContaining('我们只收集专注时长、打卡等必要数据'),
      findsOneWidget,
    );
    expect(find.text('同意并开始'), findsOneWidget);
    // 三段式语言选择存在（跟随系统 / 简体中文 / English）。
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('点 English：同帧切英文 + current 更新 + SP 落盘 en',
      (WidgetTester tester) async {
    final SharedPreferences prefs = await _mockPrefs();
    AppLocaleController.init(AppLanguage.system, store: SettingsStore(prefs));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: ConsentPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Tiny Sunflower'), findsOneWidget);
    expect(find.text("Let's Start"), findsOneWidget);
    expect(AppLocaleController.current.languageCode, 'en');
    expect(
      prefs.getString('app_language'),
      'en',
      reason: '切换语言必须立即落盘（kPrefAppLanguage）',
    );
  });

  testWidgets('切回「跟随系统」：测试垫片下回 zh，SP 落盘 system',
      (WidgetTester tester) async {
    final SharedPreferences prefs = await _mockPrefs();
    AppLocaleController.init(AppLanguage.system, store: SettingsStore(prefs));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: ConsentPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    // 切英文后段选标签也随语言变为 Follow System。
    await tester.tap(find.text('Follow System'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用小小葵番茄钟'), findsOneWidget);
    expect(AppLocaleController.current.languageCode, 'zh');
    expect(prefs.getString('app_language'), 'system');
  });

  testWidgets('语言选择与同意标记互不耦合', (WidgetTester tester) async {
    final SharedPreferences prefs = await _mockPrefs();
    AppLocaleController.init(AppLanguage.system, store: SettingsStore(prefs));
    // 主按钮会 context.go('/') → 挂一个最小 GoRouter（'/' 即欢迎页）。
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, __) => const ConsentPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // 选语言不写同意标记（首启告知 2.0：同意状态在「政策版本号」键，旧布尔键退役恒 null）。
    expect(prefs.getBool('first_launch_consented'), isNull);
    expect(prefs.getInt('consent_policy_version'), isNull);
    // 点主按钮走主流程：写「当前政策版本号」（版本三要素 / C110）。
    await tester.ensureVisible(find.text("Let's Start"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's Start"));
    await tester.pump();
    expect(prefs.getInt('consent_policy_version'), kPrivacyPolicyVersion);
    expect(prefs.getInt('consent_accepted_at_ms'), isNotNull);
  });
}
