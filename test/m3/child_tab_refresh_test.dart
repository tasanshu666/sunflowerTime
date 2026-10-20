/// C68 护栏：孩子端 tab「可见即刷新 + 时间边界兜底刷新」。
///
/// ## 背景（玄参 2026-10-14 iPad 模拟器实测反馈）
/// 进花园看到盛开的「珊瑚岭兰」**没有产生阳光** → 随手点开一个花盆 → 弹出卡片 →
/// 退出卡片后**看到了**阳光。根因不是奖励没发（库里一直是好的），而是**页面不刷新**：
/// 孩子端 5 个 tab 由外壳 `IndexedStack` 保活，原先只有「首次挂载 / 经济修订号变化 /
/// 页面内动作」三类触发，缺 **切回本 tab**、**App 回前台**、**停在页面上跨过 08:00
/// 或跨天**这三类时间性触发 → 08:00 到期的晨露行虽然已 in 库，却一直不出现在头顶气泡里。
///
/// 机制与接线见 `lib/presentation/child/state/child_tab_refresh.dart`（口径 C68）。
/// 本文件只测**机制本身**（用探针页挂 mixin + 可拨动的假时钟）；5 个真实页面的接线
/// 另由 `test/m2/store_page_test.dart` 的「C68：切回商店 tab」用例做端到端验证。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';

void main() {
  // ── 方案 B 的判据（纯函数）─────────────────────────────────────────────
  group('shouldRefreshForTimeBoundary（跨 08:00 / 跨天 才刷）', () {
    test('同一天、未跨 08:00 → 不刷', () {
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 9), DateTime(2026, 10, 14, 9, 30)),
        isFalse,
      );
    });

    test('同一天、跨过 08:00 → 刷（这一条正是玄参反馈的晨露场景）', () {
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 7, 30), DateTime(2026, 10, 14, 8, 10)),
        isTrue,
      );
    });

    test('08:00 整点算「已跨过」（last 07:59:59 → now 08:00:00）', () {
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 7, 59, 59), DateTime(2026, 10, 14, 8)),
        isTrue,
      );
    });

    test('08:00 之后不重复触发（08:10 → 09:00）', () {
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 8, 10), DateTime(2026, 10, 14, 9)),
        isFalse,
      );
    });

    test('跨天 → 刷（成长 / 枯萎 / 花谢 / 杂草害虫 / 周池都按「天」结算）', () {
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 23), DateTime(2026, 10, 15, 0, 2)),
        isTrue,
      );
      // 跨天且早于 08:00 也算跨天。
      expect(
        shouldRefreshForTimeBoundary(
            DateTime(2026, 10, 14, 20), DateTime(2026, 10, 15, 7)),
        isTrue,
      );
    });

    test('时钟回拨 / 时间未推进 → 一律不刷（防抖动反复刷）', () {
      final DateTime t = DateTime(2026, 10, 14, 10);
      expect(shouldRefreshForTimeBoundary(t, t), isFalse);
      expect(
        shouldRefreshForTimeBoundary(
            t, t.subtract(const Duration(minutes: 5))),
        isFalse,
      );
    });
  });

  // ── 机制行为（探针页挂 mixin）───────────────────────────────────────────
  group('ChildTabAutoRefresh（切 tab / 回前台 / 时间边界）', () {
    testWidgets('切回本 tab → 刷新一次；切走 → 不刷；再切回 → 再刷', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday); // 初始停在「今日」，花园不可见
      expect(h.calls, 0, reason: '不可见的 tab 不该有任何刷新');

      h.goTab(kChildTabIndexOfGarden);
      await tester.pump();
      expect(h.calls, 1,
          reason: '方案 A：切回本 tab 必须重读数据（否则停在旧快照，看不到已到期的奖励）');

      h.goTab(kChildTabIndexOfStore); // 切走
      await tester.pump();
      expect(h.calls, 1, reason: '切走的 tab 不刷新（隐藏页不白跑重活）');

      h.goTab(kChildTabIndexOfGarden); // 再切回
      await tester.pump();
      expect(h.calls, 2);
    });

    testWidgets('可见时回前台 → 刷；不可见时回前台 → 不刷', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday);

      await h.backgroundThenResume();
      expect(h.calls, 0, reason: '本页不可见 → 回前台不该刷它（可见的那个 tab 会自己刷）');

      h.goTab(kChildTabIndexOfGarden);
      await tester.pump();
      expect(h.calls, 1);

      await h.backgroundThenResume();
      expect(h.calls, 2, reason: '方案 A：回到前台且本页可见 → 必须重读（可能跨了很久）');
    });

    testWidgets('停在页面上跨过 08:00 → 定时器兜底刷新，且不重复', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfGarden);
      expect(h.calls, 0, reason: '首次挂载由页面自身 initState 的 _reload 负责，本 mixin 不重复刷');
      expect(h.now, DateTime(2026, 10, 14, 7, 30));

      // 07:30 → 07:31：没跨边界，别刷。
      await tester.pump(const Duration(seconds: 61));
      expect(h.calls, 0, reason: '未跨边界绝不刷（不能退化成「每分钟 tick 一次」）');

      // 时间跨过 08:00（孩子一直停在花园不动）。
      h.now = DateTime(2026, 10, 14, 8, 30);
      await tester.pump(const Duration(seconds: 61));
      expect(h.calls, 1, reason: '方案 B：跨过 08:00 → 晨露已到期 → 必须重算头顶气泡');

      // 再等一分钟：同一天、08:00 之后 → 不重复刷。
      await tester.pump(const Duration(seconds: 61));
      expect(h.calls, 1, reason: '08:00 之后不重复触发（基准已推进到 08:30）');
    });

    testWidgets('停在页面上跨天 → 定时器兜底刷新', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      // ⚠️ 起始时刻取 09:00（**已在 08:00 之后**）：否则「拨到当晚 23:00」会先命中
      // 「同一天跨过 08:00」这条，测不出跨天本身。
      h.now = DateTime(2026, 10, 14, 9);
      await h.mount(initialTab: kChildTabIndexOfGarden);

      await tester.pump(const Duration(seconds: 61)); // 时钟未拨动 → 不刷
      expect(h.calls, 0);

      h.now = DateTime(2026, 10, 15, 0, 2); // 跨天
      await tester.pump(const Duration(seconds: 61));
      expect(h.calls, 1, reason: '跨天要重读（成长 / 枯萎 / 杂草害虫 / 周池都按天滚动）');
    });

    testWidgets('⚠️ 不可见的 tab：定时器根本不跑（省电 + 不白跑重活）', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday); // 花园隐藏
      h.now = DateTime(2026, 10, 14, 8, 30);
      await tester.pump(const Duration(minutes: 3));
      expect(h.calls, 0);
    });

    testWidgets('在途去重：刷新未完成时，后续触发不叠加', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday);
      h.gate = Completer<void>();

      h.goTab(kChildTabIndexOfGarden); // 触发第 1 次（挂住不完成）
      await tester.pump();
      expect(h.calls, 1);

      await h.backgroundThenResume(); // 触发 2：在途 → 应被挡下
      expect(h.calls, 1);

      h.now = DateTime(2026, 10, 14, 8, 30); // 触发 3：边界 → 也应被挡下
      await tester.pump(const Duration(seconds: 61));
      expect(h.calls, 1, reason: '在途闸门：连发触发只跑一次');

      h.gate!.complete(); // 第 1 次收尾
      await tester.pump();
      await h.backgroundThenResume(); // 触发 4：闸门已复位 → 正常刷
      expect(h.calls, 2);
    });

    testWidgets('卸载后定时器停止（不留 pending timer / 不再刷）', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfGarden);

      await tester.pumpWidget(const SizedBox()); // 卸载 → dispose
      h.now = DateTime(2026, 10, 14, 8, 30);
      await tester.pump(const Duration(minutes: 5));
      expect(h.calls, 0, reason: 'dispose 后必须取消定时器（否则测试会报 pending timer，真机则泄漏）');
    });

    testWidgets('不在外壳里（refreshTabIndex = null）→ 恒可见，只吃回前台 / 边界', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday, standalone: true);
      expect(h.calls, 0);

      await h.backgroundThenResume();
      expect(h.calls, 1, reason: '路由直推的页（如 GardenPage(embedded:false)）不在外壳里 → 回前台即刷');

      h.goTab(kChildTabIndexOfStore); // 外壳切 tab 与它无关
      await tester.pump();
      expect(h.calls, 1, reason: '不在外壳里的页不该被外壳 tab 变化牵动');
    });
  });

  // ── 常量一致性（防复制粘贴串号）─────────────────────────────────────────
  test('5 个孩子端 tab 下标唯一且覆盖 0..4', () {
    expect(
      <int>{
        kChildTabIndexOfToday,
        kChildTabIndexOfGrowth,
        kChildTabIndexOfGarden,
        kChildTabIndexOfStore,
        kChildTabIndexOfProfile,
      },
      <int>{0, 1, 2, 3, 4},
      reason: '两页共用一个下标 = 一页永远「不可见」→ 永远不会自动刷新',
    );
    expect(kChildTabCount, 5);
  });

  // ── C90 期 2：孩子档案修订号触发（家长端切孩子 → 统一刷，不要求可见）────
  group('ChildTabAutoRefresh · C90 期 2 修订号触发', () {
    testWidgets('修订号变化 → 可见的 tab 刷新', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfGarden);
      expect(h.calls, 0);

      h.bumpChildProfileRevision();
      await tester.pump();
      expect(h.calls, 1,
          reason: 'C90 期 2：家长端切换/新建/编辑/删除孩子 → 修订号自增 → 必须重读'
              '（数据源已按孩子隔离，不刷 = 上个孩子的快照）');
    });

    testWidgets('⚠️ 不可见的 tab 也刷新（IndexedStack 隐藏页也在台上，统一换数据源）',
        (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday); // 花园隐藏
      expect(h.calls, 0);

      h.bumpChildProfileRevision();
      await tester.pump();
      expect(h.calls, 1,
          reason: '这是 mixin「刻意不覆盖不可见 tab」纪律的唯一例外（C90 期 2 拍板）');
    });

    testWidgets('修订号不变 → 不刷', (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfGarden);

      h.goTab(kChildTabIndexOfStore); // 切走（不触发修订号）
      await tester.pump();
      expect(h.calls, 0);
    });

    // ── F138：外壳上下台是**独立的**可见性输入 ────────────────────────────
    testWidgets('F138：外壳下台 → 本页不可见（不刷）；重新上台 → 立即刷一次',
        (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfGarden);
      expect(h.calls, 0, reason: '首帧不算「由隐藏变可见」，不刷新');

      h.setOnStage(false); // 外壳被 go('/parent') 销毁（tab 记忆仍是花园）
      await tester.pump();
      expect(h.calls, 0, reason: '外壳不在台前 → 没人看得到本页，不刷新');

      h.setOnStage(true); // 新外壳挂载上台（记忆值恢复成花园 → 本页重新可见）
      await tester.pump();
      expect(h.calls, 1,
          reason: 'F138：外壳重新上台 = 可见性变化，必须补刷一次（否则看到离开前的旧快照）');
    });

    testWidgets('F138：外壳下台后再切 tab 不刷（不可见期间不白跑重活）',
        (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.mount(initialTab: kChildTabIndexOfToday);
      h.setOnStage(false);
      await tester.pump();

      h.goTab(kChildTabIndexOfGarden); // 记忆值变了，但外壳不在台前
      await tester.pump();
      expect(h.calls, 0,
          reason: 'F138 真机 bug 同源：只有 tab 索引（记忆）不能证明本页在被人看');
    });
  });
}

/// 只挂 [ChildTabAutoRefresh] 的探针页：把「刷新被调用」记进 [_Harness.calls]。
class _Probe extends ConsumerStatefulWidget {
  const _Probe({required this.onRefresh, required this.now, this.tabIndex});

  final Future<void> Function() onRefresh;
  final DateTime Function() now;

  /// `null` = 不在外壳里（模拟路由直推页）。
  final int? tabIndex;

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe>
    with ChildTabAutoRefresh<_Probe> {
  @override
  int? get refreshTabIndex => widget.tabIndex;

  @override
  DateTime refreshNow() => widget.now();

  @override
  Future<void> onTabRefreshRequested() => widget.onRefresh();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 测试脚手架：可控外壳 tab 索引 + 可拨动假时钟 + 调用计数 + 在途闸门。
class _Harness {
  _Harness(this.tester) : container = ProviderContainer();

  final WidgetTester tester;
  final ProviderContainer container;

  /// 假时钟（`refreshNow` 的注入源）——真实 `DateTime.now()` 在 `FakeAsync` 下**不会**
  /// 随 `tester.pump(Duration)` 前进，故边界判定必须靠它拨动。
  DateTime now = DateTime(2026, 10, 14, 7, 30);

  /// `onTabRefreshRequested` 被调用次数。
  int calls = 0;

  /// 非 null 时刷新会**挂住不返回**（验证在途去重）。
  Completer<void>? gate;

  Future<void> mount({
    required int initialTab,
    bool standalone = false,
    bool onStage = true,
  }) async {
    container.read(childShellTabIndexProvider.notifier).state = initialTab;
    // F138：可见性判据 = 「外壳在台前 **且** tab 索引是本页」。真实外壳由
    // `ChildShellPage.initState` 发布上台信号；本探针用例模拟「外壳在台上」，
    // 故显式摆好 —— 否则所有用例都会被判成不可见（假红）。
    container.read(childShellOnStageProvider.notifier).state = onStage;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: _Probe(
            tabIndex: standalone ? null : kChildTabIndexOfGarden,
            now: () => now,
            onRefresh: () async {
              calls++;
              if (gate != null) await gate!.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void goTab(int index) =>
      container.read(childShellTabIndexProvider.notifier).state = index;

  /// F138：外壳上台 / 下台（真实外壳由 `ChildShellPage.initState` / `dispose` 发布）。
  void setOnStage(bool value) =>
      container.read(childShellOnStageProvider.notifier).state = value;

  /// 模拟家长端切换 / 新建 / 编辑 / 删除孩子（C90 期 1：修订号自增）。
  void bumpChildProfileRevision() =>
      container.read(childProfileRevisionProvider.notifier).state++;

  /// 模拟「退后台 → 回前台」。
  ///
  /// ⚠️ 必须先切到一个**不同**的状态：`SchedulerBinding.handleAppLifecycleStateChanged`
  /// 遇到「状态没变」会直接 return，不派发给 observer（测试里初始态就是 resumed）。
  Future<void> backgroundThenResume() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }
}
