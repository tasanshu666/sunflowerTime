/// C77 · **铲除二次确认卡「展示 == 实返」同源** widget 测试（设计 §5.4 / §6.1 接线末行 /
/// §12.3 **TC-37b**）。
///
/// 🔴 本批**真缺陷**回归：`plant_care_sheet.dart` 的铲除确认卡原先直接显示
/// `plant.shovelRefund`（列值 = **基础额** 150），而 `PlantGrowthService.shovel` 实际
/// 入账 = `shovelRefundOf(基础额, 当前称号)` = 170 ⇒ **显示 150 / 实返 170** 的不一致。
/// 修复后确认卡改调 `shovelRefundOf(plant.shovelRefund, perk)`（**同一纯函数**），
/// 本文件用「确认卡文案数字 == `onShoveled` 实返数字」把它钉死。
///
/// 覆盖三态：
///  · Lv.40 + 付费株（列 150）→ **显示 170 == 实返 170**（正例）；
///  · Lv.0  + 付费株（列 150）→ 显示 150 == 实返 150（**零回归**：无称号不加成）；
///  · Lv.40 + 免费首株（列 0）→ 显示「不返还」== 实返 0（防「免费种→铲」刷分）。
library plant_care_sheet_perk_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
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
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show ChildConfirmCard, ChildConfirmStyle;
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';

final DateTime _t = DateTime(2026, 10, 15, 8);

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株存活、可铲的付费株（[shovelRefund] = 列值：付费 150 / 免费首株 0）。
Plant _planted({required int shovelRefund}) => Plant(
      id: 'plant-1',
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.sprout,
      stageStartedAt: _t,
      growthProgress: 0.3,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: _t,
      lastWaterAt: _t,
      shovelRefund: shovelRefund,
    );

AppSettings _settings() => const AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 4,
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
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
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

class _FakePlantRepository implements PlantRepository {
  _FakePlantRepository(this._plant);
  Plant _plant;
  @override
  Future<List<Plant>> plants() async => <Plant>[_plant];
  @override
  Future<Plant?> plant(String id) async => id == _plant.id ? _plant : null;
  @override
  Future<void> savePlant(Plant plant) async => _plant = plant;
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

Widget _host({
  required int shovelRefund,
  required int perkLevel,
  required ValueChanged<int> onShoveled,
}) {
  return ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      plantRepositoryProvider
          .overrideWithValue(_FakePlantRepository(_planted(shovelRefund: shovelRefund))),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      currentPlantPerkProvider
          .overrideWith((Ref ref) async => perkOfLevel(perkLevel)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: PlantCareCard(plantId: 'plant-1', onShoveled: onShoveled),
      ),
    ),
  );
}

/// 有界推进（花盆/卡片含循环动画，`pumpAndSettle` 可能不返回）。
Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 打开养护卡 → 等就绪 → 点「铲除」→ 弹出二次确认卡 → 返回确认卡**全部文案拼接**。
///
/// F135（2026-10-19）确认卡统一换壳：`AlertDialog` → 共享的 [ChildConfirmCard]
/// （奶油底卡壳，见 `child_confirm_card.dart`），查找范围跟着换类型；返回值改成
/// **整卡所有 Text 拼接**——因为「返还额」从原先的一句话里挪到了明细行
/// （行名 `返还种植阳光` / 行值 `+170 ☀` 是两个 Text），下面三条断言因此改为
/// 「拼接串里同时出现行名与行值」，语义仍是原口径：
/// **确认卡上显示的返还数字必须 == 实际入账数字（同源 `shovelRefundOf`）**。
Future<String> _openShovelConfirm(
  WidgetTester tester, {
  required int shovelRefund,
  required int perkLevel,
  required ValueChanged<int> onShoveled,
}) async {
  await tester.pumpWidget(
    _host(
      shovelRefund: shovelRefund,
      perkLevel: perkLevel,
      onShoveled: onShoveled,
    ),
  );
  await _pumpFrames(tester, 40); // 等 _load 读仓储 + provider 就绪
  expect(find.text('向日葵'), findsWidgets, reason: '养护卡应已就绪');

  await tester.tap(find.text('铲除'));
  await _pumpFrames(tester, 20); // 确认卡路由动画

  final Iterable<Text> texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(ChildConfirmCard),
      matching: find.byType(Text),
    ),
  );
  return texts.map((Text t) => t.data ?? '').join(' ｜ ');
}

void main() {
  testWidgets('TC-37b 付费株（列 150）+ Lv.40：确认卡显示 170 == 实际入账 170（同源）',
      (WidgetTester tester) async {
    int? granted;
    final String body = await _openShovelConfirm(
      tester,
      shovelRefund: 150,
      perkLevel: 40,
      onShoveled: (int r) => granted = r,
    );

    final int expected = shovelRefundOf(150, perkOfLevel(40));
    expect(expected, 170, reason: '基础额 150 + 铲除加成 20');
    expect(body, contains('铲除后这株植物会消失'),
        reason: '后果说明（warning）不得在改版中丢失');
    expect(body, contains('返还种植阳光'), reason: '确认卡必须有返还明细行');
    expect(body, contains('+$expected ☀'),
        reason: '🔴 确认卡必须显示 shovelRefundOf(...)（防「显示 150 / 实返 170」）');

    // 确认执行 → 实际入账。
    await tester.tap(find.text('确定铲除'));
    await _pumpFrames(tester, 20);
    expect(granted, expected,
        reason: 'onShoveled 实返必须 == 确认卡显示的数字（同一 shovelRefundOf）');
  });

  testWidgets('TC-37b 付费株（列 150）+ Lv.0：显示 150 == 实返 150（零回归）',
      (WidgetTester tester) async {
    int? granted;
    final String body = await _openShovelConfirm(
      tester,
      shovelRefund: 150,
      perkLevel: 0,
      onShoveled: (int r) => granted = r,
    );

    expect(body, contains('+150 ☀'),
        reason: '无称号 → 基础额原样（C29 §2 逐位不变）');

    await tester.tap(find.text('确定铲除'));
    await _pumpFrames(tester, 20);
    expect(granted, 150);
  });

  testWidgets('TC-37b 免费首株（列 0）+ Lv.40：显示「不返还」== 实返 0（防刷分）',
      (WidgetTester tester) async {
    int? granted;
    final String body = await _openShovelConfirm(
      tester,
      shovelRefund: 0,
      perkLevel: 40,
      onShoveled: (int r) => granted = r,
    );

    expect(body, contains('本次铲除不返还阳光'),
        reason: 'base == 0 不加成（免费首株不享铲除加成，天然防「免费种→铲」刷分）');
    // 0 返还一律**不带「+」号**（旧写法是「不出现「返还种植阳光」整句」；
    // 改版后返还额进明细行，行名恒为「返还种植阳光」、行值才是数字）。
    expect(body, isNot(contains('+')), reason: '0 返还不许画成「+0 ☀」');
    // QA 复核补强（2026-10-19）：只断言「没有 + 号」会漏掉「行值渲染成裸错值」——
    // 例如把 `refund > 0 ? '+$refund ☀' : '0 ☀'` 误写成 `'$refund ☀'`，
    // 则 0 返还显示 `170 ☀`（无 + 号）也能过上面那条。故补两条**精确值**断言：
    //  ① 行值必须精确等于 '0 ☀'；② 全卡不得出现 `+数字` 形态。
    final List<String> allTexts = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(ChildConfirmCard),
          matching: find.byType(Text),
        ))
        .map((Text t) => t.data ?? '')
        .toList();
    expect(allTexts, contains('0 ☀'),
        reason: '0 返还时明细行值必须精确等于「0 ☀」（不得显示任何非 0 数字）');
    expect(
      allTexts.where((String s) => RegExp(r'^\+\s*\d').hasMatch(s)),
      isEmpty,
      reason: '0 返还不许画成「+N ☀」冒充到账',
    );

    await tester.tap(find.text('确定铲除'));
    await _pumpFrames(tester, 20);
    expect(granted, 0);
  });

  // QA 复核补强（2026-10-19）：F135 把铲除卡从 `AlertDialog` 换成统一卡壳后，
  // 「红档（破坏性操作）」只在 `child_confirm_card_test` ④ 做过**组件层**验证
  // （该用例自己传 `tone: danger`），**没有任何用例**验证 `plant_care_sheet._shovel()`
  // 真的把 `confirmTone: danger` 传了下去。
  // 变异实测（QA M3）：把调用方的 `confirmTone: ConfirmCardTone.danger` 删掉，
  // 全量 1635 条**仍然全绿** —— 红色警示退化成金色也无人报警。
  // 本用例把这条接线钉死（真实养护卡 → 点铲除 → 量确认按钮底色）。
  testWidgets('F135 铲除确认卡必须走红档（confirmTone 接线守）', (WidgetTester tester) async {
    await _openShovelConfirm(
      tester,
      shovelRefund: 150,
      perkLevel: 40,
      onShoveled: (int _) {},
    );

    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确定铲除'),
    );
    expect(
      confirm.style?.backgroundColor?.resolve(<WidgetState>{}),
      ChildConfirmStyle.danger,
      reason: '🔴 破坏性操作（铲除）的确认按钮必须渲染成警示红；'
          '退化成金色 = 调用方漏传 `confirmTone: ConfirmCardTone.danger`',
    );
    expect(
      confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
      reason: '红底必须白字（对比度）',
    );
  });
}
