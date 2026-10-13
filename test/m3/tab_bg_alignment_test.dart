/// C64（2026-10-13）**tab 整页底图对齐**的护栏测试。
///
/// 背景：玄参 iPad 实测「今日/成长/商店 背景素材上半部分留的太多」——平板比底图宽得多，
/// `BoxFit.cover` 竖向裁掉 35%~45%，固定 `topCenter` 会把场景整体拉大、卡片压在插画上。
/// 现改为按「底图场景↔留白分界线 = 卡片起点」自动算垂直对齐（**仅平板**）。
///
/// ## 本文件锁三条不变式
///  ① **平板**：分界线实际落在卡片起点（`panelTopScreenY ≈ targetY`，误差 ≤0.5pt），
///     且对齐值是「真的动过」（不是恰好 -1 的假通过）；
///  ② **手机**：恒 `topCenter`（零像素变化）—— 由 `TabBackground` 的平板闸门保证；
///  ③ **边界**：竖向无裁剪余量（商店底图按高度绑定）→ 退回 topCenter；越界目标 → 钳制。
///
/// ⚠️ 期望值一律**独立列出**（不引用被测常量），否则改常量测试不变红
/// （防自指纪律，同 `garden_layout_v3_test.dart`）。
library tab_bg_alignment_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

/// iPad Pro 11″（M5）竖屏逻辑尺寸（834×1210，shortestSide 834 ≥ 600 → 平板档）。
const Size _iPadScreen = Size(834, 1210);

/// iPhone 17 竖屏（402×874，手机档）。
const Size _phoneScreen = Size(402, 874);

/// 外壳 body 高 = 屏高 − 底部导航 ≈80（`extendBody` 未开，body 不吃底栏）。
const double _navBarH = 80;

/// 三张底图的 `(asset, 源尺寸, 分界线, 底图锚点比例)`。
///
/// ⚠️ 第 4 个元素是**底图锚点**（喂给 `TabBackground.panelTargetRatio`），
/// 不是页面卡片起点：成长/商店两者相同；**今日不同**（锚点 0.37 / 卡片 0.40，C67）。
final List<(String, Size, double, double)> _cases = <(String, Size, double, double)>[
  (kTodayBgAsset, const Size(1440, 3200), 0.399, 0.37),
  (kGrowthBgAsset, const Size(1408, 3104), 0.348, 0.34),
  (kStoreBgAsset, const Size(1600, 2848), 0.463, 0.41),
];

/// 宿主：`TabBackground` 填满「屏宽 × body 高」，除它之外不含别的 `DecoratedBox`。
Widget _host(String asset, double panelTargetRatio, double bodyHeight) => MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: double.infinity,
          height: bodyHeight,
          child: TabBackground(
            asset: asset,
            panelTargetRatio: panelTargetRatio,
            fallbackColor: const Color(0xFFFBF4E4),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

/// 取被测底图上的对齐值（`TabBackground.decorationKey` 钉死唯一性）。
Alignment _alignmentOf(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find.byKey(TabBackground.decorationKey),
  );
  final BoxDecoration deco = box.decoration as BoxDecoration;
  return deco.image!.alignment as Alignment;
}

void main() {
  group('C64 底图对齐 · 纯几何', () {
    test('常量与实测一致（换底图必须重跑 tools/probe_tab_bg_panel_top.py）', () {
      expect(kTodayBgSrcSize, const Size(1440, 3200));
      expect(kTodayBgPanelTopFraction, 0.399);
      expect(kGrowthBgSrcSize, const Size(1408, 3104));
      expect(kGrowthBgPanelTopFraction, 0.348);
      expect(kStoreBgSrcSize, const Size(1600, 2848));
      expect(kStoreBgPanelTopFraction, 0.463);
      // 分界线必须落在「场景区之后、留白区之内」的合理带内。
      for (final double f in <double>[
        kTodayBgPanelTopFraction,
        kGrowthBgPanelTopFraction,
        kStoreBgPanelTopFraction,
      ]) {
        expect(f, greaterThan(0.30));
        expect(f, lessThan(0.55));
      }
    });

    test('cover 绘制高：横比竖更「宽」时按宽度绑定，否则按高度绑定', () {
      // iPad 上 today：834/1440 = 0.579 > 1130/3200 = 0.353 → 按宽度绑定（竖向裁 39%）。
      expect(
        coverDrawnHeight(box: const Size(834, 1130), src: const Size(1440, 3200)),
        closeTo(3200 * 834 / 1440, 0.01),
      );
      // 手机上的商店图：按高度绑定（绘制高 = 容器高）→ 竖向无余量。
      expect(
        coverDrawnHeight(box: const Size(402, 794), src: const Size(1600, 2848)),
        closeTo(794, 0.01),
      );
    });

    test('⚠️ 平板三页：分界线正好落在卡片起点（误差 ≤0.5pt）且真的移动过', () {
      const Size body = Size(834, 1210 - _navBarH);
      for (final (String asset, Size src, double frac, double ratio) in _cases) {
        final double targetY = _iPadScreen.height * ratio;
        final double? a = tabBgAlignmentY(
          box: body,
          src: src,
          panelTopFraction: frac,
          targetY: targetY,
        );
        expect(a, isNotNull, reason: '$asset 在平板上必须能对齐');
        final double v = a!;
        expect(v, inInclusiveRange(-1.0, 1.0), reason: '$asset 对齐值必须合法');
        // ⚠️ 注意方向：slack < 0 时 a = -1 表示 topCenter（**不动**），越往 +1 越向上移。
        final double top =
            (body.height - coverDrawnHeight(box: body, src: src)) * (v + 1) / 2;
        expect(top, lessThan(-20.0), reason: '$asset 必须真的上移（不是停在上限）');
        expect(
          panelTopScreenY(
            box: body,
            src: src,
            panelTopFraction: frac,
            alignmentY: v,
          ),
          closeTo(targetY, 0.5),
          reason: '$asset 分界线必须落在卡片起点',
        );
      }
    });

    test('⚠️ 为什么必须加「仅平板」闸门：growth 在**手机几何**上纯算会想上移 ~11pt', () {
      // 实测分界线 0.348 略低于成长页手机侧卡点 0.34 → 纯几何会真的移动，
      // 而手机是「零像素变化」红线 → 只能由 TabBackground 的平板闸门挡掉。
      const Size body = Size(402, 874 - _navBarH);
      final double? a = tabBgAlignmentY(
        box: body,
        src: const Size(1408, 3104),
        panelTopFraction: 0.348,
        targetY: 874 * 0.34,
      );
      expect(a, isNotNull);
      final double drawnH =
          coverDrawnHeight(box: body, src: const Size(1408, 3104));
      final double top = (body.height - drawnH) * (a! + 1) / 2;
      expect(top.abs(), greaterThan(5.0), reason: '纯几何确实会动（故需闸门）');
      expect(top.abs(), lessThan(20.0), reason: '位移很小（视觉上可忽略）');
    });

    test('⚠️ 为什么必须加「仅平板」闸门：今日在**手机几何**上纯算会想上移 ~33pt', () {
      // C65 把今日卡片起点从 0.42 上移到 0.37 后，手机几何（402×874）上底图分界线
      // 0.399×893.3 = 356.4pt 已**高于**目标 0.37×874 = 323.4pt → 纯几何会真的上移 ~33pt
      // （手机自身余量只有 99pt，不会钳制）。而手机是「零像素变化」红线 →
      // 必须由 `TabBackground` 的平板闸门挡掉（见下面的手机组件级用例）。
      const Size body = Size(402, 874 - _navBarH);
      final double? a = tabBgAlignmentY(
        box: body,
        src: const Size(1440, 3200),
        panelTopFraction: 0.399,
        targetY: 874 * 0.37,
      );
      expect(a, isNotNull);
      final double drawnH =
          coverDrawnHeight(box: body, src: const Size(1440, 3200));
      final double top = (body.height - drawnH) * (a! + 1) / 2;
      expect(top, lessThan(-20.0), reason: '纯几何确实会明显上移（故需闸门）');
      expect(top, greaterThan(-45.0), reason: '位移量级 ~33pt');
    });

    test('手机档：商店底图「竖向无裁剪余量」→ 返回 null', () {
      expect(
        tabBgAlignmentY(
          box: const Size(402, 874 - _navBarH),
          src: const Size(1600, 2848),
          panelTopFraction: 0.463,
          targetY: 874 * 0.41,
        ),
        isNull,
      );
    });

    test('越界目标 → 钳到 [-1, 1]（不抛异常、不把图推出可视区）', () {
      const Size body = Size(834, 1130);
      const Size src = Size(1440, 3200);
      // ⚠️ slack < 0 时的映射：a = -1 ⇒ topCenter（不动）、a = +1 ⇒ 最大上移。
      // 目标远高于图顶（想大幅上移但余量不够）→ 钳到 +1（bottomCenter = 移到底）。
      expect(
        tabBgAlignmentY(
          box: body,
          src: src,
          panelTopFraction: 0.399,
          targetY: -500,
        ),
        1.0,
      );
      // 目标远低于容器底（想下移但无处可移）→ 钳到 -1（topCenter = 原行为）。
      expect(
        tabBgAlignmentY(
          box: body,
          src: src,
          panelTopFraction: 0.399,
          targetY: 9999,
        ),
        -1.0,
      );
    });
  });

  group('C64 底图对齐 · 组件级（TabBackground 平板闸门）', () {
    testWidgets('平板 834×1210：三页对齐值真的生效（= 纯函数结果）',
        (WidgetTester tester) async {
      tester.view.physicalSize = _iPadScreen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final (String asset, Size src, double frac, double ratio) in _cases) {
        await tester.pumpWidget(_host(asset, ratio, 1210 - _navBarH));
        await tester.pump();

        final double expected = tabBgAlignmentY(
          box: const Size(834, 1210 - _navBarH),
          src: src,
          panelTopFraction: frac,
          targetY: _iPadScreen.height * ratio,
        )!;
        final Alignment a = _alignmentOf(tester);
        expect(a.x, 0.0, reason: '$asset 水平方向不做偏移');
        expect(a.y, closeTo(expected, 1e-9), reason: '$asset 对齐值应等于纯函数结果');
        // 真的生效（不是恰好停在 topCenter）：实际位移必须 > 20pt。
        final double drawnH = coverDrawnHeight(
          box: const Size(834, 1210 - _navBarH),
          src: src,
        );
        final double top =
            (1210 - _navBarH - drawnH) * (a.y + 1) / 2;
        expect(top, lessThan(-20.0), reason: '$asset 必须真的上移了');
      }
    });

    testWidgets('手机 402×874：恒 topCenter（零像素变化红线）',
        (WidgetTester tester) async {
      tester.view.physicalSize = _phoneScreen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final (String asset, _, _, double ratio) in _cases) {
        await tester.pumpWidget(_host(asset, ratio, 874 - _navBarH));
        await tester.pump();
        expect(
          _alignmentOf(tester),
          Alignment.topCenter,
          reason: '$asset 手机端必须原样 topCenter',
        );
      }
    });

    testWidgets('未登记的底图（无几何常量）→ 退回 topCenter，不崩',
        (WidgetTester tester) async {
      tester.view.physicalSize = _iPadScreen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // store01 是备选背景（未登记几何常量）。
      await tester.pumpWidget(
        _host('assets/backgrounds/store01.webp', 0.41, 1210 - _navBarH),
      );
      await tester.pump();
      expect(_alignmentOf(tester), Alignment.topCenter);
    });
  });

  group('C64/C65/C67 页面常量（防「改了卡片位置忘了底图」）', () {
    test('三页卡片起点比例与花园限宽仍在设计值上', () {
      // 今日 0.40 = C67（2026-10-13 晚 iPad 实测：卡片再下移 ~36pt）；
      // 下边界 ~0.35，再低会裁到向日葵花头。
      expect(kTodayCardTopRatio, 0.40);
      // 今日底图锚点冻结在 C65 认可的 0.37（C67 起与卡片起点解耦）。
      expect(kTodayBgPanelTargetRatio, 0.37);
      expect(kGrowthListTopRatio, 0.34);
      expect(kStoreListTopRatio, 0.41);
      expect(kGardenGridMaxWidth, 620);
    });

    test('⚠️ C67：今日「底图锚点」与「卡片起点」解耦（有意留 3% 屏高呼吸带）', () {
      // 依据（玄参 2026-10-13 晚交付「现状 vs 期望」两张同屏截图）：
      //   ① 两图做垂直互相关 → 底图像素**零变化**（最佳偏移处 MEA = 0.17）
      //      ⇒ 期望图**只动卡片、不动底图**；
      //   ② 三张卡的图标圆心一律下移 **39px**；截图 907px 宽 ↔ iPad 834pt 宽
      //      ⇒ 1.088 px/pt ⇒ ≈ **36pt ≈ 屏高 3%**。
      expect(kTodayCardTopRatio, 0.40, reason: 'C67：卡片起点 0.37 → 0.40');
      expect(kTodayBgPanelTargetRatio, 0.37, reason: 'C67：底图锚点冻结不动');
      // 呼吸带 = 卡片起点 − 底图分界线（iPad 11″ 竖屏 1210pt 上应 ≈ 36pt）。
      expect(
        (kTodayCardTopRatio - kTodayBgPanelTargetRatio) * _iPadScreen.height,
        closeTo(36.3, 0.5),
      );
      // 方向：卡片必须在分界线**下方**（否则“呼吸带”变负 = 卡片又压回插画）。
      expect(kTodayCardTopRatio, greaterThan(kTodayBgPanelTargetRatio));
      // 下边界：低于 ~0.35 会裁到向日葵花头（花头顶 ≈ 1210r − 392）。
      expect(kTodayCardTopRatio, greaterThanOrEqualTo(0.35));
      // 上边界：不得退回到 C44e 的 0.42 以上（否则场景区再次被压扁）。
      expect(kTodayCardTopRatio, lessThanOrEqualTo(0.42));
    });

    test('⚠️ 几何复核：iPad 上锚点 0.37 与卡片 0.40 确实拉开一条带、且都能落地', () {
      const Size body = Size(834, 1210 - _navBarH);
      const Size src = Size(1440, 3200);
      // 底图锚点用 0.37 → 分界线落在 1210×0.37 = 447.7pt。
      final double? a = tabBgAlignmentY(
        box: body,
        src: src,
        panelTopFraction: 0.399,
        targetY: _iPadScreen.height * kTodayBgPanelTargetRatio,
      );
      expect(a, isNotNull, reason: '锚点 0.37 在平板上必须可对齐（未被钳制）');
      expect(
        panelTopScreenY(
          box: body,
          src: src,
          panelTopFraction: 0.399,
          alignmentY: a!,
        ),
        closeTo(_iPadScreen.height * kTodayBgPanelTargetRatio, 0.5),
      );
      // 卡片起点（0.40）在分界线下方 ≈ 36pt，且仍在屏内。
      final double cardTop = _iPadScreen.height * kTodayCardTopRatio;
      expect(cardTop, greaterThan(_iPadScreen.height * kTodayBgPanelTargetRatio));
      expect(cardTop, lessThan(_iPadScreen.height));
    });
  });
}
