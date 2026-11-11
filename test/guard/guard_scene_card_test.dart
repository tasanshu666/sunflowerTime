/// 守卫战 v2 · B2 **场景卡骨架** + B7 **卡内减法 / 教学永久一次** 的布局与交互护栏。
///
/// 真源：守卫战设计文档 §6.2 布局 v3 / §7-B2 / §7-B7
/// （零文本卡面、常驻战士、教学改 prefs 永久一次）。
///
/// ## 覆盖
/// | # | 断言 | 用例 |
/// |---|---|---|
/// | SC1 | 六件事在树（草地板 / 房子 / 战士 / 开始钮 / 卡 / 语义）；**卡内零文本**；战斗态才有倒计时细线 | SC1 |
/// | SC2 | 卡高恒 160、宽撑满槽位（288）；状态只经 `Semantics.label`（含尾标 −5 ☀） | SC2 |
/// | SC3 | 教学：**永久一次**（prefs 落盘后，就算存档的 `tutorialSeen` 回到 false 也不再弹） | SC3 |
/// | SC5 | 320 屏（288 槽）+ en + 1.3 倍字号：5 态全部不溢出 | SC5 |
///
/// ## 🔴「卡内零文本」为什么是硬断言
/// B7 玄参裁定「状态信息只留 `Semantics.label`」—— 卡面不再有任何 `Text`。
/// 这条同时钉住了：能量点气泡 C、顶部状态条幅、`−5 ☀` 尾标**全部退出卡面**
/// （它们曾是卡内唯一的三种文本来源）。
///
/// ## 🔴 绝不 `pumpAndSettle`
/// 页面夹具挂的是真 `ChildTodayPage`（阳光气泡 + 常驻战士帧序列都在循环动画）；
/// widget 级夹具虽无循环动画，也统一用定长 `pump` 推进，口径一致。
library guard_scene_card_test;

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
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
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
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// widget 级夹具（SC1 / SC2 / SC5：不碰任何服务）
// ═══════════════════════════════════════════════════════════════════════

/// 直接构造一份守卫快照（教学字段缺省 false，widget 级用例不消费它）。
GuardTodayView _view(
  GuardPillMode mode, {
  GuardThiefKind thief = GuardThiefKind.sunRat,
  int winSun = 2,
  int energy = 0,
  double balance = 0,
  bool tutorialSeen = false,
}) {
  final GuardDayStatus status = switch (mode) {
    GuardPillMode.claimed => GuardDayStatus.claimed,
    GuardPillMode.fighting => GuardDayStatus.fighting,
    GuardPillMode.freeRide => GuardDayStatus.short,
    _ => GuardDayStatus.pending,
  };
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-01-01',
      status: status,
      thiefKind: mode == GuardPillMode.absent ? null : thief,
      winSun: winSun,
      tutorialSeen: tutorialSeen,
    ),
    energyAvailable: energy,
    balance: balance,
  );
}

/// 把场景卡单独挂在 [width] 宽的槽位里（320 屏 − 左右 16 = 288）。
///
/// 🔴 卡内已零文本，但 SC5 的 en + 1.3 组合**仍走真 delegate**：一旦哪天
/// 有人把文案加回卡面，这条会立刻在 en 长文案下炸出来（护栏的价值在这一步）。
/// dayKey/childId 用字面量：widget 级用例不消费战局结果，fighting 态会挂
/// L4 战斗层跑 ticker，无妨。
Future<void> _pumpCard(
  WidgetTester tester,
  GuardTodayView view, {
  double width = 288,
  double textScale = 1.0,
  bool english = false,
  VoidCallback? onStart,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 568),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Localizations(
        locale: english ? const Locale('en') : const Locale('zh'),
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
                  width: width,
                  child: GuardSceneCard(
                    view: view,
                    dayKey: '2026-01-01',
                    childId: 'seed-0',
                    onStart: onStart,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 读读屏标签（B7：状态的**唯一**出口，不占布局 ⇒ 不需要 semantics 树）。
String _semanticsLabel(WidgetTester tester) {
  final Semantics widget =
      tester.widget<Semantics>(find.byKey(GuardSceneCard.statusSemanticsKey));
  return widget.properties.label ?? '';
}

// ═══════════════════════════════════════════════════════════════════════
// 页面级夹具（SC3 教学流：真库 + 真 prefs + 真守卫链路）
// ═══════════════════════════════════════════════════════════════════════

/// 一个装配好的今日页环境（内存库 + 内存 prefs + 已初始化的 AccountService）。
class _Env {
  _Env({required this.sp, required this.database, required this.account});

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;

  String get childId => account.childId;

  GuardStatePrefsStore get guardStore => GuardStatePrefsStore(sp);

  /// 今日守卫存档。
  Future<GuardDayState> guardState() => guardStore.read(childId);

  /// 「教学已看」的 prefs 标记（B7 起的真实判据）。
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

/// 给账本记一笔收入，把余额抬到 [amount]（余额 ≥ 5 ⇒ pendingPaid）。
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

/// 挂载真「今日页」（无字号注入 —— 本文件不做大字号页面用例，见 SC5）。
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

/// 反复 `pump` 直到 [finder] 出现（**不用** `pumpAndSettle`）。
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

/// 让浮层 / 路由过渡跑完（6 × 100ms 覆盖 200ms 级过渡）。
Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── SC1 卡内六件事 + 零文本 ───────────────────────────────────────────
  group('SC1 卡内六件事与零文本', () {
    testWidgets('待机态：草地板 / 房子 / 战士 / 开始钮 / 语义全在树，卡内零文本',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree, energy: 2),
          onStart: () {});

      expect(find.byKey(GuardSceneCard.cardKey), findsOneWidget);
      // L1 草地板（占位 = 奶油绿渐变 DecoratedBox）。
      expect(find.byKey(GuardSceneCard.backdropKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(GuardSceneCard.cardKey),
          matching: find.byType(DecoratedBox),
        ),
        findsWidgets,
        reason: 'L1 草地板必须渲染（渐变 DecoratedBox）',
      );
      // B7：房子与**常驻战士**（待机态也在树 —— 旧实现只在战斗层里画）。
      expect(find.byKey(GuardSceneCard.houseKey), findsOneWidget);
      expect(find.byKey(GuardSceneCard.soldierKey), findsOneWidget,
          reason: '🔴 B7：战士必须常驻（待机态就得站在房子旁）');
      // 右簇：开始守卫钮；倒计时细线只在战斗态。
      expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget);
      expect(find.byKey(GuardSceneCard.countdownKey), findsNothing,
          reason: '待机态不得渲染倒计时细线');

      // 🔴 卡内零文本（状态只走 Semantics.label）。
      expect(
        find.descendant(
          of: find.byKey(GuardSceneCard.cardKey),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: '🔴 B7：卡内必须零 Text（能量点气泡 / 状态条幅 / 尾标全部退出卡面）',
      );
      // 卡内开火钮已删（旧实现是一枚 local_fire_department 大圆钮）。
      expect(find.byIcon(Icons.local_fire_department), findsNothing,
          reason: '🔴 B7：卡内开火钮已删（开火改由页面右上阳光胶囊触发）');
      expect(_semanticsLabel(tester), '用专注能量赶跑它（免费）',
          reason: '状态文案必须完整活在 Semantics.label 上（读屏可读）');
    });

    testWidgets('战斗态：开始钮退位（该格留空），倒计时细线 + 战斗层上屏',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.fighting));

      expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing,
          reason: '战斗态不得再渲染「开始守卫」');
      expect(find.byKey(GuardSceneCard.countdownKey), findsOneWidget);
      expect(find.byKey(GuardSceneCard.soldierKey), findsOneWidget,
          reason: '战斗态战士仍在（常驻元素，不随 L4 装卸）');
      expect(_semanticsLabel(tester), '守卫正在赶走它…');
    });
  });

  // ── SC2 卡高 160 + 状态只走语义 ───────────────────────────────────────
  group('SC2 卡高与语义出口', () {
    testWidgets('widget 级：卡高恒 160、宽撑满槽位（288），不随内容变化',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(GuardPillMode.pendingPaid, balance: 100),
        onStart: () {},
      );
      final Rect rect = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      expect(rect.height, closeTo(kGuardSceneCardHeight, 0.5),
          reason: '🔴 卡高必须恒 = kGuardSceneCardHeight(160)');
      expect(rect.width, closeTo(288, 0.5),
          reason: '卡宽必须撑满槽位（320 − 32 = 288）');
      expect(_semanticsLabel(tester), contains('−$kGuardPayCost ☀'),
          reason: 'pendingPaid 尾标照常进语义标签（旧的卡内 Text 已删）');
    });

    testWidgets('页面级：absent ⇒ 场景卡一项都不进树（零占位）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv(); // 刻意不种植物 ⇒ resolve 无贼 ⇒ absent
      await _pumpToday(tester, env);

      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: 'absent 必须**完全不渲染**（不是透明 / 零宽）');
      expect(find.byKey(GuardSceneCard.soldierKey), findsNothing);
      expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing);
      expect(find.text('今日获取阳光'), findsOneWidget,
          reason: '守卫缺席不得连累今日页其余内容');
    });
  });

  // ── SC3 教学浮层（A）：**永久一次**（B7 改判据）────────────────────────
  group('SC3 教学浮层 A（一辈子只讲一次）', () {
    testWidgets('首次点卡 ⇒ 弹教学；「知道了」后 prefs 落盘并继续原流程',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100); // 无能量 + 余额 100 ⇒ pendingPaid
      await _pumpToday(tester, env);
      expect(env.tutorialSeenFlag, isFalse, reason: '首装：prefs 标记必须还没写');

      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _pumpUntil(tester, find.byKey(kGuardTutorialSheetKey));
      expect(find.byKey(kGuardTutorialSheetKey), findsOneWidget);
      expect(find.byKey(kGuardTutorialOkKey), findsOneWidget);
      // PRD §6 教学正文必须含「15 分钟」（攒能量规则）。
      expect(find.textContaining('15 分钟'), findsOneWidget,
          reason: '教学正文必须讲清「专注满 15 分钟 = 1 能量点」');

      // 「知道了」⇒ 浮层关闭 + prefs 落盘 + 流程继续（付费路径 ⇒ 确认卡）。
      await _settleRoute(tester);
      await tester.tap(find.byKey(kGuardTutorialOkKey));
      await _settleRoute(tester);
      expect(find.byKey(kGuardTutorialSheetKey), findsNothing);

      expect(env.tutorialSeenFlag, isTrue,
          reason: '🔴 B7：关闭浮层即写设备级 prefs（$kGuardTutorialSeenPrefKey）');
      expect((await env.guardState()).tutorialSeen, isTrue,
          reason: '兼容口径：当日存档标记照旧打上（但它已不驱动弹层）');
      expect(find.text('要花费 $kGuardPayCost 阳光，\n进行花园守卫吗？'), findsOneWidget,
          reason: '教学关闭后必须无缝接原 v1 流程（此处 = 付费确认卡）');
    });

    testWidgets('存档 tutorialSeen=false（= 次日新存档）⇒ 只要 prefs 已看过就**不再弹**',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      // 模拟「昨天看过教学、今天存档刚重建」：prefs 有标记 + 存档 tutorialSeen=false。
      await env.sp.setBool(kGuardTutorialSeenPrefKey, true);
      final String today = dayKey(DateTime.now());
      await env.guardStore.write(
        env.childId,
        GuardDayState(
          dayKey: today,
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          tutorialSeen: false,
        ),
      );
      await _pumpToday(tester, env);
      expect((await env.guardState()).tutorialSeen, isFalse,
          reason: '夹具前提：当日存档的旧标记是 false（= 旧实现会再弹一次）');

      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _settleRoute(tester);

      expect(find.byKey(kGuardTutorialSheetKey), findsNothing,
          reason: '🔴 B7 修复：教学的判据是 prefs（永久），不再吃「每日重置」的存档字段');
      expect(find.text('要花费 $kGuardPayCost 阳光，\n进行花园守卫吗？'), findsOneWidget,
          reason: '教学被跳过 ⇒ 直接落到确认卡');
    });
  });

  // ── SC5 最坏组合不溢出 ────────────────────────────────────────────────
  group('SC5 320 槽（288 宽）+ en + 1.3 倍字号：5 态全部不溢出', () {
    testWidgets('逐态渲染，宽度不被文字顶宽、无 RenderFlex overflow',
        (WidgetTester tester) async {
      for (final GuardPillMode mode in <GuardPillMode>[
        GuardPillMode.pendingFree,
        GuardPillMode.pendingPaid,
        GuardPillMode.freeRide,
        GuardPillMode.fighting,
        GuardPillMode.claimed,
      ]) {
        await _pumpCard(
          tester,
          _view(mode, energy: 2, balance: 100),
          textScale: 1.3,
          english: true,
        );
        expect(tester.takeException(), isNull,
            reason: '$mode 在 288 槽 + en + 1.3 下不得溢出（F127 教训）');
        final Rect rect = tester.getRect(find.byKey(GuardSceneCard.cardKey));
        expect(rect.width, closeTo(288, 0.5),
            reason: '$mode 卡宽必须撑满槽位，不能被文字顶宽');
        expect(rect.height, closeTo(kGuardSceneCardHeight, 0.5),
            reason: '$mode 卡高必须恒 160');
      }
    });
  });
}
