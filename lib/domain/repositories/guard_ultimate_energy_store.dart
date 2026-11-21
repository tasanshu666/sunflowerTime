/// 大招能量存储抽象 + 专注结算累计 writer 抽象（纯 Dart / 零 plugins）。
///
/// 与旧 `GuardEnergyStore` **刻意分离**：另起一套接口、另起 key，杜绝
/// 两套能量混写（口径 1 / C3 / 架构 §8-S1）。
library guard_ultimate_energy_store;

import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';

/// 读写一个孩子的大招能量快照 + 幂等去重集合。
abstract class GuardUltimateEnergyStore {
  /// 读能量（无记录 / 坏数据 ⇒ [UltimateEnergy.empty]）。
  Future<UltimateEnergy> read(String childId);

  /// 覆盖写能量快照。
  Future<void> write(String childId, UltimateEnergy energy);

  /// 读已计入的 sessionId 集合（幂等账本，与旧能量集合物理隔离）。
  Future<Set<String>> readCreditedSessionIds(String childId);

  /// 覆盖写已计入的 sessionId 集合。
  Future<void> writeCreditedSessionIds(String childId, Set<String> ids);
}

/// 专注结算累计入口（可选注入 `SunlightService`，缺省 null 老链路零改动）。
abstract class UltimateFocusWriter {
  /// 累计落库唯一入口；幂等键 = [sessionId]。
  ///
  /// 返回 `true` = 本次实际计入；`false` = 已计入（幂等命中，跳过）。
  Future<bool> creditFocus({
    required String sessionId,
    required String childId,
    required double actualFocusMin,
  });
}
