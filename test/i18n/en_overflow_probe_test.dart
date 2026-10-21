/// EN 溢出探测测试（i18n B1，T05 收口）。
///
/// 探测口径：**最坏组合** —— 最窄手机档 `320×568` + English（普遍比 zh 长）+
/// `textScaler 1.3`（系统大字号）。在此组合下：
///  ① 最「宽」的孩子端页面（[GardenPage]，含花盆格 / 一键护理胶囊 / 顶栏余额）
///     有界 pump 若干帧 → 不抛布局异常（RenderFlex overflow 等）；
///  ② 两张统一弹窗壳（[showChildConfirmCard] / [showGoldNoticeDialog]）塞入
///     调用方解析好的**长英文串** → 不抛布局异常。
///
/// 说明：花园页有无限呼吸动画（木牌 / 奖励图标），全程用有界 `pump`，
/// 禁用 `pumpAndSettle`（同 qa_independent_round2_ef_test 的口径）。
library en_overflow_probe_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    as confirm;
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    as gold;

import '../helpers/no_hit_random.dart';

// ───────────────────────────────────────────────────────────────────────────
// 夹具（照搬 qa_independent_round2_ef_test 的最小 Fake 集）
// ───────────────────────────────────────────────────────────────────────────

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
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.sprout,
    stageStartedAt: now.subtract(const Duration(hours: 2)),
    growthProgress: 0.3,
    growthFactor: 1.0,
    status: PlantStatus.growing,
    plantedAt: now.subtract(const Duration(hours: 2)),
    lastWaterAt: now,
  );
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

// ───────────────────────────────────────────────────────────────────────────
// 宿主与口径
// ───────────────────────────────────────────────────────────────────────────

/// 最坏组合：320×568（最小手机档）+ textScaler 1.3。
void _useWorstCase(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Widget _gardenHost(SharedPreferences prefs) => ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider
            .overrideWithValue(_StoringPlantRepository(<Plant>[_sprout()])),
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

/// 裸宿主（挂弹窗壳用）：L10nScope 之下一个触发按钮，点击执行 [onTap]。
Widget _dialogHost(void Function(BuildContext) onTap) => MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: Builder(builder: (BuildContext context) {
            return Center(
              child: ElevatedButton(
                onPressed: () => onTap(context),
                child: const Text('open'),
              ),
            );
          }),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    // 显式切 en（非垫片路径 —— 显式 en 恒生效，最坏文案长度）。
    AppLocaleController.init(AppLanguage.en);
  });

  tearDown(() {
    AppLocaleController.init(AppLanguage.system);
  });

  testWidgets('① 最宽页 GardenPage：320×568 + en + 1.3 倍字号 → 无布局异常',
      (WidgetTester tester) async {
    _useWorstCase(tester);
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_gardenHost(prefs));
    // 有界 pump：跨过首帧异步加载 + 若干动画帧（花园页有无限呼吸动画，
    // 不能 pumpAndSettle）。布局异常会在 pump 期间被框架捕获记录。
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull,
        reason: 'EN + 1.3 倍字号 + 320 宽下花园页不得出现 RenderFlex overflow');
  });

  testWidgets('② 确认卡壳：EN 长文案 + 320×568 + 1.3 → 无布局异常',
      (WidgetTester tester) async {
    _useWorstCase(tester);

    await tester.pumpWidget(_dialogHost((BuildContext context) {
      // 文案由调用方（页级 scope）解析后传参 —— 弹窗壳铁律。
      confirm.showChildConfirmCard(
        context: context,
        title: 'Expand your garden and unlock a bigger sunny patch',
        rows: <confirm.ConfirmCardRow>[
          const confirm.ConfirmCardRow(
            icon: Icons.wb_sunny,
            name: 'Expansion cost (one-time)',
            value: '−30 ☀',
          ),
          const confirm.ConfirmCardRow(
            icon: Icons.account_balance_wallet_outlined,
            name: 'Current balance after expansion',
            value: '969 ☀',
            muted: true,
          ),
        ],
        note:
            'New pots start empty. Plant a seed in each pot to keep growing!',
        confirmLabel: 'OK, expand',
        cancelLabel: 'Cancel',
      );
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: '确认卡壳在 EN 长文案 + 最窄档 + 1.3 倍字号下不得溢出');
  });

  testWidgets('③ 金色通知卡壳：EN 长文案 + 320×568 + 1.3 → 无布局异常',
      (WidgetTester tester) async {
    _useWorstCase(tester);

    await tester.pumpWidget(_dialogHost((BuildContext context) {
      gold.showGoldNoticeDialog(
        context,
        title: 'All growth tasks completed today!',
        items: <gold.GoldNoticeItem>[
          const gold.GoldNoticeItem(
            icon: Icons.task_alt,
            name: 'Morning reading (a very long task name indeed)',
            amountText: '+12 ☀',
          ),
          const gold.GoldNoticeItem(
            icon: Icons.task_alt,
            name: 'Jump rope',
            amountText: '',
            subtitle: 'Daily growth reward cap reached',
          ),
        ],
        footerText:
            'Earned 8 sunlight in total (1 item hit the daily cap, not credited)',
      );
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: '金色通知卡壳在 EN 长文案 + 最窄档 + 1.3 倍字号下不得溢出');
  });
}
