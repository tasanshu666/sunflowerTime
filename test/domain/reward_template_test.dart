/// 奖励模板实体单测：聚焦「本周可兑换次数」展示文案 [weeklyRedeemLabel]。
library reward_template_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/reward_template.dart';

void main() {
  group('weeklyRedeemLabel（剩余次数口径）', () {
    test('不限次数：limit<=0 恒显示「不限次数」', () {
      expect(weeklyRedeemLabel(0, 0), '不限次数');
      expect(weeklyRedeemLabel(0, 5), '不限次数');
      expect(weeklyRedeemLabel(-1, 3), '不限次数');
    });

    test('限领1次：remaining==1 显示「仅可兑换 1 次」', () {
      expect(weeklyRedeemLabel(1, 0), '仅可兑换 1 次');
    });

    test('限领>=2：remaining>=2 显示「可兑换次数为 N」', () {
      expect(weeklyRedeemLabel(3, 0), '可兑换次数为3');
      expect(weeklyRedeemLabel(3, 1), '可兑换次数为2');
      expect(weeklyRedeemLabel(2, 0), '可兑换次数为2');
    });

    test('领完隐藏：remaining<=0 返回 null（由禁用态承载）', () {
      expect(weeklyRedeemLabel(3, 3), isNull);
      expect(weeklyRedeemLabel(3, 5), isNull); // count 超过 limit 也不越界
      expect(weeklyRedeemLabel(1, 1), isNull);
    });

    test('边界：remaining 从 2 跨到 1 文案切换', () {
      expect(weeklyRedeemLabel(2, 1), '仅可兑换 1 次');
    });
  });
}
