/// 孩子档案实体（C90 期 1，玄参 2026-10-17 拍板）。
///
/// 口径（与 tables.dart `ChildProfiles` 注释一致）：
///  · 设备同一时刻只有一个「当前孩子」，切换入口只在家长天地；
///  · 免费 1 个 / 买断最多 3 个，门控只拦新增、绝不删已存档案（C69）；
///  · 数据隔离期 2 实施：本期只有兑换记录落新 childId；
///  · `ageTier` 跟孩子走，本期只落列不接线（防沉迷仍读全局 settings）。
library child_profile;

import 'package:sunflower_time/domain/entities/enums.dart';

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.ageTier,
    required this.createdAt,
  });

  /// 档案 id（uuid；默认孩子固定 = `kChildIdDefault`）。
  final String id;

  /// 孩子名（家长在家长天地维护）。
  final String name;

  /// 年龄段（期 2 接线防沉迷；本期仅存档展示）。
  final AgeTier ageTier;

  /// 创建时间。
  final DateTime createdAt;

  ChildProfile copyWith({String? name, AgeTier? ageTier}) => ChildProfile(
        id: id,
        name: name ?? this.name,
        ageTier: ageTier ?? this.ageTier,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildProfile &&
          other.id == id &&
          other.name == name &&
          other.ageTier == ageTier &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, ageTier, createdAt);

  @override
  String toString() => 'ChildProfile($id, $name, $ageTier)';
}
