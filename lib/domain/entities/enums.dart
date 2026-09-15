/// 年龄档：同一组参数的取值分档，不是并列的第二套规则（PRD §2.1）。
enum AgeTier {
  low, // 低年级 6–8 岁
  high, // 高年级 9–12 岁
}

/// 奖励分类（PRD §4.8）。
/// 自服务类（看电视 / 玩平板）一律不自动放行，必须家长放行；
/// 家长经手类可保留小额免确认。
enum RewardCategory {
  selfService, // 看电视 / 玩平板（先斩后奏风险高）
  parentHandled, // 小零食 / 文具 / 玩具 / 晚睡 / 电影之夜 / 出游 / 额外故事 / 选晚餐 / 多玩10分钟
}

/// 兑换申请状态机（S2）：pending / queued / verified。
enum RequestStatus {
  pending, // 待核销：需家长显式处理（分母计入核销履约率）
  queued, // 排队中：超池，下月 1 日按申请先后自动放行
  verified, // 已核销：家长显式核销 或 免确认自动放行
}

/// 专注会话状态（PRD §4.1 / §6.2）。
enum FocusStatus {
  active, // 进行中
  completed, // 已结算（≥5 分钟，有产出）
  shortAborted, // 短于 5 分钟，无产出
}

/// 阳光账本类型（§3.2 append-only）。
enum SunlightType {
  earn, // 产出（专注/任务/完美日）
  redeem, // 兑换扣减（verified）
  queueRelease, // 排队次月放行扣减
}

/// 植物阶段（3 段，§4.6）。
enum PlantStage {
  seed, // 种子
  sprout, // 幼苗
  adult, // 成株
}

/// 植物状态（§4.6 H2 软绑定：绝不因专注差而死）。
enum PlantStatus {
  growing, // 成长中
  bloomed, // 已开花
  dormant, // 休眠（非死亡）
}

/// 科目（§4.4 / 完美日判定）。
enum TaskSubject {
  chinese, // 语文
  math, // 数学
  english, // 英语
  general, // 通用（非学科打卡）
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

/// 埋点类型（§6 / §8.3 纪念册 + 指标）。
enum TrackingType {
  milestone, // 毕业纪念册事件
  metric, // WFD / 履约率 / 留存指标
}
