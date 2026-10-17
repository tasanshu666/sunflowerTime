/// C78（V2-4）· **家长端「解锁全部功能」入口卡金令牌视觉** widget 测试。
///
/// 钉住四件事（改版纪律：**仅样式，路由 / 门控 / 副标题逐字不变**）：
///  ① **金卡**：`解锁全部功能` 入口 = 金渐变底（`0xFFFFFDF7 → 0xFFFFF0C9`，
///     topLeft → bottomRight）+ 金描边（`0xFFE8C56A`，1.5px）+ 星标金
///     （`0xFFE8A600`）+ 字色 `0xFF6B6252` w700 + 尾部 chevron 金 —— 色值与
///     购买页金系一致；
///  ② **删除入口卡白底零回归**：`删除入口` 仍是普通 Card（无渐变、无金描边），
///     红色语义保留；~~专注报告~~（C85 已从设置页删除该卡 → 报告改从「记录」tab 进入，
///     断言同步收敛为只剩删除入口一张）。
///  ③ **路由不变**：点金卡仍 `push('/parent/premium')`；
///  ④ **副标题不变**：金卡 subtitle 仍是 `PremiumStatusText`（未解锁 → 「未解锁」）。
///
/// 🟢 夹具：内存 SettingsRepository + GoRouter 占位页；`entitlementProvider`
/// 默认 free，不触任何平台 API。
/// ⚠️ 页面根是懒构建 ListView：底部「数据与隐私」分区（只剩「删除入口」一卡）需先
/// 滚动进视口再断言。C85 起「专注报告」卡已从本页删除。
library parent_entry_gold_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';

/// 内存设置仓储假实现。
class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

Future<void> _pump(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    initialLocation: '/parent/settings',
    routes: <RouteBase>[
      GoRoute(
        path: '/parent/settings',
        // 真实 app 中该页由带 Scaffold 的家长外壳承载（金卡 Container 无自带
        // Material，ListTile 依赖外层 Scaffold 提供的 Material 祖先）。
        builder: (_, __) => const Scaffold(body: ParentSettingsPage()),
      ),
      GoRoute(
        path: '/parent/premium',
        builder: (_, __) =>
            const Scaffold(key: Key('premium-page'), body: Text('PREMIUM')),
      ),
      GoRoute(
        path: '/parent/report',
        builder: (_, __) =>
            const Scaffold(key: Key('report-page'), body: Text('REPORT')),
      ),
      GoRoute(
        path: '/parent/delete',
        builder: (_, __) =>
            const Scaffold(key: Key('delete-page'), body: Text('DELETE')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 「解锁全部功能」在树上出现两次（分区标题 + 卡标题）；取**后者**（卡标题）。
Finder _goldCardTitle() => find.text('解锁全部功能').last;

/// 从某文本向上找**最近的带渐变 Container**（金卡容器）；找不到返回 null。
Container? _nearestGradientContainerOf(WidgetTester tester, String text) {
  final Iterable<Element> ancestors = find
      .ancestor(of: find.text(text), matching: find.byType(Container))
      .evaluate();
  for (final Element e in ancestors) {
    final Container c = e.widget as Container;
    final BoxDecoration? d = c.decoration as BoxDecoration?;
    if (d?.gradient != null) {
      return c;
    }
  }
  return null;
}

void main() {
  testWidgets('① 金卡：金渐变底 + 金描边 + 星标金 + 字色 + chevron 金', (tester) async {
    await _pump(tester);

    final Container? gold =
        _nearestGradientContainerOf(tester, '解锁全部功能');
    expect(gold, isNotNull, reason: '「解锁全部功能」入口必须有金渐变容器');

    final BoxDecoration d = gold!.decoration! as BoxDecoration;
    final LinearGradient g = d.gradient! as LinearGradient;
    expect(g.begin, Alignment.topLeft);
    expect(g.end, Alignment.bottomRight);
    expect(g.colors, <Color>[
      const Color(0xFFFFFDF7),
      const Color(0xFFFFF0C9),
    ], reason: '金渐变色值必须与购买页一致');
    final Border border = d.border! as Border;
    expect(border.top.color, const Color(0xFFE8C56A));
    expect(border.top.width, 1.5);

    // 星标金。
    final Icon star = tester.widget<Icon>(
      find.descendant(
          of: find.byWidget(gold), matching: find.byIcon(Icons.star_rounded)),
    );
    expect(star.color, const Color(0xFFE8A600), reason: '星标金 0xFFE8A600');

    // 卡标题字色 + w700（分区标题无样式，用最后一个 Text 消歧）。
    final Text title = tester.widget<Text>(_goldCardTitle());
    expect(title.style?.color, const Color(0xFF6B6252));
    expect(title.style?.fontWeight, FontWeight.w700);

    // 尾部 chevron 金。
    final Icon chevron = tester.widget<Icon>(
      find.descendant(
          of: find.byWidget(gold),
          matching: find.byIcon(Icons.chevron_right)),
    );
    expect(chevron.color, const Color(0xFFE8A600), reason: '金卡 chevron 也应金色');
  });

  testWidgets('② 删除入口卡白底零回归（仍是 Card，无渐变）；红色语义保留', (tester) async {
    await _pump(tester);

    // ⚠️ 懒构建 ListView：先滚动到底部让「数据与隐私」分区的删除入口进视口。
    await tester.scrollUntilVisible(
      find.text('删除入口'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // C85：设置页只剩这一张入口卡（「专注报告」卡已删）→ 连带钉住它不再回流。
    expect(find.text('专注报告'), findsNothing,
        reason: 'C85：「专注报告」入口卡已从设置页删除（报告从「记录」tab 进入）');
    expect(find.text('数据与隐私'), findsOneWidget,
        reason: 'C85：原「数据入口」分区标题已更名为「数据与隐私」');

    for (final String title in <String>['删除入口']) {
      expect(_nearestGradientContainerOf(tester, title), isNull,
          reason: '「$title」入口不得金化（仅会员入口金令牌）');
      expect(
        find.ancestor(of: find.text(title), matching: find.byType(Card)),
        findsOneWidget,
        reason: '「$title」入口仍是普通 Card',
      );
    }
    final Text del = tester.widget<Text>(find.text('删除入口'));
    expect(del.style?.color, Colors.red, reason: '删除入口红色语义保留');
  });

  testWidgets('③ 路由不变：点金卡仍 push /parent/premium', (tester) async {
    await _pump(tester);
    await tester.tap(_goldCardTitle());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('premium-page')), findsOneWidget,
        reason: 'C78 仅改样式，路由 / PIN 门控不变');
  });

  testWidgets('④ 副标题不变：金卡 subtitle 仍是 PremiumStatusText（未解锁 → 「未解锁」）', (tester) async {
    await _pump(tester);
    expect(find.text('未解锁'), findsOneWidget,
        reason: 'PremiumStatusText 渲染位置与语义不变（entitlement 默认 free）');
  });
}
