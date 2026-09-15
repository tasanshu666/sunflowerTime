import 'package:sunflower_time/domain/entities/enums.dart';

/// 埋点事件（§3.1 tracking_event / §6 埋点最低事件集 / §8.3 纪念册）。
class TrackingEvent {
  final String id;
  final TrackingType type; // 纪念册 / 指标
  final DateTime ts;
  final Map<String, dynamic> payload; // JSON

  const TrackingEvent({
    required this.id,
    required this.type,
    required this.ts,
    required this.payload,
  });
}
