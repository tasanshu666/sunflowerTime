/// 奖励模板种子（D3/D4 占位版 → C52 默认版重写 / 阶段 4 精简为 5 条）。
///
/// 口径（§0 D3 / D4 + C52 默认版）：
///  · 全部 `parentHandled`（家长经手兑现）；
///  · 高频小额（周限 3 次）走 `frequencyLimitPerWeek=3` + `cooldownRule=weekly`，
///    大奖（周限 1 次）同规则限 1；
///  · parentHandled 类小额可走免确认；不设 selfService 种子（C5③ 已有测试覆盖）。
///
/// 阶段 4（玄参拍板）：**由 6 条精简为 5 条**，对齐免费档奖励上限 `kFreeRewardQuota`（5）。
/// ⚠️ 存量用户数据**原样保留**（C69 / F109）：仅当表为空时才播种，绝不删改既有行。
///
/// 注意：`RewardTemplate` 实体无 `enabled` 字段（enabled 仅存在于 DB 列，由
/// `RewardLocalRepository.saveTemplate` 固定写 `true`），故此处构造不传 enabled。
///
/// ## i18n B3 · T05：模板里**没有 name**
/// 与 `task_seed.dart` 同构：拆成 [RewardSeedTemplate]（结构化字段）+ `nameOf` 回调，
/// 名字由调用方按当前语言注入（`core/i18n/seed_l10n.dart` 的 `rewardSeedName`）。
/// **老库里的中文行不动** —— 播种只在表空时发生，换语言不改写用户数据。
library reward_seed;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';

/// 一条奖励种子模板（**不含 name**：名字由调用方按语言注入）。
class RewardSeedTemplate {
  /// 种子 id（= 落库后的模板 id，`seed_reward_*` / `seed_snack` 等）。
  ///
  /// ⚠️ 历史 id（`seed_snack` / `seed_extra_play` / `seed_cartoon` / `seed_toy` /
  /// `seed_weekend_outing`）**必须原样保留**：它们是老库里已落行的主键，
  /// 改名等于制造「同一条奖励两份记录」。
  final String id;

  /// 类目（当前种子全部 parentHandled）。
  final RewardCategory category;

  /// 内容分类（零食 / 娱乐 / 游玩；仅用于商店分组展示）。
  final RewardContentCategory contentCategory;

  /// 家长设定的单价（阳光）。
  final int baseCost;

  /// 每周可兑换次数上限。
  final int frequencyLimitPerWeek;

  /// 冷却规则（种子全部 weekly）。
  final CooldownRule cooldownRule;

  const RewardSeedTemplate({
    required this.id,
    required this.category,
    required this.contentCategory,
    required this.baseCost,
    required this.frequencyLimitPerWeek,
    required this.cooldownRule,
  });

  /// 装配成可落库的 [RewardTemplate]：**唯一**缺的字段是 name。
  RewardTemplate toTemplate({required String name}) => RewardTemplate(
        id: id,
        name: name,
        category: category,
        contentCategory: contentCategory,
        baseCost: baseCost,
        frequencyLimitPerWeek: frequencyLimitPerWeek,
        cooldownRule: cooldownRule,
      );
}

/// 5 条默认奖励模板（阶段 4 精简版；玄参 2026-10-14 拍板保留清单）。
///
/// 保留：小零食 / 睡前多玩10分钟 / 看一集动画片 / 买一个小玩具 / 周末出去玩。
/// 去掉：睡前多听1个故事。
/// baseCost 为家长设定单价，显示价 = 扣费价（不再叠加分龄系数 K）。
///
/// 🔴 顺序即 UI 展示序，**永不重排**。
const List<RewardSeedTemplate> kSeedRewardTemplates = <RewardSeedTemplate>[
  RewardSeedTemplate(
    id: 'seed_snack',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.snacks, // 小零食 → 零食
    baseCost: 30,
    frequencyLimitPerWeek: 3,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardSeedTemplate(
    id: 'seed_extra_play',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 截图口径：娱乐
    baseCost: 20,
    frequencyLimitPerWeek: 3,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardSeedTemplate(
    id: 'seed_cartoon',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 看动画片 → 娱乐
    baseCost: 100,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardSeedTemplate(
    id: 'seed_toy',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.entertainment, // 截图口径：娱乐
    baseCost: 100,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
  RewardSeedTemplate(
    id: 'seed_weekend_outing',
    category: RewardCategory.parentHandled,
    contentCategory: RewardContentCategory.play, // 周末出去玩 → 游玩
    baseCost: 200,
    frequencyLimitPerWeek: 1,
    cooldownRule: CooldownRule.weekly,
  ),
];

/// 首次启动播种：若当前无任何奖励模板则逐条写入（幂等，不覆盖既有数据）。
///
/// [nameOf] 必传（i18n B3 · T05）：见 `task_seed.dart::ensureTaskSeed` 的同款说明。
Future<void> ensureRewardSeed(
  RewardRepository repo, {
  required String Function(String seedId) nameOf,
}) async {
  if ((await repo.templates()).isEmpty) {
    for (final RewardSeedTemplate tpl in kSeedRewardTemplates) {
      await repo.saveTemplate(tpl.toTemplate(name: nameOf(tpl.id)));
    }
  }
}
