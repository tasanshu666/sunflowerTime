/// 年龄档：同一组参数的取值分档，不是并列的第二套规则（PRD §2.1 / D2 三档）。
///
/// index 即落库值（settings.age_tier）。迁移时旧 high(1) 被重编号为新 high(2)：
/// low=0(6–8)、mid=1(9–10)、high=2(11–12)。禁止在业务代码里写
/// `ageTier == AgeTier.high ? A : B` 三元，统一查 `kAgeTierParams`。
enum AgeTier {
  low, // 低年级 6–8 岁
  mid, // 中年级 9–10 岁（D2 新增）
  high, // 高年级 11–12 岁
}

/// 奖励分类（PRD §4.8）。
/// 自服务类（看电视 / 玩平板）一律不自动放行，必须家长放行；
/// 家长经手类可保留小额免确认。
enum RewardCategory {
  selfService, // 看电视 / 玩平板（先斩后奏风险高）
  parentHandled, // 小零食 / 文具 / 玩具 / 晚睡 / 电影之夜 / 出游 / 额外故事 / 选晚餐 / 多玩10分钟
}

/// 兑换申请状态机（S2）：pending / queued / verified / rejected。
enum RequestStatus {
  pending, // 待核销：需家长显式处理（家长确认后才入账）
  queued, // 排队中：超池，下月 1 日按申请先后自动放行
  verified, // 已核销：家长显式核销 或 免确认自动放行
  rejected, // 已拒绝：家长显式拒绝，不核销、阳光原路返回（不扣账本）
}

/// 专注会话状态（PRD §4.1 / §6.2）。
enum FocusStatus {
  active, // 进行中
  completed, // 已结算（≥5 分钟，有产出）
  shortAborted, // 短于 5 分钟，无产出
}

/// 阳光账本类型（§3.2 append-only）。
enum SunlightType {
  earn, // 产出（专注/任务/完美日/家长赠予/植物死亡退款）
  redeem, // 兑换扣减（verified）
  queueRelease, // 排队次月放行扣减
  plant, // 植物种植/养护/扩容/救回扣减（M3，与经济账本同源可追溯）
}

/// 成长项打卡的核销状态（M4，家长监管）。
///
/// 顺序**刻意**把 `verified` 放在 0：老库（v5）升级到 v6 时，`check_ins.status`
/// 列默认值 0 会把历史打卡视为「已核销」——历史行为确实是「打卡即入账」。
/// 若把 `pending` 放 0，升级后会突然冒出一堆历史遗留的「待核销」，把家长淹掉。
enum CheckInStatus {
  verified, // 已核销：联动项自动结算 / 家长核销通过 → 已入账
  pending, // 待核销：非联动项手动打卡 → 尚未入账，等家长确认
  rejected, // 已驳回：家长驳回 → 不入账
}

/// 植物阶段（3 段，§4.6）。
enum PlantStage {
  seed, // 种子
  sprout, // 幼苗
  adult, // 成株
}

/// 植物状态（生命周期态，§4.6 H2 软绑定：绝不因专注差而死）。
enum PlantStatus {
  growing, // 成长中
  bloomed, // 已开花（成株终点，仍可被浇水 / 枯萎）
  wilting, // 枯萎中（7 天未浇水触发，20 阳光可救回）
  dead, // 已死亡（返还 30% 成本，花盆释放，deadAt 仅供统计）
}

/// 植物心情（由 lastWaterAt + 当日 WFD 推导，亦可存字段，§4.6）。
enum PlantMood {
  happy, // 今日有有效专注
  calm, // 平静
  thirsty, // 口渴 / 未浇水
}

/// 科目（§4.4 / 完美日判定）。
///
/// `custom` 为 M3 修订新增：选中后由家长自由输入科目名，名字存
/// `Tasks.customSubject`（不新增枚举以外的落库口径，index 仍为整型）。
enum TaskSubject {
  chinese, // 语文
  math, // 数学
  english, // 英语
  general, // 通用（非学科打卡）
  custom, // 自定义（科目名见 Task.customSubject）
}

/// 稀有度（§8.2 植物/奖励定价）。
enum Rarity {
  common,
  rare,
  legendary,
}

/// 冷却周期（§4.8 E6 频次主阀门）。
enum CooldownPeriod {
  weekly,
  monthly,
}

/// 奖励冷却规则（D3）：冷却周期枚举，供未来 monthly 扩展；D4 默认 weekly。
///
/// 与 `CooldownPeriod` 并存：前者是「计数周期」，后者是「规则/语义」（D3/U3）。
enum CooldownRule {
  none, // 无冷却
  weekly, // 每周限领（D4：每奖励每周限领 1 次）
  monthly, // 每月限领（预留）
}

/// 埋点类型（§6 / §8.3 纪念册 + 指标）。
enum TrackingType {
  milestone, // 毕业纪念册事件
  metric, // WFD / 留存等累计指标
}

/// 成长项内容分类（M5，家长可在编辑器里给孩子设分类；孩子端按分类分组展示）。
///
/// ⚠️ index **0 MUST be `other`**：老库（v8 及之前）根本没有该列，v8→v9 迁移时
/// 给 `tasks.category` 列加了默认值 0，历史成长项会被读作 `other`，避免历史数据被
/// 误判成某个具体分类（学习/运动/生活）。新增/编辑的成长项应显式设具体分类。
enum TaskCategory {
  other, // 0：历史行安全默认值
  learning, // 学习
  sports, // 运动
  life, // 生活
}

/// [TaskCategory] 展示扩展（中文标签 + 占位图标，真实角色立绘后续由玄参大人提供）。
extension TaskCategoryX on TaskCategory {
  /// 中文分类名（学习/运动/生活/其他）。
  String get label {
    switch (this) {
      case TaskCategory.other:
        return '其他';
      case TaskCategory.learning:
        return '学习';
      case TaskCategory.sports:
        return '运动';
      case TaskCategory.life:
        return '生活';
    }
  }

  /// 占位图标（emoji，待玄参大人提供真实角色立绘后替换）。
  String get icon {
    switch (this) {
      case TaskCategory.other:
        return '⭐';
      case TaskCategory.learning:
        return '📚';
      case TaskCategory.sports:
        return '🏃';
      case TaskCategory.life:
        return '🪥';
    }
  }
}

/// 奖励内容分类（M5）。
///
/// 与既有 [RewardCategory] **语义不同**：[RewardCategory] 表示「是否家长经手兑现」
/// （自服务 / 家长经手），本枚举表示「奖励内容是什么」（零食 / 游玩 / 娱乐 / 其他），
/// 供孩子端阳光商店按内容分组。两者各存各的 DB 列，互不复用。
///
/// ⚠️ index **0 MUST be `other`**：老库（v8 及之前）无该列，v8→v9 迁移给
/// `reward_templates.content_category` 列加默认值 0，历史奖励读作 `other`。
enum RewardContentCategory {
  other, // 0：历史行安全默认值
  snacks, // 零食
  play, // 游玩
  entertainment, // 娱乐
}

/// [RewardContentCategory] 展示扩展（中文标签 + 占位图标）。
extension RewardContentCategoryX on RewardContentCategory {
  /// 中文分类名（零食/游玩/娱乐/其他）。
  String get label {
    switch (this) {
      case RewardContentCategory.other:
        return '其他';
      case RewardContentCategory.snacks:
        return '零食';
      case RewardContentCategory.play:
        return '游玩';
      case RewardContentCategory.entertainment:
        return '娱乐';
    }
  }

  /// 占位图标（emoji，待玄参大人提供真实角色立绘后替换）。
  String get icon {
    switch (this) {
      case RewardContentCategory.other:
        return '⭐';
      case RewardContentCategory.snacks:
        return '🍬';
      case RewardContentCategory.play:
        return '🎡';
      case RewardContentCategory.entertainment:
        return '🎮';
    }
  }
}

/// 孩子端成长页分组展示顺序（FIRST-LEVEL 分区头）：学习/运动/生活/其他（其他置后）。
///
/// 注意顺序与 [TaskCategory] 的 index 顺序不同（枚举 index 0 必须是 other 作安全默认），
/// 这里按人类可读的展示顺序排列，避免孩子端把「其他」顶在最前。
const List<TaskCategory> kTaskCategoryOrder = <TaskCategory>[
  TaskCategory.learning,
  TaskCategory.sports,
  TaskCategory.life,
  TaskCategory.other,
];

/// 孩子端商店页分组展示顺序（FIRST-LEVEL 分区头）：零食/游玩/娱乐/其他（其他置后）。
const List<RewardContentCategory> kRewardContentCategoryOrder =
    <RewardContentCategory>[
  RewardContentCategory.snacks,
  RewardContentCategory.play,
  RewardContentCategory.entertainment,
  RewardContentCategory.other,
];
