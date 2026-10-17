/// C82 复现（玄参 2026-10-16 小米真机 · 花园两 Bug）：**先在未修复代码上跑红灯**。
///
/// ## Bug1 · 「枯萎的盛开成株浇水救活后，盛开演出播了两次」
/// 域层机制（已确认）：`wilting` 浇水 → `_maybeRecover` 重建为 `growing`（保留
/// `growthProgress == 1.0` 与 `bloomedAt`）→ **下一 tick** `_advanceGrowth` 立刻命中
/// `adult && progress ≥ 1.0-ε` → `bloomed`。页面 diff（`_detectGrowthTransitions`）判
/// `wilting → bloomed` 触发 [GrowTransition.adultToBloomed] 演出。
///
/// 本文件在**真实 GardenPage** 上驱动「浇水」全链路，统计 [GrowthFxOverlay] 的
/// **State 实例集合**：`> 1` 即「播了两次」——既覆盖「`_playGrowthFx` 被调两次」，
/// 也覆盖「`_activeEffect` 进出导致 Stack 子元素错位 → overlay 被 **remount**（State 重建）
/// → 动画从第 0 帧重放」两种机制（两者症状都是「盛开帧播两次」）。
///
/// ## Bug2 · 「浇水 / 施肥 / 除草 / 除虫四种养护音效全无」
/// 在真实 GardenPage 上接**记录型假 just_audio 平台**，断言四种养护动作各自真实
/// **加载**了对应 `care_*.mp3`。
///   · 浇水 / 施肥：动作会触发成长跃迁 → `_playGrowthFx` 会**后发起**一路成长 SFX。
///     既有 F116 口径「后发起者赢，先发起者让位且绝不回头停别人」下，**先发起的养护 cue
///     可能被随后发起的成长 cue 静默作废**（真机冷启动 `_sfx` 首次初始化数百 ms，养护 cue
///     卡在那里时被超越 → 资产从未加载 = 「有动画没声音」）。
///   · 除草 / 除虫：无成长跃迁（不触发成长 cue）→ 若无声音，说明另有作废源。
///
/// ⚠️ 时间戳一律**相对 `DateTime.now()`**：写死时间戳越过 `kPlantWiltDays=3` 会被
/// 结算成 wilting/dead 而误红（项目硬规则）。
/// ⚠️ 单例 [AudioService.instance] 跨用例残留 → 每个用例先 [AudioService.resetForTest]。
library garden_care_repro_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

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
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';

import '../helpers/no_hit_random.dart';

// ── 记录型假 just_audio 平台 ─────────────────────────────────────────────────

class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id, this.log);
  final List<String> log;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage m = request.audioSourceMessage;
    final String uri = m is UriAudioSourceMessage ? m.uri : m.toString();
    log.add('load:$uri');
    scheduleMicrotask(() => _events.add(PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updateTime: DateTime.now(),
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          duration: const Duration(seconds: 4),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        )));
    return LoadResponse(duration: const Duration(seconds: 4));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    log.add('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
                  request) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();
  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();
}

class _RecPlatform extends JustAudioPlatform {
  final List<String> log = <String>[];
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _RecPlayer(request.id, log);
  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse.fromMap(<dynamic, dynamic>{});
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{});
}

late final _RecPlatform _fake;

int _countLoads(String substr) => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains(substr))
    .length;

// ── 假仓储 ──────────────────────────────────────────────────────────────────

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
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
      bgmOn: false, // 关掉氛围音，隔离音频记录（只关心 SFX）
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

/// 一株「盛开成株、离席多日」的植物：`bloomedAt` 在花期窗口内（< 3 天，花谢循环不触发）、
/// `lastWaterAt` 已 ≥ [kPlantWiltDays] 天（下一 tick 必枯萎）。时间戳全部相对 now。
Plant _ageingBloomedAdult() {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.adult,
    stageStartedAt: now.subtract(const Duration(days: 1)),
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: PlantStatus.bloomed,
    plantedAt: now.subtract(const Duration(days: 12)),
    lastWaterAt: now.subtract(const Duration(days: 4)),
    bloomedAt: now.subtract(const Duration(days: 1)),
    bloomCount: 1,
    mood: PlantMood.calm,
  );
}

/// 一株「有杂草的活株」：用于除草动作（无成长跃迁）的音效复现。
Plant _weedySprout() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
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
    weedAt: today,
    weedPestRollDay: today,
  );
}

/// 一株「有害虫的活株」：用于除虫动作（无成长跃迁）的音效复现。
Plant _pestySprout() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
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
    pestAt: today,
    weedPestRollDay: today,
  );
}

/// 一株「已枯萎的盛开成株、且**今日已浇过一次水**」：用于施肥触发「救活回跳」的音效复现。
///
/// [wiltedAtDelta] 用于配合预置的 `plant_water` 账本行（`ts ≥ wiltedAt` 才算「枯萎后浇水」，
/// 满足 `_maybeRecover` 的软救活条件 `w ≥ 1`）——这样**施肥**也能救活。
Plant _wiltingBloomedWithPriorWater(DateTime wiltedAt) {
  final DateTime now = DateTime.now();
  return Plant(
    id: 'p1',
    speciesId: 'species_sunflower',
    potIndex: 0,
    stage: PlantStage.adult,
    stageStartedAt: now.subtract(const Duration(days: 1)),
    growthProgress: 1.0,
    growthFactor: 1.0,
    status: PlantStatus.wilting,
    plantedAt: now.subtract(const Duration(days: 12)),
    lastWaterAt: now.subtract(const Duration(days: 4)),
    wiltedAt: wiltedAt,
    bloomedAt: now.subtract(const Duration(days: 1)),
    bloomCount: 1,
    mood: PlantMood.thirsty,
  );
}

Widget _host(PlantRepository plants, {_FakeSunlightRepository? ledger}) =>
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider
            .overrideWithValue(ledger ?? _FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(plants),
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
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

/// 交替「真实异步窗口（runAsync）+ 假时钟微任务排空（pump）」推进整条链路。
Future<void> _drainUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxRounds = 120,
  int extraRounds = 12,
  Duration realStep = const Duration(milliseconds: 40),
  Duration fakeStep = const Duration(milliseconds: 80),
}) async {
  for (int i = 0; i < maxRounds; i++) {
    if (ready()) break;
    await tester.runAsync(() => Future<void>.delayed(realStep));
    await tester.pump(fakeStep);
  }
  for (int i = 0; i < extraRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(realStep));
    await tester.pump(fakeStep);
  }
}

/// 一边推进、一边收集 [GrowthFxOverlay] 出现过的**所有 State 实例**。
///
/// State 实例集合大小 = 该组件被**挂载**的次数（remount 会新建 State）：
///  · `== 1` → 盛开演出只播一场（正确）；
///  · `> 1`  → 播了两次（真机 Bug1）。
Future<Set<Object>> _drainCollectingGrowthStates(
  WidgetTester tester, {
  int rounds = 200,
  Duration realStep = const Duration(milliseconds: 30),
  Duration fakeStep = const Duration(milliseconds: 100),
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
    await tester.runAsync(() => Future<void>.delayed(realStep));
    await tester.pump(fakeStep);
  }
  return seen;
}

/// 点有植物的花盆 → 弹出养护卡 → 点 [button]（浇水 / 施肥图标）。
Future<void> _openCareAndTap(WidgetTester tester, Finder button) async {
  final Finder pot = find.byType(GardenPot);
  await _drainUntil(tester, () => pot.evaluate().isNotEmpty, maxRounds: 60);
  expect(pot.evaluate(), isNotEmpty, reason: '前置：花盆（有植物）应已渲染');
  await tester.tap(pot.first);
  await _drainUntil(tester, () => button.evaluate().isNotEmpty, maxRounds: 80);
  expect(button.evaluate(), isNotEmpty, reason: '前置：养护卡应出现目标按钮');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(button.first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() async {
    // ⚠️ 单例跨用例残留：必须复位（否则上个用例 Zone 的播放器带进来 → setAsset 挂死）。
    AudioService.instance.resetForTest();
    _fake.log.clear();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('care_repro');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets('Bug1 复现：枯萎的盛开成株浇水救活 → 盛开演出被挂载播放的次数', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_ageingBloomedAdult()])));
    // 首屏加载 + 首 tick（应把植物结算成 wilting）。
    await _drainUntil(tester, () => find.byType(GardenPot).evaluate().isNotEmpty,
        maxRounds: 60);
    await tester.pump(const Duration(milliseconds: 200));

    await _openCareAndTap(tester, find.byIcon(Icons.water_drop));
    final Set<Object> growthStates = await _drainCollectingGrowthStates(tester);

    // 🟥 红灯判据（未修复）：盛开演出被挂载 > 1 次 = 播了两次。
    expect(growthStates.length, 1,
        reason: 'Bug1：一次「浇水救活」只应触发**一场**盛开演出；'
            'State 实例数 > 1 表示演出被重复挂载（播了两次）—— 玄参小米真机实测。'
            '实测挂载次数 = ${growthStates.length}');
  });

  testWidgets('Bug2 复现：浇水养护音效 care_water.mp3 是否被真实加载', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_ageingBloomedAdult()])));
    await _drainUntil(tester, () => find.byType(GardenPot).evaluate().isNotEmpty,
        maxRounds: 60);
    await tester.pump(const Duration(milliseconds: 200));

    await _openCareAndTap(tester, find.byIcon(Icons.water_drop));
    await _drainUntil(
      tester,
      () =>
          _countLoads('care_water.mp3') >= 1 ||
          _fake.log.where((String e) => e == 'play').isNotEmpty,
      maxRounds: 120,
      extraRounds: 15,
    );

    // 🟥 红灯判据（未修复）：养护音效应真实加载 care_water.mp3。
    expect(_countLoads('audio/sfx/care_water.mp3'), greaterThanOrEqualTo(1),
        reason: 'Bug2：浇水养护音效必须真实加载 care_water.mp3；'
            '实测 load 序列 = ${_fake.log.where((e) => e.startsWith("load:")).toList()}');
  });

  testWidgets('Bug2 复现：除草养护音效 care_weed.mp3 是否被真实加载', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_weedySprout()])));
    await _drainUntil(tester, () => find.byType(GardenPot).evaluate().isNotEmpty,
        maxRounds: 60);
    await tester.pump(const Duration(milliseconds: 200));

    // 点花盆上的杂草浮标（除草）——直接走「除草动画 + 音效」路径。
    // 浮标 = Semantics(label: '有杂草，点我拔掉 +N ☀') 包住的 GestureDetector。
    final Finder weed = find.bySemanticsLabel(RegExp('有杂草'));
    await _drainUntil(tester, () => weed.evaluate().isNotEmpty, maxRounds: 60);
    expect(weed.evaluate(), isNotEmpty, reason: '前置：有杂草的植物应显示除草浮标');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(weed.first);

    await _drainUntil(
      tester,
      () =>
          _countLoads('care_weed.mp3') >= 1 ||
          _fake.log.where((String e) => e == 'play').isNotEmpty,
      maxRounds: 120,
      extraRounds: 15,
    );

    expect(_countLoads('audio/sfx/care_weed.mp3'), greaterThanOrEqualTo(1),
        reason: 'Bug2：除草养护音效必须真实加载 care_weed.mp3；'
            '实测 load 序列 = ${_fake.log.where((e) => e.startsWith("load:")).toList()}');
  });

  testWidgets('Bug2 复现：施肥养护音效 care_fertilize.mp3 是否被真实加载', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime.now();
    // 枯萎起点 = 1 分钟前（< 3 天 → 软救活，浇水 1 次即可）；预置一条「枯萎后」的浇水行
    // 满足 w ≥ 1 → **施肥**亦可救活 → 触发 adultToBloomed 演出（与浇水同款竞态）。
    final _FakeSunlightRepository ledger = _FakeSunlightRepository()
      ..entries.add(SunlightEntry(
        id: 'seed_water',
        ts: now.subtract(const Duration(seconds: 30)),
        type: SunlightType.plant,
        gross: 1,
        net: -1,
        balanceAfter: 999,
        refType: 'plant_water',
        refId: 'p1',
        dayKey: '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}',
      ));

    await tester.pumpWidget(_host(
      _StoringPlantRepository(
          <Plant>[_wiltingBloomedWithPriorWater(now.subtract(const Duration(minutes: 1)))]),
      ledger: ledger,
    ));
    await _drainUntil(tester, () => find.byType(GardenPot).evaluate().isNotEmpty,
        maxRounds: 60);
    await tester.pump(const Duration(milliseconds: 200));

    await _openCareAndTap(tester, find.byIcon(Icons.eco));
    await _drainUntil(
      tester,
      () =>
          _countLoads('care_fertilize.mp3') >= 1 ||
          _fake.log.where((String e) => e == 'play').isNotEmpty,
      maxRounds: 120,
      extraRounds: 15,
    );

    expect(_countLoads('audio/sfx/care_fertilize.mp3'), greaterThanOrEqualTo(1),
        reason: 'Bug2：施肥养护音效必须真实加载 care_fertilize.mp3；'
            '实测 load 序列 = ${_fake.log.where((e) => e.startsWith("load:")).toList()}');
  });

  testWidgets('Bug2 复现：除虫养护音效 care_pest.mp3 是否被真实加载', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[_pestySprout()])));
    await _drainUntil(tester, () => find.byType(GardenPot).evaluate().isNotEmpty,
        maxRounds: 60);
    await tester.pump(const Duration(milliseconds: 200));

    final Finder pest = find.bySemanticsLabel(RegExp('有害虫'));
    await _drainUntil(tester, () => pest.evaluate().isNotEmpty, maxRounds: 60);
    expect(pest.evaluate(), isNotEmpty, reason: '前置：有害虫的植物应显示除虫浮标');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(pest.first);

    await _drainUntil(
      tester,
      () =>
          _countLoads('care_pest.mp3') >= 1 ||
          _fake.log.where((String e) => e == 'play').isNotEmpty,
      maxRounds: 120,
      extraRounds: 15,
    );

    expect(_countLoads('audio/sfx/care_pest.mp3'), greaterThanOrEqualTo(1),
        reason: 'Bug2：除虫养护音效必须真实加载 care_pest.mp3；'
            '实测 load 序列 = ${_fake.log.where((e) => e.startsWith("load:")).toList()}');
  });
}
