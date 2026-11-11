/// 花园守卫「今日券」的**唯一生效口**（把券折成 `PlantPerk`）+ 当日额度记账。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.7 / §3.8（收口表）。
///
/// ## 三条不可协商的纪律
///
/// ### ① 券的减免**只经本类产出 `PlantPerk`**
/// 页面 / 服务**禁止**内联 `-1` / `-2` / 「归零」。原因与 C77 称号属性完全同源
/// （防孪生 S2 / F68 先例）：`plant_perk.dart` 的 [waterCostOf] / [fertilizeCostOf]
/// 是「基础价 − 减免，再钳到 `[0, 基础价]`」的唯一算式，只要减免量走同一个
/// `PlantPerk`，券与称号就**天然相加**、也天然不会出现负价：
///
/// | 券 | 折成 | 实际效果（水 5 / 肥 10） |
/// |---|---|---|
/// | 浇水券 | `waterDiscount + 1` | 5 → 4（与 Lv.5 称号叠加：5 − 1 − 1 = 3） |
/// | 免费浇水券 | `waterDiscount + 5`（= [kPlantWaterCost]） | 5 → 0（钳制，绝不 −1） |
/// | 施肥券 | `fertilizeDiscount + 2` | 10 → 8（与 Lv.10 叠加：10 − 1 − 2 = 7） |
/// | 免费施肥券 | `fertilizeDiscount + 10`（= [kPlantFertilizeCost]） | 10 → 0 |
/// | 劳动券 | `weedBonus + 1, pestBonus + 1` | 除草 1 → 2 / 除虫 2 → 3 |
///
/// ### ② 🔴 免费券**只能用于单株**（本批最重要的安全约束）
/// 「一键浇水 5 盆 + 免费浇水券」若按整批生效 ⇒ 省 25 ☀ ⇒ 直接打穿浇水经济
/// （= 5 天浇水预算，见 PRD §3.7 硬约束 A / 验收 A10）。
/// 实现方式是**让批量调用拿不到减免**：[overlay] 的免费档在 `plantId == null`
/// （= 批量动作）时**返回不带免费减免的 perk**，[recordConsumed] 同样拒绝核销。
/// 「绝不整批免费」这条因此不依赖调用方自觉，也不依赖 UI 是否记得传 plantId。
///
/// ### ③ 额度记账走 `GuardDayState.buff`，不新建存储
/// 当日额度（施肥券 [kGuardFertilizerVoucherQuota] 次 / 免费券 1 次）就是
/// [GuardBuffState.quota]，已用 = [GuardBuffState.used]，一次核销 = 一个「券单位」
/// （[voucherUnitOf]）。超额由 [GuardBuffState.consume] 钳制 ⇒ 重复核销不会把
/// `used` 顶过 `quota`。
///
/// 🔴 **B13.4：浇水券 / 劳动券改「当日不限次」**（玄参拍板「-1 就该全天不限次」，
/// 原 PRD §3.7 的 6 ☀ / 4 ☀ 封顶废除）——这两张券的减免**只看种类、不看额度**
/// （[GuardVoucherKind.isUnlimitedDaily]），`quota` 数字仅作存量存档的记账兼容。
/// 施肥券按次记账、免费券单株单次的口径**不变**。
///
/// ## 券与掉落档的关系
/// 掉落档 [GuardDropKind] 有 6 个值（含 `none` = 无道具），券 [GuardVoucherKind]
/// 只有 5 个 —— 映射单点在枚举的构造参数上（[GuardVoucherKind.drop]），
/// 反查走 [GuardVoucherKind.of]。
library guard_voucher;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

/// 券的种类（= 掉落档里「有券」的那 5 档）。
///
/// 与 [GuardDropKind] **刻意分成两个枚举**：掉落档含 `none`（无道具，18%），
/// 而 `none` 不是券、不能减免、也不该出现在任何「用什么券」的 API 里。
/// 映射单点 = 构造参数 [drop]，反查 = [GuardVoucherKind.of]。
enum GuardVoucherKind {
  /// 浇水券：今日每次浇水每盆 −1 ☀（**当日不限次**，B13.4）。
  water(GuardDropKind.waterVoucher),

  /// 劳动券：今日每次除草 / 除虫 +1 ☀（**当日不限次**，B13.4）。
  labor(GuardDropKind.laborVoucher),

  /// 施肥券：今日**每次**施肥 −2 ☀（当日最多 [kGuardFertilizerVoucherQuota] 次）。
  fertilize(GuardDropKind.fertilizeVoucher),

  /// 🔴 免费浇水券：**任选一盆、仅一次**免费（绝不整批）。
  freeWater(GuardDropKind.freeWater),

  /// 🔴 免费施肥券：**任选一盆、仅一次**免费（最稀有）。
  freeFertilize(GuardDropKind.freeFertilize);

  const GuardVoucherKind(this.drop);

  /// 对应的掉落档（JSON / 埋点的线名仍以 [GuardDropKind.id] 为准）。
  final GuardDropKind drop;

  /// 掉落档 → 券种类；无道具档（[GuardDropKind.none]）返回 `null`。
  static GuardVoucherKind? of(GuardDropKind kind) {
    for (final GuardVoucherKind voucher in GuardVoucherKind.values) {
      if (voucher.drop == kind) return voucher;
    }
    return null;
  }

  /// 是否「免费」券（两种免费券 = true）。
  ///
  /// 🔴 免费券一律 [isSinglePlantOnly]：这是「绝不整批免费」的唯一判据。
  bool get isFree =>
      this == GuardVoucherKind.freeWater ||
      this == GuardVoucherKind.freeFertilize;

  /// 是否「当日不限次」券（浇水券 / 劳动券）。
  ///
  /// 🔴 **B13.4（玄参 2026-11-11 拍板）**：「今日浇水减 1，浇水次数应该不受
  /// 限制」——原 PRD §3.7 的当日累计封顶（浇水 6 ☀ / 劳动 4 ☀）**废除**：
  /// 减免全天足额生效。[guardVoucherQuotaOf] 的数字与存档里的 `quota` 字段
  /// **仅保留为记账**，不再钳制减免（真机实测：浇 6 次后价格从 4 跳回 5，
  /// 就是旧封顶 6 ☀ 用尽的表现）。
  bool get isUnlimitedDaily => this == water || this == labor;

  /// 是否只作用于单株单次（数据源 = [GuardDropSpec.singlePotOnly]）。
  bool get isSinglePlantOnly => drop.singlePotOnly;
}

/// 「动作种类」—— [guardVoucherKindForAction] 的输入。
///
/// 只列**有券可享**的三种动作：浇水 / 施肥 / 清理（除草 + 除虫共用劳动券）。
/// 刻意**不用** [GuardVoucherKind] 当动作参数：`freeWater` / `freeFertilize` 是
/// 「这张券叫什么」而不是「孩子在做什么」，拿它当输入必然要在调用侧再造一张
/// 「券 → 动作」的反向表（那就是本文件要消灭的第二份映射）。
enum GuardActionKind {
  /// 浇水（单株 / 一键批量）。
  water,

  /// 施肥。
  fertilize,

  /// 清理（除草 / 除虫）。
  labor,
}

/// 动作 → 该动作可享受的券种类（「同动作换名」：免费浇水券也算浇水券）。
///
/// 🔴 **单点**：`garden_page` 与 `plant_care_sheet` **都必须**调这个函数，
/// 不许各写一份 switch —— 两份映射只要分叉，就会出现「展示便宜、实扣全额」。
///
/// ## 为什么需要 [activeDrop]
/// [GuardVoucherService.overlayFor] / [GuardVoucherService.recordConsumed] 都有
/// 种类闸门（`GuardVoucherKind.of(buff.kind) != kind` 即拒绝，防「拿浇水券去免
/// 施肥费」）。当天掉落的是免费券时，`buff.kind` 是 [GuardDropKind.freeWater] /
/// [GuardDropKind.freeFertilize] —— 若调用方坚持按 `water` / `fertilize` 提问，
/// 免费券**永远不生效、也永远核销不掉**（面板显示 5 而不是 0，额度还占着）。
///
/// 传 `activeDrop` = 今天存档里那张券的掉落档时，返回**同动作换名后**的种类；
/// 不传（= 没券，或纯函数调用）时返回动作的基准券种。
GuardVoucherKind guardVoucherKindForAction(
  GuardActionKind action, {
  GuardDropKind? activeDrop,
}) {
  switch (action) {
    case GuardActionKind.water:
      return activeDrop == GuardDropKind.freeWater
          ? GuardVoucherKind.freeWater
          : GuardVoucherKind.water;
    case GuardActionKind.fertilize:
      return activeDrop == GuardDropKind.freeFertilize
          ? GuardVoucherKind.freeFertilize
          : GuardVoucherKind.fertilize;
    case GuardActionKind.labor:
      // 劳动券没有「免费版」：除草 / 除虫只有面值为 +1 ☀ 的那一张。
      return GuardVoucherKind.labor;
  }
}

/// 当日额度上限（单位随券而异：浇水 / 劳动券 = ☀，施肥 / 免费券 = 次）。
///
/// 🔴 数字全部来自 `prd_params.dart`，本函数只做「券 → 常量」的绑定。
int guardVoucherQuotaOf(GuardDropKind kind) {
  switch (kind) {
    case GuardDropKind.waterVoucher:
      // 🔴 B13.4：只作存量存档的记账兼容，**不再钳制减免**（当日不限次）。
      return kGuardWaterVoucherMaxSaves;
    case GuardDropKind.laborVoucher:
      // 同上（B13.4 不限次，数字仅记账）。
      return kGuardLaborVoucherCap;
    case GuardDropKind.fertilizeVoucher:
      // 今日**每次**施肥都 −2 ☀：额度单位是「次」，上界 = 最大盆位数
      // （每盆每天限施 1 次，见 [kGuardFertilizerVoucherQuota]）。
      return kGuardFertilizerVoucherQuota;
    case GuardDropKind.freeWater:
      return 1; // 1 次/天（单株）
    case GuardDropKind.freeFertilize:
      return 1; // 1 次/天（单株）
    case GuardDropKind.none:
      return 0; // 无道具档：没有额度
  }
}

/// 一次核销消耗多少个「额度单位」。
///
/// 浇水券 = 1 ☀（[kGuardWaterVoucherSave]）、劳动券 = 1 ☀（[kGuardLaborVoucherBonus]）、
/// 其余 = 1 次。单位与 [guardVoucherQuotaOf] 严格一致，故 `used <= quota` 恒成立。
int voucherUnitOf(GuardVoucherKind kind) {
  switch (kind) {
    case GuardVoucherKind.water:
      return kGuardWaterVoucherSave;
    case GuardVoucherKind.labor:
      return kGuardLaborVoucherBonus;
    case GuardVoucherKind.fertilize:
    case GuardVoucherKind.freeWater:
    case GuardVoucherKind.freeFertilize:
      return 1;
  }
}

/// 掉落档 → 当日 buff（无道具档返回 `null`：今天没有券）。
///
/// `claim()` 发放掉落时用它落 `GuardDayState.buff`；quota 与 kind 是**同一处**
/// 派生，故「发放」与「核销」不会各算一套上限。
GuardBuffState? guardBuffFor(GuardDropKind kind) {
  if (kind == GuardDropKind.none) return null;
  final int quota = guardVoucherQuotaOf(kind);
  if (quota <= 0) return null;
  return GuardBuffState(kind: kind, quota: quota);
}

/// 今日券服务（**唯一的券生效口**）。
///
/// 依赖 [GuardStateStore]（读今天那条状态里的 buff）+ [childId] 取值器 + 可注入时钟；
/// **不写账本**（券本身不发阳光，它是「今天便宜一点」）、不新建存储。
class GuardVoucherService {
  GuardVoucherService({
    required GuardStateStore store,
    required String Function() childId,
    DateTime Function()? clock,
  })  : _store = store,
        _childId = childId,
        _clock = clock ?? DateTime.now;

  final GuardStateStore _store;
  final String Function() _childId;
  final DateTime Function() _clock;

  /// 今天仍然存在的 buff（`null` = 今天没有券 / 存档是过去某天的 ⇒ 已过期）。
  ///
  /// ⚠️ 额度用完时**仍会返回该 buff**（`isExhausted == true`）：券在 UI 上还要
  /// 显示（只是不再减免），「用完了」与「从来没有」是两种不同的展示。
  /// 🔴 B13.5：返回**主券**（存档 `buff` 字段）；第二张券走 [currentBuffs]。
  Future<GuardBuffState?> currentBuff({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final GuardDayState state = await _store.read(_childId());
    if (state.dayKey != today) return null; // 掉落档「当天过期」
    return state.buff;
  }

  /// 🔴 B13.5：今天**所有**仍在生效的券（主券 + 第二张，0~2 张）。
  ///
  /// 花园页 buff 卡列、调试面板等「逐张展示」的调用方用本方法；
  /// 「按动作取减免」的调用方走 [overlay] / [recordConsumed]（内部按券种匹配）。
  Future<List<GuardBuffState>> currentBuffs({DateTime? now}) async {
    final String today = dayKey(now ?? _clock());
    final GuardDayState state = await _store.read(_childId());
    if (state.dayKey != today) return const <GuardBuffState>[];
    return <GuardBuffState>[
      if (state.buff != null) state.buff!,
      if (state.bonusBuff != null) state.bonusBuff!,
    ];
  }

  /// 🔴 B13.5：按**券种**从（最多两张）当日券里挑出匹配的那张。
  ///
  /// 「浇水动作只吃浇水券」：两张券互不干扰、可同时生效 —— 主券与第二张
  /// 的种类天然不同（rollBonus 排除首张），故匹配结果至多一张。
  Future<GuardBuffState?> _buffForKind(
    GuardVoucherKind kind, {
    DateTime? now,
  }) async {
    final String today = dayKey(now ?? _clock());
    final GuardDayState state = await _store.read(_childId());
    if (state.dayKey != today) return null; // 掉落档「当天过期」
    final GuardBuffState? primary = state.buff;
    if (primary != null && GuardVoucherKind.of(primary.kind) == kind) {
      return primary;
    }
    final GuardBuffState? bonus = state.bonusBuff;
    if (bonus != null && GuardVoucherKind.of(bonus.kind) == kind) {
      return bonus;
    }
    return null;
  }

  /// 今天这张券还剩多少额度（没有券 / 已过期 = 0）。
  Future<int> remainingOf(GuardVoucherKind kind, {DateTime? now}) async {
    final GuardBuffState? buff = await _buffForKind(kind, now: now);
    if (buff == null) return 0;
    return buff.remaining;
  }

  /// **纯计算核心**：把「今日券的减免」叠到称号 perk 上（不读存储、无副作用）。
  ///
  /// [buff] 来自 [currentBuff] 或调用方手里已有的当日状态；[base] 是称号 perk
  /// （可为 null = 无称号）。
  ///
  /// 🔴 [plantId] == null 表示**批量动作**（一键 N 盆）：此时免费券**一律不生效**，
  /// 返回的 perk 与 [base] 逐位相同 —— 「一键 5 盆免费 = 省 25 ☀」的漏洞不存在。
  PlantPerk overlayFor(
    GuardBuffState? buff,
    PlantPerk? base, {
    required GuardVoucherKind kind,
    required String? plantId,
  }) {
    final PlantPerk perk = base ?? PlantPerk.none;
    if (buff == null) return perk;
    // 今天只有一张券：种类不符绝不减免（防止「拿着浇水券去免施肥费」）
    if (GuardVoucherKind.of(buff.kind) != kind) return perk;
    // 🔴 B13.4：浇水 / 劳动券**当日不限次**（额度字段不再挡减免）；
    // 施肥券 / 免费券维持「额度用完 = 不再减免」（券仍然显示）。
    if (!kind.isUnlimitedDaily && !buff.hasRemaining) return perk;

    final bool single = plantId != null && plantId.isNotEmpty;
    switch (kind) {
      case GuardVoucherKind.water:
        // 每盆 −1（与称号减免相加；B13.4 起全天足额，不再按 remaining 缩减）
        return perk.add(const PlantPerk(waterDiscount: kGuardWaterVoucherSave));
      case GuardVoucherKind.labor:
        // 每次清理 +1（加在称号加成之后；B13.4 起全天足额）
        return perk.add(const PlantPerk(
          weedBonus: kGuardLaborVoucherBonus,
          pestBonus: kGuardLaborVoucherBonus,
        ));
      case GuardVoucherKind.fertilize:
        // ⚠️ 额度单位是「次」、减免额是 2 ☀ ⇒ **不按 remaining 缩额**：按
        // `min(2, remaining)` 缩额会让快用完时悄悄贬值（remaining=1 时只减 1）；
        // 是否生效只看 [GuardBuffState.hasRemaining]，每次施肥都足额 −2 ☀。
        // 当日上限由 [guardVoucherQuotaOf]（= [kGuardFertilizerVoucherQuota]）
        // 记账，[recordConsumed] 把 used 推到 quota 后来收口。
        return perk.add(const PlantPerk(
          fertilizeDiscount: kGuardFertilizerVoucherSave,
        ));
      case GuardVoucherKind.freeWater:
        // 🔴 批量（plantId == null）→ 不给减免，直接返回称号 perk。
        if (!single) return perk;
        return perk.add(const PlantPerk(waterDiscount: kPlantWaterCost));
      case GuardVoucherKind.freeFertilize:
        if (!single) return perk;
        return perk.add(const PlantPerk(fertilizeDiscount: kPlantFertilizeCost));
    }
  }

  /// 一次批量动作里**逐盆**的减免序列（长度 = [count]，第 i 项 = 第 i 盆该用的 perk）。
  ///
  /// 存在理由：券有当日封顶（浇水 6☀ / 劳动 4☀），批量里额度会**中途用尽**。
  /// 「券后单价 × 盆数」在额度用尽后就是错的（12 盆会少报 6☀）；本函数把
  /// 「第几盆开始回原价」算准，让**确认卡合计、余额闸门、执行扣费**三处同源。
  ///
  /// 免费券（[GuardVoucherKind.isSinglePlantOnly]）在这里自然失效：内部一律
  /// `plantId: null` 调 [overlayFor]，免费档直接返回 base —— 绝不整批免费。
  List<PlantPerk> overlaySequenceFor(
    GuardBuffState? buff,
    PlantPerk? base, {
    required GuardVoucherKind kind,
    required int count,
  }) {
    if (buff == null) {
      return List<PlantPerk>.filled(count, base ?? PlantPerk.none);
    }
    final List<PlantPerk> out = <PlantPerk>[];
    GuardBuffState? cur = buff;
    for (int i = 0; i < count; i++) {
      out.add(overlayFor(cur, base, kind: kind, plantId: null));
      // consume 自带钳制：额度到 0 后 hasRemaining == false，
      // 下一轮 overlayFor 自然返回 base（价格回到原样）。
      cur = cur?.consume(voucherUnitOf(kind));
    }
    return out;
  }

  /// 给「这一次调用」算出的有效 perk（= 称号 perk + 今日券减免）。
  ///
  /// 调用方式（第三批接线时照抄这两行）：
  /// ```dart
  /// final PlantPerk perk = await guardVouchers.overlay(
  ///   await growth.currentPerk(),
  ///   kind: GuardVoucherKind.water,
  ///   plantId: null,            // 一键批量；单株浇水传 plant.id
  /// );
  /// ```
  Future<PlantPerk> overlay(
    PlantPerk? base, {
    required GuardVoucherKind kind,
    required String? plantId,
    DateTime? now,
  }) async {
    // 🔴 B13.5：按券种从（最多两张）当日券里取匹配的那张。
    final GuardBuffState? buff = await _buffForKind(kind, now: now);
    return overlayFor(buff, base, kind: kind, plantId: plantId);
  }

  /// 真正用掉一次券额度（记账），**由调用方在动作成功后调用**。
  ///
  /// 幂等与安全：
  ///  · 动作失败**不要**调（先把钱扣成功、再核销 —— 反了会白送减免）；
  ///  · 免费券在 [plantId] == null（批量）时**拒绝核销**（否则一次批量就把
  ///    唯一的免费额度烧掉，而孩子一盆都没免费到）；
  ///  · 额度用尽 / 券种类不符 / 存档不是今天 → 空操作（不抛异常、不改存档）。
  Future<void> recordConsumed({
    required GuardVoucherKind kind,
    required String? plantId,
    DateTime? now,
  }) async {
    final String today = dayKey(now ?? _clock());
    final String childId = _childId();
    final GuardDayState state = await _store.read(childId);
    if (state.dayKey != today) return; // 跨天：券已过期
    // 🔴 B13.5：按券种找到匹配的那张（主券或第二张），记在哪张的账上要分清。
    final GuardBuffState? primary = state.buff;
    final bool onPrimary =
        primary != null && GuardVoucherKind.of(primary.kind) == kind;
    final GuardBuffState? bonus = state.bonusBuff;
    final bool onBonus =
        !onPrimary && bonus != null && GuardVoucherKind.of(bonus.kind) == kind;
    if (!onPrimary && !onBonus) return;
    final GuardBuffState buff = onPrimary ? primary : bonus!;
    if (!buff.hasRemaining) return;
    if (kind.isSinglePlantOnly && (plantId == null || plantId.isEmpty)) return;

    // 🔴 B13.4：不限次券（浇水 / 劳动）没有额度可记 —— 核销账只对
    // 「次数券」（施肥 / 免费）有意义；也不写库（省一次 prefs 写）。
    if (kind.isUnlimitedDaily) return;

    final GuardBuffState consumed = buff.consume(voucherUnitOf(kind));
    if (consumed == buff) return; // 钳制后无变化（already exhausted）→ 不写库
    await _store.write(
      childId,
      onPrimary
          ? state.copyWith(buff: consumed)
          : state.copyWith(bonusBuff: consumed),
    );
  }
}
