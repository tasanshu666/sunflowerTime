/// 「玩法说明」弹窗宽度自适应回归（玄参 2026-11-20 二次真机反馈）。
///
/// 🔴 上一轮只把 `maxWidth` 从 420 改到自适应上限是**假修**：`maxWidth` 只给
/// 松约束，`GardenHelpSheet`（`SingleChildScrollView + Column(min)`）会收缩到
/// 内容固有宽（≈300pt），iPad 上依旧窄长。本文件钉住 production 必须给
/// **tight 宽度**（`SizedBox(width: ...)`），并真实点开 `_showGardenHelp()` 量
/// `GardenHelpSheet` 的渲染宽度：iPhone 390 → 350、iPad 834 → 600。
library garden_help_dialog_width_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';

/// 与 `_showGardenHelp` 的 pageBuilder 同构的布局（只抽出决定宽度的那一层）。
///
/// 高度仍为松上限；宽度由 SizedBox 定死，与生产写法一致——若这里偷用
/// `ConstrainedBox(maxWidth: ...)`，harness 会退回「内容收缩」假绿。
Widget _dialogHarness() {
  return MaterialApp(
    home: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints viewport) {
        return Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    (viewport.maxHeight - 48).clamp(0.0, double.infinity),
              ),
              child: SizedBox(
                width: gardenHelpDialogWidth(viewport.maxWidth),
                child: const GardenHelpSheet(capacity: 4, expandCost: 160),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 设定视口并渲染弹窗布局，返回卡片的实测宽度。
Future<double> _measuredWidth(WidgetTester tester, Size viewport) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_dialogHarness());
  await tester.pump();
  return tester.getSize(find.byType(GardenHelpSheet)).width;
}

/// 有界帧推进：最多 [maxFrames] 帧（呼吸动画无限循环，禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 40,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(const Duration(milliseconds: 40));
  }
  return ready();
}

/// 渲染**真实** `GardenPage` → 点木牌热区 → 走生产 `_showGardenHelp()`，
/// 返回真弹窗里 `GardenHelpSheet` 的实测宽度。
///
/// 与 [_measuredWidth] 的关键区别：**不**自建布局、不复刻约束，量到的就是
/// `garden_page.dart` 里 `_showGardenHelp` 的 pageBuilder 渲染结果。
Future<double> _realDialogWidth(WidgetTester tester, Size viewport) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ProviderScope(
    child: MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
  ));

  final bool signReady = await _pumpUntil(
    tester,
    () => find.byType(GardenSignHotspot).evaluate().isNotEmpty,
  );
  expect(signReady, isTrue, reason: '木牌热区未出现（异步数据未就绪？）');
  await tester.tap(find.byType(GardenSignHotspot).first);

  final Finder sheet = find.byType(GardenHelpSheet);
  final bool shown = await _pumpUntil(tester, () => sheet.evaluate().isNotEmpty);
  expect(shown, isTrue, reason: '点木牌后「玩法说明」真弹窗未出现');

  // 真实弹窗有 200ms fade + scale(0.92→1.0) 转场；量宽度前等转场收敛，
  // 否则 scale<1 会让实测宽度偏小。300ms 覆盖动画并留余量。
  await tester.pump(const Duration(milliseconds: 300));
  final double width = tester.getSize(sheet).width;
  expect(tester.takeException(), isNull);
  return width;
}

void main() {
  group('gardenHelpDialogWidth 纯函数', () {
    test('上限 = 600，比旧的 420 大一档且不超过花园内容宽度', () {
      expect(kGardenHelpDialogMaxWidth, 600.0);
      expect(kGardenHelpDialogMaxWidth, greaterThan(420.0));
      expect(kGardenHelpDialogMaxWidth, lessThan(620.0));
    });

    test('手机视口：逐点等于旧的「视口 - 左右 Padding」结果', () {
      // iPhone 14 / iPhone 14 Pro Max：旧的 maxWidth 420 不生效，实际宽 350 / 388。
      expect(gardenHelpDialogWidth(390), 350.0);
      expect(gardenHelpDialogWidth(428), 388.0);
      expect(gardenHelpDialogWidth(390), lessThan(420.0));
    });

    test('平板视口：封顶 600，宽屏不再细长', () {
      // iPad 11″ = 834 宽、iPad 13″ = 1032 宽：两者都触顶。
      expect(gardenHelpDialogWidth(834), 600.0);
      expect(gardenHelpDialogWidth(1032), 600.0);
      // 临界点：640 - 40 = 600；640 以上不再变宽。
      expect(gardenHelpDialogWidth(640), 600.0);
      expect(gardenHelpDialogWidth(641), 600.0);
    });

    test('极端窄视口钳到 0，不产生负宽度', () {
      expect(gardenHelpDialogWidth(40), 0.0);
      expect(gardenHelpDialogWidth(0), 0.0);
      expect(gardenHelpDialogWidth(-100), 0.0);
    });
  });

  group('真实布局宽度（Padding + SizedBox(tight) + GardenHelpSheet）', () {
    testWidgets('iPhone 竖屏 390：卡片宽 350，与旧实现一致',
        (WidgetTester tester) async {
      expect(await _measuredWidth(tester, const Size(390, 844)), 350.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad 竖屏 834：卡片宽 600，明显宽于旧的 420',
        (WidgetTester tester) async {
      expect(await _measuredWidth(tester, const Size(834, 1194)), 600.0);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 生产接线守卫（埋掉上一轮「改上限但不生效」的假绿）──────────────────
  group('真实弹窗宽度（生产 _showGardenHelp，非自建 harness）', () {
    testWidgets('iPhone 竖屏 390：真实弹窗宽 ==350，手机观感不变',
        (WidgetTester tester) async {
      expect(await _realDialogWidth(tester, const Size(390, 844)), 350.0);
    });

    testWidgets('iPad 竖屏 834：真实弹窗宽 ==600 且宽约束 tight（防松约束回归）',
        (WidgetTester tester) async {
      final double width =
          await _realDialogWidth(tester, const Size(834, 1194));
      expect(width, 600.0,
          reason: '真实弹窗必须按屏宽定宽，而不是内容固有宽或硬编码 420');

      // 🔴 仅量渲染宽不足以区分 tight / 松约束：本 sheet 的 _HelpRow 内有
      // Expanded，松 maxWidth=600 时也可能被撑到 600（上一轮假绿的根因）。
      // 这里直接读生产 SizedBox/DecoratedBox 那一层的**实际布局约束**：
      // tight ⇒ minWidth == maxWidth == 600；退回 ConstrainedBox(maxWidth)
      // ⇒ minWidth == 0，本条立刻转红。
      final RenderBox decorBox = tester.renderObject<RenderBox>(
        find
            .ancestor(
              of: find.byType(GardenHelpSheet),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(decorBox.constraints.minWidth, 600.0,
          reason: '宽度必须是 tight（SizedBox），ConstrainedBox(maxWidth) 是松约束');
      expect(decorBox.constraints.maxWidth, 600.0);
    });
  });

  // 源码级守卫：行为测试之外再钉一次生产行本身，双重保险。
  group('生产接线守卫（源码精确断言）', () {
    test('garden_page.dart 的 _showGardenHelp 用 SizedBox(width: ...) 定死宽度',
        () {
      const String sourcePath =
          'lib/presentation/child/pages/garden_page.dart';
      const String target =
          'width: gardenHelpDialogWidth(viewport.maxWidth),';
      final List<String> lines = File(sourcePath).readAsLinesSync();
      // 行首锚点（trimLeft 后整行精确相等）——注释里的说明文字不会误命中。
      final List<int> hits = <int>[];
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft() == target) hits.add(i + 1);
      }
      expect(hits, isNotEmpty,
          reason: '$sourcePath 的 _showGardenHelp 必须存在 tight 宽度行 `$target`；'
              '退回 ConstrainedBox(maxWidth: ...) 时本守卫与真实弹窗宽度测试都会转红');
    });

    test('生产代码不得再用 gardenHelpDialogWidth 当 maxWidth（松约束）', () {
      const String sourcePath =
          'lib/presentation/child/pages/garden_page.dart';
      const String regression =
          'maxWidth: gardenHelpDialogWidth(viewport.maxWidth),';
      final List<String> lines = File(sourcePath).readAsLinesSync();
      expect(
          lines.where((String line) => line.trimLeft() == regression), isEmpty,
          reason: 'maxWidth 是松约束，会让内容收缩，正是 2026-11-20 二次真机反馈的根因');
    });
  });
}
