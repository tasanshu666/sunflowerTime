/// 测试专用随机源（口径 C26 配套）。
///
/// ## 为什么需要它
/// C26 给 [tickAll] 加了「每株每天 roll 杂草 / 害虫」。存量老测试要么注入固定
/// `Random(seed)` 锁 bloom 奖励序列、要么精确断言成长天数 —— 干扰物 roll 一旦
/// 命中就会「当天成长暂停」，把这些断言全部打红；且固定种子的序列跑得足够久
/// 必然命中（40% / 25% 概率），「换个种子」治标不治本。
///
/// [NoHitRandom] 的 `nextDouble()` 恒返回 `0.999…`，对任何 `rate < 1` 都不命中
/// → 注入 `weedRandom:` 后老测试彻底与干扰物隔离；它也**不消耗**主 `random`
/// 序列，「结算零消耗 / 登记消耗 N 次」类计数断言保持原语义。
///
/// 用法：
/// ```dart
/// final svc = PlantGrowthService(
///   ...,
///   random: Random(seed),          // bloom 奖励序列（原样保留）
///   weedRandom: NoHitRandom(),     // 干扰物永不出现
/// );
/// ```
library;

import 'dart:math';

/// 永不命中的确定性随机源（仅测试用）。
class NoHitRandom implements Random {
  /// 任意 `rate < 1` 都判 false 的安全值。
  static const double _neverHit = 0.9999999999999999;

  @override
  double nextDouble() => _neverHit;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}
