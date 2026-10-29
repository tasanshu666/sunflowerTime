/// F162 统一确认卡「长取值」布局守卫（玄参 2026-10-29 英文商店实测截图：
/// 「确认兑换」卡右侧 `RIGHT OVERFLOWED BY 22 PIXELS`，左侧 `Item` 被压成
/// 单字竖排 `I t e m`）。
///
/// ## 根因（两层叠在同一行里，缺一不可）
/// `_RowLine` 原本是 `[图标][8][Expanded(名称)][8][裸 Text(取值)]`：
///  · 取值**无任何约束**，按内容一路撑宽 —— 中文取值是金额 `−100 ☀`（≈60pt）
///    所以从没暴露；英文商店这一行取值是**奖励名** `「Watch one cartoon episode」`
///    （≈240pt），直接把整行顶出面板右边界；
///  · 名称是唯一的 `Expanded`，被挤到 ≈12pt —— 英文只能逐字母折行（中文名
///    「兑换物品」6 字也被压成竖排，只是这次没截到）。
///
/// 修法：两列**都** `Expanded`（`FlexFit.tight`），按 2:3 分配，取值右对齐。
/// 用 tight 而非 loose 的原因见 `child_confirm_card.dart` 里 `_kNameFlex` 注释
/// （loose 下短取值会缩到内容宽，金额就贴不住卡边）。
///
/// ## 本文件钉死四件事
///  ① 英文长取值（最坏情况）在手机 390 上**零 overflow**，名称不再被压成竖排；
///  ② 取值**右对齐贴住面板右内边**（改前 `−100 ☀` 的视觉，不能因为改布局漂走）；
///  ③ 中文短取值**仍是单行**（长取值才折行，短金额不许无故变高）；
///  ④ iPad 13″（图形 ×1.6 + 文字 ×1.6 双口径）同样零 overflow。
///
/// ⚠️ 断言不写死"折几行"：测试字体是等宽方块（每字符 = fontSize 宽），
/// 与真机字形宽度不同，钉行数会得到假红/假绿。
library f162_confirm_card_long_value_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';

/// 英文商店里最长的那条预制奖励名（真机截图原文），带中文书名号包裹。
const String _kLongValue = '「Watch one cartoon episode」';

/// 中文商店的典型取值（金额 + 短奖励名），用于对照「短取值不该折行」。
const String _kShortValue = '「小零食」';

/// 卡内容边距（与 `ChildConfirmCard.build` 的 `padding: fromLTRB(20*s, …)`
/// 及 `_buildPanel` 的 `horizontal: 14*s` 同源）—— 断言"贴右内边"要扣这两层。
const double _kCardPadX = 20;
const double _kPanelPadX = 14;

/// 明细行左侧图标宽度 + 两侧 8pt 间距（`_RowLine` 内的固定开销）。
const double _kIconAndGaps = 18 + 8 + 8;

/// 一张与英文商店「确认兑换」卡同构的卡：1 行长取值 + 2 行短金额。
ChildConfirmCard _card(String itemValue) {
  return ChildConfirmCard(
    title: 'Confirm redemption?',
    hero: const ConfirmCardBadge(icon: Icons.redeem),
    rows: <ConfirmCardRow>[
      ConfirmCardRow(
        icon: Icons.card_giftcard,
        name: 'Item',
        value: itemValue,
      ),
      const ConfirmCardRow(icon: Icons.wb_sunny, name: 'Cost', value: '−100 ☀'),
      const ConfirmCardRow(
        icon: Icons.account_balance_wallet,
        name: 'Available',
        value: '501 ☀',
        muted: true,
      ),
    ],
    warning: 'A parent must approve before sunlight is deducted.',
    confirmLabel: 'Confirm',
    // 显式传，绕开 `l10nOf` 对页级 L10nScope 的依赖（本用例只测排版）。
    cancelLabel: 'Let me think',
  );
}

/// 走**真实弹窗入口**（`showChildConfirmCard`）：只有经 `Dialog` 才有
/// `insetPadding: 32`，手机卡宽才是 326 —— 直接挂卡是 340，会低估挤压程度。
Future<void> _openCard(
  WidgetTester tester, {
  required Size logicalSize,
  required String itemValue,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(
    logicalSize.width * 3,
    logicalSize.height * 3,
  );
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showChildConfirmCard(
                context: context,
                title: 'Confirm redemption?',
                hero: const ConfirmCardBadge(icon: Icons.redeem),
                rows: _card(itemValue).rows,
                warning: 'A parent must approve before sunlight is deducted.',
                confirmLabel: 'Confirm',
                cancelLabel: 'Let me think',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 卡壳（奶油底 Container）的真实矩形。
Rect _cardRect(WidgetTester tester) =>
    tester.getRect(find.byKey(ChildConfirmCard.surfaceKey));

void main() {
  testWidgets('① 英文长取值 + 手机 390：零 overflow，名称不被压成竖排',
      (WidgetTester tester) async {
    await _openCard(
      tester,
      logicalSize: const Size(390, 844),
      itemValue: _kLongValue,
    );

    // 溢出在 paint 阶段经 FlutterError 上抛，takeException 能抓到
    // （改前此处即 `RIGHT OVERFLOWED BY … PIXELS`）。
    expect(tester.takeException(), isNull,
        reason: '英文长奖励名必须被折行收住，不许顶穿面板右边界');

    final Size nameSize = tester.getSize(find.text('Item'));
    expect(nameSize.width, greaterThanOrEqualTo(60.0),
        reason: '名称列被挤到 ${nameSize.width}pt 会逐字母竖排'
            '（真机改前实测 ≈12pt）；2:3 分配下应 ≈89.6pt');
    // 逐字母竖排的量化特征：宽度极窄 + 高度暴涨。
    expect(nameSize.height, lessThan(40.0),
        reason: '名称高度 ${nameSize.height}pt 说明「Item」被折成多行');
  });

  testWidgets('② 取值列右对齐，贴住面板右内边（金额视觉不许漂）',
      (WidgetTester tester) async {
    await _openCard(
      tester,
      logicalSize: const Size(390, 844),
      itemValue: _kLongValue,
    );

    final Rect card = _cardRect(tester);
    final double expectRight =
        card.right - (_kCardPadX + _kPanelPadX); // s = 1.0

    // 取值是 tight 盒，盒右边界即文本右边界（textAlign.right）。
    final Rect valueRect = tester.getRect(find.text(_kLongValue));
    expect(valueRect.right, closeTo(expectRight, 0.5),
        reason: '取值列必须顶到面板右内边（${expectRight}pt），'
            '实际 ${valueRect.right}pt —— 松约束会让它缩到内容宽、金额变「浮空」');

    // 数值行（短取值）也要贴右边，这是改前最直观的视觉锚点。
    final Rect costRect = tester.getRect(find.text('−100 ☀'));
    expect(costRect.right, closeTo(expectRight, 0.5),
        reason: '金额行同样要贴右内边');
    // 短取值不许被无谓折行（改前就是单行）。
    expect(costRect.height, lessThan(30.0),
        reason: '`−100 ☀` 只有 6 个字，不该折行');
  });

  testWidgets('③ 中文短取值：单行、贴右、零 overflow（手机零回归）',
      (WidgetTester tester) async {
    await _openCard(
      tester,
      logicalSize: const Size(390, 844),
      itemValue: _kShortValue,
    );

    expect(tester.takeException(), isNull);
    final Rect card = _cardRect(tester);
    final Rect valueRect = tester.getRect(find.text(_kShortValue));
    expect(valueRect.right, closeTo(card.right - (_kCardPadX + _kPanelPadX), 0.5));
    expect(valueRect.height, lessThan(30.0),
        reason: '「小零食」不足一行，短取值折行就是新引入的回归');
  });

  testWidgets('④ iPad 13″（图形 ×1.6 + 文字 ×1.6）：长取值同样零 overflow',
      (WidgetTester tester) async {
    // 口径与生产一致：`app.dart` 在平板上把 textScaler 一并放大到 1.6。
    await _openCard(
      tester,
      logicalSize: const Size(1032, 1376),
      itemValue: _kLongValue,
      textScale: 1.6,
    );

    expect(tester.takeException(), isNull,
        reason: '双口径放大下也必须零 overflow（限高 0.7 + 卡内滚动兜底）');

    // 平板 s = 1.6：名称列 ≈ (544 − 64 − 44.8 − 28.8 − 25.6) × 2/5。
    final Size nameSize = tester.getSize(find.text('Item'));
    expect(nameSize.width, greaterThanOrEqualTo(100.0),
        reason: '平板名称列应 ≈152pt，实测 ${nameSize.width}pt');

    final Rect card = _cardRect(tester);
    final Rect valueRect = tester.getRect(find.text(_kLongValue));
    expect(
      valueRect.right,
      closeTo(
        card.right - (_kCardPadX + _kPanelPadX) * 1.6,
        0.5,
      ),
    );
    // 明细行可用宽度的 60% 是取值列的上界（2:3 分配），防止有人调回 1:1 或去掉约束。
    final double rowContentWidth = card.width -
        (_kCardPadX + _kPanelPadX) * 2 * 1.6 -
        _kIconAndGaps * 1.6;
    expect(valueRect.width, lessThanOrEqualTo(rowContentWidth * 0.6 + 0.5),
        reason: '取值列不得超过行内可用宽的 60%（当前配比 3/5）');
  });
}
