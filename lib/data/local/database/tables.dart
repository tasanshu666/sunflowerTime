/// Drift 表定义（§3.1）。命名沿用领域表名，列按 §3.1 字段类型映射。
/// 枚举按 index 存 int；DateTime 用 dateTime()；UUID 用 text()。
library tables;

import 'package:drift/drift.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 全局设置（单例行，id 固定 = 1）。夜间边界为唯一收口值（§6.1）。
class Settings extends Table {
  IntColumn get id => integer()();
  IntColumn get ageTier => integer()(); // 0=low,1=mid,2=high（D2 三档；迁移时旧 1 重编号为 2）
  IntColumn get nightBoundaryHour => integer().withDefault(const Constant(kNightBoundaryDefaultHour))();
  IntColumn get nightBoundaryMinute => integer().withDefault(const Constant(0))();
  IntColumn get dailyFocusCap => integer()();
  IntColumn get dailyAppCapMinutes => integer()();
  IntColumn get restAfterSessions => integer()();
  IntColumn get restMinutes => integer()();
  IntColumn get taskSunlight => integer()();
  IntColumn get monthlyPoolBudget => integer()();
  BoolColumn get quietMode => boolean().withDefault(const Constant(false))();
  BoolColumn get soundOn => boolean().withDefault(const Constant(true))();
  BoolColumn get bgmOn => boolean().withDefault(const Constant(false))();
  BoolColumn get detectionOn => boolean().withDefault(const Constant(true))();
  IntColumn get autoConfirmSingleHigh => integer().withDefault(const Constant(kAutoApproveMaxCostHigh))();
  IntColumn get autoConfirmSingleLow => integer().withDefault(const Constant(kAutoApproveMaxCostLow))();
  RealColumn get autoConfirmMonthlyPct => real().withDefault(const Constant(kAutoApprovePoolRatio))();
  RealColumn get currencyRate => real().withDefault(const Constant(kAutoApprovePoolRatio))();
  BoolColumn get themeDark => boolean().withDefault(const Constant(false))();
  BoolColumn get autonomousMode => boolean().withDefault(const Constant(false))();
  IntColumn get gardenPotCapacity =>
      integer().withDefault(const Constant(kGardenPotCapacityDefault))(); // 花园花盆容量（M3 §3.1）

  @override
  Set<Column> get primaryKey => {id};
}

/// 植物（§3.1 plant，M3 schemaVersion 4 新增）。
class Plants extends Table {
  TextColumn get id => text()();
  TextColumn get speciesId => text()();
  IntColumn get potIndex => integer()();
  IntColumn get stage => integer()(); // PlantStage index
  DateTimeColumn get stageStartedAt => dateTime()();
  RealColumn get growthProgress => real().withDefault(const Constant(0.0))(); // 0..1
  RealColumn get growthFactor => real().withDefault(const Constant(1.0))(); // 1.0 / 1.3
  BoolColumn get waterUsed => boolean().withDefault(const Constant(false))();
  BoolColumn get fertilizerUsed => boolean().withDefault(const Constant(false))();
  IntColumn get status => integer()(); // PlantStatus index
  DateTimeColumn get plantedAt => dateTime()();
  DateTimeColumn get lastWaterAt => dateTime().nullable()();
  DateTimeColumn get wiltedAt => dateTime().nullable()();
  DateTimeColumn get deadAt => dateTime().nullable()();
  DateTimeColumn get bloomedAt => dateTime().nullable()(); // 进入「盛开」的计时起点（花谢循环；v8 新增）
  IntColumn get mood => integer().withDefault(const Constant(0))(); // PlantMood index

  @override
  Set<Column> get primaryKey => {id};
}

/// 专注会话（§3.1 focus_session）。
class FocusSessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get end => dateTime().nullable()();
  IntColumn get plannedMin => integer()();
  RealColumn get actualFocusMin => real()();
  IntColumn get status => integer()(); // FocusStatus index
  RealColumn get sunlightEarned => real()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 阳光账本（§3.1 sunlight_ledger，append-only）。
class SunlightLedgers extends Table {
  TextColumn get id => text()();
  DateTimeColumn get ts => dateTime()();
  IntColumn get type => integer()(); // SunlightType index
  RealColumn get gross => real()();
  RealColumn get net => real()();
  RealColumn get balanceAfter => real()();
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get dayKey => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 奖励模板（§3.1 reward_template）。
class RewardTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get category => integer()(); // RewardCategory index
  IntColumn get baseCost =>
      integer().withDefault(const Constant(50))(); // 单基准价（消耗侧，未乘 K）
  IntColumn get freqLimit => integer().nullable()();
  IntColumn get cooldownRule =>
      integer().withDefault(const Constant(1))(); // 冷却规则（D3，默认 weekly；CooldownRule.weekly.index == 1）
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 兑换申请（§3.1 redemption_request）。
class RedemptionRequests extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  DateTimeColumn get requestedAt => dateTime()();
  IntColumn get cost => integer()();
  IntColumn get status => integer()(); // RequestStatus index
  BoolColumn get autoApproved => boolean().withDefault(const Constant(false))();
  IntColumn get queuePosition => integer().nullable()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();
  TextColumn get parentNote => text().nullable()();
  TextColumn get childId =>
      text().withDefault(const Constant(kChildIdDefault))(); // 归属孩子（C1/D2）

  @override
  Set<Column> get primaryKey => {id};
}

/// 月度池（§3.1 monthly_pool）。
class MonthlyPools extends Table {
  TextColumn get monthKey => text()();
  IntColumn get budget => integer()();
  IntColumn get used => integer().withDefault(const Constant(0))();
  IntColumn get autoReleased => integer().withDefault(const Constant(0))();
  DateTimeColumn get resetAt => dateTime()();

  @override
  Set<Column> get primaryKey => {monthKey};
}

/// 任务（§3.1 task）。
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get subject => integer()(); // TaskSubject index
  TextColumn get customSubject =>
      text().nullable()(); // 自定义科目名（subject==custom 时生效，M3 修订）
  BoolColumn get requiresFocus => boolean()();
  IntColumn get minFocusMin => integer().withDefault(const Constant(kValidFocusMinutes))(); // 任务最少专注分钟默认，对齐 WFD 门槛（§8.3）
  IntColumn get sunlightReward => integer().withDefault(const Constant(12))();
  TextColumn get repeatRule => text().nullable()();
  BoolColumn get isCustom => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 打卡（§3.1 check_in）。M4（v6）新增 5 列，承载家长核销流水。
class CheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get completedAt => dateTime()();
  TextColumn get sessionId => text().nullable()();
  BoolColumn get isPerfectDay => boolean()();
  IntColumn get status =>
      integer().withDefault(const Constant(0))(); // CheckInStatus index（0=verified）
  RealColumn get sunlightGross =>
      real().withDefault(const Constant(0.0))(); // 应发（含完美日系数）
  RealColumn get sunlightGranted =>
      real().withDefault(const Constant(0.0))(); // 实际入账；pending 时为 0
  DateTimeColumn get resolvedAt => dateTime().nullable()(); // 家长处理时间
  TextColumn get parentNote => text().nullable()(); // 驳回理由

  @override
  Set<Column> get primaryKey => {id};
}

/// 冷却计数（§3.1 cooldown_counter）。
class CooldownCounters extends Table {
  TextColumn get templateId => text()();
  IntColumn get period => integer()(); // CooldownPeriod index
  IntColumn get usedCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {templateId, period};
}

/// 埋点（§3.1 tracking_event）。
class TrackingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get name =>
      text().withDefault(const Constant(''))(); // 事件名（供查询/导出）
  IntColumn get type => integer()(); // TrackingType index
  DateTimeColumn get ts => dateTime()();
  TextColumn get payload => text()(); // JSON

  @override
  Set<Column> get primaryKey => {id};
}
