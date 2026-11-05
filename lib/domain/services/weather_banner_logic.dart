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
/// (3) 动作齐 && shelterBoughtToday      => done
/// (4) 其余                             => todo
/// ```
///
/// ## 动作齐按日型（逐条对齐方案 §5.1 的规则表）
/// | 日型 | 判据 | 道具 |
/// |---|---|---|
/// | `drought` | 任一盆今日浇水 >= 1 次 | `shelter_shade` |
/// | `rainstorm` | 任一盆今日施肥 >= 1 次（暴雨浇水额度为 0，**不判浇水**） | `shelter_rain` |
/// | `wind` | 无动作 | `shelter_wind` |
/// | `cold` | 无动作 | `shelter_warm` |
///
/// 大风 / 极寒**不判动作**：它们的强制动作只有「买棚」一件事，故 `anyWateredToday` /
/// `anyFertilizedToday` 对它们**根本不读**（不是传 false）。
library weather_banner_logic;

import 'package:sunflower_time/domain/services/weather_system.dart';

/// 条幅三态（设计 §9.2）。
///
/// · [none] = 今天不出条幅（5 种温和日）；
/// · [todo] = 出了但还没做齐（动作 / 道具二者缺一）；
/// · [done] = 做齐了（`✓` + 一句完成语）。
enum WeatherBannerMood {
  /// 不渲染条幅（温和日）。
  none,

  /// 待办（极端日，动作或道具未齐）。
  todo,

  /// 已完成（极端日，动作齐 **且** 道具已买）。
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

/// 园级判定：**园内任意一盆**动作做齐 + 道具已买 ⇒ `done`（方案 §9.3）。
///
/// 🔴 全部入参都是**已算好的事实**（页面从账本 / 快照读出）：
///  · [day]：`todayWeatherProvider` 的 `day`（不是现算的天气）；
///  · [anyWateredToday]：`careQuotas` 里**任一株** `waterUsedToday >= 1`；
///  · [anyFertilizedToday]：同上，`fertilizeUsedToday >= 1`；
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

  // (3) 动作齐 **且** 道具已买 ⇒ done。
  if (_actionsComplete(
        kind: kind,
        anyWateredToday: anyWateredToday,
        anyFertilizedToday: anyFertilizedToday,
      ) &&
      shelterBoughtToday) {
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

/// 「动作齐」判据（按日型，见文件头的规则表）。
///
/// 🔴 大风 / 极寒返回 `true`（无动作要求）—— 它们的入参**根本不读**：
/// 写成「所有日型都要求动作齐」会让这两种日型**永远停在 todo**（变异点 M-A3-4）。
bool _actionsComplete({
  required WeatherKind kind,
  required bool anyWateredToday,
  required bool anyFertilizedToday,
}) {
  return switch (kind) {
    // 干旱：浇 1 次即算（方案 §9.3）。
    WeatherKind.drought => anyWateredToday,
    // 暴雨：浇水额度为 0（雨水代劳），强制动作是**施肥**，故不判浇水。
    WeatherKind.rainstorm => anyFertilizedToday,
    // 大风 / 极寒：只看棚，不看动作。
    WeatherKind.wind => true,
    WeatherKind.cold => true,
    // 5 种温和日：条幅不渲染，永远走不到这里（穷举兜底，保持 switch 无 default）。
    WeatherKind.sunny ||
    WeatherKind.breeze ||
    WeatherKind.cloudy ||
    WeatherKind.overcast ||
    WeatherKind.lightRain =>
      true,
  };
}
