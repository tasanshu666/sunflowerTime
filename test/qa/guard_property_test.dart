/// 花园守卫独立验收 · **V8 数据不变量（200 组）**
///
/// 期望值全部是**字面量**（`[0.45, 0.45, 0.10]` / `[0.35, 0.20, 0.15, 0.08,
/// 0.04, 0.18]` / `[0.01, 0.05]`），**不 import** 实现里的权重表来反推 ——
/// 否则「实现写错、期望跟着错」就是典型假绿。
///
/// 覆盖：
///  1. 同输入同输出（200 组 × 2 次调用逐字段相等）；
///  2. 贼分布 ≈ 45% / 45% / 10%，偏差 < 0.05；
///  3. 掉落 6 档概率和 == 1.0（字面量断言）+ 实测分布偏差 < 0.05；
///  4. 成长偷取比例 ∈ [1%, 5%]；食叶虫 ∈ [1%, 3%)；馋光鼠恒 0；
///  5. 偷阳光 ∈ {0, 1, 2, 3}；馋光鼠/贪婪鼬恒 > 0，食叶虫恒 0；
///  6. 必得阳光：无道具档恒 3，有券档 ∈ [1, 3]；
///  7. 同日同 child 反复 `resolve()` 幂等（状态/账本/成长三重不动）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardWinSunMax, kGuardWinSunMin, kGuardWinSunNoItem;
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/guard_service.dart';

import 'guard_probe_support.dart';

/// 200 组互不相同的 `(dayKey, childId)`。
List<({String dayKey, String childId})> _samples({int n = 200}) {
  final DateTime base = DateTime(2026, 1, 1);
  return <({String dayKey, String childId})>[
    for (int i = 0; i < n; i++)
      (
        dayKey: dayKey(base.add(Duration(days: i))),
        childId: 'qa_child_${i % 7}',
      ),
  ];
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // V8-1 确定性：同输入恒同输出
  // ══════════════════════════════════════════════════════════════════════
  group('V8-1 确定性（200 组 × 2 次）', () {
    test('同一 (dayKey, childId) 两次派生逐字段相等', () {
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll a =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        final GuardRoll b =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        expect(a.thief, b.thief, reason: '${s.dayKey}/${s.childId} thief 不稳');
        expect(a.drop, b.drop, reason: '${s.dayKey}/${s.childId} drop 不稳');
        expect(a.sunLoss, b.sunLoss);
        expect(a.growthLossPercent, b.growthLossPercent);
        expect(a.winSun, b.winSun);
      }
    });

    test('不同 childId 不共享同一结果（域隔离）', () {
      final DateTime base = DateTime(2026, 1, 1);
      final String day = dayKey(base);
      final Set<String> fingerprints = <String>{};
      for (int i = 0; i < 20; i++) {
        final GuardRoll r = deriveGuardRoll(dayKey: day, childId: 'kid_$i');
        fingerprints.add(
          '${r.thief.id}|${r.drop.id}|${r.sunLoss}|'
          '${r.growthLossPercent.toStringAsFixed(6)}|${r.winSun}',
        );
      }
      expect(fingerprints.length, greaterThan(15),
          reason: '20 个孩子同一天的结果几乎全同 ⇒ 通道没吃 childId');
    });

    test('dayKey 不同 ⇒ 结果会变（不是常量表）', () {
      final Set<String> fingerprints = <String>{};
      final DateTime base = DateTime(2026, 3, 1);
      for (int i = 0; i < 30; i++) {
        final GuardRoll r = deriveGuardRoll(
          dayKey: dayKey(base.add(Duration(days: i))),
          childId: 'kid_fixed',
        );
        fingerprints.add('${r.thief.id}|${r.drop.id}|${r.winSun}');
      }
      expect(fingerprints.length, greaterThan(5));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V8-2 贼分布
  // ══════════════════════════════════════════════════════════════════════
  group('V8-2 贼分布 ≈ [0.45, 0.45, 0.10]', () {
    test('200 组实测频率偏差 < 0.05', () {
      final Map<GuardThiefKind, int> counts = <GuardThiefKind, int>{
        for (final GuardThiefKind k in GuardThiefKind.values) k: 0,
      };
      final List<({String dayKey, String childId})> samples = _samples();
      for (final ({String dayKey, String childId}) s in samples) {
        final GuardThiefKind k =
            GuardThiefKind.roll(dayKey: s.dayKey, childId: s.childId);
        counts[k] = counts[k]! + 1;
      }

      final double n = samples.length.toDouble();
      const List<double> expected = <double>[0.45, 0.45, 0.10];
      for (int i = 0; i < GuardThiefKind.values.length; i++) {
        final double actual = counts[GuardThiefKind.values[i]]! / n;
        expect((actual - expected[i]).abs(), lessThan(0.05),
            reason: '${GuardThiefKind.values[i].id} 实测 $actual，期望 ${expected[i]}');
      }
    });

    test('权重表字面量就是 0.45 / 0.45 / 0.10 且和 == 1.0', () {
      // 独立于实现：直接读实体暴露的 weight，再和 PRD 字面量比。
      expect(
        GuardThiefKind.values.map((GuardThiefKind k) => k.weight).toList(),
        <double>[0.45, 0.45, 0.10],
      );
      final double sum = GuardThiefKind.values
          .fold<double>(0, (double acc, GuardThiefKind k) => acc + k.weight);
      expect(sum, closeTo(1.0, 1e-12));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V8-3 掉落 10 档（B13.20：9 券 + none）
  // 🔴 B13.20（玄参 2026-11-13）：**统一券池制**——spec.rate 语义 = 免费档
  //    全口径（5 种非免费券各 14% + 4 种免费券 0% + none 30%），与
  //    PRD §3.7 / kGuardDropRatePerVoucherFree 三处同源。
  // ══════════════════════════════════════════════════════════════════════
  group('V8-3 掉落 10 档概率和 == 1.0', () {
    test('spec.rate = B13.20 免费档全口径（三处同源，逐位一致）：[0.14×5, 0, 0, 0, 0, 0.30]', () {
      final List<double> rates = GuardDropKind.values
          .map((GuardDropKind k) => k.rate)
          .toList();
      expect(rates, <double>[
        0.14, 0.14, 0.14, 0.14, 0.14, // 券池 5 种非免费券（water/labor/fert/meal/boost）
        0, 0, 0, 0, // 4 种免费券：只进高级宝箱
        0.30, // none 闸门
      ]);
      expect(rates.fold<double>(0, (double a, double b) => a + b),
          closeTo(1.0, 1e-12));
    });

    test('B13.20 免费档字面量和 == 1.0：5×0.14 + 0.30', () {
      const List<double> freeTable = <double>[
        0.14, 0.14, 0.14, 0.14, 0.14, 0, 0, 0, 0, 0.30,
      ];
      expect(freeTable.fold<double>(0, (double a, double b) => a + b),
          closeTo(1.0, 1e-12));
    });

    test('200 组实测分布偏差 < 0.05（对拍 B13.20 免费档字面量），券池 5 档全部出现过', () {
      // 🔴 期望值是**字面量**（与 GuardDropKind.values 同序：
      //    water / labor / fertilize / focusMeal / focusBoost /
      //    freeWater / freeFertilize / freeWater3 / freeFertilize2 / none），
      //    不 import 实现表 —— 实现改错、期望不跟（本文件头铁律）。
      const List<double> freeTable = <double>[
        0.14, 0.14, 0.14, 0.14, 0.14, 0, 0, 0, 0, 0.30,
      ];
      final Map<GuardDropKind, int> counts = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      final List<({String dayKey, String childId})> samples = _samples();
      for (final ({String dayKey, String childId}) s in samples) {
        final GuardDropKind k =
            GuardDropKind.roll(dayKey: s.dayKey, childId: s.childId);
        counts[k] = counts[k]! + 1;
      }
      final double n = samples.length.toDouble();
      final List<GuardDropKind> order = GuardDropKind.values.toList();
      for (int i = 0; i < order.length; i++) {
        final GuardDropKind k = order[i];
        final double actual = counts[k]! / n;
        expect((actual - freeTable[i]).abs(), lessThan(0.05),
            reason: '${k.id} 实测 $actual，期望（B13.20 免费档全口径）${freeTable[i]}');
        if (freeTable[i] == 0) {
          // 🔴 B13.20：免费券只在高级宝箱出现，掉落层 200 组实测必须 **0 次**。
          expect(counts[k], 0, reason: '${k.id} 不该出现在掉落层（免费券只进高级宝箱）');
        } else {
          expect(counts[k], greaterThan(0), reason: '${k.id} 一次都没出现');
        }
      }
    });

    test('四种免费券 singlePotOnly == true，其余（含专注券）== false（A10 数据源）', () {
      for (final GuardDropKind k in <GuardDropKind>[
        GuardDropKind.freeWater,
        GuardDropKind.freeFertilize,
        GuardDropKind.freeWater3,
        GuardDropKind.freeFertilize2,
      ]) {
        expect(k.singlePotOnly, isTrue, reason: '${k.id} 必须是单株限定');
      }
      for (final GuardDropKind k in <GuardDropKind>[
        GuardDropKind.waterVoucher,
        GuardDropKind.laborVoucher,
        GuardDropKind.fertilizeVoucher,
        GuardDropKind.focusMeal,
        GuardDropKind.focusBoost,
        GuardDropKind.none,
      ]) {
        expect(k.singlePotOnly, isFalse, reason: '${k.id} 不该是单株限定');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V8-4 成长偷取比例 & 偷阳光区间
  // ══════════════════════════════════════════════════════════════════════
  group('V8-4 成长比例 ∈ [1%, 5%]、偷阳光 ∈ [0, 3]', () {
    test('馋光鼠：growth == 0、sun ∈ [1,3]', () {
      int sunRatTurns = 0;
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        if (r.thief != GuardThiefKind.sunRat) continue;
        sunRatTurns++;
        expect(r.growthLossPercent, 0.0);
        expect(r.sunLoss, inInclusiveRange(1, 3));
        expect(r.stealsGrowth, isFalse);
      }
      expect(sunRatTurns, greaterThan(0));
    });

    test('食叶虫：growth ∈ [1%, 3%)、sun == 0', () {
      int turns = 0;
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        if (r.thief != GuardThiefKind.leafBug) continue;
        turns++;
        expect(r.sunLoss, 0);
        expect(r.growthLossPercent, greaterThanOrEqualTo(0.01));
        expect(r.growthLossPercent, lessThan(0.03),
            reason: '区间是 [1%, 3%)，闭到 3% 会越过 PRD 上界');
      }
      expect(turns, greaterThan(0));
    });

    test('贪婪鼬：growth ∈ [1%, 5%)、sun ∈ [1,3]', () {
      int turns = 0;
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        if (r.thief != GuardThiefKind.sneakThief) continue;
        turns++;
        expect(r.sunLoss, inInclusiveRange(1, 3));
        expect(r.growthLossPercent, greaterThanOrEqualTo(0.01));
        expect(r.growthLossPercent, lessThan(0.05));
      }
      expect(turns, greaterThan(0));
    });

    test('200 组全体：growth 落在 [0, 5%] 闭区间内（永不越界）', () {
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        expect(r.growthLossPercent, greaterThanOrEqualTo(0.0));
        expect(r.growthLossPercent, lessThanOrEqualTo(0.05));
        expect(r.sunLoss, greaterThanOrEqualTo(0));
        expect(r.sunLoss, lessThanOrEqualTo(3));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V8-5 必得阳光
  // ══════════════════════════════════════════════════════════════════════
  group('V8-5 必得阳光', () {
    test('无道具档恒 5；有券档 ∈ [3, 5]', () {
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        if (!r.drop.hasVoucher) {
          expect(r.winSun, kGuardWinSunNoItem,
              reason: '${s.dayKey}: 无道具档取区间上限（决策 D2/R1；'
                  'B5b 区间 3~5 ⇒ 上限 5）');
        } else {
          expect(r.winSun, inInclusiveRange(kGuardWinSunMin, kGuardWinSunMax));
        }
      }
    });

    test('5 档 winSun 在有券的日子里都出现过（不是常量）', () {
      final Set<int> seen = <int>{};
      for (final ({String dayKey, String childId}) s in _samples()) {
        final GuardRoll r =
            deriveGuardRoll(dayKey: s.dayKey, childId: s.childId);
        if (r.drop.hasVoucher) seen.add(r.winSun);
      }
      expect(seen, <int>{3, 4, 5},
          reason: '🔴 B5b：win 区间扩到 5 档（3~5）后 5 档均匀映射，各档都必须出现');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V8-6 同日 resolve 幂等（真实链路）
  // ══════════════════════════════════════════════════════════════════════
  group('V8-6 同日 resolve 幂等', () {
    test('连续 5 次 resolve ⇒ 状态逐字段相同、账本 0 行、成长不动', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(
        clock: () => DateTime(2026, 11, 9, 10, 30),
      );
      addTearDown(env.close);
      await env.seedPlant('p1', progress: 0.5);
      await env.seedPlant('p2', progress: 0.6);
      await env.seedBalance(100);

      final GuardResolveResult first = await env.guard.resolve();
      for (int i = 0; i < 4; i++) {
        final GuardResolveResult again = await env.guard.resolve();
        expect(again.thief, first.thief);
        expect(again.state.status, first.state.status);
        expect(again.state.winSun, first.state.winSun);
        expect(again.state.dropKind, first.state.dropKind);
        expect(again.state.sunStolen, first.state.sunStolen);
        expect(again.state.growthStolen, first.state.growthStolen);
        expect(again.state.dayKey, first.state.dayKey);
      }

      expect(await env.ledgerRows(), hasLength(1),
          reason: '只有夹具的 qa_seed 一行；resolve 零账本写入');
      expect((await env.plants.plant('p1'))!.growthProgress, 0.5);
      expect((await env.plants.plant('p2'))!.growthProgress, 0.6);
    });

    test('反复 resolve 不会把「未结算的昨天」覆盖掉（100 次压力）', () async {
      final GuardProbeEnv env = await GuardProbeEnv.create(
        clock: () => DateTime(2026, 11, 9, 10, 30),
      );
      addTearDown(env.close);
      await env.seedPlant('p1');
      await env.seedBalance(100);

      // 塞一条昨天的待结算存档。
      await env.store.write(
        env.childId,
        _yesterdayPending(),
      );

      for (int i = 0; i < 100; i++) {
        final GuardResolveResult r = await env.guard.resolve();
        expect(r.needsExpire, isTrue);
      }
      expect((await env.store.read(env.childId)).dayKey, '2026-11-08');

      // 最终还是能正常结算。
      final GuardExpireOutcome out = await env.guard.expire();
      expect(out.stolenSun, 3);
      expect(await env.ledger.balance(), 97.0);
    });
  });
}

/// 构造「昨天待结算」状态（只在本文件用）。
GuardDayState _yesterdayPending() => const GuardDayState(
      dayKey: '2026-11-08',
      status: GuardDayStatus.pending,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
      sunStolen: 3,
    );
