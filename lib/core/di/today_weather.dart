/// 今日天气的**同源快照**与页面唯一入口（A3 · 测试接缝，设计 §13）。
///
/// ## 为什么需要这个文件（要防的 bug）
/// A3 之前，花园页在 **5 个地方各自 `DateTime.now()`**：
///   · `_reload` 里的 `WeatherSystem.ofDay(now)` / `dayKey(now)`；
///   · `_shelterRefTypeToday`（点按钮那一刻算「今天该搭哪种棚」）；
///   · `buyShelter(DateTime.now())`（确认弹窗之后写账本那一刻）；
///   · `batchNoneWaterMessage(day: ofDay(now))`；
///   · 首帧的 `WeatherSystem.ofDay(DateTime.now())`。
///
/// 每一处独立读钟，就多一条「跨零点错位」的路径：最狠的一条是
/// **确认卡上写「遮阳棚」、账本记成次日的「遮雨棚」**（卡片在 T1 读钟、账本在 T2
/// 读钟，中间隔着一整个弹窗交互）。
///
/// ## 为什么是**一个**值对象而不是三个 provider
/// 拆成 `weatherProvider` / `dayKeyProvider` / `clockProvider` 之后，每多一个 provider
/// 就多一次 `DateTime.now()` —— 跨零点时 `day` 与 `dayKey` 可能分属两天，
/// 于是「今天该搭遮雨棚」却去查前一天的道具账本 ⇒ 条幅恒 `todo`。
/// 本类把三者由**同一个 `now`** 派生，错位在类型层面就不可能发生。
///
/// ## 测试接缝
/// 真页面用例的日型原先由「跑测试那天」决定（`_realGardenPage` 没有日期参数），
/// 极端日约 20% 的日历天上会让天气胶囊相关断言整片变红。现在测试可以
/// `todayWeatherProvider.overrideWithValue(...)` 把日型钉死，断言内容一行都不用改。
///
/// ⚠️ 钉死日期**必须先探针确认日型**（`WeatherSystem.ofDay` 是纯函数，但「某月某日
/// 是哪一种天气」只能实测打印，不许猜）：猜错等于把「随日历变」换成「随记忆变」。
library today_weather;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';

/// 今日天气的**同源快照**：`day` / `dayKey` / `observedAt` 全部由同一个 `now` 派生。
class TodayWeather {
  /// 构造：三个字段必须来自**同一瞬间**（见类注释）。
  const TodayWeather({
    required this.day,
    required this.dayKey,
    required this.observedAt,
  });

  /// 今天的天型 + 乘数 + 额度（`WeatherSystem.ofDay(now)`）。
  final WeatherDay day;

  /// 今天的自然日键 `'yyyy-MM-dd'`（与 [day] 同一瞬间；账本按日查询一律用它）。
  final String dayKey;

  /// 取样时刻（写账本 / 传 service 一律用它，不许再 `DateTime.now()`）。
  final DateTime observedAt;

  /// 调试用：`TodayWeather(2026-11-05, drought)`。
  @override
  String toString() =>
      'TodayWeather($dayKey, ${day.kind.name}, observedAt=$observedAt)';
}

/// 今日天气 provider —— **本仓唯一读天气挂钟的地方**。
///
/// 消费约定（花园页 A3 起）：
///  · 页面 `build()` **顶层** `ref.watch` 一次，闭包内用外层捕获的变量
///    （不许写进 `LayoutBuilder` 的 builder 回调 —— 那是布局期注册监听）；
///  · 回调里用 `ref.read` 取一次，并**透传给需要时间戳的下游方法**
///    （跨一个确认弹窗也不能读第二次钟）；
///  · 跨零点刷新：`onTabRefreshRequested()` 里先 `ref.invalidate(todayWeatherProvider)`
///    再 `_reload()`（`Provider` 会缓存，不 invalidate 就永远停在首次取值）。
final Provider<TodayWeather> todayWeatherProvider = Provider<TodayWeather>((ref) {
  final DateTime now = DateTime.now();
  // 调试 override（第五批，玄参「调试面板里面没有天气的调试按钮」）：
  // 非空 = 显示的日型换成 [WeatherSystem.ofKind]（参数表既有单点，不许手搓
  // WeatherDay 字段）；`dayKey` / `observedAt` 仍来自**真实 now** ——
  // 买棚等账本口径（dayKey / 时间戳）永不因调试被带歪。
  // watch 而非 read：override 变化 ⇒ 本 provider 重算 ⇒ 页面 / 状态灯 /
  // 对话框全链路自动刷新，无需手动 invalidate。
  final WeatherKind? override = ref.watch(debugWeatherOverrideProvider);
  return TodayWeather(
    day: override == null
        ? WeatherSystem.ofDay(now)
        : WeatherSystem.ofKind(override),
    dayKey: WeatherSystem.dayKey(now),
    observedAt: now,
  );
});

/// 调试**天气日型 override**（第五批 2026-11-07，玄参拍板）。
///
///  · **仅花期调试面板（BloomDebugPanel）会写它**：release 构建调试面板整块
///    不出现（`shouldShowDebugUi` 守卫）⇒ 本 provider **无写入口、恒 null**，
///    生产用户永远走到上面的 `WeatherSystem.ofDay(now)` 真实分支；
///  · `null` = 跟随真实日期（默认）；非空 = 换「**本快照的日型**」——
///    状态灯 / 对话框 / 明日预告等展示层，**以及**买棚的落账 refType
///    （第六批 2026-11-07「买棚后不出现绿对勾」：按钮显示 / 落账 refType /
///    done 判定三者必须同源，全部取本快照 `day.kind`）；
///    `dayKey` / `observedAt` 仍来自真实 `now` —— **账本日期 / 时间戳口径
///    永不乱**（A3 §13 同源纪律不被调试破坏；跨天后 override 关闭自然回到
///    真实判定）；
///  · 测试接缝：widget 测试不改 `todayWeatherProvider`（保持生产装配），
///    直接写本 provider 驱动全链路（badge / 对话框 / 账本）。
final StateProvider<WeatherKind?> debugWeatherOverrideProvider =
    StateProvider<WeatherKind?>((StateProviderRef<WeatherKind?> ref) => null);
