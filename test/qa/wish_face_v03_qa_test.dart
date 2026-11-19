/// QA 独立差分复验 · v0.3 三态（S1/S2/S3）真实渲染 + 判据边界。
///
/// ## 为什么要「真渲染 + 纯函数穷举」双打
/// 工程师的 `test/m3/wish_face_render_test.dart` 与 `test/domain/wish_face_state_test.dart`
/// 是**同一批实现者**写的。本文件独立做三件他们最容易漏的事：
///  ① **空串边界**：`parentReply = ''` / `tagKey = ''`（DB 里真出现过空串写法的
///     历史数据）必须按 **D5 判为 S1**，不能被 `!= null` 误判成 S2；
///  ② **S3 抑制 S2**：`wayCount >= 1` 且家长也回了信 ⇒ 必须渲染 S3（有办法优先），
///     不允许变成「回信卡 + 小办法徽标」的混合态；
///  ③ **S1/S2 一律不出现「等爸爸妈妈设定目标」**（R3-P0-05②③）—— 这条只能靠
///     真实渲染断言，源码守卫抓不住「别处又渲染了」。
///
/// ## 反假绿纪律
/// 「S1 提示不可点击」不是断言源码里没有 `onTap`，而是断言**整张 S1 卡只有 1 个
/// 点击面**（卡级进详情那个），提示文本自身不新增任何热区。
library wish_face_v03_qa_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';

/// 造一条可完全掌控的愿望（默认 = S1 形态：pending + 未进箱 + 无回复 + 无标签）。
Wish _wish({
  String id = 'w1',
  String text = '想要一只小乌龟',
  WishStatus status = WishStatus.pending,
  String? tagKey,
  String? parentReply,
  DateTime? releasedAt,
  int targetValue = 0,
  int progressValue = 0,
  WishGoalMode targetMode = WishGoalMode.focusMinutes,
  DateTime? createdAt,
}) =>
    Wish(
      id: id,
      childId: 'child-1',
      text: text,
      status: status,
      createdAt: createdAt ?? DateTime(2026, 11, 1, 9),
      tagKey: tagKey,
      parentReply: parentReply,
      releasedAt: releasedAt,
      targetValue: targetValue,
      progressValue: progressValue,
      targetMode: targetMode,
      treeSlot: 0,
    );

/// 把 [WishCard] 挂到最小可渲染宿主（WishCard 是纯展示 widget，不读 provider）。
Future<void> _pumpCard(
  WidgetTester tester, {
  required Wish wish,
  required WishTreeFace face,
  required AppLocalizations t,
  int taskCount = 0,
  int waitDays = 3,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: WishCard(
          wish: wish,
          t: t,
          taskCount: taskCount,
          waitDays: waitDays,
          face: face,
          onTap: onTap,
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  final AppLocalizations zh = AppLocalizationsZh();

  group('② 三态判据 wishTreeFaceOf —— 边界穷举（D5 空串口径）', () {
    test('S1：pending + 未进箱 + 无标签 + 无回信 ⇒ hanging', () {
      expect(
        wishTreeFaceOf(wish: _wish(), wayCount: 0),
        WishTreeFace.hanging,
      );
    });

    test('🔴 D5 空串：parentReply = \'\' ⇒ 仍为 S1（不能被 != null 误判成 S2）', () {
      final Wish w = _wish(parentReply: '');
      expect(w.parentReply, isNotNull, reason: '前置：字段确实是 empty string 而非 null');
      expect(wishTreeFaceOf(wish: w, wayCount: 0), WishTreeFace.hanging,
          reason: '空串回信 = 家长"还没写"，视觉必须留在 S1');
    });

    test('🔴 D5 空串：tagKey = \'\' ⇒ 仍为 S1', () {
      final Wish w = _wish(tagKey: '');
      expect(w.tagKey, isNotNull);
      expect(wishTreeFaceOf(wish: w, wayCount: 0), WishTreeFace.hanging);
    });

    test('S2：非空 tagKey ⇒ parentResponded（旧字段 parentHasResponded 已删但语义保留）',
        () {
      final Wish w = _wish(tagKey: 'needMoreTime');
      expect(wishTreeFaceOf(wish: w, wayCount: 0),
          WishTreeFace.parentResponded);
    });

    test('S2：非空 parentReply ⇒ parentResponded', () {
      final Wish w = _wish(parentReply: '我们再想想办法');
      expect(wishTreeFaceOf(wish: w, wayCount: 0),
          WishTreeFace.parentResponded);
    });

    test('🔴 S3 抑制 S2：wayCount >= 1 且有家长回信 ⇒ 必须是 hasWays', () {
      final Wish w = _wish(
        tagKey: 'needMoreTime',
        parentReply: '我们一起努力',
        targetValue: 30,
        progressValue: 10,
      );
      expect(wishTreeFaceOf(wish: w, wayCount: 1), WishTreeFace.hasWays,
          reason: '「有办法」优先级最高：不能让 S2 的回信卡盖掉小办法列表');
      expect(wishTreeFaceOf(wish: w, wayCount: 3), WishTreeFace.hasWays);
    });

    test('🔴 releasedAt != null 不算 S1（进收藏箱的愿望不在树上等家长）', () {
      final Wish w = _wish(releasedAt: DateTime(2026, 11, 5, 10));
      expect(wishTreeFaceOf(wish: w, wayCount: 0),
          isNot(WishTreeFace.hanging),
          reason: '进箱后即便无回复也不能判 S1（S1 的"等待中"语义不成立）');
      expect(wishTreeFaceOf(wish: w, wayCount: 0),
          WishTreeFace.parentResponded);
    });

    test('非 pending 状态不算 S1（边界兜底走 S2，不露出"等家长设定目标"）', () {
      for (final WishStatus s in <WishStatus>[
        WishStatus.fulfilled,
        WishStatus.abandoned,
        WishStatus.replaced,
      ]) {
        expect(wishTreeFaceOf(wish: _wish(status: s), wayCount: 0),
            isNot(WishTreeFace.hanging),
            reason: '$s 不在树上等待 ⇒ 不得判 S1');
      }
    });

    test('wayCount = 0 是 S1/S2 的分界；1 是 S3 的起点（边界值逐个探）', () {
      final Wish bare = _wish();
      expect(wishTreeFaceOf(wish: bare, wayCount: 0), WishTreeFace.hanging);
      expect(wishTreeFaceOf(wish: bare, wayCount: 1), WishTreeFace.hasWays,
          reason: '1 条小办法即进入 S3（PRD「有办法」定义 = >= 1）');
    });

    test('三态枚举恰 3 个值（回退不得遗留第 4 态）', () {
      expect(WishTreeFace.values.length, 3);
      expect(WishTreeFace.values.toSet(), <WishTreeFace>{
        WishTreeFace.hanging,
        WishTreeFace.parentResponded,
        WishTreeFace.hasWays,
      });
    });
  });

  group('③ S1 真实渲染（不是源码守卫）', () {
    testWidgets('S1 卡：无小办法徽标 / 无进度条 / 无「等爸爸妈妈设定目标」/ 有轻提示',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(),
        face: WishTreeFace.hanging,
        t: zh,
      );

      // 原文 + 日期 + 等待天数：三态共有，必须在。
      expect(find.byKey(const Key('wish_card_text')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_created_date')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_wait_days')), findsOneWidget);

      // S1 专属：一条轻提示。
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsOneWidget);
      expect(find.text(zh.wishStateHangingHint), findsOneWidget);

      // 🔴 明确不显示（R3-P0-05②③ / D5）。
      expect(find.byKey(const Key('wish_card_task_badge')), findsNothing,
          reason: 'S1 不得显示「小办法 N 个」徽标');
      expect(find.byKey(const Key('wish_card_way_title')), findsNothing,
          reason: 'S1 不得显示 S3 标题');
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsNothing,
          reason: 'S1 不得显示果实阶段');
      expect(find.byType(WishProgressBar), findsNothing,
          reason: 'S1 不得显示进度条');
      expect(find.text(zh.wishNoTargetYet), findsNothing,
          reason: '🔴 玄参明确不要「等爸爸妈妈设定目标」');
      expect(find.byKey(const Key('wish_card_parent_reply_box')), findsNothing,
          reason: 'S1 = 家长还没回应，不得有回信区');
    });

    testWidgets('S1 轻提示不可点击：整张卡只有 1 个点击面（卡级进详情）',
        (WidgetTester tester) async {
      int cardTaps = 0;
      await _pumpCard(
        tester,
        wish: _wish(),
        face: WishTreeFace.hanging,
        t: zh,
        onTap: () => cardTaps++,
      );

      // 卡级点击面恰 1 个（多一个就说明提示被做成了可点按钮）。
      //
      // ⚠️ 不能断言 `find.byType(GestureDetector) findsNothing`：外层的
      // `SingleChildScrollView` 自带一个滚动 GestureDetector（startBehavior:
      // start + dependencies 含 ScrollConfiguration），那是宿主不是卡内容。
      expect(find.byType(InkWell), findsOneWidget,
          reason: 'S1 卡只能有卡级那一个 InkWell；提示不得自带热区');
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      // 提示必须是"裸 Text"：不是 InkWell / 不是按钮，自身无手势装配。
      final Finder hint = find.byKey(const Key('wish_card_hanging_hint'));
      expect(
        find.ancestor(of: hint, matching: find.byType(InkWell)),
        findsOneWidget,
        reason: '提示之上只应存在卡级那 1 个 InkWell（中间不得再夹一层）',
      );

      // 行为侧：点提示文本 ⇒ 走的是卡级 onTap（等价"点了整张卡"），
      // 不存在"提示专属动作"这类第二行为。
      await tester.tap(find.byKey(const Key('wish_card_hanging_hint')));
      await tester.pump();
      expect(cardTaps, 1, reason: '点提示等同点卡（进详情），无第二行为');
    });

    testWidgets('S1 满 kWishStateHintDays 天后轻提示自动隐藏（P2-01）',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(),
        face: WishTreeFace.hanging,
        t: zh,
        waitDays: kWishStateHintDays,
      );
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsNothing,
          reason: '挂树满 $kWishStateHintDays 天后提示自动隐藏，且不得出现催促替代文案');
      // 不得出现"变相催促"的替身文案。
      expect(find.text(zh.wishStateHangingHint), findsNothing);
    });
  });

  group('③ S2 真实渲染', () {
    testWidgets('S2 卡：显示家长回信；无徽标 / 无果实阶段 / 无进度条 / 无 S1 提示',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(tagKey: 'needMoreTime', parentReply: '我们再想想办法'),
        face: WishTreeFace.parentResponded,
        t: zh,
      );

      expect(find.byKey(const Key('wish_card_parent_reply_box')), findsOneWidget);
      expect(find.text('我们再想想办法'), findsOneWidget);

      expect(find.byKey(const Key('wish_card_task_badge')), findsNothing);
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsNothing);
      expect(find.byType(WishProgressBar), findsNothing);
      expect(find.text(zh.wishNoTargetYet), findsNothing,
          reason: 'S2 同样不得出现「等爸爸妈妈设定目标」');
      expect(find.byKey(const Key('wish_card_hanging_hint')), findsNothing,
          reason: 'S2 不是 S1，不得再显示"等家长看看"的轻提示');
    });

    testWidgets('S2 空回信兜底句（家长只贴了标签没写信）',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(tagKey: 'overBudget'),
        face: WishTreeFace.parentResponded,
        t: zh,
      );
      expect(find.byKey(const Key('wish_card_parent_reply_box')), findsOneWidget,
          reason: '只贴标签也算家长回应 ⇒ 必须渲染回信区（用兜底句）');
      expect(find.text(zh.wishStateParentWorking), findsOneWidget);
    });
  });

  group('③ S3 真实渲染', () {
    testWidgets('S3 卡：「小办法 N 个」徽标 + S3 标题 + 进度条，且无「任务」字样',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(targetValue: 60, progressValue: 20),
        face: WishTreeFace.hasWays,
        t: zh,
        taskCount: 3,
      );

      expect(find.byKey(const Key('wish_card_task_badge')), findsOneWidget);
      expect(find.text(zh.wishWayCountBadge(3)), findsOneWidget);
      expect(find.byKey(const Key('wish_card_way_title')), findsOneWidget);
      expect(find.text(zh.wishWayTitle), findsOneWidget);
      expect(find.byKey(const Key('wish_card_fruit_stage')), findsOneWidget);
      expect(find.byType(WishProgressBar), findsOneWidget);

      // 孩子端一律「小办法」，绝不出现「任务」二字（D2）。
      final Iterable<Text> texts =
          tester.widgetList<Text>(find.byType(Text));
      for (final Text txt in texts) {
        final String data = txt.data ?? '';
        expect(data.contains('任务'), isFalse,
            reason: '孩子端 S3 文案出现「任务」二字：「$data」');
      }
      expect(zh.wishWayCountBadge(3).contains('小办法'), isTrue,
          reason: '前置自证：徽标文案确实是「小办法」');
    });

    testWidgets('S3 与 S2 同时成立时只渲染 S3（回信区不出现）', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        wish: _wish(tagKey: 'needMoreTime', parentReply: '我们一起努力'),
        face: WishTreeFace.hasWays,
        t: zh,
        taskCount: 2,
      );
      expect(find.byKey(const Key('wish_card_task_badge')), findsOneWidget);
      expect(find.byKey(const Key('wish_card_parent_reply_box')), findsNothing,
          reason: 'S3 抑制 S2 ⇒ 不得同时出现两张主体区（会撑爆卡高、语义冲突）');
    });

    testWidgets('S3 英文端：无 CJK 且同样是「Way」而不是「Task」', (WidgetTester tester) async {
      final AppLocalizations en = AppLocalizationsEn();
      await _pumpCard(
        tester,
        wish: _wish(),
        face: WishTreeFace.hasWays,
        t: en,
        taskCount: 2,
      );
      final RegExp cjk = RegExp(r'[\u4E00-\u9FFF]');
      for (final Text txt in tester.widgetList<Text>(find.byType(Text))) {
        final String data = txt.data ?? '';
        // 愿望原文是**用户数据**（本例故意用中文原文），不属于应用文案 ⇒ 跳过。
        if (txt.key == const Key('wish_card_text')) continue;
        expect(cjk.hasMatch(data), isFalse, reason: 'en 渲染出现中文：「$data」');
        expect(data.toLowerCase().contains('task'), isFalse,
            reason: '孩子端英文也不叫 Task：「$data」');
      }
      // 反向自证：en 确实取到了英文文案（否则上面"无 CJK / 无 Task"可能是空断言）。
      expect(en.wishWayCountBadge(2).toLowerCase().contains('ways'), isTrue,
          reason: '前置自证：en 徽标文案用的是 "little ways" 而不是 Task');
      expect(find.text(en.wishWayCountBadge(2)), findsOneWidget);
    });
  });

  group('③ 孩子端文案纪律（ARB 值级别，非源码）', () {
    test('孩子端许愿树用到的全部文案零「任务」', () {
      // 这些 key 是 wish_card / wish_card_detail / wish_tree_page / wish_compose 用的，
      // 逐个人工核对过归属（家长端 key 见下一条）。
      final Map<String, String> childCopy = <String, String>{
        'wishTreeTitle': zh.wishTreeTitle,
        'wishTreeStart': zh.wishTreeStart,
        'wishTreeHanging': zh.wishTreeHanging(1, 3),
        'wishTreeTabTree': zh.wishTreeTabTree,
        'wishTreeTabBox': zh.wishTreeTabBox(2),
        'wishTreeTabPool': zh.wishTreeTabPool(1),
        'wishWayCountBadge': zh.wishWayCountBadge(2),
        'wishWayTitle': zh.wishWayTitle,
        'wishWayLabel': zh.wishWayLabel,
        'wishStateHangingHint': zh.wishStateHangingHint,
        'wishStateParentWorking': zh.wishStateParentWorking,
        'wishTaskGoFocus': zh.wishTaskGoFocus,
        'wishTaskDidIt': zh.wishTaskDidIt,
        'wishTaskDone': zh.wishTaskDone,
        'wishTaskPending': zh.wishTaskPending,
        'wishComposeTitle': zh.wishComposeTitle,
        'wishComposeHint': zh.wishComposeHint,
        'wishComposeSubmit': zh.wishComposeSubmit,
        'wishComposeTooLong': zh.wishComposeTooLong,
        'wishComposeSaveFailed': zh.wishComposeSaveFailed,
      };
      final List<String> offenders = <String>[
        for (final MapEntry<String, String> e in childCopy.entries)
          if (e.value.contains('任务')) '${e.key} = ${e.value}',
      ];
      expect(offenders, isEmpty, reason: '孩子端出现「任务」：$offenders');
    });

    test('家长端仍叫「愿望任务 · 标题」（家长视角需要"任务"这个词）', () {
      expect(zh.wishTaskBadgeLabel, '愿望任务');
      expect(zh.wishTaskBadgeOfWish('想要一只小乌龟'), '愿望任务 · 想要一只小乌龟');
      expect(zh.wishTaskBadgeOfWish('想要一只小乌龟').contains('任务'), isTrue,
          reason: '前置自证：家长端确实保留「任务」口径（不能一刀切改掉）');
    });
  });
}
