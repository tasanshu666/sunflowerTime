/// 花园天气系统 · **成长数学纯计算层**：天气乘数怎么进「进度」这条账。
///
/// ## 定位（T02 阶段一）
/// `docs/天气系统_最终方案.md` §5.1 / §5.4 / §8.1 的计算口径落点，**只做纯计算**：
/// 无 IO、无状态、无 `Random`、不读账本、不碰 `_advanceGrowth`（那是 T02 阶段二
/// 的接线活）。三个函数各管一段：
///  · [segmentProgress]：一段自然时长（通常是 24h）的自然生长增量，乘当日 `g`；
///  · [careProgress]：一次浇水 / 施肥的即时增量，乘当日 `w` / `f`（§11.2 改法 1：
///    `w`/`f` 在**即时加值侧**生效，不进日结循环）；
///  · [penaltyOf]：极端天气的惩罚（B 口径，每个未做动作各罚 1pp）。
///
/// ## 单位约定
///  · 进度一律用 **0..1 的阶段分数**（与 `Plant.growthProgress` 同口径）；
///    1pp = 0.01。文档 §5.4 的「pp/天」= 本层返回值 × 100。
///  · 首花总进度 = 300pp（seed→sprout→adult 三阶段 × 100pp）。
///
/// ## 对账（§5.4 四档表的复现口径，D 层测试钉死）
/// 日均进度 = Σ P(d) × [ 24h·g(d)/growthHoursPerStage + 水次数(d)·base水·w(d)
///   + 肥次数(d)·base肥·f(d) ]，其中**次数按当日额度截断**（`min(方案次数, 额度)`）。
/// 🔴 关键：次数与乘数**必须按日相关**（`E[次数×w]`），**不能**拆成 `E[次数]×E[w]`
/// —— 暴雨日浇水次数为 0 且 `w` 也低，拆开算会把两者的相关性行丢了
/// （3 水 1 肥：相关口径 2.992pp vs 拆开 3.21pp，差出 0.28 天，见
/// `test/m3/weather_growth_math_test.dart` D 层）。
///
/// ## 不在本层口径内（调用方处理）
///  · 进度 clamp（P1：`progress.clamp(0.0, 1.0)`）；
///  · 「只罚已关门的日子」（P2）与游标选择（P3，用既有 `stageStartedAt`）；
///  · 复开花（`kRebloomAutoProgressPerDay` 那条速率线）在**日结**里不经过本层的
///    [segmentProgress]，但 **ETA（[naturalDailyProgress]）需要它** —— 见下条。
///
/// ## A5 起本层新增的两个「展示口径」纯函数
/// [naturalDailyProgress] / [dailyEstimateProgress] 是**卡片「还要约 N 天长成」
/// 的唯一算式来源**（A5 · `docs/天气系统_A5_增量设计.md` §4.2/§4.4）。它们的定位
/// 与上面三个函数不同：前面三个是**日结实际怎么累加**，这两个是**「按今天这个天气、
/// 把当日额度做满」一天能推多少**（用于把人话天数算出来）。
///
/// 🔴 与 §5.4 基准口径的关系：§5.4 的日均表**不含** [WeatherDay.rainWaterBonusPp]
/// （那是 A4 才接进日结的收益项，`plant_growth_service.dart` 守卫内那一行）。
/// [dailyEstimateProgress] **含**它 —— 因为卡片要报的是**实现真值**（含代劳），
/// 不是 §5.4 的对账基准。两者差 `E[rainBonus] = 0.01 × 3% = 0.03pp/天`，对账时
/// 必须显式加回（`test/m3/weather_a5_eta_test.dart` 的 V1/V2 就是这么断的）。
library weather_growth_math;

import 'dart:math' as math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';

/// 天气 × 成长数学（**纯静态 / 无状态**）。
class WeatherGrowthMath {
  /// 工具类，禁止实例化。
  WeatherGrowthMath._();

  /// 一段自然时长内的**自然生长**增量（progress 单位，0..1 阶段分数）。
  ///
  /// 即 `_advanceGrowth` 的 `segHours / growthHoursPerStage` 换算，乘上当日 `g`：
  /// 普通 240h 阶段在 `g=1` 时 24h = 0.10（10pp/天）；精品 480h = 0.05（5pp/天）。
  ///
  /// ⚠️ 不乘 [kPlantAutoGrowthScale]：该常量当前为 1.0（2026-09-22 起自动成长按
  /// 真实时长推进），乘了也是 ×1；**若它将来≠1，本函数必须同步**（接线在阶段二，
  /// 到时以 `_advanceGrowth` 的实际算式为准对齐）。
  static double segmentProgress({
    required double segHours,
    required WeatherDay day,
    required double growthHoursPerStage,
  }) {
    return segHours * day.growthFactor / growthHoursPerStage;
  }

  /// **无天气的自然日速率**（progress 单位 / 天，不含 `g`）——A5 · ETA 专用。
  ///
  /// 两条速率线**必须在这里分岔**（A5 §4.2 / D5）：这是本仓「复开花」唯一的
  /// 鉴别点，漏了它就会把复花当成首花算。
  ///
  ///  · 首花（`bloomCount == 0`）：`24 / growthHoursPerStage × kPlantAutoGrowthScale`
  ///    —— 与日结 `_advanceGrowth` 的 `segmentProgress(segHours: 24)` 同源
  ///    （`segmentProgress(24) = 24 × g / T`，故此处不带 `g`）；
  ///  · 复开花（`bloomCount >= 1`）：`kRebloomAutoProgressPerDay ÷ (isPremium ? 1.5 : 1)`
  ///    —— 与日结里 `segHours × (kRebloomAutoProgressPerDay / 24) / premiumDiv × g`
  ///    的 24h 值**完全一致**。注意复花**没有** `growthHoursPerStage` 的概念，
  ///    所以它**不经过** [segmentProgress]（那是首花的算式），只在这里对应。
  ///
  /// ⚠️ 为什么 `bloomCount >= 1` 而不是 `status == bloomed`：本仓「复开花」= 花谢后
  /// 从 [kBloomWiltProgressFloor] 重新爬满的**整段 `growing` 期**（花谢时
  /// `_applyBloomCycle` 把 status 改回 `growing`），不是盛开那 3~4.5 天。用 status
  /// 判会把整段复花期判成首花，正是 D5 的病灶。
  ///
  /// `growthHoursPerStage <= 0`（脏数据）时返回 0：调用方据此走「只报百分比」兜底，
  /// 绝不显示 `∞ 天`。
  static double naturalDailyProgress({
    required double growthHoursPerStage,
    required int bloomCount,
    required bool isPremium,
  }) {
    if (bloomCount >= 1) {
      final double premiumDiv =
          isPremium ? kRebloomPremiumCycleMultiplier : 1.0;
      return kRebloomAutoProgressPerDay / premiumDiv;
    }
    if (growthHoursPerStage <= 0) return 0.0;
    return 24.0 / growthHoursPerStage * kPlantAutoGrowthScale;
  }

  /// **按今天这个天气、把当日额度做满**的日推进量（progress 单位 / 天，含雨水代劳）。
  ///
  /// 这是卡片「每天按时养护，还需约 N 天长成」的**唯一算式**（A5 §4.2）。拆三项：
  ///  · 自然项 = [naturalGainPerDay] × 当日 `g`；
  ///  · 养护项 = **当日有效额度**次 × 单次增量（已含复花/精品修正）× 当日 `w`/`f`；
  ///  · 雨水代劳 = 当日 [WeatherDay.rainWaterBonusPp]（暴雨 1pp，其余 0）。
  ///
  /// 🔴 **次数取「当日额度」而不是「今天已做几次」**（A5 §4.2 取舍①，有意偏离
  /// 方案 §10 原文）：① 文案已写「每天按时养护」，两者自相矛盾；② 早晨 8 点
  /// 「已浇水 0 次」会让干旱日只剩自然项 2pp/天 ⇒ `50pp` 报 25 天（满载是 4 天，
  /// 差 6.4 倍）；③ 满载口径下「浇了水 ⇒ 进度↑ ⇒ N 不增」，一天内单调不增。
  ///
  /// 复用 [careProgress] 而不是自己乘 `w`/`f`：乘数语义单点，将来 `w/F` 变了不会
  /// 只改一处（A4 `resolveWaterGate` 同款纪律）。
  ///
  /// 返回值恒 `≥ 0`（三项都非负），**不需要 clamp**；调用方用 `daily <= 0` 兜底
  /// 判「速率非法」。
  static double dailyEstimateProgress({
    required WeatherDay day,
    required double naturalGainPerDay,
    required double waterGainPerUse,
    required double fertilizeGainPerUse,
  }) {
    // A4 纪律：额度必须截断（小雨 1 / 暴雨 0），否则雨天会多算 2~3 次浇水。
    final int waterUses = math.min(kPlantWaterMaxPerDay, day.waterQuota);
    final int fertilizeUses =
        math.min(kPlantFertilizeMaxPerDay, day.fertilizeQuota);
    return naturalGainPerDay * day.growthFactor +
        waterUses *
            careProgress(
              baseGain: waterGainPerUse,
              day: day,
              isWater: true,
            ) +
        fertilizeUses *
            careProgress(
              baseGain: fertilizeGainPerUse,
              day: day,
              isWater: false,
            ) +
        // A4 已把它接进日结（守卫内每天一次），ETA 不加上它就会在暴雨日多报 1~2 天。
        day.rainWaterBonusPp;
  }

  /// 一次养护动作（浇水 / 施肥共用）的**即时**进度增量。
  ///
  /// [baseGain] 取 `kPlantWaterProgressGain`（1pp）或 `kPlantFertilizeProgressGain`
  /// （3pp）；[isWater] 决定乘当日 `w` 还是 `f`。
  ///
  /// ⚠️ 复开花（`bloomCount >= 1`）另有独立基数（`kRebloom*ProgressGain`，精品再
  /// ÷1.5），**由调用方先算好 baseGain 再进来**——本层只管「乘天气因子」这一步，
  /// 不感知花的生命周期，避免把两条速率线搅在一起。
  static double careProgress({
    required double baseGain,
    required WeatherDay day,
    required bool isWater,
  }) {
    final double factor = isWater ? day.waterFactor : day.fertilizeFactor;
    return baseGain * factor;
  }

  /// 极端天气惩罚（**B 口径**：每个未做动作各罚 [kWeatherPenaltyPerMissingItem]）。
  ///
  /// 返回值 **≤ 0**（0 = 无惩罚，负数 = 扣减量），调用方直接
  /// `progress += penaltyOf(...)` 后自行 `clamp(0.0, 1.0)`（P1：进度不为负，
  /// 本层不 clamp、不取绝对值）。
  ///
  /// 判据（§5.1 规则表，逐项对应）：
  ///  · 干旱：`!watered` −1pp（当天该盆浇水记录 ≥1 即算完成，做 1 次就算数）、
  ///          `!hasShelter` −1pp（[WeatherKind.drought] 对应 `shelter_shade`）；
  ///  · 暴雨：`!fertilized` −1pp、`!hasShelter` −1pp（`shelter_rain`）；
  ///  · 大风 / 极寒：只看棚（`shelter_wind` / `shelter_warm`）；
  ///  · 温和 5 种：恒 0（不问任何参数）。
  ///
  /// [hasShelter] 的判定（阶段二接线）：当日账本是否已有
  /// `countByRefTypeAndRefIdOnDay(day.shelterRefType, kWeatherShelterRefId, day) > 0`；
  /// [watered] / [fertilized] 用 `plant_water` / `plant_fertilize` + `refId=植物id`
  /// 同法查「当天 ≥1 条」。
  ///
  /// 🔴 Q2 后门（§5.6，**本版不实现**）：复开花**不减半**。若将来玄参要减半，
  /// 在返回前乘 `bloomCount >= 1 ? 0.5 : 1.0` 即可——为此需要新增入参，届时走裁定。
  static double penaltyOf({
    required WeatherDay day,
    required bool hasShelter,
    required bool watered,
    required bool fertilized,
  }) {
    final WeatherKind kind = day.kind;
    if (kind.isMild) {
      return 0.0; // 温和 5 种：无强制动作、无惩罚
    }
    double penalty = 0.0;
    if (kind == WeatherKind.drought) {
      // 干旱：浇水 ≥1 次 + 遮阳棚，缺一罚一。
      if (!watered) penalty -= kWeatherPenaltyPerMissingItem;
      if (!hasShelter) penalty -= kWeatherPenaltyPerMissingItem;
    } else if (kind == WeatherKind.rainstorm) {
      // 暴雨：施肥 ≥1 次 + 遮雨棚（浇水额度为 0，浇水与否不在判据里）。
      if (!fertilized) penalty -= kWeatherPenaltyPerMissingItem;
      if (!hasShelter) penalty -= kWeatherPenaltyPerMissingItem;
    } else {
      // 大风 / 极寒：只看棚（挡风板 / 保温棚）。
      if (!hasShelter) penalty -= kWeatherPenaltyPerMissingItem;
    }
    return penalty;
  }
}
