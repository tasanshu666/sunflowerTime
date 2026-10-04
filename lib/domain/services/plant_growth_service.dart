/// 植物养成领域服务（M3，§3.2 / §3.3 / §3.4）。
///
/// 纯 Dart、零 Flutter 依赖，可被 `flutter test` 直接单测。依赖接口而非实现，
/// 与 M2 同账本（[SunlightRepository.append]）保证植物消耗可追溯对账。
///
/// 关键纪律：
///  · 经济衔接：所有扣减经 `append(net<0, refType)`，扣前用 `balance()` 校验（§3.2 账本铁律）。
///    refType 区分 plant_plant / plant_water / plant_fertilize / plant_expand。
///    ⚠️ 死亡退款（`plant_death_refund`）**已废止**（玄参 2026-09-27「死亡全损」）：此后不再
///    产生新行，历史行只读（`child_sunlight_history_page` 仍保留其展示映射）。
///  · 软绑定底线（§4.6 H2）：成长系数 ×1.3（当日有效专注）/ ×1.0（无专注也长），**绝不因专注差而死亡**；
///    死亡只由「3+7 天未养护」触发（3 天未浇水→wilting，wilting 再 7 天→dead），死亡**全损、不返还任何资源**。
///  · 枯萎恢复（2026-09-23 替代原付费救回）：wilting 仅靠养护动作恢复——未满 3 天浇水 1 次即可；
///    已满 3 天需「浇水 3 次 + 施肥 1 次」（以账本为事实源计数，见 [_maybeRecover]）。
library plant_growth_service;

import 'dart:math';

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/bloom_reward_repository.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';

/// 植物养成业务异常（余额不足 / 状态非法 / 花盆占用等）。
class PlantOperationException implements Exception {
  final String message;

  const PlantOperationException(this.message);

  @override
  String toString() => 'PlantOperationException: $message';
}

/// 单株养护额度快照（M3 修订）：今日已用次数 + 是否可操作 + 阻塞原因。
///
/// 事实源为阳光账本（每次养护写一条 `refType='plant_water'/'plant_fertilize'`、
/// `refId=<植物 id>` 的记录），故「今日已用几次」与「上次浇水何时」都从账本读，
/// 不用 Plants 表加计数列，天然可对账、也不会被施肥动作污染（浇水最小间隔改用账本时间戳，
/// 避免施肥刷新 lastWaterAt 后绕过 30 分钟间隔）。
class PlantCareQuota {
  /// 今日已浇水次数。
  final int waterUsedToday;

  /// 今日已施肥次数。
  final int fertilizeUsedToday;

  /// 距下次可浇水还需多少分钟（0 = 间隔已满足）。仅由「30 分钟最小间隔」产生。
  final int minutesUntilNextWater;

  /// 不可浇水的原因（null = 可浇）。
  final String? waterBlockReason;

  /// 不可施肥的原因（null = 可施）。
  final String? fertilizeBlockReason;

  const PlantCareQuota({
    required this.waterUsedToday,
    required this.fertilizeUsedToday,
    required this.minutesUntilNextWater,
    required this.waterBlockReason,
    required this.fertilizeBlockReason,
  });

  /// 今日还可浇水次数。
  int get waterRemaining =>
      (kPlantWaterMaxPerDay - waterUsedToday).clamp(0, kPlantWaterMaxPerDay);

  /// 今日还可施肥次数。
  int get fertilizeRemaining =>
      (kPlantFertilizeMaxPerDay - fertilizeUsedToday)
          .clamp(0, kPlantFertilizeMaxPerDay);

  bool get canWater => waterBlockReason == null;
  bool get canFertilize => fertilizeBlockReason == null;
}

/// 种植计价方式（玄参 2026-09-27 物种表改版：按物种计价）。
enum PlantCostKind {
  /// 免费（初始物种向日葵 / 持有免费种植券）。
  free,

  /// 扣阳光（月光兰）。
  sunlight,

  /// 扣精品碎片（普通 [kSpeciesFragmentCostCommon] / 精英 [kSpeciesFragmentCostPremium]）。
  fragments,
}

/// 某物种的种植成本：[kind] + 数量（免费时 [amount] 恒为 0）。
class PlantCost {
  /// 计价方式。
  final PlantCostKind kind;

  /// 数量（阳光 / 碎片片数；[PlantCostKind.free] 时为 0）。
  final int amount;

  const PlantCost(this.kind, this.amount);

  /// 免费成本（数量恒 0）。
  const PlantCost.free() : this(PlantCostKind.free, 0);
}

/// 某物种的**可用支付方式**（玄参 2026-09-28 计价模型）。
///
/// 对应 UI「选择要种的植物」弹窗里的每个按钮：[kind] 决定扣哪种资源、[amount] 为数量
/// （[PlantCostKind.free] 时恒为 0）。见 [PlantGrowthService.plantPaymentOptions]。
class PlantPaymentOption {
  const PlantPaymentOption(this.kind, this.amount);

  /// 支付方式（免费 / 阳光 / 碎片）。
  final PlantCostKind kind;

  /// 数量（阳光片数 / 碎片片数；免费为 0）。
  final int amount;
}

/// 植物养成领域服务。
class PlantGrowthService {
  final PlantRepository _plants;
  final FocusRepository _focus;
  final SunlightRepository _ledger;
  final SettingsRepository _settings;
  final BloomRewardRepository _bloomRewards;
  final Uuid _uuid;
  final Random _random;

  /// 花园干扰物（杂草 / 害虫，口径 C26）专用随机源。
  ///
  /// 默认与 [_random] 同源（生产行为不变）；测试可单独注入「永不命中」的桩
  /// （见 `test/helpers/no_hit_random.dart`），既不让老成长 / 奖励断言被随机
  /// 暂停污染，也不消耗主随机序列（保住「结算零消耗」类计数断言）。
  final Random _weedRandom;

  /// 经济变更回调（可选）：任何会改变孩子端经济展示的操作成功后调用。
  /// 生产环境由 DI 装配自增 `economyRevisionProvider` 刷新 UI；域层保持零 Flutter 依赖。
  final void Function()? _onEconomyChanged;

  PlantGrowthService({
    required PlantRepository plants,
    required FocusRepository focus,
    required SunlightRepository ledger,
    required SettingsRepository settings,
    required BloomRewardRepository bloomRewards,
    Uuid? uuid,
    Random? random,
    Random? weedRandom,
    void Function()? onEconomyChanged,
  })  : _plants = plants,
        _focus = focus,
        _ledger = ledger,
        _settings = settings,
        _bloomRewards = bloomRewards,
        _uuid = uuid ?? const Uuid(),
        _random = random ?? Random(),
        _weedRandom = weedRandom ?? random ?? Random(),
        _onEconomyChanged = onEconomyChanged;

  /// 两档价：低年段取 low，其余（中 / 高）取 high（U3 决策：植物保留 §4.6 两档）。
  int _price(int low, int high, AgeTier tier) => tier == AgeTier.low ? low : high;

  /// 账本扣减（net<0）。refType 区分来源（§3.2 账本铁律）。
  Future<void> _appendSpend({
    required double amount,
    required SunlightType type,
    required String refType,
    required DateTime now,
    String? refId,
  }) async {
    final double balanceBefore = await _ledger.balance();
    final double newBalance = balanceBefore - amount;
    await _ledger.append(SunlightEntry(
      id: _uuid.v4(),
      ts: now,
      type: type,
      gross: -amount,
      net: -amount,
      balanceAfter: newBalance,
      refType: refType,
      refId: refId,
      dayKey: dayKey(now),
    ));
  }

  /// 账本入账（net>0，如开花奖励 / 大额阳光兜底）。
  Future<void> _appendEarn({
    required double amount,
    required String refType,
    required DateTime now,
    String? refId,
  }) async {
    final double balanceBefore = await _ledger.balance();
    final double newBalance = balanceBefore + amount;
    await _ledger.append(SunlightEntry(
      id: _uuid.v4(),
      ts: now,
      type: SunlightType.earn,
      gross: amount,
      net: amount,
      balanceAfter: newBalance,
      refType: refType,
      refId: refId,
      dayKey: dayKey(now),
    ));
  }

  /// 种植（校验花盆容量 / 占用 → 校验「每物种仅一株」→ **按物种计价收费** → 落 Plant）。
  ///
  /// 计价（玄参 2026-09-28 计价模型，见 [plantPaymentOptions]）：持有免费种植券 → 消耗券免费；
  /// 否则向日葵免费；精英仅碎片；普通二选一（阳光 / 碎片）。[payWith] 指定支付方式，
  /// 缺省按默认（精英→碎片 / 普通→阳光）。任一校验失败抛 [PlantOperationException]
  /// （UI 侧已前置校验并置灰，此处为兜底）。
  Future<Plant> plant(
    String speciesId,
    int potIndex,
    DateTime now, {
    PlantCostKind? payWith,
  }) async {
    final List<PlantSpecies> species = await _plants.species();
    final PlantSpecies? sp = _firstWhereOrNull(
      species,
      (PlantSpecies s) => s.id == speciesId,
    );
    if (sp == null) {
      throw const PlantOperationException('未找到该植物物种');
    }

    final AppSettings settings = await _settings.getSettings();
    final int capacity = settings.gardenPotCapacity;
    if (potIndex < 0 || potIndex >= capacity) {
      throw PlantOperationException('花盆序号超出容量（$potIndex / $capacity）');
    }

    // 占用校验：该花盆已有非死亡植物则不可种；有死亡残留则先释放。
    final List<Plant> existing = await _plants.plants();
    final bool occupied = existing.any(
      (Plant p) => p.potIndex == potIndex && p.status != PlantStatus.dead,
    );
    if (occupied) {
      throw PlantOperationException('花盆 #$potIndex 已被占用，请先清理');
    }
    final Plant? dead = _firstWhereOrNull(
      existing,
      (Plant p) => p.potIndex == potIndex && p.status == PlantStatus.dead,
    );
    if (dead != null) await _plants.deletePlant(dead.id);

    // 每物种同时仅存活一株（凋萎 wilting 仍算存活；死亡 dead 后可再种）。
    final bool alreadyGrowing = existing.any(
      (Plant p) => p.speciesId == speciesId && p.status != PlantStatus.dead,
    );
    if (alreadyGrowing) {
      throw const PlantOperationException('该植物已经在成长中啦');
    }

    // 按物种计价收费（免费券优先；碎片不足 / 阳光不足在此拦截）。
    await _chargeForPlanting(sp, settings, now, payWith: payWith);

    final Plant plant = Plant(
      id: _uuid.v4(),
      speciesId: speciesId,
      potIndex: potIndex,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthProgress: 0.0,
      growthFactor: 1.0,
      waterUsed: false,
      fertilizerUsed: false,
      status: PlantStatus.growing,
      plantedAt: now,
      lastWaterAt: now, // 种植即视为已浇水，枯萎计时从此起算
      wiltedAt: null,
      deadAt: null,
      mood: PlantMood.calm,
    );
    await _plants.savePlant(plant);
    // 种植可能改变经济（碎片 / 阳光）→ 通知 UI 刷新。
    _onEconomyChanged?.call();
    return plant;
  }

  /// 某物种的**可用支付方式**列表（玄参 2026-09-28 计价模型 + 2026-09-29 种子券入口）。
  ///
  /// 规则：
  ///  · 向日葵（[kStarterSpeciesId]）→ 单一免费项；
  ///  · **持有该物种免费种植券**（[BloomRewardRepository.unlockedSpeciesIds] 含其 id，
  ///    即「掉落过该物种种子且已收集」）→ **首项「用种子种 · 免费」**，付费项保留在后
  ///    （玄参 2026-09-29 拍板：券入口置顶 + 保留付费按钮）；
  ///  · 精英（[PlantSpecies.isPremium]）→ 单一碎片项（[kSpeciesFragmentCostPremium]）；
  ///  · 普通（其余）→ 两项：阳光（[kSpeciesSunlightCostCommon]）或碎片（[kSpeciesFragmentCostCommon]）。
  ///
  /// 领域层与 UI（花园页「选择要种的植物」弹窗）**必须共用本方法**，UI 不得自行重算价格。
  Future<List<PlantPaymentOption>> plantPaymentOptions(PlantSpecies sp) async {
    if (sp.id == kStarterSpeciesId) {
      return const <PlantPaymentOption>[PlantPaymentOption(PlantCostKind.free, 0)];
    }
    final List<PlantPaymentOption> paid = sp.isPremium
        ? const <PlantPaymentOption>[
            PlantPaymentOption(PlantCostKind.fragments, kSpeciesFragmentCostPremium)
          ]
        : <PlantPaymentOption>[
            const PlantPaymentOption(PlantCostKind.sunlight, kSpeciesSunlightCostCommon),
            const PlantPaymentOption(PlantCostKind.fragments, kSpeciesFragmentCostCommon),
          ];
    final Set<String> coupons = await _bloomRewards.unlockedSpeciesIds();
    if (coupons.contains(sp.id)) {
      return <PlantPaymentOption>[
        const PlantPaymentOption(PlantCostKind.free, 0),
        ...paid,
      ];
    }
    return paid;
  }

  /// 某物种的种植成本（**向后兼容**：返回 [plantPaymentOptions] 的默认项）。
  ///
  /// 旧「首购优惠 / 月光兰阳光价」计价（玄参 2026-09-27）已废弃（玄参 2026-09-28 计价模型拍板）：
  /// 向日葵免费；精英仅碎片；普通二选一（阳光 400 / 碎片 6），默认取阳光。领域层与 UI 的
  /// **唯一真源**已是 [plantPaymentOptions]，本方法仅供需要单个 [PlantCost] 的历史调用
  /// （测试 / 旧弹窗路径）使用，不应在收费主链路使用。
  Future<PlantCost> plantCost(PlantSpecies sp, AgeTier tier) async {
    final List<PlantPaymentOption> options = await plantPaymentOptions(sp);
    final PlantPaymentOption def = options.first;
    return PlantCost(def.kind, def.amount);
  }

  /// 某物种的精品碎片价：初始免费物种（[kStarterSpeciesId]）为 0，其余普通档
  /// [kSpeciesFragmentCostCommon] / 精英档 [kSpeciesFragmentCostPremium]（档位判据同
  /// [PlantSpecies.isPremium]）。
  int fragmentCostOf(PlantSpecies sp) {
    if (sp.id == kStarterSpeciesId) return 0;
    return sp.isPremium
        ? kSpeciesFragmentCostPremium
        : kSpeciesFragmentCostCommon;
  }

  /// 种植收费（玄参 2026-09-28 计价模型：向日葵免费 / 精英仅碎片 / 普通二选一）。
  ///
  ///  · 持有免费种植券（[BloomRewardRepository.unlockedSpeciesIds] 含该 id）→ **消耗券**，免费，
  ///    不写 `plant_plant`（故不消耗任何资源）；
  ///  · 向日葵（[kStarterSpeciesId]）→ 免费；
  ///  · 决定 `kind = payWith ?? (sp.isPremium ? fragments : sunlight)`；
  ///    - 防御：精英且 `payWith == sunlight` → 抛 `PlantOperationException('精英植物只能用碎片兑换')`；
  ///    - `sunlight` 分支：扣 [kSpeciesSunlightCostCommon] 阳光（余额不足抛『阳光不足，还差 N 阳光』），
  ///      走 `_appendSpend`（refType='plant_plant'、refId=物种 id）作审计；
  ///    - `fragments` 分支：`amount = sp.isPremium ? [kSpeciesFragmentCostPremium] : [kSpeciesFragmentCostCommon]`，
  ///      调 `_spendPremiumFragments`；
  ///    - `free` 分支：直接返回。
  Future<void> _chargeForPlanting(
    PlantSpecies sp,
    AppSettings settings,
    DateTime now, {
    PlantCostKind? payWith,
  }) async {
    final Set<String> coupons = await _bloomRewards.unlockedSpeciesIds();
    if (coupons.contains(sp.id)) {
      await _bloomRewards.consumeUnlock(sp.id); // 免费种植券：消耗券，不扣任何资源
      return;
    }
    if (sp.id == kStarterSpeciesId) return; // 初始免费物种

    final PlantCostKind kind =
        payWith ?? (sp.isPremium ? PlantCostKind.fragments : PlantCostKind.sunlight);

    // 防御：精英档仅接受碎片兑换。
    if (sp.isPremium && kind == PlantCostKind.sunlight) {
      throw const PlantOperationException('精英植物只能用碎片兑换');
    }

    switch (kind) {
      case PlantCostKind.free:
        return;
      case PlantCostKind.sunlight:
        final double balance = await _ledger.balance();
        if (balance < kSpeciesSunlightCostCommon) {
          throw PlantOperationException(
            '阳光不足，还差 ${(kSpeciesSunlightCostCommon - balance).ceil()} 阳光',
          );
        }
        await _appendSpend(
          amount: kSpeciesSunlightCostCommon.toDouble(),
          type: SunlightType.plant,
          refType: 'plant_plant',
          now: now,
          refId: sp.id,
        );
        return;
      case PlantCostKind.fragments:
        final int amount = sp.isPremium
            ? kSpeciesFragmentCostPremium
            : kSpeciesFragmentCostCommon;
        await _spendPremiumFragments(amount);
        return;
    }
  }

  /// 消耗精品碎片（余额不足直接抛，**绝不允许扣成负数**）。
  Future<void> _spendPremiumFragments(int cost) async {
    if (cost <= 0) return;
    final int balance = await _bloomRewards.premiumFragmentBalance();
    if (balance < cost) {
      throw PlantOperationException('碎片不足，还差 ${cost - balance} 片');
    }
    await _bloomRewards.setPremiumFragmentBalance(balance - cost);
  }

  /// 计时驱动成长：对每株推进 growthProgress；满 1.0 进阶段；adult 满 → bloomed；
  /// 同时处理枯萎 / 死亡（死亡**全损**，不写任何账本行）。返回更新后的全部植物。
  ///
  /// 成株后循环玩法 Batch 1 双阶段奖励（玄参 2026-09-26 变更 B 后）：① 每株若本次 tick
  /// 新盛开 → **登记两条**待收集记录（开花瞬间 `due=bloomedAt` + 第二段 `due=+48h`），
  /// 并在**登记时当场 roll** 好奖励内容落库（「掉落即定奖」，v12），**不再即时入账**；
  /// ② 结算「已到期但已无法收集」的待收集奖励（花谢 / 枯萎 / 植物消失 → 自动兜底发放，
  /// 照单发放库中已定好的奖励）。**仍可收集**（植物仍盛开）的到期奖励不在此发放，
  /// 留给花园页头顶图标，由小朋友手动点击收集（[collectBloomReward]）。
  ///
  /// [autoSettled]（可选，非 null 时）按结算顺序**追加**每条「花谢兜底自动到账」奖励的
  /// [BloomRewardOutcome]（`autoSettled: true`），供花园页提示「花朵凋谢，奖励已自动收下：…」。
  /// 默认 null → 完全向后兼容，**不改返回类型**（仍为 `List<Plant>`）。
  Future<List<Plant>> tickAll(
    DateTime now, {
    List<BloomRewardOutcome>? autoSettled,
  }) async {
    final List<PlantSpecies> species = await _plants.species();
    final Map<String, PlantSpecies> speciesMap =
        <String, PlantSpecies>{for (final PlantSpecies s in species) s.id: s};

    final List<Plant> all = await _plants.plants();

    final List<Plant> updated = <Plant>[];
    if (all.isNotEmpty) {
      // 预计算日期范围（最早种植时间 → now）内的有效专注日，避免每株每日起异步查库。
      DateTime earliest = now;
      for (final Plant p in all) {
        if (p.stageStartedAt.isBefore(earliest)) earliest = p.stageStartedAt;
      }
      final Set<String> wfdDays = await _validFocusDayKeys(earliest, now);
      final bool todayWfd = await _hasValidFocusDay(now);

      for (final Plant p in all) {
        final PlantSpecies? sp = speciesMap[p.speciesId];
        if (sp == null) {
          updated.add(p); // 物种缺失（数据安全）跳过成长
          continue;
        }
        // 花园干扰物「杂草 / 害虫」每日 roll（口径 C26）：每株**当天一次**、活株才参与。
        // 次日零点 ≠ 今日零点 → 杂草 / 虫自动失效、成长恢复，**不会永久卡住成长**。
        Plant np = _advanceGrowth(_rollWeedPest(p, now), sp, now, wfdDays);
        // 本次 tick 新盛开（growing → bloomed）：发放开花瞬间奖励。
        final bool justBloomed =
            p.status != PlantStatus.bloomed && np.status == PlantStatus.bloomed;
        np = _applyBloomCycle(np, sp, now);
        np = _applyWiltAndDeath(np, now);
        np = _deriveMood(np, now, todayWfd);

        final bool changed = np != p;
        // 死亡**全损**（玄参 2026-09-27 拍板）：仅置状态、释放花盆，**不写任何账本行**
        // （此前返还 30% 成本的逻辑已废止，历史 `plant_death_refund` 行只读）。
        if (changed) await _plants.savePlant(np);
        if (justBloomed) {
          // 变更 B：开花瞬间奖励不再即时入账，改为登记两条待收集记录
          // （瞬间 due=bloomedAt + 第二段 due=+48h），点击气泡才入账。
          await _enqueueBloomRewards(np, sp, species, now);
        }
        updated.add(np);
      }
    }

    // 结算「已到期但已无法收集」的待收集奖励（花谢 / 枯萎 / 植物消失 → 自动兜底发放）。
    final bool anyAutoSettled = await _autoSettleUncollectibleRewards(
        species, now, updated, autoSettled);

    if (anyAutoSettled) _onEconomyChanged?.call();
    return updated;
  }

  /// 花园干扰物「杂草 / 害虫」每日 roll（口径 C26，玄参 2026-09-30 拍板）。
  ///
  /// 规则（与 prd_params「花园干扰物」常量段一一对应）：
  ///  · 每株**活着的**植物（dead 不参与）每天**各自** roll 一次，互不共享
  ///    （每盆差异大，花园更热闹）；
  ///  · 杂草 [kGardenWeedRate] / 害虫 [kGardenPestRate] 独立判定、**可同时出现**；
  ///  · 同一天重复 tick **不重 roll**（幂等基准 `weedPestRollDay`）——否则「每天发生
  ///    一次」会退化成「每次 tick 都 roll」，杂草在孩子开着 App 的几小时里凭空冒出来；
  ///  · 只在其出现的**当天**有效：次日零点 ≠ 今日零点 → 自动清空、成长次日恢复。
  ///
  /// 返回**新的** Plant：当日发生 roll 时写入 weed_at / pest_at / weed_pest_roll_day；
  /// 已在今日 roll 过则原样返回（调用方据此判定是否变化、是否需落库）。
  Plant _rollWeedPest(Plant p, DateTime now) {
    if (p.status == PlantStatus.dead) return p;
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (p.weedPestRollDay == today) return p; // 今日已 roll → 幂等
    return p.copyWith(
      weedAt: _rollHit(kGardenWeedRate, _weedRandom) ? today : null,
      pestAt: _rollHit(kGardenPestRate, _weedRandom) ? today : null,
      weedPestRollDay: today,
    );
  }

  /// 按概率掷一次（随机源由构造器注入，测试可喂固定 `Random` 保证确定性）。
  bool _rollHit(double rate, [Random? source]) =>
      (source ?? _random).nextDouble() < rate;

  /// 逐日推进成长进度（sync）。系数：当日有效专注 ×1.3，否则 ×1.0。
  Plant _advanceGrowth(
    Plant p,
    PlantSpecies sp,
    DateTime now,
    Set<String> wfdDays,
  ) {
    if (p.status == PlantStatus.dead) return p;

    // 杂草 / 害虫任一存在 → 当天成长暂停（口径 C26）：不累加进度。
    //
    // ⚠️ 但**照常推进幂等基准** `stageStartedAt → now`：暂停的这段时间就让它过去，
    // 清掉干扰物后不再倒补。否则「有虫不长」会因为「攒着暂停时长、清完一次补回来」
    // 而**净损失为零** —— 惩罚彻底归零，孩子不除草照样一点不亏。
    // （返回入参 p 本身也会「不推进基准」，那是另一个 bug，不要照抄。）
    if (p.hasPestOrWeed) {
      return p.copyWith(
        stageStartedAt:
            now.isAfter(p.stageStartedAt) ? now : p.stageStartedAt,
      );
    }

    double progress = p.growthProgress;
    PlantStage stage = p.stage;
    bool waterUsed = p.waterUsed;
    bool fertilizerUsed = p.fertilizerUsed;
    double lastFactor = p.growthFactor;
    DateTime stageStartedAt = p.stageStartedAt;
    DateTime? bloomedAt = p.bloomedAt;
    int bloomCount = p.bloomCount;

    DateTime cursor = stageStartedAt;
    while (cursor.isBefore(now)) {
      final DateTime dayEnd = DateTime(cursor.year, cursor.month, cursor.day)
          .add(const Duration(days: 1));
      final DateTime segEnd = dayEnd.isAfter(now) ? now : dayEnd;
      // 注意：1 小时 = 3,600,000,000 微秒（原实现除以 3,600,000，整整快了 1000 倍，
      // 2026-09-22 修）。此处改用微秒 / 3.6e9，避免 inHours 截断不足 1 小时的片段。
      final double segHours =
          segEnd.difference(cursor).inMicroseconds / 3600000000.0;
      final bool wfd = wfdDays.contains(dayKey(cursor));
      final double factor = wfd ? kGrowthFactorFocused : 1.0;
      lastFactor = factor;
      // V2（玄参大人 2026-09-22）：growthHoursPerStage 已是「不养护也要 N 天长成」
      // 的**真实目标时长**，故 [kPlantAutoGrowthScale] = 1.0，自动成长按真实时间
      // 推进、不再额外缓速；养护（浇水 +1% / 施肥 +3%）在其之上叠加。
      // ⚠️ 施肥 2026-09-22 定为 +5%，2026-09-25 玄参拍板调为 **+3%**（原话「有点快」）；
      // 这里不写死数字，实际取 [kPlantFertilizeProgressGain]，改常量即生效。
      //
      // 成株后循环玩法 Batch 1（玄参拍板）：首花（bloomCount == 0，seed→sprout→adult 初始成长）
      // 沿用原常量、零改动；复开花（bloomCount ≥ 1，花谢回落 0.5 后的回填）改用独立复开花
      // 速率 [kRebloomAutoProgressPerDay]（普通 0.036/天），精品再 ÷ [kRebloomPremiumCycleMultiplier]。
      // 当日有效专注系数（factor）对两档一致生效，保持软绑定。
      if (p.bloomCount == 0) {
        progress +=
            segHours * factor / sp.growthHoursPerStage * kPlantAutoGrowthScale;
      } else {
        final double premiumDiv =
            sp.isPremium ? kRebloomPremiumCycleMultiplier : 1.0;
        progress +=
            segHours * factor * (kRebloomAutoProgressPerDay / 24.0) / premiumDiv;
      }
      cursor = segEnd;

      // 阶段推进（seed→sprout→adult），每段重置浇水 / 施肥标记。
      //
      // 浮点容差：24h/240h 累加 10 次得到的是 0.9999999999999999 而非 1.0，
      // 严格 `>= 1.0` 会把「正好 10 天一阶段」推成 11 天（2026-09-22 修）。
      while (stage.index < PlantStage.adult.index &&
          progress >= 1.0 - kGrowthEpsilon) {
        progress -= 1.0;
        if (progress < 0) progress = 0.0; // 吃掉残留的 -1e-16
        stage = PlantStage.values[stage.index + 1];
        waterUsed = false;
        fertilizerUsed = false;
        stageStartedAt = now; // 阶段计时自本次 tick 起
      }
    }

    // 幂等基准（2026-09-22 修）：把「上次成长结算点」推进到 now（只推进、不回退）。
    //
    // 原实现只在**跨阶段**时更新该字段，阶段没跨过时它原地不动，于是每次
    // tickAll 都会把「stageStartedAt → now」整段时间**重新累加**到已有进度上
    // ——真机表现为「浇水标注 +12%、实际阶段进度跳 21%」。推进到 now 后，第二次
    // tick 的 cursor 就是上一次的 now，只累加新增增量，即幂等。
    if (now.isAfter(stageStartedAt)) {
      stageStartedAt = now;
    }

    PlantStatus status = p.status;
    if (stage == PlantStage.adult) {
      if (progress >= 1.0 - kGrowthEpsilon) {
        progress = 1.0; // 同上：容差内视为长满，避免「差 1e-16 开不了花」
        if (status == PlantStatus.growing) {
          status = PlantStatus.bloomed; // 成株终点（仍可被浇水 / 枯萎）
          bloomedAt = now; // 进入花期，记录起点（花谢循环计时基准）
          bloomCount += 1; // 累计盛开次数（复开花节奏判据；首花即 0→1）
        }
      }
    }

    if (stage == p.stage &&
        progress == p.growthProgress &&
        status == p.status &&
        waterUsed == p.waterUsed &&
        fertilizerUsed == p.fertilizerUsed &&
        lastFactor == p.growthFactor &&
        stageStartedAt == p.stageStartedAt &&
        bloomedAt == p.bloomedAt &&
        bloomCount == p.bloomCount) {
      return p; // 无变化
    }
    return p.copyWith(
      stage: stage,
      growthProgress: progress,
      growthFactor: lastFactor,
      waterUsed: waterUsed,
      fertilizerUsed: fertilizerUsed,
      status: status,
      stageStartedAt: stageStartedAt,
      bloomedAt: bloomedAt,
      bloomCount: bloomCount,
    );
  }

  /// 枯萎 / 死亡状态机（sync，纯状态迁移；死亡**全损**、无退款）。
  Plant _applyWiltAndDeath(Plant p, DateTime now) {
    if (p.status == PlantStatus.dead) return p;

    PlantStatus status = p.status;
    DateTime? wiltedAt = p.wiltedAt;
    DateTime? deadAt = p.deadAt;

    // 枯萎：growing/bloomed 且距上次浇水 ≥ kPlantWiltDays 天。
    if ((status == PlantStatus.growing || status == PlantStatus.bloomed) &&
        p.lastWaterAt != null &&
        now.difference(p.lastWaterAt!) >= Duration(days: kPlantWiltDays)) {
      status = PlantStatus.wilting;
      wiltedAt = now;
    }

    // 死亡：wilting 且距枯萎起点 ≥ kPlantDeathDays 天。
    if (status == PlantStatus.wilting &&
        wiltedAt != null &&
        now.difference(wiltedAt) >= Duration(days: kPlantDeathDays)) {
      status = PlantStatus.dead;
      deadAt = now;
    }

    if (status == p.status && wiltedAt == p.wiltedAt && deadAt == p.deadAt) {
      return p;
    }
    return p.copyWith(status: status, wiltedAt: wiltedAt, deadAt: deadAt);
  }

  /// 花谢循环状态机（sync，玄参大人 2026-09-23 拍板循环玩法）。
  ///
  /// 自然逻辑：盛开不能一直保持。花期后花朵凋谢 → 退回成株(growing)，进度回落到
  /// [kBloomWiltProgressFloor]，由时间（自动成长）或养护（浇水/施肥）把进度重新养满后
  /// 再度盛开。体型保持成株，不缩回幼苗。
  ///
  /// 成株后循环玩法 Batch 1：花期分档——普通 [kBloomDurationDays]（3 天）、
  /// 精品 [kBloomDurationDaysPremium]（4.5 天），由 [sp] 的 [PlantSpecies.isPremium] 判定。
  ///
  /// `bloomedAt == null` 的情况（老库升级来的已开花植物）：以本次 tick 为计时起点补上，
  /// 不立即花谢、也不丢失已有盛开状态；后续 tick 才正常倒计时。
  Plant _applyBloomCycle(Plant p, PlantSpecies sp, DateTime now) {
    if (p.status != PlantStatus.bloomed) return p;

    final DateTime? bloomedAt = p.bloomedAt;
    if (bloomedAt == null) {
      // 老库升级来的已开花植物：补上计时起点，本 tick 不花谢。
      return p.copyWith(bloomedAt: now);
    }
    if (now.difference(bloomedAt) < _bloomDuration(sp)) {
      return p; // 花期内，保持盛开
    }

    // 花期结束 → 花谢：退到成株(growing)，进度回落。
    // 注：此处不显式清空 bloomedAt——[Plant.copyWith] 的 `bloomedAt ?? this.bloomedAt`
    // 会把显式 null 回退成旧值，且花谢后 status 已非 bloomed，bloomedAt 不再被读取；
    // 下次再盛开时 [_advanceGrowth] 会用 now 重新写入正确的花期起点。
    return p.copyWith(
      status: PlantStatus.growing,
      growthProgress: kBloomWiltProgressFloor,
    );
  }

  /// 花期时长（普通 [kBloomDurationDays] 天 / 精品 [kBloomDurationDaysPremium] 天）。
  /// 精品为小数天（4.5），故按毫秒精度换算（[Duration] 的 days 仅接受 int）。
  Duration _bloomDuration(PlantSpecies sp) {
    final double days =
        sp.isPremium ? kBloomDurationDaysPremium : kBloomDurationDays.toDouble();
    return Duration(milliseconds: (days * Duration.millisecondsPerDay).round());
  }

  /// 推导心情（sync）：wilting→thirsty；今日有有效专注→happy；超 1 天未浇水→thirsty；否则 calm。
  Plant _deriveMood(Plant p, DateTime now, bool todayWfd) {
    PlantMood mood;
    if (p.status == PlantStatus.wilting) {
      mood = PlantMood.thirsty;
    } else if (p.status == PlantStatus.dead) {
      mood = PlantMood.calm;
    } else if (todayWfd) {
      mood = PlantMood.happy;
    } else if (p.lastWaterAt != null &&
        now.difference(p.lastWaterAt!) >= const Duration(days: 1)) {
      mood = PlantMood.thirsty;
    } else {
      mood = PlantMood.calm;
    }
    if (mood == p.mood) return p;
    return p.copyWith(mood: mood);
  }

  /// 读取单株养护额度（M3 修订口径）。
  ///
  /// 规则：① 成长中 / 枯萎态可养护（dead 态不可养护）；② 浇水每天 ≤
  /// [kPlantWaterMaxPerDay] 次、施肥每天 ≤ [kPlantFertilizeMaxPerDay] 次；③ 两次浇水间隔 ≥
  /// [kPlantWaterIntervalMinutes] 分钟（「不能连续浇水」）。wilting 态浇水 / 施肥用于养护恢复。
  Future<PlantCareQuota> careQuota(Plant p, DateTime now) async {
    final String today = dayKey(now);
    final int waterUsed = await _ledger.countByRefTypeAndRefIdOnDay(
      'plant_water',
      p.id,
      today,
    );
    final int fertilizeUsed = await _ledger.countByRefTypeAndRefIdOnDay(
      'plant_fertilize',
      p.id,
      today,
    );
    final DateTime? lastWater =
        await _ledger.lastTsByRefTypeAndRefId('plant_water', p.id);
    final int minutesUntilNextWater = _minutesUntilNextWater(lastWater, now);

    final bool actionable =
        p.status == PlantStatus.growing || p.status == PlantStatus.wilting;
    final String? waterBlock = !actionable
        ? '仅成长中/枯萎植物可养护'
        : waterUsed >= kPlantWaterMaxPerDay
            ? '今日浇水已达 $kPlantWaterMaxPerDay 次上限'
            : minutesUntilNextWater > 0
                ? '浇水间隔需 $kPlantWaterIntervalMinutes 分钟，还需 $minutesUntilNextWater 分钟'
                : null;
    final String? fertilizeBlock = !actionable
        ? '仅成长中/枯萎植物可养护'
        : fertilizeUsed >= kPlantFertilizeMaxPerDay
            ? '今日施肥已达 $kPlantFertilizeMaxPerDay 次上限'
            : null;

    return PlantCareQuota(
      waterUsedToday: waterUsed,
      fertilizeUsedToday: fertilizeUsed,
      minutesUntilNextWater: minutesUntilNextWater,
      waterBlockReason: waterBlock,
      fertilizeBlockReason: fertilizeBlock,
    );
  }

  /// 批量读取养护额度（花园页一屏 N 盆，逐株并发查账本）。
  Future<Map<String, PlantCareQuota>> careQuotas(
    List<Plant> plants,
    DateTime now,
  ) async {
    final List<PlantCareQuota> quotas = await Future.wait(
      plants.map((Plant p) => careQuota(p, now)),
    );
    return <String, PlantCareQuota>{
      for (int i = 0; i < plants.length; i++) plants[i].id: quotas[i],
    };
  }

  /// 距离「可再次浇水」的剩余分钟（0 表示满足 [kPlantWaterIntervalMinutes] 间隔）。
  static int _minutesUntilNextWater(DateTime? lastWaterAt, DateTime now) {
    if (lastWaterAt == null) return 0; // 从未浇水（含刚种植）→ 立即可浇
    final Duration elapsed = now.difference(lastWaterAt);
    final Duration need = const Duration(minutes: kPlantWaterIntervalMinutes);
    if (elapsed >= need) return 0;
    return (need - elapsed).inSeconds ~/ 60 + 1;
  }

  /// 浇水：校验额度（每日次数 + 30 分钟间隔）→ 扣 [kPlantWaterCost] 阳光
  /// (refType='plant_water') → 进度 +[kPlantWaterProgressGain] → lastWaterAt=now（重置枯萎计时）。
  ///
  /// 若动作前植物处于 wilting，浇完后用 [_maybeRecover] 评估是否靠养护恢复（2026-09-23 替代付费救回）。
  Future<void> water(String plantId, DateTime now) async {
    final Plant? p = await _plants.plant(plantId);
    if (p == null) throw const PlantOperationException('植物不存在');
    final PlantCareQuota quota = await careQuota(p, now);
    if (quota.waterBlockReason != null) {
      throw PlantOperationException(quota.waterBlockReason!);
    }
    await _spendCheck(kPlantWaterCost);
    await _appendSpend(
      amount: kPlantWaterCost.toDouble(),
      type: SunlightType.plant,
      refType: 'plant_water',
      now: now,
      refId: plantId,
    );
    // 固定增量（当前阶段 0..1），非「剩余比例」，避免种子阶段一步涨太多（用户 2026-09-21）。
    // 成株后循环 Batch 1：复开花（bloomCount≥1）改用 [kRebloomWaterProgressGain]，精品再 ÷1.5。
    final PlantSpecies? sp = await _speciesOf(p.speciesId);
    final double progress = p.growthProgress +
        _careProgressGain(p, kPlantWaterProgressGain, kRebloomWaterProgressGain, sp);
    final Plant after = p.copyWith(
      growthProgress: progress > 1.0 ? 1.0 : progress,
      waterUsed: true,
      lastWaterAt: now,
    );
    // wilting 态浇水后评估恢复；非 wilting 直接落库（等同原逻辑）。
    final Plant recovered =
        p.status == PlantStatus.wilting ? await _maybeRecover(after, now) : after;
    await _plants.savePlant(recovered);
  }

  /// 施肥：校验额度（每日 1 次）→ 扣 [kPlantFertilizeCost] 阳光
  /// (refType='plant_fertilize') → 进度 +[kPlantFertilizeProgressGain]。
  ///
  /// 注意：施肥同样刷新 lastWaterAt=now（与浇水一致）。若动作前植物处于 wilting，
  /// 施完后用 [_maybeRecover] 评估是否靠养护恢复（2026-09-23 替代付费救回）。
  Future<void> fertilize(String plantId, DateTime now) async {
    final Plant? p = await _plants.plant(plantId);
    if (p == null) throw const PlantOperationException('植物不存在');
    final PlantCareQuota quota = await careQuota(p, now);
    if (quota.fertilizeBlockReason != null) {
      throw PlantOperationException(quota.fertilizeBlockReason!);
    }
    await _spendCheck(kPlantFertilizeCost);
    await _appendSpend(
      amount: kPlantFertilizeCost.toDouble(),
      type: SunlightType.plant,
      refType: 'plant_fertilize',
      now: now,
      refId: plantId,
    );
    // 固定增量（当前阶段 0..1），同浇水口径（用户 2026-09-21）。
    // 成株后循环 Batch 1：复开花（bloomCount≥1）改用 [kRebloomFertilizeProgressGain]，精品再 ÷1.5。
    final PlantSpecies? sp = await _speciesOf(p.speciesId);
    final double progress = p.growthProgress +
        _careProgressGain(
            p, kPlantFertilizeProgressGain, kRebloomFertilizeProgressGain, sp);
    final Plant after = p.copyWith(
      growthProgress: progress > 1.0 ? 1.0 : progress,
      fertilizerUsed: true,
      lastWaterAt: now,
    );
    // wilting 态施肥后评估恢复；非 wilting 直接落库（等同原逻辑）。
    final Plant recovered =
        p.status == PlantStatus.wilting ? await _maybeRecover(after, now) : after;
    await _plants.savePlant(recovered);
  }

  /// 拔掉杂草（口径 C26，玄参 2026-09-30 拍板）：清除当天杂草 + 入账
  /// [kGardenWeedReward] 阳光（账本 `refType='plant_weed'`，可 child 端阳光来源显示）。
  ///
  /// 分因失败抛 [PlantOperationException]：植物不存在 / 已死亡 / 本盆当前无杂草。
  /// ⚠️ 清除后**保留** `weedPestRollDay = 今天`：否则同日再 tick 会重 roll 又长出杂草，
  /// 「点一下就没了」退化成「点完没几分钟又冒出来」。
  Future<void> clearWeed(String plantId, DateTime now) =>
      _clearPestOrWeed(plantId: plantId, now: now, isWeed: true);

  /// 除虫（口径 C26，玄参 2026-09-30 拍板）：语义同 [clearWeed]，奖励
  /// [kGardenPestReward] 阳光（账本 `refType='plant_pest'`）。
  Future<void> clearPest(String plantId, DateTime now) =>
      _clearPestOrWeed(plantId: plantId, now: now, isWeed: false);

  /// [clearWeed] / [clearPest] 的公共实现（入账 + 清字段，不做第二次校验）。
  Future<void> _clearPestOrWeed({
    required String plantId,
    required DateTime now,
    required bool isWeed,
  }) async {
    final Plant? p = await _plants.plant(plantId);
    if (p == null) throw const PlantOperationException('植物不存在');
    if (p.status == PlantStatus.dead) {
      throw const PlantOperationException('这株已经枯萎了，不用清理啦');
    }
    final bool hit = isWeed ? p.hasWeed : p.hasPest;
    if (!hit) {
      throw PlantOperationException(isWeed ? '这盆没有杂草哦' : '这盆没有害虫哦');
    }
    await _appendEarn(
      amount: isWeed ? kGardenWeedReward : kGardenPestReward,
      refType: isWeed ? kGardenWeedRefType : kGardenPestRefType,
      now: now,
      refId: plantId,
    );
    final Plant after =
        isWeed ? p.copyWith(weedAt: null) : p.copyWith(pestAt: null);
    await _plants.savePlant(after);
  }

  /// 余额闸门：不足则抛 [PlantOperationException]（扣减前校验，§3.2 账本铁律）。
  Future<void> _spendCheck(int cost) async {
    final double balance = await _ledger.balance();
    if (balance < cost) {
      throw PlantOperationException('阳光不足，还差 ${(cost - balance).ceil()} 阳光');
    }
  }

  /// 枯萎后靠养护恢复（2026-09-23 替代原付费救回）。
  ///
  /// 判定以账本为事实源：自 [Plant.wiltedAt] 起累计 `plant_water` / `plant_fertilize` 条数。
  ///  · wiltedAt 距今 < [kPlantWiltRecoverHardDays] 天：浇水 1 次即可恢复；
  ///  · 已满阈值：需浇水 [kPlantWiltRecoverHardWater] 次 + 施肥 [kPlantWiltRecoverHardFertilize] 次。
  /// 不满足则返回原 [p]（调用方照常保存，不额外落库）。
  Future<Plant> _maybeRecover(Plant p, DateTime now) async {
    if (p.status != PlantStatus.wilting || p.wiltedAt == null) return p;
    final bool hard =
        now.difference(p.wiltedAt!) >= Duration(days: kPlantWiltRecoverHardDays);
    final int w = await _ledger.countByRefTypeAndRefIdSince(
      'plant_water',
      p.id,
      p.wiltedAt!,
    );
    final int f = await _ledger.countByRefTypeAndRefIdSince(
      'plant_fertilize',
      p.id,
      p.wiltedAt!,
    );
    final bool ok = hard
        ? (w >= kPlantWiltRecoverHardWater && f >= kPlantWiltRecoverHardFertilize)
        : (w >= 1);
    if (!ok) return p;
    // 注意：[Plant.copyWith] 对 nullable 字段用 `?? this.xxx`，显式 null 不会清空；
    // 恢复需显式清空 [Plant.wiltedAt]，故用构造器重建（2026-09-23）。
    return Plant(
      id: p.id,
      speciesId: p.speciesId,
      potIndex: p.potIndex,
      stage: p.stage,
      stageStartedAt: p.stageStartedAt,
      growthProgress: p.growthProgress,
      growthFactor: p.growthFactor,
      waterUsed: p.waterUsed,
      fertilizerUsed: p.fertilizerUsed,
      status: PlantStatus.growing,
      plantedAt: p.plantedAt,
      lastWaterAt: now,
      wiltedAt: null,
      deadAt: p.deadAt,
      bloomedAt: p.bloomedAt,
      bloomCount: p.bloomCount, // 修复 DEF-1：重建时须保留盛开次数，否则枯萎浇活后退回首花速率
      mood: p.mood,
    );
  }

  /// 花盆扩容：capacity<max → 扣扩容价(refType='plant_expand') → gardenPotCapacity+1。
  Future<void> expandPot(DateTime now) async {
    final AppSettings settings = await _settings.getSettings();
    if (settings.gardenPotCapacity >= kGardenPotCapacityMax) {
      throw const PlantOperationException('花园已达最大容量');
    }
    final int cost = _price(
      kPlantPotExpandCostLow,
      kPlantPotExpandCostHigh,
      settings.ageTier,
    );
    final double balance = await _ledger.balance();
    if (balance < cost) {
      throw PlantOperationException('阳光不足，还差 ${(cost - balance).ceil()} 阳光');
    }
    await _appendSpend(
      amount: cost.toDouble(),
      type: SunlightType.plant,
      refType: 'plant_expand',
      now: now,
    );
    await _settings.saveSettings(settings.copyWith(
      gardenPotCapacity: settings.gardenPotCapacity + 1,
    ));
  }

  // ── 成株后循环玩法 Batch 1：节奏辅助 + 花期双阶段奖励 ──────────────────────

  /// 读取物种（按 id）。找不到返回 null（安全默认：按非精品 / 首花处理）。
  Future<PlantSpecies?> _speciesOf(String speciesId) async {
    final List<PlantSpecies> list = await _plants.species();
    return _firstWhereOrNull(list, (PlantSpecies s) => s.id == speciesId);
  }

  /// 一次养护动作的进度增量：首花（bloomCount==0）用 [firstGain]；复开花用 [rebloomGain]
  /// （精品再 ÷ [kRebloomPremiumCycleMultiplier]）。[sp] 为 null 时按非精品处理（安全默认）。
  double _careProgressGain(
    Plant p,
    double firstGain,
    double rebloomGain,
    PlantSpecies? sp,
  ) =>
      careProgressGain(
        bloomCount: p.bloomCount,
        isPremium: sp?.isPremium ?? false,
        firstGain: firstGain,
        rebloomGain: rebloomGain,
      );

  /// 养护进度增量的**公开单点口径**（F68：UI 文案与领域层共用同一来源，杜绝
  /// 「按钮写死首花 +3%、复开花实际 +1.2%」的文案失真）。
  ///
  /// 首花（bloomCount==0）→ [firstGain]；复开花（bloomCount≥1）→ [rebloomGain]，
  /// 精品物种再 ÷ [kRebloomPremiumCycleMultiplier]。领域层与展示层都从这里取值，
  /// 改常量两侧自动跟随。
  static double careProgressGain({
    required int bloomCount,
    required bool isPremium,
    required double firstGain,
    required double rebloomGain,
  }) {
    if (bloomCount == 0) return firstGain;
    return rebloomGain / (isPremium ? kRebloomPremiumCycleMultiplier : 1.0);
  }

  /// 兜底结算「已到期但已无法收集」的奖励（变更 A + v12 掉落即定奖）。
  ///
  /// 对应植物已被移除、或不再盛开（花谢 / 枯萎 / 死亡）时，自动发放该奖励并置 claimed，
  /// 保证奖励不丢失。**仍可收集**（植物仍盛开）的到期奖励不在此发放——留给花园页头顶图标，
  /// 由小朋友手动点击收集（[collectBloomReward]）。
  ///
  /// [autoSettled]（可选，非 null 时）按结算顺序**追加**每条自动到账奖励的
  /// [BloomRewardOutcome]（`autoSettled: true`）。返回本次是否至少兜底发放一笔。
  Future<bool> _autoSettleUncollectibleRewards(
    List<PlantSpecies> species,
    DateTime now,
    List<Plant> plants,
    List<BloomRewardOutcome>? autoSettled,
  ) async {
    final List<PendingBloomReward> due =
        await _bloomRewards.pendingBloomRewardsDue(now);
    if (due.isEmpty) return false;
    final Map<String, Plant> byId = <String, Plant>{
      for (final Plant p in plants) p.id: p,
    };
    bool granted = false;
    for (final PendingBloomReward reward in due) {
      final Plant? p = byId[reward.plantId];
      final bool collectible = p != null && p.status == PlantStatus.bloomed;
      if (collectible) continue; // 仍可收集 → 留着让小朋友点，不自动发
      final BloomRewardOutcome outcome =
          await _settlePendingReward(reward, species, plants, now);
      await _bloomRewards.markPendingBloomRewardClaimed(reward.id);
      autoSettled?.add(outcome.copyWith(autoSettled: true));
      granted = true;
    }
    return granted;
  }

  /// 读取当前**可收集**的待收集奖励（已到期 + 未领取 + 对应植物仍在盛开）。
  ///
  /// 返回 `plantId → 待收集奖励列表`（供花园页在花盆旁掉落气泡；同一株可能同时有
  /// 「开花瞬间」与「第二段」两条 → 最多 2 个气泡）。列表按 `dueAt` 升序（瞬间的更早）。
  /// 只读、无副作用。到期但植物已不盛开者由 [tickAll] 兜底自动结算，故此处只返回仍可收集者。
  Future<Map<String, List<PendingBloomReward>>> collectibleBloomRewards(
    DateTime now,
  ) async {
    final List<PendingBloomReward> due =
        await _bloomRewards.pendingBloomRewardsDue(now);
    if (due.isEmpty) return <String, List<PendingBloomReward>>{};
    final List<Plant> all = await _plants.plants();
    final Map<String, Plant> byId = <String, Plant>{
      for (final Plant p in all) p.id: p,
    };
    final Map<String, List<PendingBloomReward>> result =
        <String, List<PendingBloomReward>>{};
    for (final PendingBloomReward reward in due) {
      final Plant? p = byId[reward.plantId];
      if (p != null && p.status == PlantStatus.bloomed) {
        (result[reward.plantId] ??= <PendingBloomReward>[]).add(reward);
      }
    }
    for (final List<PendingBloomReward> list in result.values) {
      list.sort((PendingBloomReward a, PendingBloomReward b) =>
          a.dueAt.compareTo(b.dueAt));
    }
    return result;
  }

  /// 把「零值哨兵」待收集奖励（v12 之前登记的旧行，三列 0/0/null）按当前档位回写内容，
  /// 使其头顶图标直接显示明细（不再礼物盒）。仅对「仍可收集」（植物仍盛开）的哨兵行生效；
  /// 不可收集者由 [tickAll] 兜底自动结算负责。一次性历史数据升级，幂等（已定奖行跳过）。
  ///
  /// 根因（玄参 2026-09-28 复验）：iOS 模拟器复用了 v12 之前的旧库，旧 pending 行三列全零，
  /// `rewardIconSpecsFor` 据此渲染礼物盒；本方法在花园页 `_reload` 时调用，把仍可收集的旧行
  /// 当场 roll 出内容写回，刷新后即显示阳光 / 碎片 / 种子明细。
  Future<void> materializeLegacyBloomRewards(DateTime now) async {
    final List<PendingBloomReward> due =
        await _bloomRewards.pendingBloomRewardsDue(now);
    if (due.isEmpty) return;
    final List<Plant> plants = await _plants.plants();
    final List<PlantSpecies> species = await _plants.species();
    final Map<String, Plant> byId = <String, Plant>{
      for (final Plant p in plants) p.id: p,
    };
    for (final PendingBloomReward r in due) {
      if (r.hasPreAssignedReward) continue; // 已定奖 → 跳过（幂等）
      final Plant? plant = byId[r.plantId];
      if (plant == null || plant.status != PlantStatus.bloomed) {
        continue; // 不可收集 → 留给 tickAll 兜底自动结算
      }
      final bool premium = _plantIsPremium(r.plantId, species, plants);
      final BloomRewardOutcome outcome;
      if (r.rewardKind == kBloomRewardPhaseInstant) {
        outcome = await _rollInstantReward(premium, species);
      } else {
        outcome = await _rollSecondPhaseReward(premium, species);
      }
      await _bloomRewards.updatePendingRewardContent(
        id: r.id,
        rewardSunlight: outcome.sunlight,
        rewardFragments: outcome.fragments,
        rewardSpeciesId: outcome.seedSpeciesId,
      );
    }
  }

  /// 手动收集一条待收集奖励（变更 A/B + v12，花园页头顶图标点击）。
  ///
  /// 校验「已到期 + 未领取」→ **照单发放**该条已定好的奖励（历史行零值哨兵则现场 roll
  /// 并回写）→ 置 claimed。返回实际发放结果 [BloomRewardOutcome]（供花园页拼提示文案）。
  /// 已领取 / 未到期 / 不存在则抛 [PlantOperationException]（UI 可捕获提示）。
  Future<BloomRewardOutcome> collectBloomReward(
    String rewardId,
    DateTime now,
  ) async {
    final List<PendingBloomReward> due =
        await _bloomRewards.pendingBloomRewardsDue(now);
    final PendingBloomReward? reward = _firstWhereOrNull(
      due,
      (PendingBloomReward r) => r.id == rewardId,
    );
    if (reward == null) {
      throw const PlantOperationException('奖励还没成熟，或已经被领取啦');
    }
    final List<PlantSpecies> species = await _plants.species();
    final List<Plant> plants = await _plants.plants();
    final BloomRewardOutcome outcome =
        await _settlePendingReward(reward, species, plants, now);
    await _bloomRewards.markPendingBloomRewardClaimed(reward.id);
    _onEconomyChanged?.call();
    return outcome;
  }

  /// 开花瞬间：登记**两条**待收集奖励（玄参 2026-09-26 变更 B + 2026-09-27「掉落即定奖」）。
  ///
  ///  · 开花瞬间奖励：`reward_kind = [kBloomRewardPhaseInstant]`，`due = bloomedAt`（即刻可收集）；
  ///  · 第二段奖励：`reward_kind = 档位`（`normal`/`premium`），`due = bloomedAt + 48h`。
  ///
  /// **掉落即定奖（v12）**：登记两条时**当场 roll** 出奖励内容（阳光 / 碎片 / 种子）并**写入**
  /// 对应 pending 行（`reward_sunlight / reward_fragments / reward_species_id`），结算时**照单发放**、
  /// 不再二次 roll。两条各自生成**唯一 uuid**；仍**不在登记时入账**——点击头顶图标
  /// （[collectBloomReward]）或花谢兜底（[_autoSettleUncollectibleRewards]）时才由
  /// [_settlePendingReward] 真正发放。
  Future<void> _enqueueBloomRewards(
    Plant p,
    PlantSpecies sp,
    List<PlantSpecies> species,
    DateTime now,
  ) async {
    final DateTime bloomedAt = p.bloomedAt ?? now;
    final bool premium = sp.isPremium;
    // 掉落即定奖：登记前先 roll 出两条奖励内容（消耗同一 _random 序列，与旧「结算时 roll」等价）。
    final BloomRewardOutcome instant =
        await _rollInstantReward(premium, species);
    final BloomRewardOutcome second =
        await _rollSecondPhaseReward(premium, species);
    await _bloomRewards.insertPendingBloomReward(PendingBloomReward(
      id: _uuid.v4(),
      plantId: p.id,
      dueAt: bloomedAt,
      rewardKind: kBloomRewardPhaseInstant,
      rewardSunlight: instant.sunlight,
      rewardFragments: instant.fragments,
      rewardSpeciesId: instant.seedSpeciesId,
    ));
    await _bloomRewards.insertPendingBloomReward(PendingBloomReward(
      id: _uuid.v4(),
      plantId: p.id,
      dueAt: bloomedAt.add(const Duration(hours: kBloomRewardDelayHours)),
      rewardKind: premium ? kBloomRewardKindPremium : kBloomRewardKindNormal,
      rewardSunlight: second.sunlight,
      rewardFragments: second.fragments,
      rewardSpeciesId: second.seedSpeciesId,
    ));
  }

  /// 结算一条待收集奖励（头顶图标点击 / 花谢兜底共用），**照单发放**库中已定好的奖励。
  ///
  /// · 命中「零值哨兵」`0/0/null`（历史行 = 未预先定奖）→ 退回**现场 roll** 路径，并把
  ///   roll 结果**回写**该行（`updatePendingRewardContent`，不改 `claimed`），保证老 pending
  ///   奖励金额不减、不多给；哨兵不与真实奖励冲突，因真实奖励保底基础阳光恒 ≥1。
  /// · 非哨兵 → 直接按 `reward_sunlight / reward_fragments / reward_species_id` 发放（不再 roll）。
  /// · **重复种子自动分解**（玄参 2026-09-29）：定奖内容为种子、但该物种**已持免费种植券**
  ///   → 不再写券（券不重复），改为**自动分解**为植物碎片入账（普通
  ///   [kDuplicateSeedDecomposeFragmentsCommon] / 精英 [kDuplicateSeedDecomposeFragmentsPremium]），
  ///   并把结果标记 `decomposedSeedSpeciesId` 供 UI 提示「重复的「X」种子已分解」。分解是
  ///   **结算规则**而非定奖内容，pending 三列保持原样（无需迁移）。
  ///
  /// 阶段分派：`reward_kind == [kBloomRewardPhaseInstant]` → 开花瞬间（[kBloomInstant*]）；
  /// 其它 → 第二段（[kBloomSecondPhase*]）。档位：第二段由 `reward_kind` 给出，开花瞬间由
  /// 该株物种 [PlantSpecies.isPremium] 推导（该株已删 / 物种缺失时安全默认为普通档）。
  /// 返回本次实际发放结果 [BloomRewardOutcome]。
  Future<BloomRewardOutcome> _settlePendingReward(
    PendingBloomReward reward,
    List<PlantSpecies> species,
    List<Plant> plants,
    DateTime now,
  ) async {
    final bool instant = reward.rewardKind == kBloomRewardPhaseInstant;
    final bool premium = instant
        ? _plantIsPremium(reward.plantId, species, plants)
        : reward.rewardKind == kBloomRewardKindPremium;

    final BloomRewardOutcome outcome;
    if (reward.hasPreAssignedReward) {
      // 掉落即定奖：照单发放（不再 roll）。
      outcome = BloomRewardOutcome(
        sunlight: reward.rewardSunlight,
        fragments: reward.rewardFragments,
        seedSpeciesId: reward.rewardSpeciesId,
        isInstantPhase: instant,
      );
    } else {
      // 历史行哨兵：现场 roll + 回写该行（不改 claimed）。
      outcome = instant
          ? await _rollInstantReward(premium, species)
          : await _rollSecondPhaseReward(premium, species);
      await _bloomRewards.updatePendingRewardContent(
        id: reward.id,
        rewardSunlight: outcome.sunlight,
        rewardFragments: outcome.fragments,
        rewardSpeciesId: outcome.seedSpeciesId,
      );
    }

    // 重复种子 → 自动分解为碎片（玄参 2026-09-29）：
    // 用「重写后的有效结果」发放与回传；种子分支因此不再走到 unlockSpecies。
    BloomRewardOutcome effective = outcome;
    if (outcome.seedSpeciesId != null) {
      final Set<String> coupons = await _bloomRewards.unlockedSpeciesIds();
      if (coupons.contains(outcome.seedSpeciesId)) {
        final PlantSpecies? seedSp =
            _firstWhereOrNull(species, (PlantSpecies s) => s.id == outcome.seedSpeciesId);
        final int decomposed = (seedSp?.isPremium ?? false)
            ? kDuplicateSeedDecomposeFragmentsPremium
            : kDuplicateSeedDecomposeFragmentsCommon;
        // ⚠️ 不可用 copyWith（seedSpeciesId 显式置 null 清不掉），直接构造新对象。
        effective = BloomRewardOutcome(
          sunlight: outcome.sunlight,
          fragments: decomposed,
          decomposedSeedSpeciesId: outcome.seedSpeciesId,
          isInstantPhase: outcome.isInstantPhase,
        );
      }
    }

    if (instant) {
      await _grantInstantReward(effective, premium, reward.plantId, now);
    } else {
      await _grantSecondPhaseReward(effective, reward.plantId, now);
    }
    return effective;
  }

  /// 该株是否精品档（找不到植物 / 物种时安全默认非精品）。
  bool _plantIsPremium(
    String plantId,
    List<PlantSpecies> species,
    List<Plant> plants,
  ) {
    final Plant? p = _firstWhereOrNull(plants, (Plant x) => x.id == plantId);
    if (p == null) return false;
    final PlantSpecies? sp =
        _firstWhereOrNull(species, (PlantSpecies s) => s.id == p.speciesId);
    return sp?.isPremium ?? false;
  }

  /// **当场 roll** 出「开花瞬间」奖励内容（不落库、不入账），返回 [BloomRewardOutcome]。
  ///
  /// 概率表（严格照 PRD，按植物档位分两张；精品档经变更 C 修订后两阶段对齐）：
  ///  · 普通：碎片 [kBloomInstantFragmentRate] / 本档种子 [kBloomInstantSeedRate] /
  ///    大额阳光 [kBloomInstantBonusRate] / 无额外（兜底）。
  ///  · 精品：碎片 [kBloomInstantFragmentRatePremium]（60% 掉 2 片）/ 本档种子
  ///    [kBloomInstantSeedRatePremium] / 大额阳光 [kBloomInstantBonusRatePremium] / 无额外（兜底）。
  ///
  /// ⚠️ 保底基础阳光（100% 必给）**包含在** [BloomRewardOutcome.sunlight] 内，故真实奖励恒 ≥1
  ///    （不与零值哨兵冲突）。条件概率累加与 `_random` 消耗顺序与旧「结算时 roll」**完全一致**。
  Future<BloomRewardOutcome> _rollInstantReward(
    bool premium,
    List<PlantSpecies> species,
  ) async {
    final int base =
        premium ? kBloomInstantSunlightPremium : kBloomInstantSunlight;
    int sunlight = base;
    int fragments = 0;
    String? seed;

    final double fragRate =
        premium ? kBloomInstantFragmentRatePremium : kBloomInstantFragmentRate;
    final double seedRate =
        premium ? kBloomInstantSeedRatePremium : kBloomInstantSeedRate;
    final double bonusRate =
        premium ? kBloomInstantBonusRatePremium : kBloomInstantBonusRate;
    final int bonusMin =
        premium ? kBloomBonusSunlightMinPremium : kBloomBonusSunlightMin;
    final int bonusMax =
        premium ? kBloomBonusSunlightMaxPremium : kBloomBonusSunlightMax;

    final double r = _random.nextDouble();
    if (r < fragRate) {
      fragments = premium
          ? (_random.nextDouble() < kBloomInstantFragmentDoubleRatePremium
              ? 2
              : 1)
          : 1;
    } else if (r < fragRate + seedRate) {
      final BloomRewardOutcome seedRoll = await _rollSeed(premium, species);
      if (seedRoll.seedSpeciesId != null) {
        seed = seedRoll.seedSpeciesId;
      } else {
        sunlight += seedRoll.sunlight; // 本档物种全持券 → 兜底大额阳光
      }
    } else if (r < fragRate + seedRate + bonusRate) {
      sunlight += _randRange(bonusMin, bonusMax);
    }
    // 其余：仅保底、无额外奖励。

    return BloomRewardOutcome(
      sunlight: sunlight,
      fragments: fragments,
      seedSpeciesId: seed,
      isInstantPhase: true,
    );
  }

  /// **当场 roll** 出「第二段」奖励内容（不落库、不入账），返回 [BloomRewardOutcome]。
  ///
  /// 概率表（严格照 PRD；精品档经变更 C 修订后与瞬间阶段对齐：碎片 20% / 种子 10% /
  /// 大额阳光 25% / 兜底基础阳光 45%）：
  ///  · 普通：碎片 [kBloomSecondPhaseFragmentRate] / 本档种子 [kBloomSecondPhaseSeedRate] / 大额阳光
  ///    [kBloomSecondPhaseBonusRate] / 基础阳光 [kBloomSecondPhaseBaseSunlightMin~Max]。
  ///  · 精品：碎片 [kBloomSecondPhaseFragmentRatePremium]（50% 掉 2 片）/ 本档种子
  ///    [kBloomSecondPhaseSeedRatePremium] / 大额阳光 [kBloomSecondPhaseBonusRatePremium] / 基础阳光
  ///    [kBloomSecondPhaseBaseSunlightMinPremium~MaxPremium]。
  ///
  /// 第二段奖励**恰好一项**：碎片 / 种子 / 大额阳光 / 基础阳光（四者互斥）。`_random`
  /// 消耗顺序与旧「结算时 roll」**完全一致**。
  Future<BloomRewardOutcome> _rollSecondPhaseReward(
    bool premium,
    List<PlantSpecies> species,
  ) async {
    final double fragRate = premium
        ? kBloomSecondPhaseFragmentRatePremium
        : kBloomSecondPhaseFragmentRate;
    final double seedRate =
        premium ? kBloomSecondPhaseSeedRatePremium : kBloomSecondPhaseSeedRate;
    final double bonusRate =
        premium ? kBloomSecondPhaseBonusRatePremium : kBloomSecondPhaseBonusRate;
    final int bonusMin =
        premium ? kBloomBonusSunlightMinPremium : kBloomBonusSunlightMin;
    final int bonusMax =
        premium ? kBloomBonusSunlightMaxPremium : kBloomBonusSunlightMax;
    final int baseMin = premium
        ? kBloomSecondPhaseBaseSunlightMinPremium
        : kBloomSecondPhaseBaseSunlightMin;
    final int baseMax = premium
        ? kBloomSecondPhaseBaseSunlightMaxPremium
        : kBloomSecondPhaseBaseSunlightMax;

    final double r = _random.nextDouble();
    if (r < fragRate) {
      final int count = premium
          ? (_random.nextDouble() < kBloomSecondPhaseFragmentDoubleRatePremium
              ? 2
              : 1)
          : 1;
      return BloomRewardOutcome(fragments: count);
    } else if (r < fragRate + seedRate) {
      return _rollSeed(premium, species); // 种子，或本档全持券时兜底大额阳光
    } else if (r < fragRate + seedRate + bonusRate) {
      return BloomRewardOutcome(sunlight: _randRange(bonusMin, bonusMax));
    } else {
      return BloomRewardOutcome(sunlight: _randRange(baseMin, baseMax));
    }
  }

  /// 发放**开花瞬间**奖励：保底基础阳光（单独一笔，100% 必给）+ 惊喜加成（碎片 / 种子 / 大额阳光）。
  ///
  /// ⚠️ 账本粒度与旧实现一致：保底基础阳光与「大额阳光」加成各记**一笔**（`refType` 皆为
  ///    [kBloomRewardRefType]）。基础阳光由 [premium] 确定（[BloomRewardOutcome.sunlight] 与其之差
  ///    即惊喜加成）。种子 / 碎片不走账本。
  Future<void> _grantInstantReward(
    BloomRewardOutcome outcome,
    bool premium,
    String plantId,
    DateTime now,
  ) async {
    // ① 保底基础阳光（100% 必给）——单独一笔。
    final int base =
        premium ? kBloomInstantSunlightPremium : kBloomInstantSunlight;
    await _appendEarn(
      amount: base.toDouble(),
      refType: kBloomRewardRefType,
      now: now,
      refId: plantId,
    );

    // ② 惊喜加成（碎片 / 种子 / 大额阳光；三者互斥）。
    if (outcome.fragments > 0) {
      await _addPremiumFragments(outcome.fragments);
    } else if (outcome.seedSpeciesId != null) {
      await _bloomRewards.unlockSpecies(outcome.seedSpeciesId!);
    } else if (outcome.sunlight > base) {
      // 大额阳光（含「本档全持券 → 兜底阳光」）——单独一笔。
      await _appendEarn(
        amount: (outcome.sunlight - base).toDouble(),
        refType: kBloomRewardRefType,
        now: now,
        refId: plantId,
      );
    }
  }

  /// 发放**第二段**（花开后 48h 掉落）奖励（由 [collectBloomReward] /
  /// [_autoSettleUncollectibleRewards] → [_settlePendingReward] 调用）。
  ///
  /// 第二段奖励**恰好一项**：碎片 / 种子 / 阳光（含大额与基础），据 [outcome] 发放一笔。
  Future<void> _grantSecondPhaseReward(
    BloomRewardOutcome outcome,
    String plantId,
    DateTime now,
  ) async {
    if (outcome.fragments > 0) {
      await _addPremiumFragments(outcome.fragments);
    } else if (outcome.seedSpeciesId != null) {
      await _bloomRewards.unlockSpecies(outcome.seedSpeciesId!);
    } else if (outcome.sunlight > 0) {
      await _appendEarn(
        amount: outcome.sunlight.toDouble(),
        refType: kBloomSecondPhaseRefType,
        now: now,
        refId: plantId,
      );
    }
  }

  /// **当场 roll** 一颗物种种子：从**本档**物种中随机挑一个，返回其 id
  /// （[BloomRewardOutcome.seedSpeciesId]）。
  ///
  /// 语义（玄参 2026-09-27 定「种子 = 免费种植券」；**2026-09-29 修订：允许重复掉落**）：
  ///  · 旧口径「只从未持券物种中挑、全持券兜底大额阳光」**已废止** —— 重复种子现在**允许掉落**，
  ///    结算（[_settlePendingReward]）时若该物种已持券 → **自动分解**为植物碎片
  ///    （普通 [kDuplicateSeedDecomposeFragmentsCommon] / 精英 [kDuplicateSeedDecomposeFragmentsPremium]）；
  ///  · 候选为空（物种表为空，防御）→ 仍兜底返回**大额阳光**（[BloomRewardOutcome.sunlight] > 0），
  ///    避免空掉落；
  ///  · 档位判据与 [PlantSpecies.isPremium] 一致（精英档 = rare + legendary）：
  ///    [premium] = true → 全部精英物种中随机；false → 全部普通物种（common）中随机。
  ///
  /// ⚠️ `_random` 消耗顺序与旧实现一致：先 `nextInt(candidates.length)`，
  ///    候选为空时 `nextInt`（兜底区间随机）。
  Future<BloomRewardOutcome> _rollSeed(
    bool premium,
    List<PlantSpecies> species,
  ) async {
    final List<PlantSpecies> candidates = species
        .where((PlantSpecies s) =>
            premium ? s.isPremium : s.rarity == Rarity.common)
        .toList();
    if (candidates.isEmpty) {
      // 防御兜底（物种表为空才可能走到）：大额阳光（精品档用精品区间）。
      final int amount = _randRange(
        premium ? kBloomBonusSunlightMinPremium : kBloomBonusSunlightMin,
        premium ? kBloomBonusSunlightMaxPremium : kBloomBonusSunlightMax,
      );
      return BloomRewardOutcome(sunlight: amount);
    }
    final PlantSpecies picked = candidates[_random.nextInt(candidates.length)];
    return BloomRewardOutcome(seedSpeciesId: picked.id);
  }

  /// 区间随机整数（含端点）；[max] <= [min] 时返回 [min]。
  ///
  /// v12「掉落即定奖」后，所有奖励内容已在**登记时**通过 [_rollInstantReward] /
  /// [_rollSecondPhaseReward] / [_rollSeed] roll 好（内部即用本 helper），结算时照单发放。
  int _randRange(int min, int max) {
    if (max <= min) return min;
    return min + _random.nextInt(max - min + 1);
  }

  /// 累加精品碎片余额（掉落奖励累积；**不足**方向由 [_spendPremiumFragments] 处理）。
  Future<void> _addPremiumFragments(int count) async {
    if (count <= 0) return;
    final int balance = await _bloomRewards.premiumFragmentBalance() + count;
    await _bloomRewards.setPremiumFragmentBalance(balance);
  }

  // ── 精品碎片 · 余额（种植计价 / 碎片入口展示）────────────────────────────

  /// 精品碎片当前余额（花园页碎片入口展示用）。
  Future<int> premiumFragmentBalance() => _bloomRewards.premiumFragmentBalance();

  /// 当日是否为有效专注日（WFD 口径与 M1/M2 一致）。
  Future<bool> _hasValidFocusDay(DateTime day) async {
    final List<FocusSession> sessions = await _focus.sessionsOfDay(dayKey(day));
    return sessions.any(_isWfd);
  }

  /// 预计算 [from, to] 区间内所有「有效专注日」的日键集合。
  Future<Set<String>> _validFocusDayKeys(DateTime from, DateTime to) async {
    final Set<String> result = <String>{};
    DateTime d = DateTime(from.year, from.month, from.day);
    final DateTime end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (await _hasValidFocusDay(d)) result.add(dayKey(d));
      d = d.add(const Duration(days: 1));
    }
    return result;
  }

  /// WFD 判定：actualFocusMin ≥ kValidFocusMinutes 且 完成率 ≥ kCompletionRateThreshold。
  static bool _isWfd(FocusSession s) {
    if (s.actualFocusMin < kValidFocusMinutes) return false;
    final double completion =
        s.plannedMin == 0 ? 1.0 : s.actualFocusMin / s.plannedMin;
    return completion >= kCompletionRateThreshold;
  }

  /// 轻量 firstWhereOrNull（避免引入 collection 依赖）。
  static T? _firstWhereOrNull<T>(
    List<T> list,
    bool Function(T) test,
  ) {
    for (final T item in list) {
      if (test(item)) return item;
    }
    return null;
  }
}
