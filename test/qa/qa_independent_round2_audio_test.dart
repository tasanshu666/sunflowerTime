/// QA 独立反证 · 第二批 A 项（2026-10-07 / v2）——SFX 与花园氛围音共存 + ducking。
///
/// 目的：**独立复验**工程师 A 项（`handleInterruptions:false` + ducking + 恢复）。
/// 仅以记录型假 `JustAudioPlatform.instance` 捕获「真实 `AudioPlayer` 实际发出的
/// `setVolume` / 加载请求」作为客观证据；不改任何生产代码。
///
/// 关键字段（`lib/platform/audio_service.dart`）：
///   · `_ambientPlaying` 只在 `_playGardenAmbient()` 的 **加载窗口** 内为 true
///     （line 561 置 true，line 588 finally 置 false）——稳态恒为 false。
///   · `_duckAmbientForSfx()`（:374-382）、`_restoreAmbientVolume()`（:401-411）
///     均以 `_ambientPlaying` 为**前置** → 稳态 ducking 从不触发（见 A-核心）。
///   · `applySettings()` 亦以 `_ambientPlaying` 为前置：关 BGM 不 stop（:262）、
///     重复同步设置会重复 `_playGardenAmbient()`（:268）——同源缺陷（见 同源①/②）。
///
/// 实证（probe 结论）：假平台下 `AudioPlayer.play()` **不抛异常**、`playing == true`
/// （`AudioSession.instance` 在 flutter_test 中可正常 resolve）→ 氛围音首次即成功起播
/// （bgmLoads=1，非重试/abort）。故 ducking 判据**可以**落在 `playing` 上。
///
/// ⚠️ 本文件用默认工厂（真实 `AudioPlayer`）+ 假平台；真实音频 I/O 需 path_provider 桩，
/// 且用普通 `test()`（真实定时器可自由推进）。
library qa_independent_round2_audio_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

// ── 记录型假 just_audio 平台（记录 setVolume + 可向指定播放器注入 completed 事件）──

class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id, this.log);
  final List<String> log;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  /// 最后一次加载的 uri（用于识别 SFX 播放器）。
  String loadedUri = '';

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage m = request.audioSourceMessage;
    final String uri = m is UriAudioSourceMessage ? m.uri : m.toString();
    loadedUri = uri;
    log.add('load:$uri');
    scheduleMicrotask(() => _events.add(_evt(ProcessingStateMessage.ready)));
    return LoadResponse(duration: const Duration(seconds: 10));
  }

  /// 主动发一个 `completed` 播放事件（模拟 SFX 播完）。
  void emitCompleted() =>
      _events.add(_evt(ProcessingStateMessage.completed));

  PlaybackEventMessage _evt(ProcessingStateMessage st) => PlaybackEventMessage(
        processingState: st,
        updateTime: DateTime.now(),
        updatePosition: const Duration(seconds: 4),
        bufferedPosition: const Duration(seconds: 4),
        duration: const Duration(seconds: 4),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    log.add('play');
    return PlayResponse();
  }

  /// 关键：记录每一次音量变更请求（SFX 从不调 setVolume；仅氛围音会调）。
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    log.add('volume:${request.volume}');
    return SetVolumeResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
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
  final List<_RecPlayer> players = <_RecPlayer>[];
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final _RecPlayer p = _RecPlayer(request.id, log);
    players.add(p);
    return p;
  }

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

/// 加载过 SFX 资产的那个播放器（氛围音加载的是 background.mp3）。
_RecPlayer _sfxPlayer() =>
    _fake.players.firstWhere((_RecPlayer p) => p.loadedUri.contains('audio/sfx/'));

int _loads(String substr) => _fake.log
    .where((String e) => e.startsWith('load:') && e.contains(substr))
    .length;

/// 记录到的 `setVolume(v)` 次数。
int _volumes(double v) => _fake.log.where((String e) => e == 'volume:$v').length;

/// 推进真实异步链（懒构造 + clearAssetCache + setAsset 拷贝 + play）。
Future<void> _settle() async {
  for (int i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// 自适应推进：轮询等待 [ready] 为真（真实 I/O：clearAssetCache/setAsset/play），
/// 上限 [maxRounds]×[step]；达标后再补 [extraRounds] 轮稳定计数。
/// 替代定长排空，防并行全量高负载下偶发误判（QA 2026-10-07 修）。
Future<void> _settleUntil(
  bool Function() ready, {
  int maxRounds = 100,
  int extraRounds = 10,
  Duration step = const Duration(milliseconds: 40),
}) async {
  for (int i = 0; i < maxRounds; i++) {
    if (ready()) break;
    await Future<void>.delayed(step);
  }
  for (int i = 0; i < extraRounds; i++) {
    await Future<void>.delayed(step);
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
    _fake.players.clear();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_r2_audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  group('A · ducking 独立反证（稳态）', () {
    test('A-核心：氛围音**确已在播**时播 SFX → 应把氛围音压低到 kSfxDuckAmbientVolume（期望行为）',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);

      expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
          reason: '前置：花园氛围音应正常起播');
      expect(svc.ambientShouldPlay, isTrue,
          reason: '前置：花园 tab「应播」意图应为 true');
      expect(_volumes(1.0), greaterThanOrEqualTo(1),
          reason: '对照组：起播的 setVolume(1.0) 应被捕获 —— 证明 setVolume 记录有效');

      _fake.log.clear();
      svc.playSfx(AudioCue.careWater);
      await _settleUntil(() => _volumes(kSfxDuckAmbientVolume) >= 1);

      expect(_volumes(kSfxDuckAmbientVolume), greaterThanOrEqualTo(1),
          reason: 'A 项 ducking：SFX 播放期间应把花园氛围音压低到 kSfxDuckAmbientVolume 音量');

      await svc.dispose();
    });

    test('A-对照：氛围音**未在播**时播 SFX → 不得出现任何 duck',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playSfx(AudioCue.careWater);
      await _settle();

      expect(_volumes(kSfxDuckAmbientVolume), 0,
          reason: '氛围音未在播时播 SFX 不应 duck（也不应凭空挂 5s 恢复 Timer）');

      await svc.dispose();
    });

    test('A1② 反证：连续播 3 次 SFX → 不堆叠 duck（稳态压低计 ≤1）', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      _fake.log.clear();

      svc.playSfx(AudioCue.careWater);
      svc.playSfx(AudioCue.careWeed);
      svc.playSfx(AudioCue.carePest);
      await _settleUntil(() => _volumes(kSfxDuckAmbientVolume) >= 1);

      expect(_volumes(kSfxDuckAmbientVolume), lessThanOrEqualTo(1),
          reason: '连续 3 次 SFX 不得把音量压出 3 次（不堆叠）');

      await svc.dispose();
    });
  });

  group('A-恢复 · 防「压低后永久不恢复」（技师修复后必须真跑出恢复动作）', () {
    test('A-恢复①（completed 事件）：duck 后 SFX 播完 → 氛围音恢复 1.0', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      expect(_loads('background.mp3'), greaterThanOrEqualTo(1));

      _fake.log.clear();
      svc.playSfx(AudioCue.careWater);
      await _settleUntil(() => _volumes(kSfxDuckAmbientVolume) >= 1);

      // 前置：必须先真的 duck（否则无从谈恢复）。
      expect(_volumes(kSfxDuckAmbientVolume), greaterThanOrEqualTo(1),
          reason: '前置：SFX 期间应已把氛围音压到 kSfxDuckAmbientVolume');

      // 触发 SFX 播完事件。
      _sfxPlayer().emitCompleted();
      await _settleUntil(() => _volumes(1.0) >= 1);

      final int duckIdx = _fake.log.indexOf('volume:$kSfxDuckAmbientVolume');
      final int restoreIdx = _fake.log.lastIndexOf('volume:1.0');
      expect(duckIdx, isNonNegative, reason: '前置：日志中应有 duck 记录');
      expect(restoreIdx, greaterThan(duckIdx),
          reason: 'A-恢复：SFX 播完后氛围音音量必须**恢复到 1.0**（且发生在 duck 之后）');

      await svc.dispose();
    });

    test('A-恢复②（5s 兜底 Timer）：不触发 completed，推进 kSfxDuckMaxMs 后也应恢复 1.0',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      expect(_loads('background.mp3'), greaterThanOrEqualTo(1));

      _fake.log.clear();
      svc.playSfx(AudioCue.careWater);
      await _settleUntil(() => _volumes(kSfxDuckAmbientVolume) >= 1);
      expect(_volumes(kSfxDuckAmbientVolume), greaterThanOrEqualTo(1),
          reason: '前置：SFX 期间应已把氛围音压到 kSfxDuckAmbientVolume');

      // 不发 completed，纯等 5s 兜底定时器（kSfxDuckMaxMs=5000）。假平台不会自发 completed。
      await Future<void>.delayed(const Duration(milliseconds: 5400));
      await _settleUntil(() => _volumes(1.0) >= 1);

      final int duckIdx = _fake.log.indexOf('volume:$kSfxDuckAmbientVolume');
      final int restoreIdx = _fake.log.lastIndexOf('volume:1.0');
      expect(duckIdx, isNonNegative);
      expect(restoreIdx, greaterThan(duckIdx),
          reason: 'A-恢复②：兜底 5s 后必须恢复 1.0（防音量永久卡在压低值）');

      await svc.dispose();
    });
  });

  group('A-同源缺陷 · applySettings 也误用 _ambientPlaying', () {
    test('同源①：氛围音在播时 applySettings(bgmOn:false) → 应把氛围音 stop（意图复位）',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
          reason: '前置：氛围音应在播');

      final int gen0 = svc.ambientGeneration;
      svc.applySettings(soundOn: true, bgmOn: false); // 关 BGM
      await _settleUntil(() => !svc.ambientShouldPlay);

      expect(svc.ambientShouldPlay, isFalse,
          reason: '同源①：关 BGM 必须停止在播的氛围音（复位应播意图），而非播到自然结束');
      expect(svc.ambientGeneration, greaterThan(gen0),
          reason: '同源①：应经 stopGardenAmbient（代际递增）');

      await svc.dispose();
    });

    test('同源②：氛围音在播时重复 applySettings(bgmOn:true) → 不得重启（无新 load:background.mp3）',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
          reason: '前置：氛围音应在播');

      _fake.log.clear();
      // 模拟外壳页多次同步设置。
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.applySettings(soundOn: true, bgmOn: true);
      await _settle();

      expect(_loads('background.mp3'), 0,
          reason: '同源②：已在播时重复同步设置不得从头重启氛围音（不得产生新的 background.mp3 加载）');

      await svc.dispose();
    });
  });

  group('A1⑤ · handleInterruptions 取值断言（源码取值）', () {
    test('背景类工厂 handleInterruptions:false；SFX 工厂未关闭打断处理', () {
      final String src =
          File('lib/platform/audio_service.dart').readAsStringSync();

      final RegExp bgRe = RegExp(
        r'_defaultBackgroundPlayerFactory\s*=\s*\(\)\s*=>\s*AudioPlayer\(([^)]*)\)',
      );
      final RegExpMatch? bg = bgRe.firstMatch(src);
      expect(bg, isNotNull, reason: '应能找到背景类播放器默认工厂');
      expect(bg!.group(1), contains('handleInterruptions: false'),
          reason: '背景类播放器必须 handleInterruptions:false');

      final RegExp sfxRe = RegExp(
        r'_defaultPlayerFactory\s*=\s*\(\)\s*=>\s*AudioPlayer\(([^)]*)\)',
      );
      final RegExpMatch? sfx = sfxRe.firstMatch(src);
      expect(sfx, isNotNull, reason: '应能找到 SFX 播放器默认工厂');
      expect(sfx!.group(1), isNot(contains('handleInterruptions')),
          reason: 'SFX 播放器应保留 just_audio 默认打断处理');
    });
  });
}
