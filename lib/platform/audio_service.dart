/// M2 音频模块：单例音频服务（§1.1）。
///
/// 持有一个 BGM 播放器与一个 SFX 播放器，供专注页 / 结算页跨页面复用，避免重复
/// new 播放器。所有加载与播放均在 try/catch 内静默降级——当前工程**无任何音频素材**，
/// 资源缺失时静默跳过，不抛异常、不刷日志。
library audio_service;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// 收集奖励（点头顶阳光 / 碎片 / 种子图标收集时**统一播放**；素材待玄参交付，
  /// `collect_reward.mp3`，2026-10-06 预留——缺失静默跳过）。
  collectReward,

  /// 专注页 · 1/3 进度收集阳光（配 collect 序列帧）。
  focusCollect,

  /// 结算页 · 向日葵庆祝（配 settle 序列帧）。
  focusSettle,

  /// 护眼卡 · 段① 闭眼转眼球提示（配 `assets/fx/eyecare/close/`，2026-10-05 交付）。
  eyeCareClose,

  /// 护眼卡 · 段② 再来一次转眼球（配 `assets/fx/eyecare/doitagain/`）。
  eyeCareAgain,

  /// 护眼卡 · 段③ 远眺提示（配 `assets/fx/eyecare/lookTip/`）。
  eyeCareLookTip,

  /// 护眼卡 · 段④ 远眺（配 `assets/fx/eyecare/look/`，播放列表中复用 3 次）。
  eyeCareLook,

  /// 护眼卡 · 段⑤ 结束提示（配 `assets/fx/eyecare/done/`）。
  eyeCareDone,
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
      case AudioCue.collectReward:
        return 'assets/audio/sfx/collect_reward.mp3';
      case AudioCue.focusCollect:
        return 'assets/audio/sfx/focus_collect.mp3';
      case AudioCue.focusSettle:
        return 'assets/audio/sfx/focus_settle.mp3';
      case AudioCue.eyeCareClose:
        return 'assets/audio/sfx/eyecare_close.mp3';
      case AudioCue.eyeCareAgain:
        return 'assets/audio/sfx/eyecare_doitagain.mp3';
      case AudioCue.eyeCareLookTip:
        return 'assets/audio/sfx/eyecare_lookTip.mp3';
      case AudioCue.eyeCareLook:
        return 'assets/audio/sfx/eyecare_look.mp3';
      case AudioCue.eyeCareDone:
        return 'assets/audio/sfx/eyecare_done.mp3';
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

  // ── 后台/锁屏暂停（F70，玄参 2026-10-05 反馈「花园页锁屏/退后台背景音乐还在响」）──

  /// 是否处于「后台挂起」状态（退后台/锁屏后为 true；此时一切新的播放请求被闸门拦下）。
  ///
  /// 为什么要闸门：花园页的 30s 氛围音定时器在后台仍会触发（Timer 不因退后台停止），
  /// 若只 stop 不拦新请求，背景音乐会在后台被定时器重新拉起（玄参实测的 bug 本体）。
  bool _suspendedForBackground = false;

  /// 暂停前 BGM 是否在播（回前台据此恢复）。
  bool _bgmWasPlayingBeforeBackground = false;

  /// 暂停前氛围音是否应播（回前台据此恢复；花园 tab 可见时才为 true）。
  bool _ambientShouldPlayBeforeBackground = false;

  /// [isSuspendedForBackground]（测试可见性）。
  @visibleForTesting
  bool get isSuspendedForBackground => _suspendedForBackground;

  /// [_bgmPlaying]（测试可见性）。
  @visibleForTesting
  bool get bgmPlaying => _bgmPlaying;

  /// [_ambientShouldPlay]（测试可见性）。
  @visibleForTesting
  bool get ambientShouldPlay => _ambientShouldPlay;

  /// 氛围音「应然」状态（F67）：花园 tab 可见且设置开启 → true。
  ///
  /// 背景（玄参 2026-10-04 真机反馈）：养护音效在共享 iOS 音频会话上启动时，
  /// ambient 播放器被 just_audio 打断处理暂停，原逻辑**无人续播**——最长静默到
  /// 下一个 30s 定时点、会话激活混乱时甚至一直静默。自愈监听（[_attachAmbientHeal]）
  /// 依本标记判定「应播而未播」即续播。
  bool _ambientShouldPlay = false;

  /// 主动重载窗口守卫：[_playGardenAmbient] 内部的 stop/setAsset/seek 本身会触发
  /// 播放器状态流事件，此窗口内一律忽略（否则自愈会把自己的主动 stop 误判为「被打断」）。
  bool _ambientReloading = false;

  /// 自愈节流：防止「续播后又被同一段音效打断」时高频反复重启。
  DateTime _lastAmbientHealAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 氛围音播放器状态订阅（自愈监听），[dispose] 时取消。
  StreamSubscription<PlayerState>? _ambientStateSub;

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
    await _clearStaleAssetCacheOnce();
    return _sfxPlayer;
  }

  Future<AudioPlayer?> get _bgm async {
    _bgmPlayer ??= _safeCreate();
    await _clearStaleAssetCacheOnce();
    return _bgmPlayer;
  }

  Future<AudioPlayer?> get _ambient async {
    _ambientPlayer ??= _safeCreate();
    await _clearStaleAssetCacheOnce();
    return _ambientPlayer;
  }

  /// 是否已在本次启动内清理过 just_audio 资产拷贝缓存。
  static bool _assetCacheCleared = false;

  /// 每次冷启动清理一次 just_audio 的资产拷贝缓存（tmp/just_audio_cache）。
  ///
  /// ⚠️ F77 二层根因（just_audio 0.9.46 实证）：`setAsset` 会把 bundle 资产**拷贝**
  /// 到 tmp 缓存并**只按路径判缓存、不校验内容**——App 更新后同名素材换了内容，
  /// 仍会命中陈旧拷贝永不生效（初版 1.04s 的 collect_reward.mp3 命中缓存 → iOS
  /// AudioFileStream 报 -11849 → 被静默 catch 吞 → 无声无日志）。iOS/Android 的
  /// tmp 在 App 更新后不保证清空 → 冷启动清一次，保证素材永远取自当前包；
  /// 缓存拷贝是懒加载按需进行，开销可忽略。
  Future<void> _clearStaleAssetCacheOnce() async {
    if (_assetCacheCleared) return;
    _assetCacheCleared = true;
    try {
      await AudioPlayer.clearAssetCache();
    } catch (_) {
      // headless 测试环境无 path_provider 插件：静默降级。
    }
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
  ///
  /// 后台挂起（[_suspendedForBackground]）期间一律跳过（F70 闸门）；**play() 前
  /// 二次复查**（F70 v2，玄参 2026-10-05 复测「锁屏/退后台仍会响」）：setAsset/seek
  /// 是几百 ms 的异步间隙，期间可能刚好退后台——若只查入口一次，在途加载会在
  /// 后台把音乐拉起。
  Future<void> startBgm() async {
    if (!_bgmOn || _bgmPlaying || _suspendedForBackground) return;
    final AudioPlayer? player = await _bgm;
    if (player == null) return; // 播放器构造失败：静默降级
    try {
      await player.setAsset('assets/audio/bgm/focus_loop.mp3');
      await player.setLoopMode(LoopMode.one);
      await player.seek(Duration.zero);
      if (_suspendedForBackground) {
        await player.stop(); // 加载间隙已退后台：绝不发声
        return;
      }
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

  /// 纯函数：氛围音是否需要自愈续播（可单测，headless 测试无音频后端无法造真播放器）。
  ///
  /// 被打断（paused / idle，未播完）→ 需要续播；自然播完（completed）→ 不自愈，
  /// 交给花园页 30s 定时器重播。
  static bool ambientNeedsHeal({
    required bool isPlaying,
    required bool completed,
  }) =>
      !isPlaying && !completed;

  /// 给氛围音播放器挂「自愈监听」（幂等：只在首次拿到播放器时挂一次）。
  ///
  /// 花园 tab 可见（[_ambientShouldPlay]）期间，播放器出现「应播而未播」的非自然
  /// 暂停（＝被 SFX 在共享音频会话上打断）→ 节流后从头续播，实现「音效与背景音
  /// 同响、互不打断」的用户口径（F67）。
  void _attachAmbientHeal(AudioPlayer player) {
    _ambientStateSub ??= player.playerStateStream.listen((PlayerState st) {
      if (_ambientReloading || !_ambientShouldPlay || !_bgmOn) return;
      if (!ambientNeedsHeal(
        isPlaying: st.playing,
        completed: st.processingState == ProcessingState.completed,
      )) {
        return; // 正常播放中 / 自然播完：不需要自愈
      }
      final DateTime now = DateTime.now();
      if (now.difference(_lastAmbientHealAt) < const Duration(seconds: 1)) {
        return; // 节流：1s 内不重复重启
      }
      _lastAmbientHealAt = now;
      unawaited(_playGardenAmbient()); // 从头续播
    });
  }

  /// 播放一次花园氛围音（`assets/audio/bgm/background.mp3`，约 10s，不循环）。
  ///
  /// 玄参 2026-09-28 拍板口径：**花园 tab 内每 30s 播一次**（进入立即播一次），
  /// 离开花园 tab 由花园页调 [stopGardenAmbient] 停止；受 [_bgmOn]（设置「背景音乐」）
  /// 控制，关闭时静默跳过。与专注页 BGM（[startBgm]，循环）**独立播放器**，互不打断。
  /// 资源缺失静默跳过（fire-and-forget，不阻塞 UI）。
  ///
  /// 后台挂起（[_suspendedForBackground]）期间一律跳过（F70 闸门）：否则花园页 30s
  /// 定时器会在退后台/锁屏后把氛围音重新拉起（玄参 2026-10-05 实测 bug）。
  void playGardenAmbient() {
    if (!_bgmOn || _ambientPlaying || _suspendedForBackground) return;
    unawaited(_playGardenAmbient());
  }

  Future<void> _playGardenAmbient() async {
    // F70 v2：直呼路径（自愈监听）兜底闸门——挂起态一律不进入加载流程。
    if (_suspendedForBackground) return;
    final AudioPlayer? player = await _ambient;
    if (player == null || !_bgmOn) return; // 播放器构造失败 / 设置已关：静默降级
    _attachAmbientHeal(player); // 首次拿到播放器时挂自愈监听（幂等）
    try {
      _ambientPlaying = true;
      _ambientReloading = true; // 主动重载窗口：自愈监听忽略期间的暂停事件
      await player.stop();
      await player.setAsset(kGardenAmbientAsset);
      await player.seek(Duration.zero);
      // F70 v2：setAsset 是几百 ms 的异步间隙，期间可能刚好锁屏/退后台——
      // 若只查入口一次，在途加载会在后台把氛围音拉起（玄参 2026-10-05 复测）。
      if (_suspendedForBackground) {
        await player.stop(); // 加载间隙已退后台：绝不发声、不置「应播」标记
        return;
      }
      await player.play();
      _ambientShouldPlay = true;
      // play() 返回即认为本次氛围音已启动；播完自然结束（不循环）。
    } catch (_) {
      // 资源缺失或解码失败：静默降级。
    } finally {
      _ambientReloading = false;
      _ambientPlaying = false;
    }
  }

  /// 停止花园氛围音（离开花园 tab 时由花园页调用；保留播放器便于复用）。
  ///
  /// ⚠️ 必须**先**把 [_ambientShouldPlay] 翻 false 再 stop——否则主动 stop 触发的
  /// 状态事件会被自愈监听误判为「被打断」而立刻续播（离开花园后音乐阴魂不散）。
  Future<void> stopGardenAmbient() async {
    _ambientShouldPlay = false;
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
    await _ambientStateSub?.cancel();
    _ambientStateSub = null;
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
    _ambientShouldPlay = false;
    _ambientReloading = false;
    _suspendedForBackground = false;
    _bgmWasPlayingBeforeBackground = false;
    _ambientShouldPlayBeforeBackground = false;
  }

  // ── 后台/锁屏暂停与恢复（F70，玄参 2026-10-05 反馈）─────────────────────

  /// **退后台 / 锁屏**：暂停一切音频（幂等）。
  ///
  /// 由外壳页生命周期监听（`child_shell_page.didChangeAppLifecycleState`）在
  /// `hidden` / `paused` 时调用。记录暂停前各通道的「应然」状态，回前台由
  /// [resumeFromBackground] 恢复。幂等：重复调用只生效第一次（hidden → paused
  /// 会连发两次）。
  Future<void> pauseAllForBackground() async {
    if (_suspendedForBackground) return;
    _suspendedForBackground = true;
    _bgmWasPlayingBeforeBackground = _bgmPlaying;
    _ambientShouldPlayBeforeBackground = _ambientShouldPlay;
    await stopBgm();
    await stopGardenAmbient();
  }

  /// **回前台**：恢复暂停前在播的通道（幂等；无在播通道则什么都不做）。
  ///
  /// 恢复即「从头播」：BGM 循环曲与氛围音都是短曲（10s 级），从头播无感知差异。
  Future<void> resumeFromBackground() async {
    if (!_suspendedForBackground) return;
    _suspendedForBackground = false;
    if (_bgmWasPlayingBeforeBackground) {
      _bgmWasPlayingBeforeBackground = false;
      unawaited(startBgm());
    }
    if (_ambientShouldPlayBeforeBackground) {
      _ambientShouldPlayBeforeBackground = false;
      unawaited(_playGardenAmbient());
    }
  }
}
