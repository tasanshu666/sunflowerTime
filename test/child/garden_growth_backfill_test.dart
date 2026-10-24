/// F132 · 花园成长过渡「补播」回归测试（玄参 2026-10-19 荣耀平板实测）。
///
/// ## 真机症状
/// 孩子专注约 25 分钟。专注前最后看花园时植物还是**种子**；专注结束回到花园，
/// **直接看到已经是幼芽**，成长过渡序列帧一次都没播。
///
/// ## 根因（本文件守卫的对象）
/// 专注结束 `context.go('/')` 重建整个 `ChildShellPage` → 旧外壳连同 `_GardenPageState`
/// 的内存快照一起销毁 → 新外壳 `IndexedStack` 立刻构建全部 5 个 tab（孩子还停在今日）
/// → 花园页 `initState → _reload → tickAll()` 在这里补结算（seed → sprout）→
/// 内存快照为空 → `prev.isEmpty` 提前 return → 升级被静默吞掉。
///
/// 修法 = 「孩子上次**看到**的阶段」持久化到 SP（按孩子分键）+ 不可见时入队、
/// 可见时才播。本文件逐条钉住这两条。
///
/// ⚠️ 时间戳一律相对 `DateTime.now()`（写死时间戳越过 `kPlantWiltDays` 会被结算成
/// wilting/dead 而误红）。
/// ⚠️ 循环帧禁止 `pumpAndSettle`；本文件的成长演出是一次性动画，但统一用固定次数
/// `pump(Duration)` 推进，避免与被测页面的周期定时器纠缠。
library garden_growth_backfill_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart'
    show GrowTransition;
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';

import '../helpers/no_hit_random.dart';

// ── 假仓储（与 garden_care_repro 同款最小集）──────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 关掉全部音频：本文件只关心「演出有没有上屏」，不接音频平台假实现。
AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 4,
      soundOn: false,
      bgmOn: false,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return 999.0;
  }

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
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == dayKey)
          .length;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.refId == refId &&
              !e.ts.isBefore(since))
          .length;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
      String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType != refType || e.refId != refId) continue;
      if (last == null || e.ts.isAfter(last)) last = e.ts;
    }
    return last;
  }

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _StoringPlantRepository implements PlantRepository {
  _StoringPlantRepository(this.store);
  final List<Plant> store;
  @override
  Future<List<Plant>> plants() async => List<Plant>.of(store);
  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    store.removeWhere((Plant p) => p.id == plant.id);
    store.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      store.removeWhere((Plant p) => p.id == id);
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

/// 固定 childId 的账号服务（多孩子隔离用例用；其余能力保持基类语义）。
class _FixedChildAccount extends AccountService {
  _FixedChildAccount(this._id);
  final String _id;
  @override
  String get childId => _id;
}

// ── 测试植株 ────────────────────────────────────────────────────────────────

/// `stage` 指定阶段、今日已浇水的活株；[progress] 默认 0 → 一次 tick 不会自行推进。
Plant _plant({
  required PlantStage stage,
  PlantStatus status = PlantStatus.growing,
  double progress = 0,
  String id = 'p1',
}) {
  final DateTime now = DateTime.now();
  return Plant(
    id: id,
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: stage,
    stageStartedAt: now,
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: now.subtract(const Duration(hours: 1)),
    lastWaterAt: now,
    bloomedAt: status == PlantStatus.bloomed ? now : null,
    bloomCount: status == PlantStatus.bloomed ? 1 : 0,
    mood: PlantMood.calm,
  );
}

// ── 宿主 ────────────────────────────────────────────────────────────────────

/// 外壳形态：5 个 tab 的 `IndexedStack`，花园在 index 2，隐藏时 `TickerMode(false)`
/// —— 与 `child_shell_page` 的真实结构一致（F132 的可见性判据就靠它）。
class _ShellHost extends ConsumerWidget {
  const _ShellHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int index = ref.watch(childShellTabIndexProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: <Widget>[
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          TickerMode(
            enabled: index == kChildTabIndexOfGarden,
            child: const GardenPage(embedded: true),
          ),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _Harness {
  _Harness({
    required List<Plant> plants,
    required SharedPreferences sp,
    String childId = kChildIdDefault,
  }) : container = ProviderContainer(overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          accountServiceProvider.overrideWithValue(_FixedChildAccount(childId)),
          settingsRepositoryProvider
              .overrideWithValue(_FakeSettingsRepository()),
          sunlightRepositoryProvider
              .overrideWithValue(_FakeSunlightRepository()),
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          plantRepositoryProvider
              .overrideWithValue(_StoringPlantRepository(plants)),
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
        ]);

  final ProviderContainer container;

  /// F138：可见性判据 = 「外壳在台前 **且** tab 索引是本页」。
  ///
  /// 本文件的 `_ShellHost` / 独立挂载都模拟「外壳在台上」，故在装配时显式发布上台
  /// 信号（真实外壳由 `ChildShellPage.initState` 写入）。不写会让 `tabVisible` 恒
  /// false ——「切到花园 tab 才补播」两条用例会假红。
  Widget widget({bool shell = false}) {
    container.read(childShellOnStageProvider.notifier).state = true;
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: shell
            ? const _ShellHost()
            : const Scaffold(body: GardenPage(embedded: true)),
      ),
    );
  }

  void goTab(int index) =>
      container.read(childShellTabIndexProvider.notifier).state = index;

  void bumpEconomy() =>
      container.read(economyRevisionProvider.notifier).state++;

  void dispose() => container.dispose();
}

// ── 推进 / 观测 ─────────────────────────────────────────────────────────────

/// 交替「真实异步窗口（runAsync）+ 假时钟微任务排空（pump）」推进整条链路。
Future<void> _drainUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxRounds = 120,
  int extraRounds = 10,
}) async {
  for (int i = 0; i < maxRounds; i++) {
    if (ready()) break;
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 80));
  }
  for (int i = 0; i < extraRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 边推进边收集 [GrowthFxOverlay] 出现过的**全部 State 实例**（空集 = 一次都没播）。
///
/// 用 State 集合而不是「某一刻 find 到几个」：演出会自然结束消失，逐帧采样才能证明
/// 「期间到底播没播过」。
Future<Set<Object>> _collectOverlays(
  WidgetTester tester, {
  int rounds = 50,
}) async {
  final Set<Object> seen = <Object>{};
  final Finder f = find.byType(GrowthFxOverlay);
  for (int i = 0; i < rounds; i++) {
    if (f.evaluate().isNotEmpty) {
      try {
        seen.add(tester.state(f));
      } catch (_) {
        // 过渡帧：忽略。
      }
    }
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 80));
  }
  return seen;
}

/// 等花园首屏渲染完成（`_reload` + `tickAll` + 各假仓储全部就绪）。
Future<void> _waitGarden(WidgetTester tester) => _drainUntil(
      tester,
      () => find.byType(GardenPot).evaluate().isNotEmpty,
      maxRounds: 90,
    );

/// 把当前演出完整播完（进入 360ms + 播放 4100ms + 淡出 300ms，留足余量）。
Future<void> _finishOverlay(WidgetTester tester) async {
  for (int i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(GrowthFxOverlay), findsNothing,
      reason: '前置：演出应已自然播完并移除');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences sp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sp = await SharedPreferences.getInstance();
  });

  testWidgets('核心守卫：离开期间 seed→sprout，进花园补播一次 seedToSprout',
      (WidgetTester tester) async {
    // 孩子上次看到的 = 种子（专注前最后一眼）。
    await SettingsStore(sp)
        .setLastSeenPlantPhases(<String, String>{'p1': 'seed:growing'},
            childId: kChildIdDefault);

    // 离开期间植物已被结算成幼苗（等价于专注结束返回时库里的状态）。
    final _Harness h = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.widget());
    await _waitGarden(tester);

    final Set<Object> overlays = await _collectOverlays(tester, rounds: 40);
    expect(overlays, isNotEmpty,
        reason: 'F132 核心：上次看到 seed、现在是 sprout → 必须补播一次成长演出'
            '（改前 prev.isEmpty 直接 return，这里恒为空 = 玄参真机症状）');
    expect(find.byType(GrowthFxOverlay), findsOneWidget);

    final GrowthFxOverlay overlay =
        tester.widget<GrowthFxOverlay>(find.byType(GrowthFxOverlay));
    expect(overlay.frames.first, contains('seed_to_sprout'),
        reason: '播的必须是「种子→幼苗」那一段');

    // 播完（发起播放后）快照才推进：下次进来不再重复补播。
    final Map<String, String> after =
        await SettingsStore(sp).lastSeenPlantPhases(childId: kChildIdDefault);
    expect(after['p1'], 'sprout:growing', reason: '可见播放后快照应推进到当前阶段');
  });

  testWidgets('反向：全新植物（快照里没有该 plantId）不补播',
      (WidgetTester tester) async {
    // 空快照 = 首次安装 / 刚种下的新植物，没有「上次看到」的基线。
    final _Harness h = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.widget());
    await _waitGarden(tester);

    final Set<Object> overlays = await _collectOverlays(tester);
    expect(overlays, isEmpty, reason: '首次看到该植物不该播「补播」动画');

    // 但要把它记成「已看到」，否则下一次 reload 会被误判成升级。
    final Map<String, String> after =
        await SettingsStore(sp).lastSeenPlantPhases(childId: kChildIdDefault);
    expect(after['p1'], 'sprout:growing');
  });

  testWidgets('反向：同一阶段重复 reload 只播一次', (WidgetTester tester) async {
    await SettingsStore(sp)
        .setLastSeenPlantPhases(<String, String>{'p1': 'seed:growing'},
            childId: kChildIdDefault);

    final _Harness h = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.widget());
    await _waitGarden(tester);

    expect(await _collectOverlays(tester, rounds: 25), isNotEmpty);
    await _finishOverlay(tester);

    // 再触发一次静默刷新（经济修订号 = 花园页既有刷新通路）→ 快照已相等，不得重播。
    h.bumpEconomy();
    final Set<Object> again = await _collectOverlays(tester, rounds: 40);
    expect(again, isEmpty, reason: '同一阶段重复 reload 不能重播（快照已推进）');
  });

  testWidgets('反向：不可见时不播（入队），切到花园 tab 才播一次',
      (WidgetTester tester) async {
    await SettingsStore(sp)
        .setLastSeenPlantPhases(<String, String>{'p1': 'seed:growing'},
            childId: kChildIdDefault);

    final _Harness h = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
    );
    addTearDown(h.dispose);

    // 外壳默认停在 index 0（今日）——新外壳就是这样把花园页先建出来的。
    await tester.pumpWidget(h.widget(shell: true));
    // 等花园页的 initState._reload 把升级「检测到但入队」（不可见，不写快照）。
    await _drainUntil(tester, () => false, maxRounds: 45);

    expect(await _collectOverlays(tester, rounds: 20), isEmpty,
        reason: '花园 tab 不可见时绝不能播（会演在隐藏页上，孩子仍然看不到）');
    expect(
        await SettingsStore(sp).lastSeenPlantPhases(childId: kChildIdDefault),
        <String, String>{'p1': 'seed:growing'},
        reason: '不可见期间不推进快照 —— 保持「孩子还没看过」的事实');

    // 孩子点「花园」tab。
    h.goTab(kChildTabIndexOfGarden);
    await tester.pump();
    await _drainUntil(tester, () => find.byType(GrowthFxOverlay).evaluate().isNotEmpty,
        maxRounds: 60);

    expect(await _collectOverlays(tester, rounds: 20), isNotEmpty,
        reason: '切到花园后必须把入队的那一次补播出来');
    final GrowthFxOverlay overlay =
        tester.widget<GrowthFxOverlay>(find.byType(GrowthFxOverlay));
    expect(overlay.frames.first, contains('seed_to_sprout'));
  });

  testWidgets('跨级：seed → adult 只播「最接近当前状态」的 sproutToAdult',
      (WidgetTester tester) async {
    await SettingsStore(sp)
        .setLastSeenPlantPhases(<String, String>{'p1': 'seed:growing'},
            childId: kChildIdDefault);

    final _Harness h = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.adult)],
      sp: sp,
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.widget());
    await _waitGarden(tester);

    expect(await _collectOverlays(tester, rounds: 40), isNotEmpty);
    final GrowthFxOverlay overlay =
        tester.widget<GrowthFxOverlay>(find.byType(GrowthFxOverlay));
    expect(overlay.frames.first, contains('sprout_to_adult'),
        reason: '跨级只播最后一段：seed→adult 播 sproutToAdult'
            '（不是 seedToSprout，也不是不播）');
    expect(overlay.title, '长大啦！🌿');
  });

  testWidgets('多孩子隔离：A 的快照不影响 B，各自独立补播',
      (WidgetTester tester) async {
    const String childA = 'child-a';
    const String childB = 'child-b';
    expect(lastSeenPlantPhasesKey(childA),
        isNot(lastSeenPlantPhasesKey(childB)));

    // 只有 A 有「上次看到 seed」的快照。
    await SettingsStore(sp).setLastSeenPlantPhases(
        <String, String>{'p1': 'seed:growing'},
        childId: childA);

    final _Harness a = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
      childId: childA,
    );
    addTearDown(a.dispose);
    await tester.pumpWidget(a.widget());
    await _waitGarden(tester);
    expect(await _collectOverlays(tester, rounds: 30), isNotEmpty,
        reason: '孩子 A 有 seed 基线 → 应补播');

    // ⚠️ 必须显式卸载再挂 B：同一个 ProviderScope/MaterialApp 类型链下换 container
    // 会**复用** GardenPage 的 Element/State（A 的演出与内存队列会带进 B）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // 换 B：B 没有快照 → 不补播，也不能读到 A 的快照。
    final _Harness b = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
      childId: childB,
    );
    addTearDown(b.dispose);
    await tester.pumpWidget(b.widget());
    await _waitGarden(tester);
    expect(await _collectOverlays(tester, rounds: 40), isEmpty,
        reason: '孩子 B 没有「上次看到」的基线 → 不该继承 A 的补播');
    expect(
        (await SettingsStore(sp).lastSeenPlantPhases(childId: childB))['p1'],
        'sprout:growing',
        reason: 'B 自己的快照独立写入');
    expect(
        (await SettingsStore(sp).lastSeenPlantPhases(childId: childA))['p1'],
        'sprout:growing',
        reason: 'A 的快照不被 B 写坏');

    // B 自己也有 seed 基线时 → 独立补播。
    await SettingsStore(sp).setLastSeenPlantPhases(
        <String, String>{'p1': 'seed:growing'},
        childId: childB);
    await tester.pumpWidget(const SizedBox.shrink());
    final _Harness b2 = _Harness(
      plants: <Plant>[_plant(stage: PlantStage.sprout)],
      sp: sp,
      childId: childB,
    );
    addTearDown(b2.dispose);
    await tester.pumpWidget(b2.widget());
    await _waitGarden(tester);
    expect(await _collectOverlays(tester, rounds: 30), isNotEmpty,
        reason: 'B 自己的 seed 基线 → 独立补播一次');
  });

  // 🔴 QA 复核 P2-2 的守卫：队列里存的是**基线**而不是算好的段落。
  // 旧实现在入队时就把 transition 定死 —— 若隐藏期间植物又跨了一级，孩子回来
  // 会先播「过时的前一段」，并因 `_growthFxInFlight` 闸门把真正的新跃迁吃掉。
  // 本例构造：隐藏时 seed→sprout（入队）→ 仍是隐藏态再长成 adult → 切到花园，
  // 必须播「幼苗→成株」，绝不能播「种子→幼苗」。
  testWidgets('隐藏期继续跨级：补播的是最新那一段（不是入队时的旧段落）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    await SettingsStore(sp).setLastSeenPlantPhases(
        <String, String>{'p1': 'seed:growing'},
        childId: kChildIdDefault);

    final List<Plant> plants = <Plant>[_plant(stage: PlantStage.sprout)];
    final _Harness h = _Harness(plants: plants, sp: sp);
    addTearDown(h.dispose);

    await tester.pumpWidget(h.widget(shell: true));
    await _waitGarden(tester);
    expect(await _collectOverlays(tester, rounds: 20), isEmpty,
        reason: '隐藏 tab 不得播（入队即可）');

    // 隐藏期间植物继续长成成株 —— 队列基线仍应是 seed:growing。
    plants[0] = _plant(stage: PlantStage.adult);
    h.bumpEconomy();
    await _waitGarden(tester);

    // 切到花园 → 消费队列 → 必须播最新那一段。
    h.goTab(kChildTabIndexOfGarden);
    final Set<String?> titles = <String?>{};
    for (int i = 0; i < 60; i++) {
      final Finder f = find.byType(GrowthFxOverlay);
      if (f.evaluate().isNotEmpty) {
        titles.add(tester.widget<GrowthFxOverlay>(f.first).title);
      }
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(titles, contains('长大啦！🌿'),
        reason: '隐藏期跨到成株 → 必须播「幼苗→成株」（消费时按基线重算）');
    expect(titles, isNot(contains('发芽啦！🌱')),
        reason: '旧实现会把入队时算好的「种子→幼苗」播出来（P2-2 回归）');
  });

  // 🔴 枚举顺序守卫（QA 复核 P3-5）：`_transitionOf` 用
  // `GrowTransition.values[nowRank - 1]` 把「里程碑序号」映射到演出段落
  // （rank 1 = 种子→幼苗、2 = 幼苗→成株、3 = 成株→盛开）。这条映射**依赖枚举
  // 声明顺序**，一旦有人重排 `GrowTransition`，跨级时会静默播错段落（不报错、
  // 不红、只有真机看得出）。本断言把顺序钉死，重排即红。
  test('里程碑序号 ↔ GrowTransition 枚举顺序守卫', () {
    expect(
      GrowTransition.values,
      const <GrowTransition>[
        GrowTransition.seedToSprout, // rank 1：种子 → 幼苗
        GrowTransition.sproutToAdult, // rank 2：幼苗 → 成株
        GrowTransition.adultToBloomed, // rank 3：成株 → 盛开
      ],
      reason: 'garden_page._transitionOf 用 values[rank-1]，重排枚举会让跨级补播错位',
    );
  });
}
