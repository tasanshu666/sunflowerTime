/// A-T04 许愿弹窗（A22.2 / A24.6）断言 ⑪~⑭。
///
/// 期望值写死独立量，不引用 `kWishTextMaxLength` 等实现常量（防恒绿）。
/// 文案经参数化的 [AppLocalizations] 传入，裸测试宿主零 delegate 也能挂。
library wish_compose_dialog_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_compose_dialog.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('⑪ 字数 = Unicode 码点', () {
    test('30 个 emoji = 30（不是 UTF-16 的 60）', () {
      final String emoji30 = '🌟' * 30;
      expect(emoji30.length, 60, reason: 'UTF-16 code unit 是 60');
      expect(wishTextRuneCount(emoji30), 30, reason: '码点数必须是 30');
    });

    testWidgets('UI 计数器显示 30/30', (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishComposeSheet(
        l10n: zh,
        initialText: '🌟' * 30,
      )));
      expect(find.text('30/30'), findsOneWidget,
          reason: '计数器按码点显示 30/30，不显示 60');
    });
  });

  group('⑫ 超长 ⇒ 标红 + 草稿保留', () {
    testWidgets('超长提示出现且文本仍在输入框（草稿保留）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(WishComposeSheet(
        l10n: zh,
        initialText: '愿' * 31,
      )));
      // 超长提示文案走 ARB。
      expect(find.text(zh.wishComposeTooLong), findsOneWidget);
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('wish_compose_field')),
      );
      expect(field.controller!.text, '愿' * 31,
          reason: '超长不关闭、文本留在 controller（草稿保留）');
    });

    test('超长判据按码点：30 emoji 不超长', () {
      expect(wishTextRuneCount('🌟' * 30), 30);
      // 30 是上限（写死），31 才超长。
      expect(wishTextRuneCount('🌟' * 31), 31);
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

    test('WishComposeResult 回复原文与分类下标', () {
      const WishComposeResult r = WishComposeResult(text: 'x', categoryIndex: 3);
      expect(r.text, 'x');
      expect(r.categoryIndex, 3);
    });
  });
}
