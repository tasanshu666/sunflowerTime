/// F147：**手机端花园选种卡「Premium」卡底部溢出 8px** 守卫。
///
/// ## 背景（玄参截图）
/// iPhone 尺寸（390×844 逻辑宽）下「选择要种的植物」弹窗里，精英物种卡
/// （Coral Ridge Orchid / Jade Hydrangea / Moon Orchid，带紫色 Premium 徽标）
/// 底部黄黑条 `BOTTOM OVERFLOWED BY 8.0 PIXELS`；iPad 11/13 无此问题。
///
/// ## 根因
/// 选种卡正面是**固定高度**（`kPlantCardHeight * uiScaleOf` = 116）容器，内部
/// 「名称 + Premium 徽章 + 种子徽章」一行会因英文长名在手机档折成多行，列高
/// （名称行 + 间距 + 价格按钮行）超过 96pt 的内容区 → RenderFlex 溢出。
/// F144 加入稀有度徽章挤占名称宽度后，手机档（窄）首当其冲；iPad 档卡片更宽，
/// 名称单行放得下故无恙。
/// F147 二段修复：① 容器改 `minHeight` 自适应（内容放不下向下长高）；
/// ② 名称行持券种子徽章同日废除（Seed 按钮已承载该信息）→ 名称行更宽松，
/// 本守卫继续锁「无论如何都不得溢出」。
///
/// ## 守卫口径
///  · **禁止**用像素断「行数」；RenderFlex 溢出直接由 `tester.takeException()`
///     暴露（真实装配，非几何估算）；
///  · 手机档（390×844，dpr 3.0）+ en / zh 各探一遍，逐个精英物种 `ensureVisible`
///     后断言无异常（溢出在 paint 阶段抛出，屏外卡片不 paint → 必须滚到眼前）；
///  · textScale 1.3（玄参真机可能开大字号）同口径加探一轮；
///  · iPad13（1032×1376，dpr 2.0）回归：修复不得把平板档改坏。
library garden_species_card_phone_fit_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ───────────────────────────────────────────────────────────────────────────
// 最小 Fake 集（与 test/verify/qa_b2_ui_probes_test.dart F1 组同口径）
// ───────────────────────────────────────────────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
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
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepo implements SunlightRepository {
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
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
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

class _FakeFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
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

// ───────────────────────────────────────────────────────────────────────────
// 装配
// ───────────────────────────────────────────────────────────────────────────

/// iPhone 尺寸（玄参截图机型逻辑视口）。
const Size _kPhone = Size(390, 844);

/// iPad 13 逻辑视口（回归档）。
const Size _kIpad13 = Size(1032, 1376);

/// 精英物种的**渲染名**（en / zh 两套；zh 名与 garden_seed_hint_rarity_test 同源）。
const Map<String, List<String>> _kPremiumSpeciesNames =
    <String, List<String>>{
  'species_coral_orchid': <String>['Coral Ridge Orchid', '珊瑚岭兰'],
  'species_jade_hydrangea': <String>['Jade Hydrangea', '翡翠绣球'],
  'species_moon_orchid': <String>['Moon Orchid', '月光兰'],
  'species_grape': <String>['Grape', '葡萄'], // F151（2026-10-23）第 4 精英
};

/// 普通物种的**渲染名**（en / zh 两套；QA 补测：守卫原本只探精英卡，普通卡
/// 「名称行 + 普通徽章」同样受 F147 修复影响，须确认 minHeight 自适应不破）。
const Map<String, List<String>> _kCommonSpeciesNames =
    <String, List<String>>{
  'species_sunflower': <String>['Sunflower', '向日葵'],
  'species_tomato': <String>['Tomato', '番茄'],
  'species_strawberry': <String>['Strawberry', '草莓'],
};

/// 有界帧推进（花园页有呼吸动画 → 禁用 pumpAndSettle）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 90,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 真实装配花园页 + 打开「选择要种的植物」弹窗。
Future<void> _pumpPickPlantDialog(
  WidgetTester tester, {
  required Size logicalSize,
  required double dpr,
  required double textScale,
  required AppLanguage lang,
}) async {
  tester.view.physicalSize =
      Size(logicalSize.width * dpr, logicalSize.height * dpr);
  tester.view.devicePixelRatio = dpr;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  AppLocaleController.init(lang);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  // 预置碎片余额 ≥ 20：精英物种显示真实价格按钮（0 片会置灰 + 多出禁用原因行）。
  final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
  await bloom.setPremiumFragmentBalance(20);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
      bloomRewardRepositoryProvider.overrideWithValue(bloom),
    ],
    child: const MaterialApp(
      // 页级 scope 由生产壳（child shell）提供；本用例显式补上，否则 l10n 静默回退 zh。
      home: L10nScope(child: Scaffold(body: GardenPage(embedded: true))),
    ),
  ));

  // 等花园页就绪（空花盆出现）。
  final bool ready = await _pumpUntil(
    tester,
    () => find.byType(EmptyPot).evaluate().isNotEmpty,
  );
  expect(ready, isTrue, reason: '花园页必须渲染出空花盆（否则装配失败）');

  // 点空花盆 → 打开选种弹窗（showDialog 入场动画 ~150ms + 余量）。
  await tester.tap(find.byType(EmptyPot).first);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));

  // 防假绿：弹窗必须真的打开（标题在 zh / en 下不同，按 rarity chip 锚定）。
  final String premiumLabel = lang == AppLanguage.en ? 'Premium' : '精英';
  expect(find.text(premiumLabel), findsNWidgets(4),
      reason: '选种弹窗必须打开且 4 个精英物种卡都在场（防装配失败假绿）');
}

/// 逐个把精英物种卡滚到眼前并断言无布局异常。
///
/// RenderFlex 溢出在 **paint** 阶段抛出 —— 屏外卡片不 paint 就不暴露，
/// 所以每个精英卡都要 `ensureVisible` 后再 `takeException()`。
Future<void> _expectNoOverflowOnPremiumCards(
  WidgetTester tester,
  AppLanguage lang,
) async {
  await _expectNoOverflowOnCards(tester, lang, _kPremiumSpeciesNames);
}

/// 逐个把指定物种卡滚到眼前并断言无布局异常（精英 / 普通卡共用的探针）。
Future<void> _expectNoOverflowOnCards(
  WidgetTester tester,
  AppLanguage lang,
  Map<String, List<String>> names,
) async {
  for (final MapEntry<String, List<String>> entry in names.entries) {
    final String name = lang == AppLanguage.en ? entry.value[0] : entry.value[1];
    final Finder card = find.text(name);
    expect(card, findsOneWidget,
        reason: '${entry.key} 的选种卡必须渲染（名字「$name」）');
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull,
        reason: '${entry.key}（$name）选种卡在当前视口下不得出现 RenderFlex 溢出');
  }
}

void main() {
  group('F147 · 手机端（390×844）选种弹窗精英卡无溢出', () {
    testWidgets('en + textScale 1.0：四个精英卡逐个可见、无异常',
        (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kPhone,
        dpr: 3.0,
        textScale: 1.0,
        lang: AppLanguage.en,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.en);
    });

    testWidgets('en + textScale 1.3（大字号）：四个精英卡逐个可见、无异常',
        (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kPhone,
        dpr: 3.0,
        textScale: 1.3,
        lang: AppLanguage.en,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.en);
    });

    testWidgets('zh + textScale 1.0：四个精英卡逐个可见、无异常',
        (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kPhone,
        dpr: 3.0,
        textScale: 1.0,
        lang: AppLanguage.zh,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.zh);
    });

    testWidgets('zh + textScale 1.3（大字号）：四个精英卡逐个可见、无异常',
        (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kPhone,
        dpr: 3.0,
        textScale: 1.3,
        lang: AppLanguage.zh,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.zh);
    });

    testWidgets('QA 补测 · en + textScale 1.3（大字号）：普通卡（向日葵/番茄/草莓）逐个可见、无异常',
        (WidgetTester tester) async {
      // 守卫原本只探精英卡（F151 起 4 张）；普通卡走同一正面装配（minHeight 自适应 +
      // 「普通」徽章），en + 1.3 是最坏档 —— 名称行 + 徽章可能折行，须确认
      // 卡片向下长高而不是溢出。
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kPhone,
        dpr: 3.0,
        textScale: 1.3,
        lang: AppLanguage.en,
      );
      await _expectNoOverflowOnCards(tester, AppLanguage.en, _kCommonSpeciesNames);
    });
  });

  group('F147 · iPad13（1032×1376）回归：修复不改坏平板档', () {
    testWidgets('en + textScale 1.0：无异常', (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kIpad13,
        dpr: 2.0,
        textScale: 1.0,
        lang: AppLanguage.en,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.en);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zh + textScale 1.3：无异常', (WidgetTester tester) async {
      await _pumpPickPlantDialog(
        tester,
        logicalSize: _kIpad13,
        dpr: 2.0,
        textScale: 1.3,
        lang: AppLanguage.zh,
      );
      await _expectNoOverflowOnPremiumCards(tester, AppLanguage.zh);
      expect(tester.takeException(), isNull);
    });
  });
}
