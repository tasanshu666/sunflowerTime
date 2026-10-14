/// 孩子端各 tab 的「可见即刷新 + 时间边界兜底刷新」（口径 **C68**，玄参 2026-10-14 反馈）。
library child_tab_refresh;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';

import 'shell_tab.dart';

/// 是否需要因**时间边界**刷新（方案 B 的判据；**纯函数 → 可单测**）。
///
/// 覆盖两类边界：
///  ① **跨天**（`y/m/d` 变化）—— 成长推进 / 枯萎计时 / 花谢 / 杂草害虫重 roll 全以
///     「天」为粒度（`PlantGrowthService.tickAll`），周池也按周滚动；
///  ② **同一天内跨过 08:00** —— 花期内每天 08:00 有一轮「晨露」待收集奖励**到期**
///     （登记见 `PlantGrowthService._enqueueBloomRewards`）。⚠️ 到期只是**数据**变化：
///     行早已在开花那一刻预登记好，08:00 只让它变成「可收集」，而「可收集集合」是
///     在页面 `_reload` 里才重算的 —— **页面不重读，到期了也看不见头顶气泡**
///     （这正是玄参反馈的真机症状）。
///
/// [last] = 上次成功刷新的时刻；[now] = 当前时刻。
/// 时钟回拨（`now` 不晚于 [last]）一律返回 `false`：宁可漏刷一次，也不因时钟抖动反复刷。
bool shouldRefreshForTimeBoundary(DateTime last, DateTime now) {
  if (!now.isAfter(last)) return false;
  final DateTime lastDay = DateTime(last.year, last.month, last.day);
  final DateTime nowDay = DateTime(now.year, now.month, now.day);
  if (nowDay != lastDay) return true;
  final DateTime eight = DateTime(now.year, now.month, now.day, 8);
  return last.isBefore(eight) && !now.isBefore(eight);
}

/// 孩子端 tab 页「自动刷新」mixin（**单点收口**，5 个孩子端 tab 共用同一份实现）。
///
/// ## 背景：原先只有三类刷新触发，且**全是副作用**
/// 孩子端 5 个 tab 由外壳 `IndexedStack` **保活**（`child_shell_page._tabs` 预先构建，
/// 各页 `initState` 只在外壳首次构建时跑一次），刷新只发生在：
///   ① `initState → _reload()`（切 tab **不会**重跑）；
///   ② `economyRevisionProvider` 自增（养护 / 收集 / 家长核销等副作用之后）；
///   ③ 页面内动作（如花园页养护卡片关闭）。
///
/// **缺失三类时间性触发** → 页面长期停在旧快照：
///   · **切回本 tab** —— 保活页只重建，不重读数据；
///   · **App 回前台** —— 外壳 `didChangeAppLifecycleState` 只恢复计时与音频；
///   · **停在页面上跨过 08:00 / 跨天** —— 页面里没有任何与数据相关的周期定时器。
///
/// ## 真机症状（玄参 2026-10-14 iPad 模拟器实测）
/// 进花园看到盛开的「珊瑚岭兰」**没有产生阳光** → 随手点了一个花盆 → 弹出卡片 →
/// 退出卡片后**看到了**阳光。逐步对上：上次 `_reload` 发生在 **08:00 之前**（晨露行
/// 尚未到期）→ 时间跨过 08:00 → 切到花园 tab **不刷新** → 无气泡 → 点花盆开卡片再关
/// （触发 ③）→ 重算可收集集合 → 气泡出现。**奖励一直没丢，只是界面不知道要更新。**
///
/// ## 本 mixin 补什么（方案 A + B，玄参拍板）
///   · **A** 本 tab 由隐藏变可见（[childShellTabIndexProvider] 切到本页下标）→ 刷新；
///   · **A** App `resumed` 且本页可见 → 刷新；
///   · **B** 可见期间每 [kChildTabBoundaryCheckSeconds] 秒检查一次
///     [shouldRefreshForTimeBoundary]，**跨过才真刷新**（不跨边界不碰数据库）。
///
/// ⚠️ **刻意不覆盖**「不可见的 tab」：保活页即使隐藏也刷新会白白跑重活（花园 `_reload`
/// 要 tickAll + 物化旧 pending + 去重 + 预取各物种支付按钮），而「切回时补刷」已经保证
/// 用户看到的那一刻是最新的。
///
/// ## 接线（每页只需 `with` + 两个成员，**不要**碰 `build`）
/// ```dart
/// class _XState extends ConsumerState<X> with ChildTabAutoRefresh<X> {
///   @override
///   int? get refreshTabIndex => kChildTabIndexOfX; // 不在外壳里 → 返回 null
///
///   @override
///   Future<void> onTabRefreshRequested() => _reload(silent: true);
/// }
/// ```
/// ⚠️ 必须带类型实参 `<X>`：写成 `on ConsumerState<ConsumerStatefulWidget>` 会被 Dart
/// 判为 `conflicting_generic_interfaces`（`ConsumerState<X>` 与
/// `ConsumerState<ConsumerStatefulWidget>` 是两个不同的泛型实现，同类不能同时实现）。
///
/// ## 实现要点（踩坑备忘）
/// · 监听用 **`ref.listenManual`**：`initState` 阶段 `ref.listen` 会抛
///   「ref.listen can only be used within the build method」断言（同
///   `parent_reward_page` 的注释）；`listenManual` 随 element unmount 自动关闭，无需手动解绑。
/// · 生命周期观察者由**本 mixin 自己**注册，页面**不必**再实现 `WidgetsBindingObserver`。
/// · 定时器**只在可见期间**存在：不可见即 cancel（不给既有测试留 pending timer）。
/// · 在途去重（[_refreshInFlight]）：切 tab + 回前台 + 边界可能同帧连发，只跑一次。
/// · 子类的 `initState` / `dispose` 里 `super.xxx()` **必须保留**；未定义这两者的页面
///   （如 `store_page`）由框架直接调用本 mixin 的实现。
/// · 测试见 `test/m3/child_tab_refresh_test.dart`（含「先红后绿」式负向断言）。
mixin ChildTabAutoRefresh<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 本页在外壳 `_tabs` 中的下标；**`null` = 不在外壳里**（如路由直推的
  /// `GardenPage(embedded: false)`）→ 恒视为可见，只吃「回前台 + 时间边界」两条触发。
  int? get refreshTabIndex;

  /// 真正重读数据的动作（各页自备）。⚠️ **必须静默**（不闪全屏 loading）——
  /// 切 tab / 回前台是高频动作，闪一下加载圈会让用户以为「页面重载了」。
  Future<void> onTabRefreshRequested();

  /// 当前时间源。抽成方法只为**测试可覆盖**（验证「跨 08:00 / 跨天」边界时不依赖真实时钟）。
  @protected
  DateTime refreshNow() => DateTime.now();

  late final WidgetsBindingObserver _lifecycle = _ChildTabLifecycleObserver(_onAppResumed);

  /// 可见期间的时间边界轮询（不可见时恒为 null）。
  Timer? _boundaryTimer;

  /// 上次**成功发起**刷新的时刻（方案 B 的比较基准）。
  late DateTime _lastRefreshAt;

  /// 本页当前是否可见（与花园氛围音**同源**判据：外壳 tab 索引）。
  bool _visible = false;

  /// 刷新在途闸门（连发触发只跑一次）。
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _lastRefreshAt = refreshNow();
    _visible = _isVisibleNow();
    WidgetsBinding.instance.addObserver(_lifecycle);
    if (refreshTabIndex != null) {
      ref.listenManual(childShellTabIndexProvider,
          (int? _, int next) => _onTabIndexChanged(next));
    }
    if (_visible) _startBoundaryTimer();
  }

  @override
  void dispose() {
    _stopBoundaryTimer();
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }

  /// 本页此刻是否可见（不在外壳里 → 恒可见）。
  bool _isVisibleNow() {
    final int? index = refreshTabIndex;
    return index == null || ref.read(childShellTabIndexProvider) == index;
  }

  /// 外壳 tab 索引变化：切到本页 → 起定时器 + **立即刷一次**（方案 A）；切走 → 停定时器。
  void _onTabIndexChanged(int next) {
    final bool nowVisible = next == refreshTabIndex;
    if (nowVisible == _visible) return;
    _visible = nowVisible;
    if (_visible) {
      _startBoundaryTimer();
      _requestRefresh();
    } else {
      _stopBoundaryTimer();
    }
  }

  /// App 回到前台（⚠️ **只有可见的那个 tab 会刷**：5 个页面都注册了观察者）。
  void _onAppResumed() {
    if (!mounted || !_visible) return;
    _requestRefresh();
  }

  /// 方案 B：可见期间低频检查「是否跨过 08:00 / 跨天」，跨过才真刷新。
  void _checkTimeBoundary() {
    if (!mounted || !_visible) return;
    if (shouldRefreshForTimeBoundary(_lastRefreshAt, refreshNow())) {
      _requestRefresh();
    }
  }

  void _startBoundaryTimer() {
    _boundaryTimer ??= Timer.periodic(
      const Duration(seconds: kChildTabBoundaryCheckSeconds),
      (_) => _checkTimeBoundary(),
    );
  }

  void _stopBoundaryTimer() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
  }

  /// 发起一次刷新（在途去重）。[onTabRefreshRequested] 的异常一律吞掉 ——
  /// 各页 `_reload` 内部已自带兜底，这里再加一层只为绝不让异常打断定时器。
  void _requestRefresh() {
    if (!mounted || _refreshInFlight) return;
    _refreshInFlight = true;
    _lastRefreshAt = refreshNow();
    unawaited(() async {
      try {
        await onTabRefreshRequested();
      } catch (_) {
        // 静默：刷新失败不是致命故障，下一轮触发会再试。
      } finally {
        _refreshInFlight = false;
      }
    }());
  }
}

/// 把「回前台」翻译成回调的极简生命周期观察者（避免每个页面 State 都去 `with WidgetsBindingObserver`）。
class _ChildTabLifecycleObserver extends WidgetsBindingObserver {
  _ChildTabLifecycleObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
