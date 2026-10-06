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
  // 2026-09-29 玄参拍板：花园氛围音**默认开启**（此前默认 false，且代码从未把设置
  // 接到音频服务 → 花园 BGM 从来没响过）。存量库由 v13 迁移把该列翻为 1。
  BoolColumn get bgmOn => boolean().withDefault(const Constant(true))();
  BoolColumn get detectionOn => boolean().withDefault(const Constant(true))();
  IntColumn get autoConfirmSingleHigh => integer().withDefault(const Constant(kAutoApproveMaxCostHigh))();
  IntColumn get autoConfirmSingleLow => integer().withDefault(const Constant(kAutoApproveMaxCostLow))();
  RealColumn get autoConfirmMonthlyPct => real().withDefault(const Constant(kAutoApprovePoolRatio))();
  RealColumn get currencyRate => real().withDefault(const Constant(kAutoApprovePoolRatio))();
  BoolColumn get themeDark => boolean().withDefault(const Constant(false))();
  BoolColumn get autonomousMode => boolean().withDefault(const Constant(false))();
  IntColumn get gardenPotCapacity =>
      integer().withDefault(const Constant(kGardenPotCapacityDefault))(); // 花园花盆容量（M3 §3.1）

  // ── v15 新增：C28 少儿护眼休息（玄参 2026-10-04 拍板，口径裁定表 v1 C28 §4）────
  // 三项家长端配置，均为「带默认值」的 ALTER TABLE ADD COLUMN（老库经 v15 迁移幂等补列，
  // 历史行取默认值，见 `app_database.dart` 的 ⑮ 段与 `migration_v14_to_v15_test.dart`）。
  // 护眼**时长**（固定 60 秒）刻意不落列：它是护眼有效性区间、家长端不设（玄参拍板）。
  BoolColumn get eyeCareEnabled =>
      boolean().withDefault(const Constant(kEyeCareEnabledDefault))();
  IntColumn get eyeCareIntervalMin =>
      integer().withDefault(const Constant(kEyeCareIntervalMinDefault))();
  BoolColumn get eyeCareSkipAllowed =>
      boolean().withDefault(const Constant(kEyeCareSkipAllowedDefault))();

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
  IntColumn get bloomCount =>
      integer().withDefault(const Constant(0))(); // 累计盛开次数（成株后循环玩法；v10 新增）
  IntColumn get mood => integer().withDefault(const Constant(0))(); // PlantMood index

  // ── v14 新增：花园干扰物（杂草 / 害虫，玄参 2026-09-30 拍板，口径 C26）──────
  // 存「出现当天零点」而非时刻：口径是「每天发生一次、当天有效、次日自动消失」，
  // 零点判等即天然保证跨天失效（次日零点 ≠ 今日零点 → 自动过期），不需要额外清理任务。
  DateTimeColumn get weedAt =>
      dateTime().nullable()(); // 杂草出现当天零点；null = 无杂草
  DateTimeColumn get pestAt =>
      dateTime().nullable()(); // 害虫出现当天零点；null = 无害虫
  DateTimeColumn get weedPestRollDay =>
      dateTime().nullable()(); // 「杂草/害虫每日 roll」已执行的当天零点（幂等基准）

  // ── v16 新增：铲除返还（C29，玄参 2026-10-05 拍板）───────────────────────
  // 种下时即定好的「铲除返还阳光数」：普通 150（300×50%）/ 精英 250（500×50%）；
  // 向日葵免费首株 / 历史行（v16 前种下）为 0 = 铲除不返还（防「免费种→铲→循环刷阳光」）。
  // 不返还培养（浇水/施肥）消耗；死亡株按「死亡全损」口径铲除返还 0（领域层判定）。
  IntColumn get shovelRefund =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 精品碎片账户余额（成株后循环玩法 Batch 1，v10 新增）。
///
/// 单例行（镜像 [Settings] 模式，id 固定 = 1）：精品碎片为玩家级货币，
/// 仅由开花奖励掉落（瞬间 / 花开 48h 后），集齐阈值（8）片可在花园页**手动选择**
/// 解锁 1 个精品物种（变更 B：不再自动解锁）。
@DataClassName('PremiumFragmentRow')
class PremiumFragments extends Table {
  IntColumn get id => integer()(); // 单例行主键，固定 = 1
  IntColumn get balance =>
      integer().withDefault(const Constant(0))(); // 当前持有碎片数

  @override
  Set<Column> get primaryKey => {id};
}

/// 第二段（花开后掉落）待收集奖励队列（成株后循环玩法 Batch 1，v10 新增；
/// v12 增 3 列「掉落即定奖」内容）。
///
/// 开花瞬间写入一条，`due_at = bloomed_at + 48h`；到期后由小朋友在花园页花盆旁
/// **手动点击收集**（变更 A）；若花谢 / 枯萎前未收集则 `tickAll` 自动兜底发放。
/// 领取后置 claimed = 1（每株仅发一次）。
///
/// v12（玄参 2026-09-27「掉落即定奖」）：新增 `reward_sunlight / reward_fragments /
/// reward_species_id` 三列，登记时当场 roll 并落库，结算时照单发放；UI 依据三列渲染头顶图标。
/// 历史行三列为零值哨兵 `0/0/null`（= 未预先定奖），结算时退回现场 roll 并回写。
@DataClassName('PendingBloomRewardRow')
class PendingBloomRewards extends Table {
  TextColumn get id => text()(); // 主键（uuid）
  TextColumn get plantId => text()(); // 所属植物 id
  DateTimeColumn get dueAt => dateTime()(); // 应发放（可收集）时刻
  TextColumn get rewardKind => text()(); // 档位标识：'normal' / 'premium'
  BoolColumn get claimed => boolean().withDefault(const Constant(false))();

  // ── v12 新增：掉落即定奖的奖励内容（零值哨兵 0/0/null = 未预先定奖）──────────
  IntColumn get rewardSunlight =>
      integer().withDefault(const Constant(0))(); // 预先定好的入账阳光
  IntColumn get rewardFragments =>
      integer().withDefault(const Constant(0))(); // 预先定好的植物碎片片数
  TextColumn get rewardSpeciesId =>
      text().nullable()(); // 预先定好的掉落种子物种 id（null = 无）

  @override
  Set<Column> get primaryKey => {id};
}

/// 已解锁物种记账（成株后循环玩法 Batch 1，v10 新增；图鉴 Batch 2 读它）。
///
/// 物种种子 / 碎片解锁均写入本表；`species_id` 复用植物物种种子（`plant_seed.dart`）的 id。
@DataClassName('UnlockedSpeciesRow')
class UnlockedSpecies extends Table {
  TextColumn get speciesId => text()();

  @override
  Set<Column> get primaryKey => {speciesId};
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
  IntColumn get contentCategory =>
      integer().withDefault(const Constant(0))(); // RewardContentCategory index（0=other 历史行安全默认）

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
  IntColumn get category =>
      integer().withDefault(const Constant(0))(); // TaskCategory index（0=other 历史行安全默认）

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
