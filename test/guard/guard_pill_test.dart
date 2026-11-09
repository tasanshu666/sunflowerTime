/// 第三批 · 今日页守卫胶囊 / 战斗 / 结算的**行为与布局护栏**。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §4 / §8.1 / §8.2 / §8.3。
///
/// ## 覆盖的 7 条（逐条对应交付要求）
/// | # | 断言 | 用例 |
/// |---|---|---|
/// | 1 | `absent` 零占位（第一张卡顶 == 列表顶 + 卡片内边距，无 44+10 空隙） | ① |
/// | 2 | 5 种状态的文案与可点性 | ② |
/// | 3 | 有能量时文案是「免费」且点击**不弹确认卡** | ③ |
/// | 4 | 无能量时点击**先弹确认卡**，「今天不赶了」→ 不扣钱、状态不变 | ④ |
/// | 5 | 320×554 + 1.3 字号下胶囊不溢出（宽度 = 屏宽 − 32 = 288） | ⑤ |
/// | 6 | 战斗 10 秒后自动进结算；点「跳过」立即进结算 | ⑥⑦ |
/// | 7 | `claim` 只落一次账（跳过 / 看完两条路径各只有 1 条 `guard_win`） | ⑥⑦ |
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
library guard_pill_test;

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
import 'package:sunflower_time/presentation/child/widgets/guard_battle_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_pill.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';

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
  await FocusLocalRepository(env.database, account: env.account).saveSession(
    FocusSession(
      id: id,
      start: now.subtract(const Duration(minutes: 20)),
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

/// 让**路由过渡**跑完（战斗浮层 `pop` 与结算卡 `push` 会在同一帧存在：
/// `showGeneralDialog` 的 pop future 在 pop 当帧即完成，不等退场动画 ——
/// 故「结算卡已出现」不等于「战斗浮层已消失」）。
Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 今日页第一张状态卡**标签**顶边相对列表顶边的偏移（渲染盒实测）。
///
/// 绝对值的 3pt 来自 `_StatCard` 的 1px 描边 + 行盒上行留白 —— 本文件不依赖这个
/// 绝对值，而是比较「有胶囊 / 无胶囊」两种布局的**差值**（必须恰好 54pt）。
double _firstCardOffset(WidgetTester tester) {
  final Rect listRect = tester.getRect(find.byType(ListView));
  final Rect labelRect = tester.getRect(find.text('今日获取阳光'));
  return labelRect.top - listRect.top;
}

/// 直接构造一份胶囊快照（用于纯 widget 用例，不碰任何服务）。
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

/// 把 [GuardPill] 单独挂在 288pt 宽的槽位里（= 320 屏 − 左右 16）。
Future<void> _pumpPill(
  WidgetTester tester,
  GuardTodayView view, {
  VoidCallback? onTap,
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
            child: GuardPill(view: view, onTap: onTap),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

// ═══════════════════════════════════════════════════════════════════════
// ① absent 零占位
// ═══════════════════════════════════════════════════════════════════════

void _groupAbsent() {
  group('① absent 零占位', () {
    testWidgets('全园无存活株 ⇒ 不渲染胶囊；种上植物后胶囊出现，第一张卡**恰好**下移 54pt',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv(); // 先刻意不种植物
      final ProviderContainer container = await _pumpToday(tester, env);

      // ── 前：absent ────────────────────────────────────────────────
      expect(find.byKey(GuardPill.pillKey), findsNothing,
          reason: 'absent 必须**完全不渲染**（不是透明 / 零宽）');
      final double offsetWithoutPill = _firstCardOffset(tester);

      // ── 后：种一株（= 有存活株 ⇒ resolve 生成小偷），触发一次刷新 ──
      await _seedPlant(env);
      container.read(economyRevisionProvider.notifier).state++;
      await _pumpUntil(tester, find.byKey(GuardPill.pillKey));
      await _settleRoute(tester);

      expect(find.byKey(GuardPill.pillKey), findsOneWidget,
          reason: '有存活株时 resolve() 必然生成小偷 ⇒ 胶囊必须渲染');
      final double offsetWithPill = _firstCardOffset(tester);

      // 🔴 零占位的判据：偏移量的**差值恰好等于胶囊占位高度**，
      //    也就是说 absent 时没有留下任何空档（插空 `SizedBox` 会让差值 < 54）。
      expect(offsetWithPill - offsetWithoutPill,
          closeTo(kGuardPillHeight + kGuardPillGap, 0.5),
          reason: '胶囊占位必须恰好 = kGuardPillHeight(44) + kGuardPillGap(10)');
    });

    testWidgets('胶囊矩形：紧贴列表顶、宽度 = 屏宽 − 32',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);

      final Rect listRect = tester.getRect(find.byType(ListView));
      final Rect pillRect = tester.getRect(find.byKey(GuardPill.pillKey));
      expect(pillRect.top, closeTo(listRect.top, 0.5));
      expect(pillRect.left, closeTo(listRect.left + 16, 0.5));
      expect(pillRect.width, closeTo(listRect.width - 32, 0.5));
      expect(pillRect.height, greaterThanOrEqualTo(44.0 - 0.5),
          reason: '胶囊不得低于 44pt 触控下限');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ② 五种状态的文案与可点性
// ═══════════════════════════════════════════════════════════════════════

void _groupModes() {
  group('② 五种状态的文案与可点性', () {
    /// 逐态：文案、是否可点（点击回调是否被触发）、尾标。
    final Map<GuardPillMode, String> labels = <GuardPillMode, String>{
      GuardPillMode.pendingFree: '用专注能量赶跑它（免费）',
      GuardPillMode.pendingPaid: '偷菜贼来了，现在赶跑它吧',
      GuardPillMode.freeRide: '阿葵自己顶班，今天不用管',
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
        await _pumpPill(tester, _view(mode), onTap: () => taps++);

        expect(find.text(entry.value), findsOneWidget);
        await tester.tap(find.byKey(GuardPill.pillKey));
        await tester.pump();

        if (tappable) {
          expect(taps, 1, reason: '${mode.name} 必须可点');
        } else {
          expect(taps, 0, reason: '${mode.name} 必须不可点');
        }
      });
    }

    testWidgets('pendingPaid 尾标显示 −5 ☀（数字来自 kGuardPayCost）',
        (WidgetTester tester) async {
      await _pumpPill(tester, _view(GuardPillMode.pendingPaid),
          onTap: () {});
      expect(find.byKey(GuardPill.trailingKey), findsOneWidget);
      expect(find.text('−$kGuardPayCost ☀'), findsOneWidget);
    });

    testWidgets('pendingFree 没有尾标（文案已说明免费，不重复报 0 ☀）',
        (WidgetTester tester) async {
      await _pumpPill(tester, _view(GuardPillMode.pendingFree),
          onTap: () {});
      expect(find.byKey(GuardPill.trailingKey), findsNothing);
    });

    test('guardPillModeOf：resolve 的三种成本模式映射到正确的胶囊态', () {
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
// ③ 有能量 → 免费文案 + 点击不弹确认卡
// ═══════════════════════════════════════════════════════════════════════

void _groupFreePath() {
  group('③ 有能量：文案是「免费」且点击不弹确认卡', () {
    testWidgets('有 1 次有效专注 ⇒ 胶囊写「免费」，点击直接进战斗',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _pumpToday(tester, env);

      expect(find.text('用专注能量赶跑它（免费）'), findsOneWidget);
      expect(find.byKey(GuardPill.trailingKey), findsNothing,
          reason: '免费路径不该显示 −5 ☀');

      await tester.tap(find.byKey(GuardPill.pillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // 🔴 关键断言：免费路径**不得**弹确认卡。
      expect(find.text('要花 $kGuardPayCost 阳光请阿葵出手吗？'), findsNothing,
          reason: '有能量时点胶囊必须直接开战，不弹确认卡');
      expect(find.byKey(GuardBattleOverlay.overlayKey), findsOneWidget,
          reason: '点击后应直接上战斗界面');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ④ 无能量 → 先弹确认卡；「今天不赶了」不扣钱、状态不变
// ═══════════════════════════════════════════════════════════════════════

void _groupPaidConfirm() {
  group('④ 无能量但余额够：先弹确认卡，「今天不赶了」零副作用', () {
    testWidgets('点胶囊 → 弹确认卡；点「今天不赶了」→ 不扣钱、不战斗、存档不变',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);

      // 无能量 + 余额 100 ⇒ 付费待办态。
      expect(find.text('偷菜贼来了，现在赶跑它吧'), findsOneWidget);
      final GuardDayState before = await env.guardState();
      expect(before.status, GuardDayStatus.pending);
      final String today = dayKey(DateTime.now());

      await tester.tap(find.byKey(GuardPill.pillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('要花 $kGuardPayCost 阳光请阿葵出手吗？'), findsOneWidget,
          reason: '无能量时点胶囊必须先弹确认卡');
      expect(find.text('今天不赶了'), findsOneWidget);
      expect(find.byKey(GuardBattleOverlay.overlayKey), findsNothing,
          reason: '确认之前不得开战');

      await tester.tap(find.text('今天不赶了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(GuardBattleOverlay.overlayKey), findsNothing);
      expect(find.text('偷菜贼来了，现在赶跑它吧'), findsOneWidget,
          reason: '取消后胶囊必须回到待处理态（状态不变）');

      // 零副作用三连：余额未动、账本无 guard_pay、存档未被改写。
      expect(await env.ledger.balance(), closeTo(100, 1e-9));
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0);
      final GuardDayState after = await env.guardState();
      expect(after, before, reason: '🔴 取消必须一个字都不写');
      expect(after.status, GuardDayStatus.pending);
      expect(after.paidSun, 0);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑤ 320×554 + 1.3 字号不溢出
// ═══════════════════════════════════════════════════════════════════════

void _groupOverflow() {
  group('⑤ 320×554 + 1.3 字号：胶囊不溢出', () {
    testWidgets('最长的两种文案（免费 / 阿葵顶班）都不溢出，宽度仍 = 屏宽 − 32',
        (WidgetTester tester) async {
      for (final GuardPillMode mode in <GuardPillMode>[
        GuardPillMode.pendingFree,
        GuardPillMode.pendingPaid,
        GuardPillMode.freeRide,
        GuardPillMode.fighting,
        GuardPillMode.claimed,
      ]) {
        await _pumpPill(
          tester,
          _view(mode),
          onTap: () {},
          width: 320 - 32,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull,
            reason: '${mode.name} 在 320 屏 + 1.3 字号下不得溢出（F127 教训）');
        final Rect rect = tester.getRect(find.byKey(GuardPill.pillKey));
        expect(rect.width, closeTo(288, 0.5),
            reason: '胶囊宽度必须撑满可用宽（320 − 32 = 288），不能被文字顶宽');
      }
    });

    testWidgets('今日页整页 320×554 + 1.3 字号：胶囊上屏且无 RenderFlex 溢出',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env,
          screen: const Size(320, 554), textScale: 1.3);

      expect(find.byKey(GuardPill.pillKey), findsOneWidget);
      final Rect listRect = tester.getRect(find.byType(ListView));
      final Rect pillRect = tester.getRect(find.byKey(GuardPill.pillKey));
      expect(pillRect.width, closeTo(listRect.width - 32, 0.5));
      expect(tester.takeException(), isNull,
          reason: '320×554 + 1.3 字号下整页不得出现 RenderFlex 溢出');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑥⑦ 战斗 → 结算（看完 / 跳过）+ claim 只落一次账
// ═══════════════════════════════════════════════════════════════════════

void _groupBattleAndClaim() {
  group('⑥⑦ 战斗 → 结算卡 → 收下（claim 只落一次账）', () {
    testWidgets('跳过：600ms 后才有「跳过」按钮，点了立即进结算；收下只发一次奖',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env); // 有能量 ⇒ 免费路径，不弹确认卡
      await _pumpToday(tester, env);

      await tester.tap(find.byKey(GuardPill.pillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(GuardBattleOverlay.overlayKey), findsOneWidget);
      // 防误触：一进来**没有**跳过按钮。
      expect(find.byKey(GuardBattleOverlay.skipButtonKey), findsNothing,
          reason: '$kGuardBattleSkipDelayMs ms 之前不得出现「跳过」');

      // 越过 kGuardBattleSkipDelayMs → 按钮出现。
      await tester.pump(const Duration(milliseconds: kGuardBattleSkipDelayMs));
      expect(find.byKey(GuardBattleOverlay.skipButtonKey), findsOneWidget);

      // 跳过 ⇒ 立刻进结算（不必等满 10 秒）。
      await tester.tap(find.byKey(GuardBattleOverlay.skipButtonKey));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      expect(find.byKey(GuardBattleOverlay.overlayKey), findsNothing);
      // 结算卡内容：标题 + 必得阳光 + 比较说明（R2 缓解，必须有）。
      expect(find.textContaining('赶走了'), findsOneWidget);
      final int winSun = (await env.guardState()).winSun;
      expect(find.text('拿回 $winSun 阳光'), findsOneWidget,
          reason: '必得阳光行必须是「拿回 N 阳光」（与存档里的 winSun 一致）');
      expect(find.textContaining('券还能省'), findsOneWidget,
          reason: '🔴 比较说明是 R2 缓解，必须有');

      final String today = dayKey(DateTime.now());
      // 战斗阶段**不**发奖：跳到结算卡时账本还没有 guard_win。
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0,
          reason: '🔴 奖励只在「收下」时发放，跳过动画本身不发奖');

      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 🔴 claim 只落一次账。
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1,
          reason: '必得阳光必须恰好入账一次');
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0,
          reason: '有能量路径不得扣阳光');
      final GuardDayState state = await env.guardState();
      expect(state.status, GuardDayStatus.claimed);
      expect(state.energyUsed, 1);

      // 已领取 ⇒ 胶囊切到「今天的菜守住了」，且不可再点。
      expect(find.text('今天的菜守住了'), findsOneWidget);
    });

    testWidgets('看完 10 秒：自动进结算；收下同样只发一次奖（与跳过的结果逐位相同）',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _pumpToday(tester, env);

      await tester.tap(find.byKey(GuardPill.pillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(GuardBattleOverlay.overlayKey), findsOneWidget);

      // 一次推进整段战斗时长：控制器到 1.0 ⇒ completed ⇒ 自动 pop ⇒ 进结算卡。
      await tester.pump(const Duration(milliseconds: kGuardBattleMs + 400));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      expect(find.byKey(GuardBattleOverlay.overlayKey), findsNothing,
          reason: '播完必须自动进结算（无需点任何按钮）');

      final String today = dayKey(DateTime.now());
      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      for (int i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1,
          reason: '看完路径同样恰好入账一次');
      final GuardDayState state = await env.guardState();
      expect(state.status, GuardDayStatus.claimed);
    });

    testWidgets('付费路径：确认后扣 5 ☀ 一次、发奖一次，且比较说明写「花了 5 阳光」',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);

      await tester.tap(find.byKey(GuardPill.pillKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('确定')); // 确认卡的主按钮（shared_ok）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(GuardBattleOverlay.overlayKey), findsOneWidget);

      await tester.pump(const Duration(milliseconds: kGuardBattleMs + 400));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      expect(find.textContaining('花了 $kGuardPayCost 阳光'), findsOneWidget,
          reason: '付费路径的比较说明必须点明「花了 5 阳光」');

      final String today = dayKey(DateTime.now());
      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      for (int i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 1,
          reason: '付费必须恰好扣一次');
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1,
          reason: '必得阳光必须恰好发一次');
      final GuardDayState state = await env.guardState();
      expect(state.paidSun, 5);
      expect(state.status, GuardDayStatus.claimed);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ⑧ 无掉落档（18%）：结算卡不得写「券还能省 0 阳光」
// ═══════════════════════════════════════════════════════════════════════

/// 把结算卡**单独**挂在屏幕上（不进战斗 / 不碰服务），只为看它渲染了什么文案。
Future<void> _pumpResultCard(
  WidgetTester tester,
  GuardTodayView view,
  AppLocalizations t,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuardResultCard(
          view: view,
          l10n: t,
          // 本用例只看静态文案，永远不点「收下」—— 点它会 pop 掉唯一的路由。
          onCollect: () => throw StateError('本用例不点「收下」'),
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

      // ── 对照组：今天有券（laborVoucher）⇒ 比较说明必须渲染 ──────────
      await _pumpResultCard(
        tester,
        _view(GuardPillMode.pendingPaid, drop: GuardDropKind.laborVoucher),
        t,
      );
      expect(find.textContaining('券还能省'), findsOneWidget,
          reason: '🔴 有券时必须给比较说明（R2 缓解）');
      expect(saveLines(), hasLength(1));

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
      expect(find.textContaining('券还能省'), findsNothing);
      expect(find.textContaining('花了'), findsNothing,
          reason: '无券档整行不渲染（连「花了 5 阳光」也不留半句）');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _groupAbsent();
  _groupModes();
  _groupFreePath();
  _groupPaidConfirm();
  _groupOverflow();
  _groupBattleAndClaim();
  _groupNoDrop();
  _groupVoucherSaving();
}
