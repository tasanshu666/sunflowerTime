/// C137 · 许愿树页专属背景音（玄参 2026-11-22）。
///
/// 需求原文：「给许愿树页面接入背景音效……播放一次然后停 30s，然后再播放。
/// 仅在许愿树这个界面播放，其他界面不播放。」
///
/// ## 本文件怎么证（不靠源码字符串，靠**真实 `AudioPlayer` + 记录型假平台**）
/// 用记录型假 `JustAudioPlatform.instance` 捕获真实 `AudioPlayer` 实际发出的
/// `load` / `play` / `setVolume` / `disposePlayer` 调用序列（范式照
/// `test/qa/qa_independent_round2_audio_test.dart`），据此断言：
///   1. 起播确实加载**许愿树素材**并播一次；
///   2. 重复 `start` 幂等（不会叠第二条循环）；
///   3. 「播完 → 静默 → 再播」的循环语义（`completed` 事件后必须重播）+ `stop` 后绝不再播；
///   4. `_bgmOn == false` 时不起播；
///   5. `applySettings(bgmOn:false)` 停播、`bgmOn:true` 补播；
///   6. **与花园氛围音互不干扰**（两个独立播放器，各自的调用记录互不出现对方的动作）；
///   7. 退后台即停、回前台续播；
///   8. 常量 / 素材守卫。
///
/// ⚠️ 关键实现事实（决定了上面的断言方式）：
///   · just_audio 0.9.46 的 `AudioPlayer.play()` **不等播完**（`_sendPlayRequest` 里
///     平台 play 请求一返回就 `complete()`，`just_audio.dart:998-1005`）——所以「一遍播完」
///     必须另等 `ProcessingState.completed`（生产实现见 `_awaitWishAmbientCompleted`），
///     用例里就靠 [_RecPlayer.emitCompleted] 触发。
///   · `AudioPlayer.stop()` 不会调用平台的 `stop`（平台接口没有该方法），而是
///     `_setPlatformActive(false)` → `disposePlayer(id)`；故「已停」的证据是
///     [_RecPlatform.disposedIds] 里出现该播放器的 id。
///   · 用普通 `test()`（真实定时器）：真实音频 I/O 需要 path_provider 桩，且需要自由推进
///     静默间隔；`testWidgets` 的 FakeAsync 会因残留 Timer 误判失败。
library wish_tree_ambient_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

/// 许愿树素材的**文件名片段**（`load:` 记录的 uri 里含它即认定是这个播放器）。
const String _wishKey = 'wish_tree_ambient.mp3';

/// 花园氛围音素材的文件名片段（对照组）。
const String _gardenKey = 'background.mp3';

/// 玄参交付素材的实测字节数（防误替换成别的文件）。
const int _wishAssetBytes = 242048;

// ── 记录型假 just_audio 平台 ───────────────────────────────────────────────────

/// 单个平台播放器：记录**自己**收到的调用（按播放器隔离，这是「互不干扰」的判据基础）。
class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  /// 本播放器的调用序列：`load:<uri>` / `play` / `volume:<v>` / `seek`。
  final List<String> calls = <String>[];

  /// 最后一次加载的 uri（用于识别这个播放器「是花园的还是许愿树的」）。
  String loadedUri = '';

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage message = request.audioSourceMessage;
    final String uri =
        message is UriAudioSourceMessage ? message.uri : message.toString();
    loadedUri = uri;
    calls.add('load:$uri');
    // 真实平台加载完会推 `ready`（生产实现靠它让 `setAsset` 的 Future 完成）。
    scheduleMicrotask(() => _events.add(_evt(ProcessingStateMessage.ready)));
    // 本曲实测 10.083250 s。
    return LoadResponse(duration: const Duration(milliseconds: 10083));
  }

  /// 主动发一个 `completed` 事件 = 「这一遍播完了」。
  void emitCompleted() => _events.add(_evt(ProcessingStateMessage.completed));

  PlaybackEventMessage _evt(ProcessingStateMessage state) => PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: const Duration(seconds: 4),
        bufferedPosition: const Duration(seconds: 4),
        duration: const Duration(milliseconds: 10083),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    calls.add('play');
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
  /// 本次用例创建过的**全部**平台播放器（按创建顺序）。
  final List<_RecPlayer> players = <_RecPlayer>[];

  /// 被平台侧释放（= 对应 `AudioPlayer` 被 `stop()`）的播放器 id。
  final List<String> disposedIds = <String>[];

  void reset() {
    players.clear();
    disposedIds.clear();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final _RecPlayer player = _RecPlayer(request.id);
    players.add(player);
    return player;
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

/// 加载过 [key] 的播放器（可能不止一个：`stop()` 后再起播会重建平台播放器）。
List<_RecPlayer> _playersOf(String key) =>
    _fake.players.where((_RecPlayer p) => p.loadedUri.contains(key)).toList();

/// 最近一个加载过 [key] 的播放器（`stop()` 后会换新实例，故取 last）。
_RecPlayer? _lastPlayerOf(String key) {
  final List<_RecPlayer> list = _playersOf(key);
  return list.isEmpty ? null : list.last;
}

/// [key] 素材被加载的次数 = 「起了几遍」。
int _loads(String key) => _playersOf(key).length;

/// [key] 素材的播放器累计 `play` 次数 = 「实际播了几遍」。
int _plays(String key) => _playersOf(key).fold<int>(
      0,
      (int sum, _RecPlayer p) => sum + p.calls.where((String c) => c == 'play').length,
    );

/// [key] 播放器累计 `setVolume(v)` 次数。
int _volumes(String key, double v) => _playersOf(key).fold<int>(
      0,
      (int sum, _RecPlayer p) =>
          sum + p.calls.where((String c) => c == 'volume:$v').length,
    );

/// 自适应推进：轮询等 [ready] 为真，达标后再补几轮稳定计数（真实 I/O 需要时间）。
Future<void> _settleUntil(
  bool Function() ready, {
  int maxRounds = 100,
  int extraRounds = 8,
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

/// 固定推进若干轮（无需等待条件时用）。
Future<void> _settle({int rounds = 12, Duration step = const Duration(milliseconds: 40)}) =>
    _settleUntil(() => false, maxRounds: 0, extraRounds: rounds, step: step);

/// 开好开关的服务（生产语义：设置里「背景音乐」为开）。
AudioService _bgmOnService() {
  final AudioService svc = AudioService();
  svc.applySettings(soundOn: true, bgmOn: true);
  return svc;
}

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
    final Directory tmp = Directory.systemTemp.createTempSync('wish_ambient');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  group('C137 起播语义', () {
    test('① start 会加载许愿树素材并起播一次（音量 0.5 = 原 1.0 减半）', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      expect(svc.wishTreeAmbientLooping, isFalse, reason: '前置：尚未起播');
      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);

      final _RecPlayer? player = _lastPlayerOf(_wishKey);
      expect(player, isNotNull, reason: '必须加载许愿树素材（setAsset）');
      expect(player!.loadedUri.contains(kWishTreeAmbientAsset), isTrue,
          reason: '素材路径单点常量 = $kWishTreeAmbientAsset');
      expect(_plays(_wishKey), 1, reason: '起播只播一次（不是循环 setLoopMode）');
      expect(_volumes(_wishKey, kWishTreeAmbientVolume), greaterThanOrEqualTo(1),
          reason: 'C138：每轮起播音量 = 原 1.0 减半（0.5），仅许愿树独立播放器');
      expect(svc.wishTreeAmbientShouldPlay, isTrue, reason: '页内应播意图已记录');
      expect(svc.wishTreeAmbientLooping, isTrue, reason: '循环协程在跑（静默间隔期间同样为 true）');

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('② 幂等：连续 start 两次只起一条循环、只播一次', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);

      expect(_loads(_wishKey), 1, reason: '幂等闸门 _wishAmbientLooping 拦下第二次，不重复 setAsset');
      expect(_plays(_wishKey), 1, reason: '绝不能叠出第二条循环并发播放');
      expect(svc.wishTreeAmbientPlayCalls, 2,
          reason: '起播请求计数照实记 2 次（入口处递增，与幂等无关）');

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  group('C137 循环语义（播完 → 静默 → 再播，非 Timer.periodic）', () {
    test('③ 本遍播完（completed）→ 静默 → 必须再播；stop 后绝不再播', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);
      // 静默间隔缩短到 80ms（真实 30s 无法在用例内等待；生产值仍是
      // kWishTreeAmbientGapSeconds=30，见下方常量守卫）。
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 80));

      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);
      expect(_plays(_wishKey), 1, reason: '前置：第一遍已起播');

      // 模拟「这一遍播完了」。
      _lastPlayerOf(_wishKey)!.emitCompleted();
      await _settleUntil(() => _plays(_wishKey) >= 2);
      expect(_plays(_wishKey), greaterThanOrEqualTo(2),
          reason: '播完 → 静默 → 再播：completed 之后必须重播（玄参口径「然后再播放」）');

      // ── stop：代际递增 + 循环收尾 + 平台侧真被释放 + 不再有任何新播放 ──
      final int genBefore = svc.wishTreeAmbientGeneration;
      final _RecPlayer playerBeforeStop = _lastPlayerOf(_wishKey)!;
      final int playsBeforeStop = _plays(_wishKey);

      svc.stopWishTreeAmbient(reason: 'leave');

      expect(svc.wishTreeAmbientGeneration, genBefore + 1,
          reason: 'stop 必须递增代际（作废在途加载 / 静默等待）');
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '循环闸门立即关闭');
      expect(svc.wishTreeAmbientShouldPlay, isFalse, reason: '离开页面即撤销「应播」意图');

      await _settleUntil(() => _fake.disposedIds.contains(playerBeforeStop.id),
          maxRounds: 40, extraRounds: 4);
      expect(_fake.disposedIds, contains(playerBeforeStop.id),
          reason: '播放器必须被平台侧释放（= AudioPlayer.stop() 真实发生）');

      // 跨越**已缩短的静默间隔**（80ms）再等一段时间：循环已退出，不得有新 play。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(_plays(_wishKey), playsBeforeStop,
          reason: 'stop 之后即使越过静默间隔也绝不能再播（代际 guard 生效）');
    });
  });

  group('C137 受「背景音乐」开关控制', () {
    test('④ bgmOn=false 时 start 不起播（但记下应播意图，等设置迟到补播）', () async {
      final AudioService svc = AudioService();
      addTearDown(svc.dispose);
      svc.applySettings(soundOn: true, bgmOn: false);

      unawaited(svc.startWishTreeAmbient());
      await _settle();

      expect(_loads(_wishKey), 0, reason: '关背景音乐时不得加载 / 起播');
      expect(_plays(_wishKey), 0, reason: '关背景音乐时一声都不许出');
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '不进入循环');
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: '意图先于开关判定记录（照花园 F82-b 口径），否则设置迟到无人补播');
    });

    test('⑤ applySettings(bgmOn:false) 停掉正在播的音；改回 true 并补播', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);
      final _RecPlayer playing = _lastPlayerOf(_wishKey)!;
      final int playsAtFirst = _plays(_wishKey);
      expect(playsAtFirst, 1, reason: '前置：正在播');

      // ── 关「背景音乐」（设置页 toggle）──
      svc.applySettings(soundOn: true, bgmOn: false);
      await _settleUntil(() => _fake.disposedIds.contains(playing.id),
          maxRounds: 40, extraRounds: 4);
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '关 BGM 立即停播');
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: 'keepIntent：用户还在许愿树页，意图必须保留（否则重开无法补播）');
      expect(_fake.disposedIds, contains(playing.id),
          reason: '正在播的播放器必须被真正 stop（平台侧 disposePlayer）');

      // ── 重新打开「背景音乐」──
      svc.applySettings(soundOn: true, bgmOn: true);
      await _settleUntil(() => _plays(_wishKey) >= playsAtFirst + 1);
      expect(_plays(_wishKey), greaterThanOrEqualTo(playsAtFirst + 1),
          reason: '重新打开背景音乐必须补播（本页不会再次 initState，只能靠迟到补播）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  group('C137 与花园氛围音互不干扰（关键）', () {
    test('⑥a 花园先播 → 许愿树起播期间花园播放器零新增调用', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      svc.playGardenAmbient();
      await _settleUntil(() => _loads(_gardenKey) >= 1);
      final _RecPlayer garden = _lastPlayerOf(_gardenKey)!;
      final int gardenCallsBefore = garden.calls.length;
      final int gardenGenBefore = svc.ambientGeneration;
      expect(svc.ambientShouldPlay, isTrue, reason: '前置：花园在播');

      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);

      expect(_plays(_wishKey), 1, reason: '前置：许愿树音已起播');
      expect(garden.calls.length, gardenCallsBefore,
          reason: '许愿树音起播期间，花园播放器不得被 stop / setAsset / setVolume');
      expect(garden.loadedUri.contains(_gardenKey), isTrue,
          reason: '花园播放器仍持有自己的素材（未被许愿树音覆盖 setAsset）');
      expect(svc.ambientGeneration, gardenGenBefore,
          reason: '花园代际不得被许愿树音推进（说明根本没走花园的 stop 路径）');
      expect(svc.ambientShouldPlay, isTrue, reason: '花园「应播」意图不受许愿树音影响');

      svc.stopWishTreeAmbient(reason: 'test');
      await svc.stopGardenAmbient(reason: 'test');
    });

    test('⑥b 许愿树先播 → 花园起播期间许愿树播放器零新增调用', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);
      final _RecPlayer wish = _lastPlayerOf(_wishKey)!;
      final int wishCallsBefore = wish.calls.length;
      final int wishGenBefore = svc.wishTreeAmbientGeneration;

      svc.playGardenAmbient();
      await _settleUntil(() => _loads(_gardenKey) >= 1);

      expect(_loads(_gardenKey), greaterThanOrEqualTo(1),
          reason: '前置：花园音已起播');
      expect(wish.calls.length, wishCallsBefore,
          reason: '花园起播期间，许愿树播放器不得被 stop / setAsset / setVolume');
      expect(wish.loadedUri.contains(_wishKey), isTrue,
          reason: '许愿树播放器仍持有自己的素材');
      expect(svc.wishTreeAmbientGeneration, wishGenBefore,
          reason: '许愿树代际不得被花园音推进');
      expect(svc.wishTreeAmbientLooping, isTrue, reason: '许愿树循环不被花园音打断');

      svc.stopWishTreeAmbient(reason: 'test');
      await svc.stopGardenAmbient(reason: 'test');
    });
  });

  group('C137 生命周期与素材守卫', () {
    test('⑦ 退后台即停、回前台续播', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);
      final int playsBeforeSuspend = _plays(_wishKey);

      await svc.pauseAllForBackground();
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '退后台 / 锁屏必须停（F70 同源）');
      expect(svc.wishTreeAmbientShouldPlay, isFalse, reason: '停播即撤销应播意图');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(_plays(_wishKey), playsBeforeSuspend,
          reason: '退后台期间一声都不许出');

      await svc.resumeFromBackground();
      await _settleUntil(() => _plays(_wishKey) >= playsBeforeSuspend + 1);
      expect(_plays(_wishKey), greaterThanOrEqualTo(playsBeforeSuspend + 1),
          reason: '回前台必须续播（用户仍停在许愿树页）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('⑧ 常量 / 素材守卫：路径、起播周期 30s（与花园同口径）、音量减半、文件字节数、目录已注册', () {
      expect(kWishTreeAmbientAsset, 'assets/audio/bgm/wish_tree_ambient.mp3');
      expect(kWishTreeAmbientAsset, isNot(kGardenAmbientAsset),
          reason: '许愿树音与花园氛围音必须是两个不同素材');
      expect(kWishTreeAmbientGapSeconds, 30,
          reason: 'C138：起播周期 30s（与花园一致，曲长占时自动抵扣）');
      expect(kWishTreeAmbientGapSeconds, kGardenAmbientIntervalSeconds,
          reason: '两处口径同为 30（C138 对齐花园）');
      expect(kWishTreeAmbientVolume, 0.5,
          reason: 'C138：许愿树音音量减半（1.0 → 0.5）');

      final File asset = File(kWishTreeAmbientAsset);
      expect(asset.existsSync(), isTrue, reason: '素材必须已落位：$kWishTreeAmbientAsset');
      expect(asset.lengthSync(), _wishAssetBytes,
          reason: '玄参交付素材实测 $_wishAssetBytes B（防误替换）');

      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/audio/bgm/'), isTrue,
          reason: 'BGM 目录已在 pubspec 注册（本需求无需改 pubspec）');
    });

    test('⑨ resetForTest 复位全部许愿树音状态（跨用例不残留）', () async {
      final AudioService svc = _bgmOnService();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 50));
      unawaited(svc.startWishTreeAmbient());
      await _settleUntil(() => _plays(_wishKey) >= 1);
      expect(svc.wishTreeAmbientLooping, isTrue, reason: '前置：循环在跑');

      svc.resetForTest();

      expect(svc.wishTreeAmbientLooping, isFalse);
      expect(svc.wishTreeAmbientShouldPlay, isFalse);
      expect(svc.wishTreeAmbientPlayCalls, 0);
      final int gen = svc.wishTreeAmbientGeneration;
      svc.stopWishTreeAmbient(reason: 'test');
      expect(svc.wishTreeAmbientGeneration, gen + 1,
          reason: '复位后仍是可用的干净态（stop 不炸）');
    });
  });
}
