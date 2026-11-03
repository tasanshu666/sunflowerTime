/// A2 天气道具「搭棚」按钮 —— **真实点击命中区守卫**（A2-10 的硬证据）。
///
/// ## 为什么要有这个文件
///
/// `weather_a2_test.dart` 里的命中区断言用的是
/// `tester.getSize(find.byKey(kShelterBuyButtonKey))`。**这个写法会被假绿骗过**：
///
/// - `ConstrainedBox(minHeight: 44) + OverflowBox` 让按钮**按 44 布局**，
///   `getSize` 量到 44 → 断言绿；
/// - 但**真实点击**走的是 `RenderBox.hitTest`，首行即
///   `if (!size.contains(position)) return false;`
///   —— 外层行容器只有 32 高，点在 32~44 之间的请求在**行容器那层就被拒**，
///   根本到不了按钮。
///
/// 也就是说：**测试会绿，孩子真点下去仍然点不准。** 这正是「声明尺寸 ≠ 真实尺寸」的陷阱。
///
/// 本文件用两种**不依赖 `getSize`** 的方式判定命中区：
///  1. [WidgetTester.hitTestOnBinding] —— 直接查命中链里有没有按钮；
///  2. 真实 [WidgetTester.tapAt] —— 真的点一下，看回调有没有被触发。
library weather_a2_tap_probe_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';

/// 搭一个最小宿主：左边一截 chips，右边天气行（与 `garden_page.dart` 的结构一致）。
Widget _host({
  required WeatherKind kind,
  required double pageWidth,
  required double chipsWidth,
  required VoidCallback onShelterTap,
  bool bought = false,
  bool affordable = true,
  bool showShelterButton = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: pageWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                SizedBox(width: chipsWidth, child: const Text('🧩 ×3')),
                Flexible(
                  child: GardenWeatherRow(
                    key: kWeatherRowKey,
                    kind: kind,
                    shelterRefType: kind.shelterRefType,
                    bought: bought,
                    affordable: affordable,
                    showShelterButton: showShelterButton,
                    onShelterTap: onShelterTap,
                    onPillTap: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _setPhoneView(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 该坐标的命中链里是否包含推荐道具按钮。
///
/// 直接问按钮的 [RenderObject]：这个点上它被命中了吗。
/// **不用 `getSize`** —— 那正是会假绿的口径。
bool _hitsButton(WidgetTester tester, Offset p) {
  final HitTestResult result = tester.hitTestOnBinding(p);
  final RenderObject btnRender =
      tester.renderObject(find.byKey(kShelterBuyButtonKey));
  return result.path.any((e) => e.target == btnRender);
}

void main() {
  group('A2-10 · 真实点击命中区（非 getSize 口径）', () {
    testWidgets('行容器高度必须 ≥ 44pt，否则命中区只能是「声明尺寸」',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () {},
      ));

      final double rowH = tester.getSize(find.byKey(kWeatherRowKey)).height;
      // 🔴 行容器低于 44 时，子树的 44 声明盒在真实 hitTest 中会被行容器裁掉。
      expect(rowH, greaterThanOrEqualTo(kMinTapTarget),
          reason: '行容器只有 ${rowH.toStringAsFixed(1)}pt —— '
              '按钮的 44pt 命中盒会被这层挡掉，getSize 量到的 44 是假的');
    });

    testWidgets('命中链探针：按钮下沿 6pt 内仍能命中按钮本体',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () {},
      ));

      final Rect btn = tester.getRect(find.byKey(kShelterBuyButtonKey));

      // 对照组：视觉中心必须能命中（这条是探针自身的有效性证明）。
      expect(_hitsButton(tester, btn.center), isTrue,
          reason: '探针失效：连视觉中心都命中不了按钮');

      // 关键组：按钮**视觉件之外**的 6pt（32~44 区间）必须仍能命中。
      // 若实现是「ConstrainedBox 声明 44 + 外层 32 行容器」，这里必然 false。
      final Offset justBelowVisual = Offset(btn.center.dx, btn.bottom - 2);
      expect(_hitsButton(tester, justBelowVisual), isTrue,
          reason: '按钮下沿 2pt 命中不到 —— 说明 44pt 只是「声明尺寸」，'
              '真实命中区仍被外层行容器裁成 32pt');
    });

    testWidgets('真实点击探针：点按钮下沿 2pt 必须触发 onShelterTap',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      int taps = 0;
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () => taps++,
      ));

      final Rect btn = tester.getRect(find.byKey(kShelterBuyButtonKey));

      // 先点视觉中心，确认按钮本身是活的。
      await tester.tapAt(btn.center);
      await tester.pump();
      expect(taps, 1, reason: '点视觉中心都没反应，按钮根本没接上回调');

      // 再点下沿 2pt（落在 32~44 区间）。
      await tester.tapAt(Offset(btn.center.dx, btn.bottom - 2));
      await tester.pump();
      expect(taps, 2,
          reason: '点按钮下沿 2pt 没触发 —— 真实命中区不足 44pt，'
              '孩子手指按在按钮边缘会「按了没反应」');
    });

    testWidgets('已购态与余额不足态同样能接住点击（不得退回 onTap: null）',
        (WidgetTester tester) async {
      for (final bool bought in <bool>[true, false]) {
        for (final bool affordable in <bool>[true, false]) {
          await _setPhoneView(tester, 390);
          int taps = 0;
          await tester.pumpWidget(_host(
            kind: WeatherKind.drought,
            pageWidth: 390,
            chipsWidth: 179,
            bought: bought,
            affordable: affordable,
            onShelterTap: () => taps++,
          ));

          final Rect btn = tester.getRect(find.byKey(kShelterBuyButtonKey));
          await tester.tapAt(Offset(btn.center.dx, btn.bottom - 2));
          await tester.pump();

          expect(taps, 1,
              reason: 'bought=$bought affordable=$affordable 时下沿点击未被接收');
        }
      }
    });

    // ── A2-10⑥：命中盒的**上/下/左/右四边缘 + 中心**各点一次 ──────────────
    //
    // 🔴 这条是「热区必须用真实点击验收」的正式条款：只量 `getSize` 不算数
    //    —— 声明式 44 能让 `getSize` 量到 44，而真机收不到点击。
    testWidgets('A2-10⑥ · 命中盒五点（上/下/左/右/中心）全部可点',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      int taps = 0;
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () => taps++,
      ));

      final Rect box = tester.getRect(find.byKey(kShelterBuyButtonKey));
      final Map<String, Offset> points = <String, Offset>{
        '上边缘': Offset(box.center.dx, box.top + 1),
        '下边缘': Offset(box.center.dx, box.bottom - 1),
        '左边缘': Offset(box.left + 1, box.center.dy),
        '右边缘': Offset(box.right - 1, box.center.dy),
        '中心': box.center,
      };

      int expected = 0;
      // 🔴 `tapAt` 是**受保护的异步 API**：必须 `await` 且之后 `pump`，
      //    否则回调还没派发就断言 ⇒ 假失败（flutter_test 会直接抛
      //    "Guarded function conflict. You must use 'await' with all
      //    Future-returning test APIs."）。
      for (final MapEntry<String, Offset> entry in points.entries) {
        expected += 1;
        await tester.tapAt(entry.value);
        await tester.pump();
        expect(taps, expected,
            reason: '${entry.key} 点（${entry.value}）未触发回调');
      }
      expect(taps, 5, reason: '五个点必须都触发');
    });

    // ── A2-10⑥ 强化：视觉件**之外**的那圈留白必须真的吃点击 ───────────────
    //
    // 这一条比五点更狠：它测的正是「视觉 32 / 命中 44」之间那 12pt 差值。
    // 若实现退回到「声明 44 + 32 行容器裁剪」，这两个点必然收不到。
    testWidgets('A2-10⑥ · 视觉件上下各 1pt（视觉 32 之外）必须可点',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      int taps = 0;
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () => taps++,
      ));

      final Rect visual = tester.getRect(find.byKey(kShelterButtonVisualKey));
      // 视觉件上方 1pt：必须落在命中盒的 6pt 透明留白里。
      await tester.tapAt(Offset(visual.center.dx, visual.top - 1));
      await tester.pump();
      expect(taps, 1, reason: '视觉件上方 1pt 收不到 —— 竖直方向命中区没真正外扩');

      // 视觉件下方 1pt：同理。
      await tester.tapAt(Offset(visual.center.dx, visual.bottom + 1));
      await tester.pump();
      expect(taps, 2, reason: '视觉件下方 1pt 收不到 —— 竖直方向命中区没真正外扩');
    });
  });

  group('A2-11 · 窄屏降级：名字要么完整、要么整体消失（不许半截）', () {
    /// 找出所有**被截断**的 [Text]（`didExceedMaxLines` 为真 = 渲染时补了 `…`）。
    ///
    /// 🔴 不用 `getSize` / 文本内容比对 —— `TextOverflow.ellipsis` 是**渲染期**行为，
    /// `Text.data` 仍是完整字符串，只能问 [RenderParagraph]。
    List<String> truncatedTexts(WidgetTester tester) {
      final List<String> out = <String>[];
      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        final String data = t.data ?? '';
        if (data.isEmpty) continue;
        final RenderParagraph para =
            tester.renderObject(find.byWidget(t)) as RenderParagraph;
        if (para.didExceedMaxLines) out.add(data);
      }
      return out;
    }

    testWidgets('320 窄屏下不得出现半截名字（`遮阳…` 这类）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 320);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 320,
        chipsWidth: 200,
        onShelterTap: () {},
      ));

      // 提示语（以 '· ' 开头）是**唯一**允许出现 `…` 的元素 —— 先排除它。
      final List<String> truncated = truncatedTexts(tester)
          .where((String s) => !s.startsWith('· '))
          .toList();

      expect(truncated, isEmpty,
          reason: '窄屏下出现半截文字：$truncated —— '
              '按 PRD §5.3.1 压缩铁律，名字要么完整显示、要么整体消失，'
              '不许显示一半（半截名字对不识字的 5~9 岁孩子等于没有）');
    });

    testWidgets('390 常用宽度下三个降级档均不触发（名字完整）',
        (WidgetTester tester) async {
      await _setPhoneView(tester, 390);
      await tester.pumpWidget(_host(
        kind: WeatherKind.drought,
        pageWidth: 390,
        chipsWidth: 179,
        onShelterTap: () {},
      ));

      expect(truncatedTexts(tester).where((String s) => !s.startsWith('· ')),
          isEmpty,
          reason: '390 宽度下不应有任何名字被截断');
    });
  });
}
