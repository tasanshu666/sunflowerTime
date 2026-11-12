/// 掉落档（6 档：5 种券 + 无道具）+ **单点规格表** + 确定性派生入口。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.7 / §6。
///
/// ## 纪律
///  · **概率与面值只在本文件出现一次**（经济测算、结算卡显示、单测全部读
///    [GuardDropSpec]，不得各自写 `0.35` / `5.5`）；
///  · **禁止 `Random`**：派生走 `core/utils/stable_hash.dart` 的确定性哈希；
///  · **零 CJK 字面量**：`test/i18n/no_han_in_domain_test.dart` 钉死
///    「`lib/domain/**` 注释外零 CJK」。券的中文名（浇水券 / 劳动券 / 施肥券 /
///    免费浇水券 / 免费施肥券）与所有上屏文案**留到第二批进 ARB**。
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
/// 顺序 = 概率表的顺序（与 [GuardDropKind.values] 下标一致），**不要重排**：
/// 重排会让「落桶下标」与「概率」错位，等于悄悄改掉掉落分布。
enum GuardDropKind {
  /// 浇水券（35%）：今日每次浇水每盆 −1 ☀，当日累计封顶
  /// [kGuardWaterVoucherMaxSaves]。
  waterVoucher,

  /// 劳动券（20%）：今日每次除草/除虫 +1 ☀，当日累计封顶
  /// [kGuardLaborVoucherCap]。
  laborVoucher,

  /// 施肥券（15%）：今日**每次**施肥 −[kGuardFertilizerVoucherSave] ☀。
  fertilizeVoucher,

  /// 免费浇水券（8%）：🔴 **任选一盆、仅一次**免费（绝不整批）。
  freeWater,

  /// 免费施肥券（4%）：🔴 **任选一盆、仅一次**免费（最稀有）。
  freeFertilize,

  /// 无道具（旧表 18%）：只拿保底阳光 [kGuardWinSunNoItem]，不出现空槽。
  ///
  /// 🔴 B13.5：roll 已改**分档表**（免费 none=50% / 付费 none=0，
  /// 见 `kGuardDropRatesFree` / `kGuardDropRatesPremium`）；本档旧 18% 只是
  /// PRD §3.7 历史经济测算口径（spec.rate 仍保留供 E[D] 旧账引用）。
  none;

  /// 今天的掉落是哪一档 —— **确定性派生**（禁 `Random`）。
  ///
  /// seed = `dayKey|childId<kGuardDaySaltV2>|[kGuardChannelDrop]`，按分档表
  /// （[kGuardDropRatesFree] / [kGuardDropRatesPremium]）累计概率落桶。
  ///
  /// 🔴 B13.5（玄参拍板）：掉落率**按权益档位分表** —— 免费 none=50%、
  /// 付费必掉券。`isPremium` 缺省 false（免费表）= 一切旧调用点安全默认。
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
    final List<double> rates =
        isPremium ? kGuardDropRatesPremium : kGuardDropRatesFree;
    return GuardDropKind.values[bucketOfUniform(u, rates)];
  }

  /// 🔴 B13.5：第二张券（「10% 概率掉 2 张**不同的**」的低层掷骰工具）。
  ///
  /// 🔴 **已停止调用（Guard-B13.11 · 玄参 2026-11-11 第九轮）**：第二张券从
  /// 「掉落阶段」搬进「**高级宝箱**」—— 新落点是
  /// `deriveGuardChest(...).bonusDrop`（通道 `chest_bonus_gate` /
  /// `chest_bonus_pick`）。本方法的候选表口径（「除首张外的 4 种券等概率」）
  /// 被 `domain/services/guard_chest.dart` 的 `_pickOtherVoucher` 原样沿用，
  /// 但**不再有任何调用点**：保留只为「历史 `deriveGuardRoll` 可重放」与口径
  /// 留证，别在新代码里再调。
  ///
  /// * 仅当**首张已掉券**时调用（首张 = none ⇒ 本函数不该被调）；
  /// * 🔴 **调用方必须已判完整版档**：本函数只负责「掷」，**不含档位判定** ——
  ///   旧 gate 在 `guard_math.deriveGuardRoll`（Guard-B13.10 裁定「双倍掉落券
  ///   对免费档不生效」）；任何新调用点**必须**先自己确认是完整版档；
  /// * 10% 闸门走独立通道 [kGuardChannelDropBonusGate]（与首张通道互不影响）；
  /// 第二张从「除首张外的 4 种券」里**等概率**挑（通道
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
    // 等概率：4 个候选均分 [0,1)。
    return candidates[(pick * candidates.length).floor().clamp(0, candidates.length - 1)];
  }
}

/// 一个掉落档的**全部**数值规格（概率 / 面值 / 是否单株限定）。
class GuardDropSpec {
  /// 稳定 ASCII id（冻结；`GuardDayState.toJson` 的线名就是它）。
  final String id;

  /// 占位图形（emoji = 符号，不是文案）。
  final String emoji;

  /// 出现概率（6 档合计必须 = 1.0）。
  final double rate;

  /// 面值下限。单位：☀。
  final double faceValueMin;

  /// 面值上限。单位：☀。
  final double faceValueMax;

  /// 是否**只作用于单株单次**（两种「免费」券 = true）。
  ///
  /// 🔴 这是「免费券绝不整批」的**唯一数据来源**：一键浇水 5 盆遇到免费券时，
  /// 只允许其中 1 盆归零（扣 4×5 = 20 ☀，不是 0）。任何实现若不读本字段，
  /// 就等于把浇水经济打穿 5 天。
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
  /// 口径 = 区间中点：PRD §5.1 的 `E[D] = 3.525 ☀` 正是用
  /// `0.35×5.5 + 0.20×2.5 + 0.15×2 + 0.08×5 + 0.04×10` 算出来的，
  /// 所以中点不是「随便取个平均」，而是那笔账的输入。
  double get faceValue => (faceValueMin + faceValueMax) / 2;
}

/// 🔑 **单点规格表**：6 档掉落的全部数值（PRD §3.7 表逐条落地）。
///
/// 数值冲突时以 `prd_params.dart` 的 `kGuard*` 常量为准，本表只做
/// 「档位 → 常量」的绑定，不重复写数值。
final Map<GuardDropKind, GuardDropSpec> kGuardDropSpecs =
    Map<GuardDropKind, GuardDropSpec>.unmodifiable(
  <GuardDropKind, GuardDropSpec>{
    GuardDropKind.waterVoucher: const GuardDropSpec(
      id: 'water_voucher',
      emoji: '💧',
      rate: kGuardDropWaterVoucherRate,
      faceValueMin: kGuardFaceValueWaterVoucherMin,
      faceValueMax: kGuardFaceValueWaterVoucherMax,
      singlePotOnly: false,
    ),
    GuardDropKind.laborVoucher: const GuardDropSpec(
      id: 'labor_voucher',
      emoji: '🧹',
      rate: kGuardDropLaborVoucherRate,
      faceValueMin: kGuardFaceValueLaborVoucherMin,
      faceValueMax: kGuardFaceValueLaborVoucherMax,
      singlePotOnly: false,
    ),
    GuardDropKind.fertilizeVoucher: const GuardDropSpec(
      id: 'fertilize_voucher',
      emoji: '🌱',
      rate: kGuardDropFertilizerVoucherRate,
      faceValueMin: kGuardFaceValueFertilizerVoucher,
      faceValueMax: kGuardFaceValueFertilizerVoucher,
      singlePotOnly: false,
    ),
    GuardDropKind.freeWater: const GuardDropSpec(
      id: 'free_water',
      emoji: '💦',
      rate: kGuardDropFreeWaterRate,
      faceValueMin: kGuardFaceValueFreeWater,
      faceValueMax: kGuardFaceValueFreeWater,
      singlePotOnly: true,
    ),
    GuardDropKind.freeFertilize: const GuardDropSpec(
      id: 'free_fertilize',
      emoji: '🌾',
      rate: kGuardDropFreeFertilizerRate,
      faceValueMin: kGuardFaceValueFreeFertilize,
      faceValueMax: kGuardFaceValueFreeFertilize,
      singlePotOnly: true,
    ),
    GuardDropKind.none: const GuardDropSpec(
      id: 'none',
      emoji: '',
      rate: kGuardDropNothingRate,
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

  /// 是否只作用于单株单次（两种「免费」券 = true）。
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
