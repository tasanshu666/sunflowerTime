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
  final Text text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(GuardBuffChip.chipKey),
      matching: find.byType(Text),
    ),
  );
  final InlineSpan? span = text.textSpan;
  expect(span, isNotNull, reason: 'B13.9 横排文字必须是 Text.rich（带 ☀ 内联图）');
  return span! as TextSpan;
}

/// 横排文字的纯文本（WidgetSpan 占位符 \uFFFC 不计入断言）。
String _plainTextOf(WidgetTester tester) =>
    _spanOf(tester).toPlainText().replaceAll('\uFFFC', '');

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
                  'assets/fx/focus/sunflower/idle/frame001.png'),
        ),
        findsOneWidget,
        reason: '${kind.id} 图标 = 专注页向日葵待机首帧（双券同款）',
      );
      expect(_plainTextOf(tester), contains('今日专注'),
          reason: '${kind.id} 文案保持简洁口径');
      expect(tester.takeException(), isNull, reason: '${kind.id} overflow');
    }
  });
}
