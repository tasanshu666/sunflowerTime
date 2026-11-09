/// 花园守卫「当日状态」的持久化抽象（**接口层**：零 flutter / 零插件 / 可 `dart test` 直跑）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §7.2（存储方案）。
///
/// ## 只有三个方法（不要加）
/// `read` / `write` / `clear` 已经把「一天一条存档」说完：
///  · 能量消耗点数、当日小偷、落骰结果、领取状态、当前 buff **全部**在
///    `GuardDayState` 一个 JSON 里（`dayKey` 是幂等唯一真源）；
///  · 阳光 / 被偷 / 付费走既有阳光账本，植物进度走 `plants` 表 —— 本接口
///    **只装账本与进度表装不下的那部分**。
///
/// ## 🔴 为什么 read / write 都必须带 childId
/// `SharedPreferences` 是**设备级**存储，而植物 / 专注 / 阳光数据是 **childId 级**。
/// 键名不带 childId 会直接产生两类串号事故：
///  · 「A 的小偷出现在 B 的今日页」（B 还没生成，却看到别人家的贼）；
///  · 「A 的浇水券被 B 用掉」（B 一键浇水时白拿 A 的减免）。
/// 故实现一律拼 `kGuardDayStatePrefPrefix + childId`（见 `GuardStatePrefsStore.keyOf`）。
///
/// ## 🔴 read 的口径：返回**存档原样**，它可能属于过去某一天
/// （这一条与「自动重置成今天」相反，请勿"优化"，理由如下）
///
/// `read` 只有在「从来没写过 / 存档读不出来」时才返回 `GuardDayState.empty(今天)`；
/// 若存档的 `dayKey != 今天`，**原样返回那条旧存档**（且不删键、不改写）。
///
/// 因为 `GuardService.expire()`（跨天结算）**必须**看到昨天那条存档才能算账，
/// 而它需要的三样东西**无法从账本或纯函数反推**：
///  1. `status`：昨天是「已领取 / 免罚 / 进了战斗但没点收下」中的哪一种 ——
///     决定「不计损失」「当天免罚」「补发必得阳光」三条互斥分支；
///  2. `growthStolen`：昨天**哪几盆**各被偷了多少 pp —— 啃叶虫只挑 1 株，
///     「挑哪一株」是服务层的确定性挑株结果，不在纯函数里；
///  3. `sunStolen` / `winSun`：`resolve()` 有「**只算不记账**」的硬约束
///     （结算与领取必须分离，否则跳过动画 = 免费领奖），所以它的产出**只**存在
///     于这条存档里。
///
/// 若 `read` 自行把过期存档换成空白当日状态，上述数据在**第一次读取**时即永久
/// 丢失 ⇒ `guard_stolen` 这一行永远发不出来（对账缺口），而「被偷了却没扣」
/// 是静默漏洞，比多发一条账本更难发现。
///
/// ⇒ **「今日视图」的归一化放在 `GuardService.todayState()`**（唯一消费方）：
///   它负责「存档 dayKey != 今天 ⇒ 按空白当日状态展示」，并由调用方先调
///   `expire()` 结算。两个职责因此各自只有一处实现。
library guard_state_store;

import 'package:sunflower_time/domain/entities/guard_day_state.dart';

/// 花园守卫「当日状态」存储（实现见 `data/local/guard_state_prefs_store.dart`）。
abstract class GuardStateStore {
  /// 读取 [childId] 的当日状态存档。
  ///
  /// · 没有存档 / 存档损坏 → `GuardDayState.empty(<今天>)`（**绝不抛异常**：
  ///   一份坏掉的 prefs 不该让孩子打不开今日页）；
  /// · 存档属于过去某天 → **原样返回那条旧存档**（见文件头「read 的口径」，
  ///   `expire()` 需要它来结算昨天的损失）。
  Future<GuardDayState> read(String childId);

  /// 覆盖写 [childId] 的当日状态存档（一天一条，整天只有这一条）。
  ///
  /// 只由领域服务调用（`resolve` / `claim` / `GuardVoucherService.recordConsumed`），
  /// 页面**不得**直接写 —— 状态机与账本必须同源推进。
  Future<void> write(String childId, GuardDayState state);

  /// 删除 [childId] 的当日状态存档（跨天结算完成后由 `expire()` 调用）。
  ///
  /// ⚠️ 只删本玩法自己的键；「一键删除全部本地数据」走
  /// `DataManagementService.clearAll` 的 `prefs.clear()`，天然覆盖本键。
  Future<void> clear(String childId);
}
