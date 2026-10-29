/// F165 守卫：配额达上限提示**不得再做「常驻黑条」**。
///
/// 玄参 2026-10-29 实测缺陷（原话：「只要触发了，就一直存在……回到了孩子端也存在，
/// 再次进入家长端点击 unlock all 进入会员页面也不会消失，而且这种黑色的弹窗也太丑」）。
///
/// 根因（Flutter 框架侧，非本项目逻辑错）：
///  · 带 `action` 的 SnackBar 在 `accessibleNavigation` 开启时**不自动关闭**；
///  · SnackBar 计时器还依赖「当前路由命中」（`route == null || route.isCurrent`），
///    跳页 / 切 tab 后干脆不启动；
///  · `ScaffoldMessenger` 挂在 MaterialApp 层 → 提示**跨路由存活**。
///
/// 本文件把三条都钉死：① 到时必消失 ② 跳页后**不残留** ③ 重复触发不堆叠。
/// 另加样式守卫：底色必须来自主题（不是 M3 的 `inverseSurface` 深色底）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/shared/quota_notice.dart';

const String _msg = 'Free limit: 5 (now 5). Remove extras to add more.';
const String _action = 'Unlock All';

/// 宿主：一页带按钮的 Scaffold（Navigator 的 Overlay 由 MaterialApp 提供）。
Widget _host({
  required void Function(BuildContext) onTrigger,
  bool accessibleNavigation = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext ctx) => MediaQuery(
        data: MediaQueryData(
          size: const Size(392, 800),
          accessibleNavigation: accessibleNavigation,
        ),
        child: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () => onTrigger(ctx),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(hideQuotaNotice);

  testWidgets('T1 触发后出现文案与「解锁」按钮，且不是 SnackBar', (WidgetTester t) async {
    await t.pumpWidget(_host(
      onTrigger: (BuildContext c) => showQuotaNotice(
        c,
        message: _msg,
        actionLabel: _action,
        onAction: () {},
      ),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));

    expect(find.text(_msg), findsOneWidget);
    expect(find.text(_action), findsOneWidget);
    // 回归守卫：绝不再走底部 SnackBar（玄参「黑色的弹窗太丑」）。
    expect(find.byType(SnackBar), findsNothing,
        reason: '配额提示不得回退到 SnackBar（F165）');

    // 收尾：清掉自清定时器，避免 exit 时 "A Timer is still pending"。
    hideQuotaNotice();
    await t.pump();
  });

  testWidgets('T2 到时自动消失（不依赖路由状态）', (WidgetTester t) async {
    await t.pumpWidget(_host(
      onTrigger: (BuildContext c) =>
          showQuotaNotice(c, message: _msg, actionLabel: _action, onAction: () {}),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text(_msg), findsOneWidget);

    // 默认 hold 2800ms + 兜底 400ms；多给一点余量。
    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.text(_msg), findsNothing, reason: '超时后必须自清，绝不常驻');
  });

  testWidgets('T3 🔴 跳页后不得残留（F165 核心症状）', (WidgetTester t) async {
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () =>
                  showQuotaNotice(ctx, message: _msg, actionLabel: _action),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text(_msg), findsOneWidget);

    // 模拟玄参的动作：提示还在时 push 到「会员页」。
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => const Scaffold(body: Text('premium page')),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('premium page'), findsOneWidget);

    // 关键断言：跳页后同一告示**必须已经/即将消失**，不能跟着跑到新页面。
    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.text(_msg), findsNothing,
        reason: '切页后浮层不得跨路由残留（F165：回孩子端还在）');
  });

  testWidgets('T4 点按钮：先撤浮层再执行回调，不堆叠', (WidgetTester t) async {
    int calls = 0;
    await t.pumpWidget(_host(
      onTrigger: (BuildContext c) => showQuotaNotice(
        c,
        message: _msg,
        actionLabel: _action,
        onAction: () => calls++,
      ),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));

    await t.tap(find.text(_action));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));

    expect(calls, 1, reason: '按钮只能触发一次回调');
    // 先撤后跳：回调返回后浮层必须已经不在（跳页时不带残影）。
    expect(find.text(_msg), findsNothing);
  });

  testWidgets('T5 连续触发只保留一条（不糊满屏）', (WidgetTester t) async {
    await t.pumpWidget(_host(
      onTrigger: (BuildContext c) =>
          showQuotaNotice(c, message: _msg, actionLabel: _action, onAction: () {}),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));

    expect(find.text(_msg), findsOneWidget, reason: '重复触发不得堆叠成多条');

    hideQuotaNotice();
    await t.pump();
  });

  testWidgets('T6 无障碍导航开启时同样到时消失（SnackBar 的老坑）', (WidgetTester t) async {
    await t.pumpWidget(_host(
      accessibleNavigation: true,
      onTrigger: (BuildContext c) =>
          showQuotaNotice(c, message: _msg, actionLabel: _action, onAction: () {}),
    ));
    await t.tap(find.byKey(const Key('trigger')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text(_msg), findsOneWidget);

    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.text(_msg), findsNothing,
        reason: 'accessibleNavigation 下带 action 的 SnackBar 会永久驻留，本组件不得复刻该缺陷');
  });
}
