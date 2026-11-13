/// 高级宝箱**领域派生**的验收测试（`deriveGuardChest` / `guardGrantWinSunOf`）。
///
/// 真源：`docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §3 / §4（含玄参
/// 2026-11-11 第九轮的三处覆写：种子 **5%**、碎片 **1~2 片**、其余不变）。
///
/// ## 🔴 期望值一律写字面量
/// 断言里出现的 0.20 / 0.10 / 0.05 / 1 / 2 **不许**替换成 `kGuardChest*`
/// 常量 —— 否则实现把 0.20 改成 0.02，测试会跟着一起变绿（`guard_math_test.dart`
/// 立下的同一条纪律）。
///
/// ## 覆盖清单
///  · 档位：免费档 10000 天**恒普通**（且「有普通」可达）；完整版 ≈30%（±2pp，B13.14）；
///  · 高级宝箱内：双券 ≈20%、碎片 ≈10%、种子 ≈5%（各 ±2pp，B13.14 口径）；
///  · 🔴 B13.20：高级宝箱**首张券**全券池 9 选 1 等概率（免费券只在这里出现）；
///    普通宝箱首张券 = 透传入参 drop；
///  · 碎片数量 1~2 各半；种子档位各半、物种落本档池内；
///  · **四类事件互不相关**（交叉命中率 ≈ 乘积，防通道耦合）；
///  · 首张无券 ⇒ 不出第二张券；免费档整箱为空；
///  · `GuardChestRoll` 的 `==` / `hashCode` 覆盖**全部六个字段**（含 B13.20
///    的 `firstDrop`，GuardRoll 的教训）；
///  · 同 `dayKey + childId` 幂等；JSON 往返与缺字段兜底；
///  · `guardGrantWinSunOf`：高级宝箱 ×2、普通不变、脏 `winSun = 0` 兜底。
library guard_chest_math_test;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardSeedSpeciesCommon, kGuardSeedSpeciesPremium;
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/services/guard_chest.dart';

/// 从 [start] 起的 [count] 个连续自然日 dayKey（独立实现，不复用被测代码）。
List<String> _dayKeys(DateTime start, int count) {
  final List<String> keys = <String>[];
  for (int i = 0; i < count; i++) {
    final DateTime d = DateTime(start.year, start.month, start.day + i);
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    keys.add('$y-$m-$dd');
  }
  return keys;
}

/// 造一条「今日已 resolve」的状态（只填判定用得到的字段）。
GuardDayState _state({
  GuardChestTier tier = GuardChestTier.normal,
  int winSun = 4,
}) =>
    GuardDayState(
      dayKey: '2026-11-11',
      status: GuardDayStatus.pending,
      chestTier: tier,
      winSun: winSun,
    );

void main() {
  // ───────────────────────── ① 档位 ─────────────────────────
  group('档位：免费档恒普通 / 完整版 ≈30% 高级（B13.14）', () {
    const int sampleCount = 10000;
    const String childId = 'child-chest-tier';

    test('🔴 免费档 10000 天**恒普通**（高级宝箱 0 个，且普通可达 ' 
        '$sampleCount 天）', () {
      int premium = 0;
      int normal = 0;
      for (final String day in _dayKeys(DateTime(2026, 1, 1), sampleCount)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: false,
          drop: GuardDropKind.waterVoucher,
        );
        if (roll.tier == GuardChestTier.premium) premium++;
        if (roll.tier == GuardChestTier.normal) normal++;
        // B13.20：普通宝箱首张券 = 透传入参 drop（免费档不掉免费券）。
        expect(roll.firstDrop, GuardDropKind.waterVoucher,
            reason: '$day 免费档普通宝箱首张券必须透传 drop');
        // 免费档：整箱为空（不掷任何附加通道）。
        expect(roll.bonusDrop, GuardDropKind.none,
            reason: '$day 免费档不允许第二张券');
        expect(roll.fragmentQty, 0, reason: '$day 免费档不允许碎片');
        expect(roll.seedKind, GuardSeedKind.none, reason: '$day 免费档不允许种子');
        expect(roll.seedSpeciesId, isNull, reason: '$day 免费档不允许种子');
      }
      expect(premium, 0,
          reason: '实测 $premium 天高级宝箱 vs 期望 **0**（免费档恒普通）');
      expect(normal, sampleCount, reason: '免费档每一天都是普通宝箱');
    });

    test('完整版 10000 天：高级宝箱 ≈30%（±2pp，B13.14 由 20% 上调），普通 ≈70%', () {
      int premium = 0;
      for (final String day in _dayKeys(DateTime(2027, 1, 1), sampleCount)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: GuardDropKind.waterVoucher,
        );
        if (roll.tier == GuardChestTier.premium) premium++;
      }
      final double actual = premium / sampleCount;
      expect((actual - 0.30).abs(), lessThan(0.02),
          reason: '实测高级宝箱率 ${(actual * 100).toStringAsFixed(2)}% vs 30%（B13.14）');
      // 🔴 可达性：防「把判据改成恒 normal」这类假绿。
      expect(premium, greaterThan(2500),
          reason: '10000 天里必须出现 >2500 个高级宝箱（否则档位分支不可达）');
    });

    test('同一 dayKey + childId：档位只看 isPremium（免费/完整版对照）', () {
      int premiumChestDays = 0;
      for (final String day in _dayKeys(DateTime(2027, 6, 1), 2000)) {
        final GuardChestRoll free = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: false,
          drop: GuardDropKind.waterVoucher,
        );
        final GuardChestRoll paid = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: GuardDropKind.waterVoucher,
        );
        expect(free.tier, GuardChestTier.normal, reason: '$day 免费档恒普通');
        if (paid.tier == GuardChestTier.premium) premiumChestDays++;
      }
      expect(premiumChestDays, greaterThan(500),
          reason: '2000 天里完整版必须出现 >500 天高级宝箱（可达性，30% 口径）');
    });
  });

  // ──────────────── ② 高级宝箱内容（概率 / 数量 / 档位）────────────────
  group('高级宝箱内容：双券 20% / 碎片 10%（1~2 片）/ 种子 5%（B13.14）', () {
    const int sampleCount = 40000;
    const String childId = 'child-chest-content';
    const GuardDropKind mainDrop = GuardDropKind.waterVoucher;

    late int premiumDays;
    late int bonusDays;
    late int fragmentDays;
    late int qtyOneDays;
    late int qtyTwoDays;
    late int seedDays;
    late int seedCommonDays;
    late int seedPremiumDays;
    late int bonusAndFragmentDays;
    late int seedAndFragmentDays;

    setUpAll(() {
      premiumDays = 0;
      bonusDays = 0;
      fragmentDays = 0;
      qtyOneDays = 0;
      qtyTwoDays = 0;
      seedDays = 0;
      seedCommonDays = 0;
      seedPremiumDays = 0;
      bonusAndFragmentDays = 0;
      seedAndFragmentDays = 0;
      for (final String day in _dayKeys(DateTime(2026, 3, 1), sampleCount)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: mainDrop,
        );
        if (roll.tier != GuardChestTier.premium) {
          // 普通宝箱：整箱为空（不掷附加通道）。
          expect(roll.hasAnyExtra, isFalse, reason: '$day 普通宝箱不该有附加项');
          continue;
        }
        premiumDays++;
        if (roll.hasBonusDrop) bonusDays++;
        if (roll.hasFragments) {
          fragmentDays++;
          if (roll.fragmentQty == 1) qtyOneDays++;
          if (roll.fragmentQty == 2) qtyTwoDays++;
        }
        if (roll.seedKind == GuardSeedKind.common) seedCommonDays++;
        if (roll.seedKind == GuardSeedKind.premium) seedPremiumDays++;
        if (roll.hasSeed) seedDays++;
        if (roll.hasBonusDrop && roll.hasFragments) bonusAndFragmentDays++;
        if (roll.hasSeed && roll.hasFragments) seedAndFragmentDays++;
      }
    });

    test('样本量自检：高级宝箱 ≈12000 天（否则后面的比例断言没有意义）', () {
      expect(premiumDays, greaterThan(10000));
      expect(premiumDays, lessThan(14000));
    });

    test('双 buff 券 ≈20%（±2pp，B13.14 由 10% 上调，且恒与主券不同种）', () {
      final double rate = bonusDays / premiumDays;
      expect((rate - 0.20).abs(), lessThan(0.02),
          reason: '实测 ${(rate * 100).toStringAsFixed(2)}% vs 20%');
      expect(bonusDays, greaterThan(0), reason: '双券分支必须可达');
    });

    test('植物碎片 ≈10%（±2pp，B13.14 由 5% 上调）', () {
      final double rate = fragmentDays / premiumDays;
      expect((rate - 0.10).abs(), lessThan(0.02),
          reason: '实测 ${(rate * 100).toStringAsFixed(2)}% vs 10%');
      expect(fragmentDays, greaterThan(0), reason: '碎片分支必须可达');
    });

    test('种子 ≈5%（±2pp，玄参覆写值，原设计 1%）', () {
      final double rate = seedDays / premiumDays;
      expect((rate - 0.05).abs(), lessThan(0.02),
          reason: '实测 ${(rate * 100).toStringAsFixed(2)}% vs 5%');
      expect(seedDays, greaterThan(0), reason: '种子分支必须可达');
    });

    test('碎片数量只可能是 1 或 2，且各占一半（±6pp）', () {
      expect(fragmentDays, greaterThan(200), reason: '样本量不足');
      expect(qtyOneDays + qtyTwoDays, fragmentDays,
          reason: '碎片数量必须恒为 1 或 2（不允许 0 / 3）');
      final double oneRate = qtyOneDays / fragmentDays;
      expect((oneRate - 0.50).abs(), lessThan(0.06),
          reason: '1 片占比实测 ${(oneRate * 100).toStringAsFixed(2)}% vs 50%');
      expect(qtyTwoDays, greaterThan(0),
          reason: '🔴 「1~2 片随机」必须真的会出 2 片（否则等于固定 1 片）');
      expect(qtyOneDays, greaterThan(0), reason: '必须真的会出 1 片');
    });

    test('种子档位各半（±6pp），物种落本档池内', () {
      expect(seedDays, greaterThan(200), reason: '样本量不足');
      expect(seedCommonDays + seedPremiumDays, seedDays,
          reason: '档位只能是 common 或 premium');
      final double eliteRate = seedPremiumDays / seedDays;
      expect((eliteRate - 0.50).abs(), lessThan(0.06),
          reason: '精英档占比实测 ${(eliteRate * 100).toStringAsFixed(2)}% vs 50%');
      expect(seedCommonDays, greaterThan(0));
      expect(seedPremiumDays, greaterThan(0));
    });

    test('物种恒在本档池内，且档位与物种不矛盾', () {
      for (final String day in _dayKeys(DateTime(2026, 5, 1), 20000)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: mainDrop,
        );
        if (roll.seedKind == GuardSeedKind.none) {
          expect(roll.seedSpeciesId, isNull, reason: '$day 没种子就不该有物种');
          continue;
        }
        expect(roll.seedSpeciesId, isNotNull, reason: '$day 有种子必须有物种');
        final List<String> pool = roll.seedKind == GuardSeedKind.premium
            ? kGuardSeedSpeciesPremium
            : kGuardSeedSpeciesCommon;
        expect(pool, contains(roll.seedSpeciesId),
            reason: '$day 物种 ${roll.seedSpeciesId} 不在 ${roll.seedKind.id} 池内');
        expect(roll.seedSpeciesId, isNot('species_sunflower'),
            reason: '🔴 向日葵被刻意排除（重复种子会把种子券降级成 3 片）');
      }
    });

    test('🔴 四类事件互不相关：交叉命中率 ≈ 乘积（不是「一条通道绑死」）', () {
      // 若双券与碎片共用一个 `u`，则「命中碎片的日子必然命中双券」⇒ 交叉率
      // 会等于 5%（= 碎片率），而不是 5% × 10% = 0.5%。
      final double fragAndBonusRate = bonusAndFragmentDays / premiumDays;
      expect((fragAndBonusRate - 0.02).abs(), lessThan(0.02),
          reason: '碎片∩双券 = ${(fragAndBonusRate * 100).toStringAsFixed(3)}% '
              'vs 2%（= 10% × 20%，B13.14 口径）');
      final double fragAndSeedRate = seedAndFragmentDays / premiumDays;
      expect((fragAndSeedRate - 0.005).abs(), lessThan(0.02),
          reason: '碎片∩种子 = ${(fragAndSeedRate * 100).toStringAsFixed(3)}% '
              'vs 0.5%（= 10% × 5%，B13.14 口径）');
      // 反向可达性：交叉**确实会发生**（否则上面的「≈乘积」也可能来自恒 0）。
      expect(bonusAndFragmentDays, greaterThan(0),
          reason: '200 天内必然出现「碎片 + 双券」同一天');
      expect(seedAndFragmentDays, greaterThan(0),
          reason: '200 天内必然出现「碎片 + 种子」同一天');
    });

    test('第二张券恒 ≠ 首张（B13.20：首张以重挑后的 firstDrop 为准），且恒为券档', () {
      int checked = 0;
      for (final String day in _dayKeys(DateTime(2026, 7, 1), 20000)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: mainDrop,
        );
        if (!roll.hasBonusDrop) continue;
        checked++;
        // 🔴 B13.20：高级宝箱首张券被 `chest_first_pick` 全池重挑，第二张
        //    「不同种」的排除对象是**重挑后的 firstDrop**，不是入参 mainDrop。
        expect(roll.bonusDrop, isNot(roll.firstDrop),
            reason: '$day 必须与首张（${roll.firstDrop.id}）不同种');
        expect(roll.bonusDrop.hasVoucher, isTrue, reason: '$day 第二张必须是券');
      }
      expect(checked, greaterThan(0), reason: '必须真的出现过第二张券');
    });

    test('🔴 首张无券 ⇒ 不出第二张券（判据 first != none 的不变式）', () {
      // B13.20 后高级宝箱首张恒被全池重挑成券，`first == none` 只在
      // **手工构造的入参/普通箱**里出现 —— 这里直接对拍判据本身：
      // 用普通箱透传（firstDrop = none）确认 hasBonusDrop 恒 false。
      for (final String day in _dayKeys(DateTime(2026, 9, 1), 2000)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: false,
          drop: GuardDropKind.none,
        );
        expect(roll.firstDrop, GuardDropKind.none, reason: '$day 透传 none');
        expect(roll.hasBonusDrop, isFalse,
            reason: '$day 首张无券就不该有第二张（判据 first != none）');
      }
    });
  });

  // ──────────────── ②b 高级宝箱首张券：全券池 9 选 1（B13.20）────────────────
  // 🔴 B13.20（玄参 2026-11-13）：「免费券只在高级宝箱」—— 首张券由
  //    `chest_first_pick` 通道从 9 种券（含 4 张免费券）**等概率**重挑。
  //    期望值写字面量 1/9，绝不引用池常量（防池子写漏测试跟着绿）。
  group('高级宝箱首张券：全券池 9 选 1 等概率（B13.20）', () {
    const int sampleCount = 40000;
    const String childId = 'child-chest-first-pick';
    const GuardDropKind mainDrop = GuardDropKind.waterVoucher;

    late Map<GuardDropKind, int> firstHits;
    late int premiumDays;
    late int normalDays;

    setUpAll(() {
      firstHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      premiumDays = 0;
      normalDays = 0;
      for (final String day in _dayKeys(DateTime(2028, 1, 1), sampleCount)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: childId,
          isPremium: true,
          drop: mainDrop,
        );
        if (roll.tier == GuardChestTier.premium) {
          premiumDays++;
          // 🔴 只统计高级箱的首券分布：普通箱是透传 mainDrop，
          //    计进来会把 waterVoucher 占比撑到 200%+。
          firstHits[roll.firstDrop] = firstHits[roll.firstDrop]! + 1;
        } else {
          normalDays++;
          // 普通宝箱：首张券 = 透传入参，绝不被全池重挑。
          expect(roll.firstDrop, mainDrop, reason: '$day 普通宝箱必须透传 drop');
          expect(roll.firstDrop.hasVoucher, isTrue,
              reason: '$day 付费档普通箱必掉券');
        }
      }
    });

    test('样本量自检：高级宝箱 ≈12000 天，普通箱 ≈28000 天（两分支都可达）', () {
      expect(premiumDays, greaterThan(10000));
      expect(premiumDays, lessThan(14000));
      expect(normalDays, greaterThan(25000),
          reason: '付费档普通宝箱 ≈70% 必须可达（否则档位分支假绿）');
    });

    test('高级宝箱首券恒非 none（全池 9 种、none 不在池内）', () {
      expect(firstHits[GuardDropKind.none], 0,
          reason: '高级宝箱首券不该是 none（实测 ${firstHits[GuardDropKind.none]}）');
    });

    test('9 种券各 ≈ 1/9 ≈ 11.1%（±2pp，期望写字面量）', () {
      // 1/9 ≈ 0.1111；±2pp 对 12000 样本约 7σ，既抓真偏差又不抖。
      const double expected = 1 / 9;
      for (final GuardDropKind k in GuardDropKind.values) {
        if (k == GuardDropKind.none) continue;
        final double rate = firstHits[k]! / premiumDays;
        expect((rate - expected).abs(), lessThan(0.02),
            reason: '${k.id} 首券占比实测 '
                '${(rate * 100).toStringAsFixed(2)}% vs '
                '${(expected * 100).toStringAsFixed(2)}%');
      }
    });

    test('🔴 四张免费券只从高级宝箱出来（首券全池可达性）', () {
      for (final GuardDropKind k in <GuardDropKind>[
        GuardDropKind.freeWater,
        GuardDropKind.freeFertilize,
        GuardDropKind.freeWater3,
        GuardDropKind.freeFertilize2,
      ]) {
        expect(firstHits[k]!, greaterThan(0),
            reason: '${k.id} 在 $premiumDays 个高级宝箱里必须出过（否则免费券不可达）');
      }
    });
  });

  // ───────────────── ③ 阳光翻倍唯一派生口 ─────────────────
  group('guardGrantWinSunOf：高级宝箱 ×2，其余不变', () {
    test('高级宝箱 + 基础 4 ⇒ 8', () {
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.premium, winSun: 4)),
        8,
      );
    });

    test('普通宝箱 + 基础 4 ⇒ 4（一分不多给）', () {
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.normal, winSun: 4)),
        4,
      );
    });

    test('高级宝箱 + 基础 3 ⇒ 6；普通宝箱 + 基础 5 ⇒ 5', () {
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.premium, winSun: 3)),
        6,
      );
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.normal, winSun: 5)),
        5,
      );
    });

    test('脏存档 winSun = 0：普通兜底 5、高级兜底 10', () {
      expect(guardGrantWinSunOf(_state(winSun: 0)), 5);
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.premium, winSun: 0)),
        10,
      );
    });

    test('负数 winSun 同样兜底（绝不出现负到账）', () {
      expect(guardGrantWinSunOf(_state(winSun: -3)), 5);
      expect(
        guardGrantWinSunOf(_state(tier: GuardChestTier.premium, winSun: -3)),
        10,
      );
    });
  });

  // ───────────────────── ④ 幂等与相等性 ─────────────────────
  group('确定性 / 相等性 / JSON', () {
    test('同一 dayKey + childId 连调 100 次，结果逐字段一致', () {
      const String dayKey = '2026-11-11';
      const String childId = 'child-idem';
      final GuardChestRoll first = deriveGuardChest(
        dayKey: dayKey,
        childId: childId,
        isPremium: true,
        drop: GuardDropKind.waterVoucher,
      );
      for (int i = 0; i < 100; i++) {
        final GuardChestRoll again = deriveGuardChest(
          dayKey: dayKey,
          childId: childId,
          isPremium: true,
          drop: GuardDropKind.waterVoucher,
        );
        expect(again, first, reason: '第 $i 次 iteration');
        expect(again.hashCode, first.hashCode, reason: '第 $i 次 iteration');
        expect(again.tier, first.tier);
        expect(again.firstDrop, first.firstDrop);
        expect(again.bonusDrop, first.bonusDrop);
        expect(again.fragmentQty, first.fragmentQty);
        expect(again.seedKind, first.seedKind);
        expect(again.seedSpeciesId, first.seedSpeciesId);
      }
    });

    test('不同 childId / 不同天 ⇒ 结果不全相同（seed 真的吃了入参）', () {
      final Set<String> signatures = <String>{};
      int withExtras = 0;
      for (final String day in _dayKeys(DateTime(2026, 11, 1), 2000)) {
        final GuardChestRoll roll = deriveGuardChest(
          dayKey: day,
          childId: 'child-vary',
          isPremium: true,
          drop: GuardDropKind.waterVoucher,
        );
        signatures.add(roll.toString());
        if (roll.hasAnyExtra) withExtras++;
      }
      expect(signatures.length, greaterThan(3),
          reason: '2000 天至少得到 4 种不同结果，否则派生没吃入参');
      expect(withExtras, greaterThan(0),
          reason: '2000 天里必须真的出现附加奖励（否则结果全是「空箱」）');
    });

    test('🔴 == / hashCode **覆盖全部六个字段**（GuardRoll 的教训；B13.20 起 +firstDrop）', () {
      const GuardChestRoll base = GuardChestRoll(
        tier: GuardChestTier.premium,
        firstDrop: GuardDropKind.waterVoucher,
        bonusDrop: GuardDropKind.laborVoucher,
        fragmentQty: 2,
        seedKind: GuardSeedKind.premium,
        seedSpeciesId: 'species_lotus',
      );
      expect(base, base.copyWith());
      expect(base.hashCode, base.copyWith().hashCode);

      final List<GuardChestRoll> variants = <GuardChestRoll>[
        base.copyWith(tier: GuardChestTier.normal),
        base.copyWith(firstDrop: GuardDropKind.freeWater),
        base.copyWith(firstDrop: GuardDropKind.none),
        base.copyWith(bonusDrop: GuardDropKind.freeWater),
        base.copyWith(bonusDrop: GuardDropKind.none),
        base.copyWith(fragmentQty: 1),
        base.copyWith(seedKind: GuardSeedKind.common),
        base.copyWith(seedSpeciesId: 'species_rose'),
        base.copyWith(clearSeedSpecies: true),
      ];
      for (final GuardChestRoll v in variants) {
        expect(v, isNot(base), reason: '变体必须与基准不等：$v');
        expect(v.hashCode, isNot(base.hashCode),
            reason: 'hashCode 也必须跟着字段变：$v');
      }
    });

    test('JSON 往返逐字段相等', () {
      const GuardChestRoll roll = GuardChestRoll(
        tier: GuardChestTier.premium,
        firstDrop: GuardDropKind.freeWater3,
        bonusDrop: GuardDropKind.freeFertilize,
        fragmentQty: 1,
        seedKind: GuardSeedKind.common,
        seedSpeciesId: 'species_rose',
      );
      final GuardChestRoll decoded = GuardChestRoll.fromJson(
        jsonDecode(jsonEncode(roll.toJson())) as Map<String, Object?>,
      );
      expect(decoded, roll);
      expect(decoded.hashCode, roll.hashCode);
      expect(decoded.firstDrop, GuardDropKind.freeWater3,
          reason: 'firstDrop 必须随 JSON 往返（B13.20 新键 firstDrop）');
    });

    test('JSON 缺字段 / 脏数据一律兜底，绝不抛异常', () {
      final GuardChestRoll empty = GuardChestRoll.fromJson(<String, Object?>{});
      expect(empty.tier, GuardChestTier.normal);
      expect(empty.firstDrop, GuardDropKind.none,
          reason: 'B13.20 新键 firstDrop 缺失 → none');
      expect(empty.bonusDrop, GuardDropKind.none);
      expect(empty.fragmentQty, 0);
      expect(empty.seedKind, GuardSeedKind.none);
      expect(empty.seedSpeciesId, isNull);

      final GuardChestRoll dirty = GuardChestRoll.fromJson(<String, Object?>{
        'tier': 'ultra', // 未知线名 → normal
        'firstDrop': 42, // 非字符串 → none
        'bonusDrop': 42, // 非字符串 → none
        'fragmentQty': -7, // 负片数 → 0
        'seedKind': 'none',
        'seedSpeciesId': 'species_rose', // 档位 none ⇒ 物种强制 null
      });
      expect(dirty.tier, GuardChestTier.normal);
      expect(dirty.firstDrop, GuardDropKind.none);
      expect(dirty.bonusDrop, GuardDropKind.none);
      expect(dirty.fragmentQty, 0);
      expect(dirty.seedKind, GuardSeedKind.none);
      expect(dirty.seedSpeciesId, isNull);
    });

    test('empty 常量 = 「什么都没有的普通宝箱」', () {
      expect(GuardChestRoll.empty.tier, GuardChestTier.normal);
      expect(GuardChestRoll.empty.hasAnyExtra, isFalse);
      expect(GuardChestRoll.empty, const GuardChestRoll());
    });
  });
}
