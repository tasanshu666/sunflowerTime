/// QA 独立验证 · C138（玄参测试服反馈）：
///   ① 许愿树背景音音量减半（1.0 → 0.5），且只作用许愿树独立播放器；
///   ② 循环与花园一致「每 30s 起播一次」（起播间隔 = 周期 − 本轮曲长占时，
///      不是旧实现「播完再等满 30s」的 40s 周期）。
///
/// ## 与工程师自测 / C137 QA 的独立性
/// 本文件不复用 `test/m3/wish_tree_ambient_test.dart`、
/// `test/qa/qa_independent_c137_wish_ambient_test.dart` 的任何断言形状：
/// 自建记录型假平台，并在每次 `play()` 上**打时间戳**——这是唯一能在 headless 下
/// 量化「两次起播间隔」的证据（C137 用例只断言「completed 之后等满 gap」，
/// 在曲长≈0 时无法区分 30s / 40s 两种口径）。
///
/// ## 关键判据：模拟「曲长占周期 1/2」
/// 把 gap 缩到 1000ms，本遍播放**延迟 500ms** 才 emit completed（模拟真机
/// 10.08s / 30s ≈ 1/3）。此时：
///  - C138 正确实现：间隔 = played(≈500) + (gap − played)(≈500) = gap ≈ 1000ms；
///  - 旧 40s 实现（等满 gap）：间隔 = played(≈500) + gap(1000) ≈ 1500ms。
/// 两者相差 ~500ms，用宽 tolerance band 也能稳定区分。
///
/// ## 可验边界
/// headless 只能验「调用序列 / 调度时长 / 音量参数」，验不了真实听感与真机
/// `completed` 是否按时到达（见文件末尾注释）。
library qa_independent_c138_wish_ambient_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

const String _wishKey = 'wish_tree_ambient.mp3';
const String _gardenKey = 'background.mp3';

// ── 记录型假 just_audio 平台（play 带时间戳）───────────────────────────────

class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  final List<String> calls = <String>[];
  final List<DateTime> playTimes = <DateTime>[];
  String loadedUri = '';

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  void emitCompleted() => _events.add(_evt(ProcessingStateMessage.completed));

  PlaybackEventMessage _evt(ProcessingStateMessage state) =>
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage message = request.audioSourceMessage;
    loadedUri = message is UriAudioSourceMessage ? message.uri : message.toString();
    calls.add('load:$loadedUri');
    scheduleMicrotask(() => _events.add(_evt(ProcessingStateMessage.ready)));
    return LoadResponse(duration: const Duration(seconds: 10));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    calls.add('play');
    playTimes.add(DateTime.now());
    return PlayResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    calls.add('volume:${request.volume}');
    return SetVolumeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    calls.add('seek');
    return SeekResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
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
  final List<_RecPlayer> players = <_RecPlayer>[];
  final List<String> disposedIds = <String>[];

  void reset() {
    players.clear();
    disposedIds.clear();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final _RecPlayer p = _RecPlayer(request.id);
    players.add(p);
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    disposedIds.add(request.id);
    return DisposePlayerResponse.fromMap(<dynamic, dynamic>{});
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{});
}

late final _RecPlatform _fake;

// ── 观测助手 ───────────────────────────────────────────────────────────────

List<_RecPlayer> _playersOf(String key) =>
    _fake.players.where((_RecPlayer p) => p.loadedUri.contains(key)).toList();

_RecPlayer? _lastOf(String key) {
  final List<_RecPlayer> list = _playersOf(key);
  return list.isEmpty ? null : list.last;
}

int _plays(String key) => _playersOf(key).fold(
      0,
      (int sum, _RecPlayer p) =>
          sum + p.calls.where((String c) => c == 'play').length,
    );

int _countCall(String key, String exact) => _playersOf(key).fold(
      0,
      (int sum, _RecPlayer p) =>
          sum + p.calls.where((String c) => c == exact).length,
    );

/// 所有加载过 [key] 的播放器的 play 时间戳（升序）。
List<DateTime> _playTimes(String key) => _playersOf(key)
    .expand((_RecPlayer p) => p.playTimes)
    .toList()
      ..sort();

Future<bool> _waitFor(
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 6),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (ready()) return true;
    await Future<void>.delayed(step);
  }
  return ready();
}

AudioService _svc({bool bgmOn = true}) {
  final AudioService s = AudioService();
  s.applySettings(soundOn: true, bgmOn: bgmOn);
  return s;
}

int _count(String source, String token) => source.split(token).length - 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _fake = _RecPlatform();
    JustAudioPlatform.instance = _fake;
  });

  setUp(() {
    _fake.reset();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_c138');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V · 音量：恒 0.5，且只作用许愿树播放器；花园 / SFX 未被改小
  // ══════════════════════════════════════════════════════════════════════════
  group('V · 音量 0.5 且只作用许愿树播放器', () {
    test('V1：运行时 —— 许愿树每轮 setVolume(0.5)，花园播放器不收到 0.5', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 150));

      // 花园先播：起播处 setVolume(1.0)（audio_service.dart:1482）。
      svc.playGardenAmbient();
      expect(await _waitFor(() => _playersOf(_gardenKey).isNotEmpty), isTrue);
      final _RecPlayer garden = _lastOf(_gardenKey)!;

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue);
      _lastOf(_wishKey)!.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue);

      // 许愿树两轮都设置了字面量 0.5（用字面量而非常量，常量被改坏时此处独立报红）。
      expect(_countCall(_wishKey, 'volume:0.5'), greaterThanOrEqualTo(2),
          reason: '每轮起播音量必须是 0.5');
      for (final _RecPlayer p in _playersOf(_wishKey)) {
        expect(
          p.calls.where((String c) => c == 'volume:0.5'),
          isNotEmpty,
          reason: '该许愿树播放器实例 ${p.id} 从未收到 0.5（调用：${p.calls}）',
        );
      }
      // 花园播放器绝不被 0.5 污染（把音量改动误落到 _ambientPlayer 必红）。
      expect(garden.calls.contains('volume:0.5'), isFalse,
          reason: '花园播放器不得收到许愿树音量 0.5');
      expect(garden.calls.contains('volume:1.0'), isTrue,
          reason: '花园起播仍从满音量开始');

      svc.stopWishTreeAmbient(reason: 'test');
      await svc.stopGardenAmbient(reason: 'test');
    });

    test('V2：源码守卫 —— 常量 0.5 / 唯一作用点 / 花园两处 1.0 / SFX clamp 未改小', () {
      const String path = 'lib/platform/audio_service.dart';
      final String src = File(path).readAsStringSync();

      expect(kWishTreeAmbientVolume, 0.5,
          reason: 'C138：许愿树音量常量必须减半到 0.5');
      expect(src.contains('const double kWishTreeAmbientVolume = 0.5;'), isTrue);
      // 精确匹配真实调用行（带 `await player.` 前缀）；文档注释里也提到了该常量名，
      // 用裸 token 计数会把注释算进去。
      expect(_count(src, 'await player.setVolume(kWishTreeAmbientVolume);'), 1,
          reason: '只允许许愿树循环一处真实调用该常量（不得误落花园 / SFX）');
      expect(_count(src, 'setVolume(1.0)'), 2,
          reason: '花园两处满音量（_restoreAmbientVolume + 起播）必须原样保留');
      expect(_count(src, 'setVolume(volume.clamp(0.0, 1.0))'), 2,
          reason: 'SFX 两处原音量公式不得被改小');
      expect(src.contains('setVolume(kSfxDuckAmbientVolume)'), isTrue,
          reason: 'SFX ducking 常量仍引用原值');
      expect(src.contains('setAsset(kWishTreeAmbientAsset)'), isTrue,
          reason: '起播仍走单点素材常量');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // P · 周期：起播间隔 = 周期（30s），不是 周期+曲长（40s）
  // ══════════════════════════════════════════════════════════════════════════
  group('P · 起播周期 30s（非 40s）', () {
    test('P1：曲长占 500ms / 周期 1000ms ⇒ 两次起播间隔≈1000ms（旧实现会≈1500ms）',
        () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      const Duration gap = Duration(milliseconds: 1000);
      svc.debugSetWishTreeAmbientGap(gap);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：第一遍起播');
      final DateTime t1 = _playTimes(_wishKey).first;

      // 模拟本遍曲长 ≈ 500ms（真实 10.08s / 30s ≈ 1/3，这里取 1/2 加大区分度）。
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _lastOf(_wishKey)!.emitCompleted();

      expect(
        await _waitFor(() => _plays(_wishKey) >= 2,
            timeout: const Duration(seconds: 4)),
        isTrue,
        reason: '播完必须在周期到点时再次起播',
      );
      final DateTime t2 = _playTimes(_wishKey)[1];
      final Duration interval = t2.difference(t1);
      // ignore: avoid_print
      print('[C138-QA] P1 起播间隔实测 = ${interval.inMilliseconds}ms '
          '（gap=1000ms，曲长=500ms；旧 40s 口径应≈1500ms）');

      expect(interval, greaterThan(const Duration(milliseconds: 800)),
          reason: '间隔不得短于周期太多（间隔 ${interval.inMilliseconds}ms）');
      expect(interval, lessThan(const Duration(milliseconds: 1300)),
          reason: '🔴 间隔必须≈周期 1000ms，而非「曲长+周期」的 1500ms —— '
              '若把 remaining 改回满 gap（40s 口径），此处必红'
              '（实测 ${interval.inMilliseconds}ms）');

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('P2：常量与注释口径 —— gap=30，与花园同口径', () {
      expect(kWishTreeAmbientGapSeconds, 30,
          reason: 'C138：起播周期常量必须为 30（与花园一致）');
      expect(kGardenAmbientIntervalSeconds, 30,
          reason: '花园周期常量未被改动');
      expect(kWishTreeAmbientGapSeconds, kGardenAmbientIntervalSeconds,
          reason: '许愿树与花园必须同口径');
      final String src = File('lib/core/constants/prd_params.dart')
          .readAsStringSync();
      expect(src.contains('const int kWishTreeAmbientGapSeconds = 30;'), isTrue);
      expect(src.contains('起播周期'), isTrue,
          reason: '注释须声明这是起播周期（不是播完后的静默时长）');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G · 代际防护：stale generation 不播
  // ══════════════════════════════════════════════════════════════════════════
  group('G · 代际防护', () {
    test('G1：播放中 stop 作废代际 —— 迟到的 completed 也不复活循环', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 200));

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue);
      final _RecPlayer first = _lastOf(_wishKey)!;
      final int gen = svc.wishTreeAmbientGeneration;
      final int playsAtStop = _plays(_wishKey);

      svc.stopWishTreeAmbient(reason: 'leave');
      expect(svc.wishTreeAmbientGeneration, gen + 1,
          reason: 'stop 必须递增代际');
      expect(svc.wishTreeAmbientLooping, isFalse);
      expect(svc.wishTreeAmbientShouldPlay, isFalse);

      // 平台侧迟到的 completed（订阅已被 _cancelWishAmbientWait 取消）。
      first.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(_plays(_wishKey), playsAtStop,
          reason: '过期代际的流程醒来后必须退出，不得再起播');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // B · 后台暂停 / 恢复
  // ══════════════════════════════════════════════════════════════════════════
  group('B · 后台暂停 / 恢复', () {
    test('B1：退后台一声不出，回前台续播', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 200));

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue);
      final int before = _plays(_wishKey);

      await svc.pauseAllForBackground();
      expect(svc.wishTreeAmbientLooping, isFalse,
          reason: '退后台必须停（F70 同源）');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(_plays(_wishKey), before, reason: '后台期间不得再播');

      await svc.resumeFromBackground();
      expect(await _waitFor(() => _plays(_wishKey) > before), isTrue,
          reason: '回前台必须续播');
      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // I · 意图：stop 后不复活（但 bgmOff 保留意图可补播）
  // ══════════════════════════════════════════════════════════════════════════
  group('I · 意图语义', () {
    test('I1：bgmOff 保留意图可补播；真正 leave 后开 BGM 不得复活', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 200));

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue);
      final int beforeOff = _plays(_wishKey);

      // 关 BGM：保留意图，等重开补播。
      svc.applySettings(soundOn: true, bgmOn: false);
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: '关 BGM 保留「页内应播」意图');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(_plays(_wishKey), beforeOff, reason: '关 BGM 期间不得播');

      svc.applySettings(soundOn: true, bgmOn: true);
      expect(await _waitFor(() => _plays(_wishKey) > beforeOff), isTrue,
          reason: '重开 BGM 必须补播');

      // 真正离开页面：撤销意图；此后切 BGM 不得复活。
      svc.stopWishTreeAmbient(reason: 'leave');
      expect(svc.wishTreeAmbientShouldPlay, isFalse);
      final int afterLeave = _plays(_wishKey);
      svc.applySettings(soundOn: true, bgmOn: false);
      svc.applySettings(soundOn: true, bgmOn: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(_plays(_wishKey), afterLeave,
          reason: 'leave 后意图已撤销，切 BGM 不得让许愿树音复活');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // D · 幂等：重复 start 不叠播
  // ══════════════════════════════════════════════════════════════════════════
  group('D · 幂等', () {
    test('D1：同 turn 重复 start 只起一条循环', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 150));

      unawaited(svc.startWishTreeAmbient());
      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue);
      expect(svc.wishTreeAmbientPlayCalls, 2,
          reason: '起播请求照实记 2 次');
      expect(_plays(_wishKey), 1, reason: '只起一条循环，不得叠播');

      _lastOf(_wishKey)!.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(_plays(_wishKey), 2,
          reason: '一轮只对应一次重播（3 次 = 叠了第二条循环）');
      svc.stopWishTreeAmbient(reason: 'test');
    });
  });
}

// ── headless 无法证明、需真机确认 ───────────────────────────────────────────
// 1. 真实听感：每 30s 起播一次、音量是否确为减半（本文件只证调用参数与调度时长）。
// 2. 真机 processingState==completed 是否按时到达（哑起播走 duration+5s 兜底）。
// 3. 两个 AudioPlayer 真机混音时音量是否互相压制。
