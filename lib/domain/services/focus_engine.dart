/// 专注引擎 FocusEngine（T06）。
///
/// 职责：计时 / 在场 / 产出速率 / 最短结算时长 / 四档反馈事件（PRD §4.1.3–§4.1.6、§6.2）。
///
/// 设计约束：
/// - **纯 Dart，零 Flutter 依赖**（架构 §3）——可被 `dart test` 直接测试；
/// - 时间由外部 `tick(now)` 驱动，**不内部起 Timer**——单测可完全控制时间轴；
/// - 状态机：idle → running → (absent | paused) → finished；
/// - 产出规则（§4.1.5）：在场 1 阳光/分钟；离席停产出且不扣减；
///   恢复在场自检测时刻起 10 秒线性回满，离席窗口不补产出。
///
/// 口径真源：`docs/口径裁定表_v1.md` > `docs/MVP执行规划_v2.md` > PRD v2.0。
library focus_engine;

import 'dart:async';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

/// 四档反馈档位（PRD §4.1.3 一~四档 与 §4.1.4 L0–L3 为同一套，工程统一命名 lvl1..lvl4）。
///
/// 定义于领域层以保持引擎零 Flutter 依赖；`sunflower_canvas.dart` 通过 export 复用同一枚举。
enum FeedbackLevel {
  lvl1, // 一档 · 常态产光：全程默认态，无声
  lvl2, // 二档 · 随光报信：每完成 1/3 送一粒光 + 气泡（只报信不夸奖）
  lvl3, // 三档 · 欢迎回来：离席后恢复在场，纯视觉光晕（无声）
  lvl4, // 四档 · 唤醒提醒：离席持续超阈值，睁眼说软话（语音）
}

/// lvl4 唤醒强度（PRD §4.1.4）：轻声 / 加重。
enum WakeIntensity {
  none, // 非唤醒态
  gentle, // 轻声（离席 90s）
  strong, // 加重（离席 180s）
}

/// 专注结束原因（PRD §4.1.4 / §6.2）。
enum FocusEndReason {
  timedOut, // 到时正常结束
  interrupted, // 离席累计超时自然结束（打断）
  manual, // 手动 / 竖屏结束
}

/// 引擎状态机。
enum FocusEngineState {
  idle, // 未开始
  running, // 专注中（在场）
  absent, // 离席（灭屏 / 离开，强判定）
  paused, // 已暂停（退出确认 / 手动暂停）
  finished, // 已结束
}

/// 单条反馈事件（对外经 `Stream<FocusEvent>` 与 `eventHistory` 暴露）。
class FocusEvent {
  /// 所属档位（lvl1..lvl4）。
  final FeedbackLevel level;

  /// lvl4 的唤醒强度（其余档位恒为 [WakeIntensity.none]）。
  final WakeIntensity wakeIntensity;

  /// 文案 key（供 UI 映射台词，文案真源见 PRD §4.1.3/§4.1.4）。
  final String? textKey;

  /// 结束事件携带的结算产出（非结束事件为 null）。
  final FocusOutcome? outcome;

  const FocusEvent({
    required this.level,
    this.wakeIntensity = WakeIntensity.none,
    this.textKey,
    this.outcome,
  });

  /// 是否为结束事件。
  bool get isFinished => outcome != null;
}

/// 一次专注的结算产出。
class FocusOutcome {
  /// 实际专注分钟（在场累计，含恢复回满窗口；不含离席/暂停）。
  final double actualFocusMin;

  /// 原始产出阳光（未过软顶；短于最短结算时长时为 0）。
  final double rawSunlight;

  /// 结算状态（completed / shortAborted）。
  final FocusStatus status;

  /// 结束原因。
  final FocusEndReason endReason;

  /// 本场唤醒次数（L2+L3 合计）。
  final int wakeCount;

  /// 本场「加重」次数（L3）。
  final int strongWakeCount;

  const FocusOutcome({
    required this.actualFocusMin,
    required this.rawSunlight,
    required this.status,
    required this.endReason,
    required this.wakeCount,
    required this.strongWakeCount,
  });

  /// 是否为被动打断结束。
  bool get interrupted => endReason == FocusEndReason.interrupted;

  @override
  String toString() =>
      'FocusOutcome(actual=${actualFocusMin.toStringAsFixed(2)}min, '
      'raw=$rawSunlight, status=${status.name}, reason=${endReason.name})';
}

/// 专注引擎（用例级领域服务）。
class FocusEngine {
  /// [planned] 计划时长；[clock] 时钟注入（默认 [DateTime.now]，单测可注入假时钟）。
  FocusEngine({required Duration planned, DateTime Function()? clock})
      : _planned = planned,
        _clock = clock ?? DateTime.now;

  final Duration _planned;
  final DateTime Function() _clock;

  final StreamController<FocusEvent> _controller =
      StreamController<FocusEvent>.broadcast();
  final List<FocusEvent> _history = <FocusEvent>[];

  FocusEngineState _state = FocusEngineState.idle;
  DateTime? _startedAt;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// 会话推进时长（running + absent；暂停不计）。
  Duration _sessionElapsed = Duration.zero;

  /// 当前离席窗口已持续时长。
  Duration _absentElapsed = Duration.zero;

  /// 在场累计秒数（用于 actualFocusMin 与最短结算判定）。
  double _focusSeconds = 0;

  /// 原始产出阳光累计。
  double _sunlight = 0;

  /// 恢复回满起点（null 表示当前为满速）。
  DateTime? _resumeFrom;

  final Set<int> _emittedBoundaries = <int>{};
  int _wakeCount = 0;
  int _strongWakeCount = 0;
  bool _gentleFiredThisWindow = false;
  bool _strongFiredThisWindow = false;
  FocusOutcome? _outcome;
  bool _disposed = false;

  // ── 只读访问器 ────────────────────────────────────────────────
  /// 事件流（广播，供 UI 订阅）。
  Stream<FocusEvent> get events => _controller.stream;

  /// 已发生事件的历史（同步可读，便于单测断言）。
  List<FocusEvent> get eventHistory => List<FocusEvent>.unmodifiable(_history);

  FocusEngineState get state => _state;
  Duration get planned => _planned;
  Duration get elapsed => _sessionElapsed;

  /// 剩余时长（不小于 0）。
  Duration get remaining {
    final r = _planned - _sessionElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// 原始产出阳光（未过软顶）。
  double get sunlight => _sunlight;

  /// 实际专注分钟。
  double get actualFocusMin => _focusSeconds / 60.0;

  DateTime? get startedAt => _startedAt;
  FocusOutcome? get outcome => _outcome;
  bool get isFinished => _state == FocusEngineState.finished;
  bool get isAbsent => _state == FocusEngineState.absent;

  // ── 状态迁移 ──────────────────────────────────────────────────

  /// 开始专注（idle → running）。
  void start([DateTime? now]) {
    if (_state != FocusEngineState.idle) return;
    final t = now ?? _clock();
    _startedAt = t;
    _lastTick = t;
    _state = FocusEngineState.running;
    _emit(const FocusEvent(level: FeedbackLevel.lvl1));
  }

  /// 推进时间到 [now]。应由外部定时器（默认 1s）或在测试中手动调用。
  void tick(DateTime now) => _advance(now);

  /// 把会话推进到 [now]：按**当前状态**结算区间 [_lastTick, now] 的时长归属，
  /// 再更新 [_lastTick] 并做到时判定。`tick` 与 `onAbsent`/`onPresent` 共用，
  /// 保证「离席窗口即便一个 tick 都没发生（ticker 被系统挂起）」也不会在恢复后
  /// 被错记为 running（P1 缺陷修复）。
  void _advance(DateTime now) {
    if (_state == FocusEngineState.idle || _state == FocusEngineState.finished) {
      return;
    }

    final DateTime from = _lastTick;
    final Duration dt = now.difference(from);

    if ((_state == FocusEngineState.running ||
            _state == FocusEngineState.absent) &&
        dt > Duration.zero) {
      final double dtSec = dt.inMicroseconds / 1e6;
      _sessionElapsed += dt;
      if (_state == FocusEngineState.running) {
        _focusSeconds += dtSec;
        _sunlight += _presentGain(from, now);
      } else {
        // 离席：产出停止，不扣减已有产出（§4.1.5）。
        _absentElapsed += dt;
      }
      _checkBoundaries();
      if (_state == FocusEngineState.absent) {
        _checkWake();
      }
    }

    _lastTick = now;

    // 到时正常结束（PRD §4.1.2）。离席不冻结会话时钟（暂停会冻结，见 pause）。
    if ((_state == FocusEngineState.running ||
            _state == FocusEngineState.absent) &&
        _sessionElapsed >= _planned) {
      finish(FocusEndReason.timedOut);
    }
  }

  /// 检测到恢复在场（亮屏 / 回到打盹屏）：进入 10 秒线性回满，并发 lvl3 欢迎回来。
  ///
  /// 入口先 [_advance] 结算**整段离席窗口**（即便期间无 tick），据此触发唤醒/打断——
  /// 修复「离席满 300s 但因 ticker 挂起未打断」的 P1 缺陷。
  void onPresent([DateTime? now]) {
    if (_state != FocusEngineState.absent) return;
    final DateTime t = now ?? _clock();
    _advance(t);
    if (_state != FocusEngineState.absent) return; // 离席满 300s 已在 _advance 内打断
    _state = FocusEngineState.running;
    _resumeFrom = t;
    _absentElapsed = Duration.zero;
    _gentleFiredThisWindow = false;
    _strongFiredThisWindow = false;
    _lastTick = t;
    _emit(const FocusEvent(level: FeedbackLevel.lvl3));
  }

  /// 检测到离席（灭屏 / 离开，强判定 PRD §4.3 / §6.2）：产出停止，不扣减。
  ///
  /// 入口先 [_advance] 结算「截至离席时刻」的在场时长，再切状态——修复「恢复后首帧 tick
  /// 把整段离席时长当作 running 吞入」的 P1 缺陷。
  void onAbsent([DateTime? now]) {
    if (_state != FocusEngineState.running) return;
    final DateTime t = now ?? _clock();
    _advance(t);
    if (_state != FocusEngineState.running) return; // 已到时结束
    _state = FocusEngineState.absent;
    _absentElapsed = Duration.zero;
    _gentleFiredThisWindow = false;
    _strongFiredThisWindow = false;
    _lastTick = t;
  }

  /// 手动暂停（退出确认框弹出时调用，冻结会话时钟）。
  void pause() {
    if (_state == FocusEngineState.running || _state == FocusEngineState.absent) {
      _state = FocusEngineState.paused;
    }
  }

  /// 从暂停恢复（取消退出确认）。冻结窗口不计入会话与产出。
  void resume([DateTime? now]) {
    if (_state != FocusEngineState.paused) return;
    _state = FocusEngineState.running;
    _lastTick = now ?? _clock();
  }

  /// 手动结束（竖屏退出 / 确认结束，PRD §4.1.6）。
  void stop() => finish(FocusEndReason.manual);

  /// 结束本次专注并产出 [FocusOutcome]（到时 / 打断 / 手动共用）。
  void finish(FocusEndReason reason) {
    if (_state == FocusEngineState.finished) return;
    _state = FocusEngineState.finished;

    final double actual = _focusSeconds / 60.0;
    final bool shortAborted = actual < kMinFocusMinutes;
    final FocusStatus status =
        shortAborted ? FocusStatus.shortAborted : FocusStatus.completed;
    // 短于最短结算时长 → 无产出；打断 → 全额保留（§4.1.4 / §6.2）。
    final double raw = shortAborted ? 0.0 : _sunlight;

    final outcome = FocusOutcome(
      actualFocusMin: actual,
      rawSunlight: raw,
      status: status,
      endReason: reason,
      wakeCount: _wakeCount,
      strongWakeCount: _strongWakeCount,
    );
    _outcome = outcome;
    _emit(FocusEvent(level: FeedbackLevel.lvl1, outcome: outcome));
  }

  /// 释放资源（关闭事件流）。
  void dispose() {
    _disposed = true;
    _controller.close();
  }

  // ── 内部计算 ──────────────────────────────────────────────────

  /// 在场产出增益：满速 [kSunlightPerFocusMinute]/分钟；恢复窗口内按 [kResumeSeconds] 秒
  /// 线性 0→100% 积分。
  double _presentGain(DateTime from, DateTime now) {
    final Duration span = now.difference(from);
    if (_resumeFrom == null) {
      final double minutes = span.inMicroseconds / 1e6 / 60.0;
      return minutes * kSunlightPerFocusMinute;
    }
    final DateTime r0 = _resumeFrom!;
    final double a = from.difference(r0).inMicroseconds / 1e6;
    final double b = now.difference(r0).inMicroseconds / 1e6;
    final double integral = _rampIntegral(a, b);
    if (b >= kResumeSeconds) {
      _resumeFrom = null; // 已回满，转满速
    }
    final double minutes = integral / 60.0;
    return minutes * kSunlightPerFocusMinute;
  }

  /// 线性斜坡 [0, kResumeSeconds] 秒内 rate: 0→1，之后恒为 1；返回 ∫rate dt。
  double _rampIntegral(double a, double b) {
    if (b <= 0) return 0;
    double lo = a < 0 ? 0 : a;
    if (lo >= b) return 0;
    final double r = kResumeSeconds.toDouble();
    if (lo >= r) return b - lo;
    if (b <= r) return (b * b - lo * lo) / (2 * r);
    return (r * r - lo * lo) / (2 * r) + (b - r);
  }

  /// 每完成 1/3 进度触发一次 lvl2 随光报信（天然 2 次，§4.1.3）。
  void _checkBoundaries() {
    for (int i = 0; i < kReportBoundaryFractions.length; i++) {
      if (_emittedBoundaries.contains(i)) continue;
      final int boundaryUs =
          (_planned.inMicroseconds * kReportBoundaryFractions[i]).round();
      if (_sessionElapsed.inMicroseconds >= boundaryUs) {
        _emittedBoundaries.add(i);
        _emit(const FocusEvent(
          level: FeedbackLevel.lvl2,
          textKey: 'lvl2_report',
        ));
      }
    }
  }

  /// 离席阈值检查：90s 轻声 / 180s 加重 / 300s 打断（§4.1.4 声量账）。
  ///
  /// 声量账：lvl4 每场 ≤ [kWakeMaxPerSession] 次、其中加重 ≤ [kWakeStrongMaxPerSession] 次；
  /// 达上限后不再触发，但打断仍按时间轴发生。
  void _checkWake() {
    final double absentSec = _absentElapsed.inMicroseconds / 1e6;

    if (absentSec >= kL2ThresholdSeconds && !_gentleFiredThisWindow) {
      _gentleFiredThisWindow = true;
      if (_wakeCount < kWakeMaxPerSession) {
        _wakeCount++;
        _emit(const FocusEvent(
          level: FeedbackLevel.lvl4,
          wakeIntensity: WakeIntensity.gentle,
          textKey: 'lvl4_gentle',
        ));
      }
    }

    if (absentSec >= kL3ThresholdSeconds && !_strongFiredThisWindow) {
      _strongFiredThisWindow = true;
      if (_strongWakeCount < kWakeStrongMaxPerSession &&
          _wakeCount < kWakeMaxPerSession) {
        _strongWakeCount++;
        _wakeCount++;
        _emit(const FocusEvent(
          level: FeedbackLevel.lvl4,
          wakeIntensity: WakeIntensity.strong,
          textKey: 'lvl4_strong',
        ));
      }
    }

    if (absentSec >= kL3ThresholdSeconds + kInterruptSeconds) {
      finish(FocusEndReason.interrupted);
    }
  }

  void _emit(FocusEvent event) {
    if (_disposed) return;
    _history.add(event);
    _controller.add(event);
  }
}
