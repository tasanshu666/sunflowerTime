/// M2 音频模块：单例音频服务（§1.1）。
///
/// 持有一个 BGM 播放器与一个 SFX 播放器，供专注页 / 结算页跨页面复用，避免重复
/// new 播放器。所有加载与播放均在 try/catch 内静默降级——当前工程**无任何音频素材**，
/// 资源缺失时静默跳过，不抛异常、不刷日志。
library audio_service;

import 'dart:async';

// audio_session 是 just_audio 的传递依赖（本工程 pubspec 未直接声明）。本轮改动范围
// 不含 pubspec.yaml，故就地忽略「引用了未声明依赖」这条 info 级 lint，不新增依赖声明。
// ⚠️ `AudioSessionConfiguration` 于 D1-v2（冷启动首次 play() 卡 ready 的根因修复）加入：
// 必须声明 Android/iOS 音频会话，否则首次 `play()` 渲染管道不启动（真机日志实锤）。
import 'package:audio_session/audio_session.dart' // ignore: depend_on_referenced_packages
    show
        AudioInterruptionEvent,
        AudioSession,
        AudioSessionConfiguration;
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import 'package:just_audio/just_audio.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 真机音频诊断日志统一 tag（`[AMBDIAG][毫秒时间戳][位置] 内容`）。
const String _kAmbientDiagTag = 'AMBDIAG';

/// 打印一行真机音频诊断日志（**仅 `kDebugMode`**，release 包零噪声）。
///
/// 背景（玄参 2026-10-07 真机复测）：headless 测试覆盖不到**真机音频管线**——
/// 「首进花园 BGM 不响」「种植音效打断背景音」在 872 全绿下真机仍红。故埋点取证：
/// 每次音频决策都能回答「为什么没播 / 为什么停了」。
///
/// ⚠️ 用 [debugPrint]：`flutter test` 会把全局 `debugPrint` 指向
/// `debugPrintSynchronously`（`flutter_test/binding.dart`），**不挂节流 Timer**，
/// 故在 FakeAsync widget 测试里也不会留下 pending timer。
void _adbg(String where, String msg) {
  if (!kDebugMode) return;
  debugPrint(
      '[$_kAmbientDiagTag][${DateTime.now().millisecondsSinceEpoch}][$where] $msg');
}

/// 氛围音「有限次尝试全部失败」后的**有界重试**间隔（毫秒）。
///
/// ⚠️ 本轮改动文件范围不含 `prd_params.dart`，故就近定义于本文件（后续如需可上收单点）。
const int _kAmbientFailureRetryDelayMs = 1500;

/// 氛围音失败后**额外**重试次数上限（避免首进失败后一直干等 30s 定时器 / 切 tab）。
const int _kAmbientFailureRetryAttempts = 3;

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

  /// 铲除植物（C29 二次确认后执行铲除时播放；`shovel.mp3`，
  /// 2026-10-07 玄参交付——原始 0.52s 已 apad 填静音至 3.16s 过 ≥3s 红线）。
  shovel,

  /// 种植新植物（种植成功时播放；`cultivate.mp3`，
  /// 2026-10-07 玄参交付——原始 2.95s 已 apad 填静音至 ≥3s（3.25s）过红线）。
  cultivate,

  /// 专注页 · 1/3 进度收集阳光（配 collect 序列帧）。
  focusCollect,

  /// 结算页 · 向日葵庆祝（配 settle 序列帧）。
  focusSettle,

  /// 专注到时 · 结束过渡 5 秒倒计时配音（`5s_countdown.mp3`，2026-10-08 玄参交付，
  /// 实测 4.99s；替代此前的系统「叮」，倒计时缓冲由 3s 改 5s 同日拍板）。
  focusEndCountdown,

  /// 护眼卡 · 全程单配音（`eyecare.mp3` 63.974s，2026-10-09 C43 玄参交付：
  /// 5 段配音已剪辑拼为 1 段，与 640 帧动画同时长播放；旧 5 个 cue 弃用删除）。
  eyeCare,
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
      case AudioCue.shovel:
        return 'assets/audio/sfx/shovel.mp3';
      case AudioCue.cultivate:
        return 'assets/audio/sfx/cultivate.mp3';
      case AudioCue.focusCollect:
        return 'assets/audio/sfx/focus_collect.mp3';
      case AudioCue.focusSettle:
        return 'assets/audio/sfx/focus_settle.mp3';
      case AudioCue.focusEndCountdown:
        return 'assets/audio/sfx/5s_countdown.mp3';
      case AudioCue.eyeCare:
        return 'assets/audio/sfx/eyecare.mp3';
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
      : _playerFactoryOverride = playerFactory;

  static final AudioService _instance = AudioService();

  /// 全局单例（生产使用默认工厂，构造真实 [AudioPlayer]）。
  static AudioService get instance => _instance;

  /// SFX 播放器默认工厂（一次性短音，保留 just_audio 默认的打断处理）。
  static final AudioPlayer? Function() _defaultPlayerFactory = () => AudioPlayer();

  /// 背景类播放器默认工厂（BGM / 花园氛围音，长驻）。
  ///
  /// `handleInterruptions: false`（A 项，玄参 2026-10-07「音效会打断花园背景音」）：just_audio
  /// 0.9.46 的 [AudioPlayer] 默认会监听音频会话打断事件（来电 / 耳机拔出 / 同会话其它播放器
  /// 激活），命中即 `pause()` 本播放器；花园氛围音被**同 App 内的 SFX 启动**打断正是真机
  /// 「背景音断掉、然后重头开始」的源头。关掉打断处理 → 背景音与 SFX 各播各的、不再互停。
  /// 仅背景类播放器如此；SFX 保留默认（尊重真实系统打断）。
  static final AudioPlayer? Function() _defaultBackgroundPlayerFactory =
      () => AudioPlayer(handleInterruptions: false);

  /// 测试注入的播放器工厂（可选）：给定时**统一**用于 SFX 与背景类播放器
  /// （headless 测试注入 `() => null` 验证「无可用播放器」时静默降级）。
  final AudioPlayer? Function()? _playerFactoryOverride;

  AudioPlayer? _sfxPlayer;
  AudioPlayer? _bgmPlayer;
  AudioPlayer? _ambientPlayer;
  bool _soundOn = true;
  bool _bgmOn = false;
  bool _bgmPlaying = false;
  /// ⚠️ 语义 = 氛围音**正在加载 / 起播**的窗口标记（[_playGardenAmbient] 起播前置 true、
  /// `finally` 置 false），**非**「稳态在播」。判「是否在播」请用 [_ambientAudible]。
  bool _ambientPlaying = false;

  /// 是否处于「SFX ducking」压低态（氛围音被压到 [kSfxDuckAmbientVolume] 且尚未恢复）。
  /// 连续多次 SFX 只压低一次（不堆叠 setVolume），故需此态位；起播 / stop / dispose 复位。
  bool _ambientDucked = false;

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

  /// [_ambientPlaying]（测试可见性）：氛围音**加载/起播窗口**标记（**非**稳态在播）。
  ///
  /// D1 回归护栏据此断言：起播流程返回后本标记必须已复位为 false（否则再次起播会被
  /// `skip: _ambientPlaying` 静默吞掉，正是「首进花园不响」的机制）。
  @visibleForTesting
  bool get ambientPlaying => _ambientPlaying;

  /// 氛围音代际计数（F71 v3，测试可见性）：每次 [stopGardenAmbient] 递增。
  int get ambientGeneration => _ambientGeneration;

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

  /// **重入闸门**（D1-v3，玄参 2026-10-07 真机/护栏双证）：[_playGardenAmbient] 是否
  /// 正在跑。⚠️ 必须**在函数入口同步置位**（不能等第一个 await 之后）——
  /// [_ambientPlaying] 只在拿到播放器后才置位，那时两个并发流程已经都能穿过
  /// [playGardenAmbientAndWait] 的 `skip: _ambientPlaying` 检查。
  ///
  /// 典型触发：`applySettings` 的「迟到补播」在 4ms 内被调用两次（外壳 initState 的
  /// 首调+ provider 变更监听），两次都判定 `lateRepay=true`（第一次是 `unawaited`，
  /// [_ambientRunning] 尚未来得及翻 true）→ 两个流程并发操作**同一个** `_ambientPlayer`
  /// → 第二个流程的 `player.stop()`（`_setPlatformActive(false)`）打断第一个流程正在
  /// 进行的 `setAsset`（`_setPlatformActive(true)`）→ just_audio 检测到 activation 序列
  /// 被覆盖，`checkInterruption` 抛 `PlatformException(abort, Loading interrupted)`
  /// （`just_audio.dart:1331`）→ 首播彻底失败、只能等 30s 定时器。
  bool _ambientStarting = false;

  /// 氛围音**代际**计数（F71 v3，玄参 2026-10-07「切 tab 后音乐停一下又继续」）：
  /// 每次 [stopGardenAmbient] 递增；[_playGardenAmbient] 在每个 await 间隙后校验，
  /// 被 stop 过的在途加载/启动一律作废（竞态修复，见该函数注释）。
  int _ambientGeneration = 0;

  /// 自愈节流：防止「续播后又被同一段音效打断」时高频反复重启。
  DateTime _lastAmbientHealAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 氛围音播放器状态订阅（自愈监听），[dispose] 时取消。
  StreamSubscription<PlayerState>? _ambientStateSub;

  /// [AudioSession] 是否已配置过（D1-v2 根因修复；幂等守卫，见
  /// [_ensureAudioSessionConfigured]）。
  bool _audioSessionConfigured = false;

  // ── SFX ducking（A 项，玄参 2026-10-07「音效打断背景音；背景音正常播放，或降低音量」）──
  //
  // 与「背景类播放器 handleInterruptions:false」互补：即便仍被 SFX 竞争/打断，也先**压低**
  // 氛围音而非静音，SFX 播完（或 [kSfxDuckMaxMs] 兜底超时）再恢复。仅作用于花园氛围音。

  /// duck 起始时的氛围音代际（恢复前校验，避免复活已 stop 的氛围音，F70/F71/F81 不回归）。
  int _duckAmbientGeneration = 0;

  /// ducking 恢复兜底定时器（防监听不到 SFX `completed` 导致音量被永久压低）。
  Timer? _duckRestoreTimer;

  /// SFX 播放器「播完」监听（用于及时解除 ducking；恢复后解绑）。
  StreamSubscription<PlayerState>? _sfxDuckSub;

  // ── 首进失败的有界重试（玄参 2026-10-07 真机复测「首进花园仍不响」）──

  /// 氛围音起播**失败**后的有界重试定时器（成功 / 放弃 / stop / dispose 时取消）。
  Timer? _ambientRetryTimer;

  /// 已触发的失败重试次数（成功起播 / stop / dispose 复位）。
  int _ambientRetryCount = 0;

  // ── 真机诊断：系统音频会话事件（仅 debug）──

  /// 是否已订阅 [AudioSession] 事件（幂等位）。
  bool _sessionDiagAttached = false;

  /// 打断事件订阅（真机诊断用，[dispose] 取消）。
  StreamSubscription<AudioInterruptionEvent>? _sessionInterruptSub;

  /// becomingNoisy（耳机拔出等）事件订阅（真机诊断用，[dispose] 取消）。
  StreamSubscription<void>? _sessionNoisySub;

  /// 应用设置：决定 SFX / BGM 是否生效。
  ///
  /// 若关闭 BGM 且正在播放，则立即停止；开启由调用方在 [startBgm] 触发。
  /// 花园氛围音（[_ambientPlayer]）同样受 [_bgmOn] 控制：关闭时立即停止。
  void applySettings({required bool soundOn, required bool bgmOn}) {
    _soundOn = soundOn;
    _bgmOn = bgmOn;
    final bool lateRepay = bgmOn &&
        !_suspendedForBackground &&
        _ambientShouldPlay &&
        !_ambientRunning;
    _adbg(
      'applySettings',
      'in soundOn=$soundOn bgmOn=$bgmOn | shouldPlay=$_ambientShouldPlay '
      'playing=$_ambientPlaying running=$_ambientRunning '
      'suspended=$_suspendedForBackground lateRepay=$lateRepay',
    );
    if (!_bgmOn && _bgmPlaying) {
      unawaited(stopBgm());
    }
    if (!_bgmOn && _ambientRunning) {
      unawaited(stopGardenAmbient(reason: 'bgmOff'));
    }
    // F82-b（玄参 2026-10-07 真机复测「首次进花园仍不响」）：花园页可能在设置**到达之前**
    // 就调用了 [playGardenAmbient]（那时 [_bgmOn] 还是默认 false）——「要播」意图已记为 true
    // 但没发声。设置迟到变 true 时**补一次启动**，否则要等下一个 30s 定时器 / 切 tab 才响。
    // ⚠️ 判据用 [_ambientRunning]（已在运行就不重复补播）——不能用 [_ambientPlaying]（加载
    // 窗口标记，稳态恒 false），否则每次设置同步都会把氛围音**从头重启**（QA 同源②反证）。
    if (lateRepay) {
      _adbg('applySettings', 'late补播 → _playGardenAmbient()');
      unawaited(_playGardenAmbient());
    }
  }

  /// 由 [factory] 安全构造播放器：构造失败（如无音频后端 / 绑定未初始化）返回 null，
  /// 由调用方静默降级。
  AudioPlayer? _safeCreate(AudioPlayer? Function() factory) {
    try {
      return factory();
    } catch (_) {
      return null; // 构造失败：静默降级，不崩、不刷日志
    }
  }

  /// 构造 SFX 播放器（测试覆盖优先，否则默认工厂）。
  AudioPlayer? _createSfx() =>
      _safeCreate(_playerFactoryOverride ?? _defaultPlayerFactory);

  /// 构造背景类播放器（BGM / 花园氛围音；测试覆盖优先，否则 `handleInterruptions:false`）。
  AudioPlayer? _createBackground() =>
      _safeCreate(_playerFactoryOverride ?? _defaultBackgroundPlayerFactory);

  Future<AudioPlayer?> get _sfx async {
    await _ensureAudioSessionConfigured(); // D1-v2：任何播放器首次使用前先声明音频会话
    _sfxPlayer ??= _createSfx();
    await _clearStaleAssetCacheOnce();
    return _sfxPlayer;
  }

  Future<AudioPlayer?> get _bgm async {
    await _ensureAudioSessionConfigured(); // D1-v2
    _bgmPlayer ??= _createBackground();
    await _clearStaleAssetCacheOnce();
    return _bgmPlayer;
  }

  Future<AudioPlayer?> get _ambient async {
    await _ensureAudioSessionConfigured(); // D1-v2：冷启动首次氛围音卡 ready 的根因修复
    _ambientPlayer ??= _createBackground();
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
    // A 项（玄参 2026-10-07）：播放 SFX 前把花园氛围音**压低**（ducking），播完恢复；
    // 与「背景类播放器 handleInterruptions:false」双管齐下，避免「背景音断掉、重头开始」。
    // ⚠️ 仅当确实压低了氛围音才挂「恢复」定时器/监听：否则会凭空留下一个 5s 的兜底
    // Timer（widget 测试会因「Tree disposed 后仍有 pending timer」被判失败，真机也纯属浪费）。
    final bool ducked = _duckAmbientForSfx();
    if (ducked) _armDuckRestore(player);
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

  /// 花园氛围音**此刻确实在出声**？——ducking 的前置判据。
  ///
  /// ⚠️ 不能用 [_ambientPlaying]：后者只是 [_playGardenAmbient] 的**加载窗口**标记
  /// （起播前置 true → `finally` 立即 false），**稳态恒为 false** → 若拿它当前置，
  /// ducking 与恢复在稳态**永不触发**（QA 2026-10-07 独立反证实证，见 F83）。改用真实
  /// 播放器的 [AudioPlayer.playing]——just_audio `play()` 会**乐观置 true**
  /// （`lib/just_audio.dart` `_playingSubject.add(true)`），测试假平台下同样成立。
  bool get _ambientAudible {
    final AudioPlayer? amb = _ambientPlayer;
    return amb != null && amb.playing && _ambientShouldPlay && _bgmOn;
  }

  /// 花园氛围音**已在运行**？（加载窗口内，或播放器正在播）——用于 [applySettings] 的
  /// 「是否需要停 / 是否需要补播」判定，**不掺杂 [_bgmOn]**（关 BGM 那一瞬 [_bgmOn] 已是
  /// false，仍需据此把在播的氛围音停掉；QA 2026-10-07 同源缺陷反证）。
  bool get _ambientRunning =>
      _ambientPlaying || (_ambientPlayer?.playing ?? false);

  /// SFX 开始 → 把**花园氛围音**压到 [kSfxDuckAmbientVolume]（A 项 ducking）。
  ///
  /// 仅在氛围音确实在播（[_ambientAudible]）时压低；**已在压低态则不重复 setVolume**
  /// （连续多次 SFX 只压低一次、不堆叠）。记录当时的代际，供恢复时校验（不复活已停的氛围音）。
  ///
  /// 返回 `true` 表示**处于压低态**（调用方据此决定是否挂恢复逻辑）。
  bool _duckAmbientForSfx() {
    if (_ambientDucked) {
      _adbg('duck', 'skip: already ducked（不堆叠 setVolume）');
      return true; // 已在压低态：不重复压低
    }
    if (!_ambientAudible) {
      _adbg(
        'duck',
        'no duck: ambient not audible (playing=${_ambientPlayer?.playing} '
        'shouldPlay=$_ambientShouldPlay bgmOn=$_bgmOn)',
      );
      return false;
    }
    _ambientDucked = true;
    _duckAmbientGeneration = _ambientGeneration;
    _adbg('duck',
        'duck → setVolume($kSfxDuckAmbientVolume) gen=$_ambientGeneration');
    unawaited(_ambientPlayer!.setVolume(kSfxDuckAmbientVolume));
    return true;
  }

  /// 挂「SFX 播完 → 解除 ducking」监听 + 兜底定时器（二者取先到者）。
  void _armDuckRestore(AudioPlayer sfx) {
    _duckRestoreTimer?.cancel();
    _duckRestoreTimer = Timer(
      const Duration(milliseconds: kSfxDuckMaxMs),
      _restoreAmbientVolume,
    );
    _adbg('duck',
        'arm restore: Timer(${kSfxDuckMaxMs}ms) + SFX completed listener');
    unawaited(_sfxDuckSub?.cancel());
    // D2 修复（玄参 2026-10-07 真机日志锁定）：只在 processingState **真正跃迁到 completed**
    // 时才恢复。**比单纯 `.skip(1)` 更强**——D2 护栏测试 D2-① 实证 `.skip(1)` 不够：
    //  ① `playerStateStream` 是 BehaviorSubject（`just_audio.dart:125` `_playerStateSubject =
    //     BehaviorSubject<PlayerState>()`；`:452` `playerStateStream => _playerStateSubject.stream`）
    //     → 订阅瞬间**重放当前值**；若 SFX 播放器此刻已是 completed（上一支 SFX 播完的残留态），
    //     `.skip(1)` 能挡掉这一次重放。
    //  ② 但本方法随后由 [_playSfx] 立即 `player.stop()`，而 just_audio 的 `stop()` 只
    //     `_playingSubject.add(false)`（`just_audio.dart:1023`）**不改 processingState**
    //     → 组合出的新 playerState 仍是 `(playing=false, completed)`（且与上一个 distinct）
    //     → 还是被 `.where(completed)` 命中 → 依旧秒恢复（本护栏测试实测：arm 后 1ms 即 restore）。
    // 故改为「**非 completed → completed 的跃迁**」判定：以订阅瞬间的 processingState 为前值
    // （`processingState` 与 `playerStateStream` 同源 playEvent，二者一致），只在真正跨入
    // completed 时才恢复——老 / 残留的 completed 一律不触发。
    ProcessingState prev = sfx.processingState;
    _sfxDuckSub = sfx.playerStateStream.listen((PlayerState s) {
      final ProcessingState now = s.processingState;
      final bool wasCompleted = prev == ProcessingState.completed;
      prev = now;
      if (!wasCompleted && now == ProcessingState.completed) {
        _restoreAmbientVolume(); // 本次 SFX 真正播完（新跃迁）→ 才恢复
      }
    });
  }

  /// 解除 ducking：恢复花园氛围音音量（幂等）。
  ///
  /// ⚠️ 恢复侧与 duck 侧**同一判据**（[_ambientAudible]）——否则一旦 duck 修好触发，恢复侧
  /// 仍因旧判据不成立而**永不恢复** → 氛围音音量被永久卡在 0.35（QA 2026-10-07 提醒）。
  /// ⚠️ 仅在氛围音**仍应播且代际未变**时恢复——决不在其已被 [stopGardenAmbient] 停掉后
  /// 去碰它（F70/F71/F81 约束：不得复活已停的氛围音）。
  void _restoreAmbientVolume() {
    _duckRestoreTimer?.cancel();
    _duckRestoreTimer = null;
    unawaited(_sfxDuckSub?.cancel());
    _sfxDuckSub = null;
    if (!_ambientDucked) {
      _adbg('restore', 'no-op: never ducked');
      return; // 从未压低：无需恢复
    }
    _ambientDucked = false;
    if (_duckAmbientGeneration != _ambientGeneration) {
      _adbg(
        'restore',
        'skip: generation changed duckGen=$_duckAmbientGeneration '
        'now=$_ambientGeneration（已 stop，不复活）',
      );
      return;
    }
    if (!_ambientAudible) {
      _adbg(
        'restore',
        'skip: ambient not audible (playing=${_ambientPlayer?.playing} '
        'shouldPlay=$_ambientShouldPlay bgmOn=$_bgmOn)',
      );
      return;
    }
    _adbg('restore', 'restore → setVolume(1.0)');
    unawaited(_ambientPlayer!.setVolume(1.0));
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
      // 真机诊断（item 6）：每次状态变化留痕——这是判断「背景音到底是被**暂停**了，
      // 还是只是**变轻 / 播完**」的唯一硬证据。
      _adbg(
        'ambientState',
        'playing=${st.playing} processingState=${st.processingState} '
        '(reloading=$_ambientReloading shouldPlay=$_ambientShouldPlay '
        'bgmOn=$_bgmOn ducked=$_ambientDucked)',
      );
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
      _adbg('ambientHeal', 'needs heal → 从头续播 _playGardenAmbient()');
      unawaited(_playGardenAmbient()); // 从头续播
    });
    // 真机诊断（item 7）：订阅系统音频会话事件（幂等、仅 debug）。
    unawaited(_attachSessionDiagnostics());
  }

  /// 🔴 **首次播放前必须配置 Android 音频会话**（D1-v2 根因修复，2026-10-07 真机日志实锤）。
  ///
  /// 症状 = 玄参真机反馈「杀掉程序重开、从首页直接进花园 tab，**没有背景音**，约 30s 后才响」。
  /// 真机日志铁证（`/tmp/amb_r5.log` 末次冷启动，两轮逐事件对比）：
  /// ```
  /// ✗ 卡死轮 22:52:36.620  playing=true ready → 之后 29.5 秒【零事件】、永远无 completed
  /// ✓ 正常轮 22:53:06.219  playing=true ready → 22:53:16.536 completed（实播 10.32s）
  /// ```
  /// 即 `play()` 被调用、`playing` 被乐观置 true、`processingState` 到 `ready`，但 ExoPlayer
  /// **渲染管道从未真正启动**（平台再无任何上报）→ 10 秒的曲子走不完 → 干等 30s 定时器重试。
  ///
  /// 根因：**本项目从未调用过 `AudioSession.instance.configure(...)`**（全仓库 grep 为空）。
  /// Android 上音频会话未声明时首次 `play()` 会卡在 ready 不渲染；一旦有 SFX 播过（SFX 播放器
  /// 用 just_audio 默认 `handleInterruptions: true`，其内部会自行配置/激活会话），后续氛围音
  /// 即恢复正常——这正是「首次不响、之后就响」的成因。
  ///
  /// 修法：在**任何播放器首次使用前**声明一次会话（Android 需 `AudioSessionConfiguration.music()`；
  /// iOS 用 `AVAudioSessionCategory.playback` 以便与静音键共存——本 App 的 BGM 应在静音模式下
  /// 仍可听见，这正是 just_audio 官方 `music()` 配置的语义）。
  ///
  /// 幂等：`_audioSessionConfigured` 守卫，只真正配置一次；任何失败静默（缺插件的 headless
  /// 测试环境 `AudioSession.instance` 已由 audio_session 内部 try/catch 处理）。
  Future<void> _ensureAudioSessionConfigured() async {
    if (_audioSessionConfigured) return;
    _audioSessionConfigured = true; // 先置位：并发调用只真正配置一次，且失败不反复重试
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _adbg('session', 'AudioSession configured（music）——冷启动首次 play() 不再卡 ready');
    } catch (e) {
      _adbg('session', 'configure failed（静默继续）: $e');
    }
  }

  /// 订阅系统音频会话的「打断 / becomingNoisy」事件（**仅 debug**、幂等）。
  ///
  /// 用于判定真机「背景音断掉」是否由**系统级**打断（来电 / 耳机拔出 / 其它 App 抢占）
  /// 介入。[AudioSession.instance] 内部已 try/catch 平台缺失 → headless 测试安全
  /// （无事件则永不触发）；release 下 [kDebugMode] 为 false 直接短路，零噪声。
  Future<void> _attachSessionDiagnostics() async {
    if (!kDebugMode || _sessionDiagAttached) return;
    _sessionDiagAttached = true;
    try {
      final AudioSession session = await AudioSession.instance;
      _sessionInterruptSub =
          session.interruptionEventStream.listen((AudioInterruptionEvent e) {
        _adbg('session', 'interruption type=${e.type} begin=${e.begin}');
      });
      _sessionNoisySub = session.becomingNoisyEventStream.listen((_) {
        _adbg('session', 'becomingNoisy（耳机拔出等）');
      });
      _adbg('session',
          'subscribed interruptionEventStream + becomingNoisyEventStream');
    } catch (e) {
      _adbg('session', 'attach failed: $e');
    }
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
    // fire-and-forget：生产路径不阻塞 UI（起播流程自身已在几百毫秒内返回，见 D1 修复）。
    unawaited(playGardenAmbientAndWait());
  }

  /// 触发一次花园氛围音起播并**等待起播流程结束**（[playGardenAmbient] 的可 await 版）。
  ///
  /// 生产路径 [playGardenAmbient] 只是本方法的 `unawaited` 包装；D1 回归护栏测试直接
  /// `await` 本方法，断言「起播流程在几百毫秒内返回、**绝不等于整首歌时长**」。
  @visibleForTesting
  Future<void> playGardenAmbientAndWait() async {
    // F70：挂起态（退后台 / 锁屏）一律不记意图、不发声。
    if (_suspendedForBackground) {
      _adbg('playGardenAmbient', 'skip: suspendedForBackground（后台/锁屏闸门）');
      return;
    }
    // D 修复（玄参 2026-10-07 复测「首次进花园仍不响」）：「花园要播」这一**意图/事实**
    // 必须**先于**开关判定记录——否则冷启动时 [_bgmOn] 仍是默认 false，本调用直接 return、
    // 不留任何痕迹，之后设置变 true 也无人补播（只能等 30s 定时器 / 切 tab）。
    // 记意图后若开关未允许则直接返回（不发声）；设置迟到由 [applySettings] 补播。
    _ambientShouldPlay = true;
    if (!_bgmOn) {
      _adbg('playGardenAmbient',
          'intent=play recorded; skip: !_bgmOn（等 applySettings 迟到补播）');
      return;
    }
    if (_ambientPlaying) {
      _adbg('playGardenAmbient', 'skip: _ambientPlaying（加载窗口内，勿重复起播）');
      return;
    }
    _adbg('playGardenAmbient', 'launch → _playGardenAmbient()');
    await _playGardenAmbient();
  }

  /// 有限次重试地启动氛围音（F82，玄参 2026-10-07）——纯函数，便于 headless 单测。
  ///
  /// 冷启动首次使用播放器前 `clearAssetCache()` 清了 just_audio 的资产拷贝缓存，
  /// 随后首次 `setAsset` / `play()` 可能失败或**返回后实际未在播**（[_isPlaying] 为 false）。
  /// 故：每次尝试走 [start]（stop→setAsset→seek→play），成功判据 = 无异常 **且**
  /// [_isPlaying] 为真；失败则隔 [retryDelay] 再试，最多 [maxAttempts] 次。
  ///
  /// [shouldAbort] 命中（退后台 / 氛围音代际失效）→ 立刻调 [onAbort]（停播）并返回 false，
  /// **不发声**（F70 v2 / F71 v3 约束不变）。
  /// 返回 true = 已成功启动（调用方据此置「应播」标记）；false = 有限次仍失败（静默放弃）。
  ///
  /// [onError]（可选，真机诊断）：某次 [start] 抛错时回调（带 0 基 attempt 与异常对象），
  /// 便于把「为什么没起来」打到日志；不传则行为与既有一致（向后兼容，不破既有单测）。
  static Future<bool> startAmbientWithRetries({
    required Future<void> Function() start,
    required bool Function() isPlaying,
    required bool Function() shouldAbort,
    required Future<void> Function() onAbort,
    int maxAttempts = kAmbientStartAttempts,
    Duration retryDelay = const Duration(milliseconds: kAmbientRetryDelayMs),
    void Function(int attempt, Object error)? onError,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (shouldAbort()) {
        await onAbort();
        return false;
      }
      if (attempt > 0) {
        await Future<void>.delayed(retryDelay);
        if (shouldAbort()) {
          await onAbort();
          return false;
        }
      }
      try {
        await start();
      } catch (e) {
        onError?.call(attempt, e);
        continue; // 加载 / 播放启动失败 → 重试
      }
      if (shouldAbort()) {
        await onAbort();
        return false;
      }
      if (isPlaying()) return true; // 确已启动
      // play() 返回但未真正在播 → 重试
    }
    await onAbort(); // 有限次仍失败：确保不留残响，静默放弃
    return false;
  }

  /// 有限轮询判定「氛围音 `play()` 是否真的起播」（D1 修复，玄参 2026-10-07 真机日志锁定）。
  ///
  /// 背景：just_audio 0.9.46 的 `AudioPlayer.play()` 返回的 Future **只在 pause / stop /
  /// 播放完成时才完成**（`just_audio.dart:975` `await playCompleter.future`）——`await play()`
  /// 会**阻塞整首歌**（真机日志实测：单曲 10.3s，冷启动甚至 67s）。故改为
  /// `unawaited(play())` 发起播放，再用本方法**有限轮询**判定是否真的起播。
  ///
  /// 🔴 **`playing` 是乐观置位、不能当「已发声」的判据**（D1-v2，真机日志实锤）：
  /// just_audio 的 `play()` 在首个 await **之前**就 `_playingSubject.add(true)`
  /// （`just_audio.dart:948`），冷启动时 ExoPlayer 可能卡在 `ready` 而**渲染从未开始**
  /// —— `playing=true` 却永远没有 `completed`。真机日志铁证（`/tmp/amb_r5.log` 末次冷启动）：
  /// ✗ 卡死轮 `22:52:36.620 playing=true ready` → 之后 **29.5 秒零事件、无 completed**；
  ///   ✓ 正常轮 `22:53:06.219` → `22:53:16.536 completed`（实播 10.32s）。
  /// 症状 = 玄参真机反馈「首进花园不响，约 30s 后才响」。
  ///
  /// ⚠️ **本方法无法区分「哑起播」与「正常起播」，只能如实汇报；真正的修复在
  /// [_ensureAudioSessionConfigured]**（Android 音频会话未声明 → 冷启动首次 `play()` 卡在
  /// `ready` 不渲染；一旦有 SFX 播过，会话被激活，后续氛围音即正常）。
  ///
  /// ⚠️ **也不能用 `player.position`**：`:590 _getPositionFor` 在 `playing && ready` 时返回
  /// `updatePosition + (now - updateTime)`——即使平台零上报也会随时间凭空增长，卡死时
  /// `position` 照样 > 0 → 判据形同虚设（本轮实测确认）。
  ///
  /// 轮询窗口 20ms × 最多 10 次 ≈ 200ms（真机实测起播 40~250ms 内完成），**绝不等于整首歌**。
  static Future<bool> _pollAmbientStarted(
    AudioPlayer player, {
    Duration pollInterval = const Duration(milliseconds: 20),
    int pollMaxCount = 10,
  }) async {
    for (int i = 0; i < pollMaxCount; i++) {
      if (player.playing && player.processingState != ProcessingState.idle) {
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    return player.playing;
  }

  Future<void> _playGardenAmbient() async {
    // F70 v2：直呼路径（自愈监听）兜底闸门——挂起态一律不进入加载流程。
    if (_suspendedForBackground) {
      _adbg('_playGardenAmbient', 'abort: suspendedForBackground');
      return;
    }
    // D1-v3 重入闸门：同一时刻只允许**一个**起播流程在跑。必须同步置位——下面第一个
    // await（取播放器）会让出事件循环，并发调用方会在这段时间里同时进入。
    if (_ambientStarting) {
      _adbg('_playGardenAmbient', 'skip: _ambientStarting（已有起播流程在跑，勿并发）');
      return;
    }
    _ambientStarting = true;
    try {
      await _playGardenAmbientGuarded();
    } finally {
      _ambientStarting = false;
    }
  }

  /// [_playGardenAmbient] 的真正实现（由重入闸门 [_ambientStarting] 串行化后调用）。
  Future<void> _playGardenAmbientGuarded() async {
    // F71 v3（玄参 2026-10-07 真机复测「切 tab 后音乐暂停一下又继续播完」）：
    // 代际 guard——每次 [stopGardenAmbient] 递增代际，本函数在每个 await 间隙后
    // 校验代际，被 stop 过的在途加载/启动一律作废。
    final int gen = _ambientGeneration;
    final AudioPlayer? player = await _ambient;
    if (player == null) {
      _adbg('_playGardenAmbient', 'abort: player==null（构造失败 / 无音频后端）');
      return; // 播放器构造失败：静默降级
    }
    if (!_bgmOn) {
      _adbg('_playGardenAmbient', 'abort: !_bgmOn（设置已关）');
      return;
    }
    if (gen != _ambientGeneration) {
      _adbg(
        '_playGardenAmbient',
        'abort: generation changed gen=$gen now=$_ambientGeneration（已被 stop）',
      );
      return; // 等待播放器构造期间已被 stop：作废
    }
    _attachAmbientHeal(player); // 首次拿到播放器时挂自愈监听（幂等）
    _ambientPlaying = true;
    _ambientReloading = true; // 主动重载窗口：自愈监听忽略期间的暂停事件
    bool shouldAbort() => _suspendedForBackground || gen != _ambientGeneration;
    int startCalls = 0;
    // D1 修复：本次 `start()` **有界轮询**的起播判定结果——[startAmbientWithRetries] 的
    // `isPlaying()` 即取此值（不再取 `await player.play()` 之后的 `player.playing`，因为
    // 我们**不再 await play()**，见 [start] 内注释）。
    bool polledStarted = false;
    try {
      final bool started = await startAmbientWithRetries(
        start: () async {
          startCalls++;
          _adbg('ambientStart',
              'attempt #$startCalls: stop→setAsset→seek→setVolume→play');
          await player.stop();
          await player.setAsset(kGardenAmbientAsset);
          await player.seek(Duration.zero);
          // A 项：每次重新起播都从**满音量**开始（清掉上一轮可能残留的 duck 压低）。
          await player.setVolume(1.0);
          _ambientDucked = false; // 起播即视作退出 duck 压低态
          // F70 v2：setAsset 是几百 ms 的异步间隙，期间可能退后台或离开花园 tab
          // → play() 前二次复查，命中则停播、绝不发声。
          if (shouldAbort()) {
            _adbg('ambientStart', 'attempt #$startCalls: abort（后台/代际）→ stop');
            await player.stop();
            polledStarted = false;
            return;
          }
          // D1 修复（致命，玄参 2026-10-07 真机日志锁定）：**绝不 await `player.play()`**。
          // just_audio 0.9.46 的 `AudioPlayer.play()` 返回的 Future **只在 pause / stop /
          // 播放完成时才完成**（`just_audio.dart:975` `await playCompleter.future`）——`await`
          // 它会阻塞**整首歌**（真机日志实测：单曲 10.3s，冷启动甚至 67s）。期间
          // [_ambientPlaying] 加载窗口一直开着（直到 finally 才复位），使 30s 定时器 / 切 tab
          // 回花园的再次起播被 [playGardenAmbient] 的 `skip: _ambientPlaying` 静默吞掉 →
          // 「首进花园不响」。改为「发起播放（不 await）」+ **有限轮询**判定是否真的起播
          // （[_pollAmbientStarted]，约 20ms × ≤10 ≈ 200ms 内返回）。
          unawaited(player.play());
          _adbg('ambientStart', 'attempt #$startCalls: play() 已发起（不 await）');
          polledStarted = await _pollAmbientStarted(player);
          _adbg('ambientStart',
              'attempt #$startCalls: poll→started=$polledStarted');
        },
        isPlaying: () {
          _adbg('ambientStart',
              'attempt #$startCalls: isPlaying(poll)=$polledStarted');
          return polledStarted; // D1：用「有限轮询结果」判定，而非阻塞后的 readback
        },
        shouldAbort: shouldAbort,
        onAbort: () => player.stop(),
        onError: (int attempt, Object e) {
          _adbg('ambientStart', 'attempt #${attempt + 1} start() 抛错: $e');
        },
      );
      // F82：仅「确已启动」才置应播标记；未成功则静默放弃（等自愈监听 / 下一轮定时器）。
      if (started) {
        _ambientShouldPlay = true;
        _ambientRetryCount = 0;
        _ambientRetryTimer?.cancel();
        _ambientRetryTimer = null;
        _adbg('ambientStart', 'started=true（已发声；清除失败重试计数）');
      } else if (shouldAbort()) {
        // 起播失败但根因是「已退后台 / 已被 stop / 代际已变」→ 这不是「冷启动起不来」，
        // **绝不挂重试**（否则遗留一个 1.5s Timer：真机无意义、测试会判 pending timer）。
        _adbg('ambientStart', 'started=false 但仍处 abort 态（后台/代际）→ 不挂重试');
      } else {
        _adbg('ambientStart', 'started=false（有限次仍失败）→ 挂有界重试');
        _scheduleAmbientFailureRetry(gen);
      }
    } finally {
      _ambientReloading = false;
      _ambientPlaying = false;
    }
  }

  /// 氛围音起播**有限次失败**后，挂一个**有界重试**（~1.5s 后重试、最多 N 次）。
  ///
  /// 玄参 2026-10-07 真机复测「首进花园仍不响」：冷启动时 iOS 音频会话尚未就绪，
  /// [startAmbientWithRetries]（3×400ms≈1.2s）可能**全败** → 原逻辑只能**干等 30s**
  /// 定时器 / 切 tab。此处叠加**有界**（不是无限）重试：带代际守卫，成功 / 放弃 / stop /
  /// dispose 一律取消；**不改动任何既有防护**（重试、自愈监听、30s 定时器都保留）。
  ///
  /// [gen] = 发起本次起播时的代际；挂前与每次触发时均校验，**代际已变即放弃**
  /// （已被 stop / dispose 作废 → 不遗留无意义定时器）。
  void _scheduleAmbientFailureRetry(int gen) {
    if (gen != _ambientGeneration) {
      _adbg('ambientRetry', 'skip arm: generation already changed');
      return;
    }
    if (_ambientRetryCount >= _kAmbientFailureRetryAttempts) {
      _adbg('ambientRetry',
          'give up（已达上限 $_kAmbientFailureRetryAttempts 次，等 30s 定时器/自愈）');
      return;
    }
    _ambientRetryTimer?.cancel();
    final int next = _ambientRetryCount + 1;
    _adbg('ambientRetry',
        'armed #$next in ${_kAmbientFailureRetryDelayMs}ms gen=$gen');
    _ambientRetryTimer = Timer(
      const Duration(milliseconds: _kAmbientFailureRetryDelayMs),
      () {
        _ambientRetryTimer = null;
        if (gen != _ambientGeneration) {
          _adbg('ambientRetry', 'abort: generation changed');
          return;
        }
        if (_suspendedForBackground || !_bgmOn || !_ambientShouldPlay) {
          _adbg(
            'ambientRetry',
            'abort: suspended=$_suspendedForBackground bgmOn=$_bgmOn '
            'shouldPlay=$_ambientShouldPlay',
          );
          return;
        }
        if (_ambientRunning) {
          _adbg('ambientRetry', 'abort: already running');
          return;
        }
        _ambientRetryCount++;
        _adbg('ambientRetry', 'fire #$_ambientRetryCount');
        unawaited(_playGardenAmbient());
      },
    );
  }

  /// 停止花园氛围音（离开花园 tab 时由花园页调用；保留播放器便于复用）。
  ///
  /// ⚠️ 必须**先**把 [_ambientShouldPlay] 翻 false 再 stop——否则主动 stop 触发的
  /// 状态事件会被自愈监听误判为「被打断」而立刻续播（离开花园后音乐阴魂不散）。
  /// ⚠️ F71 v3：同时递增 [_ambientGeneration] 作废一切在途加载/启动（见
  /// [_playGardenAmbient] 的代际 guard）。
  /// ## [reason]（真机诊断）
  /// 各调用点传入便于日志区分：`'leave'`（离开花园 tab）/ `'bgmOff'`（设置关 BGM）/
  /// `'suspend'`（退后台 / 锁屏）/ `'dispose'`。
  Future<void> stopGardenAmbient({String reason = 'unspecified'}) async {
    _adbg(
      'stopGardenAmbient',
      'reason=$reason | gen $_ambientGeneration→${_ambientGeneration + 1} '
      'shouldPlay(before)=$_ambientShouldPlay playing(before)=$_ambientPlaying '
      'ducked(before)=$_ambientDucked',
    );
    _ambientRetryTimer?.cancel(); // 离开/停播即作废失败重试
    _ambientRetryTimer = null;
    _ambientRetryCount = 0;
    _ambientGeneration++;
    _ambientShouldPlay = false;
    _ambientPlaying = false;
    _ambientDucked = false;
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
    _adbg('dispose',
        'release players; gen $_ambientGeneration→${_ambientGeneration + 1}');
    _ambientRetryTimer?.cancel();
    _ambientRetryTimer = null;
    _ambientRetryCount = 0;
    await _sessionInterruptSub?.cancel();
    _sessionInterruptSub = null;
    await _sessionNoisySub?.cancel();
    _sessionNoisySub = null;
    _sessionDiagAttached = false;
    await _ambientStateSub?.cancel();
    _ambientStateSub = null;
    _duckRestoreTimer?.cancel();
    _duckRestoreTimer = null;
    await _sfxDuckSub?.cancel();
    _sfxDuckSub = null;
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
    _ambientGeneration++; // F71 v3：作废一切在途氛围音加载/启动
    _bgmPlaying = false;
    _ambientPlaying = false;
    _ambientDucked = false;
    _ambientShouldPlay = false;
    _ambientReloading = false;
    _ambientStarting = false; // D1-v3：闸门复位，避免残留态卡死后续起播
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
    await stopGardenAmbient(reason: 'suspend');
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
