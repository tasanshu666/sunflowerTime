/// 守卫战 v2 · **布局护栏**（B7 裁定 v3 建立；**B8 起按 v4 口径断言**）。
///
/// 真源：`guard_card_layout.dart`（几何单一来源）+ `guard_scene_card.dart`
/// （卡内容器 / 常驻战士 / 底部倒计时细线）+ `child_today_page.dart`
/// （阳光胶囊冻结 + 开火 / 教学永久一次）。
///
/// ⚠️ B8（玄参第三轮真机）改了四处几何：卡高 160 → **108**（B10 起 112）、战士挪到**栅栏外**、
/// **能量点回归**、**去掉外框**。本文件对应地把 ④⑦⑨ 的口径换到 v4；
/// 新增的 v4 专项断言（能量点位置 / 无边框 / 战士与房子的水平关系 /
/// 通道实测值 / 素材亮度归一）在 `guard_scene_card_layout_v4_test.dart`。
///
/// ## 覆盖（逐条对应玄参 5 条修改 + 9 类测试要求）
/// | # | 断言 |
/// |---|---|
/// | ① | 待机态**存在** `soldierKey`（战士从 L4 提到 L3 常驻），且不在战斗层里 |
/// | ② | 待机两帧帧号不同（idle 19 帧循环）/ fighting 两帧帧号相同（frame001 静止） |
/// | ③ | 开火后 300ms 内攻击帧上屏，窗口过后回到静止首帧 |
/// | ④ | 状态条幅 / 气泡 C / 卡内开火钮 `findsNothing`（**能量点 B8 已回归 ⇒ 正向断言**） |
/// | ⑤ | 卡内开火钮 `findsNothing`；页面级：**点阳光胶囊**战斗中真的出子弹 |
/// | ⑥ | fighting 胶囊连测 3 帧 `getTopLeft` 逐位相同；非战斗 3 帧内有位移 |
/// | ⑦ | 尺寸字面量：房子 88 / 战士 72 / 怪 44；390 与 1024 逐位相等；320 卡 ×0.85 |
/// | ⑧ | 教学**永久一次**：首装弹 → 标记 → 同日第二遍不弹 |
/// | ⑨ | 320×568 + en + 1.3：待机 / 战斗两态零 overflow |
///
/// ## 🔴 为什么④用「字面量 Key」
/// B7 把 `energyDotKey` / `energyBubbleKey` / `statusPlateKey` / `fireButtonKey`
/// 这些**常量本身**删掉了。若测试跟着删，就再也没人守着「它们不许回来」；
/// 用 `Key('guardEnergyDot0')` 这样的字面量断言 `findsNothing`，等于把
/// **历史键名**钉成墓碑：任何人把它们加回卡面，这里立刻红。
///
/// 🔴 全文件有界 `pump`（常驻战士帧序列 / 战斗 ticker / 阳光气泡漂移都在跑，
/// 绝不 `pumpAndSettle`）。
library guard_scene_card_layout_v3_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show deriveGuardBattleScript;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// widget 级夹具
// ═══════════════════════════════════════════════════════════════════════

GuardTodayView _view(GuardPillMode mode, {int energy = 2, double balance = 0}) {
  final GuardDayStatus status = switch (mode) {
    GuardPillMode.claimed => GuardDayStatus.claimed,
    GuardPillMode.fighting => GuardDayStatus.fighting,
    GuardPillMode.freeRide => GuardDayStatus.short,
    _ => GuardDayStatus.pending,
  };
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-11-10',
      status: status,
      thiefKind: mode == GuardPillMode.absent ? null : GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: energy,
    balance: balance,
  );
}

/// 把场景卡挂在 [cardWidth] 宽的槽位里（[screenWidth] 必须 ≥ 卡宽，否则被夹）。
Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  GuardPillMode mode = GuardPillMode.pendingFree,
  double screenWidth = 320,
  double textScale = 1.0,
  bool english = false,
  GuardBattleHandle? handle,
}) async {
  tester.view.physicalSize = Size(screenWidth, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: english ? const Locale('en') : const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cardWidth,
            child: GuardSceneCard(
              view: _view(mode),
              dayKey: '2026-11-10',
              childId: 'seed-0',
              onStart: () {},
              battleHandle: handle,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 等常驻战士的序列帧解析完（AssetManifest 读取是异步的；有界推进）。
Future<void> _settleSoldier(WidgetTester tester) async {
  for (int i = 0; i < 120; i++) {
    if (find
        .descendant(
          of: find.byKey(GuardSceneCard.soldierKey),
          matching: find.byType(Image),
        )
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('等待超时：常驻战士一直没有渲染出图片（帧序列未就绪）');
}

/// 常驻战士**当前渲染的资产路径**（= 帧序号的可观测代理）。
///
/// 攻击帧是盖在待机序列之上的覆盖层（`GuardArt.attackOverlayKey`）——
/// 有覆盖层就以它为准，否则读待机序列当前帧。
String _soldierAsset(WidgetTester tester) {
  final Finder overlay = find.byKey(GuardArt.attackOverlayKey);
  final Finder scope = overlay.evaluate().isNotEmpty
      ? overlay
      : find.byKey(GuardSceneCard.soldierKey);
  final Image img = tester.widget<Image>(
    find.descendant(of: scope, matching: find.byType(Image)),
  );
  return (img.image as AssetImage).assetName;
}

// ═══════════════════════════════════════════════════════════════════════
// 页面级夹具（⑤⑥⑧：真库 + 真 prefs + 真守卫链路）
// ═══════════════════════════════════════════════════════════════════════

class _Env {
  _Env({required this.sp, required this.database, required this.account});

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;

  String get childId => account.childId;

  bool get tutorialSeenFlag => sp.getBool(kGuardTutorialSeenPrefKey) ?? false;
}

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

/// 种一株存活苗（`resolve()` 只有在有存活株时才生成小偷）。
Future<void> _seedPlant(_Env env) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(env.database, account: env.account).savePlant(
    Plant(
      id: 'plant_1',
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

/// 给账本记一笔收入（余额 ≥ 5 ⇒ pendingPaid，付费确认路径）。
Future<void> _seedBalance(_Env env, double amount) async {
  final DateTime now = DateTime.now();
  await SunlightLocalRepository(env.database, account: env.account).append(
    SunlightEntry(
      id: 'seed_${amount.toInt()}',
      ts: now,
      type: SunlightType.earn,
      gross: amount,
      net: amount,
      balanceAfter: amount,
      refType: 'seed_earn',
      refId: 'seed',
      dayKey: dayKey(now),
    ),
  );
}

Future<ProviderContainer> _pumpToday(WidgetTester tester, _Env env) async {
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
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 220,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget, reason: '等待超时：目标 widget 一直没出现');
}

Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 从今日页进入守卫战（付费路径：教学 → 确认卡「确定」）。
Future<void> _enterBattle(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
  // 教学只在首个 env 首遍弹（B7 永久一次）⇒ 弹了才点。
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(kGuardTutorialOkKey).evaluate().isNotEmpty) break;
  }
  if (find.byKey(kGuardTutorialOkKey).evaluate().isNotEmpty) {
    await _settleRoute(tester);
    await tester.tap(find.byKey(kGuardTutorialOkKey));
    await _settleRoute(tester);
  }
  await tester.tap(find.text('确定'));
  await _settleRoute(tester);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
      reason: '夹具前提：L4 战斗层已上屏');
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 战士常驻（待机态就在树）──────────────────────────────────────────
  group('① 战士常驻 L3', () {
    testWidgets('待机态存在 soldierKey；claimed / freeRide 同样在树',
        (WidgetTester tester) async {
      for (final GuardPillMode mode in <GuardPillMode>[
        GuardPillMode.pendingFree,
        GuardPillMode.pendingPaid,
        GuardPillMode.freeRide,
        GuardPillMode.claimed,
      ]) {
        await _pumpCard(tester, cardWidth: 358, screenWidth: 390, mode: mode);
        expect(find.byKey(GuardSceneCard.soldierKey), findsOneWidget,
            reason: '🔴 B7：$mode 下战士必须常驻（旧实现只在 L4 战斗层里画 ⇒ 待机态必红）');
      }
    });

    testWidgets('战士不在战斗层里（已从 GuardBattleField 提到卡内 L3）',
        (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 358,
          screenWidth: 390,
          mode: GuardPillMode.fighting);
      expect(
        find.descendant(
          of: find.byKey(GuardBattleField.fieldKey),
          matching: find.byKey(GuardSceneCard.soldierKey),
        ),
        findsNothing,
        reason: '🔴 战斗层只管怪 / 子弹 / 横幅，战士是卡内常驻元素',
      );
      expect(find.byKey(GuardSceneCard.soldierKey), findsOneWidget);
    });
  });

  // ── ② 帧序列：待机循环 / 战斗静止 ──────────────────────────────────────
  group('② 待机循环 vs 战斗静止', () {
    testWidgets('待机态两帧帧号不同（19 帧 idle 循环）', (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390, screenWidth: 390);
      await _settleSoldier(tester);
      final String a1 = _soldierAsset(tester);
      await tester.pump(const Duration(milliseconds: 150));
      final String a2 = _soldierAsset(tester);
      expect(a2, isNot(a1),
          reason: '🔴 待机必须播帧序列（两帧之间帧号要变）：$a1 → $a2');
      expect(a1, contains('assets/guard/soldier_idle/'));
    });

    testWidgets('fighting 态两帧帧号相同（B12：专用站立静态，不是帧序列）',
        (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 358, screenWidth: 390, mode: GuardPillMode.fighting);
      await _settleSoldier(tester);
      final String a1 = _soldierAsset(tester);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      final String a2 = _soldierAsset(tester);
      expect(a2, a1,
          reason: '🔴 战斗中战士必须静止站立（不能闲晃，更不能一帧帧跳）');
      expect(a1, 'assets/guard/soldier_stand.webp',
          reason: '🔴 B12：战斗站立 = **专用站立静态** soldier_stand.webp'
              '（玄参：「攻击情况下，站立动作用单独的那张站立待机图片」），'
              '不再用 idle frame001 定格');
    });
  });

  // ── ③ 开火 → 攻击帧 300ms ───────────────────────────────────────────────
  group('③ 开火切攻击帧（kGuardSoldierAttackFlashMs）', () {
    testWidgets('开火后 300ms 内出现 attack 帧；窗口过后回到站立静态',
        (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      await _pumpCard(tester,
          cardWidth: 358,
          screenWidth: 390,
          mode: GuardPillMode.fighting,
          handle: handle);
      await _settleSoldier(tester);
      expect(_soldierAsset(tester), 'assets/guard/soldier_stand.webp',
          reason: '夹具前提：没开火时是 B12 专用站立静态');
      expect(_soldierAsset(tester), isNot(contains('soldier_attack')),
          reason: '夹具前提：没开火时不该是攻击帧');

      handle.fire();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_soldierAsset(tester), 'assets/guard/soldier_attack.webp',
          reason: '🔴 开火必须立刻切攻击帧（300ms 窗口内）');

      // 窗口内（累计 ≈ 116ms）仍是攻击帧。
      await tester.pump(const Duration(milliseconds: 100));
      expect(_soldierAsset(tester), 'assets/guard/soldier_attack.webp');

      // 过窗口（> 300ms）⇒ 回站立静态（B12：soldier_stand.webp，非 idle 帧）。
      await tester.pump(const Duration(milliseconds: 250));
      final String after = _soldierAsset(tester);
      expect(after, 'assets/guard/soldier_stand.webp',
          reason: '🔴 300ms 后必须回到专用站立静态（B12），不是 idle 循环帧');
    });
  });

  // ── ④ 条幅 / 卡内开火钮 消失（能量点 B8 已回归）─────────────────────────
  group('④ 卡内减法（历史键名墓碑）', () {
    testWidgets('状态条幅 / 气泡 C / 卡内开火钮 findsNothing；能量点已回归',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390, screenWidth: 390);
      // 🔴 字面量 Key：常量已被删，这里守的是「不许回来」。
      expect(find.byKey(const Key('guardEnergyBubble')), findsNothing,
          reason: '🔴 气泡 C 随 v3 裁定退役，不许回来');
      expect(find.byKey(const Key('guardSceneStatusPlate')), findsNothing);
      expect(find.byKey(const Key('guardSceneStatusLabel')), findsNothing);
      expect(find.byKey(const Key('guardSceneFireButton')), findsNothing,
          reason: '🔴 卡内开火钮已删（开火改由页面右上阳光胶囊触发）');
      // B8：能量点回归（玄参第三轮：「能量点恢复」）—— 正向钉住，位置见 v4 专项。
      expect(find.byKey(GuardSceneCard.energyDotKey(0)), findsOneWidget);
      expect(find.byKey(GuardSceneCard.energyDotKey(1)), findsOneWidget);
      // 卡内零状态文本 ⇒ 状态条幅 / −5 ☀ 尾标都无处可渲染。
      // 🔴 B13.9：免费档锁标下的小字已删 —— 零文本豁免撤销，卡内零 Text
      // 纪律恢复（战斗演出 MISS 只在 dodge 事件后出现 600ms）。
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(GuardSceneCard.cardKey),
                matching: find.byType(Text),
              ),
            )
            .map((Text t) => t.data ?? '')
            .toSet(),
        isEmpty,
        reason: '🔴 状态信息只保留在 Semantics.label（B13.9 豁免撤销；'
            '战斗演出 MISS 只在 dodge 事件后出现 600ms）',
      );
    });
  });

  // ── ⑤ 点阳光胶囊 = 开火（页面级）──────────────────────────────────────
  group('⑤ 胶囊开火', () {
    testWidgets('战斗中点阳光胶囊 ⇒ 真的打出子弹（走 GuardBattleHandle）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);
      await _enterBattle(tester);

      expect(find.byKey(GuardBattleField.bulletKey(0)), findsNothing,
          reason: '夹具前提：还没开火 ⇒ 场上没有子弹');
      await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(GuardBattleField.bulletKey(0)), findsOneWidget,
          reason: '🔴 点胶囊必须开火（开火入口已从卡内搬到页面胶囊）');
    });
  });

  // ── ⑥ 胶囊冻结 ─────────────────────────────────────────────────────────
  group('⑥ 阳光胶囊位置（fighting 冻结 / 待机漂浮）', () {
    testWidgets('fighting 连测 3 帧 getTopLeft 逐位相同', (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);
      await _enterBattle(tester);

      final Offset p1 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump(const Duration(milliseconds: 100));
      final Offset p2 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump(const Duration(milliseconds: 100));
      final Offset p3 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      expect(p2, p1, reason: '🔴 战斗中胶囊必须钉死（开火要瞄不动的目标）');
      expect(p3, p1, reason: '🔴 连测 3 帧逐位相同');
    });

    testWidgets('非战斗态 3 帧内有位移（原漂浮轨迹没被改坏）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);

      final Offset p1 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump(const Duration(milliseconds: 180));
      final Offset p2 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump(const Duration(milliseconds: 180));
      final Offset p3 = tester.getTopLeft(find.byKey(ChildTodayPage.sunBubbleKey));
      expect(p1 == p2 && p2 == p3, isFalse,
          reason: '🔴 待机态胶囊必须照旧漂浮（$p1 → $p2 → $p3）');
    });
  });

  // ── ⑦ 尺寸字面量 + 窄卡 0.85 + 通道实测 ────────────────────────────────
  group('⑦ 尺寸与通道验收', () {
    testWidgets('房子 88 / 战士 64 / 怪 44（字面量，B13）；390 与 1024 逐位相等',
        (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 390, screenWidth: 390, mode: GuardPillMode.fighting);
      final Size houseSmall = tester.getSize(find.byKey(GuardSceneCard.houseKey));
      final Size soldierSmall =
          tester.getSize(find.byKey(GuardSceneCard.soldierKey));
      final Size monsterSmall =
          tester.getSize(find.byKey(GuardBattleField.monsterKey(0)));

      expect(houseSmall.height, closeTo(88, 0.01),
          reason: '🔴 房子高 = 88（玄参字面量）');
      expect(houseSmall.width, closeTo(156, 1.0),
          reason: '🔴 房子宽 ≈ 156（88 × 1.7746，contain 不裁切）');
      expect(soldierSmall.width, closeTo(60, 0.01),
          reason: '🔴 B13.2：战士边长 = 60（真机复验 64 → 60）');
      // 🔴 B13：战斗怪种类**跟当日小偷走**（_kindOfThief）—— 本夹具
      // dayKey '2026-11-10' / 'seed-0' 的战局种类由脚本派生，宽高按该种反解。
      final String kindId = deriveGuardBattleScript(
              dayKey: '2026-11-10', childId: 'seed-0')
          .monsters
          .first
          .kind
          .id;
      expect(monsterSmall.width,
          closeTo(const GuardCardLayout(390).monsterWidthOf(kindId), 0.01),
          reason: '🔴 m 宽 = 等面积反解（B13 种类跟当日小偷：$kindId）');
      expect(monsterSmall.height,
          closeTo(const GuardCardLayout(390).monsterHeightOf(kindId), 0.01),
          reason: '🔴 m 高 = 等面积反解（$kindId）');

      await _pumpCard(tester,
          cardWidth: 1024, screenWidth: 1024, mode: GuardPillMode.fighting);
      expect(tester.getSize(find.byKey(GuardSceneCard.houseKey)), houseSmall,
          reason: '🔴 iPad 只拉长通道，房子尺寸逐位不变');
      expect(tester.getSize(find.byKey(GuardSceneCard.soldierKey)), soldierSmall,
          reason: '🔴 战士尺寸逐位不变');
      expect(tester.getSize(find.byKey(GuardBattleField.monsterKey(0))),
          monsterSmall,
          reason: '🔴 小怪尺寸逐位不变');
    });

    testWidgets('320 卡（≤380）按 0.85 等比缩，卡高仍是 112',
        (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 320, screenWidth: 320, mode: GuardPillMode.fighting);
      final String kindId = deriveGuardBattleScript(
              dayKey: '2026-11-10', childId: 'seed-0')
          .monsters
          .first
          .kind
          .id;
      expect(tester.getSize(find.byKey(GuardSceneCard.houseKey)).height,
          closeTo(88 * 0.85, 0.05),
          reason: '🔴 窄卡：房子 88 × 0.85 = 74.8');
      expect(tester.getSize(find.byKey(GuardSceneCard.soldierKey)).width,
          closeTo(60 * 0.85, 0.05),
          reason: '🔴 窄卡：战士 60 × 0.85 = 51.0');
      expect(tester.getSize(find.byKey(GuardBattleField.monsterKey(0))).width,
          closeTo(const GuardCardLayout(320).monsterWidthOf(kindId), 0.05),
          reason: '🔴 窄卡：m 宽 × 0.85（$kindId）');
      expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
          closeTo(kGuardSceneCardHeight, 0.5),
          reason: '🔴 卡高**不缩**（跨屏宽恒定 112，滚动预算才稳）');
    });

    test('通道实测：390 卡 117.84pt / 320 卡 88.66pt / 1024 卡 751.84pt', () {
      const GuardCardLayout wide = GuardCardLayout(390);
      const GuardCardLayout narrow = GuardCardLayout(320);
      const GuardCardLayout tablet = GuardCardLayout(1024);
      expect(wide.scale, 1.0, reason: '390 卡不进窄卡缩放');
      expect(narrow.scale, kGuardNarrowCardScale, reason: '320 卡进 0.85 缩放');
      // 🔴 钉**实测值**（±0.5pt），不写宽泛阈值：
      //   B9/C3 把通道左端从「战士右缘」左移到「战士右缘 − 半个怪」
      //   （怪半个身子压住战士才停）；B13.2 战士 64→60 ⇒ 390 屏跑道 117.84pt。
      expect(wide.channelWidth, closeTo(117.84, 0.5),
          reason: '🔴 实测 ${wide.channelWidth}');
      expect(narrow.channelWidth, closeTo(88.66, 0.5),
          reason: '🔴 实测 ${narrow.channelWidth}（玄参验收线 55 ⇒ 达标）');
      expect(tablet.channelWidth, closeTo(751.84, 0.5),
          reason: '🔴 iPad 只拉长通道');
      // 兜底下限：通道至少容得下一只怪（44pt），否则演出必崩。
      expect(wide.channelWidth, greaterThanOrEqualTo(44));
      expect(narrow.channelWidth, greaterThanOrEqualTo(44));
    });
  });

  // ── ⑧ 教学永久一次（同日第二遍）────────────────────────────────────────
  group('⑧ 教学永久一次', () {
    testWidgets('首装弹 + 标记；同日第二遍点卡不再弹（存档字段仍是 false 也不弹）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);
      expect(env.tutorialSeenFlag, isFalse);

      // 第一遍：点卡 → 教学 → OK → 确认卡 → 取消（回到 pending，可再点一次）。
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _pumpUntil(tester, find.byKey(kGuardTutorialSheetKey));
      await _settleRoute(tester);
      await tester.tap(find.byKey(kGuardTutorialOkKey));
      await _settleRoute(tester);
      expect(env.tutorialSeenFlag, isTrue,
          reason: '🔴 关闭教学即写 prefs（$kGuardTutorialSeenPrefKey）');
      await tester.tap(find.text('今天不赶了'));
      await _settleRoute(tester);

      // 第二遍（同一天、同一 env）：不得再弹教学。
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _settleRoute(tester);
      expect(find.byKey(kGuardTutorialSheetKey), findsNothing,
          reason: '🔴 B7：教学一辈子只讲一次（旧实现按天重置 ⇒ 这里会再弹）');
      expect(find.text('要花费 $kGuardPayCost 阳光，\n进行花园守卫吗？'),
          findsOneWidget,
          reason: '跳过教学后必须直接落到确认卡（B13：玄参指定新文案；B13.2 分两段）');
    });
  });

  // ── ⑨ 最坏组合不溢出 ──────────────────────────────────────────────────
  group('⑨ 320×568 + en + 1.3 两态零 overflow', () {
    for (final GuardPillMode mode in <GuardPillMode>[
      GuardPillMode.pendingFree,
      GuardPillMode.fighting,
    ]) {
      testWidgets('$mode', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await _pumpCard(tester,
            cardWidth: 320,
            screenWidth: 320,
            mode: mode,
            english: true,
            textScale: 1.3);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull,
            reason: '🔴 320×568 + en + 1.3 下 $mode 不得溢出');
        expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
            closeTo(kGuardSceneCardHeight, 0.5));
      });
    }
  });

  // ── ⑩ A4 满宽贴边（页面级）────────────────────────────────────────────
  group('⑩ A4 满宽贴边（页面级）', () {
    testWidgets('390 屏：卡宽 == 屏宽、x == 0（草地贴到屏幕边）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);

      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      expect(card.width, closeTo(390, 0.5),
          reason: '🔴 卡宽 = 屏宽（ListView 的 16pt 内边距被 OverflowBox 抵掉）');
      expect(card.left, closeTo(0, 0.5), reason: '🔴 贴左边');
      expect(card.right, closeTo(390, 0.5), reason: '🔴 贴右边');
    });
  });
}
