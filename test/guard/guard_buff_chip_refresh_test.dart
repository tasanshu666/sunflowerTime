/// 花园页 buff 胶囊「守卫存档被改写后是否可靠刷新」回归（玄参真机第 ③ 条）。
///
/// 真源：玄参 2026-11-09 原话「在今日页面，守卫完成后，刷出来浇水券，在花园
/// 页面的左上角，第一次刷出来显示了，删除内存，再刷出来一次，花园左上角又不显示了」。
///
/// 🔴 本文件是**红测试**：先用真实 [GardenPage] + 真实 [BloomDebugSheet] 的守卫
/// 按钮把现象复现出来，再改产品代码。夹具照抄
/// `test/guard/guard_voucher_garden_wiring_test.dart`（`_hostGarden` /
/// `_FakeGuardStore` / `_pumpUntil`）；花园页木牌有无限动画，一律**有界 pump**，
/// 禁止 `pumpAndSettle`。
///
/// 5 个场景：
///  1. 首屏存档已有浇水券 ⇒ chip 可见（基线绿）；
///  2. 点「清空今日守卫存档」⇒ chip 消失（基线绿）；
///  3. 再点「发免费浇水券」⇒ chip **必须重新出现**（玄参报的就是这条）；
///  4. 快速连点两个守卫按钮（并发 `_reload`）⇒ 最终 chip 与**最后一次**存档一致；
///  5. GardenPage 卸载再重新挂载（杀进程重进），存档里有券 ⇒ 首帧 chip 出现。
library guard_buff_chip_refresh_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';

import '../helpers/no_hit_random.dart';

// ── 常量 ─────────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

String _todayKey() => dayKey(DateTime.now());

/// 造「今日已领取，buff = 指定券」的存档。
GuardDayState _guardDay(GuardDropKind kind, {int quota = 0}) => GuardDayState(
      dayKey: _todayKey(),
      status: GuardDayStatus.claimed,
      dropKind: kind,
      buff: GuardBuffState(kind: kind, quota: quota),
    );

// ── Fake：守卫存档（内存，忽略 childId）─────────────────────────────────────

class _FakeGuardStore implements GuardStateStore {
  _FakeGuardStore([this.state]);

  GuardDayState? state;
  int writeCount = 0;

  @override
  Future<GuardDayState> read(String childId) async =>
      state ?? GuardDayState.empty(_todayKey());

  @override
  Future<void> write(String childId, GuardDayState next) async {
    state = next;
    writeCount++;
  }

  @override
  Future<void> clear(String childId) async {
    state = null;
  }
}

// ── Fake：阳光账本 ──────────────────────────────────────────────────────────

class _MemLedger implements SunlightRepository {
  double balanceValue = 1000;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    balanceValue += entry.net;
    return balanceValue;
  }

  @override
  Future<double> balance() async => balanceValue;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;

  @override
  Future<double> dayNet(String key) async => 0;
  @override
  Future<double> earnGrossOnDay(String key) async => 0;
  @override
  Future<double> earnNetOnDay(String key) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String key) async =>
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
}

// ── Fake：其余仓储 ──────────────────────────────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this.capacity);
  final int capacity;

  @override
  Future<AppSettings> getSettings() async => AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: capacity,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemPlantRepo implements PlantRepository {
  _MemPlantRepo(this._store);
  final List<Plant> _store;

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(_store);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in _store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    final int i = _store.indexWhere((Plant p) => p.id == plant.id);
    if (i >= 0) {
      _store[i] = plant;
    } else {
      _store.add(plant);
    }
  }

  @override
  Future<void> deletePlant(String id) async =>
      _store.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

List<Plant> _plants(int n) {
  final DateTime now = DateTime.now();
  return List<Plant>.generate(
    n,
    (int i) => Plant(
      id: 'p$i',
      speciesId: _sunflower.id,
      potIndex: i,
      stage: PlantStage.sprout,
      stageStartedAt: now.subtract(const Duration(hours: 2)),
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now.subtract(const Duration(hours: 2)),
      lastWaterAt: now.subtract(const Duration(days: 2)),
    ),
  );
}

// ── 宿主 ────────────────────────────────────────────────────────────────────

/// 真实 [GardenPage] 宿主；`guardStateStoreProvider` 指向外部持有的 [_FakeGuardStore]，
/// 故跨多次 `pumpWidget` 重挂仍共享同一份存档。
Widget _hostGarden({
  required _MemLedger ledger,
  required _MemPlantRepo plants,
  required _FakeGuardStore store,
  int capacity = 4,
}) {
  return ProviderScope(
    overrides: <Override>[
      entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo(capacity)),
      sunlightRepositoryProvider.overrideWithValue(ledger),
      focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
      plantRepositoryProvider.overrideWithValue(plants),
      guardStateStoreProvider.overrideWithValue(store),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      plantGrowthServiceProvider.overrideWith((Ref ref) => PlantGrowthService(
            plants: ref.watch(plantRepositoryProvider),
            focus: ref.watch(focusRepositoryProvider),
            ledger: ref.watch(sunlightRepositoryProvider),
            settings: ref.watch(settingsRepositoryProvider),
            bloomRewards: ref.watch(bloomRewardRepositoryProvider),
            weedRandom: NoHitRandom(),
          )),
    ],
    child: const MaterialApp(
      home: Scaffold(body: GardenPage(embedded: true)),
    ),
  );
}

// ── 工具 ────────────────────────────────────────────────────────────────────

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

bool _chipOn() => find.byKey(GuardBuffChip.chipKey).evaluate().isNotEmpty;

/// 打开真实调试面板，并把守卫区块（在 ListView **末尾**）滚进视口。
Future<void> _openDebugPanel(WidgetTester tester) async {
  final bool entryShown = await _pumpUntil(
    tester,
    () => find.byType(BloomDebugEntry).evaluate().isNotEmpty,
  );
  expect(entryShown, isTrue, reason: 'debug 下花园页应出现「花期调试」入口');
  await tester.tap(find.byType(BloomDebugEntry));
  await _pumpUntil(
    tester,
    () => find.byType(BloomDebugSheet).evaluate().isNotEmpty,
  );
  // bottom sheet 入场滑入动画（有限时长）：不 pump 够按钮还在屏幕外，tap 会落空。
  await tester.pump(const Duration(milliseconds: 400));

  final Finder list = find.descendant(
    of: find.byType(BloomDebugSheet),
    matching: find.byType(ListView),
  );
  // 🔴 `find.text` 命中不等于「可点」：守卫区块在 ListView 末尾，懒构建出来后
  // 仍可能落在屏幕外（getCenter 越界 → tap 只命中 root，是假红）。用
  // `dragUntilVisible` 反复拖到 **hitTestable**（可命中）为止。
  await tester.dragUntilVisible(
    find.text('清空今日守卫存档'),
    list,
    const Offset(0, -200),
    maxIteration: 40,
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('清空今日守卫存档'), findsOneWidget,
      reason: '守卫区块应能被滚进视口（列表末尾，别挪位置）');
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // 1 · 首屏已有券 ⇒ chip 可见（基线绿）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('1 · 首屏存档已有浇水券 ⇒ GuardBuffChip 可见',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));

    expect(
      await _pumpUntil(tester, _chipOn),
      isTrue,
      reason: '首屏 _reload 读到今日券 ⇒ 左上角 chip 应渲染',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2 · 清空今日守卫存档 ⇒ chip 消失（基线绿）
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('2 · 点「清空今日守卫存档」⇒ chip 消失',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));
    expect(await _pumpUntil(tester, _chipOn), isTrue, reason: '前置：首屏有券');

    await _openDebugPanel(tester);
    await tester.tap(find.text('清空今日守卫存档'));

    final bool gone = await _pumpUntil(tester, () => !_chipOn());
    expect(gone, isTrue, reason: '清档后花园页应重读存档 ⇒ chip 消失');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3 · 玄参报的那条：清档后再发券 ⇒ chip 必须重新出现
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('3 · 清档后再点「发免费浇水券」⇒ chip 必须重新出现（玄参 ③）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));
    expect(await _pumpUntil(tester, _chipOn), isTrue, reason: '前置：第一次刷出来显示了');

    await _openDebugPanel(tester);
    // ① 删除内存（清空今日守卫存档）⇒ chip 消失。
    await tester.tap(find.text('清空今日守卫存档'));
    expect(await _pumpUntil(tester, () => !_chipOn()), isTrue,
        reason: '前置：清档后 chip 消失');

    // ② 再刷出来一次：同一面板里点「发免费浇水券」。
    await tester.tap(find.text('发免费浇水券'));
    // 存档确实被写回一张券（与 UI 无关的独立事实源）。
    expect(
      await _pumpUntil(
        tester,
        () => store.state?.buff?.kind == GuardDropKind.freeWater,
      ),
      isTrue,
      reason: '发券动作应把免费浇水券写回守卫存档',
    );

    // 🔴 玄参报的现象：第二次刷出来，花园左上角又不显示。
    expect(
      await _pumpUntil(tester, _chipOn),
      isTrue,
      reason: '守卫存档被重新写入券后，花园页左上角 chip 必须重新出现',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3b · 玄参「第二次刷出来不显示」的**快速操作**版：清档后不等 chip 消失就再发券
  //      （真机是连续点，两次 fire-and-forget _reload 因而并发）。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('3b · 清档后快速再发券 ⇒ chip 必须重新出现（玄参 ③ 快速版）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));
    expect(await _pumpUntil(tester, _chipOn), isTrue, reason: '前置：第一次显示了');

    await _openDebugPanel(tester);
    await tester.tap(find.text('清空今日守卫存档'));
    // 只等「清档」这一动作收尾（_busy 复位、按钮重新可点），**不**等 chip 消失
    // ⇒ 清档的 _reload 与发券的 _reload 并发（fire-and-forget、无代次保护）。
    await _pumpUntil(
      tester,
      () {
        final Finder f = find.widgetWithText(FilledButton, '发免费浇水券');
        if (f.evaluate().isEmpty) return false;
        return tester.widget<FilledButton>(f).onPressed != null;
      },
      maxFrames: 60,
    );
    await tester.tap(find.text('发免费浇水券'));

    expect(
      await _pumpUntil(
        tester,
        () => store.state?.buff?.kind == GuardDropKind.freeWater,
      ),
      isTrue,
      reason: '发券动作必须真的执行（把 freeWater 券写回存档）',
    );
    expect(
      await _pumpUntil(tester, _chipOn),
      isTrue,
      reason: '守卫存档重新有券 ⇒ 花园左上角 chip 必须出现（玄参 ③）',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4 · 快速连点两个守卫按钮（模拟并发 _reload）⇒ 与最后一次存档一致
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('4 · 快速连点两个发券按钮 ⇒ chip 与最后一次存档一致',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));
    expect(await _pumpUntil(tester, _chipOn), isTrue);

    await _openDebugPanel(tester);
    // 连点：先劳动券、后免费浇水券，中间只推进极少帧 ⇒ 两次 _reload 可能并发。
    await tester.tap(find.text('发劳动券'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('发免费浇水券'));

    // 充分推进，让所有 `_reload`（含 revision bump 触发的那次）都落地。
    await _pumpUntil(tester, _chipOn, maxFrames: 200);
    await _pumpUntil(tester, () => false, maxFrames: 40);
    expect(_chipOn(), isTrue, reason: '最终 chip 必须仍在屏上');
    final GuardBuffChip chip =
        tester.widget<GuardBuffChip>(find.byType(GuardBuffChip));
    final GuardDropKind? finalKind = store.state?.buff?.kind;
    expect(finalKind, isNotNull, reason: '存档里应有一张券');
    // 🔴 不预设「最后一次是哪张券」：修法把 `onChanged` 改成可 await 后，快速
    // 连点的第二个动作可能被 `_busy` 挡成串行（只有第一次生效），此时最终存档
    // 就是第一次那张。无论哪种，**chip 显示的券必须与最终存档同源**，绝不能
    // 停在旧代次（旧实现里 chip=laborVoucher 而 store=freeWater ⇒ 红）。
    expect(chip.buff.kind, finalKind,
        reason: 'chip 显示的券必须与最终存档同源（不得停在旧代次）');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6 · 根因场景：存档被「没有 onChanged 通道」的入口改写（真机即今日页
  //     `claim()`），入口按协议发出守卫修订通知 ⇒ 花园页 chip 必须跟随。
  //     旧实现里花园页不 watch 任何守卫 provider、修订号也无人听 ⇒ 通知落空，
  //     chip 停在旧快照 —— 这就是玄参「今日页守卫完成刷出券，花园左上角不显示」。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('6 · 无 onChanged 通道的入口写存档 + 修订通知 ⇒ chip 必须跟随',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _FakeGuardStore store = _FakeGuardStore(); // 今天还没有券
    await tester.pumpWidget(_hostGarden(
      ledger: _MemLedger(),
      plants: _MemPlantRepo(_plants(1)),
      store: store,
    ));
    expect(await _pumpUntil(tester, () => !_chipOn()), isTrue,
        reason: '前置：今天还没券，chip 不在屏上');

    // 模拟「今日页 claim() 落券」：直接写守卫存档（今日页没有调试面板那种
    // onChanged 回调），随后入口按协议 bump `guardBuffRevisionProvider`。
    store.state = _guardDay(GuardDropKind.waterVoucher, quota: 6);
    store.writeCount++;
    final BuildContext ctx = tester.element(find.byType(GardenPage));
    ProviderScope.containerOf(ctx, listen: false)
        .read(guardBuffRevisionProvider.notifier)
        .state++;

    expect(
      await _pumpUntil(tester, _chipOn),
      isTrue,
      reason: '修订通知必须驱动花园页重读存档 ⇒ chip 出现'
          '（旧实现无人听修订号 ⇒ 停在旧快照，红）',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5 · 卸载 GardenPage 再重挂（模拟杀进程重进）⇒ 首帧 chip 出现
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('5 · 整体卸载再重新挂载，存档有券 ⇒ 首帧 chip 出现',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_plants(1));
    final _FakeGuardStore store =
        _FakeGuardStore(_guardDay(GuardDropKind.waterVoucher, quota: 6));

    await tester.pumpWidget(
        _hostGarden(ledger: ledger, plants: plants, store: store));
    expect(await _pumpUntil(tester, _chipOn), isTrue, reason: '前置：首挂有券');

    // 卸载整棵子树（GardenPage dispose）。
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_chipOn(), isFalse, reason: '卸载后 chip 自然不在屏上');

    // 重挂：新的 ProviderScope，但 store 是外部同一实例（存档仍在）。
    await tester.pumpWidget(
        _hostGarden(ledger: ledger, plants: plants, store: store));
    expect(
      await _pumpUntil(tester, _chipOn),
      isTrue,
      reason: '重进首帧 initState._reload 应读到存档里的券 ⇒ chip 出现',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7 · 🔴 真机等价链路（玄参 2026-11-09 晚间复现仍未修）：**真实
  //     `GuardStatePrefsStore`（SharedPreferences mock）+ 真实 `GuardService`
  //     完整领域链（清档 → expire → resolve → markFighting → claim）+ 花园页在
  //     IndexedStack 后台保活（不经过调试面板 onChanged）** ⇒ 领取后 bump 修订号，
  //     chip 必须出现。现有场景 6 用的是内存 fake store，抓不到「真实存储层」
  //     或「IndexedStack 保活」这一层的丢失。
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets(
      '7 · IndexedStack 后台保活 + 真实 prefs 存储 + 真实领域链 ⇒ claim 后 chip 出现',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final GuardStatePrefsStore realStore = GuardStatePrefsStore(prefs);

    final _MemLedger ledger = _MemLedger();
    final _MemPlantRepo plants = _MemPlantRepo(_plants(1));
    final _NoFocusRepo focus = _NoFocusRepo();
    final _FakeSettingsRepo settings = _FakeSettingsRepo(12);
    const String childId = 'child_t7';
    final PlantGrowthService growth = PlantGrowthService(
      plants: plants,
      focus: focus,
      ledger: ledger,
      settings: settings,
      bloomRewards: InMemoryBloomRewardRepository(),
      weedRandom: NoHitRandom(),
    );
    final GuardService guard = GuardService(
      store: realStore,
      ledger: ledger,
      focus: focus,
      plants: plants,
      growth: growth,
      childId: () => childId,
    );

    final ValueNotifier<int> tabIndex = ValueNotifier<int>(1); // 1 = 花园在台前
    addTearDown(tabIndex.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
          settingsRepositoryProvider.overrideWithValue(settings),
          sunlightRepositoryProvider.overrideWithValue(ledger),
          focusRepositoryProvider.overrideWithValue(focus),
          plantRepositoryProvider.overrideWithValue(plants),
          bloomRewardRepositoryProvider
              .overrideWithValue(InMemoryBloomRewardRepository()),
          plantGrowthServiceProvider.overrideWithValue(growth),
          guardStateStoreProvider.overrideWithValue(realStore),
          // 🔴 guard / voucher 两个服务**共用同一个真实 store + 同一个 childId**
          //    （与生产 `providers.dart` 同源口径：都读 accountServiceProvider）。
          guardServiceProvider.overrideWithValue(guard),
          guardVoucherProvider.overrideWith((Ref ref) => GuardVoucherService(
                store: ref.watch(guardStateStoreProvider),
                childId: () => childId,
              )),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: tabIndex,
            builder: (_, int i, __) => IndexedStack(
              index: i,
              children: const <Widget>[
                // 0 = 今日页等其它 tab 的替身（花园页在后台保活）。
                Scaffold(body: SizedBox.shrink()),
                GardenPage(embedded: false),
              ],
            ),
          ),
        ),
      ),
    );
    expect(await _pumpUntil(tester, () => !_chipOn()), isTrue,
        reason: '前置：真实 prefs 是空的，chip 不在屏上');

    // 模拟「孩子切去今日页」：花园页进入 IndexedStack 后台（仍 mounted、仍监听）。
    tabIndex.value = 0;
    await tester.pump(const Duration(milliseconds: 16));

    // 真实领域链（与今日页 `_loadGuardView` / `_onGuardPillTap` 逐环等价）：
    // 清档 → expire → resolve → 造带券的 pending → markFighting → claim。
    await guard.resetForDebug();
    await guard.expire();
    await guard.resolve();
    await guard.forceThiefForDebug(drop: GuardDropKind.waterVoucher);
    await guard.markFighting();
    final GuardClaimOutcome outcome = await guard.claim();
    expect(outcome.ok, isTrue, reason: 'claim 失败 ⇒ 真机现象的另一半可能');
    expect(outcome.buff, isNotNull, reason: 'claim 必须落 buff（领域层断言）');

    // 🔴 IndexedStack 的非活动子树对默认 finder 是 offstage（`skipOffstage: true`
    //    是默认值）——后台阶段的判定一律 `skipOffstage: false`。
    final GuardBuffState? storedBuff =
        (await realStore.read(childId)).buff;
    expect(storedBuff, isNotNull, reason: 'claim 后真实 prefs 里必须有 buff');

    // 模拟今日页 `outcome.ok` 后的两个 bump（`child_today_page.dart` 的接线）。
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(GardenPage, skipOffstage: false)),
      listen: false,
    );
    container.read(economyRevisionProvider.notifier).state++;
    container.read(guardBuffRevisionProvider.notifier).state++;

    // 充分推进：花园页在后台完成 listen → _reload → _guardBuff = buff。
    final Finder deepChip =
        find.byKey(GuardBuffChip.chipKey, skipOffstage: false);
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (deepChip.evaluate().isNotEmpty) break;
    }
    expect(deepChip.evaluate().isNotEmpty, isTrue,
        reason: '真实存储 + 后台保活下，claim 后 chip 也必须被挂上树'
            '（红 ⇒ 真机根因在这一层，不在领域层）');

    // 孩子切回花园 tab → onTabRefreshRequested → 再次 reload ⇒ chip 可见。
    tabIndex.value = 1;
    await _pumpUntil(tester, _chipOn, maxFrames: 200);
    expect(_chipOn(), isTrue, reason: '切回花园后 chip 必须在屏上');
  });
}
