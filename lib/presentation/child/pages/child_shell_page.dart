/// 孩子端 5 tab 外壳（M3 导航重构 / §5 信息架构）。
///
/// 底部 [NavigationBar] + [IndexedStack] 承载：今日 / 任务 / 花园 / 商店 / 我的。
/// 用 [IndexedStack]（而非重建）保留各 tab 状态，切走再切回不丢滚动/输入。
///
/// 承重逻辑（自原 `child_home_page.dart` 整段迁移，逻辑一字不改）：
///  · 「家长已核销」弹窗提醒（M2）；
///  · 「家长拒绝」对称通知（B4）；
///  · 监听 [economyRevisionProvider]，家长端处理完返回孩子端即重新检查（B5）。
/// 已读申请 id 记在 shared_preferences，避免重复弹窗。
///
/// P0 · A（§6.1）：本页作为 **App 总时长防沉迷**的拦截落点 ——
///  · 娱乐 tab（[kAppUsageCountingTabs]：花园/商店/我的）前台计时（含切后台暂停）；
///  · 到顶后**只拦娱乐 tab**（温和提示 + 引导去「今日」），今日/成长与专注全链路永远可用。
library child_shell_page;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/state/app_usage_controller.dart';
import 'package:sunflower_time/presentation/child/widgets/app_cap_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/parent_entry_action.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';
import 'package:sunflower_time/shared/adaptive_nav_bar.dart';

/// 孩子端外壳：底部导航 + 5 个 tab。
class ChildShellPage extends ConsumerStatefulWidget {
  const ChildShellPage({super.key});

  @override
  ConsumerState<ChildShellPage> createState() => _ChildShellPageState();
}

class _ChildShellPageState extends ConsumerState<ChildShellPage>
    with WidgetsBindingObserver {
  /// 当前 tab 索引。**初值来自 [childShellTabIndexProvider] 的记忆值**（F138 口径 B）：
  /// 孩子在花园点「家长天地」→ `context.go('/parent')` 销毁整个外壳 → 退出家长天地时
  /// `context.go('/')` 重建外壳 —— 必须回到离开前那个 tab，而不是无条件回「今日」。
  ///
  /// ⚠️ 只能在 [initState] 赋值（`ref.read` 在 initState 合法，在字段初始化器里不合法）。
  late int _index;

  /// 台前信号 notifier 的字段引用（[initState] 抓取）。
  ///
  /// ⚠️ 与 [_usageCtrl] 同因：`dispose()` 阶段 `ref` 已不可用（element 先被标 disposed），
  /// 用 `ref.read(...)` 会抛 `Bad state: Cannot use "ref" after the widget was disposed.`。
  StateController<bool>? _onStageCtrl;

  /// 本外壳的挂载序号；[_shellMountSeq] 全局单调递增。
  ///
  /// 🔴 为什么需要：「下台」信号是**延后**发布的（见 [_publishOnStage]），而路由切换时
  /// 旧外壳 `dispose()` 可能晚于新外壳 `initState()`（`go()` 有转场动画时更晚）——
  /// 若旧外壳的下台信号无条件写入，会把**新外壳**刚发布的「在台前」覆盖成 false
  /// → 花园页永久不可见 → 背景音乐再也不响（把 F138 修成另一个 bug）。
  /// 故下台前校验「我还是最新的外壳吗」。
  static int _shellMountSeq = 0;
  int _mountSeq = 0;

  /// 调试期「跳过 30 分钟限时」开关（仅 kDebugMode 消费；默认 true = 绕过）。
  ///
  /// 玄参 2026-09-29：调试期间默认不进限时状态；家长端首页有临时开关可关回。
  /// release 构建不读该开关，防沉迷照常。
  bool _debugCapBypass = true;

  /// App 时长控制器引用（[initState] 期间抓取）。
  ///
  /// ⚠️ **为什么要在字段里留一份**：Riverpod 的 `ConsumerStatefulElement` 在
  /// `unmount()` 时先把自己标为 disposed，**再**调 `state.dispose()` —— 也就是
  /// 说 `dispose()` 里用 `ref` 读任何 provider 都会抛
  /// `Bad state: Cannot use "ref" after the widget was disposed.`
  /// （2026-09-23 实测：这一度被 `catch (_)` 静默吞掉 → ticker 从不取消
  /// → **真机定时器泄漏**，进锁屏/entry 页后娱乐时长仍在偷偷累加）。
  /// 因此停表**必须**走这份字段引用，不能走 `ref`。
  AppUsageController? _usageCtrl;

  /// 5 个 tab 的标题（AppBar 随当前 tab 变化）。
  static const List<String> _titles = <String>['今日', '成长', '花园', '商店', '我的'];

  /// 5 个 tab 的内容页（IndexedStack 保活，切 tab 不重建）。
  ///
  /// ⚠️ 隐藏 tab 会在 [build] 里被包一层 `TickerMode(enabled: false)` 停掉动画：
  ///  · 省电：后台 tab 无意义的动画不再逐帧重绘；
  ///  · 关键：花园页左下角木牌有**无限循环的呼吸高亮**，若后台 tab 仍跑动画，
  ///    `ChildShellPage` 的 widget 测试里 `pumpAndSettle()` 会**永不返回**（超时失败）。
  /// 切回某 tab 时 `TickerMode` 自动恢复，动画继续。
  static const List<Widget> _tabs = <Widget>[
    ChildTodayPage(),
    ChildTaskPage(),
    GardenPage(embedded: true),
    StorePage(embedded: true),
    ChildProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    // 监听 App 生命周期：切后台暂停计时、回前台（仍处娱乐 tab）恢复计时。
    WidgetsBinding.instance.addObserver(this);
    // 预热 App 时长控制器：触发一次异步 hydrate，使「是否到顶」在首次点击前就绪。
    // 同时**抓住 notifier 引用**留给 dispose 停表（见 [_usageCtrl] 注释：dispose 里 ref 已不可用）。
    _usageCtrl = ref.read(appUsageControllerProvider.notifier);
    // F138 口径 B：恢复上次离开时的 tab（记忆值）。越界值（脏数据 / 未来 tab 数变化）
    // 一律回落「今日」，绝不把外壳索引设到 `_tabs` 之外（IndexedStack 会抛区间断言）。
    //
    // 🔴 P1（玄参复核）：**娱乐 tab 必须先过防沉迷闸门才允许恢复**，且闸门要读**已 hydrate**
    // 的 usage —— 未就绪时读到的「0 秒 / 未锁定」不是真状态，默认放行等于又开一条通道。
    // 故唯一安全顺序是：**先停在「今日」（安全侧）** → 等 hydrate → 过 [_guardEntertainmentTab]
    // → 放行才切过去。绝不「先上娱乐 tab 再补拦截」（那会给孩子一个可见的绕过窗口）。
    final int remembered = ref.read(childShellTabIndexProvider);
    final bool rememberedValid = remembered >= 0 && remembered < kChildTabCount;
    _index = kChildTabIndexOfToday;
    // F138 口径 C：上台信号。⚠️ 必须在 initState 抓住 notifier 引用（dispose 不能再碰 ref），
    // 且**延后一微任务**发布 —— Riverpod 禁止在 initState / dispose 等 widget 生命周期里
    // 直接改 provider（会抛「Tried to modify a provider while the widget tree was building.」），
    // 延后发布同时避开「别的页正在卸载时被通知重建」的风险。
    _mountSeq = ++_shellMountSeq;
    _onStageCtrl = ref.read(childShellOnStageProvider.notifier);
    // 调试期限时开关：读 shared_preferences（默认 true = 绕过；异步失败保持默认）。
    // 🔴 必须先于「恢复娱乐 tab 的闸门」发起、并把 Future 留给它 await —— 否则会出现
    // 竞态：usage hydrate 先完成（或先被读到）而 `_debugCapBypass` 仍是默认 true →
    // 闸门在 debug 构建里被误判成「绕过」→ 恢复路径直接放行（P1 又漏）。
    final Future<void> capBypassReady = _loadDebugCapBypass();
    unawaited(capBypassReady);
    if (rememberedValid &&
        remembered != kChildTabIndexOfToday &&
        _usageCtrl!.isEntertainmentTab(remembered)) {
      // 娱乐 tab：异步过闸（hydrate 期间界面待在「今日」）。
      //
      // 🔴 「上台」信号**也一并延后**到闸门给出结论之后（见 [_restoreEntertainmentTab]
      // 的 finally）：若此刻就发布 `onStage=true`，在「记忆=2 + 刚上台」的那个窗口里
      // 花园页会先判自己可见并起播一次背景音（P1 用例实测抓到 1 次多余起播），
      // 而孩子其实被拦在「今日」。
      unawaited(_restoreEntertainmentTab(remembered, capBypassReady));
    } else {
      if (rememberedValid) _index = remembered; // 今日 / 成长等：无闸门，直接恢复。
      _publishOnStage(true);
    }
    // ⚠️ 2026-09-29 修复「花园背景音从来没响」：`AudioService.applySettings` 此前
    // **全项目无调用点** → 服务内 `_bgmOn` 恒为 false → 花园氛围音一进门就被 return。
    // 孩子端是家长设置的唯一消费端，故在此把设置真正接到音频服务（音效 / 背景音乐开关）。
    unawaited(_syncAudioSettings());
    // 首帧后再弹窗，避免在 build 期间触发路由/覆盖层变更。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAllNotices());
  }

  /// 把「家长端设置」的音效 / 背景音乐开关接到音频服务。
  ///
  /// 只读一次设置（异步、失败静默）：家长端改过开关后，孩子端重新进入本外壳即生效。
  /// 用静态单例 [AudioService.instance]，避免在异步间隙用 `ref`（可能已 dispose）。
  Future<void> _syncAudioSettings() async {
    try {
      final AppSettings s =
          await ref.read(settingsRepositoryProvider).getSettings();
      AudioService.instance.applySettings(
        soundOn: s.soundOn,
        bgmOn: s.bgmOn,
      );
    } catch (_) {
      // 静默降级：读不到设置时保持音频服务既有开关，不影响主流程。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开外壳务必停表（同步取消 ticker），否则定时器泄漏 → 测试 pending timer 断言红。
    _stopAppUsageCounting();
    // F138 口径 C：下台信号（延后发布；只会被「更新的外壳」覆盖，见 [_publishOnStage]）。
    _publishOnStage(false);
    super.dispose();
  }

  /// 发布「外壳在台前 / 已下台」信号（**延后一微任务**，`try/catch` 静默）。
  ///
  /// 三条硬约束（F138）：
  ///  1. **绝不能同步写**：Riverpod 的 `debugCanModifyProviders` 守卫会在
  ///     `initState` / `dispose` 这类 widget 生命周期里直接抛
  ///     「Tried to modify a provider while the widget tree was building.」；
  ///     而 `dispose` 里连 `ref` 都不能用（element 已标 disposed）→ 只能走
  ///     [initState] 抓到的 [_onStageCtrl] 字段。
  ///  2. **延缓到微任务**：同步写会立刻通知监听者，可能在别的页正卸载时触发重建。
  ///  3. **下台要校验挂载序号**：路由切换时旧外壳的 `dispose` 可能晚于新外壳的
  ///     `initState`（转场动画期间尤甚），无条件写入会把新外壳的「在台前」覆盖掉。
  ///  4. **静默兜底**：测试里 `ProviderScope` 与外壳一起卸载时容器可能已 dispose，
  ///     写 provider 会抛 `StateError` —— 那属预期，不该炸测试。
  void _publishOnStage(bool onStage) {
    scheduleMicrotask(() {
      try {
        if (!onStage && _mountSeq != _shellMountSeq) return; // 已有更新的外壳接管台前。
        _onStageCtrl?.state = onStage;
      } catch (_) {
        // 容器 / provider 已随外壳一起销毁：无需（也无法）发布，静默即可。
      }
    });
  }

  /// 恢复上次停留的**娱乐 tab**（花园 / 商店 / 我的）——先等 usage hydrate，再走
  /// 与点 tab **同一道闸门** [_guardEntertainmentTab]（F138 P1）。
  ///
  /// 为什么必须异步：
  ///  · `AppUsageController` 的状态是**异步 hydrate** 出来的（`_hydrate()` 里读 SP + 设置）。
  ///    `initState` 阶段读到的还是 `AppUsageState.initial`（0 秒 / 未锁定）——**不可能是真状态**，
  ///    拿它判拦截等于默认放行；
  ///  · 所以 `_index` 起步恒为「今日」，本方法在 hydrate 完成后才决定是否切过去。
  ///    ⚠️ 顺序反过来（先切过去再补拦截）会给被锁定的孩子一个「先看到花园、再被弹卡」的
  ///    可见绕过窗口，等于没拦。
  ///
  /// 就绪探针用 [AppUsageController.startCounting]：它内部 `await _ensureHydrated()`，
  /// 且**在到顶 / 单次锁定态下直接返回、不会起 ticker**（见其实现）——
  /// 正好「只等就绪、不越权放行」。
  ///
  /// [capBypassReady] = `_debugCapBypass` 的读取 Future（见 `initState` 的竞态说明）。
  ///
  /// 本方法**同时负责发布「上台」信号**（`finally`）：这是为了让 `onStage=true` 与
  /// 「tab 记忆与真实 `_index` 一致」在同一个时刻成立 —— 中间任何一帧两者不一致，
  /// 花园页都会把自己判成可见（记忆=2 + 在台上）而多起播一次。
  Future<void> _restoreEntertainmentTab(
    int target,
    Future<void> capBypassReady,
  ) async {
    try {
      // 先等「调试绕过开关」落地，再等 usage hydrate —— 闸门读的两个输入都必须就绪。
      await capBypassReady;
      await _usageCtrl!.startCounting(); // ← 仅作为 hydrate 探针（被拦时不会起表）
      if (!mounted) return;
      // 🔴 P2-a（QA 探针 Q6 实测复现）：恢复是**异步**的（等 SP + 等 usage hydrate）。
      // 这段窗口里孩子完全可能自己点了别的 tab —— 记忆已被 [_onSelectTab] 改写成新选择，
      // 此时异步恢复**必须放弃**，理由两条：
      //  · 否则会把人从「成长」硬拽回「花园」—— 抢用户操作，观感像 bug；
      //  · 而且我们不会回写记忆 → 形成 `_index=2 / 记忆=1` 分叉 → 花园页按
      //    「在台前 && 记忆==2」判自己不可见 → **回花园反而没背景音**
      //    （F138 的镜像形态，比原 bug 更难查）。
      // 口径：**记忆是「孩子最后一次主动选择」的真源**，异步恢复只允许在没人动过时生效。
      if (ref.read(childShellTabIndexProvider) != target) return;
      // 此刻 usage 已就绪 → 同步闸门判定是可信的（与点 tab 完全同一条路径）。
      if (_guardEntertainmentTab(target)) {
        setState(() => _index = target);
        // 记忆值本来就是 target（外壳 `_onSelectTab` 写过），无需回写；
        // 计时必须显式起（探针那次在「未到顶」时已起表，这里幂等兜一层）。
        unawaited(_usageCtrl!.startCounting());
      } else {
        // 被拦下：孩子实际落在「今日」→ **tab 记忆必须同步成今日**。
        // 可见性判据是「在台前 && 记忆 == 本页下标」，若记忆仍停在娱乐 tab，
        // 花园页会认为可见 → 又在「今日」上补播背景音（正是 F138 那个 bug 的翻版）。
        // 与 [_onUsageStateChanged] 把被踢回的人同步成 0 完全同口径。
        ref.read(childShellTabIndexProvider.notifier).state =
            kChildTabIndexOfToday;
      }
    } catch (_) {
      // 等就绪失败：保持「今日」，不放行（安全侧）。
    } finally {
      // 放行 / 拦下 / 异常三种结局都必须发布上台信号 —— 否则整个外壳永久「不在台上」，
      // 所有 tab 的可见即刷新与花园氛围音会一起哑掉。
      if (mounted) _publishOnStage(true);
    }
  }

  // ── P0 · A App 总时长：生命周期 + 拦截 ───────────────────────────────

  /// App 切前后台：非前台一律暂停计时；回前台且仍处娱乐 tab 则恢复。
  ///
  /// F70（玄参 2026-10-05）：退后台 / 锁屏时**同步暂停一切音频**（花园氛围音 +
  /// 专注 BGM），回前台恢复暂停前在播的通道——此前花园页锁屏/退后台背景音乐
  /// 仍在响。`hidden`（iOS 锁屏先于 paused）与 `paused`（Android）都触发暂停；
  /// [AudioService.pauseAllForBackground] 幂等，连发两次安全。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      if (ctrl.isEntertainmentTab(_index)) unawaited(ctrl.startCounting());
      unawaited(AudioService.instance.resumeFromBackground());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(ctrl.stopCounting());
      unawaited(AudioService.instance.pauseAllForBackground());
    } else {
      unawaited(ctrl.stopCounting());
    }
  }

  /// 读取调试限时开关（异步、失败静默：保持默认 true = 绕过）。
  Future<void> _loadDebugCapBypass() async {
    try {
      final bool bypass =
          await ref.read(settingsStoreProvider).debugCapBypass();
      if (!mounted) return;
      setState(() => _debugCapBypass = bypass);
    } catch (_) {
      // 读不到 → 保持默认（调试期绕过），不阻塞外壳。
    }
  }

  /// 安全停表（**不经过 [ref]** —— dispose 阶段 `ref` 已不可用，用它会抛 Bad state；
  /// 这里改用 [initState] 抓到的 [_usageCtrl] 引用，保证 ticker 一定被同步取消）。
  void _stopAppUsageCounting() {
    try {
      unawaited(_usageCtrl!.stopCounting());
    } catch (_) {
      // 忽略：容器已释放（此时 ticker 已由控制器的 ref.onDispose 取消）。
    }
  }

  /// 点底部 tab：到顶 / 单次锁定则**只拦娱乐 tab**（不切换 + 温和提示），其余照常切换并启停计时。
  void _onSelectTab(int i) {
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);
    // F138 P1：拦截口径抽成 [_guardEntertainmentTab]，与「恢复上次 tab」**同一道闸门**。
    if (!_guardEntertainmentTab(i)) return; // 拦下：不切 tab，卡片已弹。

    setState(() => _index = i);
    // F71：同步 tab 索引 provider——花园页据此**确定性**启停氛围音
    //（原 TickerMode 依赖重建方案在 IndexedStack 下时机不可靠，切走后音乐继续播）。
    ref.read(childShellTabIndexProvider.notifier).state = i;
    if (ctrl.isEntertainmentTab(i)) {
      unawaited(ctrl.startCounting());
    } else {
      unawaited(ctrl.stopCounting());
    }
  }

  /// **进入娱乐 tab 的唯一闸门**（F138 P1 收口：点 tab 与「恢复上次 tab」共用）。
  ///
  /// 返回 `true` = 放行（调用方负责切 tab + `startCounting()`）；
  /// 返回 `false` = 已拦下（本函数**已弹**对应卡片；调用方必须把 `_index` 留在/回落
  /// 「今日」且**不得** `startCounting()`）。
  ///
  /// 🔴 为什么必须共用：`initState` 恢复上次 tab 时若只补「开始计时」不补「能不能进」，
  /// 孩子就得到一条稳定通道 —— 玩花园玩到单次锁定 / 日总量到顶 → 被踢回今日 →
  /// 进家长天地转一圈出来 → **直接落回花园且免拦截**。
  ///
  /// ⚠️ 本函数**同步读** usage 状态，调用方必须自行保证已 hydrate（`initState` 路径由
  /// [_restoreEntertainmentTab] 先等就绪；点 tab 路径沿用既有行为：控制器在 `initState`
  /// 已预热，且状态未就绪时读到的初始态与改动前完全一致）。
  bool _guardEntertainmentTab(int i) {
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);
    // 防沉迷拦截口径：
    //  · release（!kDebugMode）→ 照常拦截；
    //  · debug → 调试开关 [_debugCapBypass]（默认 true = 绕过）或
    //    `--dart-define=DISABLE_APP_CAP=true` 任一命中即不拦；测试可把
    //    `kPrefDebugCapBypass` 写 false 恢复拦截（child_shell_app_cap_test）。
    const bool defineBypass =
        bool.fromEnvironment('DISABLE_APP_CAP', defaultValue: false);
    final bool capEnforced = !kDebugMode || (!_debugCapBypass && !defineBypass);
    if (!capEnforced || !ctrl.isEntertainmentTab(i)) return true;

    final AppUsageState usage = ref.read(appUsageControllerProvider);
    // F99：先判单次锁定（比「到顶」更早触发：玩满 10 分钟即锁，与日总量无关）。
    if (usage.sessionLockedAt(DateTime.now())) {
      unawaited(_showSessionLockDialog()); // 单次到点：不切换索引，仅给引导。
      return false;
    }
    if (usage.reached) {
      unawaited(_showAppCapDialog(usage.capMinutes)); // 到顶：不切换索引，仅给引导。
      return false;
    }
    return true;
  }

  /// F99：娱乐 tab 前台**中途**触发单次锁定 → 自动踢回「今日」tab 并给引导卡。
  ///
  /// 场景：孩子一直停在花园里玩，10 分钟单次计时在某个 tick 到点——若只在「点 tab」
  /// 时拦截，人会继续留在花园（计时虽已停，页面照用）。监听状态变化即时收口。
  /// 「日上限到顶」中途命中的旧缺口一并补上（reached 同样踢）。
  void _onUsageStateChanged(AppUsageState usage) {
    if (!mounted) return;
    // 调试期绕过（C47c 补齐，与 [_onSelectTab] 同口径）：开关开启时**自动踢人**同样
    // 不生效。此前只有「点 tab」路径读 [_debugCapBypass]，自动分支照踢 → 模拟器上
    // 娱乐时长到顶后点进商店会被立刻弹窗踢回今日（调试期自相矛盾）。release 不受影响。
    const bool defineBypass =
        bool.fromEnvironment('DISABLE_APP_CAP', defaultValue: false);
    if (kDebugMode && (_debugCapBypass || defineBypass)) return;
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);
    if (!ctrl.isEntertainmentTab(_index)) return;
    final bool sessionLocked = usage.sessionLockedAt(DateTime.now());
    if (usage.reached || sessionLocked) {
      unawaited(_usageCtrl?.stopCounting()); // 立即停表（锁定触发时控制器已停，幂等）。
      unawaited(
        sessionLocked ? _showSessionLockDialog() : _showAppCapDialog(usage.capMinutes),
      );
      setState(() => _index = 0);
      ref.read(childShellTabIndexProvider.notifier).state = 0; // F71 同步。
    }
  }

  /// 单次使用到点的**分因温和提示**（与 [AppCapDialog] 同视觉语言，文案区分）。
  ///
  /// 点「去今日开始专注」→ 关弹窗并直接切到「今日」tab（非娱乐 tab，随手停表）。
  Future<void> _showSessionLockDialog() async {
    final Object? result = await showDialog<Object>(
      context: context,
      builder: (BuildContext ctx) => const AppCapDialog.sessionLock(),
    );
    if (result == AppCapDialog.goFocus && mounted) {
      unawaited(_usageCtrl?.stopCounting()); // 今日不计入娱乐时长。
      setState(() => _index = 0);
      ref.read(childShellTabIndexProvider.notifier).state = 0; // F71 同步。
    }
  }

  /// App 总时长到顶的**分因温和提示**（儿童风多色卡片，见 [AppCapDialog]）。
  ///
  /// 用户点「去今日开始专注」→ 关弹窗并直接切到「今日」tab（非娱乐 tab，随手停表）。
  Future<void> _showAppCapDialog(int capMinutes) async {
    final Object? result = await showDialog<Object>(
      context: context,
      builder: (BuildContext ctx) => AppCapDialog(capMinutes: capMinutes),
    );
    if (result == AppCapDialog.goFocus && mounted) {
      unawaited(_usageCtrl?.stopCounting()); // 今日不计入娱乐时长。
      setState(() => _index = 0);
      ref.read(childShellTabIndexProvider.notifier).state = 0; // F71 同步。
    }
  }

  /// 当前孩子 id（C90 期 2 第二批：已读通知键按孩子分键；同步 getter，
  /// AccountService 桩模式 → 默认孩子，不触数据库）。
  String _currentChildId() => ref.read(accountServiceProvider).childId;

  /// 进入孩子端即检查「家长已核销」通知：有未读则弹窗告知，并标记已读。
  ///
  /// 判定口径：`verifiedRequests()` 中 id 不在 shared_preferences 已读列表里的申请。
  /// C90 期 2：已读列表按当前孩子分键（历史全局键不迁移）。
  /// 🔴 C91 二轮（玄参：核销确认卡跨孩子泄漏）：diff 的「待展示列表」与「已读
  /// 快照键」必须**同属本次检查捕获的 childId** —— 数据源（F123 仓储级过滤）
  /// 之外再按 childId 过滤一次；其他孩子的行（旧版本库 / 未过滤调用点 /
  /// 切孩子瞬间的旧快照）绝不 diff 进当前孩子的快照键，也绝不会被当前孩子的
  /// 「知道啦」写坏（已读状态双向串改 = 泄漏）。
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkVerifiedNotices() async {
    try {
      final RewardRepository repo = ref.read(rewardRepositoryProvider);
      final SettingsStore store = ref.read(settingsStoreProvider);
      final String childId = _currentChildId();

      final List<RedemptionRequest> verified = await repo.verifiedRequests();
      // 🔴 C91 二轮：第二层跨孩子防线 —— 只认本次检查所属孩子的行。
      final List<RedemptionRequest> mine = verified
          .where((RedemptionRequest r) => r.childId == childId)
          .toList();
      if (mine.isEmpty) return;

      final List<String> acked =
          await store.acknowledgedVerifyIds(childId: childId);
      final Set<String> ackedSet = acked.toSet();
      final List<RedemptionRequest> news =
          mine.where((RedemptionRequest r) => !ackedSet.contains(r.id)).toList();
      if (news.isEmpty) return;

      final List<RewardTemplate> tpls = await repo.templates();
      final Map<String, String> names = <String, String>{
        for (final RewardTemplate t in tpls) t.id: t.name,
      };
      if (!mounted) return;

      final int total =
          news.fold(0, (int s, RedemptionRequest r) => s + r.cost);
      // F126：卡片视觉/布局改走 `gold_notice_dialog.dart` 的**统一实现** ——
      // 兑换核销卡与任务审批卡共用一份壳，避免两份近似布局各自漂移。
      await showGoldNoticeDialog(
        context,
        // ⚠️ 标题字面量被 nav_structure_test 钉死，不要改（F126 只**新增**任务审批
        // 卡，既有兑换卡文案一字不动）。
        title: '🎉 家长已确认你的兑换',
        items: <GoldNoticeItem>[
          for (final RedemptionRequest r in news)
            GoldNoticeItem(
              icon: Icons.redeem,
              name: names[r.templateId] ?? '奖励',
              amountText: '-${r.cost} 阳光',
            ),
        ],
        footerText: '共扣除 $total 阳光',
      );

      // 标记已读（去重合并），下次进入不再重复弹窗（按当前孩子分键）。
      await store.setAcknowledgedVerifyIds(
        <String>{...acked, ...news.map((RedemptionRequest r) => r.id)}.toList(),
        childId: childId,
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// 进入孩子端即检查「家长拒绝」通知（B4 对称通知）：家长拒绝后孩子端也弹窗告知。
  ///
  /// 判定口径：`rejectedRequests()` 中 id 不在 shared_preferences 已读列表里的申请。
  /// C90 期 2：已读列表按当前孩子分键（历史全局键不迁移）。
  /// 🔴 C91 二轮：与 [_checkVerifiedNotices] 同款第二层跨孩子防线
  ///（「待展示列表」与「已读快照键」同属本次检查捕获的 childId）。
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkRejectedNotices() async {
    try {
      final RewardRepository repo = ref.read(rewardRepositoryProvider);
      final SettingsStore store = ref.read(settingsStoreProvider);
      final String childId = _currentChildId();

      final List<RedemptionRequest> rejected = await repo.rejectedRequests();
      // 🔴 C91 二轮：第二层跨孩子防线 —— 只认本次检查所属孩子的行。
      final List<RedemptionRequest> mine = rejected
          .where((RedemptionRequest r) => r.childId == childId)
          .toList();
      if (mine.isEmpty) return;

      final List<String> acked =
          await store.acknowledgedRejectIds(childId: childId);
      final Set<String> ackedSet = acked.toSet();
      final List<RedemptionRequest> news =
          mine.where((RedemptionRequest r) => !ackedSet.contains(r.id)).toList();
      if (news.isEmpty) return;

      final List<RewardTemplate> tpls = await repo.templates();
      final Map<String, String> names = <String, String>{
        for (final RewardTemplate t in tpls) t.id: t.name,
      };
      if (!mounted) return;

      // F141 ②：改走孩子端统一**通知卡**壳（`gold_notice_dialog.dart`）。
      // 语义档位用 [NoticeTone.warn]：这是**坏消息**（申请被拒），经金色奖杯
      // 庆祝卡告知是反语义的；warn 档复用 App 既有警示红（不新造色值）。
      await showGoldNoticeDialog(
        context,
        tone: NoticeTone.warn,
        badgeIcon: Icons.block,
        title: '🚫 兑换未被通过',
        items: <GoldNoticeItem>[
          for (final RedemptionRequest r in news)
            GoldNoticeItem(
              icon: Icons.redeem,
              // ⚠️ 兜底串 '奖励' / '家长拒绝了该申请' 保持语义不变（原实现同款兜底）。
              name: '· ${names[r.templateId] ?? '奖励'}',
              // F141 修 1（QA 探针 F141-BUG-01）：家长备注是**说明**不是金额 ——
              // 走 `subtitle`（名称下方小字、可自由折行），不再塞右侧 amountText，
              // 也不再用 `amountMuted` 借位表达「备注」。小屏 + 长备注不再溢出。
              subtitle: '（${r.parentNote ?? '家长拒绝了该申请'}）',
            ),
        ],
        footerText: '本次阳光未被扣除，可重新兑换其他奖励',
      );

      await store.setAcknowledgedRejectIds(
        <String>{...acked, ...news.map((RedemptionRequest r) => r.id)}.toList(),
        childId: childId,
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// 进入孩子端即检查「家长审批成长任务」通知（F126 补体验缺口）：家长在
  /// 「今日」页点「确认发放」后，孩子端也要看到一张金色确认卡 —— 与兑换核销卡
  /// 完全对称，否则孩子**感知不到任务被确认了**（此前只有家长端一条 SnackBar）。
  ///
  /// ## 判定口径（为什么是这几条）
  /// 数据源 = `checkInsByStatus(CheckInStatus.verified)`，再按下列三条件筛：
  ///  · **`resolvedAt != null`**：`verified` 同时装「家长手动审批通过」与「联动项
  ///    自动结算」（如专注联动自动打卡），后者 `resolvedAt == null` —— 自动结算
  ///    不是家长的动作，绝不能弹「家长已确认」卡（否则孩子会以为家长一直在看）；
  ///  · **最近 [kTaskVerifiedNoticeWindow]（24 小时）内被处理**：`verified` 里躺着
  ///    全部历史打卡（老库升级默认即 verified），不限窗首次上线会一次弹几十条；
  ///  · **最多 [kTaskVerifiedNoticeMaxItems] 条**：按 `resolvedAt` 倒序取最新几条，
  ///    超出部分**不写已读快照**，留到下次进入逐批补弹（不丢通知、不撑爆屏幕）。
  ///
  /// ## 跨孩子防线（C91 二轮口径的边界说明）
  /// `CheckIn` 实体**没有** `childId` 字段（构造器被大量测试夹具直接调用，加字段
  /// 会牵连一大片签名），故本方法**无法**像 [_checkVerifiedNotices] 那样再做一次
  /// `where(childId == childId)`。当前层依赖的是：
  ///  · 数据源侧的仓储级过滤 —— `TaskLocalRepository.checkInsByStatus` 内部按
  ///    注入的 `AccountService.childId` 过滤（F123 同源，与 `_currentChildId()`
  ///    读的是**同一个** AccountService 实例，快照键因此与数据同属一个孩子）；
  ///  · 已读快照键按 `childId` 分键（`acked_task_checkin_ids_read_$childId`）。
  /// ⚠️ 残留风险：若将来出现**未过滤**的 `CheckInAdminRepository` 实现（测试桩 /
  /// 新数据源把整表吐出来），本层拦不住跨孩子泄漏 —— 到那时正确的修法是给
  /// `CheckIn` 补 `childId` 字段并照 C91 二轮再过滤一次，而不是在 UI 层猜。
  ///
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkTaskVerifiedNotices() async {
    try {
      final TaskRepository taskRepo = ref.read(taskRepositoryProvider);
      // 能力探测（先例：`TaskCheckInService`）：打卡核销接口与 TaskRepository
      // 刻意分离，测试用的轻量 Fake 不实现它 → 直接跳过，不报错。
      // ⚠️ 两个接口**无继承关系**，Dart 不会自动 promote，故显式转型。
      if (taskRepo is! CheckInAdminRepository) return;
      final CheckInAdminRepository admin = taskRepo as CheckInAdminRepository;
      final SettingsStore store = ref.read(settingsStoreProvider);
      final String childId = _currentChildId();

      final List<CheckIn> verified =
          await admin.checkInsByStatus(CheckInStatus.verified);
      // 时间窗与「当前时刻」各取一次快照：避免循环内多次 `DateTime.now()` 漂移，
      // 也让「24 小时内」的边界判定可复现（测试夹具一律相对 `DateTime.now()`）。
      final DateTime now = DateTime.now();
      final DateTime windowStart = now.subtract(kTaskVerifiedNoticeWindow);

      final List<CheckIn> recentlyResolved = verified
          // ⚠️ 自动结算（resolvedAt == null）绝不算「家长审批」，必须排除。
          .where((CheckIn c) => c.resolvedAt != null)
          .where((CheckIn c) => !c.resolvedAt!.isBefore(windowStart))
          .toList()
        ..sort((CheckIn a, CheckIn b) =>
            b.resolvedAt!.compareTo(a.resolvedAt!)); // 最新处理在前。
      if (recentlyResolved.isEmpty) return;

      final List<String> acked =
          await store.acknowledgedTaskCheckInIds(childId: childId);
      final Set<String> ackedSet = acked.toSet();
      // 先剔除已读再截断：否则「最新 3 条已读」会永久挡住后面的未读条目。
      final List<CheckIn> news = recentlyResolved
          .where((CheckIn c) => !ackedSet.contains(c.id))
          .take(kTaskVerifiedNoticeMaxItems)
          .toList();
      if (news.isEmpty) return;

      // 任务名映射：任务可能已被删除 → 回退「成长任务」，绝不给空标题。
      final List<Task> allTasks = await taskRepo.tasks();
      final Map<String, String> taskNames = <String, String>{
        for (final Task t in allTasks) t.id: t.name,
      };
      if (!mounted) return;

      // 每条金额**一律取 `sunlightGranted`（实发）**，绝不回退 `sunlightGross`。
      // 为什么（F126 二轮 QA 抓到的口径错误）：`verified` 状态下 `sunlightGranted`
      // 就是真实入账额；当日成长奖励额度用尽（`kTaskCheckinDailyCap`）时
      // `verifyCheckIn` 仍以 `granted = 0 + gross = 12` 落库，若回退成 gross 就会
      // 对孩子**虚报**「+12 阳光」而实际入账 0 —— 这是钱，必须说实发。
      // ⚠️ 老库 `granted = 0 && resolvedAt == null` 的历史行**走不到这里**：上面的
      // `resolvedAt != null` 已把它们全部滤掉，故「取 granted 会误伤老数据」不成立。
      int grantedOf(CheckIn c) => sunlightDisplayInt(c.sunlightGranted);

      // 🔴 F126 三轮：**封顶判据与显示取整解耦**。
      // 「是否封顶」必须看**原始 double**（`<= 0`）；`grantedOf` 只负责「显示取整」
      // （F105 向下取整口径）。若拿 `grantedOf(c) == 0` 当判据，`granted = 0.4`
      // 这种「入了账但不足 1」的行会被误判成封顶 → 条目误报「今日额度已满」、
      // 合计误报「本次没有新增阳光」（QA 二轮实测）。
      // 注：当前写路径（`_rewardFor` 全整数 + `_dailyRewardGrant` 只补差额）实际
      // 产不出 0.4，本解耦是防「判据坏耦合」，不是修一个已可达的 bug。
      bool isCapped(CheckIn c) => c.sunlightGranted <= 0;

      final int total = news.fold(0, (int s, CheckIn c) => s + grantedOf(c));
      final int cappedCount = news.where(isCapped).length;

      // 底部合计三档（确认这件事一定发生了，但钱可能没到）：
      //  · 全部实发 > 0 → 共获得 N 阳光；
      //  · 部分封顶      → 共获得 N 阳光（X 项今日额度已满，未发放）；
      //  · 全部封顶      → 今日成长奖励已达上限，本次没有新增阳光。
      // ⚠️ 「全部封顶」判据用 `cappedCount == news.length`（按条数），**不能**用
      // `total == 0`：全是 0.4 时 total 也等于 0，但那不是封顶（实际入了账）。
      final String footer;
      if (cappedCount == news.length) {
        footer = '今日成长奖励已达上限，本次没有新增阳光';
      } else if (cappedCount > 0) {
        footer = '共获得 $total 阳光（$cappedCount 项今日额度已满，未发放）';
      } else {
        footer = '共获得 $total 阳光';
      }

      await showGoldNoticeDialog(
        context,
        title: '🎉 家长已确认你的成长任务',
        items: <GoldNoticeItem>[
          for (final CheckIn c in news)
            GoldNoticeItem(
              // 图标不随「是否封顶」变化：确认这件事本身成立，只是钱没到。
              icon: Icons.task_alt,
              name: taskNames[c.taskId] ?? '成长任务',
              // NEW-F141-01（QA 二轮）：`今日额度已满` 是**说明**不是金额 ——
              // 塞进金额位（行内剩余宽度的 40%，390 屏 = 87.2px）会被 6 个汉字
              // 顶成两行（96px > 87.2px），断在第 5 个字上（右对齐「今日额度已」/「满」）。
              // 改为：封顶行金额位留空（`amountText: ''` → 该列整块不渲染），
              // 说明走 `subtitle`（名称下方小字、可自由折行）。
              // ⚠️ 文案逐字不变：`今日额度已满` 仍出现，只是换了槽位。
              amountText: isCapped(c) ? '' : '+${grantedOf(c)} 阳光',
              subtitle: isCapped(c) ? '今日额度已满' : null,
            ),
        ],
        footerText: footer,
      );

      // 标记已读（去重合并；按当前孩子分键）。⚠️ 必须在弹窗关闭**之后**写，
      // 否则「未看先读」会把卡片永久吞掉。
      await store.setAcknowledgedTaskCheckInIds(
        <String>{...acked, ...news.map((CheckIn c) => c.id)}.toList(),
        childId: childId,
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// 汇总检查：家长已核销（M2）+ 家长拒绝（B4）+ 家长审批成长任务（F126）。
  ///
  /// 顺序**刻意**把新增的任务审批卡放在最后：既有两条卡片的弹出次序 / 去重口径
  /// 保持一字不变（已被 `nav_structure_test` / `c91` 钉死），新卡只在它们都无未读
  /// 时才轮到，避免打断既有体验。
  Future<void> _checkAllNotices() async {
    await _checkVerifiedNotices();
    await _checkRejectedNotices();
    await _checkTaskVerifiedNotices();
  }

  @override
  Widget build(BuildContext context) {
    // B5：核销同步弹窗时机修复 —— 家长核销会自增经济修订号，孩子端外壳（若仍挂载）
    // 监听修订号变化即重新检查「家长已核销」通知，避免仅 initState 触发一次、
    // 页面未重建则不弹的隐患。已读集合在仓库层去重，不会重复弹窗。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _checkAllNotices();
    });
    // F99：使用时长状态变化（单次锁定触发 / 日上限到顶）→ 人在娱乐 tab 时即时收口。
    ref.listen(appUsageControllerProvider, (_, AppUsageState next) {
      _onUsageStateChanged(next);
    });

    // C44（玄参 2026-10-09 拍板沉浸式）：今日(0)/成长(1)/商店(3) 三个 tab 用
    // 整页背景图（「上半场景+下半留白」设计）→ AppBar 透明 + body 延伸到 AppBar
    // 底下，背景得以铺到状态栏顶。花园(2)自带整页草地、我的(4)纯色底，维持原样。
    final bool immersive = _index == 0 || _index == 1 || _index == 3;

    return Scaffold(
      extendBodyBehindAppBar: immersive,
      appBar: AppBar(
        // C44e 二轮反馈（玄参 2026-10-09）：深棕字仍被亮背景吃掉 → 标题垫
        // **半透白胶囊**，任何场景底上都清晰（成长/商店 tab 同款，风格统一）。
        title: immersive
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_titles[_index]),
              )
            : Text(_titles[_index]),
        // 沉浸式三连：透明底 + 无阴影 + 滚动也不浮起阴影（否则透明底上出现色带）。
        backgroundColor: immersive ? Colors.transparent : null,
        elevation: immersive ? 0 : null,
        scrolledUnderElevation: immersive ? 0 : null,
        // C44 验收反馈（玄参 2026-10-09）：沉浸式背景是亮色场景，默认前景色
        // （白）的标题和右上家长图标「看不清」→ 换深暖棕，对比度足够且不抢戏。
        foregroundColor: immersive ? const Color(0xFF6B4A2B) : null,
        // 状态栏（时间/电量）同理：亮背景上白图标看不清 → 深色系统栏图标。
        systemOverlayStyle:
            immersive ? SystemUiOverlayStyle.dark : null,
        // 左上角余额胶囊：花园 tab（index 2）用 [SunlightPill]；商店 tab（index 3）
        // 用 [StoreBalancePill]（C47c 玄参 2026-10-09：「余额要在左上角跟『商店』
        // 一个水平位置」）。挂 AppBar `leading` 是唯一能保证与标题**严格同一行**的
        // 挂法——body 内自算偏移会被 Scaffold/SafeArea 的 padding 差异带偏（实测
        // iOS 模拟器 body 侧安全区 ≈118pt，比 AppBar 侧多 ≈39pt，导致余额被压低）。
        // 宽度：容纳「☀ + 6 位数余额（+ 待核销 N）」，配胶囊内 FittedBox 兜底。
        leadingWidth: _index == 2
            ? 112.0
            : (_index == 3 ? 160.0 : null),
        leading: switch (_index) {
          2 => const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Center(child: SunlightPill()),
            ),
          3 => const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StoreBalancePill(),
              ),
            ),
          _ => null,
        },
        actions: <Widget>[
          // 🔑 抽成 [ParentEntryAction] 单点收口：shell 与度量测试引用同一份 widget，
          // 测试量到的就是真实渲染的图标（v3 徽章右对齐到家长图标所在竖线，
          // 见 parent_entry_action.dart 文档）。两种形态（沉浸式垫白胶囊 / 裸图标）
          // 与原内联版逐位一致，仅多挂一个 [ParentEntryAction.iconKey] 供度量。
          ParentEntryAction(immersive: immersive),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          // 隐藏 tab 停掉动画（见 [_tabs] 注释）：当前 tab 正常动画，后台 tab 静音。
          for (int i = 0; i < _tabs.length; i++)
            TickerMode(enabled: i == _index, child: _tabs[i]),
        ],
      ),
      // C61 平板适配：平板下限宽居中，避免 5 个 destination 被拉散；手机端原样（零变化）。
      bottomNavigationBar: AdaptiveNavBarHost(
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onSelectTab,
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: '今日',
            ),
            NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: '成长',
            ),
            NavigationDestination(
              icon: Icon(Icons.yard_outlined),
              selectedIcon: Icon(Icons.yard),
              label: '花园',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: '商店',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
