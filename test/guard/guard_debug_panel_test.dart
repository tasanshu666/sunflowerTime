/// 花园守卫 · **调试面板**回归测试（第四批 B；B5a 追加强制剧本按钮组）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` + 第四批 B 施工图纸 +
/// 守卫战设计文档 §7-B5（调试行）。
///
/// ## 本文件钉死的条目
///  1. 面板末尾有「花园守卫」分组与 7 个按钮（**先滚动再断言**：区块在列表最末尾，
///     写「不滚动就能找到」会随面板增高变红）；
///  2. 点「刷新出偷菜贼」⇒ 领域 `todayState().status == pending`，`onChanged` 被回调；
///  3. 点「用光今日能量」⇒ `energyAvailable() == 0`；
///  4. 点「清空今日守卫存档」⇒ `todayState()` 空白 **且** `guardTodayProvider` 被
///     重置（用 `.isVisible == false` 这种语义判断，不断言具体枚举值）；
///  5. 360×780 打开面板并滚到底不 overflow（防新块做成横向撑破的布局）；
///  6. （B5a）强制剧本按钮组渲染 + provider 覆盖写入 / 清空（战斗行为级断言在
///     `guard_debug_script_test.dart`，本文件只管面板自身）。
///
/// 🔴 纪律：期望值写**字面量**；断言一律走「滚动后」的 `find.text`。
library guard_debug_panel_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';

import '../helpers/no_hit_random.dart';

// ── Fake 仓储 ────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

Plant _sprout() {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: _sunflower.id,
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: now.subtract(const Duration(hours: 2)),
    growthProgress: 0.3,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now.subtract(const Duration(hours: 2)),
    lastWaterAt: now, // 刚浇过水 → 3 天内不会枯萎
  );
}

/// 守卫存档（内存，单孩子：**忽略 childId**）。
///
/// 面板里的 `guardServiceProvider` 用的是 `AccountService.childId`，测试里另建的
/// `GuardService` 用常量 childId —— 忽略 childId 才能保证两者读写同一条存档。
class _GuardStore implements GuardStateStore {
  GuardDayState? state;
  int writeCount = 0;

  @override
  Future<GuardDayState> read(String childId) async =>
      state ?? GuardDayState.empty(dayKey(DateTime.now()));

  @override
  Future<void> write(String childId, GuardDayState next) async {
    state = next;
    writeCount++;
  }

  @override
  Future<void> clear(String childId) async => state = null;
}

class _Ledger implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _Focus implements FocusRepository {
  final Map<String, List<FocusSession>> byDay = <String, List<FocusSession>>{};

  /// 造 [count] 条「有效专注」（25 分钟 / 计划 25 分钟 ⇒ 完成率 100%）。
  void seedValid(int count) {
    final String today = dayKey(DateTime.now());
    byDay[today] = <FocusSession>[
      for (int i = 0; i < count; i++)
        FocusSession(
          id: '$today-v$i',
          start: DateTime.now().subtract(Duration(hours: i + 1)),
          plannedMin: 25,
          actualFocusMin: 25,
          status: FocusStatus.completed,
          sunlightEarned: 0,
          createdAt: DateTime.now().subtract(Duration(hours: i + 1)),
        ),
    ];
  }

  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      byDay[dayKey] ?? const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _Plants implements PlantRepository {
  _Plants(this._plants);
  final List<Plant> _plants;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_plants);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _plants) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    _plants.removeWhere((Plant p) => p.id == plant.id);
    _plants.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      _plants.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

/// 空盆干扰物（无记录）：面板的旁路回显直接降级为「今天还没 roll 过」。
class _Pots implements PotDisturbanceRepository {
  @override
  Future<List<PotDisturbance>> disturbances() async =>
      const <PotDisturbance>[];
  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => null;
  @override
  Future<void> save(PotDisturbance disturbance) async {}
  @override
  Future<void> deletePot(int potIndex) async {}
  @override
  Future<void> deleteAll() async {}
}

// ── 装配 ────────────────────────────────────────────────────────────────────

class _Harness {
  _Harness({int validSessions = 0}) {
    if (validSessions > 0) focus.seedValid(validSessions);
    plants = _Plants(<Plant>[_sprout()]);
  }

  final _GuardStore store = _GuardStore();
  final _Ledger ledger = _Ledger();
  final _Focus focus = _Focus();
  late final _Plants plants;

  /// 断言用服务：与面板**共用同一批 Fake**（store 忽略 childId ⇒ 读到同一条）。
  GuardService get guard => GuardService(
        store: store,
        ledger: ledger,
        focus: focus,
        plants: plants,
        growth: PlantGrowthService(
          plants: plants,
          focus: focus,
          ledger: ledger,
          settings: _Settings(),
          bloomRewards: InMemoryBloomRewardRepository(),
          weedRandom: NoHitRandom(),
        ),
        childId: () => 'test-child',
      );

  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        // 桩 AccountService：`childId` 恒为默认值，且**不**去建真实 DB
        // （`guardServiceProvider` 会读它；无桩时会顺带实例化 drift → 测试噪声）。
        accountServiceProvider.overrideWithValue(AccountService()),
        settingsRepositoryProvider.overrideWithValue(_Settings()),
        sunlightRepositoryProvider.overrideWithValue(ledger),
        focusRepositoryProvider.overrideWithValue(focus),
        plantRepositoryProvider.overrideWithValue(plants),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        guardStateStoreProvider.overrideWithValue(store),
        potDisturbanceRepositoryProvider.overrideWithValue(_Pots()),
        plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
              plants: ref.watch(plantRepositoryProvider),
              focus: ref.watch(focusRepositoryProvider),
              ledger: ref.watch(sunlightRepositoryProvider),
              settings: ref.watch(settingsRepositoryProvider),
              bloomRewards: ref.watch(bloomRewardRepositoryProvider),
              weedRandom: NoHitRandom(),
            )),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }
}

Widget _host(ProviderContainer container,
    {Future<void> Function()? onChanged}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: BloomDebugSheet(maxHeight: 640, onChanged: onChanged),
        ),
      ),
    );

/// 有界帧推进（面板自身无动画，但 `_refresh` 是异步的）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return ready();
}

/// 滚到列表最末尾（守卫区块在末尾，必须滚动才能进懒构建窗口）。
Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('清空今日守卫存档'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// 打开面板并等 `_loaded`（动作按钮出现）。
Future<void> _openPanel(WidgetTester tester, ProviderContainer c,
    {Future<void> Function()? onChanged}) async {
  await tester.pumpWidget(_host(c, onChanged: onChanged));
  final bool ready = await _pumpUntil(
    tester,
    () => find.text('催熟到成株').evaluate().isNotEmpty,
  );
  expect(ready, isTrue, reason: '面板应完成 _refresh 并渲染动作按钮');
  await _scrollToBottom(tester);
}

void main() {
  testWidgets('1) 面板末尾有「花园守卫」分组与 7 个按钮（滚动后可见）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    expect(find.text('花园守卫'), findsOneWidget, reason: '分组标题');
    for (final String label in <String>[
      '刷新出偷菜贼',
      '刷新出偷菜贼（带免费浇水券）',
      '用光今日能量',
      '发免费浇水券',
      '发劳动券',
      '发施肥券',
      '清空今日守卫存档',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少按钮：$label');
    }
  });

  testWidgets('1a) 点「刷新出偷菜贼（带免费浇水券）」⇒ 存档 buff = 免费水券 / 1',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    await tester.tap(find.text('刷新出偷菜贼（带免费浇水券）'));
    final bool written =
        await _pumpUntil(tester, () => h.store.state?.buff != null);
    expect(written, isTrue, reason: '按钮必须把券也发出来（只写 dropKind 用不了）');

    final GuardDayState s = await h.guard.todayState();
    expect(s.dropKind, GuardDropKind.freeWater);
    expect(s.buff!.kind, GuardDropKind.freeWater);
    expect(s.buff!.quota, 1);
  });

  testWidgets('1b) 点「发免费浇水券」⇒ 存档 buff.kind == freeWater、quota == 1',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    await tester.tap(find.text('发免费浇水券'));
    final bool written =
        await _pumpUntil(tester, () => h.store.state?.buff != null);
    expect(written, isTrue);

    final GuardDayState s = await h.guard.todayState();
    expect(s.buff!.kind, GuardDropKind.freeWater);
    expect(s.buff!.quota, 1);
  });

  testWidgets('1c) 点「发劳动券」⇒ 存档 buff.kind == laborVoucher、quota == 4',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    await tester.tap(find.text('发劳动券'));
    final bool written =
        await _pumpUntil(tester, () => h.store.state?.buff != null);
    expect(written, isTrue);

    final GuardDayState s = await h.guard.todayState();
    expect(s.buff!.kind, GuardDropKind.laborVoucher);
    expect(s.buff!.quota, 4);
  });

  testWidgets('1d) 点「发施肥券」⇒ 存档 buff.kind == fertilizeVoucher、quota == 12',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    await tester.tap(find.text('发施肥券'));
    final bool written =
        await _pumpUntil(tester, () => h.store.state?.buff != null);
    expect(written, isTrue);

    final GuardDayState s = await h.guard.todayState();
    expect(s.buff!.kind, GuardDropKind.fertilizeVoucher);
    expect(s.buff!.quota, 12, reason: '施肥券额度 = 最大盆位数（今日每次施肥）');
  });

  testWidgets('2) 点「刷新出偷菜贼」⇒ todayState().status == pending，且 onChanged 被回调',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    int changed = 0;
    await _openPanel(tester, h.container(), onChanged: () async {
      changed++;
    });

    await tester.tap(find.text('刷新出偷菜贼'));
    // 🔴 B10：`forceThiefForDebug` 现在多读一次账本（派生当日场次序号）⇒
    // 存档写入与「_run 收尾的 onChanged」之间多一个微任务。判据改成
    // 「存档已落 + 回调已到」两个都满足，不再只看写入时刻。
    final bool written = await _pumpUntil(
        tester, () => h.store.state != null && changed >= 1);
    expect(written, isTrue, reason: '点按钮后应写入今日存档并回调花园页');

    final GuardDayState s = await h.guard.todayState();
    expect(s.hasThief, isTrue);
    expect(s.status, GuardDayStatus.pending);
    expect(changed, greaterThanOrEqualTo(1), reason: '必须回调花园页刷新');
  });

  testWidgets('3) 点「用光今日能量」⇒ energyAvailable() == 0',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 先造 1 次有效专注，否则「能量 == 0」本来成立，这条测不出东西。
    final _Harness h = _Harness(validSessions: 1);
    await _openPanel(tester, h.container());

    expect(await h.guard.energyAvailable(), 1, reason: '1 次有效专注 = 1 点能量');

    await tester.tap(find.text('用光今日能量'));
    final bool drained =
        await _pumpUntil(tester, () => h.store.state?.energyUsed == 1);
    expect(drained, isTrue, reason: 'energyUsed 应被写成赚到的总量');

    expect(await h.guard.energyAvailable(), 0);
  });

  testWidgets('4) 点「清空今日守卫存档」⇒ 存档空白，且 guardTodayProvider 被重置',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await h.store.write(
      'test-child',
      GuardDayState(
        dayKey: dayKey(DateTime.now()),
        status: GuardDayStatus.pending,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
      ),
    );
    final ProviderContainer c = h.container();
    // 今日页的胶囊快照先摆成「有贼」——否则「清空后是 absent」这条断言是空转的。
    c.read(guardTodayProvider.notifier).state = GuardTodayView(
      mode: GuardPillMode.pendingFree,
      state: GuardDayState(
        dayKey: dayKey(DateTime.now()),
        status: GuardDayStatus.pending,
        thiefKind: GuardThiefKind.sunRat,
      ),
      energyAvailable: 1,
      balance: 10,
    );
    expect(c.read(guardTodayProvider).isVisible, isTrue, reason: '前置条件');

    await _openPanel(tester, c);

    await tester.tap(find.text('清空今日守卫存档'));
    final bool cleared = await _pumpUntil(tester, () => h.store.state == null);
    expect(cleared, isTrue, reason: '存档应被清空');

    final GuardDayState s = await h.guard.todayState();
    expect(s.hasThief, isFalse);
    expect(s.status, GuardDayStatus.none);

    expect(
      c.read(guardTodayProvider).isVisible,
      isFalse,
      reason: '清档后必须主动重置今日页胶囊快照（只有 ChildTodayPage 会写它）',
    );
  });

  testWidgets('5) 360×780 打开面板并滚到底不 overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    await _openPanel(tester, h.container());

    expect(find.text('清空今日守卫存档'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════
  // B5a · 强制剧本按钮组（战斗行为级断言在 guard_debug_script_test.dart）
  // ══════════════════════════════════════════════════════════════════════

  /// 滚到「强制剧本」按钮组（在「清空今日守卫存档」之后）。
  // 命名说明：main 内的**局部函数**不能带 `_` 前缀（lint
  // no_leading_underscores_for_local_identifiers），与顶层/成员函数约定不同。
  Future<void> scrollToScriptButtons(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('强制 3 只怪'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  testWidgets('6) 强制剧本按钮组 5 个 + 生效回显（滚动后可见）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();
    await _openPanel(tester, c);
    await scrollToScriptButtons(tester);

    expect(find.text('强制 3 只怪'), findsOneWidget);
    expect(find.text('强制 5 只怪'), findsOneWidget);
    expect(find.text('强制三怪混编'), findsOneWidget);
    expect(find.text('强制高偷窃战局'), findsOneWidget);
    expect(find.text('恢复随机剧本'), findsOneWidget);
    expect(find.textContaining('跟随真实派生'), findsOneWidget,
        reason: '无覆盖时回显必须是「跟随真实派生」');
    expect(tester.takeException(), isNull);
  });

  testWidgets('6a) 点「强制 5 只怪」⇒ 覆盖写入（5 只）+ 造贼 pending + 回显切换',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();
    await _openPanel(tester, c);
    await scrollToScriptButtons(tester);

    expect(c.read(debugGuardBattleScriptOverrideProvider), isNull,
        reason: '前置：默认无覆盖');

    await tester.tap(find.byKey(const ValueKey<String>(kDebugGuardScriptKeyCount5)));
    final bool written = await _pumpUntil(
      tester,
      () => c.read(debugGuardBattleScriptOverrideProvider) != null,
    );
    expect(written, isTrue, reason: '点按钮后必须写 debugGuardBattleScriptOverrideProvider');

    final GuardBattleScript? s =
        c.read(debugGuardBattleScriptOverrideProvider);
    expect(s!.monsters.length, 5, reason: '🔴 覆盖剧本必须恰 5 只怪');

    // 照抄相邻「刷新出偷菜贼」的收尾：必须顺手造贼（否则覆盖了也打不起来）。
    final GuardDayState st = await h.guard.todayState();
    expect(st.hasThief, isTrue, reason: '强制剧本必须同时造出今日贼（pending）');
    expect(st.status, GuardDayStatus.pending);

    // 回显切换（面板自身 watch provider ⇒ 自动刷新）。
    await _pumpUntil(
      tester,
      () => find.textContaining('显式覆盖中').evaluate().isNotEmpty,
    );
    expect(find.textContaining('跟随真实派生'), findsNothing);
  });

  testWidgets('6b) 点「强制三怪混编」⇒ 覆盖 kinds 恰为 [m1, m2, m3]',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();
    await _openPanel(tester, c);
    await scrollToScriptButtons(tester);

    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyMixed)));
    final bool written = await _pumpUntil(
      tester,
      () => c.read(debugGuardBattleScriptOverrideProvider) != null,
    );
    expect(written, isTrue);

    final GuardBattleScript? s =
        c.read(debugGuardBattleScriptOverrideProvider);
    expect(
      [for (final m in s!.monsters) m.kind],
      <GuardBattleMonsterKind>[
        GuardBattleMonsterKind.m1,
        GuardBattleMonsterKind.m2,
        GuardBattleMonsterKind.m3,
      ],
      reason: '🔴 混编必须走显式覆盖（kind 通道同 seed 强相关，搜不出 —— B3 报告）',
    );
  });

  testWidgets('6c) 点「强制高偷窃战局」⇒ 覆盖全 m1 且 steal 全 3',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();
    await _openPanel(tester, c);
    await scrollToScriptButtons(tester);

    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyTheft)));
    final bool written = await _pumpUntil(
      tester,
      () => c.read(debugGuardBattleScriptOverrideProvider) != null,
    );
    expect(written, isTrue);

    final GuardBattleScript? s =
        c.read(debugGuardBattleScriptOverrideProvider);
    for (final GuardBattleMonsterSpec m in s!.monsters) {
      expect(m.kind, GuardBattleMonsterKind.m1, reason: '全 m1 ⇒ 必有怪到门口');
      expect(m.steal, kGuardStealMax, reason: '偷取顶格（封顶展示素材）');
    }
  });

  testWidgets('6d) 点「恢复随机剧本」⇒ 覆盖清空（provider 回 null）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _Harness h = _Harness();
    final ProviderContainer c = h.container();
    await _openPanel(tester, c);
    await scrollToScriptButtons(tester);

    // 先造一个覆盖（前置条件）。
    await tester.tap(find.byKey(const ValueKey<String>(kDebugGuardScriptKeyCount3)));
    final bool written = await _pumpUntil(
      tester,
      () => c.read(debugGuardBattleScriptOverrideProvider) != null,
    );
    expect(written, isTrue, reason: '前置：覆盖已写入');

    // 「恢复随机剧本」在区块更下方 ⇒ 再滚。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey<String>(kDebugGuardScriptKeyFollow)));
    final bool cleared = await _pumpUntil(
      tester,
      () => c.read(debugGuardBattleScriptOverrideProvider) == null,
    );
    expect(cleared, isTrue, reason: '🔴 恢复随机 ⇒ 覆盖必须清空');
  });
}
