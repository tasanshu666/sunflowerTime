/// 打盹屏专注页（T09，横屏，独占屏）。
///
/// 依据 PRD §4.1（专注模式）/ §4.2（布局）/ §4.3（屏幕交互检测）/ §4.1.6（退出路径）。
///
/// 必须保留的既有修复（不得回退）：
/// - **B18**：方向宽限期 `kOrientationGraceSeconds`(3s) + 武装条件（须先观察到一次横屏，
///   之后的竖屏才算退出意图）——由 [PresenceDetector] 承载；
/// - **B20**：结束时用 `context.go('/settle')` / `context.go('/')` 而非 `Navigator.pop()`
///   （go_router 的 go 是替换路由栈，pop 会黑屏）；外层 `PopScope(canPop: false)` 拦
///   Android 返回键并走「暂停 + 确认」。
///
/// M1 新增：接入 [FocusEngine]（tick 驱动 + 事件流驱动四档呈现）；顶部只留
/// 「本次 mm:ss / mm:ss」（不显示阳光池数字，PRD §4.2）；离席降亮、恢复 lvl3 光晕；
/// 到时 / 打断 / 手动结束进入结算页。
///
/// M1 第二批（B27 亮屏欢迎光晕更明显更久；F01 专注期系统勿扰 DND）。
library focus_page;

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/presence_detector.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/dnd_controller.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/widgets/feedback_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_sunflower_stage.dart';

/// 本场是否已把「今日剩余额度」用尽（供专注页轻提示判定）。
///
/// 公开纯函数（便于单测，不依赖 widget）：[remainingMin] 为进入专注时的今日剩余
/// 额度（分钟，1:1 于阳光），[elapsed] 为本场会话已走时长。
/// 剩余不足 1 分钟（零头）视为已用尽——与入口页「额度耗尽」同口径。
bool focusQuotaExhausted({
  required Duration elapsed,
  required double remainingMin,
}) {
  if (remainingMin < 1) return true;
  return elapsed.inSeconds >= (remainingMin * 60).round();
}

class FocusPage extends ConsumerStatefulWidget {
  final int plannedMinutes;

  /// 专注期是否启用系统勿扰（DND）屏蔽通知；入口页可选，默认开（F01）。
  final bool dnd;

  /// 自由专注（玄参 2026-09-30 拍板）：**不预设时长、不自动结算**，孩子自己点结束。
  ///
  /// 为 true 时 [plannedMinutes] 透传 0（仅作落库口径标记 `plannedMin=0`，
  /// 结算/成长项/完美日各处 `plannedMin==0` 的既有守卫分支天然兼容）；
  /// 引擎侧改用默认档推导 1/3 报信节奏，且 `freeMode` 关闭「到时自动结算」。
  final bool freeMode;

  /// 从「成长」联动项进入时携带的成长项 id（M4）；自由专注为 null。
  ///
  /// 非空时，本次专注结束后按会话自动结算该成长项（见 [_FocusPageState._handleOutcome]）。
  final String? taskId;

  const FocusPage({
    super.key,
    this.plannedMinutes = kFocusDurationDefaultMinutes,
    this.dnd = true,
    this.freeMode = false,
    this.taskId,
  });

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage>
    with WidgetsBindingObserver {
  late final FocusEngine _engine;
  StreamSubscription<FocusEvent>? _eventSub;
  PresenceDetector? _presence;
  Timer? _ticker;
  Timer? _pulseTimer; // 二档送光脉冲
  Timer? _bubbleTimer; // 气泡/唤醒文案驻留

  FeedbackLevel _level = FeedbackLevel.lvl1;
  WakeIntensity _wake = WakeIntensity.none;
  bool _emitParticle = false;
  bool _welcoming = false;
  bool _absent = false;
  bool _paused = false;
  bool _finished = false;
  String? _bubbleKey;

  /// 进入专注时读到的「今日剩余专注额度」（分钟，1:1 于阳光）；null = 未读到。
  ///
  /// 只用于**轻提示**：额度用完后在专注页左上角弹一次小卡。真正的截断仍在结算侧
  /// （`SunlightService.settle`），本字段不是收口，读到 null 就安静不提示。
  double? _quotaRemainingMin;

  /// 「额度用完」轻提示卡是否正在显示。
  bool _quotaHint = false;

  /// 本场是否已弹过额度提示卡（整场一次，不再重复打扰）。
  bool _quotaHintShownOnce = false;

  /// 轻提示卡自动淡出的计时（UI 层驻留，非额度轮询；见 [kFocusQuotaHintSeconds]）。
  Timer? _quotaHintTimer;

  /// 本次专注会话 id（埋点 focus_session_start/end 关联用，T-B）。
  late final String _sessionId = Uuid().v4();

  /// 当前分龄档（进入时从设置读取，供埋点 payload.tier，T-B）。
  AgeTier _tier = AgeTier.low;

  // ── C28 少儿护眼休息（玄参 2026-10-04 拍板，口径裁定表 v1 C28）──────────────

  /// 进入专注时读到的设置（供护眼判定）：场内触发间隔 / 是否允许孩子跳过都来自它。
  ///
  /// null = 还没读到（首帧 tick 之前），此时**不触发**护眼——宁可晚一秒，
  /// 也绝不用假设置（默认 20 分钟）把还没到点的孩子叫起来休息。
  AppSettings? _eyeCareSettings;

  /// 「距上次护眼的**累计注视**秒数」基准。
  ///
  /// 每次护眼（场内触发 / 场末插入）都把基准回写为「护眼当下的累计注视秒数」，
  /// 于是「下一个间隔从 0 重新累计」这条幂等契约只落在一个字段上，不会出现
  /// 「同一区间反复弹卡」或「基准回退导致又立刻再弹」两种事故。
  int _eyeCareBaselineFocusSeconds = 0;

  /// 护眼卡是否正在展示（展示期间：专注计时暂停、退出确认与场末判定都不再推进）。
  bool _eyeCareActive = false;

  /// 本次专注适用的**每日专注上限**（分钟）：进入时与 [_tier] 一起从设置读取，
  /// 结算时传给 `SunlightService.settle` 做额度截断（2026-09-23 日上限口径）。
  ///
  /// 取 `settings.dailyFocusCap` 而**不是**按 [_tier] 查 `kAgeTierParams`：家长可在
  /// 设置页单独覆盖上限（下拉 60/90/120），按年段查表会忽略这次覆盖。
  /// 初值取最严档，仅在设置读取失败（本机 SQLite 几乎不可能）时才会实际生效。
  int _dailyFocusCap = kDailyFocusCapLow;

  final DndController _dnd = DndController();
  bool _dndHintShown = false;
  bool _dndBanner = false; // 未获勿扰授权时顶部常驻提示条幅（B30）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // B30：监听生命周期以在返回设置后重查 DND
    // 自由专注：plannedMinutes 透传 0（落库标记），引擎改用默认档推导 1/3 报信
    // 节奏（约 8 分钟收一次阳光），并传 freeMode=true 关闭「到时自动结算」。
    _engine = FocusEngine(
      planned: Duration(
        minutes: widget.freeMode
            ? kFocusDurationDefaultMinutes
            : widget.plannedMinutes,
      ),
      freeMode: widget.freeMode,
    );
    _eventSub = _engine.events.listen(_onEvent);
    _enterFocusMode();
    unawaited(_applyDndOnEnter()); // F01：专注开始启用勿扰（如已授权）
    unawaited(_applyAudioOnEnter()); // M2：按设置启动 BGM（如开启）
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_finished) return;
      _engine.tick(DateTime.now());
      // 额度用完轻提示：复用本 tick 判定（玄参 2026-09-30：不另起额度定时器）。
      _maybeShowQuotaHint();
      // C28：场内护眼触发同样复用本 tick（不另起定时器）。
      _maybeTriggerEyeCare();
      if (mounted) setState(() {});
    });
    _presence = PresenceDetector(
      onAbsent: _onAbsent,
      onPresent: _onPresent,
      onPortraitIntent: _requestExit,
      grace: const Duration(seconds: kOrientationGraceSeconds),
    )..start();
    // start() 会同步发出 lvl1 事件；延后到首帧后再启动，避免在 initState 中 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _engine.start();
      unawaited(_trackSessionStart()); // T-B：focus_session_start 埋点
    });
  }

  /// F01：专注开始尝试启用系统勿扰（DND）。
  ///
  /// - 已授权 → 立即生效；
  /// - 未授权 → 跳转系统勿扰权限设置页引导开启，顶部常驻提示条幅；
  ///   用户从设置返回（resumed）后会由 [didChangeAppLifecycleState] 自动重查并启用（B30 修复）。
  Future<void> _applyDndOnEnter() async {
    if (!widget.dnd) return; // 用户关闭勿扰：不处理
    final bool granted = await _dnd.isGranted();
    if (granted) {
      await _dnd.setEnabled(true);
    } else {
      // 引导去系统设置开启勿扰权限；用户回来后 resumed 时自动重查启用（B30）。
      await _dnd.requestAccess();
      if (mounted) setState(() => _dndBanner = true);
      if (mounted && !_dndHintShown) {
        _dndHintShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请在系统设置中开启勿扰权限以屏蔽通知'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// M2：进入专注时按设置装配音频——应用 soundOn/bgmOn。
  ///
  /// 玄参 2026-09-30 拍板：**专注中不放任何背景音乐**（真机反馈「没有声音反而
  /// 更好，有声音反而是打扰」）→ 不再调用 `startBgm`（`focus_loop.mp3` 资产保留
  /// 但不使用）；SFX（收集 / 欢迎回来 / 唤醒）仍按 soundOn 生效。
  Future<void> _applyAudioOnEnter() async {
    final AppSettings s = await ref.read(settingsRepositoryProvider).getSettings();
    if (!mounted) return;
    _tier = s.ageTier; // T-B：记录档位供埋点
    _dailyFocusCap = s.dailyFocusCap; // 日上限口径：结算按此截断
    // C28：护眼判定用设置（总开关 / 触发间隔 / 是否允许跳过）。
    _eyeCareSettings = s;
    ref.read(audioServiceProvider).applySettings(soundOn: s.soundOn, bgmOn: s.bgmOn);
    // 顺带读「今日剩余额度」供轻提示判定（与结算同源的账本口径）。
    try {
      final double remaining = await ref
          .read(sunlightServiceProvider)
          .focusRemainingToday(s.dailyFocusCap, DateTime.now());
      if (!mounted) return;
      setState(() => _quotaRemainingMin = remaining);
    } catch (_) {
      // 读不到就不提示（正确性由结算侧截断兜底，绝不用假数据打扰孩子）。
    }
  }

  /// 额度用完 → 轻弹一次提示卡（左上角，不遮挡居中的向日葵）。
  ///
  /// 只在**尚未提示过**且本场已专注时长达到进入时的剩余额度时触发一次；
  /// 判定挂在既有秒级 tick 上，**不新增额度定时器**（玄参 2026-09-30）。
  void _maybeShowQuotaHint() {
    if (_quotaHint || _quotaHintShownOnce) return;
    final double? remaining = _quotaRemainingMin;
    if (remaining == null) return;
    if (!focusQuotaExhausted(
      elapsed: _engine.elapsed,
      remainingMin: remaining,
    )) {
      return;
    }
    _quotaHintShownOnce = true; // 整场只弹一次
    setState(() => _quotaHint = true);
    _quotaHintTimer?.cancel();
    _quotaHintTimer = Timer(
      const Duration(seconds: kFocusQuotaHintSeconds),
      () {
        if (mounted) setState(() => _quotaHint = false);
      },
    );
  }


  Future<void> _enterFocusMode() async {
    // 常亮保持（P6 风险：国内 ROM 省电可能杀常亮，待真机验证）
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    // 锁横屏 + 隐藏系统 UI（沉浸）
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  // ── C28 护眼休息（口径裁定表 v1 C28 §1 / §7）──────────────────────────
  /// 场内「累计注视每满 N 分钟」→ 弹出护眼卡。
  ///
  /// 挂在既有 1 秒 tick 上判定，**不新增定时器**（与「额度用完轻提示」同口径）。
  /// 到点后：
  ///  · `_engine.pause()` —— **护眼期间专注计时冻结**（这才是「护眼不计入专注时长」的
  ///    唯一实现：不用结算补减，避免「暂停 + 结算时补减」两条口径打架）；
  ///  · 护眼 60 秒**不产专注阳光**（引擎 paused 状态本来就不累加 `_sunlight`）；
  ///  · 护眼结束 `_engine.resume()` 并把 [\_eyeCareBaselineFocusSeconds] 回写为
  ///    触发当下的累计注视秒数 → 下一个间隔从 0 重新累计。
  ///
  /// 无论孩子是「完成休息」还是「确认跳过」，护眼时长都**不回溯补算**为专注时长
  /// （计时已被暂停，不做任何补减）。
  void _maybeTriggerEyeCare() {
    if (_finished || _eyeCareActive) return; // 已结束 / 护眼卡正在展示
    final AppSettings? s = _eyeCareSettings;
    if (s == null || !EyeCareService.isEnabled(s)) return;
    if (_engine.state != FocusEngineState.running) return; // 离席 / 退出确认中不动

    final int presentSeconds = (_engine.actualFocusMin * 60).round();
    if (!EyeCareService.shouldTriggerInSession(
      focusElapsedSeconds: presentSeconds,
      lastEyeCareAtSecond: _eyeCareBaselineFocusSeconds,
      settings: s,
    )) {
      return;
    }
    unawaited(_openEyeCare(focusSecondsAtTrigger: presentSeconds));
  }

  /// 弹出护眼卡并等它结束。
  ///
  /// [focusSecondsAtTrigger] 是**触发当下**的累计注视秒数，护眼结束后用它回写基准，
  /// 保证「护眼这一段」被算进基准、不会被下一秒的 tick 当成「又积累了一秒」。
  Future<void> _openEyeCare({required int focusSecondsAtTrigger}) async {
    // 只有 `isEnabled` 判定通过的那条路径会走到这里，故设置必定已读到（非空）。
    final AppSettings settings = _eyeCareSettings!;
    _engine.pause(); // 护眼期间计时暂停 → 不计入专注时长（C28 §1）
    if (mounted) setState(() => _eyeCareActive = true);

    // 护眼奖励以**阳光账本为唯一真源**，在 EyeCarePage 内部就已入账，这里只收尾状态，
    // 绝不（也不允许）再写一次账本，否则一次护眼会变成 +4 阳光。
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EyeCarePage(
          args: EyeCareArgs(
            skipAllowed: EyeCareService.isSkipAllowed(settings),
          ),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _eyeCareActive = false);
    // 幂等基准：下一个间隔从护眼当下重新累计（跳过也一样，避免立刻再弹卡）。
    _eyeCareBaselineFocusSeconds =
        EyeCareService.baselineAfterTrigger(focusSecondsAtTrigger);
    _engine.resume();
  }

  /// 本场结束时「距上次护眼后的本段注视」是否达到场末插入门槛（≥ [kEyeCareSessionEndMinutes]）。
  ///
  /// 真值 → 结算页会**先**插一次护眼卡、再领奖励（先护眼、后领奖励，防孩子为拿奖励
  /// 跳过护眼）；不满足则不打断，交给「每 2 场休 10 分钟」的大休息兜底。
  bool _shouldEyeCareAtSessionEnd() {
    final AppSettings? s = _eyeCareSettings;
    if (s == null || !EyeCareService.isEnabled(s)) return false;
    return EyeCareService.shouldTriggerAtSessionEnd(
      focusElapsedSeconds: (_engine.actualFocusMin * 60).round(),
      lastEyeCareAtSecond: _eyeCareBaselineFocusSeconds,
    );
  }

  /// 【仅 debug 构建】快进场内专注时长（玄参 2026-10-04：方便调试 C28 护眼触发，
  /// 免去真等 5~15 分钟）。实现＝把引擎时间基准整体前移 [minutes] 分钟：
  /// `tick(now + Δ)` 让 `_advance` 把 (Δ) 计入 `_sessionElapsed`/`_focusSeconds`
  /// （阳光产出同步按elapsed走），随后真实 tick 的 dt 为负被 `dt > Duration.zero`
  /// 守卫跳过并回归真实时钟——**单次精确 +Δ、不重复累计**。
  ///
  /// release 包不存在该按钮（kDebugMode 门控），领域层零改动。
  void _debugFastForward({int minutes = 5}) {
    if (!kDebugMode || _finished) return;
    if (_eyeCareActive) return; // 护眼卡展示中引擎已暂停，跳过避免干扰恢复基准
    _engine.tick(DateTime.now().add(Duration(minutes: minutes)));
    _maybeShowQuotaHint();
    _maybeTriggerEyeCare(); // 立即判定（不等下一个 1s tick）
    if (mounted) setState(() {});
  }

  // ── 引擎事件 → 四档呈现 ───────────────────────────────────────
  void _onEvent(FocusEvent event) {
    if (event.isFinished) {
      _handleOutcome(event.outcome!);
      return;
    }
    if (!mounted) return;
    switch (event.level) {
      case FeedbackLevel.lvl1:
        setState(() {
          _level = FeedbackLevel.lvl1;
          _wake = WakeIntensity.none;
        });
      case FeedbackLevel.lvl2:
        setState(() => _level = FeedbackLevel.lvl2);
        _pulseParticle();
        _showBubble(event.textKey);
        ref.read(audioServiceProvider).playSfx(AudioCue.focusCollect); // 收集阳光序列帧配音
      case FeedbackLevel.lvl3:
        setState(() {
          _level = FeedbackLevel.lvl3;
          _welcoming = true;
        });
        _clearWelcomeAfter(const Duration(seconds: 3)); // B27：欢迎光晕延长至 3 秒
        ref.read(audioServiceProvider).playSfx(AudioCue.welcomeBack); // M2：「欢迎回来」
      case FeedbackLevel.lvl4:
        setState(() {
          _level = FeedbackLevel.lvl4;
          _wake = event.wakeIntensity;
        });
        _showBubble(event.textKey);
        ref.read(audioServiceProvider).playSfx(AudioCue.wake); // M2：唤醒提示音
    }
  }

  void _pulseParticle() {
    _pulseTimer?.cancel();
    setState(() => _emitParticle = true);
    _pulseTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _emitParticle = false);
    });
  }

  void _showBubble(String? textKey) {
    if (textKey == null) return;
    _bubbleTimer?.cancel();
    setState(() => _bubbleKey = textKey);
    _bubbleTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _bubbleKey = null);
    });
  }

  void _clearWelcomeAfter(Duration d) {
    Timer(d, () {
      if (mounted) setState(() => _welcoming = false);
    });
  }

  // ── 在场检测回调 ──────────────────────────────────────────────
  void _onAbsent() {
    _engine.onAbsent();
    if (mounted) setState(() => _absent = true);
  }

  void _onPresent() {
    _engine.onPresent();
    if (mounted) setState(() => _absent = false);
  }

  // ── 退出路径（B18 / B20）─────────────────────────────────────
  /// 退出意图统一入口：物理竖屏与系统返回键**共用**，行为一致（暂停 + 确认框）。
  void _requestExit() {
    // C28：护眼卡展示期间不接受「结束专注」——退出确认会把专注计时一起冻住，
    // 而护眼结束后的 resume 又被弹窗抢先，容易把计时留在 paused 态。
    if (_finished || _paused || _eyeCareActive) return;
    setState(() => _paused = true);
    _engine.pause();
    _showExitConfirm();
  }

  void _showExitConfirm() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('确定结束吗？'),
        content: const Text('向日葵还在这儿陪着你，要现在结束专注吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resume();
            },
            child: const Text('再坐一会'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _engine.stop(); // 手动结束 → 引擎发 finished → 结算
            },
            child: const Text('结束'),
          ),
        ],
      ),
    );
  }

  void _resume() {
    _engine.resume();
    if (mounted) setState(() => _paused = false);
  }

  // ── 结算 ─────────────────────────────────────────────────────
  Future<void> _handleOutcome(FocusOutcome outcome) async {
    if (_finished) return;
    _finished = true;
    unawaited(_trackSessionEnd(outcome)); // T-B：focus_session_end 埋点
    _ticker?.cancel();
    _pulseTimer?.cancel();
    _bubbleTimer?.cancel();
    _quotaHintTimer?.cancel();
    _presence?.stop();
    await _dnd.setEnabled(false); // F01：退出专注恢复通知
    await _restoreSystemChrome();

    final DateTime start = _engine.startedAt ?? DateTime.now();
    final FocusSettlement settlement =
        await ref.read(sunlightServiceProvider).settle(
              outcome: outcome,
              start: start,
              end: DateTime.now(),
              plannedMin: widget.plannedMinutes,
              // 日上限口径（2026-09-23）：按年段每日专注上限硬截断本次产出。
              dailyFocusCap: _dailyFocusCap,
            );

    // M4：联动成长项自动结算（仅从「成长」进入的专注带 taskId）。
    //
    // 纪律：此处任何失败 / 取不到会话 **都不影响「专注本身已成功」**（专注阳光已由上面的
    // settle 入账），只影响该成长项，故一律降级为非阻塞提示，**绝不回滚、绝不报错页**。
    TaskCheckInOutcome? taskOutcome;
    String? taskName;
    bool taskSettleSkipped = false;
    final String? taskId = widget.taskId;
    if (taskId != null) {
      try {
        final List<Task> tasks = await ref.read(taskRepositoryProvider).tasks();
        Task? task;
        for (final Task x in tasks) {
          if (x.id == taskId) {
            task = x;
            break;
          }
        }
        if (task != null) {
          taskName = task.name;
          // 取**真实落库**的会话对象（settle 内部已 saveSession），按 sessionId 精确匹配，
          // 绝不自造假会话（后端结算会校验 sessionId）。
          final List<FocusSession> todaySessions = await ref
              .read(focusRepositoryProvider)
              .sessionsOfDay(dayKey(DateTime.now()));
          FocusSession? session;
          for (final FocusSession s in todaySessions) {
            if (s.id == settlement.sessionId) {
              session = s;
              break;
            }
          }
          if (session == null) {
            taskSettleSkipped = true; // 兜底：正常不应发生
          } else {
            taskOutcome = await ref
                .read(taskCheckInServiceProvider)
                .settleFocusLinked(
                  task: task,
                  session: session,
                  now: DateTime.now(),
                );
            // 达标入账后自增经济修订号 → 孩子端「成长 / 今日」下次进入即自动打勾。
            if (taskOutcome.status == CheckInStatus.verified) {
              ref.read(economyRevisionProvider.notifier).state++;
            }
          }
        }
      } catch (_) {
        // 成长项结算异常不影响专注成功：仅标记跳过（见上方纪律）。
        taskSettleSkipped = true;
      }
    }

    if (!mounted) return;
    // go 是替换路由栈（B20）；结算页经 go 进入，退出用 go('/')。
    //
    // C28 §1 场末：若「距上次护眼之后的本段注视 ≥ [kEyeCareSessionEndMinutes] 分钟」，
    // 结算页会**在显示任何奖励之前**先插一次护眼卡（先护眼、后领奖励）。
    context.go(
      '/settle',
      extra: SettleArgs(
        settlement: settlement,
        taskOutcome: taskOutcome,
        taskName: taskName,
        taskSettleSkipped: taskSettleSkipped,
        eyeCarePending: _shouldEyeCareAtSessionEnd(),
      ),
    );
  }

  Future<void> _restoreSystemChrome() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    try {
      await SystemChrome.setPreferredOrientations([]); // 复位方向
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}
  }

  // ── T-B 埋点（仅新增，不重构既有逻辑）─────────────────────────

  /// focus_session_start：引擎启动后上报（会话 id / 计划时长 / 档位）。
  Future<void> _trackSessionStart() async {
    try {
      await ref.read(trackingRepositoryProvider).track(TrackingEvent(
        id: Uuid().v4(),
        name: TrackingEventNames.focusSessionStart,
        type: TrackingType.metric,
        ts: DateTime.now(),
        payload: {
          'session_id': _sessionId,
          'planned_min': widget.plannedMinutes,
          'tier': _tier.name,
        },
      ));
    } catch (_) {}
  }

  /// focus_session_end：结算时上报（会话 id / 实际时长 / 结束原因 / 档位）。
  Future<void> _trackSessionEnd(FocusOutcome outcome) async {
    try {
      await ref.read(trackingRepositoryProvider).track(TrackingEvent(
        id: Uuid().v4(),
        name: TrackingEventNames.focusSessionEnd,
        type: TrackingType.metric,
        ts: DateTime.now(),
        payload: {
          'session_id': _sessionId,
          'actual_min': outcome.actualFocusMin,
          'reason': outcome.endReason.name,
          'tier': _tier.name,
        },
      ));
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // B30：移除生命周期监听
    _ticker?.cancel();
    _pulseTimer?.cancel();
    _bubbleTimer?.cancel();
    _quotaHintTimer?.cancel();
    _eventSub?.cancel();
    _presence?.stop();
    _engine.dispose();
    // M2：退出专注释放音频播放器（下次使用懒加载重建）。专注中已不放 BGM
    // （玄参 2026-09-30 拍板），这里只负责释放 SFX 播放器。
    unawaited(ref.read(audioServiceProvider).dispose());
    // F01：万一 _handleOutcome 未跑（如进程被杀），退出时仍尝试恢复通知。
    unawaited(_dnd.setEnabled(false));
    _restoreSystemChrome();
    super.dispose();
  }

  /// B30：从系统设置返回后，若已获勿扰授权则自动启用；否则常驻提示条幅。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.dnd && !_finished && !_paused) {
      _reapplyDndIfGranted();
    }
  }

  Future<void> _reapplyDndIfGranted() async {
    final bool granted = await _dnd.isGranted();
    if (!mounted) return;
    if (granted) {
      await _dnd.setEnabled(true);
      setState(() => _dndBanner = false);
    } else {
      setState(() => _dndBanner = true);
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final Duration elapsed = _engine.elapsed;
    final Duration planned = _engine.planned;

    // 打盹屏经 go('/focus') 进入 = 路由栈底，不拦的话 Android 返回键会直接退出 App。
    // 按架构 §1.3 / M0 §7 约定，「手动退出」与物理竖屏同路：暂停 + 确认框。
    // 2026-09-30 重排（玄参反馈「叠了、花太大」）：改用「三段式 Column」——
    // 顶部计时区 / 中部向日葵(flex 自适应) / 底部提示胶囊，三段互不重叠；
    // 向日葵在 Expanded 内按可用高度动态缩放（参考 Forest / 番茄ToDo：
    // 时间在上、图案居中、提示沉底，分区清晰）。
    final bool showBanner = _dndBanner && widget.dnd && !_finished;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _requestExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF141426), // 低亮深色打盹屏底（渐变最深处）
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 背景：深蓝紫微渐变（顶部略亮的夜空感）。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF262647),
                    Color(0xFF1B1B2F),
                    Color(0xFF141426),
                  ],
                  stops: <double>[0.0, 0.5, 1.0],
                ),
              ),
            ),
            // 【仅 debug 构建】护眼调试角标：每次点击快进 5 分钟场内时长，
            // 用于真机/模拟器免等待验证 C28 护眼触发节奏（release 无此按钮）。
            if (kDebugMode && !_finished)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: '调试：快进 5 分钟（护眼触发用）',
                  icon: const Icon(
                    Icons.bug_report,
                    color: Color(0x55FFFFFF),
                    size: 28,
                  ),
                  onPressed: () => _debugFastForward(),
                ),
              ),
            // 主三段式结构：计时 / 向日葵 / 提示。SafeArea 避开刘海/圆角。
            SafeArea(
              top: false,
              child: Column(
                children: [
                  // 为顶部 DND 条幅预留等高占位（条幅绝对定位于 Stack 顶层）。
                  SizedBox(height: showBanner ? 48 : 0),
                  const SizedBox(height: 16),
                  // 顶部计时区（参考潮汐：大数字 + 极简层级）。
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.freeMode ? '自由专注' : '本次专注',
                        style: const TextStyle(
                          color: Color(0xFF9E9ECF),
                          fontSize: 14,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _fmt(elapsed),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2,
                            ),
                          ),
                          // 自由专注不显示「/ 计划时长」——没有倒计时压力，
                          // 只看已经专注了多久（玄参 2026-09-30）。
                          if (!widget.freeMode) ...<Widget>[
                            const SizedBox(width: 10),
                            Text(
                              '/ ${_fmt(planned)}',
                              style: const TextStyle(
                                color: Color(0xFF8A8AA3),
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 中部向日葵：占满剩余空间并居中，按容器高度自适应缩放，不溢出/不重叠。
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext ctx, BoxConstraints constraints) {
                        final double s =
                            constraints.biggest.height.clamp(110.0, 230.0);
                        // 以向日葵为中心的 s×s 子 Stack：气泡锚在**向日葵头右上旁**，
                        // 而不是贴屏幕右缘（玄参 2026-09-30：太远不像向日葵说的话）。
                        return Center(
                          child: SizedBox(
                            width: s,
                            height: s,
                            child: Stack(
                              clipBehavior: Clip.none, // 气泡可越出 s×s 界（仍在区内）
                              alignment: Alignment.center,
                              children: [
                                FocusSunflowerStage(
                                  collectSignal: _emitParticle,
                                  returnSignal: _welcoming,
                                  size: s,
                                ),
                                // B27：三档「欢迎回来」改为说话气泡，与二档/四档统一由
                                // 气泡层渲染（玄参 2026-09-30 拍板，取代原顶部金色大字）。
                                // 位置：花头右上外沿（left 0.92s 略越帧缘、top 0.04s 贴花顶），
                                // 尾巴左下指向花心，不遮挡角色。
                                if (_bubbleKey != null || _welcoming)
                                  Positioned(
                                    top: s * 0.04,
                                    left: s * 0.92,
                                    child: FeedbackOverlay(
                                      level: _level,
                                      wakeIntensity: _wake,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 底部提示胶囊。
                  const _FocusHintChip(),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            // 额度用完 · 轻提示卡（玄参 2026-09-30）：锚在**左上角**，向日葵居中，
            // 二者互不重叠；淡入驻留 [kFocusQuotaHintSeconds] 秒后自动淡出，整场一次。
            if (_quotaHintShownOnce)
              Positioned(
                top: showBanner ? 56 : 10,
                left: 14,
                child: IgnorePointer(
                  ignoring: !_quotaHint,
                  child: AnimatedOpacity(
                    opacity: _quotaHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 320),
                    child: const _FocusQuotaHintCard(),
                  ),
                ),
              ),
            // B30：未获勿扰授权时的顶部常驻提示条幅。
            if (showBanner)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: const Color(0xFF5D4037),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '未开启勿扰，通知仍会打扰',
                          style: TextStyle(color: Color(0xFFFFE082), fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _dnd.requestAccess();
                          unawaited(_reapplyDndIfGranted());
                        },
                        child: const Text(
                          '去开启',
                          style: TextStyle(color: Color(0xFFFFE082)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 离席降亮（灭屏=离席；离席产出停止，不扣减，PRD §4.3 / §4.1.5）
            if (_absent)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                child: const Text(
                  '向日葵在等你回来',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 18),
                ),
              ),
            // 暂停遮罩（退出确认）
            if (_paused)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Text('已暂停',
                      style: TextStyle(color: Colors.white, fontSize: 28)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「今日专注额度用完」轻提示卡（玄参 2026-09-30）。
///
/// 设计取向：**温和报信，不催不停**——自由专注下孩子自己决定何时结束，这里只
/// 说明「额度用完了、超出部分不再有阳光」，不打断、不弹窗、不遮挡向日葵。
class _FocusQuotaHintCard extends StatelessWidget {
  const _FocusQuotaHintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9B8).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black26, blurRadius: 8),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('🌻', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '今天的专注额度用完啦，剩下的时间不再收集阳光，累了随时可以结束哦',
              style: TextStyle(
                color: Color(0xFF5D4037),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部提示胶囊（玄参 2026-09-30「提示文字美化」）：
/// 低饱和小字 + 半透明白圆角胶囊 + 🌻 点缀，弱化存在感但不消失。
class _FocusHintChip extends StatelessWidget {
  const _FocusHintChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌻', style: TextStyle(fontSize: 12)),
          SizedBox(width: 8),
          Text(
            '本屏不可交互 · 竖屏即可结束',
            style: TextStyle(
              color: Color(0xFF8A8AA3),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
