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
  final PlantMood mood;

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
    this.mood = PlantMood.calm,
  });

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
    PlantMood? mood,
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
      mood: mood ?? this.mood,
    );
  }
}
