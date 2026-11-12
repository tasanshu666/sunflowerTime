/// 守卫战 v2 · B5a **调试「强制剧本」按钮组 → 真实战斗**的行为护栏。
///
/// 真源：设计文档 §7-B5 调试行 + `guard_debug_script.dart`（覆盖注入点）。
///
/// ## 覆盖
/// | # | 断言 | 层级 |
/// |---|---|---|
/// | ① | 点「强制 5 只怪」⇒ 覆盖写入 provider（5 只）→ 今日页开战 → 25s 时恰 5 只怪在车道 | 面板→页面 |
/// | ② | 点「强制三怪混编」⇒ 三只怪各挂自己的帧序列目录（m1/m2/m3 互不串线） | 面板→页面 |
/// | ③ | 点「强制高偷窃战局」⇒ 撤退后结算卡被偷行渲染「偷走 3 阳光」且账本实扣 −3（≤ 封顶 3） | 面板→页面→账本 |
/// | ④ | 点「恢复随机剧本」⇒ 覆盖清空（provider 回 null） | 面板 |
/// | ⑤ | `buildGuardBattleScriptForDebug` 纯函数：怪数/出场表/偷取轮转/混编/高偷窃 逐位字面量 | 单元 |
/// | ⑥ | 🔴 E2 回归：**IndexedStack 保活**下战局进行中改覆盖 ⇒ 战斗层立即重开
///     （「强制 3」开局、战中「强制 5」⇒ 倒计时回满 + 第 5 只怪上屏；战中
///     「恢复随机」⇒ 倒计时回满 + 回真实派生）—— 花园页面板真实点击链路 | 面板→保活页→战斗层 |
///
/// ## 覆盖注入链（与生产零感知口径互证）
/// 面板按钮 → `debugGuardBattleScriptOverrideProvider` → `ChildTodayPage` →
/// `GuardSceneCard` → `GuardBattleField`（`override ?? deriveGuardBattleScript`）。
/// 测试用**同一个** `ProviderContainer` 承载面板与今日页 —— 正是生产注入链本身。
///
/// 🔴 全文件有界 `pump`（阳光气泡无限动画 + L4 ticker 常驻，绝不
/// `pumpAndSettle`）；窗口推进用**小步长分段**（B4 教训：单大步会让
/// (30s, 31s] 视界内的到门事件先于窗口判定被处理）。
library guard_debug_script_test;

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
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具（真库 + 真 prefs + 真守卫链路；面板与今日页共用同一 container）
// ═══════════════════════════════════════════════════════════════════════

class _Env {
  _Env({required this.sp, required this.database, required this.account});

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;

  String get childId => account.childId;

  SunlightLocalRepository get ledger =>
      SunlightLocalRepository(database, account: account);

  GuardStatePrefsStore get guardStore => GuardStatePrefsStore(sp);

  Future<int> ledgerRowsOnDay(String refType, String dayKeyValue) =>
      ledger.countByRefTypeAndRefIdOnDay(refType, kGuardRefId, dayKeyValue);
}

Future<_Env> _makeEnv(String childId) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await ChildProfileLocalRepository(database)
      .create('剧本调试娃', AgeTier.high, id: childId);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  return _Env(sp: sp, database: database, account: account);
}

/// 20 分钟有效专注 = 1 点能量（提高走免费路径的概率；付费路径由确认卡兜住）。
Future<void> _seedValidFocus(_Env env) async {
  final DateTime now = DateTime.now();
  // 🔴 午夜安全：sessionsOfDay 按 start 归日（详见 guard_battle_field_test）。
  final DateTime todayStart = DateTime(now.year, now.month, now.day);
  final DateTime rawStart = now.subtract(const Duration(minutes: 20));
  final DateTime start = rawStart.isBefore(todayStart)
      ? todayStart.add(const Duration(seconds: 1))
      : rawStart;
  await FocusLocalRepository(env.database, account: env.account).saveSession(
    FocusSession(
      id: 'f_1',
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

/// 给足余额（③ 需要余额 > 封顶，排除「余额钳制」干扰）。
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

ProviderContainer _container(_Env env) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(env.sp),
      appDatabaseProvider.overrideWithValue(env.database),
      accountServiceProvider.overrideWithValue(env.account),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 调试面板宿主（与既有 guard_debug_panel_test 同款直挂 sheet；不经路由动画）。
Widget _panelHost(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: BloomDebugSheet(maxHeight: 640)),
      ),
    );

/// 今日页宿主。
Widget _todayHost(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    );

Future<bool> _pumpUntilReady(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 240,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return finder.evaluate().isNotEmpty;
}

/// 打开面板（等 _loaded）并滚到守卫区块末尾，让新按钮进懒构建窗口。
Future<void> _openPanelAndScrollToScript(WidgetTester tester,
    ProviderContainer container) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_panelHost(container));
  // 就绪信号 = 加载圈**消失**（🔴 不能等文本：守卫分组在列表最末尾，ListView
  // 懒构建下必须先滚动才进构建窗口 —— guard_debug_panel_test 同款纪律；也
  // 不能用「催熟到成株」：本文件不种植物 ⇒ 面板走空花园分支，没那个按钮）。
  // 注意语义方向：加载圈开局就在树上，必须等它**消失**而不是出现。
  bool loaded = false;
  for (int i = 0; i < 240; i++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      loaded = true;
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(loaded, isTrue, reason: '面板应完成 _refresh（加载圈消失）');

  // scrollUntilVisible 自身会驱动滚动把懒构建窗口推到守卫区块。
  await tester.scrollUntilVisible(
    find.text('强制 3 只怪'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// 面板动作收尾（_run 的 _refresh + onChanged + bump 全异步 ⇒ 有界推进）。
Future<void> _settleAction(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 切到今日页（同一 container）并等首屏刷新完成。
Future<void> _openTodayPage(WidgetTester tester,
    ProviderContainer container) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_todayHost(container));
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 越过教学浮层。
///
/// 🔴 B7：教学改成**永久一次**（设备级 prefs），同一 env 内第二次开战不会再弹 ⇒
/// 这里必须「弹了才点」（有界探测 ~0.5s，绝不为等一个不会来的浮层白推 4s 战局）。
Future<void> _passTutorial(WidgetTester tester) async {
  final bool shown =
      await _pumpUntilReady(tester, find.byKey(kGuardTutorialOkKey), maxFrames: 30);
  if (!shown) return;
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(kGuardTutorialOkKey));
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 进战斗：点开始 → 教学浮层 → （若今天掉券则付费确认卡）→ L4 上屏。
Future<void> _startBattle(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
  await _passTutorial(tester);
  // forceThiefForDebug 不指定 drop ⇒ 掉落档随今日 roll：掉券的 roll 会走
  // 付费确认卡（pendingPaid）。两条路径都要能开战 ⇒ 有确认卡就点「确定」。
  final Finder confirm = find.text('确定');
  if (confirm.evaluate().isNotEmpty) {
    await tester.tap(confirm);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  // handler microtask 收尾 + L4 挂载帧（ticker 自本帧起，sim 时间 0）。
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
      reason: '开战后 L4 战斗层必须在卡内上屏');
}

/// 读某只怪当前帧序列的**首帧路径**（B9/D2：用它区分 m1/m2/m3 三个目录）。
String _monsterFirstFrame(WidgetTester tester, int index) {
  return tester
      .widget<FrameSequencePlayer>(
        find.descendant(
          of: find.byKey(GuardBattleField.monsterKey(index)),
          matching: find.byType(FrameSequencePlayer),
        ),
      )
      .frames
      .first;
}

/// B5b：m1 素材在位 ⇒ 怪物位渲染循环帧序列（不是占位 ColoredBox）。
bool monsterM1IsSequence(WidgetTester tester, int index) {
  return find
      .descendant(
        of: find.byKey(GuardBattleField.monsterKey(index)),
        matching: find.byType(FrameSequencePlayer),
      )
      .evaluate()
      .isNotEmpty;
}

/// 读倒计时条当前值（0..1；重开战局 ⇒ 时间轴归零 ⇒ 回满 = 确定性观测点）。
double _countdownValue(WidgetTester tester) {
  return tester
      .widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(GuardSceneCard.countdownKey),
          matching: find.byType(LinearProgressIndicator),
        ),
      )
      .value!;
}

/// 真实面板入口页（与花园页同款接线：真实 [BloomDebugEntry] →
/// 真实 [showBloomDebugPanel]；E2 复现「花园页面板真实点击链路」）。
class _PanelEntryPage extends StatelessWidget {
  const _PanelEntryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: BloomDebugEntry(
          onTap: () => showBloomDebugPanel(context),
        ),
      ),
    );
  }
}

/// 打开面板（真实入口链路）并滚到「强制 3 只怪」。
Future<void> _openPanelViaEntry(WidgetTester tester) async {
  await tester.tap(find.byType(BloomDebugEntry));
  // 底部弹层 route 进出动画（有界推进，绝不 pumpAndSettle）。
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // 就绪信号 = 加载圈消失（同 _openPanelAndScrollToScript 的语义纪律）。
  bool loaded = false;
  for (int i = 0; i < 240; i++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      loaded = true;
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(loaded, isTrue, reason: '面板应完成 _refresh（加载圈消失）');
  await tester.scrollUntilVisible(
    find.text('强制 3 只怪'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// 点弹层遮罩关闭面板（route 退出动画有界推进）。
Future<void> _closePanel(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(BloomDebugSheet), findsNothing,
      reason: '面板应已随遮罩点击关闭');
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 强制 5 只怪 ⇒ 恰 5 只在车道 ─────────────────────────────────────
  testWidgets('① 点「强制 5 只怪」⇒ 覆盖写入、开战后 25s 时恰 5 只怪在车道',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('c1');
    await _seedValidFocus(env);
    final ProviderContainer container = _container(env);

    await _openPanelAndScrollToScript(tester, container);
    await tester.tap(find.byKey(const ValueKey<String>(kDebugGuardScriptKeyCount5)));
    await _settleAction(tester);

    // 覆盖已写入 provider（注入链第一环）。
    final GuardBattleScript? override =
        container.read(debugGuardBattleScriptOverrideProvider);
    expect(override, isNotNull, reason: '点按钮后覆盖必须写入 provider');
    expect(override!.monsters.length, 5, reason: '🔴 覆盖剧本必须是 5 只怪');

    // 切今日页（同 container = 生产注入链）开战，再 500ms 步进推进到
    // 「第 5 只怪（24s 出场）上屏」即停 —— 🔴 不能推到 25s 整数点：挂载帧 +
    // 教学收尾有 <1s 的 sim 漂移，若越过首怪到门时刻（m1 全场 25.385s），
    // 第 0 只怪已 fled 不再渲染（实测踩过）。24~25.3s 窗口内 5 只必然同屏。
    await _openTodayPage(tester, container);
    await _startBattle(tester);
    bool fifthSpawned = false;
    for (int i = 0; i < 60; i++) {
      if (find.byKey(GuardBattleField.monsterKey(4)).evaluate().isNotEmpty) {
        fifthSpawned = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(fifthSpawned, isTrue,
        reason: '推到窗口内（24s 出场表末项）后第 5 只怪必须上屏');
    for (int i = 0; i < 5; i++) {
      expect(find.byKey(GuardBattleField.monsterKey(i)), findsOneWidget,
          reason: '强制 5 只怪 ⇒ 第 $i 只（出场 ${i * 6}s）必须在车道上');
    }
    expect(find.byKey(GuardBattleField.monsterKey(5)), findsNothing,
        reason: '🔴 覆盖剧本只有 5 只 ⇒ 第 6 只 Key 绝不渲染');
    expect(tester.takeException(), isNull);
  });

  // ── ② 强制三怪混编 ⇒ 三色互异 ────────────────────────────────────────
  testWidgets('② 点「强制三怪混编」⇒ m1 棕 / m2 绿 / m3 灰紫三色在屏（字面量）',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('c1');
    await _seedValidFocus(env);
    final ProviderContainer container = _container(env);

    await _openPanelAndScrollToScript(tester, container);
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyMixed)));
    await _settleAction(tester);

    final GuardBattleScript? override =
        container.read(debugGuardBattleScriptOverrideProvider);
    expect(
      [for (final m in override!.monsters) m.kind],
      <GuardBattleMonsterKind>[
        GuardBattleMonsterKind.m1,
        GuardBattleMonsterKind.m2,
        GuardBattleMonsterKind.m3,
      ],
      reason: '🔴 混编覆盖必须 m1/m2/m3 各一（kind 通道强相关 ⇒ 只能显式覆盖）',
    );

    await _openTodayPage(tester, container);
    await _startBattle(tester);
    // 推 13s：三只全部已出场（0/6/12s）且都没到门（最快 m3 也要 ~19.4s）。
    for (int i = 0; i < 13; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // 🔴 B9/D2：三种怪**都有真实 7 帧序列**（占位色只留兜底）⇒ 判据从「占位色
    // 两两互异」升级为「帧序列目录两两互异」：混编阵容里三只怪必须各挂各的目录。
    expect(monsterM1IsSequence(tester, 0), isTrue,
        reason: '混编第 0 只 = m1 ⇒ 帧序列');
    expect(monsterM1IsSequence(tester, 1), isTrue,
        reason: '混编第 1 只 = m2 ⇒ 帧序列（B9/D2 接入）');
    expect(monsterM1IsSequence(tester, 2), isTrue,
        reason: '混编第 2 只 = m3 ⇒ 帧序列（B9/D2 接入）');
    final String f0 = _monsterFirstFrame(tester, 0);
    final String f1 = _monsterFirstFrame(tester, 1);
    final String f2 = _monsterFirstFrame(tester, 2);
    expect(f0, 'assets/guard/monster_m1/frame001.webp', reason: '🟤 m1 目录');
    expect(f1, 'assets/guard/monster_m2/frame001.webp',
        reason: '🟢 m2（食叶虫）目录');
    expect(f2, 'assets/guard/monster_m3/frame001.webp',
        reason: '🟣 m3（贪婪鼬）目录');
    expect(f0, isNot(f1));
    expect(f1, isNot(f2));
    expect(f0, isNot(f2));
  });

  // ── ③ 强制高偷窃 ⇒ 被偷行渲染、账本 ≤ 封顶 ────────────────────────────
  testWidgets('③ 点「强制高偷窃战局」⇒ 撤退后「偷走 3 阳光」、账本实扣 −3',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('c1');
    await _seedValidFocus(env);
    await _seedBalance(env, 10); // 余额充足 ⇒ 排除余额钳制干扰
    final ProviderContainer container = _container(env);

    await _openPanelAndScrollToScript(tester, container);
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyTheft)));
    await _settleAction(tester);

    await _openTodayPage(tester, container);
    await _startBattle(tester);
    // 一枪不发，62 × 500ms 推完窗口（B4 教训：分段推进与纯 sim 同源）。
    // 高偷窃剧本 = 全 m1 + steal 3 ⇒ 首怪 25.4s 必到门口 ⇒ 被偷 3（封顶）。
    for (int i = 0; i < 62; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await _pumpUntilReady(tester, find.byKey(GuardBattleField.bannerKey));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 🔴 T03 起结算卡前必过**宝箱演出**（宝箱与结算卡都不可跳过）：
    //    等宝箱上屏 → 点全屏热区 → 定长 5s 开箱 → 结算卡。
    await _pumpUntilReady(tester, find.byKey(GuardChestStage.stageKey),
        maxFrames: 200);
    await tester.pump(const Duration(milliseconds: 260)); // 路由过渡 200ms
    await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
    await tester.pump(const Duration(milliseconds: 50));
    await _pumpUntilReady(tester, find.byKey(GuardResultCard.cardKey),
        maxFrames: 200);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 🔴 被偷行渲染 + 字面量 3 = 封顶常量（设计 §4.2 初值 = 3，改参须有意更新本值）。
    expect(find.text('被偷菜贼偷走 3 阳光'), findsOneWidget,
        reason: '高偷窃战局（首怪必到门、steal=3）⇒ 结算卡必须有被偷行且钳在 3');

    // 账本实扣 == 卡面 N 且 ≤ 封顶（「账本 ≤3」的强形式 = 恰 −3.0）。
    final String today = dayKey(DateTime.now());
    final double net =
        await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, today);
    expect(net, -3.0,
        reason: '账本实扣 −3（= −封顶）：被偷行必须进账且不超过封顶');
    expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today), 1,
        reason: '同日至多 1 行 guard_stolen');
  });

  // ── ④ 恢复随机剧本 ⇒ 覆盖清空 ────────────────────────────────────────
  testWidgets('④ 先「强制 5 只怪」再「恢复随机剧本」⇒ provider 回 null',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('c1');
    final ProviderContainer container = _container(env);

    await _openPanelAndScrollToScript(tester, container);
    await tester.tap(find.byKey(const ValueKey<String>(kDebugGuardScriptKeyCount5)));
    await _settleAction(tester);
    expect(container.read(debugGuardBattleScriptOverrideProvider), isNotNull,
        reason: '前置：覆盖已写入');

    // 「恢复随机剧本」可能需要再滚一点（同区块更下方）。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)));
    await _settleAction(tester);

    expect(container.read(debugGuardBattleScriptOverrideProvider), isNull,
        reason: '🔴 恢复随机 ⇒ 覆盖清空，下次战斗回到真实 seed 派生');
  });

  // ── ⑥ E2 回归：IndexedStack 保活 + 花园页面板真实点击链路 ───────────────
  //
  // 玄参真机复现（「在花园调试页面点恢复随机剧本，没有任何响应」）。病理
  // 两层（B5b 修复均落在表现层）：
  //  ① 今日页在 IndexedStack 后台保活，`guardTodayProvider` 快照只有
  //     `_refreshGuard` 才更新 —— 面板 forceThiefForDebug 只写 store ⇒ 待机
  //     时卡片根本不出现。修复 = 页面 `ref.listen` 覆盖变化 ⇒ 立即重读。
  //  ② 战斗层 sim 在 initState 派生一次 ⇒ 覆盖进不了正在跑的战局。修复 =
  //     field `didUpdateWidget` 对比覆盖身份重开战局。
  // 真实语义分叉（断言按此钉死）：
  //  · 战中「强制 N 只怪」会顺带 forceThiefForDebug ⇒ 状态被覆写回 pending
  //    ⇒ 战斗层卸载（响应 = 退回待机），重开「开始守卫」后新战局吃覆盖；
  //  · 战中「恢复随机」不写状态 ⇒ 战斗层**不卸载**，走 ② 立即重开回真实
  //    派生（倒计时回满 = 重开的确定性观测点）。
  testWidgets('⑥ IndexedStack 保活：面板强制剧本有响应；战中「恢复随机」立即重开回真实派生',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('c1');
    await _seedValidFocus(env);
    final ProviderContainer container = _container(env);

    // 🔴 IndexedStack 保活夹具：今日页与面板宿主同挂；pages 只构造一次、
    // 切 tab 仅换 index（子树 Element 原样保活 = 生产外壳语义）。
    final List<Widget> pages = <Widget>[
      _todayHost(container),
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _PanelEntryPage()),
      ),
    ];
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 0, children: pages)),
    );
    for (int i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 前置：待机时（今日页先挂载）点「强制 3 只怪」⇒ 切回今日 tab 卡片必须
    // **出现**（修复①：listen ⇒ 重读 ⇒ 状态 pending ⇒ 卡片可见）——
    // 修复前这里 start 按钮永不出现（玄参「没响应」的第一现场）。
    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 1, children: pages)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _openPanelViaEntry(tester);
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyCount3)));
    await _settleAction(tester);
    expect(container.read(debugGuardBattleScriptOverrideProvider)!.monsters.length, 3,
        reason: '覆盖已写入 provider（注入链第一环）');
    await _closePanel(tester);

    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 0, children: pages)),
    );
    expect(
        await _pumpUntilReady(
            tester, find.byKey(GuardSceneCard.startButtonKey)),
        isTrue,
        reason: '🔴 E2 修复①：面板强制后切回今日页，守卫卡必须出现（可开战）');

    // 开战（确定性 3 怪剧本）⇒ monsterKey(3) 在本场永远不该出现。
    await _startBattle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget,
        reason: '3 怪战局已开跑（首怪 t=0 在场）');

    // ── 战中「强制 5 只怪」：状态被覆写回 pending ⇒ 战斗层退场（有响应）──
    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 1, children: pages)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _openPanelViaEntry(tester);
    await tester.scrollUntilVisible(
      find.text('强制 5 只怪'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('强制 5 只怪'));
    await _settleAction(tester);
    expect(container.read(debugGuardBattleScriptOverrideProvider)!.monsters.length, 5,
        reason: '覆盖已切到 5 只');
    await _closePanel(tester);

    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 0, children: pages)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(GuardBattleField.fieldKey), findsNothing,
        reason: '战中 force 覆写状态 ⇒ 战斗层退场（退回待机 = 有响应）');
    expect(
        await _pumpUntilReady(
            tester, find.byKey(GuardSceneCard.startButtonKey)),
        isTrue,
        reason: '退回待机态 ⇒ 可重新开始守卫');

    // 重开「开始守卫」⇒ 新战局吃 5 怪覆盖：monsterKey(4) 只能出自覆盖剧本。
    await _startBattle(tester);
    bool fifthSpawned = false;
    for (int i = 0; i < 60; i++) {
      if (find.byKey(GuardBattleField.monsterKey(4)).evaluate().isNotEmpty) {
        fifthSpawned = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(fifthSpawned, isTrue,
        reason: '🔴 强制 5 只怪 ⇒ 新战局第 5 只（24s 出场）必须上屏');
    for (int i = 0; i < 5; i++) {
      expect(find.byKey(GuardBattleField.monsterKey(i)), findsOneWidget);
    }
    expect(find.byKey(GuardBattleField.monsterKey(5)), findsNothing);

    // ── 战中「恢复随机」：不写状态 ⇒ 战斗层不卸载，didUpdateWidget 重开 ──
    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 1, children: pages)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _openPanelViaEntry(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)));
    await _settleAction(tester);
    expect(container.read(debugGuardBattleScriptOverrideProvider), isNull,
        reason: '恢复随机 ⇒ 覆盖清空');
    await _closePanel(tester);

    await tester.pumpWidget(
      MaterialApp(home: IndexedStack(index: 0, children: pages)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    // 🔴 E2 修复②：战斗层仍在场（状态未被覆写）且已按真实派生重开 ——
    // 观测点 = 倒计时回满（sim 时间轴归零）。修复前 override 进不了战局。
    expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
        reason: '恢复随机不写状态 ⇒ 战斗层保持在场');
    // 阈值 0.9：restart 后到本断言之间有 ~0.9s 的面板收尾泵进（重开 ≈ 0.97+；
    // 未重开的旧战局此刻已在 ~24s ⇒ 值 ≈ 0.2，分界清晰）。
    expect(_countdownValue(tester), greaterThan(0.9),
        reason: '🔴 E2 修复②：战中「恢复随机」⇒ 战局立即重开（倒计时回满）');
    // 真实派生剧本首怪 t=0 在场、次怪 6s 未出场（新时间轴刚起步）。
    expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget);
    expect(find.byKey(GuardBattleField.monsterKey(1)), findsNothing,
        reason: '重开 ⇒ 时间轴归零，第 2 只怪（6s 出场）尚未上屏');
    expect(tester.takeException(), isNull);
  });

  // ── ⑤ buildGuardBattleScriptForDebug 纯函数（字面量）───────────────────
  group('⑤ buildGuardBattleScriptForDebug 单元（零随机、逐位可复现）', () {
    test('count=3：出场表前 3 项、steal 轮转 1/2/3、默认全 m1、车道均布', () {
      final GuardBattleScript s =
          buildGuardBattleScriptForDebug(monsterCount: 3);
      expect(s.monsters.length, 3);
      expect(s.windowMs, kGuardBattleWindowMs);
      expect([for (final m in s.monsters) m.spawnMs],
          kGuardSpawnOffsetsMs.sublist(0, 3));
      expect([for (final m in s.monsters) m.steal], <int>[1, 2, 3]);
      expect(
          {for (final m in s.monsters) m.kind}, <GuardBattleMonsterKind>{
        GuardBattleMonsterKind.m1,
      });
      // 车道均布：laneY 严格递增且都在 [top, bottom] 内。
      for (int i = 0; i < 3; i++) {
        expect(s.monsters[i].laneYPt,
            inInclusiveRange(kGuardBattleLaneTopPt, kGuardBattleLaneBottomPt));
        if (i > 0) {
          expect(s.monsters[i].laneYPt,
              greaterThan(s.monsters[i - 1].laneYPt));
        }
      }
    });

    test('count=5：出场表前 5 项（0/6/12/18/24s）、steal 轮转 1/2/3/1/2', () {
      final GuardBattleScript s =
          buildGuardBattleScriptForDebug(monsterCount: 5);
      expect(s.monsters.length, 5);
      expect([for (final m in s.monsters) m.spawnMs], kGuardSpawnOffsetsMs);
      expect([for (final m in s.monsters) m.steal], <int>[1, 2, 3, 1, 2]);
    });

    test('kinds=[m1,m2,m3]：逐怪种类保序', () {
      final GuardBattleScript s = buildGuardBattleScriptForDebug(
        monsterCount: 3,
        kinds: const <GuardBattleMonsterKind>[
          GuardBattleMonsterKind.m1,
          GuardBattleMonsterKind.m2,
          GuardBattleMonsterKind.m3,
        ],
      );
      expect([for (final m in s.monsters) m.kind],
          <GuardBattleMonsterKind>[
        GuardBattleMonsterKind.m1,
        GuardBattleMonsterKind.m2,
        GuardBattleMonsterKind.m3,
      ]);
    });

    test('highTheft：全 m1（最慢 ⇒ 必有怪到门）、steal 全 = kGuardStealMax', () {
      final GuardBattleScript s = buildGuardBattleScriptForDebug(
        monsterCount: 3,
        highTheft: true,
      );
      for (final GuardBattleMonsterSpec m in s.monsters) {
        expect(m.kind, GuardBattleMonsterKind.m1,
            reason: '高偷窃必须全 m1：13pt/s ⇒ 首怪 ~25.4s 到门 < 30s 窗口');
        expect(m.steal, kGuardStealMax, reason: '偷取值全顶格');
      }
      // 首怪必在窗口内到门（「必有怪到门口」的字面化）。
      final GuardBattleMonsterSpec first = s.monsters.first;
      final double doorSec =
          (kGuardBattleFieldTravelPt / first.speedPtPerSec) +
              first.spawnMs / 1000;
      expect(doorSec, lessThan(kGuardBattleWindowMs / 1000),
          reason: '🔴 首怪到门时刻 $doorSec s 必须 < 窗口 30s（高偷窃剧本的承诺）');
    });

    test('同参数重跑逐位相等（确定性口径，金测同源）', () {
      final GuardBattleScript a = buildGuardBattleScriptForDebug(
        monsterCount: 5,
        kinds: const <GuardBattleMonsterKind>[
          GuardBattleMonsterKind.m2,
          GuardBattleMonsterKind.m3,
          GuardBattleMonsterKind.m1,
          GuardBattleMonsterKind.m2,
          GuardBattleMonsterKind.m3,
        ],
      );
      final GuardBattleScript b = buildGuardBattleScriptForDebug(
        monsterCount: 5,
        kinds: const <GuardBattleMonsterKind>[
          GuardBattleMonsterKind.m2,
          GuardBattleMonsterKind.m3,
          GuardBattleMonsterKind.m1,
          GuardBattleMonsterKind.m2,
          GuardBattleMonsterKind.m3,
        ],
      );
      // GuardBattleScript 实现了 == / hashCode（B1 冻结口径）。
      expect(a, b);
    });
  });
}
