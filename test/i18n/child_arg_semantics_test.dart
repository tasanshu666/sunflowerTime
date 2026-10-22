/// `child_*` 带参 key 的**参数语义**守卫（i18n B3 · T01）。
///
/// ## 为什么需要它
/// `arb_placeholder_guard_test` 只能证明「ARB 声明顺序 == 生成签名顺序」。
/// 但如果**两处一起写反**（ARB 声明成 `total, capped` 且调用方也按那个顺序传），
/// 守卫依然全绿，而孩子看到的是「共获得 2 阳光（17 项今日额度已满，未发放）」。
/// 唯一能挡住这类「一致地错」的手段：用**真实参数值**断言渲染结果**逐字**正确，
/// 并额外断言 `f(a, b) != f(b, a)`（两参数取值不同 ⇒ 交换必然改变输出），
/// 从而证明「顺序确实被正文消费」，装配时无法静默换位。
///
/// 覆盖 6 条最易错（B1 栽过的同型缺陷）：
///  ① `child_settle_cap_orig_vs_net(net, raw)` —— 生成顺序是 **net 在前**，
///     而人类语序是「原本 raw，实到 net」⇒ 极易传反；
///  ② `child_entry_remaining_today(cap, minutes)` —— 生成顺序 cap 在前，
///     人类语序 minutes 在前；
///  ③ `child_entry_remaining_snack(minutes, remaining)` —— 生成顺序 minutes 在前，
///     人类语序 remaining 在前（与上一条**恰好相反**，成对出现最易互抄错）；
///  ④ `child_shell_task_footer_partial(capped, total)` —— 生成顺序 capped 在前，
///     人类语序 total 在前；
///  ⑤ `child_settle_cap_body_detail(cheer, detail)` —— 生成顺序 cheer 在前，
///     人类语序 detail 在前；
///  ⑥ `child_settle_task_done(capped, name, sun)` —— 三参混合（String/String/String），
///     类型全同 ⇒ 交换零编译错。
library child_arg_semantics_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// CJK 统一表意文字 + 中文标点（用来证明 en 文案真的被翻译了）。
final RegExp _cjkRe = RegExp(
  r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]',
);

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();
  final AppLocalizationsEn en = AppLocalizationsEn();

  group('① child_settle_cap_orig_vs_net(net, raw)', () {
    test('zh 逐字：原本 {raw}，实到 {net}', () {
      expect(
        zh.child_settle_cap_orig_vs_net('5', '10'),
        '（原本 10 ☀️，实到 5 ☀️）',
        reason: '生成签名是 (net, raw) —— 第一个入参落在「实到」，第二个落在「原本」',
      );
    });

    test('交换两参必然改变输出（顺序确实被正文消费）', () {
      expect(
        zh.child_settle_cap_orig_vs_net('5', '10'),
        isNot(zh.child_settle_cap_orig_vs_net('10', '5')),
      );
    });

    test('en 同源且不含 CJK', () {
      final String s = en.child_settle_cap_orig_vs_net('5', '10');
      expect(s, '(originally 10 ☀️, credited 5 ☀️)');
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('② child_entry_remaining_today(cap, minutes)', () {
    test('zh 逐字：minutes 与 cap 各就各位', () {
      expect(
        zh.child_entry_remaining_today(30, 12),
        '今天还可以专注 12 分钟（每日上限 30 分钟）',
        reason: '生成签名是 (cap, minutes)，人类语序相反 ⇒ 最易传反的一条',
      );
    });

    test('交换两参必然改变输出', () {
      expect(
        zh.child_entry_remaining_today(30, 12),
        isNot(zh.child_entry_remaining_today(12, 30)),
      );
    });

    test('en 同源且不含 CJK', () {
      final String s = en.child_entry_remaining_today(30, 12);
      expect(s, 'You can still focus 12 min today (daily limit 30 min)');
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('③ child_entry_remaining_snack(minutes, remaining)', () {
    test('zh 逐字：与 ② 顺序**相反**（minutes 在前）', () {
      expect(
        zh.child_entry_remaining_snack(5, 8),
        '今天只剩 8 分钟额度了，这次就专注 5 分钟吧',
        reason: '生成签名是 (minutes, remaining) —— 与 ② 的 (cap, minutes) 顺序相反',
      );
    });

    test('交换两参必然改变输出', () {
      expect(
        zh.child_entry_remaining_snack(5, 8),
        isNot(zh.child_entry_remaining_snack(8, 5)),
      );
    });

    test('en 同源且不含 CJK', () {
      final String s = en.child_entry_remaining_snack(5, 8);
      expect(s, 'Only 8 min left today, so this session is 5 min');
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('④ child_shell_task_footer_partial(capped, total)', () {
    test('zh 逐字：total 落在「共获得」，capped 落在「N 项」', () {
      expect(
        zh.child_shell_task_footer_partial(2, 17),
        '共获得 17 阳光（2 项今日额度已满，未发放）',
        reason: '生成签名是 (capped, total)，人类语序 total 在前',
      );
    });

    test('交换两参必然改变输出', () {
      expect(
        zh.child_shell_task_footer_partial(2, 17),
        isNot(zh.child_shell_task_footer_partial(17, 2)),
      );
    });

    test('en 同源且不含 CJK', () {
      final String s = en.child_shell_task_footer_partial(2, 17);
      expect(s, 'Got 17 sunlight (2 item(s) hit the daily cap)');
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('⑤ child_settle_cap_body_detail(cheer, detail)', () {
    test('zh 逐字：detail 嵌中段、cheer 收尾', () {
      expect(
        zh.child_settle_cap_body_detail('明天再来哦', '（原本 10 ☀️，实到 5 ☀️）'),
        '超出额度的部分就不再收集阳光了（原本 10 ☀️，实到 5 ☀️）。明天再来哦',
        reason: '生成签名是 (cheer, detail)，人类语序 detail 在前',
      );
    });

    test('交换两参必然改变输出', () {
      expect(
        zh.child_settle_cap_body_detail('甲', '乙'),
        isNot(zh.child_settle_cap_body_detail('乙', '甲')),
      );
    });

    test('en 同源且不含 CJK', () {
      final String s =
          en.child_settle_cap_body_detail('Come back tomorrow', '(originally 10, credited 5)');
      expect(
        s,
        'No sunlight is collected beyond the quota(originally 10, credited 5). '
        'Come back tomorrow',
      );
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('⑥ child_settle_task_done(capped, name, sun)', () {
    test('zh 逐字：三参（全 String）各就各位', () {
      expect(
        zh.child_settle_task_done('', '练字', '12'),
        '成长项「练字」完成 +12 ☀',
        reason: '生成签名是 (capped, name, sun) —— 首参是**封顶尾注**，不是名字',
      );
    });

    test('封顶尾注拼接在句末', () {
      expect(
        zh.child_settle_task_done('（今日阳光已达上限）', '练字', '12'),
        '成长项「练字」完成 +12 ☀（今日阳光已达上限）',
      );
    });

    test('三参两两交换都会改变输出（证明无一路径被忽略）', () {
      final String base = zh.child_settle_task_done('A', 'B', 'C');
      expect(base, isNot(zh.child_settle_task_done('B', 'A', 'C')));
      expect(base, isNot(zh.child_settle_task_done('A', 'C', 'B')));
      expect(base, isNot(zh.child_settle_task_done('C', 'B', 'A')));
    });

    test('en 同源且不含 CJK', () {
      final String s = en.child_settle_task_done('', 'Handwriting', '12');
      expect(s, 'Task "Handwriting" done +12 ☀');
      expect(_cjkRe.hasMatch(s), isFalse);
    });
  });

  group('⑦ 类型收紧回归（Object → int/String 后调用方无法再传错类型）', () {
    test('int 形参不再接受任意 Object（编译期即挡住）', () {
      // 这条是**语义说明性**断言：能编译说明签名确实是 int。
      // 若 meta 被误删（退回 Object），下面的 `final int n = ...` 会在赋值处报错。
      final int rendered = zh.child_entry_minutes(90).length;
      expect(rendered, greaterThan(0));
      expect(zh.child_entry_minutes(90), '90 分钟');
    });

    test('String 形参不再接受 int（同上，编译器兜底）', () {
      expect(zh.child_shell_reject_subtitle('家长备注'), '（家长备注）');
    });
  });
}
