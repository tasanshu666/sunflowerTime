import 'package:sunflower_time/domain/entities/enums.dart';

/// 植物（§3.1 plant）。软绑定：绝不因专注差而死（§4.6 H2）。
class Plant {
  final String id;
  final String speciesId;
  final int potIndex;
  final PlantStage stage;
  final DateTime stageStartedAt;
  final double growthFactor; // 1.0 / 1.3
  final bool waterUsed; // 每段是否浇水
  final bool fertilizerUsed; // 每段是否施肥
  final PlantStatus status;
  final DateTime? lastWaterAt;

  const Plant({
    required this.id,
    required this.speciesId,
    required this.potIndex,
    required this.stage,
    required this.stageStartedAt,
    required this.growthFactor,
    required this.waterUsed,
    required this.fertilizerUsed,
    required this.status,
    this.lastWaterAt,
  });
}
