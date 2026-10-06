/// 独立复验探针 F（qa-verify2）：UI 口径
///  · 花园页「选择要种的植物」弹窗稀有度**两档**（普通 / 精英）+ 各物种价格文案；
///  · [PlantCard] 「花期剩余 X 天」：普通 3 天 / 精品 4.5 天，且**仅 bloomed 时**出现。
library qa_b2_ui_probes_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
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
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';

// ── 假仓储（弹窗用例）────────────────────────────────────────────────────────

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
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
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

/// 有界帧推进（木牌无限呼吸动画 → 禁用 pumpAndSettle）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

PlantSpecies _sp(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

Plant _plant({
  required String speciesId,
  required PlantStatus status,
  DateTime? bloomedAt,
}) =>
    Plant(
      id: 'p',
      speciesId: speciesId,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: DateTime(2026, 9, 27, 8),
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: status,
      plantedAt: DateTime(2026, 9, 27, 8),
      lastWaterAt: DateTime(2026, 9, 27, 8),
      bloomedAt: bloomedAt,
      bloomCount: 1,
      mood: PlantMood.calm,
    );

Future<void> _pumpCard(WidgetTester tester, Plant plant, PlantSpecies sp) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: PlantCard(plant: plant, species: sp))),
  ));
}

void main() {
  // ── 稀有度两档 + 价格文案 ────────────────────────────────────────────────
  group('F1 · 花园页选种弹窗：稀有度两档（普通 / 精英）', () {
    testWidgets('8 物种稀有度标签 + 价格文案全部按两档渲染',
        (WidgetTester tester) async {
      // 逻辑视口加高，使 modal bottom sheet（默认限高 ~9/16 屏高）能一次容纳 8 个物种项，
      // 避免懒加载把后 4 个精英项留在树外导致误判。
      tester.view.physicalSize = const Size(360, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 预置碎片余额 ≥ 10，使碎片物种显示真实价格（0 片时会置灰为「碎片不足」）。
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
          home: Scaffold(body: GardenPage(embedded: true)),
        ),
      ));

      final bool ready = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      expect(ready, isTrue);
      await tester.tap(find.byType(EmptyPot).first);
      await tester.pump(const Duration(milliseconds: 400));

      // 新「选择要种」列表：稀有度单独成 chip（普通 / 精英），支付方式单独成按钮。
      // 2026-10-05 玄参美化口径：阳光/碎片价格=「素材图标 + 数字」，不再写「N 阳光」文字。
      // 普通档 3 种：向日葵=免费（C29：无存活株时首株免费）；番茄 / 草莓 各「300」「6」两档可选（C29 修订 400→300）。
      expect(find.text('普通'), findsNWidgets(3), reason: '向日葵/番茄/草莓=普通档');
      expect(find.text('精英'), findsNWidgets(5), reason: '月光兰+4精英=精英档');
      expect(find.text('免费'), findsOneWidget, reason: '向日葵=免费');
      expect(find.text('300'), findsNWidgets(2), reason: '番茄/草莓=各 300 阳光档（C29）');
      expect(find.text('6'), findsNWidgets(2), reason: '番茄/草莓=各 6 植物碎片档');
      // 精英档（含月光兰，新计价仅碎片）各 10 植物碎片。
      expect(find.text('10'), findsNWidgets(5),
          reason: '5 精英（含月光兰）=各 10 植物碎片');

      // 不得再出现旧的稀有度词。
      for (final String old in <String>['优良', '稀有', '传奇', '史诗']) {
        expect(find.textContaining(old), findsNothing, reason: '不应出现「$old」');
      }
    });
  });

  // ── 花期剩余（PlantCard）─────────────────────────────────────────────────
  group('F2 · PlantCard 花期剩余 X 天', () {
    testWidgets('普通档（common）盛开 → 花期剩余 3 天', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      await _pumpCard(
        tester,
        _plant(speciesId: 'species_sunflower', status: PlantStatus.bloomed, bloomedAt: now),
        _sp('species_sunflower'),
      );
      expect(find.text('花期剩余 3 天'), findsOneWidget);
      expect(find.textContaining('花期剩余 4.5'), findsNothing);
    });

    testWidgets('精品档（rare）盛开 → 花期剩余 4.5 天', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      await _pumpCard(
        tester,
        _plant(speciesId: 'species_star_flower', status: PlantStatus.bloomed, bloomedAt: now),
        _sp('species_star_flower'),
      );
      expect(find.text('花期剩余 4.5 天'), findsOneWidget);
      expect(find.textContaining('花期剩余 3 '), findsNothing);
    });

    testWidgets('非盛开（growing）→ 不出现花期剩余', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _plant(speciesId: 'species_sunflower', status: PlantStatus.growing),
        _sp('species_sunflower'),
      );
      expect(find.textContaining('花期剩余'), findsNothing);
    });

    testWidgets('盛开但 bloomedAt 缺失（老库升级）→ 不编造数字、不显示', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _plant(speciesId: 'species_sunflower', status: PlantStatus.bloomed),
        _sp('species_sunflower'),
      );
      expect(find.textContaining('花期剩余'), findsNothing);
    });
  });
}
