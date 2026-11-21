/// AudioService 单元测试（M2 音频模块）。
///
/// 核心契约：**资源缺失 / 无可用播放器时静默降级**——构造后直接调用
/// [AudioService.playSfx] / [AudioService.startBgm] 等不得抛异常、不得令测试失败。
///
/// 静音开关精确语义（玄参拍板）：`soundOn` **只管「专注中收集阳光」提示音**
/// （`AudioCue.focusCollect`，唯一显式传 `respectSoundSwitch: true` 的调用点）；
/// 其余一切 SFX（结束倒计时 / 升级 / 结算 / 护眼 / 花园 / 守卫战斗与大招等）
/// 在 `soundOn=false` 时**照常播放**。本文件既有无播放器降级用例，也用记录型假
/// `JustAudioPlatform` 捕获真实 `AudioPlayer` 发出的 `load` 请求做行为级断言。
///
/// 注：headless 测试环境（无 macos/linux 原生壳）无音频后端，just_audio 的静态方法通道
/// 缺实现会抛未捕获的 MissingPluginException，无法在此环境构造真实 [AudioPlayer]。因此降级
/// 用例注入「返回 null」的播放器工厂，验证 [AudioService] 在「无可用播放器」时静默降级（与
/// 「资源缺失」同级：不抛异常、不刷日志）。行为级用例改用假平台 + 默认工厂。
library audio_service_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/platform/audio_service.dart';

// ── 记录型假 just_audio 平台：只记录 load(uri)，足以判定「闸门是否放行到真实播放链」──

class _LoadRecPlayer extends AudioPlayerPlatform {
  _LoadRecPlayer(super.id, this.loads);
  final List<String> loads;
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final AudioSourceMessage m = request.audioSourceMessage;
    final String uri = m is UriAudioSourceMessage ? m.uri : m.toString();
    loads.add('load:$uri');
    // 让 loadAssetBounded 能从加载窗口正常走出。
    scheduleMicrotask(
      () => _events.add(
        PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updateTime: DateTime.now(),
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          duration: const Duration(seconds: 4),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ),
      ),
    );
    return LoadResponse(duration: const Duration(seconds: 4));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();
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

class _LoadRecPlatform extends JustAudioPlatform {
  final List<String> loads = <String>[];
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _LoadRecPlayer(request.id, loads);
  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse.fromMap(<dynamic, dynamic>{});
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{});
}

void main() {
  // 注入返回 null 的播放器工厂：全程不构造真实 AudioPlayer，避免 headless 环境的原生异常。
  final AudioService audio = AudioService(playerFactory: () => null);

  group('AudioService 静默降级', () {
    test('构造后直接 playSfx 任意 cue 不抛异常（无可用播放器）', () {
      // playSfx 为 fire-and-forget，无可用播放器时直接跳过，不得向外抛异常。
      expect(() => audio.playSfx(AudioCue.taskReward), returnsNormally);
      expect(() => audio.playSfx(AudioCue.progress), returnsNormally);
      expect(() => audio.playSfx(AudioCue.welcomeBack), returnsNormally);
      expect(() => audio.playSfx(AudioCue.wake), returnsNormally);
    });

    test('applySettings / startBgm / stopBgm / dispose 调用本身不抛同步异常', () {
      expect(
        () => audio.applySettings(soundOn: true, bgmOn: true),
        returnsNormally,
      );
      // 无可用播放器时，startBgm/stopBgm/dispose 直接返回（空操作），Future 正常完成。
      expect(() => audio.startBgm(), returnsNormally);
      expect(() => audio.stopBgm(), returnsNormally);
      expect(() => audio.dispose(), returnsNormally);
    });

    test('soundOn=false 一刀切拦截已废除：所有默认调用点仍进入播放链（不抛异常）', () {
      audio.applySettings(soundOn: false, bgmOn: false);
      // 结束 / 升级 / 结算 / 护眼 / 花园 / 守卫 —— 全部走默认（不受管），照常起播。
      expect(() => audio.playSfx(AudioCue.focusEndCountdown), returnsNormally);
      expect(() => audio.playSfx(AudioCue.levelUpDefault), returnsNormally);
      expect(() => audio.playSfx(AudioCue.focusSettle), returnsNormally);
      expect(() => audio.playSfx(AudioCue.eyeCare), returnsNormally);
      expect(() => audio.playSfx(AudioCue.careWater), returnsNormally);
      expect(
        () => audio.playSfxPaths(<String>['assets/audio/sfx/guard_ultimate_fx.mp3']),
        returnsNormally,
      );
      // 唯一受管点（focusCollect）也照常走完调用、不抛异常（行为级断言见下方 group）。
      expect(
        () => audio.playSfx(AudioCue.focusCollect, respectSoundSwitch: true),
        returnsNormally,
      );
    });
  });

  group('氛围音自愈判定（F67：养护音效打断花园背景音后不恢复）', () {
    test('播放中 → 不自愈', () {
      expect(
        AudioService.ambientNeedsHeal(isPlaying: true, completed: false),
        isFalse,
      );
    });

    test('自然播完（completed）→ 不自愈，交给花园页 30s 定时器', () {
      expect(
        AudioService.ambientNeedsHeal(isPlaying: false, completed: true),
        isFalse,
      );
    });

    test('被打断（paused，未播完）→ 自愈续播', () {
      expect(
        AudioService.ambientNeedsHeal(isPlaying: false, completed: false),
        isTrue,
      );
    });

    test('被 stop 打断（idle，未播完）→ 自愈续播', () {
      // 被 SFX 在共享音频会话上抢停后 processingState 可能是 idle 而非 paused，
      // 两者都「未播完」，都应自愈。
      expect(
        AudioService.ambientNeedsHeal(isPlaying: false, completed: false),
        isTrue,
      );
    });
  });

  group('F203 · SFX 叠加池（战斗音效连点全消失修复）', () {
    test('挑槽策略：有空闲槽 → 取第一个空闲槽（绝不占用忙槽）', () {
      expect(
        AudioService.pickSfxPoolSlot(
          busy: <bool>[true, false, true, false],
          cursor: 2,
        ),
        1,
        reason: '空闲槽按序取第一个 —— 保证 4 支以内完全不互相打断',
      );
    });

    test('挑槽策略：全忙 → 按游标轮换', () {
      expect(
        AudioService.pickSfxPoolSlot(
          busy: <bool>[true, true, true, true],
          cursor: 0,
        ),
        0,
      );
      expect(
        AudioService.pickSfxPoolSlot(
          busy: <bool>[true, true, true, true],
          cursor: 3,
        ),
        3,
      );
      expect(
        AudioService.pickSfxPoolSlot(
          busy: <bool>[true, true, true, true],
          cursor: 4,
        ),
        0,
        reason: '游标绕回',
      );
    });

    test('playSfxOverlap 无可用播放器（null 槽）静默降级不抛', () async {
      final int idx = await audio.playSfxOverlapForTest(
        'assets/audio/sfx/guard_attack.mp3',
      );
      expect(idx, inInclusiveRange(0, AudioService.kSfxOverlapPoolSize - 1),
          reason: '返回合法槽位下标（null 槽下标合法，播放静默跳过）');
    });

    test('soundOn=false 时 playSfxOverlap 默认不受管（守卫战斗音照常起播）', () {
      audio.applySettings(soundOn: false, bgmOn: false);
      expect(
        () => audio.playSfxOverlap(AudioCue.guardAttack),
        returnsNormally,
      );
      // 即使显式受管也只走静默跳过，不抛异常（行为级断言见下方 group）。
      expect(
        () => audio.playSfxOverlap(
          AudioCue.guardAttack,
          respectSoundSwitch: true,
        ),
        returnsNormally,
      );
    });
  });

  // ── 行为级：静音开关精确语义（真实 AudioPlayer + 记录型假平台）──────────────
  group('静音开关精确语义 · 行为级（soundOn=false 只拦收集阳光）', () {
    late _LoadRecPlatform fake;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      fake = _LoadRecPlatform();
      JustAudioPlatform.instance = fake;
    });

    setUp(() {
      fake.loads.clear();
      const MethodChannel pathProvider =
          MethodChannel('plugins.flutter.io/path_provider');
      final Directory tmp =
          Directory.systemTemp.createTempSync('sfx_switch_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        pathProvider,
        (MethodCall call) async => tmp.path,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null),
      );
    });

    /// 等待真实异步链（建播放器 / 清缓存 / setAsset / play）推进到出现 [uri]。
    Future<void> settleUntil(String uri) async {
      for (int i = 0; i < 100; i++) {
        if (fake.loads.any((String e) => e.contains(uri))) return;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    /// 充分排空，用于断言「不应出现某 load」——确保有足够时间证明它确实被拦。
    Future<void> drain() async {
      for (int i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    int loadsOf(String uri) =>
        fake.loads.where((String e) => e.contains(uri)).length;

    test('受管：soundOn=false → focusCollect（respectSoundSwitch:true）无 load', () async {
      final AudioService svc = AudioService(); // 默认工厂：真实 AudioPlayer + 假平台
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.focusCollect, respectSoundSwitch: true);
      await drain();
      expect(loadsOf('focus_collect.mp3'), 0,
          reason: '音效开关关闭时，唯一受管的收集阳光音必须被拦（不进入 load 链）');
      await svc.dispose();
    });

    test('对照：soundOn=true → focusCollect 照常 load（证明拦截确由开关造成）', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: true, bgmOn: false);
      svc.playSfx(AudioCue.focusCollect, respectSoundSwitch: true);
      await settleUntil('focus_collect.mp3');
      expect(loadsOf('focus_collect.mp3'), greaterThanOrEqualTo(1),
          reason: '音效开关打开时收集阳光音应正常起播（对照组）');
      await svc.dispose();
    });

    test('不受管：soundOn=false → 专注结束倒计时照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.focusEndCountdown);
      await settleUntil('5s_countdown.mp3');
      expect(loadsOf('5s_countdown.mp3'), greaterThanOrEqualTo(1),
          reason: '玄参点名：关掉音效开关后专注结束提示音必须照常播放');
      await svc.dispose();
    });

    test('不受管：soundOn=false → 等级升级音（普通 / 称号节点）照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.levelUpDefault);
      await settleUntil('default_level_up.mp3');
      expect(loadsOf('default_level_up.mp3'), greaterThanOrEqualTo(1),
          reason: '玄参点名：关掉音效开关后等级升级提示音必须照常播放');
      await svc.dispose();

      final AudioService svc2 = AudioService();
      svc2.applySettings(soundOn: false, bgmOn: false);
      svc2.playSfx(AudioCue.levelUpFive);
      await settleUntil('5_level_up.mp3');
      expect(loadsOf('5_level_up.mp3'), greaterThanOrEqualTo(1),
          reason: '称号节点升级音同样不受管');
      await svc2.dispose();
    });

    test('不受管：soundOn=false → 结算庆祝音照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.focusSettle);
      await settleUntil('focus_settle.mp3');
      expect(loadsOf('focus_settle.mp3'), greaterThanOrEqualTo(1),
          reason: '玄参点名：关掉音效开关后结算庆祝音必须照常播放');
      await svc.dispose();
    });

    test('不受管：soundOn=false → 护眼配音照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.eyeCare);
      await settleUntil('eyecare.mp3');
      expect(loadsOf('eyecare.mp3'), greaterThanOrEqualTo(1),
          reason: '护眼配音不受音效开关影响');
      await svc.dispose();
    });

    test('不受管：soundOn=false → playSfxPaths（大招特效音）照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfxPaths(<String>['assets/audio/sfx/guard_ultimate_fx.mp3']);
      await settleUntil('guard_ultimate_fx.mp3');
      expect(loadsOf('guard_ultimate_fx.mp3'), greaterThanOrEqualTo(1),
          reason: '守卫大招音不受音效开关影响');
      await svc.dispose();
    });

    test('不受管：soundOn=false → playSfxOverlap（守卫攻击音）照常 load', () async {
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfxOverlap(AudioCue.guardAttack);
      await settleUntil('guard_attack.mp3');
      expect(loadsOf('guard_attack.mp3'), greaterThanOrEqualTo(1),
          reason: '守卫战斗音不受音效开关影响');
      await svc.dispose();
    });

    test('不受管：soundOn=false → 未 opt-in 的 focusCollect 默认调用也照常 load', () async {
      // 明确记录「受管与否由调用点显式 opt-in 决定」：不带 respectSoundSwitch 的
      // focusCollect 调用与真实生产调用点（已 opt-in）区分开，证明默认语义是不受管。
      final AudioService svc = AudioService();
      svc.applySettings(soundOn: false, bgmOn: false);
      svc.playSfx(AudioCue.focusCollect);
      await settleUntil('focus_collect.mp3');
      expect(loadsOf('focus_collect.mp3'), greaterThanOrEqualTo(1),
          reason: '默认不受管；生产调用点必须显式传 respectSoundSwitch:true 才受管');
      await svc.dispose();
    });
  });

  // 释放（无可用播放器时为空操作），便于进程干净退出。
  tearDownAll(() => unawaited(audio.dispose()));
}
