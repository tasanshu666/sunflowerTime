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
///  · 雨水代劳 [WeatherDay.rainWaterBonusPp]：**收益项**，由日结侧在暴雨日另加，
///    §5.4 的基准口径不含它（含了会对不上表）；
///  · 进度 clamp（P1：`progress.clamp(0.0, 1.0)`）；
///  · 「只罚已关门的日子」（P2）与游标选择（P3，用既有 `stageStartedAt`）；
///  · 复开花（`kRebloomAutoProgressPerDay` 那条速率线）不经过本层。
library weather_growth_math;

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
