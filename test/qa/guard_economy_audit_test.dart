/// 花园守卫 · **V1 经济红线独立验收**（QA 自造探针，不复用工程师测试）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.2 / §3.7 / §3.8 / §4。
///
/// 每条断言都写**字面量**（5 / 1 / 2 / 3 / 6 / 4 / 174 / 14），不引用
/// `kGuard*` 常量，也不引用 `waterCostOf(perk)` 反推 —— 否则实现改错时探针一起绿。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';

import 'guard_probe_support.dart';

/// 固定的「守卫运行日」。
DateTime _day() => DateTime(2026, 11, 9, 10, 30);

/// 找一天**不限制浇水次数**（`waterQuota >= 3`）的日子（天气是确定性纯函数）。
DateTime _waterFriendlyDay() {
  for (int i = 0; i < 90; i++) {
    final DateTime d = DateTime(2026, 3, 1 + i, 8, 0);
    if (WeatherSystem.ofDay(d).waterQuota >= 3) return d;
  }
  throw StateError('90 天内找不到 waterQuota >= 3 的日子');
}

/// 一条「今天已 resolve、待处理」的存档（贼/奖励由探针指定，绕过确定性派生）。
GuardDayState _pending({
  required String dayKeyValue,
  int winSun = 2,
  GuardDropKind drop = GuardDropKind.none,
  GuardDayStatus status = GuardDayStatus.pending,
  int sunStolen = 0,
  Map<String, double> growthStolen = const <String, double>{},
}) =>
    GuardDayState(
      dayKey: dayKeyValue,
      status: status,
      thiefKind: GuardThiefKind.sunRat,
      winSun: winSun,
      dropKind: drop,
      sunStolen: sunStolen,
      growthStolen: growthStolen,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ════════════════════════════════════════════════════════════════════
  // V1-1 付费赶贼：余额必须恰好 100 − 5 + winSun，账本恰好 2 行
  // ════════════════════════════════════════════════════════════════════
  group('V1-1 付费赶贼：余额 = 100 − 5 + winSun，账本恰好 2 行', () {
    for (final int winSun in <int>[3, 4, 5]) {
      test('winSun=$winSun ⇒ 余额 ${100 - 5 + winSun}、2 行（−5 / +$winSun）', () async {
        final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
        addTearDown(env.close);
        await env.seedPlant('p1');
        await env.seedBalance(100);
        await env.store.write(
          env.childId,
          _pending(dayKeyValue: env.today, winSun: winSun),
        );

        final GuardClaimOutcome out = await env.guard.claim();

        expect(out.ok, isTrue);
        expect(out.usedEnergy, isFalse, reason: '没有专注记录 ⇒ 无能量 ⇒ 付费路径');
        expect(out.paidSun, 5);
        expect(out.winSun, winSun);

        final List<SunlightEntry> guardRows = <SunlightEntry>[
          ...await env.rowsOf('guard_pay'),
          ...await env.rowsOf('guard_win'),
        ];
        expect(guardRows.length, 2, reason: '🔴 恰好 1 行扣费 + 1 行入账，不许有第三行');
        final SunlightEntry pay =
            guardRows.firstWhere((SunlightEntry e) => e.refType == 'guard_pay');
        final SunlightEntry win =
            guardRows.firstWhere((SunlightEntry e) => e.refType == 'guard_win');
        expect(pay.net, -5.0, reason: '🔴 付费行金额必须是 −5（不是 −3 / −5.0 之外的数）');
        expect(pay.gross, -5.0);
        expect(win.net, winSun.toDouble());
        expect(win.gross, winSun.toDouble());
        expect(pay.refId, 'garden');
        expect(win.refId, 'garden');
        expect(pay.dayKey, env.today);
        expect(win.dayKey, env.today);

        // 101 是「初始 100 + 两行流水」的唯一自洽结果（100 − 5 + winSun）。
        expect(await env.ledger.balance(), (100 - 5 + winSun).toDouble());
        expect(await env.ledger.balance() + 5 - winSun, 100.0,
            reason: '🔴 对账：余额 + 扣费 − 收入 必须回到初始 100');
      });
    }

    test('账本 2 行 + balanceAfter 链自洽（row2.balanceAfter == 最终余额）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _pending(dayKeyValue: env.today, winSun: 3),
      );

      await env.guard.claim();

      final double finalBalance = await env.ledger.balance();
      // 三行（qa_seed / guard_pay / guard_win）共用同一 ts，倒序不稳定；
      // 用「后写入的那行」即 guard_win 的 balanceAfter 做对账。
      final SunlightEntry win = (await env.rowsOf('guard_win')).single;
      final SunlightEntry pay = (await env.rowsOf('guard_pay')).single;
      expect(win.balanceAfter, finalBalance,
          reason: '🔴 最后一笔守卫流水的 balanceAfter 必须等于余额（对不上账即为 P0）');
      expect(pay.balanceAfter, 95.0, reason: '扣费后瞬间余额 100 − 5');
      expect(finalBalance, 98.0);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-2 免费赶贼：余额不变、账本只 1 行 guard_win
  // ════════════════════════════════════════════════════════════════════
  group('V1-2 免费赶贼（有能量）：余额不变、账本只 1 行', () {
    test('1 次有效专注 ⇒ 0 扣费、1 行 guard_win、余额 100 → 102', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.focus.saveSession(FocusSession(
        id: 'qa-valid',
        start: _day().subtract(const Duration(minutes: 25)),
        end: _day(),
        plannedMin: 25,
        actualFocusMin: 25,
        status: FocusStatus.completed,
        sunlightEarned: 0,
        createdAt: _day().subtract(const Duration(minutes: 25)),
      ));
      await env.store.write(
        env.childId,
        _pending(dayKeyValue: env.today, winSun: 2),
      );

      final GuardClaimOutcome out = await env.guard.claim();

      expect(out.ok, isTrue);
      expect(out.usedEnergy, isTrue);
      expect(out.paidSun, 0, reason: '🔴 有能量绝不花阳光');
      expect((await env.rowsOf('guard_pay')).length, 0);
      expect((await env.rowsOf('guard_win')).length, 1);
      expect((await env.ledger.all()).length, 2,
          reason: '账本里只有 qa_seed(100) + guard_win(2)，没有任何守卫扣费行');
      expect(await env.ledger.balance(), 102.0);
      expect(out.energyAvailable, 0, reason: '1 点能量已用完');
      expect((await env.store.read(env.childId)).energyUsed, 1);
    });

    test('3 分钟就放弃的会话 × 5 ⇒ 不算能量，走付费路径（对照组）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      for (int i = 0; i < 5; i++) {
        await env.focus.saveSession(FocusSession(
          id: 'qa-short-$i',
          start: _day().subtract(const Duration(minutes: 3)),
          end: _day(),
          plannedMin: 25,
          actualFocusMin: 3,
          status: FocusStatus.shortAborted,
          sunlightEarned: 0,
          createdAt: _day().subtract(const Duration(minutes: 3)),
        ));
      }
      await env.store.write(
        env.childId,
        _pending(dayKeyValue: env.today, winSun: 2),
      );

      final GuardClaimOutcome out = await env.guard.claim();

      expect(out.usedEnergy, isFalse);
      expect(out.paidSun, 5, reason: '对照组：无效专注不许发能量');
      expect(await env.ledger.balance(), 97.0);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-3 重复 claim × 3：账本行数 / 余额不再变化（幂等核心）
  // ════════════════════════════════════════════════════════════════════
  group('V1-3 重复 claim × 3：账本仍 2 行、余额不再变化', () {
    test('付费路径连点 3 次', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.store.write(
        env.childId,
        _pending(dayKeyValue: env.today, winSun: 2),
      );

      await env.guard.claim();
      final int rowsAfter1 = (await env.ledger.all()).length;
      final double balanceAfter1 = await env.ledger.balance();
      expect(rowsAfter1, 3, reason: 'qa_seed + guard_pay + guard_win');

      for (int i = 0; i < 2; i++) {
        final GuardClaimOutcome again = await env.guard.claim();
        expect(again.alreadyClaimed, isTrue);
      }

      expect((await env.ledger.all()).length, rowsAfter1,
          reason: '🔴 连点 3 次后账本行数必须不变');
      expect((await env.rowsOf('guard_pay')).length, 1);
      expect((await env.rowsOf('guard_win')).length, 1);
      expect(await env.ledger.balance(), balanceAfter1);
      expect(balanceAfter1, 97.0);
    });

    test('免费路径连点 3 次：仍只有 1 行 guard_win、能量只消耗 1 点', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);
      await env.focus.saveSession(FocusSession(
        id: 'qa-valid',
        start: _day().subtract(const Duration(minutes: 25)),
        end: _day(),
        plannedMin: 25,
        actualFocusMin: 25,
        status: FocusStatus.completed,
        sunlightEarned: 0,
        createdAt: _day().subtract(const Duration(minutes: 25)),
      ));
      await env.store.write(
        env.childId,
        _pending(dayKeyValue: env.today, winSun: 2),
      );

      await env.guard.claim();
      for (int i = 0; i < 2; i++) {
        await env.guard.claim();
      }

      expect((await env.rowsOf('guard_win')).length, 1);
      expect(await env.ledger.balance(), 102.0);
      expect((await env.store.read(env.childId)).energyUsed, 1,
          reason: '🔴 重复领取不得重复扣能量');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-4 浇水券封顶：12 盆 × 3 次 = 36 次，总减免恰好 6（花费 174）
  // ════════════════════════════════════════════════════════════════════
  group('V1-4 浇水券日封顶 6 ☀（不是 36 ☀）', () {
    test('12 盆 × 3 次：每盆 5 / 4，总花费 174、第 7 次起回原价 5', () async {
      final DateTime day = _waterFriendlyDay();
      final DateTime base = DateTime(day.year, day.month, day.day, 8, 0);
      final GuardProbeEnv env =
          await GuardProbeEnv.create(clock: () => base);
      addTearDown(env.close);
      await env.seedBalance(1000, at: base);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i, now: base);
      }
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: dayKey(base),
          status: GuardDayStatus.claimed,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.waterVoucher,
          buff: const GuardBuffState(
            kind: GuardDropKind.waterVoucher,
            quota: 6,
          ),
        ),
      );

      final List<int> prices = <int>[];
      for (int round = 0; round < 3; round++) {
        for (int i = 0; i < 12; i++) {
          final DateTime now =
              base.add(Duration(minutes: 31 * round));
          final PlantPerk perk = await env.vouchers.overlay(
            PlantPerk.none,
            kind: GuardVoucherKind.water,
            plantId: null,
            now: now,
          );
          final int price = waterCostOf(perk);
          await env.growth.water('p$i', now, perk: perk);
          await env.vouchers.recordConsumed(
            kind: GuardVoucherKind.water,
            plantId: null,
            now: now,
          );
          prices.add(price);
        }
      }

      expect(prices.length, 36);
      expect(prices.sublist(0, 6), <int>[4, 4, 4, 4, 4, 4],
          reason: '前 6 次各减 1 ☀');
      expect(prices.sublist(6), List<int>.filled(30, 5),
          reason: '🔴 第 7 次浇水开始就是原价 5（封顶后不得再减）');
      expect(prices.fold<int>(0, (int a, int b) => a + b), 174,
          reason: '🔴 36×5 − 6 = 174，不是 36×4 = 144');
      expect(prices.fold<int>(0, (int a, int b) => a + b), isNot(144));

      final int spent = (await env.rowsOf('plant_water'))
          .map((SunlightEntry e) => (-e.net).round())
          .fold<int>(0, (int a, int b) => a + b);
      expect(spent, 174, reason: '🔴 账本实扣总和必须与上面的价格序列一致');
      expect((await env.rowsOf('plant_water')).length, 36);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-5 免费券绝不整批：一键 N 盆每盆付满 5、额度仍是 1
  // ════════════════════════════════════════════════════════════════════
  group('V1-5 免费浇水券绝不整批（PRD A10）', () {
    test('一键 5 盆 ⇒ 每盆 5 ☀（合计 25）、remaining 仍为 1、未核销', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedBalance(1000);
      for (int i = 0; i < 5; i++) {
        await env.seedPlant('p$i', potIndex: i);
      }
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: env.today,
          status: GuardDayStatus.claimed,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeWater,
          buff: const GuardBuffState(
            kind: GuardDropKind.freeWater,
            quota: 1,
          ),
        ),
      );

      final List<int> prices = <int>[];
      for (int i = 0; i < 5; i++) {
        // 页面一键路径：批量一律 plantId == null。
        final PlantPerk perk = await env.vouchers.overlay(
          PlantPerk.none,
          kind: GuardVoucherKind.freeWater,
          plantId: null,
        );
        final int price = waterCostOf(perk);
        await env.growth.water('p$i', _day(), perk: perk);
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.freeWater,
          plantId: null,
        );
        prices.add(price);
      }

      expect(prices, <int>[5, 5, 5, 5, 5],
          reason: '🔴 免费券在批量路径必须完全不生效（不是 0，也不是 20 的四盆价）');
      expect(prices.fold<int>(0, (int a, int b) => a + b), 25);
      expect((await env.vouchers.currentBuff())!.remaining, 1,
          reason: '🔴 批量不得烧掉唯一的免费额度');
      expect((await env.store.read(env.childId)).buff!.used, 0);
      expect(
        (await env.rowsOf('plant_water'))
            .map((SunlightEntry e) => (-e.net).round())
            .toList(),
        <int>[5, 5, 5, 5, 5],
      );
    });

    test('对照组：单株路径 plantId 非 null ⇒ 0 ☀、额度用掉 1', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedBalance(1000);
      await env.seedPlant('p0');
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: env.today,
          status: GuardDayStatus.claimed,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.freeWater,
          buff: const GuardBuffState(
            kind: GuardDropKind.freeWater,
            quota: 1,
          ),
        ),
      );

      final PlantPerk perk = await env.vouchers.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p0',
      );
      expect(waterCostOf(perk), 0);
      await env.growth.water('p0', _day(), perk: perk);
      await env.vouchers.recordConsumed(
        kind: GuardVoucherKind.freeWater,
        plantId: 'p0',
      );

      expect((await env.rowsOf('plant_water')).single.net, 0.0);
      expect((await env.vouchers.currentBuff())!.remaining, 0);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-6 劳动券封顶 4：10 次清理 ⇒ 总加成恰好 4
  // ════════════════════════════════════════════════════════════════════
  group('V1-6 劳动券日封顶 4 ☀', () {
    test('10 次除草：单次奖励 [2,2,2,2,1,...]、总奖励 14（基础 10 + 券 4）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedBalance(100);
      for (int i = 0; i < 10; i++) {
        await env.seedPlant('w$i', potIndex: i, weed: true);
      }
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: env.today,
          status: GuardDayStatus.claimed,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.laborVoucher,
          buff: const GuardBuffState(
            kind: GuardDropKind.laborVoucher,
            quota: 4,
          ),
        ),
      );

      final List<int> rewards = <int>[];
      for (int i = 0; i < 10; i++) {
        final PlantPerk perk = await env.vouchers.overlay(
          PlantPerk.none,
          kind: GuardVoucherKind.labor,
          plantId: 'w$i',
        );
        final int reward = weedRewardOf(perk).toInt();
        await env.growth.clearWeed('w$i', _day(), perk: perk);
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.labor,
          plantId: 'w$i',
        );
        rewards.add(reward);
      }

      expect(rewards, <int>[2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
          reason: '🔴 前 4 次 +2，第 5 次起回基础 +1');
      expect(rewards.fold<int>(0, (int a, int b) => a + b), 14,
          reason: '10 次基础 10 + 券加成 4 = 14');
      expect(rewards.fold<int>(0, (int a, int b) => a + b) - 10, 4,
          reason: '🔴 券的总加成恰好 4（不是 8.4 / 10）');

      final List<int> ledgerAmounts = (await env.rowsOf('plant_weed'))
          .map((SunlightEntry e) => e.net.round())
          .toList();
      expect(ledgerAmounts.fold<int>(0, (int a, int b) => a + b), 14,
          reason: '🔴 账本实发必须与上面 10 次的奖励序列逐项一致');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // V1-7 voucherSavingOf 的自洽性（免费券随称号变小）
  // ════════════════════════════════════════════════════════════════════
  group('V1-7 voucherSavingOf 与实际节省量一致', () {
    test('免费浇水券 + Lv.5 称号：省 4（不是 5）', () {
      const PlantPerk lv5 = PlantPerk(waterDiscount: 1);
      final double claimed = voucherSavingOf(GuardDropKind.freeWater, perk: lv5);
      final int basePrice = waterCostOf(lv5);
      final int actualPrice = waterCostOf(lv5.add(const PlantPerk(waterDiscount: 5)));
      expect(basePrice, 4, reason: '有称号时水价 4');
      expect(actualPrice, 0);
      expect(claimed, 4.0, reason: '🔴 免费券省的是「这盆实际水价」4，不是面值 5');
      expect(basePrice - actualPrice, claimed.toInt());
    });

    test('免费施肥券 + Lv.10 称号：省 9（不是 10）', () {
      const PlantPerk lv10 = PlantPerk(fertilizeDiscount: 1);
      final double claimed =
          voucherSavingOf(GuardDropKind.freeFertilize, perk: lv10);
      final int basePrice = fertilizeCostOf(lv10);
      expect(basePrice, 9);
      expect(claimed, 9.0);
    });

    test('浇水券 12 盆：面值函数 6 == 实际 12 盆的省钱 6', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(clock: _day);
      addTearDown(env.close);
      await env.seedBalance(1000);
      for (int i = 0; i < 12; i++) {
        await env.seedPlant('p$i', potIndex: i);
      }
      await env.store.write(
        env.childId,
        GuardDayState(
          dayKey: env.today,
          status: GuardDayStatus.claimed,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          dropKind: GuardDropKind.waterVoucher,
          buff: const GuardBuffState(
            kind: GuardDropKind.waterVoucher,
            quota: 6,
          ),
        ),
      );

      int spent = 0;
      for (int i = 0; i < 12; i++) {
        final PlantPerk perk = await env.vouchers.overlay(
          PlantPerk.none,
          kind: GuardVoucherKind.water,
          plantId: 'p$i',
        );
        spent += waterCostOf(perk);
        await env.growth.water('p$i', _day(), perk: perk);
        await env.vouchers.recordConsumed(
          kind: GuardVoucherKind.water,
          plantId: 'p$i',
        );
      }

      final double claimed =
          voucherSavingOf(GuardDropKind.waterVoucher, potCount: 12);
      expect(12 * 5 - spent, claimed.toInt(),
          reason: '结算卡/说明上写的「还能省 N」必须等于实际省下的 ☀');
      expect(claimed, 6.0);
    });

    test('劳动券 10 次：面值函数 4 == 实际 10 次的加成 4', () {
      expect(voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 10), 4.0);
      // 与 V1-6 的实测序列对照：前 4 次 +1 加成、第 5 次起 0。
      final List<int> bonus = <int>[1, 1, 1, 1, 0, 0, 0, 0, 0, 0];
      expect(bonus.fold<int>(0, (int a, int b) => a + b), 4);
      expect(voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 10),
          bonus.fold<int>(0, (int a, int b) => a + b).toDouble());
    });
  });
}
