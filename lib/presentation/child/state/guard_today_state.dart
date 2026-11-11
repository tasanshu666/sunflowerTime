/// 今日页「向日葵守卫」的**可监听只读模型** + 唯一状态容器（第三批）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §4（状态机）/ §8.1（今日页胶囊）。
///
/// ## 为什么必须是一个 provider（而不是页面里的几个 `setState` 字段）
/// 项目踩过 `_entTier` 用 `ref.read` 的坑：**买了会员界面不刷新**。守卫的当日状态
/// 有三个消费方（今日页胶囊、第四批的 buff chip、第四批的调试面板），只要有一处
/// 用 `read` 拿一次值，就会出现「领了奖 / 用了券，另一处还是旧的」。
/// ⇒ 全部消费方 `ref.watch(`[guardTodayProvider]`)`，写操作只改这一份实例，
///   并同时自增 `economyRevisionProvider`（既有跨页刷新总线，花园页也在听）。
///
/// ## 谁写这份状态
/// **只有** `ChildTodayPage`（`_refreshGuard` / 领取成功后）。其余地方一律只读。
/// 这样「状态机推进」与「账本推进」仍然只在 `GuardService` 里发生，本文件只是
/// **把服务层的返回值缓存成可监听的一份快照**，不做任何业务判断
/// （派生规则 [guardPillModeOf] 是纯函数，可单测）。
///
/// ## 🔴 硬约束：读守卫状态必须**有界超时**
/// 纯 widget 测试宿主里某些 DB 查询会 `await` 永不返回（不是抛错）。守卫链路一旦
/// 卡住，`_loading` 就永远为 true，整个今日页只剩转圈 —— 存量今日页测试会集体变红。
/// 故本文件给出 [kGuardTodayReadTimeout]，页面必须
/// `try/catch + .timeout(kGuardTodayReadTimeout)`，超时/异常 ⇒ 视同
/// [GuardPillMode.absent]（胶囊零占位，绝不阻塞今日页）。
library guard_today_state;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

/// 守卫链路（`expire() → resolve() → energyAvailable()`）的**整条链**超时。
///
/// 为什么是 600ms 而不是 200ms（[kChildProfileReadTimeout]）：那条链只有一个
/// prefs 读，而守卫链是「prefs + plants 表 + 账本 + 专注会话」四次 IO。单次 200ms
/// 会误伤真机冷启动（首次打开 sqlite 就常常超过 200ms），导致「今天是贼来了却
/// 显示零占位」这种静默漏判。
///
/// 但这仍然是**有界**的：超时后视同 [GuardPillMode.absent]，页面照常渲染。
const Duration kGuardTodayReadTimeout = Duration(milliseconds: 600);

/// 今日页守卫胶囊的 6 种展示态（PRD §4「胶囊 5 态」+ 零占位态）。
///
/// `absent` **不是** [GuardDayStatus] 的值：它由「今天没有贼 / 链路不可用」在
/// 展示层判定 —— 「今天没有守卫」这件事不需要落盘。
enum GuardPillMode {
  /// 零占位：**完全不渲染**（连空 `SizedBox` 都不插），今日页布局与无守卫时逐像素相同。
  absent,

  /// 待处理 · 有专注能量：点击**直接开战**（0 ☀，不弹确认卡）。
  pendingFree,

  /// 待处理 · 无能量但余额 ≥ [kGuardPayCost]：点击**先弹确认卡**，确认后才花 5 ☀。
  pendingPaid,

  /// 免罚档（`GuardDayStatus.short` 或「无能量且余额 < [kGuardFreeRideBalance]」）：
  /// 当天小小葵自己顶班，胶囊不可点。
  freeRide,

  /// 战斗中（动画回放期）：不可点。
  ///
  /// 开战前会经 [GuardService.markFighting] 把存档落成
  /// [GuardDayStatus.fighting]（页面**不直接写**存储，只调领域服务）：
  /// 孩子中途杀进程 / 闪退，次日 `expire()` 走 `fighting` 分支 —— **补发**
  /// 必得阳光、**不结算**损失，而不是把他当「压根没管」照罚。
  fighting,

  /// 已领取：不可点。
  claimed,
}

/// 由「当日状态 + 剩余能量 + 余额」派生胶囊态（**纯函数**，可单测）。
///
/// 判定顺序即优先级：先看有没有贼，再看存档状态，最后才按成本细分
/// `pending`。`short`（免罚档）优先于余额判定 —— 免罚是 `resolve()` 当场
/// 定死的（并把损失写成 0），余额后来变多也不该把胶囊变回可点。
GuardPillMode guardPillModeOf(
  GuardDayState state,
  int energyAvailable,
  double balance,
) {
  if (!state.hasThief) return GuardPillMode.absent;
  switch (state.status) {
    case GuardDayStatus.none:
      return GuardPillMode.absent;
    case GuardDayStatus.claimed:
      return GuardPillMode.claimed;
    case GuardDayStatus.fighting:
      return GuardPillMode.fighting;
    case GuardDayStatus.short:
      return GuardPillMode.freeRide;
    case GuardDayStatus.pending:
      if (energyAvailable >= kGuardEnergyPerFocus) {
        return GuardPillMode.pendingFree;
      }
      if (balance >= kGuardPayCost) return GuardPillMode.pendingPaid;
      return GuardPillMode.freeRide;
  }
}

/// 今日守卫的一份**不可变快照**（胶囊 / buff chip / 调试面板共用的唯一实例）。
class GuardTodayView {
  /// 胶囊展示态。
  final GuardPillMode mode;

  /// 当日状态（`mode == absent` 时是一条空白状态，`hasThief == false`）。
  final GuardDayState state;

  /// 判定时的剩余专注能量（免费 0..[kGuardEnergyDailyMaxFree]、
  /// 付费 0..[kGuardEnergyDailyMaxPremium]）。
  final int energyAvailable;

  /// 判定时的阳光余额。
  final double balance;

  /// 当前称号 perk（结算卡「券还能省 N」要按真实单价算；`null` = 未取到）。
  ///
  /// 🔴 可选：旧调用方 / 读 perk 失败时保持 `null`，[voucherSaving] 退回面值口径，
  /// 绝不因为读不到称号让胶囊或结算卡崩掉。
  final PlantPerk? perk;

  /// 当前权益档位（🔴 B13.8 能量档位制：免费 1 颗/天 / 会员 2 颗/天）。
  ///
  /// 由领域层单点给出（`GuardResolveResult.isPremium` / `GuardClaimOutcome.isPremium`）
  /// —— 表现层不得直接摸权益 provider（白名单守卫钉死）；场景卡据此把免费档
  /// 的第 2 颗能量点画成锁标。缺省 false（免费档），旧构造点零改动。
  final bool isPremium;

  const GuardTodayView({
    required this.mode,
    required this.state,
    required this.energyAvailable,
    required this.balance,
    this.perk,
    this.isPremium = false,
  });

  /// 没有守卫 / 链路不可用（超时、异常、全园无存活株）：**零占位**。
  const GuardTodayView.absent()
      : mode = GuardPillMode.absent,
        state = _absentState,
        energyAvailable = 0,
        balance = 0,
        perk = null,
        isPremium = false;

  /// `absent` 用的哨兵状态（`dayKey` 为空串 —— 永远不会被当成「今天」写回存储）。
  static const GuardDayState _absentState =
      GuardDayState(dayKey: '', status: GuardDayStatus.none);

  /// 由 `GuardService.resolve()` 的结果构造。
  ///
  /// 🔴 `needsExpire == true` ⇒ **视同没有守卫**：那意味着「昨天还有一条未结算的
  /// 存档」，此时 `result.state` / `result.thief` 说的是**昨天**的贼 —— 拿它上屏
  /// 等于让孩子看到昨天的贼、并且当天再点一次会覆盖掉昨天的损失（对账缺口）。
  factory GuardTodayView.fromResolve(
    GuardResolveResult result, {
    PlantPerk? perk,
  }) {
    if (result.needsExpire) return const GuardTodayView.absent();
    return GuardTodayView(
      mode: guardPillModeOf(
        result.state,
        result.energyAvailable,
        result.balance,
      ),
      state: result.state,
      energyAvailable: result.energyAvailable,
      balance: result.balance,
      perk: perk,
      isPremium: result.isPremium,
    );
  }

  /// 由 `GuardService.claim()` 的结果构造（成功 / 失败都适用）。
  ///
  /// 失败分支（余额不足等）`outcome.state` 就是原状态、账本未动 ⇒ 重新派生出的
  /// 胶囊态与实际一致（会落到 [GuardPillMode.freeRide]），不会「假装已领取」。
  factory GuardTodayView.fromClaim(
    GuardClaimOutcome outcome, {
    PlantPerk? perk,
  }) {
    return GuardTodayView(
      mode: guardPillModeOf(
        outcome.state,
        outcome.energyAvailable,
        outcome.balance,
      ),
      state: outcome.state,
      energyAvailable: outcome.energyAvailable,
      balance: outcome.balance,
      perk: perk,
      isPremium: outcome.isPremium,
    );
  }

  /// 不可变副本（战斗开始/结束时只切 [GuardPillMode]，状态本身不动）。
  GuardTodayView copyWith({
    GuardPillMode? mode,
    GuardDayState? state,
    int? energyAvailable,
    double? balance,
    PlantPerk? perk,
    bool? isPremium,
  }) {
    return GuardTodayView(
      mode: mode ?? this.mode,
      state: state ?? this.state,
      energyAvailable: energyAvailable ?? this.energyAvailable,
      balance: balance ?? this.balance,
      perk: perk ?? this.perk,
      isPremium: isPremium ?? this.isPremium,
    );
  }

  /// 胶囊是否要占位（`false` ⇒ 今日页**一项都不插**）。
  bool get isVisible => mode != GuardPillMode.absent;

  /// 胶囊可点（`pendingFree` / `pendingPaid` 两种）。
  bool get isActionable =>
      mode == GuardPillMode.pendingFree || mode == GuardPillMode.pendingPaid;

  /// 点击后是否需要**先弹确认卡**（= 要花阳光的那种）。
  bool get needsPayConfirm => mode == GuardPillMode.pendingPaid;

  /// 今天来的贼（`absent` 时为 `null`）。
  GuardThiefKind? get thief => state.thiefKind;

  /// 是否需要先看教学浮层（守卫战 v2 · B2）。
  ///
  /// ⚠️ **B7 起本 getter 不再驱动弹层**（玄参真机：「每天都要再看一遍」）。
  /// 教学改由**设备级 prefs** `kGuardTutorialSeenPrefKey` 判（永久一次），
  /// 见 `child_today_page.dart` 的 `_tutorialSeenInPrefs()`。
  /// 保留本 getter 只为「当日存档里那个字段还读得到」的向后兼容 ——
  /// `GuardDayState.tutorialSeen` 字段本身按裁定**保留不删**。
  bool get needsTutorial => !state.tutorialSeen;

  /// 今天的掉落档（`absent` 时 = [GuardDropKind.none]）。
  GuardDropKind get dropKind => state.dropKind;

  /// 今天的**第二张**掉落档（B13.5 双券；`none` = 没有第二张）。
  ///
  /// 仅主券是券档时才有机会非 `none`（`rollBonus` 的闸门语义），
  /// 结果卡用它渲染第二张券卡。
  GuardDropKind get bonusDropKind => state.bonusDropKind;

  /// 今天**将**到账的必得阳光（`claim()` 里若为 0 会兜底
  /// [kGuardWinSunNoItem]，故这里用同一口径）。
  int get winSun =>
      state.winSun > 0 ? state.winSun : kGuardWinSunNoItem;

  /// 本次会**实际**花掉的阳光（能量路径 / 免罚档 = 0）。
  int get payCost => needsPayConfirm ? kGuardPayCost : 0;

  /// 这张券**实际**能再省多少 ☀（结算卡「券还能省 N 阳光」用）。
  ///
  /// 口径分两档（产品裁定，2026-11-09）：
  ///  · **免费券**（[GuardDropKind.singlePotOnly]）⇒ 单盆单次，计数固定 1：
  ///    省的是「这盆**实际**单价」，随称号减免变小（Lv.5 免费浇水省 4 而不是
  ///    面值 5；Lv.10 免费施肥省 9 而不是 10）。
  ///  · **非免费券** ⇒ 取**当日最大可省**：计数直接取当日配额
  ///    [guardVoucherQuotaOf]（浇水 6 / 劳动 4 / 施肥 [kGuardFertilizerVoucherQuota] 次），由
  ///    [voucherSavingOf] 自身的封顶钳住。理由：结算卡是**领取时**的承诺，
  ///    孩子还没决定浇几盆，报上界才诚实；报 1 会让「一天能省 6 ☀」的券
  ///    显得不值钱。🔴 不写死 6 / 4 —— 配额改了显示自动跟。
  /// 无道具档 = 0。
  ///
  /// [perk] == null（旧调用方 / 读称号失败）⇒ 退回面值 [GuardDropSpec.faceValue]
  /// 向下取整，与改造前逐位一致（绝不崩）。单位是 ☀，结果恒为非负整数。
  int get voucherSaving {
    if (!dropKind.hasVoucher) return 0;
    final PlantPerk? currentPerk = perk;
    if (currentPerk == null) return dropKind.faceValue.floor();
    // 免费券只作用于单株（单盆实际价）；其余券按「当日配额上限」算最大可省。
    final int units = dropKind.singlePotOnly ? 1 : guardVoucherQuotaOf(dropKind);
    return voucherSavingOf(
      dropKind,
      potCount: units,
      cleanCount: units,
      perk: currentPerk,
    ).round();
  }

  /// 还差多少阳光才付得起（`guard_pill_no_balance` 用；本批未上屏）。
  int get payDeficit {
    final double left = kGuardPayCost - balance;
    return left <= 0 ? 0 : left.ceil();
  }

  @override
  String toString() => 'GuardTodayView(${mode.name}, '
      'thief=${thief?.id}, energy=$energyAvailable, balance=$balance, '
      'state=${state.status.id})';
}

/// 今日守卫的唯一状态容器（`watch` 它，不要 `read`）。
///
/// 刻意**不用** `autoDispose`：今日页在 `IndexedStack` 里保活，来回切 tab 时
/// 胶囊不该闪；页面卸载后这份快照仍在，重进时先按旧值渲染、`_reload` 再校正
/// （比「先零占位再冒出来」更稳，也避免每次进页都跳一下布局）。
final StateProvider<GuardTodayView> guardTodayProvider =
    StateProvider<GuardTodayView>(
  (Ref ref) => const GuardTodayView.absent(),
);

/// 守卫存档修订号：**任何写守卫存档的表现层入口**在成功后自增，花园页据此
/// 重读今日券快照（buff chip 与价格同源）。
///
/// 为什么不能复用经济修订号 `economyRevisionProvider`：发券 / 清档 / 造贼 /
/// 领取都只写守卫当日存档，**不写阳光账本**，经济修订号不会动；而花园页的
/// `_guardBuff` 只在 `_reload` 里读一次、页面本身不 watch 任何守卫 provider
/// ⇒ 少了这条通道，「守卫完成发券 / 调试面板改存档」后左上角胶囊会停在旧
/// 快照（玄参真机 ③）。与既有跨页总线一样只是「事实通知」，真正的券仍由
/// `guardVoucherProvider.currentBuff()` 从存档读，绝不另开一份 UI 快照。
final StateProvider<int> guardBuffRevisionProvider =
    StateProvider<int>((Ref ref) => 0);
