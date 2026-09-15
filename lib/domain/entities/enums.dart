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
