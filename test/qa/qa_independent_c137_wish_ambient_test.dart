/// QA 独立验证 · C137 许愿树页专属背景音（玄参 2026-11-22）。
///
/// ## 本文件的定位（与工程师自测**互不复用**）
/// 工程师的用例在 `test/m3/wish_tree_ambient_test.dart`。本文件是 QA 侧**独立重写**的
/// 反证：判据不复用其断言形状，而是自己构造「可量化的时序证据 + 受控变异可红的咬合点」。
///
/// ## 手段
/// 记录型假 `JustAudioPlatform.instance`（范式同 `test/qa/qa_independent_round2_audio_test.dart`）
/// 捕获**真实 `AudioPlayer` 实际发出的平台调用**（`load` / `play` / `setVolume` / `seek` /
/// `disposePlayer`），按**播放器实例隔离**记录——这是「两套音互不干扰」唯一可靠的判据基础
/// （只看 AudioService 的私有字段会陷入「用实现证明实现」）。
///
/// ⚠️ headless 只能验**调用序列与调度语义**，验不了「真的听见了」。真机项见文件末尾注释。
///
/// ## 六条核心断言的落点
/// | # | 断言 | 用例 |
/// |---|------|------|
/// | 1 | 循环语义 = 播完 → 等待剩余周期 → 再播（每 30s 起播一次，与花园一致） | `A1` `A2` |
/// | 2 | 两轮之间必有 `stop()`（「只响一遍」回归闸门） | `B1` |
/// | 3 | 幂等 + 无 Timer 泄漏 | `C1` `C2` `G1` |
/// | 4 | 与花园氛围音双向零干扰（两个独立 AudioPlayer） | `D1` `D2` |
/// | 5 | bgm 开关 / 退后台 / 页面生命周期 | `E1` `E2` `E3` `G1` |
/// | 6 | 素材与常量守卫 | `F1` `F2` |
library qa_independent_c137_wish_ambient_test;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';

/// 许愿树素材文件名片段（认定「这个播放器装的是许愿树音」的判据）。
const String _wishKey = 'wish_tree_ambient.mp3';

/// 花园氛围音文件名片段（对照组）。
const String _gardenKey = 'background.mp3';

/// 玄参交付素材实测字节数（防误替换）。
const int _wishAssetBytes = 242048;

/// 玄参交付素材实测曲长（毫秒）——假平台据此回报 duration。
const int _wishTrackMs = 10083;

// ── 记录型假 just_audio 平台 ─────────────────────────────────────────────────

/// 单个平台播放器：**只记录自己**收到的调用（按实例隔离 = 独立性判据）。
class _RecPlayer extends AudioPlayerPlatform {
  _RecPlayer(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  /// 本实例的调用序列：`load:<uri>` / `play` / `volume:<v>` / `seek`。
  final List<String> calls = <String>[];

  /// 最后一次加载的 uri（空 = 还没加载过）。
  String loadedUri = '';

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  /// 主动发 `completed` = 「这一遍播完了」（引擎并不会自己发，必须由用例驱动）。
  void emitCompleted() => _events.add(_evt(ProcessingStateMessage.completed));

  PlaybackEventMessage _evt(ProcessingStateMessage state) => PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: const Duration(milliseconds: _wishTrackMs),
        duration: const Duration(milliseconds: _wishTrackMs),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage message = request.audioSourceMessage;
    final String uri =
        message is UriAudioSourceMessage ? message.uri : message.toString();
    loadedUri = uri;
    calls.add('load:$uri');
    // 真实平台加载完会推 `ready`（`setAsset` 的 Future 靠它完成）。
    scheduleMicrotask(() => _events.add(_evt(ProcessingStateMessage.ready)));
    return LoadResponse(duration: const Duration(milliseconds: _wishTrackMs));
  }

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
  /// 本次用例创建过的全部平台播放器（按创建顺序）。
  final List<_RecPlayer> players = <_RecPlayer>[];

  /// 被平台侧释放的播放器 id（`AudioPlayer.stop()` → `_setPlatformActive(false)` →
  /// `disposePlayer`）。**「两轮之间有 stop」的唯一客观证据**。
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

// ── 观测助手 ─────────────────────────────────────────────────────────────────

/// 加载过 [key] 的平台播放器（`stop()` 后重建 → 可能不止一个）。
List<_RecPlayer> _playersOf(String key) =>
    _fake.players.where((_RecPlayer p) => p.loadedUri.contains(key)).toList();

/// 最近一个加载过 [key] 的播放器。
_RecPlayer? _lastPlayerOf(String key) {
  final List<_RecPlayer> list = _playersOf(key);
  return list.isEmpty ? null : list.last;
}

int _countCalls(String key, bool Function(String) test) => _playersOf(key).fold(
      0,
      (int sum, _RecPlayer p) => sum + p.calls.where(test).length,
    );

/// 累计 `load` 次数（= 起了几遍 / 加载了几次）。
int _loads(String key) => _countCalls(key, (String c) => c.startsWith('load:'));

/// 累计 `play` 次数（= 真正发出几遍播放请求）。
int _plays(String key) => _countCalls(key, (String c) => c == 'play');

/// 累计 `setVolume(v)` 次数。
int _volumes(String key, double v) =>
    _countCalls(key, (String c) => c == 'volume:$v');

/// 自适应等待：轮询 [ready] 直到为真或超时；返回是否达标（便于断言 + 报耗时）。
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

/// 固定推进（无需等条件时用）。
Future<void> _settle([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// 开好开关的服务（生产语义：设置里「背景音乐」为开）。
AudioService _svc({bool bgmOn = true}) {
  final AudioService svc = AudioService();
  svc.applySettings(soundOn: true, bgmOn: bgmOn);
  return svc;
}

// ── 页面层宿主（真实 DI / 内存库；settings 把 just_audio 挡在用例之外）──────

class _OfflineIap implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();
  @override
  Future<bool> isStoreAvailable() async => false;
  @override
  Future<List<IapProduct>> queryProducts(Set<String> ids) async =>
      <IapProduct>[];
  @override
  Future<void> startLifetimePurchase(String id) async {}
  @override
  Future<void> startRestore() async {}
}

/// `bgmOn/soundOn` 关：起播请求计数与意图标记在入口处**同步**记录，
/// 与 just_audio 后端、开关状态都无关 —— 正是「页面是否请求起播」最干净的观测点。
class _QuietSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        soundOn: false,
        bgmOn: false,
      );

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _Host {
  _Host(this.container);

  final ProviderContainer container;

  static Future<_Host> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(database),
        accountServiceProvider.overrideWithValue(account),
        iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
        settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    return _Host(container);
  }
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
    final Directory tmp = Directory.systemTemp.createTempSync('qa_c137');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProvider, (MethodCall call) async => tmp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 1：循环语义 = 播完 → 等待剩余周期 → 再播（起播间隔 = gap，与花园一致）
  // ══════════════════════════════════════════════════════════════════════════
  group('断言1 · 循环语义：播完 → 静默 → 再播', () {
    test('A1：未收到「本遍播完」时，越过多个 gap 也一次都不重播', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      const Duration gap = Duration(milliseconds: 300);
      svc.debugSetWishTreeAmbientGap(gap);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：第一遍必须起播');
      expect(_plays(_wishKey), 1, reason: '前置：只播了 1 遍');

      // 关键：**不发 completed**，静默跨过 3 个 gap。
      await Future<void>.delayed(gap * 3);
      expect(_plays(_wishKey), 1,
          reason: '没有「播完」事件就不得重播 —— 若实现是 Timer.periodic(gap)，'
              '这 3 个周期里必然叠出 ≥3 次 play（这就是花园语义，不是许愿树语义）');
      expect(_loads(_wishKey), 1,
          reason: '同理：不得周期性重复 setAsset');
      expect(svc.wishTreeAmbientLooping, isTrue,
          reason: '此时循环协程仍在「等这一遍播完」');

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('A2：completed 之后才开始计 gap，且必须等满 gap 才重播（顺序 play→completed→gap→play）',
        () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      const Duration gap = Duration(milliseconds: 400);
      svc.debugSetWishTreeAmbientGap(gap);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：第一遍起播');
      final _RecPlayer round1 = _lastPlayerOf(_wishKey)!;

      // ── 第一遍播完 ──
      final Stopwatch clock = Stopwatch()..start();
      round1.emitCompleted();

      // gap 未走完前**绝不能**重播（这是「等待发生在播放完成之后」的正向证据；
      // 若 gap 被改成 0 / 直接跳过等待，此断言必红）。
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(_plays(_wishKey), 1,
          reason: 'gap(400ms) 未走完（才过 120ms）就重播 ⇒ 说明 gap 没有真正插在'
              '「播完」和「再播」之间');

      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue,
          reason: 'completed 之后必须重播（玄参原话「然后再播放」）');
      final Duration untilRound2 = clock.elapsed;
      // ignore: avoid_print
      print('[C137-QA] A2 第一遍播完 → 第二遍起播 实测耗时 = '
          '${untilRound2.inMilliseconds} ms（gap=400ms）');
      expect(untilRound2, greaterThanOrEqualTo(const Duration(milliseconds: 350)),
          reason: '第二遍起播必须晚于 gap（实测 ${untilRound2.inMilliseconds}ms）');
      expect(untilRound2, lessThan(const Duration(milliseconds: 2500)),
          reason: '也不得异常拖沓（实测 ${untilRound2.inMilliseconds}ms）');

      // ── 第二轮同样成立：至少跑满 2 个完整轮次 ──
      final _RecPlayer round2 = _lastPlayerOf(_wishKey)!;
      round2.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 3), isTrue,
          reason: '必须可重复：播→停→播→停→播（至少 2 个完整轮次）');
      expect(_loads(_wishKey), 3, reason: '每轮都重新加载自己的素材');

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 2：「只响一遍」回归 —— 两轮之间必须有 stop()
  // ══════════════════════════════════════════════════════════════════════════
  group('断言2 · 两轮之间必有 stop()（just_audio playing 粘滞的回归闸门）', () {
    test('B1：第二轮起播前后，平台侧必须发生一次 disposePlayer（= player.stop()）', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 150));

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：第一遍起播');

      final _RecPlayer round1 = _lastPlayerOf(_wishKey)!;
      final int disposedBefore = _fake.disposedIds.length;

      round1.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue,
          reason: '🔴 第二轮必须真的起播 —— 这正是「播一遍之后再也不响」bug 的'
              '回归闸门；若每轮的 `player.stop()` 被删掉，just_audio 0.9.46 的 '
              '`play()` 会因 `if (playing) return;` 静默挡掉（playing 在 completed 后'
              '仍为 true，见 just_audio.dart:927-933 文档），此处必红');

      // stop() 的客观证据：平台侧 disposePlayer 被调用，且对象正是第一轮那个实例。
      expect(_fake.disposedIds.length, greaterThan(disposedBefore),
          reason: '两轮之间必须调用过 player.stop()（否则 playing 粘滞 → 只响一遍）');
      expect(_fake.disposedIds.skip(disposedBefore), contains(round1.id),
          reason: '被释放的必须正是第一轮那个平台播放器（id=${round1.id}）');

      // stop() 之后 setAsset 会重建平台播放器 ⇒ 第二轮落在另一个实例上。
      final _RecPlayer round2 = _lastPlayerOf(_wishKey)!;
      expect(identical(round2, round1), isFalse,
          reason: '第二轮必须是重建后的平台播放器（同一实例 = 根本没走 stop）');
      expect(round2.id, round1.id,
          reason: '二者 AudioPlayer id 相同（同一个 AudioPlayer，只是平台侧重建）');
      expect(_playersOf(_wishKey).length, 2,
          reason: '两轮 = 两个平台播放器实例');

      // 每轮各自恰好 play 一次（不是 loopMode 单实例反复播）。
      expect(
          round1.calls.where((String c) => c == 'play').length, 1,
          reason: '第一轮只 play 一次');
      expect(
          round2.calls.where((String c) => c == 'play').length, 1,
          reason: '第二轮只 play 一次');

      // C138：许愿树音每轮起播音量 = 原 1.0 减半（0.5）；只作用于本独立播放器。
      // ⚠️ 计数口径：just_audio 在 `_setPlatformActive(true)` 时会把当前音量**补发**给新
      // 平台播放器（音频会话激活即应用 volume），故每轮会出现 ≥1 次 `volume:0.5`，
      // 不能断言「恰好每轮 1 次」——只断言「每轮都至少设置到 0.5 一次」。
      for (final _RecPlayer p in <_RecPlayer>[round1, round2]) {
        expect(
            p.calls.where((String c) => c == 'volume:$kWishTreeAmbientVolume'),
            isNotEmpty,
            reason: '每轮起播音量必须是 0.5（实例 ${p.id} 的调用：${p.calls}）');
      }
      expect(_volumes(_wishKey, kWishTreeAmbientVolume), greaterThanOrEqualTo(2),
          reason: '两轮累计至少 2 次 volume:0.5');

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 3：幂等 + 无 Timer 泄漏
  // ══════════════════════════════════════════════════════════════════════════
  group('断言3 · 幂等与不泄漏', () {
    test('C1：连续 start 两次只起一条循环（load/play 不翻倍，第二轮不叠播）', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 150));

      unawaited(svc.startWishTreeAmbient());
      unawaited(svc.startWishTreeAmbient()); // 同一 turn 内重复进入
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：起播');

      expect(_loads(_wishKey), 1, reason: '幂等闸门拦下第二次 ⇒ 只加载一次');
      expect(_plays(_wishKey), 1, reason: '绝不能叠出第二条循环并发播放');
      expect(_playersOf(_wishKey).length, 1, reason: '只有一个许愿树播放器在工作');
      expect(svc.wishTreeAmbientPlayCalls, 2,
          reason: '起播请求计数照实记 2 次（入口处同步递增，与幂等无关）');
      expect(svc.wishTreeAmbientLooping, isTrue, reason: '循环闸门为单值（bool 不变量）');

      // 跑完一轮：若真叠了第二条循环，此刻会多出一次 play。
      _lastPlayerOf(_wishKey)!.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue,
          reason: '第二轮起播');
      await _settle(300);
      expect(_plays(_wishKey), 2,
          reason: '一轮只对应一次重播；出现 3 次即说明叠了第二条循环');

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('C2：stop 打断静默间隔 ⇒ 越过 gap 零新 play，且之后能再次干净起播', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      const Duration gap = Duration(milliseconds: 300);
      svc.debugSetWishTreeAmbientGap(gap);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：起播');

      // 制造「正处于静默间隔」的状态。
      _lastPlayerOf(_wishKey)!.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(svc.wishTreeAmbientLooping, isTrue,
          reason: '静默间隔期间循环协程仍在跑（防重复起循环的闸门为 true）');

      final int genBeforeStop = svc.wishTreeAmbientGeneration;
      svc.stopWishTreeAmbient(reason: 'leave');
      expect(svc.wishTreeAmbientGeneration, genBeforeStop + 1,
          reason: 'stop 必须递增代际（作废在途静默等待）');
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '循环闸门立即关闭');
      expect(svc.wishTreeAmbientShouldPlay, isFalse,
          reason: '离开页面（非 keepIntent）必须撤销应播意图');

      final int playsAtStop = _plays(_wishKey);
      final int loadsAtStop = _loads(_wishKey);
      await Future<void>.delayed(gap * 2); // 越过 2 个 gap
      expect(_plays(_wishKey), playsAtStop,
          reason: 'stop 时正在等的 gap 必须被取消 ⇒ 越过 gap 也不得再播');
      expect(_loads(_wishKey), loadsAtStop, reason: '也不得再 setAsset');

      // 闸门未卡死：可以重新起播（真机「离开又回来」）。
      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) > playsAtStop), isTrue,
          reason: 'stop 之后必须能重新起播（否则本进程内彻底哑掉，只能杀 App）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 4：两套音双向零干扰（两个独立 AudioPlayer）
  // ══════════════════════════════════════════════════════════════════════════
  group('断言4 · 与花园氛围音互不干扰', () {
    test('D1：花园先播 → 许愿树跑满 2 轮期间花园零新增调用 / 零释放 / 代际不变', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 120));

      svc.playGardenAmbient();
      expect(await _waitFor(() => _playersOf(_gardenKey).isNotEmpty), isTrue,
          reason: '前置：花园氛围音已起播');
      final _RecPlayer garden = _lastPlayerOf(_gardenKey)!;
      final int gardenCalls = garden.calls.length;
      final int disposedBefore = _fake.disposedIds.length;
      final int gardenGen = svc.ambientGeneration;
      expect(svc.ambientShouldPlay, isTrue, reason: '前置：花园「应播」意图为 true');

      // 许愿树：跑满 2 轮。
      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '许愿树音起播');
      _lastPlayerOf(_wishKey)!.emitCompleted();
      expect(await _waitFor(() => _plays(_wishKey) >= 2), isTrue,
          reason: '许愿树音第二轮起播');

      expect(garden.calls.length, gardenCalls,
          reason: '许愿树音起播 + 两轮循环期间，花园播放器不得再收到任何 '
              'load/play/volume/seek（会被自己的 stop 抢、或被覆盖素材）');
      expect(_fake.disposedIds.skip(disposedBefore), isNot(contains(garden.id)),
          reason: '花园播放器不得被 stop（把 _wishAmbientPlayer 改成复用 _ambientPlayer '
              '时，许愿树每轮的 stop() 会打到这里 ⇒ 必红）');
      expect(svc.ambientGeneration, gardenGen,
          reason: '花园代际不得被推进（说明根本没走花园的 stop 路径）');
      expect(svc.ambientShouldPlay, isTrue, reason: '花园「应播」意图不受影响');
      expect(garden.loadedUri.contains(_gardenKey), isTrue,
          reason: '花园播放器仍持有自己的素材（未被许愿树音覆盖）');

      // 两个 AudioPlayer = 两个不同的平台 player id。
      final _RecPlayer wish = _lastPlayerOf(_wishKey)!;
      expect(wish.id, isNot(garden.id),
          reason: '🔴 必须是两个独立 AudioPlayer（复用同一实例时 id 相同 ⇒ 必红）');

      svc.stopWishTreeAmbient(reason: 'test');
      await svc.stopGardenAmbient(reason: 'test');
    });

    test('D2：许愿树先播 → 花园起播期间许愿树零新增调用 / 代际不变 / 循环不被打断', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：许愿树音起播');
      final _RecPlayer wish = _lastPlayerOf(_wishKey)!;
      final int wishCalls = wish.calls.length;
      final int disposedBefore = _fake.disposedIds.length;
      final int wishGen = svc.wishTreeAmbientGeneration;
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.playGardenAmbient();
      expect(await _waitFor(() => _playersOf(_gardenKey).isNotEmpty), isTrue,
          reason: '花园音起播');

      expect(wish.calls.length, wishCalls,
          reason: '花园起播期间，许愿树播放器不得被 load/play/volume/seek');
      expect(_fake.disposedIds.skip(disposedBefore), isNot(contains(wish.id)),
          reason: '许愿树播放器不得被花园的 stop 打到');
      expect(svc.wishTreeAmbientGeneration, wishGen,
          reason: '许愿树代际不得被花园音推进');
      expect(svc.wishTreeAmbientLooping, isTrue,
          reason: '许愿树循环不被花园音打断');
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: '许愿树「应播」意图不受花园影响');
      expect(wish.loadedUri.contains(_wishKey), isTrue,
          reason: '许愿树播放器仍持有自己的素材');
      expect(wish.id, isNot(_lastPlayerOf(_gardenKey)!.id),
          reason: '两个独立 AudioPlayer');

      svc.stopWishTreeAmbient(reason: 'test');
      await svc.stopGardenAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 5：bgm 开关与生命周期
  // ══════════════════════════════════════════════════════════════════════════
  group('断言5 · 受「背景音乐」开关与前后台生命周期控制', () {
    test('E1：bgmOn=false 时一声不出，但记下「页内应播」意图', () async {
      final AudioService svc = _svc(bgmOn: false);
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      await _settle(300);

      expect(_loads(_wishKey), 0, reason: '关背景音乐不得加载');
      expect(_plays(_wishKey), 0, reason: '关背景音乐一声都不许出');
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '不进入循环');
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: '意图先于开关判定记录（冷启动时 _bgmOn 仍为默认 false，'
              '此处不留痕迹则设置迟到后无人补播）');
      expect(svc.wishTreeAmbientPlayCalls, 1, reason: '起播请求照实记 1 次');
    });

    test('E2：applySettings(bgmOn:false) 立即停且保留意图；改回 true 必须补播', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：正在播');
      final _RecPlayer playing = _lastPlayerOf(_wishKey)!;
      final int playsBefore = _plays(_wishKey);

      svc.applySettings(soundOn: true, bgmOn: false);
      expect(await _waitFor(() => _fake.disposedIds.contains(playing.id)), isTrue,
          reason: '关背景音乐必须真的 stop 掉正在播的播放器');
      expect(svc.wishTreeAmbientLooping, isFalse, reason: '循环已收尾');
      expect(svc.wishTreeAmbientShouldPlay, isTrue,
          reason: 'keepIntent：用户还在许愿树页，意图必须保留（否则重开无法补播）');

      const Duration gap = Duration(milliseconds: 200);
      svc.debugSetWishTreeAmbientGap(gap);
      await Future<void>.delayed(gap * 2);
      expect(_plays(_wishKey), playsBefore,
          reason: '关掉之后越过 gap 也不得再播');

      svc.applySettings(soundOn: true, bgmOn: true);
      expect(await _waitFor(() => _plays(_wishKey) > playsBefore), isTrue,
          reason: '重新打开背景音乐必须补播（本页不会再次 initState）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('E3：「关掉又立刻打开」（关→开无间隔）仍必须补播，且不残留 stop 竞态', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：正在播');
      final int playsBefore = _plays(_wishKey);

      // 真机场景：设置页连续点两下 toggle（stop 的平台收尾还在飞）。
      svc.applySettings(soundOn: true, bgmOn: false);
      svc.applySettings(soundOn: true, bgmOn: true);

      expect(await _waitFor(() => _plays(_wishKey) > playsBefore), isTrue,
          reason: '必须补播（实现里 startWishTreeAmbient 会先等上一次 stop 落地，'
              '避免 just_audio activation 交叉 ⇒ 「Loading interrupted」无声）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });

    test('E4：退后台立即停（一声不出）、回前台续播', () async {
      final AudioService svc = _svc();
      addTearDown(svc.dispose);
      svc.debugSetWishTreeAmbientGap(const Duration(milliseconds: 150));

      unawaited(svc.startWishTreeAmbient());
      expect(await _waitFor(() => _plays(_wishKey) >= 1), isTrue,
          reason: '前置：正在播');
      final int playsBefore = _plays(_wishKey);

      await svc.pauseAllForBackground();
      expect(svc.wishTreeAmbientLooping, isFalse,
          reason: '退后台 / 锁屏必须停（F70 同源：否则锁屏后还在响）');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(_plays(_wishKey), playsBefore, reason: '后台期间一声都不许出');

      await svc.resumeFromBackground();
      expect(await _waitFor(() => _plays(_wishKey) > playsBefore), isTrue,
          reason: '回前台必须续播（用户仍停在许愿树页）');
      expect(svc.wishTreeAmbientLooping, isTrue);

      svc.stopWishTreeAmbient(reason: 'test');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 6：素材与常量守卫
  // ══════════════════════════════════════════════════════════════════════════
  group('断言6 · 素材与常量守卫', () {
    test('F1：路径 / 起播周期 30s / 音量减半 / 文件真实存在 / 字节数 / pubspec 已注册', () {
      expect(kWishTreeAmbientAsset, 'assets/audio/bgm/wish_tree_ambient.mp3');
      expect(kWishTreeAmbientAsset, isNot(kGardenAmbientAsset),
          reason: '许愿树音与花园氛围音必须是两个不同素材');
      expect(kWishTreeAmbientGapSeconds, 30,
          reason: 'C138：起播周期 30s（与花园一致，曲长占时自动抵扣）');
      expect(kWishTreeAmbientVolume, 0.5,
          reason: 'C138：许愿树音音量减半（1.0 → 0.5）');

      final File asset = File(kWishTreeAmbientAsset);
      expect(asset.existsSync(), isTrue,
          reason: '素材必须已落位：$kWishTreeAmbientAsset');
      expect(asset.lengthSync(), _wishAssetBytes,
          reason: '玄参交付素材实测 $_wishAssetBytes B（防误替换）');

      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/audio/bgm/'), isTrue,
          reason: 'BGM 目录必须已在 pubspec 的 assets 注册（漏了 = 真机静默无声）');
      // 目录声明覆盖了新文件（不是逐个文件声明）。
      expect(pubspec.contains('assets/audio/bgm/wish_tree_ambient.mp3'), isFalse,
          reason: '本工程按**目录**声明资产；逐个文件声明说明口径被改坏了');
    });

    test('F2：素材路径只有单点常量一处硬编码（lib/ 内不得有第二处字面量）', () {
      const String literal = "'assets/audio/bgm/wish_tree_ambient.mp3'";
      final List<String> offenders = <String>[];
      final List<File> files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      for (final File f in files) {
        if (f.readAsStringSync().contains(literal)) offenders.add(f.path);
      }
      expect(offenders, <String>['lib/core/constants/prd_params.dart'],
          reason: '字面量只允许出现在 prd_params.dart 单点常量处；'
              '音频服务必须引用 kWishTreeAmbientAsset（实际命中：$offenders）');

      final String svcSrc =
          File('lib/platform/audio_service.dart').readAsStringSync();
      expect(svcSrc.contains('setAsset(kWishTreeAmbientAsset)'), isTrue,
          reason: '起播必须走单点常量，而不是就地写死路径');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 断言 3（补充）/ 断言 5（页面层）：真实 WishTreePage 挂载触发 start、卸载触发 stop
  // ══════════════════════════════════════════════════════════════════════════
  group('页面层接线 · 真实 WishTreePage', () {
    final AudioService audio = AudioService.instance;

    setUp(() {
      audio.resetForTest();
      // 显式关掉 BGM：本组只验「页面是否请求起播 / 是否请求停止」的接线，
      // 不把真机 just_audio I/O 拉进 FakeAsync（那属于服务层 A~E 组的职责）。
      audio.applySettings(soundOn: false, bgmOn: false);
    });

    tearDown(() {
      audio.stopWishTreeAmbient(reason: 'test');
    });

    testWidgets('G1：挂载 ⇒ 请求起播一次 + 记下应播意图；卸载 ⇒ 停播 + 意图撤销 + 循环收尾'
        '（同时校验无 pending timer / 无异常）', (WidgetTester tester) async {
      final _Host h = await _Host.boot();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final int playCallsBefore = audio.wishTreeAmbientPlayCalls;
      final int genBefore = audio.wishTreeAmbientGeneration;
      expect(audio.wishTreeAmbientShouldPlay, isFalse, reason: '前置：未进树页 = 不应播');

      // ── 挂载真实树页（= 任意入口 push 进 /wish-tree）──
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: WishTreePage()),
      ));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byType(WishTreePage), findsOneWidget, reason: '真实树页已上树');
      expect(audio.wishTreeAmbientPlayCalls, playCallsBefore + 1,
          reason: '树页 initState 帧后必须调 AudioService.startWishTreeAmbient()');
      expect(audio.wishTreeAmbientShouldPlay, isTrue,
          reason: '页内「应播」意图已记录（bgmOn=false 时同样记，等设置迟到补播）');
      expect(tester.takeException(), isNull, reason: '挂载不得抛 provider / 生命周期断言');

      // ── 卸载真实树页（= pop 回花园）──
      await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(WishTreePage), findsNothing);
      expect(audio.wishTreeAmbientShouldPlay, isFalse,
          reason: '离开许愿树页必须停播专属背景音（「其他界面不播放」）');
      expect(audio.wishTreeAmbientLooping, isFalse, reason: '循环必须收尾');
      expect(audio.wishTreeAmbientGeneration, greaterThan(genBefore),
          reason: 'stopWishTreeAmbient 必须被真实调用（代际递增）');
      expect(tester.takeException(), isNull, reason: '卸载不得抛异常');
      // 本用例 teardown 时若有 Timer 残留，flutter_test 会直接判失败
      // （"A Timer is still pending even after the widget tree was disposed"）。
    });
  });
}

// ── 只能靠真机验证的部分（headless 无法证明，见 QA 报告）─────────────────────
//
// 1. 真实听感：10.083s 播完约静默 20s、每 30s 再响一次（C138 与花园同口径）
//    —— headless 只能证明「调用序列与等待时长」正确，证明不了扬声器真的安静/有声）。
// 2. iOS/Android 平台上 `processingState == completed` 是否**按时**到达（本文件用假
//    平台主动发事件；真机若「哑起播」不发 completed，实现只能靠 duration+5s 兜底）。
// 3. 与花园音共存时的真实混音（两个 AVAudioPlayer/ExoPlayer 同时出声、音量是否互相压制）。
// 4. 页面 push/pop 时的真实路由动画期间是否有可听的尾巴（dispose 时机 vs 平台 stop 耗时）。
// 5. 锁屏 / 来电 / 耳机拔出等真实音频会话打断（本文件只驱动 pauseAllForBackground 入口）。
