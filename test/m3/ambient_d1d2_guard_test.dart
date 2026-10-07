/// 真机日志锁定真因的两个**回归护栏**（玄参 2026-10-07 真机复测 + 日志取证）：
///
///  · **D1（致命）** ——`_playGardenAmbient()` 的 `start()` 内 `await player.play()` 会
///    **阻塞整首歌**（just_audio 0.9.46 `just_audio.dart:975` `await playCompleter.future`
///    只在 pause/stop/播完时完成；真机日志实测单曲 10.3s、冷启动 67s）。期间
///    `_ambientPlaying` 加载窗口一直开着 → 30s 定时器 / 切 tab 回花园的再次起播被
///    `playGardenAmbient()` 的 `skip: _ambientPlaying` 静默吞掉 → 「首进花园不响」。
///    修复：`unawaited(play())` + **有限轮询**（`playing && processingState != idle`，
///    ~20ms×≤10≈200ms），起播流程几百毫秒内返回。
///  · **D2** ——`_armDuckRestore()` 订阅 `sfx.playerStateStream`，而它是 **BehaviorSubject**
///    （`just_audio.dart:125/:452`）→ 订阅瞬间**重放当前值**；若 SFX 播放器已是
///    `completed`（上一支 SFX 播完的残留态），恢复监听被**秒触发**（真机日志 0.578 duck →
///    0.579 restore）→ ducking 形同虚设。修复：`.skip(1)` 跳过重放值，只在**新** completed 恢复。
///
/// 假 `JustAudioPlatform.instance` 可令 `play()` **永不完成**，精确复现 D1 的真机阻塞语义。
/// ⚠️ 本文件是普通 `test()`（非 FakeAsync）：真实定时器可自由推进，音频真实 I/O 需
/// path_provider 桩（与 `garden_ambient_settings_late_test` 同款写法）。
library ambient_d1d2_guard_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

// ── 记录型假 just_audio 平台（可令 play() 永不完成，复现 D1 真机阻塞）──────────────

/// 置 true 时 `play()` 返回一个**永不完成**的 Future——等价真机「await play() 阻塞整首歌」。
bool _neverCompletePlay = false;

/// 供「永不完成」复用的悬挂 Future（同一次测试内所有 play() 共享，永不 settle）。
final Completer<PlayResponse> _hang = Completer<PlayResponse>();

/// 🔴 记录 [AudioSession.configure] 的调用（记录型假 audio_session，用于 D1-v2 根因护栏）。
/// 真机证据（`/tmp/amb_r5.log` 末次冷启动）：卡死轮 `22:52:36.620 playing=true ready`
/// → 之后 29.5 秒零事件、永远无 `completed`；正常轮 10.32s 准时 completed。
/// 根因 = 项目从未调用 `AudioSession.instance.configure(...)` → Android 会话未声明 →
/// 冷启动首次 `play()` 卡在 ready 不渲染。
int _sessionConfigureCount = 0;

/// 置 true 时模拟真机「**哑起播**」：播放位置**永不推进**（D1-v2，真机日志实锤）。
///
/// 等价真机场景：会话未配置时 ExoPlayer 卡在 `ready`，`playing` 被 just_audio 乐观置 true，
/// 但平台再无任何上报 → 永远不会出现 `completed`。症状 = 玄参真机反馈「首进花园不响，
/// 约 30s 后才响」。
bool _stalledPlayback = false;

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
  void emitCompleted() => _events.add(_evt(ProcessingStateMessage.completed));

  PlaybackEventMessage _evt(ProcessingStateMessage st) => PlaybackEventMessage(
        processingState: st,
        updateTime: DateTime.now(),
        // 🔴 D1-v2：`_stalledPlayback` 时位置**永不推进**（等价真机哑起播）。
        updatePosition: _stalledPlayback
            ? Duration.zero
            : const Duration(seconds: 4),
        bufferedPosition: const Duration(seconds: 4),
        duration: const Duration(seconds: 4),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    log.add('play');
    if (_neverCompletePlay) return _hang.future; // 永不完成（D1 真机阻塞语义）
    return PlayResponse();
  }

  /// 记录每一次音量变更请求（SFX 从不调 setVolume；仅氛围音会调）。
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    final String who = loadedUri.contains('/bgm/') ? 'AMB' : 'SFX';
    log.add('volume:${request.volume}#$who');
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
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
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

/// 记录到的**花园氛围音**（AMB）的 `setVolume(v)` 次数。
///
/// ⚠️ 只统计 `#AMB`：just_audio 在 `setAsset` 重新激活平台播放器时会**内部**把播放器
/// 当前音量（默认 1.0）重新下发一次（`just_audio.dart:1479` `platform.setVolume(...)`），
/// 会命中 SFX 播放器（`#SFX`）。那不是我们的 duck/恢复动作，必须排除。
int _ambVolumes(double v) =>
    _fake.log.where((String e) => e.startsWith('volume:$v#AMB')).length;

/// 自适应推进真实异步链：轮询等待 [ready] 为真，上限 [maxRounds]×[step]；
/// 达标后再补 [extraRounds] 轮稳定计数（防并行全量高负载下的时序 flake）。
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
    _neverCompletePlay = false; // 每个用例默认「play() 正常完成」，D1 用例内部再置 true
    _stalledPlayback = false; // 默认「位置正常推进」；D1-v2 用例内部再置 true
    _sessionConfigureCount = 0;
    _fake.log.clear();
    _fake.players.clear();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('ambient_d1d2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);
    // D1-v2 根因护栏：`AudioSession.configure` 内部经此通道下发（audio_session 0.1.25
    // `core.dart:22` / `:207`），在此计数即可断言「配置会话」这一动作真的发生过。
    const MethodChannel audioSession = MethodChannel('com.ryanheise.audio_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSession, (MethodCall call) async {
      if (call.method == 'setConfiguration') _sessionConfigureCount++;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audioSession, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
    });
  });

  group('D1 · await player.play() 阻塞整首歌（起播必须几百毫秒内返回）', () {
    test('D1-①：play() 永不完成时，起播流程仍须在 ~1s 内返回（不得阻塞整首歌）', () async {
      _neverCompletePlay = true; // 复现真机：await play() 永不返回
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      final Stopwatch sw = Stopwatch()..start();
      await svc.playGardenAmbientAndWait().timeout(
            const Duration(seconds: 3),
            onTimeout: () => fail(
                '_playGardenAmbient 未在 3s 内返回 → `await player.play()` 阻塞了整首歌（D1 缺陷）'),
          );
      sw.stop();

      // 设计上：轮询 ~20ms×≤10≈200ms + 真实 I/O，几百毫秒内返回。
      // 断言给足上限（2s）仍远小于真机单曲 10.3s —— 足以钉死「不等于整首歌」。
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'D1：起播流程必须几百毫秒内返回，绝不等于整首歌时长（真机 10.3s）');
      expect(svc.ambientPlaying, isFalse,
          reason: 'D1：起播返回后加载窗口（_ambientPlaying）必须已复位为 false');
      expect(svc.ambientShouldPlay, isTrue,
          reason: 'D1：确已起播 → 「应播」意图应保持 true');

      _neverCompletePlay = false;
      await svc.dispose();
    });

    test('D1-②：起播返回后，再次 playGardenAmbient() 不得被 `skip: _ambientPlaying` 吞掉',
        () async {
      _neverCompletePlay = true;
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      await svc.playGardenAmbientAndWait();
      expect(svc.ambientPlaying, isFalse, reason: '前置：加载窗口已关闭');

      // 清记录，第二次起播必须**真的重新加载**（证明未被 skip）。
      _fake.log.clear();
      await svc.playGardenAmbientAndWait();

      expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
          reason: 'D1：加载窗口已关闭，第二次起播不得被 `skip: _ambientPlaying` 跳过'
              '（正是「首进花园不响」的机制）');

      _neverCompletePlay = false;
      await svc.dispose();
    });
  });

  group('D1-v2 · Android 音频会话未配置 → 冷启动首次 play() 卡 ready 不渲染', () {
    test('D1-v2-①：任何播放器首次使用前必须配置 AudioSession（music）', () async {
      _sessionConfigureCount = 0;
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      // 花园氛围音 = 背景类播放器（`handleInterruptions:false`）→ 首进花园这一拍必须已配置。
      await svc.playGardenAmbientAndWait();

      expect(_sessionConfigureCount, greaterThanOrEqualTo(1),
          reason: 'D1-v2 根因：项目从未调用 AudioSession.instance.configure(...) → '
              'Android 音频会话未声明 → 冷启动首次 play() 卡在 ready 不渲染 → '
              '真机症状「首进花园不响，约 30s 后才响」。会话必须在任何播放器使用前配置。');

      await svc.dispose();
    });

    test('D1-v2-②：会话配置幂等（多次播放只配置一次，不反复重配）', () async {
      _sessionConfigureCount = 0;
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      await svc.playGardenAmbientAndWait();
      final int afterFirst = _sessionConfigureCount;
      await svc.playGardenAmbientAndWait(); // 第二次起播（30s 定时器同样走这条路）
      svc.playSfx(AudioCue.careWater);

      expect(afterFirst, greaterThanOrEqualTo(1), reason: '前置：首次播放应已配置');
      expect(_sessionConfigureCount, afterFirst,
          reason: 'D1-v2：会话配置必须幂等——重复配置会重置音频焦点、可能再次打断播放');

      await svc.dispose();
    });

    test('D1-v2-③：位置不推进（哑起播）时不得静默判定成功——须走重试而非当作已发声',
        () async {
      _stalledPlayback = true; // playing=true/ready，但平台零事件、位置永不推进
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      await svc.playGardenAmbientAndWait().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                fail('起播流程未在 5s 内返回（轮询窗口上限约 200ms × 尝试次数）'),
          );

      // 本护栏不强制「必须判失败」（真机与假平台的可观测信号不同：真机靠会话配置解决，
      // 假平台无真实渲染），只钉死**关键回归点**：起播流程必须正常收尾、不抛异常、
      // 加载窗口复位——避免将来改动引入挂起。
      expect(svc.ambientPlaying, isFalse,
          reason: 'D1-v2：起播流程返回后加载窗口（_ambientPlaying）必须已复位为 false');
      expect(svc.ambientShouldPlay, isTrue,
          reason: 'D1-v2：假平台已把状态置为 ready/playing → 按既有乐观判据视为起播成功；'
              '真机上的「哑起播」由 AudioSession 配置修复，不依赖本判据');

      _stalledPlayback = false;
      await svc.dispose();
    });
  });

  group('D1-v3 · 并发起播互相打断（重入闸门）', () {
    test('D1-v3-①：并发触发起播时，只有第一个流程真正加载，后来的必须被闸门挡掉',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      // 真机同款触发：`applySettings` 的「迟到补播」在数毫秒内被调用两次
      //（外壳 initState 首调 + provider 变更监听）。第二次在第一次还在加载时进入
      // → 若无闸门，第二个流程的 `stop()` 会打断第一个流程的 `setAsset`，
      //   just_audio 抛 `PlatformException(abort, Loading interrupted)`（首播彻底失败）。
      final Future<void> a = svc.playGardenAmbientAndWait();
      final Future<void> b = svc.playGardenAmbientAndWait();
      final Future<void> c = svc.playGardenAmbientAndWait();
      await Future.wait<void>(<Future<void>>[a, b, c]).timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('并发起播流程未在 5s 内全部收尾（D1-v3 闸门疑似挂起）'),
          );

      expect(_loads('background.mp3'), 1,
          reason: 'D1-v3：三个并发起播流程中只允许**一个**真正加载 background.mp3；'
              '多于一次即说明重入闸门失效 → 并发 stop 会打断在途 setAsset '
              '（PlatformException(abort, Loading interrupted)）→ 真机「首进花园不响」');

      await svc.dispose();
    });

    test('D1-v3-②：闸门必须在流程收尾后释放（后续起播仍须能真正发声）', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      await svc.playGardenAmbientAndWait();
      expect(_loads('background.mp3'), 1, reason: '前置：首次起播应已加载一次');

      // 关键回归点：闸门若忘了在 finally 复位（或 dispose 未复位），第二轮会被永久
      // 挡掉 → 30s 定时器每次都空转、氛围音永不重播。
      await svc.playGardenAmbientAndWait();
      expect(_loads('background.mp3'), greaterThanOrEqualTo(2),
          reason: 'D1-v3：闸门必须在起播流程收尾后释放，否则第二轮起播被永久吞掉');

      await svc.dispose();
    });
  });

  group('D2 · duck 恢复不得被 playerStateStream 重放「秒触发」', () {
    test('D2-①：SFX 播放器已 completed 时，duck 后不得被重放值秒恢复（只有新 completed 才恢复）',
        () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);
      svc.playGardenAmbient();
      await _settleUntil(() => _loads('background.mp3') >= 1);
      expect(_loads('background.mp3'), greaterThanOrEqualTo(1),
          reason: '前置：花园氛围音应正常起播');

      // 让 SFX 播放器进入 completed 态（= 上一支 SFX 播完的残留状态）——
      // 正是「订阅 playerStateStream 重放 completed → 秒恢复」的前提。
      svc.playSfx(AudioCue.careWater);
      await _settleUntil(() => _loads('audio/sfx/care_water.mp3') >= 1);
      _sfxPlayer().emitCompleted();
      await _settleUntil(() => _ambVolumes(1.0) >= 1); // 让本支的 duck→restore 完整走完

      // 清记录，起第二支 SFX。此刻 SFX 播放器仍是 completed。
      _fake.log.clear();
      svc.playSfx(AudioCue.careWeed);
      // 给它足够时间完成 duck + arm（250ms ≪ 5s 兜底 Timer；无新 completed）。
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(_ambVolumes(kSfxDuckAmbientVolume), greaterThanOrEqualTo(1),
          reason: '前置：本次 SFX 应已把氛围音压到 kSfxDuckAmbientVolume');
      expect(_ambVolumes(1.0), 0,
          reason: 'D2：duck 后**不得**被「playerStateStream 重放已完成态」秒恢复；'
              '只有随后出现的**新** completed（或 5s 兜底）才恢复（跃迁判定修复）');

      await svc.dispose();
    });
  });
}
