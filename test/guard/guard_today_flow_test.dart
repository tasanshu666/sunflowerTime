/// 守卫战 v2 · 今日页守卫**场景卡**与进战流程的**行为与布局护栏**。
///
/// 沿革：第三批 `guard_pill_test.dart` → B2 场景卡迁移 → **B3 改名本文件**
/// （v1 胶囊本体与战斗浮层已退役；战斗流程用例迁往 `guard_battle_field_test.dart`）。
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §4 / §8.1 / §8.2 / §8.3；
/// 守卫战 v2 设计文档 §7-B2/B3。
///
/// ## 覆盖（迁移对照见交付报告）
/// | # | 断言 | 用例 |
/// |---|---|---|
/// | 1 | `absent` 零占位（第一张卡顶 == 列表顶 + 卡片内边距，无 140+10 空隙） | ① |
/// | 2 | 5 种状态的文案与可点性（场景卡：可点 = 「开始守卫」钮在树且回调触发） | ② |
/// | 3 | 有能量时文案是「免费」且点击**不弹确认卡**、L4 战斗层直接上屏 | ③ |
/// | 4 | 无能量时点击**先弹确认卡**，「今天不赶了」→ 不扣钱、状态不变 | ④ |
/// | 5 | 320×554 + 1.3 字号下场景卡不溢出（宽度 = 屏宽 − 32 = 288） | ⑤ |
/// | 8 | 无掉落档结算卡不写「券还能省 0 阳光」 | ⑧ |
/// | 9 | 「券还能省 N」= 真实节省量（F4 / G2） | ⑨ |
/// | 10 | T03 演出链：战完 → 宝箱（不可跳过）→ 结算卡 → 收下不成「宝箱重演」；卡面阳光 == 账本 | ⑩ |
///
/// （旧 ⑥⑦「跳过 / 看完 10 秒进结算」随战斗浮层退役；等价经济断言——
/// 「claim 只落一次账 / 付费恰好扣一次」——迁往 `guard_battle_field_test.dart`
/// 的全流程用例，断言对象换成卡内战斗与 30s 窗口，覆盖不降。）
///
/// ## 为什么用真仓储 + 内存库（而不是假服务）
/// 守卫链路是 `expire() → resolve() → energyAvailable()` 三连，且 `resolve()` 有
/// 「昨天未结算 ⇒ 拒绝覆盖」的闸门、`claim()` 有「状态层 + 账本层 + 写入层」三层
/// 幂等 —— 这些**正是本批要验证的东西**。用假服务替身等于把被验证的行为一起替掉。
/// 故这里只覆盖 `sharedPreferencesProvider` / `appDatabaseProvider` /
/// `accountServiceProvider` 三个出口（与 `test/child/shell_narrow_large_text_test.dart`
/// 同款夹具），守卫领域层跑真实现。
///
/// ## 🔴 绝不 `pumpAndSettle`
/// 今日页阳光气泡是 12 秒**无限循环**动画（`_drift.repeat()`），
/// `pumpAndSettle` 会永不返回。全文件用定长 `pump(Duration)` 推进。
library guard_today_flow_test;

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
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
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

  /// 今日守卫存档（跨天 = 昨天那条，原样返回）。
  Future<GuardDayState> guardState() => guardStore.read(childId);

  /// 某个 refType 今天在账本里的行数（`guard_win` / `guard_pay` / `guard_stolen`）。
  Future<int> ledgerRowsOnDay(String refType, String dayKeyValue) =>
      ledger.countByRefTypeAndRefIdOnDay(refType, kGuardRefId, dayKeyValue);
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

/// 种一株存活苗（`resolve()` 只有在**有存活株**时才生成小偷）。
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

/// 记一次**有效专注**（`plannedMin == 0` + `actualFocusMin ≥ 15` ⇒ 有效 ⇒ +1 能量）。
Future<void> _seedValidFocus(_Env env, {String id = 'f_1'}) async {
  final DateTime now = DateTime.now();
  // 🔴 午夜安全：sessionsOfDay 按 start 归日，`now − 20min` 在午夜后 20 分钟
  // 内属于昨天 ⇒ 能量 0 ⇒ 免罚档（详见 guard_battle_field_test 同名注释）。
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

/// 挂载「今日页」并推进到守卫链路完成。
///
/// [textScale] 从 `MaterialApp.builder` 注入（F126 教训：包在 `home` 上的
/// MediaQuery 覆盖不到 Dialog / 覆盖层）。
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  _Env env, {
  Size screen = const Size(390, 844),
  double textScale = 1.0,
  int frames = 24,
}) async {
  tester.view.physicalSize = screen;
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
      child: MaterialApp(
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const ChildTodayPage(),
      ),
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

/// 让**路由过渡**跑完（结算卡 push / 教学浮层开关的过渡各 ~200ms）。
Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 越过 B2 教学浮层。
///
/// 🔴 B7：教学改成**永久一次**（设备级 prefs `guard_tutorial_seen_v1`），
/// 同一 env 内第二次点卡不会再弹 ⇒ 这里必须「弹了才点」；无条件等它会挂到超时。
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

/// 读场景卡的状态语义标签（B7：卡内零文本，状态只经 `Semantics.label` 出口）。
String _cardLabel(WidgetTester tester) =>
    tester
        .widget<Semantics>(find.byKey(GuardSceneCard.statusSemanticsKey))
        .properties
        .label ??
    '';

/// 今日页第一张状态卡**标签**顶边相对列表顶边的偏移（渲染盒实测）。
///
/// 绝对值的 3pt 来自 `_StatCard` 的 1px 描边 + 行盒上行留白 —— 本文件不依赖这个
/// 绝对值，而是比较「有场景卡 / 无场景卡」两种布局的**差值**（B2 起必须恰好
/// 140 + 10 = 150pt；B2 前 v1 胶囊时代是 44 + 10 = 54pt）。
double _firstCardOffset(WidgetTester tester) {
  final Rect listRect = tester.getRect(find.byType(ListView));
  final Rect labelRect = tester.getRect(find.text('今日获取阳光'));
  return labelRect.top - listRect.top;
}

/// 直接构造一份守卫快照（用于纯 widget 用例，不碰任何服务）。
GuardTodayView _view(
  GuardPillMode mode, {
  GuardThiefKind thief = GuardThiefKind.sunRat,
  GuardDropKind drop = GuardDropKind.waterVoucher,
  int winSun = 2,
  int energy = 0,
  double balance = 0,
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
      dropKind: drop,
    ),
    energyAvailable: energy,
    balance: balance,
  );
}

/// 把 [GuardSceneCard] 单独挂在 [width] 宽的槽位里（= 320 屏 − 左右 16）。
///
/// （B3 迁移注：原 `_pumpPill` 的夹具对象由 GuardPill 换成 GuardSceneCard；
/// dayKey/childId 用字面量 —— widget 级用例不消费战局结果，只验布局与交互。）
Future<void> _pumpCard(
  WidgetTester tester,
  GuardTodayView view, {
  VoidCallback? onStart,
  double width = 288,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
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
  );
  await tester.pump(const Duration(milliseconds: 50));
}

// ═══════════════════════════════════════════════════════════════════════
// ① absent 零占位
// ═══════════════════════════════════════════════════════════════════════

void _groupAbsent() {
  group('① absent 零占位', () {
    testWidgets('全园无存活株 ⇒ 不渲染场景卡；种上植物后卡片出现，第一张卡**恰好**下移 122pt',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv(); // 先刻意不种植物
      final ProviderContainer container = await _pumpToday(tester, env);

      // ── 前：absent ────────────────────────────────────────────────
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing,
          reason: 'absent 必须**完全不渲染**（不是透明 / 零宽）');
      final double offsetWithoutCard = _firstCardOffset(tester);

      // ── 后：种一株（= 有存活株 ⇒ resolve 生成小偷），触发一次刷新 ──
      await _seedPlant(env);
      container.read(economyRevisionProvider.notifier).state++;
      await _pumpUntil(tester, find.byKey(GuardSceneCard.cardKey));
      await _settleRoute(tester);

      expect(find.byKey(GuardSceneCard.cardKey), findsOneWidget,
          reason: '有存活株时 resolve() 必然生成小偷 ⇒ 场景卡必须渲染');
      final double offsetWithCard = _firstCardOffset(tester);

      // 🔴 B10/B1：**卡上不再包 `Transform`**（B9 的做法会被 ListView 视口裁掉
      // ⇒ 玄参报的「房子被削顶」）。上移改成「缩上方 sceneGap」⇒ 视口顶边自己
      // 上移 16pt，卡在视口内的偏移恒为 0。
      // 注：祖先链上仍有页面级 Transform（底图 / 气泡），故判据是「**没有任何
      // 祖先把卡纵向位移**」，而不是「一个 Transform 都没有」。
      for (final Transform tf in tester.widgetList<Transform>(
        find.ancestor(
          of: find.byKey(GuardSceneCard.cardKey),
          matching: find.byType(Transform),
        ),
      )) {
        expect(tf.transform.getTranslation().y, closeTo(0, 0.01),
            reason: '🔴 B10/B1：卡的祖先不许把它纵向位移（B9 的 −16 是削顶根因）');
      }
      final Rect listRect = tester.getRect(find.byType(ListView));
      expect(
          tester.getRect(find.byKey(GuardSceneCard.cardKey)).top - listRect.top,
          closeTo(0, 0.5),
          reason: '🔴 B10/B1：卡顶 == 列表顶（整张卡合法可见，零裁剪）');

      // 🔴 零占位的判据：偏移量的**差值恰好等于场景卡占位高度**，
      //    也就是说 absent 时没有留下任何空档。
      // B10：卡高 112 + 间距 10 = **122**（偏移量相对列表顶量，故上移量不参与）。
      expect(offsetWithCard - offsetWithoutCard,
          closeTo(kGuardSceneCardHeight + kGuardPillGap, 0.5),
          reason: '场景卡占位必须恰好 = kGuardSceneCardHeight(112) + '
              'kGuardPillGap(10) = 122pt');
    });

    testWidgets('场景卡矩形：卡顶 == 列表顶（零裁剪）、宽度 = 屏宽、高度 = 112',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);

      final Rect listRect = tester.getRect(find.byType(ListView));
      final Rect cardRect = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      // 🔴 B10/B1：卡顶必须**不高于**列表顶（否则被 ClipRect 裁掉屋顶）。
      expect(cardRect.top, greaterThanOrEqualTo(listRect.top - 0.01),
          reason: '🔴 卡顶 ≥ 视口顶边（这条是 B10 的硬断言：卡不许被裁剪）');
      expect(cardRect.top, closeTo(listRect.top, 0.5),
          reason: '🔴 卡顶 == 列表顶（上移量已由 sceneGap 让出）');
      // B8/A4：卡改成**满宽贴边**（OverflowBox 抵掉 ListView 的 16pt 内边距）。
      expect(cardRect.left, closeTo(listRect.left, 0.5),
          reason: '🔴 草地条贴到屏幕左边');
      expect(cardRect.width, closeTo(listRect.width, 0.5),
          reason: '🔴 卡宽 = 屏宽（不再 − 32）');
      expect(cardRect.height, closeTo(kGuardSceneCardHeight, 0.5),
          reason: '场景卡高度恒 112pt（不随字号缩放）');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ② 五种状态的文案与可点性（B3 迁移：夹具 GuardPill → GuardSceneCard）
// ═══════════════════════════════════════════════════════════════════════

void _groupModes() {
  group('② 五种状态的文案与可点性（场景卡）', () {
    /// 逐态：文案、是否可点（可点 = 「开始守卫」钮在树且回调被触发）。
    final Map<GuardPillMode, String> labels = <GuardPillMode, String>{
      GuardPillMode.pendingFree: '用专注能量赶跑它（免费）',
      GuardPillMode.pendingPaid: '偷菜贼来了，现在赶跑它吧',
      GuardPillMode.freeRide: '小小葵自己顶班，今天不用管',
      GuardPillMode.fighting: '守卫正在赶走它…',
      GuardPillMode.claimed: '今天的菜守住了',
    };

    for (final MapEntry<GuardPillMode, String> entry in labels.entries) {
      final GuardPillMode mode = entry.key;
      final bool tappable =
          mode == GuardPillMode.pendingFree || mode == GuardPillMode.pendingPaid;

      testWidgets('${mode.name} → 「${entry.value}」· ${tappable ? '可点' : '不可点'}',
          (WidgetTester tester) async {
        int taps = 0;
        await _pumpCard(tester, _view(mode), onStart: () => taps++);

        expect(_cardLabel(tester), contains(entry.value),
            reason: '${mode.name} 的状态文案必须活在卡的 Semantics.label 上（卡内零文本）');
        if (tappable) {
          expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
              reason: '${mode.name} 必须渲染「开始守卫」钮');
          await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
          await tester.pump();
          expect(taps, 1, reason: '${mode.name} 必须可点');
        } else {
          // 等价断言（旧：整条胶囊不可点）：非可点态**没有**开始钮，
          // 点卡面其它位置也不触发回调。
          expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing,
              reason: '${mode.name} 不得渲染「开始守卫」钮');
          await tester.tap(find.byKey(GuardSceneCard.cardKey),
              warnIfMissed: false);
          await tester.pump();
          expect(taps, 0, reason: '${mode.name} 必须不可点');
        }
      });
    }

    testWidgets('pendingPaid 尾标显示 −5 ☀（数字来自 kGuardPayCost）',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingPaid), onStart: () {});
      expect(_cardLabel(tester), contains('−$kGuardPayCost ☀'));
    });

    testWidgets('pendingFree 没有尾标（文案已说明免费，不重复报 0 ☀）',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(GuardPillMode.pendingFree), onStart: () {});
      expect(_cardLabel(tester), isNot(contains('−$kGuardPayCost ☀')));
    });

    test('guardPillModeOf：resolve 的三种成本模式映射到正确的卡态', () {
      const String today = '2026-01-01';
      GuardDayState pendingState() => const GuardDayState(
            dayKey: today,
            status: GuardDayStatus.pending,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 2,
          );
      // 有能量 ⇒ 免费；无能量余额够 ⇒ 付费确认；无能量余额 < 5 ⇒ 免罚。
      expect(guardPillModeOf(pendingState(), 1, 0), GuardPillMode.pendingFree);
      expect(
          guardPillModeOf(pendingState(), 0, kGuardPayCost.toDouble()),
          GuardPillMode.pendingPaid);
      expect(
          guardPillModeOf(
              pendingState(), 0, kGuardFreeRideBalance.toDouble() - 1),
          GuardPillMode.freeRide);
      // 免罚档由 resolve() 写死，余额后来变多也不回到可点。
      expect(
          guardPillModeOf(
              const GuardDayState(
                  dayKey: today,
                  status: GuardDayStatus.short,
                  thiefKind: GuardThiefKind.sunRat),
              5,
              100),
          GuardPillMode.freeRide);
      // 没有贼 ⇒ 零占位。
      expect(
          guardPillModeOf(
              GuardDayState.empty(today), 2, 100),
          GuardPillMode.absent);
      // 已领取。
      expect(
          guardPillModeOf(
              const GuardDayState(
                  dayKey: today,
                  status: GuardDayStatus.claimed,
                  thiefKind: GuardThiefKind.sunRat),
              2,
              100),
          GuardPillMode.claimed);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ③ 有能量 → 免费文案 + 点击不弹确认卡 + L4 战斗层直接上屏
// ═══════════════════════════════════════════════════════════════════════

void _groupFreePath() {
  group('③ 有能量：文案是「免费」；B13.7 起点击也弹确认卡（防误操作）', () {
    testWidgets('有 1 次有效专注 ⇒ 卡写「免费」，点击弹免费确认卡，确认后进战斗（L4 上屏）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _pumpToday(tester, env);

      expect(_cardLabel(tester), contains('用专注能量赶跑它（免费）'));
      expect(_cardLabel(tester), isNot(contains('−$kGuardPayCost ☀')),
          reason: '免费路径不该显示 −5 ☀');

      // B2/B3：点的是场景卡「开始守卫」；fresh 环境先过教学浮层。
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _passTutorial(tester);
      await tester.pump();

      // 🔴 B13.7（玄参：防误操作）：免费路径**也弹确认卡**，但不提阳光。
      expect(find.text('要花费 $kGuardPayCost 阳光，\n进行花园守卫吗？'), findsNothing,
          reason: '免费路径的确认卡不该出现付费标题');
      expect(find.text('要派出向日葵战士，\n进行花园守卫吗？'), findsOneWidget,
          reason: '免费路径弹「派出战士」确认卡');
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
          reason: '确认后 L4 战斗层上屏（卡内战斗，v1 浮层已退役）');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ④ 无能量 → 先弹确认卡；「今天不赶了」不扣钱、状态不变
// ═══════════════════════════════════════════════════════════════════════

void _groupPaidConfirm() {
  group('④ 无能量但余额够：先弹确认卡，「今天不赶了」零副作用', () {
    testWidgets('点卡 → 弹确认卡；点「今天不赶了」→ 不扣钱、不战斗、存档不变',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);

      // 无能量 + 余额 100 ⇒ 付费待办态。
      expect(_cardLabel(tester), contains('偷菜贼来了，现在赶跑它吧'));
      final GuardDayState before = await env.guardState();
      expect(before.status, GuardDayStatus.pending);
      final String today = dayKey(DateTime.now());

      // B2/B3：点的是场景卡「开始守卫」；fresh 环境先过教学浮层。
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _passTutorial(tester);
      await tester.pump();

      expect(find.text('要花费 $kGuardPayCost 阳光，\n进行花园守卫吗？'), findsOneWidget,
          reason: '无能量时点卡必须先弹确认卡');
      expect(find.text('今天不赶了'), findsOneWidget);
      expect(find.byKey(GuardBattleField.fieldKey), findsNothing,
          reason: '确认之前不得开战');

      await tester.tap(find.text('今天不赶了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(GuardBattleField.fieldKey), findsNothing);
      expect(_cardLabel(tester), contains('偷菜贼来了，现在赶跑它吧'),
          reason: '取消后卡必须回到待处理态（状态不变）');

      // 零副作用三连：余额未动、账本无 guard_pay、存档未被改写。
      expect(await env.ledger.balance(), closeTo(100, 1e-9));
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0);
      final GuardDayState after = await env.guardState();
      // B2 唯一允许的差异 = tutorialSeen（点卡即算教过，与是否开战无关）；
      // 其余字段（status / paidSun / winSun / dropKind…）必须一个字都不写。
      expect(after, before.copyWith(tutorialSeen: true),
          reason: '🔴 取消必须零经济副作用（教学标记除外）');
      expect(after.status, GuardDayStatus.pending);
      expect(after.paidSun, 0);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑤ 320×554 + 1.3 字号不溢出（B3 迁移：夹具 GuardPill → GuardSceneCard）
// ═══════════════════════════════════════════════════════════════════════

void _groupOverflow() {
  group('⑤ 320×554 + 1.3 字号：场景卡不溢出', () {
    testWidgets('5 种状态都不溢出，宽度仍 = 屏宽 − 32',
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
          _view(mode),
          onStart: () {},
          width: 320 - 32,
          textScale: 1.3,
        );
        // fighting 态多推一帧（L4 战斗层的 ticker 跑起来后再查溢出）。
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull,
            reason: '${mode.name} 在 320 屏 + 1.3 字号下不得溢出（F127 教训）');
        final Rect rect = tester.getRect(find.byKey(GuardSceneCard.cardKey));
        expect(rect.width, closeTo(288, 0.5),
            reason: '卡宽必须撑满可用宽（320 − 32 = 288），不能被文字顶宽');
      }
    });

    testWidgets('今日页整页 320×554 + 1.3 字号：场景卡上屏且无 RenderFlex 溢出',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env,
          screen: const Size(320, 554), textScale: 1.3);

      expect(find.byKey(GuardSceneCard.cardKey), findsOneWidget);
      final Rect listRect = tester.getRect(find.byType(ListView));
      final Rect cardRect = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      expect(cardRect.width, closeTo(listRect.width, 0.5),
          reason: '🔴 满宽贴边（卡宽 = 屏宽 320，不再 − 32）');
      expect(cardRect.height, closeTo(kGuardSceneCardHeight, 0.5),
          reason: '320 屏下场景卡高度仍恒 108pt');
      expect(tester.takeException(), isNull,
          reason: '320×554 + 1.3 字号下整页不得出现 RenderFlex 溢出');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑧ 无掉落档（18%）：结算卡不得写「券还能省 0 阳光」
// ═══════════════════════════════════════════════════════════════════════

/// 把结算卡**单独**挂在屏幕上（不进战斗 / 不碰服务），只为看它渲染了什么文案。
/// B13.16：可选传 `showPremiumHint` / `stolenSun`（完整版引导行的两个渲染闸门）。
Future<void> _pumpResultCard(
  WidgetTester tester,
  GuardTodayView view,
  AppLocalizations t, {
  bool showPremiumHint = false,
  int stolenSun = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuardResultCard(
          view: view,
          l10n: t,
          // 本用例只看静态文案，永远不点「收下」—— 点它会 pop 掉唯一的路由。
          onCollect: () => throw StateError('本用例不点「收下」'),
          showPremiumHint: showPremiumHint,
          stolenSun: stolenSun,
        ),
      ),
    ),
  );
  await tester.pump();
}

void _groupNoDrop() {
  group('⑧ 无掉落档：结算卡不写「券还能省 0 阳光」', () {
    testWidgets('有券 ⇒ 比较说明在；无掉落档 ⇒ 整行消失，且全卡不见「省…阳光」',
        (WidgetTester tester) async {
      final AppLocalizations t =
          await AppLocalizations.delegate.load(const Locale('zh'));

      /// 卡片上「同时含『省』和『阳光』」的全部文案（旧 bug 的精确判据）。
      List<String> saveLines() => tester
          .widgetList<Text>(find.byType(Text))
          .map((Text w) => w.data ?? '')
          .where((String s) => s.contains('省') && s.contains('阳光'))
          .toList();

      // ── 对照组：今天有券（laborVoucher）⇒ 稀有奖励说明渲染 ────────────
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.laborVoucher),
        t,
      );
      // 🔴 B13.2 玄参裁定：不再算账 —— 有券直接写「恭喜获得稀有奖励！」。
      expect(find.text('恭喜获得稀有奖励！'), findsOneWidget,
          reason: '🔴 有 buff 增益券 ⇒ 稀有奖励文案（旧算账行已退役）');
      expect(saveLines(), isEmpty,
          reason: 'B13.2 起全卡不再出现「省 … 阳光」数字句式');

      // ── 实验组：无掉落档 ⇒ 整行不渲染，不许出现任何数字兜底 ─────────
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.none, winSun: 3),
        t,
      );

      // 该档的语义由「什么都没捡到」承担。
      expect(find.text('这次什么都没捡到，但菜保住了'), findsOneWidget);
      expect(find.textContaining('还捡到'), findsNothing,
          reason: '无掉落档不得写「还捡到 ⋯」');

      // 🔴 真 bug 的判据：不能出现「券还能省 0 阳光」这类数字句式。
      expect(saveLines(), isEmpty,
          reason: '无掉落档不得出现「省 … 阳光」：${saveLines()}');
      expect(find.textContaining('省'), findsNothing,
          reason: 'B13.2 起算账行退役，任何档都不出现「省」字句');
      expect(find.textContaining('花了'), findsNothing,
          reason: '无券档连「花了 5 阳光」也不留半句');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════

/// ⑧b 完整版引导行（B13.16 玄参）：free 档 + 打赢（未被偷）才渲染。
void _groupPremiumHint() {
  group('⑧b 完整版引导行：free + 打赢才渲染（B13.16）', () {
    testWidgets('free 档 + 未被偷 ⇒ 引导行在场（文案逐字）；被偷 ⇒ 退场',
        (WidgetTester tester) async {
      final AppLocalizations t =
          await AppLocalizations.delegate.load(const Locale('zh'));
      const String hint = '开通完整版后，守卫胜利还会掉落高级宝箱，奖励更丰富哦！';

      // ① free 档宿主传入 + 打赢（stolenSun = 0）⇒ 在场。
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.none, winSun: 3),
        t,
        showPremiumHint: true,
      );
      expect(find.byKey(GuardResultCard.premiumHintKey), findsOneWidget,
          reason: 'free 档打赢 ⇒ 完整版引导行在场（B13.16 玄参）');
      expect(find.text(hint), findsOneWidget, reason: '文案逐字（期望独立于实现）');

      // ② 同卡但被偷（stolenSun > 0）⇒ 打了败仗不推销。
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.none, winSun: 0),
        t,
        showPremiumHint: true,
        stolenSun: 5,
      );
      expect(find.byKey(GuardResultCard.premiumHintKey), findsNothing,
          reason: '被偷（败仗）不渲染引导行');

      // ③ premium 档宿主不传 ⇒ 永不渲染（他们自己就能掉高级宝箱）。
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.none, winSun: 3),
        t,
      );
      expect(find.byKey(GuardResultCard.premiumHintKey), findsNothing,
          reason: 'showPremiumHint = false（premium 档）⇒ 永不渲染');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════

void _groupVoucherSaving() {
  group('⑨ 结算卡「券还能省 N」= 真实节省量（F4）', () {
    // 🔴 期望值写字面量：Lv.5 水价 4 ⇒ 免费水省 4（不是面值 5）；
    //    Lv.10 肥价 9 ⇒ 免费肥省 9（不是面值 10）。
    test('免费浇水券 + Lv.5 称号 ⇒ saving 4（不是 5）', () {
      const GuardTodayView view = GuardTodayView(
        mode: GuardPillMode.pendingPaid,
        state: GuardDayState(
          dayKey: '2026-11-09',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeWater,
        ),
        energyAvailable: 0,
        balance: 100,
        perk: PlantPerk(waterDiscount: 1),
      );
      expect(view.voucherSaving, 4);
    });

    test('免费施肥券 + Lv.10 称号 ⇒ saving 9（不是 10）', () {
      const GuardTodayView view = GuardTodayView(
        mode: GuardPillMode.pendingPaid,
        state: GuardDayState(
          dayKey: '2026-11-09',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeFertilize,
        ),
        energyAvailable: 0,
        balance: 100,
        perk: PlantPerk(fertilizeDiscount: 1),
      );
      expect(view.voucherSaving, 9);
    });

    // 🔴 G2：非免费券报「当日最大可省」（领取时孩子还没决定浇几盆），
    //    绝不能按单盆口径报 1。期望值写字面量，不从配额常量反推。
    GuardTodayView paidView(GuardDropKind kind) => GuardTodayView(
          mode: GuardPillMode.pendingPaid,
          state: GuardDayState(
            dayKey: '2026-11-09',
            status: GuardDayStatus.pending,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 2,
            dropKind: kind,
          ),
          energyAvailable: 0,
          balance: 100,
          perk: PlantPerk.none,
        );

    test('浇水券（无称号）⇒ saving 6（当日封顶，不是单盆 1）', () {
      expect(paidView(GuardDropKind.waterVoucher).voucherSaving, 6);
    });

    test('劳动券（无称号）⇒ saving 4（当日封顶，不是单盆 1）', () {
      expect(paidView(GuardDropKind.laborVoucher).voucherSaving, 4);
    });

    test('施肥券（无称号）⇒ saving 24（当日 12 次 × 2 ☀）', () {
      // G2 裁定：voucherSaving 从 guardVoucherQuotaOf(fertilize)=12 派生 potCount，
      // 故结算卡报「当日最大可省」24，而不是单次面值 2。
      expect(paidView(GuardDropKind.fertilizeVoucher).voucherSaving, 24);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑩ 端到端：战完 → 宝箱 → 结算卡（T03 演出链接线）
// ═══════════════════════════════════════════════════════════════════════

/// 结算卡阳光奖励卡上的到账额（`+N` 里的 N；找不到即 fail，不静默兜底 0）。
int _cardSunAmount(WidgetTester tester) {
  final Iterable<Text> texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(GuardResultCard.sunRewardKey),
      matching: find.byType(Text),
    ),
  );
  for (final Text text in texts) {
    final String data = text.data ?? '';
    if (data.startsWith('+')) return int.parse(data.substring(1));
  }
  fail('阳光奖励卡上找不到「+N」文案 —— 结算卡结构被改坏了');
}

void _groupChestFlow() {
  group('⑩ 端到端：战完 → 宝箱（不可跳过）→ 结算卡 → 收下', () {
    testWidgets('一枪不发推完 30s 窗口：宝箱先上屏、点开 5s 后弹结算卡，'
        '阳光卡面 == 账本 guard_win（普通档不翻倍），收下后不再演宝箱',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env); // 有能量 ⇒ 免费路径（不弹付费确认卡的「阳光不足」分支）
      await _pumpToday(tester, env);
      final String today = dayKey(DateTime.now());

      // ── 进战斗 ────────────────────────────────────────────────────────
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await _passTutorial(tester);
      await tester.tap(find.text('确定')); // B13.7：免费路径也弹确认卡
      await _settleRoute(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget);

      // ── 一枪不发推完整窗（62 × 500ms，与纯 sim 同源；不 pumpAndSettle）──
      for (int i = 0; i < 62; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      // 横幅 ~900ms 后交回页面（落账 → 宝箱演出）。
      await tester.pump(const Duration(milliseconds: 1000));

      // ── 宝箱必须先上屏，且结算卡不许抢跑（两者都不可跳过）──────────────
      await _pumpUntil(tester, find.byKey(GuardChestStage.stageKey));
      await tester.pump(const Duration(milliseconds: 260)); // 路由过渡 200ms
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget,
          reason: '宝箱应以静态首帧停在菜地里等孩子点');
      expect(find.byKey(GuardResultCard.cardKey), findsNothing,
          reason: '🔴 宝箱没开完，结算卡不许出现（顺序：宝箱 → 结算卡）');

      // ── 点**全屏热区**开箱 → 5s（30 帧 × 166.7ms）────────────────────
      await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
      await tester.pump(); // 起播一帧：把 FrameSequencePlayer 挂上
      expect(find.byKey(GuardChestStage.chestKey), findsNothing,
          reason: '点击后静态宝箱让位给开箱动画');
      await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
      await tester.pump(const Duration(milliseconds: 50)); // completed 下一帧派发
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);
      expect(find.byKey(GuardChestStage.stageKey), findsNothing,
          reason: '30 帧播完 ⇒ 宝箱 overlay 必须收场，不能盖住结算卡');

      // ── 卡面阳光 == 账本 guard_win（同一口径 guardGrantWinSunOf）────────
      final int cardSun = _cardSunAmount(tester);
      expect(cardSun, greaterThan(0),
          reason: '有贼日必得阳光 ≥ 1（卡面不许出现 +0）');

      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final double winNet =
          await env.ledger.netByRefTypeOnDay(kGuardWinRefType, today);
      expect(winNet, cardSun.toDouble(),
          reason: '🔴 卡面 +$cardSun 恒 == 账本 guard_win $winNet'
              '（普通档 winSun 不翻倍；高级档也走同一到账口径）');

      // ── 已领取态：不再演宝箱，场景卡回到「已守住」──────────────────────
      expect(find.byKey(GuardChestStage.stageKey), findsNothing,
          reason: '🔴 已领取 ⇒ 不得再演宝箱（重进今日页也不演）');
      expect(_cardLabel(tester), contains('今天的菜守住了'));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _groupAbsent();
  _groupModes();
  _groupFreePath();
  _groupPaidConfirm();
  _groupOverflow();
  _groupNoDrop();
  _groupPremiumHint();
  _groupVoucherSaving();
  _groupChestFlow();
}
