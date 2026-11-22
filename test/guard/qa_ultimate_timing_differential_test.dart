/// QA 独立差分复验 · 本轮大招演出三修复（B1 战士裁边 / B2 清怪时序 / B3 特效放大）。
///
/// 🔴 与工程师测试独立编写，所有期望值写死为字面量，绝不 import 被测实现自证。
/// 三层防守（专治「假绿」）：
///  ① 行为层：真 `FrameSequencePlayer` 逐帧回调单调不重复；真 `GuardUltimateFx`
///     在 frame007（0 基 6）才回调一次 `onEffectFrame`（M-C 阈值改永假 → 转红）；
///  ② 源码结构守卫（私有状态机无法单测）：
///     cast 当帧不记 [_deaths]、怪走行走保持、效果帧才按 fxClockMs 记账、
///     终局挂起+fx收尾+淡出后才交回（M-D / M-E → 转红）；
///  ③ 素材完整性：cast 27 帧全 720×720 全画布（C130 玄参「不裁切」）、fx 27 帧 1470×630、
///     连号无缺、pubspec 声明不变。
library qa_ultimate_timing_differential_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:sunflower_time/platform/audio_service.dart'
    show AudioService;
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart'
    show FrameSequencePlayer, fxFrameAssets;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show GuardUltimateFx, kUltimateFxKillTriggerFrame;

String _root() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/guard') || cwd.endsWith('\\test\\guard')
      ? Directory.current.parent.parent.path
      : cwd;
}

String _src(String rel) => File('${_root()}/$rel').readAsStringSync();

/// 去掉 `//` 行注释与 `/* */` 块注释，只留代码（避免文档里的字面量误伤守卫断言）。
String _codeOnly(String src) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < src.length) {
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

String _between(String src, String from, String to) {
  final int a = src.indexOf(from);
  if (a < 0) return '';
  final int b = to.isEmpty ? src.length : src.indexOf(to, a + from.length);
  return b < 0 ? src.substring(a) : src.substring(a, b);
}

// ── headless 假 just_audio 平台：GuardUltimateFx initState 会触发 fx 音轨，
//    这里让 load 立即 ready、其余返回空响应，避免原生插件缺失导致异步错误 /
//    pending timer 假失败。只记录 load 与否，不参与任何断言 ──────────────────

class _NoopPlayer extends AudioPlayerPlatform {
  _NoopPlayer(super.id);
  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
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

class _NoopPlatform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _NoopPlayer(request.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse.fromMap(<dynamic, dynamic>{});
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{});
}

/// 解析 VP8X WebP 的画布尺寸（字节 24..26 = 宽−1，27..29 = 高−1，小端）。
List<int> _webpSize(String rel) {
  final List<int> b = File('${_root()}/$rel').readAsBytesSync();
  if (b.length < 30 || String.fromCharCodes(b.sublist(12, 16)) != 'VP8X') {
    return <int>[-1, -1];
  }
  final int w = b[24] | (b[25] << 8) | (b[26] << 16);
  final int h = b[27] | (b[28] << 8) | (b[29] << 16);
  return <int>[w + 1, h + 1];
}

/// 解析 PNG IHDR 的画布尺寸（IHDR 剩余 24..28 宽 / 28..32 高，大端）。
List<int> _pngSize(String rel) {
  final List<int> b = File('${_root()}/$rel').readAsBytesSync();
  // PNG 签名 8B + IHDR 长度/类型 8B ⇒ 数据区从 16 起：宽 16..20 / 高 20..24。
  if (b.length < 24 || String.fromCharCodes(b.sublist(12, 16)) != 'IHDR') {
    return <int>[-1, -1];
  }
  final int w =
      (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
  final int h =
      (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
  return <int>[w, h];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    JustAudioPlatform.instance = _NoopPlatform();
  });

  setUp(() {
    AudioService.instance.resetForTest();
    const MethodChannel pathProvider =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory tmp = Directory.systemTemp.createTempSync('qa_ult_timing');
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

  // ══════════════════════════════════════════════════════════════════════
  // ① 行为层：逐帧回调能力 + 效果落地帧阈值（M-C 转红）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-T1 · FrameSequencePlayer 逐帧回调（fx 清怪时序的前置能力）', () {
    testWidgets('回调单调递增、同帧仅一次、末帧可达', (WidgetTester tester) async {
      // 🔴 阈值升到 0 基 13 后，8 帧样本最高只能报到 7（永假）⇒ 改用完整
      // 27 帧 / 4000ms 真实节奏，才有能力越过高阈值。
      final List<String> frames = fxFrameAssets(
        'assets/guard/ultimate_fx',
        27,
        ext: 'webp',
      );
      final List<int> reported = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: FrameSequencePlayer(
                frames: frames,
                durationMs: 4000,
                fadeOutMs: 0,
                onFrameReached: reported.add,
              ),
            ),
          ),
        ),
      );
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(reported, isNotEmpty, reason: '逐帧回调必须真的发生');
      expect(reported.first, 0, reason: '首帧从 0 开始');
      for (int i = 1; i < reported.length; i++) {
        expect(
          reported[i],
          greaterThan(reported[i - 1]),
          reason: '单调闸门：同一帧不得重复回调',
        );
      }
      expect(reported.toSet().length, reported.length, reason: '无重复帧号');
      expect(
        reported.last,
        greaterThanOrEqualTo(13),
        reason: '必须能越过 kUltimateFxKillTriggerFrame=13 这一帧',
      );
    });
  });

  group('QA-T2 · GuardUltimateFx 效果落地帧（M-C 阈值改永假必转红）', () {
    testWidgets('frame014（0 基 13）到达时 onEffectFrame 恰好触发一次',
        (WidgetTester tester) async {
      expect(
        kUltimateFxKillTriggerFrame,
        13,
        reason: '触发帧独立写死 = 13（frame014 新素材落地帧）',
      );
      int calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 220,
              child: GuardUltimateFx(
                anchor: const Offset(160, 110),
                uiScale: 1.0,
                onEffectFrame: () => calls++,
              ),
            ),
          ),
        ),
      );

      // 🔴 必须同时验「何时触发」：只数调用次数是假绿——把判定反转成
      // `index >= 13` 会在 frame001 就触发，次数照样是 1。
      // 13/27 × 4000ms ≈ 1926ms ⇒ 1900ms 时仍在 frame013 之前，必须 0 次。
      for (int i = 0; i < 19; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        calls,
        0,
        reason: '效果帧到达前怪不得消失（M-C 判定反转成 >= 时在首帧就触发 → 转红）',
      );

      // 再泵到 2100ms，确保越过 frame014（0 基 13，≈1926ms）。
      for (int i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        calls,
        1,
        reason: '效果帧到达 ⇒ onEffectFrame 触发一次（M-C 改成永假时恒 0 → 转红）',
      );

      // 继续播完整段：闸门必须保证只触发一次。
      for (int i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls, 1, reason: '_effectFired 闸门：整段只触发一次');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ② 源码结构守卫：私有状态机四链路（M-D / M-E 转红）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-T3 · 大招清怪延迟消费时序（源码守卫，防假绿）', () {
    final String field = _codeOnly(
      _src('lib/presentation/child/widgets/guard_battle_field.dart'),
    );

    test('① cast 当帧不进 _deaths：ultimateKill 只缓存到 _pendingUltimateKills', () {
      final String block = _between(
        field,
        'if (_pendingUltimate) {',
        '_collectMissFx(report);',
      );
      expect(block, isNotEmpty, reason: '必须定位到 cast 帧分支');
      expect(block, contains('_sim.castUltimate(ms, ultEvents)'));
      expect(block, contains('_pendingUltimateKills.add(e)'));
      // 🔴 C128：held 账本从 Set 扩为 Map<int,int>（index → 被清时刻），
      // 渲染层据此纯外推继续行走；此处仍钉「cast 当帧只记账、不进 _deaths」。
      expect(
        block,
        contains('_ultimateHeldMonsters[e.monsterIndex] = ms;'),
      );
      expect(
        block,
        isNot(contains('_deaths.putIfAbsent')),
        reason: 'M-D：cast 当帧若直接记 _deaths，怪会早 4s 消失',
      );
      expect(
        block,
        isNot(contains('_collectDeathFx(report)')),
        reason: 'M-D 变体：cast 当帧直接消费事件也必须转红',
      );
    });

    test('② 效果帧前 held 怪走行走分支（_monsterSlot 保留 ultHeld 条件）', () {
      final String slot = _between(
        field,
        'Widget _monsterSlot(',
        'final int deathAgeMs',
      );
      expect(slot, isNotEmpty, reason: '必须定位到 _monsterSlot 前段');
      // 🔴 C128：Set.contains → Map.containsKey（账本扩容），语义不变。
      expect(
        slot,
        contains('final bool ultHeld = _ultimateHeldMonsters.containsKey(m.index)'),
      );
      expect(
        slot,
        contains('if (!dead || deathT == null || ultHeld)'),
        reason: 'M-E：去掉 ultHeld 分支，怪在 cast 帧即被冻成尸体/逃跑',
      );
    });

    test('③ 效果落地帧才按「触发时 fxClockMs」记 deathT 并摘 held 标记', () {
      final String fn = _between(
        field,
        'void _onUltimateFxEffectFrame()',
        'void _onUltimateFxDone()',
      );
      expect(fn, isNotEmpty, reason: '必须定位到效果帧回调实现');
      expect(
        fn,
        contains('final int now = fxClockMs'),
        reason: 'deathT 必须取效果落地那一刻的渲染时钟，不是 4s 前的事件 tMs',
      );
      expect(fn, contains('_deaths.putIfAbsent(e.monsterIndex, () => now)'));
      expect(fn, contains('_ultimateHeldMonsters.remove(index)'));
      expect(
        field,
        contains('onEffectFrame: _onUltimateFxEffectFrame'),
        reason: 'fx 回调必须真的接到战斗层（接线存在）',
      );
    });

    test('④ 终局在大招激活时挂起，fx 收尾 + 死亡淡出完成后才交回', () {
      final String terminal = _between(
        field,
        'if (_sim.isOver && !_endHandled)',
        'kUltimateFxDurationMs * 2 - kUltimateFxCastLeadMs',
      );
      expect(terminal, isNotEmpty, reason: '必须定位到终局判定分支');
      expect(terminal, contains('if (_ultimateActive)'));
      expect(terminal, contains('_deferredFinish = _DeferredFinish('));
      expect(terminal, contains('_postEndHoldForUltimate = true'));

      final String finish = _between(
        field,
        'void _maybeFinishDeferred()',
        'int get fxClockMs',
      );
      expect(finish, isNotEmpty, reason: '必须定位到延迟交回实现');
      expect(finish, contains('if (d == null || _ultimateActive) return;'));
      expect(
        finish,
        contains('if (_deathFxRemainMs() > 0) return;'),
        reason: 'fx 播完但 800ms 死亡淡出未完，仍不得弹结算卡',
      );
      // 🔴 C128：参战判定扩为「开火或大招清怪」，交回第二参改名 didAttack
      // （sim 域 hasFired 一个字节不动；guard_battle_field 判定后透传）。
      expect(
        finish,
        contains('widget.onFinished?.call(d.stolenSun, d.didAttack)'),
      );
    });

    test('⑤ D-2：_collectDeathFx / _collectSunDropFx 只认 kill，不认 ultimateKill', () {
      final String deaths = _between(
        field,
        'void _collectDeathFx(',
        'void _collectSunDropFx(',
      );
      final String drops = _between(
        field,
        'void _collectSunDropFx(',
        'void _pruneSunDrops(',
      );
      expect(deaths, contains('GuardBattleEventType.kill'));
      expect(drops, contains('GuardBattleEventType.kill'));
      expect(
        deaths,
        isNot(contains('GuardBattleEventType.ultimateKill')),
        reason: '大招击杀不得进死亡账本当帧消费',
      );
      expect(
        drops,
        isNot(contains('GuardBattleEventType.ultimateKill')),
        reason: 'D-2：表现层阳光掉落只认 kill，大招零掉落',
      );
    });

    test('⑥ M-C 源码锚点：阈值判定与一次性闸门仍在 guard_ultimate_fx.dart', () {
      final String fx = _codeOnly(
        _src('lib/presentation/child/widgets/guard_ultimate_fx.dart'),
      );
      expect(fx, contains('const int kUltimateFxKillTriggerFrame = 13'));
      expect(fx, contains('index < kUltimateFxKillTriggerFrame'));
      expect(fx, contains('_effectFired = true'));
      expect(fx, contains('widget.onEffectFrame?.call()'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ②-b 真机反馈 4：8s → 6s（cast 第 2 秒提前挂 fx + 音轨不互掐）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-T5 · 6s 演出 / 2s 提前量 / fx 音轨叠加池（源码守卫）', () {
    test('提前量 2000ms、补时减 2000ms、fx 音轨不再走单播放器掐 cast', () {
      final String params = _codeOnly(_src('lib/core/constants/prd_params.dart'));
      final String card = _codeOnly(
        _src('lib/presentation/child/widgets/guard_scene_card.dart'),
      );
      final String field = _codeOnly(
        _src('lib/presentation/child/widgets/guard_battle_field.dart'),
      );
      final String fx = _codeOnly(
        _src('lib/presentation/child/widgets/guard_ultimate_fx.dart'),
      );
      final String audio = _codeOnly(_src('lib/platform/audio_service.dart'));

      // 总演出 4s + (4s − 2s) = 6s。
      expect(params, contains('const int kUltimateFxCastLeadMs = 2000'));
      expect(card, contains('const Duration(milliseconds: kUltimateFxCastLeadMs)'));
      expect(
        card,
        contains('const Duration(milliseconds: kUltimateFxDurationMs)'),
        reason: 'cast 音轨/帧仍须播满 4s',
      );
      expect(field, contains('kUltimateFxDurationMs * 2 - kUltimateFxCastLeadMs'));

      // 通知单点：timer 与 cast 收尾兜底都走同一个去重方法。
      expect(card, contains('void _onFxStartDue()'));
      expect(card, contains('if (_fxStageStarted || !mounted) return;'));
      expect(
        'X$card'.split('_battleHandle.notifyUltimateCastDone();').length - 1,
        1,
        reason: '全文件只允许一处 notify',
      );

      // fx 音轨走叠加池；cast 音轨仍走互斥单播放器（语义不变）。
      expect(
        fx,
        contains('AudioService.instance.playSfxPathsOverlap(kGuardUltimateFxSfx)'),
      );
      expect(fx, isNot(contains('playSfxPaths(<String>[kGuardUltimateFxSfx])')));
      expect(audio, contains('void playSfxPathsOverlap(String path'));
      expect(audio, contains('unawaited(_playSfxOverlap(path, volume: volume))'));
      expect(
        card,
        contains('AudioService.instance.playSfxPaths(<String>[castSfx])'),
        reason: 'cast 音轨不得改走 overlap，互斥语义保持',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // ③ 素材完整性 + B1/B3 几何守卫
  // ══════════════════════════════════════════════════════════════════════
  group('QA-T4 · 素材完整性与不裁切 / 放大几何（期望值独立写死）', () {
    test('cast 27 帧全部 720×720（C130 全画布不裁切）、frame001..027 连号无缺', () {
      const String dir = 'assets/guard/soldier_ultimate';
      for (int n = 1; n <= 27; n++) {
        final String name =
            'frame${n.toString().padLeft(3, '0')}.webp';
        expect(
          File('${_root()}/$dir/$name').existsSync(),
          isTrue,
          reason: 'cast 帧缺号：$name',
        );
        expect(_webpSize('$dir/$name'), <int>[720, 720],
            reason: '🔴 C130 玄参「你不要给我切割」：全画布导出，'
                '禁止回退到 C129 的 277×266 裁窗口径');
      }
      expect(
        Directory('${_root()}/$dir').listSync().whereType<File>().length,
        27,
        reason: 'cast 目录恰好 27 帧，不多不少',
      );
    });

    test('原图备份（统一帧源）27 帧 720×720 PNG（裁边可复现）', () {
      const String dir = 'assets/_originals/soldier_ultimate_unified';
      for (int n = 1; n <= 27; n++) {
        final String name =
            'frame${n.toString().padLeft(3, '0')}.png';
        expect(File('${_root()}/$dir/$name').existsSync(), isTrue);
        expect(_pngSize('$dir/$name'), <int>[720, 720]);
      }
    });

    test('fx 特效 27 帧全部 1470×630、连号无缺', () {
      const String dir = 'assets/guard/ultimate_fx';
      for (int n = 1; n <= 27; n++) {
        final String name =
            'frame${n.toString().padLeft(3, '0')}.webp';
        expect(File('${_root()}/$dir/$name').existsSync(), isTrue);
        expect(_webpSize('$dir/$name'), <int>[1470, 630]);
      }
    });

    test('pubspec 声明两个大招帧目录（C129：zh 帧目录已删，不再声明）', () {
      final String pubspec = _src('pubspec.yaml');
      expect(pubspec, contains('- assets/guard/soldier_ultimate/'));
      expect(pubspec, contains('- assets/guard/ultimate_fx/'));
      expect(pubspec.contains('- assets/guard/soldier_ultimate_zh/'), isFalse,
          reason: 'C129 统一帧后 zh 目录已删除，声明必须同步移除');
    });

    test('C130 素材不裁切：脚本零裁窗字面量、增益口径不变', () {
      final String script = _src('tools/convert_guard_ultimate_assets.py');
      expect(
        script.contains('CAST_CROP_BOX'),
        isFalse,
        reason: '🔴 C130 玄参「你不要给我切割」：裁边窗口必须废除，'
            '统一帧保留原始 720×720 全画布（C129 的 (203,209,480,475) 禁止回归）',
      );
      expect(
        script,
        contains('CAST_BRIGHTNESS_GAIN = 1.0586'),
        reason: '亮度归一口径不变（战士实体帧子集校准，luma 对齐待机 156.77；'
            '2026-11-22 新「大招动作优化」素材原 luma 149.39，'
            '旧统一帧 144.49 对应 1.1027，沿用会偏亮）',
      );
    });

    test('B3 特效绘制盒高 = 卡高×uiScale，宽 = 高×1470/630', () {
      final String fx = _codeOnly(
        _src('lib/presentation/child/widgets/guard_ultimate_fx.dart'),
      );
      expect(fx, contains('const double kUltimateFxAspectRatio = 1470 / 630;'));
      expect(
        fx,
        contains('final double h = kGuardSceneCardHeight * widget.uiScale;'),
        reason: '视觉高须逐位等于守卫卡高，不是旧的 103pt',
      );
      expect(fx, contains('final double w = h * kUltimateFxAspectRatio;'));
      expect(fx, contains('fit: BoxFit.contain'));
    });
  });
}
