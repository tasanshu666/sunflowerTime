// QA 独立复验（F212 修订版）：用 SDK 真 Roboto-Black.ttf 对 GuardBuffChip
// 做渲染层实测。flutter test 默认 Ahem 字宽 ≈ 真 Roboto 的 2.17×，禁止用
// Ahem 判行布局 / 卡高 —— 本文件全部走 FontLoader 注入真 Roboto。
//
// 🔴 回归目标：en + 1.3 倍字号 + 用完态施肥 / 专注加餐券，正文不得断出孤行
// （「up」独占第三行），卡高不得突破历史真机结论 40pt（B13.17 改横排的
// 前提就是避免券卡挡住植物）。
library qa_guard_buff_roboto_orphan_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, TextBox;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart'
    show GuardBuffState;
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';

const String _kFontFamily = 'QaRobotoBlack';

/// 从 flutter_tester 可执行文件反推 SDK 的 material_fonts 目录，避免写死机器路径。
/// flutter_tester 位于 `<sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester`。
String get _robotoBlackPath {
  final Directory artifacts = Directory(Platform.resolvedExecutable)
      .parent
      .parent
      .parent;
  final File fromSdk =
      File('${artifacts.path}/material_fonts/Roboto-Black.ttf');
  if (fromSdk.existsSync()) return fromSdk.path;
  return '/Users/wangjunchao/development/flutter/bin/cache/artifacts/'
      'material_fonts/Roboto-Black.ttf';
}

Finder get _chip => find.byKey(GuardBuffChip.chipKey);

Finder get _bodyFinder => find.descendant(
      of: _chip,
      matching: find.byWidgetPredicate(
        (Widget w) => w is Text && w.textSpan != null,
      ),
    );

/// 真 Roboto 下逐字符取绘制盒，按 top 还原**实际断行文本**。
/// 只看 TextSpan 原始串无法发现 ellipsis 吞字 / 孤行（F212 教训）。
List<String> _paintedLines(WidgetTester tester) {
  final RenderParagraph para = tester.renderObject<RenderParagraph>(_bodyFinder);
  final String plain =
      (tester.widget<Text>(_bodyFinder).textSpan!).toPlainText();
  final Map<int, StringBuffer> byTop = <int, StringBuffer>{};
  for (int i = 0; i < plain.length; i++) {
    final List<TextBox> boxes = para.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) continue;
    byTop
        .putIfAbsent(boxes.first.top.round(), () => StringBuffer())
        .write(plain[i]);
  }
  final List<int> tops = byTop.keys.toList()..sort();
  return tops.map((int top) => byTop[top]!.toString()).toList();
}

Future<void> _pump(
  WidgetTester tester, {
  required GuardDropKind kind,
  required int quota,
  required int used,
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: _kFontFamily, useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GuardBuffChip(
              buff: GuardBuffState(kind: kind, quota: quota, used: used),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final File ttf = File(_robotoBlackPath);
    expect(ttf.existsSync(), isTrue, reason: 'Flutter SDK Roboto-Black.ttf 缺失');
    final FontLoader loader = FontLoader(_kFontFamily);
    loader.addFont(ttf.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load().timeout(const Duration(seconds: 10));
  });

  for (final MapEntry<Size, double> viewport in <MapEntry<Size, double>>[
    const MapEntry<Size, double>(Size(320, 568), 1.3),
    const MapEntry<Size, double>(Size(390, 844), 1.3),
  ]) {
    for (final (GuardDropKind kind, int quota, String tail) in [
      (GuardDropKind.fertilizeVoucher, 2, 'Used up'),
      (GuardDropKind.focusMeal, 1, 'Used up'),
    ]) {
      testWidgets(
        'en ${viewport.key.shortestSide}@${viewport.value} ${kind.id} 用完态'
        '不得孤行 / 卡高≤40pt',
        (WidgetTester tester) async {
          await _pump(
            tester,
            kind: kind,
            quota: quota,
            used: quota,
            size: viewport.key,
            textScale: viewport.value,
          );

          final List<String> lines = _paintedLines(tester);
          final double height = tester.getRect(_chip).height;
          final String detail = 'lines=$lines chipH=${height.toStringAsFixed(1)}';

          expect(lines.length, lessThanOrEqualTo(2),
              reason: '🔴 真 Roboto 下正文至多 2 行，$detail');
          // 末行允许是「· Used up」整段（正文前缀断行后状态词整体落到第二行），
          // 但必须含完整 tail —— 不能只剩 up。判「显示正确」而非「特定断行点」。
          expect(lines.last.trim(), endsWith(tail),
              reason: '🔴 末行必须含完整「$tail」，不得把 up 孤立成行，$detail');
          // 历史真机结论：F212 交付版 en 1.3 施肥用完态 40pt；B13.17 改横排
          // 就是为避免券卡挡植物。+1pt 容差给字体渲染取整。
          expect(height, lessThanOrEqualTo(41.0),
              reason: '🔴 卡高不得突破历史真机上限 40pt（会重新挡植物），$detail');

          final RenderParagraph body =
              tester.renderObject<RenderParagraph>(_bodyFinder);
          expect(body.didExceedMaxLines, isFalse,
              reason: '不得被 ellipsis 截断');
          expect(tester.takeException(), isNull, reason: '不得有 RenderFlex overflow');
        },
      );
    }
  }
}
