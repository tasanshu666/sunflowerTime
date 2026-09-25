/// 植物养成领域服务（M3，§3.2 / §3.3 / §3.4）。
///
/// 纯 Dart、零 Flutter 依赖，可被 `flutter test` 直接单测。依赖接口而非实现，
/// 与 M2 同账本（[SunlightRepository.append]）保证植物消耗 / 退款可追溯对账。
///
/// 关键纪律：
///  · 经济衔接：所有扣减经 `append(net<0, refType)`，退款经 `append(net>0, refType='plant_death_refund')`；
///    扣前用 `balance()` 校验（§3.2 账本铁律）。refType 区分 plant_plant/plant_water/
///    plant_fertilize/plant_expand/plant_death_refund。
///  · 软绑定底线（§4.6 H2）：成长系数 ×1.3（当日有效专注）/ ×1.0（无专注也长），**绝不因专注差而死亡**；
///    死亡只由「3+7 天未养护」触发（3 天未浇水→wilting，wilting 再 7 天→dead），且仅返还 30% 种植成本到账本。
///  · 枯萎恢复（2026-09-23 替代原付费救回）：wilting 仅靠养护动作恢复——未满 3 天浇水 1 次即可；
///    已满 3 天需「浇水 3 次 + 施肥 1 次」（以账本为事实源计数，见 [_maybeRecover]）。
library plant_growth_service;

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
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

/// 植物养成领域服务。
class PlantGrowthService {
  final PlantRepository _plants;
  final FocusRepository _focus;
  final SunlightRepository _ledger;
  final SettingsRepository _settings;
  final Uuid _uuid;

  PlantGrowthService({
    required PlantRepository plants,
    required FocusRepository focus,
    required SunlightRepository ledger,
    required SettingsRepository settings,
    Uuid? uuid,
  })  : _plants = plants,
        _focus = focus,
        _ledger = ledger,
        _settings = settings,
        _uuid = uuid ?? const Uuid();

  /// 两档价：低年段取 low，其余（中 / 高）取 high（U3 决策：植物保留 §4.6 两档）。
  int _price(int low, int high, AgeTier tier) => tier == AgeTier.low ? low : high;

  /// 种植价（随物种稀有度两档）。
  int _plantCost(PlantSpecies sp, AgeTier tier) =>
      _price(sp.baseCostLow, sp.baseCostHigh, tier);

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

  /// 账本入账（net>0，如死亡退款）。
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

  /// 种植：校验花盆容量 → 校验余额 ≥ 种植价 → 扣账本(refType='plant_plant') → 落 Plant。
  Future<Plant> plant(String speciesId, int potIndex, DateTime now) async {
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

    final int cost = _plantCost(sp, settings.ageTier);
    final double balance = await _ledger.balance();
    if (balance < cost) {
      throw PlantOperationException(
          '阳光不足，还差 ${(cost - balance).ceil()} 阳光');
    }

    await _appendSpend(
      amount: cost.toDouble(),
      type: SunlightType.plant,
      refType: 'plant_plant',
      now: now,
      refId: speciesId,
    );

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
    return plant;
  }

  /// 计时驱动成长：对每株推进 growthProgress；满 1.0 进阶段；adult 满 → bloomed；
  /// 同时处理枯萎 / 死亡（含死亡退款）。返回更新后的全部植物。
  Future<List<Plant>> tickAll(DateTime now) async {
    final List<PlantSpecies> species = await _plants.species();
    final Map<String, PlantSpecies> speciesMap =
        <String, PlantSpecies>{for (final PlantSpecies s in species) s.id: s};
    final List<Plant> all = await _plants.plants();
    if (all.isEmpty) return all;

    // 预计算日期范围（最早种植时间 → now）内的有效专注日，避免每株每日起异步查库。
    DateTime earliest = now;
    for (final Plant p in all) {
      if (p.stageStartedAt.isBefore(earliest)) earliest = p.stageStartedAt;
    }
    final Set<String> wfdDays = await _validFocusDayKeys(earliest, now);
    final bool todayWfd = await _hasValidFocusDay(now);
    final AppSettings settings = await _settings.getSettings();

    final List<Plant> updated = <Plant>[];
    for (final Plant p in all) {
      final PlantSpecies? sp = speciesMap[p.speciesId];
      if (sp == null) {
        updated.add(p); // 物种缺失（数据安全）跳过成长
        continue;
      }
      Plant np = _advanceGrowth(p, sp, now, wfdDays);
      np = _applyBloomCycle(np, now);
      np = _applyWiltAndDeath(np, now);
      np = _deriveMood(np, now, todayWfd);

      final bool changed = np != p;
      final bool died =
          np.status == PlantStatus.dead && p.status != PlantStatus.dead;
      if (died) {
        // 死亡返还 30% 种植成本（仅与养护挂钩，绝不因专注表现杀死，H2）。
        final int refund =
            (_plantCost(sp, settings.ageTier) * kPlantDeathRefundRate).round();
        if (refund > 0) {
          await _appendEarn(
            amount: refund.toDouble(),
            refType: 'plant_death_refund',
            now: now,
            refId: np.id,
          );
        }
      }
      if (changed) await _plants.savePlant(np);
      updated.add(np);
    }
    return updated;
  }

  /// 逐日推进成长进度（sync）。系数：当日有效专注 ×1.3，否则 ×1.0。
  Plant _advanceGrowth(
    Plant p,
    PlantSpecies sp,
    DateTime now,
    Set<String> wfdDays,
  ) {
    if (p.status == PlantStatus.dead) return p;

    double progress = p.growthProgress;
    PlantStage stage = p.stage;
    bool waterUsed = p.waterUsed;
    bool fertilizerUsed = p.fertilizerUsed;
    double lastFactor = p.growthFactor;
    DateTime stageStartedAt = p.stageStartedAt;
    DateTime? bloomedAt = p.bloomedAt;

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
      progress += segHours * factor / sp.growthHoursPerStage * kPlantAutoGrowthScale;
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
        bloomedAt == p.bloomedAt) {
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
    );
  }

  /// 枯萎 / 死亡状态机（sync，退款由 tickAll 异步处理）。
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
  /// 自然逻辑：盛开不能一直保持。花期 [kBloomDurationDays] 天后花朵凋谢 →
  /// 退回成株(growing)，进度回落到 [kBloomWiltProgressFloor]，由时间（自动成长）
  /// 或养护（浇水/施肥）把进度重新养满后再度盛开。体型保持成株，不缩回幼苗。
  ///
  /// `bloomedAt == null` 的情况（老库升级来的已开花植物）：以本次 tick 为计时起点补上，
  /// 不立即花谢、也不丢失已有盛开状态；后续 tick 才正常倒计时。
  Plant _applyBloomCycle(Plant p, DateTime now) {
    if (p.status != PlantStatus.bloomed) return p;

    final DateTime? bloomedAt = p.bloomedAt;
    if (bloomedAt == null) {
      // 老库升级来的已开花植物：补上计时起点，本 tick 不花谢。
      return p.copyWith(bloomedAt: now);
    }
    if (now.difference(bloomedAt) < Duration(days: kBloomDurationDays)) {
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
    final double progress = p.growthProgress + kPlantWaterProgressGain;
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
    final double progress = p.growthProgress + kPlantFertilizeProgressGain;
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
