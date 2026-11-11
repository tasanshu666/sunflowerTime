/// 花园守卫的**领域纯函数**（零 IO、零副作用、零 flutter import，可 `dart test` 直跑）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.4 / §3.5 / §3.7 / §14.1。
///
/// ## 为什么全部做成纯函数
/// 守卫玩法的三条经济红线（PRD §5）全部落在「算」上：
///  1. **确定性**：同一 `dayKey + childId` 必须永远得到同一结果（禁 `Random`）——
///     否则「跳过动画」与「看完动画」会变成两条不同的经济路径（违反「奖励与观看
///     时长零相关」）；
///  2. **封顶**：每株每天最多被偷 [kGuardGrowthStealPerPlantDailyCap]，否则 30 天
///     成株会变成 37.5 天（= 第二个成长系统）；
///  3. **单株限制 + 累计封顶**：免费券绝不整批、浇水券/劳动券当日封顶，否则一键
///     批量会把券放大 5~6 倍（`test/guard/guard_math_test.dart` 钉死 A10/A11/A12）。
///
/// 纯函数化后这三条全部可以单测，不依赖数据库、不依赖时钟。
///
/// ## 三个函数
///  · [deriveGuardRoll] —— 确定性派生「来哪只贼 / 偷多少 / 掉什么 / 保底几 ☀」；
///  · [applyGrowthTheft] —— 成长扣减（封顶 + 阶段不回退 + 开花株免疫 + 死亡株跳过）；
///  · [voucherSavingOf] —— 一张券在「这批盆 / 这株」上省了多少（不含当日累计记账）。
library guard_math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

// ── 确定性通道名（🔴 一经写入即冻结）────────────────────────────────────
//
// 通道（channel）是**域隔离**手段：同一 `dayKey + childId` 下，五个通道的均匀值
// 必须互不相关。否则「来的是贪婪鼬」会与「掉落档」绑死（抽到贪婪鼬必定出免费
// 施肥券），单测的分布检验会立刻暴露这种相关性。
// 注意 `thief` / `drop` 两个通道分别定义在 guard_thief.dart / guard_drop.dart
// （谁拥有枚举谁定义通道），本文件只定义「贼的取值」相关的三个通道。

/// 通道：偷阳光的数量。
const String _channelSun = 'sun';

/// 通道：偷成长的百分点。
const String _channelGrowth = 'growth';

/// 通道：必得阳光（3~5；B5b 玄参拍板，原 1~3）。
const String _channelWinSun = 'win';

/// 一次派生的**完整结果**（不可变）。
///
/// `resolve()` 在拿到它的那一刻就把结果落盘；奖励发放只认落盘结果，所以
/// 「跳过」与「看完」拿到的奖励逐位相同（PRD §7.3 第一条红线）。
///
/// ⚠️ 战斗动画**不**消费本类：剧本由 `deriveGuardBattleScript` 独立派生
/// （同 dayKey + childId ⇒ 同一条剧本）。玄参 2026-11-11 裁定「战斗回放不做」，
/// 本类保留为观测/测试用。
class GuardRoll {
  /// 今天来的是哪只贼。
  final GuardThiefKind thief;

  /// 每株被偷走的成长量，单位 = 进度比例（`0.03` = 3 个百分点 pp）。
  ///
  /// `0` = 这只贼不偷成长（馋光鼠）。**未取整**：区间内连续取值，交给
  /// [applyGrowthTheft] 去和 [kGuardGrowthStealPerPlantDailyCap] 比较。
  final double growthLossPercent;

  /// 被偷走的阳光，单位 ☀。`0` = 这只贼不偷阳光（食叶虫）。
  final int sunLoss;

  /// 掉落档。
  final GuardDropKind drop;

  /// 🔴 B13.5 / Guard-B13.10：第二张券（`none` = 今天没有；「10% 掉 2 张不同的」）。
  ///
  /// 🔴 **完整版专属**（玄参 2026-11-11 裁定）：「双倍掉落券对免费档不生效」——
  /// 免费档（`isPremium == false`）的该字段**恒为** [GuardDropKind.none]。
  /// gate 只有一个落点：本类的产出方 [deriveGuardRoll]（见该函数的注释）。
  final GuardDropKind bonusDrop;

  /// 必得阳光（3~5；B5b 起无道具档固定 [kGuardWinSunNoItem] = 区间上限 5）。
  final int winSun;

  const GuardRoll({
    required this.thief,
    required this.growthLossPercent,
    required this.sunLoss,
    required this.drop,
    this.bonusDrop = GuardDropKind.none,
    required this.winSun,
  });

  /// 今天会不会掉成长（贪婪鼬 / 食叶虫）。
  bool get stealsGrowth => growthLossPercent > 0;

  /// 今天会不会掉阳光（馋光鼠 / 贪婪鼬）。
  bool get stealsSun => sunLoss > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardRoll &&
          other.thief == thief &&
          other.growthLossPercent == growthLossPercent &&
          other.sunLoss == sunLoss &&
          other.drop == drop &&
          other.winSun == winSun;

  @override
  int get hashCode =>
      Object.hash(thief, growthLossPercent, sunLoss, drop, winSun);

  @override
  String toString() => 'GuardRoll(${thief.id}, sunLoss=$sunLoss, '
      'growthLoss=$growthLossPercent, drop=${drop.id}, winSun=$winSun)';
}

/// ① **确定性派生**：给定 `dayKey + childId`，算出今天来哪只贼、偷多少、掉什么。
///
/// seed = `dayKey|childId<kGuardDaySaltV2>|<通道>`；纯函数，同一入参恒得同一结果，
/// **绝无 `Random`**、不读时钟、不读余额（余额只影响「花不花得起」，不影响「掉什么」）。
///
/// 口径（PRD §3.4 / §3.7）：
///  · 贼的种类按 [kGuardThiefWeights]（0.45 / 0.45 / 0.10）落桶；
///  · 偷阳光：只有 `stealsSun` 的贼才掷，落在 `[kGuardSunStealMin, kGuardSunStealMax]`
///    的**闭区间整数**（1/2/3 各 1/3）；
///  · 偷成长：只有 `stealsGrowth` 的贼才掷，落在
///    `[growthStealMinPct, growthStealMaxPct)` 的连续值（食叶虫 1~3%、贪婪鼬 1~5%）；
///  · 掉落按 6 档概率落桶；**无道具档的必得阳光固定取上限**（决策 D2 / R1）；
///  · 第二张券（[kGuardDropDualChance] = 10%）🔴 **仅完整版档才掷**，且必须首张
///    已掉券（`drop != none`）—— 免费档的 [GuardRoll.bonusDrop] 恒 `none`
///    （Guard-B13.10，玄参 2026-11-11「双倍掉落券对免费档不生效」）。
GuardRoll deriveGuardRoll({
  required String dayKey,
  required String childId,
  bool isPremium = false,
}) {
  final GuardThiefKind thief =
      GuardThiefKind.roll(dayKey: dayKey, childId: childId);
  // 🔴 B13.5：掉落分档（免费 none=50% / 完整版必掉券）+ 10% 第二张券。
  final GuardDropKind drop = GuardDropKind.roll(
    dayKey: dayKey,
    childId: childId,
    isPremium: isPremium,
  );
  // 🔴 Guard-B13.10（玄参 2026-11-11 裁定）：「双倍掉落券」收紧为**完整版专属** ——
  //    免费档永不出第二张。本 gate 是**唯一**的档位判据，条件两颗都必须成立：
  //     ① `isPremium == true`（档位门槛，免费档恒 `none`，连通道都不掷）；
  //     ② `drop != none`（首张没券 ⇒ 没有第二张；与 B13.5 原语义一致）。
  //    注意**不要**把 gate 挪进 [GuardDropKind.rollBonus]：那个函数是纯「掷」的
  //    低层工具，档位语义属于本函数（离档位最近的唯一入口）。
  final GuardDropKind bonusDrop =
      isPremium && drop != GuardDropKind.none
          ? (GuardDropKind.rollBonus(
              dayKey: dayKey,
              childId: childId,
              exclude: drop,
            ) ??
            GuardDropKind.none)
          : GuardDropKind.none;
  final GuardThiefSpec spec = thief.spec;

  // 偷阳光：不看余额、不封顶（余额钳到 0 是「扣账」那一层的责任，见 PRD 决策 D6）。
  int sunLoss = 0;
  if (spec.stealsSun) {
    sunLoss = _intInRange(
      _uniform(dayKey: dayKey, childId: childId, channel: _channelSun),
      spec.sunStealMin,
      spec.sunStealMax,
    );
  }

  // 偷成长：每株的 pp（贪婪鼬「全园每株各一份」，食叶虫「只挑 1 株」——
  // 「挑哪一株」需要存活株列表 + 仓储，属于第二批的领域服务，不在纯函数里）。
  double growthLoss = 0;
  if (spec.stealsGrowth) {
    growthLoss = _doubleInRange(
      _uniform(dayKey: dayKey, childId: childId, channel: _channelGrowth),
      spec.growthStealMinPct,
      spec.growthStealMaxPct,
    );
  }

  // 必得阳光：无道具档取上限（R1），否则在 [kGuardWinSunMin, kGuardWinSunMax] 落整数。
  // 🔴 B5b：区间 1~3 → 3~5（玄参拍板），`_intInRange` 对任意档数本就均匀
  // （span = 5 档各 1/5），win 通道名 'win' 不变 —— 冻结通道表仅注释更新。
  final int winSun = drop.hasVoucher
      ? _intInRange(
          _uniform(dayKey: dayKey, childId: childId, channel: _channelWinSun),
          kGuardWinSunMin,
          kGuardWinSunMax,
        )
      : kGuardWinSunNoItem;

  return GuardRoll(
    thief: thief,
    growthLossPercent: growthLoss,
    sunLoss: sunLoss,
    drop: drop,
    bonusDrop: bonusDrop,
    winSun: winSun,
  );
}

/// ② **成长扣减**：返回扣过成长的新 [Plant]（不可变，不改原对象）。
///
/// 约束顺序（**这个顺序本身就是验收口径**，参见 PRD §3.5 约束 B 与验收 A6/A7）：
///  1. `status == dead` → **原样返回**（死株没有成长可偷；也避免把 `deadAt` 语义搅乱）；
///  2. `status == bloomed` → **免疫，原样返回**（🔴 见下）；
///  3. 否则 `progress = max(0, progress − min(pp, kGuardGrowthStealPerPlantDailyCap))`，
///     并断言 `stage` 未变。
///
/// [pp] 单位 = 进度比例（`0.03` = 3 个百分点）。负数 / `NaN` / `Infinity` 视为脏入参
/// → 原样返回（宁可不扣，也不能把 `progress` 写成 NaN）。
///
/// 🔴 **为什么开花株必须免疫**：开花株 `progress == 1.0`。扣 5% 会把它打到 0.95，
/// 一旦花期到点，`_applyBloomCycle` 会把进度硬设成
/// [kBloomWiltProgressFloor]（0.5）⇒ 孩子看到的是「被偷一次，花掉了一大截（−45pp）」。
/// 这就是「阶段回退」本身，属产品信任问题（PRD 风险登记 R-3）。
///
/// 🔴 **为什么不碰 [Plant.stageStartedAt]**：`_advanceGrowth` 只补
/// `stageStartedAt → now` 的增量段；改动它会导致回血或进度跳变。
/// 🔴 **为什么不碰 [Plant.stage]**：阶段只在 `_advanceGrowth` 里单向递增，
/// 只改 `growthProgress` 天然不会回退阶段 —— 本函数用断言把这条钉死。
Plant applyGrowthTheft(Plant plant, double pp) {
  // ① 死株跳过。
  if (plant.status == PlantStatus.dead) return plant;

  // ② 开花株免疫（只可能被偷阳光）。
  if (plant.status == PlantStatus.bloomed) return plant;

  // 脏入参保护：不扣，也不写 NaN 进库。
  if (!pp.isFinite || pp <= 0) return plant;

  // ③ 单株单日封顶。
  final double loss = pp > kGuardGrowthStealPerPlantDailyCap
      ? kGuardGrowthStealPerPlantDailyCap
      : pp;

  final double next = plant.growthProgress - loss;
  final double clamped = next < 0 ? 0 : (next > 1 ? 1 : next);

  final Plant updated = plant.copyWith(growthProgress: clamped);

  // 阶段绝不回退：只改 growthProgress 时本断言恒成立；它存在的意义是「将来谁
  // 想在扣减里顺手改 stage / stageStartedAt，会立刻在 debug 下炸掉」。
  assert(
    updated.stage == plant.stage,
    'applyGrowthTheft must not change stage',
  );
  assert(
    updated.stageStartedAt == plant.stageStartedAt,
    'applyGrowthTheft must not change stageStartedAt',
  );
  return updated;
}

/// ③ **券的实际节省额**：这张券在「这批盆 / 这株」上省了多少 ☀。
///
/// 只回答「省多少」，**不做当日累计记账**（那是 `GuardBuffState.consume` 的事）。
/// 5 种券口径（PRD §3.7 表 + §3.8 收口表）：
///
/// | 券 | 口径 | 与称号叠加 |
/// |---|---|---|
/// | [GuardDropKind.waterVoucher] | 每盆每次 −[kGuardWaterVoucherSave]，按 [potCount] 盆累加，**当日不限次**（B13.4，原 6 ☀ 封顶废除） | 相加（故本函数不重复算称号） |
/// | [GuardDropKind.laborVoucher] | 每次清理 +[kGuardLaborVoucherBonus]，按 [cleanCount] 次累加，**当日不限次**（B13.4，原 4 ☀ 封顶废除） | 加在称号之后（同上） |
/// | [GuardDropKind.fertilizeVoucher] | 今日**每次**施肥 −[kGuardFertilizerVoucherSave]，按 [potCount] 累加、**封顶 [kGuardFertilizerVoucherQuota]** | 相加 |
/// | [GuardDropKind.freeWater] | **只算 1 盆**（[potCount] 无效），省 = 该盆实际水价 [waterCostOf] | 归零（故随称号减免而变小） |
/// | [GuardDropKind.freeFertilize] | **只算 1 盆**（[potCount] 无效），省 = 该盆实际肥价 [fertilizeCostOf] | 归零 |
/// | [GuardDropKind.none] | 0 | — |
///
/// 🔴 **两个计数参数的语义必须分开传**（主理人裁决 6.4）：
///  · [potCount] = 本次**浇水 / 施肥的盆数**（只被浇水券与免费券使用）；
///  · [cleanCount] = 本次**清理动作次数**（除草 + 除虫，只被劳动券使用）。
///
/// 早期版本只有一个 `potCount` 参数，对劳动券等于「把除草次数当盆数传」——
/// 两个口径在这里长得一样，但调用点完全不同（一键浇水传盆数、一键除草传动作数），
/// 合并成一个参数会让「12 盆 × 3 次」与「30 次清理」这两种场景互相误用。
/// 不属于本券的计数一律**忽略**（浇水券不看 [cleanCount]，劳动券不看 [potCount]）。
///
/// 两者的封顶都来自 `prd_params` 的具名常量，页面**不得**自行加减。
///
/// 🔴 **免费券只吃单株**：[potCount] = 5 时仍只省 1 盆的钱（验收 A10：
/// 一键浇水 5 盆 + 免费浇水券 ⇒ 扣 4×5 = 20 ☀，不是 0）。这是本 PRD 最重要的
/// 实现陷阱，故它由 [GuardDropSpec.singlePotOnly] 这个数据字段驱动，
/// 而不是靠调用方自觉。
double voucherSavingOf(
  GuardDropKind kind, {
  int potCount = 1,
  int cleanCount = 1,
  PlantPerk? perk,
}) {
  final int pots = potCount > 0 ? potCount : 0;
  final int cleans = cleanCount > 0 ? cleanCount : 0;
  final PlantPerk effectivePerk = perk ?? PlantPerk.none;
  switch (kind) {
    case GuardDropKind.waterVoucher:
      {
        // 🔴 B13.4：当日不限次（玄参拍板），原「封顶 kGuardWaterVoucherMaxSaves」
        // 的钳制删除 —— 真机实测浇 6 次后价格跳回原价就是旧封顶所致。
        return (pots * kGuardWaterVoucherSave).toDouble();
      }
    case GuardDropKind.laborVoucher:
      {
        // 🔴 B13.4：当日不限次，原「封顶 kGuardLaborVoucherCap」删除。
        return (cleans * kGuardLaborVoucherBonus).toDouble();
      }
    case GuardDropKind.fertilizeVoucher:
      // 今日**每次**施肥都 −[kGuardFertilizerVoucherSave] ☀：按本次盆数累加，
      // 封顶 [kGuardFertilizerVoucherQuota]（= 最大盆位数，每盆每天限施 1 次）；
      // 与「当日最大可省」口径（G2 裁定）一致 ⇒ 12 盆 = 24、1 盆 = 2。
      final int cappedPots =
          pots > kGuardFertilizerVoucherQuota ? kGuardFertilizerVoucherQuota : pots;
      return (kGuardFertilizerVoucherSave * cappedPots).toDouble();
    case GuardDropKind.freeWater:
      // 单株单次：potCount 一律忽略。
      return waterCostOf(effectivePerk).toDouble();
    case GuardDropKind.freeFertilize:
      return fertilizeCostOf(effectivePerk).toDouble();
    case GuardDropKind.none:
      return 0;
  }
}

// ── 内部工具 ──────────────────────────────────────────────────────────────

/// 取某通道的 `[0,1)` 均匀值（通道隔离见文件头注释）。
double _uniform({
  required String dayKey,
  required String childId,
  required String channel,
}) {
  return deterministicUniform(
    dayKey: dayKey,
    childId: childId,
    salt: kGuardDaySaltV2,
    channel: channel,
  );
}

/// 把 `u ∈ [0,1)` 映射到**闭区间整数** `[min, max]`（每个整数机会均等）。
///
/// `max < min` 时返回 `min`（区间退化，防御分支）；结果再 `clamp` 一次，保证
/// `u` 恰好为 1.0（理论不可达）时也不会越界。
int _intInRange(double u, int min, int max) {
  if (max <= min) return min;
  final int span = max - min + 1;
  final int offset = (u * span).floor();
  final int value = min + offset;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// 把 `u ∈ [0,1)` 线性映射到 `[min, max)`（连续值，不取整）。
double _doubleInRange(double u, double min, double max) {
  if (max <= min) return min;
  final double value = min + (max - min) * u;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
