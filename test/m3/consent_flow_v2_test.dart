/// 首启告知 2.0（C110）· 同意流全链 widget / store 测试。
///
/// 覆盖：
///  1. **版本三要素**：`SettingsStore.consentedPolicyVersion()` —— 新装 0 /
///     v1 旧布尔键迁移为 1 / `acceptCurrentPolicyConsent()` 写版本号+时刻；
///  2. **ConsentPage 首启形态**：不同意 + 同意并开始 双按钮 / 查看完整隐私政策
///     入口 / 数据清单 4 行 / 无「政策已更新」提示条；
///  3. **不同意分支**：说明卡弹出（再想想 / 退出应用），再想想关闭且不写同意；
///  4. **同意主流程**：写当前政策版本号 + 跳转（mini GoRouter 真实入口）；
///  5. **重弹机制**：记录版本 1（< 当前 2）→ 顶部「政策已更新 v2」提示条；
///     已记录当前版本 → 无提示条；
///  6. **应用内政策全文页**：zh 章节齐全（含 §10.3）+ en 切换换文；
///  7. **家长设置入口**（接线守）：从设置页「数据与隐私」区真实点进 `/privacy-policy`。
library consent_flow_v2_test;

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
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';
import 'package:sunflower_time/presentation/shared/privacy_policy_page.dart';

Future<SharedPreferences> _mockPrefs({
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

/// 裸宿主（无路由）：首启形态 / 弹窗 / 提示条断言用。
Future<void> _pumpConsent(
  WidgetTester tester,
  SharedPreferences prefs,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: ConsentPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  group('SettingsStore · 政策版本三要素', () {
    test('新装：0 / 未同意当前版本 / 无同意时刻', () async {
      final SharedPreferences prefs = await _mockPrefs();
      final SettingsStore store = SettingsStore(prefs);
      expect(await store.consentedPolicyVersion(), 0);
      expect(await store.isCurrentPolicyConsented(), isFalse);
      expect(await store.consentAcceptedAtMs(), isNull);
    });

    test('v1 旧布尔键迁移：true → 记录版本 1（< 当前 2 → 路由守卫会重弹）', () async {
      final SharedPreferences prefs =
          await _mockPrefs(initial: <String, Object>{
        kPrefFirstLaunchConsented: true,
      });
      final SettingsStore store = SettingsStore(prefs);
      expect(await store.consentedPolicyVersion(), 1);
      expect(await store.isCurrentPolicyConsented(), isFalse,
          reason: 'v1 老用户升级后应重弹一次同意页（§10.3 重新确认机制）');
    });

    test('acceptCurrentPolicyConsent：写当前版本号 + 时刻，且不再写旧布尔键', () async {
      final SharedPreferences prefs = await _mockPrefs();
      final SettingsStore store = SettingsStore(prefs);
      await store.acceptCurrentPolicyConsent();
      expect(await store.consentedPolicyVersion(), kPrivacyPolicyVersion);
      expect(await store.isCurrentPolicyConsented(), isTrue);
      expect(await store.consentAcceptedAtMs(), isNotNull);
      expect(prefs.getBool(kPrefFirstLaunchConsented), isNull,
          reason: '新代码不得再写 v1 遗留布尔键');
    });
  });

  group('ConsentPage · 首启形态', () {
    testWidgets('双按钮 + 条款入口 + 数据清单 4 行，无更新提示条',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      await _pumpConsent(tester, prefs);

      expect(find.text('同意并开始'), findsOneWidget);
      expect(find.byKey(kConsentDisagreeKey), findsOneWidget,
          reason: 'C110：必须有「不同意」选项');
      expect(find.byKey(kConsentViewPolicyKey), findsOneWidget,
          reason: 'C110：必须有条款应用内入口');
      expect(find.text('这个应用里有哪些数据'), findsOneWidget);
      expect(find.text('专注计时与任务打卡记录'), findsOneWidget);
      expect(find.text('花园植物与孩子资料（昵称、头像）'), findsOneWidget);
      expect(find.text('全部加密存储在本机，卸载即彻底删除'), findsOneWidget);
      expect(find.text('无账号、无广告、无追踪，不联网上传'), findsOneWidget);
      expect(find.byKey(kConsentUpdateNoticeKey), findsNothing,
          reason: '首启（从未同意）不得显示「政策已更新」提示条');
      expect(find.textContaining('我们只收集专注时长、打卡等必要数据'), findsOneWidget,
          reason: '合规摘要文案一字不改');
    });

    testWidgets('不同意 → 说明卡（再想想 / 退出应用）；再想想关闭且不写同意',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      await _pumpConsent(tester, prefs);

      await tester.ensureVisible(find.byKey(kConsentDisagreeKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kConsentDisagreeKey));
      await tester.pumpAndSettle();

      expect(find.text('为什么需要同意？'), findsOneWidget);
      expect(find.text('再想想'), findsOneWidget);
      expect(find.text('退出应用'), findsOneWidget);
      expect(find.textContaining('不会上传到任何服务器'), findsOneWidget);

      await tester.tap(find.text('再想想'));
      await tester.pumpAndSettle();
      expect(find.text('为什么需要同意？'), findsNothing);
      expect(await SettingsStore(prefs).consentedPolicyVersion(), 0,
          reason: '「再想想」只是关弹窗，绝不能写同意状态');
    });

    testWidgets('同意并开始（真实路由入口）→ 写当前版本号 + 跳转',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      final GoRouter router = GoRouter(
        initialLocation: '/consent',
        routes: <RouteBase>[
          GoRoute(
            path: '/consent',
            builder: (_, __) => const ConsentPage(),
          ),
          GoRoute(
            path: '/',
            builder: (_, __) =>
                const Scaffold(key: Key('home-probe'), body: Text('HOME')),
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

      await tester.ensureVisible(find.text('同意并开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意并开始'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-probe')), findsOneWidget,
          reason: '同意后应进入主流程');
      expect(await SettingsStore(prefs).consentedPolicyVersion(),
          kPrivacyPolicyVersion);
    });
  });

  group('ConsentPage · 重弹机制（§10.3）', () {
    testWidgets('记录版本 1 < 当前 2 → 顶部「政策已更新 v2」提示条',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(initial: <String, Object>{
        kPrefConsentPolicyVersion: 1,
      });
      await _pumpConsent(tester, prefs);
      expect(find.byKey(kConsentUpdateNoticeKey), findsOneWidget);
      expect(find.textContaining('隐私政策已更新（v2）'), findsOneWidget);
    });

    testWidgets('已记录当前版本 → 无提示条（防御：直接泵页也不该闪现）',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs(initial: <String, Object>{
        kPrefConsentPolicyVersion: kPrivacyPolicyVersion,
      });
      await _pumpConsent(tester, prefs);
      expect(find.byKey(kConsentUpdateNoticeKey), findsNothing);
    });
  });

  group('PrivacyPolicyPage · 应用内政策全文', () {
    /// 页面是 ConsumerWidget（watch 语言 provider）→ 宿主必须挂 ProviderScope。
    Future<void> pumpPolicy(WidgetTester tester, SharedPreferences prefs) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: PrivacyPolicyPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zh：标题 + 章节齐全（含 10.3 重新确认机制）',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      await pumpPolicy(tester, prefs);

      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('一、写给家长和小朋友的话（双读者说明）'), findsOneWidget);
      expect(find.text('十、语言版本与政策更新机制'), findsOneWidget);
      expect(find.text('10.3 应用内重新确认机制'), findsOneWidget,
          reason: '资产应随底稿 v2.0 重生成，含新增小节');
      expect(find.textContaining('附：待确认项汇总'), findsNothing,
          reason: '内部待办节不得进包');
      // 2026-10-23 改名 + 排版整改（玄参反馈）：
      expect(find.textContaining('小小葵番茄钟'), findsWidgets,
          reason: '应用内政策资产应随底稿更名（小小葵番茄钟 / Tiny Sunflower，正文多处出现）');
      expect(find.textContaining('项：内容'), findsNothing,
          reason: '表格表头行「项 | 内容」必须跳过不渲染');
      expect(find.textContaining('包名'), findsNothing,
          reason: '包名/Bundle ID 属内部技术信息，应用内不得出现');
      expect(find.textContaining('com.sunflowertime', findRichText: true),
          findsNothing,
          reason: 'Bundle ID 不得出现（表格行走 Text.rich 渲染）');
      expect(find.textContaining('应用名称：', findRichText: true), findsOneWidget,
          reason: '§2 表格行应渲染为「项：值」形式');
    });

    testWidgets('en：切换界面语言后全文换英文', (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      AppLocaleController.init(AppLanguage.en);
      await pumpPolicy(tester, prefs);

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('1. A Note for Parents and Kids'), findsOneWidget);
      expect(find.text('10.3 In-app re-confirmation mechanism'), findsOneWidget);
    });
  });

  group('家长设置页 · 隐私政策入口（接线守）', () {
    testWidgets('从「数据与隐私」区真实点进 /privacy-policy',
        (WidgetTester tester) async {
      final GoRouter router = GoRouter(
        initialLocation: '/parent/settings',
        routes: <RouteBase>[
          GoRoute(
            path: '/parent/settings',
            builder: (_, __) => const Scaffold(body: ParentSettingsPage()),
          ),
          GoRoute(
            path: '/privacy-policy',
            builder: (_, __) => const Scaffold(
              key: Key('policy-probe'),
              body: Text('POLICY'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 页面根是懒构建 ListView：底部「数据与隐私」分区需滚动进视口。
      await tester.scrollUntilVisible(
        find.text('隐私政策'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('应用内随时查看完整隐私政策'), findsOneWidget);

      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('policy-probe')), findsOneWidget,
          reason: '设置页入口必须真实跳到政策全文页（组件在树上≠接线成功）');
    });
  });

  group('预览模式 · C110-F1（玄参目验：预览页政策入口点了没响应）', () {
    testWidgets('预览页「查看完整隐私政策」可点 → 真实跳政策全文页，零状态写入',
        (WidgetTester tester) async {
      final SharedPreferences prefs = await _mockPrefs();
      final GoRouter router = GoRouter(
        initialLocation: '/consent-preview',
        routes: <RouteBase>[
          GoRoute(
            path: '/consent-preview',
            builder: (_, __) => const ConsentPage(preview: true),
          ),
          GoRoute(
            path: '/privacy-policy',
            builder: (_, __) => const PrivacyPolicyPage(),
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

      expect(find.text('返回花园'), findsOneWidget,
          reason: '确认处于预览模式（单按钮「返回花园」）');
      // 政策入口在卡内滚动区底部，测试视口（800×600）外 → 先滚入可见区再点。
      await tester.ensureVisible(find.byKey(kConsentViewPolicyKey));
      await tester.pump();
      await tester.tap(find.byKey(kConsentViewPolicyKey));
      // 🔴 不用 pumpAndSettle：GoRouter 异步守卫（读 SP 的 Future）在 FakeAsync 下
      // 每帧重触发 rebuild → settle 永不完成；固定泵两帧（跳转 + 政策页 FutureBuilder 加载）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('隐私政策'), findsOneWidget,
          reason: '预览模式下政策入口同样必须可跳转（曾 onPressed: null 被禁用）');
      expect(await SettingsStore(prefs).consentedPolicyVersion(), 0,
          reason: '预览 + 查看政策全程零状态写入');
    });
  });
}

/// 内存设置仓储假实现（夹具同 `parent_entry_gold_test.dart`）。
class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}
