/// 天气 × 成长数学（`lib/domain/services/weather_growth_math.dart`）回归测试。
///
/// 四层，层层有独立抓错能力：
///  · **A 层**：`penaltyOf` 全组合单元测试（4 极端 × 有/无棚 × 有/无养护，
///    期望值用**字面量 0.01** 独立写出——故意不复用常量，常量被改错也能抓到）；
///  · **B 层**：合成日均日（g=E[g]、w=E[w]、f=E[f]）模拟 300pp 首花周期，
///    对 §5.4 的 4 个数（含 B 惩罚）；
///  · **C 层**：真 `WeatherSystem` 从 2000-01-01 起连跑 100 个完整周期取平均，
///    断言 G1a 护栏（§5.5）；
///  · **D 层**：§5.4 五档「日均 pp」与「天数」全表对账（含 A / B 两列惩罚），
///    用**按日相关的次数×乘数**口径，1e-9 级钉死。
///
/// 🔴 口径警戒（本仓吃过「数字包装」的亏）：D 层若对不上，**报口径，不许调容差凑**。
/// 已核实的唯一易错点：养护贡献是 `E[次数(d)×乘数(d)]`（按日相关），
/// **不是** `E[次数] × E[乘数]`（拆开算 3 水 1 肥会差 0.28 天）。
library weather_growth_math_test;

import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/weather_growth_math.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';

/// 首花总进度（pp）：seed→sprout→adult 三阶段 × 100pp。
const double _firstBloomPp = 300;

/// 普通植物阶段时长（h）→ 自然 10pp/天。
const double _normalStageHours = 240;

/// 精品植物阶段时长（h）→ 自然 5pp/天。
const double _premiumStageHours = 480;

/// 模拟起点：天气日历锚点（与分布单测同一批日期，全程在约束生效区内）。
DateTime _cursor0() => DateTime(2000, 1, 1);

/// A 层期望值（**字面量**，故意不引用 [kWeatherPenaltyPerMissingItem]）。
double _expectedPenalty(
  WeatherKind kind, {
  required bool hasShelter,
  required bool watered,
  required bool fertilized,
}) {
  switch (kind) {
    case WeatherKind.drought:
      return (watered ? 0.0 : -0.01) + (hasShelter ? 0.0 : -0.01);
    case WeatherKind.rainstorm:
      return (fertilized ? 0.0 : -0.01) + (hasShelter ? 0.0 : -0.01);
    case WeatherKind.wind:
    case WeatherKind.cold:
      return hasShelter ? 0.0 : -0.01;
    case WeatherKind.sunny:
    case WeatherKind.breeze:
    case WeatherKind.cloudy:
    case WeatherKind.overcast:
    case WeatherKind.lightRain:
      return 0.0;
  }
}

/// 单日进度增量（progress 单位）。
///
/// [waterPlan] / [fertPlan] = 当日**计划**养护次数，实际次数按当日额度截断
/// （§8.1：`min(方案次数, 额度(d))`）。[penaltyMode]：null=不计惩罚；
/// 'B'=每天假设全都没做（B 口径上限）；'A'=每极端日最多 1pp。
double _dailyGain(
  WeatherDay day, {
  required double growthHoursPerStage,
  required int waterPlan,
  required int fertPlan,
  String? penaltyMode,
}) {
  final int waterCount = math.min(waterPlan, day.waterQuota);
  final int fertCount = math.min(fertPlan, day.fertilizeQuota);
  double gain = WeatherGrowthMath.segmentProgress(
    segHours: 24,
    day: day,
    growthHoursPerStage: growthHoursPerStage,
  );
  if (waterCount > 0) {
    gain += waterCount *
        WeatherGrowthMath.careProgress(
          baseGain: kPlantWaterProgressGain,
          day: day,
          isWater: true,
        );
  }
  if (fertCount > 0) {
    gain += fertCount *
        WeatherGrowthMath.careProgress(
          baseGain: kPlantFertilizeProgressGain,
          day: day,
          isWater: false,
        );
  }
  if (penaltyMode != null) {
    gain += WeatherGrowthMath.penaltyOf(
      day: day,
      hasShelter: false,
      watered: false,
      fertilized: false,
    );
    if (penaltyMode == 'A' && day.kind.isExtreme) {
      gain += kWeatherPenaltyPerMissingItem; // A：把多项罚回单项（最多 1pp）
    }
  }
  return gain;
}

/// 逐日模拟若干个**完整**首花周期，返回平均周期天数（最后一天按剩余比例计）。
double _averageCycleDays({
  required double growthHoursPerStage,
  required int waterPlan,
  required int fertPlan,
  String? penaltyMode,
  int cycles = 100,
}) {
  DateTime cursor = _cursor0();
  double totalDays = 0;
  for (int i = 0; i < cycles; i++) {
    double progressPp = 0;
    while (true) {
      final double gainPp =
          _dailyGain(WeatherSystem.ofDay(cursor), growthHoursPerStage: growthHoursPerStage, waterPlan: waterPlan, fertPlan: fertPlan, penaltyMode: penaltyMode) * 100;
      final double remaining = _firstBloomPp - progressPp;
      if (gainPp >= remaining) {
        totalDays += remaining / gainPp; // 开花那天的分数
        break;
      }
      progressPp += gainPp;
      totalDays += 1;
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1); // 开花当天消费掉
  }
  return totalDays / cycles;
}

/// §5.4 的日均 pp（基准口径，按日相关次数×乘数）。
double _docDailyPp({required int waterPlan, required int fertPlan}) {
  double pp = 0;
  for (final WeatherKind k in WeatherKind.values) {
    pp += WeatherSystem.weightOf(k) /
        100.0 *
        _dailyGain(
          WeatherSystem.ofKind(k),
          growthHoursPerStage: _normalStageHours,
          waterPlan: waterPlan,
          fertPlan: fertPlan,
        ) *
        100;
  }
  return pp;
}

void main() {
  setUp(WeatherSystem.clearCache);
  tearDown(WeatherSystem.clearCache);

  test('A · penaltyOf：4 极端 × 有/无棚 × 有/无养护，全组合逐项断言', () {
    const List<WeatherKind> extremes = <WeatherKind>[
      WeatherKind.drought,
      WeatherKind.wind,
      WeatherKind.cold,
      WeatherKind.rainstorm,
    ];
    for (final WeatherKind kind in extremes) {
      final WeatherDay day = WeatherSystem.ofKind(kind);
      for (final bool hasShelter in <bool>[false, true]) {
        for (final bool watered in <bool>[false, true]) {
          for (final bool fertilized in <bool>[false, true]) {
            final double actual = WeatherGrowthMath.penaltyOf(
              day: day,
              hasShelter: hasShelter,
              watered: watered,
              fertilized: fertilized,
            );
            expect(
              actual,
              _expectedPenalty(
                kind,
                hasShelter: hasShelter,
                watered: watered,
                fertilized: fertilized,
              ),
              reason: '$kind shelter=$hasShelter watered=$watered '
                  'fertilized=$fertilized',
            );
            expect(actual, lessThanOrEqualTo(0.0),
                reason: '惩罚必须 ≤ 0（负数=扣减量）');
          }
        }
      }
    }
    // 逐条关键判据（防止期望表本身写错）：
    expect(
      WeatherGrowthMath.penaltyOf(
        day: WeatherSystem.ofKind(WeatherKind.drought),
        hasShelter: false,
        watered: false,
        fertilized: false,
      ),
      -0.02,
      reason: '干旱最坏 = 浇水 + 棚 两项',
    );
    expect(
      WeatherGrowthMath.penaltyOf(
        day: WeatherSystem.ofKind(WeatherKind.drought),
        hasShelter: true,
        watered: true,
        fertilized: false,
      ),
      0.0,
      reason: '干旱做齐两项 = 免罚（ fertilized 与判据无关）',
    );
    expect(
      WeatherGrowthMath.penaltyOf(
        day: WeatherSystem.ofKind(WeatherKind.rainstorm),
        hasShelter: true,
        watered: false,
        fertilized: true,
      ),
      0.0,
      reason: '暴雨做齐两项 = 免罚（watered 与判据无关：额度为 0）',
    );
    expect(
      WeatherGrowthMath.penaltyOf(
        day: WeatherSystem.ofKind(WeatherKind.wind),
        hasShelter: false,
        watered: false,
        fertilized: false,
      ),
      -0.01,
      reason: '大风只看棚，浇水施肥不做也不加罚',
    );
  });

  test('A · 温和 5 种恒 0（任何参数组合都不罚）', () {
    const List<WeatherKind> mild = <WeatherKind>[
      WeatherKind.sunny,
      WeatherKind.breeze,
      WeatherKind.cloudy,
      WeatherKind.overcast,
      WeatherKind.lightRain,
    ];
    for (final WeatherKind kind in mild) {
      final WeatherDay day = WeatherSystem.ofKind(kind);
      for (final bool hasShelter in <bool>[false, true]) {
        for (final bool watered in <bool>[false, true]) {
          for (final bool fertilized in <bool>[false, true]) {
            expect(
              WeatherGrowthMath.penaltyOf(
                day: day,
                hasShelter: hasShelter,
                watered: watered,
                fertilized: fertilized,
              ),
              0.0,
              reason: '${kind.name} 温和日不问任何参数',
            );
          }
        }
      }
    }
  });

  test('A · B 口径期望 = 0.27pp/天、A 口径期望 = 0.20pp/天（§5.2）', () {
    double expectedB = 0;
    double expectedA = 0;
    for (final WeatherKind k in WeatherKind.values) {
      final double p = WeatherSystem.weightOf(k) / 100.0;
      expectedB += p *
          -WeatherGrowthMath.penaltyOf(
            day: WeatherSystem.ofKind(k),
            hasShelter: false,
            watered: false,
            fertilized: false,
          );
      if (k.isExtreme) {
        expectedA += p * kWeatherPenaltyPerMissingItem; // A：每极端日固定 1 项
      }
    }
    // 🔴 逐月权重表上线后（2026-11-05 玄参裁定「干旱只在 5-9 月」）年度基准变成
    // 干旱 3 / 大风 8 / 极寒 5 / 暴雨 4：**极端合计仍是 20**，但「两项惩罚」的
    // 日型（干旱、暴雨）合计从 10 掉到 7，「一项惩罚」的（大风、极寒）从 10 升到 13
    // ⇒ B 口径期望从 0.30pp/天 派生为 (2×3 + 1×8 + 1×5 + 2×4)/100 = **0.27pp/天**。
    // ⚠️ 这不是玩法常量的改动，是权重重配后的派生结果（常量仍是 1pp/项）。
    expect(expectedB * 100, closeTo(0.27, 1e-9), reason: 'B = 1%×27%');
    expect(expectedA * 100, closeTo(0.20, 1e-9), reason: 'A = 1%×20%');
  });

  test('B · 合成日均日（g/w/f = 三个期望值）复现 §5.4 的 4 个数', () {
    // 合成日：乘数取三条派生量（§3.4），日型取温和（惩罚另行按期望扣）。
    const WeatherDay synthetic = WeatherDay(
      kind: WeatherKind.sunny,
      growthFactor: 0.9565,
      waterFactor: 0.9810,
      fertilizeFactor: 0.9544,
    );
    double dailyPp({
      required bool oneWater,
      required bool withPenalty,
    }) {
      double gain = WeatherGrowthMath.segmentProgress(
        segHours: 24,
        day: synthetic,
        growthHoursPerStage: _normalStageHours,
      );
      if (oneWater) {
        gain += WeatherGrowthMath.careProgress(
          baseGain: kPlantWaterProgressGain,
          day: synthetic,
          isWater: true,
        );
      }
      if (withPenalty) {
        // B 口径期望：真权重 × 真 penaltyOf（全没做）= 0.27pp/天（由 weightOf 派生）。
        for (final WeatherKind k in WeatherKind.values) {
          gain += WeatherSystem.weightOf(k) /
              100.0 *
              WeatherGrowthMath.penaltyOf(
                day: WeatherSystem.ofKind(k),
                hasShelter: false,
                watered: false,
                fertilized: false,
              );
        }
      }
      return gain * 100;
    }

    double daysOf(double ppPerDay) => _firstBloomPp / ppPerDay;

    // 零养护：9.5650pp/天 → 31.36 天（文档 §5.4）。
    expect(daysOf(dailyPp(oneWater: false, withPenalty: false)),
        closeTo(31.36, 0.15), reason: '零养护基准');
    // 1 水 0 肥：合成日 10.5460pp/天 → 28.45 天。文档写 28.49（日均 10.5300）：
    // 文档口径是 E[次数(d)×w(d)]（按日相关），合成日是 1×E[w]（0.9810），
    // 差 0.016pp/天 → 0.043 天，来源就是这层相关性行，不是实现错
    // （D 层用相关口径精确复现 28.49）。
    expect(daysOf(dailyPp(oneWater: true, withPenalty: false)),
        closeTo(28.49, 0.15), reason: '1水0肥基准（0.043 天差 = 相关性行，见注释）');
    // 带 B 惩罚：零养护 32.28 / 1水0肥 29.24（文档）。合成日分别 32.2754 / 29.1942，
    // 差 0.005 / 0.046 天，同样来自相关性行（B 口径 0.27pp/天 × 相关性）。
    expect(daysOf(dailyPp(oneWater: false, withPenalty: true)),
        closeTo(32.28, 0.15), reason: '零养护 + B 惩罚');
    expect(daysOf(dailyPp(oneWater: true, withPenalty: true)),
        closeTo(29.24, 0.15), reason: '1水0肥 + B 惩罚（同上 0.046 天相关性差）');
  });

  test('B · G1a 护栏：零养护与 1 水 0 肥 ∈ [26, 34] 天（§5.5 断言 A/B）', () {
    final double zeroCare = _averageCycleDays(
      growthHoursPerStage: _normalStageHours,
      waterPlan: 0,
      fertPlan: 0,
      penaltyMode: 'B',
    );
    final double oneWater = _averageCycleDays(
      growthHoursPerStage: _normalStageHours,
      waterPlan: 1,
      fertPlan: 0,
      penaltyMode: 'B',
    );
    expect(zeroCare, inInclusiveRange(26, 34), reason: '零养护（B 口径上限）');
    expect(oneWater, inInclusiveRange(26, 34), reason: '1水0肥（B 口径上限）');
  });

  test('C · 真实天气 100 周期均值：普通零养护 / 1水0肥（B 口径上限）∈ [26,34]', () {
    final double zeroCare = _averageCycleDays(
      growthHoursPerStage: _normalStageHours,
      waterPlan: 0,
      fertPlan: 0,
      penaltyMode: 'B',
    );
    final double oneWater = _averageCycleDays(
      growthHoursPerStage: _normalStageHours,
      waterPlan: 1,
      fertPlan: 0,
      penaltyMode: 'B',
    );
    expect(zeroCare, inInclusiveRange(26, 34),
        reason: '普通·零养护·B 实测 $zeroCare');
    expect(oneWater, inInclusiveRange(26, 34),
        reason: '普通·1水0肥·B 实测 $oneWater');
  });

  test('C · 真实天气 100 周期均值：精品零养护（基准口径）∈ [52, 68]', () {
    // §5.5 定论：精品护栏只对**基准口径**断言——含惩罚 B 的 **66.48 已进上界 68
    // （余量 1.52 天）**，旧基准 69.12 曾超 1.12 天，
    // 但「惩罚是不照顾的代价」，不该进描述理想画像的周期护栏，故不在此断言 B 口径
    // （口径纪律不因「这次刚好进界」就松；B 口径只作观察项记录）。
    final double premiumZero = _averageCycleDays(
      growthHoursPerStage: _premiumStageHours,
      waterPlan: 0,
      fertPlan: 0,
    );
    expect(premiumZero, inInclusiveRange(52, 68),
        reason: '精品·零养护·基准 实测 $premiumZero');
  });

  test('D · §5.4 五档日均 pp 与天数全表对账（1e-9 / 0.02 天）', () {
    // 档位 → (日均 pp 文档值, 天数文档值)。
    const Map<String, List<double>> table = <String, List<double>>{
      '零养护': <double>[9.5650, 31.36],
      '1水0肥': <double>[10.5300, 28.49],
      '1水1肥': <double>[13.3932, 22.40],
      '2水1肥': <double>[14.2672, 21.03],
      '3水1肥': <double>[15.1412, 19.81],
    };
    const Map<String, List<int>> plans = <String, List<int>>{
      '零养护': <int>[0, 0],
      '1水0肥': <int>[1, 0],
      '1水1肥': <int>[1, 1],
      '2水1肥': <int>[2, 1],
      '3水1肥': <int>[3, 1],
    };
    table.forEach((String tier, List<double> doc) {
      final List<int> plan = plans[tier]!;
      final double pp = _docDailyPp(waterPlan: plan[0], fertPlan: plan[1]);
      expect(pp, closeTo(doc[0], 1e-9), reason: '$tier 日均 pp');
      expect(_firstBloomPp / pp, closeTo(doc[1], 0.02), reason: '$tier 天数');
    });
  });

  test('D · §5.4 惩罚两列（A / B 口径）全表对账', () {
    // 档位 → (基准天数, A 天数, B 天数)。
    const Map<String, List<double>> table = <String, List<double>>{
      '3水1肥': <double>[19.81, 20.08, 20.17],
      '2水1肥': <double>[21.03, 21.33, 21.43],
      '1水1肥': <double>[22.40, 22.74, 22.86],
      '1水0肥': <double>[28.49, 29.04, 29.24],
      '零养护': <double>[31.36, 32.03, 32.28],
    };
    const Map<String, List<int>> plans = <String, List<int>>{
      '3水1肥': <int>[3, 1],
      '2水1肥': <int>[2, 1],
      '1水1肥': <int>[1, 1],
      '1水0肥': <int>[1, 0],
      '零养护': <int>[0, 0],
    };
    // 🔴 B 口径的日均扣减 = `E[每个极端日的缺失项数] × 1pp`（§5.2），**由 weightOf 派生**，
    //    不写死字面量：权重一改，这里跟着变，不会出现「断言说 0.27、算式用 0.30」的分裂
    //    （这正是本文件 2026-11-05 修掉的那个缺陷）。
    //    A 口径恒 `0.20`：极端合计 20% × 每极端日固定 1 项，与极端内部构成无关。
    double bDailyPp = 0;
    for (final WeatherKind k in WeatherKind.values) {
      bDailyPp += WeatherSystem.weightOf(k) /
          100.0 *
          -WeatherGrowthMath.penaltyOf(
            day: WeatherSystem.ofKind(k),
            hasShelter: false,
            watered: false,
            fertilized: false,
          );
    }
    bDailyPp *= 100;
    // 与「A · B 口径期望」那条断言互锁（同一量，两处都不许写死成不同的数）。
    expect(bDailyPp, closeTo(0.27, 1e-9));
    const double withA = 0.20 * kWeatherPenaltyPerMissingItem * 100;
    final double withB = bDailyPp;
    table.forEach((String tier, List<double> doc) {
      final List<int> plan = plans[tier]!;
      final double base = _docDailyPp(waterPlan: plan[0], fertPlan: plan[1]);
      expect(_firstBloomPp / base, closeTo(doc[0], 0.02),
          reason: '$tier 基准天数');
      expect(_firstBloomPp / (base - withA), closeTo(doc[1], 0.02),
          reason: '$tier A 口径天数');
      expect(_firstBloomPp / (base - withB), closeTo(doc[2], 0.02),
          reason: '$tier B 口径天数');
    });
  });

  test('D · 反向守卫：拆开算（E[次数]×E[乘数]）必然对不上 §5.4', () {
    // 把「3 水 1 肥」按拆开口径算一遍：9.5650 + 3×0.9810 + 1×3×0.9544 = 15.3712pp
    // → 19.52 天 ≠ 文档 19.81（差 0.29 天）。钉住这个差，防止将来有人
    // 「顺手简化」成拆开算（次数与乘数的相关性：暴雨日次数为 0 且 w 也低）。
    const double naive = 9.5650 + 3 * 0.9810 + 1 * 3 * 0.9544;
    final double correlated = _docDailyPp(waterPlan: 3, fertPlan: 1);
    expect(correlated, closeTo(15.1412, 1e-9));
    expect(naive - correlated, greaterThan(0.2),
        reason: '拆开算 vs 相关算差 $naive vs $correlated：简化即错');
  });
}
