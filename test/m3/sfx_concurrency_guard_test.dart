/// **F116 回归护栏**（玄参 2026-10-13 转来孩子真机反馈）。
///
/// 真机症状 = **专注中手动结束 → 点确认卡「结束」→ 护眼卡「只有动画、没有声音」**（孩子测出 3 次）。
///
/// ## 根因
/// SFX 全局**只有一个共享播放器**，而 [_playSfxPaths] 既无并发闸门、也无代际校验。
/// 手动结束路径上两路 SFX 相距极近地发起：
///   ① 结算页 `focus_settle`（**先发起**）卡在**首次** `_sfx` 初始化——配音频会话 / 建播放器 /
///      清资产缓存，三步平台调用几百 ms；
///   ② 护眼卡 `eyecare`（**后发起**，晚一帧 + 一次 `getSettings()`）却因会话标志已置位而
///      **绕过慢路径、抢先起播**；
///   ③ ①醒来后照旧 `await player.stop()` → **把护眼配音掐断**。
/// 护眼动画由 `FrameSequencePlayer` 的 Ticker 独立驱动（与音频是两条链路）→ 孩子看到
/// 「动画照播、没有声音」；胜负取决于两边首次平台调用的快慢 → **概率性偶发（约一半）**。
///
/// ## 修复（玄参拍板 **A + C**，2026-10-13）
///  · **A · 代际闸门** [_sfxGeneration]：每次 `playSfxPaths` **同步**递增排号，**后发起者赢**；
///    先发起者在每个 `await` 间隙自检代际，过期即**让位退出、绝不回头 stop 别人**。
///  · **C**：① 会话配置失败**可重试**（`_sessionConfigFuture` 由 `bool` 守卫改 Future 缓存）；
///    ② 资产缓存清理由 Future 缓存**串行化**（消除「删掉别人刚拷的资产」顺序竞态）；
///    ③ SFX **起播确认**（`_pollPlaybackStarted`，由「`await play()` 返回即算成功」改成
///    「确认真的在播」）。
///
/// ⚠️ 两条护栏为「**修复前必红、修复后必绿**」：
///  · **①** 先发起者被卡在首次初始化 → 修复前它会回头掐断护眼音（最后一次加载 = focus_settle）。
///  · **③** 修复前后发起者绕过慢路径 → 资产加载会**早于**会话配置完成（F86「哑起播」温床）。
/// **②** 是反向护栏（单路正常不受闸门影响），修复前后都应绿。
///
/// ⚠️ 「会话配置失败可重试」（C 的第一条）**无法在本环境可靠触发**：`audio_session` 内部
/// 吞掉了通道异常，headless 下造不出「首次失败」；该条以 `_sessionConfigFuture` 代码注释 +
/// 代码审查为保证，本文件只锁「成功路径仍只配置一次（并发共享）」。
///
/// ⚠️ 本文件用普通 `test()`（**非** FakeAsync）：需真实定时器推进异步链；假 just_audio
/// 平台与 path_provider / audio_session 桩沿用 `ambient_d1d2_guard_test.dart` 同款基建。
library sfx_concurrency_guard_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/platform/audio_service.dart';

// ── 可控假平台（记录 load/play 顺序；音频会话配置可人为延迟/抛错）──────────────

/// 首次 `AudioSession.configure`（走 `setConfiguration` 通道）的**人为延迟**。
///
/// 用于复现真机「冷启动首次初始化慢」：`_sfx` 首次要连做三步平台调用，
/// 先发起者会卡在这里 → 给后发起者留出「抢跑」窗口（F116 事故的根本条件）。
Duration _sessionConfigureDelay = Duration.zero;

/// `AudioSession.configure` 实际下发的次数（audio_session 0.1.25 走
/// `com.ryanheise.audio_session` 通道的 `setConfiguration`）。
int _sessionConfigureCount = 0;

class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id, this.log);
  final List<String> log;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  /// 最后一次加载的 uri（用于识别 SFX 播放器当前装的是哪支曲子）。
  String loadedUri = '';

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage m = request.audioSourceMessage;
    final String uri = m is UriAudioSourceMessage ? m.uri : m.toString();
    loadedUri = uri;
    log.add('load:$uri');
    // 置 ready：`_pollPlaybackStarted` 的判据是 `playing && processingState != idle`，
    // 缺了本事件起播确认永远不通过（会让「正常路径」被误判成起播失败）。
    scheduleMicrotask(() => _events.add(_evt(ProcessingStateMessage.ready)));
    return LoadResponse(duration: const Duration(seconds: 10));
  }

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

/// 记录到的资产加载序列（`load:<uri>`），按发生顺序。
List<String> get _loads =>
    _fake.log.where((String e) => e.startsWith('load:')).toList();

/// 自适应推进真实异步链：轮询等 [ready] 为真（上限 [maxRounds]×[step]），
/// 达标后再补 [extraRounds] 轮稳定计数（防并行全量高负载下的时序 flake）。
Future<void> _settleUntil(
  bool Function() ready, {
  int maxRounds = 80,
  int extraRounds = 10,
  Duration step = const Duration(milliseconds: 20),
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
    _sessionConfigureDelay = Duration.zero;
    _sessionConfigureCount = 0;
    _fake.log.clear();
    _fake.players.clear();

    // clearAssetCache 需要 path_provider；SFX 首次使用会真的走一次清缓存。
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('sfx_conc');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async => tmp.path);

    // 音频会话配置通道：可计数、可延迟（复现冷启动首次初始化慢）、可抛错（验证可重试）。
    const MethodChannel audioSession =
        MethodChannel('com.ryanheise.audio_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSession, (MethodCall call) async {
      if (call.method == 'setConfiguration') {
        _sessionConfigureCount++;
        if (_sessionConfigureDelay > Duration.zero) {
          await Future<void>.delayed(_sessionConfigureDelay);
        }
        // 与 `_fake.log` 共用同一条时间轴：便于断言「资产加载发生在会话配置完成**之后**」。
        _fake.log.add('session:done');
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audioSession, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
    });
  });

  group('F116 · SFX 并发互掐（手动结束 → 护眼卡无声）', () {
    test('① 先发起者卡在首次初始化时，**不得**掐断后起播的护眼配音', () async {
      // 冷启动首次会话配置慢 200ms —— 真机 `_sfx` 首次三步平台调用的等效场景。
      _sessionConfigureDelay = const Duration(milliseconds: 200);
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      // ① 结算页 focus_settle：先发起（真机 = 结算页 initState）。
      svc.playSfx(AudioCue.focusSettle);
      // ② 护眼卡 eyecare：20ms 后发起（真机 = postFrame + getSettings，几十 ms）。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      svc.playSfx(AudioCue.eyeCare);

      await _settleUntil(
        () => _loads.any((String e) => e.contains('eyecare.mp3')),
        maxRounds: 100,
        extraRounds: 15,
      );

      expect(_loads, isNotEmpty, reason: '前置：至少要发生一次资产加载');
      expect(
        _loads.last,
        contains('eyecare.mp3'),
        reason: 'F116：先发起者在首次初始化后醒来**必须让位**——最后一次加载必须是护眼配音。'
            '修复前（无代际闸门）它会 `player.stop()` + `setAsset(focus_settle)`，'
            '把护眼配音掐断 → 真机症状「有动画没声音」。',
      );
      expect(
        _loads.where((String e) => e.contains('focus_settle.mp3')).length,
        0,
        reason: 'F116：过期请求必须**彻底**让位——连一次资产加载都不该发生（更不许 stop）。',
      );

      await svc.dispose();
    });

    test('② 反向护栏：单路 SFX 不受闸门影响（正常加载 + 起播确认通过一次）', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      svc.playSfx(AudioCue.eyeCare);
      await _settleUntil(
        () => _loads.any((String e) => e.contains('eyecare.mp3')),
      );

      expect(_loads.length, 1,
          reason: 'F116：单路请求应**恰好**加载一次 —— 代际闸门与起播确认不得误伤正常路径');
      expect(_loads.single, contains('eyecare.mp3'));
      expect(_fake.log.contains('play'), isTrue,
          reason: 'F116-C：起播确认通过（确已起播）后应已发起 play()');

      await svc.dispose();
    });

    test('③ 并发两路必须**共享同一次**会话配置，且资产加载一律晚于会话配置完成', () async {
      // 首次会话配置慢 200ms（冷启动真机等效）。修复前：后发起者会**绕过**这条慢路径
      //（`bool _audioSessionConfigured` 已置位 → 立即返回），于是它在**会话尚未配置好**时
      // 就开始 setAsset / load —— 正是 F86「冷启动首次播放哑起播」的温床。
      _sessionConfigureDelay = const Duration(milliseconds: 200);
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: true);

      svc.playSfx(AudioCue.focusSettle);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      svc.playSfx(AudioCue.eyeCare);

      await _settleUntil(
        () => _loads.any((String e) => e.contains('eyecare.mp3')),
      );

      expect(
        _sessionConfigureCount,
        1,
        reason: 'F116-C：并发两路必须**共享同一次**会话配置（Future 缓存），不得各配一遍；'
            '而修复前的 `bool` 守卫虽也只配一次，却是靠「后到者直接跳过」实现的',
      );
      final int doneAt = _fake.log.indexOf('session:done');
      final int firstLoadAt =
          _fake.log.indexWhere((String e) => e.startsWith('load:'));
      expect(doneAt, greaterThanOrEqualTo(0), reason: '前置：会话配置确已发生');
      expect(
        firstLoadAt,
        greaterThan(doneAt),
        reason: 'F116-C：**资产加载必须晚于会话配置完成**（F86/D1-v2 口径：任何播放器首次'
            '使用前必须先声明会话）。修复前后发起者绕过慢路径 → 会话未就绪就开始加载 → '
            '冷启动首次播放「哑起播」（有画面无声音的另一种成因）。',
      );

      await svc.dispose();
    });
  });
}
