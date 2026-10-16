/// C77 · **称号专属属性**（纯 Dart：只 import `core/constants`；零 flutter、零 I/O）。
///
/// ## 定位
/// `docs/称号属性_v1_系统设计.md` §3.2 的实现落点：
///  · [PlantPerk]：一个称号的专属属性集合（全为非负增益量，0 = 无加成）；
///  · [perkOfLevel]：**唯一入口** —— 等级 → 当前称号的属性（`f(当前称号)`）；
///  · perk-aware 取值函数（[waterCostOf] … [shovelRefundOf]）：**域层扣费/发奖与 UI 展示
///    必须调用同一批函数**（防孪生 S2 / F68 先例），页面禁止内联 `5 - 1` / `+1`；
///  · [perkSummaryTextOf]：演出卡「本称号专属：…」文案装配（不写页面内 if-else）。
///
/// ## 叠加语义（🔴 关键）
/// 9 个称号节点**各绑一个不同机制**（[kPlantPerkPerTitleNode]，零重复 P5）；用户**依次解锁**，
/// 每解锁一个节点即**永久获得**该属性 ⇒ [perkOfLevel] 是**已解锁节点的累积**：
///  · Lv.1 → 仅护眼 +1（C78 前置）；Lv.5 → 护眼 +1 **且** 浇水 −1（两节点各一条，叠加）；
///  · Lv.40（满级）→ 9 条属性**全生效**。
/// （量化模型，见 PRD §1.4 (d)：「减免 48 = 浇水 36 + 施肥 12」正需两者同时生效。）
///
/// 🔴 纪律：
///  · 属性 = `perkOfLevel(levelOfMinutes(totalFocusMinutes))` —— **任何地方都不换输入**；
///    🔴 C80 修订（废止 P4）：当前属性统一走 provider/域层单点（读 `FeatureKey.titlePerks`），
///    `perkOfLevel` 本身无档位入参，门控在调用侧（旁路禁令见 `plant_perk_bypass_guard_test`）；
///  · 9 条零重复：同一常量不在两条里出现，禁止「再 −1」叠加式写法；
///  · 单次一律 ±1（仅 ⑧⑨ 两条一次性项用小幅定量）。
library plant_perk;

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 一个称号的专属属性集合（**全为非负增益量**；0 = 无加成 = 未解锁 / 无该属性）。
class PlantPerk {
  /// 浇水消耗减免（☀）。
  final int waterDiscount;

  /// 施肥消耗减免（☀）。
  final int fertilizeDiscount;

  /// 除草奖励加成（☀）。
  final int weedBonus;

  /// 除虫奖励加成（☀）。
  final int pestBonus;

  /// 开花即时阳光加成（☀）。
  final int bloomInstantBonus;

  /// 晨露每条加成（☀，**加在折损之后**）。
  final int dewBonus;

  /// 护眼完成奖励加成（☀）。
  final int eyeCareBonus;

  /// 花盆扩容减免（☀）。
  final int expandDiscount;

  /// 铲除退款加成（☀）。
  final int shovelRefundBonus;

  const PlantPerk({
    this.waterDiscount = 0,
    this.fertilizeDiscount = 0,
    this.weedBonus = 0,
    this.pestBonus = 0,
    this.bloomInstantBonus = 0,
    this.dewBonus = 0,
    this.eyeCareBonus = 0,
    this.expandDiscount = 0,
    this.shovelRefundBonus = 0,
  });

  /// 无加成（未解锁 / 未达任何称号节点）。
  static const PlantPerk none = PlantPerk();

  /// 是否无任何加成（演出/详情卡据此决定是否显示属性行）。
  bool get isNone =>
      waterDiscount == 0 &&
      fertilizeDiscount == 0 &&
      weedBonus == 0 &&
      pestBonus == 0 &&
      bloomInstantBonus == 0 &&
      dewBonus == 0 &&
      eyeCareBonus == 0 &&
      expandDiscount == 0 &&
      shovelRefundBonus == 0;

  /// 逐项相加（仅供 [perkOfLevel] 累积使用；各项均为非负，无溢出风险与负值）。
  PlantPerk add(PlantPerk other) => PlantPerk(
        waterDiscount: waterDiscount + other.waterDiscount,
        fertilizeDiscount: fertilizeDiscount + other.fertilizeDiscount,
        weedBonus: weedBonus + other.weedBonus,
        pestBonus: pestBonus + other.pestBonus,
        bloomInstantBonus: bloomInstantBonus + other.bloomInstantBonus,
        dewBonus: dewBonus + other.dewBonus,
        eyeCareBonus: eyeCareBonus + other.eyeCareBonus,
        expandDiscount: expandDiscount + other.expandDiscount,
        shovelRefundBonus: shovelRefundBonus + other.shovelRefundBonus,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlantPerk &&
          other.waterDiscount == waterDiscount &&
          other.fertilizeDiscount == fertilizeDiscount &&
          other.weedBonus == weedBonus &&
          other.pestBonus == pestBonus &&
          other.bloomInstantBonus == bloomInstantBonus &&
          other.dewBonus == dewBonus &&
          other.eyeCareBonus == eyeCareBonus &&
          other.expandDiscount == expandDiscount &&
          other.shovelRefundBonus == shovelRefundBonus;

  @override
  int get hashCode => Object.hash(
        waterDiscount,
        fertilizeDiscount,
        weedBonus,
        pestBonus,
        bloomInstantBonus,
        dewBonus,
        eyeCareBonus,
        expandDiscount,
        shovelRefundBonus,
      );

  @override
  String toString() => 'PlantPerk(water-$waterDiscount, fertilize-$fertilizeDiscount, '
      'weed+$weedBonus, pest+$pestBonus, bloom+$bloomInstantBonus, '
      'dew+$dewBonus, eye+$eyeCareBonus, expand-$expandDiscount, '
      'shovel+$shovelRefundBonus)';
}

/// 9 称号节点**各自新增**的属性（**索引与 [kFocusLevelTitleLevels] 一一对应**；
/// 🔴 **C78 节点重排（2026-10-15）**：护眼 → Lv.1，其余 8 条顺延一位；
/// 属性内容与数值一字不变，判定逻辑零改动 —— 唯一单点 = 本表）。
///
/// 🔴 **9 条零重复（P5）**：每项**恰好一个**字段非零，且 9 项绑定的字段两两不同
/// （护眼/浇水/施肥/除草/除虫/开花/晨露/扩容/铲除各一，见 `plant_perk_test.dart` TC-13）。
/// 禁止任何「同一字段出现两次」的叠加式写法。
const List<PlantPerk> kPlantPerkPerTitleNode = <PlantPerk>[
  PlantPerk(eyeCareBonus: kPerkEyeCareBonus), // Lv.1  节点（① 护眼，C78 前置）
  PlantPerk(waterDiscount: kPerkWaterDiscount), // Lv.5  节点（② 浇水）
  PlantPerk(fertilizeDiscount: kPerkFertilizeDiscount), // Lv.10 节点（③ 施肥）
  PlantPerk(weedBonus: kPerkWeedBonus), // Lv.15 节点（④ 除草）
  PlantPerk(pestBonus: kPerkPestBonus), // Lv.20 节点（⑤ 除虫）
  PlantPerk(bloomInstantBonus: kPerkBloomInstantBonus), // Lv.25 节点（⑥ 开花即时）
  PlantPerk(dewBonus: kPerkDewBonus), // Lv.30 节点（⑦ 晨露）
  PlantPerk(expandDiscount: kPerkExpandDiscount), // Lv.35 节点（⑧ 扩容）
  PlantPerk(shovelRefundBonus: kPerkShovelRefundBonus), // Lv.40 节点（⑨ 铲除）
];

/// 🔑 **唯一入口**：等级 → 当前称号的属性（= **已解锁称号节点属性的累积**）。
///
/// · `level < 1`（未解锁，累计 < 60 分钟）→ [PlantPerk.none]；
/// · 非称号节点等级（如 Lv.7）→ 取**已解锁的最高称号节点**（Lv.5）为止的累积属性；
/// · 满级（Lv.40）→ 9 条属性**全生效**。
///
/// 🔴 输入必须是**原始等级**（`levelOfMinutes(totalFocusMinutes)`），**不得**用
/// `settledLevel` / SP 锚点（否则老用户「首用静默」期属性会短暂缺失）。
/// `perkOfLevel` 为**纯等级→属性派生**（C80 起门控在调用侧：provider/`currentPerk()` 单点）；
/// ⚠️ 旁路禁令见 `plant_perk_bypass_guard_test`。
PlantPerk perkOfLevel(int level) {
  if (level < 1) return PlantPerk.none;
  PlantPerk total = PlantPerk.none;
  for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
    if (level >= kFocusLevelTitleLevels[i]) {
      total = total.add(kPlantPerkPerTitleNode[i]);
    }
  }
  return total;
}

/// 单个**称号节点**专属的那一条属性（详情卡逐行 / 升级演出「本称号专属」用）。
///
/// [nodeLevel] 必须是 [kFocusLevelTitleLevels] 之一；否则返回 [PlantPerk.none]。
PlantPerk perkOfTitleNode(int nodeLevel) {
  final int idx = kFocusLevelTitleLevels.indexOf(nodeLevel);
  return idx < 0 ? PlantPerk.none : kPlantPerkPerTitleNode[idx];
}

/// 单个称号节点属性的 emoji（[kPerkEmojis]，与节点一一对应；非节点返回空串）。
String perkEmojiOfTitleNode(int nodeLevel) {
  final int idx = kFocusLevelTitleLevels.indexOf(nodeLevel);
  return idx < 0 ? '' : kPerkEmojis[idx];
}

/// 单个称号节点属性的**名称**（[kPerkNames]，与节点一一对应；非节点返回空串）。
///
/// C81：详情卡属性行「属性名」单点收口（页面禁硬编码 9 名，防孪生 S2）；
/// 与 [perkEmojiOfTitleNode] / [perkShortTextOf] 分段渲染 ⇒「👁 护眼 +1 ☀」。
String perkNameOfTitleNode(int nodeLevel) {
  final int idx = kFocusLevelTitleLevels.indexOf(nodeLevel);
  return idx < 0 ? '' : kPerkNames[idx];
}

// ── perk-aware 取值函数（域层与 UI **共用**，杜绝孪生）────────────────────────

/// 浇水单价（☀）：基础 − 减免，钳到 `[0, 基础]`。
int waterCostOf(PlantPerk p) =>
    (kPlantWaterCost - p.waterDiscount).clamp(0, kPlantWaterCost);

/// 施肥单价（☀）：基础 − 减免，钳到 `[0, 基础]`。
int fertilizeCostOf(PlantPerk p) =>
    (kPlantFertilizeCost - p.fertilizeDiscount).clamp(0, kPlantFertilizeCost);

/// 除草奖励（☀）：基础 + 加成。
double weedRewardOf(PlantPerk p) => kGardenWeedReward + p.weedBonus;

/// 除虫奖励（☀）：基础 + 加成。
double pestRewardOf(PlantPerk p) => kGardenPestReward + p.pestBonus;

/// 开花即时**保底**基础阳光（☀）：基础（普通/精品）+ 加成。
///
/// 🔴 `_rollInstantReward` 与 `_grantInstantReward` **两处必须同源调用本函数**
/// （只改一处会漏发 / 多发，见设计 §4.3）。
int bloomInstantBaseOf(PlantPerk p, {required bool premium}) =>
    (premium ? kBloomInstantSunlightPremium : kBloomInstantSunlight) +
    p.bloomInstantBonus;

/// 晨露每条加成（☀）：由 `dewSunlightOf` **加在折损之后**。
int dewBonusOf(PlantPerk p) => p.dewBonus;

/// 护眼完成奖励（☀）：基础 + 加成。
int eyeCareRewardOf(PlantPerk p) => kEyeCareRewardSunlight + p.eyeCareBonus;

/// 花盆扩容单价（☀）：基础（高/低年段）− 减免，钳到 `[0, 基础]`。
int expandCostOf(PlantPerk p, {required bool premium}) {
  final int base = premium ? kPlantPotExpandCostHigh : kPlantPotExpandCostLow;
  return (base - p.expandDiscount).clamp(0, base);
}

/// 铲除退款（☀）：**基础额「种下时定」**（`plants.shovel_refund` 列，free 首株 0 /
/// 档位株 150/250）+ **称号加成「铲除时叠加」**。
///
/// 🔴 `baseRefund == 0` **不加成** —— 全仓 `shovel_refund` 只可能是 0（free 首株）或
/// 150/250，故「base 为 0 不加成」**恰好等价于「只有免费首株不享加成」**，天然防
/// 「免费种 → 铲 → 循环刷阳光」（无需新增任何标记位）。
int shovelRefundOf(int baseRefund, PlantPerk perk) =>
    baseRefund == 0 ? 0 : baseRefund + perk.shovelRefundBonus;

/// 属性摘要文案（升级演出「本称号专属：…」/ 详情卡 tooltip 用）。
///
/// 逐项只输出**非零**属性，用 ` · ` 连接；[PlantPerk.none] → 空串。文案**单点收口于此**
/// （页面禁止写 if-else 拼 9 种）。
String perkSummaryTextOf(PlantPerk p) {
  final List<String> parts = <String>[];
  if (p.waterDiscount > 0) parts.add('浇水消耗 −${p.waterDiscount}');
  if (p.fertilizeDiscount > 0) parts.add('施肥消耗 −${p.fertilizeDiscount}');
  if (p.weedBonus > 0) parts.add('除草奖励 +${p.weedBonus}');
  if (p.pestBonus > 0) parts.add('除虫奖励 +${p.pestBonus}');
  if (p.bloomInstantBonus > 0) parts.add('开花阳光 +${p.bloomInstantBonus}');
  if (p.dewBonus > 0) parts.add('晨露阳光 +${p.dewBonus}');
  if (p.eyeCareBonus > 0) parts.add('护眼奖励 +${p.eyeCareBonus}');
  if (p.expandDiscount > 0) parts.add('花盆扩容 −${p.expandDiscount}');
  if (p.shovelRefundBonus > 0) parts.add('铲除退款 +${p.shovelRefundBonus}');
  return parts.join(' · ');
}

/// 属性徽章**数值短语**（详情卡逐行右侧用）：**纯数值带符号**，如 `+1` / `−1` /
/// `−20` / `+20`（🔴 C81 ③：去掉「额外 / 消耗 / 返还」等描述词）。
///
/// 属性**名称**由 [perkNameOfTitleNode] 承担、阳光单位由 UI 层的
/// `assets/rewards/sunlight.png` 图标承担（C80：非 ☀ 文字）⇒ 本函数只回数值。
/// 顺序无关（9 条零重复保证单字段非零）；量值 `±${p.x}` **派生**、禁写死。
/// 与 [perkSummaryTextOf] 同源；文案单点收口于此（页面禁拼，防孪生 S2）。
String perkShortTextOf(PlantPerk p) {
  if (p.waterDiscount > 0) return '−${p.waterDiscount}';
  if (p.fertilizeDiscount > 0) return '−${p.fertilizeDiscount}';
  if (p.expandDiscount > 0) return '−${p.expandDiscount}';
  if (p.weedBonus > 0) return '+${p.weedBonus}';
  if (p.pestBonus > 0) return '+${p.pestBonus}';
  if (p.bloomInstantBonus > 0) return '+${p.bloomInstantBonus}';
  if (p.dewBonus > 0) return '+${p.dewBonus}';
  if (p.eyeCareBonus > 0) return '+${p.eyeCareBonus}';
  if (p.shovelRefundBonus > 0) return '+${p.shovelRefundBonus}';
  return '';
}
