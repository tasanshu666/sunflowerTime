/// F157-BUG-1 · **QA 独立验收探针**（严过关，2026-10-27）。
///
/// 与工程师自测 `garden_one_click_adaptive_width_test.dart` 的分工：
/// · 工程师用例：390×844 @1.0 —— 玄参真机（小米 14 Pro）复现尺寸；
/// · **本文件（QA 独立）**：把视口压到 **320×844 @ dpr3 + 英文 + textScale 1.3**
///   （玄参没测过的更窄/更大字极端），确认「不溢出、不崩、放不下时走省略号」；
///   再用 **390 @ textScale 2.0** 把宽度顶到上限，验证「顶到上限也不溢出」；
///   最后复核 zh 在 390 下宽度仍**精确 108**（逐像素零回归）。
///
/// ## 为什么不能只看 `takeException()`
/// 修复给标签包了 `Flexible + maxLines:1 + ellipsis` → 宽度不够时 Flutter **不抛**
/// `RenderFlex overflowed`，只是静默截字。因此「无异常」是**必要但不充分**条件：
/// · 放得下 → 必须 `didExceedMaxLines == false`（没截断）；
/// · 顶到上限 → 必须 `didExceedMaxLines == true`（截断发生）+ `overflow == ellipsis`
///   （截断形态是省略号而不是裁切）+ 依然无异常。
/// 三条合起来才排得掉「不出声地裁字」。
///
/// ⚠️ 花园页木牌无限呼吸动画 → 全程有界 `pump`，禁 `pumpAndSettle`。
library f157_qa_narrow_viewport_probe_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

import '../helpers/no_hit_random.dart';

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 4 株存活幼苗（存活株 ≥ `kOneClickMinPlants` 才会出现一键 FAB）。
List<Plant> _fourSprouts() {
  final DateTime now = DateTime.now();
  return <Plant>[
    for (int i = 0; i < 4; i++)
      Plant(
        id: 'p$i',
        speciesId: 'species_sunflower',
        potIndex: i,
        stage: PlantStage.sprout,
        stageStartedAt: now.subtract(const Duration(hours: 2)),
        growthProgress: 0.3,
        growthFactor: 1.0,
        status: PlantStatus.growing,
        plantedAt: now.subtract(const Duration(hours: 2)),
        lastWaterAt: now.subtract(const Duration(hours: 2)),
      ),
  ];
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 6,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
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
  _StoringPlantRepository(this._plants);
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

/// 真实花园页宿主（买断档 → 一键操作可用）+ 页级 `L10nScope`；
/// `textScale` 经 `MaterialApp.builder` 注入（覆盖整棵子树，含浮层）。
Widget _host({required double textScale}) {
  return ProviderScope(
    overrides: <Override>[
      entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      plantRepositoryProvider
          .overrideWithValue(_StoringPlantRepository(_fourSprouts())),
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
    child: MaterialApp(
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const L10nScope(
        child: Scaffold(body: GardenPage(embedded: true)),
      ),
    ),
  );
}

void _useViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 有界帧推进（花园页无限呼吸动画 → 禁 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 300,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 等一键 FAB（收拢态胶囊）出现。
Future<void> _waitFab(WidgetTester tester) async {
  final bool fab = await _pumpUntil(
    tester,
    () =>
        find.byKey(kOneClickCapsuleKey).evaluate().isNotEmpty &&
        find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fab, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');
}

/// 展开一键操作卡；返回 false = 没展开成功。
Future<bool> _expand(WidgetTester tester) async {
  await _waitFab(tester);
  await tester.tap(find.byIcon(Icons.touch_app));
  final bool shown = await _pumpUntil(
    tester,
    () => find.byKey(kOneClickCardKey).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 120));
  return shown;
}

/// 某标签的排版是否被省略号截断。
bool _exceedsMaxLines(WidgetTester tester, String label) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(
    find.text(label),
  );
  return p.didExceedMaxLines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  testWidgets(
      '① en + 320×844 @1.3：不溢出、不崩、三标签完整可见、卡与胶囊等宽',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.en);
    const double w = 320;
    _useViewport(tester, width: w, height: 844);

    await tester.pumpWidget(_host(textScale: 1.3));
    await _waitFab(tester);
    final double capsule = tester.getSize(find.byKey(kOneClickCapsuleKey)).width;
    expect(await _expand(tester), isTrue, reason: '点 FAB 应展开操作卡');

    // ① 无布局异常。
    expect(tester.takeException(), isNull,
        reason: 'en + 320 + 1.3 倍字号：展开卡不得出现 RenderFlex overflow');

    // ② 320×844@1.3 的可用宽度（上限 296）仍装得下 → 三个标签必须一个都不被截。
    for (final String label in <String>[
      'Water all',
      'Fertilize all',
      'Care all',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '标签「$label」必须在展开卡里');
      expect(_exceedsMaxLines(tester, label), isFalse,
          reason: '320@1.3 下「$label」不该被截断（宽度自适应应当撑够）');
    }

    // ③ 等宽（C29：展开/收拢不左右变形）+ 上限纪律 + 确实比 108 宽。
    final double card = tester.getSize(find.byKey(kOneClickCardKey)).width;
    expect(card, equals(capsule), reason: '胶囊与展开卡必须严格等宽（C29）');
    expect(card, greaterThan(kOneClickWidthFloor),
        reason: '英文文案比 108 宽 → 宽度必须自适应放大');
    expect(
      card,
      lessThanOrEqualTo(w - kOneClickSafeMargin * 2),
      reason: '宽度上限 = 屏宽 − 2 × kOneClickSafeMargin（不得顶出屏幕）',
    );
  });

  testWidgets(
      '② en + 390 @2.0 倍字号：宽度顶到上限（366）→ 只截字（省略号）+ 绝不溢出',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.en);
    const double w = 390;
    _useViewport(tester, width: w, height: 844);

    await tester.pumpWidget(_host(textScale: 2.0));
    await _waitFab(tester);
    final double capsule = tester.getSize(find.byKey(kOneClickCapsuleKey)).width;
    expect(await _expand(tester), isTrue, reason: '点 FAB 应展开操作卡');

    final double card = tester.getSize(find.byKey(kOneClickCardKey)).width;
    const double ceiling = w - kOneClickSafeMargin * 2; // 366
    expect(card, moreOrLessEquals(ceiling, epsilon: 0.5),
        reason: '2.0 倍字号下实测宽度必然超出上限 → 必须被钳到屏宽−24（实测 $card）');
    expect(card, equals(capsule), reason: '被钳后胶囊与展开卡仍须严格等宽（C29）');

    // 🔴 关键：顶到上限时**截字而不溢出**。
    expect(tester.takeException(), isNull,
        reason: '顶到宽度上限时绝不能抛 RenderFlex overflow（release 会裁字/黄黑条）');
    expect(_exceedsMaxLines(tester, 'Fertilize all'), isTrue,
        reason: '上限已不足 → 最宽的 `Fertilize all` 应当被省略号截断（说明上限真的生效了）');

    // 截断形态必须是「省略号 + 单行」，不是硬裁。
    final Text text = tester.widget<Text>(find.text('Fertilize all'));
    expect(text.maxLines, 1, reason: '标签必须 maxLines: 1');
    expect(text.overflow, TextOverflow.ellipsis,
        reason: '放不下时必须走省略号（不是 clip / fade）');
    expect(text.softWrap, isFalse, reason: '标签不得换行（会把 36 高的行撑破）');
  });

  testWidgets('③ zh + 390×844：宽度仍精确 108（中文侧逐像素零回归）',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.zh);
    _useViewport(tester, width: 390, height: 844);

    await tester.pumpWidget(_host(textScale: 1.0));
    await _waitFab(tester);
    final double capsule = tester.getSize(find.byKey(kOneClickCapsuleKey)).width;
    expect(capsule, equals(kOneClickWidthFloor),
        reason: '中文「一键操作」放得下 → 宽度必须仍是既有 108（零回归）');

    expect(await _expand(tester), isTrue, reason: '点 FAB 应展开操作卡');
    expect(tester.takeException(), isNull, reason: '中文侧不得出现溢出');
    for (final String label in <String>['一键浇水', '一键施肥', '一键护理']) {
      expect(_exceedsMaxLines(tester, label), isFalse,
          reason: '中文「$label」不得被截断（108 仍够用）');
    }
    expect(tester.getSize(find.byKey(kOneClickCardKey)).width, equals(capsule),
        reason: '中文侧胶囊与展开卡同样必须严格等宽（C29）');
  });
}
