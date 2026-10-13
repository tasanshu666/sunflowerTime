/// C61 平板适配（2026-10-13 玄参拍板）+ C65 平板 UI 放大 1.3× 的**组件级护栏**。
///
/// 覆盖三处接线点，证明「手机原样 / 平板生效」在真实 widget 树里确实成立：
///  ① `AdaptiveNavBarHost` —— 手机不引入任何包装层；平板限宽 [kNavBarMaxWidth]
///     且**左右留白相等**（居中），外壳仍占满通栏（同色补满）；
///  ② `GrowthFxOverlay` —— 平板短边下卡宽钳到 [kGrowFxCardMaxWidth]；
///  ③ C65 两条消费路径 —— **文字**走 `applyTabletTextScaling` 注入的
///     `MediaQuery.textScaler`（手机不注入 = 零像素回归，用「与不加 builder 的
///     对照壳逐位相等」实证）、**图形**走 `uiScaleOf`（徽标 42 → 54.6）。
///
/// ⚠️ 屏幕尺寸一律通过 `tester.view.physicalSize` × `devicePixelRatio` 设定，
/// 与项目既有护栏（`garden_layout_v3_test.dart` 的 `_setScreen`）同手法。
/// ⚠️ 文字「变多大」不去断言渲染高度（受测试字体 ascent/descent 影响、非整数倍），
/// 改为直接断言**注入后的倍率值** + 与对照壳比大小。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';
import 'package:sunflower_time/shared/adaptive_nav_bar.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 设定逻辑屏幕尺寸（物理像素 = 逻辑 × 3，与既有护栏一致）。
void _setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 五个 tab 的真实 `NavigationBar`（与孩子端 shell 同形）。
Widget _navBar() => NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (int _) {},
      destinations: const <NavigationDestination>[
        NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
        NavigationDestination(icon: Icon(Icons.checklist_outlined), label: '成长'),
        NavigationDestination(icon: Icon(Icons.yard_outlined), label: '花园'),
        NavigationDestination(icon: Icon(Icons.storefront_outlined), label: '商店'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
      ],
    );

/// 把导航外壳放进 Scaffold 的 `bottomNavigationBar` 槽（真实挂载位置）。
Widget _shell() => MaterialApp(
      home: Scaffold(bottomNavigationBar: AdaptiveNavBarHost(child: _navBar())),
    );

/// 带 body 的真实挂载形态（用于验证「底栏没有挤掉 body」）。
Widget _shellWithBody() => MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(key: Key('body')),
        bottomNavigationBar: AdaptiveNavBarHost(child: _navBar()),
      ),
    );

void main() {
  group('AdaptiveNavBarHost · 底部导航平板限宽', () {
    testWidgets('手机（短边 390）：原样返回，不引入任何 RenderObject 包装层',
        (WidgetTester tester) async {
      _setScreen(tester, 390, 844);
      await tester.pumpWidget(_shell());

      // ⚠️ 不能用「找不到 ConstrainedBox」断言：`NavigationBar` 自身内部就含
      // ConstrainedBox。改用 **renderObject 恒等** —— 手机端 build 直接 `return child`，
      // 不产生任何新的 RenderObject，这是「零像素变化」的直接证明。
      expect(
        identical(
          tester.renderObject(find.byType(AdaptiveNavBarHost)),
          tester.renderObject(find.byType(NavigationBar)),
        ),
        isTrue,
        reason: '手机端必须与 child 共用同一个 renderObject（零包装 → 零像素变化）',
      );
      expect(
        tester.getSize(find.byType(NavigationBar)).width,
        390,
        reason: '手机端导航栏仍铺满整屏宽',
      );
    });

    testWidgets('平板（短边 800）：限宽到 kNavBarMaxWidth、水平居中、外壳占满通栏',
        (WidgetTester tester) async {
      _setScreen(tester, 800, 1280);
      await tester.pumpWidget(_shell());

      expect(
        identical(
          tester.renderObject(find.byType(AdaptiveNavBarHost)),
          tester.renderObject(find.byType(NavigationBar)),
        ),
        isFalse,
        reason: '平板端必须真的插入了包装层（否则限宽没生效）',
      );

      final Rect host = tester.getRect(find.byType(AdaptiveNavBarHost));
      final Rect bar = tester.getRect(find.byType(NavigationBar));

      expect(bar.width, kNavBarMaxWidth, reason: '导航栏内容限宽到上限');
      expect(host.width, 800, reason: '外壳仍占满整屏宽（两侧同色补满，保持通栏）');
      // 🔴 回归护栏（2026-10-13 平板实测「所有页面全空白」的根因）：
      // `bottomNavigationBar` 槽位给的是「高度**有界**（max = 屏高）」的 loose 约束
      // —— `Center` 不写 `heightFactor` 时会撑满 maxHeight → 外壳占满整屏高、
      // body 被挤成 0 高、导航垂直居中（iPad 上「全米色 + 导航浮中间」）。
      expect(
        host.height,
        tester.getSize(find.byType(NavigationBar)).height,
        reason: '底栏外壳纵向只能占导航高度；撑满屏高 = 平板空白页',
      );
      expect(
        host.height,
        lessThan(200),
        reason: '底栏高度应在导航栏量级（~80），不得接近屏高',
      );
      expect(
        bar.left - host.left,
        closeTo(host.right - bar.right, 0.01),
        reason: '左右留白必须相等（水平居中）',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '底栏槽位高度无界，ColoredBox>Center 组合不得触发无界高度断言',
      );
    });

    testWidgets('平板（短边 800）：底栏不得挤掉 body（空白页回归护栏）',
        (WidgetTester tester) async {
      _setScreen(tester, 800, 1280);
      await tester.pumpWidget(_shellWithBody());
      final double bodyH = tester.getSize(find.byKey(const Key('body'))).height;
      expect(
        bodyH,
        greaterThan(1000),
        reason: 'body 必须拿到屏高减去底栏后的空间（曾因底栏撑满屏高而变 0）',
      );
      expect(
        bodyH + tester.getSize(find.byType(AdaptiveNavBarHost)).height,
        closeTo(1280, 0.01),
        reason: 'body + 底栏 = 屏高（无重叠、无溢出）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('边界（短边 600，刚好达阈值）：按平板处理', (WidgetTester tester) async {
      _setScreen(tester, 600, 960);
      await tester.pumpWidget(_shell());
      expect(tester.getSize(find.byType(NavigationBar)).width, kNavBarMaxWidth);
    });

    testWidgets('边界（短边 599.9）：按手机处理，不限宽', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(599.9 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_shell());
      expect(
        identical(
          tester.renderObject(find.byType(AdaptiveNavBarHost)),
          tester.renderObject(find.byType(NavigationBar)),
        ),
        isTrue,
        reason: '599.9 < 600 → 仍按手机处理',
      );
    });
  });

  group('GrowthFxOverlay · 成长演出卡平板限宽', () {
    /// 取卡片外框宽度（`_card` 返回的 Container 是树中第一个 Container）。
    double cardWidth(WidgetTester tester) => tester
        .getSize(
          find
              .descendant(
                of: find.byType(GrowthFxOverlay),
                matching: find.byType(Container),
              )
              .first,
        )
        .width;

    testWidgets('手机（短边 390）：卡宽 = 390 × kGrowFxCardWidthRatio',
        (WidgetTester tester) async {
      _setScreen(tester, 390, 844);
      await tester.pumpWidget(const MaterialApp(
        home: GrowthFxOverlay(
          frames: <String>[
            'assets/fx/grow/sunflower/seed_to_sprout/frame001.webp',
          ],
          durationMs: 4100,
        ),
      ));
      await tester.pump();
      expect(
        cardWidth(tester),
        closeTo(390 * kGrowFxCardWidthRatio, 0.01),
      );
    });

    testWidgets('平板（短边 800）：卡宽钳到 kGrowFxCardMaxWidth（不是 624）',
        (WidgetTester tester) async {
      _setScreen(tester, 800, 1280);
      await tester.pumpWidget(const MaterialApp(
        home: GrowthFxOverlay(
          frames: <String>[
            'assets/fx/grow/sunflower/seed_to_sprout/frame001.webp',
          ],
          durationMs: 4100,
        ),
      ));
      await tester.pump();
      expect(cardWidth(tester), closeTo(kGrowFxCardMaxWidth, 0.01));
      expect(cardWidth(tester), lessThan(800 * kGrowFxCardWidthRatio));
    });
  });

  group('C65 平板 UI 放大 · 两条消费路径在真实 widget 树里都生效', () {
    /// 探针：把「本层实际生效的文字倍率」抄出来（直接断言注入结果，
    /// 不依赖测试字体的行高度量 —— 后者受字体 ascent/descent 影响不可精确断言）。
    late double seenScale;

    Widget probeBody() => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ① 文字路径：定字号 Text（证明「放大真的传导到渲染」）
            const Text('基准', key: Key('probe_text'),
                style: TextStyle(fontSize: 20)),
            // ② 派生值路径：花盆底栏高（消费的正是注入后的 textScaler）
            Builder(
              builder: (BuildContext ctx) => SizedBox(
                key: const Key('probe_footer'),
                height: gardenPotFooterHeightOf(ctx),
              ),
            ),
            // ③ 图形路径：真实素材徽标（显式乘 uiScaleOf）
            BloomRewardIcon(
              spec: const RewardIconSpec(kind: RewardIconKind.sunlight),
              assetPath: null,
              onTap: () {},
            ),
            Builder(
              builder: (BuildContext ctx) {
                seenScale = MediaQuery.textScalerOf(ctx).scale(1.0);
                return const SizedBox.shrink();
              },
            ),
          ],
        );

    /// 「app.dart 同款注入壳」：调用的正是 app.dart 的唯一注入点
    /// [applyTabletTextScaling]（函数自身的正确性由 `responsive_baseline_test.dart`
    /// 的纯单测锁定，此处证明「注入 → 真实渲染变化」这条接线成立）。
    Widget injectedShell() => MaterialApp(
          builder: (BuildContext context, Widget? child) {
            final Widget content = child ?? const SizedBox.shrink();
            final MediaQueryData mq =
                MediaQuery.maybeOf(context) ?? const MediaQueryData();
            final MediaQueryData scaled = applyTabletTextScaling(mq);
            if (identical(scaled, mq)) return content;
            return MediaQuery(data: scaled, child: content);
          },
          home: Scaffold(body: probeBody()),
        );

    /// 对照壳：**不加** builder 注入。
    Widget plainShell() =>
        MaterialApp(home: Scaffold(body: probeBody()));

    double textHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('probe_text'))).height;
    double footerHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('probe_footer'))).height;
    double iconSize(WidgetTester tester) =>
        tester.getSize(find.byType(BloomRewardIcon)).height;

    testWidgets('手机（短边 390）：倍率 1.0 · 底栏 32 · 徽标 42 · 文字零回归',
        (tester) async {
      _setScreen(tester, 390, 844);
      await tester.pumpWidget(plainShell());
      await tester.pumpAndSettle();
      final double plainText = textHeight(tester);

      await tester.pumpWidget(injectedShell());
      await tester.pumpAndSettle();
      expect(seenScale, 1.0, reason: '手机不得注入任何文字放大');
      expect(textHeight(tester), plainText, reason: '手机文字必须零像素变化');
      expect(footerHeight(tester), kGardenPotFooterHeight);
      expect(iconSize(tester), BloomRewardIcon.hitSize);
    });

    testWidgets('平板（短边 834）：倍率 1.3 · 底栏 36.8 · 徽标 54.6 · 文字真变大',
        (tester) async {
      _setScreen(tester, 834, 1210);
      await tester.pumpWidget(plainShell());
      await tester.pumpAndSettle();
      final double plainText = textHeight(tester);

      await tester.pumpWidget(injectedShell());
      await tester.pumpAndSettle();
      expect(seenScale, kTabletUiScale);
      expect(textHeight(tester), greaterThan(plainText),
          reason: '文字必须真的变大（不只 MediaQuery 数值变了）');
      expect(
        footerHeight(tester),
        closeTo(gardenPotFooterHeightFor(kTabletUiScale), 1e-9),
        reason: '底栏必须跟着字号长高，否则文案被挤',
      );
      expect(
        iconSize(tester),
        closeTo(BloomRewardIcon.hitSize * kTabletUiScale, 1e-9),
        reason: '图片不吃 textScaler → 必须显式乘 uiScaleOf',
      );
    });

    testWidgets('⚠️ 反向护栏：图形放大比严格 = kTabletUiScale（与文字同源）',
        (tester) async {
      _setScreen(tester, 390, 844);
      await tester.pumpWidget(injectedShell());
      await tester.pumpAndSettle();
      final double phoneIcon = iconSize(tester);

      _setScreen(tester, 834, 1210);
      await tester.pumpWidget(injectedShell());
      await tester.pumpAndSettle();
      expect(iconSize(tester) / phoneIcon, closeTo(kTabletUiScale, 1e-9));
    });
  });
}
