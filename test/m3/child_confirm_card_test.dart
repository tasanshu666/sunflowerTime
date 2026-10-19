/// F135 统一确认卡 `ChildConfirmCard` 单测（玄参 2026-10-19 iPad Pro 13″ 实测：
/// 「这三张卡片太宽了，变窄一些」+「四张确认卡样式不统一」）。
///
/// 覆盖 6 件事：
///  ① **手机宽度**：`340 × uiScale(1.0)` 上界，且顶满 `Dialog` 可用宽（390−64=326）；
///  ② **平板宽度**：iPad 13″（1032 → 倍率 1.6）上限 544，**远窄于改前的 968**
///     （这是本轮用户诉求的量化落点，去掉 `maxWidth` 约束必红）；
///  ③ **不溢出**：320×568 + 1.3 倍字号（F126/F127 老坑位）下零 exception；
///  ④ **红档**：破坏性操作的确认按钮底色是红、文字是白（与金档可区分）；
///  ⑤ **返回语义**：确认 → `true`；取消 → `false`（调用方 `ok != true` 即不扣费）；
///  ⑥ **内容槽位**：title / warning / rows / note 逐条渲染（改版不得吞掉任一句）。
library child_confirm_card_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';

/// 一张「内容最满」的卡（标题 + 后果说明 + 2 行明细 + 小结 + 按钮），
/// 用来做宽度与溢出断言 —— 取最坏情况才不会被某一行侥幸撑过去。
ChildConfirmCard _card({
  ConfirmCardTone tone = ConfirmCardTone.gold,
  String confirmLabel = '确定，扣除',
}) {
  return ChildConfirmCard(
    title: '要给花园腾一个花盆吗？',
    hero: const ConfirmCardBadge(icon: Icons.yard),
    warning: '铲除后这株植物会消失。',
    rows: const <ConfirmCardRow>[
      ConfirmCardRow(icon: Icons.wb_sunny, name: '本次扩容', value: '−160 ☀'),
      ConfirmCardRow(
        icon: Icons.account_balance_wallet_outlined,
        name: '当前阳光',
        value: '1042 ☀',
        muted: true,
      ),
    ],
    note: '花园容量：4 盆 → 5 盆',
    confirmLabel: confirmLabel,
    confirmTone: tone,
  );
}

/// 直接挂一张卡（不走路由）：`Dialog` 自带 center 对齐，可单独渲染。
Future<void> _pumpCard(
  WidgetTester tester, {
  required Size logicalSize,
  Widget? card,
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
    MaterialApp(home: Scaffold(body: card ?? _card())),
  );
  await tester.pump();
}

/// 卡壳（奶油底 Container）的真实渲染宽度。
double _cardWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(ChildConfirmCard.surfaceKey)).width;

/// 宿主：点「open」→ 走 `showChildConfirmCard` → 把返回值写进 [captured]。
///
/// 必须走真实弹窗路径才能验证「取消 / 确认」的 Future 返回值契约
/// （调用方一律 `if (ok != true) return;`）。
class _Host {
  bool? captured;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showChildConfirmCard(
                    context: context,
                    title: '要给花园腾一个花盆吗？',
                    hero: const ConfirmCardBadge(icon: Icons.yard),
                    rows: const <ConfirmCardRow>[
                      ConfirmCardRow(
                        icon: Icons.wb_sunny,
                        name: '本次扩容',
                        value: '−160 ☀',
                      ),
                    ],
                    note: '花园容量：4 盆 → 5 盆',
                    confirmLabel: '确定，扣除',
                  );
                },
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
}

void main() {
  testWidgets('① 手机 390：宽度顶满可用宽 326，且不超过 340 上界',
      (WidgetTester tester) async {
    await _pumpCard(tester, logicalSize: const Size(390, 844));

    final double width = _cardWidth(tester);
    expect(width, lessThanOrEqualTo(ChildConfirmStyle.maxWidth + 0.01),
        reason: '手机卡宽不得超过 340（320 小屏取下界、390 取可用宽）');
    expect(width, closeTo(326.0, 0.5),
        reason: '390 − insetPadding 32×2 = 326，卡片应顶满可用宽（与改前视觉一致）');
  });

  testWidgets('② iPad 13″（1032 → 倍率 1.6，文字也 1.6）：宽度收敛到 544，远窄于改前的 968',
      (WidgetTester tester) async {
    // ⚠️ 口径必须与生产一致：`app.dart` 在平板上走的
    // `applyTabletTextScaling` 会把 textScaler 一并放大到 1.6
    // （= `TextScaler.linear(1.6)`），**不只是**图形乘 uiScale。
    // 只设 1.0 会低估文字占宽、掩盖横向溢出（QA 复核指出的口径瑕疵）。
    await _pumpCard(
      tester,
      logicalSize: const Size(1032, 1376),
      textScale: 1.6,
    );

    final double width = _cardWidth(tester);
    expect(width, closeTo(ChildConfirmStyle.maxWidth * 1.6, 0.5),
        reason: '340 × 1.6 = 544（宽度由 maxWidth 约束决定，与字号无关）');
    expect(width, lessThan(968.0),
        reason: '🔴 改前平板宽 = 1032 − 64 = 968（玄参：「太宽了」）；'
            '去掉 maxWidth 约束本断言必红');
    expect(tester.takeException(), isNull,
        reason: '平板「图形 ×1.6 + 文字 ×1.6」双口径下必须零 overflow'
            '（限高 0.7 + 卡内滚动兜底）');
  });

  testWidgets('③ 320×568 + 1.3 倍字号：零 overflow（F126/F127 老坑位）',
      (WidgetTester tester) async {
    await _pumpCard(
      tester,
      logicalSize: const Size(320, 568),
      textScale: 1.3,
    );

    expect(find.byKey(ChildConfirmCard.surfaceKey), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '「320 小屏 + 1.3 倍字号 + 满内容」必须零溢出（限高 + 卡内滚动兜底）');
  });

  testWidgets('④ 红档：确认按钮红底白字（破坏性操作与金档可区分）',
      (WidgetTester tester) async {
    await _pumpCard(
      tester,
      logicalSize: const Size(390, 844),
      card: _card(tone: ConfirmCardTone.danger, confirmLabel: '确定铲除'),
    );

    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确定铲除'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      ChildConfirmStyle.danger,
      reason: '红档底色必须是警示红 0xFFE5544B',
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
      reason: '红底上必须白字（对比度）',
    );

    // 金档对照：同一位置是阳光金（证明 tone 真的生效，不是恒红）。
    await _pumpCard(tester, logicalSize: const Size(390, 844));
    final FilledButton gold = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确定，扣除'),
    );
    expect(
      gold.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFFF6C445),
      reason: '金档底色 = 阳光金（GoldNoticeStyle.gold）',
    );
  });

  testWidgets('⑤ 返回语义：确认 → true；取消 → false', (WidgetTester tester) async {
    final _Host confirm = _Host();
    await confirm.open(tester);
    await tester.tap(find.text('确定，扣除'));
    await tester.pumpAndSettle();
    expect(confirm.captured, isTrue, reason: '确认 → 调用方才允许扣费');
    expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing,
        reason: '点完必须关卡');

    final _Host cancel = _Host();
    await cancel.open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cancel.captured, isFalse, reason: '取消 → 分毫不扣（领域层未触达）');
    expect(find.byKey(ChildConfirmCard.surfaceKey), findsNothing);
  });

  testWidgets('⑥ 槽位齐全：标题 / 后果说明 / 明细两行 / 小结 / 按钮都在',
      (WidgetTester tester) async {
    await _pumpCard(tester, logicalSize: const Size(390, 844));

    expect(find.text('要给花园腾一个花盆吗？'), findsOneWidget);
    expect(find.text('铲除后这株植物会消失。'), findsOneWidget);
    expect(find.text('本次扩容'), findsOneWidget);
    expect(find.text('−160 ☀'), findsOneWidget);
    expect(find.text('当前阳光'), findsOneWidget);
    expect(find.text('1042 ☀'), findsOneWidget);
    expect(find.text('花园容量：4 盆 → 5 盆'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定，扣除'), findsOneWidget);
  });
}
