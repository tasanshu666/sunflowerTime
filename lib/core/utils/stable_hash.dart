/// 确定性哈希工具（🔴 **禁止 `Random`** 的玩法共用此一处实现）。
///
/// ## 为什么需要它
/// 天气系统（`domain/services/weather_system.dart`）已经把「同一 `dayKey` 在任何
/// 设备 / 任何时刻都得到同一结果」立成纪律。花园守卫玩法继承同一条纪律
/// （PRD v2 §3.1）：`seed = dayKey + childId + kGuardDaySaltV2`，**一次派生**
/// 「小偷种类 + 偷取值 + 掉落档 + 保底阳光」的全部字段。
///
/// 三条收益（PRD §3.1 原话）：① 可单测、可重放、可调试（「强制出贪婪鼬」才有意义）；
/// ② 杀进程 + 重进不会重掷（跳过动画与看完动画结果必须逐位相同）；
/// ③ 不引入第二套随机语言。
///
/// ## 为什么单独抽文件而不是复制天气那份
/// 天气那份 [_fnv1a32] 是 `private` 的**单盐**实现（盐写死为天气盐，且不带
/// childId）。守卫需要「同一 seed 派生多个互不相关的字段」，因此本文件把
/// **「哈希原语」与「seed 拼装」拆开**，并引入 [channel]（通道）做域隔离：
/// 同一 `dayKey + childId` 下，`thief` / `drop` / `sun` / `growth` / `win` 五个
/// 通道的均匀值必须互不相关，否则「小偷种类」与「掉落档」会绑死（抽到贪婪鼬
/// 就一定出免费施肥券之类）。
///
/// ## 与天气那份的关系
/// 两者**刻意不共享实现**：天气的盐与输入格式已经冻结（`kWeatherSaltV1`，
/// 「跨版本不得改动」），任何一次「为了复用而重构」都有让历史天气不可重放的风险。
/// 本文件是新增的独立实现，只服务新玩法。
library stable_hash;

/// FNV-1a 32bit 的初始值（FNV offset basis）。
const int _fnvOffsetBasis = 0x811c9dc5;

/// FNV-1a 32bit 的乘法质数（FNV prime）。
const int _fnvPrime = 0x01000193;

/// 32bit 掩码（每步截回 32bit，保证跨平台逐位一致）。
const int _fnvMask = 0xFFFFFFFF;

/// 2^32（把 32bit 无符号整数映射到 `[0, 1)` 的分母）。
const double _unitDenominator = 4294967296.0;

/// FNV-1a 32bit 哈希（返回 32bit 无符号，落在 `[0, 2^32)`）。
///
/// 输入是 ASCII 为主的 seed 串（`dayKey|childId|salt|channel`）。VM 的 `int` 是
/// 64 位，`32bit × 32bit` 的乘积不会溢出，故每步 `& 0xFFFFFFFF` 的结果在
/// 平台间一致 —— 这是「跨设备可重放」的前提。
///
/// 非 ASCII 字符（如中文 childId）走「低字节 + 高字节」折叠（防御分支）：UTF-16
/// codeUnit 逐位吃进去，仍然是**同一输入 ⇒ 同一输出**的纯函数。
int fnv1a32(String value) {
  int hash = _fnvOffsetBasis;
  for (int i = 0; i < value.length; i++) {
    final int unit = value.codeUnitAt(i);
    hash = ((hash ^ (unit & 0xFF)) * _fnvPrime) & _fnvMask;
    if (unit > 0xFF) {
      hash = ((hash ^ ((unit >> 8) & 0xFF)) * _fnvPrime) & _fnvMask;
    }
  }
  return hash;
}

/// 拼装确定性 seed：`dayKey|childId<salt>|channel`。
///
/// 🔴 **格式一经写入即冻结**（改了它 = 改历史掉落结果）。[salt] 原样拼接，
/// 因为现有盐常量自带前导 `|`（[kGuardDaySaltV2] = `'|guard|v2'`），
/// 拼出来是 `2026-11-08|child-1|guard|v2|thief`，与 PRD §3.1 的
/// `'$dayKey|$childId|$kGuardDaySaltV2'` 逐字节一致。
///
/// [channel] 是**域隔离后缀**：同一 `dayKey + childId` 下不同通道的均匀值
/// 必须互不相关（见库注释）。
String deterministicSeed({
  required String dayKey,
  required String childId,
  required String salt,
  required String channel,
}) {
  return '$dayKey|$childId$salt|$channel';
}

/// 由 seed 派生 `[0, 1)` 的确定性均匀值（`u = hash / 2^32`）。
///
/// 用法：把 `u` 与「累计概率」比较即可落桶（见 `GuardThiefKind.roll` /
/// `GuardDropKind.roll`），或线性映射到闭区间取整（见 `guard_math.dart`）。
double uniformFromSeed(String seed) => fnv1a32(seed) / _unitDenominator;

/// [deterministicSeed] + [uniformFromSeed] 的合并入口（避免调用方写两行、
/// 也避免某处漏加 channel 导致通道串味）。
double deterministicUniform({
  required String dayKey,
  required String childId,
  required String salt,
  required String channel,
}) {
  return uniformFromSeed(
    deterministicSeed(
      dayKey: dayKey,
      childId: childId,
      salt: salt,
      channel: channel,
    ),
  );
}

/// 按「累计权重」把 [u]（`[0,1)`）落桶，返回下标（`0..weights.length-1`）。
///
/// 末尾兜底 `weights.length - 1` 是理论不可达分支（`u < 1` 且权重合计 = 1.0，
/// 浮点累加误差在 1e-16 量级）。权重为 0 的桶永远不会被落中（区间宽度 0），
/// 这正是「某个档不可能出现」的实现基础。
///
/// [u] 越界（NaN / 负数）时按第一桶处理：本函数只服务确定性派生，不做入参校验，
/// 但**绝不抛异常**（否则一个坏 seed 就能让今日页崩）。
int bucketOfUniform(double u, List<double> weights) {
  if (weights.isEmpty) return 0;
  double cumulative = 0;
  for (int i = 0; i < weights.length; i++) {
    cumulative += weights[i];
    if (u < cumulative) return i;
  }
  return weights.length - 1;
}
