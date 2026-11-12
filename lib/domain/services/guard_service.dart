/// 花园守卫的**编排层**：能量派生 / 结算（resolve）/ 领取（claim）/ 跨天过期（expire）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.2 / §3.3 / §3.6 / §4 / §7。
///
/// ## 🔴 `resolve()` 与 `claim()` 必须分开（产品硬约束，不是代码洁癖）
/// | 阶段 | 做什么 | 能不能写账本 |
/// |---|---|---|
/// | [resolve] | 判定今天来哪只贼 / 偷多少 / 掉什么 / 成本模式，**落盘 prefs** | ❌ 绝对不写 |
/// | [claim] | 真正发奖：扣阳光（或扣能量）+ 发必得阳光 + 落 buff | ✅ 唯一允许写账本的方法 |
///
/// 如果「看了战报就算领取」，那孩子**跳过动画**也能拿到奖励 —— 奖励就与观看行为
/// 脱钩了（PRD §7.3 第一条红线「跳过与看完拿到逐位相同的结果」只管「算」，不管
/// 「发」）。把发放推迟到「点收下」这一步，才能同时满足两件事：
///  · 跳过动画 **不改变** 奖励内容（落骰在 resolve 时已定死，动画只是回放）；
///  · 孩子的动作（点收下）才是记账的触发点，账本不会因为「打开过页面」多出脏行。
///
/// ## 四条账本口径（🔴 严格执行）
/// | 动作 | type | refType | refId | 金额 |
/// |---|---|---|---|---|
/// | 付费赶走 | [SunlightType.plant] | `guard_pay` | `garden` | −5 ☀ |
/// | 必得阳光 | [SunlightType.earn] | `guard_win` | `garden` | +1~3 ☀ |
/// | 未处理被偷 | [SunlightType.plant] | `guard_stolen` | `garden` | −n ☀（**钳到 0 为止**） |
///
/// 幂等三层（全靠确定性 id + 账本读判定，不新增存储）：
///  1. 状态层：`state.dayKey == today && state.isClaimed` ⇒ 空操作；
///  2. 账本层（事实源）：`countByRefTypeAndRefIdOnDay('guard_win', 'garden', today) > 0`
///     ⇒ 视为已领取（修「账本写成功、prefs 写失败」的半截状态）；
///  3. 写入层：`SunlightEntry.id = 'guard_xxx_<childId>_<dayKey>'`，DAO 是 `insert`
///     ⇒ 主键冲突即抛 ⇒ 捕获后视为「已经扣过 / 已经发过」。
///
/// 🔴 余额钳制：任何扣减都先 `min(应扣, 当前余额)`，**绝不出现负余额**（PRD 决策 D6）。
///
/// ## 本批不做的事
/// 埋点（`kGuardTrack*`）与任何 UI 接线留到第三批；本文件只碰 prefs / 账本 / `plants`。
library guard_service;

import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_validity.dart';
import 'package:sunflower_time/domain/services/guard_chest.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

/// 确定性通道名：食叶虫「今天挑哪一株」。
///
/// 🔴 **一经写入即冻结**：改了它等于让历史每一天「被咬的是哪一盆」全部重掷
/// （与 `thief` / `drop` / `sun` / `growth` / `win` 五个通道隔离，互不相关）。
const String kGuardChannelTargetPlant = 'target_plant';

/// 成本模式（胶囊右侧徽标 + 内部记账路径的**同一个**判定结果）。
enum GuardCostMode {
  /// 有能量：0 ☀，消耗 1 点能量（**不写账本**）。
  free,

  /// 无能量、余额够：扣 [kGuardPayCost] ☀。
  paid,

  /// 无能量、余额 < [kGuardFreeRideBalance]：当天免罚、胶囊不可点。
  freeRide,
}

/// [GuardService.resolve] 的结果（只描述「发生了什么」，**不含任何账本副作用**）。
class GuardResolveResult {
  const GuardResolveResult({
    required this.dayKey,
    required this.cost,
    required this.thief,
    required this.roll,
    required this.state,
    required this.energyAvailable,
    required this.balance,
    this.isPremium = false,
    this.needsExpire = false,
  });

  /// 本次派生的自然日（`yyyy-MM-dd`）。
  final String dayKey;

  /// 成本模式（free / paid / freeRide）。
  final GuardCostMode cost;

  /// 今天的贼（`null` = 全园无存活株，今天没有贼）。
  final GuardThiefKind? thief;

  /// 完整落骰结果（`null` = 没有贼）。
  ///
  /// 🔴 **本字段不驱动战斗动画**：战斗剧本由 `deriveGuardBattleScript`
  /// （dayKey + childId 独立派生）生成，动画层**不读** `roll`。
  /// 不进动画不影响公平性——奖励在 `resolve()` 落盘、`claim()` 按落盘结果
  /// 发放，「跳过」与「看完」拿到的奖励逐位相同（PRD §7.3 第一条红线）。
  ///
  /// ⚠️ 玄参 2026-11-11 裁定：**「战斗回放」功能不做**。`roll` 保留为
  /// 观测/测试用途（幂等回放一致性、派生正确性），不要把它当成动画数据源；
  /// 将来若要做回放，必须先重新评估该字段的语义与档位口径。
  final GuardRoll? roll;

  /// 已落盘（或读回）的当日状态。
  final GuardDayState state;

  /// 本次判定时剩余能量（免费 0..[kGuardEnergyDailyMaxFree]、付费
  /// 0..[kGuardEnergyDailyMaxPremium]）。
  final int energyAvailable;

  /// 本次判定时的余额。
  final double balance;

  /// 本次判定时的权益档位（🔴 B13.8 能量档位制：免费 cap 1 / 会员 cap 2）。
  ///
  /// 由领域层单点给出（`_premium`）—— 表现层（尤其孩子端页面）**不得**直接
  /// 摸权益 provider（权益标识符白名单守卫钉死），统一经本字段透传 UI。
  final bool isPremium;

  /// 🔴 昨天还有一条**未结算**的存档：本次 `resolve()` **拒绝覆盖**它。
  ///
  /// 调用方看到 `true` 必须先 `expire()`（结算昨天的损失 / 补发阳光）再回来 resolve。
  /// 没有这道闸门，「页面先 resolve 后 expire」的时序就会把昨天的 `sunStolen` /
  /// `growthStolen` 直接盖掉 —— 那是永久性的对账缺口（被偷了却没扣）。
  final bool needsExpire;

  /// 今天有没有贼。
  bool get hasThief => thief != null;

  /// 今天会掉的券（无贼时 = [GuardDropKind.none]）。
  GuardDropKind get drop => state.dropKind;

  /// 今天的必得阳光（无贼 = 0）。
  ///
  /// ⚠️ 这是**基础值**（3~5）。表现层要显示的「实际到账」请读
  /// [grantedWinSun]（高级宝箱 ×2），否则结算卡会写 +4 而账本记 +8。
  int get winSun => state.winSun;

  /// 本场**实际到账**的必得阳光（高级宝箱 ×2；无贼 = 0）。
  ///
  /// 🔴 Guard-B13.11：唯一派生口是 `guardGrantWinSunOf`，表现层**只准读它**，
  /// 不得自己 `× 2`（那会变成第二套经济账）。
  int get grantedWinSun => state.hasThief ? guardGrantWinSunOf(state) : 0;

  /// 今天**将被**偷走的阳光（免罚档 = 0）。
  int get sunLoss => state.sunStolen;

  /// 今天**将被**偷走的成长（`plantId -> pp`；免罚档为空）。
  Map<String, double> get growthLoss => state.growthStolen;
}

/// [GuardService.claim] 的失败原因（**返回值，不抛异常**）。
///
/// 为什么用返回值而不是异常：余额不足是**正常业务分支**（孩子天天会遇到），
/// 抛异常会把它和「数据库崩了」混在一起，UI 也就没法区分「还差 2 ☀」与「出错了」。
enum GuardClaimFailure {
  /// 成功（[GuardClaimOutcome.ok] == true 时恒为本值）。
  none,

  /// 今天还没有 `resolve()` 过（有存活株，但当日状态里没有贼 —— 跨天后直接点胶囊 /
  /// 状态被清 / 存档损坏都会落到这里）。
  notResolved,

  /// 今天没有贼（**全园无存活株**：`resolve()` 本就不会生成小偷）。
  noThief,

  /// 余额不足：无可用能量 **且** 余额 < [kGuardPayCost]。
  ///
  /// 🔴 此时**分毫不扣、什么都不发**（`paidSun == 0`、`winSun == 0`、无 buff）。
  insufficientBalance,
}

/// [`GuardService._grantChestExtras`] 的**三态**结果（内部实现细节，不对外暴露）。
///
/// 为什么不能是 `bool`（P2-② 修复）：`bool` 只有「置位 / 不置位」两态，而碎片的
/// 幂等标记 [GuardDayState.chestExtrasGranted] 表达的是「**已经发完了**」。
/// 「端口没注入 ⇒ 发不了」与「已经发完了」在 `bool` 里挤成同一个 `true`
/// ⇒ 标记被错误置位 ⇒ 事后补好 DI 也**永不补发**（静默丢奖励）。
/// 三态把这三件事分开，调用方只需认 [settled] 一种才置标记。
enum _ChestExtrasOutcome {
  /// 本次真的发完了 / 本来就不需要发（非高级宝箱、标记已置位）⇒ **可以置标记**。
  settled,

  /// 发放端口（`BloomRewardRepository`）**未注入** ⇒ 一片都没发。
  /// 「发不了」≠「已发完」：**绝不置标记**（否则补好 DI 后永久吞掉奖励）。
  portMissing,

  /// 仓储抖动导致**没发成** ⇒ 不置标记，留给下一次 `expire()` 重试。
  failed,
}

/// [GuardService.claim] 的结果。
class GuardClaimOutcome {
  const GuardClaimOutcome({
    required this.ok,
    required this.failure,
    required this.alreadyClaimed,
    required this.usedEnergy,
    required this.paidSun,
    required this.winSun,
    required this.drop,
    this.bonusDrop = GuardDropKind.none,
    required this.buff,
    this.bonusBuff,
    required this.energyAvailable,
    required this.balance,
    required this.state,
    this.isPremium = false,
  });

  /// 是否领取成功（`alreadyClaimed` 也算「现在这张券/这份阳光已经是你的了」）。
  final bool ok;

  /// 失败原因（成功 = [GuardClaimFailure.none]）。
  final GuardClaimFailure failure;

  /// 本次调用是否「撞上了已经领过的状态」（幂等路径，**没有**第二次记账）。
  final bool alreadyClaimed;

  /// 是否走「能量」路径（0 ☀）。
  final bool usedEnergy;

  /// 实际扣掉的阳光（能量路径 = 0）。
  final int paidSun;

  /// 实际到账的必得阳光（失败 = 0）。
  final int winSun;

  /// 今天的券档（无道具档 = [GuardDropKind.none]）。
  final GuardDropKind drop;

  /// 第二张券档（`none` = 今天没有第二张）。
  ///
  /// 🔴 Guard-B13.11：真源是**高级宝箱**（`state.chestBonusDropKind`）；这里
  /// 只是把它（或旧存档的 `bonusDropKind`）原样透传给表现层。
  final GuardDropKind bonusDrop;

  /// 今天可用的 buff（无道具档 = `null`）。
  final GuardBuffState? buff;

  /// 🔴 B13.5：第二张券的 buff（没有第二张 = `null`）。
  final GuardBuffState? bonusBuff;

  /// 领取后剩余能量。
  final int energyAvailable;

  /// 领取后的余额。
  final double balance;

  /// 领取后的当日状态。
  final GuardDayState state;

  /// 本次领取时的权益档位（🔴 B13.8：经领域层单点透传 UI，见
  /// [GuardResolveResult.isPremium] 的说明）。
  final bool isPremium;
}

/// [GuardService.expire] 的结果。
class GuardExpireOutcome {
  const GuardExpireOutcome({
    required this.today,
    required this.expiredDayKey,
    required this.settled,
    required this.stolenSun,
    required this.growthTargets,
    required this.grantedWinSun,
  });

  /// 什么都没发生（同一天 / 时钟回拨）。
  const GuardExpireOutcome.none(this.today)
      : expiredDayKey = null,
        settled = false,
        stolenSun = 0,
        growthTargets = 0,
        grantedWinSun = 0;

  /// 结算发生的「今天」。
  final String today;

  /// 被结算掉的那一天（`null` = 没有跨天）。
  final String? expiredDayKey;

  /// 是否真的结算了一条过期存档。
  final bool settled;

  /// 实际扣掉的阳光（钳制后的值；0 = 没扣）。
  final int stolenSun;

  /// 被扣成长的株数（开花株 / 死株由纯函数免疫，不计入）。
  final int growthTargets;

  /// 「进了战斗但没点收下」时补发的必得阳光（PRD §3.6）。
  final int grantedWinSun;
}

/// 花园守卫编排服务（纯 Dart，零 Flutter 依赖）。
class GuardService {
  GuardService({
    required GuardStateStore store,
    required SunlightRepository ledger,
    required FocusRepository focus,
    required PlantRepository plants,
    required PlantGrowthService growth,
    required String Function() childId,
    DateTime Function()? clock,
    // 🔴 B13.5：权益档位取值器（付费掉落表用）。缺省恒 false（免费表）——
    // 一切旧构造点（测试 / 调试）零改动；DI 接 entitlement（见 providers.dart）。
    bool Function()? isPremium,
    // 🔴 Guard-B13.11：碎片 / 种子发放端口（账户级藏品，**不走阳光账本**）。
    // 缺省 `null` = 不发放宝箱附加奖励 —— 只有「纯派生 / 记账」类老测试会走到
    // 这个分支；生产装配（providers.dart）**必须**注入，否则高级宝箱的碎片与
    // 种子会静默丢失（`guard_chest_grant_test.dart` 用真仓储钉死这条）。
    BloomRewardRepository? bloomRewards,
  })  : _store = store,
        _ledger = ledger,
        _focus = focus,
        _plants = plants,
        _growth = growth,
        _bloomRewards = bloomRewards,
        _childId = childId,
        _clock = clock ?? DateTime.now,
        _isPremium = isPremium;

  final GuardStateStore _store;
  final SunlightRepository _ledger;
  final FocusRepository _focus;
  final PlantRepository _plants;

  /// 成长扣减的落地口（[PlantGrowthService.raidGrowth]，只它一家会写 `plant.progress`）。
  final PlantGrowthService _growth;

  /// 🔴 Guard-B13.11：碎片 / 种子发放端口（`null` = 未注入 ⇒ 不发附加奖励）。
  ///
  /// 🔴 本类是该仓储在**守卫链路上的唯一调用者**：表现层（演出 / 结算卡）
  /// **一律不得**直接摸 `BloomRewardRepository`（与「表现层不得摸权益 provider」
  /// 同一条纪律）。
  final BloomRewardRepository? _bloomRewards;

  /// 碎片 / 种子发放端口是否已注入（**只读探针，供装配断言**）。
  ///
  /// 为什么需要它：`bloomRewards` 是**可选**构造参数（老测试零改动），漏注入
  /// 不会有任何报错 —— 只见「高级宝箱承诺了碎片、余额却不动」这种静默丢失。
  /// `guard_chest_stage_test.dart` 用它钉死「`guardServiceProvider` 真实装配
  /// 后端口已接上」，把这类漏接线挡在编译期之后的第一步。
  ///
  /// ⚠️ 领域层不引 `package:meta`（本工程 domain 只依赖纯 Dart + 本项目），
  /// 故不加 `@visibleForTesting`；生产代码不得读它（只读派生，无副作用）。
  bool get hasBloomRewardPort => _bloomRewards != null;

  /// 🔴 B13.5：权益档位取值器（`null` = 恒免费表；DI 接 entitlement）。
  final bool Function()? _isPremium;

  bool get _premium => _isPremium?.call() ?? false;

  /// 当前孩子的 childId（生产接 `AccountService.childId`；测试注入常量）。
  final String Function() _childId;

  final DateTime Function() _clock;

  // ═══════════════════════════════════════════════════════════════════════
  // 一、能量（从专注派生，零新表）
  // ═══════════════════════════════════════════════════════════════════════

  /// 今天还能用几发能量（免费 0..[kGuardEnergyDailyMaxFree]、
  /// 付费 0..[kGuardEnergyDailyMaxPremium]）。
  ///
  /// `可用 = clamp(今日有效专注次数 × kGuardEnergyPerFocus, 0, 档位上限) − 今日已消耗`
  ///（上限按权益档位取：免费 [kGuardEnergyDailyMaxFree] / 会员 [kGuardEnergyDailyMaxPremium]）。
  ///
  /// 🔴 「有效专注」走 `focus_validity.dart` 的单一真源（[isValidFocusSession]），
  /// **绝不**用 `sessions.length`：后者包含「点开 3 分钟就退出」的会话，
  /// 拿它发能量等于「玩一下就能刷满能量」。
  Future<int> energyAvailable({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final int earned = await _energyEarnedOn(today);
    final GuardDayState state = await _store.read(_childId());
    final int used = state.dayKey == today ? state.energyUsed : 0;
    final int left = earned - used;
    return left > 0 ? left : 0;
  }

  /// 当前权益档位的每日能量上限（免费 1 / 会员 2，B13.8 档位制）。
  int get _energyDailyCap =>
      _premium ? kGuardEnergyDailyMaxPremium : kGuardEnergyDailyMaxFree;

  /// 某个自然日**赚到**的能量（不含消耗；用于 `energyAvailable` 与跨天结算）。
  Future<int> _energyEarnedOn(String dayKeyValue) async {
    final List<FocusSession> sessions =
        await _focus.sessionsOfDay(dayKeyValue);
    final int valid = validFocusSessionsOf(sessions).length;
    final int earned = valid * kGuardEnergyPerFocus;
    final int cap = _energyDailyCap;
    return earned > cap ? cap : earned;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 二、今日视图（唯一做「跨天归一」的地方）
  // ═══════════════════════════════════════════════════════════════════════

  /// 今日状态（**给页面看**的那一份）。
  ///
  /// 存档的 `dayKey != 今天` ⇒ 返回空白当日状态：昨天的贼 / 昨天的券 / 昨天的
  /// 能量消耗**一个都不许**出现在今天的今日页。真正的结算由 [expire] 完成。
  Future<GuardDayState> todayState({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final GuardDayState state = await _store.read(_childId());
    return state.dayKey == today ? state : GuardDayState.empty(today);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 三、结算（只算、只落盘 prefs，🔴 绝不写账本）
  // ═══════════════════════════════════════════════════════════════════════

  /// 结算今天：判定小偷 / 偷多少 / 掉什么 / 成本模式，并把结果**落盘**。
  ///
  /// 幂等：同一天重复调用**不会**重掷（`GuardDayState.hasThief` 即视为已结算），
  /// 杀进程重进拿到的还是同一只贼、同一份奖励 —— 这正是「跳过动画不算作弊」的前提。
  ///
  /// 🔴 若昨天还有一条未结算的存档，本方法**拒绝覆盖**并返回
  /// `needsExpire == true`：调用方必须先 [expire]。否则昨天的 `sunStolen` /
  /// `growthStolen` 会被今天的状态盖掉（永久对账缺口）。
  ///
  /// 🔴 本方法**零账本写入**（`test/guard/guard_service_test.dart` 的 A10 钉死）。
  Future<GuardResolveResult> resolve({DateTime? now}) async {
    final DateTime at = now ?? _clock();
    final String childId = _childId();
    final String today = dayKey(at);
    final GuardDayState stored = await _store.read(childId);

    // ①′ 跨天且昨天还没结算 → **拒绝覆盖**（先让调用方 expire()，见 [needsExpire]）。
    if (stored.dayKey.compareTo(today) < 0 && _needsSettlement(stored)) {
      final int staleEnergy = await energyAvailable(now: at);
      final double staleBalance = await _ledger.balance();
      return GuardResolveResult(
        dayKey: today,
        cost: _costModeOf(stored, staleEnergy, staleBalance),
        thief: stored.thiefKind,
        roll: null,
        state: stored,
        energyAvailable: staleEnergy,
        balance: staleBalance,
        isPremium: _premium,
        needsExpire: true,
      );
    }

    // ② 幂等：今天已经结算过 → 原样回放（不重掷、不重写）。
    if (stored.dayKey == today && _isResolved(stored)) {
      final int energy = await energyAvailable(now: at);
      final double balance = await _ledger.balance();
      return GuardResolveResult(
        dayKey: today,
        cost: _costModeOf(stored, energy, balance),
        thief: stored.thiefKind,
        roll: stored.hasThief
            // 🔴 Guard-B13.10：回放也必须带档位 —— 缺 `isPremium` 时
            // `deriveGuardRoll` 走免费表，完整版用户回放会拿到「免费档」的掉落
            // （drop / bonusDrop 都可能与实际落盘的 state 不一致）。
            ? deriveGuardRoll(
                dayKey: today,
                childId: childId,
                isPremium: _premium,
              )
            : null,
        state: stored,
        energyAvailable: energy,
        balance: balance,
        isPremium: _premium,
      );
    }

    final List<Plant> alive = await _alivePlants();
    final int energy = await energyAvailable(now: at);
    final double balance = await _ledger.balance();

    // ② 全园无存活株 ⇒ 今天没有贼（胶囊零占位，零占位即零状态）。
    if (alive.isEmpty) {
      final GuardDayState empty = GuardDayState.empty(today);
      await _store.write(childId, empty);
      return GuardResolveResult(
        dayKey: today,
        cost: GuardCostMode.freeRide,
        thief: null,
        roll: null,
        state: empty,
        energyAvailable: energy,
        balance: balance,
        isPremium: _premium,
      );
    }

    // ③ 确定性派生（禁 Random）：同一 dayKey + childId 恒得同一结果。
    // 🔴 B13.5：掉落分档按权益档位；Guard-B13.11：第二张券不再由掉落层产生。
    final GuardRoll roll =
        deriveGuardRoll(dayKey: today, childId: childId, isPremium: _premium);
    // 🔴 Guard-B13.11（设计 §5.1）：宝箱档位与**全部开箱内容**在这里一次性定死。
    //    唯一派生口 = `deriveGuardChest`（纯函数，通道见 prd_params）。
    //    ⚠️ 本结果只在 `resolve()` 里算一次并落盘：表现层与发放层一律读
    //    `state`，**不得**自己重算（重算就是第二套经济账）。
    final GuardChestRoll chest = deriveGuardChest(
      dayKey: today,
      childId: childId,
      isPremium: _premium,
      drop: roll.drop,
    );
    final bool free = energy >= kGuardEnergyPerFocus;
    final GuardCostMode cost = free
        ? GuardCostMode.free
        : (balance >= kGuardPayCost
            ? GuardCostMode.paid
            : GuardCostMode.freeRide);

    // 免罚档（无能量 且 余额 < 5）：**当天不结算损失**（PRD 决策 D3）。
    // 故落盘时把损失写成 0 / 空 —— 即便将来谁忘了判 `isFreeRide`，
    // 也绝不会真的去扣（fail-safe 偏向孩子）。
    final bool waived = cost == GuardCostMode.freeRide;
    final Map<String, double> growthLoss =
        waived ? const <String, double>{} : _growthLossOf(roll, alive, today);

    final GuardDayState next = GuardDayState(
      dayKey: today,
      status: waived ? GuardDayStatus.short : GuardDayStatus.pending,
      thiefKind: roll.thief,
      energyUsed: 0,
      paidSun: 0,
      winSun: roll.winSun,
      dropKind: roll.drop,
      // 🔴 Guard-B13.11：掉落阶段不再产生第二张券（恒 none）；第二张券的真源
      // 是下面的 `chestBonusDropKind`。
      bonusDropKind: GuardDropKind.none,
      sunStolen: waived ? 0 : roll.sunLoss,
      growthStolen: growthLoss,
      // 🔴 Guard-B13.11：宝箱六字段（与 winSun / dropKind 同一次 resolve 落盘）。
      chestTier: chest.tier,
      chestBonusDropKind: chest.bonusDrop,
      chestFragmentQty: chest.fragmentQty,
      chestSeedKind: chest.seedKind,
      chestSeedSpeciesId: chest.seedSpeciesId,
      chestExtrasGranted: false,
      // 🔴 B10/B4：当日场次序号（第 1 场 = 0）在**生成状态时**定死。
      battleAttempt: await _nextBattleAttempt(today),
    );
    await _store.write(childId, next);

    return GuardResolveResult(
      dayKey: today,
      cost: cost,
      thief: roll.thief,
      roll: roll,
      state: next,
      energyAvailable: energy,
      balance: balance,
      isPremium: _premium,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 三′、进入战斗（状态机：pending → fighting）
  // ═══════════════════════════════════════════════════════════════════════

  /// 把孩子「已经动手看了战斗动画」这件事**落盘**（`pending` → `fighting`）。
  ///
  /// ## 为什么必须有这一步（体验事故，不是洁癖）
  /// [expire] 对两条分支的处理**完全相反**：
  ///  · `pending`（没处理）→ 扣阳光 + 扣成长；
  ///  · `fighting`（进了战斗但没点「收下」）→ **补发**必得阳光、**不结算损失**。
  ///
  /// 如果页面不落 `fighting`，孩子看完动画后**强杀进程 / 手机没电 / 闪退**，
  /// 次日 `expire()` 就会把他当「压根没管」照罚 —— 他明明已经动手了。
  /// 故本方法必须由页面在「确认付费通过、战斗浮层拉起之前」调用。
  ///
  /// ## 空操作（🔴 一个字节都不写）
  ///  · 存档不是**今天**的（`dayKey != today`）→ 空操作。
  ///    🔴 这条最关键：昨天的 `pending` 若被改写成 `fighting`，`expire()` 就会
  ///    走「补发」分支，昨天的损失永远收不回来（对账缺口）。
  ///  · 状态不是 [GuardDayStatus.pending]（已领取 / 免罚 / 已在战斗中 / 无贼）→ 空操作。
  ///  · 从未 resolve 过（连贼都没有）→ 空操作。
  ///
  /// ## 不抛异常
  /// 写失败一律吞掉：战斗是**给孩子看的**，存储抖动不该把浮层拦下来。
  /// 最坏结果是退回 `pending`（= 不调本方法的既有行为），不会更差。
  Future<void> markFighting({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final String childId = _childId();
    final GuardDayState state = await _store.read(childId);
    if (state.dayKey != today) return;
    if (state.status != GuardDayStatus.pending) return;
    if (!state.hasThief) return;
    try {
      await _store.write(
        childId,
        state.copyWith(status: GuardDayStatus.fighting),
      );
    } catch (_) {
      // 写失败 = 等同于没标记（次日按 pending 结算）。不阻断孩子的战斗。
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 三″、教学标记（守卫战 v2 · B2 新增；「教学浮层只播一次」的持久化口）
  // ═══════════════════════════════════════════════════════════════════════

  /// 把「教学浮层已经看过」落盘（[GuardDayState.tutorialSeen] = true）。
  ///
  /// 与 [markFighting] 同一套纪律：
  ///  · 只经领域服务写存储（页面不得直写 prefs）；
  ///  · 存档不是**今天**的 → 空操作（绝不改写昨天的存档）；
  ///  · 已看过（`tutorialSeen == true`）→ 空操作（幂等，重复调用零写入）；
  ///  · 写失败一律吞掉：教学看不成最坏结果是「明天再看一次」，不该拦战斗。
  ///
  /// 次日 `resolve()` 生成新存档时 `tutorialSeen` 回到缺省 false ⇒ 教学
  /// 「每天至多一次」的口径由存档的生命周期天然保证，零新增状态。
  Future<void> markTutorialSeen({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final String childId = _childId();
    final GuardDayState state = await _store.read(childId);
    if (state.dayKey != today) return;
    if (state.tutorialSeen) return;
    try {
      await _store.write(childId, state.copyWith(tutorialSeen: true));
    } catch (_) {
      // 写失败 = 标记没落上；下一次进战斗会再看一次教学，无经济影响。
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 四、领取（🔴 唯一允许写账本的方法）
  // ═══════════════════════════════════════════════════════════════════════

  /// 领取今天的战果：赶走小偷 → 扣成本 → 发必得阳光 → 落今日 buff。
  ///
  /// 成本顺序**先能量、后阳光**（PRD §3.2）：
  ///  · 有能量 → 只把 `energyUsed + 1`（**不写账本**：能量是派生量，不是货币）；
  ///  · 没能量 → 扣 [kGuardPayCost] ☀，余额不足则**什么都不做**并返回
  ///    [GuardClaimFailure.insufficientBalance]。
  ///
  /// 幂等：同一天连调 N 次只扣一次钱、只发一次奖励（三层幂等见文件头）。
  ///
  /// [useEnergy] = false 时强制走阳光路径（调试面板 / 未来的「攒着能量」玩法用；
  /// 默认 true，即「有能量必须不花阳光」）。
  Future<GuardClaimOutcome> claim({DateTime? now, bool useEnergy = true}) async {
    final DateTime at = now ?? _clock();
    final String childId = _childId();
    final String today = dayKey(at);
    final GuardDayState state = await _store.read(childId);
    final int energy = await energyAvailable(now: at);
    final double balance = await _ledger.balance();

    // ① 跨天 / 还没 resolve：状态不存在，不能凭「空状态」发奖。
    if (state.dayKey != today) {
      return _claimFailure(
        GuardClaimFailure.notResolved,
        state: state,
        energy: energy,
        balance: balance,
      );
    }

    // ② 幂等（状态层）：今天已经领过 → 原样回放，不动钱。
    if (state.isClaimed) return _claimReplay(state, energy: energy, balance: balance);

    // ③ 幂等（账本层，事实源）：本场已有 guard_win 行 ⇒ 视为已领取。
    //    修「账本写成功、prefs 写失败」（或状态被外部清掉）的半截状态：
    //    宁可少发一次，也绝不重复发。
    //
    // 🔴 B10/B4：判据从「当日有任何 guard_win 行」收窄为「**本场**已有 guard_win
    //    行」= `当日行数 > 本场序号`。生产路径（一天一场、`battleAttempt == 0`）
    //    与旧判据逐位等价 ⇒ **幂等一格没松**；只有「同日第二场」（调试重置后
    //    再打）才允许第二次记账，否则玄参报的「第二次花 5 阳光不扣」永远修不掉。
    final int attempt = state.battleAttempt;
    final String suffix = _attemptSuffixOf(attempt);
    final int winRows = await _ledger.countByRefTypeAndRefIdOnDay(
      kGuardWinRefType,
      kGuardRefId,
      today,
    );
    if (winRows > attempt) {
      final GuardDayState repaired = state.copyWith(status: GuardDayStatus.claimed);
      await _store.write(childId, repaired);
      return _claimReplay(repaired, energy: energy, balance: balance);
    }

    // ④ 今天没有贼：区分「全园无存活株（本来就没有贼）」与「有株但还没 resolve」。
    if (!state.hasThief) {
      final List<Plant> alive = await _alivePlants();
      return _claimFailure(
        alive.isEmpty ? GuardClaimFailure.noThief : GuardClaimFailure.notResolved,
        state: state,
        energy: energy,
        balance: balance,
      );
    }

    // ⑤ 成本判定：先能量、后阳光（🔴 绝不「先扣钱再退」）。
    final bool free = useEnergy && energy >= kGuardEnergyPerFocus;
    if (!free && balance < kGuardPayCost) {
      // 余额不足 = 正常业务分支：分毫不扣、什么都不发、状态也不改写。
      return _claimFailure(
        GuardClaimFailure.insufficientBalance,
        state: state,
        energy: energy,
        balance: balance,
      );
    }

    int energyUsed = state.energyUsed;
    int paidSun = 0;
    if (free) {
      energyUsed += kGuardEnergyPerFocus;
    } else {
      // 余额钳制：扣到 0 为止，绝不出现负余额（PRD 决策 D6）。
      final double charge = math.min(kGuardPayCost.toDouble(), balance);
      await _appendLedger(SunlightEntry(
        // 🔴 B10/B4：id 追加场次后缀（第 1 场无后缀 ⇒ 与历史逐位相同）。
        id: 'guard_pay_${childId}_$today$suffix',
        ts: at,
        type: SunlightType.plant,
        gross: -charge,
        net: -charge,
        balanceAfter: balance - charge,
        refType: kGuardPayRefType,
        refId: kGuardRefId,
        dayKey: today,
      ));
      paidSun = charge.toInt();
    }

    // ⑤′ 🆕 发宝箱附加奖励（碎片 / 种子）—— 🔴 **必须在写 `guard_win` 账本行之前**。
    //
    //    为什么顺序不能倒（设计 §5.2）：`guard_win` 行是「已领取」的**事实源**
    //    （上面第 ③ 步的账本层幂等网读它）。若先写账本再发碎片，中途崩溃 ⇒
    //    重进时判「已领取」直接回放 ⇒ **碎片永久丢失**，而结算卡已经承诺
    //    「获得碎片 1 片」。反过来（先发碎片再写账本）最坏结果是**多发 1 片**。
    //    方向明确：**宁可多发一次，也不吞掉已承诺的奖励**（这一条针对的是
    //    「发奖」，与 `_appendLedger`「宁可少发一次」的**扣钱/发钱**口径不冲突）。
    //
    //    ⚠️ 残余风险（已知、已接受，不是 bug）：无事务 ⇒ 进程恰在 ⑤′ 与 ⑧ 之间
    //    被杀时碎片会**多发 1 片**（或种子再发一颗）；`chestExtrasGranted`
    //    把窗口压到最小，绝对量级约 1e-6/天。方向偏向孩子。
    //
    //    🔴 P2-②：返回值是**三态**（见 [_ChestExtrasOutcome]），只有 `settled`
    //    才允许置幂等标记。「端口没注入 ⇒ 一片都没发」绝不能被记成「已发完」，
    //    否则事后补好 DI 也永不补发（静默丢奖励，QA 实证）。
    final _ChestExtrasOutcome extras = await _grantChestExtras(state);

    // ⑥ 发必得阳光（3~5；无道具档 = 5）。
    //    🔴 Guard-B13.11：金额必须走 `guardGrantWinSunOf`（高级宝箱 ×2），
    //    绝不能用裸 `state.winSun` —— 否则「结算卡写 +8、账本只 +4」。
    final int winSun = guardGrantWinSunOf(state);
    // 🔴 落盘的是**基础值**（`winSun` 字段的语义自 B13 起就是「基础 3~5」）：
    //    翻倍只在读取侧由 `guardGrantWinSunOf` 派生 ⇒ 任何时候都不会出现
    //    「已翻倍的值再翻一次」（设计 §2.4 / §3.4）。
    final int baseWinSun =
        state.winSun > 0 ? state.winSun : kGuardWinSunNoItem;
    final double beforeWin = await _ledger.balance();
    await _appendLedger(SunlightEntry(
      // 🔴 B10/B4：同 `guard_pay`，第 1 场 id 与历史逐位相同。
      id: 'guard_win_${childId}_$today$suffix',
      ts: at,
      type: SunlightType.earn,
      gross: winSun.toDouble(),
      net: winSun.toDouble(),
      balanceAfter: beforeWin + winSun,
      refType: kGuardWinRefType,
      refId: kGuardRefId,
      dayKey: today,
    ));

    // ⑦ 落 buff（当日券的额度账；无道具档 = 没有券）。
    //    🔴 Guard-B13.11：第二张券改由**高级宝箱**给出（`chestBonusDropKind`）。
    //    旧存档（升级前写入、当天还没领）的第二张券在 `bonusDropKind` 里 ——
    //    两处取一个非 none 的，保证「升级当天不丢券」。
    final GuardBuffState? buff = guardBuffFor(state.dropKind);
    final GuardDropKind bonusKind =
        state.chestBonusDropKind != GuardDropKind.none
            ? state.chestBonusDropKind
            : state.bonusDropKind;
    final GuardBuffState? bonusBuff = guardBuffFor(bonusKind);
    final GuardDayState next = state.copyWith(
      status: GuardDayStatus.claimed,
      energyUsed: energyUsed,
      paidSun: paidSun,
      winSun: baseWinSun,
      bonusDropKind: bonusKind,
      buff: buff,
      clearBuff: buff == null,
      bonusBuff: bonusBuff,
      clearBonusBuff: bonusBuff == null,
      // ⑧ 幂等标记：本次领取已经把碎片 / 种子发过（`expire()` 据此不重发）。
      //    🔴 只有 `settled` 才置位 —— `portMissing` / `failed` 保持原值
      //    （「发不了 / 没发成」≠「已发完」）。
      chestExtrasGranted: state.chestExtrasGranted ||
          extras == _ChestExtrasOutcome.settled,
    );
    await _store.write(childId, next);

    final int energyAfter = await energyAvailable(now: at);
    return GuardClaimOutcome(
      ok: true,
      failure: GuardClaimFailure.none,
      alreadyClaimed: false,
      usedEnergy: free,
      paidSun: paidSun,
      winSun: winSun,
      drop: next.dropKind,
      bonusDrop: next.bonusDropKind,
      buff: buff,
      bonusBuff: bonusBuff,
      energyAvailable: energyAfter,
      balance: await _ledger.balance(),
      state: next,
      isPremium: _premium,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 四′、战斗偷窃落账（守卫战 v2 新增 · 领域层唯一新增公开方法）
  // ═══════════════════════════════════════════════════════════════════════

  /// 【守卫战 v2 新增，唯一】战斗结束时**一次性**落账本场被偷的阳光。
  ///
  /// 真源：`docs/花园守卫_守卫战玩法_增量设计_v1.md` §5.2 / §5.3（裁决 B）。
  ///
  /// ## 为什么是「结束时一次写」而不是「每偷一只写一次」
  /// 战斗态**不落盘**是红线：被偷额只在 `guard_battle_sim.dart` 的内存里累计，
  /// 打完一整场（全灭 / 到点）才由表现层带着合计调本方法 —— 同日最多 1 行
  /// `guard_stolen`，中途强杀 = 半场作废、从 0 重跑（方向偏向孩子）。
  ///
  /// ## 互斥去重（与 `expire` 的 `_settleSunLoss` 自动互斥）
  /// 账本 id 复用既有冻结格式 `guard_stolen_<childId>_<dayKey>`，且写入前先
  /// `countByRefTypeAndRefIdOnDay` 读判定 —— 同日已有 `guard_stolen` 行
  /// （本方法写过 / expire 半截时序写过）⇒ **空操作**，绝不双扣。反向同理：
  /// 战斗偷过之后再跨天 `expire`，`_settleSunLoss` 的同名读判定挡住重复扣。
  ///
  /// ## 钳制（双保险，绝不产生负余额）
  /// `min(本场合计, kGuardStealDailyCap=3, 当前余额)`；余额不足 1 ☀ 不写 0 元行。
  ///
  /// ## 🔴 零成长扣减
  /// 守卫战 v2 玄参裁定：怪物到门口**只偷阳光**。本方法不碰
  /// [PlantGrowthService] / `plant.progress`，`applyGrowthTheft` 语义原样。
  ///
  /// [stolenSun] = 战斗层累计的本场实际被偷合计（模拟器 `stolenSun`，已按
  /// 封顶逐怪裁过；这里再钳一次封顶是防表现层直传脏值的双保险）。
  /// 返回实际落账额（0 = 没偷 / 已写过 / 余额不足）。
  Future<int> recordBattleTheft({required int stolenSun, DateTime? now}) async {
    final DateTime at = now ?? _clock();
    final String childId = _childId();
    final String today = dayKey(at);
    if (stolenSun <= 0) return 0;
    // ① 互斥去重（账本读判定，事实源）：同日已有 guard_stolen 行 ⇒ 空操作。
    final int existing = await _ledger.countByRefTypeAndRefIdOnDay(
      kGuardStolenRefType,
      kGuardRefId,
      today,
    );
    if (existing > 0) return 0;
    // ② 余额钳制：余额 0 扣不出东西，绝不产生负余额（PRD 决策 D6）。
    final double balance = await _ledger.balance();
    if (balance <= 0) return 0;
    // ③ 封顶钳制：先钳全场封顶，再钳余额。
    final int capped =
        stolenSun > kGuardStealDailyCap ? kGuardStealDailyCap : stolenSun;
    final double charge = math.min(capped.toDouble(), balance);
    final int charged = charge.toInt();
    if (charged <= 0) return 0; // 余额不足 1 ☀：按 0 处理，不写 0 元账本行
    final double net = -charge;
    final bool written = await _appendLedger(SunlightEntry(
      id: 'guard_stolen_${childId}_$today',
      ts: at,
      type: SunlightType.plant,
      gross: net,
      net: net,
      balanceAfter: balance - charge,
      refType: kGuardStolenRefType,
      refId: kGuardRefId,
      dayKey: today,
    ));
    return written ? charged : 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 五、跨天过期（结算未处理的损失 + 清状态）
  // ═══════════════════════════════════════════════════════════════════════

  /// 跨天过期：结算**未处理**的损失，然后清掉过期存档。
  ///
  /// 三条空操作（🔴 都必须真的「一个字都不写」）：
  ///  · `state.dayKey == 今天` → 空操作（幂等：页面每次 `_reload` 都会调它）；
  ///  · `今天 < state.dayKey`（时钟回拨 / 用户改系统时间）→ 空操作，
  ///    绝不结算「未来的一天」，也不清档（否则回拨一下就把今天的存档删了）；
  ///  · 从未 resolve 过（没有存档）→ 空操作。
  ///
  /// 结算窗口封顶 [kGuardSettleMaxDays] = 1 天：本存储一天只有一条存档，
  /// 所以「离线一周回来」结算的也只是这一条，绝不按天数叠加（PRD 验收 A8）。
  ///
  /// 分支（互斥，顺序即优先级）：
  ///  1. 已领取 → 无损失；
  ///  2. 免罚档（余额不足）→ 无损失；
  ///  3. 进了战斗但没点「收下」（`fighting`）→ **视为已处理**：补发必得阳光、
  ///     不结算损失（PRD §3.6：孩子的动作已完成，账不能因 UI 中断倒退）；
  ///  4. 其余（`pending`）→ 扣阳光（钳到 0）+ 扣成长（走 [PlantGrowthService.raidGrowth]）。
  ///
  /// ## extras（碎片 / 种子）的重跑幂等
  /// `fighting` 分支补发 extras 之后，**先把 `chestExtrasGranted` 落到那条旧档上，
  /// 再清档**（见 ⑨ 的长注释）⇒ 「发完 extras、清档前被杀」的重进**不会再发**，
  /// 与 `claim()` 的幂等口径对称。残余窗口只剩「extras 已发 → 标记 write 完成」
  /// 之间那几毫秒（两个独立存储、无事务 ⇒ 无法消除）：恰好死在那里会**多发 1 次**。
  /// 方向偏向孩子，且在 `test/guard/guard_chest_grant_test.dart` 里写成断言。
  Future<GuardExpireOutcome> expire({DateTime? now}) async {
    final DateTime at = now ?? _clock();
    final String childId = _childId();
    final String today = dayKey(at);
    final GuardDayState stored = await _store.read(childId);

    // ① 同一天 → 空操作。
    if (stored.dayKey == today) return GuardExpireOutcome.none(today);
    // ② 时钟回拨（今天早于存档日）→ 空操作。
    if (stored.dayKey.compareTo(today) > 0) return GuardExpireOutcome.none(today);
    // ③ 从未 resolve 过（空白存档 / 存档被清）→ 只清不结算。
    if (!stored.hasThief) {
      await _store.clear(childId);
      return GuardExpireOutcome.none(today);
    }

    final String expiredDay = stored.dayKey;
    int stolenSun = 0;
    int growthTargets = 0;
    int grantedWinSun = 0;

    if (stored.isClaimed || stored.isFreeRide) {
      // 已领取 / 当天免罚 → 无损失。
    } else if (stored.status == GuardDayStatus.fighting) {
      // 已进战斗但没点「收下」→ 补发必得阳光（券已过期，不发 buff）。
      //
      // 🔴 Guard-B13.11【最高风险漏点】：金额必须走 `guardGrantWinSunOf`。
      //    漏改 ⇒ 完整版孩子打到**高级宝箱**后强杀 App（不点收下），次日只补发
      //    基础 3~5 ☀（白白少一半），而结算卡当时承诺的是翻倍值 —— 且他完全
      //    看不见原因（设计 §5.5 / R-01）。
      grantedWinSun = await _grantWinIfAbsent(
        childId: childId,
        dayKeyValue: expiredDay,
        winSun: guardGrantWinSunOf(stored),
        at: at,
        // 🔴 B10/B4：补发也要用**那一场**的 id（同日第二场不能撞第一场的行）。
        attempt: stored.battleAttempt,
      );
      // 🆕 碎片 / 种子**与阳光同批补发**（设计 §5.5 第 2 处必改）。
      //
      // 为什么 extras 跟着补发，而不是像 buff 一样「过期作废」：
      //  · 阳光与碎片/种子都是**永久账户收益**，buff 是**当日**增益 —— 既有分支
      //    「补发阳光、不发 buff」的分界线本来就在这里；
      //  · 若补阳光而不补碎片，「有没点收下」就变成了奖励内容的函数 ⇒ 违反
      //    「奖励与观看/点击行为零相关」的红线（PRD §7.3）。
      //
      // 🔴 P2-①：这里**不再**用「本次真的写进了 `guard_win` 行」(`grantedWinSun > 0`)
      //    当闸门 —— 那是把 `claim()` 的不变量**方向装反**了。
      //    旧闸门的漏洞（QA-1d 实证）：进程死在「写账本行」与「发 extras」之间 ⇒
      //    下次 `expire()` 里 `_grantWinIfAbsent` 因行已存在返回 0 ⇒ 闸门为假 ⇒
      //    extras 整段跳过 ⇒ **碎片/种子永久丢失**（且结算卡早已承诺过）。
      //    而 `claim()` 是反过来的（先 extras 再写账本，见 ⑤′ 的长注释）——
      //    同一个不变量两条路径方向相反，就是缺陷本身。
      //
      //    修法（保留顺序 + 换闸门，不改「先写账本后发 extras」的账本层幂等网）：
      //    幂等闸门**内移到** [_grantChestExtras] 自己身上 —— 它本来就会查
      //    `chestTier.isPremium` 与 `chestExtrasGranted`，所以**无条件调用**它
      //    自动满足「只有高级宝箱且标记未置位才发」。
      //    最坏结果：极端半截态（extras 已发、进程在 `clear` 之前又死一次）
      //    重跑时会再发一遍 —— 方向偏向孩子，
      //    与设计 §5.2「宁可极端崩溃多发，不永久吞」一致。
      //    ⚠️ 但**「多发 1 次」这个说法当时是错的**：不落盘标记时，重发次数
      //    跟着崩溃次数增长（无界）。真正的收口在下面，见 🔴 P2-①（收尾）。
      //
      //    为什么不选「把 extras 提到 `_grantWinIfAbsent` 之前」：账本层幂等网
      //    （`guard_win` 行）是「已补发」的事实源，把它挪到 extras 之后等于让
      //    「重跑」在**写账本之前**就能再发一遍 —— 那是把窗口放宽，不是收窄。
      //
      //    🔴 P2-①（收尾，原「最坏多发 1 片」的说法**不成立**，已改正）：
      //    原来这里只调用 `_grantChestExtras` 而**不落盘**标记 —— `expire()` 结尾
      //    直接 `_store.clear()`，`chestExtrasGranted` 在 expire 路径上永远是 false。
      //    于是真实保证不是「最多多发 1 次」，而是
      //    **「每次崩溃都会多发 1 次」（次数无界）**：只要进程反复死在
      //    「extras 已发 → clear 未完成」之间，每次重进都读到同一份 flag=false 的
      //    旧档 ⇒ 再发一遍。测试名不能宣称代码没有的保证，所以这里把窗口收掉。
      final _ChestExtrasOutcome extrasOutcome = await _grantChestExtras(stored);
      // 🔴 收口：**先把「已发完」落到旧档上，再清档**（见下面 ⑨ 的长注释）。
      if (extrasOutcome == _ChestExtrasOutcome.settled &&
          stored.chestTier.isPremium &&
          !stored.chestExtrasGranted) {
        try {
          await _store.write(
            childId,
            stored.copyWith(chestExtrasGranted: true),
          );
        } catch (_) {
          // 标记没落盘 ≠ 奖励没发：此时行为**退化**到修复前（窗口回到
          // 「extras → clear」），仍然只可能「多发」不可能「吞掉」—— 方向没变坏。
          // 绝不因为一次写失败把 expire() 打成异常：那会让跨天结算整个停摆。
          developer.log(
            'chestExtrasGranted persist failed => crash window falls back to '
            'the extras->clear gap (worst case: 1 duplicate grant, biased '
            'toward the kid); dayKey=$expiredDay, '
            'extra=$extrasOutcome',
            name: 'GuardService',
            level: 900, // Level.WARNING
          );
        }
      }
    } else {
      stolenSun = await _settleSunLoss(
        childId: childId,
        dayKeyValue: expiredDay,
        wanted: stored.sunStolen,
        at: at,
      );
      if (stored.growthStolen.isNotEmpty) {
        // 🔴 计数用 [PlantGrowthService.raidGrowth] 的返回值（实际扣到的株数）：
        //    存档里的 key 可能包含开花株（免疫）或已被铲除的株，按 `.length`
        //    报数会「说 2 实际扣 1」。该字段只进日志/埋点，无经济影响。
        // 注意：raidGrowth **不读时钟**，「结算发生在哪一刻」只影响账本行
        // （上面 `_settleSunLoss` 的 `at`），与成长扣减无关。
        growthTargets =
            await _growth.raidGrowth(lossByPlantId: stored.growthStolen);
      }
    }

    // ⑨ 清档（**必须在 extras 的幂等标记落盘之后**）。
    //
    // ## 为什么是「先 write 标记、再 clear」，而不是直接 clear
    // `claim()` 的 extras 幂等标记存在**当日状态**里（第 ⑦ 步随状态一起落盘），
    // 而 `expire()` 结算完就把那条状态删了 —— 标记没有「家」可落。于是修复前
    // `expire()` 路径上的 `chestExtrasGranted` **永远是 false**，「重跑幂等」全靠
    // 「clear 成功」这一件事。进程死在 extras 与 clear 之间时，标记仍是 false、
    // 旧档仍在 ⇒ 下次重进**必再发一遍**；反复崩溃 ⇒ **反复发**（次数无界）。
    //
    // 修法就是这里上面那一步 `_store.write(... chestExtrasGranted: true)`：
    // 把「已发完」先写成**持久事实**，再删档。于是崩溃窗口从
    //   · 修复前：`extras → clear 完成`（一旦 clear 长期失败 = **无界重放**）
    //   · 修复后：`extras → write 完成`（**write 一旦落盘就再也不会发**）
    // 也就是说，最坏次数从「崩溃次数 / 清档失败次数」压到「1 次」，
    // 与 `claim()` ⑤′→⑧ 的窗口同量级、同方向（宁可多发，不吞已承诺的奖励）。
    //
    // ⚠️ 残余窗口（已知、已接受，**不是**「已完全闭掉」）：进程若恰好死在
    //    「extras 已发 → 标记 write 完成」之间（几毫秒），重进会**再发 1 次**。
    //    这段窗口无法在无事务的 prefs 上消除 —— 除非把 extras 与标记做成同一个
    //    原子写，而 `BloomRewardRepository` 与 `GuardStateStore` 是两个独立存储。
    //    量级 ≈ 1e-6/天/次启动，方向偏向孩子；`test/guard/guard_chest_grant_test.dart`
    //    把它写成了**断言**（而不是愿望）。
    //
    // 为什么 write 不会覆盖掉不该动的字段：写的是 `stored`（本次刚读出来的那条
    // 旧档）经 `copyWith` 只改了这一个 bool；且此路径上 `expire()` 是唯一写者 ——
    // `resolve()` 的 `needsExpire` 闸门（见 [needsExpire]）会在旧档未结算时**拒写**，
    // 所以「读 → 写」之间不可能被一条新当天的存档插进来。
    //
    // 为什么 write 失败也要继续 clear：失败时标记没落盘 ⇒ 行为退化到修复前
    // （只可能多发、不会吞），而**不清档**的代价大得多（`needsExpire` 会一直为真，
    // 孩子整个玩法卡死）。两害相权，清。
    await _store.clear(childId);
    return GuardExpireOutcome(
      today: today,
      expiredDayKey: expiredDay,
      settled: true,
      stolenSun: stolenSun,
      growthTargets: growthTargets,
      grantedWinSun: grantedWinSun,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 七、调试接缝（🔴 仅 kDebugMode 使用，生产路径不得调用）
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 为什么放在领域层而不是调试面板里直接写 prefs：`GuardStateStore` 的文档
  // 明确规定「只由领域服务调用，页面不得直接写」。调试面板因此只能通过这四个
  // 方法造状态 —— 面板将来被删掉，这四个方法也只是无人调用，不会留下野路子写入。
  //
  // 四个方法一律**不抛异常**：调试工具写失败时最坏结果是「造不出来」，绝不
  // 应该把调试面板打成一条红屏错误（面板侧另有 `_snack` 提示）。

  /// 调试专用：今天强制刷出一个贼（绕过 [deriveGuardRoll] 的确定性派生）。
  ///
  /// 🔴 **仅 kDebugMode 使用，生产路径不得调用。**
  ///
  /// 只写今日状态，不碰账本、不扣钱。若今天已有存档则**覆盖**（调试就是要能反复造）。
  /// 与 [resolve] 的区别：resolve 有「昨天未结算就拒写」的闸门，本方法为调试便利
  /// **不走**该闸门。
  ///
  /// [thief] 默认取 `GuardThiefKind.values.first`（固定值，**不用 `Random()`**：
  /// 本项目全域禁用随机数，调试也要可复现）；[drop] 默认 [GuardDropKind.none]；
  /// [winSun] 默认 [kGuardWinSunMin]。写出的状态 `status` 恒为
  /// [GuardDayStatus.pending]（= 待处理，孩子可点胶囊开战）。
  ///
  /// 🔴 [drop] 非 [GuardDropKind.none] 时**同时发 buff**（[guardBuffFor] 单点派生）：
  /// 「刷新出偷菜贼（带免费浇水券）」如果只写 dropKind、不写 buff，那张券当天
  /// 根本用不了 —— 调试按钮就名不副实。无道具档仍为 `buff == null`。
  Future<void> forceThiefForDebug({
    GuardThiefKind? thief,
    GuardDropKind? drop,
    int? winSun,
    DateTime? now,
  }) async {
    final String today = dayKey(now ?? _clock());
    // 🔴 B12 修复（玄参第七轮：「每次战斗完都没有增益 buff 卡片掉落」）：
    // 旧实现 `drop ?? none` —— 调试重置会把**今天自然摇到的掉落档覆盖成
    // 「无道具」**，之后每一场的结算卡都显示「什么都没捡到」。修法 =
    // 未显式指定时**保留今天应有的掉落档**：
    //  · 当天已有**非空白**存档（status != none，即 resolve 已落过账）⇒
    //    原样保留其 dropKind / buff（重置只重摆怪，不擦券）；
    //  · 当天无存档 **或存档是空白态（empty，status == none）** ⇒ 走
    //    [GuardDropKind.roll]（与 [resolve] 同源、同 seed）。🔴 空白态也必须
    //    走 roll：真仓储「无存档 / 存档损坏」返回的是 `empty(今天)`，
    //    dayKey 恰好等于今天 —— 只比 dayKey 会把「今天还没 resolve 过」误判成
    //    「已存档」，从而拿到 empty 默认的 none（D1″ 回归测试钉死）。
    // 显式传 [drop] 仍可覆盖（调试面板「发券」走 [grantVoucherForDebug]）。
    final String childId = _childId();
    final GuardDayState stored = await _store.read(childId);
    final GuardDropKind dropKind;
    if (drop != null) {
      dropKind = drop;
    } else if (stored.dayKey == today &&
        stored.status != GuardDayStatus.none) {
      dropKind = stored.dropKind;
    } else {
      dropKind = GuardDropKind.roll(dayKey: today, childId: childId);
    }
    final GuardDayState next = GuardDayState(
      dayKey: today,
      status: GuardDayStatus.pending,
      thiefKind: thief ?? GuardThiefKind.values.first,
      winSun: winSun ?? kGuardWinSunMin,
      dropKind: dropKind,
      buff: guardBuffFor(dropKind),
      // 🔴 B10/B4：调试造贼 =「新的一场」。场次序号从账本当日 `guard_win` 行数
      // 派生 ⇒ 重置后再打一场，`guard_pay` / `guard_win` 的 id 自带 `_a1` 后缀，
      // 不会再被第一场的行去重掉（玄参「第二次花 5 阳光不扣」）。
      battleAttempt: await _nextBattleAttempt(today),
    );
    try {
      await _store.write(_childId(), next);
    } catch (_) {
      // 造不出来 = 存档保持原样，调试面板照常可用。
    }
  }

  /// 调试专用：把今日能量标记为「已全部用光」（[energyAvailable] 之后返回 0）。
  ///
  /// 🔴 **仅 kDebugMode 使用，生产路径不得调用。**
  ///
  /// 实现口径：把「已用能量」直接设成今天**赚到的总量**（档位上限
  /// [kGuardEnergyDailyMaxFree] / [kGuardEnergyDailyMaxPremium] 封顶后的值），
  /// 于是 `可用 = earned − used = 0`，与「连续用光两次能量」等价，
  /// 不新增任何字段。今天的存档不存在时以空白状态为底（只写 `energyUsed`）。
  ///
  /// 不抛异常：写失败一律吞掉。
  Future<void> exhaustEnergyForDebug({DateTime? now}) async {
    final DateTime at = now ?? _clock();
    final String today = dayKey(at);
    final int earned = await _energyEarnedOn(today);
    final String childId = _childId();
    final GuardDayState stored = await _store.read(childId);
    final GuardDayState base =
        stored.dayKey == today ? stored : GuardDayState.empty(today);
    try {
      await _store.write(childId, base.copyWith(energyUsed: earned));
    } catch (_) {
      // 写失败 = 能量照旧可用（孩子不会因此丢能量）。
    }
  }

  /// 调试专用：直接发一张今日券（= 把 `GuardDayState.buff` 设成
  /// [guardBuffFor] 的结果）。
  ///
  /// 🔴 **仅 kDebugMode 使用，生产路径不得调用。**
  ///
  /// [kind] 为 [GuardDropKind.none] 时 [guardBuffFor] 返回 `null` ⇒ **空操作**
  /// （一个字节都不写、不抛异常）。券的额度仍由 [guardBuffFor] 单点派生，
  /// 本方法**不复制**任何 quota 数字。
  ///
  /// 不抛异常：写失败一律吞掉。
  Future<void> grantVoucherForDebug(
    GuardDropKind kind, {
    DateTime? now,
  }) async {
    final GuardBuffState? buff = guardBuffFor(kind);
    if (buff == null) return; // 无道具档：没有券可发（空操作）
    final String today = dayKey(now ?? _clock());
    final String childId = _childId();
    final GuardDayState stored = await _store.read(childId);
    final GuardDayState base =
        stored.dayKey == today ? stored : GuardDayState.empty(today);
    try {
      await _store.write(
        childId,
        base.copyWith(dropKind: kind, buff: buff),
      );
    } catch (_) {
      // 发券失败 = 今天照旧没有券，不影响孩子既有进度。
    }
  }

  /// 调试专用：清空今日守卫存档（[GuardStateStore.clear]）。
  ///
  /// 🔴 **仅 kDebugMode 使用，生产路径不得调用。**
  ///
  /// [now] 仅为与其余三个接缝**签名一致**：`clear` 按 childId 整条删除，
  /// 与日期无关（不会误删别的孩子的存档）。
  ///
  /// 不抛异常：清失败一律吞掉（调试面板不会因此弹红条）。
  Future<void> resetForDebug({DateTime? now}) async {
    try {
      await _store.clear(_childId());
    } catch (_) {
      // 清失败 = 存档还在，重新点一次即可。
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 八、内部工具
  // ═══════════════════════════════════════════════════════════════════════

  /// 存活株（`dead` 之外都算：`growing` / `wilting` / `bloomed`）。
  ///
  /// 开花株在成长扣减里免疫（纯函数负责），但**仍会被偷阳光** —— 所以它算存活。
  Future<List<Plant>> _alivePlants() async {
    final List<Plant> all = await _plants.plants();
    return <Plant>[
      for (final Plant plant in all)
        if (plant.status != PlantStatus.dead) plant,
    ];
  }

  /// 今天这条状态是否已经结算过（有贼 / 已领取 / 免罚，三者之一）。
  bool _isResolved(GuardDayState state) {
    return state.hasThief ||
        state.status == GuardDayStatus.claimed ||
        state.status == GuardDayStatus.short;
  }

  /// 这条（过期的）存档里是否还有「必须由 [expire] 处理」的东西：
  /// 有贼 **且** 既没领取也不是免罚档 —— 即「昨天的损失 / 补发还欠着」。
  ///
  /// `resolve()` 用它挡住「页面先 resolve、后 expire」的时序：那种顺序会把昨天的
  /// `sunStolen` / `growthStolen` 直接覆盖掉，等于永久丢掉一天的对账依据。
  bool _needsSettlement(GuardDayState state) {
    if (!state.hasThief) return false;
    if (state.isClaimed) return false;
    if (state.isFreeRide) return false;
    return true;
  }

  /// 成本模式（回放用：状态已定，用「有没有花钱」反推）。
  GuardCostMode _costModeOf(GuardDayState state, int energy, double balance) {
    if (state.paidSun > 0) return GuardCostMode.paid;
    if (state.status == GuardDayStatus.short) return GuardCostMode.freeRide;
    if (state.isClaimed) return GuardCostMode.free;
    if (energy >= kGuardEnergyPerFocus) return GuardCostMode.free;
    return balance >= kGuardPayCost
        ? GuardCostMode.paid
        : GuardCostMode.freeRide;
  }

  /// 今日成长损失（`plantId -> pp`）。
  ///
  /// · 贪婪鼬（`hitsEveryPlant`）→ 全部存活株各一份（开花株免疫，由纯函数跳过）；
  /// · 食叶虫（`targetsSingleRandomPlant`）→ **确定性挑 1 株**（禁 `Random`：
  ///   存活株 id 升序后按 `kGuardChannelTargetPlant` 通道哈希落桶）；
  /// · 馋光鼠（不偷成长）→ 空。
  Map<String, double> _growthLossOf(
    GuardRoll roll,
    List<Plant> alive,
    String dayKeyValue,
  ) {
    if (!roll.stealsGrowth) return const <String, double>{};
    final GuardThiefSpec spec = roll.thief.spec;

    if (spec.hitsEveryPlant) {
      return <String, double>{
        for (final Plant plant in alive) plant.id: roll.growthLossPercent,
      };
    }
    if (!spec.targetsSingleRandomPlant) return const <String, double>{};

    // 只从「可能被扣」的株里挑：开花株免疫，挑到它就是白来一趟。
    final List<String> ids = <String>[
      for (final Plant plant in alive)
        if (plant.status != PlantStatus.bloomed) plant.id,
    ]..sort();
    if (ids.isEmpty) return const <String, double>{};
    final double u = deterministicUniform(
      dayKey: dayKeyValue,
      childId: _childId(),
      salt: kGuardDaySaltV2,
      channel: kGuardChannelTargetPlant,
    );
    final int index = (u * ids.length).floor().clamp(0, ids.length - 1);
    return <String, double>{ids[index]: roll.growthLossPercent};
  }

  /// 账本 id 的**场次后缀**（B10/B4）：第 1 场（`attempt <= 0`）返回空串。
  ///
  /// 🔴 生产路径一天一场 ⇒ 恒为空串 ⇒ `guard_pay_<child>_<day>` /
  /// `guard_win_<child>_<day>` 与历史 id **逐位相同**（老账本零影响、老测试零改动）。
  /// 只有同日第二场起追加 `_a1` / `_a2` …，让「同一天第二次付费 / 到账」能落成
  /// 独立一行而不是被主键去重静默丢弃。
  static String _attemptSuffixOf(int attempt) => attempt > 0 ? '_a$attempt' : '';

  /// 当日**新场次的序号** = 当日已完成的 `guard_win` 行数（每场恰好一行）。
  ///
  /// 只在 `resolve()` / `forceThiefForDebug()` **生成当日状态时**调用一次，
  /// 随后冻结在 [GuardDayState.battleAttempt] 里 —— 领取过程中不再重算，
  /// 否则「第一场写成功、prefs 写失败再重试」会把重试当成新场次重复扣钱。
  ///
  /// 🔴 读账本失败一律退化为 **0**（= 第 1 场）：这是「账本抖动 / 测试假仓储
  /// 没实现该查询」时的安全方向 —— 退化成旧行为（一天一场），绝不会让
  /// `resolve()` / 调试接缝因为一个统计量而抛异常。
  Future<int> _nextBattleAttempt(String today) async {
    try {
      final int done = await _ledger.countByRefTypeAndRefIdOnDay(
        kGuardWinRefType,
        kGuardRefId,
        today,
      );
      return done > 0 ? done : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 发放**高级宝箱附加奖励**（植物碎片 / 种子）—— 本类是该仓储在守卫链路上的
  /// **唯一调用点**。
  ///
  /// ## 为什么碎片/种子不进阳光账本（与「唯一落账入口」不冲突）
  /// `plant_growth_service.dart` 的 `_grantInstantReward()` 早已立下口径：
  /// **种子 / 碎片不走账本**。它们是账户级藏品（[BloomRewardRepository]），
  /// 不是阳光货币。`claim()` 仍是**唯一**写 `guard_pay` / `guard_win` 的方法，
  /// 本次没有新增任何一处账本写入（翻倍只是金额变化，行数与 id 一字不变）。
  ///
  /// ## 口径
  ///  · 只有 [GuardChestTier.premium] 且有附加项时才发（普通宝箱一分不多给）；
  ///  · [GuardDayState.chestExtrasGranted] 已置位 ⇒ 空操作（幂等）；
  ///  · 种子：该物种**已持免费种植券**（[BloomRewardRepository.unlockedSpeciesIds]）
  ///    ⇒ 按玄参 2026-09-29 口径**自动分解**为碎片
  ///    （普通 [kDuplicateSeedDecomposeFragmentsCommon] /
  ///    精英 [kDuplicateSeedDecomposeFragmentsPremium]），不重复写券；
  ///  · 碎片：在既有余额上**只做正向加**（[BloomRewardRepository.setPremiumFragmentBalance]
  ///    是覆盖式 upsert，所以必须先读再写）。
  ///
  /// ⚠️ `unlockedSpeciesIds()` 读的是**发放前**快照 ⇒「同一天既发碎片又发种子」
  /// 不会被误判成重复；一天最多掉 1 颗种子，跨天共享同一份「已持券」集合是
  /// 正确语义（持券 = 免费种植券，用掉就消失）。
  ///
  /// ## 返回值（🔴 P2-②：三态，不是 bool）
  /// 见 [_ChestExtrasOutcome]：
  ///  · [settled] = 本次「已发完 / 本来就不需要发」⇒ 调用方**可以**置
  ///    [GuardDayState.chestExtrasGranted]；
  ///  · [portMissing] = 端口未注入 ⇒ **一片都没发**，调用方**绝不能**置标记
  ///    （「发不了」≠「已发完」，否则补好 DI 也永不补发）；
  ///  · [failed] = 仓储抖动导致没发成 ⇒ 不置标记，留给下一次 `expire()` 重试。
  ///
  /// 仓储异常**一律吞掉**：碎片发不出去是「少一件藏品」，而让 `claim()` 抛异常
  /// 会把孩子卡在「点了没反应」—— 与 `_appendLedger` 同一套取舍。
  Future<_ChestExtrasOutcome> _grantChestExtras(GuardDayState s) async {
    // 顺序有意：先判「本来就无需发放」（标记已置位 / 普通宝箱），再判端口 ——
    // 否则一个「普通宝箱 + 漏接线」的装配会天天刷一条没有意义的告警日志。
    if (s.chestExtrasGranted) return _ChestExtrasOutcome.settled;
    if (!s.chestTier.isPremium) return _ChestExtrasOutcome.settled;

    final BloomRewardRepository? repo = _bloomRewards;
    if (repo == null) {
      // 🔴 P2-②：口头承诺过「拿到碎片」却因为一根没接的线静默清零，
      //    真机上一次都定位不到（只能看出「余额不动」）。这里留一行日志。
      //
      //    为什么用 `dart:developer` 而不是 `debugPrint`：领域层**零 flutter**
      //    （同文件 339 行处「不引 package:meta」的理由同源；`guard_state_store.dart`
      //    文件头也写明本层要「可纯 Dart 直跑」）。`log()` 是 SDK 里唯一不引
      //    flutter 的日志通道，`flutter run` / DevTools 的 Logging 视图能直接看到。
      developer.log(
        'bloomRewards port not injected => premium chest fragments/seeds were '
        'NOT granted '
        '(chestFragmentQty=${s.chestFragmentQty}, '
        'chestSeedKind=${s.chestSeedKind.id}, '
        'chestSeedSpeciesId=${s.chestSeedSpeciesId}); '
        'the idempotency flag stays unset, so wiring the port later can still '
        'grant them.',
        name: 'GuardService',
        level: 900, // Level.WARNING
      );
      return _ChestExtrasOutcome.portMissing;
    }

    int fragments = s.chestFragmentQty > 0 ? s.chestFragmentQty : 0;
    final String? species = s.chestSeedSpeciesId;
    try {
      if (s.chestSeedKind != GuardSeedKind.none && species != null) {
        final Set<String> owned = await repo.unlockedSpeciesIds();
        if (owned.contains(species)) {
          // 重复种子 → 自动分解为碎片（玄参 2026-09-29 口径，常量复用）。
          fragments += s.chestSeedKind == GuardSeedKind.premium
              ? kDuplicateSeedDecomposeFragmentsPremium
              : kDuplicateSeedDecomposeFragmentsCommon;
        } else {
          // 幂等（speciesId 主键冲突合并）。
          await repo.unlockSpecies(species);
        }
      }
      if (fragments > 0) {
        final int now = await repo.premiumFragmentBalance();
        await repo.setPremiumFragmentBalance(now + fragments);
      }
      return _ChestExtrasOutcome.settled;
    } catch (_) {
      // 仓储抖动：不置 `chestExtrasGranted`，等下一次 expire() 重试。
      return _ChestExtrasOutcome.failed;
    }
  }

  /// 写一行账本（**幂等**）：主键冲突 = 同一天已经写过这一行 ⇒ 视为已写过。
  /// DAO 是 `insert`（`InsertMode.insert`），重复主键会抛 —— 捕获它就把
  /// 「重复点击 / 重放」变成了天然幂等，无需额外锁或去重表。
  /// 其余异常同样吞掉：账本写失败时**不能**让孩子卡在「点了没反应」，
  /// 而调用方随后会用自己的读判定（[SunlightRepository.countByRefTypeAndRefIdOnDay]）
  /// 确认事实，最坏结果是「少发一次」而不是「重复发」。
  Future<bool> _appendLedger(SunlightEntry entry) async {
    try {
      await _ledger.append(entry);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 扣「未处理被偷」的阳光：**钳到余额为 0 为止**，且同一天只扣一次。
  ///
  /// 返回实际扣掉的阳光（整数 ☀；0 = 没扣）。
  Future<int> _settleSunLoss({
    required String childId,
    required String dayKeyValue,
    required int wanted,
    required DateTime at,
  }) async {
    if (wanted <= 0) return 0;
    final int existing = await _ledger.countByRefTypeAndRefIdOnDay(
      kGuardStolenRefType,
      kGuardRefId,
      dayKeyValue,
    );
    if (existing > 0) return 0; // 已经结算过这一天
    final double balance = await _ledger.balance();
    if (balance <= 0) return 0; // 余额 0：扣不出东西，绝不产生负余额
    final double charge = math.min(wanted.toDouble(), balance);
    final int charged = charge.toInt();
    if (charged <= 0) return 0; // 余额不足 1 ☀：按 0 处理，不写 0 元账本行
    final double net = -charge;
    await _appendLedger(SunlightEntry(
      id: 'guard_stolen_${childId}_$dayKeyValue',
      ts: at,
      type: SunlightType.plant,
      gross: net,
      net: net,
      balanceAfter: balance - charge,
      refType: kGuardStolenRefType,
      refId: kGuardRefId,
      dayKey: dayKeyValue,
    ));
    return charged;
  }

  /// 「进了战斗但没点收下」的补发：同一天同一场只发一次（确定性 id + 账本读判定）。
  ///
  /// 🔴 B10/B4：[attempt] 是那一场的序号 —— 判据收窄为「当日行数 > 本场序号」，
  /// id 按 [_attemptSuffixOf] 追加后缀（第 1 场无后缀，与历史逐位相同）。
  Future<int> _grantWinIfAbsent({
    required String childId,
    required String dayKeyValue,
    required int winSun,
    required DateTime at,
    int attempt = 0,
  }) async {
    final int amount = winSun > 0 ? winSun : kGuardWinSunNoItem;
    final int existing = await _ledger.countByRefTypeAndRefIdOnDay(
      kGuardWinRefType,
      kGuardRefId,
      dayKeyValue,
    );
    if (existing > attempt) return 0;
    final double balance = await _ledger.balance();
    final bool written = await _appendLedger(SunlightEntry(
      id: 'guard_win_${childId}_$dayKeyValue${_attemptSuffixOf(attempt)}',
      ts: at,
      type: SunlightType.earn,
      gross: amount.toDouble(),
      net: amount.toDouble(),
      balanceAfter: balance + amount,
      refType: kGuardWinRefType,
      refId: kGuardRefId,
      dayKey: dayKeyValue,
    ));
    return written ? amount : 0;
  }

  /// 失败结果（**零副作用**：不写账本、不改存档）。
  GuardClaimOutcome _claimFailure(
    GuardClaimFailure failure, {
    required GuardDayState state,
    required int energy,
    required double balance,
  }) {
    return GuardClaimOutcome(
      ok: false,
      failure: failure,
      alreadyClaimed: false,
      usedEnergy: false,
      paidSun: 0,
      winSun: 0,
      drop: state.dropKind,
      buff: state.buff,
      energyAvailable: energy,
      balance: balance,
      state: state,
      isPremium: _premium,
    );
  }

  /// 幂等回放（已领取）：**不再记任何账**。
  GuardClaimOutcome _claimReplay(
    GuardDayState state, {
    required int energy,
    required double balance,
  }) {
    return GuardClaimOutcome(
      ok: true,
      failure: GuardClaimFailure.none,
      alreadyClaimed: true,
      usedEnergy: state.paidSun <= 0,
      paidSun: state.paidSun,
      // 🔴 Guard-B13.11：`state.winSun` 存的是**基础值**，实际到账额要走
      // `guardGrantWinSunOf`（高级宝箱 ×2）—— 回放必须与账本行逐位相等。
      winSun: guardGrantWinSunOf(state),
      drop: state.dropKind,
      bonusDrop: state.chestBonusDropKind != GuardDropKind.none
          ? state.chestBonusDropKind
          : state.bonusDropKind,
      buff: state.buff,
      energyAvailable: energy,
      balance: balance,
      state: state,
      isPremium: _premium,
    );
  }
}
