/// 空花盆干扰物仓储抽象（F155-B，玄参 2026-10-27 拍板）。
///
/// 与 [PlantRepository] 同构：**接口零 Flutter / 零 drift 依赖**，实现放在
/// `data/local/repositories/`，读写按**当前孩子**过滤（实现内部完成，签名不变）。
///
/// 单键是 `potIndex`（与 `Plants.potIndex` 同一坐标系）—— 空盆没有植物 id 可挂。
library pot_disturbance_repository;

import 'package:sunflower_time/domain/entities/pot_disturbance.dart';

abstract class PotDisturbanceRepository {
  /// 当前孩子的**全部**空盆干扰物记录（含当日无干扰物的「已 roll」行）。
  Future<List<PotDisturbance>> disturbances();

  /// 读某个花盆的记录；不存在（该盆从未 roll 过）返回 `null`。
  Future<PotDisturbance?> disturbanceOf(int potIndex);

  /// 插入或更新（按复合主键 `(childId, potIndex)` 冲突合并）。
  Future<void> save(PotDisturbance disturbance);

  /// 删除某个花盆的记录（**种下植物时**调用：该盆不再是空盆）。
  Future<void> deletePot(int potIndex);

  /// 清空当前孩子的全部记录（数据管理 / 删除全部本地数据用）。
  Future<void> deleteAll();
}
