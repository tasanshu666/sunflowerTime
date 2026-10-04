/// AudioService 单元测试（M2 音频模块）。
///
/// 核心契约：**资源缺失 / 无可用播放器时静默降级**——构造后直接调用
/// [AudioService.playSfx] / [AudioService.startBgm] 等不得抛异常、不得令测试失败。
///
/// 注：headless 测试环境（无 macos/linux 原生壳）无音频后端，just_audio 的静态方法通道
/// 缺实现会抛未捕获的 MissingPluginException，无法在此环境构造真实 [AudioPlayer]。因此测试
/// 注入「返回 null」的播放器工厂，验证 [AudioService] 在「无可用播放器」时静默降级（与
/// 「资源缺失」同级：不抛异常、不刷日志）。真实设备用 [AudioService.instance]（默认工厂）
/// 正常播放，缺失素材由内部 try/catch 吞掉。
library audio_service_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/platform/audio_service.dart';

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

    test('soundOn=false 时 playSfx 直接跳过且不触碰播放器', () {
      audio.applySettings(soundOn: false, bgmOn: false);
      expect(() => audio.playSfx(AudioCue.progress), returnsNormally);
      expect(() => audio.playSfx(AudioCue.wake), returnsNormally);
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

  // 释放（无可用播放器时为空操作），便于进程干净退出。
  tearDownAll(() => unawaited(audio.dispose()));
}
