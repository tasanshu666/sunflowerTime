import 'package:sunflower_time/domain/entities/enums.dart';

/// 植物（§3.1 plant）。软绑定：绝不因专注差而死（§4.6 H2）。
class Plant {
  final String id;
  final String speciesId;
  final int potIndex;
  final PlantStage stage;
  final DateTime stageStartedAt;
  final double growthProgress; // 当前阶段内进度 0..1
  final double growthFactor; // 1.0 / 1.3（当日有效专注系数）
  final bool waterUsed; // 本阶段是否已浇水
  final bool fertilizerUsed; // 本阶段是否已施肥
  final PlantStatus status;
  final DateTime plantedAt; // 种植时间
  final DateTime? lastWaterAt; // 上次浇水时间（枯萎计时基准）
  final DateTime? wiltedAt; // 枯萎计时起点
  final DateTime? deadAt; // 死亡计时（仅供统计）
  final DateTime? bloomedAt; // 进入「盛开」状态的时刻（花谢循环计时起点；null = 未开花 / 已花谢 / 老库升级来的已开花植物待补计时）
  final int bloomCount; // 累计盛开次数（成株后循环玩法 Batch 1：0 = 未开过花，≥1 = 复开花阶段）
  final PlantMood mood;

  /// 杂草出现的当天零点（同理 [PlantStatus] 之外的干扰物口径 C26）。
  ///
  /// 非 null = 本盆**当前**有杂草；次日每日 roll 时清空（杂草只在其出现的当天有效，
  /// 不会跨天卡成长）。存在期间该株成长暂停，点掉图标即恢复。
  final DateTime? weedAt;

  /// 害虫出现的当天零点（口径 C26）。
  ///
  /// 与 [weedAt] 互不影响、**可同时存在**；语义同 [weedAt]（当天有效 / 成长暂停）。
  final DateTime? pestAt;

  /// 「杂草 / 害虫每日 roll」已执行的那天零点（幂等基准，口径 C26）。
  ///
  /// 同一天重复 tick 不会重复 roll —— 否则「每天发生一次」会退化为「每次 tick 都 roll」，
  /// 杂草会在孩子开着 App 的几小时里凭空冒出来。null = 今日（或史上）尚未 roll。
  final DateTime? weedPestRollDay;

  /// 铲除返还阳光数（口径 C29，玄参 2026-10-05 拍板）。
  ///
  /// **种下时即定好**（领域层 `_chargeForPlanting` 计算落列）：普通档 150（300×50%）/
  /// 精英档 250（500×50%）/ 向日葵免费首株与历史行（v16 前种下）0 = 铲除不返还。
  /// 铲除时按本字段值返还（不返还培养消耗）；死亡株按「死亡全损」口径返还 0。
  final int shovelRefund;

  /// copyWith 的「清空」哨兵（仅用于 [weedAt] / [pestAt] / [weedPestRollDay] 三个可空日期字段）。
  ///
  /// ⚠️ 本项目 copyWith 一律用 `x ?? this.x` 惯写法，所以**直接**
  /// `copyWith(weedAt: null)` 在旧写法下**清不掉**（会被静默吃成「保持原值」——
  /// 历史踩过的坑：copyWith 的 `?? this.x` 让显式 null 无法把可空字段置空）。
  /// 本类已把这三个字段换成哨兵三态，置 null 的写法是：
  /// ```dart
  /// plant.copyWith(weedAt: Plant.kClear); // 清空
  /// plant.copyWith(weedAt: d);            // 设为今天
  /// plant.copyWith();                     // 保持不动
  /// ```
  ///
  /// ⚠️ 为什么「未传」与「清空」必须是**两个不同实例**：默认值就是「未传」，
  /// 若 [kClear] 同时充当默认值，传它进来会和「没传」撞车、被判成「保持原值」，
  /// 于是「显式清空」永远清不掉（本文件就栽在这上面，见 [copyWith] 的 `_resolve`）。
  static const Object kClear = _PlantFieldClear();

  /// copyWith 的「未传」标记（默认参数用它；与 [kClear] 是不同实例）。
  static const Object _unset = _PlantCopyUnset();

  const Plant({
    required this.id,
    required this.speciesId,
    required this.potIndex,
    required this.stage,
    required this.stageStartedAt,
    this.growthProgress = 0.0,
    required this.growthFactor,
    this.waterUsed = false,
    this.fertilizerUsed = false,
    required this.status,
    required this.plantedAt,
    this.lastWaterAt,
    this.wiltedAt,
    this.deadAt,
    this.bloomedAt,
    this.bloomCount = 0,
    this.mood = PlantMood.calm,
    this.weedAt,
    this.pestAt,
    this.weedPestRollDay,
    this.shovelRefund = 0,
  });

  /// 当前是否有杂草（口径 C26）。
  bool get hasWeed => weedAt != null;

  /// 当前是否有害虫（口径 C26）。
  bool get hasPest => pestAt != null;

  /// 杂草 / 害虫任一存在 → 该株成长暂停（当天不涨进度，口径 C26）。
  ///
  /// 「成长暂停」而非「成长减缓」：孩子一眼能看懂「不除草就长不大」，
  /// 且惩罚当天即可消除（点一下图标），不会产生长期挫败感。
  bool get hasPestOrWeed => weedAt != null || pestAt != null;

  /// 不可变副本（植物养成服务每帧 tick 后落库前更新字段）。
  Plant copyWith({
    String? id,
    String? speciesId,
    int? potIndex,
    PlantStage? stage,
    DateTime? stageStartedAt,
    double? growthProgress,
    double? growthFactor,
    bool? waterUsed,
    bool? fertilizerUsed,
    PlantStatus? status,
    DateTime? plantedAt,
    DateTime? lastWaterAt,
    DateTime? wiltedAt,
    DateTime? deadAt,
    DateTime? bloomedAt,
    int? bloomCount,
    PlantMood? mood,
    // ⚠️ 下面三个可空日期字段用哨兵而非 `DateTime?`：默认 null 要「保持原值」，
    // 只有显式传 [Plant.kClear] 才「清空」（三态，见 [kClear] 的注释）。
    Object? weedAt = _unset,
    Object? pestAt = _unset,
    Object? weedPestRollDay = _unset,
    int? shovelRefund,
  }) {
    return Plant(
      id: id ?? this.id,
      speciesId: speciesId ?? this.speciesId,
      potIndex: potIndex ?? this.potIndex,
      stage: stage ?? this.stage,
      stageStartedAt: stageStartedAt ?? this.stageStartedAt,
      growthProgress: growthProgress ?? this.growthProgress,
      growthFactor: growthFactor ?? this.growthFactor,
      waterUsed: waterUsed ?? this.waterUsed,
      fertilizerUsed: fertilizerUsed ?? this.fertilizerUsed,
      status: status ?? this.status,
      plantedAt: plantedAt ?? this.plantedAt,
      lastWaterAt: lastWaterAt ?? this.lastWaterAt,
      wiltedAt: wiltedAt ?? this.wiltedAt,
      deadAt: deadAt ?? this.deadAt,
      bloomedAt: bloomedAt ?? this.bloomedAt,
      bloomCount: bloomCount ?? this.bloomCount,
      mood: mood ?? this.mood,
      weedAt: _resolve(weedAt, this.weedAt),
      pestAt: _resolve(pestAt, this.pestAt),
      weedPestRollDay: _resolve(weedPestRollDay, this.weedPestRollDay),
      shovelRefund: shovelRefund ?? this.shovelRefund,
    );
  }

  /// 哨兵三态解析：没传 → 保持原值；显式 [Plant.kClear] → 置 null；否则取传入值。
  ///
  /// 必须显式判 [Plant._unset] 而不是靠默认值相等：默认值与「显式传 kClear」
  /// 是同一个实例时，两者无法区分，「清空」会退化成「保持」（本文件踩过的坑）。
  static DateTime? _resolve(Object? arg, DateTime? current) {
    if (identical(arg, _unset)) return current;
    if (identical(arg, Plant.kClear)) return null;
    return arg as DateTime?;
  }
}

/// [Plant.kClear] 的载体类型（哨兵）。
///
/// 外部只按 `Plant.kClear` 引用，不必（也不能有意义地）实例化。
class _PlantFieldClear {
  const _PlantFieldClear();
}

/// [Plant._unset] 的载体类型（哨兵，语义 = 「本次 copyWith 没碰这个字段」）。
class _PlantCopyUnset {
  const _PlantCopyUnset();
}
