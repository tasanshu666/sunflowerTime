/// 掉落档（B13.20：9 券 + 无道具；**统一券池制**）+ **单点规格表** + 确定性派生入口。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.7 / §6。
///
/// ## B13.20 统一券池制（玄参 2026-11-13 拍板，取代 B13.5 两张概率表）
///  · **普通宝箱**（免费档 100% / 付费档 70%）：首张券从 [kGuardNormalChestPool]
///    （5 种非免费券）**等概率**挑；免费档先过 30% 无道具闸门，付费档必掉券；
///  · **高级宝箱**（付费档 30%）：首张券从 [kGuardPremiumChestFirstPool]
///    （9 种全池）等概率挑 —— **免费券只在这里出现**（派生在
///    `domain/services/guard_chest.dart`，通道 `chest_first_pick`）。
///
/// ## 纪律
///  · **概率与面值只在本文件 + `prd_params.dart` 出现一次**（经济测算、结算卡
///    显示、单测全部读 [GuardDropSpec]，不得各自写 `0.14` / `10.0`）；
///  · **禁止 `Random`**：派生走 `core/utils/stable_hash.dart` 的确定性哈希；
///  · **零 CJK 字面量**：`test/i18n/no_han_in_domain_test.dart` 钉死
///    「`lib/domain/**` 注释外零 CJK」。券的中文名与所有上屏文案**进 ARB**。
library guard_drop;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';

/// 确定性通道名（掉落档）。
///
/// 🔴 **一经写入即冻结**：改了它等于让历史每一天的掉落全部重掷。
const String kGuardChannelDrop = 'drop';

/// 🔴 B13.5 新增：第二张券的 **10% 闸门**通道（与首张 [kGuardChannelDrop]
/// 平行、互不影响；新通道不重掷历史任何一天）。
///
/// 🔴 **已停止调用（Guard-B13.11 · 玄参 2026-11-11 第九轮）**：第二张券搬进
/// 高级宝箱，改走 `kGuardChannelChestBonusGate` / `kGuardChannelChestBonusPick`。
/// 本常量与 [kGuardChannelDropBonusPick] **保留但不再被任何代码读取** ——
/// 删除它们会让历史 `deriveGuardRoll` 的结果不可重放（旧存档 / 旧测试对照
/// 需要知道「当年这条通道叫什么」）。
const String kGuardChannelDropBonusGate = 'drop_bonus_gate';

/// 🔴 B13.5 新增：第二张券「挑哪种」通道（从除首张外的券里等概率挑）。
///
/// 🔴 **已停止调用**（理由同上，见 [kGuardChannelDropBonusGate]）。
const String kGuardChannelDropBonusPick = 'drop_bonus_pick';

/// 掉落档（一次掷骰命中且仅命中其中一档）。
///
/// 🔴 枚举**顺序 = 券池顺序**：普通宝箱券池 = 前 5 个值（非免费券）、
/// 高级宝箱全池 = 除 [GuardDropKind.none] 外全部 —— **不要重排**，重排会让
/// 「池内下标」错位（等于悄悄改掉掉落分布）；新券只能插在 `none` 之前的
/// 对应分组里。
enum GuardDropKind {
  /// 浇水券：今日每次浇水每盆 −1 ☀，**当日不限次**（B13.4）。
  waterVoucher,

  /// 劳动券：今日每次除草/除虫 +1 ☀，**当日不限次**（B13.4）。
  laborVoucher,

  /// 施肥券：今日**每次**施肥 −[kGuardFertilizerVoucherSave] ☀。
  fertilizeVoucher,

  /// 🔴 B13.20 新增：专注加餐券（被动券）——当日累计专注 ≥ 15 分钟 ⇒
  /// 额外 +10 ☀（一次性，达成瞬间自动到账；生效点在
  /// `SunlightService.settle`，不走养护减免链路）。
  focusMeal,

  /// 🔴 B13.20 新增：专注放大券（被动券）——当日**每场**专注结算阳光 +20%
  /// （乘算；不占每日专注上限，独立 refType）。
  focusBoost,

  /// 免费浇水券（🔴 **高级宝箱限定**，B13.20）：前 **1 次**浇水免费（B13.20 起
  /// 「前 N 次免费」语义，批量按盆计数；旧「任选一盆绝不整批」口径废除）。
  freeWater,

  /// 免费施肥券（🔴 **高级宝箱限定**，B13.20）：前 **1 次**施肥免费。
  freeFertilize,

  /// 🔴 B13.19 新增：免费浇水 ×3 券（🔴 **高级宝箱限定**，B13.20）——当日
  /// **前 3 次**浇水免费（按盆计数，额度记账 quota=3，见 [guardVoucherQuotaOf]）。
  freeWater3,

  /// 🔴 B13.19 新增：免费施肥 ×2 券（🔴 **高级宝箱限定**，B13.20）——当日
  /// **前 2 次**施肥免费。
  freeFertilize2,

  /// 无道具（免费档普通宝箱 30%）：只拿保底阳光 [kGuardWinSunNoItem]，
  /// 不出现空槽。
  ///
  /// 🔴 B13.20：roll 改**统一券池**（30% 闸门 + 5 券等概率）；旧 8 档表只是
  /// B13.19 历史口径（PRD §3.7 已随 B13.20 换版）。
  none;

  /// 普通宝箱的首张券池（5 种**非免费**券；B13.20 统一等概率）。
  ///
  /// 🔴 免费券（freeWater / freeFertilize / freeWater3 / freeFertilize2）与
  /// 专注券之外的任何新券**不得**进本池，除非玄参裁定改「免费券只在高级宝箱」
  /// 的口径。
  static final List<GuardDropKind> normalChestPool =
      List<GuardDropKind>.unmodifiable(<GuardDropKind>[
    waterVoucher,
    laborVoucher,
    fertilizeVoucher,
    focusMeal,
    focusBoost,
  ]);

  /// 高级宝箱的**首张券**全池（9 种 = 除 [GuardDropKind.none] 外全部；
  /// 免费券只在这里出现 —— B13.20「高级宝箱才含免费券」）。
  static final List<GuardDropKind> premiumChestFirstPool =
      List<GuardDropKind>.unmodifiable(<GuardDropKind>[
    ...GuardDropKind.values.where((GuardDropKind k) => k != none),
  ]);

  /// 今天的掉落是哪一档 —— **确定性派生**（禁 `Random`）。
  ///
  /// seed = `dayKey|childId<kGuardDaySaltV2>|[kGuardChannelDrop]`。
  ///
  /// 🔴 B13.20 口径：本方法只派生**普通宝箱**的首张券 ——
  ///  · 免费档：`u < kGuardDropNothingRateFree`（30%）⇒ [none]，否则从
  ///    [normalChestPool]（5 种）等概率挑；
  ///  · 付费档：无闸门，从 [normalChestPool] 等概率挑（70% 日子普通宝箱）；
  ///  · 付费档命中高级宝箱（30%）时，首张券由 `deriveGuardChest` 用
  ///    `chest_first_pick` 通道从 [premiumChestFirstPool]（9 种）**重挑并覆盖**。
  ///
  /// `isPremium` 缺省 false（免费口径）= 一切旧调用点安全默认。
  static GuardDropKind roll({
    required String dayKey,
    required String childId,
    bool isPremium = false,
  }) {
    final double u = deterministicUniform(
      dayKey: dayKey,
      childId: childId,
      salt: kGuardDaySaltV2,
      channel: kGuardChannelDrop,
    );
    if (!isPremium && u < kGuardDropNothingRateFree) return none;
    final double gate = isPremium ? 0.0 : kGuardDropNothingRateFree;
    final double span = 1.0 - gate;
    final double t = (u - gate) / span;
    final List<GuardDropKind> pool = normalChestPool;
    return pool[(t * pool.length).floor().clamp(0, pool.length - 1)];
  }

  /// 🔴 B13.5：第二张券（「10% 概率掉 2 张**不同的**」的低层掷骰工具）。
  ///
  /// 🔴 **已停止调用（Guard-B13.11 · 玄参 2026-11-11 第九轮）**：第二张券从
  /// 「掉落阶段」搬进「**高级宝箱**」—— 新落点是
  /// `deriveGuardChest(...).bonusDrop`（通道 `chest_bonus_gate` /
  /// `chest_bonus_pick`）。本方法的候选表口径（「除首张外的券等概率」，B13.20
  /// 起券库 9 种 ⇒ 除首张外 8 选 1）
  /// 被 `domain/services/guard_chest.dart` 的 `_pickOtherVoucher` 原样沿用，
  /// 但**不再有任何调用点**：保留只为「历史 `deriveGuardRoll` 可重放」与口径
  /// 留证，别在新代码里再调。
  ///
  /// * 仅当**首张已掉券**时调用（首张 = none ⇒ 本函数不该被调）；
  /// * 🔴 **调用方必须已判完整版档**：本函数只负责「掷」，**不含档位判定** ——
  ///   旧 gate 在 `guard_math.deriveGuardRoll`（Guard-B13.10 裁定「双倍掉落券
  ///   对免费档不生效」）；任何新调用点**必须**先自己确认是完整版档；
  /// * 10% 闸门走独立通道 [kGuardChannelDropBonusGate]（与首张通道互不影响）；
  /// 第二张从「除首张外的券」里**等概率**挑（通道
  /// [kGuardChannelDropBonusPick]）；确定性派生，禁 `Random`。
  // Deprecated message is a *code* string (not a UI copy), so it must be
  // ASCII: `test/i18n/no_han_in_domain_test.dart` forbids CJK outside comments.
  @Deprecated(
    'Moved to the premium chest (Guard-B13.11): use '
    'deriveGuardChest(...).bonusDrop instead; this method has no callers.',
  )
  static GuardDropKind? rollBonus({
    required String dayKey,
    required String childId,
    required GuardDropKind exclude,
  }) {
    final double gate = deterministicUniform(
      dayKey: dayKey,
      childId: childId,
      salt: kGuardDaySaltV2,
      channel: kGuardChannelDropBonusGate,
    );
    if (gate >= kGuardDropDualChance) return null;
    final double pick = deterministicUniform(
      dayKey: dayKey,
      childId: childId,
      salt: kGuardDaySaltV2,
      channel: kGuardChannelDropBonusPick,
    );
    // 🔴 B13.5 玄参原话「掉落 2 张**不同的** buff 卡券」：候选必须排除
    //    首张 [exclude]（QA 逐日对拍抓过 rollBonus 抽出与主券同种的回归）。
    final List<GuardDropKind> candidates = GuardDropKind.values
        .where((GuardDropKind k) =>
            k != GuardDropKind.none && k != exclude)
        .toList();
    // 等概率：N 个候选（B13.20 起券库 9 种 ⇒ 除首张 8 个）均分 [0,1)。
    return candidates[(pick * candidates.length).floor().clamp(0, candidates.length - 1)];
  }
}

/// 一个掉落档的**全部**数值规格（概率 / 面值 / 是否单株限定）。
class GuardDropSpec {
  /// 稳定 ASCII id（冻结；`GuardDayState.toJson` 的线名就是它）。
  final String id;

  /// 占位图形（emoji = 符号，不是文案）。
  final String emoji;

  /// **免费档全口径概率**（🔴 B13.20 语义变更）：
  ///  · 普通宝箱券池里的 5 种非免费券 = [kGuardDropRatePerVoucherFree]（0.14）；
  ///  · 4 种免费券 = **0**（普通宝箱不掉免费券，B13.20「高级宝箱才含免费券」；
  ///    它们在高级宝箱全池里的真实概率 = 1/9 ≈ 0.111，由派生层等概率保证，
  ///    不在本字段重复记账）；
  ///  · [GuardDropKind.none] = [kGuardDropNothingRateFree]（0.30）。
  /// 合计 = 5×0.14 + 0.30 = **1.0**（免费档普通宝箱的真实分布，单测钉死）。
  final double rate;

  /// 面值下限。单位：☀。
  final double faceValueMin;

  /// 面值上限。单位：☀。
  final double faceValueMax;

  /// 是否**只作用于单株单次**（4 种「免费」券 = true）。
  ///
  /// 🔴 B13.20 语义变更：免费券改「当日**前 N 次**免费」——本字段的含义从
  /// 「绝不整批」收窄为「**每次核销必须对应一次真实养护动作**」（批量按盆计数：
  /// 一键 5 盆 + ×3 券 = 前 3 盆免费、后 2 盆收费，总免费额仍 = 券面值）。
  /// 「额度按盆消耗」这条红线仍由本字段 + [guardVoucherQuotaOf] 共同守住。
  final bool singlePotOnly;

  const GuardDropSpec({
    required this.id,
    required this.emoji,
    required this.rate,
    required this.faceValueMin,
    required this.faceValueMax,
    required this.singlePotOnly,
  });

  /// 面值（用于经济测算与结算卡显示）。
  ///
  /// 口径 = 区间中点：PRD §5.1 的 E[D] 正是用各档中点乘概率算出来的，
  /// 所以中点不是「随便取个平均」，而是那笔账的输入。
  double get faceValue => (faceValueMin + faceValueMax) / 2;
}

/// 🔑 **单点规格表**：全部掉落的数值（PRD §3.7 表逐条落地，B13.20 起两处同源）。
///
/// 数值冲突时以 `prd_params.dart` 的 `kGuard*` 常量为准，本表只做
/// 「档位 → 常量」的绑定，不重复写数值。
final Map<GuardDropKind, GuardDropSpec> kGuardDropSpecs =
    Map<GuardDropKind, GuardDropSpec>.unmodifiable(
  <GuardDropKind, GuardDropSpec>{
    GuardDropKind.waterVoucher: const GuardDropSpec(
      id: 'water_voucher',
      emoji: '💧',
      rate: kGuardDropRatePerVoucherFree,
      faceValueMin: kGuardFaceValueWaterVoucherMin,
      faceValueMax: kGuardFaceValueWaterVoucherMax,
      singlePotOnly: false,
    ),
    GuardDropKind.laborVoucher: const GuardDropSpec(
      id: 'labor_voucher',
      emoji: '🧹',
      rate: kGuardDropRatePerVoucherFree,
      faceValueMin: kGuardFaceValueLaborVoucherMin,
      faceValueMax: kGuardFaceValueLaborVoucherMax,
      singlePotOnly: false,
    ),
    GuardDropKind.fertilizeVoucher: const GuardDropSpec(
      id: 'fertilize_voucher',
      emoji: '🌱',
      rate: kGuardDropRatePerVoucherFree,
      faceValueMin: kGuardFaceValueFertilizerVoucher,
      faceValueMax: kGuardFaceValueFertilizerVoucher,
      singlePotOnly: false,
    ),
    GuardDropKind.focusMeal: const GuardDropSpec(
      id: 'focus_meal',
      emoji: '🍱',
      rate: kGuardDropRatePerVoucherFree,
      faceValueMin: kGuardFaceValueFocusMeal,
      faceValueMax: kGuardFaceValueFocusMeal,
      singlePotOnly: false,
    ),
    GuardDropKind.focusBoost: const GuardDropSpec(
      id: 'focus_boost',
      emoji: '🔭',
      rate: kGuardDropRatePerVoucherFree,
      faceValueMin: kGuardFaceValueFocusBoostMin,
      faceValueMax: kGuardFaceValueFocusBoostMax,
      singlePotOnly: false,
    ),
    GuardDropKind.freeWater: const GuardDropSpec(
      id: 'free_water',
      emoji: '💦',
      // 🔴 B13.20：免费券不在普通宝箱券池 ⇒ 免费档全口径概率 = 0。
      rate: 0,
      faceValueMin: kGuardFaceValueFreeWater,
      faceValueMax: kGuardFaceValueFreeWater,
      singlePotOnly: true,
    ),
    GuardDropKind.freeFertilize: const GuardDropSpec(
      id: 'free_fertilize',
      emoji: '🌾',
      rate: 0,
      faceValueMin: kGuardFaceValueFreeFertilize,
      faceValueMax: kGuardFaceValueFreeFertilize,
      singlePotOnly: true,
    ),
    GuardDropKind.freeWater3: const GuardDropSpec(
      id: 'free_water_3',
      emoji: '🚿',
      rate: 0,
      faceValueMin: kGuardFaceValueFreeWater3,
      faceValueMax: kGuardFaceValueFreeWater3,
      singlePotOnly: true,
    ),
    GuardDropKind.freeFertilize2: const GuardDropSpec(
      id: 'free_fertilize_2',
      emoji: '🪴',
      rate: 0,
      faceValueMin: kGuardFaceValueFreeFertilize2,
      faceValueMax: kGuardFaceValueFreeFertilize2,
      singlePotOnly: true,
    ),
    GuardDropKind.none: const GuardDropSpec(
      id: 'none',
      emoji: '',
      rate: kGuardDropNothingRateFree,
      faceValueMin: kGuardFaceValueNothing,
      faceValueMax: kGuardFaceValueNothing,
      singlePotOnly: false,
    ),
  },
);

/// [GuardDropKind] 的规格读取入口（唯一推荐写法：`kind.spec`）。
extension GuardDropKindX on GuardDropKind {
  /// 本档的单点规格。
  GuardDropSpec get spec => kGuardDropSpecs[this]!;

  /// 稳定 ASCII id（冻结，用于 JSON / 埋点）。
  String get id => spec.id;

  /// 出现概率。
  double get rate => spec.rate;

  /// 面值（区间中点）。单位：☀。
  double get faceValue => spec.faceValue;

  /// 是否只作用于单株单次（4 种「免费」券 = true；B13.20 起语义见
  /// [GuardDropSpec.singlePotOnly]）。
  bool get singlePotOnly => spec.singlePotOnly;

  /// 是否有券可拿（false = 无道具档）。
  bool get hasVoucher => this != GuardDropKind.none;
}

/// 由 JSON / 埋点线名反查档位（未知 id 返回 [GuardDropKind.none]，不抛异常）。
///
/// 未知 id 兜底到「无道具档」而不是 `null`：降级安装读到未来版本的券名时，
/// 最坏结果是「今天没有小礼物」（且保底阳光照给），而不是让今日页崩掉。
GuardDropKind guardDropKindFromId(String? id) {
  if (id == null) return GuardDropKind.none;
  for (final GuardDropKind kind in GuardDropKind.values) {
    if (kind.id == id) return kind;
  }
  return GuardDropKind.none;
}
