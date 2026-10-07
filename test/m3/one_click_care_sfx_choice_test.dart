/// B 项（玄参 2026-10-07）：一键护理音效按**实际护理内容**选——
/// 「如果只有杂草，就播放除草的音效；如果有除虫和除草，就播放除虫的音效」。
///
/// 三条**行为级**断言（真实 `GardenPage` + 记录型假 `JustAudioPlatform.instance`，
/// 断言真实加载的音频资产路径；不使用源码字符串守卫）：
///   · 仅杂草 → `care_weed.mp3`（且**不**加载 `care_pest.mp3`）；
///   · 草 + 虫 → `care_pest.mp3`；
///   · 仅害虫 → `care_pest.mp3`。
/// 整批仍**只播一次**（不逐株、不叠加）。
///
/// ⚠️ 音频真实 I/O（`setAsset` 拷贝到临时目录）在 FakeAsync 下不推进 → 用
/// `tester.runAsync` + `tester.pump` 交替把整条异步链跑完（QA 已实证的写法）。
library one_click_care_sfx_choice_test;

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

/// 造一株「成长中 · 活」的干扰物株（`weed`/`pest` 决定挂哪种干扰物）。
///
/// `weedPestRollDay = 今日` → 刷新时不会重 roll（`NoHitRandom` 下也不会新增干扰物）。
Plant _plantWith(int i, {required bool weed, required bool pest}) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  return Plant(
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
    weedAt: weed ? today : null,
    pestAt: pest ? today : null,
    weedPestRollDay: today,
  );
}

/// 4 株仅杂草。
List<Plant> _weedyOnly() => <Plant>[
      for (int i = 0; i < 4; i++) _plantWith(i, weed: true, pest: false),
    ];

/// 4 株仅害虫。
List<Plant> _pestOnly() => <Plant>[
      for (int i = 0; i < 4; i++) _plantWith(i, weed: false, pest: true),
    ];

/// 2 株仅杂草 + 2 株仅害虫（草 + 虫混合）。
List<Plant> _weedAndPest() => <Plant>[
      _plantWith(0, weed: true, pest: false),
      _plantWith(1, weed: true, pest: false),
      _plantWith(2, weed: false, pest: true),
      _plantWith(3, weed: false, pest: true),
    ];

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

int _countLoads(String substr) => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains(substr))
    .length;

/// 走完整「点 FAB → 一键护理 → 确认」链路，并把音频异步链跑完。
///
/// [expectLoad] = 本用例预期被加载的音效子串（如 `audio/sfx/care_pest.mp3`）。
///
/// ⚠️ **自适应收尾（防并行全量下的时序 flake）**：`setAsset` 是多次真实文件 I/O
/// （rootBundle→临时目录），FakeAsync 下不推进；并行跑全量时机器负载高、I/O 变慢，
/// **固定轮数**会偶发不够（曾实测复现：`care_pest` 加载计数 0、断言 `1 != 0`）。故：
///   ① 交替「真实异步窗口 `runAsync` + 假时钟排空 `pump`」，**直到目标音效确实加载**（达上限退出，交由断言判失败）；
///   ② 命中后再**多排空若干轮**，仍能捕获任何多余的第 2 次加载 → 保住「整批恰好一次」的钉法（不因自适应而放松）。
Future<void> _oneClickCare(
  WidgetTester tester, {
  required String expectLoad,
}) async {
  final bool fabShown = await _pumpUntil(
    tester,
    () => find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
  );
  expect(fabShown, isTrue, reason: '存活株 ≥4 应出现一键操作 FAB');

  await tester.tap(find.byIcon(Icons.touch_app));
  await _pumpUntil(tester, () => find.text('一键护理').evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('一键护理'));

  final bool dialogShown = await _pumpUntil(
    tester,
    () => find.text('要一键护理吗？').evaluate().isNotEmpty,
  );
  expect(dialogShown, isTrue, reason: '一键护理（有目标）应先弹确认卡');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('确定'));

  // ① 自适应等待：目标音效真正被加载出来（上限 200 轮 × 20ms，常态数轮即命中）。
  int guard = 0;
  while (guard < 200 && _countLoads(expectLoad) < 1) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    guard++;
  }
  // ② 收尾排空：再多跑若干轮，确保不存在多余的第 2 次加载（钉「整批恰好一次」）。
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
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
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('care_choice_sfx');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets('仅杂草 → 播除草音效 care_weed.mp3（不播 care_pest.mp3）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_weedyOnly())));
    await _oneClickCare(tester, expectLoad: 'audio/sfx/care_weed.mp3');

    expect(_countLoads('audio/sfx/care_weed.mp3'), 1,
        reason: '仅杂草 → 恰好播一次除草音效（整批一次）');
    expect(_countLoads('audio/sfx/care_pest.mp3'), 0,
        reason: '仅杂草不应播除虫音效（玄参 2026-10-07 口径）');
  });

  testWidgets('草 + 虫 → 播除虫音效 care_pest.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_weedAndPest())));
    await _oneClickCare(tester, expectLoad: 'audio/sfx/care_pest.mp3');

    expect(_countLoads('audio/sfx/care_pest.mp3'), 1,
        reason: '存在害虫目标 → 播除虫音效（整批一次）');
    expect(_countLoads('audio/sfx/care_weed.mp3'), 0,
        reason: '有虫时播除虫音，不叠加除草音');
  });

  testWidgets('仅害虫 → 播除虫音效 care_pest.mp3', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_StoringPlantRepository(_pestOnly())));
    await _oneClickCare(tester, expectLoad: 'audio/sfx/care_pest.mp3');

    expect(_countLoads('audio/sfx/care_pest.mp3'), 1,
        reason: '仅害虫 → 播除虫音效（整批一次）');
    expect(_countLoads('audio/sfx/care_weed.mp3'), 0,
        reason: '无杂草不应播除草音效');
  });
}
