/// QA 独立反证 · 第二批 B / C 项（2026-10-07）。
///
/// 覆盖：
///   · B① 一键护理「空计划」→ **不播任何音效**（0 次 sfx 加载）；
///   · C  一键「浇水 / 施肥」空计划 + 「阳光不足」→ **居中浮层**（非 SnackBar）、
///        约 1.5s 自清、`IgnorePointer` 不挡点击。
///
/// 真实 `GardenPage(embedded:true)` + 记录型假 `JustAudioPlatform.instance`
/// （断言真实加载的音频资产路径）。⚠️ 花园页木牌无限呼吸动画 → 全程有界 `pump`。
library qa_independent_round2_ui_test;

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
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';

import '../helpers/no_hit_random.dart';

// ── 记录型假 just_audio 平台 ────────────────────────────────────────────────

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

int _sfxLoads() => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains('audio/sfx/'))
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
      gardenPotCapacity: 6,
      bgmOn: false,
    );

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => _settings();
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 可配置的假阳光/账本仓储：`balance` / 今日浇水施肥次数 / 最近浇水时间可控。
class _FakeLedger implements SunlightRepository {
  _FakeLedger({
    this.balanceV = 999.0,
    this.waterUsedToday = 0,
    this.fertilizeUsedToday = 0,
  });
  final double balanceV;
  final int waterUsedToday;
  final int fertilizeUsedToday;

  @override
  Future<double> balance() async => balanceV;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
      String refType, String refId, String dayKey) async {
    if (refType == 'plant_water') return waterUsedToday;
    if (refType == 'plant_fertilize') return fertilizeUsedToday;
    return 0;
  }

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;

  @override
  Future<double> append(SunlightEntry entry) async => balanceV;
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
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
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

/// 4 株「幼苗 · 成长中 · 无杂草无害虫」健康株（一键护理计划为空）。
List<Plant> _fourHealthySprouts() {
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
        lastWaterAt: now,
      ),
  ];
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

Widget _host(PlantRepository plants, SunlightRepository ledger) => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(ledger),
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

/// 点 FAB → 选 [label] 项 → 等居中浮层出现。
Future<void> _tapOneClick(WidgetTester tester, String label) async {
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');
  await tester.tap(find.byIcon(Icons.touch_app));
  await _pumpUntil(tester, () => find.text(label).evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label));
}

void _expectCenteredHint(WidgetTester tester, String text) {
  expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isNotEmpty,
      reason: '应弹出居中浮层（kOneClickBatchHintPillKey）');
  expect(find.text(text), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing,
      reason: '空提示不得再走底部 SnackBar');
  // IgnorePointer：浮层不挡任何点击。
  expect(
    find.ancestor(
        of: find.byKey(kOneClickBatchHintPillKey),
        matching: find.byType(IgnorePointer)),
    findsWidgets,
    reason: '浮层必须包在 IgnorePointer 内（不挡点击）',
  );
  final Offset pill = tester.getCenter(find.byKey(kOneClickBatchHintPillKey));
  const Size logical = Size(390, 844);
  final Offset center = Offset(logical.width / 2, logical.height / 2);
  expect((pill.dx - center.dx).abs(), lessThan(kOneClickBatchHintCenterTolerance),
      reason: '水平居中');
  expect((pill.dy - center.dy).abs(), lessThan(kOneClickBatchHintCenterTolerance),
      reason: '垂直居中');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() async {
    _fake.log.clear();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_r2_ui');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets('B① 一键护理（空计划）→ 不播任何音效（0 次 sfx 加载）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester
        .pumpWidget(_host(_StoringPlantRepository(_fourHealthySprouts()), _FakeLedger()));
    await _tapOneClick(tester, '一键护理');
    await _pumpUntil(tester, () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty);
    // 把可能的音频异步链跑完。
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }

    expect(find.text('没有需要护理的植物'), findsOneWidget);
    expect(_sfxLoads(), 0,
        reason: 'B①：一键护理空计划不得播放任何音效（含 care_weed / care_pest）');
  });

  testWidgets('C-浇水 空计划 → 居中浮层「今天没有可浇水的植物」、无 SnackBar、约 1.5s 自清',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 今日浇水已达上限 3 次 → 一键浇水计划为空。
    final _FakeLedger ledger = _FakeLedger(waterUsedToday: 3);
    await tester
        .pumpWidget(_host(_StoringPlantRepository(_fourHealthySprouts()), ledger));
    await _tapOneClick(tester, '一键浇水');
    await _pumpUntil(tester, () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty);

    _expectCenteredHint(tester, '今天没有可浇水的植物');
    expect(_sfxLoads(), 0, reason: '空计划不得播音效');

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isEmpty,
        reason: '浮层应约 1.5s 后淡出自清');
  });

  testWidgets('C-施肥 空计划 → 居中浮层「今天没有可施肥的植物」',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 今日施肥已达上限 1 次 → 一键施肥计划为空。
    final _FakeLedger ledger = _FakeLedger(fertilizeUsedToday: 1);
    await tester
        .pumpWidget(_host(_StoringPlantRepository(_fourHealthySprouts()), ledger));
    await _tapOneClick(tester, '一键施肥');
    await _pumpUntil(tester, () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty);

    _expectCenteredHint(tester, '今天没有可施肥的植物');
    expect(_sfxLoads(), 0, reason: '空计划不得播音效');
  });

  testWidgets('C-阳光不足 → 居中浮层「阳光不足…」、无 SnackBar（整体拦截）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 可浇水（无上限阻塞）但余额 0 < 计划合计（4×5=20）→ 阳光不足。
    final _FakeLedger ledger = _FakeLedger(balanceV: 0);
    await tester
        .pumpWidget(_host(_StoringPlantRepository(_fourHealthySprouts()), ledger));
    await _tapOneClick(tester, '一键浇水');
    await _pumpUntil(tester, () => find.byKey(kOneClickBatchHintPillKey).evaluate().isNotEmpty);

    expect(find.byKey(kOneClickBatchHintPillKey).evaluate(), isNotEmpty,
        reason: '阳光不足应弹居中浮层（整体拦截）');
    expect(find.textContaining('阳光不足'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    // 不得扣费 / 不播音效。
    expect(_sfxLoads(), 0, reason: '阳光不足整体拦截，不得播音效');
  });
}
