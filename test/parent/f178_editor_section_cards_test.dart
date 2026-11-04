/// F178 家长端编辑卡片「分区卡片化」视觉改造（玄参 2026-11-04 拍板）。
///
/// 纯视觉改造：把成长任务 / 奖励编辑弹窗里的表单控件按语义分成若干张
/// [EditorSectionCard]。本测试钉住五件事（team-lead 硬性要求）：
///  ① 任务编辑卡分 **3** 张分区，标题「基本信息 / 专注与奖励 / 重复」；
///  ② 奖励编辑卡分 **2** 张分区，标题「基本信息 / 兑换规则」；
///  ③ 结构接线：名称输入框的祖先链里确实存在 [EditorSectionCard]（防"只加装饰
///     不改结构"）；
///  ④ 溢出矩阵：**两个弹窗 × 三个宽度（320 / 390 / 768）× EN + 1.3 字号**，
///     每格 `takeException() == null`。768 是 F178 回归的发生地（卡片内距 +
///     `380 × uiScaleOf` 双收窄后，`isExpanded: false` 的英文下拉曾溢出 164px），
///     必须在矩阵里——没有它这条守卫就是瞎的。
///  ⑤ 反向证明非恒绿：分区数量必须 > 0（拆掉分区本用例必红）。
///  ⑥ 平板收窄生效：1032 宽下内容区实测宽 ≤ `380 × uiScaleOf`（倍率走真实 context）。
library f178_editor_section_cards_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_reward_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/editor_section_card.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 有界收敛（家长奖励页含无限呼吸动画 → 禁用 pumpAndSettle）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late db.AppDatabase database;

  /// 建内存库 + 真 AccountService + 家长页所需 override（参照 tablet_card_scale 同款脚手架）。
  Future<void> boot(WidgetTester tester) async {
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
        entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
      ],
    );
    addTearDown(container.dispose);
  }

  /// 任务编辑弹窗宿主（直接挂 TaskEditorDialog；它是自含弹窗，无需真实入口）。
  Widget taskApp({
    Locale locale = const Locale('zh'),
    double textScale = 1.0,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: TaskEditorDialog(initial: null, onSave: (_) async {}),
        ),
      ),
    );
  }

  /// 家长奖励页宿主（走真实入口 → 点「新增奖励」开弹窗）。
  Widget rewardApp({
    Locale locale = const Locale('zh'),
    double textScale = 1.0,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: ParentRewardPage()),
      ),
    );
  }

  /// 打开奖励编辑弹窗（点真实入口的「+ 新增奖励」按钮）。
  Future<void> openRewardEditor(WidgetTester tester) async {
    await _pumpFrames(tester);
    final Finder addBtn = find.widgetWithIcon(OutlinedButton, Icons.add);
    expect(addBtn, findsOneWidget, reason: '前置：奖励页须有「新增奖励」按钮');
    // 窄屏 / 大字号下按钮可能被顶出可视区 → 先滚入视口再点，避免 tap 落空。
    await tester.ensureVisible(addBtn);
    await _pumpFrames(tester, frames: 4);
    await tester.tap(addBtn);
    await _pumpFrames(tester);
  }

  /// 把逻辑视口设成 [width] × 900（dpr 3），并按 EN + [textScale] 挂起指定弹窗。
  ///
  /// 内部 L10nScope 走 `AppLocaleController.current` → 切 en 让分区标题 / 控件文案变英文。
  Future<void> pumpEditorAt(
    WidgetTester tester, {
    required double width,
    required bool reward,
    double textScale = 1.3,
  }) async {
    final Locale saved = AppLocaleController.current;
    AppLocaleController.current = const Locale('en');
    addTearDown(() => AppLocaleController.current = saved);

    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(reward
        ? rewardApp(locale: const Locale('en'), textScale: textScale)
        : taskApp(locale: const Locale('en'), textScale: textScale));
    if (reward) {
      await openRewardEditor(tester);
    } else {
      await _pumpFrames(tester);
    }
  }

  testWidgets('① 任务编辑卡：3 张分区，标题「基本信息 / 专注与奖励 / 重复」',
      (WidgetTester tester) async {
    await boot(tester);
    await tester.pumpWidget(taskApp());
    await _pumpFrames(tester);

    final List<EditorSectionCard> cards =
        tester.widgetList<EditorSectionCard>(find.byType(EditorSectionCard)).toList();
    expect(cards, hasLength(3), reason: '任务编辑卡必须分 3 张分区（基本信息/专注与奖励/重复）');
    expect(cards.map((EditorSectionCard c) => c.title).toList(),
        <String>['基本信息', '专注与奖励', '重复'],
        reason: '三张分区标题与 ARB 逐字一致');
  });

  testWidgets('② 奖励编辑卡：2 张分区，标题「基本信息 / 兑换规则」',
      (WidgetTester tester) async {
    await boot(tester);
    await tester.pumpWidget(rewardApp());
    await openRewardEditor(tester);

    final List<EditorSectionCard> cards =
        tester.widgetList<EditorSectionCard>(find.byType(EditorSectionCard)).toList();
    expect(cards, hasLength(2), reason: '奖励编辑卡必须分 2 张分区（基本信息/兑换规则）');
    expect(cards.map((EditorSectionCard c) => c.title).toList(),
        <String>['基本信息', '兑换规则'],
        reason: '两张分区标题与 ARB 逐字一致');
  });

  testWidgets('③ 结构接线：名称输入框的祖先链里确实存在 EditorSectionCard',
      (WidgetTester tester) async {
    await boot(tester);
    await tester.pumpWidget(taskApp());
    await _pumpFrames(tester);

    // 名称输入框是任务卡里的首个 TextField。
    final Finder firstField = find.byType(TextField).first;
    final Finder cardAncestor = find.ancestor(
      of: firstField,
      matching: find.byType(EditorSectionCard),
    );
    expect(cardAncestor, findsWidgets,
        reason: '名称输入框必须真的被装进 EditorSectionCard（防「只加装饰不改结构」）');
  });

  // ④ 溢出矩阵：两个弹窗 × 320 / 390 / 768 × EN + 1.3 字号。
  // 每个下拉都必须 `isExpanded: true`（默认 false 时按钮宽取「最宽菜单项」的内在宽，
  // 可用宽一收窄就向下溢出）；矩阵任一格变红即说明有下拉丢了 `isExpanded`。
  for (final double width in <double>[320, 390, 768]) {
    final int w = width.toInt();
    final bool isRegressionWidth = w == 768;

    testWidgets(
        '④ 任务卡 @$w × EN × 1.3：不溢出'
        '${isRegressionWidth ? '（F178 平板回归位）' : ''}',
        (WidgetTester tester) async {
      await boot(tester);
      await pumpEditorAt(tester, width: width, reward: false);
      final Object? err = tester.takeException();
      expect(err, isNull, reason: '任务编辑卡 @$w + EN + 1.3 不得溢出：$err');
      expect(find.byType(EditorSectionCard), findsNWidgets(3),
          reason: '前置：任务卡确已渲染 3 张分区');
    });

    testWidgets(
        '④ 奖励卡 @$w × EN × 1.3：不溢出'
        '${isRegressionWidth ? '（F178 平板回归位）' : ''}',
        (WidgetTester tester) async {
      await boot(tester);
      await pumpEditorAt(tester, width: width, reward: true);
      final Object? err = tester.takeException();
      expect(err, isNull, reason: '奖励编辑卡 @$w + EN + 1.3 不得溢出：$err');
      expect(find.byType(EditorSectionCard), findsNWidgets(2),
          reason: '前置：奖励卡确已渲染 2 张分区');
    });
  }

  testWidgets('⑤ 反向证明非恒绿：分区数量必须 > 0（拆掉分区本用例必红）',
      (WidgetTester tester) async {
    await boot(tester);
    await tester.pumpWidget(taskApp());
    await _pumpFrames(tester);

    expect(find.byType(EditorSectionCard), findsWidgets,
        reason: '若把分区拆回裸 Column，本用例必须红——分区被拆掉即视觉改造失效');
  });

  testWidgets('⑥ 平板收窄：1032 宽下任务卡内容区实测宽 ≤ 380 × uiScaleOf（倍率取真实 context）',
      (WidgetTester tester) async {
    await boot(tester);
    tester.view.physicalSize = const Size(1032 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(taskApp());
    await _pumpFrames(tester);

    final Finder card = find.byType(EditorSectionCard).first;
    // 卡片 `width: double.infinity` → 实测宽即 `Column`（= 被 ConstrainedBox 收窄后）的宽。
    final double cardWidth = tester.getSize(card).width;
    // 倍率必须从真实 context 取派生值，禁止写死 1.3 / 1.6 / 1.4029…。
    final double cap = 380 * uiScaleOf(tester.element(card));

    expect(cap, greaterThan(380.0),
        reason: '前置：1032 档须处于平板倍率（> 1.0），否则本用例量的是手机分支');
    expect(cardWidth, greaterThan(0.0), reason: '卡片必须真实渲染出宽度');
    expect(cardWidth, lessThanOrEqualTo(cap + 0.001),
        reason: '平板收窄失效：实测宽 $cardWidth > 上限 $cap'
            '（把 maxWidth 上限去掉，本用例必红）');
  });
}
