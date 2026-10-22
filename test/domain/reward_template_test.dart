/// 奖励模板「本周可兑换次数」展示文案单测。
///
/// i18n B3（T02）：原顶层 `weeklyRedeemLabel` 已从 domain 删除（domain 零 CJK），
/// 迁到 `core/i18n/domain_text_l10n.dart` 的 `weeklyRedeemLabelL10n(limit, used, l10n)`。
/// **断言语义与文案逐字节不变** —— 只是多一个 `AppLocalizationsZh()` 入参。
library reward_template_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/domain_text_l10n.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();

  group('weeklyRedeemLabelL10n（剩余次数口径）', () {
    test('不限次数：limit<=0 恒显示「不限次数」', () {
      expect(weeklyRedeemLabelL10n(0, 0, zh), '不限次数');
      expect(weeklyRedeemLabelL10n(0, 5, zh), '不限次数');
      expect(weeklyRedeemLabelL10n(-1, 3, zh), '不限次数');
    });

    test('限领1次：remaining==1 显示「周限 1 次」', () {
      expect(weeklyRedeemLabelL10n(1, 0, zh), '周限 1 次');
    });

    test('限领>=2：remaining>=2 显示「周限 N 次」', () {
      expect(weeklyRedeemLabelL10n(3, 0, zh), '周限 3 次');
      expect(weeklyRedeemLabelL10n(3, 1, zh), '周限 2 次');
      expect(weeklyRedeemLabelL10n(2, 0, zh), '周限 2 次');
    });

    test('领完隐藏：remaining<=0 返回 null（由禁用态承载）', () {
      expect(weeklyRedeemLabelL10n(3, 3, zh), isNull);
      expect(weeklyRedeemLabelL10n(3, 5, zh), isNull); // count 超过 limit 也不越界
      expect(weeklyRedeemLabelL10n(1, 1, zh), isNull);
    });

    test('边界：remaining 从 2 跨到 1 文案切换', () {
      expect(weeklyRedeemLabelL10n(2, 1, zh), '周限 1 次');
    });
  });
}
