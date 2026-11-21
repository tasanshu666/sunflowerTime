/// C133 · 冷启动残留 fighting（**非本会话战斗**）的「跳过回放 + 惩罚兜底」护栏。
///
/// 缺陷链路（玄参真机复现：「覆盖安装后未点开始守卫战自己开打并超时撤退」）：
/// `markFighting()` 把当日存档落成 `fighting`（「落骰已定，只回放结果」），但
/// 战局本体只活在会话内存里（`GuardBattleSim` 零落盘）。覆盖安装 / 强杀后冷启动
/// → 存档幸存 → `resolve()` 原样回放 → 卡片挂 L4 战斗层 → ticker 自动重放一场
/// 孩子根本没参与的战斗并超时撤退。
///
/// 修复（主理人拍板「方案 B + 惩罚兜底」）：页面内存标志
/// `_enteredBattleThisSession`（本会话是否真实点击进入过战斗）——
///  · 冷启动 fighting + 标志 false → 不挂战斗层，直接推进宝箱/结算演出；
///  · 该路径结算**绝不**触发 `recordNoFirePenalty` / `recordBattleTheft`
///    （验收红线：账本不得出现 `guard_stolen` 新行）；
///  · 本会话点击进入 → 战斗行为与结算完全不变（零回归）；
///  · 惩罚兜底不得误伤正常「未开火挂机撤退」场的 −3（C128 didAttack 语义
///    不回归 —— 挂机场是本会话真实发生的，必须仍罚）。
///
/// ## 为什么用真仓储 + 内存库（同 `guard_today_flow_test.dart` 口径）
/// 残留局的「resolve 原样回放 / claim 三层幂等 / 惩罚互斥」正是被验证的行为，
/// 假服务替身会把它们一起替掉。只 override `sharedPreferencesProvider` /
/// `appDatabaseProvider` / `accountServiceProvider` 三个出口。
///
/// ## 🔴 绝不 `pumpAndSettle`
/// 今日页阳光气泡是 12 秒无限循环动画；全文件用定长 `pump` 推进
/// （同 `guard_today_flow_test.dart` 纪律）。
library guard_residual_battle_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_day.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具（与 guard_today_flow_test.dart 同款，按本文件需要裁剪）
// ═══════════════════════════════════════════════════════════════════════

/// 一个装配好的今日页环境（内存库 + 内存 prefs + 已初始化的 AccountService）。
class _Env {
  _Env({
    required this.sp,
    required this.database,
    required this.account,
  });

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;

  String get childId => account.childId;

  SunlightLocalRepository get ledger =>
      SunlightLocalRepository(database, account: account);

  GuardStatePrefsStore get guardStore => GuardStatePrefsStore(sp);

  /// 今日守卫存档。
  Future<GuardDayState> guardState() => guardStore.read(childId);

  /// 某个 refType + refId 今天（守卫 6 点日界）在账本里的行数。
  Future<int> guardLedgerRows(String refType, String refId) =>
      ledger.countByRefTypeAndRefIdOnDay(
          refType, refId, guardDayKey(DateTime.now()));

  /// 某个 refType 今天（守卫 6 点日界）在账本里的净额。
  Future<double> guardLedgerNet(String refType) =>
      ledger.netByRefTypeOnDay(refType, guardDayKey(DateTime.now()));
}

/// 建库 + 建账号（**不**造数据，由各用例自己决定）。
Future<_Env> _makeEnv() async {
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
  return _Env(sp: sp, database: database, account: account);
}

/// 种一株存活苗（`resolve()` 只有在**有存活株**时才认贼）。
Future<void> _seedPlant(_Env env, {String id = 'plant_1'}) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(env.database, account: env.account).savePlant(
    Plant(
      id: id,
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

/// 记一次**有效专注**（+1 能量 ⇒ 免费路径，与 flow 测试同款午夜安全处理）。
Future<void> _seedValidFocus(_Env env, {String id = 'f_1'}) async {
  final DateTime now = DateTime.now();
  final DateTime todayStart = DateTime(now.year, now.month, now.day);
  final DateTime rawStart = now.subtract(const Duration(minutes: 20));
  final DateTime start = rawStart.isBefore(todayStart)
      ? todayStart.add(const Duration(seconds: 1))
      : rawStart;
  await FocusLocalRepository(env.database, account: env.account).saveSession(
    FocusSession(
      id: id,
      start: start,
      end: now,
      plannedMin: 0,
      actualFocusMin: 20,
      status: FocusStatus.completed,
      sunlightEarned: 0,
      createdAt: now,
    ),
  );
}

/// 给账本记一笔收入，把余额抬到 [amount]。
Future<void> _seedBalance(_Env env, double amount) async {
  final DateTime now = DateTime.now();
  await env.ledger.append(SunlightEntry(
    id: 'seed_${amount.toInt()}',
    ts: now,
    type: SunlightType.earn,
    gross: amount,
    net: amount,
    balanceAfter: amount,
    refType: 'seed_earn',
    refId: 'seed',
    dayKey: dayKey(now),
  ));
}

/// 🔴 构造「上一会话残留」的 fighting 存档（模拟覆盖安装 / 强杀后 prefs 幸存）。
///
/// 直接经 [GuardStatePrefsStore] 落盘 —— 与 `markFighting()` 的写入层级一致
/// （只经领域存储，不走页面）。`winSun` / `dropKind` 是 `resolve()` 时定死的
/// 奖励，回放局 claim 时照发。能量路径残留局是**最真实**的形态：能量记在
/// prefs 里不随重启消失，重开时 claim 走免费分支必然成功（付费残留局在余额
/// 被花掉后 claim 会 insufficientBalance —— 那条边缘由次日 expire() 自愈，
/// 见 `child_today_page._settleResidualBattle` 的文档，不在本文件覆盖内）。
Future<void> _seedResidualFighting(_Env env, {int winSun = 2}) async {
  await env.guardStore.write(
    env.childId,
    GuardDayState(
      dayKey: guardDayKey(DateTime.now()),
      status: GuardDayStatus.fighting,
      thiefKind: GuardThiefKind.sunRat,
      winSun: winSun,
      dropKind: GuardDropKind.waterVoucher,
    ),
  );
}

/// 挂载「今日页」并推进到守卫链路完成。
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  _Env env, {
  int frames = 24,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(env.sp),
      appDatabaseProvider.overrideWithValue(env.database),
      accountServiceProvider.overrideWithValue(env.account),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

/// 反复 `pump` 直到 [finder] 出现（**不用** `pumpAndSettle`）。
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

/// 让**路由过渡**跑完（结算卡 / 教学浮层的过渡各 ~200ms）。
Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 越过 B2 教学浮层（弹了才点；fresh 环境第二次点卡不会再弹）。
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

/// 本会话点击进入战斗（教学 → 免费确认卡 → L4 上屏）。
Future<void> _enterBattleThisSession(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
  await _passTutorial(tester);
  await tester.tap(find.text('确定')); // B13.7：免费路径也弹确认卡
  await _settleRoute(tester);
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
      reason: '确认后 L4 战斗层必须上屏');
}

/// 读完残留局收尾全链：宝箱出现 → 点开 → 结算卡出现 → 点「收下」。
Future<void> _collectResidualSettle(WidgetTester tester) async {
  await _pumpUntil(tester, find.byKey(GuardChestStage.stageKey));
  await tester.pump(const Duration(milliseconds: 260)); // 路由过渡 200ms
  expect(find.byKey(GuardResultCard.cardKey), findsNothing,
      reason: '宝箱没开完，结算卡不许抢跑（演出顺序：宝箱 → 结算卡）');
  await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
  await tester.pump(); // 起播一帧
  await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
  await tester.pump(const Duration(milliseconds: 50));
  await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
  await _settleRoute(tester);
  await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
  await _pumpUntil(tester, find.byType(ChildTodayPage));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ① 冷启动残留 fighting：不挂战斗层，直接推进宝箱 → 结算卡 → 收下
// ═══════════════════════════════════════════════════════════════════════

void _groupSkipReplay() {
  group('① 冷启动残留 fighting：跳过回放，直接推进宝箱 → 结算演出', () {
    testWidgets("残留 fighting + 本会话未点击 ⇒ L4 战斗层不上屏、"
        "宝箱先上屏、收下后存档落 claimed（能量路径残留局：claim 必成功）",
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      // 能量路径残留（真实形态：能量记在 prefs 不随重启消失）⇒ claim 走
      // 免费分支，成本零阳光。
      await _seedValidFocus(env);
      await _seedResidualFighting(env);
      await _pumpToday(tester, env);

      // 🔴 红线：不许自动开打 —— L4 战斗层（卡片内 ticker 自动重放）绝不上屏。
      expect(find.byKey(GuardBattleField.fieldKey), findsNothing,
          reason: '🔴 C133：非本会话战斗不许自动挂战斗层重放（玄参真机缺陷）');
      // 收尾演出起点 = 宝箱（guardStageAfterBattle：fighting 未领取 ⇒ chestDrop）。
      expect(find.byKey(GuardChestStage.stageKey), findsOneWidget,
          reason: '残留局应直接从宝箱演出开始，而不是从战斗重放开始');

      await _collectResidualSettle(tester);

      // 收下 ⇒ claim(hasFired: true) 落 claimed（三层幂等的最外层可见结果）。
      final GuardDayState after = await env.guardState();
      expect(after.status, GuardDayStatus.claimed,
          reason: '残留局收下后存档必须推进到 claimed（不再回 fighting）');
      // 场景卡回到「已守住」（且绝不再是战斗态文案）。
      final String label = tester
              .widget<Semantics>(find.byKey(GuardSceneCard.statusSemanticsKey))
              .properties
              .label ??
          '';
      expect(label, contains('今天的菜守住了'));
      // 能量路径 claim：成本不扣阳光，只补发必得阳光 +2。
      expect(await env.guardLedgerNet(kGuardWinRefType), 2.0,
          reason: 'claim(hasFired: true) 补发必得阳光 winSun=2（普通宝箱不翻倍）');
      expect(await env.ledger.balance(), closeTo(2, 1e-9),
          reason: '能量路径成本不扣阳光（balance 0 + 补发 2 = 2）');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ② 惩罚兜底：残留局结算绝不产生 guard_stolen 行（开火被偷 / 未开火罚金都不行）
// ═══════════════════════════════════════════════════════════════════════

void _groupNoTheftLedger() {
  group('② 惩罚兜底：残留局结算零 guard_stolen 落账', () {
    testWidgets("有余额（惩罚**会**写成行的环境）收下残留局 ⇒ "
        "guard_stolen 0 行（开火 garden 与罚金 garden_penalty 两个 refId 都查）、"
        "guard_win 恰好补发 winSun",
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedResidualFighting(env, winSun: 2);
      await _seedBalance(env, 100); // 余额充足：若误触发惩罚必落一行 −3
      await _pumpToday(tester, env);
      await _collectResidualSettle(tester);

      // 🔴 验收红线：账本不得出现 guard_stolen 新行（开火与惩罚两条 refId 都查）。
      expect(await env.guardLedgerRows(kGuardStolenRefType, kGuardRefId), 0,
          reason: '🔴 C133：残留局不得落 recordBattleTheft（被偷额只活在'
              '上一会话 sim 内存里，本会话没有可落账的战局）');
      expect(
          await env.guardLedgerRows(kGuardStolenRefType,
              kGuardNoFirePenaltyRefId), 0,
          reason: '🔴 C133：残留局不得落 recordNoFirePenalty（无法证明孩子'
              '没开火；惩罚只对本会话真实发生的未开火场成立）');
      expect(await env.guardLedgerNet(kGuardStolenRefType), 0.0,
          reason: 'guard_stolen 净额必须为 0（报表口径）');

      // 补发口径（与本会话正常结算的领取口径逐位一致）：必得阳光恰好一行 +2。
      expect(await env.guardLedgerNet(kGuardWinRefType), 2.0,
          reason: 'claim(hasFired: true) 补发必得阳光 winSun=2（普通宝箱不翻倍）');
      // 🔴 成本照扣（claim 领取口径，与正常路径一致）：残留局没付过成本 ⇒
      //    本环境无能量 ⇒ claim 扣 kGuardPayCost(10)（guard_pay 行）。
      expect(await env.guardLedgerNet(kGuardPayRefType), -10.0,
          reason: 'claim 成本照扣（孩子确实打过这场战斗），与本会话正常结算'
              '完全同口径，不是 C133 兜底引入的新扣款');
      // 余额 = 100 + 2 − 10。
      expect(await env.ledger.balance(), closeTo(92, 1e-9),
          reason: '余额只动补发 +2 与成本 −10，绝无 −3 罚金');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ③ 本会话点击进入：战斗行为与结算完全不变（零回归）
// ═══════════════════════════════════════════════════════════════════════

void _groupSessionEntryZeroRegression() {
  group('③ 本会话点击进入：零回归', () {
    testWidgets('点击进战 → 战斗中触发 _reload 重入（economyRevision bump）⇒ '
        '战斗层原样保留、不被强制收尾成宝箱',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env); // 有能量 ⇒ 免费路径
      final ProviderContainer container = await _pumpToday(tester, env);

      await _enterBattleThisSession(tester);

      // 🔴 战斗期间的任意 _refreshGuard 重入（economyRevision bump / 切 tab /
      //    结算收尾）撞见 fighting + 本会话标志 true ⇒ 必须**放行**既有行为
      //    （B3：同会话战斗重放是既定能力），绝不走残留局收尾。
      container.read(economyRevisionProvider.notifier).state++;
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
          reason: '本会话战斗中刷新重入不得拆掉战斗层（C133 跳过逻辑只管'
              '「本会话从未点击」的残留局）');
      expect(find.byKey(GuardChestStage.stageKey), findsNothing,
          reason: '战斗中不得被强制推进宝箱演出');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ④ 惩罚兜底不误伤：本会话「未开火挂机撤退」场恒 −3（C128 didAttack 语义不回归）
// ═══════════════════════════════════════════════════════════════════════

void _groupNoFirePenaltyUnharmed() {
  group('④ 未开火挂机撤退：−3 惩罚必达（不误伤）', () {
    testWidgets("本会话点击进战、一枪不发推完 30s 窗口 ⇒ 结算卡恒 −3、"
        "guard_stolen(garden_penalty) 恰好一行 −3",
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _seedBalance(env, 100); // 余额充足 ⇒ 惩罚实扣 3（写成账本行）
      await _pumpToday(tester, env);
      await _enterBattleThisSession(tester);

      // 一枪不发推完整窗（62 × 500ms，与纯 sim 同源；不 pumpAndSettle）。
      for (int i = 0; i < 62; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      await tester.pump(const Duration(milliseconds: 1000)); // 横幅后交回页面
      await _pumpUntil(tester, find.byKey(GuardChestStage.stageKey));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
      await tester.pump(const Duration(milliseconds: 50));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      // 🔴 C120-13 / C128：本会话真实发生的未开火场，卡面恒 −3（惩罚必达），
      //    绝不因 C133 的兜底逻辑被豁免。
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '未开火场标题 = 失败文案');
      final Iterable<Text> sunTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(GuardResultCard.sunRewardKey),
          matching: find.byType(Text),
        ),
      );
      expect(
        sunTexts.map((Text t) => t.data).whereType<String>(),
        contains('−3'),
        reason: '🔴 C128/C120-13：未开火挂机撤退的 −3 惩罚必须仍在场'
            '（C133 兜底不豁免本会话真实发生的场）',
      );

      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 账本：惩罚行恰好一行 −3（hasFired=false ⇒ 无 guard_win 行）。
      expect(
          await env.guardLedgerRows(
              kGuardStolenRefType, kGuardNoFirePenaltyRefId), 1,
          reason: '未开火惩罚必须落账（恒 −3，kGuardWinSunMin）');
      expect(await env.guardLedgerNet(kGuardStolenRefType), -3.0,
          reason: '惩罚净额 −3');
      expect(await env.guardLedgerNet(kGuardWinRefType), 0.0,
          reason: '未开火 ⇒ 不发必得阳光（B13.26 口径不回归）');
      expect(await env.ledger.balance(), closeTo(97, 1e-9),
          reason: '余额 = 100 − 3（惩罚实扣）');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _groupSkipReplay();
  _groupNoTheftLedger();
  _groupSessionEntryZeroRegression();
  _groupNoFirePenaltyUnharmed();
}
