/// App 总使用时长控制器（P0 · A 防沉迷，§6.1）。
///
/// 职责：
///  · 读 / 写 App 当日累计时长（SharedPreferences，键见 [kPrefAppUsageDate] /
///    [kPrefAppUsageSeconds]）；
///  · 在**娱乐 tab 前台**用 [Timer.periodic]（[kAppUsageTickSeconds]）驱动计时；
///  · 暴露 [AppUsageState] 供外壳判定「是否达上限 / 是否正在计时」。
///
/// 计时纪律：内核是幂等纯函数 `AppUsageService.advance`（「记录基准 + 差值」、每次结算
/// 无条件推进基准）→ 杜绝「刷新越多次涨越快」。
///
/// 判定纪律：是否到顶**只调用** `AppUsageService.isCapReached`（唯一判定入口），
/// 本类不内联任何 `seconds >= cap*60` 比较（防「判定孪生」）。
///
/// ⚠️ 定时器生命周期：随容器释放由 `ref.onDispose` 同步取消；外壳 `dispose` 亦会先
/// 调 [stopCounting]（同步取消定时器）再结算 —— 缺一都会让 widget 测试因 pending timer
/// 变红（`binding.dart` 的定时器断言）。
library app_usage_controller;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/services/app_usage_service.dart';

/// 供 UI 读取的 App 使用时长状态（不可变）。
class AppUsageState {
  /// 当日累计秒数。
  final int secondsToday;

  /// 当日上限（秒）。来自 `AppSettings.dailyAppCapMinutes`（× 60）。
  final int capSeconds;

  /// 当前是否正在计时（娱乐 tab 前台）。
  final bool counting;

  /// 是否已达当日上限（由 [AppUsageService.isCapReached] 判定，勿在此另写比较）。
  final bool reached;

  /// 本次单次连续使用累计秒数（F99；仅锁定触发时归零，离开 tab 不重置）。
  final int singleSeconds;

  /// 单次锁定解锁时刻（epoch ms；null = 未锁定）。
  final int? lockedUntilMs;

  const AppUsageState({
    required this.secondsToday,
    required this.capSeconds,
    required this.counting,
    required this.reached,
    this.singleSeconds = 0,
    this.lockedUntilMs,
  });

  /// 初始态：0 秒 / 回退上限 [kDailyAppCapMinutes] 分钟 / 未计时 / 未到顶。
  static const AppUsageState initial = AppUsageState(
    secondsToday: 0,
    capSeconds: kDailyAppCapMinutes * 60,
    counting: false,
    reached: false,
  );

  /// 上限分钟数（用于文案「上限 N 分钟」）。
  int get capMinutes => capSeconds ~/ 60;

  /// 此刻是否处于**单次锁定**（F99）：lockedUntilMs 非空且尚未到期。
  ///
  /// 惰性求值（传 [now]）——状态是快照，到期与否只能按当前时钟判定。
  bool sessionLockedAt(DateTime now) =>
      lockedUntilMs != null && now.millisecondsSinceEpoch < lockedUntilMs!;

  AppUsageState copyWith({
    int? secondsToday,
    int? capSeconds,
    bool? counting,
    bool? reached,
    int? singleSeconds,
    int? lockedUntilMs,
    bool clearLockedUntil = false,
  }) =>
      AppUsageState(
        secondsToday: secondsToday ?? this.secondsToday,
        capSeconds: capSeconds ?? this.capSeconds,
        counting: counting ?? this.counting,
        reached: reached ?? this.reached,
        singleSeconds: singleSeconds ?? this.singleSeconds,
        lockedUntilMs:
            clearLockedUntil ? null : (lockedUntilMs ?? this.lockedUntilMs),
      );
}

/// App 使用时长控制器。
///
/// ⚠️ Provider 定义在 `lib/core/di/providers.dart`（`appUsageControllerProvider`），
/// 与之保持一致的单点注册习惯。
class AppUsageController extends Notifier<AppUsageState> {
  /// 生产路径用默认口径；测试可注入缩小值免等真实 10 分钟（F99）。
  AppUsageController({int? singleLimitMinutes, int? singleLockMinutes})
      : _singleLimitMinutes = singleLimitMinutes ?? kSingleUseLimitMinutes,
        _singleLockMinutes = singleLockMinutes ?? kSingleUseLockMinutes;

  /// 单次上限（分钟）——判定交给 [AppUsageService.isSingleLimitReached]（唯一入口）。
  final int _singleLimitMinutes;

  /// 单次锁定时长（分钟）。
  final int _singleLockMinutes;

  /// 计时器（仅在娱乐 tab 前台存在；离开 / 切后台 / dispose 时取消）。
  Timer? _ticker;

  /// 内部镜像状态 —— 避免在控制器已释放后读取 `state` getter 抛错。
  AppUsageState _current = AppUsageState.initial;

  /// 累计所属自然日 key。
  String? _date;

  /// 累计秒数（内存态，与持久化同步）。
  int _secondsToday = 0;

  /// 上次结算基准（未计时为 null）。
  DateTime? _baseAt;

  /// 当日上限（分钟）。判定到顶时交给 [AppUsageService.isCapReached]（唯一入口）。
  int _capMinutes = kDailyAppCapMinutes;

  /// 本次单次连续使用秒数（F99；仅锁定触发时归零）。
  int _singleSeconds = 0;

  /// 单次锁定解锁时刻（epoch ms；null = 未锁定）。与持久化同步。
  int? _lockedUntilMs;

  bool _hydrated = false;
  Future<void>? _hydration;

  @override
  AppUsageState build() {
    // 容器释放时务必取消 ticker（否则测试/真机都残留定时器）。
    ref.onDispose(_cancelTicker);
    _hydration = _hydrate();
    return _current;
  }

  /// 从持久化 + 设置装载初始状态。
  Future<void> _hydrate() async {
    try {
      final String today = dayKey(DateTime.now());
      final String? storedDate =
          await ref.read(settingsStoreProvider).appUsageDate();
      final int storedSeconds =
          await ref.read(settingsStoreProvider).appUsageSeconds();
      final int? storedLockedUntilMs =
          await ref.read(settingsStoreProvider).appUsageLockedUntilMs();
      final int capMinutes =
          (await ref.read(settingsRepositoryProvider).getSettings())
              .dailyAppCapMinutes;
      final int seconds = storedDate == today ? storedSeconds : 0;
      _date = today;
      _secondsToday = seconds;
      _capMinutes = capMinutes;
      _lockedUntilMs = storedLockedUntilMs;
      _setStateIfAlive(AppUsageState(
        secondsToday: seconds,
        capSeconds: capMinutes * 60,
        counting: false,
        // 唯一判定入口（不在此内联比较）。
        reached: AppUsageService.isCapReached(
          capMinutes: capMinutes,
          secondsToday: seconds,
        ),
        singleSeconds: _singleSeconds,
        lockedUntilMs: _lockedUntilMs,
      ));
    } catch (_) {
      // 读取失败容忍：保持初始态（0 秒），不阻塞外壳。
      _date = dayKey(DateTime.now());
      _secondsToday = 0;
    } finally {
      _hydrated = true;
    }
  }

  Future<void> _ensureHydrated() async {
    if (!_hydrated) await _hydration;
  }

  /// 该 tab 是否计入 App 总时长（口径开关 = [kAppUsageCountingTabs]）。
  bool isEntertainmentTab(int i) => kAppUsageCountingTabs.contains(i);

  /// 进入娱乐 tab：设基准并（若未计）启动 ticker。已到顶 / 单次锁定中则不放行。
  Future<void> startCounting() async {
    await _ensureHydrated();
    final DateTime now = DateTime.now();
    _evalLockExpiry(now); // 锁定已到期 → 先解锁再放行。
    if (_current.reached) return; // 到顶不放行（UI 已拦截，这里再守一道）。
    if (_current.sessionLockedAt(now)) return; // F99：单次锁定中不放行。
    _baseAt = now;
    _ticker ??= Timer.periodic(
      const Duration(seconds: kAppUsageTickSeconds),
      (_) => _tick(),
    );
    if (!_current.counting) {
      _setStateIfAlive(_current.copyWith(counting: true));
    }
  }

  /// 离开娱乐 tab / 切后台 / dispose：先同步取消 ticker，再结算一次。
  Future<void> stopCounting() async {
    final bool wasCounting = _ticker != null;
    _cancelTicker(); // 必须**同步**取消，保证 dispose 场景无残留定时器。
    if (!wasCounting) {
      if (_current.counting) {
        _setStateIfAlive(_current.copyWith(counting: false));
      }
      return;
    }
    await _ensureHydrated();
    await _settle(DateTime.now());
    _setStateIfAlive(_current.copyWith(counting: false));
  }

  Future<void> _tick() => _settle(DateTime.now());

  /// 结算一次（幂等）：推进基准 → 更新内存态 + Provider 状态 + 落盘。
  Future<void> _settle(DateTime now) async {
    final int prevTotal = _secondsToday;
    final String? prevDate = _date;
    final AppUsageTick tick = AppUsageService.advance(
      storedDate: _date ?? dayKey(now),
      storedSeconds: _secondsToday,
      baseAt: _baseAt ?? now,
      now: now,
    );
    _date = tick.date;
    _secondsToday = tick.seconds;
    _baseAt = now;

    // F99：单次连续使用同步累加。日累计的增量（同日取差值；跨天全段都算本次连续），
    // 时钟回拨增量为 0 → 单次也不增长。
    final int delta =
        (tick.date == prevDate && tick.seconds >= prevTotal)
            ? tick.seconds - prevTotal
            : tick.seconds;
    _singleSeconds += delta > 0 ? delta : 0;

    // 唯一判定入口（不在此内联比较）。
    final bool reached = AppUsageService.isCapReached(
      capMinutes: _capMinutes,
      secondsToday: tick.seconds,
    );

    // F99：单次连续使用达上限 → 触发锁定（清零单次、记解锁时刻、停表）。
    // 每日到顶（reached）不触发本锁定——到顶后本来就不放行。
    bool lockFired = false;
    if (_lockedUntilMs == null &&
        !reached &&
        AppUsageService.isSingleLimitReached(
          limitMinutes: _singleLimitMinutes,
          singleSeconds: _singleSeconds,
        )) {
      _singleSeconds = 0;
      _lockedUntilMs =
          now.add(Duration(minutes: _singleLockMinutes))
              .millisecondsSinceEpoch;
      lockFired = true;
      _cancelTicker(); // 锁定即刻停表（人可能还停在娱乐 tab，由外壳弹卡引导离开）。
      unawaited(_persistLock(_lockedUntilMs));
    }

    _setStateIfAlive(_current.copyWith(
      secondsToday: tick.seconds,
      capSeconds: _capMinutes * 60,
      reached: reached,
      singleSeconds: _singleSeconds,
      lockedUntilMs: _lockedUntilMs,
      counting: lockFired ? false : null,
    ));

    try {
      await ref.read(settingsStoreProvider).saveAppUsage(
            date: tick.date,
            seconds: tick.seconds,
          );
    } catch (_) {
      // 落盘失败容忍：内存态仍准确，下次 tick 再试。
    }
  }

  /// 锁定到期惰性解锁：到期则清锁（内存 + 持久化），返回**此刻是否仍在锁**。
  bool _evalLockExpiry(DateTime now) {
    if (_lockedUntilMs != null &&
        now.millisecondsSinceEpoch >= _lockedUntilMs!) {
      _lockedUntilMs = null;
      unawaited(_persistLock(null));
      _setStateIfAlive(_current.copyWith(clearLockedUntil: true));
    }
    return _current.sessionLockedAt(now);
  }

  Future<void> _persistLock(int? ms) async {
    try {
      await ref.read(settingsStoreProvider).saveAppUsageLockedUntilMs(ms);
    } catch (_) {
      // 落盘失败容忍：内存态仍准确（重启后最多多玩一轮单次，日上限兜底）。
    }
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 写入内存镜像并尽力同步 Provider 状态（控制器已释放时静默跳过）。
  void _setStateIfAlive(AppUsageState s) {
    _current = s;
    try {
      state = s;
    } catch (_) {
      // 控制器已 dispose：忽略。
    }
  }
}
