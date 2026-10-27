/// F155-A 回归守卫：**英文模式下种植确认卡标题必须是英文物种名**。
///
/// ## 缺陷（玄参 2026-10-27 真机实锤）
/// 英文环境下，点空花盆 → 选「葡萄」→ 支付 → 弹出的是 **`Plant the 葡萄?`**
/// （英中混排）。根因：`garden_page._confirmAndPlant` 直接把 `species.name`
/// （= `plant_seed.dart` 里落库用的**中文原名**）塞进 `plant_confirm_title(...)`，
/// 而物种名在 UI 侧必须经 `speciesNameOr(speciesId, species.name, l10n)` 单点解析
/// （花盆格标签 / 选种卡早已这么写）。
///
/// ## 为什么必须从真实入口走进来
/// 只测 `speciesNameOr` 或只测 `plant_confirm_title` 都**测不出**这个 bug ——
/// bug 在「谁把什么值传进去」的接线处。故本用例：
///   ① 挂**真实** [GardenPage]（真实花园网格、真实选种弹窗、真实确认卡）；
///   ② 经 [AppLocaleController] 把生效语言切成 **en**（与线上切语言同一条路）；
///   ③ 点空花盆 → 选**葡萄** → 点支付 → 读确认卡标题；
///   ④ 反证：标题里**不得**出现中文「葡萄」。
///
/// 同文件补一条 zh 基线（同一条路径 → 「要种下葡萄吗？」），证明本用例不是
/// 靠「英文文案恰好不叫 Grape」碰巧通过的。
library garden_plant_confirm_i18n_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ── Fake 仓储（花园页所需最小集）──────────────────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: 4,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _FakeSunlightRepo implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
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
}

class _FakeFocusRepo implements FocusRepository {
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

class _FakePlantRepo implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

/// 空盆干扰物仓储 Fake（F155-B 的旁路 tick 用）。
///
/// 本用例只关心「种植确认卡标题」，与空盆玩法无关；但花园页刷新会旁路跑一次空盆
/// tick —— 不覆写就会去构造**真实** `AppDatabase`（测试环境无 path_provider，
/// 白刷 drift「多实例」警告）。空实现 = 永远没有干扰物，草地对齐不受影响。
class _EmptyPotDisturbanceRepo implements PotDisturbanceRepository {
  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  @override
  Future<List<PotDisturbance>> disturbances() async => store.values.toList();

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];

  @override
  Future<void> save(PotDisturbance disturbance) async {
    store[disturbance.potIndex] = disturbance;
  }

  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);

  @override
  Future<void> deleteAll() async => store.clear();
}

// ── 工具 ────────────────────────────────────────────────────────────────────

/// 有界帧推进（花园页木牌是无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 120,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 「葡萄」卡片的定位：`_PlantTile` 是私有 StatefulWidget（外部不可按类型 find），
/// 故按 **名称文本 + runtimeType 名** 双重限定 —— 只取葡萄那一张卡，
/// 避免「精英档 5 种卡都有 Seed 按钮」时误点别的物种。
Finder _tileOf(String speciesNameLabel) => find.ancestor(
      of: find.text(speciesNameLabel),
      matching: find.byElementPredicate(
        (Element e) => e.widget.runtimeType.toString() == '_PlantTile',
      ),
    );

/// 挂载真实花园页（8 物种种子表 + 一张精英券 → 精英卡都有 Seed 按钮）。
Future<void> _pumpGarden(WidgetTester tester,
    {required InMemoryBloomRewardRepository bloom}) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
      bloomRewardRepositoryProvider.overrideWithValue(bloom),
      // F155-B 旁路 tick 的空盆仓储（空实现，永不出浮标；见类注释）。
      potDisturbanceRepositoryProvider
          .overrideWithValue(_EmptyPotDisturbanceRepo()),
    ],
    child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
  ));
}

/// 点空花盆 → 选葡萄 → 点该卡的 Seed / 种子按钮 → 等确认卡出现。
Future<void> _openGrapeConfirm(
  WidgetTester tester, {
  required String speciesNameLabel,
  required String seedButtonLabel,
  required String confirmTitle,
}) async {
  final bool potsReady = await _pumpUntil(
    tester,
    () => find.byType(EmptyPot).evaluate().isNotEmpty,
  );
  expect(potsReady, isTrue, reason: '花园页必须渲染出空花盆');

  // 点空盆**底部**（避开可能的干扰物浮标热区 —— F155-B 起空盆也会长草长虫）。
  // warnIfMissed: false：底部是纯占位 `SizedBox`（无子节点 → 自身不吃命中），
  // 点击由外层 InkWell 兜住，flutter_test 会误报「没命中该 SizedBox」。
  await tester.tap(
    find.byKey(const Key('empty_pot_footer')).first,
    warnIfMissed: false,
  );
  final bool sheetShown = await _pumpUntil(
    tester,
    () => _tileOf(speciesNameLabel).evaluate().isNotEmpty,
  );
  expect(sheetShown, isTrue, reason: '点空盆必须弹出选种弹窗且含葡萄卡片');
  await tester.pump(const Duration(milliseconds: 400)); // 弹窗入场动画

  final Finder seedBtn = find.descendant(
    of: _tileOf(speciesNameLabel),
    matching: find.text(seedButtonLabel),
  );
  expect(seedBtn, findsOneWidget,
      reason: '葡萄（精英档）持券 → 卡上必须有种子支付按钮');
  // 选种弹窗是 SingleChildScrollView：葡萄是第 7 张卡，矮屏下屏外 → 必须先滚进可视区，
  // 否则 tap 的落点在视口外（实测 y≈1218 > 780 视口高），点击等于打空。
  await tester.ensureVisible(seedBtn);
  await tester.pump();
  await tester.tap(seedBtn);

  final bool confirmShown = await _pumpUntil(
    tester,
    () => find.text(confirmTitle).evaluate().isNotEmpty,
  );
  expect(confirmShown, isTrue,
      reason: '点支付按钮后必须弹出种植确认卡，标题应为「$confirmTitle」');
}

void main() {
  group('F155-A 种植确认卡标题（物种名必须随语言切换）', () {
    testWidgets('en：选葡萄 → 标题「Plant the Grape?」，且全文无中文「葡萄」',
        (WidgetTester tester) async {
      // 切语言：与线上同一条路（L10nScope 监听 controller 的 current / revision）。
      AppLocaleController.current = const Locale('en');
      addTearDown(() => AppLocaleController.current = const Locale('zh'));

      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_grape');
      await _pumpGarden(tester, bloom: bloom);

      await _openGrapeConfirm(
        tester,
        speciesNameLabel: 'Grape',
        seedButtonLabel: 'Seed',
        confirmTitle: 'Plant the Grape?',
      );

      expect(find.text('Plant the Grape?'), findsOneWidget,
          reason: '🔴 F155-A：英文模式确认卡标题必须走 speciesNameOr'
              '（不得把落库用的中文 species.name 直接拼进标题）');
      expect(find.textContaining('葡萄'), findsNothing,
          reason: '🔴 原缺陷正是「Plant the 葡萄?」：英文模式任何位置都不得出现中文物种名');
    });

    testWidgets('zh 基线：同一路径 → 标题「要种下葡萄吗？」（证明走的是真实本地化链）',
        (WidgetTester tester) async {
      AppLocaleController.current = const Locale('zh');
      addTearDown(() => AppLocaleController.current = const Locale('zh'));

      final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
      await bloom.unlockSpecies('species_grape');
      await _pumpGarden(tester, bloom: bloom);

      await _openGrapeConfirm(
        tester,
        speciesNameLabel: '葡萄',
        seedButtonLabel: '种子',
        confirmTitle: '要种下葡萄吗？',
      );

      expect(find.text('要种下葡萄吗？'), findsOneWidget,
          reason: 'zh 基线：中文环境物种名照旧（修复不得影响中文文案）');
    });
  });
}
