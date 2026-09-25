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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/state/app_usage_controller.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';

/// 孩子端外壳：底部导航 + 5 个 tab。
class ChildShellPage extends ConsumerStatefulWidget {
  const ChildShellPage({super.key});

  @override
  ConsumerState<ChildShellPage> createState() => _ChildShellPageState();
}

class _ChildShellPageState extends ConsumerState<ChildShellPage>
    with WidgetsBindingObserver {
  int _index = 0;

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
    // 首帧后再弹窗，避免在 build 期间触发路由/覆盖层变更。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAllNotices());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开外壳务必停表（同步取消 ticker），否则定时器泄漏 → 测试 pending timer 断言红。
    _stopAppUsageCounting();
    super.dispose();
  }

  // ── P0 · A App 总时长：生命周期 + 拦截 ───────────────────────────────

  /// App 切前后台：非前台一律暂停计时；回前台且仍处娱乐 tab 则恢复。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      if (ctrl.isEntertainmentTab(_index)) unawaited(ctrl.startCounting());
    } else {
      unawaited(ctrl.stopCounting());
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

  /// 点底部 tab：到顶则**只拦娱乐 tab**（不切换 + 温和提示），其余照常切换并启停计时。
  void _onSelectTab(int i) {
    final AppUsageState usage = ref.read(appUsageControllerProvider);
    final AppUsageController ctrl = ref.read(appUsageControllerProvider.notifier);

    if (ctrl.isEntertainmentTab(i) && usage.reached) {
      _showAppCapDialog(usage.capMinutes); // 到顶：不切换索引，仅给引导。
      return;
    }

    setState(() => _index = i);
    if (ctrl.isEntertainmentTab(i)) {
      unawaited(ctrl.startCounting());
    } else {
      unawaited(ctrl.stopCounting());
    }
  }

  /// App 总时长到顶的**分因温和提示**（点明原因 + 给出口；专注入口永远可用）。
  void _showAppCapDialog(int capMinutes) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('🌻 先歇一会儿吧'),
        content: Text('今天逛 App 的时间用完啦（上限 $capMinutes 分钟），去「今日」开始专注吧 🌻'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道啦'),
          ),
        ],
      ),
    );
  }

  /// 进入孩子端即检查「家长已核销」通知：有未读则弹窗告知，并标记已读。
  ///
  /// 判定口径：`verifiedRequests()` 中 id 不在 shared_preferences 已读列表里的申请。
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkVerifiedNotices() async {
    try {
      final RewardRepository repo = ref.read(rewardRepositoryProvider);
      final SettingsStore store = ref.read(settingsStoreProvider);

      final List<RedemptionRequest> verified = await repo.verifiedRequests();
      if (verified.isEmpty) return;

      final List<String> acked = await store.acknowledgedVerifyIds();
      final Set<String> ackedSet = acked.toSet();
      final List<RedemptionRequest> news =
          verified.where((RedemptionRequest r) => !ackedSet.contains(r.id)).toList();
      if (news.isEmpty) return;

      final List<RewardTemplate> tpls = await repo.templates();
      final Map<String, String> names = <String, String>{
        for (final RewardTemplate t in tpls) t.id: t.name,
      };
      if (!mounted) return;

      final int total =
          news.fold(0, (int s, RedemptionRequest r) => s + r.cost);
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('🎉 家长已确认你的兑换'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final RedemptionRequest r in news)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '· ${names[r.templateId] ?? '奖励'}  -${r.cost} 阳光',
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '共扣除 $total 阳光',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道啦'),
            ),
          ],
        ),
      );

      // 标记已读（去重合并），下次进入不再重复弹窗。
      await store.setAcknowledgedVerifyIds(
        <String>{...acked, ...news.map((RedemptionRequest r) => r.id)}.toList(),
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// 进入孩子端即检查「家长拒绝」通知（B4 对称通知）：家长拒绝后孩子端也弹窗告知。
  ///
  /// 判定口径：`rejectedRequests()` 中 id 不在 shared_preferences 已读列表里的申请。
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkRejectedNotices() async {
    try {
      final RewardRepository repo = ref.read(rewardRepositoryProvider);
      final SettingsStore store = ref.read(settingsStoreProvider);

      final List<RedemptionRequest> rejected = await repo.rejectedRequests();
      if (rejected.isEmpty) return;

      final List<String> acked = await store.acknowledgedRejectIds();
      final Set<String> ackedSet = acked.toSet();
      final List<RedemptionRequest> news =
          rejected.where((RedemptionRequest r) => !ackedSet.contains(r.id)).toList();
      if (news.isEmpty) return;

      final List<RewardTemplate> tpls = await repo.templates();
      final Map<String, String> names = <String, String>{
        for (final RewardTemplate t in tpls) t.id: t.name,
      };
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('🚫 兑换未被通过'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final RedemptionRequest r in news)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '· ${names[r.templateId] ?? '奖励'}'
                    '（${r.parentNote ?? '家长拒绝了该申请'}）',
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                '本次阳光未被扣除，可重新兑换其他奖励',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道啦'),
            ),
          ],
        ),
      );

      await store.setAcknowledgedRejectIds(
        <String>{...acked, ...news.map((RedemptionRequest r) => r.id)}.toList(),
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// 汇总检查：家长已核销（M2）+ 家长拒绝（B4）两类通知。
  Future<void> _checkAllNotices() async {
    await _checkVerifiedNotices();
    await _checkRejectedNotices();
  }

  @override
  Widget build(BuildContext context) {
    // B5：核销同步弹窗时机修复 —— 家长核销会自增经济修订号，孩子端外壳（若仍挂载）
    // 监听修订号变化即重新检查「家长已核销」通知，避免仅 initState 触发一次、
    // 页面未重建则不弹的隐患。已读集合在仓库层去重，不会重复弹窗。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _checkAllNotices();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        // 仅「花园」tab（index 2）在左上角展示阳光余额胶囊；其余 tab 外观完全不变
        // （不给它们留空 leading）。胶囊数据来自 sunlightBalanceProvider。
        // 112：容纳「☀ + 6 位数余额」胶囊（配合胶囊内 FittedBox 兜底任意位数）。
        leadingWidth: _index == 2 ? 112.0 : null,
        leading: _index == 2
            ? const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Center(child: SunlightPill()),
              )
            : null,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.family_restroom),
            tooltip: '家长天地',
            onPressed: () => context.go('/parent'),
          ),
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
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
