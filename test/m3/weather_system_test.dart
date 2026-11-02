/// 花园天气系统 · **日型纯函数层**回归测试（`lib/domain/services/weather_system.dart`）。
///
/// 覆盖的判据全部是「能抓到真错」的强断言，不是「跑通不崩」：
///  ① 确定性：同一天任何时刻 / 任何查询顺序 / 冷热缓存，结果**逐字节相同**；
///  ② 权重合计恒为 100（权重即概率，改权重就是改经济学）；
///  ③ 实际分布与名义权重的偏差（软约束会让实际值轻微偏移，故容忍度单列说明）；
///  ④⑤ 两条软约束在 100 年 36525 天上**零违反**（④ 同型不连续 3 天；
///     ⑤ **同一种**极端不连续 2 天 —— 注意是「同型」，不是「任何极端」，
///     后者会把极端占比压到 1/6，与玄参「极端 20% 概率不变」冲突）；
///  ⑥⑦ 温和加权 `g` 精确 = 1.0000 与三条派生量 E[g] / E[w] / E[f]；
///  ⑧ 道具 refType 映射（4 极端各一件，5 温和无道具）；
///  ⑨ 跨日边界（`dayKey` 按本地自然日切分，时分秒无关）；
///  ⑩ 删高温守卫（玄参 2026-11-02 拍板：全仓只有 9 种日型，没有 heat）；
///  ⑪ 参数表 = 常量（防「表里抄错一位数」，如把多云 `w` 抄成 0.96）。
library weather_system_test;

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';

/// 世纪样本区间：2000-01-01 ~ 2099-12-31（含两端，共 36525 天）。
final DateTime _centuryStart = DateTime(2000, 1, 1);

/// 世纪样本区间终点。
final DateTime _centuryEnd = DateTime(2099, 12, 31);

/// 逐日扫一段区间的日型（闭区间）。
List<WeatherKind> _scan(DateTime from, DateTime to) {
  final List<WeatherKind> kinds = <WeatherKind>[];
  DateTime day = DateTime(from.year, from.month, from.day);
  final DateTime stop = DateTime(to.year, to.month, to.day);
  while (!day.isAfter(stop)) {
    kinds.add(WeatherSystem.ofDay(day).kind);
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return kinds;
}

/// 世纪样本（**只算一次**，③④⑤ 三个断言共用，避免重复扫 36525 天）。
/// 顶层 `final` 本身即惰性初始化，故无需 `late`。
final List<WeatherKind> _centuryKinds = _scan(_centuryStart, _centuryEnd);

/// 频率统计：`kind → 出现次数`。
Map<WeatherKind, int> _histogram(List<WeatherKind> kinds) {
  final Map<WeatherKind, int> hist = <WeatherKind, int>{
    for (final WeatherKind k in WeatherKind.values) k: 0,
  };
  for (final WeatherKind k in kinds) {
    hist[k] = hist[k]! + 1;
  }
  return hist;
}

void main() {
  setUp(WeatherSystem.clearCache);
  tearDown(WeatherSystem.clearCache);

  test('① 确定性：同一日期两次结果相同，且与查询顺序/缓存冷热无关', () {
    // 同一天的不同时刻 → 完全同一份结论（只取 year/month/day）。
    final WeatherDay morning = WeatherSystem.ofDay(DateTime(2026, 11, 2, 0, 0, 1));
    final WeatherDay midnight =
        WeatherSystem.ofDay(DateTime(2026, 11, 2, 23, 59, 59));
    expect(midnight.kind, morning.kind);
    expect(midnight.growthFactor, morning.growthFactor);
    expect(midnight.waterFactor, morning.waterFactor);
    expect(midnight.fertilizeFactor, morning.fertilizeFactor);
    expect(midnight.waterQuota, morning.waterQuota);
    expect(midnight.fertilizeQuota, morning.fertilizeQuota);
    expect(midnight.rainWaterBonusPp, morning.rainWaterBonusPp);

    // 全量两遍：第二遍前清空缓存（冷缓存路径与热缓存路径必须同一结果）。
    final DateTime from = DateTime(2026, 1, 1);
    final DateTime to = DateTime(2027, 12, 31);
    final List<WeatherKind> first = _scan(from, to);
    WeatherSystem.clearCache();
    final List<WeatherKind> second = _scan(from, to);
    expect(second.length, first.length);
    expect(second, first);

    // 第三遍：**倒序**查询。软约束链条若依赖「谁先被查询」，这里必然炸。
    WeatherSystem.clearCache();
    final Map<String, WeatherKind> descending = <String, WeatherKind>{};
    DateTime cursor = to;
    while (!cursor.isBefore(from)) {
      descending[WeatherSystem.dayKey(cursor)] = WeatherSystem.ofDay(cursor).kind;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    for (int i = 0; i < first.length; i++) {
      final DateTime day = DateTime(2026, 1, 1 + i);
      expect(
        descending[WeatherSystem.dayKey(day)],
        first[i],
        reason: '倒序查询与正序查询在 ${WeatherSystem.dayKey(day)} 上不一致',
      );
    }
  });

  test('② 权重合计恒为 100（权重即概率百分位）', () {
    const List<int> weights = <int>[
      kWeatherSunnyWeight,
      kWeatherBreezeWeight,
      kWeatherCloudyWeight,
      kWeatherOvercastWeight,
      kWeatherLightRainWeight,
      kWeatherDroughtWeight,
      kWeatherWindWeight,
      kWeatherColdWeight,
      kWeatherRainstormWeight,
    ];
    expect(weights.fold<int>(0, (int a, int b) => a + b), 100);
    // 温和 80 / 极端 20（§3.2 / §3.3 的小计）。
    expect(
      kWeatherSunnyWeight +
          kWeatherBreezeWeight +
          kWeatherCloudyWeight +
          kWeatherOvercastWeight +
          kWeatherLightRainWeight,
      80,
    );
    expect(
      kWeatherDroughtWeight +
          kWeatherWindWeight +
          kWeatherColdWeight +
          kWeatherRainstormWeight,
      20,
    );
    // 枚举顺序必须与权重表一一对应（重排枚举 = 概率错位）。
    expect(WeatherSystem.weightOf(WeatherKind.sunny), kWeatherSunnyWeight);
    expect(WeatherSystem.weightOf(WeatherKind.breeze), kWeatherBreezeWeight);
    expect(WeatherSystem.weightOf(WeatherKind.cloudy), kWeatherCloudyWeight);
    expect(WeatherSystem.weightOf(WeatherKind.overcast), kWeatherOvercastWeight);
    expect(
      WeatherSystem.weightOf(WeatherKind.lightRain),
      kWeatherLightRainWeight,
    );
    expect(WeatherSystem.weightOf(WeatherKind.drought), kWeatherDroughtWeight);
    expect(WeatherSystem.weightOf(WeatherKind.wind), kWeatherWindWeight);
    expect(WeatherSystem.weightOf(WeatherKind.cold), kWeatherColdWeight);
    expect(WeatherSystem.weightOf(WeatherKind.rainstorm), kWeatherRainstormWeight);
  });

  test('③ 分布：2000-2099 共 36525 天的实测频率 vs 名义权重', () {
    expect(_centuryKinds.length, 36525);
    final Map<WeatherKind, int> hist = _histogram(_centuryKinds);
    final int total = _centuryKinds.length;

    // 名义权重 → 期望频率（百分点）。
    final Map<WeatherKind, double> nominal = <WeatherKind, double>{
      for (final WeatherKind k in WeatherKind.values)
        k: WeatherSystem.weightOf(k).toDouble(),
    };

    // 每个日型的**容忍度**：一律 1.5pp（含 4 种极端，无任何例外）。
    //
    // 软约束会让实际值轻微偏离名义值：被挡下的日子一律「顺延到下一个桶」。
    // 因为约束 ② 已收窄为「**同一种**极端不得连续两天」（不是「任何极端」），
    // 被挡下的日型只可能落到**相邻的那种极端**（干旱→大风…），不会成群回绕到
    // sunshine 上，故 9 种日型实测偏差全在 0.72pp 以内（实测最大 |偏差| =
    // sunny −0.71pp）。唯一会回绕到 sunny 的是暴雨撞暴雨（≈0.03×0.03）。
    const double tolerancePp = 1.5;

    for (final WeatherKind k in WeatherKind.values) {
      final double actualPp = hist[k]! * 100.0 / total;
      expect(
        (actualPp - nominal[k]!).abs(),
        lessThanOrEqualTo(tolerancePp),
        reason: '${k.name} 实测 ${actualPp.toStringAsFixed(4)}% '
            'vs 名义 ${nominal[k]}%',
      );
    }

    // 极端合计：玄参硬裁定「**极端 20% 的概率保持不变**」（2026-11-02 重申）⇒
    // 这里钉 20%，只留 ±1.5pp 给软约束的扰动。实测 20.31%。
    // ⚠️ 反例记档：若把约束 ② 改回「任何两种极端不得相邻」，极端占比会掉到
    // 1/6 ≈ 16.67%（稳态解 e = 0.20 × (1 − e)），本断言会立刻报红 —— 这正是
    // 我们要的守卫：让的是约束，不是概率。
    double extremePp = 0;
    for (final WeatherKind k in WeatherKind.values) {
      if (k.isExtreme) extremePp += hist[k]! * 100.0 / total;
    }
    expect(
      extremePp,
      closeTo(20.0, 1.5),
      reason: '极端合计实测 ${extremePp.toStringAsFixed(4)}%'
          '（玄参：极端 20% 概率保持不变）',
    );
  });

  test('④ 约束①：不存在「同一种日型连续 3 天」', () {
    int violations = 0;
    String? sample;
    for (int i = 2; i < _centuryKinds.length; i++) {
      final WeatherKind k = _centuryKinds[i];
      if (_centuryKinds[i - 1] == k && _centuryKinds[i - 2] == k) {
        violations++;
        sample ??= '第 $i 天（${k.name}）';
      }
    }
    expect(violations, 0, reason: '首个违例：$sample');
  });

  test('⑤ 约束②：不存在「连续两天是同一种极端」', () {
    int sameKindViolations = 0;
    int differentExtremePairs = 0;
    String? sample;
    for (int i = 1; i < _centuryKinds.length; i++) {
      final WeatherKind prev = _centuryKinds[i - 1];
      final WeatherKind today = _centuryKinds[i];
      if (!prev.isExtreme || !today.isExtreme) continue;
      if (prev == today) {
        sameKindViolations++;
        sample ??= '第 $i 天（${prev.name} → ${today.name}）';
      } else {
        differentExtremePairs++;
      }
    }
    expect(sameKindViolations, 0, reason: '首个违例：$sample');

    // 🔴 正向断言（防止将来有人把约束 ② 改回「**任何**两种极端都不许相邻」）：
    // 那种改法会把极端占比压到 1/6 ≈ 16.67%，与玄参「极端 20% 概率保持不变」
    // 直接冲突。故 100 年里必须存在大量「两种不同极端相邻」的日子
    // （实测 1701 对），否则说明约束被改宽窄了。
    expect(
      differentExtremePairs,
      greaterThan(1000),
      reason: '「不同极端相邻」实测 $differentExtremePairs 对：'
          '若为 0 说明约束②被改回「任何极端都不许相邻」',
    );
  });

  test('⑥ 温和 5 种加权 g 精确 = 1.0000（温和月不吃亏）', () {
    double weighted = 0;
    int weightSum = 0;
    for (final WeatherKind k in WeatherKind.values) {
      if (!k.isMild) continue;
      final int w = WeatherSystem.weightOf(k);
      weighted += w * WeatherSystem.ofKind(k).growthFactor;
      weightSum += w;
    }
    expect(weightSum, 80);
    expect(
      weighted / weightSum,
      closeTo(1.0, 1e-12),
      reason: '玄参要的「温和月不吃亏」：加权 g 必须精确等于 1.0000',
    );
  });

  test('⑦ 三条派生量：E[g] = 0.9280 / E[w] = 1.0700 / E[f] = 0.9514', () {
    double g = 0;
    double w = 0;
    double f = 0;
    for (final WeatherKind k in WeatherKind.values) {
      final WeatherDay day = WeatherSystem.ofKind(k);
      final int weight = WeatherSystem.weightOf(k);
      g += weight * day.growthFactor;
      w += weight * day.waterFactor;
      f += weight * day.fertilizeFactor;
    }
    expect(g / 100, closeTo(0.9280, 1e-9), reason: 'E[g]（删高温后）');
    expect(w / 100, closeTo(1.0700, 1e-9), reason: 'E[w]');
    expect(f / 100, closeTo(0.9514, 1e-9), reason: 'E[f]');
    // 极端 4 种加权 g = 0.6400（E[g] = 0.8×1.0 + 0.2×0.64 的另一半）。
    double extremeG = 0;
    int extremeWeight = 0;
    for (final WeatherKind k in WeatherKind.values) {
      if (!k.isExtreme) continue;
      extremeG += WeatherSystem.weightOf(k) * WeatherSystem.ofKind(k).growthFactor;
      extremeWeight += WeatherSystem.weightOf(k);
    }
    expect(extremeWeight, 20);
    expect(extremeG / extremeWeight, closeTo(0.6400, 1e-9));
  });

  test('⑧ 道具映射：4 极端各一件棚，5 温和全部 null', () {
    expect(
      WeatherKind.drought.shelterRefType,
      kWeatherShelterRefTypeShade,
    );
    expect(WeatherKind.wind.shelterRefType, kWeatherShelterRefTypeWind);
    expect(WeatherKind.cold.shelterRefType, kWeatherShelterRefTypeWarm);
    expect(WeatherKind.rainstorm.shelterRefType, kWeatherShelterRefTypeRain);
    // 4 个 refType 必须互不相同（同一天买两种棚要能在账本里区分开）。
    final Set<String?> extremeRefTypes = <String?>{
      for (final WeatherKind k in WeatherKind.values)
        if (k.isExtreme) k.shelterRefType,
    };
    expect(extremeRefTypes.length, 4);

    for (final WeatherKind k in WeatherKind.values) {
      if (!k.isMild) continue;
      expect(k.shelterRefType, isNull, reason: '${k.name} 不该要道具');
    }
  });

  test('⑨ 跨日边界：dayKey 按本地自然日切分，时分秒无关', () {
    expect(WeatherSystem.dayKey(DateTime(2026, 11, 2, 23, 59)), '2026-11-02');
    expect(WeatherSystem.dayKey(DateTime(2026, 11, 3, 0, 1)), '2026-11-03');
    expect(
      WeatherSystem.dayKey(DateTime(2026, 11, 2, 23, 59)),
      isNot(WeatherSystem.dayKey(DateTime(2026, 11, 3, 0, 1))),
    );
    // 补零（个位数月/日不得退化成 2026-1-2）。
    expect(WeatherSystem.dayKey(DateTime(2026, 1, 2)), '2026-01-02');
    // 同一天的两端：日型必须一致（两端允许同一天型，不同才怪）。
    expect(
      WeatherSystem.ofDay(DateTime(2026, 11, 2, 0, 0)).kind,
      WeatherSystem.ofDay(DateTime(2026, 11, 2, 23, 59)).kind,
    );
  });

  test('⑩ 删高温守卫：恰好 9 种日型，且不存在 heat', () {
    expect(WeatherKind.values.length, 9);
    final List<String> names =
        WeatherKind.values.map((WeatherKind k) => k.name).toList();
    expect(names, isNot(contains('heat')));
    expect(names, <String>[
      'sunny',
      'breeze',
      'cloudy',
      'overcast',
      'lightRain',
      'drought',
      'wind',
      'cold',
      'rainstorm',
    ]);
    // 极端判据的边界：第 4 个（lightRain）仍是温和，第 5 个（drought）起才是极端。
    expect(WeatherKind.lightRain.isExtreme, isFalse);
    expect(WeatherKind.drought.isExtreme, isTrue);
    expect(
      WeatherKind.values.where((WeatherKind k) => k.isExtreme).length,
      4,
    );
    expect(WeatherKind.values.where((WeatherKind k) => k.isMild).length, 5);
  });

  test('⑪ 参数表与常量逐项一致（防表里抄错一位数）', () {
    for (final WeatherKind k in WeatherKind.values) {
      final WeatherDay day = WeatherSystem.ofKind(k);
      expect(day.kind, k, reason: '表里 ${k.name} 的 kind 字段写错');
      // 额度：只有小雨 / 暴雨破例，其余一律 3 水 1 肥。
      final int expectedWaterQuota = switch (k) {
        WeatherKind.lightRain => kWeatherLightRainWaterQuota,
        WeatherKind.rainstorm => kWeatherRainstormWaterQuota,
        _ => kWeatherDefaultWaterQuota,
      };
      expect(day.waterQuota, expectedWaterQuota, reason: '${k.name} 浇水额度');
      expect(day.fertilizeQuota, kWeatherDefaultFertilizeQuota,
          reason: '${k.name} 施肥额度');
      // 雨水代劳只属于暴雨，且恰好 1.00pp。
      expect(
        day.rainWaterBonusPp,
        k == WeatherKind.rainstorm ? kWeatherRainstormWaterBonusPp : 0.0,
        reason: '${k.name} 雨水代劳',
      );
      // 文案 key 与日型一一对应（不得漏配 / 串到别的日型上）。
      expect(day.kind.l10nKey, 'weather.${_snakeKeyOf(k)}');
    }
    // 抽三条乘数逐个钉死（表里最容易抄错的就是温和那几档）。
    expect(WeatherSystem.ofKind(WeatherKind.sunny).growthFactor,
        kWeatherSunnyGrowthFactor);
    expect(WeatherSystem.ofKind(WeatherKind.cloudy).waterFactor,
        kWeatherCloudyWaterFactor);
    expect(WeatherSystem.ofKind(WeatherKind.cold).fertilizeFactor,
        kWeatherColdFertilizeFactor);
    expect(kWeatherRainstormWaterBonusPp, 0.01);
  });
}

/// 文案 key 的 snake_case 形式（`lightRain` → `light_rain`）。
String _snakeKeyOf(WeatherKind kind) {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < kind.name.length; i++) {
    final String ch = kind.name[i];
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) {
      buffer.write('_');
    }
    buffer.write(ch.toLowerCase());
  }
  return buffer.toString();
}
