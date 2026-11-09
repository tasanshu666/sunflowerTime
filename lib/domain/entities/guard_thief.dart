/// 偷菜贼（3 种）+ **单点规格表** + 确定性派生入口。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.4 / §6。
///
/// ## 纪律
///  · **权重与偷取区间只在本文件出现一次**（UI / 领域服务一律读 [GuardThiefSpec]，
///    不得各自 `-2` / `* 0.03`）；
///  · **禁止 `Random`**：派生走 `core/utils/stable_hash.dart` 的确定性哈希
///    （`dayKey + childId + kGuardDaySaltV2 + 通道`）；
///  · **零 CJK 字面量**：`test/i18n/no_han_in_domain_test.dart` 钉死
///    「`lib/domain/**` 注释外零 CJK」。三种贼的中文名（馋光鼠 / 啃叶虫 / 顺手贼）
///    与所有上屏文案**留到第二批进 ARB**，本文件只提供稳定 ASCII [GuardThiefSpec.id]
///    与 [GuardThiefSpec.emoji]（emoji 是符号，与 `TaskCategoryX.icon` 同理；
///    中文名绝不写成 Dart 字符串常量）。
library guard_thief;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/stable_hash.dart';

/// 确定性通道名（小偷种类）。
///
/// 🔴 **一经写入即冻结**：改了它等于让历史每一天的「来的是哪只贼」全部重掷。
const String kGuardChannelThief = 'thief';

/// 偷菜贼种类（P0 全做，3 种）。
///
/// 顺序 = 权重表的顺序（[kGuardThiefWeights] 的下标一一对应），**不要重排**：
/// 重排会让「落桶下标」与「权重」错位。
enum GuardThiefKind {
  /// 馋光鼠：只扣阳光余额 1~3 ☀，**不碰植物**。常见（权重 0.45）。
  sunRat,

  /// 啃叶虫：只偷成长 1~3%（**随机 1 株**存活株），不碰阳光。常见（权重 0.45）。
  leafBug,

  /// 顺手贼：偷阳光 1~3 ☀ **且** **全部存活株**各 −1~5% 成长。稀有（权重 0.10）。
  sneakThief;

  /// 今天的贼是谁 —— **确定性派生**（禁 `Random`）。
  ///
  /// seed = `dayKey|childId<kGuardDaySaltV2>|[kGuardChannelThief]`，按
  /// [kGuardThiefWeights] 的累计权重落桶。同一 `dayKey + childId` 恒得同一结果，
  /// 故「杀进程重进」不会重掷、「跳过动画」与「看完动画」拿到的是同一只贼。
  static GuardThiefKind roll(
      {required String dayKey, required String childId}) {
    final double u = deterministicUniform(
      dayKey: dayKey,
      childId: childId,
      salt: kGuardDaySaltV2,
      channel: kGuardChannelThief,
    );
    final List<double> weights = <double>[
      for (final GuardThiefKind kind in GuardThiefKind.values) kind.weight,
    ];
    return GuardThiefKind.values[bucketOfUniform(u, weights)];
  }
}

/// 一个贼种的**全部**数值规格（权重 / 偷阳光区间 / 偷成长区间 / 命中范围）。
///
/// 全字段只读；[GuardThiefSpec] 实例只由 [kGuardThiefSpecs] 单点构造。
class GuardThiefSpec {
  /// 稳定 ASCII id（冻结；`GuardDayState.toJson` 的线名就是它）。
  final String id;

  /// 占位图形（emoji = 符号，不是文案；正式美术素材在 P1 替换）。
  final String emoji;

  /// 出现权重（合计必须 = 1.0，见 [kGuardThiefWeights]）。
  final double weight;

  /// 偷阳光下限。单位：☀。0 = 这个贼不偷阳光。
  final int sunStealMin;

  /// 偷阳光上限。单位：☀。0 = 这个贼不偷阳光。
  final int sunStealMax;

  /// 偷成长下限。单位：进度比例（0.01 = 1 个百分点 pp）。0 = 不偷成长。
  final double growthStealMinPct;

  /// 偷成长上限。单位：进度比例。0 = 不偷成长。
  final double growthStealMaxPct;

  /// 是否**全部存活株**都被偷成长。
  ///
  /// `false` 的两种含义由 [targetsSingleRandomPlant] 区分：
  ///  · 不偷成长（[stealsGrowth] = false）→ 本字段也无意义；
  ///  · 偷成长但只命中随机 1 株（[targetsSingleRandomPlant] = true）。
  final bool hitsEveryPlant;

  /// 是否「只随机命中 1 株存活株」（啃叶虫）。
  final bool targetsSingleRandomPlant;

  const GuardThiefSpec({
    required this.id,
    required this.emoji,
    required this.weight,
    required this.sunStealMin,
    required this.sunStealMax,
    required this.growthStealMinPct,
    required this.growthStealMaxPct,
    required this.hitsEveryPlant,
    required this.targetsSingleRandomPlant,
  });

  /// 这个贼会不会偷阳光。
  bool get stealsSun => sunStealMax > 0;

  /// 这个贼会不会偷成长。
  bool get stealsGrowth => growthStealMaxPct > 0;
}

/// 🔑 **单点规格表**：3 种贼的全部数值（PRD §3.4 表逐条落地）。
///
/// 数值冲突时以 `prd_params.dart` 的 `kGuard*` 常量为准，本表只做「种类 → 常量」
/// 的绑定，不重复写数值。
///
/// 为什么是 `Map` 而不是枚举构造参数：`kGuardThiefWeights[0]` 不是常量表达式，
/// 枚举的 const 构造器吃不了；用不可变表既保住了「数值只出现一次」，又让
/// 「权重下标 = 枚举下标」这条约定可被单测钉死。
final Map<GuardThiefKind, GuardThiefSpec> kGuardThiefSpecs =
    Map<GuardThiefKind, GuardThiefSpec>.unmodifiable(
  <GuardThiefKind, GuardThiefSpec>{
    GuardThiefKind.sunRat: GuardThiefSpec(
      id: 'sun_rat',
      emoji: '🐭',
      weight: kGuardThiefWeights[0],
      sunStealMin: kGuardSunStealMin,
      sunStealMax: kGuardSunStealMax,
      growthStealMinPct: 0,
      growthStealMaxPct: 0,
      hitsEveryPlant: false,
      targetsSingleRandomPlant: false,
    ),
    GuardThiefKind.leafBug: GuardThiefSpec(
      id: 'leaf_bug',
      emoji: '🐛',
      weight: kGuardThiefWeights[1],
      sunStealMin: 0,
      sunStealMax: 0,
      growthStealMinPct: kGuardGrowthStealMinPct,
      growthStealMaxPct: kGuardGrowthStealMaxPct,
      hitsEveryPlant: false,
      targetsSingleRandomPlant: true,
    ),
    GuardThiefKind.sneakThief: GuardThiefSpec(
      id: 'sneak_thief',
      emoji: '🦝',
      weight: kGuardThiefWeights[2],
      sunStealMin: kGuardSunStealMin,
      sunStealMax: kGuardSunStealMax,
      growthStealMinPct: kGuardGrowthStealMinPct,
      growthStealMaxPct: kGuardSlyGrowthStealMaxPct,
      hitsEveryPlant: true,
      targetsSingleRandomPlant: false,
    ),
  },
);

/// [GuardThiefKind] 的规格读取入口（唯一推荐写法：`kind.spec`）。
extension GuardThiefKindX on GuardThiefKind {
  /// 本种类的单点规格。
  GuardThiefSpec get spec => kGuardThiefSpecs[this]!;

  /// 稳定 ASCII id（冻结，用于 JSON / 埋点）。
  String get id => spec.id;

  /// 占位图形。
  String get emoji => spec.emoji;

  /// 出现权重。
  double get weight => spec.weight;

  /// 会不会偷阳光。
  bool get stealsSun => spec.stealsSun;

  /// 会不会偷成长。
  bool get stealsGrowth => spec.stealsGrowth;
}

/// 由 JSON / 埋点线名反查种类（未知 id 返回 `null`，不抛异常）。
///
/// 走「不抛」而不是「抛」的理由：`SharedPreferences` 里的旧 JSON 可能来自未来
/// 版本（降级安装），一个未知 id 不该让今日页崩掉。
GuardThiefKind? guardThiefKindFromId(String? id) {
  if (id == null) return null;
  for (final GuardThiefKind kind in GuardThiefKind.values) {
    if (kind.id == id) return kind;
  }
  return null;
}
