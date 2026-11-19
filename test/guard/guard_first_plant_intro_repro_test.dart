/// 玄参 v0.3 / v0.4 真机反馈 2 的**因果链闭环** + 「没玩过」场景的判定与反馈。
///
/// ① 主用例：昨日两次有效专注攒下 2 点能量（真 GuardService + 真
///    GuardEnergyPrefsStore 入账）→ 跨天余额仍 2 → 种下第一株回今日页
///    → 首株说明卡确认 ⇒ `startButtonKey` 在树、`claimedBadgeKey` 不在树。
///    这条用例由第 3 条持久余额修复使其转绿；回退修复必须转红。
///
/// ② 玄参 2026-11 真机裁定（**已拍板，不是待确认项**）：真·当日 0 能量
///    0 余额且从未有效专注过时，守卫卡右簇**必须画「开始守卫」按钮**，
///    不得画「守卫成功」旗帜。判据 = `GuardTodayView.hasBattleResource`
///    （有没有可出战资源），由 `isActionable` 统一给出。
///
/// ③ 玄参**二次真机裁定**（推翻「打完再提示还差 N 阳光」）：按钮能点，但
///    点下去在**开战前**就被拦住 —— 弹一张「先去专注」的知道啦提示卡，
///    不走教学 / 确认卡 / 战斗 / 结算卡。用例挂真实 ChildTodayPage + 真 DI
///    + 真 GuardService，断言对象为真实 widget Key 与真实文案。
///    ④ 有资源（昨日攒 2 能量）照常开战，证明拦截只作用于没资源场景。
library guard_first_plant_intro_repro_test;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_first_plant_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

class _Env {
  _Env(this.container, this.database, this.account);

  final ProviderContainer container;
  final db.AppDatabase database;
  final AccountService account;

  GuardService get guard => container.read(guardServiceProvider);
}

Future<_Env> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
      // 会员上限 2：玄参攒的正是 2 点；免费档上限 1 会让链路失真。
      entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
    ],
  );
  addTearDown(container.dispose);
  return _Env(container, database, account);
}

/// 昨天 08:00 / 09:00 各一次有效专注（plannedMin=0 + 25min ⇒ 有效）。
Future<void> _seedTwoValidFocusesYesterday(_Env env, DateTime today) async {
  final DateTime yesterday = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 1));
  for (int i = 0; i < 2; i++) {
    final DateTime start = yesterday.add(Duration(hours: 8 + i));
    await env.container.read(focusRepositoryProvider).saveSession(
          FocusSession(
            id: 'yesterday_focus_$i',
            start: start,
            end: start.add(const Duration(minutes: 25)),
            plannedMin: 0,
            actualFocusMin: 25,
            status: FocusStatus.completed,
            sunlightEarned: 0,
            createdAt: start,
          ),
        );
  }
}

/// 今天刚完成一次有效专注（玄参报的「专注完回今日页就变旗帜」场景）。
Future<void> _seedValidFocusToday(_Env env) async {
  final DateTime start = DateTime.now().subtract(const Duration(minutes: 30));
  await env.container.read(focusRepositoryProvider).saveSession(
        FocusSession(
          id: 'today_focus',
          start: start,
          end: start.add(const Duration(minutes: 25)),
          plannedMin: 0,
          actualFocusMin: 25,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: start,
        ),
      );
}

Future<void> _seedFirstPlant(_Env env) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(env.database, account: env.account).savePlant(
    Plant(
      id: 'first_plant',
      speciesId: 'sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
    ),
  );
}

/// 挂真实今日页，走首株说明卡并点确认。
Future<void> _confirmFirstPlantIntro(WidgetTester tester, _Env env) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: ChildTodayPage(),
      ),
    ),
  );
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final BuildContext pageContext = tester.element(find.byType(ChildTodayPage));
  unawaited(maybeShowGuardFirstPlantIntro(
    context: pageContext,
    l10n: AppLocalizations.of(pageContext),
    sp: env.container.read(sharedPreferencesProvider),
    plants: env.container.read(plantRepositoryProvider),
  ));
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byKey(const Key('guardFirstPlantIntro')), findsOneWidget,
      reason: '首株说明卡必须出现');
  await tester.tap(find.byKey(const Key('guardFirstPlantOk')));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 220,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  expect(finder, findsOneWidget, reason: '等待超时：目标 widget 一直没出现');
}

/// 路由过渡（教学浮层 / 结算卡 push）各 ~200ms。
Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 越过 B2 教学浮层：同一 env 第二次点卡不会再弹，故「弹了才点」。
Future<void> _passTutorial(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(kGuardTutorialOkKey).evaluate().isNotEmpty) break;
  }
  if (find.byKey(kGuardTutorialOkKey).evaluate().isEmpty) return;
  await _settleRoute(tester);
  await tester.tap(find.byKey(kGuardTutorialOkKey));
  await _settleRoute(tester);
}

void main() {
  testWidgets('因果链：昨日攒2 → 跨天 → 今日页首株说明确认 → 仍是「开始守卫」钮',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    final DateTime today = DateTime.now();
    final DateTime yesterday =
        DateTime(today.year, today.month, today.day).subtract(
      const Duration(days: 1),
    );

    await _seedTwoValidFocusesYesterday(env, today);
    // 昨天入账：2 次有效专注 × 1（幂等键是 session id，不是日期）。
    expect(await env.guard.energyAvailable(now: yesterday), 2,
        reason: '昨日两次有效专注 ⇒ 攒下 2 点');
    // 跨天：旧口径只看当天专注 ⇒ 此处会归零，正是第 2 条的症状源头。
    expect(await env.guard.energyAvailable(now: today), 2,
        reason: '跨天后余额仍应是 2（第 3 条持久余额）');

    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);

    expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
        reason: '确认首株说明卡后应是「开始守卫」按钮');
    expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsNothing,
        reason: '确认首株说明卡后不应直接显示「守卫成功」旗帜');
  });

  testWidgets('玄参拍板：真·0能量0余额（没玩过）→ 显示「开始守卫」钮、不得显示旗帜',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    // 不种专注、不记阳光；只种第一株 ⇒ 0 能量 0 余额。
    expect(await env.guard.energyAvailable(), 0);
    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);

    expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
        reason: '玄参明确裁定：没玩过也必须画「开始守卫」按钮');
    expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsNothing,
        reason: '没玩过绝不能画「守卫成功」旗帜（那是假胜利）');
  });

  testWidgets('玄参二次裁定：没玩过点钮只弹资源不足提示，无论怎么点都进不了战斗',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    expect(await env.guard.energyAvailable(), 0);
    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);

    // ① 点真页面上的「开始守卫」钮 → 开战前就被拦下。
    await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
    await _settleRoute(tester);

    // ② **穷举式验证「无论怎么点」**：假如实现错误地放行了开战，这里会
    //    把教学 / 免费确认卡一路点掉，从而让战斗字段冒出来（变异验证靠它转红）。
    //    正确实现下这两类弹层根本不在树，循环只是空转。
    for (int i = 0; i < 12; i++) {
      if (find.byKey(kGuardTutorialOkKey).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(kGuardTutorialOkKey));
        await _settleRoute(tester);
      }
      if (find.text('确定').evaluate().isNotEmpty) {
        await tester.tap(find.text('确定').first);
        await _settleRoute(tester);
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ③ 教学 / 确认卡 / 战斗 / 结算卡：一个都不许进树。
    expect(find.byKey(kGuardTutorialOkKey), findsNothing,
        reason: '资源不足时不走教学浮层');
    expect(find.text('要派出向日葵战士，\n进行花园守卫吗？'), findsNothing,
        reason: '资源不足时不弹开战确认卡');
    expect(find.byKey(GuardBattleField.fieldKey), findsNothing,
        reason: '🔴 没资源绝不能进战斗');
    expect(find.byKey(GuardResultCard.cardKey), findsNothing,
        reason: '🔴 没资源绝不能出现「还差 10 阳光」的结算死胡同');

    // ④ 唯一弹层 = 一张「知道啦」资源不足提示，文案引导去专注。
    expect(find.byKey(kGuardNoResourceHintDialogKey), findsOneWidget);
    expect(
      find.text('没有能量点，也没有 $kGuardPayCost 阳光，先去专注获得能量或阳光吧'),
      findsOneWidget,
      reason: '玄参原话：先去专注获得阳光，不可以玩这个模式',
    );
    expect(find.text('知道啦'), findsOneWidget);
    expect(find.text('取消'), findsNothing, reason: '提示卡没有取消语义');

    // ⑤ 再推 10 秒，反复确认战斗 / 结算卡始终不进树（不是延迟弹出）。
    for (int i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(kGuardNoResourceHintDialogKey), findsOneWidget);
    expect(find.byKey(GuardBattleField.fieldKey), findsNothing);
    expect(find.byKey(GuardResultCard.cardKey), findsNothing);

    // ⑥ 关掉提示后回今日页：仍是「开始守卫」钮，不是旗帜。
    await tester.tap(find.text('知道啦'));
    await _settleRoute(tester);
    expect(find.byKey(kGuardNoResourceHintDialogKey), findsNothing);
    expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget);
    expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsNothing);
  });

  testWidgets('有能量（昨日攒2 → 跨天）照常开战：只拦没资源，不误伤正常路径',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    final DateTime today = DateTime.now();
    await _seedTwoValidFocusesYesterday(env, today);
    expect(await env.guard.energyAvailable(now: today), 2);
    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);

    await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
    await _passTutorial(tester);
    await tester.pump();
    expect(find.byKey(kGuardNoResourceHintDialogKey), findsNothing,
        reason: '有能量时不得弹资源不足提示');
    expect(find.text('要派出向日葵战士，\n进行花园守卫吗？'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await _settleRoute(tester);
    await _pumpUntil(tester, find.byKey(GuardBattleField.fieldKey));
    expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
        reason: '有资源必须照常进战斗');
  });

  testWidgets('核心bug反例：先落 short，再专注拿到能量 → 仍画开始钮、绝不变旗帜',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    // ① 先没玩过：0 能量 resolve 落 short（= freeRide 档），此时画按钮。
    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);
    expect(await env.guard.energyAvailable(), 0);
    expect((await env.guard.todayState()).status, GuardDayStatus.short);

    // ② 之后才完成一次有效专注：能量变 1，但当日存档仍是 short ——
    //    这正是玄参报的「专注完回今日页，按钮变旗帜」时序。
    await _seedValidFocusToday(env);
    expect(await env.guard.energyAvailable(), 1);
    final BuildContext pageContext = tester.element(find.byType(ChildTodayPage));
    final ProviderContainer container = ProviderScope.containerOf(pageContext);
    final GuardResolveResult refreshed = await env.guard.resolve();
    expect(refreshed.state.status, GuardDayStatus.short,
        reason: 'resolve 幂等，不会把已落盘的 short 改掉');
    container.read(guardTodayProvider.notifier).state =
        GuardTodayView.fromResolve(refreshed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(guardTodayProvider).mode, GuardPillMode.freeRide);

    expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsNothing,
        reason: '专注完变旗帜是三套打架口径里的错误分支');
    expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
        reason: '玄参最终口径：status 未 claimed 就是没玩过，有能量也必须画开始钮');
  });

  testWidgets('玩过（打完并收下 ⇒ claimed）→ 旗帜在树、开始钮不在树',
      (WidgetTester tester) async {
    final _Env env = await _boot();
    await _seedValidFocusToday(env);
    await _seedFirstPlant(env);
    await _confirmFirstPlantIntro(tester, env);

    // 走完整场：确认 → 战斗 → 宝箱 → 结算卡 → 收下（claim 落 claimed）。
    await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
    await _passTutorial(tester);
    await tester.pump();
    await tester.tap(find.text('确定'));
    await _settleRoute(tester);
    await _pumpUntil(tester, find.byKey(GuardBattleField.fieldKey));
    for (int i = 0; i < 62; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
    await tester.pump(const Duration(milliseconds: 1000));
    await _pumpUntil(tester, find.byKey(GuardChestStage.stageKey));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
    await tester.pump(const Duration(milliseconds: 50));
    await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
    await _settleRoute(tester);
    await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
    await _pumpUntil(tester, find.byType(ChildTodayPage));
    await _settleRoute(tester);

    expect((await env.guard.todayState()).status, GuardDayStatus.claimed,
        reason: '玩过严格 = claim 成功落 claimed');
    expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsOneWidget,
        reason: 'claimed 才画旗帜');
    expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing,
        reason: 'claimed 不再画开始钮');
  });
}
