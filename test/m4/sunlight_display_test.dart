/// F105 回归测试：阳光余额的**展示口径统一**（2026-10-09）。
///
/// ## 背景（玄参真机/模拟器反馈）
/// 商店页显示 **390**，今日 / 花园 / 我的显示 **389** —— 同一个余额两个数。
/// 拉模拟器库实证：`sum(net) = 389.913261`（专注按分钟计酬，净额天然带小数），
/// 根因是取整方向不一致：
///   · 今日 / 花园 / 我的 → `.toInt()`（向下）= 389；
///   · 商店 → `.round()`（四舍五入）= 390。
///
/// 修法：全端统一走 [sunlightDisplayInt]（向下取整，孩子看到的阳光永不虚高）。
/// 本文件把口径钉死——谁改回 `round()` 都会在这里红。
library sunlight_display_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/utils/sunlight_display.dart';

void main() {
  group('sunlightDisplayInt · 阳光展示口径（F105）', () {
    test('真机库实测余额 389.913261 → 389（向下取整，不是四舍五入的 390）', () {
      expect(sunlightDisplayInt(389.913261), 389);
    });

    test('小数一律不进位：x.99 也向下（可用阳光永不虚高）', () {
      expect(sunlightDisplayInt(0.99), 0);
      expect(sunlightDisplayInt(5.8986), 5); // 库中 focus_session 真实净额
      expect(sunlightDisplayInt(20.0147), 20); // 库中 focus_session 真实净额
      expect(sunlightDisplayInt(999.999), 999);
    });

    test('整数原样返回（既有四处的历史显示不变）', () {
      expect(sunlightDisplayInt(0.0), 0);
      expect(sunlightDisplayInt(1.0), 1);
      expect(sunlightDisplayInt(389.0), 389);
      expect(sunlightDisplayInt(123456.0), 123456);
    });

    test('非正数钳到 0（账本异常 / 待核销扣减超过余额时不显示负数）', () {
      expect(sunlightDisplayInt(-0.5), 0);
      expect(sunlightDisplayInt(-10.0), 0);
    });

    test('回归锚点：与 .round() 的口径差异（改回 round 必红）', () {
      expect(
        sunlightDisplayInt(389.913261),
        isNot(389.913261.round()),
        reason: '向下取整 ≠ 四舍五入；两者相等即口径已漂回 round()',
      );
    });

    test('商店「可用 = 余额 − 待核销」也走同一口径（F105 现场场景）', () {
      const double balance = 389.913261;
      const int pendingTotal = 0;
      expect(sunlightDisplayInt(balance - pendingTotal), 389);
      // 有待核销时同样向下取整（只影响展示，不动账本）。
      expect(sunlightDisplayInt(balance - 30), 359);
    });
  });
}
