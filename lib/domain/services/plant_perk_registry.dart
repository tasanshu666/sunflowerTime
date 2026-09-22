/// 植物能力注册表（M3 纯领域层，进程内单例）。
///
/// 目的：作为「植物成株后接玩法」的唯一装配点——UI 只问注册表「这株植物现在
/// 有哪些可用的能力」，不认识任何具体 Perk 实现类，从而做到新增玩法不改页面。
///
/// 约束：
///  · **默认注册表为空**：进程启动后不注册任何 Perk，故 `all` 为空、
///    `hasAnyReady` 恒为 false，**当前 UI 不会出现任何新玩法入口**——这正是
///    本轮预期（骨架先落地，玩法后接）。
///  · 未来接玩法时只需一步：`PlantPerkRegistry.instance.register(MyPerk())`，
///    无需改动本文件、页面、数据库或路由。
///  · **纯 Dart**：禁止 import flutter 及任何 UI / 持久化包，保证纯 dart 单测可跑。
///  · 注册表只做「登记 + 过滤」，不持有状态、不做定时、不落库；
///    `now` 一律由调用方注入，便于单测固定时间。
///
/// 为什么用单例 + 显式 register：
///  能力的装配时机由 App 启动流程决定（而非编译期常量），单例可让任意层
///  在无 BuildContext、无 DI 容器注入的纯 Dart 环境里访问；同时保留
///  `unregisterById` 与 [resetForTest]，避免测试之间互相串味。
library plant_perk_registry;

import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_perk.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';

/// 进程内唯一的 Perk 登记表。
class PlantPerkRegistry {
  PlantPerkRegistry._();

  /// 全局单例（默认不含任何 Perk）。
  static final PlantPerkRegistry instance = PlantPerkRegistry._();

  /// 按注册顺序保存的 Perk 列表（外部只能通过 [all] 拿到不可修改视图）。
  final List<PlantPerk> _perks = <PlantPerk>[];

  /// 注册一个能力。
  ///
  /// 抛 `StateError` 的两种情形（**刻意不用 assert**：release 构建下 assert
  /// 会被剥离，重复注册将静默变成「后注册覆盖 / 重复绘制两份入口」，
  /// 属于真机才炸的隐蔽 bug）：
  ///  · [PlantPerk.id] 为空字符串；
  ///  · 同 id 已注册过（注册表按 id 去重）。
  void register(PlantPerk perk) {
    if (perk.id.isEmpty) {
      throw StateError('PlantPerkRegistry.register: id 不能为空字符串');
    }
    for (final PlantPerk existing in _perks) {
      if (existing.id == perk.id) {
        throw StateError(
          'PlantPerkRegistry.register: 重复的能力 id "${perk.id}"，'
          '请先 unregisterById 再注册',
        );
      }
    }
    _perks.add(perk);
  }

  /// 按 id 注销（不存在时静默无操作，便于装配流程重复调用）。
  void unregisterById(String id) {
    _perks.removeWhere((PlantPerk perk) => perk.id == id);
  }

  /// 全部已注册能力（不可修改视图，防止外部绕过 register 直接改表）。
  List<PlantPerk> get all => List<PlantPerk>.unmodifiable(_perks);

  /// 该植物当前已解锁的能力（[PlantPerk.isUnlocked] 为 true 的子集）。
  List<PlantPerk> unlockedFor({
    required Plant plant,
    required PlantSpecies species,
  }) {
    return _perks
        .where((PlantPerk perk) => perk.isUnlocked(plant, species))
        .toList(growable: false);
  }

  /// 该植物当前「有内容可交互」的能力。
  ///
  /// 先过 [PlantPerk.isUnlocked] 门槛，再取 [PlantPerk.evaluate] 为
  /// [PlantPerkState.ready] 的项——**未解锁的能力即使 evaluate 返回 ready
  /// 也不算命中**，避免子类实现漏判门槛导致 UI 提前放出入口。
  List<PlantPerk> readyFor({
    required Plant plant,
    required PlantSpecies species,
    required DateTime now,
  }) {
    return _perks
        .where((PlantPerk perk) =>
            perk.isUnlocked(plant, species) &&
            perk.evaluate(plant: plant, species: species, now: now) ==
                PlantPerkState.ready)
        .toList(growable: false);
  }

  /// 是否存在任何「有内容可交互」的能力（UI 据此决定要不要显示提示角标）。
  bool hasAnyReady({
    required Plant plant,
    required PlantSpecies species,
    required DateTime now,
  }) {
    return readyFor(plant: plant, species: species, now: now).isNotEmpty;
  }

  /// 清空注册表——**仅供单测使用**。
  ///
  /// 单例跨测试用例共享，不清空会让上一个用例注册的 Perk 泄漏到下一个用例
  ///（尤其在随机执行顺序下表现为「时好时坏」）。生产代码禁止调用。
  void resetForTest() {
    _perks.clear();
  }
}
