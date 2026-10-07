/// QA 独立反证 · 第二批 D 项（本批最关键，2026-10-07）——首次进花园 BGM「设置迟到补播」。
///
/// 场景（真实 `ChildShellPage` + **可门控的慢设置仓储**）：
///   1. 挂载真实 `ChildShellPage`，`getSettings()` 挂起（设置**尚未 resolve**）；
///   2. 在设置到达**之前**切到「花园」tab（GardenPage → `playGardenAmbient()`，此时
///      `_bgmOn` 仍为默认 false → 只记意图、不发声）；
///   3. 让设置 resolve（`bgmOn = true`）→ 外壳 `_syncAudioSettings` 补调
///      `AudioService.instance.applySettings(bgmOn:true)` → 应**补播** `background.mp3`。
///
/// 断言（真实加载的资产路径，用记录型假 `JustAudioPlatform.instance` 捕获）：
///   · 步骤②后：`background.mp3` 加载 = 0（设置未到，不发声），但 `ambientShouldPlay == true`；
///   · 步骤③后：`background.mp3` 加载 ≥ 1（**确实发起播放**）且 `ambientShouldPlay == true`。
///
/// ⚠️ 花园页木牌无限呼吸动画 → 全程有界 `pump`（禁止 pumpAndSettle）；
/// 真实音频 I/O 用 `tester.runAsync` 交替推进。
library qa_independent_round2_shell_d_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/weekly_pool_repository.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';

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
          duration: const Duration(seconds: 10),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        )));
    return LoadResponse(duration: const Duration(seconds: 10));
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

int _loads(String substr) => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains(substr))
    .length;

// ── 假仓储 / 门控设置 ───────────────────────────────────────────────────────

AppSettings _settings({required bool bgmOn}) => AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: 6,
      bgmOn: bgmOn,
    );

/// 可门控的「慢设置」仓储：`getSettings()` 直到测试显式 `complete` 才返回。
class _GatedSettingsRepository implements SettingsRepository {
  final Completer<AppSettings> completer = Completer<AppSettings>();
  @override
  Future<AppSettings> getSettings() => completer.future;
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
  Future<int> totalCheckInCount() async => 0;
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

class _FakeTrackingRepository implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent e) async {}
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      <TrackingEvent>[];
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

class _FakeWeeklyPoolRepository implements WeeklyPoolRepository {
  @override
  Future<WeeklyPool?> get(String weekKey) async => null;
  @override
  Future<void> upsert(WeeklyPool pool) async {}
  @override
  List<String> weeksBetween(String fromKey, String toKey) =>
      <String>[fromKey, toKey];
}

class _FakeRewardRepository implements RewardRepository {
  @override
  Future<List<RewardTemplate>> templates() async => <RewardTemplate>[];
  @override
  Future<void> saveTemplate(RewardTemplate t) async {}
  @override
  Future<void> deleteTemplate(String id) async {}
  @override
  Future<void> createRequest(RedemptionRequest r) async {}
  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      <RedemptionRequest>[];
  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];
  @override
  Future<void> updateRequest(RedemptionRequest r) async {}
  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;
  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() async {
    _fake.log.clear();
    // 复位单例（GardenPage / 外壳均用 AudioService.instance）。
    await AudioService.instance.dispose();
    AudioService.instance.applySettings(soundOn: true, bgmOn: false);

    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_r2_shell');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  testWidgets(
      'D 关键：设置迟到补播 —— 设置 resolve 前切到花园 tab，随后 resolve(bgmOn=true) 应真的发起播放 background.mp3',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final _GatedSettingsRepository gated = _GatedSettingsRepository();

    // 手动持有容器：即便外壳 unmount 后仍能读到同一 notifier → 收尾可显式停表
    //（覆盖任何「卸载后才补建」的 app-usage ticker，消除并行全量偶发 pending Timer）。
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWithValue(gated),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
        bloomRewardRepositoryProvider
            .overrideWithValue(InMemoryBloomRewardRepository()),
        rewardRepositoryProvider.overrideWithValue(_FakeRewardRepository()),
        trackingRepositoryProvider.overrideWithValue(_FakeTrackingRepository()),
        weeklyPoolRepositoryProvider
            .overrideWithValue(_FakeWeeklyPoolRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChildShellPage()),
      ),
    );

    // 让外壳首帧渲染（设置仍挂起）。
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // ── 步骤②：设置 resolve 之前，切到「花园」tab ──
    expect(find.text('花园'), findsWidgets, reason: '底部导航应有「花园」tab');
    await tester.tap(find.text('花园'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // 把花园页氛围音的（无）异步链跑一小段。
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }

    // 关键断言①：设置未到（bgmOn=false）→ 只记意图、不发声。
    expect(AudioService.instance.ambientShouldPlay, isTrue,
        reason: '切到花园 tab 应先记下「要播氛围音」的意图');
    expect(_loads('background.mp3'), 0,
        reason: '设置尚未 resolve（bgmOn=false）→ 不得发声');

    // ── 步骤③：让设置 resolve（bgmOn = true），外壳补调 applySettings ──
    gated.completer.complete(_settings(bgmOn: true));
    // 轮询直到 background.mp3 确实发起加载（消除一次性定长排空的时序瞬态）。
    bool loaded = false;
    for (int i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
      if (_loads('background.mp3') >= 1) {
        loaded = true;
        break;
      }
    }

    // 关键断言②：设置迟到变 true → 必须真的发起播放 background.mp3。
    expect(loaded, isTrue,
        reason: 'D 修复：设置迟到（bgmOn=true）必须补播花园氛围音（首次进花园不响的修复）');
    expect(_loads('background.mp3'), greaterThanOrEqualTo(1));
    expect(AudioService.instance.ambientShouldPlay, isTrue);

    // ── 收尾（防并行全量偶发「A Timer is still pending」）──
    // 卸载外壳：GardenPage.dispose → stopGardenAmbient()（代际++ 且 _ambientShouldPlay=false
    //，作废一切在途氛围音重试）；外壳 dispose → 停 30s 氛围音 periodic + app-usage ticker。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    // 兜底①：显式停表（容器仍存活 → 同一 notifier）——覆盖任何「卸载后才补建」的
    // app-usage ticker（其 _hydrate 依赖同一门控 getSettings()，resolve 时机可能晚于卸载）。
    unawaited(container.read(appUsageControllerProvider.notifier).stopCounting());
    await tester.pump();
    // ⚠️ 关键根因（并行全量偶发红的真凶）：`AudioService.startAmbientWithRetries` 的重试间隔
    // 是 **FakeAsync 的 `Future<void>.delayed(400ms)`**（在测试 fake 时钟里，不是真实延时）。
    // 全量并行下若首次 `start()` 抛错（共享资源竞争），会进入重试分支并在该 `Future.delayed`
    // 上挂一个 pending FakeTimer；此前用 `runAsync(真实 40ms)` 排空**推不动 fake 时钟**，
    // 于是未出队的重试定时器触发 `binding.dart` 的 `!timersPending` 断言 → 偶发红。
    // 卸载已使氛围音代际失效（shouldAbort→true），故**推进假时钟** 覆盖
    // `maxAttempts×retryDelay`（3×400ms=1200ms），让在途重试命中 shouldAbort 后立即退出。
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    // 再兜底一次停表（覆盖推进假时钟期间任何晚建 ticker）。
    unawaited(container.read(appUsageControllerProvider.notifier).stopCounting());
    await tester.pump();
    // 兜底②：彻底释放单例音频服务（真实 AudioPlayer + ducking 兜底定时器 + 自愈订阅）。
    await tester.runAsync(() => AudioService.instance.dispose());
    await tester.pump();
  });
}
