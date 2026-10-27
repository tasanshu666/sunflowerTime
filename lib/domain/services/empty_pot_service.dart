/// 空花盆干扰物服务（F155-B，玄参 2026-10-27 拍板）。
///
/// ## 为什么**新建**一个服务，而不是塞进 [PlantGrowthService]
/// 拍板口径要求「空盆独立 roll + 独立清除 + 种下即清」，而 [PlantGrowthService] 被
/// 数十份域单测 / 组件测试逐字节覆盖（成长、开花、枯萎、铲除…），在类里加分支风险
/// 极高。故逻辑落在本服务：**同一套语义、独立的表与入口**，互不污染。
///
/// ## 语义（与 `PlantGrowthService` 的干扰物实现逐条对齐，别另立口径）
///  · **每日一次 roll、同日幂等**：以 `rollDay` 为幂等锚（当日已 roll 不重 roll）——
///    否则「每天发生一次」会退化成「每次 tick 都 roll」，孩子开着 App 的几小时里
///    杂草会凭空冒出来；
///  · **当天有效、次日自动失效**：写「出现当天零点」，次日零点 ≠ 今日零点 → 过期；
///  · 杂草 [kEmptyPotWeedRate] / 害虫 [kEmptyPotPestRate] 独立判定、**可同时出现**；
///  · 清除奖励**与植物完全一致**：[weedRewardOf] / [pestRewardOf]（含称号加成），
///    账本 `refType` **复用** `kGardenWeedRefType` / `kGardenPestRefType`，`refId` 取
///    `'pot:<potIndex>'`（与植物侧 `refId = plantId` 同构，孩子端阳光来源照常可读）；
///  · **不阻断种植**：点空盆照常弹种植选择；种下后该盆记录立即删除（不返还、不再显示）。
///
/// ## 首日免疫（🔴 与植物侧 `plant()` 同一口径，C100-1 先例）
/// 某个盆**第一次**被观测到时（库中无记录）只写「今日已 roll」的幂等位、**不掷骰**，
/// 次日才开始参与 roll —— 与「新种下的植株当天免疫」一字同源。理由：
///  · 空盆刚出现（首次安装 / 刚铲除 / 刚扩容）就当场长草，观感与「刚种下就长草」同样糟；
///  · 让「今天新出现的盆」与「昨天就在的盆」行为可区分，也便于回归测试构造确定状态。
/// 如需改为「首日即参与 roll」，把构造参数 [firstSightImmune] 传 `false` 即可。
///
/// ## 依赖方向（零 Flutter）
/// 只依赖域接口 [PotDisturbanceRepository] / [SunlightRepository] 与常量；随机源可
/// 注入（测试喂固定 `Random`），对齐 [PlantGrowthService] 的做法。
///
/// 🔴 **本服务刻意不依赖 [FocusRepository]、也不自己算「当前称号属性」** ——
/// 那会与 `perkOfLevel` 的单点判定形成「孪生」，绕开 `FeatureKey.titlePerks` 门控
/// （守卫测试 `test/qa/plant_perk_bypass_guard_test.dart` 明文禁此项）。
/// 称号属性一律**由调用方传入**（页面传 `currentPlantPerkProvider` 的门控值）；
/// 未传时按 [PlantPerk.none] 结算 —— 保守不发加成，绝不越权多发。
library empty_pot_service;

import 'dart:math';

import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart'
    show PlantOperationError, PlantOperationException;
import 'package:sunflower_time/domain/services/plant_perk.dart';

/// 空花盆（没种植物）的杂草 / 害虫玩法（口径见本文件头注释）。
class EmptyPotService {
  /// 空盆干扰物仓储（按当前孩子过滤在实现内部完成）。
  final PotDisturbanceRepository _disturbances;

  /// 阳光账本（清理奖励入账，§3.2 账本铁律）。
  final SunlightRepository _ledger;

  final Uuid _uuid;

  /// 杂草随机源。
  final Random _weedRandom;

  /// 害虫随机源（默认与 [_weedRandom] 同源，可单独注入以便测试定格单侧命中）。
  final Random _pestRandom;

  /// 「盆第一次被观测到当天不掷骰」（说明见文件头「首日免疫」段）。
  final bool _firstSightImmune;

  /// 经济变更回调（可选）：清理入账后调用；域层保持零 Flutter 依赖。
  final void Function()? _onEconomyChanged;

  EmptyPotService({
    required PotDisturbanceRepository disturbances,
    required SunlightRepository ledger,
    Uuid? uuid,
    Random? random,
    Random? weedRandom,
    Random? pestRandom,
    bool firstSightImmune = true,
    void Function()? onEconomyChanged,
  })  : _disturbances = disturbances,
        _ledger = ledger,
        _uuid = uuid ?? const Uuid(),
        _weedRandom = weedRandom ?? random ?? Random(),
        _pestRandom = pestRandom ?? weedRandom ?? random ?? Random(),
        _firstSightImmune = firstSightImmune,
        _onEconomyChanged = onEconomyChanged;

  /// 账本 `refId` 口径：`'pot:<potIndex>'`（与植物侧 `refId = plantId` 同构）。
  static String refIdOf(int potIndex) => 'pot:$potIndex';

  /// 每日 roll（**幂等**）：对每个空盆判定杂草 / 害虫，返回**当前**状态列表。
  ///
  /// [emptyPotIndexes] = 本轮**真正的空盆**序号（调用方按「没有非死亡植物占用」算）。
  /// 服务据此做两件事：
  ///  ① **清理脏行**：库里存在、但本轮不在 [emptyPotIndexes] 的行（已种下 / 已消失的盆）
  ///     一律删除 —— 与「种下即清」同口径的**防御性兜底**（正常路径由
  ///     [clearForPlanting] 显式删除）；
  ///  ② 对每个空盆按 [rollDay] 判幂等后 roll，命中写「当天零点」，未命中写 null。
  ///
  /// 返回顺序 = [emptyPotIndexes] 顺序（调用方可直接建 `potIndex → 状态` 映射）。
  Future<List<PotDisturbance>> tick(
    List<int> emptyPotIndexes,
    DateTime now,
  ) async {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final Set<int> empty = emptyPotIndexes.toSet();
    final List<PotDisturbance> existing = await _disturbances.disturbances();
    final Map<int, PotDisturbance> byPot = <int, PotDisturbance>{};

    for (final PotDisturbance row in existing) {
      if (empty.contains(row.potIndex)) {
        byPot[row.potIndex] = row;
      } else {
        // ① 该盆不再是空盆（已种下 / 已扩容取消）→ 记录立即失效。
        await _disturbances.deletePot(row.potIndex);
      }
    }

    final List<PotDisturbance> result = <PotDisturbance>[];
    for (final int potIndex in emptyPotIndexes) {
      final PotDisturbance? prev = byPot[potIndex];
      PotDisturbance next = prev ?? PotDisturbance(potIndex: potIndex);
      if (prev == null && _firstSightImmune) {
        // 首日免疫：只写幂等锚，不掷骰（说明见文件头）。
        next = next.copyWith(rollDay: today);
      }
      if (next.rollDay != today) {
        next = next.copyWith(
          weedAt:
              _rollHit(kEmptyPotWeedRate, _weedRandom) ? today : PotDisturbance.kClear,
          pestAt:
              _rollHit(kEmptyPotPestRate, _pestRandom) ? today : PotDisturbance.kClear,
          rollDay: today,
        );
      }
      if (prev == null || next != prev) {
        await _disturbances.save(next);
      }
      result.add(next);
    }
    return result;
  }

  /// 拔掉空盆杂草（奖励 = [weedRewardOf]，账本 `refType = kGardenWeedRefType`）。
  ///
  /// 分因失败抛 [PlantOperationException]（与植物侧 `_clearPestOrWeed` 同风格）：
  ///  · 该盆无记录 → [PlantOperationError.plantNotFound]（空盆记录已被清 = 状态失配）；
  ///  · 该盆当日无杂草 → [PlantOperationError.noWeed]。
  ///
  /// ⚠️ 清除后**保留** `rollDay = 今天`：否则同日再 tick 会重 roll 又长出杂草，
  /// 「点一下就没了」退化成「点完没几分钟又冒出来」（与植物侧逐字同口径）。
  Future<void> clearWeed(
    int potIndex,
    DateTime now, {
    PlantPerk? perk,
  }) =>
      _clear(potIndex: potIndex, now: now, isWeed: true, perk: perk);

  /// 除掉空盆害虫（奖励 = [pestRewardOf]，账本 `refType = kGardenPestRefType`）。
  Future<void> clearPest(
    int potIndex,
    DateTime now, {
    PlantPerk? perk,
  }) =>
      _clear(potIndex: potIndex, now: now, isWeed: false, perk: perk);

  /// 种下植物后清掉该盆的空盆干扰物（**不返还任何奖励**、不再显示）。
  ///
  /// 幂等：该盆本来没有记录（首日免疫 / 刚清过）时静默返回。
  Future<void> clearForPlanting(int potIndex) =>
      _disturbances.deletePot(potIndex);

  /// [clearWeed] / [clearPest] 的公共实现（校验 → 入账 → 清字段）。
  Future<void> _clear({
    required int potIndex,
    required DateTime now,
    required bool isWeed,
    PlantPerk? perk,
  }) async {
    final PotDisturbance? d = await _disturbances.disturbanceOf(potIndex);
    if (d == null) {
      // 记录不存在 = 该盆已不是空盆（种下即清）/ 从未 roll 过：与植物侧
      // 「植物不存在」同一个语义码（UI 文案同为「没找到这盆」）。
      throw const PlantOperationException(PlantOperationError.plantNotFound);
    }
    final bool hit = isWeed ? d.hasWeed : d.hasPest;
    if (!hit) {
      throw PlantOperationException(
        isWeed ? PlantOperationError.noWeed : PlantOperationError.noPest,
      );
    }
    // 称号属性只认调用方传入的门控值；未传 → [PlantPerk.none]（保守不发加成）。
    // 🔴 刻意**不**在此调 `perkOfLevel(...)` 自行派生：那会绕开
    // `FeatureKey.titlePerks` 门控形成孪生判定（见文件头「依赖方向」段）。
    final PlantPerk effectivePerk = perk ?? PlantPerk.none;
    await _appendEarn(
      amount: isWeed ? weedRewardOf(effectivePerk) : pestRewardOf(effectivePerk),
      refType: isWeed ? kGardenWeedRefType : kGardenPestRefType,
      now: now,
      refId: refIdOf(potIndex),
    );
    await _disturbances.save(
      isWeed
          ? d.copyWith(weedAt: PotDisturbance.kClear)
          : d.copyWith(pestAt: PotDisturbance.kClear),
    );
    _onEconomyChanged?.call();
  }

  /// 账本入账（net>0）。与 [PlantGrowthService] 的 `_appendEarn` 同构：
  /// 先读余额、再写 `balanceAfter`（§3.2 账本铁律：append-only、可对账）。
  Future<void> _appendEarn({
    required double amount,
    required String refType,
    required DateTime now,
    String? refId,
  }) async {
    final double balanceBefore = await _ledger.balance();
    await _ledger.append(SunlightEntry(
      id: _uuid.v4(),
      ts: now,
      type: SunlightType.earn,
      gross: amount,
      net: amount,
      balanceAfter: balanceBefore + amount,
      refType: refType,
      refId: refId,
      dayKey: dayKey(now),
    ));
  }

  /// 按概率掷一次（随机源由构造器注入，测试可喂固定 `Random` 保证确定性）。
  bool _rollHit(double rate, Random source) => source.nextDouble() < rate;
}
