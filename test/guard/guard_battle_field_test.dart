/// 守卫战 v2 · B3 **L4 战斗层（卡内最小可玩闭环）**的护栏（①~⑦ + 全流程经济口径）。
///
/// 真源：守卫战设计文档 §7-B3 / §4（引擎参数）/ §6.1（L4 层）。
///
/// ## 覆盖（逐条对应交付要求）
/// | # | 断言 | 层级 |
/// |---|---|---|
/// | ① | 同 seed + 同 fire 时间线 pump 两遍 ⇒ 锚点（10s/20s）快照逐位相等；不同 seed 不等 | widget |
/// | ② | 400ms 冷却：1000ms 开火、1200ms 连点被拦（场上 1 发）、1500ms 再开火（2 发） | widget |
/// | ③ | Victory：全灭 → 横幅 + 开火钮 disabled → 结果卡可达 → claim 只落一次账 | 页面 |
/// | ④ | Retreat：30s 到点横幅、已偷不回滚（账本零新增）、结果卡可达、claim 一次 | 页面 |
/// | ⑤ | Abandoned：战斗中重挂 widget 树 ⇒ 战局零落盘（账本零新增）、sim 重开（可重打） | 页面 |
/// | ⑥ | 战斗态 288 槽 + en + 1.3 无 overflow（怪物在车道上时） | widget |
/// | ⑦ | 三种怪素材位可区分（B9/D2：三怪各有真实 7 帧序列、目录互异） | widget |
/// | ⑥′⑦′ | 旧 ⑥⑦ 迁移：全流程（免费 / 付费）→ 结算 → claim 恰好一次账 | 页面 |
///
/// ## 🔴 页面级种子控制（防日期漂移）
/// 页面级战斗用例的 seed = `(今天, childId)`。今天随真实时钟走 ⇒ 用例先在
/// **纯 sim**里搜索一个「该天必胜」的 childId（450ms 步进连射重放，全灭才收），
/// 再把它造成**活跃孩子档案**（`ChildProfileLocalRepository.create(id: …)` 在
/// `initialize()` 之前），最后把搜出的时间线逐点经开火钮重放进 UI —— 三方
/// （搜索 / 纯 sim / UI）用同一份剧本，零随机、零 flake。
///
/// ## 🔴 绝不 `pumpAndSettle`
/// 阳光气泡无限循环动画；且战斗层 ticker 常驻 —— 全文件定长 `pump` 推进。
library guard_battle_field_test;

import 'dart:convert';

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
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 纯 sim 搜索（页面级用例的种子控制，零随机）
// ═══════════════════════════════════════════════════════════════════════

/// 450ms 步进连射（自瞄，冷却 400ms ⇒ 全部受理）重放一整场，回结束原因。
GuardBattleEndReason _replayGreedy(String dayKey, String childId) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim = GuardBattleSim(
    script: script,
    dayKey: dayKey,
    childId: childId,
  );
  for (int t = 450; t <= script.windowMs; t += 450) {
    final GuardBattleStepReport report = sim.step(t, <int>[t]);
    if (report.ended) return report.endReason;
  }
  return GuardBattleEndReason.windowExpired;
}

/// 找一个「今天用 450ms 连射能全灭」的 childId，连同**逐点开火时间线**返回
/// （UI 侧按同一份时间线经开火钮重放 —— 三方同一剧本，零 flake）。
(String, List<int>) _findWinningChild(String dayKey) {
  for (int n = 0; n < 200; n++) {
    final String childId = 'bt-win-$n';
    if (_replayGreedy(dayKey, childId) == GuardBattleEndReason.allDead) {
      return (
        childId,
        <int>[for (int t = 450; t <= kGuardBattleWindowMs; t += 450) t],
      );
    }
  }
  throw StateError('搜遍 200 个 seed 都没有可全灭阵容 —— 引擎参数或判定异常');
}

/// 找一个「**今天掉落档带券**」的 childId（结算卡的比较行只在券档渲染）。
///
/// 🔴 午夜安全（2026-11-11 实测踩坑）：掉落是 `dayKey + childId` 的确定性
/// 摇号 —— 固定 childId（'c1'）的档位**随日期漂移**（11-10 的 c1 = 浇水券、
/// 11-11 = 无道具），断言「券还能省 / 花了 5 阳光」的用例会挂一整天。
/// 与 [_findWinningChild] 同一思路：按今天的摇号**搜**一个必然带券的娃。
String _findVoucherChild(String dayKey) {
  for (int n = 0; n < 500; n++) {
    final String childId = 'bt-voucher-$n';
    if (GuardDropKind.roll(dayKey: dayKey, childId: childId).hasVoucher) {
      return childId;
    }
  }
  throw StateError('搜遍 500 个 seed 都没有券档 —— 掉落概率表异常');
}

/// 找三种「**纯色**阵容」的 childId（m1 / m2 / m3 各一个）。
///
/// 🔴 实测口径（B3）：`kind_<i>` 通道在同一 seed 内强相关 —— 200 个 seed 里
/// 从未出现三怪混编（同 seed 几乎全同种，偶有一只偏离）。故 ⑦ 改用三个
/// **纯色 seed** 各渲一怪、断「m1 走帧序列、m2/m3 占位色互异」—— 判据等价
/// （色表注入是单射 ⇒ 任何混编阵容同样可区分），且不依赖小概率阵容。
(Map<String, String>, Map<String, GuardBattleMonsterKind>) _findPureKindChildren(
    String dayKey) {
  final Map<String, String> ids = <String, String>{};
  final Map<String, GuardBattleMonsterKind> kinds = <String, GuardBattleMonsterKind>{};
  for (int n = 0; n < 500 && ids.length < 3; n++) {
    final String childId = 'bt-pure-$n';
    final GuardBattleScript script =
        deriveGuardBattleScript(dayKey: dayKey, childId: childId);
    final Set<GuardBattleMonsterKind> set = <GuardBattleMonsterKind>{
      for (final GuardBattleMonsterSpec m in script.monsters) m.kind,
    };
    if (set.length != 1) continue;
    final GuardBattleMonsterKind kind = set.first;
    if (ids.containsKey(kind.id)) continue;
    ids[kind.id] = childId;
    kinds[kind.id] = kind;
  }
  if (ids.length < 3) {
    throw StateError('三种纯色阵容没凑齐（只找到 ${ids.keys}）—— 出怪表异常');
  }
  return (ids, kinds);
}

// ═══════════════════════════════════════════════════════════════════════
// widget 级夹具（①②⑥⑦：不碰任何服务）
// ═══════════════════════════════════════════════════════════════════════

/// widget 级战斗层会话：快照收集器 + 已注册的手柄（测试经手柄开火）。
class _FieldSession {
  _FieldSession(this.snaps, this.handle);
  final List<GuardBattleSnapshot> snaps;
  final GuardBattleHandle handle;
}

/// 直接挂一个 L4 战斗层（288×140 卡内槽位），返回会话。
///
/// 🔴 第二个 `pump(1ms)` 是**挂载帧**：本帧构建 field 并 start ticker，
/// 不给 ticker 推进时间 ⇒ 之后的 pump 差值 = sim 时间轴（确定性基线）。
Future<_FieldSession> _pumpField(
  WidgetTester tester, {
  String dayKey = '2026-01-01',
  required String childId,
  ValueChanged<int>? onFinished,
  bool english = false,
  double textScale = 1.0,
}) async {
  final List<GuardBattleSnapshot> snaps = <GuardBattleSnapshot>[];
  final GuardBattleHandle handle = GuardBattleHandle();
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
                  width: 288,
                  height: 140,
                  child: GuardBattleField(
                    dayKey: dayKey,
                    childId: childId,
                    handle: handle,
                    onSnapshot: snaps.add,
                    onFinished: onFinished,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1));
  return _FieldSession(snaps, handle);
}

/// 把 [GuardSceneCard] 挂在 288 槽（战斗态溢出探针 ⑥ 用）。
Future<void> _pumpCard(
  WidgetTester tester,
  GuardTodayView view, {
  required String dayKey,
  required String childId,
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
                  width: 288,
                  child: GuardSceneCard(
                    view: view,
                    dayKey: dayKey,
                    childId: childId,
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
  await tester.pump(const Duration(milliseconds: 1));
}

GuardTodayView _fightingView() {
  return const GuardTodayView(
    mode: GuardPillMode.fighting,
    state: GuardDayState(
      dayKey: '2026-01-01',
      status: GuardDayStatus.fighting,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: 1,
    balance: 100,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 页面级夹具（③④⑤⑥′⑦′：真库 + 真 prefs + 真守卫链路）
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

  Future<GuardDayState> guardState() => guardStore.read(childId);

  Future<int> ledgerRowsOnDay(String refType, String dayKeyValue) =>
      ledger.countByRefTypeAndRefIdOnDay(refType, kGuardRefId, dayKeyValue);
}

/// 建库 + 以 [childId] 建**活跃孩子**（在 initialize() 前插档 ⇒ initialize
/// 不再建默认娃，`account.childId == childId`）—— 页面级战斗用例的种子控制点。
Future<_Env> _makeEnvWithChild(String childId) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await ChildProfileLocalRepository(database)
      .create('战斗用例娃', AgeTier.high, id: childId);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  assert(account.childId == childId, '活跃孩子应是搜索出的 seed 娃');
  return _Env(sp: sp, database: database, account: account);
}

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

Future<void> _seedValidFocus(_Env env) async {
  final DateTime now = DateTime.now();
  // 🔴 午夜安全（2026-11-11 00:05 北京实测踩坑）：`sessionsOfDay` 按 **start**
  // 归日（`start >= dayStart && start < dayEnd`），`start = now − 20min` 在
  // 午夜后 20 分钟内属于**昨天** ⇒ 今日能量 0 ⇒ resolve 落免罚档 ⇒ 开战钮
  // 不存在，③④⑤⑥′ 在 00:00~00:20 必挂。钳到「今天 00:00 之后」即与
  // 运行时刻无关（validity 只看 actualFocusMin，不校验墙钟时长）。
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

/// 用**同一个** container 重挂今日页（⑤ Abandoned 的「重挂 widget 树」）。
Future<void> _repumpToday(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

/// 读场景卡的状态语义标签（B7：卡内零文本，状态只经 `Semantics.label` 出口）。
String _cardLabel(WidgetTester tester) =>
    tester
        .widget<Semantics>(find.byKey(GuardSceneCard.statusSemanticsKey))
        .properties
        .label ??
    '';

/// 越过 B2 教学浮层（与 guard_today_flow_test 同口径）。
///
/// 🔴 B7：教学改成**永久一次**（prefs），同一 env 内第二次点卡不会再弹 ⇒
/// 这里必须「弹了才点」，不能无条件 `_pumpUntil` 等它出现（会挂到超时）。
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

/// 进战斗并推进到「L4 已挂载、ticker 从 0 起跑」的干净基线
/// （挂载帧不推进 sim 时间 ⇒ 之后的 pump 差值 = sim 时间轴）。
///
/// [paid] = 走付费路径（确认卡「确定」）；否则免费路径直达。
Future<void> _startBattle(
  WidgetTester tester, {
  bool paid = false,
}) async {
  await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
  await _passTutorial(tester);
  if (paid) {
    await tester.tap(find.text('确定')); // 确认卡主按钮（shared_ok）
    await _settleRoute(tester);
  }
  // handler 的 microtask 收尾（markFighting / provider 翻转）。
  await tester.pump(const Duration(milliseconds: 50));
  // L4 挂载帧（ticker 自本帧起，elapsed = 0）。
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
      reason: '开始守卫后 L4 战斗层必须在卡内上屏');
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① widget 级确定性 ─────────────────────────────────────────────────
  group('① widget 级确定性：同 seed + 同时间线逐位重放', () {
    /// 固定时间线（1000/2000/3000ms 各一枪），回锚点 10s/20s 的快照 JSON。
    Future<Map<int, String>> runOnce(
      WidgetTester tester,
      String childId,
    ) async {
      final _FieldSession s = await _pumpField(tester, childId: childId);
      await tester.pump(const Duration(seconds: 1)); // t=1000
      s.handle.fire();
      await tester.pump(const Duration(seconds: 1)); // t=2000
      s.handle.fire();
      await tester.pump(const Duration(seconds: 1)); // t=3000
      s.handle.fire();
      await tester.pump(const Duration(seconds: 7)); // t=10000
      final String at10s = jsonEncode(s.snaps.last.toJson());
      await tester.pump(const Duration(seconds: 10)); // t=20000
      final String at20s = jsonEncode(s.snaps.last.toJson());
      await tester.pumpWidget(const SizedBox.shrink()); // 卸载，防 ticker 叠加
      return <int, String>{10: at10s, 20: at20s};
    }

    testWidgets('同 seed pump 两遍 ⇒ 锚点逐位相等；不同 seed ⇒ 不等',
        (WidgetTester tester) async {
      final Map<int, String> runA = await runOnce(tester, 'seed-0');
      final Map<int, String> runB = await runOnce(tester, 'seed-0');
      expect(runA[10], runB[10], reason: '🔴 10s 锚点必须逐字符相同（金测同口径）');
      expect(runA[20], runB[20], reason: '🔴 20s 锚点必须逐字符相同（金测同口径）');

      final Map<int, String> runC = await runOnce(tester, 'seed-42');
      final bool differs =
          runA[10] != runC[10] || runA[20] != runC[20];
      expect(differs, isTrue, reason: '不同 seed 的战局必须不同（剧本派生生效）');
    });
  });

  // ── ② 冷却闸门 ────────────────────────────────────────────────────────
  group('② 冷却闸门（400ms）', () {
    testWidgets('400ms 内第二次点击无第二发；过冷却再点有第二发',
        (WidgetTester tester) async {
      final _FieldSession s = await _pumpField(tester, childId: 'seed-0');

      // t=1000：首枪受理（首发恒过闸门；seed-0 首怪 m2 @0ms 已在场）。
      await tester.pump(const Duration(seconds: 1));
      s.handle.fire();
      await tester.pump(const Duration(milliseconds: 200)); // t=1200
      s.handle.fire(); // 距上枪 200ms < 400 ⇒ 应被拦
      await tester.pump(const Duration(milliseconds: 50)); // t=1250
      expect(s.snaps.last.bullets.length, 1,
          reason: '🔴 冷却内的连点不得产生第二发（场上应只有 1 发在飞）');

      await tester.pump(const Duration(milliseconds: 250)); // t=1500
      s.handle.fire(); // 距首枪 500ms ≥ 400 ⇒ 受理
      await tester.pump(const Duration(milliseconds: 100)); // t=1600
      expect(s.snaps.last.bullets.length, 2,
          reason: '过冷却的第二次开火必须有第二发（首枪弹 ~1817ms 才到达，仍在飞）');
    });
  });

  // ── ⑥ 战斗态溢出 ──────────────────────────────────────────────────────
  group('⑥ 战斗态 288 槽 + en + 1.3×：无 overflow', () {
    testWidgets('怪物在车道上、倒计时递减时整卡不溢出', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _fightingView(),
        dayKey: '2026-01-01',
        childId: 'seed-0',
        textScale: 1.3,
        english: true,
      );
      // 推 2s：首怪入车道 + L2 倒计时开始递减。
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull,
          reason: '战斗态在 288 槽 + en + 1.3 下不得溢出（F127 教训）');
      // 卡高仍恒 140（战斗层不得撑破卡）。
      expect(
        tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
        closeTo(kGuardSceneCardHeight, 0.5),
      );
    });
  });

  // ── ⑦ 三种怪「素材位」可区分 ──────────────────────────────────────────
  group('⑦ 三种怪素材位可区分（B9/D2：三怪各有真实帧序列）', () {
    testWidgets('m1/m2/m3 各渲一怪（三 finder 各一）；三种帧序列目录互异',
        (WidgetTester tester) async {
      const String dayKey = '2026-01-01';
      final (Map<String, String> ids, Map<String, GuardBattleMonsterKind> kinds) =
          _findPureKindChildren(dayKey);

      // 每种怪一个 seed：推 2s（首怪 @0ms 已在车道上），读它的渲染素材位。
      // 🔴 B9/D2：三种怪**都有真实 7 帧序列** ⇒ 每个纯色 seed 的首怪都必须渲染
      // FrameSequencePlayer，且帧目录分别指向 monster_m1 / m2 / m3（互不串线）；
      // 占位色块只留在「素材缺失」兜底（guard_art_fallback_test 覆盖）。
      final Map<String, String> firstFrame = <String, String>{};
      for (final String kindId in ids.keys) {
        await _pumpField(tester, dayKey: dayKey, childId: ids[kindId]!);
        await tester.pump(const Duration(seconds: 2));
        expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget,
            reason: '$kindId 阵容的首怪必须在车道上渲染（三 finder 各一之一）');
        final FrameSequencePlayer player = tester.widget<FrameSequencePlayer>(
          find.descendant(
            of: find.byKey(GuardBattleField.monsterKey(0)),
            matching: find.byType(FrameSequencePlayer),
          ),
        );
        expect(player.frames, hasLength(7),
            reason: '$kindId 进攻动画 7 帧');
        firstFrame[kindId] = player.frames.first;
        await tester.pumpWidget(const SizedBox.shrink());
      }

      expect(firstFrame.keys.toSet(), <String>{'m1', 'm2', 'm3'},
          reason: '🔴 三种怪都在车道上渲过');
      expect(firstFrame['m1'], 'assets/guard/monster_m1/frame001.webp',
          reason: '🔴 m1（馋光鼠）= monster_m1 目录');
      expect(firstFrame['m2'], 'assets/guard/monster_m2/frame001.webp',
          reason: '🔴 B9/D2：m2（食叶虫）= monster_m2 目录');
      expect(firstFrame['m3'], 'assets/guard/monster_m3/frame001.webp',
          reason: '🔴 B9/D2：m3（贪婪鼬）= monster_m3 目录');
    });
  });

  // ── ③ Victory 全流程（种子受控）───────────────────────────────────────
  group('③ Victory：全灭 → 横幅 + disabled → 结算卡 → claim 一次', () {
    testWidgets('全灭后横幅出现、按钮 disabled、claim 后账本行数与旧路径逐位一致',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final (String childId, List<int> timeline) = _findWinningChild(today);
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env); // 有能量 ⇒ 免费路径
      await _pumpToday(tester, env);
      await _startBattle(tester);

      // 按搜出的时间线逐点开火（每 pump 恰好落在时间线点上，fire 时刻逐位一致）。
      // 🔴 B7：开火入口 = 页面右上的**阳光胶囊**（卡内大圆钮已删；胶囊在守卫战
      // 期间冻结位置并接管开火）。
      int last = 0;
      for (final int t in timeline) {
        await tester.pump(Duration(milliseconds: t - last));
        last = t;
        await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey),
            warnIfMissed: false);
      }

      // 终局：横幅上屏。
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      expect(find.text('怪物全赶跑了！'), findsOneWidget,
          reason: 'Victory 横幅必须是「怪物全赶跑了！」');
      // 🔴 B7：卡内开火钮已删，「按钮 disabled（Opacity 0.4）」这个载体不存在了；
      // 终局禁用的语义改由 `GuardBattleHandle.fire()` 的 over 闸门承担 ——
      // 这里直接验行为：终局后再点胶囊**不得再出子弹**。
      await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(GuardBattleField.bulletKey(0)), findsNothing,
          reason: '🔴 终局后的开火必须被手柄闸门丢掉（UI 面不再递枪）');

      // 横幅 ~900ms 后交回页面 → 结算卡（既有流，入参 view 不变）。
      await tester.pump(const Duration(milliseconds: 1000));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      final String today2 = dayKey(DateTime.now());
      // 战斗阶段零写账；B4 起结算前落「被偷」，但本战局全灭 = 零怪到门口
      // ⇒ sim 被偷合计 0 ⇒ recordBattleTheft(0) 空操作（领域层口径）。
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today2), 0,
          reason: '🔴 奖励只在「收下」时发放');
      expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today2), 0,
          reason: '全灭战局被偷合计 0 ⇒ 被偷行也必须是 0 行（B4 落账口径）');

      final int winSun = (await env.guardState()).winSun;
      expect(find.text('拿回 $winSun 阳光'), findsOneWidget,
          reason: '结果卡入参 view 不变：必得阳光口径与 v1 逐位一致');

      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // claim 只落一次账（与 v1 老路径逐位同口径）。
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today2), 1,
          reason: '必得阳光必须恰好入账一次');
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today2), 0,
          reason: '有能量路径不得扣阳光');
      final GuardDayState state = await env.guardState();
      expect(state.status, GuardDayStatus.claimed);
      expect(state.energyUsed, 1);
      expect(_cardLabel(tester), contains('今天的菜守住了'),
          reason: 'claim 之后卡回到 claimed 态（B7：状态只在 Semantics.label 上）');
    });
  });

  // ── ④ Retreat ─────────────────────────────────────────────────────────
  group('④ Retreat：30s 到点横幅 + 已偷不回滚（UI 呈现）', () {
    testWidgets('到点横幅、按钮 disabled、账本零新增、结果卡可达、claim 一次',
        (WidgetTester tester) async {
      final _Env env = await _makeEnvWithChild('c1');
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _pumpToday(tester, env);
      await _startBattle(tester);

      // 一枪不发，整窗推完（ticker 一次吃下 31s ⇒ sim 内 30s 收场）。
      await tester.pump(const Duration(seconds: 31));
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      expect(find.text('时间到，剩下的怪物撤退了'), findsOneWidget,
          reason: 'Retreat 横幅必须是「时间到，剩下的怪物撤退了」');
      // 🔴 B7：卡内开火钮已删 —— 终局禁用的行为断言（点了不出子弹）。
      await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(GuardBattleField.bulletKey(0)), findsNothing,
          reason: '🔴 终局后的开火必须被手柄闸门丢掉');

      // 「已偷不回滚」的 UI 呈现：战局期间账本零新增。B4 起结算前会落
      // 「被偷行」，但本用例**余额 0** ⇒ recordBattleTheft 的余额钳制兜住
      // （charged ≤ 0 不写 0 元行，PRD 决策 D6）—— 断言口径不变。
      final String today = dayKey(DateTime.now());
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today), 0);
      expect(await env.ledger.balance(), closeTo(0, 1e-9));

      await tester.pump(const Duration(milliseconds: 1000));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1,
          reason: 'Retreat 收场同样走既有 claim，恰好入账一次');
      final GuardDayState state = await env.guardState();
      expect(state.status, GuardDayStatus.claimed);
    });
  });

  // ── ⑤ Abandoned ───────────────────────────────────────────────────────
  group('⑤ Abandoned：战斗中重挂 widget 树', () {
    testWidgets('战局零落盘（账本零新增）、sim 重开可重打、存档仍 fighting',
        (WidgetTester tester) async {
      final _Env env = await _makeEnvWithChild('c1');
      await _seedPlant(env);
      await _seedValidFocus(env);
      final ProviderContainer container = await _pumpToday(tester, env);
      await _startBattle(tester);

      // 打到 2s（首怪已入车道），随后整树重挂。
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _repumpToday(tester, container);

      // 🔴 战局零落盘：重挂后账本零新增行（Abandoned 不经落账）。
      final String today = dayKey(DateTime.now());
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0);
      expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today), 0);

      // sim 重开（可重打）：L4 重新上屏、倒计时从**新战局**起算。
      // 重挂后 _repumpToday 推 24 × 100ms，其中挂载帧吃掉首个 100ms
      // （ticker 在该帧才 start）⇒ 新 sim 走了 2300ms ⇒ 值 = (30000−2300)/30000
      // ≈ 0.9233。若续打旧战局应为 (30000−4400)/30000 ≈ 0.853 —— 字面量可区分，
      // 证明是「重打」不是「续打」。
      expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
          reason: '重挂后卡仍在战斗态 ⇒ L4 重新上屏（战局从头打，零持久化）');
      final LinearProgressIndicator bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(GuardSceneCard.countdownKey),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(0.9233, 0.005),
          reason: '🔴 sim 重开（新战局 ~2.3s 处）而非续打旧战局（4.4s 处 ≈ 0.853）');

      // 存档层：markFighting 已写（v1 语义保位）⇒ 次日 expire 补发不罚。
      final GuardDayState stored = await env.guardState();
      expect(stored.status, GuardDayStatus.fighting);
    });
  });

  // ── ⑥′⑦′ 旧 ⑥⑦ 迁移：全流程经济口径（种子无关）────────────────────────
  group('⑥′ 全流程（免费路径）：30s 到点自动进结算；收下只发一次奖', () {
    testWidgets('战斗结束 ⇒ 横幅 ⇒ 结算卡；claim 只落一次账、能量恰扣 1',
        (WidgetTester tester) async {
      // 🔴 午夜安全：比较行只在券档渲染，childId 必须按今天的摇号搜（见
      // [_findVoucherChild] 的说明 —— 固定 'c1' 在 11-11 摇到无道具档）。
      final _Env env = await _makeEnvWithChild(
          _findVoucherChild(dayKey(DateTime.now())));
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _pumpToday(tester, env);
      await _startBattle(tester);

      // 不关心该 seed 打到全灭还是到点（两种终局结算流同一条）⇒ 直接推满窗口。
      await tester.pump(const Duration(seconds: 31));
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      await tester.pump(const Duration(milliseconds: 1000));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      // 结算卡内容与 v1 同口径（入参 view 不变）。
      expect(find.textContaining('赶走了'), findsOneWidget);
      final int winSun = (await env.guardState()).winSun;
      expect(find.text('拿回 $winSun 阳光'), findsOneWidget);
      expect(find.textContaining('券还能省'), findsOneWidget,
          reason: '🔴 比较说明是 R2 缓解，必须有');

      final String today = dayKey(DateTime.now());
      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1,
          reason: '必得阳光必须恰好入账一次');
      expect(await env.ledgerRowsOnDay(kGuardPayRefType, today), 0,
          reason: '有能量路径不得扣阳光');
      final GuardDayState state = await env.guardState();
      expect(state.status, GuardDayStatus.claimed);
      expect(state.energyUsed, 1);
      expect(_cardLabel(tester), contains('今天的菜守住了'),
          reason: 'claim 之后卡回到 claimed 态（B7：状态只在 Semantics.label 上）');
    });
  });

  group('⑦′ 全流程（付费路径）：确认后扣 5 ☀ 一次、发奖一次', () {
    testWidgets('确认 → 战斗 → 结算 → 收下：pay/win 各恰好一行、paidSun = 5',
        (WidgetTester tester) async {
      final _Env env = await _makeEnvWithChild(
          _findVoucherChild(dayKey(DateTime.now())));
      await _seedPlant(env);
      await _seedBalance(env, 100);
      await _pumpToday(tester, env);
      await _startBattle(tester, paid: true);

      await tester.pump(const Duration(seconds: 31));
      await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
      await tester.pump(const Duration(milliseconds: 1000));
      await _pumpUntil(tester, find.byKey(GuardResultCard.cardKey));
      await _settleRoute(tester);

      expect(find.textContaining('花了 $kGuardPayCost 阳光'), findsOneWidget,
          reason: '付费路径的比较说明必须点明「花了 5 阳光」');

      final String today = dayKey(DateTime.now());
      await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
      await _pumpUntil(tester, find.byType(ChildTodayPage));
      for (int i = 0; i < 20; i++) {
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
