/// 花园守卫「宝箱」档位 / 种子档位 / 一次开箱结果（不可变纯数据 + JSON 往返）。
///
/// 真源：`docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §2.4 / §3。
///
/// ## 为什么宝箱要单独一个实体（而不是塞进 `GuardDayState` 的散字段）
/// 宝箱是「一次开箱的**完整结果**」：档位 + 第二张券 + 碎片数量 + 种子（档位 +
/// 物种）。四类奖励**互不相关**（各自一条确定性通道，见 `prd_params.dart` 的
/// `kGuardChannelChest*`），但它们必须作为**一个整体**从派生层传到发放层
/// （`deriveGuardChest` → `GuardDayState` → `claim()`），否则「档位是高级、
/// 但碎片丢了」这种半截状态没有任何地方能表达。
///
/// ## 纪律
///  · 本文件**零 IO / 零 flutter import / 零 CJK 字面量**（`test/i18n/
///    no_han_in_domain_test.dart` 钉死），可 `dart test` 直跑；
///  · **禁止 `Random`**：档位与全部内容由 `domain/services/guard_chest.dart`
///    的确定性派生给出，本文件只**装**结果；
///  · 线名（[GuardChestTier.id] / [GuardSeedKind.id]）一经写入即冻结。
library guard_chest_entity;

import 'package:sunflower_time/domain/entities/guard_drop.dart';

/// 宝箱档位（线名冻结：`'normal'` / `'premium'`）。
///
/// ## 为什么没有 `none`
/// 设计稿 §2.4 曾打算用 `none` 表示「没有宝箱（旧存档）」；本批实现改为
/// **两值 + 缺省 `normal`**：
///  · 经济上「普通宝箱」= 改造前的全部内容（必得阳光 + 主券），所以旧存档
///    读成 `normal` **一分钱都不会多发**；
///  · 少一个取值就少一处「三态 switch」，表现层不必再区分「没宝箱 / 有宝箱」
///    两条收场路径（`GuardChestTier.none` 的语义由「表现层是否搭宝箱」承担）。
///
/// ⇒ 旧的 `GuardDayState` JSON（根本没有 `chestTier` 键）反序列化成
/// [GuardChestTier.normal]，行为等价于「只有普通宝箱」。
enum GuardChestTier {
  /// 普通宝箱：必得阳光（不翻倍）+ 主券。= 改造前的全部掉落内容。
  normal,

  /// 高级宝箱（完整版 20%）：普通内容 + 阳光翻倍 + 10% 双券 + 5% 碎片 +
  /// 5% 种子。
  premium;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardChestTier.normal:
        return 'normal';
      case GuardChestTier.premium:
        return 'premium';
    }
  }

  /// 是否高级宝箱（阳光翻倍 / 附加奖励的唯一判据）。
  bool get isPremium => this == GuardChestTier.premium;
}

/// 由 JSON / 埋点线名反查档位（未知 id 兜底 [GuardChestTier.normal]，不抛异常）。
///
/// 兜底取 `normal` 而不是 `premium`：降级安装读到未来版本写的 `chestTier` 时，
/// 最坏结果是「今天只是普通宝箱」（净值与改造前一致），绝不会白送翻倍与碎片。
GuardChestTier guardChestTierFromId(String? id) {
  if (id == null) return GuardChestTier.normal;
  for (final GuardChestTier tier in GuardChestTier.values) {
    if (tier.id == id) return tier;
  }
  return GuardChestTier.normal;
}

/// 种子档位（线名冻结：`'none'` / `'common'` / `'premium'`）。
///
/// 「档位」而不是「具体物种」：档位决定面值（普通 10 片 / 精英 20 片）与
/// 「重复种子自动分解」的片数（3 / 5），是**发放逻辑**的输入；具体物种只是
/// 档位内的等概率取值（见 [GuardChestRoll.seedSpeciesId]）。
enum GuardSeedKind {
  /// 今天没有种子。
  none,

  /// 普通档（番茄 / 草莓 / 玫瑰 / 蓝莓 —— 向日葵被刻意排除，见
  /// `kGuardSeedSpeciesCommon` 的注释）。
  common,

  /// 精英档（月光兰 / 珊瑚岭兰 / 翡翠绣球 / 葡萄 / 荷花）。
  premium;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardSeedKind.none:
        return 'none';
      case GuardSeedKind.common:
        return 'common';
      case GuardSeedKind.premium:
        return 'premium';
    }
  }

  /// 是否真的有种子（`none` = 没有）。
  bool get hasSeed => this != GuardSeedKind.none;
}

/// 由 JSON / 埋点线名反查种子档位（未知 id 兜底 [GuardSeedKind.none]，不抛异常）。
GuardSeedKind guardSeedKindFromId(String? id) {
  if (id == null) return GuardSeedKind.none;
  for (final GuardSeedKind kind in GuardSeedKind.values) {
    if (kind.id == id) return kind;
  }
  return GuardSeedKind.none;
}

/// 一次开箱的**完整结果**（不可变，纯数据）。
///
/// ## 🔴 `==` / `hashCode` 必须包含**全部**字段（吸取 `GuardRoll` 的教训）
/// `GuardRoll.operator==` 当年漏了 `bonusDrop`，于是「第二张券被重掷 / 丢失」
/// 这类回归在 `expect(rollA, rollB)` 下**永远假绿**（`test/guard/
/// guard_service_test.dart` 只能逐字段手写断言来绕开）。本类的相等性
/// **逐字段齐全**，并且 `guard_chest_math_test.dart` 用「只改一个字段的两个
/// 实例必须不等」反向钉死它。
class GuardChestRoll {
  /// 箱体档位（决定「有没有附加奖励」与「阳光是否翻倍」）。
  final GuardChestTier tier;

  /// 本箱的**首张券**（🔴 B13.20 新增字段；[GuardDropKind.none] = 今天无券）。
  ///
  /// B13.20 起「免费券只在高级宝箱」：高级宝箱的首张券由派生层从**全券池
  /// 9 种**等概率重挑（可能是一张免费券），普通宝箱则原样透传
  /// `deriveGuardRoll` 的 `drop`（5 种非免费券池 / 无道具）。
  /// `GuardService.resolve` 把本值落盘为 `GuardDayState.dropKind`。
  final GuardDropKind firstDrop;

  /// 第二张 buff 券（[GuardDropKind.none] = 没有第二张）。
  ///
  /// 🔴 恒与首张 [GuardDropKind.none] **不同种**（派生时从「除首张外 8 种券」
  /// 里挑，B13.20 券库 9 种），且只有 [GuardChestTier.premium] 且当天首张已掉券
  /// 时才可能非空。
  final GuardDropKind bonusDrop;

  /// 碎片数量（`0` = 没有；否则 [kGuardChestFragmentQtyMin] ~
  /// [kGuardChestFragmentQtyMax] 之一）。
  ///
  /// ⚠️ 这里存的是**最终发放片数**（1 或 2），不是「有没有碎片」的布尔：
  /// 结算卡要显示「+1 / +2」，账本对账也要逐片可比。
  final int fragmentQty;

  /// 种子档位（[GuardSeedKind.none] = 没有种子）。
  final GuardSeedKind seedKind;

  /// 具体物种 id（`seedKind != none` 时非空；否则恒 `null`）。
  final String? seedSpeciesId;

  const GuardChestRoll({
    this.tier = GuardChestTier.normal,
    this.firstDrop = GuardDropKind.none,
    this.bonusDrop = GuardDropKind.none,
    this.fragmentQty = 0,
    this.seedKind = GuardSeedKind.none,
    this.seedSpeciesId,
  });

  /// 「什么都没有的普通宝箱」（免费档无道具日的默认结果）。
  static const GuardChestRoll empty = GuardChestRoll();

  /// 有没有碎片。
  bool get hasFragments => fragmentQty > 0;

  /// 有没有种子（且物种非空 —— 两者必须同时成立才可发放）。
  bool get hasSeed => seedKind != GuardSeedKind.none && seedSpeciesId != null;

  /// 有没有第二张券。
  bool get hasBonusDrop => bonusDrop != GuardDropKind.none;

  /// 是否为「高级宝箱且至少有一项附加奖励」（结算卡文案 / 演出用）。
  bool get hasAnyExtra => hasBonusDrop || hasFragments || hasSeed;

  /// 序列化（线名冻结；键名即 `GuardDayState` 的线名）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tier': tier.id,
      'firstDrop': firstDrop.id,
      'bonusDrop': bonusDrop.id,
      'fragmentQty': fragmentQty,
      'seedKind': seedKind.id,
      'seedSpeciesId': seedSpeciesId,
    };
  }

  /// 反序列化（**缺字段 / 脏数据一律兜底**：`tier` → normal、`firstDrop` /
  /// `bonusDrop` → none、`fragmentQty` → 0、`seedKind` → none、
  /// `seedSpeciesId` → null）。
  ///
  /// 绝不抛异常：一份坏掉的存档不该让孩子打不开今日页。
  factory GuardChestRoll.fromJson(Map<String, Object?> json) {
    final Object? rawQty = json['fragmentQty'];
    final int qty = rawQty is int
        ? rawQty
        : (rawQty is num
            ? rawQty.toInt()
            : (rawQty is String ? (int.tryParse(rawQty) ?? 0) : 0));
    final GuardSeedKind kind = guardSeedKindFromId(_stringOf(json['seedKind']));
    return GuardChestRoll(
      tier: guardChestTierFromId(_stringOf(json['tier'])),
      firstDrop: guardDropKindFromId(_stringOf(json['firstDrop'])),
      bonusDrop: guardDropKindFromId(_stringOf(json['bonusDrop'])),
      // 负数 / 脏值收敛成 0（宁可少发，也不让一个坏存档写出负片数）。
      fragmentQty: qty > 0 ? qty : 0,
      seedKind: kind,
      // 档位为 none 时物种强制 null（不变量：两者必须同时成立）。
      seedSpeciesId: kind == GuardSeedKind.none ? null : _stringOf(json['seedSpeciesId']),
    );
  }

  /// 不可变副本（[seedSpeciesId] 可空 ⇒ 用显式 `clearSeedSpecies` 清空，
  /// 避免 `x ?? this.x` 那种「可空字段清不掉」的老坑，见 `Plant.kClear`）。
  GuardChestRoll copyWith({
    GuardChestTier? tier,
    GuardDropKind? firstDrop,
    GuardDropKind? bonusDrop,
    int? fragmentQty,
    GuardSeedKind? seedKind,
    String? seedSpeciesId,
    bool clearSeedSpecies = false,
  }) {
    return GuardChestRoll(
      tier: tier ?? this.tier,
      firstDrop: firstDrop ?? this.firstDrop,
      bonusDrop: bonusDrop ?? this.bonusDrop,
      fragmentQty: fragmentQty ?? this.fragmentQty,
      seedKind: seedKind ?? this.seedKind,
      seedSpeciesId:
          clearSeedSpecies ? null : (seedSpeciesId ?? this.seedSpeciesId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardChestRoll &&
          other.tier == tier &&
          other.firstDrop == firstDrop &&
          other.bonusDrop == bonusDrop &&
          other.fragmentQty == fragmentQty &&
          other.seedKind == seedKind &&
          other.seedSpeciesId == seedSpeciesId;

  @override
  int get hashCode => Object.hash(
        tier,
        firstDrop,
        bonusDrop,
        fragmentQty,
        seedKind,
        seedSpeciesId,
      );

  @override
  String toString() => 'GuardChestRoll(${tier.id}, first=${firstDrop.id}, '
      'bonus=${bonusDrop.id}, '
      'fragments=$fragmentQty, seed=${seedKind.id}, species=$seedSpeciesId)';
}

/// JSON 里的字符串字段（非 `String` / 空串一律 `null`，**不抛类型异常**）。
String? _stringOf(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}
