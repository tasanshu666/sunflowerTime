/// 许愿弹窗（A22.2 / A24.6 + **v0.3.0 居中 Dialog / 删分类 / 字数双阈值**）。
///
/// 覆盖 R3-P0-02（居中 / 85% 高 / 底边 ≥80 / 键盘避让 / 内部滚动）、
/// R3-P0-03（分类 chip 全删）、R3-P0-04（100 / 300 双阈值 + counter==校验）。
///
/// 期望值写死独立量（100 / 300），不引用实现常量的「同一个值」做自证 —— 防恒绿；
/// 仅 `kWishTextMaxLengthZh/En` 用于确认「常量本身就是 100/300」。
/// 文案经参数化的 [AppLocalizations] 传入，裸测试宿主零 delegate 也能挂。
library wish_compose_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_compose_dialog.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 在真实 `showDialog` 路径上挂一个「点击打开弹层」的宿主（测居中 / 尺寸）。
Widget _dialogHost({
  required AppLocalizations l10n,
  required int maxTextLength,
  String initialText = '',
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              key: const Key('open_compose'),
              onPressed: () => showWishComposeDialog(
                context: context,
                l10n: l10n,
                maxTextLength: maxTextLength,
                initialText: initialText,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('⑪ 字数 = Unicode 码点', () {
    test('30 个 emoji = 30（不是 UTF-16 的 60）', () {
      final String emoji30 = '🌟' * 30;
      expect(emoji30.length, 60, reason: 'UTF-16 code unit 是 60');
      expect(wishTextRuneCount(emoji30), 30, reason: '码点数必须是 30');
    });

    testWidgets('UI 计数器按码点上限显示（zh 100 / en 300）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishComposeSheet(
        l10n: zh,
        initialText: '愿' * 12,
        maxTextLength: 100,
      )));
      expect(find.text('12/100'), findsOneWidget,
          reason: '中文 counter 上限 = 100（写死值，不引用常量自证）');

      await tester.pumpWidget(_host(WishComposeSheet(
        l10n: en,
        initialText: 'a' * 12,
        maxTextLength: 300,
      )));
      expect(find.text('12/300'), findsOneWidget, reason: '英文 counter 上限 = 300');
    });
  });

  group('⑫ 超长 ⇒ 标红 + 草稿保留', () {
    testWidgets('中文 101 字符 ⇒ 出现超长提示且草稿保留（99/100 不提示）',
        (WidgetTester tester) async {
      // 100 字符：不超长。（换 Key ⇒ 强制新 State，否则二帧复用旧 controller）
      await tester.pumpWidget(_host(WishComposeSheet(
        key: const Key('zh_100'),
        l10n: zh,
        initialText: '愿' * 100,
        maxTextLength: 100,
      )));
      expect(find.text(zh.wishComposeTooLong), findsNothing,
          reason: '恰 100 字符必须可提交（R3-P0-04③）');
      expect(find.text('100/100'), findsOneWidget);

      // 101 字符：超长 + 草稿保留。
      await tester.pumpWidget(_host(WishComposeSheet(
        key: const Key('zh_101'),
        l10n: zh,
        initialText: '愿' * 101,
        maxTextLength: 100,
      )));
      await tester.pump();
      expect(find.text(zh.wishComposeTooLong), findsOneWidget);
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('wish_compose_field')),
      );
      expect(field.controller!.text, '愿' * 101,
          reason: '超长不关闭、文本留在 controller（草稿保留）');
      expect(find.text('101/100'), findsOneWidget);
    });

    testWidgets('英文 301 字符 ⇒ 被拦（300 放行）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishComposeSheet(
        key: const Key('en_300'),
        l10n: en,
        initialText: 'a' * 300,
        maxTextLength: 300,
      )));
      expect(find.text(en.wishComposeTooLong), findsNothing, reason: '300 放行');
      expect(find.text('300/300'), findsOneWidget);

      await tester.pumpWidget(_host(WishComposeSheet(
        key: const Key('en_301'),
        l10n: en,
        initialText: 'a' * 301,
        maxTextLength: 300,
      )));
      await tester.pump();
      expect(find.text(en.wishComposeTooLong), findsOneWidget, reason: '301 被拦');
      expect(find.text('301/300'), findsOneWidget);
    });

    test('counter 上限与常量同源（zh=100 / en=300）', () {
      expect(kWishTextMaxLengthZh, 100);
      expect(kWishTextMaxLengthEn, 300);
      // 「counter 显示的上限 == 提交校验的上限」由同一 `maxTextLength` 入参保证；
      // 取数函数是唯一入口（R3-P0-04②）。
      expect(wishMaxTextLength('zh'), kWishTextMaxLengthZh);
      expect(wishMaxTextLength('en'), kWishTextMaxLengthEn);
    });
  });

  group('⑬ 关闭再开 ⇒ 草稿回填', () {
    testWidgets('initialText 回填到输入框', (WidgetTester tester) async {
      const String draft = '想要一个小恐龙';
      await tester.pumpWidget(_host(WishComposeSheet(
        l10n: zh,
        initialText: draft,
      )));
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('wish_compose_field')),
      );
      expect(field.controller!.text, draft);
    });
  });

  group('⑭ 弹窗文案走 ARB（无 CJK 硬编码，切 en 生效）', () {
    testWidgets('英文宿主显示英文标题与提交按钮', (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishComposeSheet(l10n: en)));
      expect(find.text(en.wishComposeTitle), findsOneWidget);
      expect(find.text(en.wishComposeSubmit), findsOneWidget);
      expect(find.text(en.wishComposeHint), findsOneWidget);
    });

    test('WishComposeResult 只带文本（v0.3.0 分类已下线）', () {
      const WishComposeResult r = WishComposeResult(text: 'x');
      expect(r.text, 'x');
    });
  });

  group('R3-P0-03 分类 UI 全删', () {
    testWidgets('弹层内不存在任何 wish_compose_category_* 节点',
        (WidgetTester tester) async {
      await tester.pumpWidget(_dialogHost(l10n: zh, maxTextLength: 100));
      await tester.tap(find.byKey(const Key('open_compose')));
      await tester.pumpAndSettle();
      for (int i = 0; i < 6; i++) {
        expect(find.byKey(Key('wish_compose_category_$i')), findsNothing,
            reason: '分类 chip 已下线（R3-P0-03①），index $i');
      }
      // 分类名字样也不得渲染（英文宿主同理）。
      expect(find.text(zh.wishCategoryGift), findsNothing);
    });
  });

  group('R3-P0-02 居中弹层几何', () {
    // 常见手机视口：390×844。
    Future<void> pumpOpen(WidgetTester tester, {double height = 844}) async {
      tester.view.physicalSize = Size(390, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dialogHost(l10n: zh, maxTextLength: 100));
      await tester.tap(find.byKey(const Key('open_compose')));
      await tester.pumpAndSettle();
    }

    testWidgets('① 中心与屏幕垂直中心偏差 ≤24dp；② 底边距 ≥80dp；③ ≤85% 屏高',
        (WidgetTester tester) async {
      await pumpOpen(tester);
      final Rect rect = tester.getRect(find.byKey(kWishComposeDialogKey));
      expect((rect.center.dy - 844 / 2).abs(), lessThanOrEqualTo(24),
          reason: '弹层必须居中（玄参反馈 2）');
      expect(rect.bottom, lessThanOrEqualTo(844 - 80),
          reason: '底边距屏幕底 ≥80dp（排除贴底 BottomSheet 观感）');
      expect(rect.height, lessThanOrEqualTo(844 * 0.85),
          reason: '最大高度 ≤ 屏高 85%');
      expect(tester.takeException(), isNull);
    });

    testWidgets('④ 键盘弹起（viewInsets.bottom>0）时输入框完整可见',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dialogHost(l10n: zh, maxTextLength: 100));
      await tester.tap(find.byKey(const Key('open_compose')));
      await tester.pumpAndSettle();

      // 模拟键盘 300dp。
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final Rect dialogRect =
          tester.getRect(find.byKey(kWishComposeDialogKey));
      final Rect fieldRect =
          tester.getRect(find.byKey(const Key('wish_compose_field')));
      // 只写不变式：输入框底边不越过弹层底边（不被键盘挤出可视区）。
      expect(fieldRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
      expect(dialogRect.bottom, lessThanOrEqualTo(844 - 300),
          reason: '弹层整体让位键盘（bottom padding = viewInsets）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('⑤ 内容超高 ⇒ 弹层内部可滚动（SingleChildScrollView）',
        (WidgetTester tester) async {
      // 矮视口 + 超长草稿（5 行输入框撑高）⇒ 内部滚动条生效。
      await pumpOpen(tester, height: 480);
      final Rect rect = tester.getRect(find.byKey(kWishComposeDialogKey));
      expect(rect.height, lessThanOrEqualTo(480 * 0.85 + 0.5),
          reason: '超高内容被 85% 上限兜住');
      expect(
        find.descendant(
          of: find.byKey(kWishComposeDialogKey),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
        reason: '弹层内部用 SingleChildScrollView 承接滚动',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('⑥ barrierDismissible:false ⇒ 点遮罩不关闭；取消按钮可关',
        (WidgetTester tester) async {
      await pumpOpen(tester);
      // 点弹层外的空白（左上角）。
      await tester.tapAt(const Offset(6, 6));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsOneWidget,
          reason: 'barrierDismissible:false ⇒ 点遮罩不关（防误触丢草稿）');

      // 显式取消出口。
      await tester.tap(find.byKey(const Key('wish_compose_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(kWishComposeDialogKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
