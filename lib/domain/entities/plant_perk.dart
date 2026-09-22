/// 植物能力（Perk）接口骨架 + 掉落物数据模型（M3 纯领域层）。
///
/// 目的：把「成株之后还能接什么玩法」收敛成一份纯 Dart 契约——UI 只依赖
/// [PlantPerk] 抽象，不依赖任何一种具体玩法；新增玩法时只需实现本接口并
/// 注册进 `PlantPerkRegistry`，页面 / 数据库 / 路由零改动。
///
/// 约束（本轮只交付骨架，不含任何具体规则）：
///  · **无数值、无定时、无落库**：本文件不定义产出多少、多久产出一次、
///    也不定义表结构；[PlantDrop] 只是内存态的可收集物快照。
///  · **纯 Dart**：禁止 import flutter 及任何 UI 包，保证 `dart test` 与
///    `flutter test` 都能直接跑，领域层可独立单测。
///  · **只描述状态、不执行动作**：[PlantPerk.evaluate] 回答「此刻是什么状态」，
///    Perk 自身不得改数据、不得持有仓储、不得访问数据库。
///  · **时间由调用方注入**：所有需要「现在」的判定都收 `now` 形参，实体内
///    绝不调用 `DateTime.now()`，否则单测无法固定时间、真机边界也无法复现。
///
/// 为什么这么设计：
///  · 注册表默认为空 → 当前 UI 不会凭空出现任何玩法入口；这是本轮预期，
///    未来接玩法只是「实现 + register」一步，不回头改公共代码。
///  · [PlantPerkKind] 只给一个 `custom` 兜底：未来新玩法不必先回来改枚举，
///    避免每次扩展都动公共枚举引发全量回归。
///  · [PlantPerk.isUnlocked] 给默认实现（成株 / 已开花 且 非枯萎非死亡），
///    让「门槛」这一共性逻辑只写一处，特殊玩法再自行覆盖。
library plant_perk;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 能力种类。
///
/// `sunlightDrop` 表示「产出可被收集的一次性掉落物」；其余未来玩法统一走
/// `custom` 兜底，避免在公共枚举里塞入尚未确定的语义。
enum PlantPerkKind {
  /// 产出可收集的阳光掉落物。
  sunlightDrop,

  /// 其余未来能力的兜底种类（语义由具体 Perk 自己解释）。
  custom,
}

/// 能力在某株植物上的当前状态（UI 据此决定入口显隐）。
enum PlantPerkState {
  /// 未解锁：该植物当前不具备此能力，UI 不显示入口。
  locked,

  /// 已解锁但此刻没有可交互内容：UI 不提示（不打扰孩子）。
  idle,

  /// 已解锁且此刻有可交互内容：UI 显示入口 / 提示。
  ready,
}

/// 植物能力契约（抽象基类，子类实现具体玩法）。
///
/// 实现类必须是**无副作用**的状态判定器：同样的入参必须给出同样的结果，
/// 便于单测与 UI 反复重建（build 期间会被调用多次）。
abstract class PlantPerk {
  /// 常量构造：子类（及测试替身）可声明为 const，便于在单测里复用同一实例。
  const PlantPerk();

  /// 全局唯一 id（注册表按 id 去重，重复注册会抛 `StateError`）。
  String get id;

  /// 能力种类。
  PlantPerkKind get kind;

  /// 给孩子看的短名（UI 文案，非规则）。
  String get displayName;

  /// 该植物此刻是否具备此能力。
  ///
  /// 默认门槛：非枯萎、非死亡，且（已成株 或 已开花）。
  /// 子类可覆盖以放宽 / 收紧门槛；本方法必须纯函数、无副作用。
  bool isUnlocked(Plant plant, PlantSpecies species) {
    if (plant.status == PlantStatus.wilting) return false;
    if (plant.status == PlantStatus.dead) return false;
    return plant.stage == PlantStage.adult || plant.status == PlantStatus.bloomed;
  }

  /// 评估此刻状态（[PlantPerkState.locked] / [PlantPerkState.idle] /
  /// [PlantPerkState.ready]）。
  ///
  /// 只描述「当前状态」，不含任何数值规则；`now` 由调用方注入以保证可测。
  PlantPerkState evaluate({
    required Plant plant,
    required PlantSpecies species,
    required DateTime now,
  });
}

/// 可收集掉落物（纯数据模型）。
///
/// 仅表达「有一次可被收集的东西、它什么时候过期、被谁收走了」：
///  · **不落库**：本轮没有对应表，实例只存在于内存 / 由调用方自行持久化；
///  · **不含规则**：何时生成、生成多少由未来的具体 Perk 决定，这里不定义。
class PlantDrop {
  /// 掉落物唯一 id。
  final String id;

  /// 所属植物 id。
  final String plantId;

  /// 掉落物对应的能力种类（决定 UI 表现与入账口径）。
  final PlantPerkKind kind;

  /// 生成时刻。
  final DateTime createdAt;

  /// 过期时刻（此刻起不可再收集；判定含左不含右，见 [isCollectableAt]）。
  final DateTime expiresAt;

  /// 收集时刻（null 表示尚未被收集）。
  final DateTime? collectedAt;

  /// 阳光数量；`kind != PlantPerkKind.sunlightDrop` 时为 0。
  final int amount;

  const PlantDrop({
    required this.id,
    required this.plantId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    this.collectedAt,
    this.amount = 0,
  });

  /// 是否已被收集（与「是否过期」正交：已收集的不论过期与否都算收集过）。
  bool get isCollected => collectedAt != null;

  /// 在 `now` 时刻是否可被收集：未收集 且 尚未过期。
  ///
  /// 边界：正好等于 [expiresAt] 视为**已过期**（返回 false），即区间为
  /// `[createdAt, expiresAt)`，避免「同一时刻既有效又失效」的双重判定。
  bool isCollectableAt(DateTime now) => !isCollected && now.isBefore(expiresAt);

  /// 标记已收集后的不可变副本（其余字段原样保留）。
  PlantDrop copyWith({DateTime? collectedAt}) {
    return PlantDrop(
      id: id,
      plantId: plantId,
      kind: kind,
      createdAt: createdAt,
      expiresAt: expiresAt,
      collectedAt: collectedAt ?? this.collectedAt,
      amount: amount,
    );
  }
}
