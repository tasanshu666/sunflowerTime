/// 花园守卫领域纯函数的验收测试（PRD v2 §11 的 A6 / A7 / A10 / A11 / A12 / A13
/// 全部在这一层跑绿）。
///
/// ## 为什么期望值一律写死
/// 🔴 期望值**不许**从实现里引 `kGuard*` 常量反推 —— 那样实现改错了测试也一起变绿。
/// 本文件所有阈值（0.45 / 0.05 / 6 / 15 / 3.525 …）都是 PRD 表上的**字面量**。
///
/// ## 覆盖清单
///  · 确定性：同 seed 100 次逐位一致（防偷偷用 `Random`）；跨 childId / 跨天不同；
///  · 分布：10000 天，3 种贼 + 6 档掉落与 PRD 表误差 < ±1.5 个百分点；
///  · 🔴 掉落层第二张券（Guard-B13.11）：**恒 none**（两档都是）—— 10% 双券已
///    迁至高级宝箱（分布断言见 `guard_chest_math_test.dart`）；本文件保留
///    「掉落层不再产生第二张券」+「首张券仍按档位分表」两组可达性断言；
///  · 成长扣减：3% / 5% 封顶 / 不为负 / **开花株免疫** / **阶段不回退** / 死株跳过；
///  · 券节省：5 种券各算对；浇水 / 劳动券当日不限次（B13.4）；免费券只算单株。
library guard_math_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart'
    show kGuardWinSunNoItem;
import 'package:sunflower_time/core/utils/stable_hash.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/guard_math.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

/// 造一株植物（只填判定用得到的字段）。
Plant _plant({
  PlantStatus status = PlantStatus.growing,
  PlantStage stage = PlantStage.seed,
  double progress = 0.5,
  String id = 'plant-1',
}) {
  return Plant(
    id: id,
    speciesId: 'sunflower',
    potIndex: 0,
    stage: stage,
    stageStartedAt: DateTime(2026, 11, 1, 8),
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: DateTime(2026, 10, 1, 8),
    bloomedAt: status == PlantStatus.bloomed ? DateTime(2026, 11, 6, 8) : null,
  );
}

/// `yyyy-MM-dd`（零填充，与实现无关的独立实现，避免「用被测代码造输入」）。
String _dayKey(DateTime d) {
  final String y = d.year.toString().padLeft(4, '0');
  final String m = d.month.toString().padLeft(2, '0');
  final String dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// 从 [start] 起的 [count] 个连续自然日 dayKey。
List<String> _dayKeys(DateTime start, int count) {
  final List<String> keys = <String>[];
  for (int i = 0; i < count; i++) {
    keys.add(_dayKey(DateTime(start.year, start.month, start.day + i)));
  }
  return keys;
}

void main() {
  // ─────────────────────────── 确定性 ───────────────────────────
  group('确定性派生（禁 Random）', () {
    test('同一 dayKey + childId 连调 100 次，结果逐字段完全一致', () {
      const String dayKey = '2026-11-08';
      const String childId = 'child-a';
      final GuardRoll first = deriveGuardRoll(dayKey: dayKey, childId: childId);
      for (int i = 0; i < 100; i++) {
        final GuardRoll again =
            deriveGuardRoll(dayKey: dayKey, childId: childId);
        expect(again.thief, first.thief, reason: '第 $i 次 iteration');
        expect(again.sunLoss, first.sunLoss, reason: '第 $i 次 iteration');
        expect(again.growthLossPercent, first.growthLossPercent,
            reason: '第 $i 次 iteration');
        expect(again.drop, first.drop, reason: '第 $i 次 iteration');
        expect(again.winSun, first.winSun, reason: '第 $i 次 iteration');
        // 顺带锁住 == / hashCode（第二批「跳过 = 看完」的实现会依赖它）。
        expect(again, first);
        expect(again.hashCode, first.hashCode);
      }
    });

    test('三个派生入口（贼 / 掉落 / 整体）各自也是纯函数', () {
      const String dayKey = '2026-11-09';
      const String childId = 'child-a';
      expect(GuardThiefKind.roll(dayKey: dayKey, childId: childId),
          GuardThiefKind.roll(dayKey: dayKey, childId: childId));
      expect(GuardDropKind.roll(dayKey: dayKey, childId: childId),
          GuardDropKind.roll(dayKey: dayKey, childId: childId));
    });

    test('不同 childId → 结果不能全部相同（防串档）', () {
      final List<String> days = _dayKeys(DateTime(2026, 1, 1), 40);
      int differed = 0;
      for (final String day in days) {
        final GuardRoll a = deriveGuardRoll(dayKey: day, childId: 'child-a');
        final GuardRoll b = deriveGuardRoll(dayKey: day, childId: 'child-b');
        if (a != b) differed++;
      }
      expect(differed, greaterThanOrEqualTo(30),
          reason: '两个 childId 在 40 天里至少 30 天结果不同，否则 seed 没吃 childId');
    });

    test('跨天 → 结果不能全部相同', () {
      final List<String> days = _dayKeys(DateTime(2026, 3, 1), 40);
      final Set<String> distinct = <String>{
        for (final String day in days)
          deriveGuardRoll(dayKey: day, childId: 'child-a').toString(),
      };
      expect(distinct.length, greaterThan(1));
    });

    test('seed 通道隔离：同一 dayKey 下五个通道的均匀值互不相同', () {
      const String dayKey = '2026-11-08';
      const String childId = 'child-a';
      const String salt = '|guard|v2';
      final Set<double> values = <double>{
        for (final String channel in <String>[
          'thief',
          'drop',
          'sun',
          'growth',
          'win',
        ])
          deterministicUniform(
            dayKey: dayKey,
            childId: childId,
            salt: salt,
            channel: channel,
          ),
      };
      expect(values.length, 5, reason: '五个通道必须给出五个不同的 u，否则字段会绑死');
    });
  });

  // ─────────────────────────── 概率分布 ───────────────────────────
  // 🔴 B13.20（玄参 2026-11-13 拍板）：**统一券池制**取代 B13.5 两张概率表 ——
  //    免费档先过 30% 无道具闸门，再从普通宝箱券池（5 种非免费券）**等概率**挑；
  //    免费券只进高级宝箱（掉落层恒 0）。
  //    旧 B13.19 8 档表 [22/14/11/8/5/7/3/30] 已退役为历史口径。
  group('概率分布 · 免费档（10000 天，误差 < ±1.5 个百分点）', () {
    const int sampleCount = 10000;
    const double tolerance = 0.015;

    late Map<GuardThiefKind, int> thiefHits;
    late Map<GuardDropKind, int> dropHits;

    setUpAll(() {
      thiefHits = <GuardThiefKind, int>{
        for (final GuardThiefKind k in GuardThiefKind.values) k: 0,
      };
      dropHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      final List<String> days = _dayKeys(DateTime(2026, 1, 1), sampleCount);
      for (final String day in days) {
        final GuardRoll roll =
            deriveGuardRoll(dayKey: day, childId: 'child-dist');
        thiefHits[roll.thief] = thiefHits[roll.thief]! + 1;
        dropHits[roll.drop] = dropHits[roll.drop]! + 1;
      }
    });

    test('馋光鼠 ≈ 45%', () {
      final double actual = thiefHits[GuardThiefKind.sunRat]! / sampleCount;
      expect((actual - 0.45).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs PRD 45%');
    });

    test('食叶虫 ≈ 45%', () {
      final double actual = thiefHits[GuardThiefKind.leafBug]! / sampleCount;
      expect((actual - 0.45).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs PRD 45%');
    });

    test('贪婪鼬 ≈ 10%', () {
      final double actual = thiefHits[GuardThiefKind.sneakThief]! / sampleCount;
      expect((actual - 0.10).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs PRD 10%');
    });

    test('浇水券 ≈ 14%（统一券池等概率 1/5 × 70%）', () {
      final double actual = dropHits[GuardDropKind.waterVoucher]! / sampleCount;
      expect((actual - 0.14).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 免费档 14%');
    });

    test('劳动券 ≈ 14%（统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.laborVoucher]! / sampleCount;
      expect((actual - 0.14).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 免费档 14%');
    });

    test('施肥券 ≈ 14%（统一券池等概率）', () {
      final double actual =
          dropHits[GuardDropKind.fertilizeVoucher]! / sampleCount;
      expect((actual - 0.14).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 免费档 14%');
    });

    test('专注加餐券 ≈ 14%（B13.20 新券 · 统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.focusMeal]! / sampleCount;
      expect((actual - 0.14).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 免费档 14%');
    });

    test('专注放大券 ≈ 14%（B13.20 新券 · 统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.focusBoost]! / sampleCount;
      expect((actual - 0.14).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 免费档 14%');
    });

    test('四种免费券 = 0%（B13.20：普通宝箱不掉免费券，只进高级宝箱）', () {
      // 期望值写字面量 0，不用 spec.rate 去读 —— 否则实现把池子写漏了测试会跟绿。
      expect(dropHits[GuardDropKind.freeWater], 0,
          reason: '免费浇水券实测出现 ${dropHits[GuardDropKind.freeWater]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeFertilize], 0,
          reason: '免费施肥券实测出现 ${dropHits[GuardDropKind.freeFertilize]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeWater3], 0,
          reason: '免费浇水×3 实测出现 ${dropHits[GuardDropKind.freeWater3]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeFertilize2], 0,
          reason: '免费施肥×2 实测出现 ${dropHits[GuardDropKind.freeFertilize2]} 次 vs 期望 0');
    });

    test('无道具 ≈ 30%（闸门常量 kGuardDropNothingRateFree）', () {
      final double actual = dropHits[GuardDropKind.none]! / sampleCount;
      expect((actual - 0.30).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs 30% 无道具闸门');
    });

    test('全部档位合计 = 10000（没有漏统计的档）', () {
      int total = 0;
      for (final int v in dropHits.values) {
        total += v;
      }
      expect(total, sampleCount);
    });
  });

  // 🔴 B13.5 付费档：none=0%（必出券），其余按付费表。
  group('概率分布 · 付费档（10000 天，误差 < ±1.5 个百分点）', () {
    const int sampleCount = 10000;
    const double tolerance = 0.015;

    late Map<GuardDropKind, int> dropHits;
    late Map<GuardDropKind, int> bonusHits;

    setUpAll(() {
      dropHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      bonusHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      final List<String> days = _dayKeys(DateTime(2026, 1, 1), sampleCount);
      for (final String day in days) {
        final GuardRoll roll = deriveGuardRoll(
          dayKey: day,
          childId: 'child-dist-premium',
          isPremium: true,
        );
        dropHits[roll.drop] = dropHits[roll.drop]! + 1;
        // ignore: deprecated_member_use_from_same_package
        bonusHits[roll.bonusDrop] = bonusHits[roll.bonusDrop]! + 1;
      }
    });

    test('无道具 = 0%（付费必出券）', () {
      expect(dropHits[GuardDropKind.none], 0,
          reason: '付费档 none 概率 = 0.0，10000 天一次都不该出现');
    });

    test('浇水券 ≈ 20%（B13.20 统一券池：无闸门 5 券等概率）', () {
      final double actual = dropHits[GuardDropKind.waterVoucher]! / sampleCount;
      expect((actual - 0.20).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 付费档 20%');
    });

    test('劳动券 ≈ 20%（统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.laborVoucher]! / sampleCount;
      expect((actual - 0.20).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 付费档 20%');
    });

    test('施肥券 ≈ 20%（统一券池等概率）', () {
      final double actual =
          dropHits[GuardDropKind.fertilizeVoucher]! / sampleCount;
      expect((actual - 0.20).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 付费档 20%');
    });

    test('专注加餐券 ≈ 20%（B13.20 新券 · 统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.focusMeal]! / sampleCount;
      expect((actual - 0.20).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 付费档 20%');
    });

    test('专注放大券 ≈ 20%（B13.20 新券 · 统一券池等概率）', () {
      final double actual = dropHits[GuardDropKind.focusBoost]! / sampleCount;
      expect((actual - 0.20).abs(), lessThan(tolerance),
          reason: '实测 ${(actual * 100).toStringAsFixed(2)}% vs B13.20 付费档 20%');
    });

    test('四种免费券 = 0%（B13.20：掉落层/普通宝箱不掉免费券）', () {
      // 免费券只出现在高级宝箱首券（chest_first_pick 全池重挑），
      // 掉落层派生的 GuardRoll.drop 恒不含它们 —— 字面量 0 钉死。
      expect(dropHits[GuardDropKind.freeWater], 0,
          reason: '免费浇水券实测出现 ${dropHits[GuardDropKind.freeWater]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeFertilize], 0,
          reason: '免费施肥券实测出现 ${dropHits[GuardDropKind.freeFertilize]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeWater3], 0,
          reason: '免费浇水×3 实测出现 ${dropHits[GuardDropKind.freeWater3]} 次 vs 期望 0');
      expect(dropHits[GuardDropKind.freeFertilize2], 0,
          reason: '免费施肥×2 实测出现 ${dropHits[GuardDropKind.freeFertilize2]} 次 vs 期望 0');
    });

    test('🔴 掉落层不再产生第二张券：bonusDrop 恒 none（完成版也一样）', () {
      int voucherDays = 0;
      int bonusDays = 0;
      for (final GuardDropKind k in dropHits.keys) {
        voucherDays += dropHits[k]!;
      }
      voucherDays -= dropHits[GuardDropKind.none]!;
      for (final GuardDropKind k in bonusHits.keys) {
        if (k == GuardDropKind.none) continue;
        bonusDays += bonusHits[k]!;
      }
      expect(voucherDays, sampleCount,
          reason: '付费档每天都是券日（none=0）');
      // Guard-B13.11（玄参 2026-11-11 第九轮）：第二张券搬进高级宝箱 ⇒
      // **掉落层恒 none**。双券的分布断言迁到 `guard_chest_math_test.dart`
      // （那里按「高级宝箱内 10%」采样）。
      expect(bonusDays, 0,
          reason: '🔴 实测 $bonusDays 天第二张券 vs 期望 **0**'
              '（掉落层已不再产生第二张券，见 Guard-B13.11）');
      expect(bonusHits[GuardDropKind.none], sampleCount,
          reason: '全部落 none');
    });
  });

  // 🔴 Guard-B13.11（玄参 2026-11-11 第九轮）：第二张券**迁至高级宝箱** ⇒
  //    本组口径从「免费档恒 0、完整版 ≈10%」再收一步：
  //    **掉落层的 `bonusDrop` 两档都恒 none**（免费 10000 天 + 完整版对照见下一组）。
  //    双券的分布断言整体迁到 `test/guard/guard_chest_math_test.dart`
  //    （「高级宝箱内 10%」）。
  //    期望值一律写字面量（0 / 0.50），绝不用 `kGuardDropDualChance` 去乘
  //    ——否则实现把 gate 写反了，测试会跟着一起变绿。
  group('掉落层 bonusDrop 恒 none（免费档 10000 天）', () {
    const int sampleCount = 10000;
    late Map<GuardDropKind, int> dropHits;
    late Map<GuardDropKind, int> bonusHits;

    setUpAll(() {
      dropHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      bonusHits = <GuardDropKind, int>{
        for (final GuardDropKind k in GuardDropKind.values) k: 0,
      };
      final List<String> days = _dayKeys(DateTime(2026, 2, 1), sampleCount);
      for (final String day in days) {
        // isPremium 缺省 = false，显式写出来，防将来默认值被改。
        final GuardRoll roll = deriveGuardRoll(
          dayKey: day,
          childId: 'child-bonus',
          isPremium: false,
        );
        dropHits[roll.drop] = dropHits[roll.drop]! + 1;
        // ignore: deprecated_member_use_from_same_package
        bonusHits[roll.bonusDrop] = bonusHits[roll.bonusDrop]! + 1;
      }
    });

    test('第二张券恒为 none（10000 天 0 次 · 掉落层已不再产生）', () {
      int bonusDays = 0;
      for (final MapEntry<GuardDropKind, int> e in bonusHits.entries) {
        if (e.key != GuardDropKind.none) bonusDays += e.value;
      }
      expect(bonusDays, 0,
          reason: '实测出现 $bonusDays 天第二张券 vs 期望 **0**'
              '（掉落层不再产生第二张券，Guard-B13.11 迁至高级宝箱）');
      // 显式再钉一次「全落 none」：防有人把 bonusHits 统计口径改坏。
      expect(bonusHits[GuardDropKind.none], sampleCount);
    });

    test('免费档仍有首张券（≈70% 券日 —— 不是「免费档永远无券」）', () {
      final int voucherDays = sampleCount - dropHits[GuardDropKind.none]!;
      final double actual = voucherDays / sampleCount;
      // 期望值 0.70 是 B13.19 免费表的字面量（无道具 30%，玄参「50% 保底太高」）。
      expect((actual - 0.70).abs(), lessThan(0.02),
          reason: '实测券日 ${(actual * 100).toStringAsFixed(2)}% vs 70%');
      expect(voucherDays, greaterThan(0), reason: '券日必须可达（否则本组假绿）');
    });

    test('券日也不出第二张（逐日对拍：drop != none ⇒ bonus == none）', () {
      int voucherDays = 0;
      final List<String> days = _dayKeys(DateTime(2026, 2, 1), sampleCount);
      for (final String day in days) {
        final GuardRoll roll = deriveGuardRoll(
          dayKey: day,
          childId: 'child-bonus',
          isPremium: false,
        );
        if (roll.drop.hasVoucher) voucherDays++;
        // ignore: deprecated_member_use_from_same_package
        expect(roll.bonusDrop, GuardDropKind.none,
            reason: '$day：掉落层不再产生第二张券（主券 ${roll.drop.id}）');
      }
      expect(voucherDays, greaterThan(0), reason: '10000 天里必须有券日');
    });
  });

  // ── 跨档对照（🔴 防「改坏成永远 none」的假绿）─────────────────────────────
  //
  // 🔴 Guard-B13.11 后本组的判据**反转了方向**：不再是「免费恒 none / 完整版
  //    ≈10%」，而是「**两档都恒 none**」+「首张券仍按档位分表（免费 70% 券日 /
  //    完整版必掉券）」—— 后者是唯一能证明「跑的不是同一张免费表」的可达性断言。
  //    双券的「确实会出」可达性由 `guard_chest_math_test.dart` 的高级宝箱组承担。
  group('跨档对照 · 掉落层 bonusDrop 两档都恒 none', () {
    const int sampleCount = 10000;

    test('同一 dayKey+childId：isPremium:false / true 的 bonusDrop 都恒 none', () {
      int freeVoucherDays = 0;
      int premiumVoucherDays = 0;
      final List<String> days = _dayKeys(DateTime(2026, 3, 1), sampleCount);
      for (final String day in days) {
        final GuardRoll free = deriveGuardRoll(
          dayKey: day,
          childId: 'child-cross-tier',
          isPremium: false,
        );
        final GuardRoll premium = deriveGuardRoll(
          dayKey: day,
          childId: 'child-cross-tier',
          isPremium: true,
        );
        // ignore: deprecated_member_use_from_same_package
        expect(free.bonusDrop, GuardDropKind.none, reason: '$day 免费档');
        // ignore: deprecated_member_use_from_same_package
        expect(premium.bonusDrop, GuardDropKind.none,
            reason: '$day 完整版档（掉落层也不再产生第二张券）');
        if (free.drop.hasVoucher) freeVoucherDays++;
        if (premium.drop.hasVoucher) premiumVoucherDays++;
      }
      // 🔴 可达性：两档的首张券表必须**不同**（免费 ≈70% 券日 / 完整版 100%）。
      final double freeRate = freeVoucherDays / sampleCount;
      expect((freeRate - 0.70).abs(), lessThan(0.02),
          reason: '免费档券日实测 ${(freeRate * 100).toStringAsFixed(2)}% vs 70%');
      expect(premiumVoucherDays, sampleCount,
          reason: '完整版档必掉券（none 概率 = 0）');
    });

    test('完整版逐日对拍：首张恒为券，第二张恒 none', () {
      final List<String> days = _dayKeys(DateTime(2026, 4, 1), 2000);
      for (final String day in days) {
        final GuardRoll roll = deriveGuardRoll(
          dayKey: day,
          childId: 'child-cross-tier',
          isPremium: true,
        );
        expect(roll.drop, isNot(GuardDropKind.none), reason: '$day 必掉券');
        // ignore: deprecated_member_use_from_same_package
        expect(roll.bonusDrop, GuardDropKind.none, reason: day);
      }
    });
  });

  // ─────────────────────── 派生字段自洽 ───────────────────────
  group('派生字段自洽（偷什么 / 偷多少 / 保底阳光）', () {
    test('不偷阳光的贼 → sunLoss 恒 0；偷阳光的贼 → 落在 1..3', () {
      for (final String day in _dayKeys(DateTime(2026, 5, 1), 500)) {
        final GuardRoll roll = deriveGuardRoll(dayKey: day, childId: 'child-a');
        if (roll.thief.stealsSun) {
          expect(roll.sunLoss, inInclusiveRange(1, 3), reason: day);
        } else {
          expect(roll.sunLoss, 0, reason: day);
        }
      }
    });

    test(
        '不偷成长的贼 → growthLossPercent 恒 0；食叶虫落在 1%~3%；'
        '贪婪鼬落在 1%~5%', () {
      for (final String day in _dayKeys(DateTime(2026, 5, 1), 800)) {
        final GuardRoll roll = deriveGuardRoll(dayKey: day, childId: 'child-a');
        if (!roll.thief.stealsGrowth) {
          expect(roll.growthLossPercent, 0, reason: day);
          continue;
        }
        expect(roll.growthLossPercent, greaterThanOrEqualTo(0.01), reason: day);
        if (roll.thief == GuardThiefKind.leafBug) {
          expect(roll.growthLossPercent, lessThanOrEqualTo(0.03), reason: day);
        } else {
          expect(roll.growthLossPercent, lessThanOrEqualTo(0.05), reason: day);
        }
      }
    });

    test('无道具档 → 必得阳光固定取区间上限（R1；B5b 区间 3~5 ⇒ 5）', () {
      int checked = 0;
      for (final String day in _dayKeys(DateTime(2026, 1, 1), 2000)) {
        final GuardRoll roll = deriveGuardRoll(dayKey: day, childId: 'child-a');
        if (roll.drop != GuardDropKind.none) continue;
        checked++;
        expect(roll.winSun, kGuardWinSunNoItem, reason: day);
      }
      expect(checked, greaterThan(0), reason: '2000 天里必须出现过无道具档');
    });

    test('有券档 → 必得阳光落在 3..5（B5b 玄参拍板，原 1..3）', () {
      for (final String day in _dayKeys(DateTime(2026, 1, 1), 2000)) {
        final GuardRoll roll = deriveGuardRoll(dayKey: day, childId: 'child-a');
        if (roll.drop == GuardDropKind.none) continue;
        expect(roll.winSun, inInclusiveRange(3, 5), reason: day);
      }
    });

    test('贪婪鼬命中全园；食叶虫只挑 1 株；馋光鼠不碰植物', () {
      expect(GuardThiefKind.sneakThief.spec.hitsEveryPlant, isTrue);
      expect(GuardThiefKind.leafBug.spec.hitsEveryPlant, isFalse);
      expect(GuardThiefKind.leafBug.spec.targetsSingleRandomPlant, isTrue);
      expect(GuardThiefKind.sunRat.spec.stealsGrowth, isFalse);
      expect(GuardThiefKind.sunRat.spec.stealsSun, isTrue);
      expect(GuardThiefKind.leafBug.spec.stealsSun, isFalse);
    });

    test('权重表与规格表下标一一对应（0.45 / 0.45 / 0.10）', () {
      expect(GuardThiefKind.sunRat.weight, 0.45);
      expect(GuardThiefKind.leafBug.weight, 0.45);
      expect(GuardThiefKind.sneakThief.weight, 0.10);
      double sum = 0;
      for (final GuardThiefKind kind in GuardThiefKind.values) {
        sum += kind.weight;
      }
      expect(sum, closeTo(1.0, 1e-12));
    });

    test('掉落概率表合计 = 1.0 且各档概率/面值符合 PRD §3.7（B13.20 统一券池）', () {
      double sum = 0;
      for (final GuardDropKind kind in GuardDropKind.values) {
        sum += kind.rate;
      }
      // B13.20 rate 语义 = 免费档全口径：5×0.14（券池）+ 4×0（免费券）+ 0.30（none）。
      expect(sum, closeTo(1.0, 1e-12));

      // 🔴 B13.20：spec.rate 与统一券池三处同源（PRD §3.7 / kGuardDropRatePerVoucherFree
      // / 本表）。期望值写字面量，绝不引用常量去乘 —— 否则实现改错了测试跟着绿。
      expect(GuardDropKind.waterVoucher.rate, 0.14);
      expect(GuardDropKind.waterVoucher.faceValue, 5.5);
      expect(GuardDropKind.laborVoucher.rate, 0.14);
      expect(GuardDropKind.laborVoucher.faceValue, 2.5);
      expect(GuardDropKind.fertilizeVoucher.rate, 0.14);
      expect(GuardDropKind.fertilizeVoucher.faceValue, 2.0);
      expect(GuardDropKind.focusMeal.rate, 0.14,
          reason: 'B13.20 新券：普通宝箱券池成员');
      expect(GuardDropKind.focusMeal.faceValue, 10.0,
          reason: 'B13.20：专注加餐券面值 = 10 ☀');
      expect(GuardDropKind.focusBoost.rate, 0.14,
          reason: 'B13.20 新券：普通宝箱券池成员');
      expect(GuardDropKind.focusBoost.faceValue, 10.0,
          reason: 'B13.20：专注放大券面值 = (8+12)/2 中点');
      // 四种免费券：普通宝箱不掉 ⇒ 免费档全口径概率 = 0（真实概率 1/9 在高级宝箱
      // 全池，由派生层等概率保证，不在这里重复记账）。
      expect(GuardDropKind.freeWater.rate, 0);
      expect(GuardDropKind.freeWater.faceValue, 5.0);
      expect(GuardDropKind.freeFertilize.rate, 0);
      expect(GuardDropKind.freeFertilize.faceValue, 10.0);
      expect(GuardDropKind.freeWater3.rate, 0);
      expect(GuardDropKind.freeWater3.faceValue, 15.0,
          reason: '3 × 一盆浇水标价（kPlantWaterCost=5）');
      expect(GuardDropKind.freeFertilize2.rate, 0);
      expect(GuardDropKind.freeFertilize2.faceValue, 20.0,
          reason: '2 × 一盆施肥标价（kPlantFertilizeCost=10）');
      expect(GuardDropKind.none.rate, 0.30);
      expect(GuardDropKind.none.faceValue, 0.0);
    });

    test('面值期望 E[D] = 4.20 ☀（B13.20 统一后的 PRD §5.1 那笔账）', () {
      // 0.14 × (5.5 + 2.5 + 2.0 + 10 + 10) + 0.30 × 0 = 0.14 × 30 = 4.20。
      double expected = 0;
      for (final GuardDropKind kind in GuardDropKind.values) {
        expected += kind.rate * kind.faceValue;
      }
      expect(expected, closeTo(4.20, 1e-12));
    });

    test('「免费」四档是仅有的单株限定档（防整批免费；B13.19 起含 ×3/×2 版）', () {
      for (final GuardDropKind kind in GuardDropKind.values) {
        final bool shouldBeSingle = kind == GuardDropKind.freeWater ||
            kind == GuardDropKind.freeFertilize ||
            kind == GuardDropKind.freeWater3 ||
            kind == GuardDropKind.freeFertilize2;
        expect(kind.singlePotOnly, shouldBeSingle, reason: kind.id);
      }
    });
  });

  // ─────────────────────── 成长扣减 ───────────────────────
  group('applyGrowthTheft：封顶 / 不为负 / 阶段不回退', () {
    test('扣 3% → progress 1.0 变 0.97', () {
      final Plant plant = _plant(progress: 1.0);
      final Plant after = applyGrowthTheft(plant, 0.03);
      expect(after.growthProgress, closeTo(0.97, 1e-12));
    });

    test('单株单日封顶 5%：传 20% 只扣 5%', () {
      final Plant plant = _plant(progress: 0.5);
      final Plant after = applyGrowthTheft(plant, 0.20);
      expect(after.growthProgress, closeTo(0.45, 1e-12));
    });

    test('绝不扣成负数：progress 0.03 传 5% → 0.0', () {
      final Plant plant = _plant(progress: 0.03);
      final Plant after = applyGrowthTheft(plant, 0.05);
      expect(after.growthProgress, 0.0);
      expect(after.growthProgress, greaterThanOrEqualTo(0.0));
    });

    test('恰好 5% 也只扣 5%（边界含等号）', () {
      final Plant plant = _plant(progress: 0.5);
      final Plant after = applyGrowthTheft(plant, 0.05);
      expect(after.growthProgress, closeTo(0.45, 1e-12));
    });

    test('🔴 开花株免疫：progress 仍 1.0、stage 不变、对象原样返回', () {
      final Plant bloomed = _plant(
        status: PlantStatus.bloomed,
        stage: PlantStage.adult,
        progress: 1.0,
      );
      for (final double pp in <double>[0.01, 0.03, 0.05, 0.20, 1.0]) {
        final Plant after = applyGrowthTheft(bloomed, pp);
        expect(after.growthProgress, 1.0, reason: 'pp=$pp 不该扣开花株');
        expect(after.stage, PlantStage.adult);
        expect(after.stageStartedAt, bloomed.stageStartedAt);
        expect(identical(after, bloomed), isTrue, reason: '开花株必须原样返回，连新对象都不该造');
      }
    });

    test('🔴 阶段不回退：成株 1% 余量穷举边界，stage 恒为 adult', () {
      final List<double> progresses = <double>[
        0.05,
        0.04,
        0.03,
        0.02,
        0.01,
        0.0
      ];
      for (final double progress in progresses) {
        final Plant plant = _plant(
            status: PlantStatus.growing,
            stage: PlantStage.adult,
            progress: progress);
        final Plant after = applyGrowthTheft(plant, 0.05);
        expect(after.stage, PlantStage.adult,
            reason: 'progress=$progress 扣减后阶段不许回退');
        expect(after.stage, plant.stage);
        expect(after.growthProgress, greaterThanOrEqualTo(0.0));
        expect(after.growthProgress, lessThanOrEqualTo(1.0));
      }
    });

    test('🔴 阶段不回退：种子期 progress 0.02 扣 5% → 0.0，stage 仍 seed', () {
      final Plant plant = _plant(
          status: PlantStatus.growing, stage: PlantStage.seed, progress: 0.02);
      final Plant after = applyGrowthTheft(plant, 0.05);
      expect(after.growthProgress, 0.0);
      expect(after.stage, PlantStage.seed);
    });

    test('死亡株跳过：原样返回（progress / stage / 引用都不变）', () {
      final Plant dead = _plant(
          status: PlantStatus.dead, stage: PlantStage.adult, progress: 0.4);
      final Plant after = applyGrowthTheft(dead, 0.05);
      expect(identical(after, dead), isTrue);
      expect(after.growthProgress, 0.4);
      expect(after.stage, PlantStage.adult);
    });

    test('stageStartedAt 永不被改动（动了会回血或跳变）', () {
      final Plant plant = _plant(progress: 0.5);
      final Plant after = applyGrowthTheft(plant, 0.03);
      expect(after.stageStartedAt, plant.stageStartedAt);
    });

    test('脏入参（0 / 负数 / NaN / Infinity）→ 原样返回', () {
      final Plant plant = _plant(progress: 0.5);
      for (final double pp in <double>[
        0,
        -0.05,
        double.nan,
        double.infinity,
      ]) {
        final Plant after = applyGrowthTheft(plant, pp);
        expect(identical(after, plant), isTrue, reason: 'pp=$pp');
        expect(after.growthProgress.isNaN, isFalse);
        expect(after.growthProgress, 0.5);
      }
    });

    test('枯萎株（wilting）照常被偷（只有 dead / bloomed 豁免）', () {
      final Plant wilting = _plant(
          status: PlantStatus.wilting, stage: PlantStage.sprout, progress: 0.5);
      final Plant after = applyGrowthTheft(wilting, 0.03);
      expect(after.growthProgress, closeTo(0.47, 1e-12));
      expect(after.stage, PlantStage.sprout);
    });
  });

  // ─────────────────────── 券的实际节省额 ───────────────────────
  group('voucherSavingOf：5 种券各算对', () {
    test('浇水券：按盆累加、当日不限次（B13.4，原封顶 6 废除）', () {
      expect(voucherSavingOf(GuardDropKind.waterVoucher), 1.0);
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 1),
        1.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 4),
        4.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 5),
        5.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 6),
        6.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 7),
        7.0,
        reason: 'B13.4：当日不限次，第 7 盆仍 −1（旧封顶 6 废除）',
      );
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 12),
        12.0,
        reason: 'B13.4：12 盆 × 1 ☀ = 12，不再钳到 6',
      );
    });

    test('劳动券：按清理动作次数累加、当日不限次（B13.4，原封顶 4 废除）', () {
      expect(voucherSavingOf(GuardDropKind.laborVoucher), 1.0);
      expect(
        voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 3),
        3.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 4),
        4.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 12),
        12.0,
        reason: 'B13.4：12 次清理 × 1 ☀ = 12，不再钳到 4',
      );
    });

    test('🔴 两个计数参数互不串用：浇水券只看盆数、劳动券只看清理次数', () {
      // 浇水券忽略 cleanCount（除草次数再多也不给浇水折扣）。
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher,
            potCount: 2, cleanCount: 99),
        2.0,
      );
      // 劳动券忽略 potCount（盆数再多也不追加劳动奖励）。
      expect(
        voucherSavingOf(GuardDropKind.laborVoucher,
            potCount: 12, cleanCount: 2),
        2.0,
      );
    });

    test('施肥券：今日每次 −2 ☀、按盆累加封顶 12 盆 ⇒ 24', () {
      // 面值口径改为「当日最大可省」：1 盆 2、5 盆 10、12 盆 24、20 盆仍 24。
      expect(voucherSavingOf(GuardDropKind.fertilizeVoucher), 2.0);
      expect(
        voucherSavingOf(GuardDropKind.fertilizeVoucher, potCount: 1),
        2.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.fertilizeVoucher, potCount: 5),
        10.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.fertilizeVoucher, potCount: 12),
        24.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.fertilizeVoucher, potCount: 20),
        24.0,
        reason: '封顶 12 盆（最大盆位数），再多也不放大',
      );
    });

    test('🔴 免费浇水券：只算单株（potCount=5 仍只省 1 盆的钱）', () {
      expect(voucherSavingOf(GuardDropKind.freeWater), 5.0);
      expect(
        voucherSavingOf(GuardDropKind.freeWater, potCount: 5),
        5.0,
        reason: 'A10：一键 5 盆 + 免费券 ⇒ 只省 1 盆（扣 4×5 = 20），不是省 25',
      );
      expect(
        voucherSavingOf(GuardDropKind.freeWater, potCount: 12),
        5.0,
      );
    });

    test('🔴 免费施肥券：只算单株', () {
      expect(voucherSavingOf(GuardDropKind.freeFertilize), 10.0);
      expect(
        voucherSavingOf(GuardDropKind.freeFertilize, potCount: 5),
        10.0,
      );
    });

    test('无道具档：0', () {
      expect(voucherSavingOf(GuardDropKind.none), 0.0);
      expect(voucherSavingOf(GuardDropKind.none, potCount: 12), 0.0);
    });

    test('数量 <= 0 → 按 0 算（浇水券省 0、劳动券追加 0）', () {
      expect(voucherSavingOf(GuardDropKind.waterVoucher, potCount: 0), 0.0);
      expect(voucherSavingOf(GuardDropKind.waterVoucher, potCount: -3), 0.0);
      expect(voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 0), 0.0);
      expect(voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: -3), 0.0);
    });

    test('称号减免：免费券随水价/肥价变小（归零语义），浇水/劳动券不受影响', () {
      const PlantPerk none = PlantPerk.none;
      const PlantPerk lv5 = PlantPerk(waterDiscount: 1);
      const PlantPerk lv10 = PlantPerk(fertilizeDiscount: 1);
      const PlantPerk both = PlantPerk(waterDiscount: 1, fertilizeDiscount: 1);

      // 免费券 = 「这一盆归零」⇒ 省的钱就是原价减称号减免后的价。
      expect(voucherSavingOf(GuardDropKind.freeWater, perk: none), 5.0);
      expect(voucherSavingOf(GuardDropKind.freeWater, perk: lv5), 4.0);
      expect(voucherSavingOf(GuardDropKind.freeFertilize, perk: none), 10.0);
      expect(voucherSavingOf(GuardDropKind.freeFertilize, perk: lv10), 9.0);
      expect(voucherSavingOf(GuardDropKind.freeFertilize, perk: both), 9.0);

      // 浇水券 / 劳动券是「与称号相加」的定额减免，本函数不重复算称号。
      expect(
        voucherSavingOf(GuardDropKind.waterVoucher, potCount: 4, perk: lv5),
        4.0,
      );
      expect(
        voucherSavingOf(GuardDropKind.laborVoucher, cleanCount: 3, perk: both),
        3.0,
      );
    });
  });

  // ─────────────────── 落桶工具（无限值边界） ───────────────────
  group('bucketOfUniform 边界（权重 0.45 / 0.45 / 0.10）', () {
    const List<double> w = <double>[0.45, 0.45, 0.10];

    test('u = 0 → 0；u = 0.4499 → 0', () {
      expect(bucketOfUniform(0, w), 0);
      expect(bucketOfUniform(0.4499, w), 0);
    });

    test('u = 0.45（边界）→ 1', () {
      expect(bucketOfUniform(0.45, w), 1);
    });

    test('u = 0.8999 → 1；u = 0.90（边界）→ 2', () {
      expect(bucketOfUniform(0.8999, w), 1);
      expect(bucketOfUniform(0.90, w), 2);
    });

    test('u 接近 1 → 最后一桶（兜底分支）', () {
      expect(bucketOfUniform(0.9999999999, w), 2);
      expect(bucketOfUniform(1.0, w), 2);
    });

    test('权重为 0 的桶永远不会被落中', () {
      const List<double> sparse = <double>[1.0, 0.0, 0.0];
      for (final double u in <double>[0, 0.5, 0.999]) {
        expect(bucketOfUniform(u, sparse), 0);
      }
    });
  });

  // ─────────────────── 确定性哈希原语 ───────────────────
  group('stable_hash 原语', () {
    test('fnv1a32 落在 [0, 2^32) 且同输入同输出', () {
      final int a = fnv1a32('2026-11-08|child-a|guard|v2|thief');
      final int b = fnv1a32('2026-11-08|child-a|guard|v2|thief');
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThan(4294967296));
    });

    test('不同输入的哈希不同（不撞在一处）', () {
      final Set<int> hashes = <int>{
        fnv1a32('a'),
        fnv1a32('b'),
        fnv1a32('ab'),
        fnv1a32('ba'),
      };
      expect(hashes.length, 4);
    });

    test('uniformFromSeed 落在 [0, 1)', () {
      for (int i = 0; i < 500; i++) {
        final double u = uniformFromSeed('seed-$i');
        expect(u, greaterThanOrEqualTo(0.0));
        expect(u, lessThan(1.0));
      }
    });

    test('non-ASCII childId 也是纯函数（中文 childId 不炸）', () {
      expect(
        deterministicUniform(
          dayKey: '2026-11-08',
          childId: '小明',
          salt: '|guard|v2',
          channel: 'thief',
        ),
        deterministicUniform(
          dayKey: '2026-11-08',
          childId: '小明',
          salt: '|guard|v2',
          channel: 'thief',
        ),
      );
    });
  });
}
