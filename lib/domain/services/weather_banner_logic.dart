/// 天气条幅的**三态判定纯函数**（A3 · 顶部天气条幅，设计 §2）。
///
/// ## 一句话
/// `resolveWeatherBanner(...)` = 「今天这个日型，条幅该不该出、出了是 `todo` 还是 `done`」。
///
/// ## 为什么必须是纯函数
/// 判定涉及「4 种极端 × 2 种动作判据 × 道具 × 会话缓存」的组合，只要它住在 widget 里，
/// 就只能靠泵页面碰运气；放进纯函数后 9 种日型 × 4 组笛卡尔积可以在单测里**穷举**，
/// 且页面只剩一件事：把已经算好的事实递进来（零 IO、零时钟、零 context）。
///
/// ## 判据顺序（写死，无 default 分支）
/// ```
/// (1) kind.isMild                      => none   （5 种温和日，不问任何入参）
/// (2) sessionDone                      => done   （本会话已置上，见设计 §3.3）
/// (3) shelterBoughtToday               => done   （第八批：买棚即完成）
/// (4) 其余                             => todo
/// ```
///
/// ## 完成判据（第八批 2026-11-07 玄参拍板：**买棚即 done**）
/// | 日型 | 判据 | 道具 |
/// |---|---|---|
/// | `drought` | 无动作 | `shelter_shade` |
/// | `rainstorm` | 无动作 | `shelter_rain` |
/// | `wind` | 无动作 | `shelter_wind` |
/// | `cold` | 无动作 | `shelter_warm` |
///
/// 第八批起 4 种极端日**统一只看棚**：干旱去掉「浇水 ≥ 1」、暴雨去掉「施肥 ≥ 1」
/// 门槛（浇水 / 施肥的**额度**与天气影响照旧，只是不再作为 done 条件）。
/// `anyWateredToday` / `anyFertilizedToday` 已不参与判定 —— 参数保留（调用点
/// 不拆装），实现**根本不读**。
library weather_banner_logic;

import 'package:sunflower_time/domain/services/weather_system.dart';

/// 条幅三态（设计 §9.2）。
///
/// · [none] = 今天不出条幅（5 种温和日）；
/// · [todo] = 出了但还没做齐（第八批起判据只剩道具：未买棚）；
/// · [done] = 已完成（`✓` + 一句完成语；买棚即 done）。
enum WeatherBannerMood {
  /// 不渲染条幅（温和日）。
  none,

  /// 待办（极端日，动作或道具未齐）。
  todo,

  /// 已完成（极端日，道具已买 —— 第八批起买棚即 done）。
  done,
}

/// 一次判定的完整结果（不可变值对象）。
///
/// UI **只读它**，不再自行从 `kind` / `_shelterBoughtToday` 推导任何东西 ——
/// 这样「三态判据」只有一个真源，测试也只需要拿这一个对象做断言。
class WeatherBannerState {
  /// 构造：三态 + 当日日型 + 该日型要求的道具 refType（温和日为 `null`）。
  const WeatherBannerState({
    required this.mood,
    required this.kind,
    required this.shelterRefType,
  });

  /// 三态。
  final WeatherBannerMood mood;

  /// 当日日型（条幅图标 / 文案都按它取）。
  final WeatherKind kind;

  /// 该日型对应的道具 refType；温和日为 `null`。
  final String? shelterRefType;

  /// 是否渲染条幅（`mood != none`）。
  bool get visible => mood != WeatherBannerMood.none;

  /// 调试用（纯 ASCII）：`WeatherBannerState(todo, drought, shelter_shade)`。
  @override
  String toString() =>
      'WeatherBannerState(${mood.name}, ${kind.name}, $shelterRefType)';
}

/// 园级判定：**道具已买 ⇒ `done`**（第八批 2026-11-07 玄参拍板「买棚即完成」）。
///
/// 🔴 全部入参都是**已算好的事实**（页面从账本 / 快照读出）：
///  · [day]：`todayWeatherProvider` 的 `day`（不是现算的天气）；
///  · [anyWateredToday]：`careQuotas` 里**任一株** `waterUsedToday >= 1`
///    （第八批起**不参与判定**，参数保留 —— 调用点不拆装）；
///  · [anyFertilizedToday]：同上，`fertilizeUsedToday >= 1`（不参与判定）；
///  · [shelterBoughtToday]：`countByRefTypeAndRefIdOnDay(refType, 'garden', dayKey) > 0`；
///  · [sessionDone]：本会话内存 Set 命中当日日键（`done` 的加速层，不是事实源）。
///
/// 幂等：事实不变时重复调用结果恒定（账本 append-only，重算天然幂等，§3.2）。
WeatherBannerState resolveWeatherBanner({
  required WeatherDay day,
  required bool anyWateredToday,
  required bool anyFertilizedToday,
  required bool shelterBoughtToday,
  required bool sessionDone,
}) {
  final WeatherKind kind = day.kind;

  // (1) 温和日：**不问任何入参**（传什么都不得变成 todo / done）。
  if (kind.isMild) {
    return WeatherBannerState(
      mood: WeatherBannerMood.none,
      kind: kind,
      shelterRefType: null,
    );
  }

  // (2) 本会话已置上完成态（先于账本判据：完成瞬间立刻切态、且不因异步查询闪回）。
  // 🔴 只对极端日生效 —— 温和日已在上一步 return，内存 Set 点不亮温和日。
  if (sessionDone) {
    return WeatherBannerState(
      mood: WeatherBannerMood.done,
      kind: kind,
      shelterRefType: kind.shelterRefType,
    );
  }

  // (3) 道具已买 ⇒ done（第八批：买棚即完成，4 种极端日统一只看棚；
  //     干旱「浇水 ≥ 1」/ 暴雨「施肥 ≥ 1」门槛已删，动作入参根本不读）。
  if (shelterBoughtToday) {
    return WeatherBannerState(
      mood: WeatherBannerMood.done,
      kind: kind,
      shelterRefType: kind.shelterRefType,
    );
  }

  // (4) 其余一律 todo（穷举完毕，无 default 分支）。
  return WeatherBannerState(
    mood: WeatherBannerMood.todo,
    kind: kind,
    shelterRefType: kind.shelterRefType,
  );
}
