/// 奖励模板种子（D3/D4 占位版 → C52 默认版重写，玄参 2026-10-10 截图拍板）。
///
/// 口径（§0 D3 / D4 + C52 默认版）：
///  · 全部 `parentHandled`（家长经手兑现）；
///  · 高频小额（周限 3 次）走 `frequencyLimitPerWeek=3` + `cooldownRule=weekly`，
///    大奖（周限 1 次）同规则限 1；
///  · parentHandled 类小额可走免确认；不设 selfService 种子（C5③ 已有测试覆盖）。
///
/// 注意：`RewardTemplate` 实体无 `enabled` 字段（enabled 仅存在于 DB 列，由
/// `RewardLocalRepository.saveTemplate` 固定写 `true`），故此处构造不传 enabled。
library reward_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';

/// 6 条默认奖励模板（C52 默认版，玄参 2026-10-10 截图拍板）。
/// baseCost 为家长设定单价，显示价 = 扣费价（不再叠加分龄系数 K）。
const List<RewardTemplate> kSeedRewardTemplates = [
  RewardTemplate(
    id: 'seed_snack',
    name: '小零食',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.snacks, // 小零食 → 零食
    baseCost: 30,
    frequencyLimitPerWeek: 3,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_cartoon',
    name: '看一集动画片',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 看动画片 → 娱乐
    baseCost: 100,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_extra_play',
    name: '睡前多玩10分钟',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 截图口径：娱乐
    baseCost: 20,
    frequencyLimitPerWeek: 3,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_weekend_outing',
    name: '周末出去玩',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.play, // 周末出去玩 → 游玩
    baseCost: 200,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_toy',
    name: '买一个小玩具',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 截图口径：娱乐
    baseCost: 100,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_story',
    name: '睡前多听1个故事',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 截图口径：娱乐
    baseCost: 30,
    frequencyLimitPerWeek: 3,
    cooldownRule: CooldownRule.weekly,
  ),
];

/// 首次启动播种：若当前无任何奖励模板则逐条写入（幂等，不覆盖既有数据）。
Future<void> ensureRewardSeed(RewardRepository repo) async {
  if ((await repo.templates()).isEmpty) {
    for (final RewardTemplate t in kSeedRewardTemplates) {
      await repo.saveTemplate(t);
    }
  }
}
