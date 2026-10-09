/// 独立复验（QA/Edward）· P0-③ 一键护理音效 + P1-④ 种植音效（**行为级**，非源码字符串守卫）。
///
/// 工程用例 `one_click_care_sfx_guard_test.dart` 只是 `grep` 源码字符串（弱测试）。本文件
/// 用项目**既有可注入钩子** `just_audio` 的 `JustAudioPlatform.instance` 打桩（记录型假平台），
/// 在**真实 GardenPage** 上跑完整交互链路，断言音频资产**确实被加载**：
///   · D1 一键护理（**仅杂草**）→ 恰好加载一次 `care_weed.mp3`（且**不**加载 `care_pest.mp3`）；
///   · D2 种植成功 → 恰好加载一次 `cultivate.mp3`；
///   · D3 种植「取消」→ **不**加载 `cultivate.mp3`（失败/取消路径不得播音）。
library qa_independent_p0_care_sfx_behavior_test;

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
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

import '../helpers/no_hit_random.dart';

// ── 记录型假 just_audio 平台（可注入钩子，项目既有平台接口）────────────────────

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
      bgmOn: false, // 关掉氛围音，避免背景 BGM 污染音频记录
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

/// 4 株「有杂草」的活株（可触发一键护理；weedPestRollDay=今天 → 刷新不重 roll）。
List<Plant> _fourWeedySprouts() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
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
        weedAt: today,
        weedPestRollDay: today,
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

Widget _host(PlantRepository plants) => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
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

int _countLoads(String substr) =>
    _fake.log.where((String e) => e.startsWith('load:') && e.contains(substr)).length;

/// 自适应排空：交替 `runAsync`（真实异步窗口）+ `pump`（假时钟微任务排空），
/// 直到 [ready] 为真（或达 [maxRounds] 上限）——替代**定长窗口**，避免并行全量
/// 高负载下真实 `setAsset` I/O 未跑完而误判（QA 2026-10-07 修：消除偶发红）。
/// 达标后再补 [extraRounds] 轮，让「恰好一次」计数稳定。
Future<void> _drainUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxRounds = 100,
  int extraRounds = 12,
  Duration step = const Duration(milliseconds: 60),
}) async {
  for (int i = 0; i < maxRounds; i++) {
    if (ready()) break;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  for (int i = 0; i < extraRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() async {
    _fake.log.clear();
    // path_provider：just_audio 的 setAsset 会把资产拷到临时缓存目录。
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_sfx');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets('D1 一键护理（仅杂草）成功 → 恰好加载一次 care_weed.mp3（且不加载 care_pest.mp3）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_fourWeedySprouts())));

    final bool fabShown = await _pumpUntil(
      tester,
      () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
    );
    expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

    await tester.tap(find.byIcon(Icons.touch_app));
    await _pumpUntil(tester, () => find.text('一键护理').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('一键护理'));

    await _pumpUntil(tester, () => find.text('要一键护理吗？').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定'));
    // onPressed 同步触发 playSfx（fire-and-forget）；just_audio 的 setAsset 是多次
    // 真实 I/O（rootBundle→临时文件），FakeAsync 下不会推进 → 交替「真实异步窗口
    // (runAsync) + 假时钟微任务排空 (pump)」把整条异步链跑完。**自适应**：轮询到
    // care_weed 真加载（防并行全量高负载下定长窗口跑不完 → 偶发红）。
    await _drainUntil(
        tester, () => _countLoads('audio/sfx/care_weed.mp3') >= 1);

    expect(_countLoads('audio/sfx/care_weed.mp3'), 1,
        reason: '一键护理（**仅杂草**）→ 按实际内容恰好播一次除草音效 care_weed.mp3（整批一次）');
    expect(_countLoads('audio/sfx/care_pest.mp3'), 0,
        reason: '仅杂草不应播除虫音效（玄参 2026-10-07 口径修订：按实际护理内容选音效）');
  });

  testWidgets('D2 种植成功 → 恰好加载一次 cultivate.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 空花园：首株向日葵免费。
    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[])));

    // 点第一个空花盆 → 选种弹窗。
    final Finder emptyPot = find.byType(EmptyPot);
    await _pumpUntil(tester, () => emptyPot.evaluate().isNotEmpty);
    expect(emptyPot.evaluate(), isNotEmpty, reason: '空花园应有空花盆');
    await tester.tap(emptyPot.first);
    final bool sheetShown = await _pumpUntil(
        tester, () => find.text('选择要种的植物').evaluate().isNotEmpty);
    expect(sheetShown, isTrue, reason: '点空盆应弹出选种弹窗');

    await tester.tap(find.text('免费'));
    final bool confirmShown = await _pumpUntil(
        tester, () => find.text('要种下向日葵吗？').evaluate().isNotEmpty);
    expect(confirmShown, isTrue, reason: '选免费应弹二次确认');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确定种植'));
    await _drainUntil(
        tester, () => _countLoads('audio/sfx/cultivate.mp3') >= 1);

    expect(_countLoads('audio/sfx/cultivate.mp3'), 1,
        reason: '种植成功后应恰好加载一次 cultivate.mp3');
  });

  testWidgets('D3 种植「取消」→ 不加载 cultivate.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(<Plant>[])));

    final Finder emptyPot = find.byType(EmptyPot);
    await _pumpUntil(tester, () => emptyPot.evaluate().isNotEmpty);
    await tester.tap(emptyPot.first);
    await _pumpUntil(
        tester, () => find.text('选择要种的植物').evaluate().isNotEmpty);
    await tester.tap(find.text('免费'));
    await _pumpUntil(
        tester, () => find.text('要种下向日葵吗？').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    // 取消路径不应播音效：给足排空窗口（若真会播，此时也必然已加载）。
    await _drainUntil(tester, () => false, maxRounds: 15, extraRounds: 0);

    expect(_countLoads('audio/sfx/cultivate.mp3'), 0,
        reason: '取消种植不得播放种植音效（失败/取消路径不播）');
  });
}
