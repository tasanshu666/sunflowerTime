/// M2 音频模块：单例音频服务（§1.1）。
///
/// 持有一个 BGM 播放器与一个 SFX 播放器，供专注页 / 结算页跨页面复用，避免重复
/// new 播放器。所有加载与播放均在 try/catch 内静默降级——当前工程**无任何音频素材**，
/// 资源缺失时静默跳过，不抛异常、不刷日志。
library audio_service;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 音效提示（SFX）枚举。每个 cue 映射到 `assets/audio/sfx/<name>`。
///
/// 2026-09-28 新增 5 个 mp3 cue（成长过渡 3 段 + 养护 2 段）；2026-09-29 新增专注页
/// 2 个 mp3 cue（收集 / 结算），并把 `welcomeBack` 由 `.wav` 改为交付实况 `.mp3`。
/// 新 cue 一律 mp3；`wake` / `taskReward` 等尚未交付的既有 wav 保持不动。
enum AudioCue {
  /// 光回罐 / 结算奖励（settle 页 net > 0）。
  taskReward,

  /// 二档送光粒子 / 气泡（专注进度）。
  progress,

  /// 三档「欢迎回来」（= `welcome_back.mp3`）。
  welcomeBack,

  /// 四档唤醒。
  wake,

  /// 成长过渡 · 种子破土成幼苗（花园升级动画配乐）。
  growthSeedToSprout,

  /// 成长过渡 · 幼苗长成成株。
  growthSproutToAdult,

  /// 成长过渡 · 成株绽放盛开。
  growthAdultToBloomed,

  /// 养护 · 浇水（花盆上叠加浇水效果帧时播放）。
  careWater,

  /// 养护 · 施肥。
  careFertilize,

  /// 养护 · 除草（点杂草 → 播除草效果帧 + 音效，2026-10-03 玄参交付）。
  careWeed,

  /// 养护 · 除虫（点害虫 → 播除虫效果帧 + 音效）。
  carePest,

  /// 专注页 · 1/3 进度收集阳光（配 collect 序列帧）。
  focusCollect,

  /// 结算页 · 向日葵庆祝（配 settle 序列帧）。
  focusSettle,
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
        return 'assets/audio/sfx/welcome_back.mp3';
      case AudioCue.wake:
        return 'assets/audio/sfx/wake.wav';
      case AudioCue.growthSeedToSprout:
        return 'assets/audio/sfx/grow_seed_to_sprout.mp3';
      case AudioCue.growthSproutToAdult:
        return 'assets/audio/sfx/grow_sprout_to_adult.mp3';
      case AudioCue.growthAdultToBloomed:
        return 'assets/audio/sfx/grow_adult_to_bloomed.mp3';
      case AudioCue.careWater:
        return 'assets/audio/sfx/care_water.mp3';
      case AudioCue.careFertilize:
        return 'assets/audio/sfx/care_fertilize.mp3';
      case AudioCue.careWeed:
        return 'assets/audio/sfx/care_weed.mp3';
      case AudioCue.carePest:
        return 'assets/audio/sfx/care_pest.mp3';
      case AudioCue.focusCollect:
        return 'assets/audio/sfx/focus_collect.mp3';
      case AudioCue.focusSettle:
        return 'assets/audio/sfx/focus_settle.mp3';
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
  AudioPlayer? _ambientPlayer;
  bool _soundOn = true;
  bool _bgmOn = false;
  bool _bgmPlaying = false;
  bool _ambientPlaying = false;

  /// 应用设置：决定 SFX / BGM 是否生效。
  ///
  /// 若关闭 BGM 且正在播放，则立即停止；开启由调用方在 [startBgm] 触发。
  /// 花园氛围音（[_ambientPlayer]）同样受 [_bgmOn] 控制：关闭时立即停止。
  void applySettings({required bool soundOn, required bool bgmOn}) {
    _soundOn = soundOn;
    _bgmOn = bgmOn;
    if (!_bgmOn && _bgmPlaying) {
      unawaited(stopBgm());
    }
    if (!_bgmOn && _ambientPlaying) {
      unawaited(stopGardenAmbient());
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

  Future<AudioPlayer?> get _ambient async {
    _ambientPlayer ??= _safeCreate();
    return _ambientPlayer;
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
    // 真机修复（玄参 2026-09-30 反馈「离席回来欢迎音无声」）：app 刚从后台恢复时
    // 音频会话可能尚未就绪，首次播放被系统静默吞掉 → 首败后延迟 600ms 重试一次。
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        await player.stop();
        await player.setAsset(cue.assetPath);
        await player.seek(Duration.zero);
        await player.play();
        return; // 启动成功即返回（播放中失败不在本层感知）
      } catch (_) {
        // 资源缺失或播放启动失败：重试一次后静默降级。
      }
    }
  }

  /// 循环播放背景音乐（focus_loop.mp3）。资源缺失静默跳过。
  Future<void> startBgm() async {
    if (!_bgmOn || _bgmPlaying) return;
    final AudioPlayer? player = await _bgm;
    if (player == null) return; // 播放器构造失败：静默降级
    try {
      await player.setAsset('assets/audio/bgm/focus_loop.mp3');
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

  /// 播放一次花园氛围音（`assets/audio/bgm/background.mp3`，约 10s，不循环）。
  ///
  /// 玄参 2026-09-28 拍板口径：**花园 tab 内每 30s 播一次**（进入立即播一次），
  /// 离开花园 tab 由花园页调 [stopGardenAmbient] 停止；受 [_bgmOn]（设置「背景音乐」）
  /// 控制，关闭时静默跳过。与专注页 BGM（[startBgm]，循环）**独立播放器**，互不打断。
  /// 资源缺失静默跳过（fire-and-forget，不阻塞 UI）。
  void playGardenAmbient() {
    if (!_bgmOn || _ambientPlaying) return;
    unawaited(_playGardenAmbient());
  }

  Future<void> _playGardenAmbient() async {
    final AudioPlayer? player = await _ambient;
    if (player == null || !_bgmOn) return; // 播放器构造失败 / 设置已关：静默降级
    try {
      _ambientPlaying = true;
      await player.stop();
      await player.setAsset(kGardenAmbientAsset);
      await player.seek(Duration.zero);
      await player.play();
      // play() 返回即认为本次氛围音已启动；播完自然结束（不循环）。
    } catch (_) {
      // 资源缺失或解码失败：静默降级。
    } finally {
      _ambientPlaying = false;
    }
  }

  /// 停止花园氛围音（离开花园 tab 时由花园页调用；保留播放器便于复用）。
  Future<void> stopGardenAmbient() async {
    _ambientPlaying = false;
    if (_ambientPlayer == null) return;
    try {
      await _ambientPlayer!.stop();
      await _ambientPlayer!.seek(Duration.zero);
    } catch (_) {
      // 静默降级。
    }
  }

  /// 释放所有播放器（专注页 [dispose] 时调用；下次使用懒加载重建）。
  Future<void> dispose() async {
    try {
      await _sfxPlayer?.dispose();
      await _bgmPlayer?.dispose();
      await _ambientPlayer?.dispose();
    } catch (_) {
      // 静默降级。
    }
    _sfxPlayer = null;
    _bgmPlayer = null;
    _ambientPlayer = null;
    _bgmPlaying = false;
    _ambientPlaying = false;
  }
}
