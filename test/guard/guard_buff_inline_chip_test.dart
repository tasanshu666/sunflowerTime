// 守卫券卡 B13.9「横排卡」widget 级测试。
//
// B13.9（玄参）：翻转卡退役，改「小图标 + 右侧文字」横排 —— 图标缩到 24 宽
// （48 的一半，AspectRatio 276/294），右侧单行「今日浇水 −1☀」（☀ 用
// sunlight.png 的 WidgetSpan 内联小图）。无点击行为 ⇒ 整卡 IgnorePointer。
//
// widget 级夹具（不碰任何服务）；直挂 [GuardBuffChip] 于宿主，zh / en 都跑。
// 🔴 屏幕固定 390×844（uiScale == 1.0）：chip 宽高乘 uiScale，非手机宽度下
//   数值断言会错位（默认 800 宽测试面 uiScale = 1.3，踩过）。
library guard_buff_inline_chip_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, TextBox;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart'
    show GuardBuffState;
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';

/// 宿主：MaterialApp + 本地化 + 左上角挂 chip。
Widget _host(Widget child, {Locale locale = const Locale('zh')}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );
}

/// 统一 pump：390×844（uiScale 1.0）+ 渲染两帧等图片资源解析。
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('zh'),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(child, locale: locale));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 横排文字的 Text.rich 根 span（样式 / 纯文本都从这取）。
TextSpan _spanOf(WidgetTester tester) {
  // 🔴 B13.21 第 2 轮：xN 已拆成独立 Text(data:)，此处只取正文 Text.rich
  // （`textSpan != null`），否则 finder 命中两个 Text 报 "Too many elements"。
  final Text text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(GuardBuffChip.chipKey),
      matching: find.byWidgetPredicate(
          (Widget w) => w is Text && w.textSpan != null),
    ),
  );
  final InlineSpan? span = text.textSpan;
  expect(span, isNotNull, reason: 'B13.9 横排文字必须是 Text.rich（带 ☀ 内联图）');
  return span! as TextSpan;
}

/// 横排文字的纯文本（历史口径：正文 + 空格 + 数值 + 空格 + 独立 xN widget，
/// 拼成「…0 x1」）。
/// 🔴 修订方案：数值已从正文段落挪到尾部 `guardBuffChipValue`，这里把三段
/// 拼回去，让②/②b/⑤/⑤b 等历史「文案含数值 / xN」断言继续按原口径工作。
String _plainTextOf(WidgetTester tester) {
  final String main = _spanOf(tester).toPlainText().replaceAll('\uFFFC', '');
  final Finder value = find.byKey(GuardBuffChip.valueKey);
  final Finder suffix = find.byKey(const Key('guardBuffChipRemaining'));
  final String valueText =
      value.evaluate().isEmpty ? '' : tester.widget<Text>(value).data ?? '';
  final String suffixText =
      suffix.evaluate().isEmpty ? '' : tester.widget<Text>(suffix).data ?? '';
  final List<String> parts = <String>[main, valueText, suffixText]
      .where((String part) => part.isNotEmpty)
      .toList();
  return parts.join(' ');
}

/// 统一 pump（指定 textScale）：390×844（uiScale 1.0）+ 渲染两帧。
Future<void> _pumpAtScale(
  WidgetTester tester,
  Widget child, {
  required double textScale,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(_host(child, locale: const Locale('en')));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 横排文字的 RenderParagraph（钉住「是否被 ellipsis 截断 / 占几行」）。
RenderParagraph _paragraphOf(WidgetTester tester) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(GuardBuffChip.chipKey),
      matching: find.byWidgetPredicate(
          (Widget w) => w is Text && w.textSpan != null),
    ),
  );
}

/// 🔴 钉住「[fragment] 真的被绘制到屏幕上」，而不是只存在于 TextSpan 原始串里
/// （QA 指出 `_plainTextOf` 在 ellipsis 截断时仍含被吞掉的字符 = 假绿）。
/// 双保险：① `didExceedMaxLines == false`（无行被省略）；② 该片段在
/// RenderParagraph 上确有绘制 box。
void expectPainted(
  WidgetTester tester,
  String fragment, {
  String reason = '',
}) {
  final RenderParagraph para = _paragraphOf(tester);
  expect(para.didExceedMaxLines, isFalse,
      reason: '文案被 ellipsis 截断了，"$fragment" 所在行可能整行丢失');
  final String plain = _spanOf(tester).toPlainText();
  final int start = plain.indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0),
      reason: 'TextSpan 原始串里应含 "$fragment"');
  final List<TextBox> boxes = para.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + fragment.length),
  );
  expect(boxes, isNotEmpty,
      reason: reason.isNotEmpty
          ? reason
          : '🔴 "$fragment" 必须真的被绘制（有 box），否则就是被 ellipsis 吞掉的假绿');
}

/// 🔴 钉住「剩余次数 xN 是 Row 末尾独立 widget 且真被绘制」——
/// 不再参与正文 ellipsis，任何语言 / 字号下都不会被吞（截图原案主路径）。
void expectRemainingPainted(
  WidgetTester tester,
  String expected, {
  String reason = '',
}) {
  final Finder suffix = find.byKey(const Key('guardBuffChipRemaining'));
  expect(suffix, findsOneWidget,
      reason: '免费券 xN 必须是独立 widget（不进 Text.rich.children）');
  final Text text = tester.widget<Text>(suffix);
  expect(text.data, expected, reason: '🔴 xN 必须是 ASCII 小写 x（绝不为 ×）');
  final RenderParagraph para = tester.renderObject<RenderParagraph>(suffix);
  expect(para.didExceedMaxLines, isFalse, reason: reason);
  final List<TextBox> boxes = para.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  expect(boxes, isNotEmpty, reason: '🔴 "$expected" 必须真被绘制在屏幕上');
}

/// 🔴 修订方案：数值已独立成 Text，这里按 valueKey 做与 xN 同口径的渲染层
/// 断言（didExceedMaxLines + getBoxesForSelection），防止只看 TextSpan 假绿。
void expectValuePainted(
  WidgetTester tester,
  String expected, {
  String reason = '',
}) {
  final Finder value = find.byKey(GuardBuffChip.valueKey);
  expect(value, findsOneWidget,
      reason: '数值必须是尾部紧凑组里的独立 Text（不进 Text.rich.children）');
  final Text text = tester.widget<Text>(value);
  expect(text.data, expected, reason: '数值口径错误');
  expect(text.data, isNot(contains('×')),
      reason: '🔴 数值绝不能出现 ×（A3 / 开花奖励用例按 × 定位）');
  final RenderParagraph para = tester.renderObject<RenderParagraph>(value);
  expect(para.didExceedMaxLines, isFalse, reason: reason);
  final List<TextBox> boxes = para.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  expect(boxes, isNotEmpty, reason: '🔴 "$expected" 必须真被绘制在屏幕上');
}

/// 正文 Text.rich 的唯一 finder（尾部数值 / xN 都是独立 Text，textSpan == null）。
Finder _bodyFinder() {
  return find.descendant(
    of: find.byKey(GuardBuffChip.chipKey),
    matching: find.byWidgetPredicate(
        (Widget w) => w is Text && w.textSpan != null),
  );
}

/// 尾部 ☀ 内联小图（AssetImage 指向 sunlight.png）。
Finder _sunGlyph() {
  return find.descendant(
    of: find.byKey(GuardBuffChip.chipKey),
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/rewards/sunlight.png',
    ),
  );
}

/// 左侧券卡插画（assets/guard/buff_voucher/*.webp）。
Finder _voucherImage() {
  return find.descendant(
    of: find.byKey(GuardBuffChip.chipKey),
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName.contains('buff_voucher'),
    ),
  );
}

/// ⑨ 号用例的关键组合夹具（kind / 额度 / 已用 / 数值 / 剩余次数 / 必绘文案）。
class _ChipCase {
  const _ChipCase(
    this.kind,
    this.quota,
    this.used,
    this.value,
    this.remaining,
    this.word,
  );

  final GuardDropKind kind;
  final int quota;
  final int used;
  final String value;
  final String remaining;
  final String word;
}

void main() {
  testWidgets('① 横排几何：图标槽 24 宽 / 比例 276:294 / 整卡 IgnorePointer',
      (WidgetTester tester) async {
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 0),
      ),
    );

    // 图标槽 = 24 宽（48 的一半）；AspectRatio 276:294 ⇒ 高 ≈ 25.57。
    final AspectRatio ratio = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(ratio.aspectRatio, closeTo(276 / 294, 1e-6),
        reason: '图标必须沿用美术原比 276:294');

    final Rect icon = tester.getRect(_voucherImage());
    expect(icon.width, closeTo(24, 0.5),
        reason: '🔴 图标宽 = 48 的一半 = 24（uiScale 1.0）');
    expect(icon.height, closeTo(24 * 294 / 276, 0.8),
        reason: '图标高按 276:294 原比派生');

    final Rect rect = tester.getRect(find.byKey(GuardBuffChip.chipKey));
    // 🔴 B13.16 实底白卡：Material 内加 Padding(h6/v3) ⇒ 卡高 = 图标高 25.57
    //    + 上下各 3 = **31.57**（旧口径 25.6 已随白卡背景退役）。
    expect(rect.height, closeTo(24 * 294 / 276 + 6, 0.8),
        reason: 'B13.16 白卡卡高 = 图标 25.57 + 上下 padding 3×2（图标缩半不变）');
    expect(rect.width, greaterThan(24), reason: '右侧有文字，总宽必须大于图标宽');
    expect(rect.width, lessThan(160),
        reason: '横排卡总宽 ~24 + 4 + 文字，显著小于旧竖卡时代的可伸缩上限');
    // 🔴 修订③：卡宽 132 → 136（uiScale 1.0），+ Padding 左右各 6 = 148 < 160。
    final ConstrainedBox widthBox = tester.widget<ConstrainedBox>(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byType(ConstrainedBox),
      ),
    );
    expect(widthBox.constraints.maxWidth, 136,
        reason: '修订③ 卡宽必须是 136*uiScale（手机 uiScale = 1.0）');
    expect(rect.width, lessThanOrEqualTo(148.5),
        reason: '卡宽 136 + Padding 12 = 148，仍显著小于 160');

    // 🔴 无点击行为 ⇒ 整卡 IgnorePointer（放行花盆点击，wiring ⑤/⑭ 回归）。
    expect(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
      reason: 'B13.9 横排无交互，必须包 IgnorePointer',
    );
    // 翻转卡遗迹不许回来。
    expect(find.byKey(const Key('gardenGuardBuffChipFront')), findsNothing,
        reason: 'B13.8 翻转卡正面 Key 已删');
    expect(find.byKey(const Key('gardenGuardBuffChipBack')), findsNothing,
        reason: 'B13.8 翻转卡背面 Key 已删');
    expect(tester.takeException(), isNull);
  });

  testWidgets('② 文字内容（zh）：「今日浇水 -1」+ ☀ 内联小图',
      (WidgetTester tester) async {
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 0),
      ),
    );

    final String plain = _plainTextOf(tester);
    expect(plain, contains('今日浇水'), reason: '前缀 + shortOf 组装');
    expect(plain, contains('-1'), reason: 'effectValueOf = 浇水省 1 ☀（常量派生）');
    expect(_sunGlyph(), findsOneWidget,
        reason: '☀ 必须是 sunlight.png 的 WidgetSpan 内联小图');
    expect(tester.takeException(), isNull);
  });

  testWidgets('②b 符号口径：劳动券 +N、施肥券 −N（沿用 descLineOf 逻辑）',
      (WidgetTester tester) async {
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.laborVoucher, quota: 6, used: 0),
      ),
    );
    expect(_plainTextOf(tester), contains('今日除草'),
        reason: '劳动券动作词 = 除草');
    expect(_plainTextOf(tester), contains('+1'),
        reason: '劳动类是加（+kGuardLaborVoucherBonus）');

    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.fertilizeVoucher, quota: 2, used: 1),
      ),
    );
    expect(_plainTextOf(tester), contains('今日施肥'));
    expect(_plainTextOf(tester), contains('-2'),
        reason: '施肥类是省（−kGuardFertilizerVoucherSave）');
    expect(_plainTextOf(tester), isNot(contains('已用完')),
        reason: '额度未用完 ⇒ 不追加「已用完」');
    expect(tester.takeException(), isNull);
  });

  testWidgets('②c en：前缀走 ARB 语序（Today: {action}）+ ☀ 小图',
      (WidgetTester tester) async {
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 0),
      ),
      locale: const Locale('en'),
    );

    final String plain = _plainTextOf(tester);
    expect(plain, startsWith('Today:'), reason: 'en 语序由 ARB 占位符决定');
    expect(plain, contains('-1'));
    expect(_sunGlyph(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('③ 已用完态：施肥券用完灰显 + 「· 已用完」；浇水券不限次永不出现',
      (WidgetTester tester) async {
    // 施肥券 quota 2 used 2 ⇒ 用完。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.fertilizeVoucher, quota: 2, used: 2),
      ),
    );
    expect(_plainTextOf(tester), contains('已用完'),
        reason: '判定单点 usedUpOf（与 descLineOf 共用）');
    expect(_spanOf(tester).style!.color, const Color(0xFF9A8F7F),
        reason: '已用完 ⇒ 灰显（不再是红色）—— 样式在 TextSpan 上，不在 Text 上');

    // 浇水券（B13.4 不限次）quota 2 used 2 ⇒ 永不「已用完」。
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 2, used: 2),
      ),
    );
    expect(_plainTextOf(tester), isNot(contains('已用完')),
        reason: '🔴 不限次券永不「已用完」');
    expect(_spanOf(tester).style!.color, const Color(0xFFD93025),
        reason: '正常态 = 红色');
    expect(tester.takeException(), isNull);
  });

  testWidgets('④ 全券种：文案不含 `×`（A3 / 开花奖励用例按 × 定位 chips 行）',
      (WidgetTester tester) async {
    for (final GuardDropKind kind in <GuardDropKind>[
      GuardDropKind.waterVoucher,
      GuardDropKind.laborVoucher,
      GuardDropKind.fertilizeVoucher,
      GuardDropKind.freeWater,
      GuardDropKind.freeFertilize,
    ]) {
      await _pump(
        tester,
        GuardBuffChip(buff: GuardBuffState(kind: kind, quota: 6, used: 2)),
      );
      expect(_plainTextOf(tester), isNot(contains('×')), reason: '${kind.id} ×');
      expect(tester.takeException(), isNull, reason: '${kind.id} overflow');
    }
  });

  // 🔴 B13.20a（玄参 2026-11-13）：免费券在 ☀ 之后显示剩余次数 xN（ASCII
  // 小写 x），用一次减一；用完 = x0 + 灰显，**不再追加「· 已用完」**。
  testWidgets('⑤ B13.20a 免费券剩余次数：x2 → x1 → x0，x0 灰显且无「已用完」',
      (WidgetTester tester) async {
    // 免费施肥×2 券：额度 2 → x2。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.freeFertilize2, quota: 2, used: 0),
      ),
    );
    expect(_plainTextOf(tester), contains(' x2'),
        reason: '玄参原话「今日施肥0阳光 x2」——☀ 图标之后是 ASCII x2');
    expect(_plainTextOf(tester), isNot(contains('已用完')));

    // 用一次 → x1。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.freeFertilize2, quota: 2, used: 1),
      ),
    );
    expect(_plainTextOf(tester), contains(' x1'),
        reason: '用一次变 x1');
    expect(_spanOf(tester).style!.color, const Color(0xFFD93025),
        reason: '还有额度 ⇒ 红色');

    // 再用一次 → x0：灰显（第二重反馈），文案无「已用完」（x0 已表达）。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.freeFertilize2, quota: 2, used: 2),
      ),
    );
    expect(_plainTextOf(tester), contains(' x0'),
        reason: '再用一次变 x0');
    expect(_plainTextOf(tester), isNot(contains('已用完')),
        reason: '🔴 免费券用完态由 x0 承担，「不需要过多的文案」');
    expect(_spanOf(tester).style!.color, const Color(0xFF9A8F7F),
        reason: 'x0 ⇒ 灰显（样式在根 TextSpan 上）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑤b B13.20a 免费浇水券 x1 / ×3 券 x3；付费券与专注券无 xN 后缀',
      (WidgetTester tester) async {
    // 免费浇水券额度 1 ⇒ x1。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 0),
      ),
    );
    expect(_plainTextOf(tester), contains(' x1'),
        reason: '免费浇水券 = 今日前 1 次免费 ⇒ x1');

    // ×3 券额度 3 ⇒ x3。
    await _pump(
      tester,
      const GuardBuffChip(
        buff:
            GuardBuffState(kind: GuardDropKind.freeWater3, quota: 3, used: 0),
      ),
    );
    expect(_plainTextOf(tester), contains(' x3'));

    // 付费浇水券（不限次）与专注加餐券（被动券）：无 xN。
    for (final GuardDropKind kind in <GuardDropKind>[
      GuardDropKind.waterVoucher,
      GuardDropKind.focusMeal,
      GuardDropKind.focusBoost,
    ]) {
      await _pump(
        tester,
        GuardBuffChip(buff: GuardBuffState(kind: kind, quota: 1, used: 0)),
      );
      expect(RegExp(r' x\d').hasMatch(_plainTextOf(tester)), isFalse,
          reason: '${kind.id} 无次数概念，不加 xN');
      expect(tester.takeException(), isNull, reason: '${kind.id} overflow');
    }
  });

  testWidgets('⑤c B13.20a/b 专注双券（加餐+放大）图标 = 同一张向日葵待机首帧',
      (WidgetTester tester) async {
    // 🔴 B13.20b（玄参 2026-11-13）：「专注放大券和专注加餐券应该是同一个图标」
    // —— 两张券都渲染专注页待机首帧 PNG，且都不再是 buff_voucher 浇水卡面。
    for (final GuardDropKind kind in <GuardDropKind>[
      GuardDropKind.focusMeal,
      GuardDropKind.focusBoost,
    ]) {
      await _pump(
        tester,
        GuardBuffChip(buff: GuardBuffState(kind: kind, quota: 1, used: 0)),
      );
      expect(find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byWidgetPredicate((Widget w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage)
                .assetName
                .contains('buff_voucher')),
      ), findsNothing, reason: '${kind.id} 不再复用浇水卡面');
      expect(
        find.descendant(
          of: find.byKey(GuardBuffChip.chipKey),
          matching: find.byWidgetPredicate((Widget w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'assets/fx/focus/sunflower/idle/frame001.webp'),
        ),
        findsOneWidget,
        reason: '${kind.id} 图标 = 专注页向日葵待机首帧（双券同款）',
      );
      expect(_plainTextOf(tester), contains('今日专注'),
          reason: '${kind.id} 文案保持简洁口径');
      expect(tester.takeException(), isNull, reason: '${kind.id} overflow');
    }
  });

  // 🔴 B13.21（玄参 2026-11-24 截图）：en「Today: Water 0…」被 ellipsis 截断，
  // 尾部 xN / ☀ 看不见。QA 独立验证指出「只查原始 TextSpan = 假绿」，本用例
  // 全部改用渲染层断言（didExceedMaxLines + getBoxesForSelection）。
  testWidgets('⑥ en 免费券截图原案：尾部 x1 / ☀ 真被绘制；zh 零回归',
      (WidgetTester tester) async {
    // ── 截图原案：en 免费浇水券「Today: Water 0☀ x1」。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 0),
      ),
      locale: const Locale('en'),
    );
    final Text enText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(GuardBuffChip.chipKey),
        matching: find.byWidgetPredicate(
            (Widget w) => w is Text && w.textSpan != null),
      ),
    );
    expect(enText.maxLines, 5,
        reason: '🔴 上限必须够：免费券 3 行 / 用完施肥 4 行 / 1.3 倍最多 5 行');
    expect(enText.overflow, TextOverflow.ellipsis,
        reason: 'ellipsis 仅作极端无障碍字号兜底，防 RenderFlex overflow');
    expect(_spanOf(tester).toPlainText(), isNot(contains('x1')),
        reason: '🔴 结构断言：xN 必须已从 Text.rich.children 拆出');
    expectPainted(tester, 'Today: Water', reason: '动作词真被绘制');
    expectValuePainted(tester, '0', reason: '数值 0 真被绘制');
    expectRemainingPainted(tester, 'x1',
        // QA 指出的假绿点：旧断言 `_plainTextOf` 即使被吞也含 x1。
        // 现在独立 widget + getBoxesForSelection，截断时必红。
        );
    expect(_sunGlyph(), findsOneWidget, reason: '☀ 独立 widget 在位');
    expect(tester.takeException(), isNull);

    // ── zh：同款免费券中文短，仍完整 + 卡高不变（Wrap 横排零回归）。
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 0),
      ),
    );
    expectRemainingPainted(tester, 'x1', reason: 'zh 免费券 ASCII 小写 x + 次数口径不变');
    expect(tester.getRect(find.byKey(GuardBuffChip.chipKey)).height, lessThan(40),
        reason: 'zh 文案短，卡高不撑大，左上角不挡植物');
    expect(tester.takeException(), isNull);
  });

  // 🔴 QA 独立验证第 4 项：en 用完态「· Used up」与 1.3 倍字号下
  // 数值 / ☀ / xN 被吞。此处把三组最坏组合全部钉在「渲染层真被绘制」上。
  testWidgets('⑦ en 最坏组合（用完态 / 1.3 倍字号）关键信息仍全部被绘制',
      (WidgetTester tester) async {
    // ── en 施肥用完态「Today: Feed -2 · Used up☀」，scale 1.0。
    await _pumpAtScale(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.fertilizeVoucher, quota: 2, used: 2),
      ),
      textScale: 1.0,
    );
    expectValuePainted(tester, '-2', reason: '减免数值不能被吞');
    expectPainted(tester, 'Used up', reason: '用完态文案不能被吞');
    expect(_sunGlyph(), findsOneWidget, reason: '☀ 独立 widget 在位');

    // ── 同券 scale 1.3（此前连 -2 都只剩 '-'）。
    await _pumpAtScale(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(
            kind: GuardDropKind.fertilizeVoucher, quota: 2, used: 2),
      ),
      textScale: 1.3,
    );
    expectValuePainted(tester, '-2', reason: '🔴 1.3 倍字号下数值仍须完整');
    // 🔴 QA 真 Roboto 复验：原版此处正文断成 3 行（up 孤行）、卡高 57pt；
    // 已改为 en 用完态「动作词 ·\nUsed up」两行紧凑口径，末行不拆词。
    // Ahem 字宽是真 Roboto 的 2.17×，断行位置不同但同样不超 5 行上限。
    expectPainted(tester, 'Used up',
        reason: '🔴 1.3 倍字号下 Used up 仍须完整绘制且不孤行');
    expect(_sunGlyph(), findsOneWidget, reason: '🔴 1.3 倍字号下 ☀ 仍在位');

    // ── en 免费浇水 + scale 1.3（此前只绘制「Today: Water 」）。
    await _pumpAtScale(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 0),
      ),
      textScale: 1.3,
    );
    expectPainted(tester, 'Today: Water');
    expectValuePainted(tester, '0', reason: '🔴 免费券数值 0 不能被吞');
    expectRemainingPainted(tester, 'x1', reason: '🔴 1.3 倍字号下 x1 仍须完整');
    expect(_sunGlyph(), findsOneWidget, reason: '🔴 1.3 倍字号下 ☀ 仍在位');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑧ 修订①②：正文与数值不黏字；longestLine 消除用完态假空白',
      (WidgetTester tester) async {
    await _pump(
      tester,
      const GuardBuffChip(
        buff: GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 0),
      ),
      locale: const Locale('en'),
    );
    final RenderParagraph bodyPara = _paragraphOf(tester);
    final String plain = _spanOf(tester).toPlainText();
    expect(plain, isNot(contains('0')),
        reason: '结构断言：数值已移出正文段落');

    // 正文末字的绘制盒右边缘 → 数值绘制盒左边缘，混入 2px spacer 后必须 ≥2px。
    final List<TextBox> lastBoxes = bodyPara.getBoxesForSelection(
      TextSelection(baseOffset: plain.length - 1, extentOffset: plain.length),
    );
    expect(lastBoxes, isNotEmpty, reason: '正文末字必须真被绘制');
    final double bodyRight =
        tester.getRect(_bodyFinder()).left + lastBoxes.last.right;
    final RenderParagraph valuePara =
        tester.renderObject<RenderParagraph>(find.byKey(GuardBuffChip.valueKey));
    final List<TextBox> valueBoxes = valuePara.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    expect(valueBoxes, isNotEmpty);
    final double valueLeft =
        tester.getRect(find.byKey(GuardBuffChip.valueKey)).left +
        valueBoxes.first.left;
    expect(valueLeft - bodyRight, greaterThanOrEqualTo(1.99),
        reason: '🔴 修订②：正文与数值之间必须有 2px spacer，不能黏成 Water0');

    // 修订①：textWidthBasis 必须生效，段落盒宽 = 最长已排行宽（不再取固有最大宽）。
    expect(tester.widget<Text>(_bodyFinder()).textWidthBasis,
        TextWidthBasis.longestLine,
        reason: '🔴 修订①：正文必须设 longestLine');
    final List<TextBox> allBoxes = bodyPara.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length),
    );
    expect(allBoxes, isNotEmpty);
    final double maxLineRight = allBoxes.fold<double>(
        0.0,
        (double max, TextBox box) => box.right > max ? box.right : max);
    expect(bodyPara.size.width, lessThanOrEqualTo(maxLineRight + 1.0),
        reason:
            '🔴 longestLine 生效：段落盒宽应紧贴最长已排行，右侧不得有假空白');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑨ 修订后关键组合：数值 / xN / 动作词逐字符绘制且无 overflow',
      (WidgetTester tester) async {
    const List<_ChipCase> cases = <_ChipCase>[
      _ChipCase(GuardDropKind.laborVoucher, 6, 0, '+1', '', 'Weeding'),
      _ChipCase(GuardDropKind.focusBoost, 1, 0, '+20%', '', 'Focus'),
      _ChipCase(GuardDropKind.freeFertilize2, 2, 0, '0', 'x2', 'Feed'),
      _ChipCase(GuardDropKind.freeWater, 1, 1, '0', 'x0', 'Water'),
      _ChipCase(GuardDropKind.fertilizeVoucher, 2, 2, '-2', '', 'Used up'),
    ];
    for (final _ChipCase entry in cases) {
      await _pump(
        tester,
        GuardBuffChip(
          buff: GuardBuffState(
            kind: entry.kind,
            quota: entry.quota,
            used: entry.used,
          ),
        ),
        locale: const Locale('en'),
      );
      expectPainted(tester, entry.word, reason: '${entry.kind.id} 动作词/状态');
      expectValuePainted(tester, entry.value, reason: '${entry.kind.id} 数值');
      // 🔴 修订①几何复核（含 en 施肥用完态「· Used up」）：段落盒宽必须紧贴
      // 最长已排行，不能等于固有最大宽而在末行右侧留下假空白。
      final RenderParagraph bodyPara = _paragraphOf(tester);
      final String bodyPlain = _spanOf(tester).toPlainText();
      final List<TextBox> lineBoxes = bodyPara.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: bodyPlain.length),
      );
      final double longestLine = lineBoxes.fold<double>(
          0.0,
          (double max, TextBox box) => box.right > max ? box.right : max);
      expect(bodyPara.size.width, lessThanOrEqualTo(longestLine + 1.0),
          reason: '🔴 ${entry.kind.id} longestLine 生效，右侧不得留假空白');
      if (entry.remaining.isEmpty) {
        expect(find.byKey(const Key('guardBuffChipRemaining')), findsNothing,
            reason: '${entry.kind.id} 无剩余次数概念');
      } else {
        expectRemainingPainted(tester, entry.remaining,
            reason: '${entry.kind.id} xN 永不被吞');
      }
      expect(_sunGlyph(), findsOneWidget, reason: '${entry.kind.id} ☀ 在位');
      expect(tester.takeException(), isNull, reason: '${entry.kind.id} overflow');
    }
  });

  // 🔴 flutter test 默认 Ahem 字宽约为真 Roboto 的 2.17×，不能据此判「单行」。
  // 真 Roboto 390 手机单行由 QA 前置全券种核查（Roboto-Black.ttf 实测）覆盖；
  // 这里在 Ahem 下只钉「不截断 / 不黏字 / 不溢出」三个与字体无关的结构性质。
  testWidgets('⑩ 关键组合（Ahem）：无 ellipsis / 正文与数值不黏字 / 无溢出',
      (WidgetTester tester) async {
    const List<_ChipCase> cases = <_ChipCase>[
      _ChipCase(GuardDropKind.laborVoucher, 6, 0, '+1', '', 'Weeding'),
      _ChipCase(GuardDropKind.focusBoost, 1, 0, '+20%', '', 'Focus'),
      _ChipCase(GuardDropKind.freeWater, 1, 0, '0', 'x1', 'Water'),
      _ChipCase(GuardDropKind.freeWater, 1, 1, '0', 'x0', 'Water'),
    ];
    for (final _ChipCase entry in cases) {
      await _pump(
        tester,
        GuardBuffChip(
          buff: GuardBuffState(
            kind: entry.kind,
            quota: entry.quota,
            used: entry.used,
          ),
        ),
        locale: const Locale('en'),
      );
      final RenderParagraph body = _paragraphOf(tester);
      final String plain = _spanOf(tester).toPlainText();
      final List<TextBox> boxes = body.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length),
      );
      expect(body.didExceedMaxLines, isFalse,
          reason: '${entry.kind.id} 不允许 ellipsis 截断');
      expect(boxes, isNotEmpty, reason: '${entry.kind.id} 正文必须真被绘制');
      final List<TextBox> lastBoxes = body.getBoxesForSelection(
        TextSelection(baseOffset: plain.length - 1, extentOffset: plain.length),
      );
      final double bodyRight =
          tester.getRect(_bodyFinder()).left + lastBoxes.last.right;
      final RenderParagraph valuePara = tester.renderObject<RenderParagraph>(
          find.byKey(GuardBuffChip.valueKey));
      final List<TextBox> valueBoxes = valuePara.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      final double valueLeft =
          tester.getRect(find.byKey(GuardBuffChip.valueKey)).left +
          valueBoxes.first.left;
      expect(valueLeft - bodyRight, greaterThanOrEqualTo(1.99),
          reason: '🔴 ${entry.kind.id} 正文末字与数值间距必须 ≥2px');
      expectPainted(tester, entry.word);
      expectValuePainted(tester, entry.value);
      if (entry.remaining.isEmpty) {
        expect(find.byKey(const Key('guardBuffChipRemaining')), findsNothing);
      } else {
        expectRemainingPainted(tester, entry.remaining);
      }
      expect(tester.takeException(), isNull, reason: '${entry.kind.id} overflow');
    }
  });
}
