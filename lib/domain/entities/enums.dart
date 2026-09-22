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
