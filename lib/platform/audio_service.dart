/// M2 音频模块：单例音频服务（§1.1）。
///
/// 持有一个 BGM 播放器与一个 SFX 播放器，供专注页 / 结算页跨页面复用，避免重复
/// new 播放器。所有加载与播放均在 try/catch 内静默降级——当前工程**无任何音频素材**，
/// 资源缺失时静默跳过，不抛异常、不刷日志。
library audio_service;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 音效提示（SFX）枚举。每个 cue 映射到 `assets/audio/sfx/<name>.wav`。
enum AudioCue {
  /// 光回罐 / 结算奖励（settle 页 net > 0）。
  taskReward,

  /// 二档送光粒子 / 气泡（专注进度）。
  progress,

  /// 三档「欢迎回来」。
  welcomeBack,

  /// 四档唤醒。
  wake,
}

/// [AudioCue] 到 assets 音频文件路径的映射（相对工程根）。
extension AudioCueX on AudioCue {
  /// 资源路径（pubspec 已注册 `assets/audio/sfx/` 目录）。
  String get assetPath {
    switch (this) {
      case AudioCue.taskReward:
        return 'assets/audio/sfx/task_reward.wav';
      case AudioCue.progress:
        return 'assets/audio/sfx/progress.wav';
      case AudioCue.welcomeBack:
        return 'assets/audio/sfx/welcome_back.wav';
      case AudioCue.wake:
        return 'assets/audio/sfx/wake.wav';
    }
  }
}

/// 单例音频服务（M2 音频模块）。
///
/// 设计要点（回归红线）：
/// - **单例**：全局唯一，BGM/SFX 各一个播放器，跨 focus↔settle 不重复初始化；
/// - **非阻塞**：SFX 调用 fire-and-forget，绝不 await；专注引擎 tick 内禁止触碰音频；
/// - **静默降级**：任何加载/播放失败均被 try/catch 吞掉，缺素材不崩、不刷日志；
/// - dispose 由专注页在 [dispose] 时调用，释放播放器，下次使用懒加载重建。
class AudioService {
  /// 播放器工厂（可注入用于测试）。默认使用 just_audio 的 [AudioPlayer]。
  ///
  /// headless 测试环境无音频后端，无法构造真实 [AudioPlayer]（just_audio 的静态方法通道缺
  /// 实现会抛未捕获异常）；测试可注入返回 null 的工厂，验证 [AudioService] 在「无可用播放器」
  /// 时静默降级。生产使用 [instance]（默认工厂）。
  AudioService({AudioPlayer? Function()? playerFactory})
      : _playerFactory = playerFactory ?? _defaultPlayerFactory;

  static final AudioService _instance = AudioService();

  /// 全局单例（生产使用默认工厂，构造真实 [AudioPlayer]）。
  static AudioService get instance => _instance;

  static final AudioPlayer? Function() _defaultPlayerFactory = () => AudioPlayer();

  final AudioPlayer? Function() _playerFactory;

  AudioPlayer? _sfxPlayer;
  AudioPlayer? _bgmPlayer;
  bool _soundOn = true;
  bool _bgmOn = false;
  bool _bgmPlaying = false;

  /// 应用设置：决定 SFX / BGM 是否生效。
  ///
  /// 若关闭 BGM 且正在播放，则立即停止；开启由调用方在 [startBgm] 触发。
  void applySettings({required bool soundOn, required bool bgmOn}) {
    _soundOn = soundOn;
    _bgmOn = bgmOn;
    if (!_bgmOn && _bgmPlaying) {
      unawaited(stopBgm());
    }
  }

  /// 安全构造播放器：构造失败（如无音频后端 / 绑定未初始化）返回 null，由调用方静默降级。
  AudioPlayer? _safeCreate() {
    try {
      return _playerFactory();
    } catch (_) {
      return null; // 构造失败：静默降级，不崩、不刷日志
    }
  }

  Future<AudioPlayer?> get _sfx async {
    _sfxPlayer ??= _safeCreate();
    return _sfxPlayer;
  }

  Future<AudioPlayer?> get _bgm async {
    _bgmPlayer ??= _safeCreate();
    return _bgmPlayer;
  }

  /// 播放一次性音效（fire-and-forget，非阻塞）。
  ///
  /// 受 [_soundOn] 保护；内部异步加载与播放，任何失败均静默忽略。
  void playSfx(AudioCue cue) {
    if (!_soundOn) return;
    unawaited(_playSfx(cue));
  }

  Future<void> _playSfx(AudioCue cue) async {
    final AudioPlayer? player = await _sfx;
    if (player == null) return; // 播放器构造失败：静默降级
    try {
      await player.stop();
      await player.setAsset(cue.assetPath);
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {
      // 资源缺失或解码失败：静默降级。
    }
  }

  /// 循环播放背景音乐（focus_loop.wav）。资源缺失静默跳过。
  Future<void> startBgm() async {
    if (!_bgmOn || _bgmPlaying) return;
    final AudioPlayer? player = await _bgm;
    if (player == null) return; // 播放器构造失败：静默降级
    try {
      await player.setAsset('assets/audio/bgm/focus_loop.wav');
      await player.setLoopMode(LoopMode.one);
      await player.seek(Duration.zero);
      await player.play();
      _bgmPlaying = true;
    } catch (_) {
      // 资源缺失：静默降级。
    }
  }

  /// 停止背景音乐（保留播放器，便于下次 [startBgm] 复用）。
  Future<void> stopBgm() async {
    _bgmPlaying = false;
    if (_bgmPlayer == null) return;
    try {
      await _bgmPlayer!.stop();
      await _bgmPlayer!.seek(Duration.zero);
    } catch (_) {
      // 静默降级。
    }
  }

  /// 释放所有播放器（专注页 [dispose] 时调用；下次使用懒加载重建）。
  Future<void> dispose() async {
    try {
      await _sfxPlayer?.dispose();
      await _bgmPlayer?.dispose();
    } catch (_) {
      // 静默降级。
    }
    _sfxPlayer = null;
    _bgmPlayer = null;
    _bgmPlaying = false;
  }
}
