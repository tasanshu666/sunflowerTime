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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/presence_detector.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/dnd_controller.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/widgets/feedback_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

class FocusPage extends ConsumerStatefulWidget {
  final int plannedMinutes;

  /// 专注期是否启用系统勿扰（DND）屏蔽通知；入口页可选，默认开（F01）。
  final bool dnd;

  /// 从「成长」联动项进入时携带的成长项 id（M4）；自由专注为 null。
  ///
  /// 非空时，本次专注结束后按会话自动结算该成长项（见 [_FocusPageState._handleOutcome]）。
  final String? taskId;

  const FocusPage({
    super.key,
    this.plannedMinutes = kFocusDurationDefaultMinutes,
    this.dnd = true,
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

  /// 本次专注会话 id（埋点 focus_session_start/end 关联用，T-B）。
  late final String _sessionId = Uuid().v4();

  /// 当前分龄档（进入时从设置读取，供埋点 payload.tier，T-B）。
  AgeTier _tier = AgeTier.low;

  final DndController _dnd = DndController();
  bool _dndHintShown = false;
  bool _dndBanner = false; // 未获勿扰授权时顶部常驻提示条幅（B30）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // B30：监听生命周期以在返回设置后重查 DND
    _engine = FocusEngine(planned: Duration(minutes: widget.plannedMinutes));
    _eventSub = _engine.events.listen(_onEvent);
    _enterFocusMode();
    unawaited(_applyDndOnEnter()); // F01：专注开始启用勿扰（如已授权）
    unawaited(_applyAudioOnEnter()); // M2：按设置启动 BGM（如开启）
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_finished) return;
      _engine.tick(DateTime.now());
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

  /// M2：进入专注时按设置装配音频——应用 soundOn/bgmOn，开启则启动 BGM 循环。
  Future<void> _applyAudioOnEnter() async {
    final AppSettings s = await ref.read(settingsRepositoryProvider).getSettings();
    if (!mounted) return;
    _tier = s.ageTier; // T-B：记录档位供埋点
    final AudioService audio = ref.read(audioServiceProvider);
    audio.applySettings(soundOn: s.soundOn, bgmOn: s.bgmOn);
    if (s.bgmOn) unawaited(audio.startBgm());
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
        ref.read(audioServiceProvider).playSfx(AudioCue.progress); // M2：送光提示音
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
    if (_finished || _paused) return; // 已在确认中/已结束则不重复弹
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
    context.go(
      '/settle',
      extra: SettleArgs(
        settlement: settlement,
        taskOutcome: taskOutcome,
        taskName: taskName,
        taskSettleSkipped: taskSettleSkipped,
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
    _eventSub?.cancel();
    _presence?.stop();
    _engine.dispose();
    // M2：退出专注停止并释放音频播放器（下次进入懒加载重建）。
    unawaited(ref.read(audioServiceProvider).stopBgm());
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
    final double progress = planned.inMicroseconds == 0
        ? 0
        : (elapsed.inMicroseconds / planned.inMicroseconds).clamp(0.0, 1.0);

    // 打盹屏经 go('/focus') 进入 = 路由栈底，不拦的话 Android 返回键会直接退出 App。
    // 按架构 §1.3 / M0 §7 约定，「手动退出」与物理竖屏同路：暂停 + 确认框。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _requestExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B1B2F), // 低亮深色打盹屏底
      body: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
            // 中央：在做自己事的花（呼吸式明暗，零突事件）
            SunflowerCanvas(
              level: _level,
              emitParticle: _emitParticle,
              progress: progress,
              welcoming: _welcoming,
            ),
            // B30：未获勿扰授权时的顶部常驻提示条幅（用户从设置返回后自动消失）。
            if (_dndBanner && widget.dnd && !_finished)
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
            // 顶部：只留本次倒计时（不显示阳光池数字，PRD §4.2）
            // B30：顶部出现 DND 提示条幅时，倒计时下移避免遮挡。
            Positioned(
              top: _dndBanner && widget.dnd && !_finished ? 56 : 24,
              left: 0,
              right: 0,
              child: Text(
                '本次 ${_fmt(elapsed)} / ${_fmt(planned)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 22,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            // B27：三档「欢迎回来」文字（亮屏瞬间补判），与离席遮罩区分，2–3 秒后消失。
            if (_welcoming)
              const Positioned(
                top: 76,
                left: 0,
                right: 0,
                child: Text(
                  '欢迎回来',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // 底部：本屏不可交互提示
            const Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Text(
                '本屏不可交互 · 竖屏即可结束',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF616161), fontSize: 14),
              ),
            ),
            // 二档/四档气泡层（lvl1/lvl3 不出气泡）
            if (_bubbleKey != null)
              FeedbackOverlay(level: _level, wakeIntensity: _wake),
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
