/// 一键操作 FAB · **自适应宽度**回归（F157-BUG-1，玄参 2026-10-27 小米 14 Pro 真机）。
///
/// ## 缺陷现象
/// 英文界面点花园右下角「一键操作」展开 → 三行菜单（`Water all` / `Fertilize all` /
/// `Care all`）**右侧被裁**，debug 包出现黄黑溢出条，Flutter 报
/// `RenderFlex overflowed by 4 pixels`。iPad 13″ 不复现（屏宽足够）。
///
/// ## 根因
/// `_OneClickFab` 的宽度被钉死 `108 * uiScaleOf(context)`：中文「一键浇水」够用，
/// 英文 `Fertilize all` + 图标 + 行内边距**超出固定宽度** → 行内 `Row` 溢出。
///
/// ## 本文件的断言（为什么这三条能钉住它）
///  ① `tester.takeException()` 为 null —— 不再有 `RenderFlex overflowed`
///     （debug 黄黑条的来源）；
///  ② 三个标签的 `RenderParagraph.didExceedMaxLines` 均为 `false` —— **没被省略号截断**。
///     这条是**变异验证**的关键：把宽度改回固定 108 后不会抛异常（新代码用
///     `Flexible` + ellipsis 兜底），但最宽的 `Fertilize all` 会被截 → 只有这条断言
///     会红。若只断言「不抛异常」，固定 108 会假绿。
///  ③ 胶囊与展开卡 `getSize().width` **严格相等** —— 玄参口径 C29
///     「宽度要一致，不要来回变化」。
///
/// 另补中文同视口用例：中文侧宽度必须仍为 108（既有口径逐像素零回归，
/// 防「为了修英文把中文也一起放宽」）。
///
/// ⚠️ 花园页木牌是无限呼吸动画 → 全程有界 `pump`，**禁止 `pumpAndSettle`**。
library garden_one_click_adaptive_width_test;

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

/// 4 株「幼苗 · 成长中」的活株 —— 存活株 ≥ [kOneClickMinPlants] 才会出现一键 FAB。
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

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 6,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
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

/// 有界帧推进（花园页有无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 240,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 真实花园页宿主：买断档（一键操作已解锁）+ 页级 `L10nScope`（文案跟 locale 走）。
Widget _host() => ProviderScope(
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
      child: const MaterialApp(
        home: L10nScope(
          child: Scaffold(body: GardenPage(embedded: true)),
        ),
      ),
    );

/// 小米 14 Pro 的逻辑视口（玄参真机）。
const Size _phone = Size(390, 844);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 三个操作标签是否**都未被截断**（`RenderParagraph.didExceedMaxLines` 全 false）。
///
/// 为什么不用「不抛异常」当唯一判据：新代码给标签包了 `Flexible` + `ellipsis`
/// 兜底，宽度不够时**不抛 RenderFlex 异常**、只是静默截字 —— 光看异常会假绿。
/// 宽度被改回固定 108 时，正是这条断言变红（变异验证见汇报）。
void _expectLabelsNotTruncated(WidgetTester tester, List<String> labels) {
  for (final String label in labels) {
    final Finder finder = find.text(label);
    expect(finder, findsOneWidget, reason: '标签「$label」必须在展开卡里');
    final RenderParagraph paragraph =
        tester.renderObject<RenderParagraph>(finder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '标签「$label」被省略号截断了（宽度不够）→ 固定 108 的老 bug 复发',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  testWidgets('① 英文 + 390×844：展开卡不溢出、三标签不截断、胶囊与卡等宽',
      (WidgetTester tester) async {
    // 显式 en（玄参真机就是英文界面）。
    AppLocaleController.init(AppLanguage.en);
    _usePhoneViewport(tester);

    await tester.pumpWidget(_host());
    // 等一键 FAB 出现（存活株 ≥ 4）。
    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

    final double capsuleWidth =
        tester.getSize(find.byKey(kOneClickCapsuleKey)).width;

    // 展开。
    await tester.tap(find.byIcon(Icons.touch_app));
    final bool cardShown = await _pumpUntil(
      tester,
      () => find.byKey(kOneClickCardKey).evaluate().isNotEmpty,
    );
    expect(cardShown, isTrue, reason: '点 FAB 应展开操作卡');
    await tester.pump(const Duration(milliseconds: 120));

    // ① 无布局异常（RenderFlex overflow 会在这里被捕获）。
    expect(
      tester.takeException(),
      isNull,
      reason: 'EN + 390 宽下展开卡不得出现 RenderFlex overflow（真机黄黑条）',
    );

    // ② 三标签都没被截断（英文文案必须完整可见）。
    _expectLabelsNotTruncated(
      tester,
      <String>['Water all', 'Fertilize all', 'Care all'],
    );

    // ③ 胶囊与展开卡严格等宽（C29「宽度要一致，不要来回变化」）。
    final double cardWidth =
        tester.getSize(find.byKey(kOneClickCardKey)).width;
    expect(
      cardWidth,
      equals(capsuleWidth),
      reason: '胶囊与展开卡必须严格等宽（C29）',
    );
    // 英文文案比 108 宽 → 自适应确实生效（否则上面的截断断言必红）。
    expect(
      cardWidth,
      greaterThan(kOneClickWidthFloor),
      reason: '英文 `Fertilize all` 比固定 108 宽 → 宽度应自适应放大',
    );
    // 上限纪律：绝不超过「屏宽 − 2 × 安全边距」。
    expect(
      cardWidth,
      lessThanOrEqualTo(_phone.width - kOneClickSafeMargin * 2),
      reason: '宽度上限 = 屏宽 − 2 × kOneClickSafeMargin',
    );
  });

  testWidgets('② 中文 + 390×844：宽度仍为 108（中文侧逐像素零回归）',
      (WidgetTester tester) async {
    AppLocaleController.init(AppLanguage.zh);
    _usePhoneViewport(tester);

    await tester.pumpWidget(_host());
    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue);

    final double capsuleWidth =
        tester.getSize(find.byKey(kOneClickCapsuleKey)).width;
    // 中文默认字号下三条 row 实测 ≈94（< 108）→ 仍取下限 108，与改前**逐像素相同**。
    //
    // ⚠️ 这条 `== 108` **只保证默认字号**：本算法是「实测最宽 + 下限 + 上限」的
    // 自适应，用户把系统字号调大（`MediaQuery.textScaler` 变大）或平板倍率
    // `uiScaleOf > 1` 时，中文也会跟着变宽 —— 这是**自适应设计的预期行为**，
    // 不是回归。故此处不做「任何情况下都恒等于 108」的过强断言；
    // 真正要守的红线是「不溢出、不被省略号截断、胶囊与卡片等宽」（见本文件
    // 其余断言）。
    expect(
      capsuleWidth,
      equals(kOneClickWidthFloor),
      reason: '中文「一键操作」放得下 → 默认字号下宽度必须仍是既有 108（零回归）',
    );

    await tester.tap(find.byIcon(Icons.touch_app));
    final bool cardShown = await _pumpUntil(
      tester,
      () => find.byKey(kOneClickCardKey).evaluate().isNotEmpty,
    );
    expect(cardShown, isTrue, reason: '点 FAB 应展开操作卡');
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull, reason: '中文侧不得出现溢出');
    _expectLabelsNotTruncated(
      tester,
      <String>['一键浇水', '一键施肥', '一键护理'],
    );
    expect(
      tester.getSize(find.byKey(kOneClickCardKey)).width,
      equals(capsuleWidth),
      reason: '中文侧胶囊与展开卡同样必须严格等宽（C29）',
    );
  });
}
