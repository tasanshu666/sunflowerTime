/// 树上三态**渲染**断言（v0.3.0 / R3-P0-05、R3-P0-10④）。
///
/// 与 `wish_face_state_test.dart` 分工：那个测**判据纯函数**，本文件测
/// **判据落到 UI 上的元素集合**（S1/S2 必须 `findsNothing` 徽标 / 进度条 /
/// 「等爸爸妈妈设定目标」，S3 必须有「小办法」标题 + 计数 + 进度）。
library wish_face_render_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card_detail.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';

final AppLocalizations _t = AppLocalizationsZh();

Wish _wish({
  String? tagKey,
  String? parentReply,
  int targetValue = 0,
  int progressValue = 0,
}) =>
    Wish(
      id: 'w1',
      childId: 'c1',
      text: '想要一只小乌龟',
      status: WishStatus.pending,
      createdAt: DateTime(2026, 11, 10),
      tagKey: tagKey,
      parentReply: parentReply,
      targetValue: targetValue,
      progressValue: progressValue,
    );

Widget _hostCard(Wish wish, WishTreeFace face, {int wayCount = 0, int waitDays = 2}) =>
    MaterialApp(
      home: Scaffold(
        body: WishCard(
          wish: wish,
          t: _t,
          face: face,
          taskCount: wayCount,
          waitDays: waitDays,
        ),
      ),
    );

Widget _hostDetail(Wish wish, WishTreeFace face, {int wayCount = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: WishCardDetail(
          wish: wish,
          t: _t,
          face: face,
          taskCount: wayCount,
          waitDays: 2,
          confirmTitle: _t.wishTreeSelfFulfillConfirm,
          confirmMessage: _t.wishSelfFulfillConfirm,
          confirmLabel: _t.wishSelfFulfill,
          cancelLabel: _t.shared_cancel,
        ),
      ),
    );

void main() {
  group('S1 刚挂上（家长未回应）', () {
    testWidgets('卡片：只显原文/日期/等待天数/**不可点击**轻提示；徽标·果实阶段·进度条全无',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostCard(_wish(), WishTreeFace.hanging));

      expect(find.byKey(const Key('wish_card_text')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_created_date')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_wait_days')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsOneWidget);
      expect(find.text(_t.wishStateHangingHint), findsOneWidget);

      // 🔴 R3-P0-05②：三者一律不得出现。
      expect(find.byKey(const Key('wish_card_task_badge')), findsNothing);
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsNothing);
      expect(find.byType(WishProgressBar), findsNothing);
      expect(find.text(_t.wishNoTargetYet), findsNothing,
          reason: '「等爸爸妈妈设定目标」必须消失');
      expect(find.text(_t.wishFruitWaiting), findsNothing);
      // 分类 emoji 已下线（R3-P0-03③）：6 个分类符号一个都不许出现。
      for (final String emoji in <String>['🌱', '🎁', '🎈', '🧸', '🌟', '💛']) {
        expect(find.text(emoji), findsNothing, reason: '分类 emoji $emoji 已下线');
      }
    });

    testWidgets('轻提示**不可点击**：不是按钮，也没有比卡片本身更多的可点层',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostCard(_wish(), WishTreeFace.hanging));
      final Finder hint = find.byKey(const Key('wish_card_hanging_hint'));
      final Finder cardText = find.byKey(const Key('wish_card_text'));

      // ① 提示本身是纯 Text（不是按钮 widget）。
      expect(tester.widget(hint), isA<Text>());
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);

      // ② 提示的可点祖先数 == 原文的可点祖先数 ⇒ 提示没有「额外的」可点层。
      //    （卡片本体那个 InkWell 用于打开详情，与提示是否可点无关。）
      final int hintTappables = find
          .ancestor(of: hint, matching: find.byType(InkWell))
          .evaluate()
          .length;
      final int textTappables = find
          .ancestor(of: cardText, matching: find.byType(InkWell))
          .evaluate()
          .length;
      expect(hintTappables, textTappables,
          reason: 'S1 提示必须是**非按钮式**纯文本（R3-P0-07⑤）');
    });

    testWidgets('满 7 天后提示自动隐藏（R3-P2-01），且无替代催促文案',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _hostCard(_wish(), WishTreeFace.hanging, waitDays: 7),
      );
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsNothing);
      expect(find.text(_t.wishStateHangingHint), findsNothing);
      // 不得换成别的催促（如 stale hint 之外的「还没人理你」类文案）。
      expect(find.text(_t.wishStateParentWorking), findsNothing);
    });

    testWidgets('详情卡 S1：无果实阶段 / 无进度条 / 不显示「还没回信」区',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostDetail(_wish(), WishTreeFace.hanging));
      expect(find.byKey(const Key('wish_detail_hanging_hint')), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_fruit_stage')), findsNothing);
      expect(find.byType(WishProgressBar), findsNothing);
      expect(find.byKey(const Key('wish_detail_back')), findsNothing,
          reason: 'S1 不显示回信区（避免「爸爸妈妈还没回信」的变相催促）');
    });
  });

  group('S2 家长已回应（正在想办法 / 暂时做不到）', () {
    testWidgets('卡片：显示家长回信原文；无徽标 / 果实阶段 / 进度条',
        (WidgetTester tester) async {
      const String reply = '这个愿望有点难，不过爸爸妈妈记在心里了';
      await tester.pumpWidget(_hostCard(
        _wish(tagKey: 'not_possible', parentReply: reply),
        WishTreeFace.parentResponded,
      ));

      expect(find.text(reply), findsOneWidget);
      expect(find.byKey(const Key('wish_card_parent_reply')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_task_badge')), findsNothing);
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsNothing);
      expect(find.byType(WishProgressBar), findsNothing);
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsNothing,
          reason: 'S1 提示不得出现在 S2');
    });

    testWidgets('回信为空 ⇒ 显示兜底句「爸爸妈妈正在帮你想办法…」',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostCard(
        _wish(tagKey: 'parents_working'),
        WishTreeFace.parentResponded,
      ));
      expect(find.text(_t.wishStateParentWorking), findsOneWidget);
    });

    testWidgets('兜底句与家长回信**互斥**（不可同时出现两段）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostCard(
        _wish(tagKey: 'over_budget', parentReply: '下个月再看看'),
        WishTreeFace.parentResponded,
      ));
      expect(find.text('下个月再看看'), findsOneWidget);
      expect(find.text(_t.wishStateParentWorking), findsNothing);
    });

    testWidgets('详情卡 S2：显示回信区、无进度条', (WidgetTester tester) async {
      await tester.pumpWidget(_hostDetail(
        _wish(tagKey: 'not_possible', parentReply: '记在心里了'),
        WishTreeFace.parentResponded,
      ));
      expect(find.byKey(const Key('wish_detail_back')), findsOneWidget);
      expect(find.text('记在心里了'), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_fruit_stage')), findsNothing);
      expect(find.byType(WishProgressBar), findsNothing);
    });
  });

  group('S3 家长给了小办法', () {
    testWidgets('卡片：显示「小办法 n 个」+ S3 标题 + 果实阶段 + 进度条',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostCard(
        _wish(targetValue: 30, progressValue: 10),
        WishTreeFace.hasWays,
        wayCount: 2,
      ));

      expect(find.byKey(const Key('wish_card_task_badge')), findsOneWidget);
      expect(find.text(_t.wishWayCountBadge(2)), findsOneWidget);
      expect(find.byKey(const Key('wish_card_way_title')), findsOneWidget);
      expect(find.text(_t.wishWayTitle), findsOneWidget);
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsOneWidget);
      expect(find.byType(WishProgressBar), findsOneWidget);
      // 孩子端文案不含「任务」二字（D2）。
      expect(find.textContaining('任务'), findsNothing);
    });

    testWidgets('详情卡 S3：「小办法」标题 + 计数 + 进度条',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostDetail(
        _wish(targetValue: 30, progressValue: 30),
        WishTreeFace.hasWays,
        wayCount: 3,
      ));
      expect(find.byKey(const Key('wish_detail_way_title')), findsOneWidget);
      expect(find.text(_t.wishWayCountBadge(3)), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_fruit_stage')), findsOneWidget);
      expect(find.byType(WishProgressBar), findsOneWidget);
      expect(find.textContaining('任务'), findsNothing);
    });
  });

  group('三态元素集合无交叉错用', () {
    testWidgets('S1 ⟂ S3：同一数据在两种 face 下元素集合互不重叠',
        (WidgetTester tester) async {
      final Wish w = _wish(targetValue: 30, progressValue: 5);
      await tester.pumpWidget(_hostCard(w, WishTreeFace.hanging));
      expect(find.byType(WishProgressBar), findsNothing);
      expect(find.byKey(const Key('wish_card_way_title')), findsNothing);

      await tester.pumpWidget(
        _hostCard(w, WishTreeFace.hasWays, wayCount: 1),
      );
      expect(find.byType(WishProgressBar), findsOneWidget);
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsNothing);
    });
  });
}
