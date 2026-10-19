/// 孩子档案仓储抽象（C90 期 1，玄参 2026-10-17 拍板）。
///
/// ⚠️ 本接口**独立新建**（不动任何现有接口）—— 仓内教训：
/// `implements FocusRepository` 的实现类有 57 处，往既有接口加方法会连锁爆。
/// Drift 实现在 `lib/data/local/repositories/child_profile_local_repository.dart`。
library child_profile_repository;

import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

abstract class ChildProfileRepository {
  /// 全部档案（按创建时间升序；「第一个孩子」= 最早建的默认孩子）。
  Future<List<ChildProfile>> children();

  /// 新建档案并返回（uuid 自生成；[id] 仅供 AccountService 建默认孩子时
  /// 固定为 `kChildIdDefault`，业务调用方一律不传）。
  ///
  /// 🔴 门控配额（免费 1 / 买断 3）在**调用方**（家长 UI / AccountService 判定，
  /// 矩阵单点 `quotaAllowsAdd`）；本仓储只管落库。C69 红线指的是「超额只拦新增」，
  /// 玄参拍板的**主动删除**（家长 PIN 复核）见 [deleteById]。
  Future<ChildProfile> create(String name, AgeTier ageTier, {String? id});

  /// 档案总数（门控配额核算用，只读计数）。
  Future<int> count();

  /// 更新档案（改名 / 调年龄段；id 与 createdAt 不变，C90 期 1 追加）。
  /// 编辑**不受门控配额限制**（不是新增，C69 只拦新增）。
  ///
  /// C90-C：可选 [avatar]（null = 不改头像；[kChildAvatarSun] = 阳光，
  /// 否则为植物物种 id）。
  Future<void> update(
    String id, {
    required String name,
    required AgeTier ageTier,
    String? avatar,
  });

  /// 按 id 删除档案（C90 期 1 追加，玄参拍板：需家长 PIN 复核）。
  ///
  /// 🔴 兜底纪律在**调用方**：① 至少保留一个档案；② 家长 PIN 复核通过才允许；
  /// ③ 删除的是当前孩子时自动切到剩余第一个。本仓储只管落库。
  Future<void> deleteById(String id);
}
