/// A-T05 家长端 ParentWishActionSheet 断言 ⑭~⑯（A21.4 / A24 / V15）。
///
/// 标签 6 选 1 / 预设回复按标签过滤重排（推荐词首位）/ 时机 5 选 1 不可自由输入 /
/// 回信为空允许提交 / 文案走 ARB。期望值写死独立量。
library wish_action_sheet_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/wish_l10n.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/parent/widgets/parent_wish_action_sheet.dart';

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('⑭ 标签 / 回复 / 时机 L10n 出口逐字', () {
    test('6 个标签中文逐字（PRD W19.1）', () {
      expect(wishTagText(WishTag.needMoreTime, zh), '需要更多时间');
      expect(wishTagText(WishTag.overBudget, zh), '超出预算');
      expect(wishTagText(WishTag.notPossible, zh), '现实里做不到');
      expect(wishTagText(WishTag.smallerWish, zh), '换一个更小的愿望');
      expect(wishTagText(WishTag.waitForMoment, zh), '等一个特别的时机');
      expect(wishTagText(WishTag.parentsWorkingOnIt, zh), '爸爸妈妈也在想办法');
    });

    test('8 条预设回复中文逐字（PRD W19.2 定稿）', () {
      expect(wishReplyPresetText(WishReplyPreset.hardButLove, zh),
          '这个愿望有点难做到，不过爸爸妈妈记在心里了，我们一起想想别的办法，好吗？');
      expect(wishReplyPresetText(WishReplyPreset.dinosaur, zh),
          '养恐龙这件事爸爸妈妈真的做不到，但你想要的那种勇敢，我们一定帮你实现。');
      expect(wishReplyPresetText(WishReplyPreset.weSawIt, zh),
          '你的愿望爸爸妈妈看到了，写下来就已经很棒了。');
      expect(wishReplyPresetText(WishReplyPreset.weWantItToo, zh),
          '爸爸妈妈也想做到，我们一起努力攒一攒，好不好？');
    });

    test('时机占位：onOccasion 用 5 选 1 文案替换 {occasion}', () {
      expect(
        wishReplyPresetText(
          WishReplyPreset.onOccasion,
          zh,
          occasion: wishOccasionText(WishOccasion.birthday, zh),
        ),
        '等 生日 那天，爸爸妈妈会认真准备这个礼物。',
      );
      expect(
        wishReplyPresetText(
          WishReplyPreset.onOccasion,
          en,
          occasion: wishOccasionText(WishOccasion.christmas, en),
        ),
        contains('Christmas'),
      );
    });

    test('en 文案无 CJK（英文模式零中文）', () {
      final RegExp cjk = RegExp(r'[\u4e00-\u9fff]');
      for (final WishTag tag in WishTag.values) {
        expect(cjk.hasMatch(wishTagText(tag, en)), isFalse, reason: tag.name);
      }
      for (final WishReplyPreset p in WishReplyPreset.values) {
        expect(cjk.hasMatch(wishReplyPresetText(p, en, occasion: 'x')), isFalse,
            reason: p.name);
      }
      for (final WishOccasion o in WishOccasion.values) {
        expect(cjk.hasMatch(wishOccasionText(o, en)), isFalse, reason: o.name);
      }
    });
  });

  group('⑯ 预设词按标签过滤并重排（推荐词首位）', () {
    test('选中 notPossible ⇒ dinosaur 推荐词排首位', () {
      final List<WishReplyPreset> presets =
          wishPresetsForTag(WishTag.notPossible);
      expect(presets.first, WishReplyPreset.dinosaur,
          reason: 'notPossible 的推荐词首位');
      expect(presets.length, 8, reason: '8 条全在（只重排不隐藏）');
      expect(presets.toSet().length, 8, reason: '无重复');
    });

    test('选中 overBudget ⇒ tooExpensive 首位；通用词 weSawIt 恒保留', () {
      final List<WishReplyPreset> presets =
          wishPresetsForTag(WishTag.overBudget);
      expect(presets.first, WishReplyPreset.tooExpensive);
      expect(presets.contains(WishReplyPreset.weSawIt), isTrue);
    });

    test('未选标签 ⇒ 通用词 weSawIt 首位', () {
      expect(wishPresetsForTag(null).first, WishReplyPreset.weSawIt);
    });
  });

  group('⑰ 时机 5 选 1，不可自由输入', () {
    test('WishOccasion 恰好 5 个成员', () {
      expect(WishOccasion.values.length, 5);
    });

    test('源码守卫：时机用 DropdownButtonFormField（无 TextField 自由输入）', () {
      final String src =
          File('lib/presentation/parent/widgets/parent_wish_action_sheet.dart')
              .readAsStringSync();
      expect(src.contains('DropdownButtonFormField<WishOccasion>'), isTrue);
      // 时机下拉那一段（key 之后 400 字符）不含自由输入框。
      final int start = src.indexOf("Key('parent_wish_occasion_picker')");
      final String slice = src.substring(start, start + 600);
      expect(slice.contains('TextField'), isFalse,
          reason: '时机选择不含自由输入框');
    });
  });

  group('⑮ 回信为空允许提交 + 三动作入口', () {
    test('WishTagReplyResult 允许全空（孩子端显示占位）', () {
      const WishTagReplyResult empty = WishTagReplyResult();
      expect(empty.tag, isNull);
      expect(empty.reply, isNull);
    });

    test('源码守卫：sheet 恰好 3 个动作入口 + 回信输入框常驻', () {
      final String src =
          File('lib/presentation/parent/widgets/parent_wish_action_sheet.dart')
              .readAsStringSync();
      expect(src.contains("Key('sheet_action_setup')"), isTrue);
      expect(src.contains("Key('sheet_action_fulfill')"), isTrue);
      expect(src.contains("Key('sheet_action_tag')"), isTrue);
      expect(src.contains("Key('parent_wish_reply_input')"), isTrue);
      // 不落 reply_source（PRD W21 无此列）—— 排除文档注释行。
      final Iterable<String> codeLines = src
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('///'))
          .where((String line) => !line.trimLeft().startsWith('//'));
      final String code = codeLines.join('\n');
      expect(code.contains('reply_source'), isFalse);
      expect(code.contains('replySource'), isFalse);
    });
  });

  group('埋点契约（V15）', () {
    test('家长侧动作统一 wish_parent_action；三作废埋点不存在', () {
      final String names =
          File('lib/core/constants/tracking_event_names.dart')
              .readAsStringSync();
      expect(names.contains("wishParentAction = 'wish_parent_action'"), isTrue);
      expect(names.contains('wishTaskAssigned'), isFalse);
      expect(names.contains('wishTaskCompleted'), isFalse);
      expect(names.contains('wishSelfFulfilled'), isFalse);
    });
  });

  // ── v0.2.0 / R-P0-06~08：弹层三缺陷回归（testWidgets） ──────────────────
  ParentWishActionSheet buildSheet() => ParentWishActionSheet(
        wish: Wish(
          id: 'w1',
          childId: 'c1',
          text: '愿望',
          createdAt: DateTime(2026, 11, 18),
        ),
        onSetup: () {},
        onFulfill: () {},
        onTagReply: (_) {},
      );

  Widget buildHost({required VoidCallback onOpen}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open_sheet'),
              onPressed: onOpen,
              child: const Text('open'),
            ),
          ),
        ),
      );

  group('R-P0-06 双标题 / 重复取消项', () {
    testWidgets('两个标题文案各恰好出现 1 次（只留 labelText）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildSheet())));
      expect(find.text(zh.parent_wish_tag_hint), findsOneWidget,
          reason: '标签标题只由 InputDecoration.labelText 承载');
      expect(find.text(zh.parent_wish_reply_preset), findsOneWidget,
          reason: '预设回复标题只由 InputDecoration.labelText 承载');
    });

    testWidgets('标签下拉 items 恰好 6 项，无 value:null 取消项',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildSheet())));
      await tester.tap(find.byKey(const Key('parent_wish_tag_picker')));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownMenuItem<WishTag?>), findsNWidgets(6));
      expect(
        find.ancestor(
          of: find.text(zh.shared_cancel),
          matching: find.byType(DropdownMenuItem<WishTag?>),
        ),
        findsNothing,
        reason: '取消不再作为下拉项混入（弹层底部按钮仍在）',
      );
    });
  });

  group('R-P0-07 取消返回契约', () {
    testWidgets('点取消弹出 null，无异常、无类型错误',
        (WidgetTester tester) async {
      Future<WishTagReplyResult?>? result;
      await tester.pumpWidget(buildHost(
        onOpen: () {
          result = showDialog<WishTagReplyResult>(
            context: tester.element(find.byKey(const Key('open_sheet'))),
            barrierDismissible: false,
            builder: (_) => buildSheet(),
          );
        },
      ));
      await tester.tap(find.byKey(const Key('open_sheet')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent_wish_action_sheet')), findsOneWidget);

      await tester.tap(find.text(zh.shared_cancel));
      await tester.pumpAndSettle();
      expect(await result, isNull, reason: '取消弹 null，不再弹 false');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('parent_wish_action_sheet')), findsNothing);
    });
  });

  group('R-P0-08 点遮罩不退出', () {
    test('生产调用点 showDialog 设 barrierDismissible: false', () {
      final String src =
          File('lib/presentation/parent/pages/parent_today_page.dart')
              .readAsStringSync();
      expect(src.contains('barrierDismissible: false'), isTrue,
          reason: '点遮罩不得关闭弹层（防落入 PopScope 的 context.go("/")）');
      expect(src.contains('result is! WishTagReplyResult'), isTrue,
          reason: '调用方必须防御非契约返回值');
    });

    testWidgets('点弹层外空白后弹层仍在（barrierDismissible:false 语义）',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildHost(
        onOpen: () {
          unawaited(showDialog<WishTagReplyResult>(
            context: tester.element(find.byKey(const Key('open_sheet'))),
            barrierDismissible: false,
            builder: (_) => buildSheet(),
          ));
        },
      ));
      await tester.tap(find.byKey(const Key('open_sheet')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent_wish_action_sheet')), findsOneWidget,
          reason: '点遮罩不关闭；只能走显式按钮');
      expect(tester.takeException(), isNull);
    });
  });
}
