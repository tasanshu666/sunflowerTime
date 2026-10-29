/// F166 守卫测试（玄参 2026-10-29）：**家长端「关于与反馈」** + **花园锁定加盆格**。
///
/// 两件事的产品口径（玄参原话）：
///  ① 「增加一个我的网站和邮箱的说明，有问题或者有反馈的 bug 可以通过邮箱联系我，
///    没有这个说明的话，用户是不是很难联系到开发者提供有价值的信息？」
///  ② 「免费模式下就只有 4 个花盆，后面也没有可以增加花盆的图标 …… 应该是得展现
///    可扩展花盆的图标，但是这个图标仅用于提示、展示使用，不用于孩子操作」。
///
/// 本文件只覆盖 ①（花园侧在 `garden_layout_v3_test.dart` 的 F166 组）。
///
/// 🔴 为什么版本号要读 `pubspec.yaml` 做断言：`kAppVersionLabel` 是**手写常量**，
/// 与 `pubspec.yaml` 的 `version:` 是同一事实的两份拷贝，天然会漂移。加了守卫后
/// 「升版本忘了改常量」会让测试直接变红，而不是等提审时在关于页看到旧版本号。
///
/// 🔴 为什么用可覆写的 `externalLinkOpener` 而不是 mock platform interface：
/// 后者要显式依赖 `url_launcher_platform_interface`（analyze 会多一条
/// `depend_on_referenced_packages` info，打破 77 info 的基线），且验证的是
/// 第三方插件的内部路径；本文件关心的是「我们点了哪个 URL」，覆写单点更直接。
library f166_about_section_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/utils/external_link.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';

/// 离线 IAP 适配器：商店恒不可用（**绝不触碰真实 StoreKit / Play Billing**）。
class _OfflineIapAdapter implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();

  @override
  Future<bool> isStoreAvailable() async => false;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async =>
      <IapProduct>[];

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────── ① 纯函数（不需要任何装配） ─────────────────────────

  group('① mailto URI 组装（纯函数）', () {
    test('收件人来自单点常量，主题 / 正文完整编码', () {
      final Uri uri = buildSupportMailUri(
        subject: 'Tiny Sunflower feedback v1.0.0',
        body: 'Tell me what happened below:\n\n--\nVersion: 1.0.0 (2104)\nPlatform: iOS',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, kSupportEmail, reason: '收件人必须是单点常量（与隐私政策一致）');
      expect(uri.queryParameters['subject'], 'Tiny Sunflower feedback v1.0.0');
      // 换行 / 括号都必须原样往返（编码 → 解码后与原文逐字相等）。
      expect(uri.queryParameters['body'],
          contains('Version: 1.0.0 (2104)'));
      expect(uri.queryParameters['body'], contains('Platform: iOS'));
    });

    test('🔴 空格编成 %20 而不是 +（RFC 6068；+ 会被部分客户端当字面加号）', () {
      final Uri uri = buildSupportMailUri(subject: 'a b', body: 'c d');
      final String raw = uri.toString();

      expect(raw, contains('subject=a%20b'));
      expect(raw, contains('body=c%20d'));
      expect(raw.contains('+'), isFalse,
          reason: 'mailto 的 header 值用 percent-encoding，出现 + 就是错编');
    });

    test('平台标签三分支（iOS / Android / 其它不落空）', () {
      expect(supportMailPlatformLabel(TargetPlatform.iOS), 'iOS');
      expect(supportMailPlatformLabel(TargetPlatform.android), 'Android');
      // 其它平台回落自身名字，绝不能是空串（反馈邮件里这一列是排查关键）。
      expect(supportMailPlatformLabel(TargetPlatform.macOS), isNotEmpty);
    });
  });

  group('② 版本常量与 pubspec 同源', () {
    test('kAppVersionLabel 必须等于 pubspec 的 version 行', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final RegExpMatch? m =
          RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml 必须有 version 行');

      expect('$kAppVersionName+$kAppBuildNumber', m!.group(1),
          reason: '🔴 升版本号必须同步 app_constants.dart 的 kAppVersionName / '
              'kAppBuildNumber（关于页就显示这两个值）');
      expect(kAppVersionLabel, '$kAppVersionName ($kAppBuildNumber)');
    });

    test('联系方式常量格式自检（邮箱含 @、网址为 https 且无尾斜杠）', () {
      expect(kSupportEmail, contains('@'));
      expect(kOfficialWebsite, startsWith('https://'));
      expect(kOfficialWebsite.endsWith('/'), isFalse,
          reason: '带尾斜杠会让 Uri.parse 把它当路径根，规范化后可能变异');
    });
  });

  // ───────────────────────── ③ 设置页真实入口 ─────────────────────────

  late ProviderContainer container;
  late db.AppDatabase database;

  /// 本次用例期间被「点开」的 URL（覆写 [externalLinkOpener] 捕获）。
  late List<Uri> launched;
  late bool launchShouldSucceed;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();

    container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        iapServiceProvider
            .overrideWithValue(IapService(adapter: _OfflineIapAdapter())),
      ],
    );
    addTearDown(container.dispose);
  }

  setUp(() async {
    AppLocaleController.init(AppLanguage.zh);
    launched = <Uri>[];
    launchShouldSucceed = true;
    externalLinkOpener = (Uri uri) async {
      launched.add(uri);
      return launchShouldSucceed;
    };
    await boot();
  });

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
    // 🔴 必须还原全局单点，否则同文件后续用例会共享脏状态（F155 的教训）。
    externalLinkOpener = defaultExternalLinkOpener;
  });

  /// 真实页面宿主（页级 `L10nScope` 由页面自己包，不在宿主补）。
  Widget pageHost(Widget page) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: page)),
      );

  Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// 一次把整页撑开（设置页很长，「关于」分区在底部；不撑开就得滚动，
  /// 而滚动位置会让后续 `tap` 命中不到目标 —— 直接给足够高度最稳）。
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(pageHost(const ParentSettingsPage()));
    await pumpFrames(tester);
  }

  group('③ 设置页「关于与反馈」分区', () {
    testWidgets('三行齐备：版本号（纯展示）/ 联系开发者 / 官方网站', (WidgetTester tester) async {
      await pumpSettings(tester);

      expect(find.text('关于与反馈'), findsOneWidget, reason: '分区标题');
      expect(find.text('版本'), findsOneWidget);
      expect(find.text(kAppVersionLabel), findsOneWidget,
          reason: '版本号直接取常量（与 pubspec 同源，另有用例守着）');
      expect(find.text('联系开发者'), findsOneWidget);
      expect(find.text('官方网站'), findsOneWidget);
      expect(find.text(kSupportEmail), findsNothing,
          reason: '界面用「联系开发者」作标题；邮箱只在邮件正文/失败提示里出现');
    });

    testWidgets('版本行是纯展示行：不带 chevron（避免「点了没反应像 bug」）',
        (WidgetTester tester) async {
      await pumpSettings(tester);

      // 版本行的 ListTile 里不应出现返回箭头。
      final Finder versionTile =
          find.ancestor(of: find.text('版本'), matching: find.byType(ListTile));
      expect(versionTile, findsOneWidget);
      expect(find.descendant(of: versionTile, matching: find.byIcon(Icons.chevron_right)),
          findsNothing);

      // 对照：联系开发者行必须有箭头（可点）。
      final Finder contactTile = find.ancestor(
          of: find.text('联系开发者'), matching: find.byType(ListTile));
      expect(find.descendant(of: contactTile, matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget);
    });

    testWidgets('🔴 点「联系开发者」→ mailto 预填版本 + 平台', (WidgetTester tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('联系开发者'));
      await pumpFrames(tester);

      expect(launched, hasLength(1), reason: '必须只打开一次（不重复唤起）');
      final Uri uri = launched.single;
      expect(uri.scheme, 'mailto');
      expect(uri.path, kSupportEmail);
      expect(uri.queryParameters['subject'], contains(kAppVersionName),
          reason: '主题带版本号：玄参能一眼看出用户是哪一版');
      expect(uri.queryParameters['body'], contains(kAppBuildNumber),
          reason: '正文带构建号（同 build 才能对比二进制行为）');
      expect(uri.queryParameters['body'],
          contains(supportMailPlatformLabel(defaultTargetPlatform)),
          reason: '正文带平台，iOS/Android 差异排查的关键列');
    });

    testWidgets('点「官方网站」→ https 打开的正好是官网', (WidgetTester tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('官方网站'));
      await pumpFrames(tester);

      expect(launched, hasLength(1));
      expect(launched.single.toString(), kOfficialWebsite);
    });

    testWidgets('打开失败 → 必须给可手动操作的地址（绝不静默）',
        (WidgetTester tester) async {
      launchShouldSucceed = false;
      await pumpSettings(tester);

      await tester.tap(find.text('联系开发者'));
      await pumpFrames(tester);

      expect(find.textContaining(kSupportEmail), findsOneWidget,
          reason: '没有邮件 App 时也要让家长抄得到地址');
    });

    testWidgets('英语环境三行同样生效（防半迁移）', (WidgetTester tester) async {
      AppLocaleController.init(AppLanguage.en);
      await pumpSettings(tester);

      expect(find.text('About & feedback'), findsOneWidget);
      expect(find.text('Contact the developer'), findsOneWidget);
      expect(find.text('Official website'), findsOneWidget);
      // 中文必须消失。
      expect(find.text('关于与反馈'), findsNothing);
      expect(find.text('联系开发者'), findsNothing);
    });
  });
}
