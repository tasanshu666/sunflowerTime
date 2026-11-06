/// 天气系统 · **逐月权重表（季节口径）** 回归测试（S1~S7）。
///
/// ## 为什么需要这一层
/// 2026-11-05 玄参裁定「**干旱只在 5-9 月**」（北方季节实际）⇒ 天气从「全年固定
/// 权重」改成「逐月权重表」`kWeatherWeightsByMonth`（`prd_constants` 单点真源）。
/// 这一层的职责是把「**名义表**」与「**实测世纪分布**」两端同时钉住：
///  · S1/S2 钉**表本身**（结构、合计、查询入口的越界行为）；
///  · S3/S4/S5/S7 钉**真实跑出来的 100 年**（`WeatherSystem.ofDay` 逐日扫
///    2000-01-01 ~ 2099-12-31，共 36525 天）—— 只有「哪个月不可能出现某种
///    天气」这类**定性**事实能当断言，因为软约束②的 spillover 会让逐格实测值
///    偏离名义值最多 ~3.7pp（3 月大风：20% → 16.3%，被挡后只能回绕到 sunny）。
///  · S6 钉「年度基准」这条语义：`weightOf` 返回的是**定出来的常量**
///    （`kWeather*Weight`），**不是** 12 个月权重的列均值 —— 派生经济量
///    E[g] / E[w] / E[f] 用的就是它。两者只保证「差 ≤1.5pp」，不保证相等：
///    实测列均值 vs 常量 = 晴 20.17→20 / 微风 13.83→14 / 云 18.42→18 /
///    阴 14.83→14 / **小雨 12.75→14** / 旱 3.17→3 / **大风 7.67→8** /
///    极寒 5.08→5 / 暴雨 4.08→4，**最大差 1.25pp（小雨）**。
///    🔴 所以**不能把 `weightOf` 写成列均值**（K23：常量是定出来的，不是量出来的）；
///    改成列均值会连带把 E[g] 从 0.9565 拉到 0.9540、E[w] 从 0.9810 拉到 0.9878。
///  · 🔴 **G2 是年度口径，不是逐月**（玄参 2026-11-06 裁定，方案 §2.7 裁定 7）：
///    逐月温和加权 g 是 0.98938（6 月）~ 1.00413（9 月），6/7/8 三个月低于 1.0
///    属**已知且已接受的季节特征**，**不是缺陷**。本文件也**不**断言逐月温和加权 g
///    = 1.0 —— 断它必红，且「修」它的唯一办法是取消季节化。
///
/// ⚠️ **故意不写**「逐月实测 vs 逐月名义 ±1.5pp」：108 格里最大偏差 **3.68pp**
/// （3 月 wind，名义 20% → 实测 16.32%，同一手把 3 月 sunny 顶到 21.13%），
/// 写死就只能放宽容差 = 自欺。用 S3/S4/S5/S7 这四条定性断言代替。
///
/// ## 附：正确盐下的世纪实测（仅供核对，**没有任何断言读这组数**）
/// 逐档：sunny 20.79 / breeze 14.31 / cloudy 18.09 / overcast 14.95 / lightRain 12.94
/// / drought 3.20 / wind 7.15 / cold 4.60 / rainstorm 3.97；极端合计 **18.92%**。
/// 逐月极端占比：1 月 17.5 / 2 月 16.8 / 3 月 16.3 / 4 月 19.3 / 5 月 19.2 /
/// 6 月 21.0 / 7 月 20.6 / 8 月 20.2 / 9 月 19.2 / 10 月 20.4 / 11 月 19.0 / 12 月 17.5。
/// 🔴 冬季（1/2/12 月）极端明显低于名义 20% 是**结构性的**：drought 与 rainstorm
/// 冬季权重为 0、wind 只剩 3~4，cold 被约束 ② 挡下后只能一路回绕到 sunny。

library weather_season_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';

// ── 世纪样本（**只算一次**：36525 天，S3~S7 共用）─────────────────────────────

/// 世纪扫描结果（逐月天数 / 逐月逐档天数 / 总计）。
class _Century {
  _Century._({
    required this.daysPerMonth,
    required this.kindsPerMonth,
    required this.total,
    required this.kindsTotal,
  });

  /// `daysPerMonth[1..12]` = 该月的总天数（19825 天级别的真实月长，含闰年）。
  final List<int> daysPerMonth;

  /// `kindsPerMonth[1..12][kind]` = 该月该日型的天数。
  final List<Map<WeatherKind, int>> kindsPerMonth;

  /// 总天数（36525）。
  final int total;

  /// 全世纪逐档天数。
  final Map<WeatherKind, int> kindsTotal;

  /// 全世纪某档的百分比（百分点）。
  double pct(WeatherKind kind) => kindsTotal[kind]! * 100.0 / total;

  /// 某月某档的天数。
  int count(int month, WeatherKind kind) => kindsPerMonth[month][kind]!;

  /// 某月某档的百分比（百分点，分母 = 该月天数）。
  double monthPct(int month, WeatherKind kind) =>
      kindsPerMonth[month][kind]! * 100.0 / daysPerMonth[month];
}

_Century _scan() {
  final List<Map<WeatherKind, int>> perMonth = <Map<WeatherKind, int>>[
    for (int m = 0; m < 13; m++)
      <WeatherKind, int>{for (final WeatherKind k in WeatherKind.values) k: 0},
  ];
  final List<int> daysPerMonth = List<int>.filled(13, 0);
  final Map<WeatherKind, int> total = <WeatherKind, int>{
    for (final WeatherKind k in WeatherKind.values) k: 0,
  };
  int days = 0;
  final DateTime stop = DateTime(2099, 12, 31);
  for (DateTime d = DateTime(2000, 1, 1);
      !d.isAfter(stop);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final WeatherKind kind = WeatherSystem.ofDay(d).kind;
    total[kind] = total[kind]! + 1;
    perMonth[d.month][kind] = perMonth[d.month][kind]! + 1;
    daysPerMonth[d.month] = daysPerMonth[d.month] + 1;
    days++;
  }
  return _Century._(
    daysPerMonth: daysPerMonth,
    kindsPerMonth: perMonth,
    total: days,
    kindsTotal: total,
  );
}

/// 世纪样本（顶层 `final` ⇒ 惰性求值一次，S3~S7 共用同一份）。
final _Century _century = _scan();

void main() {
  // 缓存对结论零影响（纯性能设施），但扫完清掉不留跨文件污染。
  tearDownAll(WeatherSystem.clearCache);

  // ══════════════════════════════════════════════════════════════════════════
  // S1 · 表结构：12 行 × 9 列、每行合计 100、温和 80 / 极端 20
  // ══════════════════════════════════════════════════════════════════════════
  test('S1 逐月权重表结构：12 行 × 9 列，每行合计 100（温和 80 / 极端 20）', () {
    expect(kWeatherWeightsByMonth.length, 12,
        reason: '必须正好 12 行（1 月 → 第 0 行，下标 = 月份 − 1）');
    for (int m = 1; m <= 12; m++) {
      final List<int> row = kWeatherWeightsByMonth[m - 1];
      expect(row.length, WeatherKind.values.length,
          reason: '$m 月的列数必须等于日型总数 9（列顺序 = WeatherKind.index）');
      expect(row.fold<int>(0, (int a, int b) => a + b), 100,
          reason: '$m 月权重合计必须恒为 100（落桶算法依赖「权重即百分位」）');

      int mild = 0;
      int extreme = 0;
      final List<String> nonPositiveMild = <String>[];
      for (final WeatherKind k in WeatherKind.values) {
        if (k.isMild) {
          mild += row[k.index];
          // 温和 5 档**逐月全为正**：这是「`_pickKind` 顺延 9 次内必命中」的前提
          // （至少 4 个合法温和桶），也是 S7「权重 0 的档绝不出现」不误伤温和档的
          // 结构保证。改成 0 会让冬季出现「无温和可选」的死角。
          if (row[k.index] <= 0) nonPositiveMild.add(k.name);
        } else {
          extreme += row[k.index];
        }
      }
      expect(mild, 80, reason: '$m 月温和 5 档合计必须 80');
      expect(extreme, 20, reason: '$m 月极端 4 档合计必须 20（玄参：极端 20% 不变）');
      expect(nonPositiveMild, isEmpty,
          reason: '$m 月温和 5 档必须全为正，实际为 0 的是 $nonPositiveMild');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S2 · 查询入口：首末月正确、越界抛 ArgumentError（不静默回绕）
  // ══════════════════════════════════════════════════════════════════════════
  test('S2 weightsOfMonth / weightOfMonth 取值正确，month 越界抛 ArgumentError', () {
    // 首末月逐位对齐表本身（不是「差不多」）。
    for (int m in <int>[1, 12]) {
      final List<int> row = kWeatherWeightsByMonth[m - 1];
      expect(WeatherSystem.weightsOfMonth(m), row, reason: '$m 月逐位对齐');
      for (final WeatherKind k in WeatherKind.values) {
        expect(WeatherSystem.weightOfMonth(k, m), row[k.index],
            reason: '$m 月 ${k.name} 的 weightOfMonth 必须等于表值');
      }
    }
    // 1 月干旱权重 0（玄参裁定「干旱只在 5-9 月」的直接体现）。
    expect(WeatherSystem.weightOfMonth(WeatherKind.drought, 1), 0);
    expect(WeatherSystem.weightOfMonth(WeatherKind.drought, 5), greaterThan(0));
    expect(WeatherSystem.weightOfMonth(WeatherKind.drought, 9), greaterThan(0));
    expect(WeatherSystem.weightOfMonth(WeatherKind.drought, 10), 0);

    // 🔴 越界必须抛，绝不静默回绕：这是本层唯一的越界入口，
    //    静默回绕会让 `ofDay(DateTime(2026, 13, 1))` 那类月份传错算出一个
    //    「看起来合理」的天气，永远查不出来。
    expect(() => WeatherSystem.weightsOfMonth(0), throwsArgumentError);
    expect(() => WeatherSystem.weightsOfMonth(13), throwsArgumentError);
    expect(() => WeatherSystem.weightsOfMonth(-1), throwsArgumentError);
    expect(
      () => WeatherSystem.weightOfMonth(WeatherKind.sunny, 0),
      throwsArgumentError,
      reason: 'weightOfMonth 必须复用 weightsOfMonth 的校验，不得自己下标',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S3 · 干旱只在 5-9 月：其余 7 个月实测天数逐月 == 0
  // ══════════════════════════════════════════════════════════════════════════
  test('S3 世纪实测：1/2/3/4/10/11/12 月 drought 天数逐月 == 0', () {
    expect(_century.total, 36525, reason: '世纪样本必须是 2000-01-01~2099-12-31');
    for (final int m in <int>[1, 2, 3, 4, 10, 11, 12]) {
      final int droughtCount = _century.count(m, WeatherKind.drought);
      expect(droughtCount, 0,
          reason: '$m 月干旱权重为 0 ⇒ 世纪实测必须 0 天，'
              '实际 $droughtCount 天（漏 `w[bucket] > 0` 会在这里露出来）');
    }
    // 反向：旱季必须真的有（否则「只在 5-9 月」退化成「从不出现」）。
    for (final int m in <int>[5, 6, 7, 8, 9]) {
      expect(_century.count(m, WeatherKind.drought), greaterThan(0),
          reason: '$m 月干旱权重 > 0，世纪实测不该是 0 天');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S4 · 盛夏无寒：cold 权重为 0 的 7 个月（3~9 月）实测天数逐月 == 0
  // ══════════════════════════════════════════════════════════════════════════
  test('S4 世纪实测：cold 权重为 0 的 3~9 月，逐月天数 == 0', () {
    // 表里 cold 为 0 的是 3/4/5/6/7/8/9 月（1/2/12 月 17/16/16，10 月 3，11 月 9）。
    for (final int m in <int>[3, 4, 5, 6, 7, 8, 9]) {
      final int coldCount = _century.count(m, WeatherKind.cold);
      expect(coldCount, 0,
          reason: '$m 月极寒权重为 0 ⇒ 世纪实测必须 0 天，实际 $coldCount 天');
    }
    // 冬季与深秋必须有极寒（否则「只在冷季出现」退化成「从不出现」）。
    for (final int m in <int>[1, 2, 10, 11, 12]) {
      expect(_century.count(m, WeatherKind.cold), greaterThan(0),
          reason: '$m 月极寒权重 > 0，世纪实测不该是 0 天');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S5 · 雨季错位：1 月雨类 < 10%、7 月雨类 > 26%，且 7 月 > 1 月 × 3
  // ══════════════════════════════════════════════════════════════════════════
  test('S5 世纪实测：雨类占比 1 月 < 10% 且 7 月 > 26%，7 月 > 3×1 月', () {
    double rainPct(int month) =>
        _century.monthPct(month, WeatherKind.lightRain) +
        _century.monthPct(month, WeatherKind.rainstorm);

    final double jan = rainPct(1);
    final double jul = rainPct(7);
    // ignore: avoid_print
    print('[季节] 雨类占比：1 月 ${jan.toStringAsFixed(2)}%，'
        '7 月 ${jul.toStringAsFixed(2)}%');
    expect(jan, lessThan(10.0),
        reason: '1 月雨类（小雨 6 + 暴雨 0）⇒ 实测 $jan%');
    expect(jul, greaterThan(26.0),
        reason: '7 月雨类合计 22+10 = 32 ⇒ 实测 $jul%');
    expect(jul, greaterThan(jan * 3),
        reason: '「夏天多雨、冬天少雨」的定性事实：7 月 $jul% 应超过 1 月 $jan% 的 3 倍');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S6 · 年度基准语义：weightOf == kWeather*Weight，且 = 12 个月均值（≤1.5pp）
  // ══════════════════════════════════════════════════════════════════════════
  test('S6 weightOf 逐位等于 kWeather*Weight，且与 12 个月均值相差 ≤1.5pp', () {
    const Map<WeatherKind, int> expected = <WeatherKind, int>{
      WeatherKind.sunny: kWeatherSunnyWeight,
      WeatherKind.breeze: kWeatherBreezeWeight,
      WeatherKind.cloudy: kWeatherCloudyWeight,
      WeatherKind.overcast: kWeatherOvercastWeight,
      WeatherKind.lightRain: kWeatherLightRainWeight,
      WeatherKind.drought: kWeatherDroughtWeight,
      WeatherKind.wind: kWeatherWindWeight,
      WeatherKind.cold: kWeatherColdWeight,
      WeatherKind.rainstorm: kWeatherRainstormWeight,
    };
    expected.forEach((WeatherKind kind, int weight) {
      expect(WeatherSystem.weightOf(kind), weight,
          reason: '${kind.name} 的年度基准必须等于对应常量（枚举顺序守卫）');
      int sum = 0;
      for (int m = 1; m <= 12; m++) {
        sum += WeatherSystem.weightOfMonth(kind, m);
      }
      final double mean = sum / 12.0;
      expect((mean - weight).abs(), lessThanOrEqualTo(1.5),
          reason: '${kind.name}：12 个月均值 $mean 与年度基准 $weight 相差 '
              '${(mean - weight).abs()}pp（「年度名义基准」这条语义要求 ≤1.5pp）');
    });
    // 年度基准本身仍是「温和 80 / 极端 20」。
    int mildSum = 0;
    int extremeSum = 0;
    for (final WeatherKind k in WeatherKind.values) {
      if (k.isMild) {
        mildSum += WeatherSystem.weightOf(k);
      } else {
        extremeSum += WeatherSystem.weightOf(k);
      }
    }
    expect(mildSum, 80);
    expect(extremeSum, 20);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S7 · 通用顺延守卫：权重为 0 的档，在该月实测天数必须为 0（9 档 × 12 月全扫）
  // ══════════════════════════════════════════════════════════════════════════
  test('S7 世纪实测：weightOfMonth(kind, month) == 0 ⇒ 该月该档天数 == 0（108 格全扫）', () {
    int zeroCells = 0;
    for (int m = 1; m <= 12; m++) {
      for (final WeatherKind k in WeatherKind.values) {
        if (WeatherSystem.weightOfMonth(k, m) != 0) continue;
        zeroCells++;
        expect(_century.count(m, k), 0,
            reason: '$m 月 ${k.name} 权重为 0，实测却有 '
                '${_century.count(m, k)} 天 —— 顺延跨过了零权重桶'
                '（`_pickKind` 的 `w[bucket] > 0` 判据失效）');
      }
    }
    // 零格数量守卫：表里必须真有「零权重格」（否则这条断言等于空转）。
    // 逐档点数：干旱 7（1/2/3/4/10/11/12）+ 极寒 7（3/4/5/6/7/8/9）+ 暴雨 5（1/2/3/11/12）
    // = **19**；大风 12 个月全非零。表一被改回「全年固定权重」，这里立刻掉到 0。
    expect(zeroCells, 19,
        reason: '108 格里应有 19 个零权重格（干旱 7 + 极寒 7 + 暴雨 5），'
            '实际 $zeroCells 个 —— 变少说明表被改回「全年固定」或某月被手滑填成非零');
  });
}
