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

  /// C74 专注等级 · **普通升级**（非称号节点）配音（`default_level_up.mp3`，
  /// 2026-10-14 玄参交付，实测 3.5788s，已按 C35 归一化到 −20 LUFS）。
  ///
  /// 配 `assets/fx/levelUp/defaultLevelUp/` 36 帧；**不发阳光、不写账本**。
  levelUpDefault,

  /// C74 专注等级 · **称号节点**（1/5/10/…/40）配音（`5_level_up.mp3`，
  /// 2026-10-14 玄参交付，实测 4.1796s，实测已 −20.42 LUFS 无需校正）。
  ///
  /// 配 `assets/fx/levelUp/5leveUp/` 41 帧（目录名按交付原样，少一个 `l`）。
  levelUpFive,
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
      case AudioCue.levelUpDefault:
        return 'assets/audio/sfx/default_level_up.mp3';
      case AudioCue.levelUpFive:
        return 'assets/audio/sfx/5_level_up.mp3';
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

  // ── SFX「代际」闸门（F116；玄参 2026-10-13 转来孩子真机反馈）─────────────────
  /// SFX 播放**代际计数器**：每次 [playSfxPaths] **同步**递增一次（先于一切 `await`）。
  ///
  /// 语义 = 「谁号大谁说话」：[playSfxPaths] 起手记住自己的号，之后**每个 `await` 间隙**
  /// 都比对一次，一旦过期（已有更新的请求发起过）立刻**让位退出**——尤其**绝不**在
  /// 过期后还去 `player.stop()`，否则会把别人刚起播的音频掐断。
  ///
  /// ⚠️ 回放真实事故（玄参 2026-10-13 孩子真机反馈「专注中手动结束 → 护眼只有动画没声音」，
  /// 出现 3 次）：SFX 全局只有**一个共享播放器**，而首次 `_sfx` 要连做三步平台调用
  /// （配音频会话 / 建播放器 / 清资产缓存，几百 ms 级）。手动结束路径上
  /// 「结算页 focus_settle」先发起、卡在首次初始化；「护眼卡 eyecare」后发起却**抢先起播**
  /// → 前者醒来后照旧 `stop()`，把护眼配音掐断；护眼动画由 `FrameSequencePlayer` 的 Ticker
  /// 独立驱动，不受影响 → 孩子看到「有动画、没声音」。胜负取决于两边首次平台调用的快慢
  /// → 概率性偶发（约一半）。详见 bug 记录表 F116。
  int _sfxGeneration = 0;

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

  /// 氛围音**起播请求**累计次数（测试可见性，F138 新增）。
  ///
  /// 用途：断言「花园页没有在后台持续补播」。生产路径的每一次
  /// [playGardenAmbient]（进入花园首播 + 每 `kGardenAmbientIntervalSeconds` 秒的
  /// 定时补播）都会让本计数 +1；它**不受开关状态 / 起播成败影响**（在入口处递增），
  /// 因此是「页面认为自己可见」最直接、最不受 stop / applySettings 时序干扰的观测点。
  /// ⚠️ 只增不减；与其它跨用例状态一样由 [resetForTest] 复位。
  @visibleForTesting
  int get gardenAmbientPlayCalls => _gardenAmbientPlayCalls;

  int _gardenAmbientPlayCalls = 0;

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

  /// 起播闸门 [_ambientStarting] 的**置位时刻**（F133 僵尸门兜底）。
  ///
  /// 🔴 玄参 2026-10-19 iPad 13 真机日志：`setAsset` 被打断后**永不返回** → [_playGardenAmbientGuarded]
  /// 卡在 `try` 内 → `finally` 永不执行 → 闸门永久 `true`，之后每次补播都被自己的闸门挡掉
  /// （日志每 30s 一条 `skip: _ambientStarting`，直到杀 App 才恢复）。
  /// 故记录置位时刻：[_playGardenAmbient] 见到「已持有且超时」时强制复位（见 [kAmbientStartGateStuckMs]）。
  DateTime? _ambientStartingSince;

  /// 氛围音**代际**计数（F71 v3，玄参 2026-10-07「切 tab 后音乐停一下又继续」）：
  /// 每次 [stopGardenAmbient] 递增；[_playGardenAmbient] 在每个 await 间隙后校验，
  /// 被 stop 过的在途加载/启动一律作废（竞态修复，见该函数注释）。
  int _ambientGeneration = 0;

  /// 自愈节流：防止「续播后又被同一段音效打断」时高频反复重启。
  DateTime _lastAmbientHealAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 氛围音播放器状态订阅（自愈监听），[dispose] 时取消。
  StreamSubscription<PlayerState>? _ambientStateSub;

  /// 音频会话**是否已配置成功**（D1-v2 根因修复的幂等守卫；F116-C）。
  ///
  /// ⚠️ 只在**成功**后置 true；失败保持 false → 下次调用会重新尝试（原实现把置位写在
  /// `try` **之前**，一次冷启动失败 = 本进程此后所有播放都可能「哑起播」且永不重试，
  /// 而「会话未声明 → 冷启动首次 `play()` 卡 ready 不渲染」正是 F86 的真机根因）。
  bool _sessionConfigured = false;

  /// **正在进行中**的会话配置（null = 无在途）——仅用于让**并发**调用共享同一次配置。
  ///
  /// ⚠️ **为什么「已完成」用布尔、而不是把这个 Future 当最终状态留着**（F116 收尾实测）：
  /// 把已完成的 Future 长期留在字段里，会让**后续**调用直接 `await` 一个属于**旧 Zone**
  /// 的已完成 Future——监听回调按 Future **创建时**的 Zone 排进微任务队列，而那个 Zone
  /// 在 `flutter_test` 里每个 `testWidgets` 一个 FakeAsync Zone（本单例 [instance] 跨用例
  /// 复用），早已销毁 → 回调永不执行 → **整个 `_sfx` 永久挂起**（实测：同文件第 2/3 个
  /// 用例音效零加载、`setAsset` 一次未发生）。改用「在途共享 Future + 完成即清空」后，
  /// 已完成路径现场生成新 Future（Zone 安全），而并发语义（共享同一次配置）与
  /// 「失败可重试」语义**完全保留**。
  Future<void>? _sessionConfigFuture;

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

  /// 资产拷贝缓存**是否已清过**（一次即可；失败也置 true——清不掉只是可能命中陈旧拷贝，
  /// 不是致命故障，沿用既有「一次即可、失败静默」口径，避免反复删目录）。
  static bool _assetCacheCleared = false;

  /// **正在进行中**的清理（null = 无在途）——仅用于让**并发**调用等待同一次清理。
  ///
  /// ⚠️ 为什么需要「在途共享」（F116 修）：`bool` 版「先置位、再清」会让**并发**的两路
  /// SFX 产生顺序竞态——A 置位后开始删目录（慢），B 见已置位直接跳过并 `setAsset` 拷入新
  /// 文件，A 的删除**随后**落地 → 把 B 刚拷的资产删掉 → iOS AudioFileStream 报 −11849
  /// → 被静默 catch 吞 → **无声无日志**（与 F77 同款症状，只是触发路径不同）。改成
  /// 「在途共享」后，B 会**等 A 删完再拷**。
  ///
  /// ⚠️ 与 [_sessionConfigFuture] 同理：**已完成**状态由 [_assetCacheCleared] 布尔承载，
  /// 绝不把这个已完成的 Future 留在字段里给后续调用 `await`（跨 Zone → 回调永不执行）。
  static Future<void>? _assetCacheClearFuture;

  /// 每次冷启动清理一次 just_audio 的资产拷贝缓存（tmp/just_audio_cache）。
  ///
  /// ⚠️ F77 二层根因（just_audio 0.9.46 实证）：`setAsset` 会把 bundle 资产**拷贝**
  /// 到 tmp 缓存并**只按路径判缓存、不校验内容**——App 更新后同名素材换了内容，
  /// 仍会命中陈旧拷贝永不生效（初版 1.04s 的 collect_reward.mp3 命中缓存 → iOS
  /// AudioFileStream 报 -11849 → 被静默 catch 吞 → 无声无日志）。iOS/Android 的
  /// tmp 在 App 更新后不保证清空 → 冷启动清一次，保证素材永远取自当前包；
  /// 缓存拷贝是懒加载按需进行，开销可忽略。
  Future<void> _clearStaleAssetCacheOnce() => _assetCacheCleared
      ? Future<void>.value() // 已完成：现场生成新 Future（**绝不**复用旧的已完成 Future）
      : (_assetCacheClearFuture ??= _doClearAssetCache());

  /// [AudioPlayer.clearAssetCache] 的实际执行体（在途共享 Future 的目标）。
  ///
  /// 清缓存失败**不作废缓存**（与「会话配置失败」不同）：清不掉只是可能命中陈旧拷贝，
  /// 不是致命故障，沿用既有的「一次即可、失败静默」口径，避免反复删目录。
  static Future<void> _doClearAssetCache() async {
    try {
      await AudioPlayer.clearAssetCache();
    } catch (_) {
      // headless 测试环境无 path_provider 插件：静默降级。
    } finally {
      // 在途标记用完即清：后续调用走 [_assetCacheCleared] 短路（**不在**字段里留已完成
      // Future——那会让跨 Zone 的后续调用永远等不到回调）。
      _assetCacheCleared = true;
      _assetCacheClearFuture = null;
    }
  }

  /// 播放一次性音效（fire-and-forget，非阻塞）。
  ///
  /// 受 [_soundOn] 保护；内部异步加载与播放，任何失败均静默忽略。
  /// ⚠️ 多路并发时的胜负由 [_sfxGeneration] 决定（F116：**后发起者赢**，先发起者过期即让位）。
  void playSfx(AudioCue cue) => playSfxPaths(<String>[cue.assetPath]);

  /// 播放一次性音效，**按 [paths] 顺序依次回退**（fire-and-forget，非阻塞）。
  ///
  /// 用于「物种专属 → 通用兜底」这类多候选场景（成长过渡音，口径 C59；候选由
  /// `growSfxAssetCandidates` 生成）：前一个候选资源缺失 / 加载失败 → 试下一个；
  /// 全部失败 → 静默（与「素材缺失」的既有降级口径一致：不崩、不刷日志）。
  /// 受 [_soundOn] 保护；[paths] 为空直接返回。
  ///
  /// ⚠️ **F116（玄参 2026-10-13）**：SFX 只有一个共享播放器，两路请求**相距极近**地发起时
  /// （真机事故：手动结束 → 结算页 `focus_settle` 与护眼卡 `eyecare`）会互相 `stop()`。
  /// 由 [_sfxGeneration] 保证「**后发起者赢**；先发起者过期即让位，**绝不回头停别人**」。
  void playSfxPaths(List<String> paths) {
    if (!_soundOn || paths.isEmpty) return;
    unawaited(_playSfxPaths(paths));
  }

  Future<void> _playSfxPaths(List<String> paths) async {
    // F116 排号：**同步**递增（先于本函数内一切 `await`）→ 后发起者号更大，天然「后到者赢」。
    final int gen = ++_sfxGeneration;
    // 本次请求是否已过期（已有更新的请求发起过）——过期一律让位，**绝不**再碰播放器。
    bool stale() => gen != _sfxGeneration;
    // 🔴 C82 真机日志：养护 cue 被随后发起的成长 cue「静默作废」是「有动画没声音」的机制，
    //    故把「作废点」全部日志化（release 下 _adbg 直接短路，零噪声）。
    _adbg('sfx', 'begin gen=$gen paths=$paths');
    void abandon(String stage) =>
        _adbg('sfx', 'abandon gen=$gen @$stage（已被更新的 SFX 超越）now=$_sfxGeneration');

    final AudioPlayer? player = await _sfx;
    if (player == null) return; // 播放器构造失败：静默降级
    // 🔴 F116 核心（真机事故点）：`_sfx` 首次要连做三步平台调用（配会话 / 建播放器 / 清资产
    // 缓存，几百 ms 级）。若在这期间有更新的 SFX **抢先起播**，本协程醒来后**必须让位**——
    // 否则下面那句 `player.stop()` 会把对方刚起播的音频掐断（= 护眼卡「有动画没声音」）。
    if (stale()) {
      _adbg('sfx', 'abandon gen=$gen（取播放器期间已有更新的 SFX）now=$_sfxGeneration');
      return;
    }
    // A 项（玄参 2026-10-07）：播放 SFX 前把花园氛围音**压低**（ducking），播完恢复；
    // 与「背景类播放器 handleInterruptions:false」双管齐下，避免「背景音断掉、重头开始」。
    // ⚠️ 仅当确实压低了氛围音才挂「恢复」定时器/监听：否则会凭空留下一个 5s 的兜底
    // Timer（widget 测试会因「Tree disposed 后仍有 pending timer」被判失败，真机也纯属浪费）。
    final bool ducked = _duckAmbientForSfx();
    if (ducked) _armDuckRestore(player);
    // 真机修复（玄参 2026-09-30 反馈「离席回来欢迎音无声」）：app 刚从后台恢复时
    // 音频会话可能尚未就绪，首次播放被系统静默吞掉 → 整轮延迟 600ms 重试一次。
    // 外层 = 重试轮次；内层 = 候选回退（C59：物种专属 → 通用兜底）。
    for (int round = 0; round < 2; round++) {
      if (round > 0) {
        if (stale()) {
          abandon('retry-round');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (stale()) {
          abandon('retry-delay');
          return;
        }
      }
      for (final String path in paths) {
        if (stale()) {
          abandon('before-path');
          return;
        }
        try {
          // 每个 `await` 之后都重新比对代际：中途被更新的请求超越 → 立刻让位退出，
          // 既不把对方掐断，也不白播（F116）。
          await player.stop();
          if (stale()) {
            abandon('after-stop');
            return;
          }
          // F133：同款**有界加载**——SFX 与氛围音共患同一个 just_audio 缺陷（`setAsset` 在
          // 「加载途中被 `stop()`」时永不返回）。SFX 侧虽不致命（代际闸门让后来者赢），
          // 但卡住的协程会一直占着**同一个**共享 SFX 播放器，后续每次 `player.stop()` 都可能
          // 跟着挂住 → 音效整体永久哑。超时即当该候选失败，试下一个。
          if (!await loadAssetBounded(() => player.setAsset(path))) {
            _adbg('sfx',
                'setAsset 超时（${kAmbientSetAssetTimeoutMs}ms）→ 试下一候选: $path');
            continue;
          }
          _adbg('sfx', 'loaded gen=$gen path=$path');
          if (stale()) {
            abandon('after-setAsset');
            return;
          }
          await player.seek(Duration.zero);
          if (stale()) {
            abandon('after-seek');
            return;
          }
          // D1 同款（玄参 2026-10-07 真机日志锁定）：**绝不 await `player.play()`**——
          // just_audio 0.9.46 的 `play()` 返回的 Future 只在 pause / stop / 播完时才完成，
          // `await` 它会挂到**整段播完**（护眼配音 63.97s 就挂 64 秒）。改为「发起播放
          // （不 await）」+ **有限轮询**判定是否真的起播（[_pollPlaybackStarted]，
          // 正常起播时**首次检查即命中、零延迟**；未起播才轮到 20ms × ≤10 的轮询）。
          unawaited(player.play());
          final bool started = await _pollPlaybackStarted(player);
          if (stale()) {
            abandon('after-play');
            return;
          }
          if (started) return; // 确已起播 → 成功返回（F116-C：不再「发起即认为成功」）
          _adbg('sfx', 'not started（有限轮询未起播）→ 试下一候选 / 下一轮: $path');
        } catch (_) {
          // 该候选缺失 / 播放启动失败：试下一个候选（本轮全碰壁则下一轮再试一遍）。
        }
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
    //  ② 但本方法随后由 [_playSfxPaths] 立即 `player.stop()`，而 just_audio 的 `stop()` 只
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
  /// 幂等：由 [_sessionConfigured]（成功态）+ [_sessionConfigFuture]（在途共享）共同守卫——
  /// **成功只配置一次**（并发调用共享同一在途 Future，见 [_configureAudioSession]）；
  /// **失败保持未配置态 → 下次调用自动重试**；任何失败静默（缺插件的 headless 测试环境
  /// `AudioSession.instance` 已由 audio_session 内部 try/catch 处理）。
  ///
  /// ⚠️ 已完成路径必须**现场生成新 Future**（`Future.value()`），**不能**把旧的已完成
  /// Future 直接返回给调用方 `await`——跨 Zone 会导致回调永不执行（见 [_sessionConfigFuture]）。
  Future<void> _ensureAudioSessionConfigured() => _sessionConfigured
      ? Future<void>.value()
      : (_sessionConfigFuture ??= _configureAudioSession());

  Future<void> _configureAudioSession() async {
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _sessionConfigured = true; // 成功才置位（幂等：并发/后续调用都不会重复配置）
      _adbg('session', 'AudioSession configured（music）——冷启动首次 play() 不再卡 ready');
    } catch (e) {
      // 🔴 F116-C：失败**不置位**。原实现把 `_audioSessionConfigured = true` 写在 try
      // **之前**（「先置位：并发调用只真正配置一次，且失败不反复重试」），代价是**一次冷启动
      // 失败 = 本进程此后所有播放都可能「哑起播」且永不重试**——而「会话未声明 → 冷启动首次
      // `play()` 卡 ready 不渲染」正是 F86 的真机根因。改为：失败即保持未配置态（下次调用
      // 重新尝试），成功才置位（仍只配置一次）。
      _adbg('session', 'configure failed（下次调用重试）: $e');
    } finally {
      // 在途标记用完即清：后续路径一律由 [_sessionConfigured] 决定（成功短路 / 失败重试）。
      _sessionConfigFuture = null;
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
    // F138：测试可见的「起播请求」计数（入口处同步递增，与开关 / 成败无关）。
    _gardenAmbientPlayCalls++;
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

  /// 有限轮询判定「`play()` 是否真的起播」（D1 修复，玄参 2026-10-07 真机日志锁定）。
  ///
  /// **两处共用**：① 花园氛围音 [_playGardenAmbientGuarded]（D1）；② 一次性音效
  /// [_playSfxPaths]（**F116-C**：由「`await play()` 返回即认为成功」改成「起播确认」——
  /// 原来遇到静默哑起播就彻底无声，既不重试、也无任何日志）。
  ///
  /// 背景：just_audio 0.9.46 的 `AudioPlayer.play()` 返回的 Future **只在 pause / stop /
  /// 播放完成时才完成**（`just_audio.dart:975` `await playCompleter.future`）——`await play()`
  /// 会**阻塞整首歌**（真机日志实测：单曲 10.3s，冷启动甚至 67s）。故一律改为
  /// `unawaited(play())` 发起播放，再用本方法**有限轮询**判定是否真的起播。
  ///
  /// 🔴 **`playing` 是乐观置位、不能当「已发声」的判据**（D1-v2，真机日志实锤）：
  /// just_audio 的 `play()` 在首个 await **之前**就 `_playingSubject.add(true)`
  /// （`just_audio.dart:948`），冷启动时 ExoPlayer 可能卡在 `ready` 而**渲染从未开始**
  /// —— `playing=true` 却永远没有 `completed`。真机日志铁证（`/tmp/amb_r5.log` 末次冷启动）：
  /// ✗ 卡死轮 `22:52:36.620 playing=true ready` → 之后 **29.5 秒零事件、无 completed**；
  ///   ✓ 正常轮 `22:53:06.219` → `22:53:16.536 completed`（实播 10.32s）。
  /// 症状 = 玄参真机反馈「首进花园不响，约 30s 后才响」。
  /// 故本方法判据取 `playing && processingState != idle`（**不单独信 `playing`**）。
  ///
  /// ⚠️ **本方法无法区分「哑起播」与「正常起播」，只能如实汇报；氛围音的真正修复在
  /// [_ensureAudioSessionConfigured]**（Android 音频会话未声明 → 冷启动首次 `play()` 卡在
  /// `ready` 不渲染；一旦有 SFX 播过，会话被激活，后续氛围音即正常）。
  ///
  /// ⚠️ **也不能用 `player.position`**：`:590 _getPositionFor` 在 `playing && ready` 时返回
  /// `updatePosition + (now - updateTime)`——即使平台零上报也会随时间凭空增长，卡死时
  /// `position` 照样 > 0 → 判据形同虚设（本轮实测确认）。
  ///
  /// 轮询窗口 20ms × 最多 10 次 ≈ 200ms（真机实测起播 40~250ms 内完成），**绝不等于整首歌**。
  /// ✅ 正常起播时**首次检查即命中、零延迟返回**（不产生任何 `Future.delayed`）。
  static Future<bool> _pollPlaybackStarted(
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

  /// **有界**加载资源（F133）：把「可能永不返回」的 `setAsset` 变成「有界失败」。
  ///
  /// 🔴 根因见 [_playGardenAmbientGuarded] 内注释：just_audio 的 `setAsset` Future 只在
  /// 拿到 `ready` 时完成；加载途中被 `stop()` 打断会被平台**丢弃**——既不完成也不抛错。
  /// 不加超时 → 整个起播协程永久挂起 → `finally` 不执行 → 重入闸门永久关死
  /// （iPad 13 实测：此后每 30s 一条 `skip: _ambientStarting`，只能杀 App 恢复）。
  ///
  /// 返回 `true` = 加载完成（或加载失败但**已抛错**，由 [startAmbientWithRetries] 的
  /// `try/catch` 兜）；`false` = **超时**，调用方必须丢弃该播放器（它仍卡在 `loading`，
  /// 会继续占着共享音频会话）。
  ///
  /// 独立成静态纯函数便于 headless 单测（真机才有的「平台永不返回」用永不完成的
  /// Future 即可复现）。
  @visibleForTesting
  static Future<bool> loadAssetBounded(
    Future<void> Function() load, {
    int timeoutMs = kAmbientSetAssetTimeoutMs,
  }) async {
    try {
      await load().timeout(Duration(milliseconds: timeoutMs));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// 丢弃一个**卡死**的氛围音播放器（F133）：解引用 + 取消状态订阅 + 异步释放。
  ///
  /// ⚠️ 仅在 `identical(_ambientPlayer, player)` 时生效——僵尸体复位后可能已由新流程
  /// 建了新播放器，绝不能误杀。
  /// ⚠️ 释放一律 fire-and-forget：卡住的平台调用可能连 `dispose()` 一起挂住，`await`
  /// 会让本轮起播重新陷入「永不返回」。
  void _discardAmbientPlayer(AudioPlayer player) {
    if (!identical(_ambientPlayer, player)) return;
    _adbg('_discardAmbientPlayer', '丢弃卡死的氛围音播放器并解引用（待下轮重建）');
    _ambientPlayer = null;
    unawaited(_ambientStateSub?.cancel() ?? Future<void>.value());
    _ambientStateSub = null; // 置空 → 新播放器会重新挂自愈监听
    unawaited(_disposeQuietly(player));
  }

  Future<void> _playGardenAmbient() async {
    // F70 v2：直呼路径（自愈监听）兜底闸门——挂起态一律不进入加载流程。
    if (_suspendedForBackground) {
      _adbg('_playGardenAmbient', 'abort: suspendedForBackground');
      return;
    }
    // D1-v3 重入闸门：同一时刻只允许**一个**起播流程在跑。必须同步置位——下面第一个
    // await（取播放器）会让出事件循环，并发调用方会在这段时间里同时进入。
    //
    // F133 僵尸门兜底（玄参 2026-10-19 iPad 13 真机）：平台侧卡死会让 `finally` 永不执行
    // → 闸门永久 `true`。此处按「置位时刻」判僵尸：持有超过 [kAmbientStartGateStuckMs]
    // 即强制复位（正常起播最慢也就 ~1s，20s 绝不误伤）——把「只能杀 App」降级为「等一轮」。
    if (_ambientStarting) {
      final DateTime? since = _ambientStartingSince;
      final Duration held =
          since == null ? Duration.zero : DateTime.now().difference(since);
      if (since != null &&
          held > const Duration(milliseconds: kAmbientStartGateStuckMs)) {
        _adbg('_playGardenAmbient',
            'zombie gate: 闸门已持有 ${held.inMilliseconds}ms（疑似平台卡死）→ 强制复位并作废在途流程');
        _ambientStarting = false;
        _ambientStartingSince = null;
        // 递增代际 → 那个僵死的在途流程（若它真的醒来了）在每个 await 间隙都会被判作废，
        // 绝不允许它和新流程同时操作同一个播放器。⚠️ 刻意**不**动 `_ambientShouldPlay`：
        // 用户意图仍是「要播」，只是这一轮卡住了。
        _ambientGeneration++;
      } else {
        _adbg('_playGardenAmbient', 'skip: _ambientStarting（已有起播流程在跑，勿并发）');
        return;
      }
    }
    _ambientStarting = true;
    _ambientStartingSince = DateTime.now();
    try {
      await _playGardenAmbientGuarded();
    } finally {
      _ambientStarting = false;
      _ambientStartingSince = null;
    }
  }

  /// 仅供测试：把起播闸门伪造成「已被持有 [ago]」的僵尸态（覆盖 F133 兜底路径）。
  ///
  /// 不能用 `tester.pump(duration)` 推进——`fake_async` 不代理 `DateTime.now()`，
  /// 故直接改写「置位时刻」而不是等真实时间流逝。
  @visibleForTesting
  void debugSetAmbientGateStuck({
    bool stuck = true,
    Duration ago = const Duration(seconds: 30),
  }) {
    _ambientStarting = stuck;
    _ambientStartingSince = stuck ? DateTime.now().subtract(ago) : null;
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
          // F133：每次尝试都**重新取**播放器——上一次尝试可能因 `setAsset` 超时被丢弃
          // （见下方 `on TimeoutException`），重建后必须换成新实例，否则会对已释放的
          // 播放器继续操作。
          final AudioPlayer? p = await _ambient;
          if (p == null) {
            _adbg('ambientStart', 'attempt #$startCalls: abort（播放器构造失败）');
            polledStarted = false;
            return;
          }
          _attachAmbientHeal(p); // 幂等；重建后会重新挂到新播放器上
          _adbg('ambientStart',
              'attempt #$startCalls: stop→setAsset→seek→setVolume→play');
          await p.stop();
          // 🔴 F133（玄参 2026-10-19 iPad 13 真机日志锁定）：`setAsset` 返回的 Future
          // **只在拿到 `ready` 时完成**；加载途中被 `stop()`（= 孩子退出花园 / 切 tab）
          // 打断后，平台侧的等待被**丢弃**——既不完成也不抛错，`await` 永远不返回。
          // 后果链：本函数卡在 `try` 内 → `finally` 不执行 → [_ambientStarting] 永久 true
          // （且 `stopGardenAmbient` 只清 `_ambientPlaying`、不清闸门）→ 该进程内氛围音
          // 再也不起播，**只能杀 App**（真机日志：此后每 30s 一条 `skip: _ambientStarting`）。
          // 故加载一律**有界**：超时即当本次失败。
          final bool loaded = await loadAssetBounded(
            () => p.setAsset(kGardenAmbientAsset),
          );
          if (!loaded) {
            _adbg('ambientStart',
                'attempt #$startCalls: setAsset 超时（${kAmbientSetAssetTimeoutMs}ms）→ 丢弃播放器待重建');
            // 丢弃：卡在 `loading` 的播放器会一直占着共享音频会话，连 SFX 都可能被堵
            // （iPad 13 实测「花园里所有操作都没声」）。下一轮 `await _ambient` 会重建。
            if (shouldAbort()) {
              polledStarted = false;
              return; // 已被 stop / 僵尸体复位作废 → 绝不误杀新流程的播放器
            }
            _discardAmbientPlayer(p);
            polledStarted = false;
            return;
          }
          await p.seek(Duration.zero);
          // A 项：每次重新起播都从**满音量**开始（清掉上一轮可能残留的 duck 压低）。
          await p.setVolume(1.0);
          _ambientDucked = false; // 起播即视作退出 duck 压低态
          // F70 v2：setAsset 是几百 ms 的异步间隙，期间可能退后台或离开花园 tab
          // → play() 前二次复查，命中则停播、绝不发声。
          if (shouldAbort()) {
            _adbg('ambientStart', 'attempt #$startCalls: abort（后台/代际）→ stop');
            await p.stop();
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
          // （[_pollPlaybackStarted]，约 20ms × ≤10 ≈ 200ms 内返回）。
          unawaited(p.play());
          _adbg('ambientStart', 'attempt #$startCalls: play() 已发起（不 await）');
          polledStarted = await _pollPlaybackStarted(p);
          _adbg('ambientStart',
              'attempt #$startCalls: poll→started=$polledStarted');
        },
        isPlaying: () {
          _adbg('ambientStart',
              'attempt #$startCalls: isPlaying(poll)=$polledStarted');
          return polledStarted; // D1：用「有限轮询结果」判定，而非阻塞后的 readback
        },
        shouldAbort: shouldAbort,
        // F133：播放器可能已在上一轮被丢弃重建 → 取**当前**实例，缺失即无操作
        // （原实现闭包捕获首个 `player`，重建后会去 stop 一个已释放的实例）。
        onAbort: () async {
          final AudioPlayer? p = _ambientPlayer;
          if (p == null) return;
          try {
            await p.stop();
          } catch (_) {
            // 静默降级。
          }
        },
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
    _ambientStartingSince = null; // F133：闸门置位时刻同步清空（字段维护约定）
    _suspendedForBackground = false;
    _bgmWasPlayingBeforeBackground = false;
    _ambientShouldPlayBeforeBackground = false;
  }

  /// 仅供测试：把单例恢复到「接近全新构造」的状态。
  ///
  /// ⚠️ **每个 `testWidgets` 之间必须调用一次**（放在这些测试文件的 `setUp` 里）。
  ///
  /// 为什么必须：[instance] 是**跨用例复用**的全局单例，而 `flutter_test` 给每个
  /// `testWidgets` 一套**独立的 FakeAsync Zone**。上一个用例创建的 [AudioPlayer] 及其平台侧
  /// 事件流属于**已销毁的 Zone** → 本用例 `setAsset` 内部**永远等不到 `ready` 事件**
  /// （`play` 从未发生），而 `load:` 已**同步**记录 → 断言仍然通过 = **假绿**（F116 收尾实测
  /// 发现，属**改动前既存**）。⚠️ 只能用本钩子：`garden_page.dart` 的音效是**直接调
  /// [instance]**（绕过 `audioServiceProvider`），`overrideWithValue` 无效。
  ///
  /// ⚠️ 本方法**同步**、**绝不 `await`** 任何来自旧 Zone 的 Future —— [dispose] 会 `await`
  /// 播放器的 `dispose()`，跨 Zone 时可能**永不返回**（与 §5.20 记录的「已完成 Future 跨
  /// Zone」同源）。释放动作一律 fire-and-forget。
  ///
  /// ⚠️ 维护约定：**将来新增「跨用例会残留」的状态字段，必须同步补到这里**（字段清单与
  /// [dispose] 对齐，避免漂移）。
  @visibleForTesting
  void resetForTest() {
    // 1) 释放并解引用三个播放器（**不 await**）。
    for (final AudioPlayer? p in <AudioPlayer?>[
      _sfxPlayer,
      _bgmPlayer,
      _ambientPlayer,
    ]) {
      unawaited(_disposeQuietly(p));
    }
    _sfxPlayer = null;
    _bgmPlayer = null;
    _ambientPlayer = null;
    // 2) 与播放器绑定的定时器 / 订阅一并作废（否则它们仍引用旧播放器）。
    _ambientRetryTimer?.cancel();
    _ambientRetryTimer = null;
    _ambientRetryCount = 0;
    _duckRestoreTimer?.cancel();
    _duckRestoreTimer = null;
    unawaited(_ambientStateSub?.cancel() ?? Future<void>.value());
    _ambientStateSub = null;
    unawaited(_sfxDuckSub?.cancel() ?? Future<void>.value());
    _sfxDuckSub = null;
    // 3) 播放器 / 会话 / 缓存相关的幂等位与代际全部归零。
    _sfxGeneration = 0;
    _bgmPlaying = false;
    _ambientPlaying = false;
    _ambientDucked = false;
    _ambientShouldPlay = false;
    _ambientReloading = false;
    _ambientStarting = false;
    _ambientStartingSince = null; // F133：闸门置位时刻（与 dispose 字段清单对齐）
    _ambientGeneration++;
    _gardenAmbientPlayCalls = 0; // F138：起播请求计数（跨用例必须复位）
    _sessionConfigured = false;
    _sessionConfigFuture = null;
    _assetCacheCleared = false;
    _assetCacheClearFuture = null;
    // 4) 刻意**不**动：`_soundOn` / `_bgmOn`（各用例自己用 `applySettings` 驱动）、
    //    `_suspendedForBackground` 等生命周期态（测试不涉及后台切换）。
  }

  /// 静默释放单个播放器（[resetForTest] 专用；失败无意义、不刷日志）。
  static Future<void> _disposeQuietly(AudioPlayer? player) async {
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {
      // 静默降级。
    }
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
