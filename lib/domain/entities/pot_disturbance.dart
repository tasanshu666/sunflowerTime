/// 空花盆干扰物（杂草 / 害虫）—— F155-B（玄参 2026-10-27 拍板）。
///
/// ## 为什么需要它
/// 口径：**空花盆（没种植物）每天也独立 roll 杂草 / 害虫**，清理奖励与植物完全一致
/// （[weedRewardOf] / [pestRewardOf]，含称号加成），频率为植物的一半
/// （[kEmptyPotWeedRate] 0.20 / [kEmptyPotPestRate] 0.15）。空盆没有 `Plant` 行可挂
/// 干扰物，因此需要一份**按盆（potIndex）**定位的独立状态。
///
/// ## 与 [Plant] 的语义对齐（逐字一致，别另立口径）
///  · `weedAt` / `pestAt` = 「**出现当天零点**」；非当天即自动失效（次日零点 ≠ 今日零点）；
///  · `rollDay` = 「每日 roll 已执行的当天零点」（幂等锚）：同日重复 tick **不重 roll**；
///  · `hasWeed` / `hasPest` = 非 null 即存在（过期由 `tick` 统一改写，读侧不重复判日）。
///
/// 与原 [Plant] 的差异只有一处：空盆干扰物**不阻断种植**（点空盆照常弹种植选择），
/// 种下后该盆的记录立即删除（不返还、不再显示）。
library pot_disturbance;

/// 单个空花盆的干扰物状态（不可变值对象）。
class PotDisturbance {
  /// 花盆序号（0 基，与 `Plants.potIndex` 同一坐标系）。
  final int potIndex;

  /// 杂草出现的当天零点；`null` = 无杂草。
  final DateTime? weedAt;

  /// 害虫出现的当天零点；`null` = 无害虫（与 [weedAt] 互不影响、可同时存在）。
  final DateTime? pestAt;

  /// 「杂草 / 害虫每日 roll」已执行的那天零点（幂等基准）；`null` = 尚未 roll。
  final DateTime? rollDay;

  const PotDisturbance({
    required this.potIndex,
    this.weedAt,
    this.pestAt,
    this.rollDay,
  });

  /// 当前是否有杂草。
  bool get hasWeed => weedAt != null;

  /// 当前是否有害虫。
  bool get hasPest => pestAt != null;

  /// 杂草 / 害虫任一存在（UI 判断「要不要渲染浮标」用）。
  bool get hasPestOrWeed => weedAt != null || pestAt != null;

  /// copyWith 的「清空」哨兵（仅用于 [weedAt] / [pestAt] / [rollDay] 三个可空日期字段）。
  ///
  /// 与原 [Plant] 同款三态写法（同一坑：`x ?? this.x` 让显式 null 清不掉字段），
  /// 置 null 的写法是 `pot.copyWith(weedAt: PotDisturbance.kClear)`。
  static const Object kClear = _PotDisturbanceFieldClear();

  /// copyWith 的「未传」标记（默认参数用它；与 [kClear] 必须是不同实例）。
  static const Object _unset = _PotDisturbanceCopyUnset();

  /// 不可变副本（哨兵三态见 [kClear] 的注释）。
  PotDisturbance copyWith({
    int? potIndex,
    Object? weedAt = _unset,
    Object? pestAt = _unset,
    Object? rollDay = _unset,
  }) {
    return PotDisturbance(
      potIndex: potIndex ?? this.potIndex,
      weedAt: _resolve(weedAt, this.weedAt),
      pestAt: _resolve(pestAt, this.pestAt),
      rollDay: _resolve(rollDay, this.rollDay),
    );
  }

  /// 哨兵三态解析：没传 → 保持原值；显式 [kClear] → 置 null；否则取传入值。
  static DateTime? _resolve(Object? arg, DateTime? current) {
    if (identical(arg, _unset)) return current;
    if (identical(arg, kClear)) return null;
    return arg as DateTime?;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PotDisturbance &&
          other.potIndex == potIndex &&
          other.weedAt == weedAt &&
          other.pestAt == pestAt &&
          other.rollDay == rollDay;

  @override
  int get hashCode => Object.hash(potIndex, weedAt, pestAt, rollDay);

  @override
  String toString() => 'PotDisturbance(pot: $potIndex, weedAt: $weedAt, '
      'pestAt: $pestAt, rollDay: $rollDay)';
}

/// [PotDisturbance.kClear] 的载体类型（哨兵）。
class _PotDisturbanceFieldClear {
  const _PotDisturbanceFieldClear();
}

/// [PotDisturbance._unset] 的载体类型（哨兵，语义 = 「本次 copyWith 没碰这个字段」）。
class _PotDisturbanceCopyUnset {
  const _PotDisturbanceCopyUnset();
}
