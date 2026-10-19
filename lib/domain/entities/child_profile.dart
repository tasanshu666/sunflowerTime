/// 孩子档案实体（C90 期 1，玄参 2026-10-17 拍板；C90-C 增头像）。
///
/// 口径（与 tables.dart `ChildProfiles` 注释一致）：
///  · 设备同一时刻只有一个「当前孩子」，切换入口只在家长天地；
///  · 免费 1 个 / 买断最多 3 个，门控只拦新增、绝不删已存档案（C69）；
///  · 数据隔离期 2 实施：兑换记录等业务数据按 childId 隔离；
///  · `ageTier` 跟孩子走（期 2 已接线，玄参拍板）；
///  · **C90-C（2026-10-18）**：`avatar` 跟孩子走 —— 默认阳光（[kChildAvatarSun]），
///    可选该孩子**已种植过**的植物物种 id（未种植的物种不可选，见孩子端
///    「我的」页头像选择面板），切孩子各用各的。
library child_profile;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.ageTier,
    required this.createdAt,
    this.avatar = kChildAvatarSun,
  });

  /// 档案 id（uuid；默认孩子固定 = `kChildIdDefault`）。
  final String id;

  /// 孩子名（家长在家长天地维护）。
  final String name;

  /// 年龄段（跟孩子走；家长天地编辑可调）。
  final AgeTier ageTier;

  /// 创建时间。
  final DateTime createdAt;

  /// 头像（**C90-C**）：[kChildAvatarSun] = 阳光（默认）；否则为植物物种 id。
  final String avatar;

  ChildProfile copyWith({String? name, AgeTier? ageTier, String? avatar}) =>
      ChildProfile(
        id: id,
        name: name ?? this.name,
        ageTier: ageTier ?? this.ageTier,
        createdAt: createdAt,
        avatar: avatar ?? this.avatar,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildProfile &&
          other.id == id &&
          other.name == name &&
          other.ageTier == ageTier &&
          other.createdAt == createdAt &&
          other.avatar == avatar;

  @override
  int get hashCode => Object.hash(id, name, ageTier, createdAt, avatar);

  @override
  String toString() => 'ChildProfile($id, $name, $ageTier, avatar: $avatar)';
}
