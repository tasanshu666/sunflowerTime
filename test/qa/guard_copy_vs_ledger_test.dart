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

import 'guard_probe_support.dart';

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
    test('浇水券剩 6 + 12 盆：卡面 54 == 实扣 54（逐盆序列）', () async {
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
      expect(cardTotal, 54, reason: '卡面合计 = 前 6 盆 4 + 后 6 盆 5');

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

      expect(spent, 54.0, reason: '前 6 盆 4 + 后 6 盆 5 = 54');
      expect(await _sumPlantWater(env), 54.0, reason: '账本实扣 54');

      // ③ 等式护栏：确认卡数字 == 实扣之和。
      expect(cardTotal, spent.toInt(),
          reason: '🟢 确认卡 54 == 实扣 54（F2 后三处同源）');
      expect(spent.toInt() - cardTotal, 0);
    });

    test('🔴 阳光闸门用逐盆合计价：余额 50 < 54 ⇒ 整体拦截，一盆都不执行',
        () async {
      final DateTime day = _waterFriendlyDay();
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: () => day);
      addTearDown(env.close);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i, progress: 0.5);
      }
      await env.seedBalance(50);
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
      expect(plannedCost, 54);
      final double balance = await env.ledger.balance();
      expect(balance < plannedCost, isTrue, reason: '50 < 54 ⇒ 必须整体拦截');

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
      expect(await env.ledger.balance(), 50.0, reason: '分毫不扣');
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
    test('劳动券 4 + 10 处杂草：note 合计 +14 == 实到 14', () async {
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
      expect(plannedEarn, 14, reason: '2×4 + 1×6');
      // ARB 上屏口径（zh）：共清理 {count} 处，奖励合计 +{total} ☀。
      expect(
        AppLocalizationsZh().garden_care_note_total(plan.careTargets.length,
            plannedEarn),
        '共清理 10 处，奖励合计 +14 ☀',
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

      expect(sequence, <int>[2, 2, 2, 2, 1, 1, 1, 1, 1, 1]);
      expect(earned, 14);
      expect(await _sumWeed(env), 14, reason: '账本 plant_weed 合计 14');

      // 🟢 等式护栏：care note 合计 == 实到之和。
      expect(plannedEarn, earned, reason: '🟢 note 合计 14 == 实到 14');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V3-3 单株浇水 / 施肥：按钮价 == 实扣
  // ══════════════════════════════════════════════════════════════════════
  group('V3-3 养护卡按钮价 vs 实扣（同一 perk 变量）', () {
    test('浇水券剩 1 + 单株 ⇒ 按钮 4、账本 −4、额度归零', () async {
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
      expect((await env.vouchers.currentBuff())!.remaining, 0);
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
  group('V3-5 buff chip 剩余额度 vs 存档 remaining', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    test('浇水券也不含「剩 N」（玄参 2026-11-09：与劳动券同口径，只显示 buff）', () {
      const GuardBuffState buff = GuardBuffState(
        kind: GuardDropKind.waterVoucher,
        quota: 6,
        used: 2, // remaining = 4
      );
      final String label = GuardBuffChip.labelOf(buff, zh);
      expect(label, '今日浇水 −1 ☀', reason: '只显示 buff 本身：$label');
      expect(label.contains('剩'), isFalse, reason: label);
      expect(label.contains('4'), isFalse,
          reason: '剩余额度不上屏（仍记账，只影响确认卡价格）：$label');
      final String exhausted = GuardBuffChip.labelOf(
        const GuardBuffState(
            kind: GuardDropKind.waterVoucher, quota: 6, used: 6),
        zh,
      );
      expect(exhausted, '今日浇水 −1 ☀ · 已用完', reason: exhausted);
    });

    test('用完 ⇒ chip 仍在屏上但带「已用完」（劳动券不再显示剩余量）', () {
      const GuardBuffState buff = GuardBuffState(
        kind: GuardDropKind.laborVoucher,
        quota: 4,
        used: 4,
      );
      final String label = GuardBuffChip.labelOf(buff, zh);
      expect(label, isNotEmpty);
      expect(label.contains('已用完'), isTrue, reason: label);
      expect(label.contains('剩'), isFalse,
          reason: '劳动券只显示 buff +「已用完」，不再显示剩余额度：$label');
    });

    test('劳动券：labelOf 不含「剩」、不等于旧「· 剩 4」、用完仍含「已用完」', () {
      const GuardBuffState buff = GuardBuffState(
        kind: GuardDropKind.laborVoucher,
        quota: 4,
        used: 0, // remaining = 4
      );
      final String label = GuardBuffChip.labelOf(buff, zh);
      expect(label.contains('剩'), isFalse, reason: '劳动券只显示 buff：$label');
      expect(label, isNot('今日除草除虫 +1 ☀ · 剩 4'),
          reason: '不得回退成带「剩 N」的旧文案：$label');
      expect(label, '今日除草除虫 +1 ☀', reason: '新文案不带参数');
      final String exhausted = GuardBuffChip.labelOf(
        const GuardBuffState(
            kind: GuardDropKind.laborVoucher, quota: 4, used: 4),
        zh,
      );
      expect(exhausted.contains('已用完'), isTrue,
          reason: '额度用完仍追加「已用完」：$exhausted');
    });

    test('中英文案都不含 `×` 字符（资源 chips 行的定位口径）', () {
      for (final GuardDropKind kind in <GuardDropKind>[
        GuardDropKind.waterVoucher,
        GuardDropKind.laborVoucher,
        GuardDropKind.fertilizeVoucher,
        GuardDropKind.freeWater,
        GuardDropKind.freeFertilize,
      ]) {
        final GuardBuffState buff = GuardBuffState(kind: kind, quota: 3, used: 1);
        expect(GuardBuffChip.labelOf(buff, zh).contains('×'), isFalse);
        expect(GuardBuffChip.labelOf(buff, en).contains('×'), isFalse);
      }
    });

    test('施肥券 / 免费券没有「剩 N」概念（不显示剩余额度）', () {
      final String f = GuardBuffChip.labelOf(
        const GuardBuffState(kind: GuardDropKind.fertilizeVoucher, quota: 12),
        zh,
      );
      final String fw = GuardBuffChip.labelOf(
        const GuardBuffState(kind: GuardDropKind.freeWater, quota: 1),
        zh,
      );
      expect(f.contains('剩'), isFalse,
          reason: '施肥券是「今日每次施肥 −2 ☀」，不显示剩余额度：$f');
      expect(fw.contains('剩'), isFalse, reason: fw);
      expect(fw.contains('盆'), isTrue, reason: '免费券文案应说明「1 盆」：$fw');
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
}
