/// D 项（玄参 2026-10-07 真机复测「首次进花园仍不响」）：花园氛围音与**设置到达的先后**
/// 解耦——花园页可能在 `applySettings(bgmOn:true)` **到达之前**就调用了 [playGardenAmbient]
/// （那时 `_bgmOn` 还是默认 false）。修复后：意图先记，设置迟到再补播。
///
/// 本文件用**默认工厂**（真实 `AudioPlayer`）+ 记录型假 `JustAudioPlatform.instance`，
/// 断言真实加载的资产路径（`background.mp3`）：
///   · ① 设置迟到补播：`bgmOn` 先 false 记意图 → `applySettings(true)` → 补播 `background.mp3`；
///   · ② `bgmOn=false` 时不发声（仅记意图）；
///   · ③ 离开花园（stop）后设置再变化**不误播**（意图已复位，F70/F71/F81 不回归）。
///
/// ⚠️ 真实音频 I/O（`clearAssetCache` / `setAsset` 拷贝）需 path_provider 桩；
/// 本文件是普通 `test()`（非 FakeAsync），真实定时器可自由推进。
library garden_ambient_settings_late_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/platform/audio_service.dart';

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

int _loads(String substr) => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains(substr))
    .length;

/// 推进真实异步链：`_ambient` 懒构造 + `clearAssetCache` + `setAsset` 拷贝 + `play`
/// 都是真实 I/O / 微任务，需真实等待若干轮（含可能的 400ms 重试）。
Future<void> _settle() async {
  for (int i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
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
    final Directory tmp = Directory.systemTemp.createTempSync('ambient_late');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  test('① 设置迟到补播：bgmOn 先 false 记意图 → applySettings(true) → 补播 background.mp3',
      () async {
    final AudioService svc = AudioService();
    svc.applySettings(soundOn: true, bgmOn: false);

    svc.playGardenAmbient(); // 花园页先于设置到达：记意图，但因 bgmOn=false 不发声
    await _settle();
    expect(svc.ambientShouldPlay, isTrue, reason: '「花园要播」意图必须先记下（与设置解耦）');
    expect(_loads('background.mp3'), 0, reason: 'bgmOn=false 时不得发声');

    // 设置迟到 → 必须补播。
    svc.applySettings(soundOn: true, bgmOn: true);
    await _settle();
    expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
        reason: '设置迟到变 true 必须补播花园氛围音（首次进花园不响的修复）');

    await svc.dispose();
  });

  test('② bgmOn=false 时不发声（仅记意图，不加载背景音）', () async {
    final AudioService svc = AudioService();
    svc.applySettings(soundOn: true, bgmOn: false);

    svc.playGardenAmbient();
    await _settle();
    expect(svc.ambientShouldPlay, isTrue);
    expect(_loads('background.mp3'), 0, reason: '设置未开（bgmOn=false）不得发声');

    await svc.dispose();
  });

  test('③ 离开花园（stop）后设置再变化不误播', () async {
    final AudioService svc = AudioService();
    svc.applySettings(soundOn: true, bgmOn: true);
    svc.playGardenAmbient();
    await _settle();
    expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
        reason: '花园可见 + 设置开 → 正常起播');

    // 离开花园：stop 复位「应播」意图并递增代际。
    await svc.stopGardenAmbient();
    expect(svc.ambientShouldPlay, isFalse, reason: 'stop 后意图必须复位');

    _fake.log.clear();
    svc.applySettings(soundOn: true, bgmOn: true); // 设置再变化
    await _settle();
    expect(_loads('background.mp3'), 0,
        reason: '离开花园后设置变化不得误播（F70/F71/F81 不回归）');

    await svc.dispose();
  });
}
