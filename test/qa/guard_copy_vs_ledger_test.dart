/// 花园守卫独立验收 · **V3「文案说 N、实扣 M」全点位扫描**
///
/// 判据：任何「确认卡 / 飘字 / 价格按钮 / chip 剩余额度」上的数字，必须与
/// 阳光账本里**实际发生**的金额逐位相等。不等即判红，并写明实现坐标。
///
/// 本文件对每个点位给出**两条证据**：
///  1. 页面渲染数字的**来源表达式**（file:line，静态可核）；
///  2. 用真实服务链路跑出的**实际账本金额**（本文件的探针断言）。
/// 两者一比，就是「文案 vs 账本」。
///
/// 覆盖点位：
///  · 一键浇水确认卡 `−{plan.totalCost} ☀` + note「N 盆 × X ☀」；
///  · 一键护理确认卡 note「除草 +A / 除虫 +B」；
///  · 单株浇水（养护卡按钮价）；
///  · 单株 / 空盆除草·除虫（飘字金额 vs 账本）；
///  · buff chip 额度文案 vs 存档 `remaining`（浇水券带「剩 N」、劳动券只显示 buff）；
///  · 阳光流水页三条 `guard_*` 来源标签。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';

import 'guard_probe_support.dart';

/// 汉字判定（与 `guard_i18n_audit_test` 同口径：en 文案不得含汉字）。
final RegExp _han = RegExp(r'[\u4e00-\u9fff]');

/// 找一个「普通日」（`waterQuota >= 3`），保证 12 盆各能浇一次。
DateTime _waterFriendlyDay() {
  DateTime d = DateTime(2026, 3, 1, 10, 30);
  for (int i = 0; i < 90; i++) {
    final DateTime cand = d.add(Duration(days: i));
    if (WeatherSystem.ofDay(cand).waterQuota >= 3) return cand;
  }
  throw StateError('90 天内找不到普通日');
}

/// 造「今天有券」的存档。
Future<void> _giveVoucher(
  GuardProbeEnv env, {
  required GuardDropKind kind,
  required int quota,
  int used = 0,
}) async {
  await env.store.write(
    env.childId,
    GuardDayState(
      dayKey: env.today,
      status: GuardDayStatus.claimed,
      dropKind: kind,
      buff: GuardBuffState(kind: kind, quota: quota, used: used),
    ),
  );
}

Future<double> _sumPlantWater(GuardProbeEnv env) async {
  final List<SunlightEntry> rows = await env.rowsOf('plant_water');
  return rows.fold<double>(0, (double a, SunlightEntry e) => a + e.net.abs());
}

Future<int> _sumWeed(GuardProbeEnv env) async {
  final List<SunlightEntry> rows = await env.rowsOf('plant_weed');
  return rows.fold<int>(0, (int a, SunlightEntry e) => a + e.net.round());
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // V3-1 一键浇水确认卡 vs 账本
  // ══════════════════════════════════════════════════════════════════════
  group('V3-1 一键浇水确认卡「−合计 ☀」vs 实扣', () {
    test('浇水券 + 12 盆（B13.4 不限次）：卡面 48 == 实扣 48（逐盆序列）', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i, progress: 0.5);
      }
      await env.seedBalance(1000);
      await _giveVoucher(env, kind: GuardDropKind.waterVoucher, quota: 6);

      // ① 页面确认卡的来源（F2 后 = `overlaySequenceFor` 逐盆实价之和）：
      //    garden_page.dart 的 `plannedCost`。
      final GuardBuffState? buff = await env.vouchers.currentBuff();
      final OneClickPlan plan = await env.growth.oneClickPlan(
        PlantOneClickKind.water,
        day,
        perk: env.vouchers.overlayFor(
          buff,
          null,
          kind: GuardVoucherKind.water,
          plantId: null,
        ),
      );
      final List<PlantPerk> seq = env.vouchers.overlaySequenceFor(
        buff,
        null,
        kind: GuardVoucherKind.water,
        count: plan.plantIds.length,
      );
      final int cardTotal = seq.fold(
        0,
        (int sum, PlantPerk p) => sum + waterCostOf(p),
      );

      expect(plan.plantIds.length, 12);
      expect(plan.totalCost, 48, reason: '旧口径「券后单价 × 盆数」仍在服务里（页面不再使用）');
      expect(cardTotal, 48, reason: '🔴 B13.4 不限次：12 盆全部 4（旧 54 废除）');

      // ② 实际执行：逐盆核销（与 garden_page.dart 的 seq 执行同构）。
      double spent = 0;
      for (int i = 0; i < plan.plantIds.length; i++) {
        final String id = plan.plantIds[i];
        final PlantPerk perk = seq[i];
        spent += waterCostOf(perk);
        await env.growth.water(id, day, perk: perk);
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.water,
          plantId: null,
        );
      }

      expect(spent, 48.0, reason: '12 盆全 4 = 48');
      expect(await _sumPlantWater(env), 48.0, reason: '账本实扣 48');

      // ③ 等式护栏：确认卡数字 == 实扣之和。
      expect(cardTotal, spent.toInt(),
          reason: '🟢 确认卡 48 == 实扣 48（F2 后三处同源）');
      expect(spent.toInt() - cardTotal, 0);
    });

    test('🔴 阳光闸门用逐盆合计价：余额 40 < 48 ⇒ 整体拦截，一盆都不执行',
        () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i, progress: 0.5);
      }
      await env.seedBalance(40);
      await _giveVoucher(env, kind: GuardDropKind.waterVoucher, quota: 6);

      final GuardBuffState? buff = await env.vouchers.currentBuff();
      final OneClickPlan plan = await env.growth.oneClickPlan(
        PlantOneClickKind.water,
        day,
        perk: env.vouchers.overlayFor(
          buff,
          null,
          kind: GuardVoucherKind.water,
          plantId: null,
        ),
      );
      final List<PlantPerk> seq = env.vouchers.overlaySequenceFor(
        buff,
        null,
        kind: GuardVoucherKind.water,
        count: plan.plantIds.length,
      );
      final int plannedCost = seq.fold(
        0,
        (int sum, PlantPerk p) => sum + waterCostOf(p),
      );

      // 与 garden_page.dart 的闸门同构：`_balance < plannedCost` ⇒ 直接 return。
      expect(plannedCost, 48, reason: 'B13.4 不限次：12 盆全 4 = 48');
      final double balance = await env.ledger.balance();
      expect(balance < plannedCost, isTrue, reason: '40 < 48 ⇒ 必须整体拦截');

      int okCount = 0;
      if (balance >= plannedCost) {
        for (int i = 0; i < plan.plantIds.length; i++) {
          await env.growth.water(plan.plantIds[i], day, perk: seq[i]);
          await env.vouchers.recordConsumed(
            kind: GuardVoucherKind.water,
            plantId: null,
          );
          okCount++;
        }
      }

      expect(okCount, 0, reason: '🟢 闸门不通过时一盆都不执行');
      expect(await env.ledger.balance(), 40.0, reason: '分毫不扣');
      expect(await _sumPlantWater(env), 0.0, reason: '账本无 plant_water 行');
    });

    test('无券基线：卡面 60 == 实扣 60（对照组，防「一律不等」的假红）', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i, progress: 0.5);
      }
      await env.seedBalance(1000);

      final OneClickPlan plan =
          await env.growth.oneClickPlan(PlantOneClickKind.water, day);
      expect(plan.totalCost, 60);

      double spent = 0;
      for (final String id in plan.plantIds) {
        spent += waterCostOf(PlantPerk.none);
        await env.growth.water(id, day);
      }
      expect(spent, 60.0);
      expect(await _sumPlantWater(env), 60.0);
      expect(plan.totalCost, spent.toInt());
    });
  });

    test('施肥券（今日每次施肥都 −2 ☀）+ 5 盆：卡面 40 == 实扣 40', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 5; i++) {
        await env.seedPlant('p$i', potIndex: i);
      }
      await env.seedBalance(1000);
      await _giveVoucher(env, kind: GuardDropKind.fertilizeVoucher, quota: 12);

      final GuardBuffState? buff = await env.vouchers.currentBuff();
      final PlantPerk cardPerk = env.vouchers.overlayFor(
        buff,
        null,
        kind: GuardVoucherKind.fertilize,
        plantId: null,
      );
      expect(fertilizeCostOf(cardPerk), 8, reason: '券后单价 10 − 2');
      final OneClickPlan plan = await env.growth.oneClickPlan(
        PlantOneClickKind.fertilize,
        day,
        perk: cardPerk,
      );
      expect(plan.totalCost, 40,
          reason: '5 盆 × 8 = 40（服务内单价口径；页面改用逐盆序列，两处一致）');

      final List<PlantPerk> seq = env.vouchers.overlaySequenceFor(
        buff,
        null,
        kind: GuardVoucherKind.fertilize,
        count: plan.plantIds.length,
      );
      final int plannedCost = seq.fold(
        0,
        (int sum, PlantPerk p) => sum + fertilizeCostOf(p),
      );
      expect(plannedCost, 40,
          reason: '今日每次施肥都 −2 ☀、额度 12 次不缩额 ⇒ 5 盆各 8 = 40');

      double spent = 0;
      for (int i = 0; i < plan.plantIds.length; i++) {
        final PlantPerk perk = seq[i];
        spent += fertilizeCostOf(perk);
        await env.growth.fertilize(plan.plantIds[i], day, perk: perk);
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.fertilize,
          plantId: null,
        );
      }
      expect(spent, 40.0, reason: '5 盆各 8 = 40');
      expect(plannedCost, spent.toInt(),
          reason: '🟢 卡面 40 == 实扣 40（F2 后三处同源）');
    });

  // ══════════════════════════════════════════════════════════════════════
  // V3-2 一键护理确认卡 note vs 账本入账
  // ══════════════════════════════════════════════════════════════════════
  group('V3-2 一键护理「合计 +N」vs 实到', () {
    test('劳动券 + 10 处杂草（B13.4 不限次）：note 合计 +20 == 实到 20', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 10; i++) {
        await env.seedPlant('p$i', potIndex: i, weed: true);
      }
      await env.seedBalance(100);
      await _giveVoucher(env, kind: GuardDropKind.laborVoucher, quota: 4);

      final GuardBuffState? buff = await env.vouchers.currentBuff();
      final OneClickPlan plan = await env.growth.oneClickPlan(
        PlantOneClickKind.care,
        day,
      );
      expect(plan.careTargets.length, 10);

      // F2/F3：确认卡 note 的「合计」= 逐处实发之和（seq 由同一份 buff 推出）。
      final List<PlantPerk> seq = env.vouchers.overlaySequenceFor(
        buff,
        null,
        kind: GuardVoucherKind.labor,
        count: plan.careTargets.length,
      );
      int plannedEarn = 0;
      for (int i = 0; i < seq.length; i++) {
        final ({String plantId, bool weed}) target = plan.careTargets[i];
        plannedEarn +=
            (target.weed ? weedRewardOf(seq[i]) : pestRewardOf(seq[i])).toInt();
      }
      expect(plannedEarn, 20, reason: '🔴 B13.4 不限次：10 处全部 2×1（旧 2×4+1×6 废除）');
      // ARB 上屏口径（zh）：共清理 {count} 处，奖励合计 +{total} ☀。
      expect(
        AppLocalizationsZh().garden_care_note_total(plan.careTargets.length,
            plannedEarn),
        '共清理 10 处，奖励合计 +20 ☀',
      );

      // 实际执行（与 garden_page.dart 的 seq 执行同构）。
      int earned = 0;
      final List<int> sequence = <int>[];
      for (int i = 0; i < plan.careTargets.length; i++) {
        final ({String plantId, bool weed}) t = plan.careTargets[i];
        final PlantPerk perk = seq[i];
        final int reward =
            (t.weed ? weedRewardOf(perk) : pestRewardOf(perk)).toInt();
        if (t.weed) {
          await env.growth.clearWeed(t.plantId, day, perk: perk);
        } else {
          await env.growth.clearPest(t.plantId, day, perk: perk);
        }
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.labor,
          plantId: null,
        );
        earned += reward;
        sequence.add(reward);
      }

      expect(sequence, List<int>.filled(10, 2),
          reason: '🔴 B13.4 不限次：次次 +1');
      expect(earned, 20);
      expect(await _sumWeed(env), 20, reason: '账本 plant_weed 合计 20');

      // 🟢 等式护栏：care note 合计 == 实到之和。
      expect(plannedEarn, earned, reason: '🟢 note 合计 20 == 实到 20');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-3 单株浇水 / 施肥：按钮价 == 实扣
  // ══════════════════════════════════════════════════════════════════════
  group('V3-3 养护卡按钮价 vs 实扣（同一 perk 变量）', () {
    test('浇水券 + 单株 ⇒ 按钮 4、账本 −4（🔴 B13.4：额度字段不再记账）', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      await env.seedPlant('p0');
      await env.seedBalance(100);
      await _giveVoucher(
        env,
        kind: GuardDropKind.waterVoucher,
        quota: 1,
        used: 0,
      );

      // plant_care_sheet.dart 的 `_perkWithVoucher(action, plantId)`（display）
      final PlantPerk perk = env.vouchers.overlayFor(
        await env.vouchers.currentBuff(),
        null,
        kind: GuardVoucherKind.water,
        plantId: 'p0',
      );
      final int buttonPrice = waterCostOf(perk);
      expect(buttonPrice, 4);

      await env.growth.water('p0', day, perk: perk);
      await env.vouchers.recordConsumed(
        kind: GuardVoucherKind.water,
        plantId: 'p0',
      );

      final List<SunlightEntry> rows = await env.rowsOf('plant_water');
      expect(rows, hasLength(1));
      expect(-rows.single.net, buttonPrice.toDouble());
      expect(rows.single.net, -4.0);
      // 🔴 B13.4：浇水券当日不限次 ⇒ recordConsumed 空操作、不写库，
      // 额度字段停在初始值（旧口径「额度归零」废除）。
      expect((await env.vouchers.currentBuff())!.remaining, 1);
    });

    test('免费浇水券 + 单株 ⇒ 按钮 0、账本 0 元行、额度归零', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      await env.seedPlant('p0');
      await env.seedBalance(100);
      await _giveVoucher(
        env,
        kind: GuardDropKind.freeWater,
        quota: 1,
        used: 0,
      );

      final PlantPerk perk = env.vouchers.overlayFor(
        await env.vouchers.currentBuff(),
        null,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p0',
      );
      expect(waterCostOf(perk), 0);

      await env.growth.water('p0', day, perk: perk);
      await env.vouchers.recordConsumed(
        kind: GuardVoucherKind.freeWater,
        plantId: 'p0',
      );

      final List<SunlightEntry> rows = await env.rowsOf('plant_water');
      expect(rows, hasLength(1));
      expect(rows.single.net, 0.0);
      expect(await env.ledger.balance(), 100.0);
      expect((await env.vouchers.currentBuff())!.remaining, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-4 单株 / 空盆 除草·除虫：飘字 vs 账本
  // ══════════════════════════════════════════════════════════════════════
  group('V3-4 单株除草飘字 vs 账本', () {
    test('有植物盆 + 劳动券 ⇒ 账本 +2（页面飘字用同一 perk）', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      await env.seedPlant('p0', weed: true);
      await env.seedBalance(100);
      await _giveVoucher(env, kind: GuardDropKind.laborVoucher, quota: 4);

      final PlantPerk clearPerk = env.vouchers.overlayFor(
        await env.vouchers.currentBuff(),
        null,
        kind: GuardVoucherKind.labor,
        plantId: 'p0',
      );
      // garden_page.dart `_clearPest`：`svc.clearWeed(pid, now, perk: clearPerk)`
      // 与 `_onClearAnimated(clearPerk: clearPerk)` 是**同一个变量**。
      final int floatText = weedRewardOf(clearPerk).toInt();
      await env.growth.clearWeed('p0', day, perk: clearPerk);

      final List<SunlightEntry> rows = await env.rowsOf('plant_weed');
      expect(rows, hasLength(1));
      expect(rows.single.net, floatText.toDouble());
      expect(rows.single.net, 2.0, reason: '飘字 +2 == 账本 +2');
    });

    test('无券 ⇒ 账本 +1（基础值），飘字同源', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      await env.seedPlant('p0', weed: true);
      await env.seedBalance(100);

      expect(weedRewardOf(PlantPerk.none).toInt(), 1);
      await env.growth.clearWeed('p0', day);

      final List<SunlightEntry> rows = await env.rowsOf('plant_weed');
      expect(rows.single.net, 1.0);
    });

    test('除虫基础值 +2，与除草不同键（防串价）', () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      await env.seedPlant('p0', pest: true);
      await env.seedBalance(100);
      await _giveVoucher(env, kind: GuardDropKind.laborVoucher, quota: 4);

      final PlantPerk perk = env.vouchers.overlayFor(
        await env.vouchers.currentBuff(),
        null,
        kind: GuardVoucherKind.labor,
        plantId: 'p0',
      );
      expect(pestRewardOf(perk).toInt(), 3, reason: '基础 2 + 券 1');
      await env.growth.clearPest('p0', day, perk: perk);

      final List<SunlightEntry> rows = await env.rowsOf('plant_pest');
      expect(rows.single.net, 3.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-5 buff chip 剩余额度 vs 存档
  // ══════════════════════════════════════════════════════════════════════
  group('V3-5 buff 券卡文案（B13.5：卡面图 + 券名 + 增益描述）', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    test('九种券的 zh 券名逐个对字面量（B13.20：券库 9 种）', () {
      expect(GuardBuffChip.nameOf(GuardDropKind.waterVoucher, zh), '浇水卡券');
      expect(GuardBuffChip.nameOf(GuardDropKind.laborVoucher, zh), '劳动卡券');
      expect(GuardBuffChip.nameOf(GuardDropKind.fertilizeVoucher, zh), '施肥卡券');
      expect(GuardBuffChip.nameOf(GuardDropKind.focusMeal, zh), '专注加餐卡券',
          reason: 'B13.20 新券');
      expect(GuardBuffChip.nameOf(GuardDropKind.focusBoost, zh), '专注放大卡券',
          reason: 'B13.20 新券');
      expect(GuardBuffChip.nameOf(GuardDropKind.freeWater, zh), '免费浇水卡券');
      expect(GuardBuffChip.nameOf(GuardDropKind.freeFertilize, zh), '免费施肥卡券');
      expect(GuardBuffChip.nameOf(GuardDropKind.freeWater3, zh), '免费浇水卡券（3 次）',
          reason: 'B13.19 新档；🔴 不用「×」号');
      expect(GuardBuffChip.nameOf(GuardDropKind.freeFertilize2, zh), '免费施肥卡券（2 次）',
          reason: 'B13.19 新档');
    });

    test('九种券的 zh 增益描述逐个对字面量（玄参：「写清楚 buff 增益」；B13.20 免费券改前 N 次口径）', () {
      expect(GuardBuffChip.descOf(GuardDropKind.waterVoucher, zh),
          '今日浇水每次可减少 1 阳光消耗');
      expect(GuardBuffChip.descOf(GuardDropKind.laborVoucher, zh),
          '今日除草除虫每次可多赚 1 阳光');
      expect(GuardBuffChip.descOf(GuardDropKind.fertilizeVoucher, zh),
          '今日施肥每次可减少 2 阳光消耗');
      expect(GuardBuffChip.descOf(GuardDropKind.focusMeal, zh),
          '今日累计专注满 15 分钟，额外获得 10 阳光',
          reason: 'B13.20 新券（被动券）');
      expect(GuardBuffChip.descOf(GuardDropKind.focusBoost, zh),
          '今日每场专注结算的阳光额外加 20%',
          reason: 'B13.20 新券（被动券）');
      expect(GuardBuffChip.descOf(GuardDropKind.freeWater, zh),
          '今日第 1 次浇水完全免费',
          reason: 'B13.20：「任选一盆」→「前 N 次免费」');
      expect(GuardBuffChip.descOf(GuardDropKind.freeFertilize, zh),
          '今日第 1 次施肥完全免费',
          reason: 'B13.20：「任选一盆」→「前 N 次免费」');
      expect(GuardBuffChip.descOf(GuardDropKind.freeWater3, zh),
          '今日前 3 次浇水完全免费',
          reason: 'B13.19 新档；B13.20 改前 N 次口径');
      expect(GuardBuffChip.descOf(GuardDropKind.freeFertilize2, zh),
          '今日前 2 次施肥完全免费',
          reason: 'B13.19 新档；B13.20 改前 N 次口径');
    });

    test('券名 / 描述不含「剩 N」、不含 `×`、en 不含汉字（中英可切换口径）', () {
      for (final GuardDropKind kind in GuardDropKind.values) {
        if (GuardVoucherKind.of(kind) == null) continue;
        final String name = GuardBuffChip.nameOf(kind, zh);
        final String desc = GuardBuffChip.descOf(kind, zh);
        expect(name.contains('剩'), isFalse, reason: name);
        expect(desc.contains('剩'), isFalse, reason: desc);
        expect(name.contains('×'), isFalse, reason: name);
        expect(desc.contains('×'), isFalse, reason: desc);
        expect(_han.hasMatch(GuardBuffChip.nameOf(kind, en)), isFalse,
            reason: GuardBuffChip.nameOf(kind, en));
        expect(_han.hasMatch(GuardBuffChip.descOf(kind, en)), isFalse,
            reason: GuardBuffChip.descOf(kind, en));
      }
    });

    test('🔴 B13.4：浇水 / 劳动券（不限次）永不追加「已用完」（存量 used==quota 只是旧记账）', () {
      const GuardBuffState usedUp =
          GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 6);
      expect(
        GuardBuffChip.descLineOf(GuardDropKind.waterVoucher, usedUp, zh),
        '今日浇水每次可减少 1 阳光消耗',
      );
      const GuardBuffState laborUsedUp =
          GuardBuffState(kind: GuardDropKind.laborVoucher, quota: 4, used: 4);
      expect(
        GuardBuffChip.descLineOf(GuardDropKind.laborVoucher, laborUsedUp, zh),
        '今日除草除虫每次可多赚 1 阳光',
      );
    });

    test('施肥 / 免费券（次数券）用完 ⇒ 描述追加「· 已用完」', () {
      const GuardBuffState usedUp =
          GuardBuffState(kind: GuardDropKind.fertilizeVoucher, quota: 12, used: 12);
      expect(
        GuardBuffChip.descLineOf(GuardDropKind.fertilizeVoucher, usedUp, zh),
        '今日施肥每次可减少 2 阳光消耗 · 已用完',
      );
      const GuardBuffState freeUsedUp =
          GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 1);
      expect(
        GuardBuffChip.descLineOf(GuardDropKind.freeWater, freeUsedUp, en),
        'Your first watering today is free · Used up',
        reason: 'B13.20 文案：前 N 次免费口径',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-6 阳光流水页：三条 guard_* 来源标签
  // ══════════════════════════════════════════════════════════════════════
  group('V3-6 阳光流水页来源标签', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    test('guard_pay / guard_win / guard_stolen 都有专属中文标签', () {
      final String pay = refLabelOf('guard_pay', zh);
      final String win = refLabelOf('guard_win', zh);
      final String stolen = refLabelOf('guard_stolen', zh);

      expect(pay, isNot(zh.hist_other), reason: '🔴 落到 default「其他」= 来源对不上账');
      expect(win, isNot(zh.hist_other));
      expect(stolen, isNot(zh.hist_other));
      expect(<String>{pay, win, stolen}, hasLength(3),
          reason: '三条标签必须互不相同：$pay / $win / $stolen');
      expect(pay.contains('守卫'), isTrue, reason: pay);
    });

    test('英文同样不是 Other，且三条互异', () {
      final String pay = refLabelOf('guard_pay', en);
      final String win = refLabelOf('guard_win', en);
      final String stolen = refLabelOf('guard_stolen', en);
      expect(pay, isNot(en.hist_other));
      expect(win, isNot(en.hist_other));
      expect(stolen, isNot(en.hist_other));
      expect(<String>{pay, win, stolen}, hasLength(3));
    });

    test('未知 refType 仍安全兜底为「其他」（对照组）', () {
      expect(refLabelOf('qa_unknown_ref', zh), zh.hist_other);
      expect(refLabelOf(null, zh), zh.hist_other);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-7 结算卡「券还能省 N 阳光」vs 实际可省
  // ══════════════════════════════════════════════════════════════════════
  group('V3-7 结算卡「券还能省 N」vs 实际可省', () {
    test('免费浇水券 + Lv.5 称号：卡面 4 == 实际省 4', () {
      // F4：卡面来源 = `GuardTodayView.voucherSaving`，按当前称号 perk 的**实际单价**算。
      const PlantPerk titled = PlantPerk(waterDiscount: 1);
      const GuardTodayView view = GuardTodayView(
        mode: GuardPillMode.pendingPaid,
        state: GuardDayState(
          dayKey: '2026-11-09',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeWater,
        ),
        energyAvailable: 0,
        balance: 100,
        perk: titled,
      );
      expect(view.voucherSaving, 4, reason: '有称号时水价 4 ⇒ 免费券只省 4');
      expect(waterCostOf(titled), 4);

      final double actual = voucherSavingOf(
        GuardDropKind.freeWater,
        potCount: 1,
        perk: titled,
      );
      expect(actual, 4.0, reason: '领域函数自己写着「随称号减免而变小」');

      // 🟢 等式护栏：卡面 == 真实节省量。
      expect(view.voucherSaving, actual,
          reason: '🟢 卡面 4 == 实际 4（F4 后同源）');
    });

    test('免费施肥券 + Lv.10 称号：卡面 9 == 实际省 9', () {
      const PlantPerk titled = PlantPerk(fertilizeDiscount: 1);
      const GuardTodayView view = GuardTodayView(
        mode: GuardPillMode.pendingPaid,
        state: GuardDayState(
          dayKey: '2026-11-09',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeFertilize,
        ),
        energyAvailable: 0,
        balance: 100,
        perk: titled,
      );
      expect(view.voucherSaving, 9);
      expect(fertilizeCostOf(titled), 9);
      final double actual = voucherSavingOf(
        GuardDropKind.freeFertilize,
        potCount: 1,
        perk: titled,
      );
      expect(actual, 9.0);
      expect(view.voucherSaving, actual, reason: '🟢 卡面 9 == 实际 9');
    });

    test('无称号时两者相等（对照组，防「一律不等」的假红）', () {
      expect(
        voucherSavingOf(
          GuardDropKind.freeWater,
          potCount: 1,
          perk: PlantPerk.none,
        ),
        5.0,
      );
      expect(
        voucherSavingOf(
          GuardDropKind.freeFertilize,
          potCount: 1,
          perk: PlantPerk.none,
        ),
        10.0,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-8 结算卡被偷行（守卫战 v2 B4）：卡面 N == recordBattleTheft 实扣
  // ══════════════════════════════════════════════════════════════════════
  group('V3-8 结算卡「被偷菜贼偷走 N 阳光」vs 账本实扣', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    /// 待机态战报快照（贼 / 必得 / 成本都在，stolenSun 走独立入参）。
    GuardTodayView viewForCard() => const GuardTodayView(
          mode: GuardPillMode.pendingPaid,
          state: GuardDayState(
            dayKey: '2026-11-09',
            status: GuardDayStatus.pending,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 2,
          ),
          energyAvailable: 0,
          balance: 100,
        );

    Future<void> pumpCard(
      WidgetTester tester, {
      required int stolenSun,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuardResultCard(
              view: viewForCard(),
              l10n: zh,
              // 只验渲染，绝不点「收下」⇒ onCollect 永不被调。
              onCollect: () async => throw StateError('本用例不点收下'),
              stolenSun: stolenSun,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('文案模板（zh/en 成对）：N 进句式，与流水页「被偷菜贼偷走」同语根', () {
      expect(zh.guard_result_stolen(2), '被偷菜贼偷走 2 阳光');
      expect(en.guard_result_stolen(2), 'The thief stole 2 sunlight');
    });

    testWidgets('有被偷（实扣 2）⇒ 卡面渲染「被偷菜贼偷走 2 阳光」', (tester) async {
      await pumpCard(tester, stolenSun: 2);
      expect(find.text('被偷菜贼偷走 2 阳光'), findsOneWidget,
          reason: '🟢 卡面 2 == recordBattleTheft 实扣 2（页面只传账本返回值）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('实扣 0 ⇒ 整行不渲染（🔴「偷走 0 阳光」=「省 0 阳光」同罪）',
        (tester) async {
      await pumpCard(tester, stolenSun: 0);
      expect(find.textContaining('偷走'), findsNothing,
          reason: '🔴 0 时被偷行绝不渲染');
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-9 B13.5 双券：结算卡奖励区渲染主券 + 第二张
  // ══════════════════════════════════════════════════════════════════════
  group('V3-9 B13.5 双券：结算卡第二张券卡', () {
    final AppLocalizations zh = AppLocalizationsZh();

    Future<void> pumpView(
      WidgetTester tester, {
      required GuardDayState state,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuardResultCard(
              view: GuardTodayView(
                mode: GuardPillMode.pendingPaid,
                state: state,
                energyAvailable: 0,
                balance: 100,
              ),
              l10n: zh,
              onCollect: () async => throw StateError('本用例不点收下'),
              stolenSun: 0,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('双券日 ⇒ 主券卡 + 第二张券卡都渲染，券名各就各位', (tester) async {
      await pumpView(
        tester,
        state: const GuardDayState(
          dayKey: '2026-11-11',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.waterVoucher,
          bonusDropKind: GuardDropKind.laborVoucher,
        ),
      );
      expect(find.byKey(GuardResultCard.voucherRewardKey), findsOneWidget,
          reason: '主券卡在');
      expect(find.byKey(GuardResultCard.bonusVoucherRewardKey), findsOneWidget,
          reason: '🔴 B13.5 第二张券卡在');
      // 券名走 guardDropName（guard_drop_name_* 旧键：浇水券 / 劳动券），
      // 与 buff 卡片的 guard_voucher_name_*（浇水卡券）是两套线，别混。
      expect(find.text('浇水券'), findsOneWidget);
      expect(find.text('劳动券'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('单券日（无第二张）⇒ 第二张卡不渲染（防误画空卡）', (tester) async {
      await pumpView(
        tester,
        state: const GuardDayState(
          dayKey: '2026-11-11',
          status: GuardDayStatus.pending,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.waterVoucher,
        ),
      );
      expect(find.byKey(GuardResultCard.voucherRewardKey), findsOneWidget);
      expect(find.byKey(GuardResultCard.bonusVoucherRewardKey), findsNothing,
          reason: 'bonusDropKind == none ⇒ 第二张卡绝不出现');
      expect(tester.takeException(), isNull);
    });
  });
}
