/// 奖励模板种子（D3/D4）：5 条占位模板，首次启动若无模板则写入。
///
/// 口径（§0 D3 / D4）：
///  · 每奖励每周限领 1 次 → `frequencyLimitPerWeek=1` + `cooldownRule=CooldownRule.weekly`；
///  · parentHandled 类小额可走免确认；selfService 类（多看一集动画片）不自动放行（C5③）。
///
/// 注意：`RewardTemplate` 实体无 `enabled` 字段（enabled 仅存在于 DB 列，由
/// `RewardLocalRepository.saveTemplate` 固定写 `true`），故此处构造不传 enabled。
library reward_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';

/// 5 条占位奖励模板（D3）。baseCost 为家长设定单价，显示价 = 扣费价（不再叠加分龄系数 K）。
const List<RewardTemplate> kSeedRewardTemplates = [
  RewardTemplate(
    id: 'seed_snack',
    name: '小零食',
    category: RewardCategory.parentHandled,
    baseCost: 20,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_cartoon_tonight',
    name: '选今晚动画片',
    category: RewardCategory.parentHandled,
    baseCost: 40,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_extra_10min',
    name: '多玩10分钟',
    category: RewardCategory.parentHandled,
    baseCost: 60,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardTemplate(
    id: 'seed_weekend_outing',
    name: '周末出去玩',
    category: RewardCategory.parentHandled,
    baseCost: 120,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  // C5③ 验证：selfService 类不自动放行，须家长核销。
  RewardTemplate(
    id: 'seed_extra_episode',
    name: '多看一集动画片',
    category: RewardCategory.selfService,
    baseCost: 50,
    frequencyLimitPerWeek: 1,
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
