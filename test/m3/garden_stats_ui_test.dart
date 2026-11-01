/// F169 · 孩子端「我的」页「花园统计」分组（玄参 2026-11-01 需求）。
///
/// 需求原话：「在孩子的我的页面里面，现在不是有一个累计成就吗？在下面新增加一个
/// 花园统计，然后统计一下浇水、施肥、除草、除虫的次数。」
///
/// 口径：与「累计护眼」同源同法 —— 以**阳光账本**为唯一事实源，
/// `SunlightRepository.countByRefType(<refType>)` 全量计数，零 schema 变更。
///
/// 本测试刻意用**四个互不相同**的计数（11 / 22 / 33 / 44），因为：
/// 任一 refType 常量的值写错、或四个字段接错位，页面上的某个数字就会对不上 →
/// 必然变红。用「都返回 1」的写法会四路互相掩护，测不出错位。
library garden_stats_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';

// ── 假仓储 ────────────────────────────────────────────────────────────────────

/// 账本桩：`countByRefType` 按 refType 查表返回（不认识的一律 0）。
class _FakeSunlightRepository implements SunlightRepository {
  _FakeSunlightRepository({this.counts = const <String, int>{}});

  final Map<String, int> counts;

  @override
  Future<int> countByRefType(String refType) async => counts[refType] ?? 0;

  @override
  Future<double> balance() async => 320;

  @override
  Future<double> append(SunlightEntry entry) async => 320;
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
        totalFocusMinutes: 120,
        totalSessions: 8,
        totalValidDays: 3,
      );
}

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];
  @override
  Future<int> totalCheckInCount() async => 5;
}

class _FakePlantRepository implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

// ── 测试台 ────────────────────────────────────────────────────────────────────

/// 四个互不相同的计数：任何 refType 写错 / 字段接错位都会立刻对不上。
const int kWater = 11;
const int kFertilize = 22;
const int kWeed = 33;
const int kPest = 44;

Future<void> _pumpProfile(WidgetTester tester) async {
  // 页面共 10 张成就卡 + 2 个分组标题：默认 800×600 视口会裁掉下半截，
  // 而 `ListView` 懒加载 → 未构建的卡片 `find.text` 找不到，故给足高度。
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      sunlightRepositoryProvider.overrideWithValue(
        _FakeSunlightRepository(counts: <String, int>{
          kPlantWaterRefType: kWater,
          kPlantFertilizeRefType: kFertilize,
          kGardenWeedRefType: kWeed,
          kGardenPestRefType: kPest,
          kEyeCareRefType: 7,
        }),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
  ));
  // 有界 pump：页面内有无限动画组件，绝不能用 pumpAndSettle。
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('花园统计').evaluate().isNotEmpty) break;
  }
}

void main() {
  setUp(() {
    AppLocaleController.init(AppLanguage.zh);
  });

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  group('「我的」页 · 花园统计', () {
    testWidgets('分组标题与四项标签齐全，且排在「累计成就」之后', (tester) async {
      await _pumpProfile(tester);

      expect(find.text('累计成就'), findsOneWidget);
      expect(find.text('花园统计'), findsOneWidget);
      expect(find.text('浇水'), findsOneWidget);
      expect(find.text('施肥'), findsOneWidget);
      expect(find.text('除草'), findsOneWidget);
      expect(find.text('除虫'), findsOneWidget);

      // 「花园统计」必须**排在**「累计成就」下方（同一 ListView 内的上下顺序）。
      final double achievementsY = tester.getTopLeft(find.text('累计成就')).dy;
      final double gardenY = tester.getTopLeft(find.text('花园统计')).dy;
      final double waterY = tester.getTopLeft(find.text('浇水')).dy;
      expect(gardenY, greaterThan(achievementsY),
          reason: '花园统计应在累计成就下方');
      expect(waterY, greaterThan(gardenY), reason: '四项统计应在分组标题下方');
    });

    testWidgets('四项数值各自取对 refType（四值互不相同，接错位必红）',
        (tester) async {
      await _pumpProfile(tester);

      expect(find.text('$kWater 次'), findsOneWidget, reason: '浇水次数取 plant_water');
      expect(find.text('$kFertilize 次'), findsOneWidget,
          reason: '施肥次数取 plant_fertilize');
      expect(find.text('$kWeed 次'), findsOneWidget, reason: '除草次数取 plant_weed');
      expect(find.text('$kPest 次'), findsOneWidget, reason: '除虫次数取 plant_pest');
      // 累计护眼不受影响（同一账本、不同 refType）。
      expect(find.text('7 次'), findsOneWidget);
    });

    testWidgets('全零也要显示（0 次），不能整块消失', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
          taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
          plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
          sunlightRepositoryProvider
              .overrideWithValue(_FakeSunlightRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
      ));
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('花园统计').evaluate().isNotEmpty) break;
      }

      expect(find.text('花园统计'), findsOneWidget);
      // 四项全 0 → 四张「0 次」卡片（还有其他统计可能也是 0，故只要求 ≥4）。
      expect(find.text('0 次'), findsAtLeastNWidgets(4));
    });

    testWidgets('英文界面：Garden stats / 四项译名', (tester) async {
      AppLocaleController.init(AppLanguage.en);
      await _pumpProfile(tester);

      expect(find.text('Garden stats'), findsOneWidget);
      expect(find.text('Watering'), findsOneWidget);
      expect(find.text('Fertilizing'), findsOneWidget);
      expect(find.text('Weeding'), findsOneWidget);
      expect(find.text('Pest removal'), findsOneWidget);
      expect(find.text('$kWater times'), findsOneWidget);
    });
  });
}
