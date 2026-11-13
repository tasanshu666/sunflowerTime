/// 高级宝箱的**领域派生**（零 IO、零副作用、零 flutter import、零 `Random`）。
///
/// 真源：`docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §3（含玄参 2026-11-11
/// 第九轮的三处覆写：种子 **5%**、碎片 **1~2 片**、其余不变）。
///
/// ## 🔴 两条纪律（改这个文件前先读）
/// 1. **通道冻结**：全部均匀值来自 `core/utils/stable_hash.dart` 的
///    `deterministicUniform(dayKey, childId, kGuardDaySaltV2, channel)`，通道名
///    定义在 `prd_params.dart`（`kGuardChannelChest*`）。**改了通道字符串 =
///    让历史每一天的宝箱内容全部重掷**（同一 `dayKey` 在不同版本上得到不同的
///    经济结果）。只能追加新通道，不能改名。
/// 2. **唯一派生口**：宝箱档位与全部开箱内容**只**由 [deriveGuardChest] 产生，
///    **只**由 `GuardService.resolve()` 落盘一次。表现层（演出 / 结算卡）与
///    发放层（`claim()` / `expire()`）一律**读落盘结果**，不得自己重算 ——
///    重算就等于第二套经济账，「跳过与看完拿到逐位相同的结果」这条红线会失效。
///
/// ## 四类奖励各自一条通道（互不相关）
/// | 奖励 | 闸门通道 | 取值通道 | 概率（高级宝箱内） |
/// |---|---|---|---|
/// | 箱体档位 | `chest_tier` | — | 30%（完整版；免费恒普通）🔴 B13.14：原 20% |
/// | 首张券（高级箱重挑） | — | `chest_first_pick` | 100%（🔴 B13.20：全券池 9 选 1，免费券只在这里出现） |
/// | 第二张券 | `chest_bonus_gate` | `chest_bonus_pick` | 20%（且当天首张已掉券）🔴 B13.14：原 10% |
/// | 植物碎片 | `chest_fragment_gate` | `chest_fragment_qty` | 10%（数量 1~2 各半）🔴 B13.14：原 5% |
/// | 植物种子 | `chest_seed_gate` | `chest_seed_pick` | 5%（档位各半，档内等概率） |
/// | 第二张券候选池 | — | — | 除首张外 **8 选 1**（B13.20 券库 9 种，动态取 values） |
///
/// 复用同一个通道会把两件事绑死（「命中碎片的日子必然命中双券」），分布检验
/// 立刻能抓到这种相关性 —— 这正是 `stable_hash.dart` 文件头立下的域隔离纪律。
library guard_chest_math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';

/// **确定性派生**：给定 `dayKey + childId + 权益档位 + 已定死的首张券`，
/// 算出今天的宝箱档位与全部开箱内容。
///
/// 纯函数：同一入参恒得同一结果（禁 `Random`、不读时钟、不读余额）。
///
/// ## 入参 [drop] 的语义
/// 它是**已经**由 [deriveGuardRoll] 定死的「普通宝箱首张券」（5 种非免费券池 /
/// 无道具）。普通宝箱日原样透传为 [GuardChestRoll.firstDrop]；**高级宝箱日**
/// 则用 `chest_first_pick` 通道从**全券池 9 种**等概率重挑并覆盖 —— 这是
/// B13.20「免费券只在高级宝箱」的实现点（高级箱首张可能是一张免费券）。
///
/// ## 分支（顺序即语义）
/// ① 档位：`isPremium && u(chest_tier) < 0.30` ⇒ 高级，否则普通。
///    🔴 免费档**恒普通**（不掷任何其它通道、直接早返回）—— 付费墙的唯一
///    判据在 `isPremium` 上，不是「u 掷到了就送」。
/// ② 普通宝箱：首张券 = [drop] 透传，无附加项 ⇒ 早返回，
///    **不掷其它通道**（省下的哈希不会影响任何既有通道）。
/// ③ 高级宝箱：首张券全池重挑 + 依次掷双券 / 碎片 / 种子，三者**互不影响**。
GuardChestRoll deriveGuardChest({
  required String dayKey,
  required String childId,
  required bool isPremium,
  required GuardDropKind drop,
}) {
  /// 取某通道的 `[0,1)` 均匀值（通道隔离，见文件头）。
  double u(String channel) => deterministicUniform(
        dayKey: dayKey,
        childId: childId,
        salt: kGuardDaySaltV2,
        channel: channel,
      );

  // ① 档位：🔴 免费档恒普通（判据 = isPremium && u < 0.30）。
  final bool premiumChest =
      isPremium && u(kGuardChannelChestTier) < kGuardChestPremiumChance;
  if (!premiumChest) {
    // ② 普通宝箱：首张券透传 + 没有任何附加项 ⇒ 早返回，不掷其它通道。
    return GuardChestRoll(tier: GuardChestTier.normal, firstDrop: drop);
  }

  // ③-0 首张券全池重挑（🔴 B13.20）：9 种券（含 4 张免费券）等概率。
  //     付费档普通宝箱日必掉券（无道具率 = 0），故全池重挑**不会**把
  //     「必掉券」的日子变成无券日 —— 重挑结果只会在 9 种券里。
  final List<GuardDropKind> firstPool = GuardDropKind.premiumChestFirstPool;
  final double firstU = u(kGuardChannelChestFirstPick);
  final GuardDropKind first =
      firstPool[(firstU * firstPool.length).floor().clamp(0, firstPool.length - 1)];

  // ③-1 双 buff 券（20%）：🔴 必须首张已掉券（没有第一张就没有「第二张」）。
  GuardDropKind bonus = GuardDropKind.none;
  if (first != GuardDropKind.none &&
      u(kGuardChannelChestBonusGate) < kGuardChestBonusChance) {
    bonus = _pickOtherVoucher(first, u(kGuardChannelChestBonusPick));
  }

  // ③-2 植物碎片（10% ⇒ 片数由独立通道取 1 或 2，各 50%）。
  int fragmentQty = 0;
  if (u(kGuardChannelChestFragmentGate) < kGuardChestFragmentChance) {
    final double qtyU = u(kGuardChannelChestFragmentQty);
    fragmentQty =
        qtyU < 0.5 ? kGuardChestFragmentQtyMin : kGuardChestFragmentQtyMax;
  }

  // ③-3 种子（5%）：一个 `u` 同时决定档位（各 50%）与档内物种（等概率）。
  GuardSeedKind seedKind = GuardSeedKind.none;
  String? seedSpecies;
  if (u(kGuardChannelChestSeedGate) < kGuardChestSeedChance) {
    final double pick = u(kGuardChannelChestSeedPick);
    final bool elite = pick < 0.5;
    seedKind = elite ? GuardSeedKind.premium : GuardSeedKind.common;
    final List<String> pool =
        elite ? kGuardSeedSpeciesPremium : kGuardSeedSpeciesCommon;
    // 用 pick 的**小数部分**取物种：`pick × 2 ∈ [0,2)`，取小数即得 `[0,1)`
    // 的均匀值 ⇒ 与「档位判据（pick < 0.5）」天然独立，无需第二个通道。
    final double frac = (pick * 2) % 1.0;
    seedSpecies = pool[(frac * pool.length).floor().clamp(0, pool.length - 1)];
  }

  return GuardChestRoll(
    tier: GuardChestTier.premium,
    firstDrop: first,
    bonusDrop: bonus,
    fragmentQty: fragmentQty,
    seedKind: seedKind,
    seedSpeciesId: seedSpecies,
  );
}

/// 本场**实际到账**的必得阳光（高级宝箱 ×2）。
///
/// 🔴 **三个发放点必须都读它**：`GuardService.claim()` / `expire()` 的
/// `fighting` 补发分支 / 任何调试接缝。任一地方漏读 ⇒ 高级宝箱用户在
/// 「强杀 App 次日补发」路径上少拿一半阳光，且**完全看不见原因**（结算卡
/// 承诺了 +8，账本只 +4）。
///
/// [GuardDayState.winSun] 存的**永远是基础值**（3~5），翻倍只在这里做 ——
/// 这样老存档的 `winSun` 语义一字不变，也不会出现「已翻倍的值再翻一次」。
int guardGrantWinSunOf(GuardDayState s) {
  final int base = s.winSun > 0 ? s.winSun : kGuardWinSunNoItem;
  return s.chestTier.isPremium ? base * 2 : base;
}

// ── 内部工具 ──────────────────────────────────────────────────────────────

/// 从「除 [exclude] 外的券」里等概率挑一张（`none` 永不入选；B13.20 起
/// 券库 9 种 ⇒ 除首张外 8 选 1）。
///
/// 与 `GuardDropKind.rollBonus` 的候选表口径**完全一致**（玄参 B13.5 原话
/// 「掉落 2 张**不同的** buff 卡券」），但走高级宝箱自己的通道
/// [kGuardChannelChestBonusPick]：旧通道 `drop_bonus_pick` 已停止调用
/// （保留常量只为历史 `deriveGuardRoll` 可重放）。
GuardDropKind _pickOtherVoucher(GuardDropKind exclude, double u) {
  final List<GuardDropKind> candidates = GuardDropKind.values
      .where((GuardDropKind k) => k != GuardDropKind.none && k != exclude)
      .toList();
  if (candidates.isEmpty) return GuardDropKind.none;
  return candidates[
      (u * candidates.length).floor().clamp(0, candidates.length - 1)];
}
