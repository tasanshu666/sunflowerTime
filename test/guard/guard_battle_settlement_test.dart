/// 守卫战 v2 · B4 **结算账务闭环**的护栏（①②③⑤⑥；④ = 互斥回归指针）。
///
/// 真源：守卫战设计文档 §7-B4 / §5.3（落账裁决 B：结束时一次写）。
///
/// ## 覆盖（逐条对应交付要求）
/// | # | 断言 | 层级 |
/// |---|---|---|
/// | ① | 未开火惩罚必达（C120-13）：阳光卡 −3 + 失败标题 + 被偷行恒渲染、账本恒 −3 | 页面 |
/// | ② | 封顶（开火场口径；未开火数值巧合相等）：卡面 3、账本 3 | 页面 |
/// | ③ | 无怪到门口：被偷行**不渲染**（「偷走 0 阳光」句式绝不出现）、账本 0 行 | 页面 |
/// | ⑤ | 经济守恒：未开火惩罚恒扣 3、守卫账本行数恰为 1（付费则 2） | 页面 |
/// | ⑥ | 落账失败注入（store 抛异常）⇒ 结算卡照常弹出、无第二次扣减尝试 | 页面 |
/// | ④ | 互斥回归（战斗已落 `guard_stolen` ⇒ 次日 `expire` 零扣）：E4 既有用例
///       在 `test/guard/guard_service_test.dart`，B4 全量复跑确认仍绿 —— 本文件不重复 | 领域 |
///
/// ## 🔴 页面级种子控制（与 guard_battle_field_test 同范式）
/// seed = `(今天, childId)` 随真实时钟漂移 ⇒ 用例先在**纯 sim**里搜出目标战局
/// （「必被偷 N」/「必触顶」/「必胜」的 childId），再把它造成活跃孩子档案
/// （`ChildProfileLocalRepository.create(id: …)` 在 `initialize()` 之前），
/// 最后在 UI 里重放同一时间线 —— 三方同一剧本，零随机、零 flake。
/// 「今天必有贼」由 `GuardThiefKind.roll` 的权重表保证（三桶合计 1.0），
/// 搜索出的孩子不会落空成 absent。
///
/// ## 🔴 绝不 `pumpAndSettle`
/// 阳光气泡无限循环 + 战斗层 ticker 常驻 —— 全文件定长 `pump` 推进。
///
/// ## 🔴 T03 起：结算卡前多了一段**不可跳过**的宝箱演出
/// 链路变成 `终局横幅 → 落账 → 宝箱 drop/idle → 点击开箱(5s) → 结算卡`。
/// 六个 case 统一经 [awaitOpenChestAndResult] 走完这段（点全屏热区 + 定长 5s），
/// 不靠 8s 自动开箱兜底 —— 否则等于「跳过孩子真实路径」，宝箱阶段的回归全漏。
library guard_battle_settlement_test;

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
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 纯 sim 搜索（页面级用例的种子控制，零随机）
// ═══════════════════════════════════════════════════════════════════════

/// 一枪不发的整场重放（推满 30s 窗口），回终局快照。
/// 被偷合计 = 快照 `stolenSun`（含到点时刻的钳制值，sim 内逐怪已裁）。
GuardBattleSnapshot _replayNoFire(String dayKey, String childId) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim =
      GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
  for (int t = 500; t <= script.windowMs; t += 500) {
    sim.step(t, const <int>[]);
  }
  return sim.snapshot();
}

/// 450ms 步进连射（自瞄，冷却 400ms ⇒ 全部受理）重放一整场，回结束原因。
/// （③「无怪到门口」用：全灭 = 零怪走到门口 = 零被偷。）
GuardBattleEndReason _replayGreedy(String dayKey, String childId) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim =
      GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
  for (int t = 450; t <= script.windowMs; t += 450) {
    final GuardBattleStepReport report = sim.step(t, <int>[t]);
    if (report.ended) return report.endReason;
  }
  return GuardBattleEndReason.windowExpired;
}

/// 找一个「今天用 450ms 连射能全灭」的 childId，连同逐点开火时间线返回。
(String, List<int>) _findWinningChild(String dayKey) {
  for (int n = 0; n < 200; n++) {
    final String childId = 'bt4-win-$n';
    if (_replayGreedy(dayKey, childId) == GuardBattleEndReason.allDead) {
      return (
        childId,
        <int>[for (int t = 450; t <= kGuardBattleWindowMs; t += 450) t],
      );
    }
  }
  throw StateError('搜遍 200 个 seed 都没有可全灭阵容 —— 引擎参数或判定异常');
}

/// 找「必被偷恰 [want] ☀（未触顶）」的 childId。
///
/// 限定 `want ∈ {1, 2}`（< 封顶 3）⇒ 领域层三道钳制（封顶 / 余额 / 幂等）
/// 都不会改写数额 ⇒ 账本实扣 == sim 值，卡面/账本可逐位互证。
/// 🔴 B13.22：怪数 8~12 后「被偷 1」结构性不可达 —— 前 2 只怪（spawn 0/2.5s）
/// 横穿 ~19~25s 必然都在 30s 窗口内到门、各偷 ≥1 ⇒ 未触顶的最小被偷 = 2。
/// 🔴 B13.27：怪数改 6~9 后复测 300 seed 直方图 {3:279, 2:21, 恰1:0} —— 结论
/// 不变（前 2 只怪仍在窗口内必到门），故默认仍搜 **want=2**；win ≥ 3 恒成立
/// ⇒ 经济守恒（win − stolen ≥ 0）不受影响。
/// 🔴 B13.27 增量（C120-13）：未开火场惩罚恒 3、与 sim 被偷值解耦 —— 本搜索
/// 退化为「挑任意未开火战局」的选局工具（want 值不再进断言）。
(String, int) _findStolenChild(String dayKey, {int want = 2}) {
  for (int n = 0; n < 500; n++) {
    final String childId = 'bt4-stolen-$n';
    if (_replayNoFire(dayKey, childId).stolenSun == want) {
      return (childId, want);
    }
  }
  throw StateError('搜遍 500 个 seed 没找到被偷恰 $want ☀ 的战局 —— 出怪/偷取参数异常');
}

/// 找「必触顶」的 childId：sim 被偷合计钳在封顶 [kGuardStealDailyCap]，且
/// **名义被偷合计**（到门口怪的 `steal_i` 之和）> 封顶 —— 证明确实是
/// 「封顶钳制」而不是「恰好偷 3」。
String _findCappedChild(String dayKey) {
  for (int n = 0; n < 500; n++) {
    final String childId = 'bt4-cap-$n';
    final GuardBattleScript script =
        deriveGuardBattleScript(dayKey: dayKey, childId: childId);
    final GuardBattleSnapshot snap = _replayNoFire(dayKey, childId);
    if (snap.stolenSun != kGuardStealDailyCap) continue;
    // 名义合计 = 到门口（fled）各怪的剧本偷取值之和 —— 封顶用尽的怪
    // 「只演出退场、偷 0」，但它的 steal_i 仍算进名义合计。
    int potential = 0;
    for (final GuardBattleMonsterSnapshot m in snap.monsters) {
      if (m.phaseId == GuardBattleMonsterPhase.fled.id) {
        potential += script.monsters[m.index].steal;
      }
    }
    if (potential > kGuardStealDailyCap) return childId;
  }
  throw StateError('搜遍 500 个 seed 没找到触顶战局 —— 封顶路径无法验证');
}

// ═══════════════════════════════════════════════════════════════════════
// 页面级夹具（真库 + 真 prefs + 真守卫链路；与 guard_battle_field_test 同款）
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

  Future<int> ledgerRowsOnDay(String refType, String dayKeyValue,
      {String? refId}) =>
      ledger.countByRefTypeAndRefIdOnDay(refType, refId ?? kGuardRefId, dayKeyValue);

  /// 惩罚行（B13.27 增量 C120-13：refId 分流为 garden_penalty）计数。
  Future<int> penaltyRowsOnDay(String dayKeyValue) =>
      ledger.countByRefTypeAndRefIdOnDay(
          kGuardStolenRefType, kGuardNoFirePenaltyRefId, dayKeyValue);
}

/// 建库 + 以 [childId] 建**活跃孩子**（在 initialize() 前插档 ⇒ initialize
/// 不再建默认娃，`account.childId == childId`）—— 页面级战斗用例的种子控制点。
Future<_Env> _makeEnvWithChild(String childId) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await ChildProfileLocalRepository(database)
      .create('结算用例娃', AgeTier.high, id: childId);
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
  List<Override> overrides = const <Override>[],
  int frames = 24,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      ...overrides,
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

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 220,
  String? reason,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget, reason: reason ?? '等待超时：目标 widget 一直没出现');
}

Future<void> _settleRoute(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 越过 B2 教学浮层（与 guard_today_flow_test 同口径）。
/// 越过 B2 教学浮层。
///
/// 🔴 B7：教学改成**永久一次**（设备级 prefs），同一 env 内第二次点卡不会再弹 ⇒
/// 这里必须「弹了才点」，不能无条件等它出现（会挂到超时）。
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

/// 进战斗并推进到「L4 已挂载、ticker 从 0 起跑」的干净基线。
Future<void> _startBattle(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
  await _passTutorial(tester);
  // 🔴 B13.7：免费路径也弹确认卡（玄参：防误操作）⇒ 两条路径都点「确定」。
  await tester.tap(find.text('确定'));
  await _settleRoute(tester);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
      reason: '开始守卫后 L4 战斗层必须在卡内上屏');
}

/// 宝箱演出 → 开箱 → 结算卡（T03 起结算卡前**必过**宝箱阶段）。
///
/// 🔴 为什么每个 case 都必须走这里：设计 §2.2 把「终局 → 宝箱 → 结算卡」定为
/// **不可跳过**的演出链，结算卡不再由终局直接弹出。用例若直接等结算卡，等到的是
/// 8s 自动开箱的兜底路径（不是孩子真实路径），且会把宝箱阶段的回归全部漏掉。
///
/// 点的是**全屏热区**（`tapCatcherKey`）而不是宝箱本体 —— 与真实交互一致
/// （§7.4 热区 2：3~8 岁孩子不会精确点到箱子上）。
Future<void> awaitOpenChestAndResult(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    find.byKey(GuardChestStage.stageKey),
    reason: '🔴 终局横幅之后必须先演宝箱（宝箱与结算卡都不可跳过）',
  );
  // 路由过渡（kGuardBattleToResultMs=200ms）走完再点，避免点在动画位移上。
  await tester.pump(const Duration(milliseconds: 260));
  expect(find.byKey(GuardChestStage.chestKey), findsOneWidget,
      reason: '宝箱落下后应以静态首帧（frame001）停在菜地里');
  expect(find.byKey(GuardResultCard.cardKey), findsNothing,
      reason: '🔴 宝箱没开完，结算卡不许抢跑');
  await tester.tap(find.byKey(GuardChestStage.tapCatcherKey));
  await tester.pump(); // 起播一帧：把 FrameSequencePlayer 挂上
  expect(find.byKey(GuardChestStage.chestKey), findsNothing,
      reason: '点击后静态宝箱让位给开箱动画');
  // 5s 开箱（30 帧 × 166.7ms）—— 定长推进，绝不 pumpAndSettle。
  await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
  await tester.pump(const Duration(milliseconds: 50)); // completed 在到点下一帧派发
  await _pumpUntil(
    tester,
    find.byKey(GuardResultCard.cardKey),
    reason: '开箱 5s 播完后必须弹结算卡',
  );
  await _settleRoute(tester);
}

/// 把一场战斗从「开战」打到「结算卡上屏」，回账本日键。
/// [fireTimeline] 非空 = 逐点经**阳光胶囊**重放（③ 全灭流）；空 = 一枪不打（①②⑤⑥）。
Future<String> _runBattleToResultCard(
  WidgetTester tester, {
  List<int> fireTimeline = const <int>[],
}) async {
  if (fireTimeline.isEmpty) {
    // 一枪不发：按 500ms 步进推进整窗 —— 与纯 sim 搜索（_replayNoFire）
    // **逐帧同源**。🔴 不能一次 pump(31s)：sim 在单大步下会先处理
    // (30s, 31s] 视界内的「到门口」事件、后判窗口到点（事件循环在撤退
    // 判定之前），等于让刚超时的怪也偷一笔 —— 生产是 ~16ms 小帧，收场
    // 恒发生在跨过 30s 的那一帧；测试分段必须与搜索一致才可逐位互证。
    for (int i = 0; i < 62; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  } else {
    int last = 0;
    for (final int t in fireTimeline) {
      await tester.pump(Duration(milliseconds: t - last));
      last = t;
      // 🔴 终局横幅一上屏就停手：时间线表是按 30s 窗口铺的，全灭战局会在中途
      // 就收场；继续按表点下去，点到的已经是**宝箱演出的全屏热区**（overlay 在
      // 最上层），会把宝箱提前打开 ⇒ 后面的「点宝箱开箱」步骤就落在 opening 态。
      if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) break;
      // 🔴 B7：开火入口从「卡内大圆钮」改成「页面右上阳光胶囊」
      // （胶囊在守卫战期间冻结并接管开火，见 child_today_page）。
      await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey),
          warnIfMissed: false);
    }
  }
  await _pumpUntil(tester, find.byKey(GuardBattleField.bannerKey));
  // 横幅 ~900ms 后交回页面：落账 + 宝箱演出 + 结算卡。
  await tester.pump(const Duration(milliseconds: 1000));
  await awaitOpenChestAndResult(tester);
  return dayKey(DateTime.now());
}

/// 点「收下」并等今日页回到前台（claim + 刷新链路走完）。
Future<void> _collectAndSettle(WidgetTester tester) async {
  await tester.tap(find.byKey(GuardResultCard.collectButtonKey));
  await _pumpUntil(tester, find.byType(ChildTodayPage));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ═══════════════════════════════════════════════════════════════════════

/// 注入「被偷行写不进去」的账本：`guard_stolen` 的 append 抛异常。
///
/// 🔴 走的是**领域层**的真实失败路径：`GuardService._appendLedger` 吞掉写异常
/// 回 false ⇒ `recordBattleTheft` 返回 0 —— 生产里「存储崩了」就是这样表现，
/// 页面的 try/catch（读判定 / 余额抛异常那条路）只是第二道保险。
class _ThrowingStolenLedger extends SunlightLocalRepository {
  _ThrowingStolenLedger(super.db, {super.account});

  /// `guard_stolen` 的写尝试次数（断言「无第二次扣减尝试」）。
  int stolenAppendAttempts = 0;

  @override
  Future<double> append(SunlightEntry entry) async {
    if (entry.refType == kGuardStolenRefType) {
      stolenAppendAttempts++;
      throw StateError('注入：guard_stolen 写入失败');
    }
    return super.append(entry);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 未开火惩罚必达：卡面恒 −3、账本恒扣 3（C120-13）────────────────
  group('① 未开火惩罚必达（C120-13）：阳光卡 −3、被偷行恒渲染、账本恒 −3', () {
    testWidgets('未开火战局（sim 被偷 2 的局）⇒ 卡面「被偷菜贼偷走了 3 阳光」+ 失败标题、账本 −3、收下不发必得',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final (String childId, int stolen) = _findStolenChild(today);
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env); // 有能量 ⇒ 免费路径
      await _seedBalance(env, 10); // 余额充足 ⇒ 实扣 = 惩罚全额 3
      await _pumpToday(tester, env);
      await _startBattle(tester);

      // ── B13.27 增量：胶囊教学气泡（首场必显示 + 可见性钉死）──────────
      // 时序复核：全新 prefs ⇒ 计数 0 < kGuardPillTeachMaxBattles(3) ⇒ 开战
      // 判定显示（无 off-by-one：计数只在结算时 +1）—— **首场必显示**。
      // 可见性：气泡 Text 在树中渲染（页面 Stack 无裁剪层覆盖它 —— 胶囊之后
      // 声明的兄弟仅左上角徽章 Positioned，几何不重叠；场景卡在底层 ListView
      // 内、绘制先于胶囊），且矩形完整落在屏幕内、位于胶囊**下方**。
      {
        final Finder teach = find.text(
            '点这个阳光胶囊，帮向日葵战士发射阳光打跑小偷！');
        expect(teach, findsOneWidget,
            reason: '🔴 首场（prefs 计数 0）战斗态必显示胶囊教学气泡');
        final RenderBox teachBox = tester.renderObject<RenderBox>(teach);
        final Offset teachTopLeft = teachBox.localToGlobal(Offset.zero);
        final Size teachSize = teachBox.size;
        final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(teachTopLeft.dx, greaterThanOrEqualTo(0),
            reason: '气泡左缘不越屏');
        expect(teachTopLeft.dx + teachSize.width, lessThanOrEqualTo(screen.width),
            reason: '气泡右缘不越屏（B13.27 锚定复核）');
        expect(teachTopLeft.dy + teachSize.height, lessThanOrEqualTo(screen.height),
            reason: '气泡完整落在屏内（页面 Stack 无裁剪截断）');
        // 位置：气泡在胶囊**下方**（B13.27 改版口径），水平与胶囊重叠（箭头对齐）。
        final RenderBox capsuleBox =
            tester.renderObject<RenderBox>(find.byKey(ChildTodayPage.sunBubbleKey));
        final Offset capsuleTopLeft = capsuleBox.localToGlobal(Offset.zero);
        expect(teachTopLeft.dy, greaterThan(capsuleTopLeft.dy + capsuleBox.size.height),
            reason: '🔴 B13.27：气泡必须显示在胶囊下方（玄参「更醒目 + 移到下方」）');
        expect(
          teachTopLeft.dx < capsuleTopLeft.dx + capsuleBox.size.width &&
              teachTopLeft.dx + teachSize.width > capsuleTopLeft.dx,
          isTrue,
          reason: '气泡与胶囊水平重叠（箭头指向胶囊）',
        );
      }

      await _runBattleToResultCard(tester);

      // 🔴 B13.27 增量（C120-13「惩罚必达」）：未开火 = 固定罚金 kGuardWinSunMin，
      //    **与 sim 被偷值无关**（本局 sim 被偷 2 也恒扣 3）—— 无视当日互斥 /
      //    封顶；标题切失败态（guard_result_title_defeat）。
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '🔴 未开火场标题 = 失败文案，不再显示「花园守卫成功」误导');
      expect(find.text('被偷菜贼偷走了 3 阳光'), findsOneWidget,
          reason: '🔴 惩罚恒 3（sim 实际被偷 $stolen 不影响卡面）');

      // 🔴 账本恒 −3（recordNoFirePenalty；refType 仍 guard_stolen 报表口径）。
      final double stolenNet =
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, today);
      expect(stolenNet, -kGuardWinSunMin.toDouble(),
          reason: '惩罚必达：账本恒扣 3（余额充足时实扣 = 全额）');
      expect(await env.penaltyRowsOnDay(today), 1,
          reason: '惩罚行恰 1 行（_p0 序号；refId=garden_penalty 分流）');

      // B13.26（玄参 2026-11-16）：本战局**一枪不发**（无 fireTimeline）⇒
      // 收下也不发必得阳光（被怪偷走了）—— guard_win 账本 0 行。
      await _collectAndSettle(tester);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0,
          reason: '🔴 未开火场不发必得阳光（B13.26）');
    });
  });

  // ── ② 封顶（开火场口径）：名义被偷 > 3 ⇒ 卡面 3、账本 3 ────────────────
  // 🔴 B13.27 增量（C120-13）：「每天最多被偷一次 / 封顶 3」只对**开火场**
  // 生效；未开火场已改走固定惩罚（①），本组战局虽仍未开火构造，但数值上
  // 惩罚恒 3 与封顶值巧合相等 —— 断言保留（数值防线不放松），语义见 C120-13。
  group('② 封顶：名义被偷合计 > 3 ⇒ 卡面 3、账本 3', () {
    testWidgets('触顶战局：卡面与账本都钳在 kGuardStealDailyCap',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final String childId = _findCappedChild(today);
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _seedBalance(env, 10);
      await _pumpToday(tester, env);
      await _startBattle(tester);
      await _runBattleToResultCard(tester);

      // 🔴 字面量 3 = 封顶常量（设计 §4.2 初值 = 3，改参须有意更新本值）：
      //    未开火场（C120-13）走固定惩罚恒扣 3 —— 卡面/账本都只能是 3。
      expect(find.text('被偷菜贼偷走了 3 阳光'), findsOneWidget,
          reason: '名义被偷 > 3 ⇒ 卡面必须钳在 3（不许出现 4/5）');
      final double stolenNet =
          await env.ledger.netByRefTypeOnDay(kGuardStolenRefType, today);
      expect(stolenNet, -3.0,
          reason: '账本实扣同样钳在 3');
      expect(await env.penaltyRowsOnDay(today), 1);

      // B13.26：本战局一枪不发 ⇒ 收下也不发必得阳光（guard_win 0 行）。
      await _collectAndSettle(tester);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0);
    });
  });

  // ── ③ 无怪到门口：被偷行不渲染、账本 0 行 ──────────────────────────────
  group('③ 无怪到门口：被偷行不渲染、guard_stolen 0 行', () {
    testWidgets('全灭战局（种子受控）：卡上没有「偷走」句式、账本零新增',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final (String childId, List<int> timeline) = _findWinningChild(today);
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _seedBalance(env, 10); // 故意给余额：若有怪到门口就会写下被偷行
      await _pumpToday(tester, env);
      await _startBattle(tester);
      await _runBattleToResultCard(tester, fireTimeline: timeline);

      // 🔴 「偷走 0 阳光」与「券还能省 0 阳光」同罪 —— 0 时整行不渲染。
      expect(find.textContaining('偷走'), findsNothing,
          reason: '🔴 全灭 = 零被偷 ⇒ 被偷行必须整行不渲染');
      expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today), 0,
          reason: 'recordBattleTheft(0) 空操作 ⇒ 账本零新增');

      await _collectAndSettle(tester);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 1);
    });
  });

  // ── ⑤ 经济守恒探针 ────────────────────────────────────────────────────
  group('⑤ 经济守恒：未开火场零发放、惩罚恒扣 3、不倒贴（C120-13）', () {
    testWidgets('免费路径 + 未开火：guard_stolen（惩罚）恰一行 −3、guard_win 0 行',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final (String childId, int stolen) = _findStolenChild(today); // 任意未开火局
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env);
      const double seeded = 10;
      await _seedBalance(env, seeded);
      await _pumpToday(tester, env);
      await _startBattle(tester);
      await _runBattleToResultCard(tester);
      await _collectAndSettle(tester);

      // 守卫账本行数：免费路径无 guard_pay；一枪不发 ⇒ 无 guard_win；
      // 恰好 1 行（惩罚）。
      final int winRows = await env.ledgerRowsOnDay(kGuardWinRefType, today);
      final int stolenRows = await env.penaltyRowsOnDay(today);
      final int payRows = await env.ledgerRowsOnDay(kGuardPayRefType, today);
      expect(winRows, 0, reason: '🔴 B13.26：未开火场不发必得阳光');
      expect(stolenRows, 1, reason: '惩罚行恰好一行');
      expect(payRows, 0, reason: '免费路径不得有 guard_pay');
      expect(winRows + stolenRows + payRows, 1,
          reason: '🔴 守卫账本行数恰为 1（未开火场：只有惩罚行）');

      // 余额守恒：只罚、零发放 —— 10 − 3（惩罚必达，C120-13），绝不倒贴。
      expect(await env.ledger.balance(), closeTo(seeded - kGuardWinSunMin, 1e-9),
          reason: '余额 = 种子 $seeded − 惩罚 3（sim 被偷 $stolen 不影响数额；未开火无进账）');
    });
  });

  // ── ⑥ 落账失败注入：store 抛异常 ⇒ 结算卡照常弹出、无第二次扣减 ────────
  group('⑥ 落账失败注入（guard_stolen 写入抛异常）', () {
    testWidgets('结算卡照常弹出（未开火惩罚卡面恒 −3）、写尝试恰好 1 次、收下不发奖',
        (WidgetTester tester) async {
      final String today = dayKey(DateTime.now());
      final (String childId, int stolen) = _findStolenChild(today);
      final _Env env = await _makeEnvWithChild(childId);
      await _seedPlant(env);
      await _seedValidFocus(env);
      await _seedBalance(env, 10); // 余额充足：若写入成功本应落 −3
      final _ThrowingStolenLedger ledger =
          _ThrowingStolenLedger(env.database, account: env.account);
      await _pumpToday(
        tester,
        env,
        overrides: <Override>[
          sunlightRepositoryProvider.overrideWithValue(ledger),
        ],
      );
      await _startBattle(tester);
      await _runBattleToResultCard(tester);

      // 🔴 落账失败不阻断：结算卡照常弹出（孩子不多看一张卡，也不被卡死）。
      //    🔴 C120-13 拍板取舍：未开火场惩罚是**确定性罚金** ⇒ 落账失败时
      //    卡面仍**恒 −3 + 被偷行恒渲染**（「卡面==账本」契约仅此未开火场景
      //    让步，见 recordNoFirePenalty 文档与口径表）。
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '🔴 未开火场标题 = 失败文案');
      expect(find.text('被偷菜贼偷走了 3 阳光'), findsOneWidget,
          reason: '🔴 惩罚必达：落账失败也恒显示 −3（C120-13）');
      expect(await env.ledgerRowsOnDay(kGuardStolenRefType, today), 0,
          reason: '写入失败 ⇒ 账本零新增（无半截行）');

      // 🔴 无第二次扣减尝试：整条流程对 guard_stolen 的写尝试恰好 1 次
      //    （页面吞掉失败后不重试；收下路径也不补写）。
      expect(ledger.stolenAppendAttempts, 1,
          reason: '🔴 recordNoFirePenalty 恰好一次写尝试，绝不重试');

      // 收下流程照常走完（失败被吞不影响 claim 主链路）；一枪不发 ⇒
      // 不发必得阳光（B13.26），guard_win 0 行。
      await _collectAndSettle(tester);
      expect(await env.ledgerRowsOnDay(kGuardWinRefType, today), 0,
          reason: '🔴 B13.26：未开火场不发必得阳光');
      expect(ledger.stolenAppendAttempts, 1,
          reason: '收下后仍无第二次扣减尝试');
    });
  });
}
