/// 花园页「头顶奖励图标」UI 测试（玄参 2026-09-27「奖励物图标化 + 掉落即定奖」，任务 #6）。
///
/// 覆盖 4 类：
///  ① **图标数量 / 类型**：按奖励三列派生（阳光 / 植物碎片 / 种子 / 礼包），与角标数值；
///  ② **点击消失 + 账本恰一次**：点任一图标 → 收下该条 pending 全部奖励 → 图标消失、不重复入账；
///  ③ **花谢自动到账提示**：未盛开植物的到期奖励 → tickAll 兜底 → SnackBar 提示「奖励已自动收下」；
///  ④ **窄屏不 overflow**：最坏 ~4 图标 + 3 列窄屏 → 不抛 overflow（FittedBox 缩放）。
///
/// ⚠️ 花园页木牌默认 `animate: true`（无限呼吸动画）→ 一律 `pumpAndSettle` 会永不返回，
///    故用**有界 `pump`** 推进（同 `garden_layout_v3_test` / `garden_bloom_reward_ui_test` 的手法）。
library garden_reward_icons_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

// ── 假仓储 ──────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 一株「盛开且本 tick 不枯萎」的植物（2 天前开花 / 2 天前浇水）。
Plant _bloomedPlant(DateTime now) {
  final DateTime bloomAt = now.subtract(const Duration(days: 2));
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.adult,
    stageStartedAt: bloomAt,
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: PlantStatus.bloomed,
    plantedAt: bloomAt,
    lastWaterAt: bloomAt,
    bloomedAt: bloomAt,
    bloomCount: 1,
    mood: PlantMood.calm,
  );
}

/// 一株「成长中（progress<1，本 tick 不会盛开）」的植物：其到期奖励走花谢兜底。
Plant _growingPlant(DateTime now) => Plant(
      id: 'p1',
      speciesId: 'species_sunflower',
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: now,
      growthProgress: 0.5,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: now,
      mood: PlantMood.calm,
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

/// 账本 Fake：记录全部 append 条目（供「账本恰一次」断言）。
class _FakeSunlightRepository implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);
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
  _FakePlantRepository(this._plants);
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
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

// ── 辅助 ────────────────────────────────────────────────────────────────────

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

int _iconCount(IconData icon) => find.byIcon(icon).evaluate().length;

/// 组装 GardenPage（带可注入的账本 / 待收集奖励 / 资源集合）。
Future<void> _pumpGarden(
  WidgetTester tester, {
  required Plant plant,
  required InMemoryBloomRewardRepository bloom,
  required _FakeSunlightRepository ledger,
  Size size = const Size(360 * 3, 780 * 3),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      sunlightRepositoryProvider.overrideWithValue(ledger),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      plantRepositoryProvider
          .overrideWithValue(_FakePlantRepository(<Plant>[plant])),
      bloomRewardRepositoryProvider.overrideWithValue(bloom),
      // 空资源集合 → 头顶图标全回退内置 Icons（测试无需真实素材）。
      rewardAssetsProvider.overrideWith((ref) => <String>{}),
    ],
    child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
  ));
}

PendingBloomReward _pending({
  required String id,
  required DateTime dueAt,
  required String kind,
  int sunlight = 0,
  int fragments = 0,
  String? speciesId,
}) =>
    PendingBloomReward(
      id: id,
      plantId: 'p1',
      dueAt: dueAt,
      rewardKind: kind,
      rewardSunlight: sunlight,
      rewardFragments: fragments,
      rewardSpeciesId: speciesId,
    );

void main() {
  // ── ① 图标数量 / 类型 ────────────────────────────────────────────────────
  testWidgets('奖励三列派生图标：阳光 / 植物碎片 各就位（含角标）', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    // 开花瞬间：阳光 10 + 植物碎片 1；晨露：阳光 12（C45 聚合后阳光合计 +22）。
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_instant',
      dueAt: now.subtract(const Duration(hours: 1)),
      kind: kBloomRewardPhaseInstant,
      sunlight: 10,
      fragments: 1,
    ));
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_second',
      dueAt: now.subtract(const Duration(hours: 2)),
      kind: kBloomRewardKindNormal,
      sunlight: 12,
    ));

    await _pumpGarden(tester, plant: _bloomedPlant(now), bloom: bloom, ledger: ledger);

    final bool appeared = await _pumpUntil(
      tester,
      () => _iconCount(Icons.wb_sunny) >= 1,
    );
    expect(appeared, isTrue, reason: '应出现阳光图标');

    // C45 聚合口径：两条 pending 的阳光合并为一个图标（+22），碎片独立一个（×1）。
    expect(_iconCount(Icons.wb_sunny), 1, reason: '两条 pending 的阳光聚合为一个图标');
    expect(_iconCount(Icons.auto_awesome), 1, reason: '一条含植物碎片 → 1 个碎片图标');
    expect(_iconCount(Icons.eco), 0, reason: '无种子 → 无种子图标');
    expect(_iconCount(Icons.card_giftcard), 0, reason: '均已预先定奖 → 无礼包图标');
    // 角标数值来自真实数据（阳光合计 10+12=22）。
    expect(find.text('+22'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });

  testWidgets('历史行（0/0/null 哨兵）→ 加载时物化为明细图标（不再礼物盒）',
      (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    // 三列默认 0/0/null → 哨兵（v12 之前的旧数据）。
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_legacy',
      dueAt: now.subtract(const Duration(hours: 1)),
      kind: kBloomRewardKindNormal,
    ));

    await _pumpGarden(tester, plant: _bloomedPlant(now), bloom: bloom, ledger: ledger);
    // 加载时 materializeLegacyBloomRewards 把哨兵回写为真实奖励内容 → 显示明细、不再礼物盒。
    final bool appeared = await _pumpUntil(
      tester,
      () =>
          _iconCount(Icons.wb_sunny) +
              _iconCount(Icons.auto_awesome) +
              _iconCount(Icons.eco) >=
          1,
    );
    expect(appeared, isTrue, reason: '哨兵历史行应物化为明细图标');
    expect(_iconCount(Icons.card_giftcard), 0,
        reason: '物化后不再显示通用礼包图标');
    // 第二段奖励恒一项明细（随机落阳光/碎片/种子其一），合计恰 1。
    expect(
      _iconCount(Icons.wb_sunny) +
          _iconCount(Icons.auto_awesome) +
          _iconCount(Icons.eco),
      1,
      reason: '第二段奖励恰一项明细',
    );
  });

  // ── ② 点击消失 + 账本恰一次 ──────────────────────────────────────────────
  testWidgets('点击图标 → 收下该条全部奖励、图标消失；账本恰一次、不重复', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    // 即刻可收集的开花瞬间：阳光 6（= 普通保底，恰一笔），无额外。
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_instant',
      dueAt: now.subtract(const Duration(hours: 1)),
      kind: kBloomRewardPhaseInstant,
      sunlight: kBloomInstantSunlight,
    ));

    await _pumpGarden(tester, plant: _bloomedPlant(now), bloom: bloom, ledger: ledger);
    expect(await _pumpUntil(tester, () => _iconCount(Icons.wb_sunny) >= 1), isTrue);

    // 让入场动画（有限时长）走完，避免误点在缩放中途。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.wb_sunny));
    final bool gone = await _pumpUntil(tester, () => _iconCount(Icons.wb_sunny) == 0);
    expect(gone, isTrue, reason: '收集后头图消失');

    final List<SunlightEntry> earns = ledger.entries
        .where((SunlightEntry e) => e.refType == kBloomRewardRefType)
        .toList();
    expect(earns, hasLength(1), reason: '账本恰一次');
    expect(earns.first.net, kBloomInstantSunlight);

    // 再 pump 数帧：不得重复入账。
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      ledger.entries.where((SunlightEntry e) => e.refType == kBloomRewardRefType),
      hasLength(1),
      reason: '重复不发放',
    );
    expect(await bloom.pendingBloomRewardsDue(DateTime.now()), isEmpty,
        reason: '已收集（claimed）');
  });

  // ── ③ 花谢自动到账提示 ───────────────────────────────────────────────────
  testWidgets('未盛开植物的到期奖励 → tickAll 兜底并提示「奖励已自动收下」',
      (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_second',
      dueAt: now.subtract(const Duration(hours: 1)),
      kind: kBloomRewardKindNormal,
      sunlight: 12,
    ));

    // 成长中（不会盛开）→ 到期奖励走花谢兜底自动到账。
    await _pumpGarden(tester, plant: _growingPlant(now), bloom: bloom, ledger: ledger);

    final bool toast = await _pumpUntil(
      tester,
      () => find.textContaining('奖励已自动收下').evaluate().isNotEmpty,
    );
    expect(toast, isTrue, reason: '花谢自动到账也要提示');
    expect(find.textContaining('+12 ☀ 阳光'), findsOneWidget,
        reason: '提示数值来自实际发放结果');

    final List<SunlightEntry> earns = ledger.entries
        .where((SunlightEntry e) => e.refType == kBloomSecondPhaseRefType)
        .toList();
    expect(earns, hasLength(1), reason: '自动到账恰一次');
    expect(earns.first.net, 12);
  });

  // ── ④ 窄屏不 overflow ────────────────────────────────────────────────────
  testWidgets('窄屏 + 多条目聚合 3 图标 → 不 overflow', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _FakeSunlightRepository ledger = _FakeSunlightRepository();
    final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
    // 开花瞬间：阳光 + 碎片；晨露：阳光 + 种子（C45 聚合 → 阳光 +19 / 碎片 / 种子）。
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_instant',
      dueAt: now.subtract(const Duration(hours: 1)),
      kind: kBloomRewardPhaseInstant,
      sunlight: 10,
      fragments: 1,
    ));
    await bloom.insertPendingBloomReward(_pending(
      id: 'pr_second',
      dueAt: now.subtract(const Duration(hours: 2)),
      kind: kBloomRewardKindNormal,
      sunlight: 9,
      speciesId: 'species_tomato',
    ));

    // 窄屏（320 宽 3 列 → 单格 ~94px；聚合后 3 图标 ×42 ≈ 126 → 仍需缩放防溢出）。
    await _pumpGarden(
      tester,
      plant: _bloomedPlant(now),
      bloom: bloom,
      ledger: ledger,
      size: const Size(320 * 3, 640 * 3),
    );

    expect(await _pumpUntil(tester, () => _iconCount(Icons.wb_sunny) >= 1), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: '窄屏不得 overflow（FittedBox 缩放）');
    // 聚合后 3 个图标（阳光合计 / 碎片 / 种子），缩放而非丢弃。
    expect(_iconCount(Icons.wb_sunny), 1);
    expect(_iconCount(Icons.auto_awesome), 1);
    expect(_iconCount(Icons.eco), 1);
  });
}
