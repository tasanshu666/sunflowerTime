/// 花园天气系统 · **日型纯函数层**：`f(本地自然日) → 当天天气`。
///
/// ## 定位（本轮范围）
/// `docs/天气系统_最终方案.md` §3.1~§3.4 的**唯一实现落点**，只做一件事：
/// 「给定一个自然日，算出那天是 9 种日型中的哪一种，以及那天的三个乘数 + 两个额度」。
/// **不含**：UI / 条幅、日结与惩罚判定、道具购买与账本、仓储、`schemaVersion`。
/// 后续批次（`_advanceGrowth` 读 `g`、即时加值读 `w`/`f`、日结读惩罚）**只允许**
/// 通过 [WeatherSystem.ofDay] 取数，禁止在别处重算或内联天气乘数。
///
/// ## 确定性（🔴 硬纪律 G4）
///  · **禁用 `Random`**：全部由「日期字符串 → FNV-1a 32bit → 百分位落桶」决定，
///    同一台设备、同一天，任何会话、任何查询顺序，**永远是同一种天气**；
///  · 时分秒无关：只取 `year/month/day`（本地自然日）；
///  · 常量全部来自 `core/constants/prd_params.dart`，本文件**零裸数值**
///    （除算法自身的 `2^32` / `100` 与 `0.0`/`1.0` 语义中位数）。
///
/// ## 两条软约束（仍是纯函数，不改 hash / 不引随机）
///  ① 同一日型不得连续出现 3 天 → 命中则顺延到下一个桶（超出末尾回绕）
///  ② **同一种**极端不得连续两天 → 命中则顺延到下一个桶（超出末尾回绕）
///
/// ⚠️ 约束 ② 是「同型极端」，**不是「任何极端」**：禁止任何两种极端相邻会让
/// 极端占比数学上掉到 1/6 ≈ 16.67%，与玄参「极端 20% 概率保持不变」相冲，
/// 故只挡「同一种极端连着两天」这种孩子真会记住的重复。
///
/// ⚠️ **为什么链条要从「绝对锚点」起算，而不是「从被查询日往回看 2 天」**：
/// 约束需要「昨天 / 前天」的**最终**结论，而它们的结论又依赖各自的前两天 ——
/// 若把「回看层数」按「距被查询日的距离」计数，则 `kind(D)` 会随**谁先被查询**
/// 而变（先查 D 时 D-2 在深度 2 上被截断成裸桶，先查 D-2 时它带完整约束），
/// 表现为「昨天是暴雨，今天回看昨天变晴天」。故链条固定从
/// [kWeatherCalendarEpochYear] 起算：锚点之前按**裸桶**（只落权重），
/// 锚点起逐日按全规则推进 ⇒ `day` 的日型**只由 `day` 决定**（与查询顺序无关）。
/// 代价是冷缓存下首次查询要补算「锚点 → 目标日」这一串，故有
/// [kWeatherCacheMaxEntries] 的内存缓存 + 「逐日正向回填」的迭代实现（不递归、不爆栈）。
library weather_system;

import 'dart:collection';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 9 种天气日型（温和 5 + 极端 4）。
///
/// 🔴 **枚举顺序是测试基线的一部分，禁止重排/插入**：`index` 同时是
///  · 权重表 [WeatherSystem] 内部 `_weights` 的下标；
///  · 软约束「顺延到下一个桶」的桶序号（回绕 = `(index + 1) % 9`）。
/// 新增日型**只能追加到末尾**（会改变权重合计，须先走裁定并同步 100 的口径）。
enum WeatherKind {
  /// 阳光明媚（温和，20%）
  sunny,

  /// 微风（温和，14%）
  breeze,

  /// 多云（温和，18%）
  cloudy,

  /// 阴天（温和，14%）
  overcast,

  /// 小雨（温和，14%；唯一压浇水额度的温和日）
  lightRain,

  /// 干旱（极端，7%；`g` ×0.20 / `w` ×3.00）
  drought,

  /// 大风（极端，5%）
  wind,

  /// 极寒（极端，5%；`f` ×1.50）
  cold,

  /// 暴雨（极端，3%；浇水额度 0 + 雨水代劳 +1.00pp）
  rainstorm;

  /// 是否**极端**日型（后 4 个：drought / wind / cold / rainstorm）。
  ///
  /// 判据写 `index >= drought.index` 而不是 `index >= 5`：重排禁令一旦被破坏，
  /// 这里会跟着错（测试另有 `values.length == 9` 守卫）。
  bool get isExtreme => index >= WeatherKind.drought.index;

  /// 是否**温和**日型（前 5 个）。温和日不需要道具、也不吃任何惩罚。
  bool get isMild => !isExtreme;

  /// 文案 key（ARB 文案由 i18n 批次补；**本层只出 key，不含任何中文字面量**）。
  String get l10nKey => switch (this) {
        WeatherKind.sunny => 'weather.sunny',
        WeatherKind.breeze => 'weather.breeze',
        WeatherKind.cloudy => 'weather.cloudy',
        WeatherKind.overcast => 'weather.overcast',
        WeatherKind.lightRain => 'weather.light_rain',
        WeatherKind.drought => 'weather.drought',
        WeatherKind.wind => 'weather.wind',
        WeatherKind.cold => 'weather.cold',
        WeatherKind.rainstorm => 'weather.rainstorm',
      };

  /// 该日型**要求的道具** refType；温和日返回 `null`（= 不需要道具）。
  ///
  /// 🔴 一个天气一个 refType（不是 `refType='shelter'` + refId 区分），
  /// 购买判定一律用既有 `countByRefTypeAndRefIdOnDay(refType, 'garden', day)`。
  String? get shelterRefType => switch (this) {
        WeatherKind.drought => kWeatherShelterRefTypeShade,
        WeatherKind.wind => kWeatherShelterRefTypeWind,
        WeatherKind.cold => kWeatherShelterRefTypeWarm,
        WeatherKind.rainstorm => kWeatherShelterRefTypeRain,
        WeatherKind.sunny ||
        WeatherKind.breeze ||
        WeatherKind.cloudy ||
        WeatherKind.overcast ||
        WeatherKind.lightRain =>
          null,
      };
}

/// **一天的天气结论**（不可变值对象）：日型 + 三个乘数 + 两个额度 + 雨水代劳。
///
/// 全部字段都是「当天有效」的即时口径，**不含任何累计状态**（累计在植物 / 账本侧）。
class WeatherDay {
  /// 构造：日型与三个乘数必填，额度缺省即「满额度」（3 水 1 肥）。
  const WeatherDay({
    required this.kind,
    required this.growthFactor,
    this.waterFactor = 1.0,
    this.fertilizeFactor = 1.0,
    this.waterQuota = kWeatherDefaultWaterQuota,
    this.fertilizeQuota = kWeatherDefaultFertilizeQuota,
    this.rainWaterBonusPp = 0.0,
  });

  /// 日型。
  final WeatherKind kind;

  /// `g`：**自然生长乘数**（日结侧乘到逐日推进的进度上）。
  final double growthFactor;

  /// `w`：**浇水乘数**（即时加值侧：一次浇水的进度收益 × `w`）。
  final double waterFactor;

  /// `f`：**施肥乘数**（即时加值侧：一次施肥的进度收益 × `f`）。
  final double fertilizeFactor;

  /// 当天**浇水额度**（次数）：默认 3；小雨 1；暴雨 0。
  final int waterQuota;

  /// 当天**施肥额度**（次数）：9 种日型全为 1。
  final int fertilizeQuota;

  /// **雨水代劳**自动进度（单位 = 百分点 pp；仅暴雨 = 1.00pp，其余 0）。
  final double rainWaterBonusPp;

  /// 调试用（**纯 ASCII**：`lib/domain/**` 有「注释外零 CJK」守卫，
  /// 见 `test/i18n/no_han_in_domain_test.dart`）：
  /// `WeatherDay(sunny, g=1.05, w=1.10, f=1.05, water=3, fert=1, rain=0.0)`。
  @override
  String toString() => 'WeatherDay(${kind.name}, g=$growthFactor, '
      'w=$waterFactor, f=$fertilizeFactor, water=$waterQuota, '
      'fert=$fertilizeQuota, rain=$rainWaterBonusPp)';
}

/// 天气日历（**纯静态 / 无随机**）。
///
/// 唯一入口：[ofDay]（给定自然日 → [WeatherDay]）。其余成员均为内部实现细节，
/// 唯一对外补充是 [ofKind]（按日型取参数表，给道具/文案侧复用，避免各处重抄表格）
/// 与 [weightOf] / [clearCache]（后者仅测试与诊断用）。
class WeatherSystem {
  /// 工具类，禁止实例化。
  WeatherSystem._();

  // ── 参数表 ────────────────────────────────────────────────────────────────

  /// 9 种日型的权重（**下标 = [WeatherKind.index]**，合计恒为 100）。
  ///
  /// 单点真源是 `prd_params.dart` 的 `kWeather*Weight`；本表只是按枚举顺序排好，
  /// `weightOf` 与分布单测双向钉死（既钉「数值」也钉「顺序」）。
  static const List<int> _weights = <int>[
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

  /// 9 种日型的完整参数（`const` 表，无任何运行时构造）。
  static const Map<WeatherKind, WeatherDay> _table = <WeatherKind, WeatherDay>{
    WeatherKind.sunny: WeatherDay(
      kind: WeatherKind.sunny,
      growthFactor: kWeatherSunnyGrowthFactor,
      waterFactor: kWeatherSunnyWaterFactor,
      fertilizeFactor: kWeatherSunnyFertilizeFactor,
    ),
    WeatherKind.breeze: WeatherDay(
      kind: WeatherKind.breeze,
      growthFactor: kWeatherBreezeGrowthFactor,
      waterFactor: kWeatherBreezeWaterFactor,
      fertilizeFactor: kWeatherBreezeFertilizeFactor,
    ),
    WeatherKind.cloudy: WeatherDay(
      kind: WeatherKind.cloudy,
      growthFactor: kWeatherCloudyGrowthFactor,
      waterFactor: kWeatherCloudyWaterFactor,
      fertilizeFactor: kWeatherCloudyFertilizeFactor,
    ),
    WeatherKind.overcast: WeatherDay(
      kind: WeatherKind.overcast,
      growthFactor: kWeatherOvercastGrowthFactor,
      waterFactor: kWeatherOvercastWaterFactor,
      fertilizeFactor: kWeatherOvercastFertilizeFactor,
    ),
    WeatherKind.lightRain: WeatherDay(
      kind: WeatherKind.lightRain,
      growthFactor: kWeatherLightRainGrowthFactor,
      waterFactor: kWeatherLightRainWaterFactor,
      fertilizeFactor: kWeatherLightRainFertilizeFactor,
      waterQuota: kWeatherLightRainWaterQuota,
    ),
    WeatherKind.drought: WeatherDay(
      kind: WeatherKind.drought,
      growthFactor: kWeatherDroughtGrowthFactor,
      waterFactor: kWeatherDroughtWaterFactor,
      fertilizeFactor: kWeatherDroughtFertilizeFactor,
    ),
    WeatherKind.wind: WeatherDay(
      kind: WeatherKind.wind,
      growthFactor: kWeatherWindGrowthFactor,
      waterFactor: kWeatherWindWaterFactor,
      fertilizeFactor: kWeatherWindFertilizeFactor,
    ),
    WeatherKind.cold: WeatherDay(
      kind: WeatherKind.cold,
      growthFactor: kWeatherColdGrowthFactor,
      waterFactor: kWeatherColdWaterFactor,
      fertilizeFactor: kWeatherColdFertilizeFactor,
    ),
    WeatherKind.rainstorm: WeatherDay(
      kind: WeatherKind.rainstorm,
      growthFactor: kWeatherRainstormGrowthFactor,
      waterFactor: kWeatherRainstormWaterFactor,
      fertilizeFactor: kWeatherRainstormFertilizeFactor,
      waterQuota: kWeatherRainstormWaterQuota,
      rainWaterBonusPp: kWeatherRainstormWaterBonusPp,
    ),
  };

  // ── 缓存（纯性能设施；不影响任何结论）────────────────────────────────────

  /// 日型缓存：`dayKey('yyyy-MM-dd') → WeatherDay`。
  ///
  /// 用 [LinkedHashMap] 的**插入顺序**做 FIFO 淘汰（超 [kWeatherCacheMaxEntries]
  /// 就丢最旧一条）：顺序回看只需要最近两天，FIFO 天然保住它们，
  /// 而「整表清空」会让长寿进程周期性重新补算整条链。
  static final LinkedHashMap<String, WeatherDay> _cache =
      LinkedHashMap<String, WeatherDay>();

  /// 约束链的**绝对锚点**（[kWeatherCalendarEpochYear] / 月 / 日）。
  ///
  /// 锚点之前：只落权重（裸桶），不套软约束（没有更早的历史可参照）。
  static final DateTime _epoch = DateTime(
    kWeatherCalendarEpochYear,
    kWeatherCalendarEpochMonth,
    kWeatherCalendarEpochDay,
  );

  // ── 唯一入口 ──────────────────────────────────────────────────────────────

  /// 给定日期 → 当天 [WeatherDay]（**纯函数**：同一日期永远同一结果）。
  ///
  /// 只读 `day.year / day.month / day.day`，**时分秒与 UTC 标志一律忽略**
  /// （口径 = 孩子设备本地自然日）。
  static WeatherDay ofDay(DateTime day) {
    final DateTime natural = DateTime(day.year, day.month, day.day);
    final String key = dayKey(natural);
    final WeatherDay? cached = _cache[key];
    if (cached != null) return cached;
    return _resolve(natural);
  }

  /// 按日型直接取参数（不涉及日期）。
  ///
  /// 存在意义：道具侧（该买哪种棚）、文案侧（该显示哪句）只需知道日型，
  /// 不该自己重抄一遍乘数表 —— 防孪生（同仓 S2 纪律）。
  static WeatherDay ofKind(WeatherKind kind) => _table[kind]!;

  /// 日型权重（= 概率百分位，合计 100）。
  static int weightOf(WeatherKind kind) => _weights[kind.index];

  /// 清空缓存（**仅供测试与诊断**：缓存无副作用，只影响耗时）。
  ///
  /// 让「同一日期在**冷缓存**与**热缓存**下结果一致」成为可断言的事实，
  /// 也就是「软约束链条与查询顺序无关」这条确定性纪律的可验证形式。
  static void clearCache() {
    _cache.clear();
  }

  // ── 日期口径 ──────────────────────────────────────────────────────────────

  /// `dayKey(day) = 'yyyy-MM-dd'`（补零，如 `2026-11-02`）。
  ///
  /// 与 `core/utils/datetime_ext.dart` 的同名函数口径一致，但这里**故意不依赖
  /// intl / DateFormat**：哈希的输入必须逐字节可预期（DateFormat 会受 locale
  /// 与平台实现影响），拼装写死才谈得上「跨版本不得改动」。
  static String dayKey(DateTime day) {
    final String y = day.year.toString().padLeft(4, '0');
    final String m = day.month.toString().padLeft(2, '0');
    final String d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 自然日平移（`day + delta` 天；月/年溢出由 [DateTime] 构造器自动归一）。
  static DateTime _shift(DateTime day, int delta) =>
      DateTime(day.year, day.month, day.day + delta);

  // ── 哈希与落桶 ────────────────────────────────────────────────────────────

  /// FNV-1a 32bit（返回 32bit 无符号，落在 `[0, 2^32)`）。
  ///
  /// 输入恒为 ASCII（`yyyy-MM-dd` + [kWeatherSaltV1]），故 `codeUnit` 即 UTF-8
  /// 单字节流；非 ASCII 的 codeUnit 走「低字节 + 高字节」折叠（防御分支，
  /// 正常路径不可达）。VM 的 `int` 是 64 位，`32bit × 32bit` 的乘积不会溢出，
  /// 故每步 `& 0xFFFFFFFF` 的结果在平台间一致。
  ///
  /// 实现上**不拼 `dayKey + salt` 字符串、也不取 `codeUnits` 列表**（两者都会
  /// 每次分配内存，而冷启动要连算两万天）：先吃 dayKey 的字符再吃固定 salt，
  /// 与「拼接后再哈希」是**逐字节等价**的同一字节流。
  static int _fnv1a32(String dayKeyValue) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < dayKeyValue.length; i++) {
      hash = _fnvStep(hash, dayKeyValue.codeUnitAt(i));
    }
    for (int i = 0; i < kWeatherSaltV1.length; i++) {
      hash = _fnvStep(hash, kWeatherSaltV1.codeUnitAt(i));
    }
    return hash;
  }

  /// FNV-1a 的单步：`hash = (hash ^ byte) * prime`，每步截回 32bit。
  static int _fnvStep(int hash, int codeUnit) {
    const int prime = 0x01000193;
    const int mask = 0xFFFFFFFF;
    int h = ((hash ^ (codeUnit & 0xFF)) * prime) & mask;
    if (codeUnit > 0xFF) {
      h = ((h ^ ((codeUnit >> 8) & 0xFF)) * prime) & mask;
    }
    return h;
  }

  /// 落桶：`u = seed / 2^32`，按**累计权重**找到所属桶（0..8）。
  ///
  /// `seed` 的字符流恒为 `dayKey + [kWeatherSaltV1]`（salt 由 [_fnv1a32] 内部追加，
  /// 此处**不得再拼一次**，否则等于盐了两遍、与 §3.1 的公式不符）。
  /// 权重合计 100 ⇒ 等价于「按百分位落桶」，第 i 个桶占
  /// `[前 i 个权重之和, +权重_i) / 100`。末尾兜底 `_weights.length - 1`
  /// 是理论不可达分支（`u < 1` 且合计 100，浮点累加误差也在 1e-16 量级）。
  static int _bucketOf(String dayKeyValue) {
    final int seed = _fnv1a32(dayKeyValue);
    final double u = seed / 4294967296.0;
    double cumulative = 0;
    for (int i = 0; i < _weights.length; i++) {
      cumulative += _weights[i] / 100.0;
      if (u < cumulative) return i;
    }
    return _weights.length - 1;
  }

  /// 裸桶（**只落权重、不套软约束**）：锚点前的日子与理论不可达分支用它。
  static WeatherKind _nakedKind(String dayKeyValue) =>
      WeatherKind.values[_bucketOf(dayKeyValue)];

  // ── 约束链 ────────────────────────────────────────────────────────────────

  /// 补算 `target` 的日型（**迭代、正向回填，无递归 ⇒ 无爆栈风险**）。
  ///
  /// 两步：
  ///  1. **反向走**：从 `target` 逐日往回收集「需要补算的日子」，直到某一天的
  ///     前两天的结论都已在缓存里（或走到锚点前）—— 这就是「链条」的起点；
  ///  2. **正向回填**：从最靠前的一天开始逐日推进，每天用已定稿的「昨天 / 前天」
  ///     套两条软约束，算完立刻入缓存（下一天就能读到）。
  static WeatherDay _resolve(DateTime target) {
    final String targetKey = dayKey(target);
    final WeatherDay? cached = _cache[targetKey];
    if (cached != null) return cached;

    // 锚点之前：裸桶（无更早历史可参照，故不套约束）。
    if (target.isBefore(_epoch)) {
      final WeatherDay bare = _table[_nakedKind(targetKey)]!;
      _put(targetKey, bare);
      return bare;
    }

    // 1) 反向走：从 `target` 逐日往回收集，直到某一天的**前两天的结论齐备**
    //    （已缓存，或落在锚点前＝裸桶）为止。
    //    ⚠️ 已缓存的日子也一并入列：链条必须**逐日连续**，回填时才能用「局部变量
    //    携带昨天/前天」，而不必每天再查两次缓存（冷启动要连算上万天）。
    final List<DateTime> pending = <DateTime>[];
    DateTime cursor = target;
    while (!cursor.isBefore(_epoch)) {
      pending.add(cursor);
      final DateTime prev1Day = _shift(cursor, -1);
      if (_isKnown(prev1Day) && _isKnown(_shift(cursor, -2))) break;
      cursor = prev1Day;
    }

    // 2) 正向回填：`pending` 是倒序的（末尾＝最靠前那天），从末尾往前走；
    //    起点两天的日型从缓存/裸桶取（必已定稿），此后全靠局部变量传递。
    final DateTime first = pending.last;
    WeatherKind prev1 = _kindOf(_shift(first, -1));
    WeatherKind prev2 = _kindOf(_shift(first, -2));

    // 长链补算时，链条中段那上万天插进去也必然被 FIFO 淘汰（[kWeatherCacheMaxEntries]）
    // —— 只缓存**目标侧尾部**（下标越小＝越靠近 target），省掉「插一万条再淘汰六千」的白工。
    // 短链（≤ 上限）则整条都缓存：这些日子都是「下次顺序回看」的昨天/前天。
    final int cacheFrom = pending.length > kWeatherCacheMaxEntries
        ? kWeatherCacheMaxEntries ~/ 2
        : pending.length;

    WeatherDay? result;
    for (int i = pending.length - 1; i >= 0; i--) {
      final String key = dayKey(pending[i]);
      WeatherDay value;
      final WeatherDay? hit = _cache[key];
      if (hit != null) {
        value = hit; // 已定稿的日子：权威值直接沿用（顺带推进链条状态）
      } else {
        value = _table[_pickKind(key, prev1, prev2)]!;
        if (i < cacheFrom) _put(key, value);
      }
      prev2 = prev1; // 前进一天：新「前天」= 旧「昨天」
      prev1 = value.kind; // 新「昨天」= 今天
      result = value;
    }

    // `pending` 恒以 `target` 收尾（首轮迭代必入列且 `target` 未缓存），故 `result`
    // 必已赋值；可空类型只是为了让「正常路径」零假初值。
    final WeatherDay resolved = result ?? _table[_nakedKind(targetKey)]!;
    // 目标日可能因「只缓存尾部」而没入缓存，补写一次：下次查询 O(1)。
    if (!_cache.containsKey(targetKey)) _put(targetKey, resolved);
    return resolved;
  }

  /// 某天的结论是否已可用（已缓存、或落在锚点前＝裸桶）。
  static bool _isKnown(DateTime day) =>
      day.isBefore(_epoch) || _cache.containsKey(dayKey(day));

  /// 取某天的**已定稿**日型。
  ///
  /// 只会在两种情况下走到「未缓存」：① 锚点前（裸桶，口径明确）；
  /// ② 理论不可达分支（[WeatherSystem._resolve] 的反向走已保证前两天齐备）。
  /// 两种都按裸桶返回 —— 宁可在不可达分支上少套一次软约束，也不抛异常
  /// （纯函数层不允许把异常抛到 UI 主流程）。
  static WeatherKind _kindOf(DateTime day) {
    final String key = dayKey(day);
    final WeatherDay? cached = _cache[key];
    if (cached != null) return cached.kind;
    return _nakedKind(key);
  }

  /// 落桶 + 顺延，直到得到一个**合法**日型。
  ///
  /// 顺延最多 [kWeatherRebucketMaxAttempts] 次（= 9，相当于把 9 个桶全试一遍）；
  /// 第 9 次仍不合法是**理论不可达**（同型极端被约束 ② 挡住时，往后顺延必然先
  /// 撞上另一种极端——它是合法的，直接命中；温和 5 种里最多只有 1 种被约束 ①
  /// 挡住 ⇒ 至少 4 个合法桶），届时兜底返回原桶：宁可偶发违反一次软约束，
  /// 也不留死循环。
  static WeatherKind _pickKind(
    String dayKeyValue,
    WeatherKind prev1,
    WeatherKind prev2,
  ) {
    final int base = _bucketOf(dayKeyValue);
    int bucket = base;
    for (int attempt = 0; attempt < kWeatherRebucketMaxAttempts; attempt++) {
      final WeatherKind candidate = WeatherKind.values[bucket];
      if (_isAllowed(candidate, prev1, prev2)) return candidate;
      bucket = (bucket + 1) % WeatherKind.values.length; // 超出末尾回绕到第一个桶
    }
    return WeatherKind.values[base];
  }

  /// 软约束判据（两条，纯函数）：
  ///  ① 同一日型不得连续出现 3 天（昨天、前天都同型 ⇒ 今天不能再来一次）；
  ///  ② **同一种**极端不得连续两天（昨天也是「同一个」极端 ⇒ 今天不能再来一次）。
  ///
  /// 🔴 约束 ② 的口径是「**同型**极端不连续」，**不是**「任何两种极端不连续」：
  /// 后者与「极端概率 20%」数学互斥（稳态解只有 1/6 ≈ 16.67%，见
  /// `docs/天气系统_最终方案.md` 与 team-lead 2026-11-02 的裁定），而玄参重申
  /// 「极端 20% 的概率保持不变」⇒ **让的是约束，不是概率**。
  /// 干旱→暴雨 是**允许**的（那本来就是天气变化）；干旱→干旱 才重选。
  /// 顺延方向仍是「下一个桶」，故干旱被挡会落到大风（另一种极端，合法），
  /// 极端总量几乎不损失；只有暴雨（最后一个极端桶）被挡才回绕到 sunny，
  /// 概率约 `0.03 × 0.03` ⇒ sunny 只多 0.09pp。
  static bool _isAllowed(
    WeatherKind candidate,
    WeatherKind prev1,
    WeatherKind prev2,
  ) {
    if (candidate == prev1 && candidate == prev2) return false;
    if (candidate.isExtreme && candidate == prev1) return false;
    return true;
  }

  /// 入缓存（FIFO 淘汰：超上限丢最旧一条，见 [kWeatherCacheMaxEntries]）。
  static void _put(String key, WeatherDay value) {
    _cache[key] = value;
    while (_cache.length > kWeatherCacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
